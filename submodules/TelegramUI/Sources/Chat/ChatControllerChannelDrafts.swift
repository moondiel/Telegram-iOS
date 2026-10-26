import Foundation
import UIKit
import SwiftSignalKit
import TelegramCore
import AccountContext
import ChatPresentationInterfaceState
import TextFormat
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
        navigationController.pushViewController(controller)
    }
}
