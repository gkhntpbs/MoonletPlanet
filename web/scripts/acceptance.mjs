// Browser acceptance: compile the generated GLSL in a real WebGL2 context and check that
// every planet actually paints.
//
// A shader that compiles is not a shader that draws. This bundles the module, serves it,
// runs headless Chrome against it and asserts on the coverage each canvas reports — a
// ringless planet is a circle inscribed in a square, so it has to come back at π/4.
//
//   node scripts/acceptance.mjs            assert
//   node scripts/acceptance.mjs --shot out.png   …and keep the screenshot
import { spawn, spawnSync } from 'node:child_process'
import { createServer } from 'node:http'
import { readFile, mkdtemp, rm } from 'node:fs/promises'
import { openSync, closeSync } from 'node:fs'
import { tmpdir } from 'node:os'
import { join, extname } from 'node:path'
import { fileURLToPath } from 'node:url'

const root = fileURLToPath(new URL('..', import.meta.url))
const shotIndex = process.argv.indexOf('--shot')
const shotPath = shotIndex > 0 ? process.argv[shotIndex + 1] : join(await mkdtemp(join(tmpdir(), 'planet-')), 'acceptance.png')

const CHROME = process.env.CHROME ?? '/Applications/Google Chrome.app/Contents/MacOS/Google Chrome'

// 1. Bundle, because a browser cannot import TypeScript.
const build = spawnSync('node_modules/.bin/esbuild',
  ['src/index.ts', '--bundle', '--format=esm', '--outfile=dev/bundle.js', '--log-level=warning'],
  { cwd: root, stdio: 'inherit' })
if (build.status !== 0) { console.error('bundle failed'); process.exit(1) }

// 2. Serve `dev/` on a port nobody else is on.
const types = { '.html': 'text/html', '.js': 'text/javascript', '.json': 'application/json' }
const server = createServer(async (request, response) => {
  const name = request.url === '/' ? '/acceptance.html' : request.url.split('?')[0]
  try {
    const body = await readFile(join(root, 'dev', name))
    response.writeHead(200, { 'content-type': types[extname(name)] ?? 'application/octet-stream' })
    response.end(body)
  } catch { response.writeHead(404); response.end() }
})
await new Promise(resolve => server.listen(0, '127.0.0.1', resolve))
const port = server.address().port

// 3. One headless frame. The page animates only with `?animate`, because an open
//    requestAnimationFrame loop means virtual time never runs out and Chrome never exits.
const profile = await mkdtemp(join(tmpdir(), 'planet-chrome-'))
// The DOM goes to a file rather than a pipe. Chrome's crashpad helper inherits stdout and
// outlives the browser, so a pipe never reaches `close` and the run hangs until the timeout
// no matter how quickly the page finished.
const domPath = join(profile, 'dom.html')
const domFd = openSync(domPath, 'w')
const chrome = spawn(CHROME, [
  '--headless=new', '--disable-gpu', '--enable-unsafe-swiftshader',
  // A fresh profile otherwise spends most of the run on first-run setup and update checks.
  '--no-first-run', '--no-default-browser-check', '--disable-extensions',
  '--disable-background-networking', '--disable-component-update', '--disable-sync',
  `--user-data-dir=${profile}`, '--virtual-time-budget=6000',
  '--window-size=1200,1100', `--screenshot=${shotPath}`, '--dump-dom',
  `http://127.0.0.1:${port}/acceptance.html`,
], { stdio: ['ignore', domFd, 'ignore'] })

// Headless Chrome does not exit here once it has written its artefacts — `--dump-dom` and
// `--screenshot` both land on disk and the process stays up. So this waits for the *output*
// rather than for the process, and then ends it. Waiting on exit is what made two earlier
// versions of this script hang until their timeout with a perfectly good render sitting in
// a file beside them.
const deadline = Date.now() + 120_000
let dom = ''
while (Date.now() < deadline) {
  await new Promise(resolve => setTimeout(resolve, 500))
  dom = await readFile(domPath, 'utf8').catch(() => '')
  if (dom.includes('id="report"')) break
  if (chrome.exitCode !== null) break
}
chrome.kill()
closeSync(domFd)
server.close()

// Chrome's helpers outlive it and keep writing into the profile, so the first rmdir races
// them. Cleaning up a temp directory is not worth failing the run over either way.
for (let attempt = 0; attempt < 5; attempt++) {
  try { await rm(profile, { recursive: true, force: true }); break }
  catch { await new Promise(resolve => setTimeout(resolve, 400)) }
}

if (!dom) { console.error('Chrome produced no DOM — is it installed? Set CHROME=<path>'); process.exit(1) }
if (!dom.includes('id="report"')) { console.error('The page never finished rendering'); process.exit(1) }

// 4. Assert on what the page measured.
const report = JSON.parse(dom.match(/<script id="report" type="application\/json">([\s\S]*?)<\/script>/)?.[1] ?? 'null')
if (!report) { console.error('The page did not publish a report'); process.exit(1) }
if (!report.compiled) {
  console.error('WebGL acceptance FAILED')
  for (const error of report.errors) console.error(`  ${error.label}: ${error.message}`)
  process.exit(1)
}

let failed = false
for (const { label, coverage } of report.drawn) {
  // A planet with no rings fills a circle inscribed in its square: π/4 ≈ 0.785. A ringed
  // one zooms out to hold the rings, so it covers less — but never nothing. A spacefaring
  // one zooms out to hold its station's orbit, 1.185 radii by default: π/4 / 1.185² ≈ 0.56.
  const floor = label.includes('rings') || label.includes('saturn') || label.includes('uranus') ? 0.15
    : label.includes('spacefaring') ? 0.5 : 0.7
  const ok = coverage >= floor
  if (!ok) failed = true
  console.log(`${ok ? '  ok  ' : ' FAIL '} ${label.padEnd(34)} coverage ${coverage}`)
}
console.log(failed ? 'acceptance FAILED' : `acceptance passed — ${report.drawn.length} planets, screenshot at ${shotPath}`)
process.exit(failed ? 1 : 0)
