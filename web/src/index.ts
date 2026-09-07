import { fragmentShader, vertexShader } from './shaders.ts'

export { archetypeRecipes, solarSystem, gasGiantRecipe } from './presets.ts'
export { randomized, colorFromHSB } from './random.ts'

export type PlanetColor = { red: number; green: number; blue: number; opacity: number }
export type PlanetRecipe = {
  archetype: 0 | 1 | 2 | 3 | 4 | 5 | 6 | 7 | 8 | 9
  seed: number
  palette: Record<'highlight' | 'primary' | 'shadow' | 'storm' | 'atmosphere', PlanetColor>
    & { ring?: PlanetColor; ice?: PlanetColor; life?: PlanetColor }
  rotationSpeed: number
  turbulence: number
  detail: number
  warpStrength: number
  bandCount: number
  bandSharpness: number
  stormCount: number
  stormStrength: number
  cloudCoverage: number
  cloudSpeed: number
  atmosphereDensity: number
  atmosphereGlow: number
  roughness: number
  featureAmount: number
  lightAzimuth: number
  lightElevation: number
  exposure: number
  /** 0 is no rings and skips the ring path entirely; 1 is Saturn's own optical depths. */
  ringOpacity?: number
  /**
   * The planet's pole, in radians, and therefore the angle its rings are seen at — rings lie
   * in the equator. 0 points the pole up the screen and shows rings edge-on; `Math.PI / 2`
   * points it at the camera. Bands and ice caps follow it too.
   */
  axialTilt?: number
  /** In planet radii. Saturn's are 1.235 and 2.27. */
  ringInnerRadius?: number
  ringOuterRadius?: number
  /** How strongly ringlets band the system. 0 is four smooth annuli. */
  ringDetail?: number
  /** Position of the freezing isotherm: 0 is a world with no ice, 1 glaciates it. */
  iceCoverage?: number
  /** Lapse rate — how much colder altitude makes a place, so highlands hold snow. */
  iceAltitude?: number
  /** How differently the two hemispheres freeze. No real world has matching caps. */
  polarAsymmetry?: number
  /** How much fine, high-frequency structure sits on top of everything. */
  microDetail?: number
  /** Where the planet is in its own day, in radians, added to whatever the clock turned. */
  rotationPhase?: number
  /**
   * How fast the star sweeps around, in radians a second. Zero holds the light still.
   * This moves the *terminator* — the planet running through its phases — which is a
   * different thing from `rotationSpeed` turning the ground under a light that stays put.
   */
  dayNightSpeed?: number
  /**
   * Whether anything lives here. 0 sterile, 1 simple life, 2 a civilisation with city
   * lights on the night side, 3 one that has put something in orbit.
   */
  life?: 0 | 1 | 2 | 3
}

/** The ring fields postdate the first recipes, so a recipe without them is ringless. */
const optionalDefaults = {
  ringOpacity: 0, axialTilt: 0, ringInnerRadius: 1.235, ringOuterRadius: 2.27, ringDetail: 0.8,
  iceCoverage: 0, iceAltitude: 0.22, polarAsymmetry: 0, microDetail: 1, rotationPhase: 0,
  dayNightSpeed: 0,
} as const
const defaultRingColor: PlanetColor = { red: 0.94, green: 0.9, blue: 0.83, opacity: 1 }
const defaultIceColor: PlanetColor = { red: 0.93, green: 0.95, blue: 0.97, opacity: 1 }
const defaultLifeColor: PlanetColor = { red: 0.28, green: 0.46, blue: 0.2, opacity: 1 }

const scalarKeys = ['rotationSpeed', 'turbulence', 'detail', 'warpStrength', 'bandCount', 'bandSharpness', 'stormCount', 'stormStrength', 'cloudCoverage', 'cloudSpeed', 'atmosphereDensity', 'atmosphereGlow', 'roughness', 'featureAmount', 'lightAzimuth', 'lightElevation', 'exposure'] as const
const optionalKeys = ['ringOpacity', 'axialTilt', 'ringInnerRadius', 'ringOuterRadius', 'ringDetail', 'iceCoverage', 'iceAltitude', 'polarAsymmetry', 'microDetail', 'rotationPhase', 'dayNightSpeed'] as const
const colors = { highlight: 'color0', primary: 'color1', shadow: 'color2', storm: 'color3', atmosphere: 'atmosphereColor' } as const

export function validateRecipe(recipe: PlanetRecipe) {
  if (!Number.isInteger(recipe.seed) || recipe.seed < 0 || recipe.seed > 0xffffffff) throw new RangeError('Invalid planet seed')
  if (!Number.isInteger(recipe.archetype) || recipe.archetype < 0 || recipe.archetype > 9) throw new RangeError('Invalid planet archetype')
  // The shader dispatches on this number, so an out-of-range one renders an unlit world
  // rather than failing — which is the kind of wrong that is hard to notice.
  const life = recipe.life ?? 0
  if (!Number.isInteger(life) || life < 0 || life > 3) throw new RangeError('Invalid planet life')
  for (const key of scalarKeys) if (!Number.isFinite(recipe[key])) throw new RangeError(`Invalid planet ${key}`)
  for (const key of optionalKeys) {
    const value = recipe[key]
    if (value !== undefined && !Number.isFinite(value)) throw new RangeError(`Invalid planet ${key}`)
  }
  if ((recipe.ringOpacity ?? 0) > 0) {
    const inner = recipe.ringInnerRadius ?? optionalDefaults.ringInnerRadius
    const outer = recipe.ringOuterRadius ?? optionalDefaults.ringOuterRadius
    // Rings inside the planet, or inside out, are not a look — they are a division by a
    // negative span in the profile.
    if (!(inner > 1)) throw new RangeError('Rings cannot start inside the planet')
    if (!(outer > inner)) throw new RangeError('Ring outer radius must exceed the inner')
  }
  for (const key of Object.keys(colors) as (keyof typeof colors)[]) {
    const color = recipe.palette[key]
    if (![color.red, color.green, color.blue, color.opacity].every(value => Number.isFinite(value) && value >= 0 && value <= 1)) throw new RangeError(`Invalid planet ${key} color`)
  }
}

export function createPlanetRenderer(canvas: HTMLCanvasElement) {
  const gl = canvas.getContext('webgl2', { alpha: true, premultipliedAlpha: true, antialias: false, depth: false, stencil: false })
  if (!gl) return null
  const shaders: WebGLShader[] = []
  const program = gl.createProgram()
  if (!program) return null
  let disposed = false
  const dispose = () => {
    if (disposed) return
    disposed = true
    for (const shader of shaders) gl.deleteShader(shader)
    gl.deleteProgram(program)
  }
  try {
    for (const [type, source] of [[gl.VERTEX_SHADER, vertexShader], [gl.FRAGMENT_SHADER, fragmentShader]] as const) {
      const shader = gl.createShader(type)
      if (!shader) throw new Error('Cannot allocate planet shader')
      shaders.push(shader)
      gl.shaderSource(shader, source)
      gl.compileShader(shader)
      if (!gl.getShaderParameter(shader, gl.COMPILE_STATUS)) throw new Error(gl.getShaderInfoLog(shader) ?? 'Planet shader compilation failed')
      gl.attachShader(program, shader)
    }
    gl.linkProgram(program)
    if (!gl.getProgramParameter(program, gl.LINK_STATUS)) throw new Error(gl.getProgramInfoLog(program) ?? 'Planet shader link failed')
  } catch (error) { dispose(); throw error }
  const uniforms = new Map<string, WebGLUniformLocation | null>()
  const location = (name: string) => {
    if (!uniforms.has(name)) uniforms.set(name, gl.getUniformLocation(program, `u.${name}`))
    return uniforms.get(name) ?? null
  }
  return {
    render(recipe: PlanetRecipe, time: number, width: number, height: number, pixelRatio = 1) {
      if (disposed || gl.isContextLost()) return false
      validateRecipe(recipe)
      if (![time, width, height, pixelRatio].every(Number.isFinite) || width <= 0 || height <= 0 || pixelRatio <= 0) throw new RangeError('Invalid planet viewport or time')
      const scale = Math.min(2, pixelRatio)
      const max = gl.getParameter(gl.MAX_VIEWPORT_DIMS) as Int32Array
      const w = Math.max(1, Math.min(max[0], Math.round(width * scale)))
      const h = Math.max(1, Math.min(max[1], Math.round(height * scale)))
      if (canvas.width !== w) canvas.width = w
      if (canvas.height !== h) canvas.height = h
      gl.viewport(0, 0, w, h)
      gl.useProgram(program)
      gl.uniform2f(location('viewportSize'), w, h)
      gl.uniform1f(location('time'), time)
      gl.uniform1ui(location('seed'), recipe.seed)
      gl.uniform1ui(location('archetype'), recipe.archetype)
      gl.uniform1ui(location('life'), recipe.life ?? 0)
      for (const key of scalarKeys) gl.uniform1f(location(key), recipe[key])
      for (const key of optionalKeys) gl.uniform1f(location(key), recipe[key] ?? optionalDefaults[key])
      for (const key of Object.keys(colors) as (keyof typeof colors)[]) {
        const color = recipe.palette[key]
        gl.uniform4f(location(colors[key]), color.red, color.green, color.blue, color.opacity)
      }
      const ring = recipe.palette.ring ?? defaultRingColor
      gl.uniform4f(location('ringColor'), ring.red, ring.green, ring.blue, ring.opacity)
      const ice = recipe.palette.ice ?? defaultIceColor
      gl.uniform4f(location('iceColor'), ice.red, ice.green, ice.blue, ice.opacity)
      const life = recipe.palette.life ?? defaultLifeColor
      gl.uniform4f(location('lifeColor'), life.red, life.green, life.blue, life.opacity)
      gl.drawArrays(gl.TRIANGLE_STRIP, 0, 4)
      return true
    },
    dispose,
  }
}
