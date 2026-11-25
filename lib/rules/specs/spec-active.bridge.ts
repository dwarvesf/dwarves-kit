// Bridge: build a temp repo with three root specs (each named exactly for the slug, nested under a longer slug,
// or unrelated; each open, closed or header-less), run the real lib/spec/spec-active.sh in its default and --live
// modes for a branch, and compare kind and pick with the rule's decision (spec-active.ts).
import {mkdirSync, rmSync, writeFileSync} from 'node:fs'
import {join} from 'node:path'
import {KINDS, specActive} from './spec-active.ts'
import {KIT, run, seeded, tmp, type BridgeResult} from './util.ts'

const SH = join(KIT, 'lib/spec/spec-active.sh')
const NAMES = ['gate', 'ship-gate', 'other'] as const
const STATUS = ['Status: DRAFT\n', 'Status: SHIPPED\n', ''] as const // open, closed, header-less (open under --none live)
const BRANCHES = ['feat/gate', 'feat/ship-gate', 'feat/other-1', 'fix/zzz', 'feat/ship']

function features(files: string[], branch: string) {
  const slug = branch.replace(/^[^/]*\//, '')
  const tokens = branch.split(/[/_.-]/).filter(Boolean)
  return files.map(f => {
    const p = f.replace(/\.md$/, '').replace(/^SPEC-[0-9]+-/, '')
    return {glob: f.startsWith('SPEC-') && f.endsWith(`-${slug}.md`), exact: p === slug, tok: tokens.some(t => `-${p}-`.includes(`-${t}-`))}
  })
}

export async function bridge(): Promise<BridgeResult> {
  const f = specActive()
  const t = tmp('spec-active')
  let agree = 0
  try {
    const rand = seeded(7)
    const cases: [number[], number[], number][] = []
    for (let i = 0; i < 27; i++) cases.push([[i % 3, (i / 3 | 0) % 3, (i / 9 | 0) % 3], [0, 0, 0], 0]) // every name mix, all open
    for (let i = 0; i < 27; i++) cases.push([[0, 1, 2], [i % 3, (i / 3 | 0) % 3, (i / 9 | 0) % 3], 1]) // every status mix
    for (let i = 0; i < 160; i++) cases.push([[rand(3), rand(3), rand(3)], [rand(3), rand(3), rand(3)], rand(BRANCHES.length)])
    let n = 0
    for (const [names, sts, b] of cases) {
      const root = join(t.dir, `r${n++}`), dir = join(root, 'docs/specs')
      mkdirSync(dir, {recursive: true})
      const files = names.map((k, i) => `SPEC-00${i + 1}-${NAMES[k] === 'other' ? `other-${i}` : NAMES[k]}.md`)
      files.forEach((file, i) => writeFileSync(join(dir, file), `# ${file}\n${STATUS[sts[i]]}`))
      const branch = BRANCHES[b]
      const fx = features(files, branch)
      const input = Object.fromEntries([0, 1, 2].flatMap(i => [[`live${i}`, sts[i] !== 1], [`glob${i}`, fx[i].glob], [`exact${i}`, fx[i].exact], [`tok${i}`, fx[i].tok]]))
      const m = f.run(input as never) as {kind: string, idx: number, nameIdx: number}
      const idxOf = (out: string) => { const p = out.split('\n')[0].split('\t')[1] ?? ''; const k = files.findIndex(x => p.endsWith(`/${x}`)); return k < 0 ? 3 : k }
      const d = run(['bash', SH, '--branch', branch, root])
      const l = run(['bash', SH, '--live', '--branch', branch, root])
      const lkind = l.code === 1 ? 'none' : l.out.split('\t')[0]
      const bash = {nameIdx: d.code === 0 ? idxOf(d.out) : 3, kind: lkind, idx: lkind === 'ambiguous' || lkind === 'none' ? 3 : idxOf(l.out)}
      rmSync(root, {recursive: true, force: true})
      if (bash.nameIdx !== m.nameIdx || bash.kind !== m.kind || bash.idx !== m.idx || !KINDS.includes(lkind as never))
        return {agree, diverge: {files, status: sts.map(s => ['open', 'closed', 'no header'][s]), branch, bash, rule: m, out: l.out}}
      agree++
    }
    return {agree, diverge: null}
  } finally { t.done() }
}

// The refuted reviewer law on the real bash: slug `gate` picks the nested spec over the one named exactly for it.
export async function confirm() {
  const t = tmp('spec-active-cx')
  try {
    const dir = join(t.dir, 'docs/specs'); mkdirSync(dir, {recursive: true})
    writeFileSync(join(dir, 'SPEC-001-ship-gate.md'), '# a\nStatus: DRAFT\n')
    writeFileSync(join(dir, 'SPEC-002-gate.md'), '# b\nStatus: DRAFT\n')
    const d = run(['bash', SH, '--branch', 'feat/gate', t.dir])
    const l = run(['bash', SH, '--live', '--branch', 'feat/gate', t.dir])
    return [{law: 'when a spec named exactly for the slug exists, the name pick is that spec',
      repro: 'docs/specs/{SPEC-001-ship-gate.md,SPEC-002-gate.md} (both DRAFT); bash lib/spec/spec-active.sh --branch feat/gate .',
      reproduced: d.out.includes('SPEC-001-ship-gate.md') && l.out.includes('SPEC-001-ship-gate.md'),
      default: d.out.trim().replace(t.dir, '.'), live: l.out.trim().replace(t.dir, '.')}]
  } finally { t.done() }
}

if (import.meta.url === `file://${process.argv[1]}`) console.log(JSON.stringify({bridge: await bridge(), confirm: await confirm()}, null, 1))
