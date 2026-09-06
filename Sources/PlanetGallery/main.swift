import Foundation
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers
import MoonletPlanet

// Renders the images the README uses. Run from the package root:
//     swift run PlanetGallery
// It writes into Documentation/, which is what the README points at, so a change to the
// shader is one command away from being visible in the docs rather than a stale picture.

let out = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
    .appendingPathComponent("Documentation")
try? FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)

@MainActor func write(_ image: CGImage, _ name: String) {
    let url = out.appendingPathComponent("\(name).png")
    guard let dest = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil) else { return }
    CGImageDestinationAddImage(dest, image, nil)
    CGImageDestinationFinalize(dest)
    print("wrote", url.lastPathComponent)
}

/// A grid of planets on the palette Moonlet is dressed in.
@MainActor func sheet(_ recipes: [MoonletPlanetRecipe], cell: Int, cols: Int, gap: Int, file: String) {
    let rows = (recipes.count + cols - 1) / cols
    let w = cell * cols + gap * (cols + 1)
    let h = cell * rows + gap * (rows + 1)
    guard let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                              space: CGColorSpace(name: CGColorSpace.sRGB)!,
                              bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue) else { return }
    // Void, the app's background.
    ctx.setFillColor(CGColor(red: 0x09 / 255, green: 0x0A / 255, blue: 0x0D / 255, alpha: 1))
    ctx.fill(CGRect(x: 0, y: 0, width: w, height: h))
    for (i, recipe) in recipes.enumerated() {
        guard let img = MoonletPlanetSnapshotRenderer.image(recipe: recipe, size: cell * 2, time: 18) else { continue }
        let col = i % cols, row = i / cols
        let x = gap + col * (cell + gap)
        let y = h - gap - (row + 1) * cell - row * gap
        ctx.draw(img, in: CGRect(x: x, y: y, width: cell, height: cell))
    }
    if let img = ctx.makeImage() { write(img, file) }
}

@MainActor func run() {
    print("metal available:", MoonletPlanetRendering.isMetalAvailable)

    // The hero. One planet, large, worth looking at.
    var hero = MoonletPlanetRecipe.preset(.gasGiant)
    hero.seed = 240513
    hero.atmosphereGlow = 1.15
    if let img = MoonletPlanetSnapshotRenderer.image(recipe: hero, size: 1200, time: 18) {
        write(img, "hero")
    }

    if let img = MoonletPlanetSnapshotRenderer.image(recipe: MoonletPlanetPreset.saturn.style!.recipe, size: 1100, time: 18) {
        write(img, "rings")
    }

    // The same ring system at five tilts, edge-on to face-on.
    // The ice line as a physical result: one world, the isotherm walked from none to all.
    sheet((0..<5).map { i -> MoonletPlanetRecipe in
        var r = MoonletPlanetPreset.earth.style!.recipe
        r.iceCoverage = Double(i) * 0.25
        r.polarAsymmetry = 0.16
        return r
    }, cell: 300, cols: 5, gap: 12, file: "ice")
    sheet((0..<5).map { i -> MoonletPlanetRecipe in
        var r = MoonletPlanetPreset.saturn.style!.recipe
        r.axialTilt = 0.06 + Double(i) * (1.45 - 0.06) / 4
        return r
    }, cell: 300, cols: 5, gap: 12, file: "ring-tilts")
    sheet(MoonletPlanetArchetype.allCases.map { .preset($0) }, cell: 240, cols: 5, gap: 16, file: "archetypes")
    sheet(MoonletPlanetPreset.allCases.filter { $0 != .custom }.map { $0.style!.recipe },
          cell: 240, cols: 5, gap: 16, file: "solar-system")

    // What one archetype does across seeds — the argument for `randomized`.
    sheet((0..<10).map { MoonletPlanetRecipe.preset(.gasGiant).randomized(seed: UInt32(1 + $0 * 7717)) },
          cell: 240, cols: 5, gap: 16, file: "seeds")
    exit(0)
}

DispatchQueue.main.async { run() }
RunLoop.main.run()
