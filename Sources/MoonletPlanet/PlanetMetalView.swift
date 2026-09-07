import SwiftUI
@preconcurrency import MetalKit
import MoonletPlanetShaderTypes

#if canImport(AppKit)
private final class MoonletTransparentMTKView: MTKView {
    override var isOpaque: Bool { false }
}

struct MoonletPlanetMetalView: NSViewRepresentable {
    let recipe: MoonletPlanetRecipe
    let frozenTime: Double?
    var timeScale: Double = 1
    var isPaused = false

    func makeCoordinator() -> MoonletPlanetRenderer? {
        MoonletPlanetRenderer(recipe: recipe, timeOverride: frozenTime)
    }

    func makeNSView(context: Context) -> MTKView {
        context.coordinator?.makeView() ?? MTKView(frame: .zero, device: nil)
    }

    func updateNSView(_ view: MTKView, context: Context) {
        context.coordinator?.recipe = recipe
        context.coordinator?.timeOverride = frozenTime
        context.coordinator?.timeScale = timeScale
    }
}
#elseif canImport(UIKit)
struct MoonletPlanetMetalView: UIViewRepresentable {
    let recipe: MoonletPlanetRecipe
    let frozenTime: Double?
    var timeScale: Double = 1
    var isPaused = false

    func makeCoordinator() -> MoonletPlanetRenderer? {
        MoonletPlanetRenderer(recipe: recipe, timeOverride: frozenTime)
    }

    func makeUIView(context: Context) -> MTKView {
        context.coordinator?.makeView() ?? MTKView(frame: .zero, device: nil)
    }

    func updateUIView(_ view: MTKView, context: Context) {
        context.coordinator?.recipe = recipe
        context.coordinator?.timeOverride = frozenTime
        context.coordinator?.timeScale = timeScale
        // A frozen planet draws the same pixels every frame, so sixty of them a second is
        // sixty draws that change nothing. `isPaused` with on-demand drawing keeps the one
        // frame on screen and stops the display link; `setNeedsDisplay` covers the case
        // where the recipe changed while frozen, which is the icon studies changing a
        // colour and expecting to see it.
        //
        // Being off screen stops it for a different reason and with a different rule: there
        // is nothing to redraw when the recipe changes, because nobody is looking. So the
        // two conditions share `isPaused` and only the frozen one asks for a frame.
        let frozen = frozenTime != nil
        view.isPaused = frozen || isPaused
        view.enableSetNeedsDisplay = frozen
        if frozen { view.setNeedsDisplay() }
    }
}
#endif

final class MoonletPlanetRenderer: NSObject, MTKViewDelegate {
    var recipe: MoonletPlanetRecipe
    var timeOverride: Double?

    /// How fast the planet's own weather runs. 1 is as designed.
    ///
    /// Separate from `timeOverride`, which pins one instant so an icon study renders the
    /// same frame every time. This scales the passage of time instead, which is what a
    /// phone asking for less motion actually wants: the clouds still move, slowly, rather
    /// than the planet becoming a photograph.
    ///
    /// Applied to the *elapsed* value rather than by slowing the display link, so the
    /// shader keeps receiving a smooth monotonic time and nothing stutters.
    var timeScale: Double = 1

    fileprivate let device: any MTLDevice
    fileprivate let commandQueue: any MTLCommandQueue
    fileprivate let pipeline: any MTLRenderPipelineState
    private let startedAt = CACurrentMediaTime()

    init?(recipe: MoonletPlanetRecipe, timeOverride: Double? = nil) {
        guard let shared = SharedContext.shared else { return nil }
        self.recipe = recipe
        self.timeOverride = timeOverride
        self.device = shared.device
        self.commandQueue = shared.commandQueue
        self.pipeline = shared.pipeline
        super.init()
    }

    /// Device, queue and pipeline are built once and shared by every planet on screen.
    ///
    /// Each renderer used to compile its own — which meant a screen showing twelve
    /// mascots compiled the shader twelve times and held twelve pipelines. The state is
    /// per-draw uniforms, so there is nothing per-instance worth duplicating.
    ///
    /// `@unchecked Sendable` and it is safe: the three things it holds are created once and
    /// never mutated, and `MTLDevice`, `MTLCommandQueue` and `MTLRenderPipelineState` are
    /// documented as safe to use from multiple threads. The annotation is needed because the
    /// Metal protocols are not themselves marked `Sendable`, which older toolchains treat as
    /// an error on a `static let` rather than a warning — so without it this package builds
    /// on one Mac and not on another.
    fileprivate struct SharedContext: @unchecked Sendable {
        let device: any MTLDevice
        let commandQueue: any MTLCommandQueue
        let pipeline: any MTLRenderPipelineState

        static let shared: SharedContext? = {
            guard let device = MTLCreateSystemDefaultDevice(),
                  let commandQueue = device.makeCommandQueue(),
                  let library = MoonletPlanetRenderer.makeLibrary(device: device),
                  let vertex = library.makeFunction(name: "moonletPlanetVertex"),
                  let fragment = library.makeFunction(name: "moonletPlanetFragment") else {
                return nil
            }
            let descriptor = MTLRenderPipelineDescriptor()
            descriptor.vertexFunction = vertex
            descriptor.fragmentFunction = fragment
            descriptor.colorAttachments[0].pixelFormat = .bgra8Unorm
            descriptor.colorAttachments[0].isBlendingEnabled = true
            descriptor.colorAttachments[0].sourceRGBBlendFactor = .one
            descriptor.colorAttachments[0].destinationRGBBlendFactor = .oneMinusSourceAlpha
            descriptor.colorAttachments[0].sourceAlphaBlendFactor = .one
            descriptor.colorAttachments[0].destinationAlphaBlendFactor = .oneMinusSourceAlpha
            guard let pipeline = try? device.makeRenderPipelineState(descriptor: descriptor) else {
                return nil
            }
            return SharedContext(device: device, commandQueue: commandQueue, pipeline: pipeline)
        }()
    }

    /// Two build systems ship this shader two different ways, so both are tried.
    ///
    /// Xcode compiles `PlanetRenderer.metal` into the target's `default.metallib` and
    /// does not copy the source. SwiftPM's `.process("Shaders")` copies the source and
    /// produces no metallib. Precompiled first — it is faster and cannot fail to parse.
    fileprivate static func makeLibrary(device: any MTLDevice) -> (any MTLLibrary)? {
        if let library = try? device.makeDefaultLibrary(bundle: Bundle.module),
           library.makeFunction(name: "moonletPlanetVertex") != nil {
            return library
        }
        let url = Bundle.main.url(forResource: "PlanetRenderer", withExtension: "metal")
            ?? Bundle.module.url(forResource: "PlanetRenderer", withExtension: "metal")
        guard let url, let source = try? String(contentsOf: url, encoding: .utf8) else { return nil }
        return try? device.makeLibrary(source: source, options: nil)
    }

    /// Whether the planet can be rendered at all on this device and in this bundle.
    /// Probed once; callers fall back to the SwiftUI planet when false.
    static var isAvailable: Bool { SharedContext.shared != nil }

    /// The shader is fragment-bound: six octaves of noise, a lit sphere and an atmosphere,
    /// evaluated per pixel per frame. At native scale a 424pt stage on a 3× phone is 1.6
    /// million of those a frame; at 2× it is 720 thousand. The subject is a softly shaded
    /// sphere with no text and no hard edges on it, so the half of the resolution being paid
    /// for buys nothing that survives the atmosphere's own gradient — and the ring, the face
    /// and the name are SwiftUI, still drawn at full scale on top.
    static let maximumContentScale: CGFloat = 2

    @MainActor func makeView() -> MTKView {
        #if canImport(AppKit)
        let view = MoonletTransparentMTKView(frame: .zero, device: device)
        #else
        let view = MTKView(frame: .zero, device: device)
        view.contentScaleFactor = min(Self.maximumContentScale, view.traitCollection.displayScale)
        #endif
        view.delegate = self
        view.colorPixelFormat = .bgra8Unorm
        view.clearColor = MTLClearColorMake(0, 0, 0, 0)
        #if canImport(AppKit)
        view.layer?.isOpaque = false
        view.layer?.backgroundColor = NSColor.clear.cgColor
        #else
        view.isOpaque = false
        view.backgroundColor = .clear
        #endif
        view.framebufferOnly = true
        view.preferredFramesPerSecond = 60
        view.autoResizeDrawable = true
        return view
    }

    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {
        // `size` is in pixels and already carries the capped scale, so the thresholds are
        // compared against the point size the placement actually asked for.
        #if canImport(UIKit)
        let scale = min(Self.maximumContentScale, view.traitCollection.displayScale)
        #else
        let scale = view.window?.backingScaleFactor ?? 2
        #endif
        let side = min(size.width, size.height) / max(1, scale)
        view.preferredFramesPerSecond = side < 96 ? (side < 60 ? 20 : 30) : 60
    }

    func draw(in view: MTKView) {
        guard let descriptor = view.currentRenderPassDescriptor,
              let drawable = view.currentDrawable,
              let commandBuffer = commandQueue.makeCommandBuffer(),
              let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: descriptor) else { return }
        let elapsed = (CACurrentMediaTime() - startedAt) * timeScale
        var uniforms = makeUniforms(size: view.drawableSize, time: timeOverride ?? elapsed)
        encoder.setRenderPipelineState(pipeline)
        encoder.setFragmentBytes(&uniforms, length: MemoryLayout<MoonletPlanetUniforms>.stride, index: 0)
        encoder.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4)
        encoder.endEncoding()
        commandBuffer.present(drawable)
        commandBuffer.commit()
    }

    // Assigned field by field rather than through the memberwise initialiser: at thirty-odd
    // arguments the type-checker gives up on the single expression, and the error it gives
    // ("unable to type-check in reasonable time") says nothing about which field is new.
    fileprivate func makeUniforms(size: CGSize, time: Double) -> MoonletPlanetUniforms {
        let palette = recipe.palette
        var u = MoonletPlanetUniforms()
        u.viewportSize = SIMD2(Float(size.width), Float(size.height))
        u.time = Float(time)
        u.archetype = recipe.archetype.rawValue
        u.seed = recipe.seed
        u.rotationSpeed = Float(recipe.rotationSpeed)
        u.turbulence = Float(recipe.turbulence)
        u.detail = Float(recipe.detail)
        u.warpStrength = Float(recipe.warpStrength)
        u.bandCount = Float(recipe.bandCount)
        u.bandSharpness = Float(recipe.bandSharpness)
        u.stormCount = Float(recipe.stormCount)
        u.stormStrength = Float(recipe.stormStrength)
        u.cloudCoverage = Float(recipe.cloudCoverage)
        u.cloudSpeed = Float(recipe.cloudSpeed)
        u.atmosphereDensity = Float(recipe.atmosphereDensity)
        u.atmosphereGlow = Float(recipe.atmosphereGlow)
        u.roughness = Float(recipe.roughness)
        u.featureAmount = Float(recipe.featureAmount)
        u.lightAzimuth = Float(recipe.lightAzimuth)
        u.lightElevation = Float(recipe.lightElevation)
        u.exposure = Float(recipe.exposure)
        u.ringOpacity = Float(recipe.ringOpacity)
        u.axialTilt = Float(recipe.axialTilt)
        u.ringInnerRadius = Float(recipe.ringInnerRadius)
        u.ringOuterRadius = Float(recipe.ringOuterRadius)
        u.ringDetail = Float(recipe.ringDetail)
        u.iceCoverage = Float(recipe.iceCoverage)
        u.iceAltitude = Float(recipe.iceAltitude)
        u.polarAsymmetry = Float(recipe.polarAsymmetry)
        u.microDetail = Float(recipe.microDetail)
        u.rotationPhase = Float(recipe.rotationPhase)
        u.dayNightSpeed = Float(recipe.dayNightSpeed)
        u.life = recipe.life.rawValue
        u.stationCount = UInt32(clamping: max(0, recipe.stationCount))
        u.stationOrbitRadius = Float(recipe.stationOrbitRadius)
        u.stationSpeed = Float(recipe.stationSpeed)
        u.stationInclination = Float(recipe.stationInclination)
        u.stationSize = Float(recipe.stationSize)
        u.color0 = palette.highlight.simd
        u.color1 = palette.primary.simd
        u.color2 = palette.shadow.simd
        u.color3 = palette.storm.simd
        u.atmosphereColor = palette.atmosphere.simd
        u.ringColor = palette.ring.simd
        u.iceColor = palette.ice.simd
        u.lifeColor = palette.life.simd
        return u
    }
}

public enum MoonletPlanetSnapshotRenderer {
    @MainActor public static func image(recipe: MoonletPlanetRecipe, size: Int, time: Double) -> CGImage? {
        guard size > 0,
              let renderer = MoonletPlanetRenderer(recipe: recipe, timeOverride: time),
              let texture = renderer.device.makeTexture(descriptor: textureDescriptor(size: size)),
              let commandBuffer = renderer.commandQueue.makeCommandBuffer() else { return nil }
        let descriptor = MTLRenderPassDescriptor()
        descriptor.colorAttachments[0].texture = texture
        descriptor.colorAttachments[0].loadAction = .clear
        descriptor.colorAttachments[0].storeAction = .store
        descriptor.colorAttachments[0].clearColor = MTLClearColorMake(0, 0, 0, 0)
        guard let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: descriptor) else { return nil }
        var uniforms = renderer.makeUniforms(size: CGSize(width: size, height: size), time: time)
        encoder.setRenderPipelineState(renderer.pipeline)
        encoder.setFragmentBytes(&uniforms, length: MemoryLayout<MoonletPlanetUniforms>.stride, index: 0)
        encoder.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4)
        encoder.endEncoding()
        commandBuffer.commit()
        commandBuffer.waitUntilCompleted()
        guard commandBuffer.status == .completed else { return nil }
        let bytesPerRow = size * 4
        var bytes = [UInt8](repeating: 0, count: bytesPerRow * size)
        texture.getBytes(&bytes, bytesPerRow: bytesPerRow, from: MTLRegionMake2D(0, 0, size, size), mipmapLevel: 0)
        guard let provider = CGDataProvider(data: Data(bytes) as CFData),
              let colorSpace = CGColorSpace(name: CGColorSpace.sRGB) else { return nil }
        return CGImage(
            width: size,
            height: size,
            bitsPerComponent: 8,
            bitsPerPixel: 32,
            bytesPerRow: bytesPerRow,
            space: colorSpace,
            bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedFirst.rawValue).union(.byteOrder32Little),
            provider: provider,
            decode: nil,
            shouldInterpolate: true,
            intent: .defaultIntent
        )
    }

    private static func textureDescriptor(size: Int) -> MTLTextureDescriptor {
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .bgra8Unorm, width: size, height: size, mipmapped: false)
        descriptor.storageMode = .shared
        descriptor.usage = [.renderTarget]
        return descriptor
    }
}

private extension MoonletColor {
    var simd: SIMD4<Float> {
        SIMD4(Float(red), Float(green), Float(blue), Float(opacity))
    }
}
