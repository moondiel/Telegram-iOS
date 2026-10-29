import Foundation
import TelegramCore
import TelegramPresentationData
import TelegramStringFormatting

// Subscriber Globe: followers of a channel by country, shown on a globe in channel statistics.
// See docs/subscriber-globe/README.md.
//
// Telegram's statistics do not report countries (`stats.broadcastStats` has languages only), so the
// screen shows a demo distribution, marked as such, until the server sends one. The model is the
// shape a server aggregate would have: a count per country, never individual followers.

/// One country of a channel's audience.
struct ChannelStatsCountry: Equatable {
    /// ISO 3166-1 alpha-2.
    let code: String
    let followers: Int
    /// Where the country's marker sits on the globe.
    let latitude: Double
    let longitude: Double
}

/// A channel's followers by country, most followers first.
struct ChannelStatsCountries: Equatable {
    let countries: [ChannelStatsCountry]
    /// Not the channel's data: a stand-in until the server reports countries.
    let isDemo: Bool

    var total: Int {
        return self.countries.reduce(0, { $0 + $1.followers })
    }
}

/// Marker positions: each country's capital or largest city.
private let countryMarkerCoordinates: [String: (Double, Double)] = [
    "RU": (55.76, 37.62),
    "UA": (50.45, 30.52),
    "BY": (53.90, 27.56),
    "KZ": (43.24, 76.89),
    "UZ": (41.30, 69.24),
    "GE": (41.72, 44.79),
    "AM": (40.18, 44.51),
    "AZ": (40.41, 49.87),
    "DE": (52.52, 13.40),
    "NL": (52.37, 4.90),
    "PL": (52.23, 21.01),
    "RS": (44.79, 20.45),
    "FR": (48.86, 2.35),
    "ES": (40.42, -3.70),
    "IT": (41.90, 12.50),
    "GB": (51.51, -0.13),
    "TR": (41.01, 28.98),
    "CY": (34.68, 33.04),
    "IL": (32.09, 34.78),
    "AE": (25.20, 55.27),
    "IN": (28.61, 77.21),
    "TH": (13.76, 100.50),
    "ID": (-6.21, 106.85),
    "US": (40.71, -74.01),
    "CA": (43.65, -79.38),
    "BR": (-23.55, -46.63)
]

extension ChannelStatsCountries {
    /// A plausible spread of `followers` over a handful of countries, the same for the same channel
    /// every time. Only for showing the feature: the screen labels it Demo.
    static func demo(peerId: EnginePeer.Id, followers: Int) -> ChannelStatsCountries {
        var random = SplitMix64(seed: UInt64(bitPattern: peerId.toInt64()))

        var pool = countryMarkerCoordinates.keys.sorted()
        for i in stride(from: pool.count - 1, to: 0, by: -1) {
            pool.swapAt(i, Int(random.next() % UInt64(i + 1)))
        }
        let codes = Array(pool.prefix(8))

        // One country dominates, the rest fall off, as audiences usually do.
        var weights: [Double] = []
        var weight = 1.0
        for _ in codes {
            weights.append(weight * (0.75 + Double(random.next() % 1000) / 2000.0))
            weight *= 0.55
        }

        let total = max(followers, 1)
        let sum = weights.reduce(0.0, +)
        var counts = weights.map { Int((Double(total) * $0 / sum).rounded(.down)) }
        // Hand out what rounding left, largest remainders first.
        let remainders = weights.enumerated().map { ($0.offset, Double(total) * $0.element / sum - Double(counts[$0.offset])) }.sorted(by: { $0.1 > $1.1 })
        var left = total - counts.reduce(0, +)
        for (index, _) in remainders where left > 0 {
            counts[index] += 1
            left -= 1
        }

        var countries: [ChannelStatsCountry] = []
        for (index, code) in codes.enumerated() where counts[index] > 0 {
            guard let coordinate = countryMarkerCoordinates[code] else {
                continue
            }
            countries.append(ChannelStatsCountry(code: code, followers: counts[index], latitude: coordinate.0, longitude: coordinate.1))
        }
        countries.sort(by: { $0.followers > $1.followers })
        return ChannelStatsCountries(countries: countries, isDemo: true)
    }

    /// The countries as a statistics graph, in the JSON the server sends for the languages graph,
    /// so Telegram's own pie chart and legend draw them (`StatsGraphItem`, `.pie`).
    func graph(strings: PresentationStrings, period: StatsDateRange) -> StatsGraph {
        let locale = localeWithStrings(strings)
        // A fixed palette for the demo; with real data the server sends the colours, as it does for
        // the languages graph.
        let colors = ["#3497ED", "#2373DB", "#9ED448", "#5FB641", "#F5BD25", "#F79E39", "#E65850", "#5E5DB1"]

        // A column per country with the same value every day: the pie shows the shares.
        let days = 7
        let maxDate = Double(period.maxDate)
        var dates: [Any] = ["x"]
        for day in 0 ..< days {
            dates.append((maxDate - Double(days - 1 - day) * 86400.0) * 1000.0)
        }
        var columns: [[Any]] = [dates]
        var types: [String: String] = ["x": "x"]
        var names: [String: String] = [:]
        var colorMap: [String: String] = [:]
        for (index, country) in self.countries.enumerated() {
            let id = "y\(index)"
            var column: [Any] = [id]
            for _ in 0 ..< days {
                column.append(country.followers)
            }
            columns.append(column)
            types[id] = "area"
            let name = locale.localizedString(forRegionCode: country.code) ?? country.code
            names[id] = "\(flagEmoji(countryCode: country.code)) \(name)"
            colorMap[id] = colors[index % colors.count]
        }
        let json: [String: Any] = [
            "columns": columns,
            "types": types,
            "names": names,
            "colors": colorMap,
            "percentage": true,
            "stacked": true
        ]
        guard let data = try? JSONSerialization.data(withJSONObject: json), let string = String(data: data, encoding: .utf8) else {
            return .Empty
        }
        return .Loaded(token: nil, data: string)
    }
}

/// A small seeded generator, so a channel's demo data does not change between visits.
private struct SplitMix64 {
    private var state: UInt64

    init(seed: UInt64) {
        self.state = seed
    }

    mutating func next() -> UInt64 {
        self.state &+= 0x9E3779B97F4A7C15
        var z = self.state
        z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9
        z = (z ^ (z >> 27)) &* 0x94D049BB133111EB
        return z ^ (z >> 31)
    }
}
