# Subscriber Globe

Subscriber Globe adds a **Followers by country** card to a channel's statistics. The card shows a
pie chart of the countries or, switched from the section header, a dotted globe in the theme's
colours with a marker per country carrying its number of followers. A tap opens the globe in a
sheet.

Telegram's statistics do not report countries yet: `stats.broadcastStats` breaks followers down
by language only. The section therefore shows a demo distribution, labelled **DEMO** in the
section header, until the server sends a country breakdown. The change that would take on the server is
in [api.md](api.md). The client is built so that real data only replaces one function.

## The flow

1. Open a channel you admin, then Statistics. Below **Languages** there is a new section,
   **FOLLOWERS BY COUNTRY**, with a **DEMO** badge and **Show Globe** on the right.
2. The card first shows a pie chart with a legend of every country and its share, the same chart
   and legend as **Languages**.
3. **Show Globe** switches the card to the globe; the header then reads **Show Chart**.
4. The globe opens over the country with the most followers and turns slowly on its own. Land is
   dots, each country is an accent dot whose ring pings outward, sized by its share, with a label
   carrying its flag and number of followers. When two labels would overlap, the larger audience
   keeps its label. A sideways drag turns the globe and lets it coast; up-and-down drags scroll
   the list.
5. A tap on the globe opens Telegram's glass sheet with a glass close button, as statistics'
   transaction info does. It holds a large globe at the card's turn, whose labels also name the
   country, which turns any way and zooms with a pinch or a double tap. Under it is the list of
   countries with flag, name, share and followers; tapping one turns the globe to it. A drag that
   starts on the globe turns the globe; anywhere else it pulls the sheet down.

## Requirements

The same as for the main project: macOS 26 and Xcode 26.6 (`versions.json`), plus your own
`api_id` and `api_hash`. The branch includes the Xcode 26 build fix `24193067`, which is not part
of the feature.

The globe is drawn on the device and needs no network.

## Build from scratch

### 1. Clone

```sh
git clone --recursive -j8 -b feature/subscriber-globe https://github.com/moondiel/Telegram-iOS.git
cd Telegram-iOS
```

### 2. Build configuration

Edit `build-system/template_minimal_development_configuration.json`:

- `bundle_id`: `org.<identifier>.Telegram`, with an identifier from `openssl rand -hex 8`;
- `api_id` and `api_hash`: yours;
- `team_id`: in Keychain Access, open the `Apple Development: …` certificate; it is the
  Organizational Unit under Details.

### 3. Generate the Xcode project

```sh
python3 build-system/Make/Make.py \
    --cacheDir="$HOME/telegram-bazel-cache" \
    generateProject \
    --configurationPath=build-system/template_minimal_development_configuration.json \
    --disableProvisioningProfiles
```

For a device, use `--xcodeManagedCodesigning` instead of `--disableProvisioningProfiles`.

### 4. Run

Open the generated project, choose the `Telegram` scheme and a simulator or your iPhone, then Run.
Statistics are only available for channels with enough followers; the server decides which.

## What is real and what is limited

**Works for real**

- The section, its card styling and its place in Statistics, built from Telegram's own items:
  the section header with a badge and an action, the glass card, the pie chart.
- The globe: a sphere with the land as about 3,000 dots, drawn with SceneKit in the theme's
  colours, light or dark. It turns under the finger, coasts, and turns slowly when left alone.
- Markers sized by share, labels with flags, follower counts and (in the sheet) country names in the
  app's language, and labels that give way to larger audiences.
- The globe sheet with the country list, and turning to a tapped country.

**Limited**

- **The numbers are a demo.** They are generated from the channel's id (the same each visit) and
  add up to its real follower count, but the split by country is made up. Telegram's API has no
  country breakdown. Getting one is a server change; see [api.md](api.md).
- The coastlines are drawn by hand at the 2° scale of the dots (no map data could be bundled or
  downloaded). They are a picture of the world, not a map: small islands are missing.
- Marker positions come from a table of 26 countries; a country outside it would need a row.
- There are no automated tests.

**Not verified**

- The globe has not been run on a device yet: its frame rate on older iPhones, and how the card's
  sideways drag shares the screen with the back swipe.
- How the pie chart's zoom slider behaves with the demo's flat daily columns (seven equal days).

## How the countries travel (prototype vs. production)

The section is drawn from a `ChannelStatsCountries` value: a list of `{ country code, followers,
marker coordinate }`. In the prototype, `ChannelStatsCountries.demo(peerId:followers:)` makes one.

In production, the server would add an aggregated `countries_graph` to `stats.broadcastStats`
next to `languages_graph`, in the same JSON format, as described in [api.md](api.md). Then:

- `ChannelStats` would carry the new graph, as it carries `languagesGraph`;
- the countries would be read from that graph instead of `demo(...)`, which goes away together
  with the badge.

The country shares are an aggregate, never a list of followers. A per-follower map is not
possible on the client, and should not be:

- channel statistics never name followers' countries;
- followers' phone numbers are hidden from admins;
- the only country field in the API, `peerSettings.phone_country`, describes a stranger who
  writes to you, as an anti-spam hint.

## Where the code is

New files:

| File | Role |
|---|---|
| `submodules/StatisticsUI/Sources/ChannelStatsCountries.swift` | The model, marker coordinates, the demo distribution, and the pie chart's graph |
| `submodules/StatisticsUI/Sources/StatsGlobeLand.swift` | The land: a grid of dots 2° apart, one bit each (1.7 KB), and its decoder |
| `submodules/StatisticsUI/Sources/StatsGlobeView.swift` | The globe: SceneKit sphere, land dots, markers and their rings, labels, turning, coasting and zooming |
| `submodules/StatisticsUI/Sources/StatsGlobeItem.swift` | The globe card: a list item hosting the globe in the statistics list |
| `submodules/StatisticsUI/Sources/StatsGlobeSheetScreen.swift` | The globe sheet: Telegram's glass sheet with a large globe and the country list |
| `docs/subscriber-globe/*` | This write-up, the decision log and the API proposal |

Changed files:

- `submodules/StatisticsUI/Sources/ChannelStatsController.swift`: the section
  (`StatsSection.countries`), its entries (header with the DEMO badge and the Show Globe / Show
  Chart action, globe, pie chart), whether the card shows the globe, opening the globe
  sheet, and the entries after the section moved down four stable ids.
- `Telegram/Telegram-iOS/en.lproj/Localizable.strings`: `ChannelStats.Countries.Title`,
  `ChannelStats.Countries.Demo`, `ChannelStats.Countries.ShowGlobe`, `ChannelStats.Countries.ShowChart`,
  `ChannelStats.Countries.ScreenTitle`.

The whole change is one patch against the base commit `16a3d3c5`, without the Xcode 26 build fix:
[`subscriber-globe.patch`](subscriber-globe.patch). Apply it with `git apply`.

## Further reading

- [api.md](api.md): the server change that would make the data real.
- [decisions.md](decisions.md): why the feature works the way it does.
