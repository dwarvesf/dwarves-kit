// Bridge: `lib/mega/mega.sh status` against megaStatus(), the way tests/test-mega.sh drives it: a real temp git repo as
// the code root (branches with 0 or 2 commits past master), a stub `gh` (GH_BIN) answering `pr view N` and
// `pr list --state open` from tables, and a megagoals root whose ROADMAP rows are generated (box, `PR #N`, a goal file
// with or without **Branch:**). Each row's printed label is compared with the rule's class for the same facts.
import {mkdirSync, writeFileSync} from 'node:fs'
import {join} from 'node:path'
import {CLASSES, megaStatus} from './mega-status.ts'
import {cleanup, git, initRepo, lib, rng, sh, stub, tmp, type BridgeResult} from './_bridge.ts'

export async function bridge(opts: {cases?: number, seed?: number} = {}): Promise<BridgeResult> {
  const cases = opts.cases ?? 30
  const g = rng(opts.seed ?? 41)
  const f = megaStatus()
  const root = tmp('megastatus-')
  let agree = 0, diverge: BridgeResult['diverge'] = null
  try {
    const code = join(root, 'code'); initRepo(code)
    const branches: Record<string, number> = {}
    for (const [name, ahead] of [['feat/zero', 0], ['feat/two', 2]] as const) {
      git(code, 'checkout', '-q', '-b', name, 'master')
      for (let k = 0; k < ahead; k++) { writeFileSync(join(code, `${name.replace('/', '-')}-${k}`), 'x\n'); git(code, 'add', '-A'); git(code, 'commit', '-q', '-m', `c${k}`) }
      git(code, 'checkout', '-q', 'master'); branches[name] = ahead
    }
    const ghTables = join(root, 'ghtables'); mkdirSync(ghTables)
    const gh = stub(root, 'gh', `case "$1 $2" in\n  "pr view") awk -v n="$3" '$1==n {print $2; f=1} END{exit !f}' "${ghTables}/states" ;;\n  "pr list") cat "${ghTables}/open.json" ;;\n  *) exit 1 ;;\nesac`)
    for (let c = 0; c < cases && !diverge; c++) {
      const mroot = join(root, `m${c}`), slug = 'mg'
      mkdirSync(join(mroot, slug, 'goals'), {recursive: true})
      const base = g.next() < 0.75 ? 'master' : 'nosuchbase'
      const rows = Array.from({length: 4}, (_, i) => ({
        sub: `0${i + 1}-s${i}`, box: g.pick(['open', 'open', 'done', 'parked'] as const),
        pr: g.next() < 0.6 ? 100 + i : 0, state: g.pick(['none', 'MERGED', 'OPEN', 'CLOSED'] as const),
        branch: g.pick(['', 'feat/zero', 'feat/two', 'feat/gone'] as const),
      }))
      // open PRs are per branch: every row naming that branch sees it
      const openHeads = (['feat/zero', 'feat/two', 'feat/gone'] as const).filter(() => g.next() < 0.3)
      const tok = {open: '[ ]', done: '[x]', parked: '[~]'}
      writeFileSync(join(mroot, slug, 'ROADMAP.md'), `# Mega\n## Sub-goals\n${rows.map(r => `- ${tok[r.box]} ${r.sub} (code), prose${r.pr ? `, PR #${r.pr}` : ''}`).join('\n')}\n`)
      for (const r of rows) if (r.branch) writeFileSync(join(mroot, slug, 'goals', `${r.sub}.md`), `**Branch:** ${r.branch}\n`)
      writeFileSync(join(ghTables, 'states'), rows.filter(r => r.pr && r.state !== 'none').map(r => `${r.pr} ${r.state}\n`).join(''))
      writeFileSync(join(ghTables, 'open.json'), JSON.stringify(openHeads.map((h, k) => ({number: 500 + k, headRefName: h}))))
      const res = sh('bash', [lib('mega/mega.sh'), 'status', slug, '--megagoals-root', mroot, '--code-root', code, '--base', base], {env: {GH_BIN: gh}})
      const got = res.out.split('\n').filter(l => /^  \S+ \S+/.test(l)).map(l => l.trim().split(/\s+/)[2].toLowerCase())
      const want = rows.map(r => {
        const exists = r.branch !== '' && r.branch in branches
        const out = f.run({box: r.box, hasPr: r.pr > 0, prState: r.pr ? r.state : 'none', named: r.branch !== '', exists,
          baseOk: base === 'master', commits: exists ? branches[r.branch] : 0, openPr: (openHeads as readonly string[]).includes(r.branch)} as never) as {cls: number}
        return CLASSES[out.cls]
      })
      if (JSON.stringify(want) !== JSON.stringify(got)) diverge = {base, rows, openHeads, rule: want, bash: got, out: res.out.trim().split('\n')}
      else agree += rows.length
    }
  } finally { cleanup(root) }
  return {agree, diverge}
}

if (import.meta.url === `file://${process.argv[1]}`) {
  const t0 = Date.now()
  const res = await bridge({cases: Number(process.env.CASES ?? 30), seed: Number(process.env.SEED ?? 41)})
  console.log(JSON.stringify(res, null, 1), `${Date.now() - t0}ms`)
  process.exit(res.diverge ? 1 : 0)
}
