import Foundation
import SwiftSignalKit
import TelegramCore
import AccountContext
import TelegramPresentationData

/// The Drafts screen: a regular chat controller over these custom contents
/// (`ChatControllerSubject.customChatContents`), the same mechanism as Quick Replies and Welcome
/// Messages. Every draft is shown as a post of the channel signed by the admin, so the bubbles,
/// the input panel (attachments, stickers, voice), selection and the message menu are Telegram's own.
///
/// Sending on this screen saves a new draft; editing a bubble edits the draft; deleting removes it.
public final class ChannelDraftsChatContents: ChatCustomContentsProtocol {
    public let kind: ChatCustomContentsKind
    public let peerId: EnginePeer.Id

    /// Use Draft in the message menu (text drafts). Set by the channel chat that opened the screen.
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

    // MARK: Message ids

    /// A draft with an album is shown as several grouped messages; each gets its own id inside the
    /// draft's block of ids.
    private static let messagesPerDraft: Int32 = 64

    private static func messageId(channelId: EnginePeer.Id, draftId: ChannelDraft.Id, index: Int) -> EngineMessage.Id {
        return EngineMessage.Id(peerId: channelId, namespace: Namespaces.Message.ScheduledLocal, id: draftId * ChannelDraftsChatContents.messagesPerDraft + Int32(index))
    }

    public static func draftId(messageId: EngineMessage.Id) -> ChannelDraft.Id {
        return messageId.id / ChannelDraftsChatContents.messagesPerDraft
    }

    public func draft(messageId: EngineMessage.Id) -> ChannelDraft? {
        let draftId = ChannelDraftsChatContents.draftId(messageId: messageId)
        return self.drafts.first(where: { $0.id == draftId })
    }

    // MARK: History

    /// Drafts as channel posts: authored by the channel, signed with the admin's name, marked
    /// edited after an edit. Messages live in the scheduled-local namespace, so the bubbles behave
    /// like Scheduled Messages posts (no share button, comments or reactions). Nothing is stored in
    /// the message history.
    private static func historyView(drafts: [ChannelDraft], channel: EnginePeer, account: EnginePeer, signature: String) -> EngineRawMessageHistoryView {
        let channelPeer = channel._asPeer()
        var peers = EngineSimpleDictionary<EnginePeer.Id, EngineRawPeer>()
        peers[channel.id] = channelPeer
        peers[account.id] = account._asPeer()

        var entries: [EngineRawMessageHistoryEntry] = []
        for draft in drafts {
            let media = draft.decodedMedia
            // Text only, or one message per media item; the caption goes with the first one.
            let itemCount = max(1, media.count)
            let isAlbum = media.count > 1
            for index in 0 ..< itemCount {
                let isCaptionItem = index == 0
                var attributes: [EngineMessage.Attribute] = []
                if isCaptionItem && !draft.entities.isEmpty {
                    attributes.append(TextEntitiesMessageAttribute(entities: draft.entities))
                }
                attributes.append(AuthorSignatureMessageAttribute(signature: signature))
                if let editDate = draft.editDate {
                    attributes.append(EditedMessageAttribute(date: editDate, isHidden: false))
                }
                let id = ChannelDraftsChatContents.messageId(channelId: channel.id, draftId: draft.id, index: index)
                let message = EngineRawMessage(
                    stableId: UInt32(bitPattern: id.id),
                    stableVersion: UInt32(bitPattern: draft.editDate ?? 0),
                    id: id,
                    globallyUniqueId: nil,
                    groupingKey: isAlbum ? Int64(draft.id) : nil,
                    groupInfo: isAlbum ? .init(stableId: UInt32(bitPattern: draft.id)) : nil,
                    threadId: nil,
                    timestamp: draft.date,
                    flags: [],
                    tags: [],
                    globalTags: [],
                    localTags: [],
                    customTags: [],
                    forwardInfo: nil,
                    author: channelPeer,
                    text: isCaptionItem ? draft.text : "",
                    attributes: attributes,
                    media: index < media.count ? [media[index]] : [],
                    peers: peers,
                    associatedMessages: EngineSimpleDictionary(),
                    associatedMessageIds: [],
                    associatedMedia: [:],
                    associatedThreadInfo: nil,
                    associatedStories: [:]
                )
                entries.append(EngineRawMessageHistoryEntry(message: message, isRead: true, location: nil, monthLocation: nil, attributes: EngineRawMutableMessageHistoryEntryAttributes(authorIsContact: false)))
            }
        }
        return EngineRawMessageHistoryView(tag: nil, namespaces: .all, entries: entries, holeEarlier: false, holeLater: false, isLoading: false)
    }

    // MARK: Publishing

    /// Send Now in the menu of a draft with media: posts it to the channel as it is (album, caption
    /// and entities), then removes it from Drafts.
    public func publish(_ draft: ChannelDraft) {
        let media = draft.decodedMedia
        var captionAttributes: [EngineMessage.Attribute] = []
        if !draft.entities.isEmpty {
            captionAttributes.append(TextEntitiesMessageAttribute(entities: draft.entities))
        }
        var messages: [EnqueueMessage] = []
        if media.isEmpty {
            messages.append(.message(text: draft.text, attributes: captionAttributes, inlineStickers: [:], mediaReference: nil, threadId: nil, replyToMessageId: nil, replyToStoryId: nil, localGroupingKey: nil, correlationId: nil, bubbleUpEmojiOrStickersets: []))
        } else {
            let groupingKey: Int64? = media.count > 1 ? Int64.random(in: 1 ..< Int64.max) : nil
            for (index, item) in media.enumerated() {
                messages.append(.message(text: index == 0 ? draft.text : "", attributes: index == 0 ? captionAttributes : [], inlineStickers: [:], mediaReference: .standalone(media: item), threadId: nil, replyToMessageId: nil, replyToStoryId: nil, localGroupingKey: groupingKey, correlationId: nil, bubbleUpEmojiOrStickersets: []))
            }
        }
        let engine = self.context.engine
        let peerId = self.peerId
        let _ = (TelegramCore.enqueueMessages(account: self.context.account, peerId: peerId, messages: messages)
        |> mapToSignal { _ -> Signal<Never, NoError> in
            return ChannelDraftsStore.delete(engine: engine, peerId: peerId, ids: Set([draft.id]))
        }).startStandalone()
    }

    // MARK: ChatCustomContentsProtocol

    public var historyView: Signal<(EngineRawMessageHistoryView, EngineViewUpdateType), NoError> {
        return self.historyViewPromise.get()
    }

    public var messageLimit: Int? {
        return nil
    }

    /// Send on the Drafts screen saves a new draft: text, media, or an album with a caption
    /// (messages sharing a grouping key become one draft).
    public func enqueueMessages(messages: [EnqueueMessage]) {
        var groups: [(key: Int64?, items: [(text: String, entities: [MessageTextEntity], media: EngineRawMedia?)])] = []
        for message in messages {
            guard case let .message(text, attributes, _, mediaReference, _, _, _, localGroupingKey, _, _) = message else {
                continue
            }
            var entities: [MessageTextEntity] = []
            for attribute in attributes {
                if let attribute = attribute as? TextEntitiesMessageAttribute {
                    entities = attribute.entities
                }
            }
            let item = (text: text, entities: entities, media: mediaReference?.media)
            if let localGroupingKey, let index = groups.firstIndex(where: { $0.key == localGroupingKey }) {
                groups[index].items.append(item)
            } else {
                groups.append((key: localGroupingKey, items: [item]))
            }
        }
        for group in groups {
            let caption = group.items.first(where: { !$0.text.isEmpty })
            let media = group.items.compactMap(\.media).map(ChannelDraft.encodeMedia)
            let text = caption?.text ?? ""
            if text.isEmpty && media.isEmpty {
                continue
            }
            let _ = ChannelDraftsStore.add(engine: self.context.engine, peerId: self.peerId, text: text, entities: caption?.entities ?? [], media: media).startStandalone()
        }
    }

    public func deleteMessages(ids: [EngineMessage.Id]) {
        let draftIds = Set(ids.filter { $0.peerId == self.peerId }.map(ChannelDraftsChatContents.draftId(messageId:)))
        if draftIds.isEmpty {
            return
        }
        let _ = ChannelDraftsStore.delete(engine: self.context.engine, peerId: self.peerId, ids: draftIds).startStandalone()
    }

    /// ✓ in the "Edit Draft" header. Saving an empty text deletes a text-only draft; a draft with
    /// media keeps its media and loses its caption.
    public func editMessage(id: EngineMessage.Id, text: String, media: RequestEditMessageMedia, entities: TextEntitiesMessageAttribute?, webpagePreviewAttribute: WebpagePreviewMessageAttribute?, disableUrlPreview: Bool) {
        guard id.peerId == self.peerId, let draft = self.draft(messageId: id) else {
            return
        }
        if text.isEmpty && draft.media.isEmpty {
            let _ = ChannelDraftsStore.delete(engine: self.context.engine, peerId: self.peerId, ids: Set([draft.id])).startStandalone()
        } else {
            let _ = ChannelDraftsStore.update(engine: self.context.engine, peerId: self.peerId, id: draft.id, text: text, entities: entities?.entities ?? []).startStandalone()
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
