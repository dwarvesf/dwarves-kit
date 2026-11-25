// Shared helpers for the specs-area rules and their bridges: a choice built from a numeric term, a seeded
// random source, and a runner for the real bash in temp dirs (never the repo's own state).
import {Choice, type Cond} from 'gdp-wired'
import {spawnSync} from 'node:child_process'
import {mkdtempSync, readFileSync, rmSync} from 'node:fs'
import {tmpdir} from 'node:os'
import {dirname, join, resolve} from 'node:path'
import {fileURLToPath} from 'node:url'

/** The kit root (lib/rules/specs/../../..). */
export const KIT = resolve(dirname(fileURLToPath(import.meta.url)), '../../..')

/** A choice of `values` whose index is the term `t` (a `when` chain of constants). */
export const pick = <const K extends string>(values: readonly K[], t: unknown) => new Choice<K>(t as never, values)

/** a <-> b for two conditions. */
export const iff = (a: Cond, b: Cond) => a.implies(b).and(b.implies(a))

/** A seeded PRNG (mulberry32): rand(n) is an integer in [0, n). */
export function seeded(seed: number) {
  let s = seed >>> 0
  const next = () => {
    s = (s + 0x6d2b79f5) >>> 0
    let t = s
    t = Math.imul(t ^ (t >>> 15), t | 1)
    t ^= t + Math.imul(t ^ (t >>> 7), t | 61)
    return ((t ^ (t >>> 14)) >>> 0) / 4294967296
  }
  return (n: number) => Math.floor(next() * n)
}

export type Ran = {code: number, out: string, err: string}

/** Run a command (argv) with a clean-ish env; the env given is merged over PATH/HOME. */
export function run(argv: string[], opts: {cwd?: string, env?: Record<string, string>, input?: string} = {}): Ran {
  const r = spawnSync(argv[0], argv.slice(1), {
    cwd: opts.cwd, input: opts.input, encoding: 'utf8',
    env: {PATH: process.env.PATH ?? '/usr/bin:/bin', HOME: opts.env?.HOME ?? process.env.HOME ?? '/tmp', LC_ALL: 'C', ...opts.env},
  })
  return {code: r.status ?? -1, out: r.stdout ?? '', err: r.stderr ?? ''}
}

/** A fresh temp dir, removed by the returned cleanup. */
export function tmp(tag: string) {
  const d = mkdtempSync(join(tmpdir(), `kit-rules-${tag}-`))
  return {dir: d, done: () => rmSync(d, {recursive: true, force: true})}
}

export type BridgeResult = {agree: number, diverge: null | Record<string, unknown>}

/** lib/board/states.tsv, the board's one declaration: [state, class] rows in file order (never a copy here). */
export const BOARD_MACHINE: [string, string][] = readFileSync(resolve(KIT, 'lib/board/states.tsv'), 'utf8').split('\n')
  .filter(l => l && !l.startsWith('#')).map(l => l.split('\t')).filter(c => c.length >= 2).map(c => [c[0], c[1]])
