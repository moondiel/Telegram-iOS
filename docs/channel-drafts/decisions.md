# Channel Drafts: decision log

Each entry gives what was decided, why, and what was tried and dropped.

## The Drafts screen is a chat controller, not a new screen

The Drafts screen is `ChatControllerImpl` with `ChatControllerSubject.customChatContents`, the
mechanism behind Quick Replies and Greeting Messages. Drafts are synthetic messages in the
`ScheduledLocal` namespace, laid out as the channel's own posts. The bubbles, input panel,
attachments, stickers, voice recording, selection and message menu are therefore Telegram's own.
A custom list would have had to copy all of them.

## It looks and behaves like Scheduled Messages

Scheduled Messages is the existing screen of "posts not published yet". Everything that has a
counterpart there copies it:

- the back button, the title pill and the channel avatar;
- the empty state;
- a send button without send options;
- the menu order;
- delete confirmation inside the menu;
- Clear All with its sheet, warning and "cleared" undo toast;
- the bubble with only the time in its corner.

Two things were tried and reverted:

- An admin signature and an "edited" mark on the bubbles. Scheduled Messages shows neither.
- A "Send Now" item in the draft menu. It was replaced by Use Draft (see below).

## Drafts are stored on the device

Telegram's API has one cloud draft per chat, the composer's own. Several drafts per channel would
need a new server API, which a client change cannot add. Drafts are kept in the account's item
cache, one entry per channel. `ChannelDraftsStore` is the single place to change when a server
API exists. Its writes are serialized because each one is a read-modify-write of the whole entry.

## Save Draft travels as a schedule time

The send menus of the composer, the attach screen, the photo editor, the recording preview and
the sticker and GIF menus already carry a schedule time down to the chat's send funnels. "Send
When Online" uses a reserved timestamp the same way. Save Draft uses another reserved timestamp,
`channelDraftSaveScheduleTimestamp`, and the funnels save instead of sending. This added one item
per send menu and no new plumbing through the media pickers.

## Use Draft works like Edit

A draft is a post that is not finished. Taking it back into the composer is closest to editing a
post, so Use Draft copies Edit:

- the header above the input, with no preview (a preview like Forward's was built, then removed:
  the Edit header has none);
- erasing the text keeps the header;
- media stays out of the text field;
- the caption limit;
- no link preview on a caption;
- a recording is discarded first;
- the composer's previous text comes back after ×, Save Draft or Send.

While a draft is linked, the chat carries the same `editMessageState` Edit sets for a post.
Every component that follows an edit then follows the draft with no code of its own: the
attachment button's replace icon and enabled state, the send button, send-as, and the input's
context queries. Earlier versions re-implemented these one by one, and each missed case was a
bug.

## The attachment button keeps the regular attach menu

Edit's media picker has only a Done button. With a linked draft, the attachment button keeps
Edit's replace icon and disabled state but opens the regular attach menu, so the send options
(Send, Schedule, Save Draft) stay. Picked or captured media replaces the draft's media. Edit's
picker was tried first and dropped: publishing on Done hid Schedule and Save Draft.

## Edit and captions follow `canEditMessage` and `messageMediaEditingOptions`

Which draft can be edited, and what its attachment button may do, are Telegram's own rules,
applied to a synthetic message with the draft's media:

- stickers, round videos, contacts, locations, polls and dice cannot be edited and take no
  caption;
- voice messages, round videos, stickers and music albums cannot have their media replaced.

When a draft cannot take a caption, the composer text is posted before it as a separate message,
as Forward posts its comment first.

## The composer link is stored with the drafts

Telegram keeps an edit in progress when the chat is closed. The draft in the composer is recorded
in the channel's entry (`linkedId`) and restored when the chat opens, without changing the
persisted `ChatInterfaceState`. Deleting that draft on the Drafts screen takes it out of the
composer, as deleting a post ends its edit.

## Showing the time needed one shared check

Telegram hides the time on every custom chat screen. Each bubble type has its own check. The
checks now ask `ChatControllerSubject.hidesMessageTime`, which is true for the business editors
and false for drafts. That is one line in each bubble node instead of a different hack per node.
