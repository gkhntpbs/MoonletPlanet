import { fragmentShader, vertexShader } from './shaders.ts'
import { layoutSystem, systemExtent, drawnExtent, orbitPoints, skyStars, defaultOrbitStyle, type PlanetSystem } from './system.ts'

export { archetypeRecipes, solarSystem, gasGiantRecipe, systemExample } from './presets.ts'
export { randomized, colorFromHSB } from './random.ts'
export { layoutSystem, systemExtent, systemLightColor, placeBody, orbitPoints, orbitPosition, starfieldPoints, skyStars, skyDirections, defaultSky, defaultOrbitStyle, toView, fromView, toShader, bodyFrame, drawnExtent, type Sky, type OrbitStyle, type PlanetSystem, type PlanetOrbit, type Placement } from './system.ts'

export type PlanetColor = { red: number; green: number; blue: number; opacity: number }
export type PlanetRecipe = {
  /** 10 is a star: it makes its own light, and the atmosphere settings shape its corona. */
  archetype: 0 | 1 | 2 | 3 | 4 | 5 | 6 | 7 | 8 | 9 | 10
  seed: number
  palette: Record<'highlight' | 'primary' | 'shadow' | 'storm' | 'atmosphere', PlanetColor>
    & { ring?: PlanetColor; ice?: PlanetColor; life?: PlanetColor; light?: PlanetColor }
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
   * lights on the night side, 3 one that has put something in orbit, 4 one with shuttles
   * now and then between the ground and orbit.
   */
  life?: 0 | 1 | 2 | 3 | 4
  /** How many are in orbit once `life` is 3. One by default; below that level nothing is drawn. */
  stationCount?: number
  /** The orbit in planet radii. 1.085 is low enough to cross the disc rather than skirt it. */
  stationOrbitRadius?: number
  /** Radians a second around the orbit; precession follows it. */
  stationSpeed?: number
  /** The orbit's angle to the equator in radians. 0.9 is roughly what the ISS flies. */
  stationInclination?: number
  /** A multiplier on the drawn size. It never shrinks below a pixel. */
  stationSize?: number
  /**
   * Stars only: 0 a ball of fire, 0.5 hot and bright with a bloom, 1 nothing but light.
   * Ignored by every other archetype.
   */
  luminosity?: number
  /** Turns the drawn body on screen, counter-clockwise radians. 0 is upright. */
  roll?: number
}

/** The ring fields postdate the first recipes, so a recipe without them is ringless. */
const optionalDefaults = {
  ringOpacity: 0, axialTilt: 0, ringInnerRadius: 1.235, ringOuterRadius: 2.27, ringDetail: 0.8,
  iceCoverage: 0, iceAltitude: 0.22, polarAsymmetry: 0, microDetail: 1, rotationPhase: 0,
  dayNightSpeed: 0,
  stationOrbitRadius: 1.085, stationSpeed: 0.55, stationInclination: 0.9, stationSize: 1,
  luminosity: 0.5, roll: 0,
} as const
const defaultRingColor: PlanetColor = { red: 0.94, green: 0.9, blue: 0.83, opacity: 1 }
const defaultIceColor: PlanetColor = { red: 0.93, green: 0.95, blue: 0.97, opacity: 1 }
const defaultLifeColor: PlanetColor = { red: 0.28, green: 0.46, blue: 0.2, opacity: 1 }
/** White light changes nothing; a system sets it from its star. */
const defaultLightColor: PlanetColor = { red: 1, green: 1, blue: 1, opacity: 1 }

const scalarKeys = ['rotationSpeed', 'turbulence', 'detail', 'warpStrength', 'bandCount', 'bandSharpness', 'stormCount', 'stormStrength', 'cloudCoverage', 'cloudSpeed', 'atmosphereDensity', 'atmosphereGlow', 'roughness', 'featureAmount', 'lightAzimuth', 'lightElevation', 'exposure'] as const
const optionalKeys = ['ringOpacity', 'axialTilt', 'ringInnerRadius', 'ringOuterRadius', 'ringDetail', 'iceCoverage', 'iceAltitude', 'polarAsymmetry', 'microDetail', 'rotationPhase', 'dayNightSpeed', 'stationOrbitRadius', 'stationSpeed', 'stationInclination', 'stationSize', 'luminosity', 'roll'] as const
const colors = { highlight: 'color0', primary: 'color1', shadow: 'color2', storm: 'color3', atmosphere: 'atmosphereColor' } as const

export function validateRecipe(recipe: PlanetRecipe) {
  if (!Number.isInteger(recipe.seed) || recipe.seed < 0 || recipe.seed > 0xffffffff) throw new RangeError('Invalid planet seed')
  if (!Number.isInteger(recipe.archetype) || recipe.archetype < 0 || recipe.archetype > 10) throw new RangeError('Invalid planet archetype')
  // The shader dispatches on this number, so an out-of-range one renders an unlit world
  // rather than failing — which is the kind of wrong that is hard to notice.
  const life = recipe.life ?? 0
  if (!Number.isInteger(life) || life < 0 || life > 4) throw new RangeError('Invalid planet life')
  const stations = recipe.stationCount ?? 1
  if (!Number.isInteger(stations) || stations < 0 || stations > 8) throw new RangeError('Invalid planet stationCount')
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
  const programs: WebGLProgram[] = []
  const program = gl.createProgram()
  if (!program) return null
  let disposed = false
  const dispose = () => {
    if (disposed) return
    disposed = true
    for (const shader of shaders) gl.deleteShader(shader)
    gl.deleteProgram(program)
    for (const extra of programs) gl.deleteProgram(extra)
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
  // A second, trivial program for orbit lines: positions in clip space and one colour.
  const lineProgram = gl.createProgram()!
  programs.push(lineProgram)
  for (const [type, source] of [
    [gl.VERTEX_SHADER, '#version 300 es\nin vec2 p;\nvoid main() { gl_Position = vec4(p, 0, 1); }'],
    [gl.FRAGMENT_SHADER, '#version 300 es\nprecision mediump float;\nuniform vec4 c;\nout vec4 o;\nvoid main() { o = c; }'],
  ] as const) {
    const shader = gl.createShader(type)!
    gl.shaderSource(shader, source)
    gl.compileShader(shader)
    gl.attachShader(lineProgram, shader)
    shaders.push(shader)
  }
  gl.linkProgram(lineProgram)
  const lineBuffer = gl.createBuffer()
  const lineVAO = gl.createVertexArray()
  gl.bindVertexArray(lineVAO)
  gl.bindBuffer(gl.ARRAY_BUFFER, lineBuffer)
  const lineAttribute = gl.getAttribLocation(lineProgram, 'p')
  gl.enableVertexAttribArray(lineAttribute)
  gl.vertexAttribPointer(lineAttribute, 2, gl.FLOAT, false, 0, 0)
  gl.bindVertexArray(null)
  /**
   * The near or far half of every orbit over the whole canvas. Each segment is a thin quad
   * rather than a GL line, because WebGL will not draw a line wider than one pixel.
   */
  const drawOrbits = (system: PlanetSystem, w: number, h: number, scale: number, near: boolean, pixelScale: number) => {
    const style = system.orbitStyle ?? defaultOrbitStyle
    const half = Math.max(0.5, style.width * pixelScale / 2)
    const vertices: number[] = []
    const clip = (px: number, py: number) => vertices.push(px / (w / 2), py / (h / 2))
    for (let i = 0; i < system.bodies.length; i++) {
      const points = orbitPoints(system, i)
      points.forEach((a, k) => {
        const b = points[(k + 1) % points.length]
        if ((a.depth + b.depth > 0) !== near) return
        // In device pixels from the centre, y up.
        const ax = a.x * scale, ay = a.y * scale, bx = b.x * scale, by = b.y * scale
        const len = Math.hypot(bx - ax, by - ay) || 1
        const nx = -(by - ay) / len * half, ny = (bx - ax) / len * half
        clip(ax + nx, ay + ny); clip(ax - nx, ay - ny); clip(bx + nx, by + ny)
        clip(bx + nx, by + ny); clip(ax - nx, ay - ny); clip(bx - nx, by - ny)
      })
    }
    if (!vertices.length) return
    gl.viewport(0, 0, w, h)
    gl.useProgram(lineProgram)
    gl.bindVertexArray(lineVAO)
    gl.bindBuffer(gl.ARRAY_BUFFER, lineBuffer)
    gl.bufferData(gl.ARRAY_BUFFER, new Float32Array(vertices), gl.STREAM_DRAW)
    const alpha = near ? style.opacity : style.opacity * 0.18 / 0.28
    // Premultiplied, like everything else on the canvas.
    gl.uniform4f(gl.getUniformLocation(lineProgram, 'c'), style.color.red * alpha, style.color.green * alpha, style.color.blue * alpha, alpha)
    gl.drawArrays(gl.TRIANGLES, 0, vertices.length / 2)
    gl.bindVertexArray(null)
    gl.useProgram(program)
  }
  // And one for the starfield: round points, each with its own size and colour.
  const starProgram = gl.createProgram()!
  programs.push(starProgram)
  for (const [type, source] of [
    [gl.VERTEX_SHADER, '#version 300 es\nin vec2 p;\nin float size;\nin vec4 color;\nout vec4 v;\nvoid main() { gl_Position = vec4(p, 0, 1); gl_PointSize = size; v = color; }'],
    [gl.FRAGMENT_SHADER, '#version 300 es\nprecision mediump float;\nin vec4 v;\nout vec4 o;\nvoid main() { float d = length(gl_PointCoord - 0.5) * 2.0; float a = v.a * (1.0 - smoothstep(0.6, 1.0, d)); o = vec4(v.rgb * a, a); }'],
  ] as const) {
    const shader = gl.createShader(type)!
    gl.shaderSource(shader, source)
    gl.compileShader(shader)
    gl.attachShader(starProgram, shader)
    shaders.push(shader)
  }
  gl.linkProgram(starProgram)
  const starBuffer = gl.createBuffer()
  const starVAO = gl.createVertexArray()
  gl.bindVertexArray(starVAO)
  gl.bindBuffer(gl.ARRAY_BUFFER, starBuffer)
  for (const [name, count, offset] of [['p', 2, 0], ['size', 1, 8], ['color', 4, 12]] as const) {
    const at = gl.getAttribLocation(starProgram, name)
    gl.enableVertexAttribArray(at)
    gl.vertexAttribPointer(at, count, gl.FLOAT, false, 28, offset)
  }
  gl.bindVertexArray(null)
  /** Distant stars over the whole canvas, `pixelScale` device pixels to a CSS pixel. */
  const drawStarfield = (system: PlanetSystem, w: number, h: number, pixelScale: number, time: number) => {
    const data: number[] = []
    // In CSS pixels so the field is the same at any pixel ratio, then into clip space.
    for (const s of skyStars(system, w / pixelScale, h / pixelScale, time)) {
      data.push(s.x / (w / pixelScale) * 2 - 1, 1 - s.y / (h / pixelScale) * 2,
        Math.max(1, s.radius * 2 * pixelScale + 1), s.red, s.green, s.blue, s.alpha)
    }
    if (!data.length) return
    gl.viewport(0, 0, w, h)
    gl.useProgram(starProgram)
    gl.bindVertexArray(starVAO)
    gl.bindBuffer(gl.ARRAY_BUFFER, starBuffer)
    gl.bufferData(gl.ARRAY_BUFFER, new Float32Array(data), gl.STREAM_DRAW)
    gl.drawArrays(gl.POINTS, 0, data.length / 7)
    gl.bindVertexArray(null)
    gl.useProgram(program)
  }
  const uniforms = new Map<string, WebGLUniformLocation | null>()
  const location = (name: string) => {
    if (!uniforms.has(name)) uniforms.set(name, gl.getUniformLocation(program, `u.${name}`))
    return uniforms.get(name) ?? null
  }
  /** One body into one rectangle of the canvas, in device pixels, y up from the bottom. */
  const draw = (recipe: PlanetRecipe, time: number, x: number, y: number, w: number, h: number) => {
    gl.viewport(x, y, w, h)
    gl.uniform2f(location('viewportSize'), w, h)
    gl.uniform1f(location('time'), time)
    gl.uniform1ui(location('seed'), recipe.seed)
    gl.uniform1ui(location('archetype'), recipe.archetype)
    gl.uniform1ui(location('life'), recipe.life ?? 0)
    gl.uniform1ui(location('stationCount'), recipe.stationCount ?? 1)
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
    const light = recipe.palette.light ?? defaultLightColor
    gl.uniform4f(location('lightColor'), light.red, light.green, light.blue, light.opacity)
    gl.drawArrays(gl.TRIANGLE_STRIP, 0, 4)
  }
  /** Sizes the canvas for a CSS size and pixel ratio, and returns it in device pixels. */
  const size = (width: number, height: number, pixelRatio: number) => {
    const scale = Math.min(2, pixelRatio)
    const max = gl.getParameter(gl.MAX_VIEWPORT_DIMS) as Int32Array
    const w = Math.max(1, Math.min(max[0], Math.round(width * scale)))
    const h = Math.max(1, Math.min(max[1], Math.round(height * scale)))
    if (canvas.width !== w) canvas.width = w
    if (canvas.height !== h) canvas.height = h
    return { w, h }
  }
  return {
    render(recipe: PlanetRecipe, time: number, width: number, height: number, pixelRatio = 1) {
      if (disposed || gl.isContextLost()) return false
      validateRecipe(recipe)
      if (![time, width, height, pixelRatio].every(Number.isFinite) || width <= 0 || height <= 0 || pixelRatio <= 0) throw new RangeError('Invalid planet viewport or time')
      const { w, h } = size(width, height, pixelRatio)
      gl.disable(gl.BLEND)
      gl.useProgram(program)
      draw(recipe, time, 0, 0, w, h)
      return true
    },
    /**
     * A star and its planets, each lit from the star, fitted to the canvas. Bodies are drawn
     * back to front over each other, so the canvas is cleared first and blended after.
     */
    renderSystem(system: PlanetSystem, time: number, width: number, height: number, pixelRatio = 1, options: { showsStarfield?: boolean } = {}) {
      if (disposed || gl.isContextLost()) return false
      if (![time, width, height, pixelRatio].every(Number.isFinite) || width <= 0 || height <= 0 || pixelRatio <= 0) throw new RangeError('Invalid planet viewport or time')
      const placements = layoutSystem(system, time)
      for (const placement of placements) validateRecipe(placement.recipe)
      const { w, h } = size(width, height, pixelRatio)
      const side = Math.min(w, h)
      const scale = side / 2 / Math.max(systemExtent(system), 1e-6)
      gl.clearColor(0, 0, 0, 0)
      gl.clear(gl.COLOR_BUFFER_BIT)
      gl.enable(gl.BLEND)
      // The shader's output is premultiplied.
      gl.blendFunc(gl.ONE, gl.ONE_MINUS_SRC_ALPHA)
      // Distant stars first, turning with the camera: they are what tells the eye the
      // camera is moving rather than the planets.
      if (options.showsStarfield || system.sky?.isVisible) drawStarfield(system, w, h, Math.min(2, pixelRatio), time)
      // The far half of the orbits under everything and the near half just over the star,
      // the same layering as the Swift view.
      if (system.showsOrbits) drawOrbits(system, w, h, scale, false, Math.min(2, pixelRatio))
      gl.useProgram(program)
      for (const p of placements) {
        const drawn = Math.max(1, Math.round(2 * p.radius * drawnExtent(p.recipe) * scale))
        const cx = w / 2 + p.x * scale, cy = h / 2 + p.y * scale
        draw(p.recipe, time, Math.round(cx - drawn / 2), Math.round(cy - drawn / 2), drawn, drawn)
        if (p.index === null && system.showsOrbits) drawOrbits(system, w, h, scale, true, Math.min(2, pixelRatio))
      }
      gl.disable(gl.BLEND)
      return true
    },
    dispose,
  }
}
