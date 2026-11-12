import SwiftUI

enum MusicXTheme {
    static let background = Color(red: 0.035, green: 0.047, blue: 0.075)
    static let surface = Color(red: 0.075, green: 0.09, blue: 0.13)
    static let blue = Color(red: 0.28, green: 0.55, blue: 0.96)
    /// Secondary text. Raised from 0.58 so captions stay readable on the dark background on every page.
    static let muted = Color.white.opacity(0.72)
    /// Solid base under the floating mini player and tab bar, so scrolling content never shows through.
    static let chrome = Color(red: 0.045, green: 0.058, blue: 0.125)
    /// Fill for the floating mini player and tab bar capsules.
    static let chromeCapsule = Color(red: 0.10, green: 0.13, blue: 0.26)
    /// Thin separator lines shared by every page.
    static let hairline = Color.white.opacity(0.14)
}
