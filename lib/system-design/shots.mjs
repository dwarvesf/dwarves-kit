// Per-sheet PNGs: node shots.mjs <built.html> <outdir> [id,id]. Needs node 22+ and Chrome (CHROME env or macOS path).
// SHOT_CLIP=figure crops to each sheet's drawing; with it, SHOT_FORMAT=svg writes a standalone <id>.svg instead:
// the drawing, the CSS rules it uses with the light and the prefers-color-scheme dark tokens, and the web fonts it
// was measured with, subset to its own characters and embedded as data URIs (an SVG shown in <img> fetches nothing).
// ponytail: no retry on a missing Chrome port; add if Chrome startup flakes.
import { spawn } from 'node:child_process';
import { createHash } from 'node:crypto';
import { mkdtempSync, mkdirSync, writeFileSync, existsSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { resolve, join } from 'node:path';

const [file, outdir, only] = process.argv.slice(2);
if (!file || !outdir) { console.error('usage: shots.mjs <built.html> <outdir> [id,id]'); process.exit(2); }
const FORMAT = process.env.SHOT_FORMAT || 'png';
if (FORMAT !== 'png' && FORMAT !== 'svg') { console.error('shots: SHOT_FORMAT must be png or svg'); process.exit(2); }
if (FORMAT === 'svg' && process.env.SHOT_CLIP !== 'figure') { console.error('shots: SHOT_FORMAT=svg needs SHOT_CLIP=figure'); process.exit(2); }
const ZOOM = Number(process.env.SHOT_ZOOM || 1);
if (!(ZOOM >= 0.5 && ZOOM <= 3)) { console.error('shots: SHOT_ZOOM must be a number from 0.5 to 3'); process.exit(2); }
// CHROME wins; otherwise the first Chromium-family browser installed on this Mac.
const chrome = process.env.CHROME || [
  '/Applications/Google Chrome.app/Contents/MacOS/Google Chrome',
  '/Applications/Microsoft Edge.app/Contents/MacOS/Microsoft Edge',
  '/Applications/Brave Browser.app/Contents/MacOS/Brave Browser',
  '/Applications/Chromium.app/Contents/MacOS/Chromium',
  '/Applications/Helium.app/Contents/MacOS/Helium',
].find((path) => existsSync(path)) || '/Applications/Google Chrome.app/Contents/MacOS/Google Chrome';
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

// In-page: each sheet's figure as standalone SVG markup, plus the web-font faces its text uses and its characters.
function extractSvgs(zoom) {
  const sheets = [...document.styleSheets].filter(sh => sh.ownerNode && sh.ownerNode.tagName === 'STYLE');
  const keep = (rule, svg) => {
    if (rule instanceof CSSStyleRule) {
      const sel = rule.selectorText;
      if (sel.includes(':root')) return rule.cssText;
      if (sel === '*') return '';
      try { return svg.querySelector(sel) ? rule.cssText : ''; } catch { return ''; }
    }
    if (rule instanceof CSSMediaRule && /prefers-color-scheme/.test(rule.conditionText)) {
      const inner = [...rule.cssRules].map(r => keep(r, svg)).filter(Boolean).join('\n');
      return inner ? `@media ${rule.conditionText}{\n${inner}\n}` : '';
    }
    return '';
  };
  const NS = 'http://www.w3.org/2000/svg';
  const el = (name, attrs) => { const e = document.createElementNS(NS, name); for (const k in attrs) e.setAttribute(k, attrs[k]); return e; };
  const webFaces = [...document.fonts].filter(f => f.status === 'loaded').map(f => f.family.replace(/^["']|["']$/g, ''));
  return [...document.querySelectorAll('section.sheet figure .canvas svg')].map(svg => {
    const id = svg.closest('section').id, vb = svg.viewBox.baseVal, w = Math.ceil(vb.width), h = Math.ceil(vb.height);
    const used = new Map(); let chars = '';
    for (const t of svg.querySelectorAll('text')) {
      const cs = getComputedStyle(t), family = cs.fontFamily.split(',')[0].trim().replace(/^["']|["']$/g, '');
      used.set(family + '|' + cs.fontWeight, { family, weight: Number(cs.fontWeight), web: webFaces.includes(family) });
      chars += t.textContent;
    }
    const css = ['/*@fonts*/', ...sheets.flatMap(sh => [...sh.cssRules].map(r => keep(r, svg))).filter(Boolean),
      '.dk-sheet{fill:var(--sheet)} .dk-grid{fill:none;stroke:var(--grid);stroke-width:1} .dk-rule{fill:none;stroke:var(--rule);stroke-width:1}'].join('\n');
    const out = svg.cloneNode(true);
    out.removeAttribute('style');
    out.setAttribute('width', Math.ceil(w * zoom)); out.setAttribute('height', Math.ceil(h * zoom));
    out.setAttribute('data-doc-figures', id.replace(/^d-/, ''));
    const style = el('style', {}); style.textContent = css;
    const pattern = el('pattern', { id: 'dk-grid', width: 20, height: 20, patternUnits: 'userSpaceOnUse' });
    pattern.append(el('path', { class: 'dk-grid', d: 'M0 .5H20M.5 0V20' }));
    const defs = el('defs', {}); defs.append(pattern);
    out.prepend(style, defs, el('rect', { class: 'dk-sheet', width: w, height: h }), el('rect', { fill: 'url(#dk-grid)', width: w, height: h }));
    out.append(el('rect', { class: 'dk-rule', x: .5, y: .5, width: w - 1, height: h - 1 }));
    return { id, svg: new XMLSerializer().serializeToString(out), used: [...used.values()], chars: [...new Set(chars)].sort().join('') };
  });
}

// Node side: the @font-face rules the figure's text uses, from the page's Google Fonts links, subset to its
// characters with the css2 `text` parameter and inlined. A web font with no face to embed fails the figure.
const BROWSER_AGENT = 'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/126.0.0.0 Safari/537.36';
async function embedFonts(links, used, chars) {
  let css = ''; const got = new Set();
  for (const href of links) {
    const res = await fetch(href + '&text=' + encodeURIComponent(chars), { headers: { 'User-Agent': BROWSER_AGENT } });
    if (!res.ok) throw new Error(`font css ${res.status}: ${href}`);
    for (const face of (await res.text()).match(/@font-face\s*{[^}]*}/g) || []) {
      const family = (/font-family:\s*['"]?([^;'"]+)/.exec(face) || [])[1];
      const [lo, hi = lo] = ((/font-weight:\s*([^;]+);/.exec(face) || [])[1] || '400').trim().split(/\s+/).map(Number);
      const hits = used.filter(u => u.family === family && u.weight >= lo && u.weight <= hi);
      if (!hits.length) continue;
      const url = /url\(([^)]+)\)/.exec(face)[1].replace(/^['"]|['"]$/g, '');
      const font = await fetch(url, { headers: { 'User-Agent': BROWSER_AGENT } });
      if (!font.ok) throw new Error(`font ${font.status}: ${url}`);
      const b64 = Buffer.from(await font.arrayBuffer()).toString('base64');
      const mime = /format\(['"]?woff2/.test(face) ? 'font/woff2' : /format\(['"]?woff['"]?\)/.test(face) ? 'font/woff' : 'font/ttf';
      css += face.replace(/url\([^)]+\)/, `url(data:${mime};base64,${b64})`).replace(/\s*font-display:[^;]+;/, '') + '\n';
      hits.forEach(u => got.add(u.family + '|' + u.weight));
    }
  }
  const missing = used.filter(u => u.web && !got.has(u.family + '|' + u.weight));
  if (missing.length) throw new Error('no face to embed for ' + missing.map(u => `${u.family} ${u.weight}`).join(', '));
  return css;
}

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
  if (FORMAT === 'svg') {
    const links = await ev('[...document.querySelectorAll("link[rel=stylesheet]")].map(l=>l.href).filter(h=>h.includes("fonts.googleapis.com/css"))');
    const figs = (await ev(`(${extractSvgs})(${ZOOM})`)).filter(f => !want || want.has(f.id));
    if (want) for (const w of want) if (!figs.some(f => f.id === w)) failed.push(`${w}: no such sheet`);
    const seen = new Map();
    for (const f of figs) {
      let fonts;
      try { fonts = await embedFonts(links, f.used, f.chars); } catch (e) { failed.push(`${f.id}.svg: ${e.message}`); continue; }
      const text = '<?xml version="1.0" encoding="UTF-8"?>\n' + f.svg.replace('/*@fonts*/', () => fonts) + '\n';
      writeFileSync(join(outdir, f.id + '.svg'), text);
      const bytes = Buffer.byteLength(text), md5 = createHash('md5').update(text).digest('hex');
      console.log(`svg ${f.id}.svg ${bytes} bytes md5 ${md5.slice(0, 8)}`);
      if (bytes > 150 * 1024) console.error(`shots: ${f.id}.svg is ${Math.round(bytes / 1024)} KB, over the 150 KB budget`);
      if (seen.has(md5)) failed.push(`${f.id}.svg: same md5 as ${seen.get(md5)}.svg`); else seen.set(md5, f.id);
    }
    if (!figs.length) failed.push('no figure to export');
  } else {
    const SEL = process.env.SHOT_CLIP === 'figure' ? 'section.sheet figure .canvas' : 'section.cover,section.sheet';
    // A figure PNG draws at its natural size times SHOT_ZOOM: a drawing wider than the page column widens its canvas
    // instead of shrinking to fit, so a label drawn at 13 px stays 13 px. A narrower one keeps the column width.
    if (process.env.SHOT_CLIP === 'figure') await ev(`document.querySelectorAll("${SEL} svg").forEach(s=>{const c=s.parentElement, w=Math.ceil(s.viewBox.baseVal.width*${ZOOM});
      s.style.width=w+"px"; s.style.maxWidth=s.style.minWidth="none"; c.style.backgroundSize="${20 * ZOOM}px ${20 * ZOOM}px";
      if(w+2>c.getBoundingClientRect().width) c.style.width=(w+2)+"px"; })`);
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
  }
} finally { ws.close(); proc.kill(); }
if (failed.length) { console.error('shots: FAILED\n' + failed.join('\n')); process.exit(1); }
