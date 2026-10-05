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

    // A system is edited through the same panel as a planet: whichever body is selected
    // is `recipe`, and every change to `recipe` is written back into the system.
    @State private var mode = Mode.planet
    @State private var system: MoonletPlanetSystem = {
        // The studio looks through a real camera; the library's default stays flat.
        var system = MoonletPlanetSystem.example
        system.perspective = 0.8
        system.showsOrbits = true
        system.sky.isVisible = true
        return system
    }()
    /// How quickly a flicked camera slows, per second. Higher stops it sooner.
    @State private var coastFriction = 2.2
    /// The selected body, or `nil` for the star.
    @State private var selection: Int?
    /// The body a drag on the stage picked up.
    @State private var dragging: Int?
    /// Where the camera was when a drag on empty space began, which turns it.
    @State private var cameraStart: (azimuth: Double, elevation: Double)?
    /// The zoom when a pinch began.
    @State private var zoomStart: Double?
    @State private var clock = Clock()

    enum Mode: String, CaseIterable { case planet = "Planet", system = "System" }

    /// The studio keeps the system's time itself, so a drag knows where a moving planet is.
    final class Clock {
        var started = Date()
        var now: Double = 0
        /// The camera's spin after a drag is let go, in radians a second, and when it was
        /// last applied. It runs down rather than stopping dead, which is most of what
        /// makes a turned camera feel like a camera.
        var spin: Double = 0
        var lastSpin = Date()
    }

    var body: some View {
        HStack(spacing: 0) {
            stage
            Divider()
            controls
                .frame(width: 340)
        }
        .background(Color(red: 0.035, green: 0.04, blue: 0.05))
        .preferredColorScheme(.dark)
        .onChange(of: recipe) { _, new in
            guard mode == .system else { return }
            if let index = selection, system.bodies.indices.contains(index) {
                system.bodies[index].recipe = new
            } else if selection == nil {
                system.star = new
            }
        }
    }

    @ViewBuilder
    private var stage: some View {
        if mode == .system { systemStage } else { planetStage }
    }

    private var systemStage: some View {
        GeometryReader { proxy in
            // The view fits the system in the largest square in the middle and fills the rest
            // with sky; the drag has to measure the same square.
            let side = min(proxy.size.width, proxy.size.height)
            let scale = side / 2 / max(system.extent, 1e-6)
            let centre = CGPoint(x: proxy.size.width / 2, y: proxy.size.height / 2)
            TimelineView(.animation(paused: paused)) { context in
                let time = clockTime(context.date)
                MoonletSystemView(system: system, frozenTime: time)
                    .frame(width: proxy.size.width, height: proxy.size.height)
                    .position(centre)
                    .onChange(of: context.date) { _, now in coast(now) }
            }
            .contentShape(Rectangle())
            // Drag a planet to move it: it picks up whichever planet is nearest where the
            // drag began, and both its distance and its place on the orbit follow. Drag
            // anywhere else to walk the camera round the system, all the way round.
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        let point = { (p: CGPoint) in ((p.x - centre.x) / scale, (centre.y - p.y) / scale) }
                        let time = clock.now
                        if dragging == nil && cameraStart == nil {
                            let (sx, sy) = point(value.startLocation)
                            let hit = system.layout(at: time)
                                .compactMap { p in p.index.map { ($0, hypot(p.x - sx, p.y - sy) - p.radius) } }
                                .min { $0.1 < $1.1 }
                            if let hit, hit.1 < 0.6 {
                                dragging = hit.0
                                select(hit.0)
                            } else {
                                cameraStart = (system.viewAzimuth, system.viewElevation)
                            }
                        }
                        if let start = cameraStart {
                            system.viewAzimuth = (start.azimuth - value.translation.width * 0.008)
                                .remainder(dividingBy: 2 * .pi)
                            system.viewElevation = min(max(start.elevation + value.translation.height * 0.006, -.pi / 2), .pi / 2)
                            return
                        }
                        guard let index = dragging else { return }
                        let (x, y) = point(value.location)
                        system.place(index, atX: x, y: y, time: time)
                    }
                    .onEnded { value in
                        // A flick keeps turning: the drag's speed at release, in the same
                        // radians per point the drag itself uses.
                        if cameraStart != nil {
                            let flick = value.predictedEndTranslation.width - value.translation.width
                            clock.spin = -flick * 0.008 * 2.5
                            clock.lastSpin = Date()
                        }
                        dragging = nil
                        cameraStart = nil
                    }
            )
            // Pinch to zoom, as on any camera.
            .simultaneousGesture(
                MagnifyGesture()
                    .onChanged { value in
                        let start = zoomStart ?? system.zoom
                        zoomStart = start
                        system.zoom = min(max(start * value.magnification, 0.5), 4)
                    }
                    .onEnded { _ in zoomStart = nil }
            )
        }
        .background(Color(red: 0.035, green: 0.04, blue: 0.05))
    }

    private func coast(_ now: Date) {
        let dt = min(now.timeIntervalSince(clock.lastSpin), 0.1)
        clock.lastSpin = now
        guard abs(clock.spin) > 0.002, cameraStart == nil else { clock.spin = 0; return }
        system.viewAzimuth = (system.viewAzimuth + clock.spin * dt).remainder(dividingBy: 2 * .pi)
        clock.spin *= exp(-dt * coastFriction)
    }

    private func clockTime(_ date: Date) -> Double {
        let t = date.timeIntervalSince(clock.started)
        clock.now = t
        return t
    }

    private func select(_ index: Int?) {
        selection = index
        if let index { recipe = system.bodies[index].recipe } else { recipe = system.star }
    }

    private var planetStage: some View {
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
                Picker("Mode", selection: $mode) {
                    ForEach(Mode.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .onChange(of: mode) { _, new in if new == .system { select(selection) } }

                if mode == .system { systemControls }

                section(mode == .system ? (selection == nil ? "Star" : "Selected planet") : "Planet") {
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

                if recipe.archetype == .star {
                    section("Star") {
                        // 0 a ball of fire, 1 nothing but light.
                        slider("Luminosity", $recipe.luminosity, 0...1)
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
                    // A menu rather than segments: five titles do not fit the panel, and a
                    // segment that reads "Interplane" is worse than a click.
                    HStack(spacing: 8) {
                        Text("Level").font(.caption).frame(width: 86, alignment: .leading)
                        Picker("Life", selection: $recipe.life) {
                            ForEach(MoonletPlanetLife.allCases) { Text($0.title).tag($0) }
                        }
                        .labelsHidden()
                    }
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
                        HStack(spacing: 8) {
                            Text("Stations").font(.caption).frame(width: 86, alignment: .leading)
                            Stepper(value: $recipe.stationCount, in: 0...4) {
                                Text("\(recipe.stationCount)").font(.caption2.monospaced())
                            }
                        }
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

    // MARK: - System

    @ViewBuilder
    private var systemControls: some View {
        section("System") {
            // Every body as a button; the selected one is what the panel below edits.
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 2), spacing: 6) {
                bodyButton("Star", selected: selection == nil) { select(nil) }
                ForEach(system.bodies.indices, id: \.self) { i in
                    bodyButton("\(i + 1). \(system.bodies[i].recipe.archetype.title)", selected: selection == i) { select(i) }
                }
            }
            HStack {
                Menu("Add planet") {
                    ForEach(MoonletPlanetPreset.allCases.filter { $0 != .custom && $0 != .sun }) { preset in
                        Button(preset.title) { addPlanet(preset.style!.recipe) }
                    }
                    Divider()
                    ForEach(MoonletPlanetArchetype.allCases.filter { $0 != .star }) { archetype in
                        Button(archetype.title) { addPlanet(.preset(archetype)) }
                    }
                }
                if let index = selection {
                    Button("Remove") {
                        system.bodies.remove(at: index)
                        select(nil)
                    }
                }
            }
            Button("Reset camera") {
                system.viewAzimuth = 0
                system.viewElevation = 0.35
                system.zoom = 1
                clock.spin = 0
            }
            Text("Drag a planet to move it; drag empty space to turn the camera.")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        section("Camera") {
            // All the way round, and from below the plane as well as above it.
            slider("Turn", $system.viewAzimuth, -(.pi)...(.pi))
            slider("View angle", $system.viewElevation, -(.pi / 2)...(.pi / 2))
            // 0 is flat; above it nearer is bigger and every pole stays put as it turns.
            slider("Depth", $system.perspective, 0...1)
            slider("Zoom", $system.zoom, 0.5...4)
            // How soon a flicked camera stops coasting.
            slider("Coast stop", $coastFriction, 0.3...8)
        }
        section("Sky") {
            Toggle("Stars", isOn: $system.sky.isVisible)
            if system.sky.isVisible {
                HStack(spacing: 8) {
                    Text("Count").font(.caption).frame(width: 86, alignment: .leading)
                    Stepper(value: $system.sky.starCount, in: 0...5000, step: 100) {
                        Text("\(system.sky.starCount)").font(.caption2.monospaced())
                    }
                }
                HStack(spacing: 8) {
                    Text("Sky seed").font(.caption).frame(width: 86, alignment: .leading)
                    Text("\(system.sky.seed)").font(.caption2.monospaced())
                    Spacer()
                    Button("New sky") { system.sky.seed = UInt32.random(in: 1...UInt32.max) }
                }
                slider("Brightness", $system.sky.brightness, 0...2)
                slider("Star size", $system.sky.starSize, 0.3...3)
                slider("Colour range", $system.sky.warmth, 0...2)
                slider("Twinkle", $system.sky.twinkle, 0...1)
                // A Milky Way: a share of the stars gathered in a belt across the sky.
                slider("Band", $system.sky.bandStrength, 0...1)
                slider("Band tilt", $system.sky.bandTilt, -(.pi / 2)...(.pi / 2))
                ColorPicker("Star colour", selection: Binding(get: { system.sky.color.color }, set: { system.sky.color = MoonletColor($0) }))
            }
        }
        section("Orbits") {
            Toggle("Orbit lines", isOn: $system.showsOrbits)
            if system.showsOrbits {
                slider("Line opacity", $system.orbitStyle.opacity, 0...1)
                slider("Line width", $system.orbitStyle.width, 0.3...4)
                ColorPicker("Line colour", selection: Binding(get: { system.orbitStyle.color.color }, set: { system.orbitStyle.color = MoonletColor($0) }))
            }
            // Every orbit at once; 0 stops them all where they are.
            slider("All speeds", $system.orbitSpeed, 0...4)
        }
        section("Light") {
            slider("Star tint", $system.lightTint, 0...1)
            // How much dimmer the outer worlds are; 1 is the inverse-square law.
            slider("Falloff", $system.lightFalloff, 0...1)
            slider("Star size", $system.starRadius, 0.3...2)
        }
        if let index = selection, system.bodies.indices.contains(index) {
            section("Orbit") {
                slider("Distance", $system.bodies[index].distance, (system.starRadius * 1.05)...12)
                slider("Size", $system.bodies[index].radius, 0.05...1.5)
                slider("Position", $system.bodies[index].phase, -(.pi)...(.pi))
                // Zero holds it where it is put.
                slider("Speed", $system.bodies[index].speed, -0.6...0.6)
                // Out of the system's plane, and which way across it.
                slider("Inclination", $system.bodies[index].inclination, -(.pi / 2)...(.pi / 2))
                slider("Node", $system.bodies[index].node, -(.pi)...(.pi))
            }
        }
    }

    private func bodyButton(_ title: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title).font(.caption).lineLimit(1).frame(maxWidth: .infinity).padding(.vertical, 3)
        }
        .buttonStyle(.bordered)
        .tint(selected ? .accentColor : nil)
    }

    private func addPlanet(_ recipe: MoonletPlanetRecipe) {
        let furthest = system.bodies.map(\.distance).max() ?? system.starRadius * 1.5
        system.bodies.append(.init(recipe: recipe, radius: 0.35, distance: furthest + 1.2, phase: Double.random(in: -.pi ... .pi), speed: 0.1))
        select(system.bodies.count - 1)
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
