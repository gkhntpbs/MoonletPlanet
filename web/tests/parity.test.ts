import test from 'node:test'
import assert from 'node:assert/strict'
import { readFileSync } from 'node:fs'
import { randomized, colorFromHSB } from '../src/random.ts'
import { archetypeRecipes, solarSystem } from '../src/presets.ts'
import { validateRecipe, type PlanetRecipe } from '../src/index.ts'

type ParityCase = { seed: number; archetype: number; recipe: PlanetRecipe }
const cases: ParityCase[] = JSON.parse(readFileSync(new URL('./parity.json', import.meta.url), 'utf8'))

const archetypeByNumber = Object.values(archetypeRecipes)

test('the seeded palette matches the Swift package exactly', () => {
  assert.ok(cases.length > 0, 'parity fixtures missing — run `swift run PlanetExport`')
  for (const expected of cases) {
    const base = archetypeByNumber.find(r => r.archetype === expected.archetype)
    assert.ok(base, `no preset for archetype ${expected.archetype}`)
    const actual = randomized(base as PlanetRecipe, expected.seed)
    for (const key of ['highlight', 'primary', 'shadow', 'storm', 'atmosphere'] as const) {
      for (const channel of ['red', 'green', 'blue'] as const) {
        assert.ok(
          Math.abs(actual.palette[key][channel] - expected.recipe.palette[key][channel]) < 1e-12,
          `seed ${expected.seed} archetype ${expected.archetype} ${key}.${channel}: ` +
          `${actual.palette[key][channel]} vs ${expected.recipe.palette[key][channel]}`
        )
      }
    }
    assert.equal(actual.seed, expected.recipe.seed)
  }
})

test('the same seed is the same planet, and a different seed is not', () => {
  const base = archetypeRecipes.gasGiant as PlanetRecipe
  assert.deepEqual(randomized(base, 99), randomized(base, 99))
  assert.notDeepEqual(randomized(base, 99), randomized(base, 100))
})

test('hue wraps rather than clamping', () => {
  assert.deepEqual(colorFromHSB(1.25, 1, 1), colorFromHSB(0.25, 1, 1))
})

test('every exported preset is a valid recipe', () => {
  for (const [name, recipe] of Object.entries({ ...archetypeRecipes, ...solarSystem })) {
    assert.doesNotThrow(() => validateRecipe(recipe as PlanetRecipe), `${name} is not valid`)
  }
})

test('the ringed planets came across with their rings', () => {
  assert.ok((solarSystem.saturn.ringOpacity ?? 0) > 0, 'Saturn lost its rings in export')
  assert.ok((solarSystem.uranus.ringOpacity ?? 0) > 0)
  assert.equal(solarSystem.jupiter.ringOpacity ?? 0, 0)
  // The Cassini Division has to fall inside the system or the profile draws nothing at it.
  assert.ok(solarSystem.saturn.ringInnerRadius! < 1.95)
  assert.ok(solarSystem.saturn.ringOuterRadius! > 2.025)
})

test('the worlds with ice came across with it, and the gas giants did not', () => {
  // Ice sits on ground. A gas giant has none, and gets a polar hood in the shader instead.
  for (const name of ['jupiter', 'saturn', 'neptune', 'uranus'] as const) {
    assert.equal(solarSystem[name].iceCoverage ?? 0, 0, `${name} should carry no surface ice`)
  }
  for (const name of ['earth', 'mars', 'pluto'] as const) {
    assert.ok((solarSystem[name].iceCoverage ?? 0) > 0, `${name} lost its caps in export`)
  }
  // No real world has two matching caps.
  assert.notEqual(solarSystem.mars.polarAsymmetry ?? 0, 0)
})

test('a tilted planet carries its tilt across', () => {
  // Uranus is on its side and that is most of what it looks like.
  assert.ok((solarSystem.uranus.axialTilt ?? 0) > 1)
  assert.ok((solarSystem.earth.axialTilt ?? 0) > 0.3 && (solarSystem.earth.axialTilt ?? 0) < 0.5)
})

test('rings that are inside out are refused rather than drawn', () => {
  const bad = { ...(solarSystem.saturn as PlanetRecipe), ringInnerRadius: 2.5, ringOuterRadius: 1.5 }
  assert.throws(() => validateRecipe(bad), RangeError)
  const inside = { ...(solarSystem.saturn as PlanetRecipe), ringInnerRadius: 0.4 }
  assert.throws(() => validateRecipe(inside), RangeError)
})
