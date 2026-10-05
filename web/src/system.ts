// A star and the worlds around it, each lit from wherever the star is.
//
// Ported from `MoonletPlanetSystem` in the Swift package, line for line, and held to it by
// `tests/systems.json`, which the Swift side writes: the same system at the same time has
// to put every planet in the same place and light it from the same side in both.
//
// Everything is in one unit, the system's own: the star's radius, each planet's radius and
// each orbit's distance. The planets' recipes are never changed; `layoutSystem` returns lit
// copies.

import type { PlanetColor, PlanetRecipe } from './index.ts'

export type PlanetOrbit = {
  id?: string
  recipe: PlanetRecipe
  /** The planet's radius, in system units. */
  radius: number
  /** From the star's centre, in system units. */
  distance: number
  /** Where on the orbit it is at time zero, in radians: 0 right of the star, π/2 behind it. */
  phase: number
  /** Radians a second. Zero holds it still. */
  speed: number
  /** How far the orbit is tipped out of the system's plane, in radians. 0 if absent. */
  inclination?: number
  /** Which way across the plane a tipped orbit crosses it, in radians. 0 if absent. */
  node?: number
}

/** How a system's orbit lines are drawn. */
export type OrbitStyle = {
  /** The near half's opacity; the far half is two thirds of it. */
  opacity: number
  /** In CSS pixels. */
  width: number
  color: PlanetColor
}

/** The sky behind a system. */
export type Sky = {
  isVisible: boolean
  starCount: number
  /** Which sky. 0 is the one the package has always drawn. */
  seed: number
  brightness: number
  starSize: number
  /** How much the stars vary in colour. 0 is all one colour. */
  warmth: number
  color: PlanetColor
  twinkle: number
  /** What share of the stars gather in a band, like the Milky Way. */
  bandStrength: number
  bandTilt: number
}

export const defaultOrbitStyle: OrbitStyle = { opacity: 0.28, width: 1, color: { red: 1, green: 1, blue: 1, opacity: 1 } }
export const defaultSky: Sky = {
  isVisible: false, starCount: 900, seed: 0, brightness: 1, starSize: 1, warmth: 1,
  color: { red: 1, green: 1, blue: 1, opacity: 1 }, twinkle: 0, bandStrength: 0, bandTilt: 1,
}

export type PlanetSystem = {
  star: PlanetRecipe
  starRadius: number
  bodies: PlanetOrbit[]
  /** Radians above the orbital plane: 0 edge-on, π/2 straight down, below zero from underneath. */
  viewElevation: number
  /** Where round the system the camera is, in radians. 0 if absent. */
  viewAzimuth?: number
  /** Whether to draw each planet's orbit as a faint line. */
  showsOrbits?: boolean
  /**
   * How much the camera sees in depth. 0 (or absent) is flat. Above zero it is a real
   * camera: nearer worlds are larger, orbits narrow towards the back, and every body keeps
   * its pole, rings and face fixed in the system as the camera walks round it.
   */
  perspective?: number
  /** 1 fits the whole system; 2 shows the middle half, larger. */
  zoom?: number
  /** 0 lights every world the same; 1 is the inverse-square law from three star radii out. */
  lightFalloff?: number
  /** A multiplier on every orbit's speed. */
  orbitSpeed?: number
  orbitStyle?: OrbitStyle
  sky?: Sky
  /** 0 white light, 1 the star's own colour. */
  lightTint: number
}

export type Placement = {
  /** Which body, or null for the star. */
  index: number | null
  /** System units, x right and y up. */
  x: number
  y: number
  /** Towards the camera is positive; draw in increasing depth. */
  depth: number
  radius: number
  recipe: PlanetRecipe
  /** How far the drawn body is turned on screen, counter-clockwise; also `recipe.roll`. */
  roll: number
}

const groundless = new Set([0, 1, 7, 9, 10])

/** How far from its centre a recipe draws, in planet radii. Mirrors `drawnExtent` in Swift. */
export function drawnExtent(recipe: PlanetRecipe): number {
  const rings = (recipe.ringOpacity ?? 0) > 0 ? Math.max(1, (recipe.ringOuterRadius ?? 2.27) * 1.04) : 1
  const life = recipe.life ?? 0
  const stations = life >= 3 && (recipe.stationCount ?? 1) > 0 ? (recipe.stationOrbitRadius ?? 1.085) + 0.1 : 1
  const traffic = life >= 4 && !groundless.has(recipe.archetype) ? 1.3 : 1
  const corona = recipe.archetype === 10 ? 1.6 : 1
  return Math.max(Math.max(rings, corona), Math.max(stations, traffic))
}

export function systemLightColor(system: PlanetSystem): PlanetColor {
  const h = system.star.palette.highlight, p = system.star.palette.primary
  const r = (h.red + p.red) / 2, g = (h.green + p.green) / 2, b = (h.blue + p.blue) / 2
  const peak = Math.max(r, g, b, 1e-6)
  const t = Math.min(Math.max(system.lightTint, 0), 1)
  return { red: 1 + (r / peak - 1) * t, green: 1 + (g / peak - 1) * t, blue: 1 + (b / peak - 1) * t, opacity: 1 }
}

type Vector = { x: number; y: number; z: number }

/** How far anything reaches before perspective magnifies the near side. */
function flatReach(system: PlanetSystem): number {
  let reach = system.starRadius * drawnExtent(system.star)
  for (const body of system.bodies) reach = Math.max(reach, body.distance + body.radius * drawnExtent(body.recipe))
  return reach
}

/** The camera's distance from the star, or null for a flat view. */
function cameraDistance(system: PlanetSystem): number | null {
  const p = system.perspective ?? 0
  return p > 0 ? flatReach(system) * 2.5 / Math.min(p, 1) : null
}

/** How much a point at `depth` is magnified: one at the star, more nearer the camera. */
function magnification(camera: number | null, depth: number): number {
  return camera === null ? 1 : camera / (camera - depth)
}

/** Where a planet is in the system at `angle` round its own orbit; an inclined orbit is turned about its nodes. */
export function orbitPosition(system: PlanetSystem, index: number, angle: number): Vector {
  const body = system.bodies[index]
  const flat = { x: body.distance * Math.cos(angle), y: 0, z: body.distance * Math.sin(angle) }
  const inclination = body.inclination ?? 0
  if (inclination === 0) return flat
  const node = body.node ?? 0
  const k = { x: Math.cos(node), y: 0, z: Math.sin(node) }
  const c = Math.cos(inclination), s = Math.sin(inclination)
  const dot = flat.x * k.x + flat.z * k.z
  const cross = { x: k.y * flat.z - k.z * flat.y, y: k.z * flat.x - k.x * flat.z, z: k.x * flat.y - k.y * flat.x }
  return {
    x: flat.x * c + cross.x * s + k.x * dot * (1 - c),
    y: flat.y * c + cross.y * s + k.y * dot * (1 - c),
    z: flat.z * c + cross.z * s + k.z * dot * (1 - c),
  }
}

const orbitAngle = (system: PlanetSystem, index: number, time: number) =>
  system.bodies[index].phase + time * system.bodies[index].speed * (system.orbitSpeed ?? 1)

function unzoomedExtent(system: PlanetSystem): number {
  const reach = flatReach(system)
  const camera = cameraDistance(system)
  if (camera === null) return reach
  let projected = system.starRadius * drawnExtent(system.star)
  system.bodies.forEach((body, index) => {
    const size = body.radius * drawnExtent(body.recipe)
    for (let k = 0; k < 128; k++) {
      const v = toView(system, orbitPosition(system, index, k / 128 * 2 * Math.PI))
      const m = magnification(camera, v.z)
      projected = Math.max(projected, Math.max(Math.abs(v.x), Math.abs(v.y)) * m + size * m)
    }
  })
  return projected * 1.01
}

/** How far from the star a view of the whole system reaches, after `zoom`. */
export function systemExtent(system: PlanetSystem): number {
  return unzoomedExtent(system) / Math.max(system.zoom ?? 1, 0.01)
}

/** A direction fixed in the system, as the camera sees it: x right, y up, z towards the camera. */
export function toView(system: PlanetSystem, v: Vector): Vector {
  const az = system.viewAzimuth ?? 0
  const ca = Math.cos(az), sa = Math.sin(az)
  const sinE = Math.sin(system.viewElevation), cosE = Math.cos(system.viewElevation)
  const X = v.x * ca + v.z * sa
  const Z = v.z * ca - v.x * sa
  return { x: X, y: Z * sinE + v.y * cosE, z: -Z * cosE + v.y * sinE }
}

/** The inverse of `toView`. */
export function fromView(system: PlanetSystem, v: Vector): Vector {
  const az = system.viewAzimuth ?? 0
  const ca = Math.cos(az), sa = Math.sin(az)
  const sinE = Math.sin(system.viewElevation), cosE = Math.cos(system.viewElevation)
  const Z = v.y * sinE - v.z * cosE
  const Y = v.y * cosE + v.z * sinE
  return { x: v.x * ca - Z * sa, y: Y, z: v.x * sa + Z * ca }
}

/** Into the shader's space, whose y runs down the screen — measured, not assumed. Its own inverse. */
export const toShader = (v: Vector): Vector => ({ x: v.x, y: -v.y, z: v.z })

/** A body's pole and prime meridian, fixed in the system. */
export function bodyFrame(recipe: PlanetRecipe): { pole: Vector; meridian: Vector } {
  const t = recipe.axialTilt ?? 0, phase = recipe.rotationPhase ?? 0
  const pole = { x: Math.sin(t), y: Math.cos(t), z: 0 }
  const a = { x: Math.cos(t), y: -Math.sin(t), z: 0 }
  const b = { x: pole.y * a.z - pole.z * a.y, y: pole.z * a.x - pole.x * a.z, z: pole.x * a.y - pole.y * a.x }
  const c = Math.cos(phase), s = Math.sin(phase)
  return { pole, meridian: { x: a.x * c + b.x * s, y: a.y * c + b.y * s, z: a.z * c + b.z * s } }
}

/** Sets a copy's tilt, phase, roll and light so the shader draws it as the camera sees it. */
function orient(system: PlanetSystem, recipe: PlanetRecipe, light: Vector | null): number {
  const { pole, meridian } = bodyFrame(recipe)
  const p = toShader(toView(system, pole)), m = toShader(toView(system, meridian))
  const roll = Math.atan2(-p.x, p.y)
  const cr = Math.cos(roll), sr = Math.sin(roll)
  const unroll = (v: Vector): Vector => ({ x: v.x * cr + v.y * sr, y: -v.x * sr + v.y * cr, z: v.z })
  const pu = unroll(p), mu = unroll(m)
  const tilt = Math.atan2(pu.z, pu.y)
  recipe.axialTilt = tilt
  const forward = { y: Math.sin(tilt), z: -Math.cos(tilt) }
  recipe.rotationPhase = Math.atan2(-(mu.y * forward.y + mu.z * forward.z), mu.x)
  if (light) {
    const l = unroll(toShader(light))
    recipe.lightAzimuth = Math.atan2(l.z, l.x)
    recipe.lightElevation = Math.asin(Math.min(Math.max(l.y, -1), 1))
  }
  recipe.roll = roll
  return roll
}

/** Where everything is at `time` seconds, back to front, each planet lit from the star. */
export function layoutSystem(system: PlanetSystem, time: number): Placement[] {
  const light = systemLightColor(system)
  const azimuth = system.viewAzimuth ?? 0
  const deep = (system.perspective ?? 0) > 0
  const camera = cameraDistance(system)
  const falloff = system.lightFalloff ?? 0
  const star: PlanetRecipe = { ...system.star }
  let starRoll = 0
  if (deep) starRoll = orient(system, star, null)
  else star.rotationPhase = (star.rotationPhase ?? 0) + azimuth
  const placements: Placement[] = [{ index: null, x: 0, y: 0, depth: 0, radius: system.starRadius, recipe: star, roll: starRoll }]
  system.bodies.forEach((body, index) => {
    const v = toView(system, orbitPosition(system, index, orbitAngle(system, index, time)))
    const x = v.x, y = v.y, depth = v.z
    const recipe: PlanetRecipe = { ...body.recipe, palette: { ...body.recipe.palette, light }, dayNightSpeed: 0 }
    const length = Math.sqrt(x * x + y * y + depth * depth)
    let roll = 0
    if (deep) {
      roll = orient(system, recipe, length > 1e-9 ? { x: -x / length, y: -y / length, z: -depth / length } : null)
    } else {
      if (length > 1e-9) {
        // The shader's y runs down the screen, so the screen-up y changes sign on the way in.
        const lx = -x / length, ly = y / length, lz = -depth / length
        recipe.lightAzimuth = Math.atan2(lz, lx)
        recipe.lightElevation = Math.asin(Math.min(Math.max(ly, -1), 1))
      }
      // The camera turning one way is the planet's face turning the other way.
      recipe.rotationPhase = (body.recipe.rotationPhase ?? 0) + azimuth
    }
    if (falloff > 0 && length > 1e-9) {
      const reference = system.starRadius * 3
      recipe.exposure *= Math.pow(Math.min(Math.max(reference / length, 0.05), 4), 2 * Math.min(falloff, 1))
    }
    // The light was worked out in the real positions; only the drawing is projected.
    const m = magnification(camera, depth)
    placements.push({ index, x: x * m, y: y * m, depth, radius: body.radius * m, recipe, roll })
  })
  return placements
    .map((placement, order) => ({ placement, order }))
    .sort((a, b) => a.placement.depth !== b.placement.depth ? a.placement.depth - b.placement.depth : a.order - b.order)
    .map(({ placement }) => placement)
}

/** Slides a planet round its orbit, distance kept, to the point on it nearest (x, y) on screen. */
function slide(system: PlanetSystem, index: number, x: number, y: number, time: number) {
  const camera = cameraDistance(system)
  const miss = (angle: number) => {
    const v = toView(system, orbitPosition(system, index, angle))
    const m = magnification(camera, v.z)
    return Math.hypot(v.x * m - x, v.y * m - y)
  }
  let best = 0, bestMiss = Infinity
  for (let k = 0; k < 180; k++) {
    const a = k / 180 * 2 * Math.PI
    const d = miss(a)
    if (d < bestMiss) { best = a; bestMiss = d }
  }
  let step = 2 * Math.PI / 180
  for (let round = 0; round < 24; round++) {
    for (const candidate of [best - step, best + step]) {
      const d = miss(candidate)
      if (d < bestMiss) { best = candidate; bestMiss = d }
    }
    step *= 0.5
  }
  const body = system.bodies[index]
  body.phase = best - time * body.speed * (system.orbitSpeed ?? 1)
}

function placeFlat(system: PlanetSystem, index: number, x: number, y: number, time: number) {
  const sinE = Math.sin(system.viewElevation)
  if (Math.abs(sinE) < 0.2) return slide(system, index, x, y, time)
  const body = system.bodies[index]
  const planeZ = y / sinE
  body.distance = Math.max(Math.sqrt(x * x + planeZ * planeZ), system.starRadius * 1.05)
  const angle = Math.atan2(planeZ, x) + (system.viewAzimuth ?? 0)
  body.phase = angle - time * body.speed * (system.orbitSpeed ?? 1)
}

/** Moves a planet to the screen point nearest (x, y), in system units, at `time`. Mutates. */
export function placeBody(system: PlanetSystem, index: number, x: number, y: number, time: number) {
  const body = system.bodies[index]
  if (!body) return
  if ((body.inclination ?? 0) !== 0) return slide(system, index, x, y, time)
  const camera = cameraDistance(system)
  let m = 1
  for (let round = 0; round < (camera === null ? 1 : 6); round++) {
    placeFlat(system, index, x / m, y / m, time)
    const at = layoutSystem(system, time).find(p => p.index === index)
    if (!at) return
    m = magnification(cameraDistance(system), at.depth)
  }
}

/** A planet's orbit as `count` points, with the same units and depth as `layoutSystem`. */
export function orbitPoints(system: PlanetSystem, index: number, count = 96): { x: number; y: number; depth: number }[] {
  if (!system.bodies[index] || count <= 2) return []
  const camera = cameraDistance(system)
  return Array.from({ length: count }, (_, k) => {
    const v = toView(system, orbitPosition(system, index, k / count * 2 * Math.PI))
    const m = magnification(camera, v.z)
    return { x: v.x * m, y: v.y * m, depth: v.z }
  })
}

// --- the sky ----------------------------------------------------------------------------

/** Every star of the sky, from the same 64-bit LCG as the Swift `MoonletSky`, six draws a star. */
export function skyDirections(sky: Sky) {
  const mask = (1n << 64n) - 1n
  let state = (0x9e3779b97f4a7c15n ^ ((BigInt(sky.seed >>> 0) * 0xd1b54a32d192ed03n) & mask)) & mask
  const next = () => {
    state = (state * 6364136223846793005n + 1442695040888963407n) & mask
    return Number(state >> 11n) / 9007199254740992
  }
  const tiltC = Math.cos(sky.bandTilt), tiltS = Math.sin(sky.bandTilt)
  const count = Math.max(0, Math.min(sky.starCount, 5000))
  return Array.from({ length: count }, () => {
    const z = next() * 2 - 1, a = next() * 2 * Math.PI
    const brightness = next() ** 3, warmth = next()
    const roll = next(), offset = next()
    if (roll < sky.bandStrength) {
      const y = (offset - 0.5) * 0.22, r = Math.sqrt(1 - y * y)
      const bx = r * Math.cos(a), bz = r * Math.sin(a)
      return { x: bx, y: y * tiltC - bz * tiltS, z: y * tiltS + bz * tiltC, brightness, warmth, flicker: offset }
    }
    const r = Math.sqrt(1 - z * z)
    return { x: r * Math.cos(a), y: z, z: r * Math.sin(a), brightness, warmth, flicker: offset }
  })
}

/** The sky's stars as they land in a w×h view at `time`, y down. */
export function skyStars(system: PlanetSystem, width: number, height: number, time = 0) {
  const sky = system.sky ?? defaultSky
  const focal = Math.max(width, height) * 0.9
  const warmth = Math.min(Math.max(sky.warmth, 0), 2)
  const out: { x: number; y: number; radius: number; red: number; green: number; blue: number; alpha: number }[] = []
  for (const star of skyDirections(sky)) {
    const v = toView(system, star)
    if (!(v.z < -0.05)) continue
    const sx = width / 2 + v.x / -v.z * focal
    const sy = height / 2 - v.y / -v.z * focal
    if (!(sx > -2 && sy > -2 && sx < width + 2 && sy < height + 2)) continue
    let alpha = (0.25 + 0.75 * star.brightness) * sky.brightness
    if (sky.twinkle > 0) {
      const rate = 1.5 + 4 * star.warmth
      alpha *= 1 - Math.min(sky.twinkle, 1) * (0.5 + 0.5 * Math.sin(time * rate + star.flicker * 2 * Math.PI))
    }
    out.push({
      x: sx, y: sy, radius: (0.45 + star.brightness * 1.1) * sky.starSize,
      red: sky.color.red * (1 - 0.2 * warmth * (1 - star.warmth)),
      green: sky.color.green * (1 - 0.15 * warmth),
      blue: sky.color.blue * (1 - 0.2 * warmth * star.warmth),
      alpha: Math.min(Math.max(alpha, 0), 1),
    })
  }
  return out
}

/** Kept for callers of the first starfield; the sky is `skyStars` now. */
export const starfieldPoints = (system: PlanetSystem, width: number, height: number) => skyStars(system, width, height)
