// system-design: parse a SYSTEM-DESIGN.md model and diff two of them. Pure functions, no DOM.
// The build inlines this file into template.html; test.mjs requires it in node.

var UML_TYPES = ['usecase', 'class', 'erd', 'sequence', 'state', 'component'];

var idn = function (e) { return typeof e === 'string' ? e : (e.id || e.name); };
var arrowKey = function (extra) {
  return function (e) { return e.id || (e.from + ' → ' + e.to + (e[extra] ? ' ' + e[extra] : '')); };
};

// Per type: [field, kind label, identity fn]. Identity is id, else name, else from/to.
var UML_COLL = {
  usecase: [['actors', 'actor', idn], ['cases', 'case', idn]],
  class: [['classes', 'class', idn], ['relations', 'relation', arrowKey('kind')]],
  erd: [['tables', 'table', idn], ['rels', 'rel', arrowKey('label')]],
  sequence: [['participants', 'participant', idn], ['messages', 'message', function (e) { return e.from + '|' + e.to + '|' + e.text; }]],
  state: [['states', 'state', idn], ['transitions', 'transition', arrowKey('event')]],
  component: [['nodes', 'node', idn], ['edges', 'edge', arrowKey('label')]]
};

// Rows inside an element that get their own +/-/~ marks.
var rowName = function (r) { return Array.isArray(r) ? String(r[0]) : String(r).split(/[:(\s]/)[0]; };
var UML_ROWS = { table: [['cols', 'col']], class: [['attrs', 'attr'], ['ops', 'op']] };

// Layout hints place an element on its sheet and tone colors it; neither is a design change, so the delta skips them.
var LAYOUT_KEYS = { at: 1, via: 1, route: 1, side: 1, lane: 1, tone: 1 };
function bare(v) {
  if (!v || typeof v !== 'object' || Array.isArray(v)) return v;
  var o = {}, ks = Object.keys(v).filter(function (k) { return !LAYOUT_KEYS[k]; });
  ks.forEach(function (k) { o[k] = v[k]; });
  // A participant given as {name: X, tone: ...} is the same participant as the string X.
  return ks.length === 1 && ks[0] === 'name' && typeof o.name === 'string' ? o.name : o;
}

function canon(v) {
  if (Array.isArray(v)) return '[' + v.map(canon).join(',') + ']';
  if (v && typeof v === 'object') return '{' + Object.keys(v).sort().map(function (k) { return JSON.stringify(k) + ':' + canon(v[k]); }).join(',') + '}';
  return JSON.stringify(v === undefined ? null : v);
}

var PROSE_SECTIONS = /^##\s+(Cross-cutting concepts|Risks and technical debt)\s*$/i;

// Split prose on "## " headings: named sections (or every heading when all) go to model.sections,
// the rest returns as the diagram note.
function takeSections(text, model, all) {
  return text.split(/^(?=## )/m).filter(function (seg) {
    var hm = /^##\s+(.+)$/m.exec(seg);
    if (!/^## /.test(seg) || !(all || PROSE_SECTIONS.test(seg.split('\n')[0]))) return !all;
    model.sections.push({ title: hm[1].trim(), body: seg.slice(seg.indexOf('\n') + 1).trim() });
    return false;
  }).join('');
}

function parseModel(md, load) {
  var model = { title: '', intro: '', rev: '', decided: [], diagrams: [], sections: [], errors: [] };
  // Optional front matter: rev (review round letter) and decided (decisions so far), drawn on the cover.
  var fm = /^---[ \t]*\n([\s\S]*?)\n---[ \t]*\n/.exec(md);
  if (fm) {
    md = md.slice(fm[0].length);
    try {
      var top = load(fm[1]) || {};
      if (top.rev != null) model.rev = String(top.rev);
      if (top.decided != null) model.decided = (Array.isArray(top.decided) ? top.decided : [top.decided]).map(String);
    } catch (e) { model.errors.push('front matter: YAML: ' + e.message); }
  }
  var h = /^#\s+(.+)$/m.exec(md), last = 0;
  if (h) {
    model.title = h[1].trim();
    // The prose between the title and the first heading or block is the cover's intro, not a diagram note.
    var rest = md.slice(h.index + h[0].length), stop = rest.search(/^(## |```uml)/m);
    if (stop < 0) stop = rest.length;
    model.intro = rest.slice(0, stop).trim();
    last = h.index + h[0].length + stop;
  }
  var re = /^```uml[^\n]*\n([\s\S]*?)^```[ \t]*$/gm, m, n = 0, seen = {};
  while ((m = re.exec(md))) {
    n++;
    var note = takeSections(md.slice(last, m.index), model, false);
    last = re.lastIndex;
    var spec;
    try { spec = load(m[1]); } catch (e) { model.errors.push('block ' + n + ': YAML: ' + e.message); continue; }
    if (!spec || typeof spec !== 'object') { model.errors.push('block ' + n + ': not a YAML mapping'); continue; }
    if (!spec.id) { model.errors.push('block ' + n + ': missing id'); continue; }
    if (UML_TYPES.indexOf(spec.type) < 0) { model.errors.push(spec.id + ': unknown type ' + spec.type); continue; }
    if (seen[spec.id]) { model.errors.push(spec.id + ': duplicate id'); continue; }
    seen[spec.id] = 1;
    model.diagrams.push({ id: spec.id, type: spec.type, title: spec.title || spec.id, level: spec.level || '', note: note, review: [].concat(spec.review || []).map(String), caption: spec.caption ? String(spec.caption) : "", spec: spec });
  }
  takeSections(md.slice(last), model, true);
  return model;
}

// Merge two lists by identity. Current order wins; a removed item sits after
// its nearest surviving predecessor from the base list.
function mergeList(baseArr, curArr, keyFn, norm) {
  norm = norm || bare;
  baseArr = baseArr || []; curArr = curArr || [];
  var bk = baseArr.map(keyFn), ck = curArr.map(keyFn), bmap = {}, cset = {};
  bk.forEach(function (k, i) { bmap[k] = baseArr[i]; });
  ck.forEach(function (k) { cset[k] = 1; });
  var out = curArr.map(function (el, i) {
    var k = ck[i], b = bmap[k];
    return { key: k, el: el, base: b, st: b === undefined ? 'new' : (canon(norm(b)) === canon(norm(el)) ? '' : 'changed') };
  });
  bk.forEach(function (k, i) {
    if (cset[k]) return;
    var at = 0;
    for (var j = i - 1; j >= 0; j--) {
      var p = out.findIndex(function (o) { return o.key === bk[j]; });
      if (p >= 0) { at = p + 1; break; }
    }
    out.splice(at, 0, { key: k, el: baseArr[i], base: baseArr[i], st: 'removed' });
  });
  return out;
}

function rowDetail(kind, item) {
  var specs = UML_ROWS[kind];
  if (!specs || item.st !== 'changed') return [];
  var d = [];
  specs.forEach(function (s) {
    var rows = mergeList(item.base[s[0]], item.el[s[0]], rowName);
    rows.filter(function (r) { return r.st === 'removed'; }).forEach(function (r) { d.push('-' + s[1] + ' ' + r.key); });
    rows.filter(function (r) { return r.st === 'new'; }).forEach(function (r) { d.push('+' + s[1] + ' ' + r.key); });
    rows.filter(function (r) { return r.st === 'changed'; }).forEach(function (r) { d.push('~' + s[1] + ' ' + r.key); });
  });
  Object.keys(Object.assign({}, item.base, item.el)).forEach(function (f) {
    if (LAYOUT_KEYS[f] || specs.some(function (s) { return s[0] === f; })) return;
    if (canon(item.base[f]) !== canon(item.el[f])) d.push('~' + f);
  });
  return d;
}

function fieldDetail(item) {
  if (item.st !== 'changed') return [];
  return Object.keys(Object.assign({}, item.base, item.el)).filter(function (f) {
    return !LAYOUT_KEYS[f] && canon(item.base[f]) !== canon(item.el[f]);
  }).map(function (f) { return '~' + f; });
}

// One diagram's collections merged against its base version (null = all new).
function mergeDiagram(baseD, curD, noBase) {
  var spec = (curD || baseD).spec, merged = {};
  UML_COLL[spec.type].forEach(function (c) {
    var b = baseD ? baseD.spec[c[0]] : [], cur = curD ? curD.spec[c[0]] : [];
    if (noBase) b = cur;
    var keyFn = function (e, i) { return c[2](e, i); };
    var items = c[0] === 'messages' ? mergeMessages(b, cur, keyFn) : mergeList(b, cur, keyFn);
    if (!curD) items.forEach(function (it) { it.st = 'removed'; });
    items.forEach(function (it) {
      it.kind = c[1];
      it.detail = UML_ROWS[c[1]] ? rowDetail(c[1], it) : fieldDetail(it);
      var rs = UML_ROWS[c[1]];
      if (rs) {
        it.rows = {};
        rs.forEach(function (s) {
          it.rows[s[0]] = it.st === 'changed' ? mergeList(it.base[s[0]], it.el[s[0]], rowName)
            : (it.el[s[0]] || []).map(function (r) { return { key: rowName(r), el: r, st: '' }; });
        });
      }
    });
    merged[c[0]] = items;
  });
  return merged;
}

// A message is keyed by from|to|text plus an occurrence counter, so an insert
// does not re-key the messages after it. A repeat of the same triple gets #2, #3.
function mergeMessages(b, cur, keyFn) {
  var keyed = function (arr) {
    var seen = {};
    return (arr || []).map(function (e) {
      var k = keyFn(e), n = seen[k] = (seen[k] || 0) + 1;
      return { k: n > 1 ? k + ' #' + n : k, e: e };
    });
  };
  var out = mergeList(keyed(b), keyed(cur), function (x) { return x.k; }, function (x) { return { k: x.k, e: bare(x.e) }; });
  out.forEach(function (o) { o.el = o.el.e; o.base = o.base && o.base.e; });
  return out;
}

function diffModels(base, cur) {
  var list = [], sheets = [], bmap = {}, cset = {};
  (base ? base.diagrams : []).forEach(function (d) { bmap[d.id] = d; });
  cur.diagrams.forEach(function (d) { cset[d.id] = 1; });
  cur.diagrams.forEach(function (d) {
    var b = bmap[d.id];
    if (base && !b) {
      sheets.push({ d: d, st: 'new', merged: mergeDiagram(null, d) });
      list.push({ diagram: d.id, title: d.title, st: 'new', kind: 'diagram', key: d.type, detail: [] });
      return;
    }
    var merged = mergeDiagram(b, d, !base), st = '';
    if (b && (b.type !== d.type || b.title !== d.title || b.level !== d.level)) {
      st = 'changed';
      list.push({ diagram: d.id, title: d.title, st: 'changed', kind: 'diagram', key: d.type, detail: ['~title/level/type'] });
    }
    UML_COLL[d.type].forEach(function (c) {
      merged[c[0]].forEach(function (it) {
        if (!it.st) return;
        st = 'changed';
        list.push({ diagram: d.id, title: d.title, st: it.st, kind: it.kind, key: it.key, name: it.el && typeof it.el === 'object' ? it.el.name : undefined, detail: it.detail });
      });
    });
    sheets.push({ d: d, st: st, merged: merged });
  });
  (base ? base.diagrams : []).forEach(function (b) {
    if (cset[b.id]) return;
    sheets.push({ d: b, st: 'removed', merged: mergeDiagram(b, null) });
    list.push({ diagram: b.id, title: b.title, st: 'removed', kind: 'diagram', key: b.type, detail: [] });
  });
  return { list: list, sheets: sheets };
}

function deltaLines(delta) {
  return delta.list.map(function (x) {
    return x.st + ' ' + x.diagram + ' ' + x.kind + ' ' + x.key + (x.detail.length ? ': ' + x.detail.join(', ') : '');
  });
}

if (typeof module !== 'undefined') module.exports = { parseModel: parseModel, diffModels: diffModels, deltaLines: deltaLines, mergeList: mergeList };
