# Mention Cards for Telegram iOS

Mentions drawn as pills: the person's avatar and name, right in the line.

This is a copy of [Telegram-iOS](https://github.com/TelegramMessenger/Telegram-iOS) with the **Mention Cards** feature on the `feature/mention-cards` branch. For compiling Telegram in general, see Telegram's [original guide](https://github.com/TelegramMessenger/Telegram-iOS/blob/master/README.md).

## What it does

1. A mention in a message or a channel post, `@username` or a name linked to a person, is drawn in the line as a pill: a small round avatar and the name on a tinted capsule, the way Notion, Slack and Discord draw mentions.
2. Tapping the pill opens the account, as tapping the mention did; holding it gives the mention's menu. Copying the message gives back the text as written.
3. It works in every chat, group and channel and needs nothing from the sender: any message with a mention shows pills, including old ones and ones from other apps.
4. It is built from Telegram's own pieces: the message's link colour and font, its avatars, its username lookup, and the way custom emoji sit in a line.

## Links

- [All changes of the feature](https://github.com/moondiel/Telegram-iOS/compare/16a3d3c5...feature/mention-cards)
- [Write-up](docs/mention-cards/README.md): building from scratch, how the pill is made, what is limited, where the code is
- [Decision log](docs/mention-cards/decisions.md)
- [The whole change as one patch](docs/mention-cards/mention-cards.patch)

## Status

A client-side prototype, built and checked by hand on a device (2026-10-30); there are no automated tests. It changes only how messages are drawn: messages are sent and stored as before, so other apps keep showing plain mentions. Limits are listed in the write-up.
