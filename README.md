# Mention Cards for Telegram iOS

A message that mentions someone shows their card, the way a `t.me` link does.

This is a copy of [Telegram-iOS](https://github.com/TelegramMessenger/Telegram-iOS) with the **Mention Cards** feature on the `feature/mention-cards` branch. For compiling Telegram in general, see Telegram's [original guide](https://github.com/TelegramMessenger/Telegram-iOS/blob/master/README.md).

## What it does

1. A message or channel post that mentions an account, by `@username` or by a name linked to it, shows that account's card under the text: the avatar, the name, the description and a button ("View Channel", "Send Message", "View Group").
2. The card is Telegram's own link preview, the one a `t.me/username` link gets, so it looks and behaves exactly like it. Tapping it opens the account.
3. It works in every chat, group and channel, and needs nothing from the sender: any text message with a mention shows the card, including old ones.
4. One card per message, for the first mention, as Telegram shows one preview per message.

## Links

- [All changes of the feature](https://github.com/moondiel/Telegram-iOS/compare/16a3d3c5...feature/mention-cards)
- [Write-up](docs/mention-cards/README.md): building from scratch, how the card is made, what is limited, where the code is
- [Decision log](docs/mention-cards/decisions.md)
- [The whole change as one patch](docs/mention-cards/mention-cards.patch)

## Status

A client-side prototype; there are no automated tests, and it has not been built or run yet. It changes only how messages are drawn: messages are sent and stored as before, so other apps keep showing plain mentions. Limits are listed in the write-up.
