import SwiftUI
import UniformTypeIdentifiers
import MoonletPlanet

// The package's own workbench.
//
// The point of it is that this repository is developable without the app it came from: the
// shader can be changed and looked at in one command, every parameter has a control, and a
// planet that looks right can leave as JSON or as a PNG.
//
//     swift run PlanetStudio

@main
struct PlanetStudio: App {
    var body: some Scene {
        WindowGroup("Planet Studio") {
            StudioView()
                .frame(minWidth: 940, minHeight: 640)
        }
        .windowStyle(.hiddenTitleBar)
    }
}

struct StudioView: View {
    @State private var recipe = MoonletPlanetRecipe.preset(.gasGiant)
    @State private var paused = false
    @State private var status: String?
    /// Where the planet was when the drag began, so the gesture is absolute rather than
    /// accumulated — an incremental one drifts as soon as a frame is dropped.
    @State private var dragStart: (phase: Double, tilt: Double)?

    var body: some View {
        HStack(spacing: 0) {
            stage
            Divider()
            controls
                .frame(width: 340)
        }
        .background(Color(red: 0.035, green: 0.04, blue: 0.05))
        .preferredColorScheme(.dark)
    }

    private var stage: some View {
        ZStack {
            Color(red: 0.035, green: 0.04, blue: 0.05)
            MoonletPlanetView(recipe: recipe, isPaused: paused)
                .padding(28)
                // Drag to turn it. Sideways is the planet's own day; up and down tips the
                // pole, which is the same number that opens the rings.
                .gesture(
                    DragGesture()
                        .onChanged { value in
                            guard let start = dragStart else {
                                dragStart = (recipe.rotationPhase, recipe.axialTilt)
                                return
                            }
                            recipe.rotationPhase = start.phase - value.translation.width * 0.006
                            recipe.axialTilt = min(max(start.tilt + value.translation.height * 0.004, 0), .pi / 2)
                        }
                        .onEnded { _ in dragStart = nil }
                )
            if let status {
                Text(status)
                    .font(.caption.monospaced())
                    .padding(8)
                    .background(.black.opacity(0.6), in: RoundedRectangle(cornerRadius: 6))
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
                    .padding()
            }
        }
        .frame(minWidth: 560)
    }

    private var controls: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                section("Planet") {
                    Picker("Archetype", selection: $recipe.archetype) {
                        ForEach(MoonletPlanetArchetype.allCases) { Text($0.title).tag($0) }
                    }
                    .onChange(of: recipe.archetype) { _, new in
                        // Changing archetype without changing the numbers shows the shader's
                        // other branch on this planet's settings, which is what you want when
                        // you are working on a surface function and not on a preset.
                        var next = MoonletPlanetRecipe.preset(new, seed: recipe.seed)
                        next.ringOpacity = recipe.ringOpacity
                        next.axialTilt = recipe.axialTilt
                        next.iceCoverage = recipe.iceCoverage
                        next.polarAsymmetry = recipe.polarAsymmetry
                        next.life = recipe.life
                        next.dayNightSpeed = recipe.dayNightSpeed
                        next.stationCount = recipe.stationCount
                        next.stationOrbitRadius = recipe.stationOrbitRadius
                        next.stationSpeed = recipe.stationSpeed
                        next.stationInclination = recipe.stationInclination
                        next.stationSize = recipe.stationSize
                        recipe = next
                    }
                    // 0 points the pole up the screen; .pi / 2 points it at the camera. The
                    // rings lie in the equator, so this opens them too.
                    slider("Axial tilt", $recipe.axialTilt, 0...(.pi / 2))
                    slider("Longitude", $recipe.rotationPhase, -(.pi)...(.pi))
                    HStack {
                        Text("Seed").frame(width: 92, alignment: .leading)
                        Text("\(recipe.seed)").font(.caption.monospaced())
                        Spacer()
                        Button("Randomize") { recipe = recipe.randomized() }
                    }
                }

                section("Solar system") {
                    // Fixed columns rather than adaptive ones, and every button stretched to
                    // fill its cell: an adaptive grid sizes each button to its own title, so
                    // "Mercury" and "Moon" come out different widths in the same row. Two
                    // columns because there are ten of them, and three leaves an orphan.
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 2), spacing: 6) {
                        ForEach(MoonletPlanetPreset.allCases.filter { $0 != .custom }) { preset in
                            Button {
                                if let style = preset.style { recipe = style.recipe }
                            } label: {
                                Text(preset.title)
                                    .font(.caption)
                                    .lineLimit(1)
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 3)
                            }
                            .buttonStyle(.bordered)
                        }
                    }
                }

                section("Surface") {
                    slider("Rotation", $recipe.rotationSpeed, 0...0.6)
                    slider("Turbulence", $recipe.turbulence, 0...1)
                    slider("Detail", $recipe.detail, 0...1)
                    slider("Warp", $recipe.warpStrength, 0...1.5)
                    slider("Bands", $recipe.bandCount, 0...30)
                    slider("Band edge", $recipe.bandSharpness, 0...1)
                    slider("Storms", $recipe.stormCount, 0...5)
                    slider("Storm force", $recipe.stormStrength, 0...1.5)
                    slider("Features", $recipe.featureAmount, 0...1)
                    slider("Roughness", $recipe.roughness, 0...1)
                    slider("Fine detail", $recipe.microDetail, 0...1.5)
                }

                section("Life") {
                    Picker("Life", selection: $recipe.life) {
                        ForEach(MoonletPlanetLife.allCases) { Text($0.title).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    if recipe.life != .none {
                        ColorPicker("Growth", selection: colorBinding(\.life))
                    }
                    if recipe.life.isLit {
                        Text("City lights show on the night side. Turn the day up to see them.")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }

                if recipe.life.hasOrbitalStation {
                    section("In orbit") {
                        Stepper("Stations: \(recipe.stationCount)", value: $recipe.stationCount, in: 0...4)
                            .font(.caption)
                        // Below 1.03 the trail dips into the limb; past the rings' inner edge
                        // it flies through them.
                        slider("Orbit", $recipe.stationOrbitRadius, 1.03...1.8)
                        slider("Speed", $recipe.stationSpeed, 0...1.5)
                        slider("Inclination", $recipe.stationInclination, 0...(.pi / 2))
                        slider("Size", $recipe.stationSize, 0.5...3)
                    }
                }

                section("Ice") {
                    // A position for the freezing isotherm, not a cap radius: 0 is a world
                    // with no ice and 1 glaciates it to the equator.
                    slider("Coverage", $recipe.iceCoverage, 0...1)
                    slider("Lapse rate", $recipe.iceAltitude, 0...1)
                    slider("Asymmetry", $recipe.polarAsymmetry, -0.6...0.6)
                    ColorPicker("Ice", selection: colorBinding(\.ice))
                }

                section("Air") {
                    slider("Cloud cover", $recipe.cloudCoverage, 0...1)
                    slider("Cloud speed", $recipe.cloudSpeed, 0...4)
                    slider("Density", $recipe.atmosphereDensity, 0...1)
                    slider("Glow", $recipe.atmosphereGlow, 0...2)
                }

                section("Rings") {
                    Toggle("Rings", isOn: $recipe.hasRing)
                    if recipe.hasRing {
                        slider("Opacity", $recipe.ringOpacity, 0...2)
                        slider("Inner", $recipe.ringInnerRadius, 1.02...2.2)
                        slider("Outer", $recipe.ringOuterRadius, 1.1...3.4)
                        slider("Ringlets", $recipe.ringDetail, 0...1)
                        ColorPicker("Ice", selection: colorBinding(\.ring))
                    }
                }

                section("Light") {
                    slider("Azimuth", $recipe.lightAzimuth, 0...(.pi * 2))
                    slider("Elevation", $recipe.lightElevation, -1.2...1.2)
                    slider("Exposure", $recipe.exposure, 0.2...4)
                    // The terminator sweeping, which is a different thing from the ground
                    // turning under a light that stays put.
                    slider("Day cycle", $recipe.dayNightSpeed, 0...1.2)
                }

                section("Palette") {
                    ColorPicker("Highlight", selection: colorBinding(\.highlight))
                    ColorPicker("Primary", selection: colorBinding(\.primary))
                    ColorPicker("Shadow", selection: colorBinding(\.shadow))
                    ColorPicker("Storm", selection: colorBinding(\.storm))
                    ColorPicker("Atmosphere", selection: colorBinding(\.atmosphere))
                }

                section("Take it with you") {
                    Toggle("Pause", isOn: $paused)
                    Button("Copy recipe as JSON") { copyJSON() }
                    Button("Paste recipe") { pasteJSON() }
                    Button("Export 1024px PNG…") { exportPNG() }
                }
            }
            .padding(16)
        }
        .scrollIndicators(.automatic)
    }

    // MARK: - Pieces

    @ViewBuilder
    private func section(_ title: String, @ViewBuilder content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(title.uppercased())
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
            content()
        }
    }

    private func slider(_ label: String, _ value: Binding<Double>, _ range: ClosedRange<Double>) -> some View {
        HStack(spacing: 8) {
            Text(label).font(.caption).frame(width: 86, alignment: .leading).lineLimit(1)
            Slider(value: value, in: range)
            Text(String(format: "%.2f", value.wrappedValue))
                .font(.caption2.monospaced())
                .foregroundStyle(.secondary)
                .frame(width: 38, alignment: .trailing)
        }
    }

    private func colorBinding(_ key: WritableKeyPath<MoonletPlanetPalette, MoonletColor>) -> Binding<Color> {
        Binding(
            get: { recipe.palette[keyPath: key].color },
            set: { recipe.palette[keyPath: key] = MoonletColor($0) }
        )
    }

    // MARK: - Export

    private func note(_ text: String) {
        status = text
        Task { try? await Task.sleep(for: .seconds(2.5)); status = nil }
    }

    private func copyJSON() {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(recipe), let text = String(data: data, encoding: .utf8) else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        note("recipe copied")
    }

    private func pasteJSON() {
        guard let text = NSPasteboard.general.string(forType: .string),
              let decoded = try? JSONDecoder().decode(MoonletPlanetRecipe.self, from: Data(text.utf8)) else {
            note("clipboard is not a recipe")
            return
        }
        recipe = decoded
        note("recipe pasted")
    }

    private func exportPNG() {
        guard let image = MoonletPlanetSnapshotRenderer.image(recipe: recipe, size: 1024, time: 18) else {
            note("render failed")
            return
        }
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.png]
        panel.nameFieldStringValue = "planet.png"
        guard panel.runModal() == .OK, let url = panel.url,
              let dest = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil) else { return }
        CGImageDestinationAddImage(dest, image, nil)
        CGImageDestinationFinalize(dest)
        note("saved \(url.lastPathComponent)")
    }
}
