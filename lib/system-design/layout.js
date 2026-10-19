// system-design layout: grid placement, orthogonal routing, edge label placement. Pure functions, no DOM.
// The build inlines this file into template.html; test.mjs requires it in node.
// A diagram is a grid of cells. A hinted node sits at its `at: [col, row]`; the rest are placed
// deterministically (layered by edge direction, or one column per lane). Edges run orthogonally
// through the gutters between cells, so no edge crosses a box.

const isCell = a => Array.isArray(a) && a.length === 2 && a.every(n => Number.isInteger(n) && n >= 0);

// Longest-path rank along edge direction; back edges of cycles (found by DFS in input order) are ignored.
function rankNodes(ids, edges) {
  const out = {}, rank = {}, state = {}, back = {};
  ids.forEach(id => { out[id] = []; rank[id] = 0; });
  edges.forEach(e => { if (e.v in out && e.w in out && e.v !== e.w) out[e.v].push(e.w); });
  const dfs = v => {
    state[v] = 1;
    out[v].forEach(w => { if (state[w] === 1) back[v + '>' + w] = 1; else if (!state[w]) dfs(w); });
    state[v] = 2;
  };
  ids.forEach(id => { if (!state[id]) dfs(id); });
  for (let k = 0; k < ids.length; k++) {
    let moved = false;
    ids.forEach(v => out[v].forEach(w => {
      if (!back[v + '>' + w] && rank[w] < rank[v] + 1) { rank[w] = rank[v] + 1; moved = true; }
    }));
    if (!moved) break;
  }
  return rank;
}

// Cell per node id. o.dir 'LR' (ranks are columns) or 'TB' (ranks are rows); o.lanes = ordered lane ids,
// node.lane picks one: each lane is a column, rows follow rank. Hinted nodes keep their cell.
function placeGrid(nodes, edges, o) {
  o = o || {};
  const cell = {}, taken = {}, K = (c, r) => c + ',' + r, warn = o.warn || [];
  nodes.forEach(n => {
    if (n.at == null) return;
    if (!isCell(n.at)) { warn.push(n.id + ': at must be [col, row] of whole numbers >= 0, placed automatically'); return; }
    if (taken[K(n.at[0], n.at[1])]) { warn.push(n.id + ': cell ' + n.at + ' already holds ' + taken[K(n.at[0], n.at[1])] + ', placed automatically'); return; }
    cell[n.id] = n.at.slice(); taken[K(n.at[0], n.at[1])] = n.id;
  });
  const free = nodes.filter(n => !cell[n.id]);
  if (!free.length) return cell;
  const ids = nodes.map(n => n.id), rank = rankNodes(ids, edges);
  const lanes = o.lanes && o.lanes.length ? o.lanes : null;
  // primary axis: lane index or rank; secondary: order inside it.
  const prim = {};
  free.forEach(n => { prim[n.id] = lanes ? (lanes.indexOf(n.lane) < 0 ? lanes.length : lanes.indexOf(n.lane)) : rank[n.id]; });
  const layers = [];
  free.forEach(n => { (layers[prim[n.id]] = layers[prim[n.id]] || []).push(n.id); });
  const nb = {};
  ids.forEach(id => { nb[id] = { up: [], down: [] }; });
  edges.forEach(e => { if (nb[e.v] && nb[e.w] && e.v !== e.w) { nb[e.w].up.push(e.v); nb[e.v].down.push(e.w); } });
  const slot = {};
  if (lanes) {
    // Inside a lane, follow rank, then input order.
    layers.forEach(L => { if (!L) return; L.sort((a, b) => rank[a] - rank[b] || ids.indexOf(a) - ids.indexOf(b)).forEach((id, i) => { slot[id] = i; }); });
  } else {
    // Barycenter sweeps (stable sort keeps input order on ties), then align each node with its neighbours' median.
    layers.forEach(L => L && L.forEach((id, i) => { slot[id] = i; }));
    const bary = (L, dir) => {
      const bc = id => { const xs = nb[id][dir].filter(x => x in slot).map(x => slot[x]); return xs.length ? xs.reduce((a, b) => a + b, 0) / xs.length : slot[id]; };
      const keyed = L.map(id => [id, bc(id)]);
      keyed.sort((a, b) => a[1] - b[1]);
      keyed.forEach((k, i) => { slot[k[0]] = i; L[i] = k[0]; });
    };
    for (let round = 0; round < 2; round++) {
      layers.forEach(L => L && bary(L, 'up'));
      for (let i = layers.length - 1; i >= 0; i--) if (layers[i]) bary(layers[i], 'down');
    }
    layers.forEach(L => {
      if (!L) return;
      let last = -1;
      L.forEach(id => {
        const xs = nb[id].up.filter(x => x in slot && prim[x] < prim[id]).map(x => slot[x]).sort((a, b) => a - b);
        const want = xs.length ? xs[Math.floor((xs.length - 1) / 2)] : last + 1;
        slot[id] = Math.max(want, last + 1); last = slot[id];
      });
    });
  }
  const lr = lanes || (o.dir || 'LR') === 'LR';
  layers.forEach((L, p) => L && L.forEach(id => {
    let s = slot[id];
    const at = () => lr ? [p, s] : [s, p];
    while (taken[K(...at())]) s++;
    cell[id] = at(); taken[K(...at())] = id;
  }));
  return cell;
}

// Route plans in grid terms. Each plan names its shape and the gutters it uses.
// Gutter i on the column axis sits before column i (0 = left margin); on the row axis, before row i.
function planRoutes(edges, cell) {
  const occ = {};
  Object.keys(cell).forEach(id => { occ[cell[id][0] + ',' + cell[id][1]] = id; });
  const empty = (c, r) => !occ[c + ',' + r];
  const between = (a, b) => { const out = []; for (let i = Math.min(a, b) + 1; i < Math.max(a, b); i++) out.push(i); return out; };
  return edges.map(e => {
    const A = cell[e.v], B = cell[e.w];
    if (!A || !B) return null;
    if (e.v === e.w) return { t: 'self' };
    if (e.via) return { t: 'via' };
    if (e.route === 'straight') return { t: 'straight' };
    const [ca, ra] = A, [cb, rb] = B, dc = Math.sign(cb - ca), dr = Math.sign(rb - ra);
    if (ra === rb && between(ca, cb).every(c => empty(c, ra))) return { t: 'h' };
    if (ca === cb && between(ra, rb).every(r => empty(ca, r))) return { t: 'v' };
    if (ra === rb) return { t: 'uh', rg: ra };
    if (ca === cb) return { t: 'uv', cg: ca + 1 };
    // L: along A's row to B's column, then into B's top or bottom.
    if (between(ca, cb).concat([cb]).every(c => empty(c, ra)) && between(ra, rb).every(r => empty(cb, r))) return { t: 'L1' };
    // L: along A's column to B's row, then into B's side.
    if (between(ra, rb).concat([rb]).every(r => empty(ca, r)) && between(ca, cb).every(c => empty(c, rb))) return { t: 'L2' };
    // Z through a column gutter, middle gutter first.
    const cgs = []; for (let g = Math.min(ca, cb) + 1; g <= Math.max(ca, cb); g++) cgs.push(g);
    const mid = (Math.min(ca, cb) + Math.max(ca, cb) + 1) / 2;
    cgs.sort((a, b) => Math.abs(a - mid) - Math.abs(b - mid) || a - b);
    // Gutter g sits between index g-1 and g. Cells between an end and the gutter must be empty.
    const span = (a, b) => { const out = []; for (let i = a; i < b; i++) out.push(i); return out; };
    for (const g of cgs) {
      const okA = (dc > 0 ? span(ca + 1, g) : span(g, ca)).every(c => empty(c, ra));
      const okB = (dc > 0 ? span(g, cb) : span(cb + 1, g)).every(c => empty(c, rb));
      if (okA && okB) return { t: 'zh', cg: g };
    }
    const rgs = []; for (let g = Math.min(ra, rb) + 1; g <= Math.max(ra, rb); g++) rgs.push(g);
    const midr = (Math.min(ra, rb) + Math.max(ra, rb) + 1) / 2;
    rgs.sort((a, b) => Math.abs(a - midr) - Math.abs(b - midr) || a - b);
    for (const g of rgs) {
      const okA = (dr > 0 ? span(ra + 1, g) : span(g, ra)).every(r => empty(ca, r));
      const okB = (dr > 0 ? span(g, rb) : span(rb + 1, g)).every(r => empty(cb, r));
      if (okA && okB) return { t: 'zv', rg: g };
    }
    // Channel: out of A into its adjacent column gutter, along the row gutter next to B, into B.
    return { t: 'ch', cg: dc > 0 ? ca + 1 : ca, rg: dr > 0 ? rb : rb + 1 };
  });
}

// Pixel geometry from cells, node sizes and gutter widths.
function geometry(nodes, cell, gc, gr, o) {
  let nc = 0, nr = 0;
  nodes.forEach(n => { const c = cell[n.id]; if (c) { nc = Math.max(nc, c[0] + 1); nr = Math.max(nr, c[1] + 1); } });
  const cw = Array(nc).fill(o.emptyW || 60), rh = Array(nr).fill(o.emptyH || 40), seen = {};
  nodes.forEach(n => {
    const c = cell[n.id]; if (!c) return;
    cw[c[0]] = Math.max(seen['c' + c[0]] ? cw[c[0]] : 0, n.w); seen['c' + c[0]] = 1;
    rh[c[1]] = Math.max(seen['r' + c[1]] ? rh[c[1]] : 0, n.h); seen['r' + c[1]] = 1;
  });
  const cx = [], ry = [];
  let x = 0; for (let i = 0; i < nc; i++) { x += gc[i]; cx.push(x); x += cw[i]; }
  const W = x + gc[nc];
  let y = 0; for (let i = 0; i < nr; i++) { y += gr[i]; ry.push(y); y += rh[i]; }
  const H = y + gr[nr];
  const box = {};
  nodes.forEach(n => {
    const c = cell[n.id]; if (!c) return;
    box[n.id] = { x: cx[c[0]] + (cw[c[0]] - n.w) / 2, y: o.alignTop ? ry[c[1]] : ry[c[1]] + (rh[c[1]] - n.h) / 2, w: n.w, h: n.h };
  });
  const gx = i => (i === 0 ? 0 : cx[i - 1] + cw[i - 1]) + gc[i] / 2;
  const gy = i => (i === 0 ? 0 : ry[i - 1] + rh[i - 1]) + gr[i] / 2;
  const at = v => { const f = Math.floor(v); return v - f >= 0.25 ? gx(f + 1) : cx[f] + cw[f] / 2; };
  const atY = v => { const f = Math.floor(v); return v - f >= 0.25 ? gy(f + 1) : ry[f] + rh[f] / 2; };
  return { nc, nr, cw, rh, cx, ry, W, H, box, gx, gy, at, atY };
}

const sideOf = (b, s, t) => s === 'r' ? [b.x + b.w, b.y + b.h * t] : s === 'l' ? [b.x, b.y + b.h * t] : s === 'b' ? [b.x + b.w * t, b.y + b.h] : [b.x + b.w * t, b.y];
// Where the ray from a box's center toward p leaves the box.
function clip(b, p) {
  const cx = b.x + b.w / 2, cy = b.y + b.h / 2, dx = p[0] - cx, dy = p[1] - cy;
  if (!dx && !dy) return [cx, cy];
  const s = Math.min(dx ? (b.w / 2) / Math.abs(dx) : Infinity, dy ? (b.h / 2) / Math.abs(dy) : Infinity);
  return [cx + dx * s, cy + dy * s];
}

// Points per edge, plus which segment sits in which gutter (for track offsets) and which ends sit on which side.
function pixelize(edges, plans, cell, G) {
  return edges.map((e, i) => {
    const p = plans[i]; if (!p) return null;
    const A = G.box[e.v], B = G.box[e.w], [ca, ra] = cell[e.v], [cb, rb] = cell[e.w];
    const acx = A.x + A.w / 2, acy = A.y + A.h / 2, bcx = B.x + B.w / 2, bcy = B.y + B.h / 2;
    const r = { pts: null, tracks: [], ends: [] };
    const hs = cb > ca ? ['r', 'l'] : ['l', 'r'], vs = rb > ra ? ['b', 't'] : ['t', 'b'];
    if (p.t === 'self') {
      const x = A.x + A.w, y = acy;
      r.pts = [[x, y - 8], [x + 22, y - 8], [x + 22, y + 8], [x, y + 8]];
    } else if (p.t === 'straight') {
      r.pts = [clip(A, [bcx, bcy]), clip(B, [acx, acy])];
    } else if (p.t === 'via') {
      const raw = [[acx, acy]].concat(e.via.map(v => [G.at(v[0]), G.atY(v[1])]), [[bcx, bcy]]);
      const pts = [raw[0]];
      for (let k = 1; k < raw.length; k++) {
        const a = pts[pts.length - 1], b = raw[k];
        if (a[0] !== b[0] && a[1] !== b[1]) pts.push([b[0], a[1]]);
        pts.push(b);
      }
      const first = pts[1], last = pts[pts.length - 2];
      pts[0] = first[1] === acy ? [first[0] > acx ? A.x + A.w : A.x, acy] : [acx, first[1] > acy ? A.y + A.h : A.y];
      pts[pts.length - 1] = last[1] === bcy ? [last[0] > bcx ? B.x + B.w : B.x, bcy] : [bcx, last[1] > bcy ? B.y + B.h : B.y];
      r.pts = pts;
    } else if (p.t === 'h') {
      const y = (Math.max(A.y, B.y) + Math.min(A.y + A.h, B.y + B.h)) / 2;
      r.pts = [[hs[0] === 'r' ? A.x + A.w : A.x, y], [hs[1] === 'l' ? B.x : B.x + B.w, y]];
      r.ends = [[e.v, hs[0], 0, 'y'], [e.w, hs[1], 1, 'y']]; r.straight = 'y';
    } else if (p.t === 'v') {
      const x = (Math.max(A.x, B.x) + Math.min(A.x + A.w, B.x + B.w)) / 2;
      r.pts = [[x, vs[0] === 'b' ? A.y + A.h : A.y], [x, vs[1] === 't' ? B.y : B.y + B.h]];
      r.ends = [[e.v, vs[0], 0, 'x'], [e.w, vs[1], 1, 'x']]; r.straight = 'x';
    } else if (p.t === 'uh') {
      const y = G.gy(p.rg);
      r.pts = [[acx, A.y], [acx, y], [bcx, y], [bcx, B.y]];
      r.tracks = [['r', p.rg, 1]]; r.ends = [[e.v, 't', 0, 'x'], [e.w, 't', 3, 'x']];
    } else if (p.t === 'uv') {
      const x = G.gx(p.cg);
      r.pts = [[A.x + A.w, acy], [x, acy], [x, bcy], [B.x + B.w, bcy]];
      r.tracks = [['c', p.cg, 1]]; r.ends = [[e.v, 'r', 0, 'y'], [e.w, 'r', 3, 'y']];
    } else if (p.t === 'L1') {
      r.pts = [[hs[0] === 'r' ? A.x + A.w : A.x, acy], [bcx, acy], [bcx, vs[1] === 't' ? B.y : B.y + B.h]];
      r.ends = [[e.v, hs[0], 0, 'y'], [e.w, vs[1], 2, 'x']];
    } else if (p.t === 'L2') {
      r.pts = [[acx, vs[0] === 'b' ? A.y + A.h : A.y], [acx, bcy], [hs[1] === 'l' ? B.x : B.x + B.w, bcy]];
      r.ends = [[e.v, vs[0], 0, 'x'], [e.w, hs[1], 2, 'y']];
    } else if (p.t === 'zh') {
      const x = G.gx(p.cg);
      r.pts = [[hs[0] === 'r' ? A.x + A.w : A.x, acy], [x, acy], [x, bcy], [hs[1] === 'l' ? B.x : B.x + B.w, bcy]];
      r.tracks = [['c', p.cg, 1]]; r.ends = [[e.v, hs[0], 0, 'y'], [e.w, hs[1], 3, 'y']];
    } else if (p.t === 'zv') {
      const y = G.gy(p.rg);
      r.pts = [[acx, vs[0] === 'b' ? A.y + A.h : A.y], [acx, y], [bcx, y], [bcx, vs[1] === 't' ? B.y : B.y + B.h]];
      r.tracks = [['r', p.rg, 1]]; r.ends = [[e.v, vs[0], 0, 'x'], [e.w, vs[1], 3, 'x']];
    } else {
      const x = G.gx(p.cg), y = G.gy(p.rg), vin = rb > ra ? 't' : 'b';
      r.pts = [[hs[0] === 'r' ? A.x + A.w : A.x, acy], [x, acy], [x, y], [bcx, y], [bcx, vin === 't' ? B.y : B.y + B.h]];
      r.tracks = [['c', p.cg, 1], ['r', p.rg, 2]]; r.ends = [[e.v, hs[0], 0, 'y'], [e.w, vin, 4, 'x']];
    }
    return r;
  });
}

// Spread segments sharing a gutter, and edge ends sharing a box side, so no two lines lie on top of each other.
function separate(routes, edges, G, step) {
  const groups = {};
  routes.forEach((r, i) => r && r.tracks.forEach(t => { (groups[t[0] + t[1]] = groups[t[0] + t[1]] || []).push([i, t]); }));
  Object.keys(groups).forEach(k => {
    const g = groups[k]; if (g.length < 2) return;
    const ax = g[0][1][0] === 'c' ? 0 : 1, oth = 1 - ax;
    g.sort((a, b) => {
      const pa = routes[a[0]].pts, pb = routes[b[0]].pts;
      return Math.min(pa[a[1][2]][oth], pa[a[1][2] + 1][oth]) - Math.min(pb[b[1][2]][oth], pb[b[1][2] + 1][oth]) || a[0] - b[0];
    });
    g.forEach(([i, t], n) => {
      const d = (n - (g.length - 1) / 2) * step, pts = routes[i].pts;
      pts[t[2]][ax] += d; pts[t[2] + 1][ax] += d;
    });
  });
  // Box sides: ends sorted by where the edge heads, then spaced evenly along the side.
  const sides = {};
  routes.forEach((r, i) => r && r.ends.forEach(en => { (sides[en[0] + '|' + en[1]] = sides[en[0] + '|' + en[1]] || []).push([i, en]); }));
  Object.keys(sides).forEach(k => {
    const s = sides[k]; if (s.length < 2) return;
    const b = G.box[s[0][1][0]], ax = s[0][1][3] === 'y' ? 1 : 0;
    const far = ([i, en]) => { const pts = routes[i].pts, j = en[2] === 0 ? Math.min(2, pts.length - 1) : Math.max(0, pts.length - 3); return pts[j][ax]; };
    s.sort((a, b2) => far(a) - far(b2) || a[0] - b2[0]);
    const len = ax ? b.h : b.w, gap = Math.min(24, len / (s.length + 1));
    s.forEach(([i, en], n) => {
      const pos = (ax ? b.y : b.x) + len / 2 + (n - (s.length - 1) / 2) * gap, pts = routes[i].pts;
      if (routes[i].straight) return; // straight lines are moved below, both ends together
      const j = en[2], nj = j === 0 ? 1 : j - 1;
      pts[j][ax] = pos; pts[nj][ax] = pos;
    });
  });
  // Parallel straight edges between the same two boxes sit side by side.
  const pairs = {};
  routes.forEach((r, i) => { if (r && r.straight) { const k = [edges[i].v, edges[i].w].sort().join('|'); (pairs[k] = pairs[k] || []).push(i); } });
  Object.keys(pairs).forEach(k => {
    const g = pairs[k]; if (g.length < 2) return;
    g.forEach((i, n) => { const ax = routes[i].straight === 'y' ? 1 : 0, d = (n - (g.length - 1) / 2) * 22; routes[i].pts.forEach(p => { p[ax] += d; }); });
  });
}

const hit = (a, b) => a.x < b.x + b.w && b.x < a.x + a.w && a.y < b.y + b.h && b.y < a.y + a.h;
const segRect = (p, q) => ({ x: Math.min(p[0], q[0]) - 1, y: Math.min(p[1], q[1]) - 1, w: Math.abs(p[0] - q[0]) + 2, h: Math.abs(p[1] - q[1]) + 2 });

// Label spots: each segment, longest first, at a few points along it, on either side.
// Hard: a box, another label or the frame edge. Soft: crossing another edge's line.
function placeLabels(edges, routes, G, obstacles, LH) {
  const placed = [], fails = [], segs = [];
  routes.forEach((r, i) => r && r.pts.slice(1).forEach((q, k) => segs.push({ i, p: r.pts[k], q })));
  edges.forEach((e, i) => {
    const r = routes[i]; if (!r || !e.lw) return;
    const h = e.lines.length * LH, w = e.lw;
    const cands = [];
    r.pts.slice(1).map((q, k) => [r.pts[k], q]).sort((a, b) => Math.hypot(b[1][0] - b[0][0], b[1][1] - b[0][1]) - Math.hypot(a[1][0] - a[0][0], a[1][1] - a[0][1]))
      .forEach(([p, q]) => [0.5, 0.35, 0.65, 0.2, 0.8, 0.1, 0.9].forEach(f => {
        const mx = p[0] + (q[0] - p[0]) * f, my = p[1] + (q[1] - p[1]) * f;
        if (p[1] === q[1]) {
          cands.push({ x: mx - w / 2, y: my - h - 5, a: 'middle' }, { x: mx - w / 2, y: my + 5, a: 'middle' });
        } else if (p[0] === q[0]) {
          cands.push({ x: mx + 7, y: my - h / 2, a: 'start' }, { x: mx - 7 - w, y: my - h / 2, a: 'end' });
        } else {
          cands.push({ x: mx + 6, y: my - h - 2, a: 'start' }, { x: mx - 6 - w, y: my + 2, a: 'start' });
        }
      }));
    let best = null, bestScore = Infinity;
    cands.forEach(c => {
      const rc = { x: c.x - 2, y: c.y - 1, w: w + 4, h: h + 2 };
      let score = 0;
      if (rc.x < 2 || rc.y < 2 || rc.x + rc.w > G.W - 2 || rc.y + rc.h > G.H - 2) score += 1000;
      obstacles.forEach(b => { if (hit(rc, b)) score += 1000; });
      placed.forEach(b => { if (hit(rc, b)) score += 1000; });
      segs.forEach(s => { if (s.i !== i && hit(rc, segRect(s.p, s.q))) score += 1; });
      if (score < bestScore) { bestScore = score; best = c; }
    });
    if (!best) return;
    const rect = { x: best.x - 2, y: best.y - 1, w: w + 4, h: h + 2 };
    placed.push(rect);
    if (bestScore >= 1000) fails.push({ i, rect }); else if (bestScore > 0) fails.push({ i, rect, soft: true });
    r.label = { x: best.a === 'middle' ? best.x + w / 2 : best.a === 'end' ? best.x + w : best.x, y: best.y, a: best.a, lines: e.lines, rect };
  });
  return fails;
}

// The whole pipeline. nodes [{id, w, h, at, lane}], edges [{v, w, lines, lw, via, route}].
// o: {dir, lanes, gutterW, gutterH, margin, alignTop, warn, lineH, obstacles(G) -> rects}.
// Returns {cell, box, routes, W, H, G}. Labels that cannot find a clear spot widen the gutters around them.
function layoutGraph(nodes, edges, o) {
  o = o || {};
  const warn = o.warn || [], LH = o.lineH || 13;
  const known = {}; nodes.forEach(n => { known[n.id] = 1; });
  const ok = edges.filter(e => { if (known[e.v] && known[e.w]) return true; warn.push('edge ' + e.v + ' to ' + e.w + ': unknown end, not drawn'); return false; });
  const cell = placeGrid(nodes, ok, { dir: o.dir, lanes: o.lanes, warn });
  const plans = planRoutes(ok, cell);
  let nc = 0, nr = 0;
  Object.keys(cell).forEach(id => { nc = Math.max(nc, cell[id][0] + 1); nr = Math.max(nr, cell[id][1] + 1); });
  const m = o.margin == null ? 40 : o.margin;
  const gc = Array(nc + 1).fill(o.gutterW || 80), gr = Array(nr + 1).fill(o.gutterH || 56);
  gc[0] = gc[nc] = m; gr[0] = gr[nr] = m;
  Object.keys(o.gutterRows || {}).forEach(k => { if (+k <= nr) gr[+k] = Math.max(gr[+k], o.gutterRows[k]); });
  // Gutters fit the labels of straight edges between neighbours and the tracks that run through them.
  const count = {};
  plans.forEach((p, i) => {
    if (!p) return;
    const e = ok[i], A = cell[e.v], B = cell[e.w];
    if (p.t === 'h' && Math.abs(A[0] - B[0]) === 1) gc[Math.max(A[0], B[0])] = Math.max(gc[Math.max(A[0], B[0])], (e.lw || 0) + 30);
    if (p.t === 'v' && Math.abs(A[1] - B[1]) === 1) gr[Math.max(A[1], B[1])] = Math.max(gr[Math.max(A[1], B[1])], e.lines.length * LH + 22);
    if (p.cg != null) count['c' + p.cg] = (count['c' + p.cg] || 0) + 1;
    if (p.rg != null) count['r' + p.rg] = (count['r' + p.rg] || 0) + 1;
  });
  Object.keys(count).forEach(k => { const g = +k.slice(1), need = count[k] * 12 + 28; if (k[0] === 'c') gc[g] = Math.max(gc[g], need); else gr[g] = Math.max(gr[g], need); });
  let G, routes, fails = [];
  for (let round = 0; round < 7; round++) {
    G = geometry(nodes, cell, gc, gr, o);
    routes = pixelize(ok, plans, cell, G);
    separate(routes, ok, G, 12);
    const obs = Object.keys(G.box).map(id => { const b = G.box[id]; return { x: b.x - 3, y: b.y - 3, w: b.w + 6, h: b.h + 6 }; }).concat(o.obstacles ? o.obstacles(G) : []);
    // A label on top of another edge's line widens its gutter only in the first rounds; a label on a box always does.
    fails = placeLabels(ok, routes, G, obs, LH).filter(f => !f.soft || round < 2);
    if (!fails.length) break;
    // Widen each gutter a failed label overlaps (once per round), then lay out again.
    const wc = {}, wr = {};
    fails.forEach(f => {
      const r = f.rect;
      for (let g = 0; g <= G.nc; g++) {
        const x0 = g === 0 ? 0 : G.cx[g - 1] + G.cw[g - 1], x1 = g === G.nc ? G.W : G.cx[g];
        if (r.x < x1 && r.x + r.w > x0) wc[g] = 1;
      }
      for (let g = 0; g <= G.nr; g++) {
        const y0 = g === 0 ? 0 : G.ry[g - 1] + G.rh[g - 1], y1 = g === G.nr ? G.H : G.ry[g];
        if (r.y < y1 && r.y + r.h > y0) wr[g] = 1;
      }
    });
    Object.keys(wc).forEach(g => { gc[g] += 30; });
    Object.keys(wr).forEach(g => { gr[g] += 16; });
    if (!Object.keys(wc).length && !Object.keys(wr).length) gc[0] += 30;
  }
  fails = fails.filter(f => !f.soft);
  if (fails.length) warn.push(fails.length + ' edge label(s) overlap something; add at: or via: hints');
  const all = routes.map((r, i) => r && Object.assign(r, { e: ok[i] })).filter(Boolean);
  return { cell, box: G.box, routes: all, W: G.W, H: G.H, G };
}

if (typeof module !== 'undefined') module.exports = { rankNodes, placeGrid, planRoutes, layoutGraph, isCell };
