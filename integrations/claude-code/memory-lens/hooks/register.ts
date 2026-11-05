/**
 * Hook registration for memory-lens.
 *
 * Events:
 * - session.start: find this project's memory folder (a worktree maps to its
 *   parent repo), then build the index in the background so the session is
 *   never held up. Also reads two optional local files: a client list and a
 *   mirror file of remote titles written by a private job outside this mod.
 * - prompt.submit: the top 3 memories above the score floor go to the model as
 *   one context entry and to the human as one transcript line. The 2.1.283
 *   prompt.submit contract: an answer carries { text } and an optional
 *   context that is a list of non-empty strings (binary checkArgument).
 * - tool.call (Read, Edit, Write, Grep, Glob): the path is a new query; at
 *   most one memory not yet recalled this session is added as tool context.
 *   A Write or Edit under the memory folder re-indexes that file.
 * - command.run{command=memory-lens}: stats, reload, show <n>.
 *
 * Negative pins: no process.run, no http.fetch, no store. Nothing on the hot
 * path touches the network; every file read happens at session start or after
 * a memory write. Hooks module format: exports register(on, options).
 */

import { contextText, percentiles, screenLines } from '../src/format.js';
import {
  MAX_DOCS,
  MAX_FILE_BYTES,
  defaultTrustedRoots,
  hasDotDot,
  isIndexFile,
  isTrustedRoot,
  normalizePath,
  parentProjectKey,
  parseMemory,
  parseMirror,
  parseTrustedRoots,
  projectKey,
} from '../src/memory.js';
import { LensIndex } from '../src/rank.js';
import type { Hit, LensPrivate, MemoryDoc } from '../src/types.js';

/** Minimal $ facade for the calls this module makes. */
type Lens$ = {
  env: { get: (name: string) => Promise<string | undefined> };
  fs: {
    exists: (path: string) => Promise<boolean>;
    read: (path: string) => Promise<string>;
    list: (path: string) => Promise<Array<{ name: string; kind: 'file' | 'dir' | 'other'; size?: number }> | null>;
  };
  ui: { log: (text: string, options?: { to?: 'transcript' | 'debug' }) => Promise<void> };
  command: { register: (spec: { name: string; description: string }) => Promise<unknown> };
  clock: { after: (ms: number, fn: () => void) => { cancel?: () => void } };
};

type NextFn<E> = (ev: E) => Promise<unknown>;
type SessionStartEvent = { cwd?: string };
type PromptSubmitEvent = { text?: string; [k: string]: unknown };
type ToolCallEvent = { tool: string; tool_use_id?: string; [argument: string]: unknown };
type CommandEvent = { command?: string; args?: string; text?: string };

/** Tools whose path argument is a useful mid-task query. */
const PATH_TOOLS = new Set(['Read', 'Edit', 'Write', 'Grep', 'Glob']);

// Module-scope state (per session)
let home = '';
// Memory folders, repo store first: it wins a file-name clash with the machine-local one.
let repoMemoryDir = '';
let localMemoryDir = '';
let mirrorPath = '';
let priv: LensPrivate = { clientTerms: [] };
let docs = new Map<string, MemoryDoc>();
let index: LensIndex | null = null;
let building: Promise<void> | null = null;
const recalled = new Set<string>();
const queryMs: number[] = [];
let lastHits: Hit[] = [];

function join(...parts: string[]): string {
  return parts.join('/').replace(/\/+/g, '/');
}

/** Names in ~/.claude/memory-lens, listed first so a missing optional file is not read (and not logged as an error). */
let lensFiles = new Set<string>();

async function readPrivate($: Lens$): Promise<LensPrivate> {
  const entries = (await $.fs.list(join(home, '.claude', 'memory-lens')).catch(() => null)) ?? [];
  lensFiles = new Set(entries.map((x) => x.name));
  if (!lensFiles.has('private.json')) return { clientTerms: [] };
  try {
    const raw = JSON.parse(await $.fs.read(join(home, '.claude', 'memory-lens', 'private.json'))) as { clientTerms?: unknown };
    const terms = Array.isArray(raw.clientTerms) ? raw.clientTerms.filter((t): t is string => typeof t === 'string') : [];
    return { clientTerms: terms };
  } catch {
    return { clientTerms: [] };
  }
}

function memoryDirs(): string[] {
  return [repoMemoryDir, localMemoryDir].filter((d) => d !== '');
}

/** Where a repo's `.claude/memory` may be trusted: the roots file when it exists (even empty), else the defaults. */
async function trustedRoots($: Lens$): Promise<string[]> {
  const file = join(home, '.claude', 'memory-lens', 'trusted-roots');
  try {
    if (!(await $.fs.exists(file))) return defaultTrustedRoots(home.replace(/\/+$/, ''));
    return parseTrustedRoots(await $.fs.read(file), home.replace(/\/+$/, ''));
  } catch {
    return [];
  }
}

/**
 * The per-repo store: the nearest <dir>/.claude/memory from cwd up to the git root (the first dir with a
 * .git file or folder). Its text goes to the model as context, so a cloned repo must not plant it:
 * the lookup refuses unless HOME is set and cwd is under it, never climbs to HOME or above, and takes
 * the store only when the git root sits under a trusted prefix.
 */
async function findRepoMemory($: Lens$, cwd: string): Promise<string> {
  const stop = normalizePath(home);
  const start = normalizePath(cwd);
  if (!stop.startsWith('/') || stop === '/' || !start.startsWith(stop + '/')) return '';
  let dir = start;
  let found = '';
  while (dir.length > stop.length) {
    const candidate = join(dir, '.claude', 'memory');
    if (!found && (await $.fs.exists(candidate).catch(() => false))) found = candidate;
    if (await $.fs.exists(join(dir, '.git')).catch(() => false)) {
      if (!found) return '';
      return isTrustedRoot(dir, await trustedRoots($)) ? found : '';
    }
    dir = dir.slice(0, dir.lastIndexOf('/'));
  }
  return '';
}

async function loadDocs($: Lens$): Promise<Map<string, MemoryDoc>> {
  const out = new Map<string, MemoryDoc>();
  const seen = new Set<string>();
  for (const dir of memoryDirs()) {
    const entries = (await $.fs.list(dir).catch(() => null)) ?? [];
    for (const e of entries) {
      if (out.size >= MAX_DOCS) break;
      if (e.kind !== 'file' || !e.name.endsWith('.md') || isIndexFile(e.name) || seen.has(e.name)) continue;
      if (typeof e.size === 'number' && e.size > MAX_FILE_BYTES) continue;
      const path = join(dir, e.name);
      try {
        const text = await $.fs.read(path);
        if (text.length > MAX_FILE_BYTES) continue;
        out.set(path, parseMemory(path, text));
        seen.add(e.name);
      } catch {
        // unreadable file: skip it, never fail the session
      }
    }
  }
  if (lensFiles.has(mirrorPath.split('/').pop() ?? '')) {
    try {
      for (const d of parseMirror(await $.fs.read(mirrorPath), 'mirror')) out.set(`mirror:${d.id}`, d);
    } catch {
      // unreadable mirror file: local memory only
    }
  }
  return out;
}

async function build($: Lens$): Promise<void> {
  const t0 = Date.now();
  priv = await readPrivate($);
  docs = await loadDocs($);
  index = new LensIndex([...docs.values()]);
  await $.ui.log(`memory-lens: indexed ${index.size} memories in ${Date.now() - t0} ms (${memoryDirs().join(' + ')})`, { to: 'debug' });
}

/** Longest the first prompt waits for the index; later prompts never wait. */
export const FIRST_WAIT_MS = 2000;

/** Await p, or give up after ms using the engine clock (a mod has no ambient timers). */
async function waitFor($: Lens$, p: Promise<void>, ms: number): Promise<void> {
  let timer: { cancel?: () => void } | undefined;
  const expired = new Promise<void>((resolve) => {
    try {
      timer = $.clock.after(ms, () => resolve());
    } catch {
      resolve();
    }
  });
  try {
    await Promise.race([p, expired]);
  } finally {
    timer?.cancel?.();
  }
}

function timedQuery(text: string, k: number): Hit[] {
  if (!index) return [];
  const t0 = Date.now();
  const hits = index.query(text, k, recalled);
  queryMs.push(Date.now() - t0);
  if (queryMs.length > 500) queryMs.shift();
  return hits;
}

function withContext(result: unknown, entry: string): unknown {
  if (!result || typeof result !== 'object') return result;
  const r = result as Record<string, unknown>;
  const prior = Array.isArray(r.context) ? (r.context as unknown[]).filter((c): c is string => typeof c === 'string' && c !== '') : [];
  return { ...r, context: [...prior, entry] };
}

function pathQuery(e: ToolCallEvent): string {
  const raw = String(e.file_path ?? e.path ?? e.pattern ?? '');
  // the last three path segments carry the topic; the home prefix carries none
  return raw.split('/').slice(-3).join(' ').replace(/\.[a-z0-9]+$/i, '');
}

export function register(on: (event: string, matcherOrHook: unknown, hook?: unknown) => void, _options?: unknown): void {
  on('session.start', async ($: Lens$, e: SessionStartEvent, next: NextFn<SessionStartEvent>) => {
    home = (await $.env.get('HOME').catch(() => undefined)) ?? '';
    const key = parentProjectKey(projectKey(e?.cwd ?? ''));
    localMemoryDir = join(home, '.claude', 'projects', key, 'memory');
    repoMemoryDir = await findRepoMemory($, e?.cwd ?? '');
    mirrorPath = join(home, '.claude', 'memory-lens', `mirror-${key}.json`);
    index = null;
    recalled.clear();
    lastHits = [];
    building = build($).catch(() => undefined);
    await $.command.register({ name: 'memory-lens', description: 'Memory lens: stats, reload, show <n>' }).catch(() => undefined);
    return next(e);
  });

  on('prompt.submit', async ($: Lens$, e: PromptSubmitEvent, next: NextFn<PromptSubmitEvent>) => {
    // Query BEFORE next(e) and hand the context down the chain. Measured on
    // 2.1.283 (2026-09-28): the classic UserPromptSubmit hooks run inside
    // next(e) for about 560 ms, and the turn started before an answer built
    // after next(e) settled, so that context never reached the model.
    let ev = e;
    let ctx: string | null = null;
    let hits: Hit[] = [];
    // The first prompt can arrive while the index is still building (headless
    // -p sends it at once): wait for the build, at most FIRST_WAIT_MS.
    if (!index && building) await waitFor($, building, FIRST_WAIT_MS);
    try {
      if (index && typeof e?.text === 'string') {
        hits = timedQuery(e.text, 3);
        ctx = hits.length ? contextText(hits) : null;
        if (ctx) ev = withContext(e, ctx) as PromptSubmitEvent;
      }
    } catch {
      ctx = null;
    }
    const result = (await next(ev)) ?? ev;
    try {
      const r = result as PromptSubmitEvent & { drop?: unknown };
      if (!ctx || typeof r.text !== 'string' || r.drop !== undefined) return result;
      lastHits = hits;
      for (const h of hits) recalled.add(h.doc.id);
      // One call, rows joined on one line: measured in the 2.1.283 TUI, a
      // newline inside a log call renders as a replacement glyph, and a second
      // $.ui.log in the same hook call never drew (the hook settled at once).
      try {
        await $.ui.log(screenLines(hits, priv, home).join('  │  '), { to: 'debug' });
      } catch {
        // no log surface: the context still went to the model
      }
      const has = Array.isArray(r.context) && (r.context as unknown[]).includes(ctx);
      return has ? result : withContext(result, ctx);
    } catch {
      return result;
    }
  });

  on('tool.call', async ($: Lens$, e: ToolCallEvent, next?: NextFn<ToolCallEvent>) => {
    const result = next ? ((await next(e)) ?? {}) : {};
    try {
      if (!PATH_TOOLS.has(e.tool)) return result;
      const raw = String(e.file_path ?? '');
      // a path that climbs with ../ could point out of the folder it starts with
      const path = hasDotDot(raw) ? '' : normalizePath(raw);
      const writtenIn = path ? memoryDirs().find((d) => path.startsWith(d + '/')) : undefined;
      if ((e.tool === 'Write' || e.tool === 'Edit') && writtenIn && path.endsWith('.md')) {
        // a memory was written: re-index that one file so the next prompt can find it
        const name = path.split('/').pop() ?? '';
        if (!isIndexFile(name)) {
          if (writtenIn === repoMemoryDir) docs.delete(join(localMemoryDir, name));
          if (writtenIn === repoMemoryDir || !docs.has(join(repoMemoryDir, name))) {
            const text = await $.fs.read(path);
            if (text.length <= MAX_FILE_BYTES && (docs.has(path) || docs.size < MAX_DOCS)) {
              docs.set(path, parseMemory(path, text));
              index = new LensIndex([...docs.values()]);
            }
          }
        }
        return result;
      }
      if (!index) return result;
      const hits = timedQuery(pathQuery(e), 1);
      const ctx = contextText(hits);
      if (!hits.length || !ctx) return result;
      recalled.add(hits[0].doc.id);
      return withContext(result, ctx);
    } catch {
      return result;
    }
  });

  on('command.run', { command: 'memory-lens' }, async ($: Lens$, e: CommandEvent) => {
    const args = String(e?.args ?? e?.text ?? '').trim().split(/\s+/);
    if (args[0] === 'reload') {
      building = build($).catch(() => undefined);
      await building;
      return { text: `memory-lens: reloaded ${index?.size ?? 0} memories` };
    }
    if (args[0] === 'show') {
      const n = Number(args[1]) - 1;
      const h = lastHits[n];
      if (!h) return { text: `memory-lens: no hit ${args[1] ?? ''} on the last prompt` };
      return { text: `${n + 1}. ${h.doc.name}\n   ${h.doc.desc}\n   ${h.doc.id}` };
    }
    await building;
    const p = percentiles(queryMs);
    return {
      text: `memory-lens: ${index?.size ?? 0} memories from ${memoryDirs().join(' + ') || '(no project)'} · ${recalled.size} recalled this session · query p50 ${p.p50} ms p95 ${p.p95} ms over ${p.n}`,
    };
  });
}
