# MoonletPlanet — web

The same planets in the browser, in WebGL2, with no dependencies at runtime.

```ts
import { createPlanetRenderer, solarSystem } from '@moonlet/planet'

const renderer = createPlanetRenderer(canvas)   // null if there is no WebGL2
renderer.render(solarSystem.saturn, 18, 400, 400, devicePixelRatio)
```

Create one renderer per canvas, call `render(recipe, seconds, width, height, pixelRatio)`
with CSS dimensions, and `dispose()` on removal. The caller owns the clock — this module
has no animation loop, no mascot and no orbit. Pixel ratio is capped at two, as on iOS.
A missing WebGL2 context returns `null`; a shader that fails to compile throws, and the
host is expected to show a fallback and rebuild the renderer after context restoration. No
frame is submitted after `dispose()` or during context loss.

## Nothing here is written twice

Three files in `src/` are **generated from the Swift package** and are not edited by hand:

| | from | regenerate |
|---|---|---|
| `src/shaders.ts` | `Sources/MoonletPlanet/Shaders/PlanetRenderer.metal` | `npm run generate` |
| `src/presets.ts` | the Swift presets | `swift run PlanetExport` |
| `tests/parity.json` | Swift's `randomized(seed:)` | `swift run PlanetExport` |

`npm run check:source` fails if the checked-in GLSL has drifted from the Metal, and CI runs
it. The generator only performs *mechanical* translation — types, address-space qualifiers,
integer literal suffixes, how a fragment returns — and throws rather than guessing if it
meets a construct it was not taught. Every surface equation lives in the Metal file.

`src/random.ts` is the one deliberate re-implementation: SplitMix64, ported so a seed
produces the same planet in a browser as on a phone. `tests/parity.json` holds it to that,
to the last bit of a double.

## Commands

```sh
npm run studio      # the workbench, in a browser, rebuilding as you edit
npm test            # parity with Swift, preset validity, ring validation
npm run typecheck   # tsc, strict
npm run check:source # the GLSL is current with the Metal
npm run accept      # compile in real Chrome and assert every planet paints
```

`npm run studio` (or `make web-studio` from the package root, which also opens the browser)
serves `dev/` on <http://127.0.0.1:8791> with esbuild rebuilding the bundle on every request.
It is the same workbench the macOS `PlanetStudio` is — every parameter on a slider next to
the planet, the solar system presets, a randomizer, and buttons to copy the recipe as JSON
or save a PNG — so a shader change can be looked at in the browser it will ship in.

One thing to know: esbuild's server **stops when its stdin closes**, which is what it does
when you background it. Run it in a terminal and leave it there.

`npm run accept` is the one that matters. It bundles the module, serves `dev/`, runs
headless Chrome and reads back each canvas's alpha coverage — because a shader that
compiles is not a shader that draws. A planet with no rings is a circle inscribed in a
square, so it has to come back at π/4 ≈ 0.785; anything less and something rendered
nothing. Point `CHROME=` at another binary if yours is elsewhere.

`dev/acceptance.html` is that grid, and `dev/index.html` is the studio. The acceptance page
animates only with `?animate`; a headless run with an open `requestAnimationFrame` loop never
finishes advancing virtual time.

## Still missing

- No ring composition helper: rings are in the recipe and the shader draws them, but there
  is no equivalent of the Swift `MoonletPlanetView` convenience layer.
- The npm package is `private`. It is published nowhere yet.
