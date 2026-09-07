import SwiftUI

/// Whether anything lives on a planet, and how far along it is.
///
/// Raw values are a wire format: the shader dispatches on the number, so a case is appended
/// and never inserted. Ordered, because each level is the one before it plus something.
public enum MoonletPlanetLife: UInt32, CaseIterable, Codable, Identifiable, Sendable, Comparable {
    /// Sterile. The default, and what every planet was before this existed.
    case none
    /// Something is growing. Low, wet ground has gone green; nothing is built and nothing is
    /// lit, so the night side stays dark.
    case simple
    /// Somebody is home. Cities appear on the night side, clustered on the coasts, and only
    /// some of the land is lit.
    case complex
    /// A civilisation that has left the ground. The night side is bright and something of
    /// theirs is in orbit.
    case advanced

    public var id: Self { self }

    public var title: String {
        switch self {
        case .none: "Sterile"
        case .simple: "Simple life"
        case .complex: "Civilisation"
        case .advanced: "Spacefaring"
        }
    }

    /// Whether this level puts lights on the night side.
    public var isLit: Bool { self >= .complex }

    /// Whether this level puts something in orbit.
    public var hasOrbitalStation: Bool { self == .advanced }

    public static func < (a: Self, b: Self) -> Bool { a.rawValue < b.rawValue }
}
