import Foundation
import SwiftSignalKit
import TelegramCore
import AccountContext
import TelegramPresentationData

/// The Drafts screen: a regular chat controller over these custom contents
/// (`ChatControllerSubject.customChatContents`), the same mechanism as Quick Replies and Welcome
/// Messages. Every draft is shown as a post of the channel signed by the admin, so the bubbles,
/// the input panel, selection and the message menu are Telegram's own.
///
/// Sending on this screen saves a new draft; editing a bubble edits the draft; deleting removes it.
public final class ChannelDraftsChatContents: ChatCustomContentsProtocol {
    public let kind: ChatCustomContentsKind
    public let peerId: EnginePeer.Id

    /// Use Draft in the message menu. Set by the channel chat that opened the screen.
    public var useDraft: ((ChannelDraft) -> Void)?

    /// The drafts currently shown, oldest first. Main queue.
    public private(set) var drafts: [ChannelDraft] = []

    private let context: AccountContext
    private let historyViewPromise = Promise<(EngineRawMessageHistoryView, EngineViewUpdateType)>()
    private var disposable: Disposable?
    private var didEmitInitialView = false

    public init(context: AccountContext, peerId: EnginePeer.Id) {
        self.context = context
        self.peerId = peerId
        self.kind = .channelDrafts(peerId: peerId)

        let peers = context.engine.data.subscribe(
            TelegramEngine.EngineData.Item.Peer.Peer(id: peerId),
            TelegramEngine.EngineData.Item.Peer.Peer(id: context.account.peerId)
        )
        self.disposable = (combineLatest(queue: Queue.mainQueue(),
            ChannelDraftsStore.drafts(engine: context.engine, peerId: peerId),
            peers
        )
        |> deliverOnMainQueue).startStrict(next: { [weak self] drafts, peers in
            guard let self, let channel = peers.0, let account = peers.1 else {
                return
            }
            self.drafts = drafts
            let presentationData = self.context.sharedContext.currentPresentationData.with { $0 }
            let signature = account.displayTitle(strings: presentationData.strings, displayOrder: presentationData.nameDisplayOrder)
            let view = ChannelDraftsChatContents.historyView(drafts: drafts, channel: channel, account: account, signature: signature)
            let updateType: EngineViewUpdateType = self.didEmitInitialView ? .Generic : .Initial
            self.didEmitInitialView = true
            self.historyViewPromise.set(.single((view, updateType)))
        })
    }

    deinit {
        self.disposable?.dispose()
    }

    public func draft(messageId: EngineMessage.Id) -> ChannelDraft? {
        return self.drafts.first(where: { $0.id == messageId.id })
    }

    /// Drafts as channel posts: authored by the channel, signed with the admin's name, marked
    /// edited after an edit. Message ids are the draft ids in the local namespace; nothing is stored
    /// in the message history.
    private static func historyView(drafts: [ChannelDraft], channel: EnginePeer, account: EnginePeer, signature: String) -> EngineRawMessageHistoryView {
        let channelPeer = channel._asPeer()
        var peers = EngineSimpleDictionary<EnginePeer.Id, EngineRawPeer>()
        peers[channel.id] = channelPeer
        peers[account.id] = account._asPeer()

        let entries = drafts.map { draft -> EngineRawMessageHistoryEntry in
            var attributes: [EngineMessage.Attribute] = []
            if !draft.entities.isEmpty {
                attributes.append(TextEntitiesMessageAttribute(entities: draft.entities))
            }
            attributes.append(AuthorSignatureMessageAttribute(signature: signature))
            if let editDate = draft.editDate {
                attributes.append(EditedMessageAttribute(date: editDate, isHidden: false))
            }
            let message = EngineRawMessage(
                stableId: UInt32(bitPattern: draft.id),
                stableVersion: UInt32(bitPattern: draft.editDate ?? 0),
                id: EngineMessage.Id(peerId: channel.id, namespace: Namespaces.Message.Local, id: draft.id),
                globallyUniqueId: nil,
                groupingKey: nil,
                groupInfo: nil,
                threadId: nil,
                timestamp: draft.date,
                flags: [],
                tags: [],
                globalTags: [],
                localTags: [],
                customTags: [],
                forwardInfo: nil,
                author: channelPeer,
                text: draft.text,
                attributes: attributes,
                media: [],
                peers: peers,
                associatedMessages: EngineSimpleDictionary(),
                associatedMessageIds: [],
                associatedMedia: [:],
                associatedThreadInfo: nil,
                associatedStories: [:]
            )
            return EngineRawMessageHistoryEntry(message: message, isRead: true, location: nil, monthLocation: nil, attributes: EngineRawMutableMessageHistoryEntryAttributes(authorIsContact: false))
        }
        return EngineRawMessageHistoryView(tag: nil, namespaces: .all, entries: entries, holeEarlier: false, holeLater: false, isLoading: false)
    }

    // MARK: ChatCustomContentsProtocol

    public var historyView: Signal<(EngineRawMessageHistoryView, EngineViewUpdateType), NoError> {
        return self.historyViewPromise.get()
    }

    public var messageLimit: Int? {
        return nil
    }

    /// Send on the Drafts screen: each text message becomes a new draft.
    public func enqueueMessages(messages: [EnqueueMessage]) {
        for message in messages {
            guard case let .message(text, attributes, _, _, _, _, _, _, _, _) = message, !text.isEmpty else {
                continue
            }
            var entities: [MessageTextEntity] = []
            for attribute in attributes {
                if let attribute = attribute as? TextEntitiesMessageAttribute {
                    entities = attribute.entities
                }
            }
            let _ = ChannelDraftsStore.add(engine: self.context.engine, peerId: self.peerId, text: text, entities: entities).startStandalone()
        }
    }

    public func deleteMessages(ids: [EngineMessage.Id]) {
        let draftIds = Set(ids.filter { $0.peerId == self.peerId }.map(\.id))
        if draftIds.isEmpty {
            return
        }
        let _ = ChannelDraftsStore.delete(engine: self.context.engine, peerId: self.peerId, ids: draftIds).startStandalone()
    }

    /// ✓ in the "Edit Draft" header. Saving an empty text deletes the draft.
    public func editMessage(id: EngineMessage.Id, text: String, media: RequestEditMessageMedia, entities: TextEntitiesMessageAttribute?, webpagePreviewAttribute: WebpagePreviewMessageAttribute?, disableUrlPreview: Bool) {
        guard id.peerId == self.peerId else {
            return
        }
        if text.isEmpty {
            let _ = ChannelDraftsStore.delete(engine: self.context.engine, peerId: self.peerId, ids: Set([id.id])).startStandalone()
        } else {
            let _ = ChannelDraftsStore.update(engine: self.context.engine, peerId: self.peerId, id: id.id, text: text, entities: entities?.entities ?? []).startStandalone()
        }
    }

    public func quickReplyUpdateShortcut(value: String) {
    }

    public func businessLinkUpdate(message: String, entities: [MessageTextEntity], title: String?) {
    }

    public func loadMore() {
    }

    public func hashtagSearchUpdate(query: String) {
    }

    public var hashtagSearchResultsUpdate: ((SearchMessagesResult, SearchMessagesState)) -> Void = { _ in }
}
