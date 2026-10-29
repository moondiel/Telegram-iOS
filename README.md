This is a copy of [Telegram-iOS](https://github.com/TelegramMessenger/Telegram-iOS) with the **Subscriber Globe** feature on the `feature/subscriber-globe` branch. For compiling Telegram in general, see Telegram's [original guide](https://github.com/TelegramMessenger/Telegram-iOS/blob/master/README.md).

# Subscriber Globe for Telegram iOS

See where a channel's followers are, on a globe in its statistics.

## What it does

1. Channel Statistics gets a **Followers by country** section under Languages.
2. A satellite globe, which turns and zooms, shows a marker per country with its number of followers. Nearby markers merge into one with their sum.
3. Below the globe, a pie chart lists every country and its share, as the Languages chart does.
4. It is built from Telegram's own pieces: Apple's satellite map from Telegram's location screens, the statistics section and chart, and country names and flags as giveaways show them.

## Links

- [All changes of the feature](https://github.com/moondiel/Telegram-iOS/compare/16a3d3c5...feature/subscriber-globe)
- [Write-up](docs/subscriber-globe/README.md): building from scratch, what is real and what is a demo, where the code is
- [API proposal](docs/subscriber-globe/api.md) and [decision log](docs/subscriber-globe/decisions.md)
- [The whole change as one patch](docs/subscriber-globe/subscriber-globe.patch)

## Status

A client-side prototype on **demo data**, marked as such on screen. Telegram's API has no followers-by-country statistic, so the numbers are a stable sample that adds up to the channel's real follower count. The [API proposal](docs/subscriber-globe/api.md) describes the server change that would make them real. Not built or tested yet.
