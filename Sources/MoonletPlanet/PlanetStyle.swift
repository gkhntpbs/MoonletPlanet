import SwiftUI

#if canImport(AppKit)
import AppKit
#elseif canImport(UIKit)
import UIKit
#endif

public struct MoonletPlanetStyle: Equatable, Sendable {
    public var name: String
    public var recipe: MoonletPlanetRecipe

    /// Rings live in the recipe, because they are part of what the planet *is* rather than
    /// how it is presented. This stays for the call sites that already ask a style.
    public var hasRing: Bool {
        get { recipe.hasRing }
        set { recipe.hasRing = newValue }
    }

    public init(name: String = "My Planet", recipe: MoonletPlanetRecipe = .preset(.gasGiant), hasRing: Bool = false) {
        self.name = name
        self.recipe = recipe
        if hasRing { self.recipe.hasRing = true }
    }

    public init(
        name: String = "My Planet",
        primaryColor: Color = Color(red: 0.2, green: 0.34, blue: 0.48),
        secondaryColor: Color = Color(red: 0.08, green: 0.14, blue: 0.24),
        accentColor: Color = Color(red: 0.38, green: 0.82, blue: 0.94),
        surface: MoonletPlanetSurface = .cratered,
        hasRing: Bool = false
    ) {
        var recipe = MoonletPlanetRecipe.preset(surface == .banded ? .gasGiant : surface == .archipelago ? .ocean : .rocky)
        recipe.palette.primary = MoonletColor(primaryColor)
        recipe.palette.shadow = MoonletColor(secondaryColor)
        recipe.palette.atmosphere = MoonletColor(accentColor)
        recipe.featureAmount = surface == .smooth ? 0.12 : 0.72
        self.init(name: name, recipe: recipe, hasRing: hasRing)
    }
}
