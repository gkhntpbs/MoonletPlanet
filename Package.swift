// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "MoonletPlanet",
    platforms: [.macOS(.v14), .iOS(.v17), .tvOS(.v17), .visionOS(.v1)],
    products: [
        .library(name: "MoonletPlanet", targets: ["MoonletPlanet"])
    ],
    targets: [
        .target(name: "MoonletPlanetShaderTypes", publicHeadersPath: "include"),
        .target(
            name: "MoonletPlanet",
            dependencies: ["MoonletPlanetShaderTypes"],
            resources: [.process("Shaders")]
        ),
        // Renders the README's images. Not part of the library product.
        .executableTarget(name: "PlanetGallery", dependencies: ["MoonletPlanet"]),
        // The workbench: every parameter on a slider, next to the planet it changes.
        .executableTarget(name: "PlanetStudio", dependencies: ["MoonletPlanet"]),
        // Writes the web port's presets and parity fixtures from these definitions.
        .executableTarget(name: "PlanetExport", dependencies: ["MoonletPlanet"]),
        .testTarget(name: "MoonletPlanetTests", dependencies: ["MoonletPlanet"])
    ]
)
