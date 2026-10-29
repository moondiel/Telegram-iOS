import Foundation

// Subscriber Globe: where the land is, for the dotted globe. See docs/subscriber-globe/README.md.
//
// The land is a grid of dots 2° apart, kept as one bit per dot: 90 rows of latitude from the south
// pole up, each row holding as many dots as fit around the globe at that latitude, so the dots stay
// evenly spaced instead of crowding at the poles. The outlines were drawn by hand at the scale of the
// grid: the globe is a picture of where an audience is, not a map to navigate by.

/// Degrees between neighbouring dots, along a row and between rows.
private let landGridStep: Double = 2.0
private let landGridRows = 90

/// The land bits, row after row, least significant bit first.
private let landGridBits = """
////////////v//////4f////4D/8P//PwD4gP///wcAQAD///8fAAAIAID//wcAAEAAAID/fwAAAIAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAABgAAAAAAAAAAAAAAAAIAAAAAAAAAAAAAAADAAAAAAAAAAAAA
AAAAAAAHAAAAAAAAAAAAAAAAAAAHAAAAAAAAAAAAAAAAAABwAAAAAAAAAAAAAAQAAAAA4AEAAAAAAAAAACDAAAAAAAA8AAAAAAAA
AAAAIIAAAAAAAPgAAAAAAAAAAAAAABAAAAAAAH4AAAAAAAAAAADAAwAAAAAAAPwBAAAAAAAAAICAHwAAAAAAAMA/AAAA8AAAAADg
4Q8AAAAAAADAfwAAAOADAAAAwP8/AAAAAAAAAP4HAAAAfwAAAAD4/wcAAAAAAACA/wEAAMA/AAAAAPz/BwAAAAAAAAD/BwAAgP8g
AAAA8P8/AAAAAAAAAOD/AQAA8B8GAAAA/v8HAAAAAAAAAPj/AQAA/A8HAAAA/P8DAAAAAAAAAPD/AwAA+D8MAAAAwP8DAAAAAAAA
AMD/HwAAwP/jAAAAAPgzAAAAAAAAAAD+/wMAAPj/EQAAAAA8BgAAAAAAAADA//8BAAD8fwgAAAAAOAEAAAAAAAAA4P//AwAA/H8A
AAAAAAAAAAAAAAAAAMD//w8AAPj/AAAAAAAAaAAAAAAAAAAA//8/AADA/wcAAADwAPABAAAAAAAAAPz//wEAAP8/AAAAQMCABwAA
AAAAAADA//8BAADw/wMAAADmBB8AAAAAAAAAAPz/AwAAgP9/AAAAMN4AAAAAAAAAAADA/x8AAAD4/w8AAADhCQAAAAAAAAAAAPj/
AQAAgP//AQAAKBwAAAAAAAAAAACA/w8AABb//z8AAKCBAQAAAAAAAAAAAPwPAAD4////AQABBGAAAAAAAAAAAADuHwAA4P///w8A
BgAAAAAAAAAAAAAABAMAAOD///8zAAyAAwAAAAAAAAAAAAwAAADg////AQAG8AMBAAAAAAAAAMAHAAAA+P//PweAA/wgAAAAAAAA
AAA/AAAAAP////cDeOAHAgAAAAAAAAA8AwcAAPj//98/4IdfAAAAAAAAAAB4hAEAAPD//59/wJ+/AAAAAAAAAAA8AAAAAPD//+8/
+P//BQAAAAAAAMAHAAAAAP7/f3/A//9fAAAAAAAAQD8AAAAA+P//fv7//38AAAAAAACgPwgAAAD4/7/f////HwAAAAAAAP7/AAAA
gP/3/f///38AAAAAAAD8/wMAAAD/APz///8/BAAAAACA//8BAADAH4T/////0QMAAAAA/v8PAACAIeC/////JwIAAAAA//8HAADw
QP3n//8/QgAAAAD4/z8AAICD/s////8HAAAAAPz/PwAA4NGD+f///xEAAADA//8HAAD+r/P///8DAAAA8P//AADA//////8/AAAA
gP//EQCA//////8fAAAA/P//AAD6/////38AAAD8//8AQP3/////BwEA4P/3AQAD/////4MBEPg/PAAg5v///x8GcPg/OAAA5///
/4cB/v9DIADc////v4P//yAMgP3////f/v9zjsHv//////+fOYDf////+IeaD3jg//8BOOYHgP5/AHDADwD8AQAwPwBxDAD0Q4AA
AH4EAAA8AABAAAAAAAA=
"""

/// One dot of land: its latitude and longitude in radians.
struct StatsGlobeLandDot {
    let latitude: Float
    let longitude: Float
}

/// The dots of land, decoded once.
let statsGlobeLandDots: [StatsGlobeLandDot] = {
    guard let data = Data(base64Encoded: landGridBits, options: .ignoreUnknownCharacters) else {
        return []
    }
    let bytes = [UInt8](data)
    var dots: [StatsGlobeLandDot] = []
    var bitIndex = 0
    for row in 0 ..< landGridRows {
        let latitude = -90.0 + landGridStep / 2.0 + Double(row) * landGridStep
        // The same count the grid was encoded with: the row's length in steps, rounded half up.
        let count = max(1, Int((360.0 * cos(latitude * Double.pi / 180.0) / landGridStep + 0.5).rounded(.down)))
        for column in 0 ..< count {
            let byteIndex = bitIndex >> 3
            if byteIndex < bytes.count, (bytes[byteIndex] >> UInt8(bitIndex & 7)) & 1 != 0 {
                let longitude = -180.0 + (Double(column) + 0.5) * 360.0 / Double(count)
                dots.append(StatsGlobeLandDot(latitude: Float(latitude * Double.pi / 180.0), longitude: Float(longitude * Double.pi / 180.0)))
            }
            bitIndex += 1
        }
    }
    return dots
}()
