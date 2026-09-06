import SwiftUI

#if canImport(AppKit)
import AppKit
#elseif canImport(UIKit)
import UIKit
#endif

public struct MoonletColor: Codable, Equatable, Hashable, Sendable {
    public var red: Double
    public var green: Double
    public var blue: Double
    public var opacity: Double

    public init(red: Double, green: Double, blue: Double, opacity: Double = 1) {
        self.red = red
        self.green = green
        self.blue = blue
        self.opacity = opacity
    }

    public init(hue: Double, saturation: Double, brightness: Double, opacity: Double = 1) {
        let normalizedHue = (hue.truncatingRemainder(dividingBy: 1) + 1).truncatingRemainder(dividingBy: 1)
        let sector = normalizedHue * 6
        let index = Int(sector)
        let fraction = sector - Double(index)
        let p = brightness * (1 - saturation)
        let q = brightness * (1 - saturation * fraction)
        let t = brightness * (1 - saturation * (1 - fraction))
        switch index % 6 {
        case 0: self.init(red: brightness, green: t, blue: p, opacity: opacity)
        case 1: self.init(red: q, green: brightness, blue: p, opacity: opacity)
        case 2: self.init(red: p, green: brightness, blue: t, opacity: opacity)
        case 3: self.init(red: p, green: q, blue: brightness, opacity: opacity)
        case 4: self.init(red: t, green: p, blue: brightness, opacity: opacity)
        default: self.init(red: brightness, green: p, blue: q, opacity: opacity)
        }
    }

    public init(_ color: Color) {
        #if canImport(AppKit)
        let resolved = NSColor(color).usingColorSpace(.deviceRGB) ?? .white
        self.init(red: resolved.redComponent, green: resolved.greenComponent, blue: resolved.blueComponent, opacity: resolved.alphaComponent)
        #elseif canImport(UIKit)
        var red: CGFloat = 1
        var green: CGFloat = 1
        var blue: CGFloat = 1
        var alpha: CGFloat = 1
        UIColor(color).getRed(&red, green: &green, blue: &blue, alpha: &alpha)
        self.init(red: red, green: green, blue: blue, opacity: alpha)
        #else
        self.init(red: 1, green: 1, blue: 1)
        #endif
    }

    public var color: Color {
        Color(red: red, green: green, blue: blue, opacity: opacity)
    }
}

public struct MoonletPlanetPalette: Codable, Equatable, Hashable, Sendable {
    public var highlight: MoonletColor
    public var primary: MoonletColor
    public var shadow: MoonletColor
    public var storm: MoonletColor
    public var atmosphere: MoonletColor
    /// What the rings are made of. Saturn's are dirty water ice, so the default is a
    /// near-white that the profile's own tints darken rather than replace.
    public var ring: MoonletColor
    /// Surface ice. Not pure white — snow takes the colour of the sky above it, and a flat
    /// #FFFFFF cap is the thing that makes a rendered planet look like a diagram.
    public var ice: MoonletColor

    public init(
        highlight: MoonletColor,
        primary: MoonletColor,
        shadow: MoonletColor,
        storm: MoonletColor,
        atmosphere: MoonletColor,
        ring: MoonletColor = MoonletColor(red: 0.94, green: 0.90, blue: 0.83),
        ice: MoonletColor = MoonletColor(red: 0.93, green: 0.95, blue: 0.97)
    ) {
        self.highlight = highlight
        self.primary = primary
        self.shadow = shadow
        self.storm = storm
        self.atmosphere = atmosphere
        self.ring = ring
        self.ice = ice
    }

    // A palette is stored data, so a field added after somebody saved theirs has to decode
    // to something rather than fail. See CHANGELOG.md for why that is a rule and not a
    // courtesy.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        highlight = try container.decode(MoonletColor.self, forKey: .highlight)
        primary = try container.decode(MoonletColor.self, forKey: .primary)
        shadow = try container.decode(MoonletColor.self, forKey: .shadow)
        storm = try container.decode(MoonletColor.self, forKey: .storm)
        atmosphere = try container.decode(MoonletColor.self, forKey: .atmosphere)
        ring = try container.decodeIfPresent(MoonletColor.self, forKey: .ring)
            ?? MoonletColor(red: 0.94, green: 0.90, blue: 0.83)
        ice = try container.decodeIfPresent(MoonletColor.self, forKey: .ice)
            ?? MoonletColor(red: 0.93, green: 0.95, blue: 0.97)
    }
}
