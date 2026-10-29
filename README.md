# Followers by Country for Telegram iOS

See where a channel's followers are, on a globe in its statistics.

This is a copy of [Telegram-iOS](https://github.com/TelegramMessenger/Telegram-iOS) with the **Subscriber Globe** feature on the `feature/subscriber-globe` branch. For compiling Telegram in general, see Telegram's [original guide](https://github.com/TelegramMessenger/Telegram-iOS/blob/master/README.md).

## What it does

1. Channel Statistics gets a **Followers by Country** card under Languages, with Telegram's statistics tabs at its top: **Chart** and **Globe**, the tabs that switch Boosts / Gifts.
2. **Chart** is the same pie chart as Languages and behaves as it does: the same days and range slider, legend toggles and details on a tap. Each country takes the colour its main language has in the Languages chart.
3. **Globe** slides in like a profile's tabs and arrives spinning: a dotted Earth in the theme's colours, each country a dot in its colour with a ring that pings outward and a label with its name and share. Drag it to turn it, flick it to let it coast, pinch to look closer; it springs back and turns slowly on its own.
4. Everything is built from Telegram's own components: the statistics tabs and pie chart, SceneKit as the Premium star uses it, and the edge effect of the glass bars.

## Links

- [All changes of the feature](https://github.com/moondiel/Telegram-iOS/compare/16a3d3c5...feature/subscriber-globe)
- [Write-up](docs/subscriber-globe/README.md): building from scratch, what is real and what is estimated, where the code is
- [API proposal](docs/subscriber-globe/api.md) and [decision log](docs/subscriber-globe/decisions.md)
- [The whole change as one patch](docs/subscriber-globe/subscriber-globe.patch)

## Status

A client-side prototype, checked by hand on a device; there are no automated tests. Telegram's API has no followers-by-country statistic, so the countries are estimated from the channel's real languages graph, and the screen says so; production would need the server change in the [API proposal](docs/subscriber-globe/api.md). Limits are listed in the write-up.
