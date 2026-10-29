# Subscriber Globe — API proposal

The client needs one thing the server does not send yet: how many of a channel's followers are
in each country. This page proposes the smallest change that would provide it.

## The change

Add a graph to `stats.broadcastStats`, next to `languages_graph`:

```
stats.broadcastStats#… … languages_graph:StatsGraph countries_graph:flags.N?StatsGraph … = stats.BroadcastStats;
```

- `countries_graph` uses the same JSON format as `languages_graph`: an `x` column of days, and a
  column per country with its followers on each day.
- Column ids can stay opaque (`y0`, `y1`…). `names` gives the ISO 3166-1 alpha-2 code, for
  example `"y0": "DE"`, so the client localizes the name and draws the flag. `colors` works as in
  the other graphs.
- It is loaded on demand like the other heavy graphs (`StatsGraph` with an async token), so the
  first screen does not wait for it.

## Privacy

The graph is an aggregate, like the other statistics:

- The server decides each follower's country from what it already uses for such purposes,
  such as the phone number's country or the IP region. The client never learns it for a person.
- Countries with fewer followers than a threshold (for example 10) are merged into an "Other"
  column, so a small country cannot single out a follower.
- It is available under the same conditions as the rest of the channel's statistics, such as the
  follower minimum and admin rights.

## What changes in the client

- `ChannelStats` gains `countriesGraph: StatsGraph`, parsed like `languagesGraph`.
- `ChannelStatsCountries` is built from that graph: country codes from `names`, counts from the
  columns, marker coordinates from the table in `ChannelStatsCountries.swift`.
- `ChannelStatsCountries.demo(peerId:followers:)`, and the DEMO badge are removed.

The globe, the markers, the pie chart and the section stay as they are.
