# Changelog

Notable changes to MoonletPlanet. The format is
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and this project follows
[semver](https://semver.org).

**What a major version means here.** `MoonletPlanetRecipe` is a stored format — somebody's
planet is a couple of dozen numbers they saved. Adding a field with a default is minor;
removing one, renaming one, or changing what a value *means* is major, even when every call
site still compiles. A planet that comes back looking different from the one that was saved
is the breakage this rule exists to prevent.

Changing how the shader draws a given recipe is a minor version and is noted under
**Changed**, because the pixels moved even though the format did not.

## [1.0.0] — 2026-09-06

First release. Extracted from Moonlet's mascot lab, where the planet had lived since August
2026 and never had a reason to know about the mascot orbiting it.

### The planet

- `MoonletPlanetRecipe` — a couple of dozen parameters, `Codable`, `Hashable`, `Sendable`.
  The whole planet, and the only thing that needs storing.
- Ten archetypes: gas giant, ice giant, ocean, frozen, rocky, molten, desert, toxic, lush,
  cloud. Each is its own surface function; the shader dispatches on the archetype's number,
  so the case order is a wire format.
- Ten solar system presets through `MoonletPlanetPreset`, with the real obliquities, ice and
  rings.
- `randomized(seed:)` — a seeded palette, so the same seed is the same planet forever.

### Rings, and they are Saturn's

The radii and optical depths are Cassini's measurements: the C ring from 1.235 planet radii,
the B ring to 1.95, the Cassini Division to 2.025, the A ring to 2.27 with the Encke and
Keeler gaps cut into it. `ringInnerRadius` and `ringOuterRadius` *stretch* that anatomy
rather than replacing it, so a narrower system still has a Division in the right place.

The ring plane is the planet's equator and the camera is orthographic, so the intersection
has a closed form — no marching, no second pass, no geometry. Everything that makes rings
read as rings falls out of it: the near arc in front of the planet and the far arc behind,
the planet's shadow across the rings, the rings' shadow band on the planet, the unlit face
seen by transmitted light, the opposition surge, and per-pixel ringlet fading so a nearly
edge-on system does not alias.

### Ice, from where it actually freezes

`iceCoverage`, `iceAltitude` and `polarAsymmetry`, plus `palette.ice`. Nothing is drawing a
cap: annual mean insolation is the second-Legendre approximation
`S(phi) proportional to 1 - 0.482*P2(sin phi)`, and ice sits where that, minus a lapse rate
times altitude, falls under an isotherm that `iceCoverage` moves. Caps with the right shape,
highland ice far from the poles, hemispheres that differ, and a snowball at the top of the
range all fall out of the model rather than being special-cased. Gas giants get the polar
hood they really have.

### One tilt

`axialTilt` is the planet's pole and therefore also the angle its rings are seen at — rings
lie in the equator, so these were never two settings. Bands, ice and the daily rotation are
computed in the planet's own frame, so a tilted world's weather tilts with it.
`rotationPhase` turns it through its own day independently of the clock, which is what both
workbenches drag.

### Drawing it

- `MoonletPlanetView` for SwiftUI, with `frozenTime` for a still frame and `timeScale` for
  reduced motion.
- `MoonletPlanetSnapshotRenderer` — a `CGImage` at any size, off screen.
- `MoonletPlanetFallback`, drawn where Metal is unavailable, keeping the palette and the
  light direction. Probe it with `MoonletPlanetRendering.isMetalAvailable`.
- The shader emits premultiplied alpha and the pipeline blends accordingly, which is what
  lets a semi-transparent ring composite over the planet and over nothing with the same
  arithmetic.

### In the browser

`web/` is a dependency-free WebGL2 port. Nothing in it is written twice: the GLSL is
generated from the Metal source, the presets are exported from the Swift definitions, and
the seeded randomizer is held to Swift's own output to the last bit of a double.
`npm run check:source` fails if any of them have drifted.

`npm run accept` compiles the shader in real headless Chrome and asserts that every planet
actually paints — a shader that compiles is not a shader that draws. A planet with no rings
is a circle inscribed in a square, so it has to come back at pi/4.

Early, and honest about it: there is no convenience view layer, so a caller owns the canvas
and the clock, and the npm package is not published.

### Working on it

- `make studio` — a macOS workbench with every parameter on a slider next to the planet,
  the solar system presets, a randomizer, drag-to-turn, and buttons to copy the recipe as
  JSON or export a PNG.
- `make web-studio` — the same panel in a browser against the WebGL2 renderer, rebuilding as
  you edit. Both take the same recipe JSON, so a planet copied from one pastes into the
  other.
- `make docs` renders every image the README uses.
- A `Makefile`, GitHub Actions CI, and `CONTRIBUTING.md` — which says the two things that are
  easy to get wrong: the shader's uniform struct exists twice, and the recipe is stored data.
