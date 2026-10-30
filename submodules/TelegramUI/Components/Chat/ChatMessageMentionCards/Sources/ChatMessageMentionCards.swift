import Foundation
import SwiftSignalKit
import TelegramCore
import AccountContext

// Mention cards: a text message that mentions an account (`@username`, or a name linked to an
// account with a username) shows that account's card under the text: the same preview Telegram
// draws for a `t.me/username` link, with the avatar, name, description and the "View Channel" /
// "Send Message" button. See docs/mention-cards/README.md.
//
// The card is Telegram's own link preview. The preview is asked from the server exactly as the
// composer asks for a pasted link (`messages.getWebPagePreview` on `https://t.me/<username>`), and
// the bubble shows it with `ChatMessageWebpageBubbleContentNode` on a copy of the message that
// carries it. Nothing is sent or stored: the message itself is unchanged.

/// Link previews of `t.me/<username>`, asked once per username and kept for the session.
public final class MentionPreviewStore {
    public enum Lookup {
        case webpage(TelegramMediaWebpage)
        /// No account, or no preview for it: the mention stays as written.
        case none
        /// Not asked yet, or the answer is on its way.
        case unknown
    }

    private struct Key: Hashable {
        let accountPeerId: EnginePeer.Id
        let isTestingEnvironment: Bool
    }

    private static let storesLock = NSLock()
    private static var stores: [Key: MentionPreviewStore] = [:]

    /// The store of the context's account.
    public static func shared(context: AccountContext) -> MentionPreviewStore {
        let key = Key(accountPeerId: context.account.peerId, isTestingEnvironment: context.account.testingEnvironment)
        self.storesLock.lock()
        defer {
            self.storesLock.unlock()
        }
        if let current = self.stores[key] {
            return current
        }
        let store = MentionPreviewStore(account: context.account)
        self.stores[key] = store
        return store
    }

    private let account: Account
    private let lock = NSLock()
    private var previews: [String: TelegramMediaWebpage?] = [:]
    /// Main queue only: callers waiting for a username's answer.
    private var waiting: [String: [() -> Void]] = [:]

    private init(account: Account) {
        self.account = account
    }

    static func normalized(_ username: String) -> String {
        var value = username
        if value.hasPrefix("@") {
            value.removeFirst()
        }
        return value.lowercased()
    }

    /// What is known about a username. Safe on any thread: message layout runs off the main queue.
    public func lookup(username: String) -> Lookup {
        let key = MentionPreviewStore.normalized(username)
        self.lock.lock()
        defer {
            self.lock.unlock()
        }
        guard let entry = self.previews[key] else {
            return .unknown
        }
        if let webpage = entry {
            return .webpage(webpage)
        } else {
            return .none
        }
    }

    /// Asks for a username's preview, then calls `completion` on the main queue. Calls for a
    /// username already on its way share the request.
    public func fetch(username: String, completion: @escaping () -> Void) {
        assert(Thread.isMainThread)
        let key = MentionPreviewStore.normalized(username)
        if case .unknown = self.lookup(username: key) {
        } else {
            completion()
            return
        }
        if var current = self.waiting[key] {
            current.append(completion)
            self.waiting[key] = current
            return
        }
        self.waiting[key] = [completion]

        let _ = (webpagePreview(account: self.account, urls: ["https://t.me/\(key)"])
        |> mapToSignal { result -> Signal<TelegramMediaWebpage?, NoError> in
            switch result {
            case .progress:
                return .complete()
            case let .result(value):
                guard let webpage = value?.webpage else {
                    return .single(nil)
                }
                if case .Loaded = webpage.content {
                    return .single(webpage)
                } else {
                    // A pending preview is followed by the loaded one.
                    return .complete()
                }
            }
        }
        |> take(1)
        |> deliverOnMainQueue).startStandalone(next: { [weak self] webpage in
            guard let self else {
                return
            }
            self.lock.lock()
            self.previews[key] = .some(webpage)
            self.lock.unlock()
            let completions = self.waiting.removeValue(forKey: key) ?? []
            for completion in completions {
                completion()
            }
        })
    }
}

/// How many of a message's mentions are considered for its card, in order.
private let maxMentionCandidates = 5

/// The usernames a message's mentions point to, in order, without repeats: `@username` mentions,
/// and names linked to an account that has a username. Mentions under a spoiler are left out, since
/// a card would reveal them.
public func mentionCardUsernames(text: String, entities: [MessageTextEntity], peerById: (EnginePeer.Id) -> EnginePeer?) -> [String] {
    let nsText = text as NSString
    var spoilerRanges: [Range<Int>] = []
    for entity in entities {
        if case .Spoiler = entity.type {
            spoilerRanges.append(entity.range)
        }
    }

    var result: [String] = []
    for entity in entities.sorted(by: { $0.range.lowerBound < $1.range.lowerBound }) {
        if result.count >= maxMentionCandidates {
            break
        }
        if spoilerRanges.contains(where: { $0.overlaps(entity.range) }) {
            continue
        }
        var username: String?
        switch entity.type {
        case .Mention:
            if entity.range.lowerBound >= 0 && entity.range.upperBound <= nsText.length {
                username = nsText.substring(with: NSRange(location: entity.range.lowerBound, length: entity.range.count))
            }
        case let .TextMention(peerId):
            username = peerById(peerId)?.addressName
        default:
            break
        }
        guard let username else {
            continue
        }
        let normalized = MentionPreviewStore.normalized(username)
        if !normalized.isEmpty && !result.contains(normalized) {
            result.append(normalized)
        }
    }
    return result
}

/// A message's mention card: the preview of its first mention that has one. While an earlier
/// mention is still being asked about, there is no card yet, so the card never moves from a later
/// mention to an earlier one. `usernamesToFetch` are the mentions still to ask about.
///
/// Only plain text messages get a card, as only they get link previews: no media (captions keep
/// their mentions as they are), no link preview of their own, not sponsored, not in a secret chat.
public func mentionCard(message: EngineMessage, context: AccountContext) -> (webpage: TelegramMediaWebpage?, usernamesToFetch: [String]) {
    if !message.media.isEmpty || message.adAttribute != nil || message.text.isEmpty {
        return (nil, [])
    }
    if message.id.peerId.namespace == Namespaces.Peer.SecretChat {
        return (nil, [])
    }
    guard let entities = message.textEntitiesAttribute?.entities, !entities.isEmpty else {
        return (nil, [])
    }
    let usernames = mentionCardUsernames(text: message.text, entities: entities, peerById: { peerId in
        return message.enginePeers[peerId]
    })
    if usernames.isEmpty {
        return (nil, [])
    }

    let store = MentionPreviewStore.shared(context: context)
    var usernamesToFetch: [String] = []
    for username in usernames {
        switch store.lookup(username: username) {
        case let .webpage(webpage):
            return (usernamesToFetch.isEmpty ? webpage : nil, usernamesToFetch)
        case .none:
            continue
        case .unknown:
            usernamesToFetch.append(username)
        }
    }
    return (nil, usernamesToFetch)
}
