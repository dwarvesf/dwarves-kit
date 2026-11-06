// Smoke test: node test.mjs. No install. Asserts the exact delta list for the marketplace fixture.
// ponytail: fetches js-yaml from the same pinned cdnjs URL the page loads, so it needs network.
// Upgrade path if offline runs matter: cache the file under $TMPDIR keyed by version.
import { readFileSync } from 'node:fs';
import { createRequire } from 'node:module';
import vm from 'node:vm';
import assert from 'node:assert/strict';

const here = new URL('.', import.meta.url).pathname;
const { parseModel, diffModels, deltaLines, c4Zoom } = createRequire(import.meta.url)('./delta.js');
const { placeGrid, layoutGraph, planBoundaries, boundaryFrames, frameClashes } = createRequire(import.meta.url)('./layout.js');

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

// C4 sheets: the marketplace example as a four-view set (context, container, component, deployment) with a base for the delta.
const readC4 = f => readFileSync(here + 'examples/marketplace-c4/' + f, 'utf8');
const c4base = parseModel(readC4('SYSTEM-DESIGN.base.md'), load);
const c4cur = parseModel(readC4('SYSTEM-DESIGN.md'), load);
assert.deepEqual(c4base.errors, []);
assert.deepEqual(c4cur.errors, []);
assert.deepEqual(c4cur.diagrams.map(d => d.spec.view), ['context', 'container', 'component', 'deployment']);
assert.ok(c4cur.diagrams.every(d => d.type === 'c4'));
// Parsing keeps the c4 fields as written.
const core = c4cur.diagrams[1].spec.elements.find(e => e.id === 'core');
assert.deepEqual([core.c4, core.tech, core.boundary, core.zoom], ['container', 'Go, REST /v1, JSON', 'mono', 'c4-core']);
assert.equal(c4cur.diagrams[0].spec.elements.find(e => e.id === 'stripe').ext, true);
assert.equal(JSON.stringify(c4cur.diagrams[1].spec.boundaries.map(b => [b.id, b.kind, b.in ?? null])), JSON.stringify([['mkt', 'system', null], ['mono', 'container', 'mkt']]));

// Delta: c4 elements and relations are new, changed or removed exactly like component nodes and edges.
const c4want = [
  'new c4-context element email',
  'new c4-context relation marketplace → email Sends notices',
  'changed c4-containers element web: ~desc',
  'removed c4-containers element cron',
  'new c4-containers element r2',
  'removed c4-containers relation cron → core Expires quotes',
  'removed c4-containers relation core → stripe Charges',
  'new c4-containers relation core → r2 Stores images',
  'new c4-containers relation core → stripe PaymentGateway',
  'new c4-core element webhook',
  'new c4-core relation stripe → webhook Posts events',
  'new c4-core relation webhook → orders Marks paid',
  'new c4-deploy element app-2',
  'new c4-deploy relation cf-edge → app-2 Forwards',
  'new c4-deploy relation app-2 → pg Reads and writes',
  'removed c4-deploy relation app-1 → email Sends',
  'new c4-deploy relation app-2 → email Sends',
  'new c4-deploy relation app-2 → r2 Stores images',
];
const c4got = deltaLines(diffModels(c4base, c4cur));
assert.deepEqual(c4got, c4want);
assert.deepEqual(deltaLines(diffModels(null, c4cur)), []);

// A changed technology or kind marks the element or relation; layout keys, tone and zoom never do; a moved boundary does.
const c4 = (o = {}) => '# T\n\n```uml\nid: v\ntype: c4\nview: ' + (o.view || 'container') + '\ntitle: V\nboundaries:\n  - {id: b1, name: B1, kind: system' + (o.btone ? ', tone: blue' : '') + '}\n  - {id: b2, name: B2, kind: system}\nelements:\n  - {id: a, name: A, c4: ' + (o.kind || 'container') + ', tech: ' + (o.tech || 'Go') + ', boundary: ' + (o.bnd || 'b1') + ', at: ' + (o.at || '[0, 0]') + (o.tone ? ', tone: ' + o.tone : '') + (o.zoom ? ', zoom: ' + o.zoom : '') + '}\n  - {id: b, name: B, c4: db, boundary: b1}\nrelations:\n  - {from: a, to: b, label: reads, tech: ' + (o.rtech || 'SQL') + (o.via ? ', via: ' + o.via : '') + '}\n```\n';
const k0 = parseModel(c4(), load);
assert.deepEqual(k0.errors, []);
const dl = o => deltaLines(diffModels(k0, parseModel(c4(o), load)));
assert.deepEqual(dl({ tech: 'Rust' }), ['changed v element a: ~tech']);
assert.deepEqual(dl({ kind: 'component' }), ['changed v element a: ~c4']);
assert.deepEqual(dl({ rtech: 'gRPC' }), ['changed v relation a → b reads: ~tech']);
assert.deepEqual(dl({ at: '[2, 3]', tone: 'rose', via: '[[0.5, 1]]', zoom: 'other', btone: true }), []);
assert.deepEqual(dl({ bnd: 'b2' }), ['changed v element a: ~boundary']);
assert.deepEqual(dl({ view: 'component' }), ['changed v diagram c4: ~view']);
// The view is required and checked.
assert.match(parseModel(c4().replace('view: container\n', ''), load).errors[0], /c4 view must be one of context, container, component, deployment/);
assert.match(parseModel(c4({ view: 'code' }), load).errors[0], /got code/);

// Zoom links: every zoom on the example names a sheet of the model; a dangling one is reported as not ok.
const zooms = c4Zoom(c4cur);
assert.ok(zooms.length >= 2);
assert.deepEqual(zooms.filter(z => !z.ok), []);
assert.deepEqual(new Set(zooms.map(z => z.zoom)), new Set(['c4-containers', 'c4-core']));
assert.deepEqual(c4Zoom(parseModel(c4({ zoom: 'nowhere' }), load)).map(z => [z.element, z.zoom, z.ok]), [['a', 'nowhere', false]]);
assert.deepEqual(c4Zoom(parseModel(c4({ zoom: 'v' }), load)).map(z => z.ok), [true]);

// Boundaries nest: parents come before children, every subtree stays contiguous, and a loose element sits left of the
// frames when it only calls into them, else right.
const bp = planBoundaries([{ id: 'acct', name: 'Acct' }, { id: 'reg', name: 'Reg', in: 'acct' }, { id: 'other', name: 'Other' }],
  [{ id: 'p' }, { id: 'x', boundary: 'reg' }, { id: 'y', boundary: 'acct' }, { id: 'z', boundary: 'other' }, { id: 'q' }],
  [{ v: 'p', w: 'x' }, { v: 'x', w: 'q' }, { v: 'q', w: 'x' }]);
assert.deepEqual(bp.order, ['\u0000left', 'acct', 'reg', 'other', '\u0000right']);
assert.deepEqual([bp.laneOf.p, bp.laneOf.q], ['\u0000left', '\u0000right']);
const loopWarn = []; planBoundaries([{ id: 'a', in: 'b' }, { id: 'b', in: 'a' }, { id: 'c', in: 'nope' }], [{ id: 'k', boundary: 'a' }], [], loopWarn);
assert.equal(loopWarn.length, 2);
// A frame that covers a foreign box is reported.
const fbox = { a: { x: 0, y: 0, w: 100, h: 50 }, b: { x: 0, y: 80, w: 100, h: 50 }, c: { x: 140, y: 0, w: 100, h: 50 } };
const fplan = planBoundaries([{ id: 'f' }], [{ id: 'a', boundary: 'f' }, { id: 'c', boundary: 'f' }, { id: 'b' }], []);
assert.deepEqual(frameClashes(boundaryFrames(fplan, fbox), fbox), []);
fbox.b.y = 10;
assert.deepEqual(frameClashes(boundaryFrames(fplan, fbox), fbox), [['f', 'b']]);

// Fallback layout on every marketplace sheet the grid engine draws, UML and C4: deterministic, orthogonal, no edge
// through a box, no box on another, and every label clear of boxes. C4 boundaries also hold: each frame covers its own
// elements and no foreign one.
const SPEC = { component: ['nodes', 'edges', 'LR'], erd: ['tables', 'rels', 'LR'], state: ['states', 'transitions', 'LR'], class: ['classes', 'relations', 'TB'], c4: ['elements', 'relations', 'LR'] };
let laid = 0, framed = 0;
for (const d of cur.diagrams.concat(c4cur.diagrams).filter(x => SPEC[x.type])) {
  const [nk, ek, dir] = SPEC[d.type];
  const id = e => e.id || e.name;
  const edges = (d.spec[ek] || []).map(e => ({ v: e.from, w: e.to, lines: e.label ? [String(e.label)] : [], lw: e.label ? String(e.label).length * 6.4 : 0 }));
  const plan = d.type === 'c4' ? planBoundaries(d.spec.boundaries || [], d.spec[nk].map(e => ({ id: id(e), boundary: e.boundary })), edges) : null;
  const nodes = d.spec[nk].map((e, i) => ({ id: id(e), w: 150 + (i % 3) * 20, h: 50 + (i % 2) * 30, lane: plan ? plan.laneOf[id(e)] : e.group }));
  const lanes = plan ? (plan.order.length ? plan.order : null) : d.type === 'component' ? [...new Set(nodes.map(n => n.lane).filter(Boolean))] : null;
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
  if (plan) {
    const frames = boundaryFrames(plan, L.box);
    assert.deepEqual(frameClashes(frames, L.box), [], d.id + ': a boundary frame covers a foreign element');
    for (const f of frames) for (const m of plan.own[f.id] || []) assert.ok(f.members.includes(m), d.id + ': frame ' + f.id + ' lacks ' + m);
    // A parent frame encloses its children's frames.
    for (const f of frames) for (const k of plan.kids[f.id]) {
      const fk = frames.find(x => x.id === k);
      if (fk) assert.ok(f.x <= fk.x && f.y <= fk.y && f.x + f.w >= fk.x + fk.w && f.y + f.h >= fk.y + fk.h, d.id + ': frame ' + f.id + ' does not enclose ' + k);
    }
    framed += frames.length;
  }
  laid++;
}
assert.ok(laid >= 10);
assert.ok(framed >= 5);
console.log('ok: ' + got.length + ' uml and ' + c4got.length + ' c4 deltas match, ' + zooms.length + ' zoom links resolve, ' + laid + ' fallback layouts clean (' + framed + ' boundary frames)');
