# Subscriber Globe

Subscriber Globe adds a **Followers by country** section to a channel's statistics. It is a satellite
globe with a marker per country carrying its number of followers, and a pie chart of the countries
below it.

Telegram's statistics do not report countries yet: `stats.broadcastStats` breaks followers down
by language only. The section therefore shows a demo distribution, labelled **DEMO** with a note
below it, until the server sends a country breakdown. The change that would take on the server is
in [api.md](api.md). The client is built so that real data only replaces one function.

## The flow

1. Open a channel you admin, then Statistics. Below **Languages** there is a new section,
   **FOLLOWERS BY COUNTRY**, with a **DEMO** badge.
2. The globe opens over the country with the most followers. Drag to turn it; pinch to zoom in on
   a region (down to about 1,500 km).
3. Each country is a marker in the theme's accent colour with its number of followers. Its flag
   and name show under it when there is room. Markers that would overlap merge into one with
   their sum, and split again as you zoom in.
4. Below the globe, a pie chart with a legend lists every country and its share. It is the same
   chart and legend as **Languages**.
5. A note under the section says the data is a demo and why.

## Requirements

The same as for the main project: macOS 26 and Xcode 26.6 (`versions.json`), plus your own
`api_id` and `api_hash`. The branch includes the Xcode 26 build fix `24193067`, which is not part
of the feature.

The globe is Apple's satellite map, so it needs a network connection to load its imagery.

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
  the section header with a badge, the glass card, the pie chart, the footer note.
- The globe: Apple's satellite map, which Telegram's location screens already show in Satellite
  mode. It turns under the finger and zooms in, and follows the light or dark theme.
- Markers with follower counts, country names in the app's language, and clustering.

**Limited**

- **The numbers are a demo.** They are generated from the channel's id (the same each visit) and
  add up to its real follower count, but the split by country is made up. Telegram's API has no
  country breakdown. Getting one is a server change; see [api.md](api.md).
- The globe sits inside the scrolling list. Dragging on it turns the globe; scrolling the list
  works from anywhere else.
- There are no automated tests.

**Not verified**

- Behaviour on a slow network while the satellite imagery loads.
- How the pie chart's zoom slider behaves with the demo's flat daily columns (seven equal days).

## How the countries travel (prototype vs. production)

The section is drawn from a `ChannelStatsCountries` value: a list of `{ country code, followers,
marker coordinate }`. In the prototype, `ChannelStatsCountries.demo(peerId:followers:)` makes one.

In production, the server would add an aggregated `countries_graph` to `stats.broadcastStats`
next to `languages_graph`, in the same JSON format, as described in [api.md](api.md). Then:

- `ChannelStats` would carry the new graph, as it carries `languagesGraph`;
- the countries would be read from that graph instead of `demo(...)`, which goes away together
  with the badge and the note.

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
| `submodules/StatisticsUI/Sources/StatsGlobeItem.swift` | The globe card: a list item hosting MapKit's satellite globe with country markers and clusters |
| `docs/subscriber-globe/*` | This write-up, the decision log and the API proposal |

Changed files:

- `submodules/StatisticsUI/Sources/ChannelStatsController.swift`: the section
  (`StatsSection.countries`), its four entries (header with the DEMO badge, globe, pie chart,
  note), and the entries after it moved down four stable ids.
- `Telegram/Telegram-iOS/en.lproj/Localizable.strings`: `ChannelStats.Countries.Title`,
  `ChannelStats.Countries.Demo`, `ChannelStats.Countries.DemoInfo`.

The whole change is one patch against the base commit `16a3d3c5`, without the Xcode 26 build fix:
[`subscriber-globe.patch`](subscriber-globe.patch). Apply it with `git apply`.

## Further reading

- [api.md](api.md): the server change that would make the data real.
- [decisions.md](decisions.md): why the feature works the way it does.
