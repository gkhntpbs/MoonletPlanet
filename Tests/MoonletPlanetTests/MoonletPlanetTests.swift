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

// MARK: - Life

/// A planet is sterile until somebody says otherwise, including one saved before life existed.
@Test func lifeIsOptOutOfNothing() throws {
    #expect(MoonletPlanetRecipe.preset(.ocean).life == .none)
    for archetype in MoonletPlanetArchetype.allCases {
        #expect(MoonletPlanetRecipe.preset(archetype).life == .none, "\(archetype) came pre-inhabited")
    }
    // The same legacy recipe the ring and ice tests use: no `life` key at all.
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
    #expect(recipe.life == .none, "a world saved before life must not be found inhabited")
    #expect(recipe.dayNightSpeed == 0, "and its day must not start moving")
    #expect(recipe.palette.life.opacity == 1)
    // The one station a spacefaring world flew before it was a setting.
    #expect(recipe.stationCount == 1)
    #expect(recipe.stationOrbitRadius == 1.085)
    #expect(recipe.stationSpeed == 0.55)
    #expect(recipe.stationInclination == 0.9)
    #expect(recipe.stationSize == 1)
}

/// The shader zooms out to hold whatever is drawn outside the disc, and a view that sizes
/// the body against a square has to know by how much — or the outermost thing is cut off.
@Test func drawnExtentCoversRingsAndStations() {
    var recipe = MoonletPlanetRecipe.preset(.ocean)
    #expect(recipe.drawnExtent == 1, "a bare planet fills its own disc")

    recipe.life = .advanced
    #expect(recipe.drawnExtent > recipe.stationOrbitRadius, "the station's orbit must fit, trail and glint included")
    recipe.stationCount = 0
    #expect(recipe.drawnExtent == 1, "no stations, nothing outside the disc")
    recipe.life = .interplanetary
    #expect(recipe.drawnExtent == 1.3, "traffic climbs past the limb even with no station")
    recipe.archetype = .gasGiant
    #expect(recipe.drawnExtent == 1, "nothing leaves a world with no ground")
    recipe.archetype = .ocean
    recipe.life = .advanced

    recipe.stationCount = 2
    recipe.life = .complex
    #expect(recipe.drawnExtent == 1, "stations are only drawn for a spacefaring world")

    recipe.hasRing = true
    #expect(recipe.drawnExtent == max(1, recipe.ringOuterRadius * 1.04))
    recipe.life = .advanced
    recipe.stationOrbitRadius = 3
    #expect(recipe.drawnExtent == 3.1, "whichever reaches further wins")
}

/// A star is drawn with its corona around it, and has nothing on it that needs ground.
@Test func starsShineAndHaveNoGround() {
    var recipe = MoonletPlanetRecipe.preset(.star)
    #expect(recipe.archetype == .star)
    #expect(!MoonletPlanetArchetype.star.hasGround, "nobody lives on a star")
    #expect(recipe.drawnExtent == 1.6, "the flames must fit inside the square")
    recipe.life = .interplanetary
    recipe.stationCount = 0
    #expect(recipe.drawnExtent == 1.6, "no traffic leaves a star")
    // The shader dispatches on the raw value, so it is part of the wire format.
    #expect(MoonletPlanetArchetype.star.rawValue == 10)
    #expect(MoonletPlanetPreset.sun.style?.recipe.archetype == .star)
    #expect(MoonletPlanetRecipe.preset(.star).luminosity == 0.5, "between fire and light")
}

/// A recipe saved before luminosity existed comes back at the middle of the range.
@Test func luminosityHasADefaultAndSurvivesARoundTrip() throws {
    var recipe = MoonletPlanetRecipe.preset(.star)
    recipe.luminosity = 0.9
    let data = try JSONEncoder().encode(recipe)
    #expect(try JSONDecoder().decode(MoonletPlanetRecipe.self, from: data).luminosity == 0.9)
    var object = try JSONSerialization.jsonObject(with: data) as! [String: Any]
    object.removeValue(forKey: "luminosity")
    let old = try JSONSerialization.data(withJSONObject: object)
    #expect(try JSONDecoder().decode(MoonletPlanetRecipe.self, from: old).luminosity == 0.5)
}

/// The levels are ordered, and each is the one before it plus something.
@Test func lifeLevelsAreOrdered() {
    #expect(MoonletPlanetLife.none < .simple)
    #expect(MoonletPlanetLife.simple < .complex)
    #expect(MoonletPlanetLife.complex < .advanced)
    #expect(MoonletPlanetLife.advanced < .interplanetary)

    // Nothing is lit until there is somebody to light it, and nothing is in orbit until they
    // can get there.
    #expect(MoonletPlanetLife.none.isLit == false)
    #expect(MoonletPlanetLife.simple.isLit == false, "simple life builds no cities")
    #expect(MoonletPlanetLife.complex.isLit)
    #expect(MoonletPlanetLife.advanced.isLit)

    #expect(MoonletPlanetLife.complex.hasOrbitalStation == false)
    #expect(MoonletPlanetLife.advanced.hasOrbitalStation)
    #expect(MoonletPlanetLife.interplanetary.hasOrbitalStation, "the station does not leave when the shuttles arrive")
    #expect(MoonletPlanetLife.advanced.hasTraffic == false)
    #expect(MoonletPlanetLife.interplanetary.hasTraffic)

    for level in MoonletPlanetLife.allCases { #expect(!level.title.isEmpty) }
}

/// The raw values are what the shader dispatches on, so they are a wire format.
@Test func lifeRawValuesAreStable() {
    #expect(MoonletPlanetLife.none.rawValue == 0)
    #expect(MoonletPlanetLife.simple.rawValue == 1)
    #expect(MoonletPlanetLife.complex.rawValue == 2)
    #expect(MoonletPlanetLife.advanced.rawValue == 3)
    #expect(MoonletPlanetLife.interplanetary.rawValue == 4)
}

/// Life and the day cycle survive being written down, like everything else.
@Test func lifeSurvivesACodableRoundTrip() throws {
    for level in MoonletPlanetLife.allCases {
        var recipe = MoonletPlanetRecipe.preset(.ocean)
        recipe.life = level
        recipe.dayNightSpeed = 0.37
        recipe.stationCount = 3
        recipe.stationOrbitRadius = 1.3
        recipe.stationSpeed = 0.2
        recipe.stationInclination = 0.4
        recipe.stationSize = 1.6
        recipe.palette.life = MoonletColor(red: 0.4, green: 0.1, blue: 0.5)
        let decoded = try JSONDecoder().decode(
            MoonletPlanetRecipe.self,
            from: JSONEncoder().encode(recipe)
        )
        #expect(decoded == recipe, "\(level) did not survive the round trip")
    }
}

// MARK: - Systems

/// The light is the direction to the star, in the shader's own light space.
@Test func aPlanetInASystemIsLitFromItsStar() throws {
    func light(_ r: MoonletPlanetRecipe) -> (x: Double, y: Double, z: Double) {
        (cos(r.lightElevation) * cos(r.lightAzimuth), sin(r.lightElevation), cos(r.lightElevation) * sin(r.lightAzimuth))
    }
    var system = MoonletPlanetSystem(viewElevation: 0)
    system.bodies = [.init(recipe: .preset(.rocky), distance: 3, phase: 0, speed: 0)]
    // To the star's right, seen edge-on: lit from the left.
    var planet = try #require(system.layout(at: 0).first { $0.index == 0 })
    var l = light(planet.recipe)
    #expect(abs(l.x + 1) < 1e-9 && abs(l.y) < 1e-9 && abs(l.z) < 1e-9)
    #expect(planet.x == 3)

    // In front of the star: lit from behind, so the camera sees its night side.
    system.bodies[0].phase = -.pi / 2
    planet = try #require(system.layout(at: 0).first { $0.index == 0 })
    l = light(planet.recipe)
    #expect(abs(l.z + 1) < 1e-9, "lit from behind")
    #expect(planet.depth > 0, "and in front of the star")

    // Looking down on the plane, a world behind the star is above it on screen and lit from
    // below — which in the shader's space, whose y runs down the screen, is +y.
    system.viewElevation = 0.5
    system.bodies[0].phase = .pi / 2
    planet = try #require(system.layout(at: 0).first { $0.index == 0 })
    #expect(planet.y > 0)
    #expect(light(planet.recipe).y > 0)
}

/// Moving round the orbit with time, and drawn back to front.
@Test func aSystemMovesAndDrawsBackToFront() {
    var system = MoonletPlanetSystem.example
    for i in system.bodies.indices { system.bodies[i].speed = 0.5 }
    let a = system.layout(at: 0), b = system.layout(at: 1)
    #expect(a.count == system.bodies.count + 1, "every planet and the star")
    #expect(a.map(\.depth) == a.map(\.depth).sorted(), "back to front")
    #expect(a.first { $0.index == 0 }!.x != b.first { $0.index == 0 }!.x)
    // The planets' own recipes are not touched; the light lives on the copies.
    #expect(system.bodies[0].recipe == MoonletPlanetPreset.mercury.style!.recipe)
    for p in a where p.index != nil { #expect(p.recipe.dayNightSpeed == 0) }
}

/// The view has to hold the furthest thing drawn, rings and all, and the star's flames.
@Test func aSystemsExtentHoldsEverything() {
    var system = MoonletPlanetSystem()
    #expect(system.extent == system.starRadius * system.star.drawnExtent)
    system.bodies = [.init(recipe: MoonletPlanetPreset.saturn.style!.recipe, radius: 0.5, distance: 5)]
    #expect(system.extent == 5 + 0.5 * MoonletPlanetPreset.saturn.style!.recipe.drawnExtent)
    for p in system.layout(at: 3) {
        #expect(abs(p.x) + p.radius * p.recipe.drawnExtent <= system.extent + 1e-9)
        #expect(abs(p.y) + p.radius * p.recipe.drawnExtent <= system.extent + 1e-9)
    }
}

/// A white light is the light every planet had before, and a tinted one is the star's.
@Test func theLightTakesTheStarsColourOnlyWhenAsked() throws {
    #expect(MoonletPlanetRecipe.preset(.ocean).palette.light == MoonletColor(red: 1, green: 1, blue: 1))
    var system = MoonletPlanetSystem()
    system.lightTint = 0
    #expect(system.lightColor == MoonletColor(red: 1, green: 1, blue: 1))
    system.lightTint = 1
    let c = system.lightColor
    #expect(max(c.red, c.green, c.blue) == 1, "a colour, not a brightness")
    #expect(c.blue < c.red, "an orange star lights warm")

    // A palette saved before light existed is lit white.
    let data = try JSONEncoder().encode(MoonletPlanetRecipe.preset(.ocean).palette)
    var object = try JSONSerialization.jsonObject(with: data) as! [String: Any]
    object.removeValue(forKey: "light")
    let old = try JSONSerialization.data(withJSONObject: object)
    #expect(try JSONDecoder().decode(MoonletPlanetPalette.self, from: old).light == MoonletColor(red: 1, green: 1, blue: 1))
}

@Test func aSystemSurvivesACodableRoundTrip() throws {
    let system = MoonletPlanetSystem.example
    let decoded = try JSONDecoder().decode(MoonletPlanetSystem.self, from: JSONEncoder().encode(system))
    #expect(decoded == system)
}

/// Dragging a planet to a point puts it at that point, whenever the drag happens.
@Test func aPlanetDraggedToAPointIsThere() throws {
    var system = MoonletPlanetSystem.example
    system.viewElevation = 0.6
    system.place(1, atX: -2.5, y: 0.8, time: 7)
    let p = try #require(system.layout(at: 7).first { $0.index == 1 })
    #expect(abs(p.x + 2.5) < 1e-9 && abs(p.y - 0.8) < 1e-9)

    // Edge-on there is no depth on screen; it slides along its orbit and keeps its distance.
    system.viewElevation = 0
    let distance = system.bodies[1].distance
    system.place(1, atX: 1, y: 0, time: 7)
    let q = try #require(system.layout(at: 7).first { $0.index == 1 })
    #expect(abs(q.x - 1) < 1e-9)
    #expect(system.bodies[1].distance == distance)
}

/// Walking the camera round the system half a turn puts every planet on the other side.
@Test func turningTheCameraTurnsTheSystem() throws {
    var system = MoonletPlanetSystem.example
    let before = system.layout(at: 2)
    system.viewAzimuth = .pi
    let after = system.layout(at: 2)
    for i in system.bodies.indices {
        let a = try #require(before.first { $0.index == i }), b = try #require(after.first { $0.index == i })
        #expect(abs(a.x + b.x) < 1e-9 && abs(a.depth + b.depth) < 1e-9)
    }
    // And a planet dragged with the camera turned lands where it was dropped.
    system.viewAzimuth = 1.1
    system.place(0, atX: 1.5, y: 0.4, time: 2)
    let p = try #require(system.layout(at: 2).first { $0.index == 0 })
    #expect(abs(p.x - 1.5) < 1e-9 && abs(p.y - 0.4) < 1e-9)
}

/// An orbit line goes through the planet, wherever the camera is.
@Test func anOrbitLinePassesThroughItsPlanet() throws {
    var system = MoonletPlanetSystem.example
    system.viewElevation = 0.7
    let points = system.orbitPoints(1, count: 3600)
    let p = try #require(system.layout(at: 5).first { $0.index == 1 })
    let nearest = points.map { hypot($0.x - p.x, $0.y - p.y) }.min()!
    #expect(nearest < 0.01)
    // A system saved before the camera turned comes back facing forward, without lines.
    var object = try JSONSerialization.jsonObject(with: JSONEncoder().encode(system)) as! [String: Any]
    object.removeValue(forKey: "viewAzimuth"); object.removeValue(forKey: "showsOrbits")
    let old = try JSONDecoder().decode(MoonletPlanetSystem.self, from: JSONSerialization.data(withJSONObject: object))
    #expect(old.viewAzimuth == 0 && !old.showsOrbits)
}

/// With perspective, nearer is bigger, poles tip with the camera, and everything still fits.
@Test func aSystemInPerspectiveIsSeenByARealCamera() throws {
    var flat = MoonletPlanetSystem.example
    flat.viewElevation = 0.5
    for i in flat.bodies.indices { flat.bodies[i].radius = 0.3 }
    var deep = flat
    deep.perspective = 1
    let near = try #require(deep.layout(at: 0).max { $0.depth < $1.depth })
    let far = try #require(deep.layout(at: 0).min { $0.depth < $1.depth })
    #expect(near.radius > 0.3 && far.radius < 0.3, "nearer is bigger and further is smaller")
    #expect(flat.layout(at: 0).first { $0.index == 2 }!.recipe.axialTilt == flat.bodies[2].recipe.axialTilt, "flat changes nothing")
    for t in stride(from: 0.0, through: 60, by: 3) {
        for p in deep.layout(at: t) {
            #expect(max(abs(p.x), abs(p.y)) + p.radius * p.recipe.drawnExtent <= deep.extent + 1e-9)
        }
    }
    // Dragging in perspective still puts it under the pointer, closely.
    deep.place(1, atX: -2, y: 0.9, time: 0)
    let moved = try #require(deep.layout(at: 0).first { $0.index == 1 })
    #expect(hypot(moved.x + 2, moved.y - 0.9) < 0.01)
}

/// Walking the camera round a system must not turn anything in it: every body's pole and
/// its prime meridian, read back out of what the shader is handed, point the same way in
/// the system from every angle, and the light still comes from the star.
@Test func aRealCameraLeavesEveryBodyWhereItIs() throws {
    var system = MoonletPlanetSystem.example
    system.perspective = 0.8
    system.bodies[1].recipe.axialTilt = 0.41
    system.bodies[1].recipe.rotationPhase = 1.3
    func world(_ p: MoonletPlanetSystem.Placement, in s: MoonletPlanetSystem) -> (pole: (Double, Double, Double), meridian: (Double, Double, Double)) {
        // Rebuilt in the shader's space (y down the screen) and rolled there, as the shader does.
        let t = p.recipe.axialTilt, f = p.recipe.rotationPhase, r = p.roll
        let roll = { (v: (Double, Double, Double)) in (v.0 * cos(r) - v.1 * sin(r), v.0 * sin(r) + v.1 * cos(r), v.2) }
        let out = { (v: (Double, Double, Double)) in s.fromView(MoonletPlanetSystem.toShader(roll(v))) }
        let pole = out((0, cos(t), sin(t)))
        let meridian = out((cos(f), -sin(f) * sin(t), sin(f) * cos(t)))
        return ((pole.x, pole.y, pole.z), (meridian.x, meridian.y, meridian.z))
    }
    let close = { (a: (Double, Double, Double), b: (Double, Double, Double)) in abs(a.0 - b.0) + abs(a.1 - b.1) + abs(a.2 - b.2) < 1e-9 }
    for index in [nil, 0, 1, 2] as [Int?] {
        let original = index.map { system.bodies[$0].recipe } ?? system.star
        let expected = MoonletPlanetSystem.frame(of: original)
        for azimuth in stride(from: -3.0, through: 3.0, by: 0.75) {
            for elevation in [-1.2, -0.4, 0.0, 0.35, 0.9, 1.5] {
                system.viewAzimuth = azimuth
                system.viewElevation = elevation
                let layout = system.layout(at: 0)
                let p = try #require(layout.first { $0.index == index })
                let w = world(p, in: system)
                #expect(close(w.pole, (expected.pole.x, expected.pole.y, expected.pole.z)), "pole of \(String(describing: index)) at \(azimuth), \(elevation)")
                #expect(close(w.meridian, (expected.meridian.x, expected.meridian.y, expected.meridian.z)), "meridian of \(String(describing: index)) at \(azimuth), \(elevation)")
                if let index {
                    // The light, rolled back and out of the camera, points at the star.
                    let r = p.recipe, roll = p.roll
                    let l = (cos(r.lightElevation) * cos(r.lightAzimuth), sin(r.lightElevation), cos(r.lightElevation) * sin(r.lightAzimuth))
                    let lw = system.fromView(MoonletPlanetSystem.toShader((l.0 * cos(roll) - l.1 * sin(roll), l.0 * sin(roll) + l.1 * cos(roll), l.2)))
                    let body = system.bodies[index]
                    let n = (-cos(body.phase), 0.0, -sin(body.phase))
                    #expect(close((lw.x, lw.y, lw.z), n), "light on \(index) at \(azimuth), \(elevation)")
                }
            }
        }
    }
}

/// The ground truth, in pixels rather than in the conventions the code assumes: a world on
/// screen below its star is lit on its top half, one to its left on its right half, and a
/// ring turned by `roll` turns the way Core Graphics turns things.
@MainActor @Test func aPlanetIsLitOnTheSideFacingItsStarInPixels() throws {
    guard MoonletPlanetRendering.isMetalAvailable else { return }
    func sample(_ recipe: MoonletPlanetRecipe) -> (top: Double, bottom: Double, left: Double, right: Double) {
        let img = MoonletPlanetSnapshotRenderer.image(recipe: recipe, size: 120, time: 0)!
        let data = img.dataProvider!.data! as Data
        func at(_ x: Int, _ y: Int) -> Double {
            let i = y * img.bytesPerRow + x * 4
            return Double(data[i]) + Double(data[i + 1]) + Double(data[i + 2])
        }
        // Image rows run top to bottom.
        return (at(60, 22), at(60, 98), at(22, 60), at(98, 60))
    }
    for perspective in [0.0, 0.8] {
        var system = MoonletPlanetSystem.example
        system.perspective = perspective
        system.bodies[0].recipe.atmosphereDensity = 0
        system.bodies[0].speed = 0
        // Seen from high above, in front of the star: below it on screen.
        system.viewElevation = 1.2
        system.bodies[0].phase = -.pi / 2
        var p = try #require(system.layout(at: 0).first { $0.index == 0 })
        #expect(p.y < 0)
        var b = sample(p.recipe)
        #expect(b.top > b.bottom * 2, "lit from the star above it, perspective \(perspective)")
        // Edge-on, to the star's left: lit on its right.
        system.viewElevation = 0
        system.bodies[0].phase = .pi
        p = try #require(system.layout(at: 0).first { $0.index == 0 })
        b = sample(p.recipe)
        #expect(b.right > b.left * 2, "lit from the star to its right, perspective \(perspective)")
    }
}

/// Every setting added to a system defaults to drawing what was drawn before it, and a
/// system saved without them decodes to exactly the system it was.
@Test func newSystemSettingsDefaultToTheOldDrawing() throws {
    var system = MoonletPlanetSystem.example
    system.perspective = 0.6
    var object = try JSONSerialization.jsonObject(with: JSONEncoder().encode(system)) as! [String: Any]
    for key in ["zoom", "lightFalloff", "orbitSpeed", "orbitStyle", "sky"] { object.removeValue(forKey: key) }
    var bodies = object["bodies"] as! [[String: Any]]
    for i in bodies.indices { bodies[i].removeValue(forKey: "inclination"); bodies[i].removeValue(forKey: "node") }
    object["bodies"] = bodies
    let old = try JSONDecoder().decode(MoonletPlanetSystem.self, from: JSONSerialization.data(withJSONObject: object))
    #expect(old == system)
    #expect(old.zoom == 1 && old.lightFalloff == 0 && old.orbitSpeed == 1 && !old.sky.isVisible)
}

/// An inclined orbit leaves the plane, still goes through its planet, and a drag along it lands.
@Test func anInclinedOrbitLeavesThePlane() throws {
    var system = MoonletPlanetSystem.example
    system.viewElevation = 0
    system.bodies[1].inclination = 0.6
    system.bodies[1].node = 0.3
    let points = system.orbitPoints(1, count: 720)
    #expect(points.map(\.y).max()! > 1, "edge-on, an inclined orbit is not a line")
    let p = try #require(system.layout(at: 4).first { $0.index == 1 })
    #expect(points.map { hypot($0.x - p.x, $0.y - p.y) }.min()! < 0.02)
    // Dragged to a point on its own orbit, it goes there.
    let target = points[200]
    system.place(1, atX: target.x, y: target.y, time: 4)
    let q = try #require(system.layout(at: 4).first { $0.index == 1 })
    #expect(hypot(q.x - target.x, q.y - target.y) < 1e-3)
    // And it is still lit from its star.
    #expect(system.bodies[1].distance == MoonletPlanetSystem.example.bodies[1].distance)
}

/// Zoom shows less of the system, larger; falloff dims the outer worlds; the orbit speed
/// multiplies every orbit.
@Test func zoomFalloffAndOrbitSpeedDoWhatTheySay() throws {
    var system = MoonletPlanetSystem.example
    let wide = system.extent
    system.zoom = 2
    #expect(abs(system.extent - wide / 2) < 1e-9)
    system.lightFalloff = 1
    let layout = system.layout(at: 0)
    let inner = try #require(layout.first { $0.index == 0 }), outer = try #require(layout.first { $0.index == 2 })
    #expect(inner.recipe.exposure > system.bodies[0].recipe.exposure, "closer than three star radii is brighter")
    #expect(outer.recipe.exposure < system.bodies[2].recipe.exposure, "further is dimmer")
    system.orbitSpeed = 0
    #expect(system.layout(at: 0).map(\.x) == system.layout(at: 50).map(\.x), "stopped")
}

/// The sky: the default is the sky as it was drawn, a seed is another sky, a band gathers
/// the stars, and brightness and size scale what they say.
@Test func theSkyIsSettable() {
    var system = MoonletPlanetSystem.example
    let base = system.skyStars(width: 400, height: 400)
    #expect(!base.isEmpty)
    system.sky.seed = 7
    #expect(system.skyStars(width: 400, height: 400) != base, "another seed, another sky")
    system.sky.seed = 0
    system.sky.brightness = 0.5
    system.sky.starSize = 2
    let dim = system.skyStars(width: 400, height: 400)
    #expect(dim.count == base.count)
    for (a, b) in zip(base, dim) {
        #expect(abs(b.alpha - a.alpha * 0.5) < 1e-9)
        #expect(abs(b.radius - a.radius * 2) < 1e-9)
    }
    // A full band puts every star within a thin belt of its great circle.
    system.sky = .init(bandStrength: 1, bandTilt: 0)
    for star in system.sky.directions() { #expect(abs(star.y) <= 0.111) }
    system.sky.starCount = 50
    #expect(system.sky.directions().count == 50)
}
