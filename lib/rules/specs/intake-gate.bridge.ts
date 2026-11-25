// Bridge: run the real lib/intake/intake.sh `gate "zonkplume reader"` with an operator config that turns each
// store on or off, stub stores (notes: prose-rag, PRs: gh, the URL ledger is skipped for a non-URL subject), a
// one-row board whose Notes cell carries the row features ([eval] tag, the word eval, eval inside `retrieval` or
// `medieval`, a skim), and a verdict file that matches or not. Exit and row_kind are compared with the rule.
import {chmodSync, mkdirSync, symlinkSync, writeFileSync} from 'node:fs'
import {join} from 'node:path'
import {execSync} from 'node:child_process'
import {intakeGate, STORES, type Variant} from './intake-gate.ts'
import {KIT, run, seeded, tmp, type BridgeResult} from './util.ts'

const SH = join(KIT, 'lib/intake/intake.sh')
type Case = {boardOn: boolean, boardMatch: boolean, verdictOn: boolean, verdictMatch: boolean, noteOn: boolean, noteMatch: boolean,
  prOn: boolean, prMatch: boolean, tag: boolean, word: boolean, inner: number, skim: boolean}

export async function bridge(variant: Variant = 'shipped'): Promise<BridgeResult> {
  const f = intakeGate(variant)
  const t = tmp('intake')
  let agree = 0
  try {
    const stub = join(t.dir, 'stub'); mkdirSync(stub)
    for (const tool of ['jq', 'python3', 'git']) symlinkSync(execSync(`command -v ${tool}`, {shell: '/bin/bash'}).toString().trim(), join(stub, tool))
    const one = (c: Case, n: number) => {
      const d = join(t.dir, `c${n}`); mkdirSync(join(d, 'op'), {recursive: true}); mkdirSync(join(d, 'repo')); mkdirSync(join(d, 'bin'))
      const notes = [c.tag && '[eval]', c.word && 'eval run measured', c.inner === 1 && 'retrieval notes', c.inner === 2 && 'medieval tooling',
        c.skim && 'skim only', 'plain words'].filter(Boolean).join(', ')
      writeFileSync(join(d, 'board.md'), `| ID | Item | Notes | Status |\n|---|---|---|---|\n| FX-1 | ${c.boardMatch ? 'zonkplume reader' : 'unrelated thing'} | ${notes} | queued |\n`)
      writeFileSync(join(d, 'boards.txt'), `fixture ${join(d, 'board.md')}\n`)
      writeFileSync(join(d, 'verdicts.md'), c.verdictMatch ? '| 2026-01-01 | zonkplume reader | NO-GO | x |\n' : '| 2026-01-01 | other | GO | x |\n')
      writeFileSync(join(d, 'op/kit.toml'), ['[intake]', c.boardOn && `boards = "${join(d, 'boards.txt')}"`,
        c.verdictOn && `verdicts = "${join(d, 'verdicts.md')}"`, c.noteOn && 'notes = "prose-rag"'].filter(Boolean).join('\n') + '\n')
      writeFileSync(join(d, 'bin/prose-rag'), `#!/usr/bin/env bash\necho '${c.noteMatch ? '[{"source":"n.md","heading":"zonkplume"}]' : '[]'}'\n`)
      writeFileSync(join(d, 'bin/gh'), c.prOn ? `#!/usr/bin/env bash\necho '${c.prMatch ? '[{"title":"zonkplume reader","url":"u"}]' : '[]'}'\n` : '#!/usr/bin/env bash\nexit 1\n')
      chmodSync(join(d, 'bin/prose-rag'), 0o755); chmodSync(join(d, 'bin/gh'), 0o755)
      const res = run(['bash', SH, 'gate', 'zonkplume reader'], {env: {PATH: `${join(d, 'bin')}:${stub}:/usr/bin:/bin`, HOME: d,
        REPO_ROOT: join(d, 'repo'), DWARVES_KIT_LOG_DIR: join(d, 'log'), KIT_LEDGER_DIR: join(d, 'log'), PRECEDENT_REGISTRY: join(d, 'none.txt'),
        KIT_CONFIG_OPERATOR: join(d, 'op'), KIT_PROJECT_ROOT: join(d, 'repo')}})
      const input: Record<string, boolean> = {urlOn: false, urlMatch: false, ownedOn: true, ownedMatch: false,
        boardOn: c.boardOn, boardMatch: c.boardMatch, verdictOn: c.verdictOn, verdictMatch: c.verdictMatch,
        noteOn: c.noteOn, noteMatch: c.noteMatch, prOn: c.prOn, prMatch: c.prMatch,
        tag: c.tag, word: c.word, inner: c.inner > 0, skim: c.skim}
      const m = f.run(input as never) as {exit: number, rowKind: string}
      let out: any = {}; try { out = JSON.parse(res.out) } catch { /* compared below */ }
      const boardHit = (out.hits ?? []).find((h: any) => h.kind === 'board')
      const bash = {exit: res.code, rowKind: boardHit?.row_kind ?? null}
      const want = {exit: m.exit, rowKind: c.boardOn && c.boardMatch ? m.rowKind : null}
      if (bash.exit !== want.exit || bash.rowKind !== want.rowKind) return {case: c, notes, bash, rule: want, stderr: res.err.trim()}
      agree++
      return null
    }
    let n = 0
    // every row-feature mix on a board hit
    for (let k = 0; k < 24; k++) {
      const x = one({boardOn: true, boardMatch: true, verdictOn: false, verdictMatch: false, noteOn: false, noteMatch: false, prOn: false, prMatch: false,
        tag: (k & 1) > 0, word: (k & 2) > 0, skim: (k & 4) > 0, inner: k >> 3}, n++)
      if (x) return {agree, diverge: x}
    }
    const rand = seeded(5), b = () => rand(2) === 1
    for (let i = 0; i < 40; i++) {
      const x = one({boardOn: b(), boardMatch: b(), verdictOn: b(), verdictMatch: b(), noteOn: b(), noteMatch: b(), prOn: b(), prMatch: b(),
        tag: rand(4) === 0, word: rand(4) === 0, skim: b(), inner: rand(3)}, n++)
      if (x) return {agree, diverge: x}
    }
    return {agree, diverge: null}
  } finally { t.done() }
  void STORES
}

if (import.meta.url === `file://${process.argv[1]}`) {
  const v = (process.argv[2] ?? 'shipped') as Variant
  console.log(JSON.stringify({variant: v, bridge: await bridge(v)}, null, 1))
}
