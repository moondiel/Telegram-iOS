import Foundation
import SwiftSignalKit
import TelegramCore
import TelegramUIPreferences

/// One saved post of a broadcast channel that has not been published yet.
public struct ChannelDraft: Codable, Equatable {
    public typealias Id = Int32

    /// Unique within the channel and never reused, so a stale reference (the composer's linked
    /// draft, a row on the Drafts screen) can never point at a different draft.
    public let id: Id
    /// The post text, or the caption when the draft has media.
    public var text: String
    public var entities: [MessageTextEntity]
    /// Attached media (photos, videos, files, voice, a sticker), PostboxCoding-encoded. Several
    /// items form an album. Read with `ChannelDraft.decodedMedia`.
    public var media: [Data]
    /// Rich content (headings, lists, tables...: what the composer sends as a rich message), as an
    /// encoded `RichTextMessageAttribute`. `text` is empty then. Read with `decodedRichText`.
    public var richText: Data?
    /// Creation time; drafts are listed in creation order, oldest first, like chat history.
    public let date: Int32
    /// Last edit time, `nil` until the draft is edited.
    public var editDate: Int32?

    public init(id: Id, text: String, entities: [MessageTextEntity], media: [Data] = [], richText: Data? = nil, date: Int32, editDate: Int32?) {
        self.id = id
        self.text = text
        self.entities = entities
        self.media = media
        self.richText = richText
        self.date = date
        self.editDate = editDate
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case text
        case entities
        case media
        case richText
        case date
        case editDate
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try container.decode(Id.self, forKey: .id)
        self.text = try container.decode(String.self, forKey: .text)
        self.entities = try container.decode([MessageTextEntity].self, forKey: .entities)
        // Drafts saved before media support have no media.
        self.media = try container.decodeIfPresent([Data].self, forKey: .media) ?? []
        self.richText = try container.decodeIfPresent(Data.self, forKey: .richText)
        self.date = try container.decode(Int32.self, forKey: .date)
        self.editDate = try container.decodeIfPresent(Int32.self, forKey: .editDate)
    }

    public var decodedMedia: [EngineRawMedia] {
        return self.media.compactMap(ChannelDraft.decodeMedia)
    }

    public static func encodeMedia(_ media: EngineRawMedia) -> Data {
        let encoder = EnginePostboxEncoder()
        encoder.encodeRootObject(media)
        return encoder.makeData()
    }

    public static func decodeMedia(_ data: Data) -> EngineRawMedia? {
        return EnginePostboxDecoder(buffer: EngineMemoryBuffer(data: data)).decodeRootObject() as? EngineRawMedia
    }

    public var decodedRichText: RichTextMessageAttribute? {
        return self.richText.flatMap(ChannelDraft.decodeRichText)
    }

    public static func encodeRichText(_ richText: RichTextMessageAttribute) -> Data {
        let encoder = EnginePostboxEncoder()
        encoder.encodeRootObject(richText)
        return encoder.makeData()
    }

    public static func decodeRichText(_ data: Data) -> RichTextMessageAttribute? {
        return EnginePostboxDecoder(buffer: EngineMemoryBuffer(data: data)).decodeRootObject() as? RichTextMessageAttribute
    }
}

/// Everything stored for one channel. Kept as one item-cache entry per channel.
private struct ChannelDraftsState: Codable, Equatable {
    var drafts: [ChannelDraft]
    var lastId: ChannelDraft.Id
    /// The draft taken into the channel's composer with Use Draft, so the composer finds it again
    /// when the chat is opened next, as an edit in progress survives leaving the chat.
    var linkedId: ChannelDraft.Id?

    static let empty = ChannelDraftsState(drafts: [], lastId: 0, linkedId: nil)
}

/// Runs the store's read-modify-writes one at a time: two of them started together (an update
/// and a link change, a delete from the Drafts screen and a publish from the chat) would
/// otherwise both read the same state and the second write would drop the first one's change.
private final class ChannelDraftsWriter {
    private let queue = Queue()
    private var isRunning = false
    private var pending: [() -> Void] = []

    func enqueue<T>(_ signal: Signal<T, NoError>) -> Signal<T, NoError> {
        return Signal { subscriber in
            let disposable = MetaDisposable()
            let queue = self.queue
            var didFinish = false
            let finish: () -> Void = { [weak self] in
                queue.async {
                    guard let self, !didFinish else {
                        return
                    }
                    didFinish = true
                    self.isRunning = false
                    self.runNext()
                }
            }
            queue.async {
                self.pending.append {
                    disposable.set(signal.start(next: { value in
                        subscriber.putNext(value)
                    }, completed: {
                        subscriber.putCompletion()
                        finish()
                    }))
                }
                self.runNext()
            }
            return ActionDisposable {
                disposable.dispose()
                finish()
            }
        }
    }

    private func runNext() {
        guard !self.isRunning, !self.pending.isEmpty else {
            return
        }
        self.isRunning = true
        self.pending.removeFirst()()
    }
}

/// Device-local storage of channel drafts in the account's item cache
/// (`ApplicationSpecificItemCacheCollectionId.channelDrafts`, keyed by channel id).
///
/// Drafts never leave the device. Syncing them between devices and between the admins of a channel
/// needs a server API (see the README); these functions are the only place that would change.
public enum ChannelDraftsStore {
    private static let writer = ChannelDraftsWriter()

    private static func key(peerId: EnginePeer.Id) -> EngineDataBuffer {
        let key = EngineDataBuffer(length: 8)
        key.setInt64(0, value: peerId.toInt64())
        return key
    }

    private static func stateItem(peerId: EnginePeer.Id) -> TelegramEngine.EngineData.Item.ItemCache.Item {
        return TelegramEngine.EngineData.Item.ItemCache.Item(collectionId: ApplicationSpecificItemCacheCollectionId.channelDrafts, id: self.key(peerId: peerId))
    }

    private static func currentTimestamp() -> Int32 {
        return Int32(CFAbsoluteTimeGetCurrent() + kCFAbsoluteTimeIntervalSince1970)
    }

    /// The drafts of a channel, oldest first. Emits again after every change.
    public static func drafts(engine: TelegramEngine, peerId: EnginePeer.Id) -> Signal<[ChannelDraft], NoError> {
        return engine.data.subscribe(self.stateItem(peerId: peerId))
        |> map { entry -> [ChannelDraft] in
            return entry?.get(ChannelDraftsState.self)?.drafts ?? []
        }
        |> distinctUntilChanged
    }

    /// Reads the state, applies `f` and writes the result back. Returns what `f` returns.
    private static func modify<T>(engine: TelegramEngine, peerId: EnginePeer.Id, _ f: @escaping (inout ChannelDraftsState) -> T) -> Signal<T, NoError> {
        let collectionId = ApplicationSpecificItemCacheCollectionId.channelDrafts
        let key = self.key(peerId: peerId)
        return self.writer.enqueue(engine.data.get(self.stateItem(peerId: peerId))
        |> mapToSignal { entry -> Signal<T, NoError> in
            var state = entry?.get(ChannelDraftsState.self) ?? .empty
            let result = f(&state)
            let write: Signal<Never, NoError>
            if state.drafts.isEmpty && state.lastId == 0 && state.linkedId == nil {
                write = engine.itemCache.remove(collectionId: collectionId, id: key)
            } else {
                write = engine.itemCache.put(collectionId: collectionId, id: key, item: state)
            }
            return write
            |> map { _ -> T in }
            |> then(.single(result))
        })
    }

    /// The draft taken into the channel's composer (Use Draft), if it still exists.
    public static func linkedDraft(engine: TelegramEngine, peerId: EnginePeer.Id) -> Signal<ChannelDraft?, NoError> {
        return engine.data.get(self.stateItem(peerId: peerId))
        |> map { entry -> ChannelDraft? in
            guard let state = entry?.get(ChannelDraftsState.self), let linkedId = state.linkedId else {
                return nil
            }
            return state.drafts.first(where: { $0.id == linkedId })
        }
    }

    /// Records which draft the composer holds (`nil`: none). Deleting that draft clears it.
    public static func setLinkedDraft(engine: TelegramEngine, peerId: EnginePeer.Id, id: ChannelDraft.Id?) -> Signal<Never, NoError> {
        return self.modify(engine: engine, peerId: peerId, { state -> Void in
            state.linkedId = id
        })
        |> ignoreValues
    }

    public struct NewDraft {
        public var text: String
        public var entities: [MessageTextEntity]
        public var media: [Data]
        public var richText: Data?

        public init(text: String, entities: [MessageTextEntity], media: [Data] = [], richText: Data? = nil) {
            self.text = text
            self.entities = entities
            self.media = media
            self.richText = richText
        }
    }

    /// Messages as the chat sends them, as drafts: one per message, or one per album (messages that
    /// share a grouping key) with the caption and media of its items. With the correlation id of
    /// each send, if any.
    public static func newDrafts(from messages: [EnqueueMessage]) -> [(draft: NewDraft, correlationId: Int64?)] {
        var groups: [(key: Int64?, correlationId: Int64?, items: [(text: String, entities: [MessageTextEntity], richText: RichTextMessageAttribute?, media: EngineRawMedia?)])] = []
        for message in messages {
            guard case let .message(text, attributes, _, mediaReference, _, _, _, localGroupingKey, correlationId, _) = message else {
                continue
            }
            var entities: [MessageTextEntity] = []
            var richText: RichTextMessageAttribute?
            for attribute in attributes {
                if let attribute = attribute as? TextEntitiesMessageAttribute {
                    entities = attribute.entities
                } else if let attribute = attribute as? RichTextMessageAttribute {
                    richText = attribute
                }
            }
            let item = (text: text, entities: entities, richText: richText, media: mediaReference?.media)
            if let localGroupingKey, let index = groups.firstIndex(where: { $0.key == localGroupingKey }) {
                groups[index].items.append(item)
                if let correlationId {
                    groups[index].correlationId = correlationId
                }
            } else {
                groups.append((key: localGroupingKey, correlationId: correlationId, items: [item]))
            }
        }
        var result: [(draft: NewDraft, correlationId: Int64?)] = []
        for group in groups {
            let caption = group.items.first(where: { !$0.text.isEmpty })
            let media = group.items.compactMap(\.media).map(ChannelDraft.encodeMedia)
            let richText = group.items.compactMap(\.richText).first.map(ChannelDraft.encodeRichText)
            let text = caption?.text ?? ""
            if text.isEmpty && media.isEmpty && richText == nil {
                continue
            }
            result.append((NewDraft(text: text, entities: caption?.entities ?? [], media: media, richText: richText), group.correlationId))
        }
        return result
    }

    /// Saves a new draft at the end of the list and returns it.
    public static func add(engine: TelegramEngine, peerId: EnginePeer.Id, text: String, entities: [MessageTextEntity], media: [Data] = []) -> Signal<ChannelDraft, NoError> {
        return self.add(engine: engine, peerId: peerId, drafts: [NewDraft(text: text, entities: entities, media: media)])
        |> map { drafts -> ChannelDraft in
            return drafts[0]
        }
    }

    /// Saves several new drafts in one write, in order, and returns them.
    public static func add(engine: TelegramEngine, peerId: EnginePeer.Id, drafts: [NewDraft]) -> Signal<[ChannelDraft], NoError> {
        let timestamp = self.currentTimestamp()
        return self.modify(engine: engine, peerId: peerId, { state -> [ChannelDraft] in
            var result: [ChannelDraft] = []
            for item in drafts {
                state.lastId += 1
                let draft = ChannelDraft(id: state.lastId, text: item.text, entities: item.entities, media: item.media, richText: item.richText, date: timestamp, editDate: nil)
                state.drafts.append(draft)
                result.append(draft)
            }
            return result
        })
    }

    /// Rewrites a draft in place: same id, same position. `media` replaces all of its media (photos
    /// saved to a draft taken into the composer); `replacingMedia` swaps one item (a photo or video
    /// replaced while editing); without either the media stays. Does nothing if the
    /// draft has been deleted meanwhile.
    public static func update(engine: TelegramEngine, peerId: EnginePeer.Id, id: ChannelDraft.Id, text: String, entities: [MessageTextEntity], richText: Data? = nil, media: [Data]? = nil, replacingMedia: (index: Int, media: Data)? = nil) -> Signal<Never, NoError> {
        let timestamp = self.currentTimestamp()
        return self.modify(engine: engine, peerId: peerId, { state -> Void in
            guard let index = state.drafts.firstIndex(where: { $0.id == id }) else {
                return
            }
            state.drafts[index].text = text
            state.drafts[index].entities = entities
            state.drafts[index].richText = richText
            if let media {
                state.drafts[index].media = media
            }
            if let replacingMedia {
                if replacingMedia.index < state.drafts[index].media.count {
                    state.drafts[index].media[replacingMedia.index] = replacingMedia.media
                } else {
                    state.drafts[index].media.append(replacingMedia.media)
                }
            }
            state.drafts[index].editDate = timestamp
        })
        |> ignoreValues
    }

    public static func delete(engine: TelegramEngine, peerId: EnginePeer.Id, ids: Set<ChannelDraft.Id>) -> Signal<Never, NoError> {
        return self.modify(engine: engine, peerId: peerId, { state -> Void in
            state.drafts.removeAll(where: { ids.contains($0.id) })
            if let linkedId = state.linkedId, ids.contains(linkedId) {
                state.linkedId = nil
            }
        })
        |> ignoreValues
    }
}
