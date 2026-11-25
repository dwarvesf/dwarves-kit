// Shared plumbing for the hook bridges: run a real hook with generated Claude Code hook JSON, in a sandbox.
// Every run gets a temp HOME (so ~/.claude, ~/.config, ~/.cache and ~/.local/state are throwaway), a temp ledger and
// log dir, and CLAUDE_PLUGIN_ROOT at this checkout (so a hook finds lib/gate/gate-policy.sh the way an install does).
// Nothing here touches the real repo's files or the user's ~/.claude.
import {spawnSync} from 'node:child_process'
import {mkdtempSync, mkdirSync, writeFileSync, rmSync, symlinkSync} from 'node:fs'
import {tmpdir} from 'node:os'
import {dirname, join, resolve} from 'node:path'
import {fileURLToPath} from 'node:url'

export const KIT = resolve(dirname(fileURLToPath(import.meta.url)), '../../..')
export const HOOKS = join(KIT, 'hooks')

const made: string[] = []
export function tmp(prefix = 'kit-bridge'): string {
  const d = mkdtempSync(join(tmpdir(), `${prefix}-`))
  made.push(d)
  return d
}
export function cleanup() {
  for (const d of made.splice(0)) rmSync(d, {recursive: true, force: true})
}

export type Run = {code: number, stdout: string, stderr: string}

// A fresh sandbox: HOME, XDG dirs, ledger and log roots all under one temp dir.
export function sandbox(): {home: string, env: Record<string, string>} {
  const home = tmp('kit-home')
  for (const d of ['.config', '.cache', '.local/state', 'ledger', 'logs']) mkdirSync(join(home, d), {recursive: true})
  const env: Record<string, string> = {
    PATH: process.env.PATH ?? '/usr/bin:/bin',
    HOME: home,
    XDG_CONFIG_HOME: join(home, '.config'),
    XDG_CACHE_HOME: join(home, '.cache'),
    XDG_STATE_HOME: join(home, '.local/state'),
    KIT_LEDGER_DIR: join(home, 'ledger'),
    DWARVES_KIT_LOG_DIR: join(home, 'logs'),
    CLAUDE_PLUGIN_ROOT: KIT,
    TMPDIR: home,
    LANG: 'en_US.UTF-8',
  }
  return {home, env}
}

// Run hooks/<hook> under bash with `payload` on stdin (a string is sent as is, anything else as JSON).
export function runHook(hook: string, payload: unknown, opts: {env?: Record<string, string>, cwd?: string, args?: string[], timeoutMs?: number} = {}): Run {
  const input = typeof payload === 'string' ? payload : JSON.stringify(payload)
  const env = opts.env ?? sandbox().env
  const r = spawnSync('bash', [join(process.env.BRIDGE_HOOKS_DIR ?? HOOKS, hook), ...(opts.args ?? [])], {
    input, env, cwd: opts.cwd ?? env.HOME, encoding: 'utf8', timeout: opts.timeoutMs ?? 20000,
  })
  return {code: r.status ?? (r.signal ? 128 : -1), stdout: r.stdout ?? '', stderr: r.stderr ?? ''}
}

export function sh(cmd: string, cwd: string, env?: Record<string, string>): string {
  const r = spawnSync('bash', ['-c', cmd], {cwd, encoding: 'utf8', env: env ?? {...process.env, GIT_CONFIG_GLOBAL: '/dev/null', GIT_CONFIG_NOSYSTEM: '1'}})
  if (r.status !== 0) throw new Error(`sh failed (${r.status}): ${cmd}\n${r.stderr}`)
  return r.stdout
}

// A temp git repo with these files committed (and `extra` left uncommitted in the work tree).
export function gitRepo(files: Record<string, string>, extra: Record<string, string> = {}, branch = 'main'): string {
  const d = tmp('kit-repo')
  const g = (c: string) => sh(c, d)
  g(`git init -q -b ${branch} . && git config user.email t@t && git config user.name t && git config commit.gpgsign false`)
  for (const [p, c] of Object.entries(files)) { mkdirSync(dirname(join(d, p)), {recursive: true}); writeFileSync(join(d, p), c) }
  g('git add -A && git commit -q --allow-empty -m "chore: seed"')
  for (const [p, c] of Object.entries(extra)) { mkdirSync(dirname(join(d, p)), {recursive: true}); writeFileSync(join(d, p), c) }
  return d
}

export function write(dir: string, files: Record<string, string>) {
  for (const [p, c] of Object.entries(files)) { mkdirSync(dirname(join(dir, p)), {recursive: true}); writeFileSync(join(dir, p), c) }
}
export {symlinkSync, join}

// A seeded generator (mulberry32), so a divergence found by a random input replays exactly.
export function rng(seed: number) {
  let a = seed >>> 0
  const next = () => {
    a = (a + 0x6D2B79F5) >>> 0
    let t = a
    t = Math.imul(t ^ (t >>> 15), t | 1)
    t ^= t + Math.imul(t ^ (t >>> 7), t | 61)
    return ((t ^ (t >>> 14)) >>> 0) / 4294967296
  }
  return {
    next,
    int: (n: number) => Math.floor(next() * n),
    bool: () => next() < 0.5,
    pick: <T>(xs: readonly T[]): T => xs[Math.floor(next() * xs.length)],
  }
}

export type BridgeResult = {agree: number, diverge: null | Record<string, unknown>, disagree?: number, more?: Record<string, unknown>[], notes?: string[]}

// Tally one comparison: the first disagreement is kept with its exact input.
export class Tally {
  agree = 0
  diverge: null | Record<string, unknown> = null
  disagree = 0
  more: Record<string, unknown>[] = []
  notes: string[] = []
  check(ok: boolean, detail: () => Record<string, unknown>) {
    if (ok) { this.agree++; return }
    this.disagree++
    if (!this.diverge) this.diverge = detail()
    else if (this.more.length < 80) this.more.push(detail())
  }
  note(s: string) { if (!this.notes.includes(s)) this.notes.push(s) }
  result(): BridgeResult { cleanup(); return {agree: this.agree, diverge: this.diverge, disagree: this.disagree, more: this.more, notes: this.notes} }
}

// Step a proven rule's compiled machine, the way production would, and read its state back.
export function machine(r: any, params: Record<string, unknown> = {}) {
  const c = r.compiled()
  const p = r.encodeParams(params)
  let st = c.init(p)
  return {
    step(input: Record<string, unknown>) { st = c.step(p, st, r.encodeInput(input)); return r.decode(st) },
    get state() { return r.decode(st) },
  }
}

// A PATH holding every command of the current PATH except those named (e.g. python3), as symlinks in a temp dir.
import {readdirSync, existsSync as _exists} from 'node:fs'
export function pathWithout(...names: string[]): string {
  const bin = tmp('kit-bin')
  for (const dir of (process.env.PATH ?? '').split(':')) {
    if (!dir || !_exists(dir)) continue
    let entries: string[] = []
    try { entries = readdirSync(dir) } catch { continue }
    for (const e of entries) {
      if (names.some((n) => e === n || e.startsWith(`${n}.`) || e.startsWith(n))) continue
      if (_exists(join(bin, e))) continue
      try { symlinkSync(join(dir, e), join(bin, e)) } catch { /* first wins */ }
    }
  }
  return bin
}

// A bin dir of stub commands (name -> bash body), to put first on PATH.
import {chmodSync as _chmod} from 'node:fs'
export function stubs(bodies: Record<string, string>): string {
  const bin = tmp('kit-stubs')
  for (const [name, body] of Object.entries(bodies)) {
    writeFileSync(join(bin, name), `#!/bin/bash\n${body}\n`)
    _chmod(join(bin, name), 0o755)
  }
  return bin
}
