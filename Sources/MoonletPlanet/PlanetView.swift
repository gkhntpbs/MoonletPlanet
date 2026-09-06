import SwiftUI

/// A procedurally generated planet, drawn by a Metal fragment shader.
///
/// The view fills whatever frame it is given and draws nothing outside it. There is no
/// mesh, no texture and no asset: the sphere is analytic (`z = sqrt(1 - r²)` over a
/// full-screen quad) and everything on it is noise evaluated per pixel, so the same
/// `MoonletPlanetRecipe` produces the same planet at any size on any device.
///
///     MoonletPlanetView(recipe: .preset(.gasGiant))
///         .frame(width: 300, height: 300)
///
/// Where Metal is unavailable the view falls back to `MoonletPlanetFallback`, which keeps
/// the palette and the light direction and loses only the surface detail.
public struct MoonletPlanetView: View {
    private let recipe: MoonletPlanetRecipe
    private let hasRing: Bool
    private let frozenTime: Double?
    private let timeScale: Double
    private let isPaused: Bool
    private let showsAtmosphere: Bool

    /// - Parameters:
    ///   - recipe: what the planet is made of.
    ///   - hasRing: draws a Saturn-style ring behind the body.
    ///   - frozenTime: pins the planet to one instant, so it renders identically every
    ///     time. Use it for thumbnails and exported images; leave it `nil` to animate.
    ///   - timeScale: how fast the planet's own weather runs. 1 is as designed. Lower it
    ///     rather than freezing when the reader has asked for reduced motion — the clouds
    ///     still move, slowly, instead of the planet becoming a photograph.
    ///   - isPaused: stops the display link. For a planet that is off screen.
    ///   - showsAtmosphere: the soft glow filled behind the body. Off gives a bare sphere.
    public init(
        recipe: MoonletPlanetRecipe,
        hasRing: Bool = false,
        frozenTime: Double? = nil,
        timeScale: Double = 1,
        isPaused: Bool = false,
        showsAtmosphere: Bool = true
    ) {
        self.recipe = recipe
        self.hasRing = hasRing
        self.frozenTime = frozenTime
        self.timeScale = timeScale
        self.isPaused = isPaused
        self.showsAtmosphere = showsAtmosphere
    }

    /// The same view described by a named, ringed `MoonletPlanetStyle`.
    public init(
        style: MoonletPlanetStyle,
        frozenTime: Double? = nil,
        timeScale: Double = 1,
        isPaused: Bool = false,
        showsAtmosphere: Bool = true
    ) {
        self.init(
            recipe: style.recipe,
            hasRing: style.hasRing,
            frozenTime: frozenTime,
            timeScale: timeScale,
            isPaused: isPaused,
            showsAtmosphere: showsAtmosphere
        )
    }

    public var body: some View {
        GeometryReader { proxy in
            let side = min(proxy.size.width, proxy.size.height)
            body(side: side)
            .frame(width: proxy.size.width, height: proxy.size.height)
        }
        .aspectRatio(1, contentMode: .fit)
    }

    @ViewBuilder
    private func body(side: CGFloat) -> some View {
        Group {
            if MoonletPlanetRenderer.isAvailable {
                MoonletPlanetMetalView(
                    recipe: recipe,
                    frozenTime: frozenTime,
                    timeScale: timeScale,
                    isPaused: isPaused
                )
            } else {
                MoonletPlanetFallback(recipe: recipe)
            }
        }
        .frame(width: side, height: side)
        // The atmosphere is behind the planet as a gradient, not around it as a shadow.
        //
        // A `.shadow` on the Metal view is a blur of the largest, busiest layer in the
        // composition, re-derived every frame because its content changes every frame —
        // to add a glow the shader is already computing (`rim`, `atmosphereGlow`). This
        // fills the same falloff once, underneath, and costs a gradient.
        .background {
            if showsAtmosphere {
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [
                                recipe.palette.atmosphere.color.opacity(0.15),
                                recipe.palette.atmosphere.color.opacity(0.045),
                                .clear
                            ],
                            center: .center,
                            startRadius: side * 0.5,
                            endRadius: side * 0.6
                        )
                    )
                    .frame(width: side * 1.2, height: side * 1.2)
            }
        }
    }
}

/// Whether this device and bundle can render the shader at all.
///
/// Probed once. False means no Metal device, or a build that shipped neither a compiled
/// `default.metallib` nor the shader source — in which case `MoonletPlanetView` draws
/// `MoonletPlanetFallback` and nothing crashes.
public enum MoonletPlanetRendering {
    public static var isMetalAvailable: Bool { MoonletPlanetRenderer.isAvailable }
}

#Preview("Archetypes") {
    ScrollView {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 140))], spacing: 20) {
            ForEach(MoonletPlanetArchetype.allCases) { archetype in
                VStack(spacing: 8) {
                    MoonletPlanetView(recipe: .preset(archetype))
                        .frame(width: 140, height: 140)
                    Text(archetype.title)
                        .font(.caption)
                }
            }
        }
        .padding()
    }
    .background(Color.black)
}
