# Channel Drafts

Channel Drafts lets a channel admin keep several unpublished posts per channel inside the official
Telegram-iOS client. A draft is saved from anything the channel can send. Drafts are listed on a
screen that looks and behaves like Scheduled Messages. A draft is taken back into the composer
with **Use Draft**, which works the way Edit works for a post.

The feature is built only from Telegram's own components, tokens, icons and strings. Drafts are
stored on the device: there is no server API for them (see
[How drafts are stored](#how-drafts-are-stored)).

## The flow

1. In a channel you can post in, type a post (or record a voice message, pick photos, choose a
   sticker or a GIF) and long-press Send. The send menu has **Save Draft**. The composer clears,
   and a **Drafts** button appears at the left of the input field.
2. **Drafts** opens the Drafts screen. It has Scheduled Messages' header, input panel and empty
   state. Each draft is drawn as a channel post with the time it was saved. Anything sent from this
   screen becomes a new draft, including text, rich text, media, albums, files, voice messages,
   round videos, stickers, polls, locations and contacts. The send button shows the Save Draft
   glyph.
3. Long-press a draft: **Use Draft · Copy · Edit · Delete · Select**, in Scheduled Messages' order.
   - **Edit** is Telegram's own edit: the edit header, ✓, and replacing a photo or video. It is
     offered only where Telegram lets a post be edited.
   - **Delete** asks for confirmation in the menu, as in Scheduled Messages. **Select** selects the
     whole draft, every item of an album.
   - **Clear All** in the selection header shows Scheduled Messages' sheet and warning. Then a
     "Drafts cleared" toast with Undo appears above the input.
4. **Use Draft** closes the screen and puts the draft into the channel composer under a **Draft**
   header, as Edit puts a post there:
   - Text keeps its formatting.
   - Media stays out of the text field. The header reads "Photo", "Video" and so on when there is
     no caption.
   - The caption limit applies.
   - The attachment button shows Edit's replace icon. It is disabled for a voice message, round
     video, sticker or music album.
5. From there:
   - **Send** or **Schedule** publishes the post and removes the draft.
   - **Save Draft** updates the draft.
   - **×** leaves the draft untouched.
   - Media picked from the attach menu replaces the draft's media. The picker keeps its send
     options (Send, Schedule, Save Draft).

   After any of these, the composer gets back what it held before Use Draft, as it does after an
   edit.

The full behaviour, including the edge cases, is specified in [spec.md](spec.md).

## Requirements

- macOS 26 and Xcode 26.6, the version `versions.json` pins. `Make.py` downloads the Bazel
  version it needs.
  - The branch includes one build fix that is not part of the feature: commit `17e34668`, *Build
    with Xcode 26*. It lets the code base, which targets the iOS 27.1 SDK, build with Xcode 26.
- Your own Telegram `api_id` and `api_hash`
  ([obtain them here](https://core.telegram.org/api/obtaining_api_id)).
- An account that is an admin of a broadcast channel with the right to post. Use a test channel:
  Send and Schedule publish for real.

## Build from scratch

### 1. Clone

```sh
git clone --recursive -j8 -b feature/channel-drafts https://github.com/moondiel/Telegram-iOS.git
cd Telegram-iOS
```

### 2. Build configuration

Edit `build-system/template_minimal_development_configuration.json`:

- `bundle_id`: `org.<identifier>.Telegram`, with an identifier from `openssl rand -hex 8`;
- `api_id` and `api_hash`: yours;
- `team_id`: in Keychain Access, open the `Apple Development: …` certificate; it is the
  Organizational Unit under Details.

### 3. Generate the Xcode project

A simulator build needs no provisioning profiles:

```sh
python3 build-system/Make/Make.py \
    --cacheDir="$HOME/telegram-bazel-cache" \
    generateProject \
    --configurationPath=build-system/template_minimal_development_configuration.json \
    --disableProvisioningProfiles
```

For a device, use `--xcodeManagedCodesigning` instead of `--disableProvisioningProfiles`. This
follows the main README.

### 4. Run

Open the generated project, choose the `Telegram` scheme and a simulator or your iPhone, then Run.
Log in and open a channel you admin.

### 5. Try it

Type a post, long-press Send, then **Save Draft**. Tap the **Drafts** button that appears in the
input field. From there, the flow above applies.

## What is real and what is limited

**Works for real**

- Saving everything the channel can send:
  - text and rich text (headings, lists, tables);
  - photos, videos and albums, including captions;
  - files and music;
  - voice messages, including after review, and round videos;
  - stickers, GIFs, polls, locations and contacts.
- The Drafts screen with Scheduled Messages' header, menu, selection, delete, Clear All with undo,
  and empty state.
- Use Draft, set up like Edit:
  - a voice message being recorded is discarded first;
  - the caption limit applies;
  - a caption gets no link preview;
  - the attachment button follows Telegram's media editing rules;
  - the composer's previous text comes back afterwards.
- Publishing with Send or Schedule; Save Draft from every send menu.
- The link between the composer and its draft survives reopening the chat. It ends when the draft
  is deleted on the Drafts screen.

**Limited**

- Drafts never leave the device. They are not synced to other devices or to other admins of the
  channel.
- Drafts belong to the account's local storage. Logging out removes them.
- A sticker, round video, poll, location, contact or dice cannot carry a caption. The composer
  text is posted before it, as a separate message, as Forward posts its comment first.
- Media picked for a draft that has an album replaces the whole album, not one item of it.
- There are no automated tests. The feature was checked by hand in a test channel.

**Not verified**

- Clearing the cache in Storage Usage with drafts that hold media picked from the device but never
  sent. That media lives only in the local media cache, so clearing it may break those drafts.
- The build steps above on a clean machine. They are Telegram's own steps for a development
  build; the feature was built with the author's configuration.

## How drafts are stored

Telegram's API has one cloud draft per chat (`messages.saveDraft`): the composer's own text, kept
per user. Several drafts per channel have no server counterpart, so they are kept on the device:

- All drafts of a channel are one entry in the account's item cache
  (`ApplicationSpecificItemCacheCollectionId.channelDrafts`, keyed by the channel id).
  - `ChannelDraft` holds the text and entities, the media (PostboxCoding-encoded `Media`), rich
    content (an encoded `RichTextMessageAttribute`) and the dates.
  - Ids are never reused, so a stale reference cannot point at another draft.
- The entry also records which draft is in the composer (`linkedId`). A reopened chat has it under
  the Draft header again, as an edit in progress survives leaving the chat.
- Every write is a read-modify-write of that entry. `ChannelDraftsWriter` runs them one at a time,
  so two writes started together cannot lose a change.

In production, drafts would need a server API for multiple drafts per peer, synced between
devices and shared between a channel's admins. `ChannelDraftsStore` is the only place that would
change.

## Where the code is

New files:

| File | Role |
|---|---|
| `submodules/TelegramUI/Components/Chat/ChannelDrafts/Sources/ChannelDraftsStore.swift` | `ChannelDraft`, device-local storage (add, update, delete, observe, the composer link), the serial writer |
| `submodules/TelegramUI/Components/Chat/ChannelDrafts/Sources/ChannelDraftsChatContents.swift` | The Drafts screen's `ChatCustomContentsProtocol`: drafts as channel posts, send = save, edit, delete |
| `submodules/TelegramUI/Sources/Chat/ChatControllerChannelDrafts.swift` | Every `ChatControllerImpl` hook: Save Draft, Use Draft, publishing, the Draft header's state, the draft menu, Clear All |
| `submodules/ChatPresentationInterfaceState/Sources/ChatChannelDraftsState.swift` | `ChatChannelDraftsState`: availability, the Drafts button, the draft in the composer |
| `submodules/TelegramUI/Images.xcassets/Chat/…` | `Input/Text/AccessoryIconDrafts`, `Input/SaveDraftIcon`, `Context Menu/SaveDraft`, `Context Menu/UseDraft` |
| `docs/channel-drafts/*` | This write-up, the spec and the decision log |

Existing files get small hooks: an enum case, one call into the feature, one branch.

- `AccountContext/Sources/ChatController.swift`:
  - `ChatCustomContentsKind.channelDrafts`;
  - the Save Draft marker `channelDraftSaveScheduleTimestamp`;
  - `ChatControllerSubject.hidesMessageTime`.
- `ChatPresentationInterfaceState` (`ChatPresentationInterfaceState.swift`,
  `ChatPanelInterfaceInteraction.swift`, `ChatTextInputPanelState.swift`): the `channelDrafts`
  state, the `openChannelDrafts` and `unlinkChannelDraft` interactions, and the `.channelDrafts`
  input button.
- `ChatSendMessageActionUI`: the Save Draft item in the send menu.
- `TelegramUI/Sources`:
  - `ChatController.swift`, `ChatControllerNode.swift`, `Chat/ChatControllerLoadDisplayNode.swift`,
    `Chat/ChatControllerMediaRecording.swift`, `ChatControllerOpenAttachmentMenu.swift`: the send
    funnels save or publish drafts;
  - `ChatInterfaceStateAccessoryPanels.swift`: the Draft and Edit Draft headers;
  - `ChatInterfaceStateContextMenus.swift`: the draft menu;
  - `ChatInterfaceInputContexts.swift`: the Drafts button;
  - `Chat/ChatControllerNavigationButtonAction.swift` and
    `ChatInterfaceStateNavigationButtons.swift`: Clear All and the avatar;
  - `ChatControllerContentData.swift`: the title;
  - `Chat/ChatControllerOpenPeer.swift`: the channel name stays on the screen;
  - `ChatHistoryListNode.swift`: drafts laid out as the channel's posts;
  - `Chat/UpdateChatPresentationInterfaceState.swift`: the state reducer;
  - the remaining `switch` sites get a `.channelDrafts` case.
- `TelegramUI/Components/Chat`:
  - `ChatTextInputPanelNode`: the Save Draft send glyph, the send button for a draft with media,
    the caption counter, the Drafts button;
  - `ChatInputMessageAccessoryPanel`: a custom header;
  - `ChatEmptyNode`: the empty state;
  - the message bubble nodes show the time on the Drafts screen through `hidesMessageTime`.
- `ChatEntityKeyboardInputNode`: Save Draft in the sticker and GIF menus.
- `AttachmentUI`, `AttachmentTextInputPanelNode`, `MediaPickerUI`, `LegacyMediaPickerUI`,
  `LegacyComponents`, `AttachmentFileController`, `ContactSelectionController`: Save Draft in the
  attach screen's and photo editor's send menus, and the Save Draft glyph on their send buttons.
- `ChatTitleView`: a title pill that fits its text.
- `TelegramPresentationData`: the icon resources.
- `TelegramUIPreferences/Sources/PostboxKeys.swift`: the item cache collection id.
- `Telegram/Telegram-iOS/en.lproj/Localizable.strings`: the `ChannelDrafts.*` strings and
  `Conversation.SendMessage.SaveDraft`.

The whole change is one patch against the branch's base commit `16a3d3c5`, without the Xcode 26
build fix:
[`channel-drafts.patch`](channel-drafts.patch). Apply it with `git apply --binary`.

## Further reading

- [spec.md](spec.md): the behaviour in full and the rules the code follows.
- [decisions.md](decisions.md): why the feature works the way it does.
