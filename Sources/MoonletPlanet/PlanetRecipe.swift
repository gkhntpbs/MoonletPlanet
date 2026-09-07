import SwiftUI

#if canImport(AppKit)
import AppKit
#elseif canImport(UIKit)
import UIKit
#endif

public struct MoonletPlanetRecipe: Codable, Equatable, Hashable, Sendable {
    public var archetype: MoonletPlanetArchetype
    public var seed: UInt32
    public var palette: MoonletPlanetPalette
    public var rotationSpeed: Double
    public var turbulence: Double
    public var detail: Double
    public var warpStrength: Double
    public var bandCount: Double
    public var bandSharpness: Double
    public var stormCount: Double
    public var stormStrength: Double
    public var cloudCoverage: Double
    public var cloudSpeed: Double
    public var atmosphereDensity: Double
    public var atmosphereGlow: Double
    public var roughness: Double
    public var featureAmount: Double
    public var lightAzimuth: Double
    public var lightElevation: Double
    public var exposure: Double

    /// How much material the rings carry. 0 is no rings at all and skips the whole ring
    /// path in the shader; 1 is Saturn's own optical depths.
    public var ringOpacity: Double
    /// The planet's pole, in radians, and therefore also the angle its rings are seen at —
    /// rings lie in the equator, so these were never two independent settings. 0 points the
    /// pole up the screen and shows any rings edge-on; `.pi / 2` points it at the camera and
    /// opens them fully. Bands and ice caps follow it too.
    public var axialTilt: Double
    /// Where the ring system starts and ends, in planet radii. Saturn's are 1.235 and 2.27,
    /// and these stretch that anatomy rather than replacing it: the Cassini Division stays
    /// proportionally where it belongs however wide the system is.
    public var ringInnerRadius: Double
    public var ringOuterRadius: Double
    /// How strongly the ringlets band the system. 0 is four smooth annuli.
    public var ringDetail: Double

    /// How much of the world is under ice, as a position for the freezing isotherm rather
    /// than a cap radius: 0 is a world with no ice at all, 1 glaciates it to the equator.
    /// Earth sits near 0.24, Mars near 0.3, a snowball near 0.9.
    public var iceCoverage: Double
    /// The lapse rate — how much colder height makes a place. Above zero, mountains hold
    /// snow far from the poles, which is why the equator has glaciers on it.
    public var iceAltitude: Double
    /// How differently the two hemispheres freeze. Zero is a world with two matching caps,
    /// which no real one has: Antarctica is a continent and the Arctic is a sea, and Mars's
    /// southern cap outlasts its northern one because of orbital eccentricity.
    public var polarAsymmetry: Double
    /// How much fine, high-frequency structure sits on top of everything. 0 is the broad
    /// shapes alone.
    public var microDetail: Double
    /// Where the planet is in its own day, in radians, added to whatever the clock has turned
    /// it. Set it to look at a particular face; a planet with `rotationSpeed` of zero still
    /// turns when this changes.
    public var rotationPhase: Double
    /// How fast the star sweeps around the planet, in radians a second. Zero holds the light
    /// still, which is what every planet did before this existed and remains the default.
    ///
    /// This is the *terminator* moving — the planet running through its phases, lit to
    /// crescent to dark — and it is a different thing from `rotationSpeed`, which turns the
    /// ground underneath a light that stays put. A world with both has ground that travels
    /// into its own night, which is what makes city lights appear as land rotates away from
    /// the star rather than switching on where they already were.
    public var dayNightSpeed: Double
    /// Whether anything lives here. Sterile by default, which is what every planet was before
    /// this existed.
    public var life: MoonletPlanetLife
    /// How many of theirs are in orbit, once `life` is `.advanced`; below that level the
    /// count is kept but nothing is drawn. One by default. More than one share an orbit's
    /// radius, speed and inclination but not its plane, so they do not read as beads.
    public var stationCount: Int
    /// The orbit, in planet radii. 1.085 is low enough to pass across the disc rather than
    /// skirt it; anything past the rings' inner edge flies through them.
    public var stationOrbitRadius: Double
    /// Radians a second around the orbit. Its precession is tied to this, so a slow station
    /// is slow in everything rather than fast in one thing.
    public var stationSpeed: Double
    /// The orbit's angle to the planet's equator, in radians. 0.9 is roughly the 51.6° the
    /// ISS flies; 0 is an equatorial orbit that only ever transits on a planet seen edge-on.
    public var stationInclination: Double
    /// A multiplier on the station's drawn size. It never shrinks below a pixel.
    public var stationSize: Double

    /// How far from the disc's centre the shader draws, in planet radii — 1 for a bare
    /// planet, wider for rings or anything in orbit. A view that sizes the body against a
    /// square has to divide by this or the outermost thing drawn is cut off at the square's
    /// edge. The shader computes the same number and the two must agree.
    public var drawnExtent: Double {
        let rings = hasRing ? max(1, ringOuterRadius * 1.04) : 1
        let stations = life.hasOrbitalStation && stationCount > 0 ? stationOrbitRadius + 0.1 : 1
        return max(rings, stations)
    }

    /// Whether this planet has rings at all.
    ///
    /// Turning them on opens an upright planet to an angle they can be seen at. `axialTilt`
    /// is the pole *and* the ring angle, and its right default for a planet is zero —
    /// upright — which for rings means exactly edge-on: a hairline, and not what anybody
    /// asking for rings meant. A planet already tilted keeps the tilt it had.
    public var hasRing: Bool {
        get { ringOpacity > 0 }
        set {
            guard newValue else { ringOpacity = 0; return }
            ringOpacity = max(ringOpacity, 1)
            if axialTilt == 0 { axialTilt = 0.45 }
        }
    }

    public init(
        archetype: MoonletPlanetArchetype,
        seed: UInt32,
        palette: MoonletPlanetPalette,
        rotationSpeed: Double,
        turbulence: Double,
        detail: Double,
        warpStrength: Double,
        bandCount: Double,
        bandSharpness: Double,
        stormCount: Double,
        stormStrength: Double,
        cloudCoverage: Double,
        cloudSpeed: Double,
        atmosphereDensity: Double,
        atmosphereGlow: Double,
        roughness: Double,
        featureAmount: Double,
        lightAzimuth: Double,
        lightElevation: Double,
        exposure: Double,
        ringOpacity: Double = 0,
        axialTilt: Double = 0,
        ringInnerRadius: Double = 1.235,
        ringOuterRadius: Double = 2.27,
        ringDetail: Double = 0.8,
        iceCoverage: Double = 0,
        iceAltitude: Double = 0.22,
        polarAsymmetry: Double = 0,
        microDetail: Double = 1,
        rotationPhase: Double = 0,
        dayNightSpeed: Double = 0,
        life: MoonletPlanetLife = .none,
        stationCount: Int = 1,
        stationOrbitRadius: Double = 1.085,
        stationSpeed: Double = 0.55,
        stationInclination: Double = 0.9,
        stationSize: Double = 1
    ) {
        self.archetype = archetype
        self.seed = seed
        self.palette = palette
        self.rotationSpeed = rotationSpeed
        self.turbulence = turbulence
        self.detail = detail
        self.warpStrength = warpStrength
        self.bandCount = bandCount
        self.bandSharpness = bandSharpness
        self.stormCount = stormCount
        self.stormStrength = stormStrength
        self.cloudCoverage = cloudCoverage
        self.cloudSpeed = cloudSpeed
        self.atmosphereDensity = atmosphereDensity
        self.atmosphereGlow = atmosphereGlow
        self.roughness = roughness
        self.featureAmount = featureAmount
        self.lightAzimuth = lightAzimuth
        self.lightElevation = lightElevation
        self.exposure = exposure
        self.ringOpacity = ringOpacity
        self.axialTilt = axialTilt
        self.ringInnerRadius = ringInnerRadius
        self.ringOuterRadius = ringOuterRadius
        self.ringDetail = ringDetail
        self.iceCoverage = iceCoverage
        self.iceAltitude = iceAltitude
        self.polarAsymmetry = polarAsymmetry
        self.microDetail = microDetail
        self.rotationPhase = rotationPhase
        self.dayNightSpeed = dayNightSpeed
        self.life = life
        self.stationCount = stationCount
        self.stationOrbitRadius = stationOrbitRadius
        self.stationSpeed = stationSpeed
        self.stationInclination = stationInclination
        self.stationSize = stationSize
    }

    // Stored data again: five fields that did not exist when somebody saved their planet,
    // and a planet that comes back ringless is better than one that fails to come back.
    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        archetype = try c.decode(MoonletPlanetArchetype.self, forKey: .archetype)
        seed = try c.decode(UInt32.self, forKey: .seed)
        palette = try c.decode(MoonletPlanetPalette.self, forKey: .palette)
        rotationSpeed = try c.decode(Double.self, forKey: .rotationSpeed)
        turbulence = try c.decode(Double.self, forKey: .turbulence)
        detail = try c.decode(Double.self, forKey: .detail)
        warpStrength = try c.decode(Double.self, forKey: .warpStrength)
        bandCount = try c.decode(Double.self, forKey: .bandCount)
        bandSharpness = try c.decode(Double.self, forKey: .bandSharpness)
        stormCount = try c.decode(Double.self, forKey: .stormCount)
        stormStrength = try c.decode(Double.self, forKey: .stormStrength)
        cloudCoverage = try c.decode(Double.self, forKey: .cloudCoverage)
        cloudSpeed = try c.decode(Double.self, forKey: .cloudSpeed)
        atmosphereDensity = try c.decode(Double.self, forKey: .atmosphereDensity)
        atmosphereGlow = try c.decode(Double.self, forKey: .atmosphereGlow)
        roughness = try c.decode(Double.self, forKey: .roughness)
        featureAmount = try c.decode(Double.self, forKey: .featureAmount)
        lightAzimuth = try c.decode(Double.self, forKey: .lightAzimuth)
        lightElevation = try c.decode(Double.self, forKey: .lightElevation)
        exposure = try c.decode(Double.self, forKey: .exposure)
        ringOpacity = try c.decodeIfPresent(Double.self, forKey: .ringOpacity) ?? 0
        axialTilt = try c.decodeIfPresent(Double.self, forKey: .axialTilt) ?? 0
        ringInnerRadius = try c.decodeIfPresent(Double.self, forKey: .ringInnerRadius) ?? 1.235
        ringOuterRadius = try c.decodeIfPresent(Double.self, forKey: .ringOuterRadius) ?? 2.27
        ringDetail = try c.decodeIfPresent(Double.self, forKey: .ringDetail) ?? 0.8
        iceCoverage = try c.decodeIfPresent(Double.self, forKey: .iceCoverage) ?? 0
        iceAltitude = try c.decodeIfPresent(Double.self, forKey: .iceAltitude) ?? 0.22
        polarAsymmetry = try c.decodeIfPresent(Double.self, forKey: .polarAsymmetry) ?? 0
        // A planet saved before this existed was drawn with all of it, so its default is on.
        microDetail = try c.decodeIfPresent(Double.self, forKey: .microDetail) ?? 1
        rotationPhase = try c.decodeIfPresent(Double.self, forKey: .rotationPhase) ?? 0
        dayNightSpeed = try c.decodeIfPresent(Double.self, forKey: .dayNightSpeed) ?? 0
        life = try c.decodeIfPresent(MoonletPlanetLife.self, forKey: .life) ?? .none
        // The one station a spacefaring world had before these were settings.
        stationCount = try c.decodeIfPresent(Int.self, forKey: .stationCount) ?? 1
        stationOrbitRadius = try c.decodeIfPresent(Double.self, forKey: .stationOrbitRadius) ?? 1.085
        stationSpeed = try c.decodeIfPresent(Double.self, forKey: .stationSpeed) ?? 0.55
        stationInclination = try c.decodeIfPresent(Double.self, forKey: .stationInclination) ?? 0.9
        stationSize = try c.decodeIfPresent(Double.self, forKey: .stationSize) ?? 1
    }

    public static func preset(_ archetype: MoonletPlanetArchetype, seed: UInt32 = 240513) -> Self {
        switch archetype {
        case .gasGiant:
            return Self(
                archetype: archetype,
                seed: seed,
                palette: .init(
                    highlight: .init(red: 0.96, green: 0.86, blue: 0.66),
                    primary: .init(red: 0.62, green: 0.34, blue: 0.16),
                    shadow: .init(red: 0.12, green: 0.07, blue: 0.09),
                    storm: .init(red: 0.94, green: 0.68, blue: 0.36),
                    atmosphere: .init(red: 0.48, green: 0.72, blue: 0.95)
                ),
                rotationSpeed: 0.11,
                turbulence: 0.78,
                detail: 0.82,
                warpStrength: 0.76,
                bandCount: 13,
                bandSharpness: 0.62,
                stormCount: 5,
                stormStrength: 0.86,
                cloudCoverage: 0.92,
                cloudSpeed: 0.65,
                atmosphereDensity: 0.52,
                atmosphereGlow: 0.62,
                roughness: 0.72,
                featureAmount: 0.7,
                lightAzimuth: 2.2,
                lightElevation: 0.46,
                exposure: 1.08
            )
        case .iceGiant:
            var recipe = preset(.gasGiant, seed: seed)
            recipe.archetype = archetype
            recipe.palette = .init(
                highlight: .init(red: 0.78, green: 0.94, blue: 1),
                primary: .init(red: 0.16, green: 0.55, blue: 0.76),
                shadow: .init(red: 0.025, green: 0.08, blue: 0.2),
                storm: .init(red: 0.53, green: 0.88, blue: 0.98),
                atmosphere: .init(red: 0.22, green: 0.72, blue: 1)
            )
            recipe.turbulence = 0.48
            recipe.warpStrength = 0.42
            recipe.bandCount = 8
            recipe.stormCount = 3
            recipe.stormStrength = 0.52
            recipe.atmosphereGlow = 0.86
            recipe.roughness = 0.48
            return recipe
        case .ocean:
            var recipe = preset(.gasGiant, seed: seed)
            recipe.archetype = archetype
            recipe.palette = .init(
                highlight: .init(red: 0.62, green: 0.9, blue: 0.98),
                primary: .init(red: 0.025, green: 0.28, blue: 0.58),
                shadow: .init(red: 0.01, green: 0.035, blue: 0.13),
                storm: .init(red: 0.95, green: 0.98, blue: 1),
                atmosphere: .init(red: 0.24, green: 0.68, blue: 1)
            )
            recipe.turbulence = 0.57
            recipe.detail = 0.7
            recipe.warpStrength = 0.54
            recipe.bandCount = 6
            recipe.bandSharpness = 0.28
            recipe.stormCount = 4
            recipe.cloudCoverage = 0.58
            recipe.roughness = 0.22
            recipe.featureAmount = 0.64
            return recipe
        case .frozen:
            var recipe = preset(.iceGiant, seed: seed)
            recipe.archetype = archetype
            recipe.palette = .init(
                highlight: .init(red: 0.94, green: 0.98, blue: 1),
                primary: .init(red: 0.42, green: 0.7, blue: 0.83),
                shadow: .init(red: 0.05, green: 0.12, blue: 0.24),
                storm: .init(red: 0.72, green: 0.94, blue: 1),
                atmosphere: .init(red: 0.46, green: 0.82, blue: 1)
            )
            recipe.rotationSpeed = 0.035
            recipe.turbulence = 0.36
            recipe.warpStrength = 0.28
            recipe.bandCount = 4
            recipe.stormCount = 1
            recipe.cloudCoverage = 0.3
            recipe.roughness = 0.9
            recipe.featureAmount = 0.92
            return recipe
        case .rocky:
            var recipe = preset(.gasGiant, seed: seed)
            recipe.archetype = archetype
            recipe.palette = .init(
                highlight: .init(red: 0.79, green: 0.66, blue: 0.5),
                primary: .init(red: 0.35, green: 0.24, blue: 0.18),
                shadow: .init(red: 0.075, green: 0.055, blue: 0.06),
                storm: .init(red: 0.54, green: 0.42, blue: 0.28),
                atmosphere: .init(red: 0.58, green: 0.42, blue: 0.3)
            )
            recipe.rotationSpeed = 0.025
            recipe.turbulence = 0.7
            recipe.warpStrength = 0.33
            recipe.bandCount = 3
            recipe.stormCount = 0
            recipe.cloudCoverage = 0.08
            recipe.atmosphereDensity = 0.16
            recipe.atmosphereGlow = 0.2
            recipe.roughness = 0.96
            recipe.featureAmount = 0.82
            return recipe
        case .molten:
            var recipe = preset(.rocky, seed: seed)
            recipe.archetype = archetype
            recipe.palette = .init(
                highlight: .init(red: 1, green: 0.86, blue: 0.26),
                primary: .init(red: 0.95, green: 0.19, blue: 0.025),
                shadow: .init(red: 0.035, green: 0.008, blue: 0.012),
                storm: .init(red: 1, green: 0.46, blue: 0.04),
                atmosphere: .init(red: 1, green: 0.19, blue: 0.03)
            )
            recipe.rotationSpeed = 0.045
            recipe.turbulence = 0.84
            recipe.detail = 0.9
            recipe.warpStrength = 0.58
            recipe.cloudCoverage = 0.18
            recipe.atmosphereDensity = 0.38
            recipe.atmosphereGlow = 0.74
            recipe.roughness = 0.88
            recipe.featureAmount = 0.88
            recipe.exposure = 1.18
            return recipe
        case .desert:
            var recipe = preset(.rocky, seed: seed)
            recipe.archetype = archetype
            recipe.palette = .init(
                highlight: .init(red: 0.98, green: 0.78, blue: 0.43),
                primary: .init(red: 0.68, green: 0.31, blue: 0.12),
                shadow: .init(red: 0.16, green: 0.07, blue: 0.045),
                storm: .init(red: 0.9, green: 0.57, blue: 0.26),
                atmosphere: .init(red: 0.96, green: 0.52, blue: 0.22)
            )
            recipe.turbulence = 0.58
            recipe.warpStrength = 0.42
            recipe.atmosphereDensity = 0.26
            recipe.featureAmount = 0.7
            return recipe
        case .toxic:
            var recipe = preset(.gasGiant, seed: seed)
            recipe.archetype = archetype
            recipe.palette = .init(
                highlight: .init(red: 0.83, green: 1, blue: 0.36),
                primary: .init(red: 0.2, green: 0.58, blue: 0.14),
                shadow: .init(red: 0.025, green: 0.12, blue: 0.055),
                storm: .init(red: 0.92, green: 0.78, blue: 0.16),
                atmosphere: .init(red: 0.46, green: 1, blue: 0.24)
            )
            recipe.bandCount = 9
            recipe.stormCount = 4
            recipe.atmosphereDensity = 0.78
            recipe.atmosphereGlow = 0.92
            return recipe
        case .lush:
            var recipe = preset(.ocean, seed: seed)
            recipe.archetype = archetype
            recipe.palette = .init(
                highlight: .init(red: 0.75, green: 0.96, blue: 0.84),
                primary: .init(red: 0.025, green: 0.29, blue: 0.34),
                shadow: .init(red: 0.012, green: 0.055, blue: 0.075),
                storm: .init(red: 0.12, green: 0.62, blue: 0.25),
                atmosphere: .init(red: 0.24, green: 0.88, blue: 0.72)
            )
            recipe.featureAmount = 0.84
            recipe.cloudCoverage = 0.42
            return recipe
        case .cloud:
            var recipe = preset(.gasGiant, seed: seed)
            recipe.archetype = archetype
            recipe.palette = .init(
                highlight: .init(red: 1, green: 0.95, blue: 0.86),
                primary: .init(red: 0.82, green: 0.68, blue: 0.55),
                shadow: .init(red: 0.22, green: 0.14, blue: 0.18),
                storm: .init(red: 0.98, green: 0.82, blue: 0.66),
                atmosphere: .init(red: 0.9, green: 0.76, blue: 0.68)
            )
            recipe.turbulence = 0.44
            recipe.bandSharpness = 0.22
            recipe.cloudCoverage = 1
            recipe.atmosphereDensity = 0.86
            return recipe
        }
    }

    public func randomized(seed: UInt32 = UInt32.random(in: 1...UInt32.max)) -> Self {
        var generator = MoonletPlanetRandomGenerator(seed: seed)
        var result = self
        result.seed = seed
        let baseHue = generator.nextDouble()
        let accentHue = (baseHue + generator.next(in: 0.08...0.24)).truncatingRemainder(dividingBy: 1)
        result.palette = .init(
            highlight: .init(hue: accentHue, saturation: generator.next(in: 0.28...0.62), brightness: generator.next(in: 0.88...1)),
            primary: .init(hue: baseHue, saturation: generator.next(in: 0.54...0.92), brightness: generator.next(in: 0.46...0.78)),
            shadow: .init(hue: (baseHue + generator.next(in: 0...0.08)).truncatingRemainder(dividingBy: 1), saturation: generator.next(in: 0.48...0.9), brightness: generator.next(in: 0.06...0.2)),
            storm: .init(hue: accentHue, saturation: generator.next(in: 0.52...0.94), brightness: generator.next(in: 0.72...1)),
            atmosphere: .init(hue: (baseHue + generator.next(in: 0.12...0.34)).truncatingRemainder(dividingBy: 1), saturation: generator.next(in: 0.48...0.88), brightness: generator.next(in: 0.74...1))
        )
        return result
    }

    static func solarPreset(_ preset: MoonletPlanetPreset) -> Self {
        switch preset {
        case .earth:
            var recipe = Self.preset(.ocean, seed: 39916801)
            recipe.palette = .init(
                highlight: .init(red: 0.86, green: 0.95, blue: 1),
                primary: .init(red: 0.02, green: 0.22, blue: 0.56),
                shadow: .init(red: 0.005, green: 0.025, blue: 0.11),
                storm: .init(red: 0.08, green: 0.48, blue: 0.18),
                atmosphere: .init(red: 0.22, green: 0.62, blue: 1)
            )
            recipe.featureAmount = 0.72
            recipe.cloudCoverage = 0.54
            // Earth's ice reaches roughly 60–70° in the north and covers a continent in
            // the south, which is what the asymmetry stands for. The tilt is 23.4°.
            recipe.iceCoverage = 0.19
            recipe.iceAltitude = 0.34
            recipe.polarAsymmetry = 0.16
            recipe.axialTilt = 0.409
            return recipe
        case .mars:
            var recipe = Self.preset(.desert, seed: 14479891)
            recipe.palette.primary = .init(red: 0.62, green: 0.18, blue: 0.07)
            recipe.palette.shadow = .init(red: 0.12, green: 0.035, blue: 0.025)
            recipe.atmosphereDensity = 0.11
            // Mars keeps small caps and a strong asymmetry: its southern cap survives the
            // summer and its northern one does not, because of orbital eccentricity.
            recipe.iceCoverage = 0.15
            recipe.iceAltitude = 0.18
            recipe.polarAsymmetry = 0.34
            recipe.axialTilt = 0.44
            recipe.palette.ice = .init(red: 0.96, green: 0.95, blue: 0.94)
            return recipe
        case .jupiter:
            return Self.preset(.gasGiant, seed: 125573)
        case .saturn:
            var recipe = Self.preset(.gasGiant, seed: 138759)
            recipe.palette = .init(
                highlight: .init(red: 1, green: 0.91, blue: 0.7),
                primary: .init(red: 0.76, green: 0.58, blue: 0.36),
                shadow: .init(red: 0.21, green: 0.14, blue: 0.11),
                storm: .init(red: 0.9, green: 0.76, blue: 0.54),
                atmosphere: .init(red: 0.82, green: 0.72, blue: 0.55)
            )
            recipe.turbulence = 0.34
            recipe.bandCount = 18
            recipe.stormCount = 1
            // Saturn's own rings: the full C-through-A span, opened to the angle it is
            // most often seen at, and the pale dirty ice they are actually made of.
            recipe.ringOpacity = 1
            recipe.axialTilt = 0.47
            recipe.ringInnerRadius = 1.235
            recipe.ringOuterRadius = 2.27
            recipe.ringDetail = 0.9
            recipe.palette.ring = .init(red: 0.93, green: 0.88, blue: 0.78)
            return recipe
        case .uranus:
            var recipe = Self.preset(.iceGiant, seed: 948291)
            recipe.palette.primary = .init(red: 0.3, green: 0.72, blue: 0.74)
            recipe.palette.shadow = .init(red: 0.04, green: 0.18, blue: 0.24)
            recipe.bandCount = 5
            recipe.stormCount = 1
            // Uranus is ringed too, but narrowly and darkly, and it is tipped on its side —
            // which is why its rings are drawn near face-on rather than near edge-on.
            recipe.ringOpacity = 0.42
            recipe.axialTilt = 1.32
            recipe.ringInnerRadius = 1.64
            recipe.ringOuterRadius = 2.0
            recipe.ringDetail = 0.5
            recipe.palette.ring = .init(red: 0.58, green: 0.62, blue: 0.66)
            return recipe
        case .neptune:
            var recipe = Self.preset(.iceGiant, seed: 614271)
            recipe.palette.primary = .init(red: 0.055, green: 0.23, blue: 0.72)
            recipe.palette.shadow = .init(red: 0.01, green: 0.025, blue: 0.18)
            recipe.palette.atmosphere = .init(red: 0.16, green: 0.46, blue: 1)
            recipe.stormCount = 4
            recipe.stormStrength = 0.8
            recipe.axialTilt = 0.49
            return recipe
        case .venus:
            var recipe = Self.preset(.cloud, seed: 871923)
            recipe.palette.primary = .init(red: 0.78, green: 0.53, blue: 0.22)
            recipe.palette.shadow = .init(red: 0.22, green: 0.12, blue: 0.055)
            recipe.atmosphereDensity = 0.96
            return recipe
        case .mercury:
            var recipe = Self.preset(.rocky, seed: 128667)
            recipe.palette.primary = .init(red: 0.42, green: 0.38, blue: 0.34)
            recipe.palette.highlight = .init(red: 0.76, green: 0.71, blue: 0.64)
            recipe.atmosphereDensity = 0
            recipe.atmosphereGlow = 0
            return recipe
        case .moon:
            var recipe = Self.preset(.rocky, seed: 240513)
            recipe.palette.primary = .init(red: 0.46, green: 0.46, blue: 0.47)
            recipe.palette.highlight = .init(red: 0.83, green: 0.82, blue: 0.78)
            recipe.palette.shadow = .init(red: 0.08, green: 0.08, blue: 0.095)
            recipe.atmosphereDensity = 0
            recipe.atmosphereGlow = 0
            return recipe
        case .pluto:
            var recipe = Self.preset(.frozen, seed: 551902)
            recipe.palette.primary = .init(red: 0.58, green: 0.45, blue: 0.38)
            recipe.palette.highlight = .init(red: 0.88, green: 0.76, blue: 0.67)
            recipe.atmosphereDensity = 0.03
            // Nitrogen ice over most of it, and Sputnik Planitia is nothing like symmetric.
            recipe.iceCoverage = 0.55
            recipe.iceAltitude = 0.12
            recipe.polarAsymmetry = -0.24
            return recipe
        case .custom:
            return Self.preset(.gasGiant)
        }
    }
}

private struct MoonletPlanetRandomGenerator {
    private var state: UInt64

    init(seed: UInt32) {
        state = UInt64(seed)
    }

    mutating func nextDouble() -> Double {
        state &+= 0x9E3779B97F4A7C15
        var value = state
        value = (value ^ (value >> 30)) &* 0xBF58476D1CE4E5B9
        value = (value ^ (value >> 27)) &* 0x94D049BB133111EB
        value ^= value >> 31
        return Double(value >> 11) / Double(1 << 53)
    }

    mutating func next(in range: ClosedRange<Double>) -> Double {
        range.lowerBound + nextDouble() * (range.upperBound - range.lowerBound)
    }
}

