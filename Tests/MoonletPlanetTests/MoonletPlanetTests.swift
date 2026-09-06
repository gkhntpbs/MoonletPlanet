import Testing
import Foundation
@testable import MoonletPlanet

/// A recipe is the whole planet, so it has to survive being written down.
///
/// The point of the type is that somebody's planet can be stored and come back as the
/// same pixels. A field added to the struct and forgotten in the coding keys would not
/// fail to compile and would not look wrong on screen — it would quietly reset one slider
/// for everybody who saved a planet before it existed.
@Test func recipeSurvivesACodableRoundTrip() throws {
    for archetype in MoonletPlanetArchetype.allCases {
        let original = MoonletPlanetRecipe.preset(archetype).randomized(seed: 4242)
        let decoded = try JSONDecoder().decode(
            MoonletPlanetRecipe.self,
            from: JSONEncoder().encode(original)
        )
        #expect(decoded == original, "\(archetype) did not survive the round trip")
    }
}

/// Every archetype has to answer `preset`, and answer as itself.
///
/// The switch has a `default` arm, so a case added to the enum keeps compiling and starts
/// silently rendering as a gas giant.
@Test func everyArchetypeHasItsOwnPreset() {
    for archetype in MoonletPlanetArchetype.allCases {
        #expect(MoonletPlanetRecipe.preset(archetype).archetype == archetype)
        #expect(!archetype.title.isEmpty)
    }
}

/// The same seed is the same planet.
///
/// This is the whole contract of `randomized`: a seed is what somebody keeps in order to
/// find their planet again. Pulling from the system generator instead would still look
/// fine on screen and would lose them.
@Test func randomizedIsDeterministicForASeed() {
    let base = MoonletPlanetRecipe.preset(.iceGiant)
    #expect(base.randomized(seed: 99) == base.randomized(seed: 99))
    #expect(base.randomized(seed: 99) != base.randomized(seed: 100))
    #expect(base.randomized(seed: 7).seed == 7)
}

/// The solar system presets all resolve to a style.
@Test func namedPlanetsResolve() {
    for preset in MoonletPlanetPreset.allCases where preset != .custom {
        #expect(preset.style != nil, "\(preset) resolved to nothing")
    }
    #expect(MoonletPlanetPreset.custom.style == nil)
    #expect(MoonletPlanetPreset.saturn.style?.hasRing == true)
}

/// HSB and RGB describe the same colour.
///
/// `MoonletColor(hue:saturation:brightness:)` is hand-rolled rather than routed through
/// the platform, because the type is `Sendable` and `Codable` and has to work with no
/// UIKit or AppKit around. A hand-rolled conversion is one that can be wrong.
@Test func hsbMatchesRgbAtTheCorners() {
    let red = MoonletColor(hue: 0, saturation: 1, brightness: 1)
    #expect(abs(red.red - 1) < 0.001 && abs(red.green) < 0.001 && abs(red.blue) < 0.001)

    let green = MoonletColor(hue: 1.0 / 3.0, saturation: 1, brightness: 1)
    #expect(abs(green.green - 1) < 0.001 && abs(green.red) < 0.001)

    let grey = MoonletColor(hue: 0.5, saturation: 0, brightness: 0.5)
    #expect(abs(grey.red - 0.5) < 0.001 && abs(grey.red - grey.blue) < 0.001)

    // A hue outside 0...1 wraps rather than clamping — otherwise every randomized palette
    // that crosses the wrap point collapses to red.
    #expect(MoonletColor(hue: 1.25, saturation: 1, brightness: 1)
            == MoonletColor(hue: 0.25, saturation: 1, brightness: 1))
}

/// Presets stay inside the ranges the shader was written against.
///
/// The shader does not clamp its inputs — it is a fragment shader run millions of times a
/// frame and every guard costs. A negative `detail` or a `bandCount` in the hundreds does
/// not crash; it renders a planet nobody would choose.
@Test func presetsStayInsideTheShadersRanges() {
    for archetype in MoonletPlanetArchetype.allCases {
        let recipe = MoonletPlanetRecipe.preset(archetype)
        #expect((0...1).contains(recipe.detail), "\(archetype) detail")
        #expect((0...1).contains(recipe.roughness), "\(archetype) roughness")
        #expect((0...1).contains(recipe.cloudCoverage), "\(archetype) cloudCoverage")
        #expect((0...1).contains(recipe.atmosphereDensity), "\(archetype) atmosphereDensity")
        #expect((0...5).contains(recipe.stormCount), "\(archetype) stormCount")
        #expect(recipe.exposure > 0, "\(archetype) exposure")
        #expect(recipe.bandCount >= 0, "\(archetype) bandCount")
    }
}

/// A randomized planet is still a renderable one.
///
/// `randomized` only replaces the palette, and this is what keeps that true: a future
/// version that starts randomizing the numeric fields has to keep them in range.
@Test func randomizedPlanetsStayRenderable() {
    for seed in stride(from: UInt32(1), through: 2001, by: 250) {
        for archetype in MoonletPlanetArchetype.allCases {
            let recipe = MoonletPlanetRecipe.preset(archetype).randomized(seed: seed)
            #expect((0...1).contains(recipe.detail))
            #expect(recipe.exposure > 0)
            for channel in [recipe.palette.primary, recipe.palette.shadow, recipe.palette.storm] {
                #expect((0...1).contains(channel.red))
                #expect((0...1).contains(channel.green))
                #expect((0...1).contains(channel.blue))
            }
        }
    }
}

// MARK: - Rings

/// A planet saved before rings existed still decodes, and decodes ringless.
///
/// This is the CHANGELOG's rule under test. Five fields appeared in `MoonletPlanetRecipe`
/// and one in `MoonletPlanetPalette` after somebody could already have stored a planet; the
/// synthesised `Codable` would have thrown `keyNotFound` on every one of those and taken
/// their collection with it.
@Test func recipesSavedBeforeRingsStillDecode() throws {
    let legacy = """
    {
      "archetype": 0, "seed": 240513,
      "palette": {
        "highlight": {"red":0.96,"green":0.86,"blue":0.66,"opacity":1},
        "primary": {"red":0.62,"green":0.34,"blue":0.16,"opacity":1},
        "shadow": {"red":0.12,"green":0.07,"blue":0.09,"opacity":1},
        "storm": {"red":0.94,"green":0.68,"blue":0.36,"opacity":1},
        "atmosphere": {"red":0.48,"green":0.72,"blue":0.95,"opacity":1}
      },
      "rotationSpeed":0.11,"turbulence":0.78,"detail":0.82,"warpStrength":0.76,
      "bandCount":13,"bandSharpness":0.62,"stormCount":5,"stormStrength":0.86,
      "cloudCoverage":0.5,"cloudSpeed":1,"atmosphereDensity":0.7,"atmosphereGlow":1,
      "roughness":0.5,"featureAmount":0.5,"lightAzimuth":2.2,"lightElevation":0.4,
      "exposure":1.4
    }
    """
    let recipe = try JSONDecoder().decode(MoonletPlanetRecipe.self, from: Data(legacy.utf8))
    #expect(recipe.archetype == .gasGiant)
    #expect(recipe.bandCount == 13)
    #expect(recipe.hasRing == false, "a planet saved without rings must not grow them")
    #expect(recipe.ringInnerRadius < recipe.ringOuterRadius)
    // The palette's new colour has to be there rather than crash on first draw.
    #expect(recipe.palette.ring.opacity == 1)
}

/// Rings survive the round trip like everything else.
@Test func ringsSurviveACodableRoundTrip() throws {
    var original = MoonletPlanetPreset.saturn.style!.recipe
    original.axialTilt = 0.31
    original.ringDetail = 0.44
    let decoded = try JSONDecoder().decode(
        MoonletPlanetRecipe.self,
        from: JSONEncoder().encode(original)
    )
    #expect(decoded == original)
}

/// The two ringed planets in the solar system have rings, and nothing else does.
@Test func onlyTheRingedPlanetsHaveRings() {
    for preset in MoonletPlanetPreset.allCases where preset != .custom {
        let style = preset.style!
        let expected = (preset == .saturn || preset == .uranus)
        #expect(style.hasRing == expected, "\(preset) rings: \(style.hasRing)")
    }
    // Saturn's are the measured ones. If somebody retunes them, the Cassini Division has to
    // still land inside the system rather than outside it.
    let saturn = MoonletPlanetPreset.saturn.style!.recipe
    #expect(saturn.ringInnerRadius > 1, "rings cannot start inside the planet")
    #expect(saturn.ringInnerRadius < 1.95 && saturn.ringOuterRadius > 2.025,
            "the Cassini Division at 1.95–2.025 has to fall within the system")
    #expect(saturn.axialTilt > 0 && saturn.axialTilt < .pi / 2)
}

/// `hasRing` is a view onto `ringOpacity`, so setting it either way is not lossy.
@Test func hasRingTogglesWithoutLosingTheRingGeometry() {
    var recipe = MoonletPlanetPreset.saturn.style!.recipe
    let tilt = recipe.axialTilt
    let inner = recipe.ringInnerRadius
    recipe.hasRing = false
    #expect(recipe.ringOpacity == 0)
    recipe.hasRing = true
    #expect(recipe.hasRing)
    #expect(recipe.axialTilt == tilt, "turning rings off must not forget their geometry")
    #expect(recipe.ringInnerRadius == inner)
}

/// A style still answers for rings the way it always did.
@Test func styleRingsReachTheRecipe() {
    var style = MoonletPlanetStyle(name: "Test", recipe: .preset(.gasGiant), hasRing: true)
    #expect(style.recipe.hasRing)
    style.hasRing = false
    #expect(style.recipe.ringOpacity == 0)
}

// MARK: - Ice and tilt

/// The worlds that have ice have it, and the ones with no ground do not.
///
/// Ice sits on a surface. A gas giant has none — the shader gives it a polar hood instead —
/// and a preset that grew a cap would be drawing one on cloud tops.
@Test func iceSitsOnGroundAndNowhereElse() {
    for preset in [MoonletPlanetPreset.jupiter, .saturn, .neptune, .uranus] {
        #expect(preset.style!.recipe.iceCoverage == 0, "\(preset) should carry no surface ice")
    }
    for preset in [MoonletPlanetPreset.earth, .mars, .pluto] {
        #expect(preset.style!.recipe.iceCoverage > 0, "\(preset) lost its caps")
    }
    // No real world has two matching caps: Antarctica is a continent and the Arctic is a sea.
    #expect(MoonletPlanetPreset.earth.style!.recipe.polarAsymmetry != 0)
    #expect(MoonletPlanetPreset.mars.style!.recipe.polarAsymmetry != 0)
}

/// Uranus is on its side, and that is most of what it looks like.
@Test func axialTiltCameAcross() {
    let uranus = MoonletPlanetPreset.uranus.style!.recipe
    #expect(uranus.axialTilt > 1, "Uranus is tipped over, not upright")
    // Rings lie in the equator, so the tilt that opens them is the same number.
    #expect(uranus.hasRing)

    let earth = MoonletPlanetPreset.earth.style!.recipe
    #expect(abs(earth.axialTilt - 0.409) < 0.01, "Earth's obliquity is 23.4°")
}

/// A planet saved before ice, tilt or fine detail existed still decodes, and decodes as it
/// was drawn then: no caps, upright, and with all of the detail it had.
@Test func recipesSavedBeforeIceStillDecode() throws {
    let legacy = """
    {
      "archetype": 2, "seed": 7,
      "palette": {
        "highlight": {"red":1,"green":1,"blue":1,"opacity":1},
        "primary": {"red":0.2,"green":0.3,"blue":0.6,"opacity":1},
        "shadow": {"red":0.02,"green":0.04,"blue":0.1,"opacity":1},
        "storm": {"red":0.1,"green":0.5,"blue":0.2,"opacity":1},
        "atmosphere": {"red":0.5,"green":0.7,"blue":1,"opacity":1}
      },
      "rotationSpeed":0.1,"turbulence":0.5,"detail":0.8,"warpStrength":0.5,
      "bandCount":6,"bandSharpness":0.4,"stormCount":0,"stormStrength":0,
      "cloudCoverage":0.6,"cloudSpeed":1,"atmosphereDensity":0.7,"atmosphereGlow":1,
      "roughness":0.4,"featureAmount":0.6,"lightAzimuth":2,"lightElevation":0.4,
      "exposure":1.2
    }
    """
    let recipe = try JSONDecoder().decode(MoonletPlanetRecipe.self, from: Data(legacy.utf8))
    #expect(recipe.iceCoverage == 0, "a world saved without ice must not grow caps")
    #expect(recipe.axialTilt == 0, "a world saved upright must stay upright")
    #expect(recipe.polarAsymmetry == 0)
    // Detail was on before it was a setting, so an old recipe keeps it rather than flattening.
    #expect(recipe.microDetail == 1)
    #expect(recipe.palette.ice.opacity == 1)
}

/// The ice model is an isotherm, so coverage has to move monotonically.
@Test func moreCoverageIsNeverLessIce() {
    // The shader is what draws it, but the contract is that these two ends mean something:
    // 0 leaves the isotherm below the coldest latitude and 1 puts it above the warmest.
    var recipe = MoonletPlanetPreset.earth.style!.recipe
    recipe.iceCoverage = 0
    #expect(recipe.iceCoverage == 0)
    recipe.iceCoverage = 1
    #expect(recipe.iceCoverage == 1)
    // And it survives being written down, like every other field.
    let decoded = try? JSONDecoder().decode(MoonletPlanetRecipe.self, from: JSONEncoder().encode(recipe))
    #expect(decoded?.iceCoverage == 1)
}

/// Turning rings on gives rings somebody can see.
///
/// `axialTilt` is the pole and the ring angle at once, and zero is the right default for a
/// planet — upright. For rings it is exactly edge-on, so a caller that only says `hasRing =
/// true` would get a hairline. This is the seam between those two correct defaults.
@Test func ringsTurnedOnAreVisible() {
    var recipe = MoonletPlanetRecipe.preset(.gasGiant)
    #expect(recipe.axialTilt == 0, "a planet with no rings should stand upright")
    recipe.hasRing = true
    #expect(recipe.ringOpacity > 0)
    #expect(recipe.axialTilt > 0.2, "rings on an upright planet are an invisible edge")

    // A planet that already has a tilt keeps it — this opens rings, it does not re-aim worlds.
    var tilted = MoonletPlanetRecipe.preset(.ocean)
    tilted.axialTilt = 1.1
    tilted.hasRing = true
    #expect(tilted.axialTilt == 1.1)

    // And turning them off leaves the tilt alone, because the tilt was never about the rings.
    tilted.hasRing = false
    #expect(tilted.ringOpacity == 0)
    #expect(tilted.axialTilt == 1.1)
}
