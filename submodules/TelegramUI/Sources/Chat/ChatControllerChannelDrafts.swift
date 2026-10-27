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
import LegacyMediaPickerUI
import ChatMessageItemCommon

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
    // Like the Edit header, the Draft header stays when the text is erased: only ×, sending,
    // scheduling or saving the draft unlinks it. It goes with the chat's ability to keep drafts.
    if channelDrafts.attachedDraft != nil && !channelDrafts.isAvailable {
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
        if state.channelDrafts.attachedDraft?.media.isEmpty == false {
            // A draft with media can be saved with an empty caption.
            return true
        }
        return !state.interfaceState.composeInputState.isEmpty
    }

    /// Send menu → Save Draft. Updates the linked draft if the text came from one, otherwise adds a
    /// new draft; then clears the composer.
    func saveChannelDraftFromComposer() {
        guard let peerId = self.channelDraftsPeerId else {
            return
        }
        var attachedDraft = self.presentationInterfaceState.channelDrafts.attachedDraft
        if let draft = attachedDraft, !draft.media.isEmpty, !channelDraftContentIsEditable(context: self.context, media: draft.media) {
            // A sticker, round video, poll... carries no caption: the text is posted before it, so
            // it is saved as a draft of its own and the linked one stays as it is.
            guard self.channelDraftContentFromComposer() != nil else {
                return
            }
            attachedDraft = nil
        }
        // A draft with media may be saved with an empty caption; it keeps its media either way.
        guard let content = self.channelDraftContentFromComposer() ?? (attachedDraft?.media.isEmpty == false ? (text: "", entities: []) : nil) else {
            return
        }
        // Content the entities cannot express (headings, lists, tables...) is kept rich, as sending
        // it would be.
        let composeContent = (self.chatDisplayNode.textInputPanelNode?.inputTextState ?? self.presentationInterfaceState.interfaceState.composeInputState).content
        let richText: Data? = composeContent.isEntityExpressible() ? nil : ChannelDraft.encodeRichText(RichTextMessageAttribute(instantPage: instantPage(from: composeContent), fullInstantPage: nil))
        let text = richText == nil ? content.text : ""
        let entities = richText == nil ? content.entities : []
        let engine = self.context.engine
        if let attachedDraft {
            let _ = ChannelDraftsStore.update(engine: engine, peerId: peerId, id: attachedDraft.id, text: text, entities: entities, richText: richText).startStandalone()
        } else {
            let _ = ChannelDraftsStore.add(engine: engine, peerId: peerId, drafts: [ChannelDraftsStore.NewDraft(text: text, entities: entities, richText: richText)]).startStandalone()
        }

        self.updateChatPresentationInterfaceState(animated: true, interactive: true, saveInterfaceState: true, { state in
            var channelDrafts = state.channelDrafts
            channelDrafts.attachedDraft = nil
            return state.updatedInterfaceState { interfaceState in
                return interfaceState.withUpdatedComposeInputState(ChatTextInputState(inputText: NSAttributedString(string: "")))
            }.updatedChannelDrafts(channelDrafts)
        })
    }

    /// Tap on the "Draft" header: the draft as it will be posted, in the same preview the Reply and
    /// Forward headers open (a previewing chat in a context menu), with "Do Not Use Draft" as
    /// Reply's preview has "Do Not Reply".
    func presentChannelDraftPreview(sourceView: UIView) {
        guard let peerId = self.channelDraftsPeerId, let attachedDraft = self.presentationInterfaceState.channelDrafts.attachedDraft else {
            return
        }
        let contents = ChannelDraftsChatContents(context: self.context, peerId: peerId, onlyDraftId: attachedDraft.id)
        let chatController = ChatControllerImpl(context: self.context, chatLocation: .customChatContents, subject: .customChatContents(contents: contents), mode: .standard(.previewing))
        chatController.canReadHistory.set(false)

        let strings = self.presentationData.strings
        let items: [ContextMenuItem] = [
            .action(ContextMenuActionItem(text: strings.ChannelDrafts_DontUseDraft, textColor: .destructive, icon: { theme in
                return generateTintedImage(image: UIImage(bundleImageName: "Chat/Context Menu/Delete"), color: theme.contextMenu.destructiveColor)
            }, action: { [weak self] _, f in
                f(.default)
                guard let self else {
                    return
                }
                // As × in the header: the composer is cleared and the draft stays as it was.
                self.unlinkChannelDraft()
                self.updateChatPresentationInterfaceState(animated: true, interactive: true, { state in
                    return state.updatedInterfaceState { $0.withUpdatedComposeInputState(ChatTextInputState(inputText: NSAttributedString(string: ""))) }
                })
            }))
        ]
        let sourceId = AnyHashable("channelDraft")
        let source = ContextController.Source(
            id: sourceId,
            title: strings.ChannelDrafts_AttachedPanelTitle,
            source: .controller(ChatContextControllerContentSourceImpl(controller: chatController, sourceView: sourceView, passthroughTouches: true)),
            items: .single(ContextController.Items(content: .list(items)))
        )
        let contextController = makeContextController(
            presentationData: self.presentationData,
            configuration: ContextController.Configuration(sources: [source], initialId: sourceId)
        )
        self.canReadHistory.set(false)
        contextController.dismissed = { [weak self] in
            self?.canReadHistory.set(true)
        }
        self.chatDisplayNode.dismissInput()
        self.presentInGlobalOverlay(contextController)
    }

    /// Save Draft in the send options of the media picker or the photo editor: the picked media,
    /// with its caption, is saved instead of sent.
    func saveChannelDraft(mediaSignals signals: [Any]?, completion: @escaping () -> Void) {
        guard let signals else {
            completion()
            return
        }
        let _ = (legacyAssetPickerEnqueueMessages(context: self.context, account: self.context.account, signals: signals)
        |> deliverOnMainQueue).startStandalone(next: { [weak self] items in
            self?.saveChannelDraft(messages: items.map(\.message))
            completion()
        })
    }

    /// Save Draft for anything the chat would send (a recording, files, music, a sticker, a GIF,
    /// picked media): the messages are saved as new drafts instead. Only when the attach flow took
    /// a draft's text over as the caption do they go into that draft (its first one: text and
    /// media). A draft linked to the composer is not touched: a sticker or a voice message is not
    /// part of the post being written, as sending them leaves the composer text alone.
    func saveChannelDraft(messages: [EnqueueMessage]) {
        guard let peerId = self.channelDraftsPeerId else {
            return
        }
        let engine = self.context.engine
        var newDrafts = ChannelDraftsStore.newDrafts(from: messages).map { $0.draft }
        if let takenDraft = self.channelDraftTakenByCaption, !newDrafts.isEmpty {
            self.channelDraftTakenByCaption = nil
            let first = newDrafts.removeFirst()
            let _ = ChannelDraftsStore.update(engine: engine, peerId: peerId, id: takenDraft.id, text: first.text, entities: first.entities, richText: first.richText, media: first.media).startStandalone()
        }
        if !newDrafts.isEmpty {
            let _ = ChannelDraftsStore.add(engine: engine, peerId: peerId, drafts: newDrafts).startStandalone()
        }
        // A saved recording leaves the composer as a sent one does.
        self.updateChatPresentationInterfaceState(animated: true, interactive: true, { state in
            return state.updatedInterfaceState { $0.withUpdatedMediaDraftState(nil) }
        })
    }

    /// The attach flow's send, with a draft's text as the caption: the post is published and the
    /// draft leaves Drafts.
    func publishChannelDraftTakenByCaption() {
        guard let takenDraft = self.channelDraftTakenByCaption, let peerId = self.channelDraftsPeerId else {
            return
        }
        self.channelDraftTakenByCaption = nil
        let _ = ChannelDraftsStore.delete(engine: self.context.engine, peerId: peerId, ids: Set([takenDraft.id])).startStandalone()
    }

    /// A photo, video or file picked with the attachment button while a draft with media is in the
    /// composer replaces that media (its first item), as picking a replacement does while editing
    /// a post. The picker's caption becomes the composer text, as it does for an edit. True if the
    /// pick was for the draft.
    func replaceChannelDraftMedia(with messages: [EnqueueMessage]) -> Bool {
        guard self.presentationInterfaceState.interfaceState.editMessage == nil, let peerId = self.channelDraftsPeerId else {
            return false
        }
        // The picker may have taken the composer text over as its caption, unlinking the draft.
        guard let linkedDraft = self.presentationInterfaceState.channelDrafts.attachedDraft ?? self.channelDraftTakenByCaption, !linkedDraft.media.isEmpty else {
            return false
        }
        self.channelDraftTakenByCaption = nil
        guard let message = messages.first, case let .message(text, attributes, _, maybeMediaReference, _, _, _, _, _, _) = message, let mediaReference = maybeMediaReference else {
            return true
        }
        var entities: [MessageTextEntity] = []
        for attribute in attributes {
            if let attribute = attribute as? TextEntitiesMessageAttribute {
                entities = attribute.entities
            }
        }
        var media = linkedDraft.media
        media[0] = mediaReference.media
        let caption = text.isEmpty ? linkedDraft.text : text
        let _ = ChannelDraftsStore.update(engine: self.context.engine, peerId: peerId, id: linkedDraft.id, text: caption, entities: text.isEmpty ? [] : entities, replacingMedia: (0, ChannelDraft.encodeMedia(mediaReference.media))).startStandalone()
        let updatedDraft = ChatChannelDraftsState.AttachedDraft(id: linkedDraft.id, text: caption, media: media, mediaEditingOptions: channelDraftMediaEditingOptions(media: media, peerId: peerId))
        self.updateChatPresentationInterfaceState(animated: true, interactive: true, { state in
            var channelDrafts = state.channelDrafts
            channelDrafts.attachedDraft = updatedDraft
            var state = state.updatedChannelDrafts(channelDrafts)
            if !text.isEmpty {
                state = state.updatedInterfaceState { $0.withUpdatedComposeInputState(ChatTextInputState(inputText: chatInputStateStringWithAppliedEntities(text, entities: entities))) }
            }
            return state
        })
        return true
    }

    /// The chat's send funnels: messages marked with `channelDraftSaveScheduleTimestamp` (Save Draft
    /// in a send menu, carried as the schedule time) are saved as drafts, not sent. True if they were.
    func saveChannelDraftIfRequested(_ messages: [EnqueueMessage]) -> Bool {
        var isRequested = false
        let unmarked = messages.map { message -> EnqueueMessage in
            return message.withUpdatedAttributes { attributes in
                return attributes.filter { attribute in
                    if let attribute = attribute as? OutgoingScheduleInfoMessageAttribute, attribute.scheduleTime == channelDraftSaveScheduleTimestamp {
                        isRequested = true
                        return false
                    }
                    return true
                }
            }
        }
        if !isRequested {
            return false
        }
        self.saveChannelDraft(messages: unmarked)
        return true
    }

    /// Save Draft offered for the recording in the composer (a voice message under review or a
    /// round video being recorded).
    var canSaveRecordingAsChannelDraft: Bool {
        let state = self.presentationInterfaceState
        guard state.channelDrafts.isAvailable, state.interfaceState.editMessage == nil else {
            return false
        }
        return state.interfaceState.mediaDraftState != nil || self.videoRecorderValue != nil
    }

    /// Save Draft for the recording: sent as Schedule sends it, with the Save Draft marker as the
    /// time, which the send funnels turn into a draft.
    func saveRecordingAsChannelDraft() {
        if self.presentationInterfaceState.interfaceState.mediaDraftState != nil {
            self.sendMediaRecording(scheduleTime: channelDraftSaveScheduleTimestamp)
        } else if let videoRecorderValue = self.videoRecorderValue {
            videoRecorderValue.sendVideoRecording(silentPosting: nil, scheduleTime: channelDraftSaveScheduleTimestamp, repeatPeriod: nil, messageEffect: nil)
        }
    }

    /// × in the "Draft" header: the composer lets go of the draft, which stays as it was.
    func unlinkChannelDraft() {
        self.updateChatPresentationInterfaceState(animated: true, interactive: true, { state in
            var channelDrafts = state.channelDrafts
            channelDrafts.attachedDraft = nil
            return state.updatedChannelDrafts(channelDrafts)
        })
    }

    /// The composer's Send or Schedule with a linked draft publishes it: the draft's media is
    /// posted with the composer text as its caption (an album for several items), and the draft
    /// leaves the Drafts list. Called before the send's completion, which clears the composer (and
    /// with it the link) when scheduling.
    func publishChannelDraft(composerMessages messages: [EnqueueMessage]) -> [EnqueueMessage] {
        guard let attachedDraft = self.presentationInterfaceState.channelDrafts.attachedDraft else {
            return messages
        }
        var result = messages
        if !attachedDraft.media.isEmpty {
            result = channelDraftMessagesAttachingMedia(attachedDraft.media, to: messages, captionable: channelDraftContentIsEditable(context: self.context, media: attachedDraft.media), threadId: self.chatLocation.threadId)
        }
        self.channelDraftsDidSendMessages(result)
        return result
    }

    /// A post sent or scheduled from a linked draft publishes that draft: it leaves the Drafts list.
    /// Called from the composer's send (`publishChannelDraft`) and from every send of the chat; the
    /// second call finds the draft unlinked.
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

    /// Use Draft: the draft's text (or caption) goes into the composer, linked to the draft ("Draft"
    /// header); its media goes with the link and is posted by Send or Schedule, as editing a post
    /// with media keeps the media out of the text field. The draft stays in the list until then.
    func useChannelDraft(_ draft: ChannelDraft) {
        // Rich content goes in with its structure, the same InstantPage → composer hop editing a
        // rich message uses.
        let inputState: ChatTextInputState
        if let richText = draft.decodedRichText {
            let content = chatInputContent(fromInstantPage: richText.instantPage)
            inputState = ChatTextInputState(content: content, selectionRange: content.length ..< content.length)
        } else {
            inputState = ChatTextInputState(inputText: chatInputStateStringWithAppliedEntities(draft.text, entities: draft.entities))
        }
        let media = draft.decodedMedia
        self.updateChatPresentationInterfaceState(animated: true, interactive: true, saveInterfaceState: true, { state in
            var channelDrafts = state.channelDrafts
            channelDrafts.attachedDraft = ChatChannelDraftsState.AttachedDraft(id: draft.id, text: draft.decodedRichText == nil ? draft.text : inputState.inputText.string, media: media, mediaEditingOptions: channelDraftMediaEditingOptions(media: media, peerId: state.chatLocation.peerId))
            return state.updatedInterfaceState { interfaceState in
                return interfaceState.withUpdatedComposeInputState(inputState)
            }.updatedInputMode { _ in
                return .text
            }.updatedChannelDrafts(channelDrafts)
        })
        self.chatDisplayNode.ensureInputViewFocused()
    }

    /// ✓ in the "Edit Draft" header on the Drafts screen, and a replacement photo or video picked
    /// with the attachment button while editing (Telegram's own replace-media flow commits the edit
    /// with the picked media in `editMessageState.mediaReference`). The draft is not a stored
    /// message, so the regular edit path (which edits it on the server) is not used.
    func commitChannelDraftEdit(contents: ChatCustomContentsProtocol) -> Bool {
        guard case .channelDrafts = contents.kind, let editMessage = self.presentationInterfaceState.interfaceState.editMessage else {
            return false
        }
        let text = trimChatInputText(convertMarkdownToAttributes(expandedInputStateAttributedString(editMessage.inputState.inputText)))
        let entities = generateTextEntities(text.string, enabledTypes: .all, currentEntities: generateChatInputTextEntities(text))
        let media: RequestEditMessageMedia
        if let mediaReference = self.presentationInterfaceState.editMessageState?.mediaReference {
            media = .update(mediaReference)
        } else {
            media = .keep
        }
        // As the regular edit: content the entities cannot express stays rich.
        let content = editMessage.inputState.content
        let richText: RichTextMessageAttribute? = content.isEntityExpressible() ? nil : RichTextMessageAttribute(instantPage: instantPage(from: content), fullInstantPage: nil)
        if let contents = contents as? ChannelDraftsChatContents {
            contents.editMessage(id: editMessage.messageId, text: text.string, media: media, entities: entities.isEmpty ? nil : TextEntitiesMessageAttribute(entities: entities), richText: richText)
        } else {
            contents.editMessage(id: editMessage.messageId, text: text.string, media: media, entities: entities.isEmpty ? nil : TextEntitiesMessageAttribute(entities: entities), webpagePreviewAttribute: nil, disableUrlPreview: true)
        }
        self.updateChatPresentationInterfaceState(animated: true, interactive: true, { state in
            return state.updatedInterfaceState { $0.withUpdatedEditMessage(nil) }.updatedEditMessageState(nil)
        })
        return true
    }

    /// The channel whose Drafts screen this is; nil on any other screen.
    var channelDraftsScreenPeerId: EnginePeer.Id? {
        if case let .customChatContents(customChatContents) = self.presentationInterfaceState.subject, case let .channelDrafts(peerId) = customChatContents.kind {
            return peerId
        }
        return nil
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
/// any chat. The preview of a single draft is titled "Draft", as its header in the composer.
func channelDraftsTitleContent(contents: ChatCustomContentsProtocol, selectionState: ChatInterfaceSelectionState?, strings: PresentationStrings) -> ChatTitleContent {
    guard let selectionState else {
        let isSingleDraft = (contents as? ChannelDraftsChatContents)?.showsSingleDraft ?? false
        let title = isSingleDraft ? strings.ChannelDrafts_AttachedPanelTitle : strings.ChannelDrafts_Title
        return .custom(title: [ChatTitleContent.TitleTextItem(id: AnyHashable(0), content: .text(title))], subtitle: nil, isEnabled: false, hugsTitle: true)
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
/// (Use Draft in the place of Send Now / Edit Time): Use Draft · Copy · Edit · Delete · Select.
/// Telegram's own menu items, strings and icons.
func channelDraftContextMenuItems(context: AccountContext, message: EngineRawMessage, contents: ChatCustomContentsProtocol, strings: PresentationStrings, interfaceInteraction: ChatPanelInterfaceInteraction, controllerInteraction: ChatControllerInteraction) -> [ContextMenuItem] {
    guard let contents = contents as? ChannelDraftsChatContents, let draft = contents.draft(messageId: message.id) else {
        return []
    }
    let draftMessageIds = contents.messageIds(draft: draft)
    var items: [ContextMenuItem] = []

    // Continue it in the channel composer (its media goes with it and is posted on Send).
    items.append(.action(ContextMenuActionItem(text: strings.ChannelDrafts_UseDraft, icon: { theme in
        return generateTintedImage(image: UIImage(bundleImageName: "Chat/Context Menu/UseDraft"), color: theme.actionSheet.primaryTextColor)
    }, action: { [weak contents] _, f in
        f(.dismissWithoutContent)
        contents?.useDraft?(draft)
    })))

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

    // Edit where Telegram allows editing such a message (not stickers, round videos, polls...).
    if channelDraftContentIsEditable(context: context, media: draft.decodedMedia) {
        items.append(.action(ContextMenuActionItem(text: strings.Conversation_MessageDialogEdit, icon: { theme in
            return generateTintedImage(image: UIImage(bundleImageName: "Chat/Context Menu/Edit"), color: theme.actionSheet.primaryTextColor)
        }, action: { _, f in
            interfaceInteraction.setupEditMessage(draftMessageIds.first ?? message.id, { transition in
                f(.custom(transition))
            })
        })))
    }

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

/// The composer's messages with a draft's media added: the first text message becomes the caption
/// of the first item (an album for several items), any further text follows as it was. Without
/// text the media is posted alone. Media that cannot carry a caption (a sticker, a round video,
/// a poll...) goes after the text, sent as it is, as Forward sends its comment before the
/// forwarded messages.
private func channelDraftMessagesAttachingMedia(_ media: [EngineRawMedia], to messages: [EnqueueMessage], captionable: Bool, threadId: Int64?) -> [EnqueueMessage] {
    if !captionable {
        let groupingKey: Int64? = media.count > 1 ? Int64.random(in: 1 ..< Int64.max) : nil
        return messages + media.map { item -> EnqueueMessage in
            return .message(text: "", attributes: [], inlineStickers: [:], mediaReference: .standalone(media: item), threadId: threadId, replyToMessageId: nil, replyToStoryId: nil, localGroupingKey: groupingKey, correlationId: nil, bubbleUpEmojiOrStickersets: [])
        }
    }
    var caption: (text: String, attributes: [EngineMessage.Attribute], inlineStickers: [EngineMedia.Id: EngineRawMedia], replyToMessageId: EngineMessageReplySubject?, bubbleUpEmojiOrStickersets: [EngineItemCollectionId])?
    var rest: [EnqueueMessage] = []
    for message in messages {
        if caption == nil, case let .message(text, attributes, inlineStickers, _, _, replyToMessageId, _, _, _, bubbleUpEmojiOrStickersets) = message, !text.isEmpty {
            // A link preview does not go with a caption.
            caption = (text, attributes.filter { !($0 is WebpagePreviewMessageAttribute) }, inlineStickers, replyToMessageId, bubbleUpEmojiOrStickersets)
        } else {
            rest.append(message)
        }
    }
    let groupingKey: Int64? = media.count > 1 ? Int64.random(in: 1 ..< Int64.max) : nil
    var result: [EnqueueMessage] = []
    for (index, item) in media.enumerated() {
        let isCaptionItem = index == 0
        result.append(.message(
            text: isCaptionItem ? (caption?.text ?? "") : "",
            attributes: isCaptionItem ? (caption?.attributes ?? []) : [],
            inlineStickers: isCaptionItem ? (caption?.inlineStickers ?? [:]) : [:],
            mediaReference: .standalone(media: item),
            threadId: threadId,
            replyToMessageId: isCaptionItem ? caption?.replyToMessageId : nil,
            replyToStoryId: nil,
            localGroupingKey: groupingKey,
            correlationId: nil,
            bubbleUpEmojiOrStickersets: isCaptionItem ? (caption?.bubbleUpEmojiOrStickersets ?? []) : []
        ))
    }
    result.append(contentsOf: rest)
    return result
}

/// What a draft's media may be replaced with: Telegram's rule for editing a post with that media
/// (`messageMediaEditingOptions`), asked about its first item, as part of an album if it has
/// several.
func channelDraftMediaEditingOptions(media: [EngineRawMedia], peerId: EnginePeer.Id?) -> MessageMediaEditingOptions {
    guard let first = media.first, let peerId else {
        return []
    }
    let message = EngineRawMessage(
        stableId: 0,
        stableVersion: 0,
        id: EngineMessage.Id(peerId: peerId, namespace: Namespaces.Message.ScheduledLocal, id: 0),
        globallyUniqueId: nil,
        groupingKey: media.count > 1 ? 1 : nil,
        groupInfo: nil,
        threadId: nil,
        timestamp: 0,
        flags: [],
        tags: [],
        globalTags: [],
        localTags: [],
        customTags: [],
        forwardInfo: nil,
        author: nil,
        text: "",
        attributes: [],
        media: [first],
        peers: EngineSimpleDictionary(),
        associatedMessages: EngineSimpleDictionary(),
        associatedMessageIds: [],
        associatedMedia: [:],
        associatedThreadInfo: nil,
        associatedStories: [:]
    )
    return messageMediaEditingOptions(message: message)
}

/// Whether a draft's content can be edited (and so carry a caption), by Telegram's own rule for
/// editing a message (`canEditMessage`): stickers, round videos, contacts, locations, polls and
/// dice cannot. Asked about the account's own copy of the content, so only the content counts.
func channelDraftContentIsEditable(context: AccountContext, media: [EngineRawMedia]) -> Bool {
    guard let first = media.first else {
        return true
    }
    let message = EngineRawMessage(
        stableId: 0,
        stableVersion: 0,
        id: EngineMessage.Id(peerId: context.account.peerId, namespace: Namespaces.Message.QuickReplyCloud, id: 0),
        globallyUniqueId: nil,
        groupingKey: nil,
        groupInfo: nil,
        threadId: nil,
        timestamp: Int32(CFAbsoluteTimeGetCurrent() + kCFAbsoluteTimeIntervalSince1970),
        flags: [],
        tags: [],
        globalTags: [],
        localTags: [],
        customTags: [],
        forwardInfo: nil,
        author: nil,
        text: "",
        attributes: [],
        media: [first],
        peers: EngineSimpleDictionary(),
        associatedMessages: EngineSimpleDictionary(),
        associatedMessageIds: [],
        associatedMedia: [:],
        associatedThreadInfo: nil,
        associatedStories: [:]
    )
    return canEditMessage(accountPeerId: context.account.peerId, limitsConfiguration: context.currentLimitsConfiguration.with { EngineConfiguration.Limits($0) }, message: message)
}
