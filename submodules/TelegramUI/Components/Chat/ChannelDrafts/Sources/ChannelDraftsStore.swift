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
    public var text: String
    public var entities: [MessageTextEntity]
    /// Creation time; drafts are listed in creation order, oldest first, like chat history.
    public let date: Int32
    /// Last edit time, `nil` until the draft is edited.
    public var editDate: Int32?

    public init(id: Id, text: String, entities: [MessageTextEntity], date: Int32, editDate: Int32?) {
        self.id = id
        self.text = text
        self.entities = entities
        self.date = date
        self.editDate = editDate
    }
}

/// Everything stored for one channel. Kept as one item-cache entry per channel.
private struct ChannelDraftsState: Codable, Equatable {
    var drafts: [ChannelDraft]
    var lastId: ChannelDraft.Id

    static let empty = ChannelDraftsState(drafts: [], lastId: 0)
}

/// Device-local storage of channel drafts in the account's item cache
/// (`ApplicationSpecificItemCacheCollectionId.channelDrafts`, keyed by channel id).
///
/// Drafts never leave the device. Syncing them between devices and between the admins of a channel
/// needs a server API (see the README); these functions are the only place that would change.
public enum ChannelDraftsStore {
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
        return engine.data.get(self.stateItem(peerId: peerId))
        |> mapToSignal { entry -> Signal<T, NoError> in
            var state = entry?.get(ChannelDraftsState.self) ?? .empty
            let result = f(&state)
            let write: Signal<Never, NoError>
            if state.drafts.isEmpty && state.lastId == 0 {
                write = engine.itemCache.remove(collectionId: collectionId, id: key)
            } else {
                write = engine.itemCache.put(collectionId: collectionId, id: key, item: state)
            }
            return write
            |> map { _ -> T in }
            |> then(.single(result))
        }
    }

    /// Saves a new draft at the end of the list and returns it.
    public static func add(engine: TelegramEngine, peerId: EnginePeer.Id, text: String, entities: [MessageTextEntity]) -> Signal<ChannelDraft, NoError> {
        let timestamp = self.currentTimestamp()
        return self.modify(engine: engine, peerId: peerId, { state -> ChannelDraft in
            state.lastId += 1
            let draft = ChannelDraft(id: state.lastId, text: text, entities: entities, date: timestamp, editDate: nil)
            state.drafts.append(draft)
            return draft
        })
    }

    /// Rewrites a draft in place: same id, same position in the list. Does nothing if the draft
    /// has been deleted meanwhile.
    public static func update(engine: TelegramEngine, peerId: EnginePeer.Id, id: ChannelDraft.Id, text: String, entities: [MessageTextEntity]) -> Signal<Never, NoError> {
        let timestamp = self.currentTimestamp()
        return self.modify(engine: engine, peerId: peerId, { state -> Void in
            guard let index = state.drafts.firstIndex(where: { $0.id == id }) else {
                return
            }
            state.drafts[index].text = text
            state.drafts[index].entities = entities
            state.drafts[index].editDate = timestamp
        })
        |> ignoreValues
    }

    public static func delete(engine: TelegramEngine, peerId: EnginePeer.Id, ids: Set<ChannelDraft.Id>) -> Signal<Never, NoError> {
        return self.modify(engine: engine, peerId: peerId, { state -> Void in
            state.drafts.removeAll(where: { ids.contains($0.id) })
        })
        |> ignoreValues
    }
}
