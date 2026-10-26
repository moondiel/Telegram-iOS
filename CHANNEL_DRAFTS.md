# Channel Drafts — rules and plan

Extra instructions for this feature, on top of `CLAUDE.md`. Read both before changing anything.

## What we are building

Channel admins can keep several drafts per broadcast channel:

- **Save Draft** in the long-press menu of the Send button saves the composer text as a draft and
  clears the composer.
- A **Drafts** button in the input field (next to the Scheduled Messages clock) opens the Drafts
  screen. It is shown while the channel has at least one draft and the text field is empty.
- The **Drafts screen** looks like Scheduled Messages: drafts are channel posts signed by the admin,
  with the same input panel (attachments, stickers, voice). Sending there creates a new draft:
  text, media, or an album with a caption.
- Long-press a draft: **Send Now · Use Draft · Copy · Edit · Delete · Select**, in the order of
  Scheduled Messages. Use Draft is offered for text drafts only (media cannot go into the
  composer). Delete, from the menu or the selection bar, confirms the way Scheduled Messages does
  (one destructive "Delete Draft(s)" item in the menu); Select takes the whole draft.
- **Use Draft** closes the screen and puts the text into the channel composer with a **Draft**
  header (like "Edit Message"). Save Draft then updates that draft; Send publishes the post and
  removes the draft; × in the header clears the composer and leaves the draft untouched.
- **Edit** edits the draft in place with the usual edit header and ✓.

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
