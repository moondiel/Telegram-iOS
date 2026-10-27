import Foundation
import TelegramCore

/// Channel Drafts state of a broadcast channel's chat, as the input panels need it.
public struct ChatChannelDraftsState: Equatable {
    /// The draft taken into the composer with Use Draft. Save Draft updates it, Send publishes
    /// and deletes it, × in its header unlinks it. Erasing the text keeps it, as with Edit.
    public struct AttachedDraft: Equatable {
        public let id: Int32
        /// The draft's text, or its caption when it has media.
        public let text: String
        /// The draft's photos, videos, files or audio. They are not in the composer: Send and
        /// Schedule post them with the composer text as the caption (an album for several).
        public let media: [EngineRawMedia]
        /// What the attachment button may replace the media with, by Telegram's rule for editing a
        /// post with this media (`messageMediaEditingOptions`). Empty: the button is disabled
        /// (voice and round video messages, stickers, music albums), as when editing.
        public let mediaEditingOptions: MessageMediaEditingOptions

        public init(id: Int32, text: String, media: [EngineRawMedia] = [], mediaEditingOptions: MessageMediaEditingOptions = []) {
            self.id = id
            self.text = text
            self.media = media
            self.mediaEditingOptions = mediaEditingOptions
        }

        public static func ==(lhs: AttachedDraft, rhs: AttachedDraft) -> Bool {
            if lhs.id != rhs.id || lhs.text != rhs.text || lhs.media.count != rhs.media.count || lhs.mediaEditingOptions != rhs.mediaEditingOptions {
                return false
            }
            for i in 0 ..< lhs.media.count {
                if !lhs.media[i].isEqual(to: rhs.media[i]) {
                    return false
                }
            }
            return true
        }
    }

    /// Drafts can be saved in this chat (a broadcast channel the user can post in).
    public var isAvailable: Bool
    /// The channel has at least one draft; shows the Drafts button in the input field.
    public var hasDrafts: Bool
    public var attachedDraft: AttachedDraft?

    public init(isAvailable: Bool = false, hasDrafts: Bool = false, attachedDraft: AttachedDraft? = nil) {
        self.isAvailable = isAvailable
        self.hasDrafts = hasDrafts
        self.attachedDraft = attachedDraft
    }
}
