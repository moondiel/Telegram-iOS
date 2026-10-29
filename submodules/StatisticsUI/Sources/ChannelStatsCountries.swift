import Foundation
import TelegramCore
import TelegramPresentationData
import TelegramStringFormatting

// Subscriber Globe: followers of a channel by country, shown on a globe in channel statistics.
// See docs/subscriber-globe/README.md.
//
// Telegram's statistics do not report countries (`stats.broadcastStats` has languages only), so the
// countries are estimated from the real languages graph: each language's followers are shared out
// over the countries where Telegram users speak it. The model is the shape a server aggregate would
// have: a count per country, never individual followers.

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
    /// Estimated from languages rather than reported by the server.
    let isEstimate: Bool

    var total: Int {
        return self.countries.reduce(0, { $0 + $1.followers })
    }
}

/// Marker positions: each country's capital or largest city.
private let countryMarkerCoordinates: [String: (Double, Double)] = [
    "AE": (25.20, 55.27),
    "AF": (34.53, 69.17),
    "AM": (40.18, 44.51),
    "AO": (-8.84, 13.23),
    "AR": (-34.60, -58.38),
    "AT": (48.21, 16.37),
    "AU": (-33.87, 151.21),
    "AZ": (40.41, 49.87),
    "BE": (50.85, 4.35),
    "BG": (42.70, 23.32),
    "BR": (-23.55, -46.63),
    "BY": (53.90, 27.56),
    "CA": (43.65, -79.38),
    "CH": (47.38, 8.54),
    "CI": (5.36, -4.01),
    "CL": (-33.45, -70.67),
    "CO": (4.71, -74.07),
    "CY": (34.68, 33.04),
    "CZ": (50.08, 14.44),
    "DE": (52.52, 13.40),
    "DK": (55.68, 12.57),
    "DZ": (36.75, 3.06),
    "EC": (-0.18, -78.47),
    "EE": (59.44, 24.75),
    "EG": (30.04, 31.24),
    "ES": (40.42, -3.70),
    "ET": (9.03, 38.74),
    "FI": (60.17, 24.94),
    "FR": (48.86, 2.35),
    "GB": (51.51, -0.13),
    "GE": (41.72, 44.79),
    "GR": (37.98, 23.73),
    "HK": (22.32, 114.17),
    "HR": (45.81, 15.98),
    "HU": (47.50, 19.04),
    "ID": (-6.21, 106.85),
    "IL": (32.09, 34.78),
    "IN": (28.61, 77.21),
    "IQ": (33.31, 44.36),
    "IR": (35.69, 51.39),
    "IT": (41.90, 12.50),
    "JO": (31.95, 35.93),
    "JP": (35.68, 139.69),
    "KE": (-1.29, 36.82),
    "KG": (42.87, 74.59),
    "KR": (37.57, 126.98),
    "KZ": (43.24, 76.89),
    "LB": (33.89, 35.50),
    "LT": (54.69, 25.28),
    "LV": (56.95, 24.11),
    "MA": (33.57, -7.59),
    "MD": (47.01, 28.86),
    "MX": (19.43, -99.13),
    "MY": (3.14, 101.69),
    "NG": (6.52, 3.38),
    "NL": (52.37, 4.90),
    "NO": (59.91, 10.75),
    "PE": (-12.05, -77.04),
    "PH": (14.60, 120.98),
    "PK": (24.86, 67.01),
    "PL": (52.23, 21.01),
    "PT": (38.72, -9.14),
    "RO": (44.43, 26.10),
    "RS": (44.79, 20.45),
    "RU": (55.76, 37.62),
    "SA": (24.71, 46.68),
    "SE": (59.33, 18.07),
    "SG": (1.35, 103.82),
    "SK": (48.15, 17.11),
    "SY": (33.51, 36.29),
    "TH": (13.76, 100.50),
    "TJ": (38.56, 68.79),
    "TM": (37.96, 58.33),
    "TR": (41.01, 28.98),
    "TW": (25.03, 121.57),
    "TZ": (-6.79, 39.21),
    "UA": (50.45, 30.52),
    "US": (40.71, -74.01),
    "UZ": (41.30, 69.24),
    "VE": (10.48, -66.90),
    "VN": (21.03, 105.85),
    "YE": (15.37, 44.19),
    "ZA": (-26.20, 28.05)
]

/// Where Telegram users of a language are, as shares that add up to 1, keyed by ISO 639-1 code.
/// A rough picture of where each language is spoken, weighted towards where Telegram is used; it
/// places a Russian speaker in Dubai in Russia, which is why the screen calls the result an estimate.
private let languageCountryShares: [String: [(String, Double)]] = [
    "ru": [("RU", 0.70), ("UA", 0.07), ("KZ", 0.07), ("BY", 0.05), ("UZ", 0.04), ("DE", 0.03), ("IL", 0.02), ("KG", 0.02)],
    "en": [("IN", 0.22), ("US", 0.20), ("NG", 0.09), ("GB", 0.08), ("PH", 0.07), ("PK", 0.07), ("CA", 0.05), ("AE", 0.05), ("AU", 0.04), ("ZA", 0.04), ("KE", 0.04), ("SG", 0.05)],
    "uk": [("UA", 0.88), ("PL", 0.06), ("DE", 0.06)],
    "es": [("MX", 0.25), ("ES", 0.15), ("CO", 0.13), ("AR", 0.12), ("PE", 0.08), ("VE", 0.08), ("CL", 0.07), ("US", 0.07), ("EC", 0.05)],
    "pt": [("BR", 0.85), ("PT", 0.10), ("AO", 0.05)],
    "de": [("DE", 0.80), ("AT", 0.10), ("CH", 0.10)],
    "fr": [("FR", 0.60), ("BE", 0.10), ("CA", 0.10), ("MA", 0.10), ("CI", 0.10)],
    "it": [("IT", 0.95), ("CH", 0.05)],
    "tr": [("TR", 1.0)],
    "fa": [("IR", 0.90), ("AF", 0.10)],
    "ar": [("EG", 0.20), ("SA", 0.15), ("IQ", 0.12), ("DZ", 0.10), ("MA", 0.10), ("AE", 0.08), ("SY", 0.08), ("JO", 0.07), ("YE", 0.05), ("LB", 0.05)],
    "uz": [("UZ", 1.0)],
    "kk": [("KZ", 1.0)],
    "be": [("BY", 1.0)],
    "pl": [("PL", 1.0)],
    "id": [("ID", 1.0)],
    "ms": [("MY", 0.90), ("SG", 0.10)],
    "hi": [("IN", 1.0)],
    "vi": [("VN", 1.0)],
    "th": [("TH", 1.0)],
    "ko": [("KR", 1.0)],
    "ja": [("JP", 1.0)],
    "zh": [("TW", 0.40), ("HK", 0.30), ("SG", 0.20), ("MY", 0.10)],
    "he": [("IL", 1.0)],
    "nl": [("NL", 0.75), ("BE", 0.25)],
    "cs": [("CZ", 1.0)],
    "sk": [("SK", 1.0)],
    "hu": [("HU", 1.0)],
    "ro": [("RO", 0.80), ("MD", 0.20)],
    "sr": [("RS", 1.0)],
    "hr": [("HR", 1.0)],
    "bg": [("BG", 1.0)],
    "el": [("GR", 0.90), ("CY", 0.10)],
    "sv": [("SE", 1.0)],
    "nb": [("NO", 1.0)],
    "da": [("DK", 1.0)],
    "fi": [("FI", 1.0)],
    "et": [("EE", 1.0)],
    "lv": [("LV", 1.0)],
    "lt": [("LT", 1.0)],
    "az": [("AZ", 1.0)],
    "hy": [("AM", 1.0)],
    "ka": [("GE", 1.0)],
    "ky": [("KG", 1.0)],
    "tg": [("TJ", 1.0)],
    "tk": [("TM", 1.0)],
    "am": [("ET", 1.0)],
    "sw": [("KE", 0.50), ("TZ", 0.50)],
    "ca": [("ES", 1.0)]
]

/// The languages graph names its columns by language. Its names are matched in English and as
/// ISO 639-1 codes.
private let languageCodesByName: [String: String] = [
    "russian": "ru", "english": "en", "ukrainian": "uk", "spanish": "es", "portuguese": "pt",
    "brazilian portuguese": "pt", "german": "de", "french": "fr", "italian": "it", "turkish": "tr",
    "persian": "fa", "farsi": "fa", "arabic": "ar", "uzbek": "uz", "kazakh": "kk", "belarusian": "be",
    "polish": "pl", "indonesian": "id", "malay": "ms", "hindi": "hi", "vietnamese": "vi", "thai": "th",
    "korean": "ko", "japanese": "ja", "chinese": "zh", "hebrew": "he", "dutch": "nl", "czech": "cs",
    "slovak": "sk", "hungarian": "hu", "romanian": "ro", "serbian": "sr", "croatian": "hr",
    "bulgarian": "bg", "greek": "el", "swedish": "sv", "norwegian": "nb", "danish": "da",
    "finnish": "fi", "estonian": "et", "latvian": "lv", "lithuanian": "lt", "azerbaijani": "az",
    "armenian": "hy", "georgian": "ka", "kyrgyz": "ky", "tajik": "tg", "turkmen": "tk",
    "amharic": "am", "swahili": "sw", "catalan": "ca"
]

private func languageCode(forColumnName name: String) -> String? {
    let normalized = name.trimmingCharacters(in: .whitespaces).lowercased()
    if languageCountryShares[normalized] != nil {
        return normalized
    }
    if let code = languageCodesByName[normalized] {
        return code
    }
    // "pt-br", "zh_Hans" and the like.
    let prefix = String(normalized.prefix(while: { $0.isLetter }))
    if prefix.count == 2, languageCountryShares[prefix] != nil {
        return prefix
    }
    return nil
}

extension ChannelStatsCountries {
    /// The channel's followers by country, estimated from its languages graph: each language's
    /// latest share of followers is shared out over the countries where it is spoken. Languages the
    /// table does not know are left out. Nil until the languages graph has loaded.
    static func estimated(fromLanguagesGraph graph: StatsGraph, followers: Int) -> ChannelStatsCountries? {
        guard case let .Loaded(_, data) = graph, followers > 0 else {
            return nil
        }
        guard let jsonData = data.data(using: .utf8), let json = (try? JSONSerialization.jsonObject(with: jsonData)) as? [String: Any] else {
            return nil
        }
        guard let columns = json["columns"] as? [[Any]], let names = json["names"] as? [String: String] else {
            return nil
        }
        let types = json["types"] as? [String: String] ?? [:]

        // The latest value of every language, the graph's last day.
        var languageValues: [(code: String?, value: Double)] = []
        for column in columns {
            guard let id = column.first as? String, id != "x", types[id] != "x" else {
                continue
            }
            guard let last = column.last as? NSNumber, column.count > 1 else {
                continue
            }
            let value = last.doubleValue
            if value <= 0.0 {
                continue
            }
            languageValues.append((names[id].flatMap(languageCode(forColumnName:)), value))
        }
        let languagesTotal = languageValues.reduce(0.0, { $0 + $1.value })
        if languagesTotal <= 0.0 {
            return nil
        }

        var estimates: [String: Double] = [:]
        for (code, value) in languageValues {
            guard let code, let shares = languageCountryShares[code] else {
                continue
            }
            let languageFollowers = Double(followers) * value / languagesTotal
            for (country, share) in shares {
                estimates[country, default: 0.0] += languageFollowers * share
            }
        }

        // The largest countries, enough to read on a globe and in a list.
        var countries: [ChannelStatsCountry] = []
        for (code, estimate) in estimates.sorted(by: { $0.value > $1.value }).prefix(10) {
            let count = Int(estimate.rounded())
            guard count > 0, let coordinate = countryMarkerCoordinates[code] else {
                continue
            }
            countries.append(ChannelStatsCountry(code: code, followers: count, latitude: coordinate.0, longitude: coordinate.1))
        }
        if countries.isEmpty {
            return nil
        }
        return ChannelStatsCountries(countries: countries, isEstimate: true)
    }

    /// The countries as a statistics graph, in the JSON the server sends for the languages graph,
    /// so Telegram's own pie chart and legend draw them (`StatsGraphItem`, `.pie`).
    func graph(strings: PresentationStrings, period: StatsDateRange) -> StatsGraph {
        let locale = localeWithStrings(strings)
        // With real data the server sends the colours, as it does for the languages graph.
        let colors = ["#3497ED", "#2373DB", "#9ED448", "#5FB641", "#F5BD25", "#F79E39", "#E65850", "#5E5DB1", "#45B8C9", "#A65EB3"]

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
