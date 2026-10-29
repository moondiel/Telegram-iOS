# Subscriber Globe — decision log

Each entry is one decision and the reason for it. A decision that was later replaced stays in the
list, marked "Replaced by D-0xx". Entries marked (moondiel) are design calls made by the author.

## Base (2026-10-29)

**D-001. A separate branch from the clean base.** `feature/subscriber-globe` starts from
`16a3d3c5`, like `feature/channel-drafts`, and shares no code with it. Either feature can be taken
alone. It carries the same Xcode 26 build fix, which is left out of the patch.

## Data (2026-10-29)

**D-002. "Where each follower is from" is not possible on the client.** Channel statistics
(`stats.broadcastStats`) have no country data, only `languages_graph`. Followers' phone numbers
are hidden from admins. `peerSettings.phone_country` exists only for a stranger who messages you,
as an anti-spam hint. Collecting it person by person to map a channel's audience would be
tracking people, not statistics.

**D-003. An aggregate by country, on demo data, with an API proposal. (moondiel)** The feature
shows followers per country, the shape a server statistic would have. Until the server sends it,
the numbers are a demo, marked with a DEMO badge and a note. [api.md](api.md) proposes
`countries_graph` in `stats.broadcastStats`. A language-to-region estimate from real data was
offered and not taken.

**D-004. The demo is stable and sums to the real follower count.** It is seeded with the channel's
id, so it does not change between visits, and splits the channel's actual follower count.

## Look (2026-10-29)

**D-005. A satellite globe. (moondiel)** A contour globe in theme colours was offered as the
lighter option; the satellite look of the DataFast reference was chosen.

**D-006. The globe is MapKit's satellite map, the one Telegram already shows.** Telegram's
location screens have a Satellite mode (`LocationMapNode`, `.satelliteFlyover`). Zoomed out, the
same map is a real 3D globe that turns and zooms. This avoids bundling a planet texture of
several MB and writing a renderer, and it reuses what the app already ships.

**D-007. Countries are MapKit markers in the accent colour, with clustering.** Each marker shows
its follower count and, when there is room, the flag and localized country name (as giveaways
name countries: `flagEmoji` and `localeWithStrings`). Overlapping markers merge into one showing
their sum. There are no per-follower avatars as in the DataFast reference: the data is an
aggregate.

**D-008. A new section under Languages, with the same pie chart. (moondiel)** The globe gives the
geography. The pie chart and legend under it give exact shares, drawn by Telegram's own
`StatsGraphItem` from a graph in the server's JSON format, so real data later needs no new chart
code.
