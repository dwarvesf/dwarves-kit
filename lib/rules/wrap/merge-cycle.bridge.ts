// Bridge: lib/wrap/wrap-common.sh:_merge_verify_push (the real cycle, sourced through lib/wrap/wrap.sh) on real git
// repos against merge-cycle. Each case is a bare origin whose main moved on past a pushed feature branch, a clone
// with the branch in a worktree, a ship-gate stub (WRAP_LAND_SHIP_GATE) that passes or blocks, and a pre-receive
// hook on origin that accepts or refuses the push. The --verify command is none, `true`, `false`, one that commits
// (moves HEAD) or one that edits a tracked file. Two more cases: the fetch fails (origin gone), and origin/main is
// already in the branch (rc 4). What the rule is fed is what the bash meets, in order; what is compared is the exit
// code and whether origin's branch now holds the merge commit.
import {join} from 'node:path'
import {bash, KIT, sandbox, stub, type BridgeResult} from './bridge-util.ts'
import {mergeCycle, RC} from './merge-cycle.ts'

const CMDS = {none: '', pass: 'true', fail: 'false', move: 'git commit -q --allow-empty -m verify-commit', touch: 'echo touched >> base.txt'} as const
type Cmd = keyof typeof CMDS
type Case = {kind: 'normal' | 'fetchFail' | 'contains', cmd: Cmd, gate: boolean, push: boolean}

function events(c: Case): string[] {
  if (c.kind === 'fetchFail') return ['fetchFail']
  if (c.kind === 'contains') return ['contains']
  const ev = ['fetchOk', 'mergeOk']
  if (c.cmd !== 'none') {
    if (c.cmd !== 'pass') return [...ev, 'verifyFail', c.cmd === 'touch' ? 'undoLeft' : 'undoClean']
    ev.push('verifyPass')
  }
  if (!c.gate) return [...ev, 'gateBlock', 'undoClean']
  ev.push('gatePass')
  return c.push ? [...ev, 'pushOk'] : [...ev, 'pushRefused', 'undoClean']
}

export async function bridge(): Promise<BridgeResult> {
  const sb = sandbox('merge-cycle')
  try {
    const pass = stub(sb.bin, 'gate-pass.sh', 'cat >/dev/null; exit 0')
    const block = stub(sb.bin, 'gate-block.sh', 'cat >/dev/null; echo "BLOCKED: fixture gate" >&2; exit 2')
    const cases: Case[] = [{kind: 'fetchFail', cmd: 'none', gate: true, push: true}, {kind: 'contains', cmd: 'none', gate: true, push: true}]
    for (const cmd of Object.keys(CMDS) as Cmd[]) for (const gate of [true, false]) for (const push of [true, false]) cases.push({kind: 'normal', cmd, gate, push})
    const r = mergeCycle()
    let agree = 0
    for (let i = 0; i < cases.length; i++) {
      const c = cases[i], d = join(sb.dir, `c${i}`)
      const out = bash(`
        set -u
        git init -q -b main '${d}/seed'; cd '${d}/seed'; echo base > base.txt; git add -A; git commit -q -m base
        git clone -q --bare '${d}/seed' '${d}/origin.git'
        git clone -q '${d}/origin.git' '${d}/clone'; cd '${d}/clone'
        git worktree add -q -b feat '${d}/wt' main; cd '${d}/wt'; echo feat > feat.txt; git add -A; git commit -q -m feat
        git push -q origin feat
        ${c.kind === 'contains' ? '' : `cd '${d}/seed'; echo other > other.txt; git add -A; git commit -q -m other; git push -q '${d}/origin.git' main`}
        ${c.push ? '' : `printf '#!/bin/sh\\nwhile read o n r; do [ "$r" = refs/heads/feat ] && { echo refused >&2; exit 1; }; done; exit 0\\n' > '${d}/origin.git/hooks/pre-receive'; chmod +x '${d}/origin.git/hooks/pre-receive'`}
        ${c.kind === 'fetchFail' ? `git -C '${d}/clone' remote set-url origin '${d}/gone.git'` : ''}
        tip="$(git -C '${d}/wt' rev-parse HEAD)"
        export WRAP_LAND_SHIP_GATE='${c.gate ? pass : block}'
        source '${KIT}/lib/wrap/wrap.sh' >/dev/null 2>&1
        _merge_verify_push '${d}/wt' feat main "$tip" "" ${CMDS[c.cmd] ? `'${CMDS[c.cmd]}'` : ''} >'${d}/out' 2>&1 </dev/null; rc=$?
        remote="$(git --git-dir='${d}/origin.git' rev-parse refs/heads/feat)"
        echo "RESULT $rc $([ "$remote" != "$tip" ] && echo 1 || echo 0)"`, sb.env, sb.dir, 120_000)
      const m = /RESULT (\d+) (\d)/.exec(out.stdout)
      const real = {rc: m ? Number(m[1]) : -1, onOrigin: m?.[2] === '1'}
      const it = r.interpreter(), p = r.encodeParams({hasCmd: c.cmd !== 'none'})
      let st = it.init(p)
      for (const ev of events(c)) st = it.step(p, st, r.encodeInput({ev}))
      const dec = r.decode(st) as {phase: string, onOrigin: boolean}
      const want = {rc: RC[dec.phase] ?? -1, onOrigin: dec.onOrigin}
      if (real.rc !== want.rc || real.onOrigin !== want.onOrigin) {
        return {agree, diverge: {case: c, events: events(c), bash: real, rule: {...want, phase: dec.phase}, stderr: out.stderr.slice(-400), out: bash(`cat '${d}/out'`, sb.env).stdout.slice(-600)}}
      }
      agree++
    }
    return {agree, diverge: null}
  } finally { sb.cleanup() }
}

if (import.meta.url === `file://${process.argv[1]}`) console.log(JSON.stringify(await bridge(), null, 1))
