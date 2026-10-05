import Foundation

/// A star and the worlds around it, each lit from wherever the star actually is.
///
/// A planet on its own is lit by `lightAzimuth` and `lightElevation`, two numbers somebody
/// chose. In a system nobody chooses them: they are the direction from the planet to the
/// star, worked out from where the two are, so a world passing in front of its star shows
/// its night side and one beside it is half lit. The planets' own recipes are never
/// changed — `layout(at:)` hands back lit copies — so a planet taken out of a system is the
/// same planet it was before it went in.
///
/// Everything is measured in one unit, the system's own: the star's radius, each planet's
/// radius and each orbit's distance. The camera looks at the orbital plane from
/// `viewElevation` above it.
///
/// Every setting added after the first systems has a default that draws exactly what was
/// drawn before it, and decodes to that default when it is missing.
public struct MoonletPlanetSystem: Codable, Equatable, Hashable, Sendable {
    public var star: MoonletPlanetRecipe
    /// The star's radius, in system units.
    public var starRadius: Double
    public var bodies: [MoonletPlanetOrbit]

    // MARK: Camera

    /// How far above the orbital plane the camera sits, in radians. 0 is edge-on, where
    /// planets pass in front of and behind the star; `.pi / 2` looks straight down on it,
    /// and below zero looks up at it from underneath.
    public var viewElevation: Double
    /// Where round the system the camera is, in radians. Turning it walks the camera round
    /// the star, so every world is seen from another side.
    public var viewAzimuth: Double
    /// How much the camera sees in depth. 0 is flat — no perspective, and every planet
    /// keeps its own pole whatever the camera does. Above zero it is a real camera: nearer
    /// worlds are larger and further ones smaller, orbits narrow towards the back, and every
    /// body keeps its pole, rings and face fixed in the system as the camera moves.
    public var perspective: Double
    /// How close the view is. 1 fits the whole system; 2 shows the middle half of it, larger.
    public var zoom: Double

    // MARK: Light and time

    /// How much the planets take the star's colour. 0 is white light; 1 is the star's own.
    public var lightTint: Double
    /// How much dimmer a world further out is. 0 lights every world the same, as a system
    /// always did; 1 is the inverse-square law, measured from three star radii out.
    public var lightFalloff: Double
    /// A multiplier on every orbit's speed. 0 stops them all where they are.
    public var orbitSpeed: Double

    // MARK: Drawing

    /// Whether a view draws each planet's orbit as a faint line.
    public var showsOrbits: Bool
    /// How the orbit lines look.
    public var orbitStyle: MoonletOrbitStyle
    /// The sky behind the system.
    public var sky: MoonletSky

    public init(
        star: MoonletPlanetRecipe = .preset(.star),
        starRadius: Double = 1,
        bodies: [MoonletPlanetOrbit] = [],
        viewElevation: Double = 0.35,
        viewAzimuth: Double = 0,
        showsOrbits: Bool = false,
        perspective: Double = 0,
        lightTint: Double = 0.6,
        zoom: Double = 1,
        lightFalloff: Double = 0,
        orbitSpeed: Double = 1,
        orbitStyle: MoonletOrbitStyle = .init(),
        sky: MoonletSky = .init()
    ) {
        self.star = star
        self.starRadius = starRadius
        self.bodies = bodies
        self.viewElevation = viewElevation
        self.viewAzimuth = viewAzimuth
        self.showsOrbits = showsOrbits
        self.perspective = perspective
        self.lightTint = lightTint
        self.zoom = zoom
        self.lightFalloff = lightFalloff
        self.orbitSpeed = orbitSpeed
        self.orbitStyle = orbitStyle
        self.sky = sky
    }

    // Stored data: a system saved before any of these existed comes back drawn the way it
    // was.
    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        star = try c.decode(MoonletPlanetRecipe.self, forKey: .star)
        starRadius = try c.decode(Double.self, forKey: .starRadius)
        bodies = try c.decode([MoonletPlanetOrbit].self, forKey: .bodies)
        viewElevation = try c.decode(Double.self, forKey: .viewElevation)
        viewAzimuth = try c.decodeIfPresent(Double.self, forKey: .viewAzimuth) ?? 0
        showsOrbits = try c.decodeIfPresent(Bool.self, forKey: .showsOrbits) ?? false
        perspective = try c.decodeIfPresent(Double.self, forKey: .perspective) ?? 0
        lightTint = try c.decode(Double.self, forKey: .lightTint)
        zoom = try c.decodeIfPresent(Double.self, forKey: .zoom) ?? 1
        lightFalloff = try c.decodeIfPresent(Double.self, forKey: .lightFalloff) ?? 0
        orbitSpeed = try c.decodeIfPresent(Double.self, forKey: .orbitSpeed) ?? 1
        orbitStyle = try c.decodeIfPresent(MoonletOrbitStyle.self, forKey: .orbitStyle) ?? .init()
        sky = try c.decodeIfPresent(MoonletSky.self, forKey: .sky) ?? .init()
    }

    /// The colour of the star's light: its hot and its cooler gas together, brought up so
    /// the brightest channel is one — a light's colour, not its brightness — and then
    /// moved from white by `lightTint`.
    public var lightColor: MoonletColor {
        let h = star.palette.highlight, p = star.palette.primary
        let r = (h.red + p.red) / 2, g = (h.green + p.green) / 2, b = (h.blue + p.blue) / 2
        let peak = max(r, g, b, 1e-6)
        let t = min(max(lightTint, 0), 1)
        return MoonletColor(red: 1 + (r / peak - 1) * t, green: 1 + (g / peak - 1) * t, blue: 1 + (b / peak - 1) * t)
    }

    // MARK: - Framing

    /// How far from the star, in system units, a view showing the whole system reaches
    /// from its centre to its edge, after `zoom`.
    public var extent: Double {
        unzoomedExtent / max(zoom, 0.01)
    }

    /// The whole system's reach, rings and flames and the near side of every orbit.
    private var unzoomedExtent: Double {
        let reach = flatReach
        guard cameraDistance != nil else { return reach }
        // In perspective the near side of an orbit is magnified and the far side shrunk,
        // so the reach is measured round every orbit rather than bounded from the worst
        // case — which left the whole system small in the middle of its view.
        var projected = starRadius * star.drawnExtent
        for index in bodies.indices {
            let size = bodies[index].radius * bodies[index].recipe.drawnExtent
            for k in 0..<128 {
                let v = toView(orbitPosition(index, angle: Double(k) / 128 * 2 * .pi))
                let m = magnification(v.z)
                projected = max(projected, max(abs(v.x), abs(v.y)) * m + size * m)
            }
        }
        // The 128 samples can step past the true peak by a sliver.
        return projected * 1.01
    }

    /// How far anything reaches before perspective magnifies the near side.
    private var flatReach: Double {
        var reach = starRadius * star.drawnExtent
        for body in bodies {
            reach = max(reach, body.distance + body.radius * body.recipe.drawnExtent)
        }
        return reach
    }

    /// How far the camera is from the star, or `nil` for a flat view. Never closer than
    /// two and a half times the system's reach, so nothing passes behind the camera.
    private var cameraDistance: Double? {
        guard perspective > 0 else { return nil }
        return flatReach * 2.5 / min(perspective, 1)
    }

    /// How much a point at `depth` is magnified: one at the star, more nearer the camera.
    private func magnification(_ depth: Double) -> Double {
        guard let camera = cameraDistance else { return 1 }
        return camera / (camera - depth)
    }

    // MARK: - Layout

    /// One thing to draw: where, how big, how near the camera, and with what recipe.
    public struct Placement: Equatable, Sendable {
        /// Which body this is, or `nil` for the star.
        public var index: Int?
        /// The centre, in system units: x to the right, y up the screen.
        public var x: Double
        public var y: Double
        /// Towards the camera is positive. Draw in increasing depth and nearer things cover
        /// further ones.
        public var depth: Double
        /// The body's radius in system units. The view it is drawn into is
        /// `radius * recipe.drawnExtent` from centre to edge, because the recipe draws
        /// its rings and stations outside its disc.
        public var radius: Double
        public var recipe: MoonletPlanetRecipe
        /// How far the drawn body is turned on screen, counter-clockwise in radians — the
        /// same number the recipe carries as `roll`, which the shader applies. Zero in a flat
        /// system.
        public var roll: Double = 0
    }

    /// Where a planet is in the system — X across the plane, Y its normal, Z across it the
    /// other way — at `angle` round its own orbit. An inclined orbit is the flat circle
    /// turned about its line of nodes.
    func orbitPosition(_ index: Int, angle: Double) -> Vector {
        let body = bodies[index]
        let flat: Vector = (body.distance * cos(angle), 0, body.distance * sin(angle))
        guard body.inclination != 0 else { return flat }
        // Rodrigues' rotation about the node line, which lies in the plane.
        let k: Vector = (cos(body.node), 0, sin(body.node))
        let c = cos(body.inclination), s = sin(body.inclination)
        let dot = flat.x * k.x + flat.z * k.z
        let cross: Vector = (k.y * flat.z - k.z * flat.y, k.z * flat.x - k.x * flat.z, k.x * flat.y - k.y * flat.x)
        return (flat.x * c + cross.x * s + k.x * dot * (1 - c),
                flat.y * c + cross.y * s + k.y * dot * (1 - c),
                flat.z * c + cross.z * s + k.z * dot * (1 - c))
    }

    /// Where the body is round its orbit at `time`.
    func orbitAngle(_ index: Int, time: Double) -> Double {
        bodies[index].phase + time * bodies[index].speed * orbitSpeed
    }

    /// Where everything is at `time` seconds, back to front, with each planet lit from the
    /// star. The star is always in it; the order is the order to draw in.
    public func layout(at time: Double) -> [Placement] {
        let light = lightColor
        var starRecipe = star
        var starRoll = 0.0
        if perspective > 0 {
            starRoll = orient(&starRecipe, light: nil)
            starRecipe.roll = starRoll
        } else {
            starRecipe.rotationPhase += viewAzimuth
        }
        var placements = [Placement(index: nil, x: 0, y: 0, depth: 0, radius: starRadius, recipe: starRecipe, roll: starRoll)]
        for index in bodies.indices {
            let body = bodies[index]
            let v = toView(orbitPosition(index, angle: orbitAngle(index, time: time)))
            let x = v.x, y = v.y, depth = v.z
            var recipe = body.recipe
            var roll = 0.0
            let length = (x * x + y * y + depth * depth).squareRoot()
            if perspective > 0 {
                roll = orient(&recipe, light: length > 1e-9 ? (-x / length, -y / length, -depth / length) : nil)
                recipe.roll = roll
            } else {
                if length > 1e-9 {
                    // Towards the star, in the shader's light space — x right, y *down* the
                    // screen, z at the camera — so the screen-up y here changes sign on the
                    // way in. Measured, not assumed: light at +y lights a planet's bottom.
                    let lx = -x / length, ly = y / length, lz = -depth / length
                    recipe.lightAzimuth = atan2(lz, lx)
                    recipe.lightElevation = asin(min(max(ly, -1), 1))
                }
                // The camera turning one way is the planet's face turning the other way.
                recipe.rotationPhase += viewAzimuth
            }
            // The system moves the light; a day cycle of the planet's own would fight it.
            recipe.dayNightSpeed = 0
            recipe.palette.light = light
            if lightFalloff > 0, length > 1e-9 {
                // Inverse square, relative to a world three star radii out, and only ever
                // as strong as the setting asks.
                let reference = starRadius * 3
                recipe.exposure *= pow(min(max(reference / length, 0.05), 4), 2 * min(lightFalloff, 1))
            }
            // The light was worked out in the real positions; only the drawing is projected.
            let m = magnification(depth)
            placements.append(Placement(index: index, x: x * m, y: y * m, depth: depth, radius: body.radius * m, recipe: recipe, roll: roll))
        }
        // Stable, so two things at the same depth keep the order they were given in.
        return placements.enumerated()
            .sorted { $0.element.depth != $1.element.depth ? $0.element.depth < $1.element.depth : $0.offset < $1.offset }
            .map(\.element)
    }

    // MARK: - A real camera

    typealias Vector = (x: Double, y: Double, z: Double)

    /// A direction fixed in the system — X across the plane, Y its normal, Z across it the
    /// other way — as the camera sees it: x right, y up, z towards the camera.
    func toView(_ v: Vector) -> Vector {
        let ca = cos(viewAzimuth), sa = sin(viewAzimuth)
        let sinE = sin(viewElevation), cosE = cos(viewElevation)
        let X = v.x * ca + v.z * sa
        let Z = v.z * ca - v.x * sa
        return (X, Z * sinE + v.y * cosE, -Z * cosE + v.y * sinE)
    }

    /// From the view's y-up space into the shader's, which runs y down the screen. Its own
    /// inverse.
    static func toShader(_ v: Vector) -> Vector { (v.x, -v.y, v.z) }

    /// The inverse of `toView`.
    func fromView(_ v: Vector) -> Vector {
        let ca = cos(viewAzimuth), sa = sin(viewAzimuth)
        let sinE = sin(viewElevation), cosE = cos(viewElevation)
        let Z = v.y * sinE - v.z * cosE
        let Y = v.y * cosE + v.z * sinE
        return (v.x * ca - Z * sa, Y, v.x * sa + Z * ca)
    }

    /// A body's pole and prime meridian, fixed in the system. Its `axialTilt` leans the pole
    /// from the orbit's normal towards +X, and its `rotationPhase` turns the meridian about
    /// the pole — so neither moves when the camera does.
    static func frame(of recipe: MoonletPlanetRecipe) -> (pole: Vector, meridian: Vector) {
        let t = recipe.axialTilt, phase = recipe.rotationPhase
        let pole: Vector = (sin(t), cos(t), 0)
        let a: Vector = (cos(t), -sin(t), 0)
        // pole × a, which is -Z when the pole is upright: the direction the shader turns a
        // meridian towards as its phase grows.
        let b: Vector = (pole.y * a.z - pole.z * a.y, pole.z * a.x - pole.x * a.z, pole.x * a.y - pole.y * a.x)
        return (pole, (a.x * cos(phase) + b.x * sin(phase), a.y * cos(phase) + b.y * sin(phase), a.z * cos(phase) + b.z * sin(phase)))
    }

    /// Sets a copy's tilt, phase and light so the shader draws the body as the camera sees
    /// it, and returns the roll to draw it at.
    ///
    /// The shader's own frame has its pole in the y–z plane: tilted `axialTilt` towards the
    /// camera from straight up. Any pole the camera sees is that pole rolled about the line
    /// of sight, so the roll is whatever brings the pole's screen direction to straight up,
    /// and everything else — the meridian, the light — is rolled back by the same amount
    /// before it is handed to the shader.
    func orient(_ recipe: inout MoonletPlanetRecipe, light: Vector?) -> Double {
        let (pole, meridian) = Self.frame(of: recipe)
        // Everything below is in the shader's own space, whose y runs down the screen.
        let p = Self.toShader(toView(pole)), m = Self.toShader(toView(meridian))
        let roll = atan2(-p.x, p.y)
        let cr = cos(roll), sr = sin(roll)
        let unroll = { (v: Vector) -> Vector in (v.x * cr + v.y * sr, -v.x * sr + v.y * cr, v.z) }
        let pu = unroll(p), mu = unroll(m)
        let tilt = atan2(pu.z, pu.y)
        recipe.axialTilt = tilt
        // The shader samples its surface at R(spin) of the view direction, so a meridian at
        // spin φ sits along cos φ·right − sin φ·forward, forward being (0, sin T, −cos T).
        let forward: Vector = (0, sin(tilt), -cos(tilt))
        recipe.rotationPhase = atan2(-(mu.y * forward.y + mu.z * forward.z), mu.x)
        if let light {
            let l = unroll(Self.toShader(light))
            recipe.lightAzimuth = atan2(l.z, l.x)
            recipe.lightElevation = asin(min(max(l.y, -1), 1))
        }
        return roll
    }

    // MARK: - Dragging

    /// Moves a planet to the point on screen nearest `(x, y)`, in system units, at `time` —
    /// which is how somebody drags one into place.
    ///
    /// On a flat orbit both its distance and its phase follow the point. Seen nearly edge-on
    /// the screen has no depth to give, and an inclined orbit is not the plane the point is
    /// in, so in either case it keeps its distance and slides to the place on its orbit
    /// nearest the point.
    public mutating func place(_ index: Int, atX x: Double, y: Double, time: Double) {
        guard bodies.indices.contains(index) else { return }
        if bodies[index].inclination != 0 {
            slide(index, towardX: x, y: y, time: time)
            return
        }
        // Back out of the perspective: place it flat, see what depth that lands it at, and
        // place it again at that depth's magnification. It settles in a few rounds, because
        // the magnification changes much more slowly than the position does.
        var m = 1.0
        for _ in 0..<(perspective > 0 ? 6 : 1) {
            place(flat: index, x: x / m, y: y / m, time: time)
            guard let at = layout(at: time).first(where: { $0.index == index }) else { return }
            m = magnification(at.depth)
        }
    }

    private mutating func place(flat index: Int, x: Double, y: Double, time: Double) {
        let sinE = sin(viewElevation)
        guard abs(sinE) >= 0.2 else { return slide(index, towardX: x, y: y, time: time) }
        var body = bodies[index]
        let planeZ = y / sinE
        // Back out of the camera's turn: the point is at this angle on screen, and the
        // system is turned by the azimuth under it.
        body.distance = max((x * x + planeZ * planeZ).squareRoot(), starRadius * 1.05)
        let angle = atan2(planeZ, x) + viewAzimuth
        body.phase = angle - time * body.speed * orbitSpeed
        bodies[index] = body
    }

    /// Slides a planet round its orbit, distance kept, to the point on it nearest `(x, y)`
    /// on screen: a coarse search round the circle and then a fine one about the best.
    private mutating func slide(_ index: Int, towardX x: Double, y: Double, time: Double) {
        func miss(_ angle: Double) -> Double {
            let v = toView(orbitPosition(index, angle: angle))
            let m = magnification(v.z)
            return hypot(v.x * m - x, v.y * m - y)
        }
        var best = 0.0, bestMiss = Double.infinity
        for k in 0..<180 {
            let a = Double(k) / 180 * 2 * .pi
            let d = miss(a)
            if d < bestMiss { best = a; bestMiss = d }
        }
        var step = 2 * Double.pi / 180
        for _ in 0..<24 {
            for candidate in [best - step, best + step] where miss(candidate) < bestMiss {
                best = candidate; bestMiss = miss(candidate)
            }
            step *= 0.5
        }
        bodies[index].phase = best - time * bodies[index].speed * orbitSpeed
    }

    // MARK: - Orbit lines

    /// A planet's orbit as `count` points round the circle, in the same units and with the
    /// same depth as `layout(at:)` — so a view can draw the half behind the star behind it
    /// and the half in front in front.
    public func orbitPoints(_ index: Int, count: Int = 96) -> [(x: Double, y: Double, depth: Double)] {
        guard bodies.indices.contains(index), count > 2 else { return [] }
        return (0..<count).map { k in
            let v = toView(orbitPosition(index, angle: Double(k) / Double(count) * 2 * .pi))
            let m = magnification(v.z)
            return (v.x * m, v.y * m, v.z)
        }
    }

    // MARK: - The sky

    /// One star of the sky, placed in a view.
    public struct SkyStar: Equatable, Sendable {
        /// In points from the view's top-left, y down.
        public var x: Double, y: Double
        public var radius: Double
        public var red: Double, green: Double, blue: Double, alpha: Double
    }

    /// The sky's stars as they land in a `width` × `height` view at `time`: stars at
    /// infinity, fixed in the system, so they slide past as the camera turns and rises —
    /// the way a background does when the camera moves and not the scene.
    public func skyStars(width: Double, height: Double, time: Double = 0) -> [SkyStar] {
        let focal = max(width, height) * 0.9
        let tint = sky.color
        let warmth = min(max(sky.warmth, 0), 2)
        var result: [SkyStar] = []
        for star in sky.directions() {
            // The same turn and tilt the planets get, applied to a direction.
            let v = toView((star.x, star.y, star.z))
            // Only what is beyond the system, away from the camera, is on screen.
            guard v.z < -0.05 else { continue }
            let sx = width / 2 + v.x / -v.z * focal
            let sy = height / 2 - v.y / -v.z * focal
            guard sx > -2, sy > -2, sx < width + 2, sy < height + 2 else { continue }
            var alpha = (0.25 + 0.75 * star.brightness) * sky.brightness
            if sky.twinkle > 0 {
                let rate = 1.5 + 4 * star.warmth
                alpha *= 1 - min(sky.twinkle, 1) * (0.5 + 0.5 * sin(time * rate + star.flicker * 2 * .pi))
            }
            result.append(SkyStar(
                x: sx, y: sy,
                radius: (0.45 + star.brightness * 1.1) * sky.starSize,
                red: tint.red * (1 - 0.2 * warmth * (1 - star.warmth)),
                green: tint.green * (1 - 0.15 * warmth),
                blue: tint.blue * (1 - 0.2 * warmth * star.warmth),
                alpha: min(max(alpha, 0), 1)))
        }
        return result
    }

    /// A small system to start from: the Sun, a rocky inner world, Earth, and a ringed giant.
    public static var example: Self {
        Self(
            star: MoonletPlanetPreset.sun.style!.recipe,
            starRadius: 1,
            bodies: [
                .init(recipe: MoonletPlanetPreset.mercury.style!.recipe, radius: 0.22, distance: 1.9, phase: 0.6, speed: 0.22),
                .init(recipe: MoonletPlanetPreset.earth.style!.recipe, radius: 0.36, distance: 3.0, phase: 3.5, speed: 0.13),
                .init(recipe: MoonletPlanetPreset.saturn.style!.recipe, radius: 0.5, distance: 4.4, phase: 5.75, speed: 0.07)
            ]
        )
    }
}

/// How a system's orbit lines are drawn.
public struct MoonletOrbitStyle: Codable, Equatable, Hashable, Sendable {
    /// The near half's opacity; the far half, behind the star, is drawn at two thirds of it.
    public var opacity: Double
    /// In points.
    public var width: Double
    public var color: MoonletColor

    public init(opacity: Double = 0.28, width: Double = 1, color: MoonletColor = .init(red: 1, green: 1, blue: 1)) {
        self.opacity = opacity
        self.width = width
        self.color = color
    }

    /// The far half's opacity: two thirds of the near half's, which is 0.18 for the default.
    public var farOpacity: Double { opacity * 0.18 / 0.28 }
}

/// The sky behind a system: stars at infinity that turn with the camera, and a band of
/// them like the Milky Way if asked for.
public struct MoonletSky: Codable, Equatable, Hashable, Sendable {
    /// Whether a view draws it.
    public var isVisible: Bool
    public var starCount: Int
    /// Which sky. 0 is the one the package has always drawn.
    public var seed: UInt32
    /// A multiplier on every star's opacity.
    public var brightness: Double
    /// A multiplier on every star's size.
    public var starSize: Double
    /// How much the stars vary in colour, warm to cool. 0 is all one colour.
    public var warmth: Double
    /// The colour the stars vary around.
    public var color: MoonletColor
    /// How much the stars flicker. 0 holds them steady.
    public var twinkle: Double
    /// What share of the stars gather in a band across the sky. 0 is none.
    public var bandStrength: Double
    /// How the band crosses the system's plane, in radians.
    public var bandTilt: Double

    public init(
        isVisible: Bool = false,
        starCount: Int = 900,
        seed: UInt32 = 0,
        brightness: Double = 1,
        starSize: Double = 1,
        warmth: Double = 1,
        color: MoonletColor = .init(red: 1, green: 1, blue: 1),
        twinkle: Double = 0,
        bandStrength: Double = 0,
        bandTilt: Double = 1
    ) {
        self.isVisible = isVisible
        self.starCount = starCount
        self.seed = seed
        self.brightness = brightness
        self.starSize = starSize
        self.warmth = warmth
        self.color = color
        self.twinkle = twinkle
        self.bandStrength = bandStrength
        self.bandTilt = bandTilt
    }

    /// Every star as a direction on the sphere and the numbers that decide how it looks,
    /// from a 64-bit LCG the web port reproduces exactly. Six draws a star whatever the
    /// settings, so changing one setting never reshuffles the rest of the sky.
    func directions() -> [(x: Double, y: Double, z: Double, brightness: Double, warmth: Double, flicker: Double)] {
        var state: UInt64 = 0x9E3779B97F4A7C15 ^ (UInt64(seed) &* 0xD1B54A32D192ED03)
        func next() -> Double {
            state = state &* 6364136223846793005 &+ 1442695040888963407
            return Double(state >> 11) / Double(1 << 53)
        }
        let tiltC = cos(bandTilt), tiltS = sin(bandTilt)
        return (0..<max(0, min(starCount, 5000))).map { _ in
            let z = next() * 2 - 1, a = next() * 2 * .pi
            let brightness = pow(next(), 3), warmth = next()
            let roll = next(), offset = next()
            if roll < bandStrength {
                // In the band: a thin belt round a great circle, then tipped by its tilt.
                let y = (offset - 0.5) * 0.22, r = (1 - y * y).squareRoot()
                let bx = r * cos(a), bz = r * sin(a)
                return (bx, y * tiltC - bz * tiltS, y * tiltS + bz * tiltC, brightness, warmth, offset)
            }
            let r = (1 - z * z).squareRoot()
            // Uniform on the sphere, not bunched at the poles.
            return (r * cos(a), z, r * sin(a), brightness, warmth, offset)
        }
    }
}

/// One world in a `MoonletPlanetSystem` and the circle it goes round on.
public struct MoonletPlanetOrbit: Codable, Equatable, Hashable, Sendable, Identifiable {
    public var id: UUID
    public var recipe: MoonletPlanetRecipe
    /// The planet's radius, in system units.
    public var radius: Double
    /// From the star's centre, in system units.
    public var distance: Double
    /// Where on the orbit it is at time zero, in radians. With `speed` at zero this is
    /// simply where it is: 0 is to the star's right, `.pi / 2` behind it, `-.pi / 2` in
    /// front of it.
    public var phase: Double
    /// Radians a second around the orbit. Zero holds it still.
    public var speed: Double
    /// How far the orbit is tipped out of the system's plane, in radians. 0 lies in it.
    public var inclination: Double
    /// Which way across the plane the tipped orbit crosses it — its line of nodes — in
    /// radians round the plane. Only matters once `inclination` is not zero.
    public var node: Double

    public init(id: UUID = UUID(), recipe: MoonletPlanetRecipe, radius: Double = 0.35, distance: Double = 3,
                phase: Double = 0, speed: Double = 0.1, inclination: Double = 0, node: Double = 0) {
        self.id = id
        self.recipe = recipe
        self.radius = radius
        self.distance = distance
        self.phase = phase
        self.speed = speed
        self.inclination = inclination
        self.node = node
    }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        recipe = try c.decode(MoonletPlanetRecipe.self, forKey: .recipe)
        radius = try c.decode(Double.self, forKey: .radius)
        distance = try c.decode(Double.self, forKey: .distance)
        phase = try c.decode(Double.self, forKey: .phase)
        speed = try c.decode(Double.self, forKey: .speed)
        inclination = try c.decodeIfPresent(Double.self, forKey: .inclination) ?? 0
        node = try c.decodeIfPresent(Double.self, forKey: .node) ?? 0
    }
}
