# Mention Cards

Mention Cards draws a mention in a message as a pill in the line: the mentioned account's round
avatar and name on a tinted capsule, the way Notion, Slack and Discord draw mentions. Tapping the
pill opens the account.

It is a change in how messages are drawn only. Nothing is sent differently and nothing is stored:
every message with a mention, old or new, from any app, shows pills.

## The flow

1. Someone writes "Ask @durov about it" in a chat, a group or a channel post.
2. The message reads "Ask [avatar Pavel] about it": in place of `@durov`, a capsule in the
   message's link colour with the account's photo (or its initials) and its short name.
3. A name linked to a person (a text mention) becomes a pill the same way.
4. Tapping the pill opens the account; holding it shows the mention's menu, as for a mention.
   Selecting and copying the message give back the text as written, `@durov` included.
5. The first time a username is seen, it is looked up: the message shows the mention as written
   and gets the pill a moment later. After that the pill shows at once.

## What Telegram already has

A mention is blue text, and nothing else. The nearest thing to a card is the preview a
`t.me/username` link gets (name, description, photo, "Send Message"), but that is for a link, one
per message, and under the text. No Telegram app draws a mention with its avatar in the line.

## Requirements

The same as for the main project: macOS 26 and Xcode 26.6 (`versions.json`), plus your own
`api_id` and `api_hash`. The branch includes the Xcode 26 build fix `c29c7458`, which is not part
of the feature.

## Build from scratch

### 1. Clone

```sh
git clone --recursive -j8 -b feature/mention-cards https://github.com/moondiel/Telegram-iOS.git
cd Telegram-iOS
```

### 2. Build configuration

Edit `build-system/template_minimal_development_configuration.json`:

- `bundle_id`: `org.<identifier>.Telegram`, with an identifier from `openssl rand -hex 8`;
- `api_id` and `api_hash`: yours;
- `team_id`: in Keychain Access, open the `Apple Development: …` certificate; it is the
  Organizational Unit under Details.

### 3. Generate the Xcode project

```sh
python3 build-system/Make/Make.py \
    --cacheDir="$HOME/telegram-bazel-cache" \
    generateProject \
    --configurationPath=build-system/template_minimal_development_configuration.json \
    --xcodeManagedCodesigning
```

### 4. Run

Open `Telegram/Telegram.xcodeproj`, choose the `Telegram` scheme and a simulator or your iPhone,
then Run. Send yourself a message with a mention, for example in Saved Messages.

The build needs room: keep 30–40 GB free on the disk.

## How the pill is made

The pill is one run of the message's text. After the message's entities are applied
(`stringWithAppliedEntities`), `applyMentionPills` replaces each mention with a single character:

- a run delegate gives it the pill's width and a line height 1 pt taller above and below, the way
  custom emoji reserve their room, so the pill flows and wraps with the line;
- it carries an `InteractiveTextEmbeddedLayerItem`, a small generic hook added to
  `InteractiveTextNodeWithEntities` beside custom emoji: the node keeps one layer per item key in
  the run's place and removes it when the run goes. The layer draws the capsule (the link colour at
  15%), the avatar (`peerAvatarCompleteImage`: the photo, or the initials on the account's colour)
  and the name (`compactDisplayTitle`, medium weight, in the link colour). A name wider than the
  pill's 220 pt is shortened with an ellipsis;
- it carries the mention's own tap attribute (`PeerMention` or `PeerTextMention`), so the bubble's
  existing tap and long-press handling opens the account;
- it carries an `OriginalTextAttribute` with the mention as written, the mechanism custom emoji
  use, so selection and copy map back to the original text.

### Which account a mention is

- A text mention carries its account's id; the account comes from the message's own peers.
- `@username` is looked up with `resolvePeerByName`, which keeps answers for two days.
  `MentionPillResolver` keeps them for the session, shares one request per username, and is safe to
  read during layout, which runs off the main queue. A message whose usernames are not known yet is
  laid out with the mentions as written, starts the lookups, and asks to be laid out again when they
  answer (`requestMessageUpdate`).
- A username with no account stays a plain mention, and so does a mention under a spoiler (a pill
  would reveal it) or with a custom emoji in it.

## What is real and what is limited

**Works for real**

- Pills for `@username` and text mentions in text messages and media captions, in every chat.
- Real avatars and names; channels, groups and bots mentioned by username get pills too.
- Tap, long press, selection and copy behave as they did for the mention.

**Limited**

- Only the message bubble draws pills. The composer, the chat list preview, replies and
  notifications keep the text.
- The first time a username appears, its message is laid out again when the lookup answers.
- A pill does not break across lines; a long name is shortened instead.
- There are no automated tests.

## Where the code is

New files:

| File | Role |
|---|---|
| `submodules/TelegramUI/Components/Chat/ChatMessageMentionCards/Sources/ChatMessageMentionCards.swift` | The resolver, the pill's run and its layer |
| `submodules/TelegramUI/Components/Chat/ChatMessageMentionCards/BUILD` | The module |
| `docs/mention-cards/*` | This write-up and the decision log |

Changed files:

- `submodules/TelegramUI/Components/InteractiveTextComponent/Sources/InteractiveTextNodeWithEntities.swift`:
  `InteractiveTextEmbeddedLayerItem`, layers kept for embedded runs beside custom emoji.
- `submodules/TelegramUI/Components/Chat/ChatMessageTextBubbleContentNode/Sources/ChatMessageTextBubbleContentNode.swift`
  and its `BUILD`: applies the pills and resolves pending usernames.

The whole change is one patch against the base commit `16a3d3c5`, without the Xcode 26 build fix:
[`mention-cards.patch`](mention-cards.patch). Apply it with `git apply`.
