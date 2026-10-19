// Smoke test: node test.mjs. No install. Asserts the exact delta list for the marketplace fixture.
// ponytail: fetches js-yaml from the same pinned cdnjs URL the page loads, so it needs network.
// Upgrade path if offline runs matter: cache the file under $TMPDIR keyed by version.
import { readFileSync } from 'node:fs';
import { createRequire } from 'node:module';
import vm from 'node:vm';
import assert from 'node:assert/strict';

const here = new URL('.', import.meta.url).pathname;
const { parseModel, diffModels, deltaLines } = createRequire(import.meta.url)('./delta.js');
const { placeGrid, layoutGraph } = createRequire(import.meta.url)('./layout.js');

const src = await (await fetch('https://cdnjs.cloudflare.com/ajax/libs/js-yaml/4.1.0/js-yaml.min.js')).text();
const ctx = {}; ctx.self = ctx; vm.runInNewContext(src, ctx);
const load = ctx.jsyaml.load;

const read = f => readFileSync(here + 'examples/marketplace/' + f, 'utf8');
const base = parseModel(read('SYSTEM-DESIGN.base.md'), load);
const cur = parseModel(read('SYSTEM-DESIGN.md'), load);
assert.deepEqual(base.errors, []);
assert.deepEqual(cur.errors, []);
assert.equal(cur.diagrams.length, 14);

const got = deltaLines(diffModels(base, cur));
// Removed items sit after their nearest surviving base predecessor.
const want = [
  'changed schema table variants: -col stock, +col stock_on_hand, +col stock_reserved',
  'changed schema table quotes: -col approve_token, +col idempotency_scope, +col request_hash, +col tax_calculation_id, +col payment_intent_id, +col approve_token_hash',
  'new schema table outbox',
  'new sm-quote state paying',
  'removed sm-quote transition sent → paid owner pays',
  'new sm-quote transition sent → paying owner pays',
  'removed sm-quote transition open → paid agent pays (card)',
  'new sm-quote transition open → paying agent pays (card)',
  'new sm-quote transition paying → paid payment_succeeded',
  'new sm-quote transition paying → cancelled owner rejects',
  'new sm-quote transition paying → expired held_until passes',
  'new sm-order state cancelling',
  'new sm-order state refunding',
  'removed sm-order transition paid → cancelled cancel',
  'removed sm-order transition shipped → refunded refund',
  'removed sm-order transition delivered → refunded refund',
  'new sm-order transition paid → cancelling cancel',
  'new sm-order transition cancelling → cancelled charge.refunded',
  'new sm-order transition shipped → refunding refund',
  'new sm-order transition delivered → refunding refund',
  'new sm-order transition refunding → refunded charge.refunded',
];
assert.deepEqual(got, want);

// Inserting one message early in a sequence marks exactly one new message, not every later one.
const seq = msgs => '# T\n\n```uml\nid: s\ntype: sequence\ntitle: S\nparticipants: [a, b]\nmessages:\n' + msgs.map(m => '  - {from: ' + m[0] + ', to: ' + m[1] + ', text: ' + m[2] + '}').join('\n') + '\n```\n';
const m1 = ['a', 'b', 'one'], m2 = ['b', 'a', 'two'], m3 = ['a', 'b', 'one'], m4 = ['a', 'b', 'three'];
const sb = parseModel(seq([m1, m2, m3, m4]), load);
const sc = parseModel(seq([['a', 'b', 'early'], m1, m2, m3, m4]), load);
const sd = deltaLines(diffModels(sb, sc)).filter(l => l.includes(' message '));
assert.deepEqual(sd, ['new s message a|b|early']);

// Trailing prose after the last block becomes a section, not a diagram note.
const tail = parseModel(seq([m1]) + '\n## Risks and technical debt\n\n- queue can back up\n', load);
assert.deepEqual(tail.sections.map(s => s.title), ['Risks and technical debt']);
assert.match(tail.sections[0].body, /queue can back up/);

// No base: nothing is marked.
assert.deepEqual(deltaLines(diffModels(null, cur)), []);

// Front matter: rev and decided go to the cover; the prose under the title is the intro, not a diagram note.
const fm = parseModel('---\nrev: C\ndecided: [one, two]\n---\n# M\n\nIntro text.\n\n## A\n\nNote A.\n\n' + seq([m1]).slice(4), load);
assert.equal(fm.rev, 'C');
assert.deepEqual([...fm.decided], ['one', 'two']);
assert.equal(fm.title, 'M');
assert.equal(fm.intro, 'Intro text.');
assert.doesNotMatch(fm.diagrams[0].note, /Intro/);
assert.match(fm.diagrams[0].note, /Note A/);

// Layout hints are not design changes: moving a node or rerouting an edge marks nothing; a label edit still does.
const comp = (at, via, lbl) => '# T\n\n```uml\nid: c\ntype: component\ntitle: C\nreview: [check this]\nnodes:\n  - {id: a, name: A, at: ' + at + '}\n  - {id: b, name: B}\nedges:\n  - {from: a, to: b, label: ' + lbl + ', via: ' + via + '}\n```\n';
const c0 = parseModel(comp('[0, 0]', '[[0.5, 1]]', 'calls'), load);
assert.deepEqual([...c0.diagrams[0].review], ['check this']);
assert.deepEqual(deltaLines(diffModels(c0, parseModel(comp('[3, 2]', '[[1.5, 0]]', 'calls'), load))), []);
assert.deepEqual(deltaLines(diffModels(c0, parseModel(comp('[3, 2]', '[[1.5, 0]]', 'reads'), load))), ['removed c edge a → b calls', 'new c edge a → b reads']);

// Tone is presentation: adding or changing it marks nothing, also on a participant that turns from a string into {name, tone}.
const tonal = (tone, ptone) => '# T\n\n```uml\nid: c\ntype: component\ntitle: C\nlanes: [{id: l, name: L' + (tone ? ', tone: ' + tone : '') + '}]\nnodes:\n  - {id: a, name: A, lane: l' + (tone ? ', tone: ' + tone : '') + '}\n  - {id: b, name: B}\nedges:\n  - {from: a, to: b' + (tone ? ', tone: rose' : '') + '}\n```\n\n```uml\nid: s\ntype: sequence\ntitle: S\nparticipants: [' + (ptone ? '{name: P, tone: ' + ptone + '}' : 'P') + ', Q]\nmessages:\n  - {from: P, to: Q, text: hi' + (ptone ? ', tone: rose' : '') + '}\n```\n';
const t0 = parseModel(tonal('', ''), load);
assert.deepEqual(t0.errors, []);
assert.deepEqual(deltaLines(diffModels(t0, parseModel(tonal('blue', 'green'), load))), []);
assert.deepEqual(deltaLines(diffModels(parseModel(tonal('blue', 'green'), load), parseModel(tonal('amber', 'violet'), load))), []);

// Every tone has a fill, stroke and label ink in the light palette and both dark blocks; label ink is AA (4.5) on the fill,
// the stroke is 3:1 against the sheet.
const tpl = readFileSync(here + 'template.html', 'utf8');
const blocks = tpl.slice(tpl.indexOf(':root{'), tpl.indexOf('*{box-sizing')).split(/(?=:root|  :root)/).filter(b => /--tn-blue-f/.test(b));
assert.equal(blocks.length, 3, 'tone tokens: light + two dark blocks');
const lum = hex => { const c = [1, 3, 5].map(i => parseInt(hex.slice(i, i + 2), 16) / 255).map(v => v <= 0.03928 ? v / 12.92 : ((v + 0.055) / 1.055) ** 2.4); return 0.2126 * c[0] + 0.7152 * c[1] + 0.0722 * c[2]; };
const ratio = (a, b) => { const [x, y] = [lum(a), lum(b)].sort((m, n) => n - m); return (x + 0.05) / (y + 0.05); };
for (const blk of blocks) {
  const tok = k => new RegExp('--' + k + ':(#[0-9a-fA-F]{6})').exec(blk)?.[1];
  const sheet = tok('sheet') || '#ffffff';
  for (const t of ['blue', 'green', 'amber', 'rose', 'violet', 'gray']) {
    const [f, st, ink] = ['f', 's', 'i'].map(k => tok('tn-' + t + '-' + k));
    assert.ok(f && st && ink, t + ': missing token');
    assert.ok(ratio(ink, f) >= 4.5, t + ': label ink on fill ' + ratio(ink, f).toFixed(2));
    assert.ok(ratio(ink, sheet) >= 4.5, t + ': label ink on sheet ' + ratio(ink, sheet).toFixed(2));
    assert.ok(ratio(st, sheet) >= 3, t + ': stroke on sheet ' + ratio(st, sheet).toFixed(2));
  }
}

// Grid placement: hints win, bad or clashing hints fall back with a warning, nothing shares a cell.
const warn = [];
const cells = placeGrid([{ id: 'a', at: [2, 1] }, { id: 'b', at: [2, 1] }, { id: 'c', at: [-1, 0] }, { id: 'd' }], [{ v: 'a', w: 'd' }], { warn });
assert.deepEqual(cells.a, [2, 1]);
assert.equal(warn.length, 2);
assert.equal(new Set(Object.values(cells).map(String)).size, 4);

// Fallback layout on every marketplace sheet the grid engine draws: deterministic, orthogonal, no edge through a box,
// no box on another, and every label clear of boxes.
const SPEC = { component: ['nodes', 'edges', 'LR'], erd: ['tables', 'rels', 'LR'], state: ['states', 'transitions', 'LR'], class: ['classes', 'relations', 'TB'] };
let laid = 0;
for (const d of cur.diagrams.filter(x => SPEC[x.type])) {
  const [nk, ek, dir] = SPEC[d.type];
  const id = e => e.id || e.name;
  const nodes = d.spec[nk].map((e, i) => ({ id: id(e), w: 150 + (i % 3) * 20, h: 50 + (i % 2) * 30, lane: e.group }));
  const edges = (d.spec[ek] || []).map(e => ({ v: e.from, w: e.to, lines: e.label ? [String(e.label)] : [], lw: e.label ? String(e.label).length * 6.4 : 0 }));
  const lanes = d.type === 'component' ? [...new Set(nodes.map(n => n.lane).filter(Boolean))] : null;
  const run = () => { const w = []; return { L: layoutGraph(nodes, edges, { dir, lanes, warn: w }), w }; };
  const { L, w } = run();
  assert.deepEqual(JSON.stringify(run().L.routes.map(r => r.pts)), JSON.stringify(L.routes.map(r => r.pts)), d.id + ': layout is not deterministic');
  assert.deepEqual(w.filter(x => /overlap/.test(x)), [], d.id + ': ' + w.join('; '));
  const boxes = Object.entries(L.box);
  for (const [i, a] of boxes) for (const [j, b] of boxes) if (i < j) assert.ok(a.x + a.w <= b.x || b.x + b.w <= a.x || a.y + a.h <= b.y || b.y + b.h <= a.y, d.id + ': ' + i + ' overlaps ' + j);
  for (const r of L.routes) {
    r.pts.slice(1).forEach((q, k) => {
      const p = r.pts[k];
      assert.ok(p[0] === q[0] || p[1] === q[1], d.id + ': diagonal segment on ' + r.e.v + ' to ' + r.e.w);
      for (const [bid, b] of boxes) {
        const x0 = Math.min(p[0], q[0]), x1 = Math.max(p[0], q[0]), y0 = Math.min(p[1], q[1]), y1 = Math.max(p[1], q[1]);
        const inside = x1 > b.x + 1.5 && x0 < b.x + b.w - 1.5 && y1 > b.y + 1.5 && y0 < b.y + b.h - 1.5;
        assert.ok(!inside, d.id + ': edge ' + r.e.v + ' to ' + r.e.w + ' crosses ' + bid);
      }
    });
    if (r.label) for (const [bid, b] of boxes) assert.ok(!(r.label.rect.x < b.x + b.w && b.x < r.label.rect.x + r.label.rect.w && r.label.rect.y < b.y + b.h && b.y < r.label.rect.y + r.label.rect.h), d.id + ': label on ' + bid);
  }
  laid++;
}
assert.ok(laid >= 6);
console.log('ok: ' + got.length + ' deltas match, ' + laid + ' fallback layouts clean');
