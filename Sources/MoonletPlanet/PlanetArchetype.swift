import SwiftUI

#if canImport(AppKit)
import AppKit
#elseif canImport(UIKit)
import UIKit
#endif

public enum MoonletPlanetArchetype: UInt32, CaseIterable, Codable, Identifiable, Sendable {
    case gasGiant
    case iceGiant
    case ocean
    case frozen
    case rocky
    case molten
    case desert
    case toxic
    case lush
    case cloud

    public var id: Self { self }

    public var title: String {
        switch self {
        case .gasGiant: "Gas Giant"
        case .iceGiant: "Ice Giant"
        case .ocean: "Ocean World"
        case .frozen: "Frozen World"
        case .rocky: "Rocky World"
        case .molten: "Molten World"
        case .desert: "Desert World"
        case .toxic: "Toxic World"
        case .lush: "Lush World"
        case .cloud: "Cloud World"
        }
    }
}

public enum MoonletPlanetPreset: String, CaseIterable, Codable, Identifiable, Sendable {
    case custom
    case earth
    case mars
    case jupiter
    case saturn
    case uranus
    case neptune
    case venus
    case mercury
    case moon
    case pluto

    public var id: Self { self }

    public var title: String {
        rawValue.capitalized
    }

    public var style: MoonletPlanetStyle? {
        switch self {
        case .custom:
            nil
        case .earth:
            .init(name: "Earth", recipe: .solarPreset(.earth))
        case .mars:
            .init(name: "Mars", recipe: .solarPreset(.mars))
        case .jupiter:
            .init(name: "Jupiter", recipe: .solarPreset(.jupiter))
        case .saturn:
            .init(name: "Saturn", recipe: .solarPreset(.saturn), hasRing: true)
        case .uranus:
            .init(name: "Uranus", recipe: .solarPreset(.uranus), hasRing: true)
        case .neptune:
            .init(name: "Neptune", recipe: .solarPreset(.neptune))
        case .venus:
            .init(name: "Venus", recipe: .solarPreset(.venus))
        case .mercury:
            .init(name: "Mercury", recipe: .solarPreset(.mercury))
        case .moon:
            .init(name: "Moon", recipe: .solarPreset(.moon))
        case .pluto:
            .init(name: "Pluto", recipe: .solarPreset(.pluto))
        }
    }
}

public enum MoonletPlanetSurface: String, CaseIterable, Identifiable, Sendable {
    case smooth
    case cratered
    case banded
    case archipelago

    public var id: Self { self }
}
