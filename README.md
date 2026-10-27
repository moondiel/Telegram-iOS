This is a copy of [Telegram-iOS](https://github.com/TelegramMessenger/Telegram-iOS) with the **Channel Drafts** feature on the `feature/channel-drafts` branch. For compiling Telegram in general, see Telegram's [original guide](https://github.com/TelegramMessenger/Telegram-iOS/blob/master/README.md).

# Channel Drafts for Telegram iOS

Keep several unpublished posts per channel, the way Scheduled Messages keeps posts for later.

## What it does

1. **Save Draft** in the send menu of anything a channel can send saves it as a draft: text, rich text, photos and albums, files, voice messages, round videos, stickers, GIFs, polls, locations and contacts.
2. A **Drafts** button in the input field opens the Drafts screen. It looks and behaves like Scheduled Messages: drafts are drawn as the channel's posts, and their menu is Use Draft · Copy · Edit · Delete · Select. Clear All asks for confirmation and offers Undo.
3. **Use Draft** puts a draft back into the composer under a **Draft** header, the way Edit puts a post there. Send or Schedule publishes it and removes the draft, Save Draft updates it, and × leaves it as it was.
4. Everything is built from Telegram's own components, icons and strings. Drafts are stored on the device, as Telegram's API has no multiple drafts per chat.

## Links

- [All changes of the feature](https://github.com/moondiel/Telegram-iOS/compare/16a3d3c5...feature/channel-drafts)
- [Write-up](docs/channel-drafts/README.md): building from scratch, how drafts are stored, what is limited, where the code is
- [Decision log](docs/channel-drafts/decisions.md) and [full behaviour spec](docs/channel-drafts/spec.md)
- [The whole change as one patch](docs/channel-drafts/channel-drafts.patch)

## Status

A client-side prototype, checked by hand in a test channel; there are no automated tests. Drafts are kept on the device and are not synced between devices or between a channel's admins; production would need a server API for several drafts per chat. Limits are listed in the write-up.

