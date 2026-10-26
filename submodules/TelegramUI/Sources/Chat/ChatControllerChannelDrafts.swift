import Foundation
import UIKit
import SwiftSignalKit
import TelegramCore
import AccountContext
import ChatPresentationInterfaceState
import TextFormat
import Display
import ContextUI
import Pasteboard
import TelegramPresentationData
import ChatControllerInteraction
import UndoUI
import ChannelDrafts
import ChatTitleView
import ChatInterfaceState
import PresentationDataUtils

// Channel Drafts: every hook the feature needs in `ChatControllerImpl` lives in this file.
// See CHANNEL_DRAFTS.md.

/// Drafts can be saved in a plain broadcast-channel chat the user can post in.
func channelDraftsAreAvailable(_ state: ChatPresentationInterfaceState) -> Bool {
    guard state.subject == nil, case .peer = state.chatLocation else {
        return false
    }
    guard let channel = state.renderedPeer?.peer as? TelegramChannel, case .broadcast = channel.info else {
        return false
    }
    return canSendMessagesToChat(state)
}

/// Keeps `channelDrafts` consistent with the rest of the state. Called on every state update.
func updatedChannelDraftsState(_ state: ChatPresentationInterfaceState) -> ChatPresentationInterfaceState {
    var channelDrafts = state.channelDrafts
    channelDrafts.isAvailable = channelDraftsAreAvailable(state)
    // Clearing the composer unlinks the draft it was taken from; the draft itself stays.
    if channelDrafts.attachedDraft != nil && (state.interfaceState.composeInputState.isEmpty || !channelDrafts.isAvailable) {
        channelDrafts.attachedDraft = nil
    }
    if channelDrafts == state.channelDrafts {
        return state
    }
    return state.updatedChannelDrafts(channelDrafts)
}

extension ChatControllerImpl {
    private var channelDraftsPeerId: EnginePeer.Id? {
        guard self.presentationInterfaceState.subject == nil, case let .peer(peerId) = self.chatLocation, peerId.namespace == Namespaces.Peer.CloudChannel else {
            return nil
        }
        return peerId
    }

    /// Follows the channel's drafts so the Drafts button appears with the first one and disappears
    /// with the last one.
    func startChannelDraftsObservation() {
        guard let peerId = self.channelDraftsPeerId else {
            return
        }
        self.channelDraftsDisposable.set((ChannelDraftsStore.drafts(engine: self.context.engine, peerId: peerId)
        |> map { drafts -> Bool in
            return !drafts.isEmpty
        }
        |> distinctUntilChanged
        |> deliverOnMainQueue).startStrict(next: { [weak self] hasDrafts in
            guard let self else {
                return
            }
            self.updateChatPresentationInterfaceState(animated: true, interactive: false, { state in
                var channelDrafts = state.channelDrafts
                channelDrafts.hasDrafts = hasDrafts
                return state.updatedChannelDrafts(channelDrafts)
            })
        }))
    }

    /// The composer text as a draft: plain text plus entities, the same conversion sending uses.
    private func channelDraftContentFromComposer() -> (text: String, entities: [MessageTextEntity])? {
        let inputState = self.chatDisplayNode.textInputPanelNode?.inputTextState ?? self.presentationInterfaceState.interfaceState.composeInputState
        let text = trimChatInputText(convertMarkdownToAttributes(expandedInputStateAttributedString(inputState.inputText)))
        if text.string.isEmpty {
            return nil
        }
        let entities = generateTextEntities(text.string, enabledTypes: .all, currentEntities: generateChatInputTextEntities(text))
        return (text.string, entities)
    }

    /// Save Draft is offered in the send menu for text in a channel where drafts are available.
    func canSaveChannelDraftFromComposer(hasMediaPreview: Bool) -> Bool {
        let state = self.presentationInterfaceState
        guard state.channelDrafts.isAvailable, !hasMediaPreview else {
            return false
        }
        if state.interfaceState.forwardMessageIds != nil || state.interfaceState.mediaDraftState != nil || state.interfaceState.editMessage != nil {
            return false
        }
        return !state.interfaceState.composeInputState.isEmpty
    }

    /// Send menu → Save Draft. Updates the linked draft if the text came from one, otherwise adds a
    /// new draft; then clears the composer.
    func saveChannelDraftFromComposer() {
        guard let peerId = self.channelDraftsPeerId, let content = self.channelDraftContentFromComposer() else {
            return
        }
        let engine = self.context.engine
        if let attachedDraft = self.presentationInterfaceState.channelDrafts.attachedDraft {
            let _ = ChannelDraftsStore.update(engine: engine, peerId: peerId, id: attachedDraft.id, text: content.text, entities: content.entities).startStandalone()
        } else {
            let _ = ChannelDraftsStore.add(engine: engine, peerId: peerId, text: content.text, entities: content.entities).startStandalone()
        }

        self.updateChatPresentationInterfaceState(animated: true, interactive: true, saveInterfaceState: true, { state in
            var channelDrafts = state.channelDrafts
            channelDrafts.attachedDraft = nil
            return state.updatedInterfaceState { interfaceState in
                return interfaceState.withUpdatedComposeInputState(ChatTextInputState(inputText: NSAttributedString(string: "")))
            }.updatedChannelDrafts(channelDrafts)
        })
    }

    /// A post sent (or scheduled) from a linked draft publishes that draft: it leaves the Drafts list.
    func channelDraftsDidSendMessages(_ messages: [EnqueueMessage]) {
        guard !messages.isEmpty, let peerId = self.channelDraftsPeerId, let attachedDraft = self.presentationInterfaceState.channelDrafts.attachedDraft else {
            return
        }
        let _ = ChannelDraftsStore.delete(engine: self.context.engine, peerId: peerId, ids: Set([attachedDraft.id])).startStandalone()
        self.updateChatPresentationInterfaceState(animated: false, interactive: false, { state in
            var channelDrafts = state.channelDrafts
            channelDrafts.attachedDraft = nil
            return state.updatedChannelDrafts(channelDrafts)
        })
    }

    /// The Drafts button in the input field: opens the Drafts screen, a chat controller over
    /// `ChannelDraftsChatContents`, presented like Scheduled Messages.
    func openChannelDrafts() {
        guard let peerId = self.channelDraftsPeerId, let navigationController = self.effectiveNavigationController, navigationController.topViewController == self else {
            return
        }
        let contents = ChannelDraftsChatContents(context: self.context, peerId: peerId)
        let controller = ChatControllerImpl(context: self.context, chatLocation: .customChatContents, subject: .customChatContents(contents: contents))
        controller.navigationPresentation = .modal
        contents.useDraft = { [weak self, weak controller] draft in
            controller?.dismiss()
            self?.useChannelDraft(draft)
        }
        navigationController.pushViewController(controller)
    }

    /// Use Draft: the draft's text goes into the composer, linked to the draft ("Draft" header).
    /// The draft stays in the list until the post is sent.
    func useChannelDraft(_ draft: ChannelDraft) {
        let inputText = chatInputStateStringWithAppliedEntities(draft.text, entities: draft.entities)
        self.updateChatPresentationInterfaceState(animated: true, interactive: true, saveInterfaceState: true, { state in
            var channelDrafts = state.channelDrafts
            channelDrafts.attachedDraft = ChatChannelDraftsState.AttachedDraft(id: draft.id, text: draft.text)
            return state.updatedInterfaceState { interfaceState in
                return interfaceState.withUpdatedComposeInputState(ChatTextInputState(inputText: inputText))
            }.updatedInputMode { _ in
                return .text
            }.updatedChannelDrafts(channelDrafts)
        })
        self.chatDisplayNode.ensureInputViewFocused()
    }

    /// ✓ in the "Edit Draft" header on the Drafts screen. The draft is not a stored message, so the
    /// regular edit path (which looks the message up in the database) is not used.
    func commitChannelDraftEdit(contents: ChatCustomContentsProtocol) -> Bool {
        guard case .channelDrafts = contents.kind, let editMessage = self.presentationInterfaceState.interfaceState.editMessage else {
            return false
        }
        let text = trimChatInputText(convertMarkdownToAttributes(expandedInputStateAttributedString(editMessage.inputState.inputText)))
        let entities = generateTextEntities(text.string, enabledTypes: .all, currentEntities: generateChatInputTextEntities(text))
        contents.editMessage(id: editMessage.messageId, text: text.string, media: .keep, entities: entities.isEmpty ? nil : TextEntitiesMessageAttribute(entities: entities), webpagePreviewAttribute: nil, disableUrlPreview: true)
        self.updateChatPresentationInterfaceState(animated: true, interactive: true, { state in
            return state.updatedInterfaceState { $0.withUpdatedEditMessage(nil) }.updatedEditMessageState(nil)
        })
        return true
    }

    /// The channel's avatar on the Drafts screen opens the channel's profile, as in Scheduled
    /// Messages.
    func openChannelDraftsChannelInfo() {
        guard case let .customChatContents(customChatContents) = self.presentationInterfaceState.subject, case .channelDrafts = customChatContents.kind, let peer = self.presentationInterfaceState.renderedPeer?.peer else {
            return
        }
        if let infoController = self.context.sharedContext.makePeerInfoController(context: self.context, updatedPresentationData: self.updatedPresentationData, peer: EnginePeer(peer), mode: .generic, avatarInitiallyExpanded: peer.smallProfileImage != nil, fromChat: true, requestsContext: nil) {
            self.effectiveNavigationController?.pushViewController(infoController)
        }
    }

    /// Clear All in the selection header of the Drafts screen: the same action sheet and warning
    /// as Scheduled Messages' Clear All, then every draft of the channel is deleted.
    func presentClearChannelDrafts() -> Bool {
        guard case let .customChatContents(customChatContents) = self.presentationInterfaceState.subject, case .channelDrafts = customChatContents.kind, let contents = customChatContents as? ChannelDraftsChatContents else {
            return false
        }
        let presentationData = self.presentationData
        let actionSheet = ActionSheetController(presentationData: presentationData)
        actionSheet.setItemGroups([
            ActionSheetItemGroup(items: [
                ActionSheetButtonItem(title: presentationData.strings.ChannelDrafts_ClearAllConfirmation, color: .destructive, action: { [weak self, weak actionSheet, weak contents] in
                    actionSheet?.dismissAnimated()
                    guard let self else {
                        return
                    }
                    let alertController = textAlertController(
                        context: self.context,
                        title: presentationData.strings.ChatList_DeleteSavedMessagesConfirmationTitle,
                        text: presentationData.strings.ChatList_DeleteSavedMessagesConfirmationText,
                        actions: [
                            TextAlertAction(type: .genericAction, title: presentationData.strings.Common_Cancel, action: {
                            }),
                            TextAlertAction(type: .destructiveAction, title: presentationData.strings.ChatList_DeleteSavedMessagesConfirmationAction, action: { [weak self, weak contents] in
                                self?.updateChatPresentationInterfaceState(animated: true, interactive: true, { state in
                                    return state.updatedInterfaceState { $0.withoutSelectionState() }
                                })
                                contents?.deleteAllDrafts()
                            })
                        ]
                    )
                    self.present(alertController, in: .window(.root))
                })
            ]),
            ActionSheetItemGroup(items: [
                ActionSheetButtonItem(title: presentationData.strings.Common_Cancel, color: .accent, font: .bold, action: { [weak actionSheet] in
                    actionSheet?.dismissAnimated()
                })
            ])
        ])
        self.chatDisplayNode.dismissInput()
        self.present(actionSheet, in: .window(.root))
        return true
    }

    /// Delete in the selection bar of the Drafts screen. Like Scheduled Messages: a menu over the
    /// button with one destructive "Delete Drafts" item.
    func deleteSelectedChannelDrafts(contents: ChatCustomContentsProtocol, sourceView: UIView?) -> Bool {
        guard case .channelDrafts = contents.kind else {
            return false
        }
        guard let selectedIds = self.presentationInterfaceState.interfaceState.selectionState?.selectedIds, !selectedIds.isEmpty, let sourceView else {
            return true
        }
        let item = channelDraftsDeleteConfirmationItem(messageIds: selectedIds, contents: contents, strings: self.presentationData.strings, completed: { [weak self] in
            self?.updateChatPresentationInterfaceState(animated: true, interactive: true, { state in
                return state.updatedInterfaceState { $0.withoutSelectionState() }
            })
        })
        let contextController = makeContextController(
            presentationData: self.presentationData,
            source: .reference(ChatControllerContextReferenceContentSource(controller: self, sourceView: sourceView, insets: .zero, actionsOnTop: true)),
            items: .single(ContextController.Items(content: .list([item]))),
            gesture: nil
        )
        self.chatDisplayNode.dismissInput()
        self.presentInGlobalOverlay(contextController)
        return true
    }
}

/// The Drafts screen title. Like "Scheduled Messages": text only, without the channel's badges,
/// in a pill that fits it; during selection the same "N Selected" / "Select Messages" title as
/// any chat.
func channelDraftsTitleContent(selectionState: ChatInterfaceSelectionState?, strings: PresentationStrings) -> ChatTitleContent {
    guard let selectionState else {
        return .custom(title: [ChatTitleContent.TitleTextItem(id: AnyHashable(0), content: .text(strings.ChannelDrafts_Title))], subtitle: nil, isEnabled: false, hugsTitle: true)
    }
    if selectionState.selectedIds.isEmpty {
        return .custom(title: [ChatTitleContent.TitleTextItem(id: AnyHashable(2), content: .text(strings.Conversation_SelectMessages))], subtitle: nil, isEnabled: false)
    }
    let rawText = strings.Conversation_SelectedMessagesFormat(Int32(selectionState.selectedIds.count))
    var items: [ChatTitleContent.TitleTextItem] = []
    if let range = rawText.range(of: "{}") {
        if range.lowerBound != rawText.startIndex {
            items.append(ChatTitleContent.TitleTextItem(id: AnyHashable("selection_0"), content: .text(String(rawText[rawText.startIndex ..< range.lowerBound]))))
        }
        items.append(ChatTitleContent.TitleTextItem(id: AnyHashable("selection_1"), content: .number(selectionState.selectedIds.count, minDigits: 1)))
        if range.upperBound != rawText.endIndex {
            items.append(ChatTitleContent.TitleTextItem(id: AnyHashable("selection_2"), content: .text(String(rawText[range.upperBound ..< rawText.endIndex]))))
        }
    }
    return .custom(title: items, subtitle: nil, isEnabled: false)
}

/// The confirmation Scheduled Messages shows for Delete ("Delete Scheduled Message(s)"), with the
/// Drafts strings. Drafts are deleted at once, without an undo toast, as scheduled messages are.
private func channelDraftsDeleteConfirmationItem(messageIds: Set<EngineMessage.Id>, contents: ChatCustomContentsProtocol, strings: PresentationStrings, completed: @escaping () -> Void) -> ContextMenuItem {
    let title = ChannelDraftsChatContents.draftCount(messageIds: messageIds) > 1 ? strings.ChannelDrafts_DeleteMany : strings.ChannelDrafts_Delete
    return .action(ContextMenuActionItem(text: title, textColor: .destructive, icon: { _ in nil }, action: { [weak contents] _, f in
        f(.dismissWithoutContent)
        completed()
        contents?.deleteMessages(ids: Array(messageIds))
    }))
}

/// Long-press menu of a draft on the Drafts screen, in the order of Scheduled Messages
/// (Use Draft in the place of Send Now / Edit Time): Use Draft (text) · Copy · Edit · Delete ·
/// Select. Telegram's own menu items, strings and icons.
func channelDraftContextMenuItems(message: EngineRawMessage, contents: ChatCustomContentsProtocol, strings: PresentationStrings, interfaceInteraction: ChatPanelInterfaceInteraction, controllerInteraction: ChatControllerInteraction) -> [ContextMenuItem] {
    guard let contents = contents as? ChannelDraftsChatContents, let draft = contents.draft(messageId: message.id) else {
        return []
    }
    let draftMessageIds = contents.messageIds(draft: draft)
    var items: [ContextMenuItem] = []

    if draft.media.isEmpty {
        // Text: continue it in the channel composer. Media cannot go into the composer.
        items.append(.action(ContextMenuActionItem(text: strings.ChannelDrafts_UseDraft, icon: { theme in
            return generateTintedImage(image: UIImage(bundleImageName: "Chat/Context Menu/UseDraft"), color: theme.actionSheet.primaryTextColor)
        }, action: { [weak contents] _, f in
            f(.dismissWithoutContent)
            contents?.useDraft?(draft)
        })))
    }

    if !draft.text.isEmpty {
        items.append(.action(ContextMenuActionItem(text: strings.Conversation_ContextMenuCopy, icon: { theme in
            return generateTintedImage(image: UIImage(bundleImageName: "Chat/Context Menu/Copy"), color: theme.actionSheet.primaryTextColor)
        }, action: { _, f in
            storeMessageTextInPasteboard(draft.text, entities: draft.entities)
            Queue.mainQueue().after(0.2, {
                controllerInteraction.displayUndo(.copy(text: strings.Conversation_MessageCopied))
            })
            f(.default)
        })))
    }

    items.append(.action(ContextMenuActionItem(text: strings.Conversation_MessageDialogEdit, icon: { theme in
        return generateTintedImage(image: UIImage(bundleImageName: "Chat/Context Menu/Edit"), color: theme.actionSheet.primaryTextColor)
    }, action: { _, f in
        interfaceInteraction.setupEditMessage(draftMessageIds.first ?? message.id, { transition in
            f(.custom(transition))
        })
    })))

    // Delete swaps the menu for its confirmation, as in Scheduled Messages.
    items.append(.action(ContextMenuActionItem(text: strings.Conversation_ContextMenuDelete, textColor: .destructive, icon: { theme in
        return generateTintedImage(image: UIImage(bundleImageName: "Chat/Context Menu/Delete"), color: theme.actionSheet.destructiveActionTextColor)
    }, action: { [weak contents] c, f in
        guard let contents, let c else {
            f(.dismissWithoutContent)
            return
        }
        let item = channelDraftsDeleteConfirmationItem(messageIds: Set(draftMessageIds), contents: contents, strings: strings, completed: {})
        c.setItems(.single(ContextController.Items(content: .list([item]))), minHeight: nil, animated: true)
    })))

    items.append(.separator)

    // A draft is one post: Select takes all of its messages (every item of an album).
    items.append(.action(ContextMenuActionItem(text: strings.Conversation_ContextMenuSelect, icon: { theme in
        return generateTintedImage(image: UIImage(bundleImageName: "Chat/Context Menu/Select"), color: theme.actionSheet.primaryTextColor)
    }, action: { _, f in
        interfaceInteraction.beginMessageSelection(draftMessageIds, { transition in
            f(.custom(transition))
        })
    })))

    return items
}
