import Foundation

/// Channel Drafts state of a broadcast channel's chat, as the input panels need it.
public struct ChatChannelDraftsState: Equatable {
    /// The draft taken into the composer with Use Draft. Save Draft updates it, Send publishes
    /// and deletes it, × in its header (or clearing the composer) unlinks it.
    public struct AttachedDraft: Equatable {
        public let id: Int32
        public let text: String

        public init(id: Int32, text: String) {
            self.id = id
            self.text = text
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
