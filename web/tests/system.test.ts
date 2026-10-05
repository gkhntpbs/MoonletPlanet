import test from 'node:test'
import assert from 'node:assert/strict'
import { readFileSync } from 'node:fs'
import { layoutSystem, systemExtent, placeBody, orbitPoints, skyStars, type PlanetSystem } from '../src/system.ts'
import { systemExample } from '../src/presets.ts'
import { validateRecipe } from '../src/index.ts'

type Body = { index: number | null; x: number; y: number; depth: number; radius: number; lightAzimuth: number; lightElevation: number; rotationPhase: number; axialTilt: number; roll: number; exposure: number; orbit: number[]; light: { red: number; green: number; blue: number } }
type SystemCase = { system: PlanetSystem; time: number; extent: number; layout: Body[]; starfield: number[] }
const cases: SystemCase[] = JSON.parse(readFileSync(new URL('./systems.json', import.meta.url), 'utf8'))
// Swift leaves a nil out of its JSON altogether; the star is the body with no index.
for (const c of cases) for (const body of c.layout) body.index ??= null
const close = (a: number, b: number) => Math.abs(a - b) < 1e-9

test('a system lays out exactly as the Swift package does', () => {
  assert.ok(cases.length > 0, 'system fixtures missing — run `swift run PlanetExport`')
  for (const expected of cases) {
    assert.ok(close(systemExtent(expected.system), expected.extent), 'extent')
    const actual = layoutSystem(expected.system, expected.time)
    assert.deepEqual(actual.map(p => p.index), expected.layout.map(p => p.index), 'draw order')
    actual.forEach((p, i) => {
      const e = expected.layout[i]
      const where = `t=${expected.time} elevation=${expected.system.viewElevation} body ${e.index}`
      for (const key of ['x', 'y', 'depth', 'radius'] as const) assert.ok(close(p[key], e[key]), `${where} ${key}: ${p[key]} vs ${e[key]}`)
      // Every body, the star too, is turned to the camera in perspective.
      assert.ok(close(p.recipe.rotationPhase ?? 0, e.rotationPhase), `${where} rotationPhase: ${p.recipe.rotationPhase} vs ${e.rotationPhase}`)
      assert.ok(close(p.recipe.axialTilt ?? 0, e.axialTilt), `${where} axialTilt: ${p.recipe.axialTilt} vs ${e.axialTilt}`)
      assert.ok(close(p.recipe.roll ?? 0, e.roll), `${where} roll`)
      assert.ok(close(p.roll, e.roll), `${where} placement roll`)
      assert.ok(close(p.recipe.exposure, e.exposure), `${where} exposure`)
      if (e.index !== null) {
        assert.ok(close(p.recipe.lightAzimuth, e.lightAzimuth), `${where} azimuth`)
        assert.ok(close(p.recipe.lightElevation, e.lightElevation), `${where} elevation`)
        const orbit = orbitPoints(expected.system, e.index, 8).flatMap(q => [q.x, q.y, q.depth])
        orbit.forEach((v, k) => assert.ok(close(v, e.orbit[k]), `${where} orbit[${k}]`))
        for (const c of ['red', 'green', 'blue'] as const) assert.ok(close(p.recipe.palette.light![c], e.light[c]), `${where} light.${c}`)
      }
    })
    const stars = skyStars(expected.system, 500, 500, expected.time).slice(0, 24).flatMap(s => [s.x, s.y, s.radius, s.alpha, s.red, s.green, s.blue])
    assert.equal(stars.length, expected.starfield.length, 'starfield count')
    stars.forEach((v, k) => assert.ok(close(v, expected.starfield[k]), `starfield[${k}]: ${v} vs ${expected.starfield[k]}`))
  }
})

test('the planets in a system stay valid recipes, and their own are untouched', () => {
  const system = structuredClone(systemExample)
  const before = structuredClone(system.bodies[0].recipe)
  for (const p of layoutSystem(system, 12)) assert.doesNotThrow(() => validateRecipe(p.recipe))
  assert.deepEqual(system.bodies[0].recipe, before)
})

test('a planet dragged to a point is there', () => {
  const system = structuredClone(systemExample)
  system.viewElevation = 0.6
  placeBody(system, 1, -2.5, 0.8, 7)
  const p = layoutSystem(system, 7).find(p => p.index === 1)!
  assert.ok(close(p.x, -2.5) && close(p.y, 0.8))
})
