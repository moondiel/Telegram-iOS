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

    /// Delete in the selection bar of the Drafts screen: confirms with an action sheet, then
    /// deletes the selected drafts.
    func deleteSelectedChannelDrafts(contents: ChatCustomContentsProtocol) -> Bool {
        guard case .channelDrafts = contents.kind else {
            return false
        }
        guard let selectedIds = self.presentationInterfaceState.interfaceState.selectionState?.selectedIds, !selectedIds.isEmpty else {
            return true
        }
        let presentationData = self.presentationData
        let actionSheet = ActionSheetController(presentationData: presentationData)
        actionSheet.setItemGroups([
            ActionSheetItemGroup(items: [
                ActionSheetButtonItem(title: presentationData.strings.ChannelDrafts_DeleteDrafts(Int32(selectedIds.count)), color: .destructive, action: { [weak self, weak actionSheet, weak contents] in
                    actionSheet?.dismissAnimated()
                    contents?.deleteMessages(ids: Array(selectedIds))
                    self?.updateChatPresentationInterfaceState(animated: true, interactive: true, { state in
                        return state.updatedInterfaceState { $0.withoutSelectionState() }
                    })
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
}

/// Long-press menu of a draft on the Drafts screen:
/// Use Draft · Copy · Edit · Delete · Select. Telegram's own menu items and icons.
func channelDraftContextMenuItems(message: EngineRawMessage, contents: ChatCustomContentsProtocol, strings: PresentationStrings, interfaceInteraction: ChatPanelInterfaceInteraction, controllerInteraction: ChatControllerInteraction) -> [ContextMenuItem] {
    guard let contents = contents as? ChannelDraftsChatContents, let draft = contents.draft(messageId: message.id) else {
        return []
    }
    var items: [ContextMenuItem] = []

    items.append(.action(ContextMenuActionItem(text: strings.ChannelDrafts_UseDraft, icon: { theme in
        return generateTintedImage(image: UIImage(bundleImageName: "Chat/Context Menu/Check"), color: theme.actionSheet.primaryTextColor)
    }, action: { [weak contents] _, f in
        f(.dismissWithoutContent)
        contents?.useDraft?(draft)
    })))

    items.append(.action(ContextMenuActionItem(text: strings.Conversation_ContextMenuCopy, icon: { theme in
        return generateTintedImage(image: UIImage(bundleImageName: "Chat/Context Menu/Copy"), color: theme.actionSheet.primaryTextColor)
    }, action: { _, f in
        storeMessageTextInPasteboard(draft.text, entities: draft.entities)
        Queue.mainQueue().after(0.2, {
            controllerInteraction.displayUndo(.copy(text: strings.Conversation_MessageCopied))
        })
        f(.default)
    })))

    items.append(.action(ContextMenuActionItem(text: strings.Conversation_MessageDialogEdit, icon: { theme in
        return generateTintedImage(image: UIImage(bundleImageName: "Chat/Context Menu/Edit"), color: theme.actionSheet.primaryTextColor)
    }, action: { _, f in
        interfaceInteraction.setupEditMessage(message.id, { transition in
            f(.custom(transition))
        })
    })))

    items.append(.action(ContextMenuActionItem(text: strings.Conversation_ContextMenuDelete, textColor: .destructive, icon: { theme in
        return generateTintedImage(image: UIImage(bundleImageName: "Chat/Context Menu/Delete"), color: theme.actionSheet.destructiveActionTextColor)
    }, action: { [weak contents] _, f in
        f(.dismissWithoutContent)
        contents?.deleteMessages(ids: [message.id])
    })))

    items.append(.separator)

    items.append(.action(ContextMenuActionItem(text: strings.Conversation_ContextMenuSelect, icon: { theme in
        return generateTintedImage(image: UIImage(bundleImageName: "Chat/Context Menu/Select"), color: theme.actionSheet.primaryTextColor)
    }, action: { _, f in
        interfaceInteraction.beginMessageSelection([message.id], { transition in
            f(.custom(transition))
        })
    })))

    return items
}
