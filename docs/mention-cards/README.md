# Mention Cards

A text message that mentions an account shows that account's card under the text: the same
preview Telegram draws for a `t.me/username` link, with the avatar, the name, the description and a
button. Tapping the card opens the account.

It is a change in how messages are drawn only. Nothing is sent differently and nothing is stored:
every text message with a mention, old or new, from any app, shows the card.

## The flow

1. Someone writes "Subscribe to @durov" in a chat, a group or a channel post.
2. The message shows its text as before, the mention included, and under it the card Telegram
   shows for `t.me/durov`: the bar in the sender's colour, the name, the description, the avatar on
   the right, and "Send Message" (a channel's card says "View Channel", a group's "View Group").
3. A name linked to an account (a text mention) gets the card of that account's username.
4. Tapping the card or its button opens the account.
5. The first time a username is seen, its preview is asked for: the message shows without the card
   and gets it a moment later. After that the card shows at once.

## What Telegram already has

Telegram shows this card only for a link: paste `t.me/username` and the composer asks the server
for the link's preview, then sends it with the message. A message gets one preview, the sender can
remove it, and a mention (`@username`) never gets one. Mention Cards gives mentions that same card,
on the reading side.

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

## How the card is made

- **Which mention.** `mentionCardUsernames` takes the message's mention entities in order:
  `@username`, and text mentions of accounts that have a username. Mentions under a spoiler are
  left out, so the card cannot reveal them. At most the first five are considered.
- **The preview.** `MentionPreviewStore` asks the server for the preview of
  `https://t.me/<username>` with `webpagePreview`, the call the composer makes for a pasted link,
  once per username, and keeps the answer for the session. It is safe to read during layout, which
  runs off the main queue. The text bubble starts the request when it lays the message out and asks
  for the message to be laid out again when the answer comes (`requestMessageUpdate`).
- **The card.** `mentionCard` picks the preview of the first mention that has one. While an earlier
  mention is still being asked about there is no card yet, so the card never jumps from a later
  mention to an earlier one. `ChatMessageBubbleItemNode` then adds Telegram's
  `ChatMessageWebpageBubbleContentNode` for a copy of the message that carries the preview, exactly
  where a real link preview goes. The copy is only for drawing; the stored message is untouched.
- **Opening.** The copy marks the preview as safe (`WebpagePreviewMessageAttribute.isSafe`), so the
  `t.me` link opens the account directly, without the "Open this link?" question.

Everything the card shows and does (layout, colours, avatar, button title, tap, long press) is the
link preview's own code.

## What is real and what is limited

**Works for real**

- Cards for users, bots, channels and groups mentioned by `@username`, and for text mentions of
  accounts with a username, in text messages in every chat.
- The cards are the server's previews, so names, descriptions and photos are real and current.

**Limited**

- One card per message, for the first mention that has a preview.
- Only text messages: a media caption, a message with its own link preview, a sponsored message and
  a secret chat get no card.
- A text mention of an account without a username gets no card: the preview needs a `t.me` link.
- The first time a username appears, its message gets taller once, when the card arrives.
- Each new username costs one preview request, once per session.
- There are no automated tests.

## Where the code is

New files:

| File | Role |
|---|---|
| `submodules/TelegramUI/Components/Chat/ChatMessageMentionCards/Sources/ChatMessageMentionCards.swift` | The preview store, which mentions count, which card a message gets |
| `submodules/TelegramUI/Components/Chat/ChatMessageMentionCards/BUILD` | The module |
| `docs/mention-cards/*` | This write-up and the decision log |

Changed files:

- `submodules/TelegramUI/Components/Chat/ChatMessageBubbleItemNode/Sources/ChatMessageBubbleItemNode.swift`
  and its `BUILD`: adds the link-preview node for a message with a card.
- `submodules/TelegramUI/Components/Chat/ChatMessageTextBubbleContentNode/Sources/ChatMessageTextBubbleContentNode.swift`
  and its `BUILD`: asks for the previews and lays the message out again when they come.

The whole change is one patch against the base commit `16a3d3c5`, without the Xcode 26 build fix:
[`mention-cards.patch`](mention-cards.patch). Apply it with `git apply`.
