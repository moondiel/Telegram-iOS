import Foundation
import UIKit
import CoreText
import Display
import SwiftSignalKit
import TelegramCore
import TextFormat
import AccountContext
import LocalizedPeerData
import AvatarNode
import InteractiveTextComponent

// Mention pills: a mention in a message (`@username`, or a name linked to an account) is drawn in
// the line as a pill: the account's round avatar and its name on a tinted capsule, the way Notion,
// Slack and Discord draw mentions. Tapping it opens the account, as tapping the mention did. See
// docs/mention-cards/README.md.
//
// The pill is one run of the message's text: the mention's characters are replaced with a single
// character whose width a run delegate sets (the way custom emoji reserve their room), and the text
// node keeps a layer drawing the pill in that run's place (`InteractiveTextEmbeddedLayerItem`). So
// the pill flows, wraps, highlights and lays out with the rest of the line, and the bubble needs
// no layout of its own.

// MARK: - Resolving usernames

/// Accounts behind `@username` mentions, resolved once and kept for the session. A username is
/// resolved through `resolvePeerByName`, which keeps its answers for two days, so a username costs a
/// request at most once in that time.
public final class MentionPillResolver {
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
    private static var resolvers: [Key: MentionPillResolver] = [:]

    /// The resolver of the context's account.
    public static func shared(context: AccountContext) -> MentionPillResolver {
        let key = Key(accountPeerId: context.account.peerId, isTestingEnvironment: context.account.testingEnvironment)
        self.resolversLock.lock()
        defer {
            self.resolversLock.unlock()
        }
        if let current = self.resolvers[key] {
            return current
        }
        let resolver = MentionPillResolver(engine: context.engine)
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
        let key = MentionPillResolver.normalized(username)
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
        let key = MentionPillResolver.normalized(username)
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

// MARK: - The pill

/// How a message draws its mention pills: the bubble's text font and link colour.
public struct MentionPillStyle: Equatable {
    public let font: UIFont
    public let textColor: UIColor
    public let backgroundColor: UIColor

    public init(font: UIFont, textColor: UIColor, backgroundColor: UIColor) {
        self.font = font
        self.textColor = textColor
        self.backgroundColor = backgroundColor
    }
}

/// The pill's measurements for a font.
private struct MentionPillMetrics {
    /// Room on each side of the pill, so it does not touch the text around it.
    static let margin: CGFloat = 1.0
    /// The avatar's inset from the capsule's edge.
    static let avatarInset: CGFloat = 2.0
    static let avatarSpacing: CGFloat = 5.0
    static let trailingInset: CGFloat = 9.0
    static let maxWidth: CGFloat = 220.0
    /// The line grows by this much above and below, so the capsule is a little taller than the text.
    static let lineOutset: CGFloat = 1.0

    let height: CGFloat
    let avatarSize: CGFloat

    init(font: UIFont) {
        self.height = ceil(font.ascender - font.descender) + MentionPillMetrics.lineOutset * 2.0
        self.avatarSize = self.height - MentionPillMetrics.avatarInset * 2.0
    }
}

/// The run a pill occupies. The text node keeps one layer per key, so the avatar is not reloaded
/// when the message is laid out again.
private final class MentionPillItem: InteractiveTextEmbeddedLayerItem {
    let account: Account
    let peer: EnginePeer
    let title: String
    let style: MentionPillStyle
    let pillSize: CGSize
    let margin: CGFloat

    init(key: String, account: Account, peer: EnginePeer, title: String, style: MentionPillStyle, pillSize: CGSize, margin: CGFloat) {
        self.account = account
        self.peer = peer
        self.title = title
        self.style = style
        self.pillSize = pillSize
        self.margin = margin

        super.init(key: key)
    }

    override func isEqual(_ object: Any?) -> Bool {
        guard let other = object as? MentionPillItem else {
            return false
        }
        return self.key == other.key && self.peer == other.peer && self.title == other.title && self.style == other.style && self.pillSize == other.pillSize
    }

    override var hash: Int {
        return self.key.hashValue
    }

    override func makeLayer() -> CALayer {
        return MentionPillLayer()
    }

    override func update(layer: CALayer) {
        (layer as? MentionPillLayer)?.update(account: self.account, peer: self.peer, title: self.title, style: self.style, size: self.pillSize)
    }

    override func layerFrame(runRect: CGRect) -> CGRect {
        return CGRect(
            x: runRect.minX + self.margin,
            y: runRect.minY + floor((runRect.height - self.pillSize.height) / 2.0),
            width: self.pillSize.width,
            height: self.pillSize.height
        )
    }
}

/// A pill drawn into a plain layer: the capsule, the avatar (the photo, or the initials on the
/// account's colour) and the name.
private final class MentionPillLayer: CALayer {
    private struct Content: Equatable {
        let peer: EnginePeer
        let title: String
        let style: MentionPillStyle
        let size: CGSize
    }

    private let avatarDisposable = MetaDisposable()
    private var content: Content?
    private var avatarPeerId: EnginePeer.Id?
    private var avatarImage: UIImage?

    override init() {
        super.init()

        self.contentsScale = UIScreenScale
    }

    override init(layer: Any) {
        super.init(layer: layer)
    }

    required init?(coder: NSCoder) {
        preconditionFailure()
    }

    deinit {
        self.avatarDisposable.dispose()
    }

    func update(account: Account, peer: EnginePeer, title: String, style: MentionPillStyle, size: CGSize) {
        let content = Content(peer: peer, title: title, style: style, size: size)
        if self.content == content {
            return
        }
        self.content = content

        let avatarSize = size.height - MentionPillMetrics.avatarInset * 2.0
        if self.avatarPeerId != peer.id {
            self.avatarPeerId = peer.id
            self.avatarImage = nil
            let signal = peerAvatarCompleteImage(account: account, peer: peer, size: CGSize(width: avatarSize, height: avatarSize), font: avatarPlaceholderFont(size: floor(avatarSize * 0.45)))
            self.avatarDisposable.set((signal |> deliverOnMainQueue).startStrict(next: { [weak self] image in
                guard let self else {
                    return
                }
                self.avatarImage = image
                self.redraw()
            }))
        }
        self.redraw()
    }

    private func redraw() {
        guard let content = self.content else {
            return
        }
        let metrics = MentionPillMetrics(font: content.style.font)
        let avatarImage = self.avatarImage
        self.contents = generateImage(content.size, rotatedContext: { size, context in
            context.clear(CGRect(origin: CGPoint(), size: size))

            context.setFillColor(content.style.backgroundColor.cgColor)
            context.addPath(UIBezierPath(roundedRect: CGRect(origin: CGPoint(), size: size), cornerRadius: size.height / 2.0).cgPath)
            context.fillPath()

            let avatarFrame = CGRect(x: MentionPillMetrics.avatarInset, y: MentionPillMetrics.avatarInset, width: metrics.avatarSize, height: metrics.avatarSize)
            if let avatarImage {
                UIGraphicsPushContext(context)
                avatarImage.draw(in: avatarFrame)
                UIGraphicsPopContext()
            } else {
                context.setFillColor(content.style.textColor.withMultipliedAlpha(0.2).cgColor)
                context.fillEllipse(in: avatarFrame)
            }

            let title = NSAttributedString(string: content.title, attributes: [.font: content.style.font, .foregroundColor: content.style.textColor])
            let titleHeight = ceil(content.style.font.lineHeight)
            UIGraphicsPushContext(context)
            title.draw(at: CGPoint(x: avatarFrame.maxX + MentionPillMetrics.avatarSpacing, y: floor((size.height - titleHeight) / 2.0)))
            UIGraphicsPopContext()
        })?.cgImage
    }
}

private final class MentionPillRunDelegateData {
    let ascent: CGFloat
    let descent: CGFloat
    let width: CGFloat

    init(ascent: CGFloat, descent: CGFloat, width: CGFloat) {
        self.ascent = ascent
        self.descent = descent
        self.width = width
    }
}

/// One character as wide as the pill, the way custom emoji reserve their room. The character itself
/// is never seen: a run carrying an embedded item is not drawn.
private func mentionPillRun(width: CGFloat, ascent: CGFloat, descent: CGFloat, font: UIFont, attributes: [NSAttributedString.Key: Any]) -> NSAttributedString {
    let string = NSMutableAttributedString(string: "&", attributes: attributes)
    let range = NSRange(location: 0, length: string.length)
    string.addAttribute(.font, value: font, range: range)
    string.addAttribute(.foregroundColor, value: UIColor.clear, range: range)
    let data = MentionPillRunDelegateData(ascent: ascent, descent: descent, width: width)
    var callbacks = CTRunDelegateCallbacks(
        version: kCTRunDelegateCurrentVersion,
        dealloc: { dataRef in
            Unmanaged<MentionPillRunDelegateData>.fromOpaque(dataRef).release()
        },
        getAscent: { dataRef in
            return Unmanaged<MentionPillRunDelegateData>.fromOpaque(dataRef).takeUnretainedValue().ascent
        },
        getDescent: { dataRef in
            return Unmanaged<MentionPillRunDelegateData>.fromOpaque(dataRef).takeUnretainedValue().descent
        },
        getWidth: { dataRef in
            return Unmanaged<MentionPillRunDelegateData>.fromOpaque(dataRef).takeUnretainedValue().width
        }
    )
    if let runDelegate = CTRunDelegateCreate(&callbacks, Unmanaged.passRetained(data).toOpaque()) {
        string.addAttribute(NSAttributedString.Key(kCTRunDelegateAttributeName as String), value: runDelegate, range: range)
    }
    return string
}

/// The name as it fits in a pill: shortened with an ellipsis when it is wider than `maxWidth`.
private func mentionPillTitle(_ title: String, font: UIFont, maxWidth: CGFloat) -> (String, CGFloat) {
    func width(_ value: String) -> CGFloat {
        return ceil(NSAttributedString(string: value, attributes: [.font: font]).size().width)
    }
    let fullWidth = width(title)
    if fullWidth <= maxWidth {
        return (title, fullWidth)
    }
    var characters = Array(title)
    while !characters.isEmpty {
        characters.removeLast()
        let candidate = String(characters).trimmingCharacters(in: .whitespaces) + "…"
        let candidateWidth = width(candidate)
        if candidateWidth <= maxWidth {
            return (candidate, candidateWidth)
        }
    }
    return ("…", width("…"))
}

private let embeddedItemKey = NSAttributedString.Key(rawValue: "Attribute__EmbeddedItem")
private let peerMentionKey = NSAttributedString.Key(rawValue: TelegramTextAttributes.PeerMention)
private let peerTextMentionKey = NSAttributedString.Key(rawValue: TelegramTextAttributes.PeerTextMention)
private let spoilerKeys: [NSAttributedString.Key] = [
    NSAttributedString.Key(rawValue: "Attribute__Spoiler"),
    NSAttributedString.Key(rawValue: TelegramTextAttributes.Spoiler)
]

/// Replaces every mention in a message's text with a pill. A mention stays as it was under a
/// spoiler (a pill would reveal it), where a custom emoji sits in it, or when its account is not
/// known: a name linked to an account the message does not carry, or a username that does not
/// exist. Usernames not resolved yet are returned, so the caller can resolve them and lay the
/// message out again.
public func applyMentionPills(
    to text: NSAttributedString,
    context: AccountContext,
    style: MentionPillStyle,
    peerById: (EnginePeer.Id) -> EnginePeer?,
    resolver: MentionPillResolver
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

    func canBePill(_ range: NSRange) -> Bool {
        var result = true
        text.enumerateAttributes(in: range, options: [], using: { attributes, _, stop in
            if spoilerKeys.contains(where: { attributes[$0] != nil }) || attributes[embeddedItemKey] != nil {
                result = false
                stop.pointee = true
            }
        })
        return result
    }

    text.enumerateAttribute(peerMentionKey, in: fullRange, options: [], using: { value, range, _ in
        guard let mention = value as? TelegramPeerMention, canBePill(range), let peer = peerById(mention.peerId) else {
            return
        }
        mentions.append(Mention(range: range, tapKey: peerMentionKey, tapValue: mention, peer: peer))
    })
    text.enumerateAttribute(peerTextMentionKey, in: fullRange, options: [], using: { value, range, _ in
        guard let username = value as? String, canBePill(range) else {
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

    let metrics = MentionPillMetrics(font: style.font)
    let maxTitleWidth = MentionPillMetrics.maxWidth - MentionPillMetrics.avatarInset - metrics.avatarSize - MentionPillMetrics.avatarSpacing - MentionPillMetrics.trailingInset
    let result = NSMutableAttributedString(attributedString: text)

    // From the end, so the ranges still to come stay valid.
    for (index, mention) in mentions.enumerated().reversed() {
        let original = (result.string as NSString).substring(with: mention.range)

        var attributes = result.attributes(at: mention.range.location, effectiveRange: nil)
        // The pill draws its own name; the mention's underline and link styling would be drawn
        // under it.
        for key in [NSAttributedString.Key.underlineStyle, NSAttributedString.Key.link, NSAttributedString.Key.strikethroughStyle] {
            attributes.removeValue(forKey: key)
        }
        // The pill opens the account, as the mention did.
        attributes[mention.tapKey] = mention.tapValue

        let (title, titleWidth) = mentionPillTitle(mention.peer.compactDisplayTitle, font: style.font, maxWidth: maxTitleWidth)
        let pillSize = CGSize(width: MentionPillMetrics.avatarInset + metrics.avatarSize + MentionPillMetrics.avatarSpacing + titleWidth + MentionPillMetrics.trailingInset, height: metrics.height)
        attributes[embeddedItemKey] = MentionPillItem(
            key: "mention-pill-\(index)-\(mention.peer.id.toInt64())",
            account: context.account,
            peer: mention.peer,
            title: title,
            style: style,
            pillSize: pillSize,
            margin: MentionPillMetrics.margin
        )
        // Selecting and copying give back the mention as it was written.
        attributes[originalTextAttributeKey] = OriginalTextAttribute(id: 1_000_000 + index, string: original)

        let run = mentionPillRun(
            width: pillSize.width + MentionPillMetrics.margin * 2.0,
            ascent: style.font.ascender + MentionPillMetrics.lineOutset,
            descent: -style.font.descender + MentionPillMetrics.lineOutset,
            font: style.font,
            attributes: attributes
        )
        result.replaceCharacters(in: mention.range, with: run)
    }

    return (result, pendingUsernames)
}
