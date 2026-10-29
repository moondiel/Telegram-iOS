This is a copy of [Telegram-iOS](https://github.com/TelegramMessenger/Telegram-iOS) with the **Subscriber Globe** feature on the `feature/subscriber-globe` branch. For compiling Telegram in general, see Telegram's [original guide](https://github.com/TelegramMessenger/Telegram-iOS/blob/master/README.md).

# Subscriber Globe for Telegram iOS

See where a channel's followers are, on a globe in its statistics.

## What it does

1. Channel Statistics gets a **Followers by country** card under Languages. At the top of the card, Telegram's statistics tabs (**Chart** / **Globe**, as Boosts / Gifts switch theirs) switch the same card between a pie chart and a globe.
2. The globe is drawn in the theme's colours: land as dots, each country as a dot in its colour from the chart with a ring that pings outward, and a label with its name and share. It turns slowly on its own and under a sideways drag.
3. Switching slides the chart and the globe like a profile's tabs, and the globe arrives spinning. A tap on the globe opens it large in a sheet, at the same turn, where it turns and zooms freely.
4. It is built from Telegram's own pieces: the statistics section, tabs and pie chart, the glass sheet, SceneKit as the Premium star uses it, and country names as giveaways show them.

## Links

- [All changes of the feature](https://github.com/moondiel/Telegram-iOS/compare/16a3d3c5...feature/subscriber-globe)
- [Write-up](docs/subscriber-globe/README.md): building from scratch, what is real and what is estimated, where the code is
- [API proposal](docs/subscriber-globe/api.md) and [decision log](docs/subscriber-globe/decisions.md)
- [The whole change as one patch](docs/subscriber-globe/subscriber-globe.patch)

## Status

A client-side prototype on **real data, estimated**. Telegram's API has no followers-by-country statistic, so the countries are estimated from the channel's real languages graph: each language's followers are shared out over the countries where it is spoken, and the screen says so. The [API proposal](docs/subscriber-globe/api.md) describes the server change that would make them exact. Not built or tested yet.
