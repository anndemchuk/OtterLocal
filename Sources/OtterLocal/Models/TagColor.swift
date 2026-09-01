import SwiftUI

/// A colored tag you can put on a recording -- useful for marking things
/// like "needs review" (red) or "exam material" (purple) at a glance, since
/// there's no other way to categorize recordings in the sidebar yet.
enum TagColor: String, Codable, CaseIterable, Identifiable {
    case red, orange, yellow, green, purple

    var id: String { rawValue }

    var color: Color {
        switch self {
        case .red: return .red
        case .orange: return .orange
        case .yellow: return .yellow
        case .green: return .green
        case .purple: return .purple
        }
    }

    var label: String {
        rawValue.capitalized
    }

    /// A colored circle emoji matching this tag. Native macOS menu items
    /// render SF Symbol icons as template (monochrome) images regardless of
    /// what color you apply to them, so a colored SF Symbol dot always shows
    /// up plain white in the Tag menu. Emoji aren't template-rendered, so
    /// this is what actually shows the right color there.
    var emoji: String {
        switch self {
        case .red: return "\u{1F534}"
        case .orange: return "\u{1F7E0}"
        case .yellow: return "\u{1F7E1}"
        case .green: return "\u{1F7E2}"
        case .purple: return "\u{1F7E3}"
        }
    }
}
