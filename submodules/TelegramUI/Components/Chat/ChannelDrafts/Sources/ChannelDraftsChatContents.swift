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

    /// The chat clears its input field, and animates the bubble out of it, when the sent message
    /// appears in the list carrying the send's correlation id (`OutgoingMessageInfoAttribute`), as
    /// every real sent message does. Drafts are not real messages, so the id is kept here, in
    /// memory, for the draft each send created.
    private var correlationIds: [ChannelDraft.Id: Int64] = [:]
    /// One entry per draft being saved, in save order: the correlation id of its send, if any.
    private var pendingCorrelationIds: [Int64?] = []

    /// Writes run one after another, so a second send never reads the state before the first one
    /// is stored.
    private var pendingWrites: [Signal<Never, NoError>] = []
    private var isWriting = false

    public init(context: AccountContext, peerId: EnginePeer.Id) {
        self.context = context
        self.peerId = peerId
        self.kind = .channelDrafts(peerId: peerId)

        let channelPeer = context.engine.data.subscribe(
            TelegramEngine.EngineData.Item.Peer.Peer(id: peerId)
        )
        let drafts = ChannelDraftsStore.drafts(engine: context.engine, peerId: peerId)
        self.disposable = (combineLatest(queue: Queue.mainQueue(),
            drafts,
            channelPeer
        )
        |> deliverOnMainQueue).startStrict(next: { [weak self] drafts, channel in
            guard let self, let channel else {
                return
            }
            let knownIds = Set(self.drafts.map(\.id))
            // New drafts appear in the order they were saved.
            for draft in drafts where !knownIds.contains(draft.id) && self.didEmitInitialView && !self.pendingCorrelationIds.isEmpty {
                if let correlationId = self.pendingCorrelationIds.removeFirst() {
                    self.correlationIds[draft.id] = correlationId
                }
            }
            self.drafts = drafts
            let view = ChannelDraftsChatContents.historyView(drafts: drafts, channel: channel, correlationIds: self.correlationIds)
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

    /// Every message a draft is shown as: one, or one per album item. A draft is selected and
    /// deleted as a whole.
    public func messageIds(draft: ChannelDraft) -> [EngineMessage.Id] {
        return (0 ..< max(1, draft.media.count)).map { index in
            return ChannelDraftsChatContents.messageId(channelId: self.peerId, draftId: draft.id, index: index)
        }
    }

    /// The number of drafts the given messages belong to.
    public static func draftCount(messageIds: Set<EngineMessage.Id>) -> Int {
        return Set(messageIds.map(ChannelDraftsChatContents.draftId(messageId:))).count
    }

    // MARK: History

    /// Drafts as channel posts, drawn as Scheduled Messages draws them: authored by the channel,
    /// only the time in the corner (no signature, no "edited"). Messages live in the scheduled-local namespace, so the bubbles behave
    /// like Scheduled Messages posts (no share button, comments or reactions). Nothing is stored in
    /// the message history.
    private static func historyView(drafts: [ChannelDraft], channel: EnginePeer, correlationIds: [ChannelDraft.Id: Int64]) -> EngineRawMessageHistoryView {
        let channelPeer = channel._asPeer()
        var peers = EngineSimpleDictionary<EnginePeer.Id, EngineRawPeer>()
        peers[channel.id] = channelPeer

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
                if isCaptionItem, let richText = draft.decodedRichText {
                    attributes.append(richText)
                }
                // The send carries its correlation id on its last message (the last album item).
                if index == itemCount - 1, let correlationId = correlationIds[draft.id] {
                    attributes.append(OutgoingMessageInfoAttribute(uniqueId: 0, flags: [], acknowledged: true, correlationId: correlationId, bubbleUpEmojiOrStickersets: [], partialReference: nil))
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

    // MARK: Writes

    private func write(_ signal: Signal<Never, NoError>) {
        self.pendingWrites.append(signal)
        self.runNextWrite()
    }

    private func runNextWrite() {
        guard !self.isWriting, !self.pendingWrites.isEmpty else {
            return
        }
        self.isWriting = true
        let signal = self.pendingWrites.removeFirst()
        // Holds the contents until the write is stored, even if the screen closes meanwhile.
        let _ = (signal |> deliverOnMainQueue).startStandalone(completed: {
            self.isWriting = false
            self.runNextWrite()
        })
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
        let newDrafts = ChannelDraftsStore.newDrafts(from: messages)
        if newDrafts.isEmpty {
            return
        }
        self.pendingCorrelationIds.append(contentsOf: newDrafts.map { $0.correlationId })
        self.write(ChannelDraftsStore.add(engine: self.context.engine, peerId: self.peerId, drafts: newDrafts.map { $0.draft }) |> ignoreValues)
    }

    /// Clear All in the selection header.
    public func deleteAllDrafts() {
        let ids = Set(self.drafts.map(\.id))
        if ids.isEmpty {
            return
        }
        self.write(ChannelDraftsStore.delete(engine: self.context.engine, peerId: self.peerId, ids: ids))
    }

    public func deleteMessages(ids: [EngineMessage.Id]) {
        let draftIds = Set(ids.filter { $0.peerId == self.peerId }.map(ChannelDraftsChatContents.draftId(messageId:)))
        if draftIds.isEmpty {
            return
        }
        self.write(ChannelDraftsStore.delete(engine: self.context.engine, peerId: self.peerId, ids: draftIds))
    }

    /// ✓ in the "Edit Draft" header, or a photo or video picked to replace the one being edited.
    /// Saving an empty text deletes a text-only draft; a draft with media keeps its media and
    /// loses its caption.
    public func editMessage(id: EngineMessage.Id, text: String, media: RequestEditMessageMedia, entities: TextEntitiesMessageAttribute?, webpagePreviewAttribute: WebpagePreviewMessageAttribute?, disableUrlPreview: Bool) {
        self.editMessage(id: id, text: text, media: media, entities: entities, richText: nil)
    }

    /// Edit with rich content: `richText` is the edited content when the composer cannot express it
    /// as text and entities (it then replaces the text), `nil` when it can.
    public func editMessage(id: EngineMessage.Id, text: String, media: RequestEditMessageMedia, entities: TextEntitiesMessageAttribute?, richText: RichTextMessageAttribute?) {
        guard id.peerId == self.peerId, let draft = self.draft(messageId: id) else {
            return
        }
        var replacingMedia: (index: Int, media: Data)?
        if case let .update(mediaReference) = media {
            // The item of the album this message shows.
            let index = Int(id.id - draft.id * ChannelDraftsChatContents.messagesPerDraft)
            replacingMedia = (index, ChannelDraft.encodeMedia(mediaReference.media))
        }
        if text.isEmpty && richText == nil && draft.media.isEmpty && replacingMedia == nil {
            self.write(ChannelDraftsStore.delete(engine: self.context.engine, peerId: self.peerId, ids: Set([draft.id])))
        } else {
            self.write(ChannelDraftsStore.update(engine: self.context.engine, peerId: self.peerId, id: draft.id, text: richText == nil ? text : "", entities: richText == nil ? (entities?.entities ?? []) : [], richText: richText.map(ChannelDraft.encodeRichText), replacingMedia: replacingMedia))
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
