# Contributing

Everything runs from the package root. `make` on its own lists the targets.

```sh
make studio       # the workbench: every parameter on a slider, next to the planet
make web-studio   # the same thing in a browser, on the WebGL2 renderer
make test         # the Swift tests
make check        # everything CI runs
```

## The workbench is the development loop

`make studio` opens a macOS window with the planet on the left and every parameter on the
right, plus the solar system presets, a randomizer, and buttons to copy the recipe as JSON
or export a 1024px PNG. Change the shader, run it again, look.

That is the intended way to work on a surface function. Rendering a contact sheet and
squinting at it is the slow version of the same loop.

`make web-studio` is the same panel against the WebGL2 renderer, served on
<http://127.0.0.1:8791> with esbuild rebuilding as you edit. Use it to check that a shader
change survived the translation to GLSL — the two studios take the same recipe JSON, so a
planet can be copied from one and pasted into the other.

## Changing the shader

`Sources/MoonletPlanet/Shaders/PlanetRenderer.metal` is the planet. Three things travel
with it and are easy to forget:

1. **The uniform struct exists twice** — in the `.metal` file and in
   `Sources/MoonletPlanetShaderTypes/include/MoonletPlanetShaderTypes.h`. They must match
   field for field and in order, because Swift fills the buffer using the header's layout
   and the GPU reads it using the shader's. A mismatch does not fail to compile; it draws
   the wrong planet, and the field that looks wrong is rarely the field you added.
2. **Order and types must match exactly**, field for field. Both compilers apply the same C
   layout rules — scalars align to four bytes, the `float4` block to sixteen — so the
   trailing padding works itself out and the field *count* does not matter. What does matter
   is that neither struct grows a field the other lacks, or in a different place.
3. **The web shader is generated** from the Metal source. Run `make web` after any change
   and commit the result; `make web-check` is what CI runs to catch the copy that drifted.

Then `make docs` and commit the images — CI fails if the rendered documentation does not
match the shader that is checked in.

## Changing the recipe

`MoonletPlanetRecipe` is a **stored format**. Somebody's planet is nineteen-odd numbers they
saved, so:

- A new field gets a default **and** a line in `init(from:)` using `decodeIfPresent`. The
  synthesised `Codable` throws `keyNotFound` on a field that did not exist when they saved,
  which loses the planet rather than the field.
- A field that changes meaning or disappears is a **major** version, even when everything
  still compiles. See `CHANGELOG.md`.
- Add a case to `recipesSavedBeforeRingsStillDecode` — that test is the rule.

## Adding an archetype

`MoonletPlanetArchetype` is `UInt32`-raw-valued and the shader dispatches on the number, so
the case order is a wire format: append, never insert. Add the surface function, add the
branch, add a preset, and check `everyArchetypeHasItsOwnPreset` still passes — it exists
because the dispatch has a `default` arm and a new case otherwise renders silently as a gas
giant.

## Style

The Swift is dense and comment-light; the comments that are there say *why*, not what. Match
that. Tokens, ranges and magic numbers belong next to a sentence explaining where they came
from — the ring profile's radii are Cassini's measurements and the file says so.
