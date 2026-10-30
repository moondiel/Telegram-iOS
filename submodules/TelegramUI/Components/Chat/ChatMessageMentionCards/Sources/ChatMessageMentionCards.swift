import Foundation
import UIKit
import CoreText
import Display
import SwiftSignalKit
import TelegramCore
import TelegramPresentationData
import TextFormat
import AccountContext
import AvatarNode
import InteractiveTextComponent

// Mention cards: a mention in a message (`@username`, or a name linked to a person) is drawn as a
// card of its own, like a quote: the account's avatar, name and username, on the quote's bar and
// tint. Tapping it opens the account, as tapping the mention did. See docs/mention-cards/README.md.
//
// The card is text: the mention's range is replaced with the card's lines inside a block quote of
// the `.mention` kind, and the avatar is a layer the text node keeps in place of a run at the start
// of the first line (`InteractiveTextEmbeddedLayerItem`). So the card wraps, truncates, highlights,
// selects and lays out with the rest of the message, and the bubble needs no layout of its own.

// MARK: - Resolving usernames

/// Accounts behind `@username` mentions, resolved once and kept for the session. A username is
/// resolved through `resolvePeerByName`, which keeps its answers for two days, so a username costs a
/// request at most once in that time.
public final class MentionCardResolver {
    public enum Lookup {
        case peer(EnginePeer)
        /// No such account: the mention stays as it was written.
        case none
        /// Not asked yet, or the answer is on its way.
        case unknown
    }

    private struct Key: Hashable {
        let accountPeerId: EnginePeer.Id
        let isTestingEnvironment: Bool
    }

    private static let resolversLock = NSLock()
    private static var resolvers: [Key: MentionCardResolver] = [:]

    /// The resolver of the context's account.
    public static func shared(context: AccountContext) -> MentionCardResolver {
        let key = Key(accountPeerId: context.account.peerId, isTestingEnvironment: context.account.testingEnvironment)
        self.resolversLock.lock()
        defer {
            self.resolversLock.unlock()
        }
        if let current = self.resolvers[key] {
            return current
        }
        let resolver = MentionCardResolver(engine: context.engine)
        self.resolvers[key] = resolver
        return resolver
    }

    private let engine: TelegramEngine
    private let lock = NSLock()
    private var peers: [String: EnginePeer?] = [:]
    /// Main queue only: callers waiting for a username's answer.
    private var waiting: [String: [() -> Void]] = [:]

    private init(engine: TelegramEngine) {
        self.engine = engine
    }

    private static func normalized(_ username: String) -> String {
        var value = username
        if value.hasPrefix("@") {
            value.removeFirst()
        }
        return value.lowercased()
    }

    /// What is known about a username. Safe on any thread: message layout runs off the main queue.
    public func lookup(username: String) -> Lookup {
        let key = MentionCardResolver.normalized(username)
        self.lock.lock()
        defer {
            self.lock.unlock()
        }
        guard let entry = self.peers[key] else {
            return .unknown
        }
        if let peer = entry {
            return .peer(peer)
        } else {
            return .none
        }
    }

    /// Resolves a username, then calls `completion` on the main queue. Calls for a username already
    /// on its way share the request.
    public func resolve(username: String, completion: @escaping () -> Void) {
        assert(Thread.isMainThread)
        let key = MentionCardResolver.normalized(username)
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

        let _ = (self.engine.peers.resolvePeerByName(name: key, referrer: nil)
        |> mapToSignal { result -> Signal<EnginePeer?, NoError> in
            guard case let .result(peer) = result else {
                return .complete()
            }
            return .single(peer)
        }
        |> take(1)
        |> deliverOnMainQueue).startStandalone(next: { [weak self] peer in
            guard let self else {
                return
            }
            self.lock.lock()
            self.peers[key] = .some(peer)
            self.lock.unlock()
            let completions = self.waiting.removeValue(forKey: key) ?? []
            for completion in completions {
                completion()
            }
        })
    }
}

// MARK: - The card

/// How a message draws its mention cards, from the bubble's own text and quote styles.
public struct MentionCardStyle {
    public let titleFont: UIFont
    public let subtitleFont: UIFont
    public let titleColor: UIColor
    public let subtitleColor: UIColor
    /// The quote bar's colours: a message's quotes use the sender's name colours.
    public let barColor: UIColor
    public let secondaryBarColor: UIColor?
    public let tertiaryBarColor: UIColor?

    public init(titleFont: UIFont, subtitleFont: UIFont, titleColor: UIColor, subtitleColor: UIColor, barColor: UIColor, secondaryBarColor: UIColor?, tertiaryBarColor: UIColor?) {
        self.titleFont = titleFont
        self.subtitleFont = subtitleFont
        self.titleColor = titleColor
        self.subtitleColor = subtitleColor
        self.barColor = barColor
        self.secondaryBarColor = secondaryBarColor
        self.tertiaryBarColor = tertiaryBarColor
    }
}

/// The avatar at the start of a card's first line. The text node keeps one layer per key, so the
/// avatar is not reloaded when the message is laid out again.
private final class MentionCardAvatarItem: InteractiveTextEmbeddedLayerItem {
    let account: Account
    let peer: EnginePeer
    let size: CGFloat
    /// From the top of the first line to the bottom of the last: the avatar is centred on it.
    let cardTextHeight: CGFloat

    init(key: String, account: Account, peer: EnginePeer, size: CGFloat, cardTextHeight: CGFloat) {
        self.account = account
        self.peer = peer
        self.size = size
        self.cardTextHeight = cardTextHeight

        super.init(key: key)
    }

    override func isEqual(_ object: Any?) -> Bool {
        guard let other = object as? MentionCardAvatarItem else {
            return false
        }
        return self.key == other.key && self.peer == other.peer && self.size == other.size && self.cardTextHeight == other.cardTextHeight
    }

    override var hash: Int {
        return self.key.hashValue
    }

    override func makeLayer() -> CALayer {
        return MentionCardAvatarLayer()
    }

    override func update(layer: CALayer) {
        (layer as? MentionCardAvatarLayer)?.update(account: self.account, peer: self.peer, size: CGSize(width: self.size, height: self.size))
    }

    override func layerFrame(runRect: CGRect) -> CGRect {
        let y = runRect.minY + floor((self.cardTextHeight - self.size) / 2.0)
        return CGRect(x: runRect.minX, y: y, width: self.size, height: self.size)
    }
}

/// An avatar drawn into a plain layer: the peer's photo, or its initials on its colour.
private final class MentionCardAvatarLayer: CALayer {
    private let disposable = MetaDisposable()
    private var currentPeer: EnginePeer?
    private var currentSize: CGSize?

    override init() {
        super.init()

        self.contentsGravity = .resizeAspectFill
        self.contentsScale = UIScreenScale
        self.masksToBounds = true
    }

    override init(layer: Any) {
        super.init(layer: layer)
    }

    required init?(coder: NSCoder) {
        preconditionFailure()
    }

    deinit {
        self.disposable.dispose()
    }

    func update(account: Account, peer: EnginePeer, size: CGSize) {
        self.cornerRadius = size.width / 2.0
        if self.currentPeer == peer && self.currentSize == size {
            return
        }
        self.currentPeer = peer
        self.currentSize = size
        let signal = peerAvatarCompleteImage(account: account, peer: peer, size: size, font: avatarPlaceholderFont(size: floor(size.width * 0.4)))
        self.disposable.set((signal |> deliverOnMainQueue).startStrict(next: { [weak self] image in
            self?.contents = image?.cgImage
        }))
    }
}

private final class MentionCardRunDelegateData {
    let ascent: CGFloat
    let descent: CGFloat
    let width: CGFloat

    init(ascent: CGFloat, descent: CGFloat, width: CGFloat) {
        self.ascent = ascent
        self.descent = descent
        self.width = width
    }
}

/// One character as wide as `width`, with the line's ascent and descent, the way custom emoji
/// reserve their room. The character itself is never seen: a run carrying an embedded item is not
/// drawn, and the spacer of a second line is clear.
private func mentionCardSpacer(width: CGFloat, font: UIFont, attributes: [NSAttributedString.Key: Any]) -> NSAttributedString {
    let string = NSMutableAttributedString(string: "&", attributes: attributes)
    let range = NSRange(location: 0, length: string.length)
    string.addAttribute(.font, value: font, range: range)
    string.addAttribute(.foregroundColor, value: UIColor.clear, range: range)
    let data = MentionCardRunDelegateData(ascent: font.ascender, descent: -font.descender, width: width)
    var callbacks = CTRunDelegateCallbacks(
        version: kCTRunDelegateCurrentVersion,
        dealloc: { dataRef in
            Unmanaged<MentionCardRunDelegateData>.fromOpaque(dataRef).release()
        },
        getAscent: { dataRef in
            return Unmanaged<MentionCardRunDelegateData>.fromOpaque(dataRef).takeUnretainedValue().ascent
        },
        getDescent: { dataRef in
            return Unmanaged<MentionCardRunDelegateData>.fromOpaque(dataRef).takeUnretainedValue().descent
        },
        getWidth: { dataRef in
            return Unmanaged<MentionCardRunDelegateData>.fromOpaque(dataRef).takeUnretainedValue().width
        }
    )
    if let runDelegate = CTRunDelegateCreate(&callbacks, Unmanaged.passRetained(data).toOpaque()) {
        string.addAttribute(NSAttributedString.Key(kCTRunDelegateAttributeName as String), value: runDelegate, range: range)
    }
    return string
}

private let blockQuoteKey = NSAttributedString.Key(rawValue: "Attribute__Blockquote")
private let embeddedItemKey = NSAttributedString.Key(rawValue: "Attribute__EmbeddedItem")
private let peerMentionKey = NSAttributedString.Key(rawValue: TelegramTextAttributes.PeerMention)
private let peerTextMentionKey = NSAttributedString.Key(rawValue: TelegramTextAttributes.PeerTextMention)
private let spoilerKeys: [NSAttributedString.Key] = [
    NSAttributedString.Key(rawValue: "Attribute__Spoiler"),
    NSAttributedString.Key(rawValue: TelegramTextAttributes.Spoiler)
]

/// Replaces every mention in a message's text with a card. A mention stays as it was when it is
/// inside a quote or a code block (a card cannot nest in a block), under a spoiler, or when its
/// account is not known: a name linked to an account the message does not carry, or a username
/// that does not exist. Usernames not resolved yet are returned, so the caller can resolve them
/// and lay the message out again.
public func applyMentionCards(
    to text: NSAttributedString,
    context: AccountContext,
    strings: PresentationStrings,
    nameDisplayOrder: PresentationPersonNameOrder,
    style: MentionCardStyle,
    peerById: (EnginePeer.Id) -> EnginePeer?,
    resolver: MentionCardResolver
) -> (text: NSAttributedString, pendingUsernames: [String]) {
    struct Mention {
        let range: NSRange
        let tapKey: NSAttributedString.Key
        let tapValue: Any
        let peer: EnginePeer
    }

    var mentions: [Mention] = []
    var pendingUsernames: [String] = []
    let fullRange = NSRange(location: 0, length: text.length)

    func isCardable(_ range: NSRange) -> Bool {
        var result = true
        text.enumerateAttributes(in: range, options: [], using: { attributes, _, stop in
            if attributes[blockQuoteKey] != nil || spoilerKeys.contains(where: { attributes[$0] != nil }) || attributes[embeddedItemKey] != nil {
                result = false
                stop.pointee = true
            }
        })
        return result
    }

    text.enumerateAttribute(peerMentionKey, in: fullRange, options: [], using: { value, range, _ in
        guard let mention = value as? TelegramPeerMention, isCardable(range), let peer = peerById(mention.peerId) else {
            return
        }
        mentions.append(Mention(range: range, tapKey: peerMentionKey, tapValue: mention, peer: peer))
    })
    text.enumerateAttribute(peerTextMentionKey, in: fullRange, options: [], using: { value, range, _ in
        guard let username = value as? String, isCardable(range) else {
            return
        }
        switch resolver.lookup(username: username) {
        case let .peer(peer):
            mentions.append(Mention(range: range, tapKey: peerTextMentionKey, tapValue: username, peer: peer))
        case .none:
            break
        case .unknown:
            if !pendingUsernames.contains(username) {
                pendingUsernames.append(username)
            }
        }
    })

    if mentions.isEmpty {
        return (text, pendingUsernames)
    }
    mentions.sort(by: { $0.range.location < $1.range.location })

    let result = NSMutableAttributedString(attributedString: text)
    let barData = TextNodeBlockQuoteData(
        kind: .mention,
        title: nil,
        color: style.barColor,
        secondaryColor: style.secondaryBarColor,
        tertiaryColor: style.tertiaryBarColor,
        backgroundColor: style.barColor.withMultipliedAlpha(0.1),
        isCollapsible: false
    )

    // From the end, so the ranges still to come stay valid.
    for (index, mention) in mentions.enumerated().reversed() {
        let string = result.string as NSString
        var start = mention.range.location
        var end = mention.range.location + mention.range.length
        // The card takes a paragraph of its own: the spaces around the mention go, and a line break
        // goes in on each side that does not already have one.
        while start > 0, let scalar = UnicodeScalar(string.character(at: start - 1)), scalar == " " || scalar == "\t" {
            start -= 1
        }
        while end < string.length, let scalar = UnicodeScalar(string.character(at: end)), scalar == " " || scalar == "\t" {
            end += 1
        }
        let needsLeadingBreak = start > 0 && string.character(at: start - 1) != 0x0a
        let needsTrailingBreak = end < string.length && string.character(at: end) != 0x0a

        var plainAttributes = result.attributes(at: mention.range.location, effectiveRange: nil)
        for key in [peerMentionKey, peerTextMentionKey, NSAttributedString.Key.underlineStyle, NSAttributedString.Key.link] {
            plainAttributes.removeValue(forKey: key)
        }

        let peer = mention.peer
        let title = peer.displayTitle(strings: strings, displayOrder: nameDisplayOrder)
        let username = peer.addressName
        let lineCount: CGFloat = username == nil ? 1.0 : 2.0
        let cardTextHeight = lineCount == 2.0 ? ceil(style.titleFont.lineHeight + style.subtitleFont.lineHeight) : ceil(style.titleFont.lineHeight)
        let avatarSize = lineCount == 2.0 ? floor(cardTextHeight - 4.0) : floor(cardTextHeight)
        let indent = avatarSize + 8.0

        let card = NSMutableAttributedString()
        var avatarAttributes = plainAttributes
        avatarAttributes[embeddedItemKey] = MentionCardAvatarItem(
            key: "mention-\(index)-\(peer.id.toInt64())",
            account: context.account,
            peer: peer,
            size: avatarSize,
            cardTextHeight: cardTextHeight
        )
        card.append(mentionCardSpacer(width: indent, font: style.titleFont, attributes: avatarAttributes))
        var titleAttributes = plainAttributes
        titleAttributes[.font] = style.titleFont
        titleAttributes[.foregroundColor] = style.titleColor
        card.append(NSAttributedString(string: title, attributes: titleAttributes))
        if let username {
            var subtitleAttributes = plainAttributes
            subtitleAttributes[.font] = style.subtitleFont
            subtitleAttributes[.foregroundColor] = style.subtitleColor
            card.append(NSAttributedString(string: "\n", attributes: subtitleAttributes))
            card.append(mentionCardSpacer(width: indent, font: style.subtitleFont, attributes: subtitleAttributes))
            card.append(NSAttributedString(string: "@\(username)", attributes: subtitleAttributes))
        }
        let cardRange = NSRange(location: 0, length: card.length)
        card.addAttribute(blockQuoteKey, value: barData, range: cardRange)
        // The whole card opens the account, as the mention did.
        card.addAttribute(mention.tapKey, value: mention.tapValue, range: cardRange)

        let replacement = NSMutableAttributedString()
        if needsLeadingBreak {
            replacement.append(NSAttributedString(string: "\n", attributes: plainAttributes))
        }
        replacement.append(card)
        if needsTrailingBreak {
            replacement.append(NSAttributedString(string: "\n", attributes: plainAttributes))
        }
        // Selecting and copying give back the mention as it was written.
        let originalText = string.substring(with: NSRange(location: start, length: end - start))
        replacement.addAttribute(originalTextAttributeKey, value: OriginalTextAttribute(id: 1_000_000 + index, string: originalText), range: NSRange(location: 0, length: replacement.length))

        result.replaceCharacters(in: NSRange(location: start, length: end - start), with: replacement)
    }

    return (result, pendingUsernames)
}
