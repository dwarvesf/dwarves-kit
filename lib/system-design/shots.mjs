// Per-sheet PNGs: node shots.mjs <built.html> <outdir> [id,id]. Needs node 22+ and Chrome (CHROME env or macOS path).
// ponytail: no retry on a missing Chrome port; add if Chrome startup flakes.
import { spawn } from 'node:child_process';
import { createHash } from 'node:crypto';
import { mkdtempSync, mkdirSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { resolve, join } from 'node:path';

const [file, outdir, only] = process.argv.slice(2);
if (!file || !outdir) { console.error('usage: shots.mjs <built.html> <outdir> [id,id]'); process.exit(2); }
const chrome = process.env.CHROME || '/Applications/Google Chrome.app/Contents/MacOS/Google Chrome';
mkdirSync(outdir, { recursive: true });

const proc = spawn(chrome, ['--headless=new', '--remote-debugging-port=0', '--no-first-run', '--disable-gpu',
  '--hide-scrollbars', `--user-data-dir=${mkdtempSync(join(tmpdir(), 'shots-'))}`, 'about:blank'], { stdio: ['ignore', 'ignore', 'pipe'] });
const wsUrl = await new Promise((ok, no) => {
  let buf = '';
  proc.on('error', no);
  proc.stderr.on('data', d => { buf += d; const m = buf.match(/ws:\/\/\S+/); if (m) ok(m[0]); });
  setTimeout(() => no(new Error('chrome did not start')), 15000);
});
const ws = new WebSocket(wsUrl);
await new Promise((ok, no) => { ws.onopen = ok; ws.onerror = no; });
let n = 0; const pending = new Map();
ws.onmessage = e => { const m = JSON.parse(e.data); const p = pending.get(m.id); if (p) { pending.delete(m.id); m.error ? p[1](new Error(m.error.message)) : p[0](m.result); } };
const send = (method, params = {}, sessionId) => new Promise((ok, no) => { const id = ++n; pending.set(id, [ok, no]); ws.send(JSON.stringify({ id, method, params, sessionId })); });

let failed = [];
try {
  const { targetId } = await send('Target.createTarget', { url: 'about:blank' });
  const { sessionId: s } = await send('Target.attachToTarget', { targetId, flatten: true });
  await send('Emulation.setDeviceMetricsOverride', { width: 1400, height: 1000, deviceScaleFactor: Number(process.env.SHOT_SCALE) || 1, mobile: false }, s);
  await send('Page.navigate', { url: 'file://' + resolve(file) }, s);
  const ev = async expr => (await send('Runtime.evaluate', { expression: expr, returnByValue: true }, s)).result.value;
  // Rendered when sheets exist and none still holds a pending placeholder; two equal counts in a row settle it.
  let last = -1, ready = false;
  for (let i = 0; i < 100 && !ready; i++) {
    await new Promise(r => setTimeout(r, 300));
    const c = await ev('document.querySelectorAll("section.sheet").length');
    ready = c > 0 && c === last; last = c;
  }
  if (!ready) throw new Error('no section.sheet rendered (are cdnjs scripts reachable?)');
  const want = only ? new Set(only.split(',')) : null;
  const SEL = process.env.SHOT_CLIP === 'figure' ? 'section.sheet figure .canvas' : 'section.cover,section.sheet';
  const rects = (await ev(`[...document.querySelectorAll("${SEL}")].map(e=>{const r=e.getBoundingClientRect();return{id:(e.closest("section")||e).id,x:r.left+scrollX,y:r.top+scrollY,width:r.width,height:r.height}})`))
    .filter(r => !want || want.has(r.id));
  if (want) for (const w of want) if (!rects.some(r => r.id === w)) failed.push(`${w}: no such sheet`);
  const seen = new Map();
  for (const { id, ...clip } of rects) {
    const { data } = await send('Page.captureScreenshot', { format: 'png', captureBeyondViewport: true, clip: { ...clip, scale: 1 } }, s);
    const buf = Buffer.from(data, 'base64');
    writeFileSync(join(outdir, id + '.png'), buf);
    const md5 = createHash('md5').update(buf).digest('hex');
    console.log(`${id}.png ${buf.length} bytes md5 ${md5.slice(0, 8)}`);
    if (buf.length <= 10240) failed.push(`${id}.png: ${buf.length} bytes (<=10 KB)`);
    if (seen.has(md5)) failed.push(`${id}.png: same md5 as ${seen.get(md5)}.png`); else seen.set(md5, id);
  }
} finally { ws.close(); proc.kill(); }
if (failed.length) { console.error('shots: FAILED\n' + failed.join('\n')); process.exit(1); }
