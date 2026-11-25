// Bridge: `lib/gate/dispatch-gate.sh disjoint <specA> <specB>` against touchesDisjoint(). Every pair of `<prefix>/**`
// globs whose prefix is one or two segments from {a, b, ., .., empty} is written into two specs' `## Touches` and run;
// exit 0 (provably disjoint) / 1 (overlap) is compared with the rule's gateOverlaps.
import {writeFileSync} from 'node:fs'
import {join} from 'node:path'
import {SEGS, touchesDisjoint} from './touches-disjoint.ts'
import {cleanup, lib, sh, tmp, type BridgeResult} from './_bridge.ts'

const TXT: Record<typeof SEGS[number], string> = {a: 'a', b: 'b', dot: '.', dotdot: '..', empty: ''}

export async function bridge(): Promise<BridgeResult> {
  const f = touchesDisjoint()
  const globs: {n: number, s1: typeof SEGS[number], s2: typeof SEGS[number]}[] = []
  for (const s1 of SEGS) globs.push({n: 1, s1, s2: 'a'})
  for (const s1 of SEGS) for (const s2 of SEGS) globs.push({n: 2, s1, s2})
  const text = (g: typeof globs[number]) => (g.n === 1 ? TXT[g.s1] : `${TXT[g.s1]}/${TXT[g.s2]}`) + '/**'
  const root = tmp('touches-')
  let agree = 0, diverge: BridgeResult['diverge'] = null
  try {
    // One bash process per left glob: it sources the gate and loops over every right glob.
    for (const A of globs) {
      if (diverge) break
      writeFileSync(join(root, 'A.md'), `# A\n\n## Touches\n- ${text(A)}\n`)
      globs.forEach((B, i) => writeFileSync(join(root, `B${i}.md`), `# B\n\n## Touches\n- ${text(B)}\n`))
      const res = sh('bash', ['-c', `for i in $(seq 0 ${globs.length - 1}); do bash "${lib('gate/dispatch-gate.sh')}" disjoint "$1/A.md" "$1/B$i.md" >/dev/null 2>&1; echo $?; done`, 'x', root])
      const codes = res.out.trim().split('\n')
      globs.forEach((B, i) => {
        if (diverge) return
        const want = (f.run({n1: A.n, x1: A.s1, x2: A.s2, n2: B.n, y1: B.s1, y2: B.s2} as never) as {gateOverlaps: number}).gateOverlaps === 1 ? 'overlap' : 'disjoint'
        const got = codes[i] === '0' ? 'disjoint' : codes[i] === '1' ? 'overlap' : `exit ${codes[i]}`
        if (want !== got) diverge = {a: text(A), b: text(B), rule: want, bash: got}
        else agree++
      })
    }
  } finally { cleanup(root) }
  return {agree, diverge}
}

// F8 reproduction pairs (the gate says disjoint; they share files): `./**` vs `a/**`, `a/./**` vs `a/a/**`,
// `a//**` vs `a/b/**`, `b/../a/**` vs `a/**`.
export const F8_PAIRS = [['./**', 'a/**'], ['a/./**', 'a/a/**'], ['a//**', 'a/b/**'], ['b/../a/**', 'a/**']]

if (import.meta.url === `file://${process.argv[1]}`) {
  const t0 = Date.now()
  const res = await bridge()
  console.log(JSON.stringify(res, null, 1), `${Date.now() - t0}ms`)
  process.exit(res.diverge ? 1 : 0)
}
