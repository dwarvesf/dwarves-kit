// Bridge: lib/gate/gate-policy.sh `enabled` (the real script) against gate-policy. Temp git repos hold the project
// .kit.toml as untracked, tracked and clean, tracked and dirty, or committed at a base read with --at HEAD (the
// working copy then says something else). Operator and kit-root files are temp files. Keys: proof_of_done (opt-in),
// board_row_gate (default on), a key the script does not know.
import {mkdirSync, writeFileSync} from 'node:fs'
import {join} from 'node:path'
import {bash, KIT, sandbox, type BridgeResult} from './bridge-util.ts'
import {gatePolicy, PVS} from './gate-policy.ts'

type PV = typeof PVS[number]
const KEYS = [{key: 'proof_of_done', known: true, defaultOn: false}, {key: 'board_row_gate', known: true, defaultOn: true},
  {key: 'not_a_gate', known: false, defaultOn: false}]
const STATES = ['untracked', 'clean', 'dirty', 'at'] as const
const val = (v: PV) => v === 'true' ? 'true' : v === 'false' ? 'false' : 'yes'
const body = (key: string, v: PV) => v === 'absent' ? '[wrap]\ndistill = false\n' : `[gate]\n${key} = ${val(v)}  # set here\n`
const flip = (v: PV): PV => v === 'true' ? 'false' : 'true'

export async function bridge(): Promise<BridgeResult> {
  const f = gatePolicy()
  const sb = sandbox('gate-policy')
  try {
    type Case = {k: typeof KEYS[number], op: PV, root: PV, pv: PV, state: typeof STATES[number], repo: string, cfg: string}
    const cases: Case[] = []
    let setup = ''
    let n = 0
    for (const k of KEYS) for (const pv of PVS) for (const state of STATES) {
      const repo = join(sb.dir, `r${n++}`)
      mkdirSync(repo, {recursive: true})
      const committed = state === 'at' ? pv : state === 'dirty' ? flip(pv) : pv
      const working = state === 'at' ? flip(pv) : pv
      setup += `git -C '${repo}' init -q; git -C '${repo}' commit -q --allow-empty -m base\n`
      if (state === 'untracked') setup += `printf '%s' '${body(k.key, working)}' > '${repo}/.kit.toml'\n`
      else {
        setup += `printf '%s' '${body(k.key, committed)}' > '${repo}/.kit.toml'; git -C '${repo}' add .kit.toml; git -C '${repo}' commit -q -m cfg\n`
        if (state !== 'clean') setup += `printf '%s' '${body(k.key, working)}' > '${repo}/.kit.toml'\n`
      }
      for (const op of PVS) for (const root of ['absent', 'true', 'false'] as PV[]) {
        const cfg = join(repo + '-cfg', `${op}-${root}`)
        mkdirSync(join(cfg, 'o'), {recursive: true}); mkdirSync(join(cfg, 'r'), {recursive: true})
        if (op !== 'absent') writeFileSync(join(cfg, 'o', 'kit.toml'), body(k.key, op))
        if (root !== 'absent') writeFileSync(join(cfg, 'r', 'kit.toml'), body(k.key, root))
        cases.push({k, op, root, pv, state, repo, cfg})
      }
    }
    bash(setup, sb.env, sb.dir, 120_000)
    const out = bash(`while IFS='|' read -r repo cfg key at; do
        KIT_CONFIG_OPERATOR="$cfg/o" KIT_CONFIG_ROOT="$cfg/r" bash '${KIT}/lib/gate/gate-policy.sh' enabled "$key" "$repo" $at 2>/dev/null; echo $?
      done <<'ROWS'
${cases.map((c) => `${c.repo}|${c.cfg}|${c.k.key}|${c.state === 'at' ? '--at HEAD' : ''}`).join('\n')}
ROWS`, sb.env, sb.dir, 300_000)
    const rcs = out.stdout.trim().split('\n')
    let agree = 0
    for (let i = 0; i < cases.length; i++) {
      const c = cases[i]
      const want = f.run({known: c.k.known, opSet: c.op, rootSet: c.root, defaultOn: c.k.defaultOn, pv: c.pv,
        at: c.state === 'at', clean: c.state === 'clean'})
      if ((rcs[i] === '0') !== want.on) {
        return {agree, diverge: {key: c.k.key, operator: c.op, kitRoot: c.root, project: c.pv, projectFile: c.state, bashExit: rcs[i], rule: want}}
      }
      agree++
    }
    return {agree, diverge: null}
  } finally { sb.cleanup() }
}

if (import.meta.url === `file://${process.argv[1]}`) console.log(JSON.stringify(await bridge()))
