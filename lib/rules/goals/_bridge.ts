// Shared plumbing for the goals-area bridges: run the real bash in throwaway directories, seeded randomness, and a
// uniform result shape ({agree, diverge}). Nothing here touches the repo's own state: every bridge points the
// scripts' store overrides (ATTEMPT_REGISTRY_DIR, GOAL_REGISTRY_DIR, KIT_LEDGER_DIR, ...) at a fresh temp dir, and
// stubs `claude`, `gh`, `tmux` and the network through the scripts' own mock seams.
import {execFileSync, spawnSync} from 'node:child_process'
import {mkdtempSync, rmSync, writeFileSync, chmodSync, mkdirSync} from 'node:fs'
import {tmpdir} from 'node:os'
import {join, resolve, dirname} from 'node:path'
import {fileURLToPath} from 'node:url'

export const KIT = resolve(dirname(fileURLToPath(import.meta.url)), '../../..')
export const lib = (p: string) => join(KIT, 'lib', p)

export type BridgeResult = {agree: number, diverge: null | Record<string, unknown>}

export function tmp(prefix = 'goals-bridge-'): string {
  return mkdtempSync(join(process.env.TMPDIR || tmpdir(), prefix))
}
export function cleanup(dir: string) { rmSync(dir, {recursive: true, force: true}) }

export function sh(cmd: string, args: string[], opts: {env?: Record<string, string>, cwd?: string, input?: string} = {}) {
  const r = spawnSync(cmd, args, {
    cwd: opts.cwd, input: opts.input, encoding: 'utf8',
    env: {...process.env, ...opts.env}, maxBuffer: 16 << 20,
  })
  return {code: r.status ?? -1, out: r.stdout ?? '', err: r.stderr ?? ''}
}

export function git(dir: string, ...args: string[]) {
  return execFileSync('git', ['-C', dir, ...args], {encoding: 'utf8', env: {...process.env, GIT_AUTHOR_NAME: 'b', GIT_AUTHOR_EMAIL: 'b@x', GIT_COMMITTER_NAME: 'b', GIT_COMMITTER_EMAIL: 'b@x'}}).trim()
}

export function initRepo(dir: string) {
  mkdirSync(dir, {recursive: true})
  git(dir, 'init', '-q', '-b', 'master')
  writeFileSync(join(dir, 'README.md'), 'x\n')
  git(dir, 'add', '-A'); git(dir, 'commit', '-q', '-m', 'init')
}

export function stub(dir: string, name: string, body: string): string {
  const p = join(dir, name)
  writeFileSync(p, `#!/usr/bin/env bash\n${body}\n`)
  chmodSync(p, 0o755)
  return p
}

// mulberry32: a small seeded generator, so a divergence comes with a seed that reproduces it.
export function rng(seed: number) {
  let a = seed >>> 0
  const next = () => {
    a |= 0; a = (a + 0x6D2B79F5) | 0
    let t = Math.imul(a ^ (a >>> 15), 1 | a)
    t = (t + Math.imul(t ^ (t >>> 7), 61 | t)) ^ t
    return ((t ^ (t >>> 14)) >>> 0) / 4294967296
  }
  return {next, int: (n: number) => Math.floor(next() * n), pick: <T>(xs: readonly T[]) => xs[Math.floor(next() * xs.length)]}
}

// Every tuple of the domains (a small cartesian product), for exhaustive bridges.
export function product<T extends Record<string, readonly unknown[]>>(doms: T): {[k in keyof T]: T[k][number]}[] {
  let out: Record<string, unknown>[] = [{}]
  for (const [k, vs] of Object.entries(doms)) out = out.flatMap(o => vs.map(v => ({...o, [k]: v})))
  return out as never
}

export function report(name: string, r: BridgeResult) {
  if (r.diverge) console.log(`DIVERGE  ${name}: ${r.agree} agreed before ${JSON.stringify(r.diverge)}`)
  else console.log(`agree   ${name}: ${r.agree} cases`)
}

// A map cell of an interpreter state: the raw value (a natural; a choice's index, a yes/no as 0/1), else the default.
export function cell(st: any, map: string, k: number): number {
  const m = st.maps?.[map]
  const v = m instanceof Map ? m.get(k) : m?.[k]
  return v ?? st.defaults?.[map] ?? 0
}
