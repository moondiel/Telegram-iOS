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
the numbers are a demo, marked with a DEMO badge and a note (the note was dropped in D-015). [api.md](api.md) proposes
`countries_graph` in `stats.broadcastStats`. A language-to-region estimate from real data was
offered and not taken.

**D-004. The demo is stable and sums to the real follower count.** It is seeded with the channel's
id, so it does not change between visits, and splits the channel's actual follower count.

## Look (2026-10-29)

**D-005. A satellite globe. (moondiel)** Replaced by D-009. A contour globe in theme colours was offered as the
lighter option; the satellite look of the DataFast reference was chosen.

**D-006. The globe is MapKit's satellite map, the one Telegram already shows.** Replaced by D-010. Telegram's
location screens have a Satellite mode (`LocationMapNode`, `.satelliteFlyover`). Zoomed out, the
same map is a real 3D globe that turns and zooms. This avoids bundling a planet texture of
several MB and writing a renderer, and it reuses what the app already ships.

**D-007. Countries are MapKit markers in the accent colour, with clustering.** Replaced by D-012. Each marker shows
its follower count and, when there is room, the flag and localized country name (as giveaways
name countries: `flagEmoji` and `localeWithStrings`). Overlapping markers merge into one showing
their sum. There are no per-follower avatars as in the DataFast reference: the data is an
aggregate.

**D-008. A new section under Languages, with the same pie chart. (moondiel)** Replaced by D-013. The globe gives the
geography. The pie chart and legend under it give exact shares, drawn by Telegram's own
`StatsGraphItem` from a graph in the server's JSON format, so real data later needs no new chart
code.

## Telegram's own globe (2026-10-29)

**D-009. A globe of Telegram's own design, not Apple's map. (moondiel)** The satellite map looked
like Apple Maps inside Telegram. The globe is now drawn in the theme's colours: a sea a shade of
the accent away from the card, land as dots, countries in the accent colour, with a soft halo
around the globe and its edge fading into the card. Light and dark themes each get their own
mix.

**D-010. Drawn with SceneKit, as the Premium star is.** `PremiumStarComponent` already ships a
SceneKit view in Telegram, so this adds no framework and no dependency. The land is one geometry
of small discs lying on the sphere (about 3,000 dots, one draw call), built once and shared. The
camera is orthographic, so the globe's size on screen is exactly the radius the layout asks for,
and labels can be placed with plain arithmetic.

**D-011. The land is hand-drawn and embedded as bits.** No map data could be downloaded (the
network here and on the author's machine blocks GitHub, npm and PyPI), and a texture would weigh
megabytes. Simplified outlines were drawn at the scale of the grid, checked against rendered
previews, and turned into a grid of dots 2° apart: one bit per dot, 1.7 KB of base64 in
`StatsGlobeLand.swift`. Each row holds as many dots as fit at its latitude, so the dots stay evenly
spaced up to the poles.

**D-012. Countries are accent dots with a pinging ring and a label.** A dot's area follows the
country's share. Its ring grows and fades in turn with the others, so the globe reads as live.
Labels show the flag and the follower count, and in fullscreen the country's name. They fade out
as their country turns towards the edge, and when two would overlap the larger audience keeps its
label. This replaces MapKit's clustering.

**D-013. One card, switched between the chart and the globe. (moondiel)** The globe no longer
sits above the chart. The section header's action, **Show Globe** / **Show Chart**, switches the
card, as other Telegram headers carry an action (folder names' Enable Animations). The chart is
shown first; the choice lasts while the screen is open.

**D-014. A tap dives into the globe. (moondiel)** The fullscreen globe starts exactly over the
card's globe, at its size and turn, and grows to fill the screen with a slight overshoot; the
card's globe hides meanwhile. Close shrinks it back onto the card, which carries on from the
fullscreen globe's turn. Fullscreen, the globe turns any way and zooms (pinch, double tap). In the
card it only takes sideways drags, so the list still scrolls over it, and it leaves the left edge
to the back swipe.

**D-015. No demo note under the card. (moondiel)** The explanation under the section, on the card
and fullscreen, is gone; the DEMO badge in the header still marks the numbers. Why they are a demo
is in this write-up and in [api.md](api.md).
