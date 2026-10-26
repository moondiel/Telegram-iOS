# Channel Drafts — rules and plan

Extra instructions for this feature, on top of `CLAUDE.md`. Read both before changing anything.

## What we are building

Channel admins can keep several drafts per broadcast channel:

- **Save Draft** in the long-press menu of the Send button saves the composer text as a draft and
  clears the composer.
- A **Drafts** button in the input field (next to the Scheduled Messages clock) opens the Drafts
  screen. It is shown while the channel has at least one draft and the text field is empty.
- The **Drafts screen** is Scheduled Messages with drafts in it: the same back button, a "Drafts"
  title in a pill that fits it ("N Selected" during selection), the channel's avatar on the right
  (opens the channel profile), the same input panel. Sending there saves a draft (text, media, or an
  album with a caption); the send button shows the Save Draft glyph, has no send options, and the
  input clears and the bubble flies up exactly as for a scheduled message.
- Long-press a draft: **Use Draft · Copy · Edit · Delete · Select**, in the order of Scheduled
  Messages. Delete, from the menu or the selection bar, confirms the way Scheduled Messages does
  (one destructive "Delete Draft(s)" item in the menu); Select takes the whole draft. **Clear All**
  in the selection header shows Scheduled Messages' sheet and warning and deletes every draft.
- The Drafts button is the leftmost button in the channel's input field.
- **Use Draft** closes the screen and puts the text (or caption) into the channel composer with a
  **Draft** header, as editing a post does. A draft's photos, videos, files or audio stay out of
  the text field, like the media of a post being edited, and the header reads "Photo", "Video"...
  when there is no caption. Send or Schedule publishes a normal post (an album for several items,
  the composer text as the caption) and removes the draft; Save Draft updates it; × in the header
  unlinks it and leaves it untouched.
- **Edit** edits the draft in place with the usual edit header and ✓; while editing, the
  attachment button replaces the photo or video, through Telegram's own replace-media flow.
- Everything the chat can send is a draft on the Drafts screen: text, rich text (headings, lists,
  tables, the article editor), photos, videos, albums, files, voice messages (also after review),
  round videos, stickers, polls, locations, contacts. The attach screen's send button shows the
  Save Draft glyph, as the input's does.

The working prototype (UIKit, outside this repo) is the reference for behaviour, not for code.

## Rules

1. **Telegram's own building blocks only.** Every surface reuses what the app already has:
   - Drafts screen: `ChatControllerImpl` with `ChatControllerSubject.customChatContents`, like
     Quick Replies and Welcome Messages. No custom list, bubble or navigation code.
   - Send menu item: one `ContextMenuActionItem` in `ChatSendMessageContextScreen`.
   - Draft menu: `ContextMenuActionItem`s in `ChatInterfaceStateContextMenus.swift`.
   - Headers above the input: `ChatInputMessageAccessoryPanel`.
   - Input button: a new `ChatTextInputAccessoryItem` case drawn by `AccessoryItemIconButton`.
   - Empty state: `ChatEmptyNode`'s regular content (the "No scheduled messages here yet..." pill).
2. **Telegram's tokens only.** Colors and fonts come from `PresentationTheme` /
   `PresentationResourcesChat`; icons from `submodules/TelegramUI/Images.xcassets` (reuse an
   existing asset where one fits); every user-facing string is a key in
   `Telegram/Telegram-iOS/en.lproj/Localizable.strings`, read as `strings.<Key>`. No hard-coded
   colors, sizes, strings or new animations.
3. **The feature lives in one module.** `submodules/TelegramUI/Components/Chat/ChannelDrafts`
   holds the model, the storage and the custom chat contents. Changes in existing files are small
   hooks: a new enum case, one call into the module, one branch. Larger logic in `TelegramUI` goes
   into `Sources/Chat/ChatControllerChannelDrafts.swift`, not into `ChatController.swift`.
4. **No new server API.** Drafts are stored on the device, in the account's item cache
   (`ApplicationSpecificItemCacheCollectionId.channelDrafts`), keyed by channel id.
5. **No `import Postbox` in new files.** Use the `Engine*` / `EngineRaw*` aliases from TelegramCore.
6. **Builds are warning-free.** Modules compile with `-warnings-as-errors`.
7. **Exhaustive switches get a real decision.** When a new enum case (`.channelDrafts`) has to be
   added to a `switch`, choose the behaviour on purpose (usually the one of `.welcomeMessages`) and
   do not hide it behind `default:`.

## Stages

Each stage ends with a commit on `feature/channel-drafts`, a build on the device, and a check
of the listed behaviour before the next stage starts.

| # | Stage | Done when |
|---|---|---|
| 1 | **Data.** `ChannelDrafts` module: `ChannelDraft`, storage (add / update / delete / observe), the item cache collection id, strings. | The app builds; nothing visible changes. |
| 2 | **Save Draft + button.** `saveDraft` in the send menu for broadcast channels the user can post in; the composer clears; the Drafts accessory button appears. | Long-press Send → Save Draft → field clears, Drafts button appears; it hides while typing. |
| 3 | **Drafts screen.** `ChatCustomContentsKind.channelDrafts`, `ChannelDraftsChatContents` (drafts as signed channel posts), title, empty state, close button; sending on the screen creates a draft. | The button opens the screen with the saved drafts; empty state shows when there are none; a new draft can be added there. |
| 4 | **Draft menu.** Use Draft, Copy, Edit (edit header, ✓ saves, empty ✓ deletes), Delete, Select + delete selected. | Every item works on the screen. |
| 5 | **Linked draft.** "Draft" header in the channel composer; Save Draft updates the same draft; Send publishes and removes it; × clears and unlinks. | The full flow from the README works end to end. |
| 6 | **Package.** README in the feature repo format, `changes.patch` against `feature/custom`, screenshots and the demo video. | A Telegram developer can apply it from the README alone. |
