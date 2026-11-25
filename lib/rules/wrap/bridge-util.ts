// Shared plumbing for the wrap-area bridges: run real bash in a scratch dir with a scrubbed environment, a seeded
// random source, and a small agreement tally. Nothing here touches the real repo's state, ~/.claude or the network:
// every bridge points HOME, the kit config layers and the ledger at a temp dir, and puts stubs first on PATH.
import {spawnSync} from 'node:child_process'
import {mkdirSync, mkdtempSync, rmSync, writeFileSync, chmodSync} from 'node:fs'
import {tmpdir} from 'node:os'
import {dirname, join, resolve} from 'node:path'
import {fileURLToPath} from 'node:url'

export const KIT = resolve(dirname(fileURLToPath(import.meta.url)), '../../..')

export type Divergence = null | Record<string, unknown>
export type BridgeResult = {agree: number, diverge: Divergence, notes?: string[]}

// A temp dir with HOME, config layers, a stub bin dir, all scoped to it.
export function sandbox(tag: string) {
  const dir = mkdtempSync(join(process.env.TMPDIR || tmpdir(), `dk-${tag}-`))
  const bin = join(dir, 'bin'), home = join(dir, 'home')
  mkdirSync(bin, {recursive: true}); mkdirSync(home, {recursive: true})
  // A no-op sleep, so retry and poll loops run at once.
  stub(bin, 'sleep', 'exit 0')
  const env: Record<string, string> = {
    PATH: `${bin}:/usr/bin:/bin:/usr/sbin:/sbin:/opt/homebrew/bin:/usr/local/bin`,
    HOME: home, TMPDIR: dir, LC_ALL: 'C',
    KIT_CONFIG_OPERATOR: join(dir, 'no-operator'), KIT_CONFIG_ROOT: join(dir, 'no-root'),
    KIT_PROJECT_ROOT: join(dir, 'no-project'), KIT_LEDGER_DIR: join(dir, 'ledger'),
    XDG_CONFIG_HOME: join(home, '.config'), GIT_CONFIG_NOSYSTEM: '1', GIT_TERMINAL_PROMPT: '0',
    GIT_AUTHOR_NAME: 't', GIT_AUTHOR_EMAIL: 't@t', GIT_COMMITTER_NAME: 't', GIT_COMMITTER_EMAIL: 't@t',
  }
  return {dir, bin, home, env, cleanup: () => rmSync(dir, {recursive: true, force: true})}
}

export function stub(bin: string, name: string, body: string) {
  const p = join(bin, name)
  writeFileSync(p, `#!/usr/bin/env bash\n${body}\n`)
  chmodSync(p, 0o755)
  return p
}

// The script goes through a file, not `bash -c`: Linux caps one argument at 128 KiB (MAX_ARG_STRLEN), and the
// larger bridges write more than that.
let scriptN = 0
export function bash(script: string, env: Record<string, string>, cwd?: string, timeoutMs = 60_000) {
  const dir = mkdtempSync(join(process.env.TMPDIR || tmpdir(), 'dk-script-'))
  const file = join(dir, `s${scriptN++}.sh`)
  writeFileSync(file, script)
  try {
    const r = spawnSync('bash', [file], {env, cwd: cwd ?? KIT, encoding: 'utf8', timeout: timeoutMs, maxBuffer: 64 << 20})
    return {stdout: r.stdout ?? '', stderr: r.stderr ?? '', status: r.status ?? -1}
  } finally { rmSync(dir, {recursive: true, force: true}) }
}

// mulberry32: a seeded random source, so a divergence can be replayed from its seed.
export function rng(seed: number) {
  let a = seed >>> 0
  const next = () => {
    a = (a + 0x6D2B79F5) >>> 0
    let t = a
    t = Math.imul(t ^ (t >>> 15), t | 1)
    t ^= t + Math.imul(t ^ (t >>> 7), t | 61)
    return ((t ^ (t >>> 14)) >>> 0) / 4294967296
  }
  return {next, int: (n: number) => Math.floor(next() * n), pick: <T>(xs: readonly T[]) => xs[Math.floor(next() * xs.length)]}
}

// Every sequence over `alphabet` of length 1..n.
export function sequences<T>(alphabet: readonly T[], n: number): T[][] {
  const out: T[][] = []
  let layer: T[][] = [[]]
  for (let i = 0; i < n; i++) {
    layer = layer.flatMap((s) => alphabet.map((a) => [...s, a]))
    out.push(...layer)
  }
  return out
}

export function cartesian<T extends Record<string, readonly unknown[]>>(dom: T): {[k in keyof T]: T[k][number]}[] {
  let rows: Record<string, unknown>[] = [{}]
  for (const [k, vs] of Object.entries(dom)) rows = rows.flatMap((r) => vs.map((v) => ({...r, [k]: v})))
  return rows as {[k in keyof T]: T[k][number]}[]
}

export function same(a: unknown, b: unknown) { return JSON.stringify(a) === JSON.stringify(b) }

export const q = (s: string) => `'${s.replace(/'/g, `'\\''`)}'`
