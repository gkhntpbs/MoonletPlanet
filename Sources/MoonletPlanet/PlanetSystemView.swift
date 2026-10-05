import SwiftUI
import CoreGraphics

/// A star and its planets, each lit from where the star is.
///
///     MoonletSystemView(system: .example)
///         .frame(width: 600, height: 600)
///
/// Each body is an ordinary `MoonletPlanetView`, so a planet looks here exactly as it does
/// on its own except for where its light comes from. The system fits the largest square
/// in the middle of the view, rings and flames included; the sky fills the whole view,
/// because a sky that stopped at the edge of a square would read as a picture of one.
/// Give it a square frame to get just the square.
public struct MoonletSystemView: View {
    private let system: MoonletPlanetSystem
    private let frozenTime: Double?
    private let timeScale: Double
    private let isPaused: Bool
    private let showsStarfield: Bool
    @State private var startedAt = Date()

    /// - Parameters:
    ///   - frozenTime: pins the whole system — orbits and weather — to one instant.
    ///   - timeScale: how fast the orbits and the weather run. 1 is as designed.
    ///   - isPaused: stops the orbits and the planets' display links.
    ///   - showsStarfield: draws the system's sky even when `system.sky.isVisible` is off.
    ///     Distant stars that turn with the camera are what tells the eye the camera is
    ///     moving rather than the planets.
    public init(system: MoonletPlanetSystem, frozenTime: Double? = nil, timeScale: Double = 1, isPaused: Bool = false, showsStarfield: Bool = false) {
        self.system = system
        self.frozenTime = frozenTime
        self.timeScale = timeScale
        self.isPaused = isPaused
        self.showsStarfield = showsStarfield
    }

    public var body: some View {
        GeometryReader { proxy in
            let side = min(proxy.size.width, proxy.size.height)
            TimelineView(.animation(paused: frozenTime != nil || isPaused)) { context in
                let time = frozenTime ?? context.date.timeIntervalSince(startedAt) * timeScale
                let scale = side / 2 / max(system.extent, 1e-6)
                let layout = system.layout(at: time)
                // The orbit lines go in two halves: the far one under everything, the near
                // one just over the star, so a planet in front still covers its own line
                // and the star does not cover the near half of one passing in front of it.
                let starOrder = Double(layout.firstIndex { $0.index == nil } ?? 0)
                ZStack {
                    if showsStarfield || system.sky.isVisible {
                        Canvas { context, size in
                            for p in system.skyStars(width: size.width, height: size.height, time: time) {
                                context.fill(Path(ellipseIn: CGRect(x: p.x - p.radius, y: p.y - p.radius, width: p.radius * 2, height: p.radius * 2)),
                                             with: .color(Color(red: p.red, green: p.green, blue: p.blue, opacity: p.alpha)))
                            }
                        }
                        .frame(width: proxy.size.width, height: proxy.size.height)
                        .allowsHitTesting(false)
                    }
                    bodies(layout: layout, side: side, scale: scale, starOrder: starOrder)
                        .frame(width: side, height: side)
                }
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
        }
    }

    /// The star, the planets and the orbit lines, in a square `side` across.
    private func bodies(layout: [MoonletPlanetSystem.Placement], side: CGFloat, scale: CGFloat, starOrder: Double) -> some View {
                ZStack {
                    if system.showsOrbits {
                        orbits(side: side, scale: scale, near: false).zIndex(-1)
                        orbits(side: side, scale: scale, near: true).zIndex(starOrder + 0.5)
                    }
                    ForEach(Array(layout.enumerated()), id: \.element.index) { order, placement in
                        let size = 2 * placement.radius * placement.recipe.drawnExtent * scale
                        MoonletPlanetView(
                            recipe: placement.recipe,
                            frozenTime: frozenTime,
                            timeScale: timeScale,
                            isPaused: isPaused
                        )
                        .frame(width: size, height: size)
                        .position(x: side / 2 + placement.x * scale, y: side / 2 - placement.y * scale)
                        .zIndex(Double(order))
                    }
                }
    }

    private func orbits(side: CGFloat, scale: CGFloat, near: Bool) -> some View {
        let style = system.orbitStyle
        return Canvas { context, _ in
            context.stroke(MoonletPlanetSystem.orbitPath(system, side: side, scale: scale, near: near),
                           with: .color(style.color.color.opacity(near ? style.opacity : style.farOpacity)),
                           lineWidth: style.width)
        }
        .frame(width: side, height: side)
        .allowsHitTesting(false)
    }
}

extension MoonletPlanetSystem {
    /// Every orbit's near or far half as one path, in a square `side` points across with y
    /// down — the view's own coordinates.
    static func orbitPath(_ system: Self, side: CGFloat, scale: CGFloat, near: Bool) -> Path {
        var path = Path()
        for index in system.bodies.indices {
            let points = system.orbitPoints(index)
            for k in points.indices {
                let a = points[k], b = points[(k + 1) % points.count]
                guard ((a.depth + b.depth) > 0) == near else { continue }
                path.move(to: CGPoint(x: side / 2 + a.x * scale, y: side / 2 - a.y * scale))
                path.addLine(to: CGPoint(x: side / 2 + b.x * scale, y: side / 2 - b.y * scale))
            }
        }
        return path
    }
}

extension MoonletPlanetSnapshotRenderer {
    /// The whole system at one instant, as one square image with a transparent background.
    @MainActor public static func image(system: MoonletPlanetSystem, size: Int, time: Double, showsStarfield: Bool = false) -> CGImage? {
        guard size > 0,
              let context = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: size * 4,
                                      space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                      bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue)
        else { return nil }
        let side = Double(size)
        let scale = side / 2 / max(system.extent, 1e-6)
        if showsStarfield || system.sky.isVisible {
            for p in system.skyStars(width: side, height: side, time: time) {
                context.setFillColor(CGColor(red: p.red, green: p.green, blue: p.blue, alpha: p.alpha))
                // Points are y-down; Core Graphics is y-up.
                context.fillEllipse(in: CGRect(x: p.x - p.radius, y: side - p.y - p.radius, width: p.radius * 2, height: p.radius * 2))
            }
        }
        if system.showsOrbits { strokeOrbits(system, in: context, side: side, scale: scale, near: false) }
        for placement in system.layout(at: time) {
            let drawn: Double = 2 * placement.radius * placement.recipe.drawnExtent * scale
            let pixels = max(1, Int(drawn.rounded(.up)))
            if let body = image(recipe: placement.recipe, size: pixels, time: time) {
                // Core Graphics is y-up, which is the system's own convention.
                let x: Double = side / 2 + placement.x * scale - drawn / 2
                let y: Double = side / 2 + placement.y * scale - drawn / 2
                // The roll is in the recipe and the shader has drawn it already.
                context.draw(body, in: CGRect(x: x, y: y, width: drawn, height: drawn))
            }
            // The near half of the orbits goes over the star and under everything after it.
            if placement.index == nil && system.showsOrbits {
                strokeOrbits(system, in: context, side: side, scale: scale, near: true)
            }
        }
        return context.makeImage()
    }

    /// The orbit path is y-down, the view's convention, so it is flipped into Core Graphics.
    private static func strokeOrbits(_ system: MoonletPlanetSystem, in context: CGContext, side: Double, scale: Double, near: Bool) {
        context.saveGState()
        context.translateBy(x: 0, y: side)
        context.scaleBy(x: 1, y: -1)
        context.addPath(MoonletPlanetSystem.orbitPath(system, side: side, scale: scale, near: near).cgPath)
        let style = system.orbitStyle
        context.setStrokeColor(CGColor(red: style.color.red, green: style.color.green, blue: style.color.blue,
                                       alpha: near ? style.opacity : style.farOpacity))
        // Points in the view; the snapshot is `side` pixels for a view about 600 points across.
        context.setLineWidth(max(1, style.width * side / 600))
        context.strokePath()
        context.restoreGState()
    }
}

#Preview("System") {
    MoonletSystemView(system: .example)
        .frame(width: 520, height: 520)
        .background(Color.black)
}
