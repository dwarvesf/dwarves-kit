// Bridge: `lib/goal/goal-drafts.sh archive [--dry-run]` against goalDrafts(). Every sequence of three requests
// (archive, dry, ship, reopen) for each target kind and each starting layout (top only, top + an archived copy) is
// run in temp GOAL_DRAFTS_DIR / GOAL_SPECS_DIR roots; ship/reopen rewrite the spec's Status header. The draft's
// location afterwards is compared with the rule.
import {existsSync, mkdirSync, rmSync, writeFileSync} from 'node:fs'
import {join} from 'node:path'
import {goalDrafts} from './goal-drafts.ts'
import {cleanup, lib, product, sh, tmp, type BridgeResult} from './_bridge.ts'

const OPS = ['archive', 'dry', 'ship', 'reopen'] as const
const TARGET = {specless: 'target_spec: (none yet)', unresolvable: 'target_spec: SPEC-404', spec: 'target_spec: SPEC-027'}

export async function bridge(): Promise<BridgeResult> {
  const root = tmp('drafts-')
  let agree = 0, diverge: BridgeResult['diverge'] = null
  try {
    for (const start of product({target: ['specless', 'unresolvable', 'spec'] as const, withCopy: [false, true], a: OPS, b: OPS, c: OPS})) {
      if (diverge) break
      const drafts = join(root, 'drafts'), specs = join(root, 'specs')
      rmSync(drafts, {recursive: true, force: true}); rmSync(specs, {recursive: true, force: true})
      mkdirSync(join(drafts, 'done'), {recursive: true}); mkdirSync(specs)
      const body = `---\nslug: d1\n${TARGET[start.target]}\n---\nbody\n`
      writeFileSync(join(drafts, 'd1.md'), body)
      if (start.withCopy) writeFileSync(join(drafts, 'done', 'd1.md'), 'an older archived copy\n')
      const spec = join(specs, 'SPEC-027-thing.md')
      writeFileSync(spec, 'Status: DRAFT\n')
      const r = goalDrafts(), it = r.interpreter(), P = r.encodeParams({target: start.target})
      let st: any = it.init(P)
      if (start.withCopy) st = {...st, scalars: {...st.scalars, done: 1}}
      const env = {GOAL_DRAFTS_DIR: drafts, GOAL_SPECS_DIR: specs}
      const trace: string[] = []
      for (const op of [start.a, start.b, start.c]) {
        if (op === 'ship') writeFileSync(spec, 'Status: SHIPPED (v1.0.0)\n')
        else if (op === 'reopen') writeFileSync(spec, 'Status: DRAFT\n')
        else sh('bash', [lib('goal/goal-drafts.sh'), 'archive', ...(op === 'dry' ? ['--dry-run'] : [])], {env})
        st = it.step(P, st, r.encodeInput({op}))
        trace.push(op)
        const got = `${existsSync(join(drafts, 'd1.md')) ? 'top' : '-'}/${existsSync(join(drafts, 'done', 'd1.md')) ? 'done' : '-'}`
        const want = `${st.scalars.top ? 'top' : '-'}/${st.scalars.done ? 'done' : '-'}`
        if (got !== want) { diverge = {target: start.target, archived_copy_at_start: start.withCopy, trace, rule: want, bash: got}; break }
        agree++
      }
    }
  } finally { cleanup(root) }
  return {agree, diverge}
}

if (import.meta.url === `file://${process.argv[1]}`) {
  const t0 = Date.now()
  const res = await bridge()
  console.log(JSON.stringify(res, null, 1), `${Date.now() - t0}ms`)
  process.exit(res.diverge ? 1 : 0)
}
