# Mention Cards for Telegram iOS

See who a message mentions, with their avatar, right in the message.

This is a copy of [Telegram-iOS](https://github.com/TelegramMessenger/Telegram-iOS) with the **Mention Cards** feature on the `feature/mention-cards` branch. For compiling Telegram in general, see Telegram's [original guide](https://github.com/TelegramMessenger/Telegram-iOS/blob/master/README.md).

## What it does

1. A mention in a message or a channel post, `@username` or a name linked to a person, becomes a card of its own, the way a quote does: the account's avatar, its name and its @username, on the quote's coloured bar.
2. Tapping the card opens the account, as tapping the mention did; holding it gives the mention's menu.
3. It works in every chat, group and channel, and needs nothing from the sender: any message with a mention shows the card.
4. Everything is built from Telegram's own pieces: the message's quote block and colours, its avatars, and its username lookup.

## Links

- [All changes of the feature](https://github.com/moondiel/Telegram-iOS/compare/16a3d3c5...feature/mention-cards)
- [Write-up](docs/mention-cards/README.md): building from scratch, how a mention becomes a card, what is limited, where the code is
- [Decision log](docs/mention-cards/decisions.md)
- [The whole change as one patch](docs/mention-cards/mention-cards.patch)

## Status

A client-side prototype; there are no automated tests, and it has not been built or run yet. It changes only how messages are drawn: messages are sent and stored as before, so other apps keep showing plain mentions. Limits are listed in the write-up.
