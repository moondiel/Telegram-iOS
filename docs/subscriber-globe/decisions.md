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

**D-003. An aggregate by country, on demo data, with an API proposal. (moondiel)** The demo part is replaced by D-017. The feature
shows followers per country, the shape a server statistic would have. Until the server sends it,
the numbers are a demo, marked with a DEMO badge and a note (the note was dropped in D-015). [api.md](api.md) proposes
`countries_graph` in `stats.broadcastStats`. A language-to-region estimate from real data was
offered and not taken.

**D-004. The demo is stable and sums to the real follower count.** Replaced by D-017. It is seeded with the channel's
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
Labels show the flag and the follower count, and in the sheet the country's name. They fade out
as their country turns towards the edge, and when two would overlap the larger audience keeps its
label. This replaces MapKit's clustering.

**D-013. One card, switched between the chart and the globe. (moondiel)** The header action is replaced by D-018's tabs. The globe no longer
sits above the chart. The section header's action, **Show Globe** / **Show Chart**, switches the
card, as other Telegram headers carry an action (folder names' Enable Animations). The chart is
shown first; the choice lasts while the screen is open.

**D-014. A tap dives into the globe. (moondiel)** Replaced by D-016. The fullscreen globe starts exactly over the
card's globe, at its size and turn, and grows to fill the screen with a slight overshoot; the
card's globe hides meanwhile. Close shrinks it back onto the card, which carries on from the
fullscreen globe's turn. Fullscreen, the globe turns any way and zooms (pinch, double tap). In the
card it only takes sideways drags, so the list still scrolls over it, and it leaves the left edge
to the back swipe.

**D-015. No demo note under the card. (moondiel)** Superseded by D-017, which has no demo. The explanation under the section, on the card
and fullscreen, is gone; the DEMO badge in the header still marks the numbers. Why they are a demo
is in this write-up and in [api.md](api.md).

**D-016. A tap opens the globe in a sheet. (moondiel)** Instead of the fullscreen dive, the card
opens Telegram's glass sheet (`SheetComponent`, `.glass`, with a `GlassBarButtonComponent` close
button), built as statistics' `TransactionInfoScreen` is. The sheet has room for what the card
does not: a large globe that turns any way and zooms, and the list of countries with flag, name,
share and followers, where tapping a country turns the globe to it by the shorter way round. The
globe opens at the card's turn. A drag that starts on the globe turns it (the globe declines the
sheet's drag the way `UISlider` declines a scroll view's); anywhere else it pulls the sheet down.

## Real data (2026-10-29)

**D-017. Countries are estimated from the real languages graph, not made up. (moondiel)** The
API has no country of a follower anywhere a client can reach: not in statistics, not in profiles,
and `peerSettings.phone_country` only describes strangers who write to you. What is real is the
languages graph. The estimate takes its latest day, shares the channel's follower count out by
language, and shares each language out over the countries where Telegram users speak it, from a
table of rough shares. The result has no made-up numbers, but it is an estimate: a Russian
speaker in Dubai counts towards Russia. The DEMO badge goes; a note under the card ("Estimated
from the languages your followers use Telegram in.") and a subtitle under the sheet's title
("Estimated from languages") say where the numbers come from. A poll in the channel and invite
links per country were considered as other real sources and not taken.

## Telegram's tabs and colours (2026-10-29)

**D-018. The card switches with Telegram's statistics tabs. (moondiel)** Telegram switches what a
statistics card shows with a row of tabs at its top: Boosts / Gifts, TON / Stars
(`BoostsTabsItem`). The countries card uses that same item with **Chart** / **Globe**, in place of
the header's Show Globe action, so the switch lives inside the card. The globe card is as tall as
the pie chart (361 pt), so switching does not move the list.

**D-019. Countries are told apart by colour, not flags. (moondiel)** As the Languages chart colours
its languages, each country gets one colour by rank, used by the pie chart, its marker and ring on
the globe, the dot on its label and the dot in the sheet's list. Flags are gone everywhere; labels
read "Russia 49%".

**D-020. The globe stays cheap while it turns.** Found after the sheet stuttered: the radial
gradients were reassigned on every frame (each assignment redraws them), and the labels' shadows
had no path (an off-screen pass per label per frame). The gradients now change only when the
globe moves or grows, and the labels carry a shadow path. SceneKit prepares each globe's scene off
the main thread before it is shown, and the card's globe stops while the sheet covers it.
