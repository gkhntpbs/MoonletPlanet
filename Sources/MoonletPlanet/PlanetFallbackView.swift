import SwiftUI

#if canImport(AppKit)
import AppKit
#elseif canImport(UIKit)
import UIKit
#endif

/// Drawn when the Metal renderer is unavailable — no shader compiler, no metallib, or a
/// device without Metal. The planet keeps its palette and light direction so the scene
/// still reads correctly; it simply loses surface detail.
///
/// The character must be complete with effects off. That is a hard requirement, not a
/// nicety, so this path is never allowed to crash or render nothing.
public struct MoonletPlanetFallback: View {
    public init(recipe: MoonletPlanetRecipe) { self.recipe = recipe }

    let recipe: MoonletPlanetRecipe

    public var body: some View {
        let palette = recipe.palette
        // Match the shader's light direction so the terminator lands in the same place.
        let light = UnitPoint(
            x: 0.5 + 0.32 * cos(recipe.lightAzimuth),
            y: 0.5 - 0.32 * sin(recipe.lightElevation)
        )

        Circle()
            .fill(
                RadialGradient(
                    colors: [
                        palette.highlight.color,
                        palette.primary.color,
                        palette.shadow.color
                    ],
                    center: light,
                    startRadius: 0,
                    endRadius: 120
                )
            )
            .overlay(
                Circle()
                    .strokeBorder(palette.atmosphere.color.opacity(0.5), lineWidth: 1.5)
                    .blur(radius: 1)
            )
    }
}
