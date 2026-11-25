// Shared bridge plumbing for the gates area: a throwaway ledger root and HOME per bridge, a bash runner,
// a seeded random source, and the verdict reporters prove.ts uses. Nothing here touches the real repo state:
// every call runs with KIT_LEDGER_DIR, HOME and XDG_CONFIG_HOME pointing into a fresh temp dir.
import {spawnSync} from 'node:child_process'
import {mkdtempSync, mkdirSync, rmSync, writeFileSync} from 'node:fs'
import {tmpdir} from 'node:os'
import {dirname, join, resolve} from 'node:path'
import {fileURLToPath} from 'node:url'

// BRIDGE_KIT points the bridges at another copy of the kit (an archive of HEAD before a fix, for the before/after
// results); unset, the bridges run this checkout's bash.
export const KIT = process.env.BRIDGE_KIT ?? resolve(dirname(fileURLToPath(import.meta.url)), '../../..')
export const GATE = join(KIT, 'lib/gate')

export type Sandbox = {dir: string, env: NodeJS.ProcessEnv, done: () => void}

// A fresh sandbox: ledger root, HOME, operator config dir and a scratch cwd, all under one temp dir.
export function sandbox(): Sandbox {
  const dir = mkdtempSync(join(tmpdir(), 'gates-bridge-'))
  for (const d of ['ledger', 'home', 'xdg', 'cwd']) mkdirSync(join(dir, d), {recursive: true})
  const env: NodeJS.ProcessEnv = {
    PATH: process.env.PATH, TMPDIR: process.env.TMPDIR ?? '/tmp', LANG: 'C', LC_ALL: 'C',
    HOME: join(dir, 'home'), XDG_CONFIG_HOME: join(dir, 'xdg'), XDG_STATE_HOME: join(dir, 'home/.state'),
    KIT_LEDGER_DIR: join(dir, 'ledger'), KIT_CONFIG_OPERATOR: join(dir, 'xdg/dwarves-kit'),
    DWARVES_KIT_LANES_D: join(dir, 'xdg/lanes.d'), GIT_CONFIG_NOSYSTEM: '1',
    GIT_AUTHOR_NAME: 'Bridge Bot', GIT_AUTHOR_EMAIL: 'bridge@dwarves.foundation',
    GIT_COMMITTER_NAME: 'Bridge Bot', GIT_COMMITTER_EMAIL: 'bridge@dwarves.foundation',
  }
  return {dir, env, done: () => rmSync(dir, {recursive: true, force: true})}
}

export type Run = {code: number, out: string, err: string}

export function bash(sb: Sandbox, args: string[], opts: {cwd?: string, input?: string, env?: NodeJS.ProcessEnv} = {}): Run {
  const r = spawnSync('bash', args, {cwd: opts.cwd ?? join(sb.dir, 'cwd'), env: {...sb.env, ...(opts.env ?? {})},
    input: opts.input ?? '', encoding: 'utf8', timeout: 60_000})
  return {code: r.status ?? -1, out: r.stdout ?? '', err: r.stderr ?? ''}
}

export function sh(sb: Sandbox, script: string, cwd?: string, env?: NodeJS.ProcessEnv): Run {
  return bash(sb, ['-c', script], {cwd, env})
}

// A git repo with one commit on main, and an origin (a bare clone) whose HEAD names main.
export function gitRepo(sb: Sandbox, name = 'repo'): string {
  const root = join(sb.dir, name)
  const bare = join(sb.dir, `${name}.git`)
  const r = sh(sb, [
    `git init -q -b main ${q(root)}`, `cd ${q(root)}`, 'git config commit.gpgsign false',
    'echo seed > README.md', 'git add -A', 'git commit -q -m init',
    `git clone -q --bare ${q(root)} ${q(bare)}`, `git remote add origin ${q(bare)}`, 'git fetch -q origin',
    'git remote set-head origin main >/dev/null 2>&1 || true',
  ].join(' && '))
  if (r.code !== 0) throw new Error(`gitRepo: ${r.err}`)
  return root
}

export function write(path: string, text: string) { mkdirSync(dirname(path), {recursive: true}); writeFileSync(path, text) }

export const q = (s: string) => `'${s.replace(/'/g, `'\\''`)}'`

// mulberry32: a small seeded generator, so a divergence names a seed that reproduces it.
export function rng(seed: number) {
  let a = seed >>> 0
  const next = () => { a = (a + 0x6D2B79F5) >>> 0; let t = a; t = Math.imul(t ^ (t >>> 15), t | 1); t ^= t + Math.imul(t ^ (t >>> 7), t | 61); return ((t ^ (t >>> 14)) >>> 0) / 4294967296 }
  return {next, int: (n: number) => Math.floor(next() * n), pick: <T>(xs: readonly T[]): T => xs[Math.floor(next() * xs.length)]}
}

// Every combination of the given finite domains, in order.
export function* product<T extends Record<string, readonly unknown[]>>(doms: T): Generator<{[k in keyof T]: T[k][number]}> {
  const keys = Object.keys(doms) as (keyof T)[]
  const idx = keys.map(() => 0)
  if (keys.some(k => doms[k].length === 0)) return
  while (true) {
    yield Object.fromEntries(keys.map((k, i) => [k, doms[k][idx[i]]])) as {[k in keyof T]: T[k][number]}
    let i = keys.length - 1
    while (i >= 0 && ++idx[i] === doms[keys[i]].length) { idx[i] = 0; i-- }
    if (i < 0) return
  }
}

export type BridgeResult = {agree: number, diverge: null | Record<string, unknown>}
