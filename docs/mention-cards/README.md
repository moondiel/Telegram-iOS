# Mention Cards

Mention Cards draws a mention in a message as a card: the mentioned account's avatar, name and
@username in a block of its own, styled as the message's quotes are. Tapping the card opens the
account.

It is a change in how messages are drawn only. Nothing is sent differently, nothing is stored, and
no server change is needed: every message with a mention, old or new, from any app, shows cards.

## The flow

1. Someone writes "Subscribe to @durov and to the channel." in a chat, a group or a channel post.
2. The message shows "Subscribe to", then a card, then "and to the channel.". The card has the
   quote's coloured bar and tint (the sender's name colours, as quotes use), a round avatar on the
   left, the name in semibold and "@durov" under it.
3. A name linked to a person (a text mention) becomes a card the same way. If the account has no
   username, the card has one line: the avatar and the name.
4. Tapping anywhere on the card opens the account; holding it shows the mention's menu, as for a
   mention. Selecting and copying the message give back the text as it was written.
5. The first time a username is seen, it is looked up: the message shows the mention as written
   and becomes a card a moment later. After that the answer is known, and the card shows at once.

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
    --disableProvisioningProfiles
```

For a device, use `--xcodeManagedCodesigning` instead of `--disableProvisioningProfiles`.

### 4. Run

Open the generated project, choose the `Telegram` scheme and a simulator or your iPhone, then Run.
Send yourself a message with a mention, for example in Saved Messages.

## How a mention becomes a card

The card is text, not a view laid over the message. After the message's entities are applied
(`stringWithAppliedEntities`), `applyMentionCards` replaces each mention's range with the card's
lines:

- the spaces around the mention are dropped and a line break goes in on each side that has none,
  so the card is a paragraph of its own;
- the card's lines are the avatar's room (a run whose width a run delegate sets, as custom emoji
  reserve theirs) followed by the name, then the same room followed by "@username";
- the whole card is a block quote of a new kind, `.mention`: the quote's bar and tint, without the
  quote icon;
- the whole card carries the mention's own tap attribute (`PeerMention` or `PeerTextMention`), so
  the bubble's existing tap and long-press handling opens the account;
- the whole replacement carries an `OriginalTextAttribute` with the mention as written, the
  mechanism custom emoji use, so selection and copy map back to the original text.

The avatar is drawn by the text node: the avatar's run carries an `InteractiveTextEmbeddedLayerItem`,
a small generic hook added to `InteractiveTextNodeWithEntities` beside custom emoji. The node keeps
one layer per item key, places it where the run is (here centred on the card's lines), and removes
it when the run goes. The layer draws `peerAvatarCompleteImage`: the photo, or the initials on the
account's colour.

So the card wraps, truncates, highlights on touch and lays out with the rest of the message, and
the bubble needs no layout of its own.

### Which account a mention is

- A text mention carries its account's id; the account comes from the message's own peers.
- `@username` is looked up with `resolvePeerByName`, which keeps answers for two days, so a username
  costs at most one request in that time. `MentionCardResolver` keeps the answers for the session,
  shares one request per username, and is safe to read during layout, which runs off the main
  queue. A message whose usernames are not known yet is laid out with the mentions as written,
  starts the lookups, and asks to be laid out again when they answer
  (`requestMessageUpdate`).
- A username with no account stays a plain mention. So does any mention inside a quote or a code
  block (a block cannot hold another), under a spoiler, or with a custom emoji in it.

## What is real and what is limited

**Works for real**

- Cards for `@username` and text mentions in text messages and media captions, in every chat.
- Avatars, names and usernames of real accounts; channels and bots mentioned by username get their
  card too.
- Tap, long press, selection and copy behave as they did for the mention.

**Limited**

- The first time a username appears, its message changes height once, when the mention turns into
  a card.
- A message that is mostly mentions, such as a list of @usernames, becomes a stack of cards.
- Mentions inside quotes, code, spoilers and custom emoji stay inline (see above).
- Only the message bubble draws cards; chat list previews, replies and notifications keep the text.
- There are no automated tests.

**Not verified**

- The branch has not been built or run yet.

## Where the code is

New files:

| File | Role |
|---|---|
| `submodules/TelegramUI/Components/Chat/ChatMessageMentionCards/Sources/ChatMessageMentionCards.swift` | The resolver, the card's text and its avatar layer |
| `submodules/TelegramUI/Components/Chat/ChatMessageMentionCards/BUILD` | The module |
| `docs/mention-cards/*` | This write-up and the decision log |

Changed files:

- `submodules/Display/Source/TextNode.swift`: the `.mention` block kind (no icon, no icon inset).
- `submodules/TelegramUI/Components/InteractiveTextComponent/Sources/InteractiveTextComponent.swift`:
  the same for the interactive text node.
- `submodules/TelegramUI/Components/InteractiveTextComponent/Sources/InteractiveTextNodeWithEntities.swift`:
  `InteractiveTextEmbeddedLayerItem`, layers kept for embedded runs beside custom emoji.
- `submodules/TelegramUI/Components/Chat/ChatMessageTextBubbleContentNode/Sources/ChatMessageTextBubbleContentNode.swift`
  and its `BUILD`: applies the cards and resolves pending usernames.

The whole change is one patch against the base commit `16a3d3c5`, without the Xcode 26 build fix:
[`mention-cards.patch`](mention-cards.patch). Apply it with `git apply`.
