# Channel Drafts — decision log

Each entry is one decision and the reason for it. A decision that was later replaced stays in the
list, marked "Replaced by D-0xx". Entries marked (moondiel) are design calls made by the author.

## Environment and base (2026-10-26)

**D-001. The feature is built on commit `16a3d3c5`.** The branch starts from the author's
Telegram-iOS snapshot. `channel-drafts.patch` and the compare link are taken against that commit.

**D-002. Xcode 26 builds need one fix outside the feature.** The code base targets the iOS 27.1
SDK. `UIView.reservedRegions(kind:)` does not exist in Xcode 26, so commit `17e34668` compiles it
out there. The fix is not part of the feature and is left out of the patch.

**D-003. Rules first.** Only Telegram's components, tokens, icons and strings are used. The
feature lives in one module, existing files get small hooks, new files do not import Postbox, the
build stays warning-free, and every `switch` gets an explicit `.channelDrafts` case. See
[spec.md](spec.md).

## Storage (2026-10-26)

**D-004. Drafts are stored on the device.** Telegram's API has one cloud draft per chat, the
composer's own. Several drafts per channel need a server API that a client change cannot add.
Drafts are kept in the account's item cache, one entry per channel. `ChannelDraftsStore` is the
only place to change once a server API exists.

**D-005. Draft ids are never reused.** A stale reference (the composer's draft, a row on the
screen) can never point at another draft.

## The Drafts screen (2026-10-27)

**D-006. The Drafts screen is a chat controller.** It is `ChatControllerImpl` over
`customChatContents`, the mechanism behind Quick Replies and Greeting Messages, so the bubbles,
input panel, attachments, selection and menu are Telegram's own. Drafts are synthetic messages in
the `ScheduledLocal` namespace.

**D-007. It is Scheduled Messages with drafts in it. (moondiel)** Wherever Scheduled Messages has
a counterpart, the screen copies it:

- the back button, the title pill and the channel avatar (which opens the profile);
- the empty state;
- the send button without send options;
- the menu order;
- delete confirmation inside the menu;
- Clear All with its sheet and warning.

**D-008. The title pill fits its text. (moondiel)** It was briefly the standard chat width
(replaced the same night). `ChatTitleContent.custom` gained `hugsTitle`.

**D-009. The channel's name in a draft does not navigate away.** Tapping it stays on the screen,
as in Scheduled Messages, instead of opening the channel.

**D-010. Clear All shows the "cleared" undo toast. (moondiel)** This is Scheduled Messages'
`beginClearHistory`: the list looks cleared at once, and the drafts are deleted when the toast
commits.

## The bubble (2026-10-27)

**D-011. Drafts are drawn as the channel's posts.** The history list lays them out at the
channel's location. They are incoming broadcast posts, as scheduled posts are.

**D-012. An admin signature and an "edited" mark.** Replaced by D-013.

**D-013. Only the time in the corner. (moondiel)** Scheduled Messages shows neither a signature
nor "edited". Telegram hides the time on every custom chat screen, and each bubble type has its
own check. The checks now ask `ChatControllerSubject.hidesMessageTime`, which is false for drafts
only.

## Saving (2026-10-27)

**D-014. Save Draft travels as a schedule time.** Every send menu (composer, attach screen, photo
editor, recording preview, sticker and GIF menus) already carries a schedule time to the send
funnels. "Send When Online" uses a reserved timestamp the same way. Save Draft uses another one,
`channelDraftSaveScheduleTimestamp`, and the funnels save instead of sending. This adds one item
per menu and no new plumbing through the pickers.

**D-015. Save Draft for everything the channel can send. (moondiel)** This covers text, rich
text, media, albums, files, music, voice (also after review), round videos, stickers, GIFs, polls,
locations and contacts.

**D-016. The send button on the Drafts screen shows the Save Draft glyph.** It is a document with
a plus, drawn to match the schedule glyph's size and stroke.

## Use Draft (2026-10-27)

**D-017. Send Now in the draft menu.** Replaced by D-018.

**D-018. Use Draft instead of Send Now. (moondiel)** It takes the draft back into the channel
composer, so the post can be finished, scheduled or sent from there.

**D-019. Use Draft works like Edit. (moondiel)** It copies Edit:

- a header above the input; erasing the text keeps it;
- media stays out of the text field;
- the caption limit applies, and a caption gets no link preview;
- a recording is discarded first;
- the composer's previous text comes back after ×, Save Draft or Send;
- an edit in progress gives way.

**D-020. A preview behind the Draft header, drawn like the Forward preview.** Replaced by D-021.

**D-021. No preview. (moondiel)** The Edit header has none.

**D-022. A linked draft carries Edit's `editMessageState`.** Every component that follows an
edit then follows the draft with no code of its own:

- the attachment button's replace icon and its disabled state;
- the send button, send-as and the input's context queries;
- the input field's buttons.

The earlier one-by-one re-implementation kept missing cases.

**D-023. Editing and captions follow `canEditMessage` and `messageMediaEditingOptions`.** These
rules are applied to a synthetic message with the draft's media:

- no Edit and no caption for stickers, round videos, contacts, locations, polls and dice;
- no media replacement for voice messages, round videos, stickers and music albums.

When a draft cannot take a caption, the composer text is posted before it, as Forward posts its
comment first.

**D-024. Edit's media picker for a linked draft, Done publishes.** Replaced by D-025.

**D-025. The regular attach menu with its send options. (moondiel)** The attachment button keeps
Edit's replace icon and disabled state, but opens the regular menu, so Send, Schedule and Save
Draft stay. Picked or captured media replaces the draft's media, with or without a caption.

**D-026. Stickers, GIFs and voice sent beside a linked draft are separate messages.** They leave
the draft linked. Save Draft from their menus makes a new draft.

## Robustness (2026-10-27)

**D-027. The composer link is stored with the drafts.** Telegram keeps an edit in progress when
the chat closes. The draft in the composer is recorded in the channel's entry (`linkedId`) and
restored when the chat opens, without changing the persisted `ChatInterfaceState`.

**D-028. Deleting the linked draft on the Drafts screen takes it out of the composer.** This
works as deleting a post ends its edit.

**D-029. Store writes are serialized.** Each write is a read-modify-write of the channel's
entry. `ChannelDraftsWriter` runs them one at a time, so two writes started together cannot lose a
change.

## Packaging (2026-10-27)

**D-030. The repo carries the feature, not Telegram's guide.** The root README has a short
feature section and links to Telegram's compilation guide upstream. The write-up, this log and the
spec live in `docs/channel-drafts`, with the whole change as one patch.
