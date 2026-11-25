// Bridge: hold hooks/commit-format.sh to the commit-format rule. Each case is a command and the facts of the subject
// git would really record; the gate is turned on through the operator overlay (KIT_CONFIG_OPERATOR) or left at its
// default (off). Seeded random subjects are built from parts whose facts are known.
import {commitFormat} from './commit-format.ts'
import {rng, runHook, sandbox, Tally, write, type BridgeResult} from './_bridge.ts'

const msg = (form: string, subject: string, body = 'Body line.') =>
  form === 'plain' ? `git commit -m "${subject}"`
  : form === 'heredoc' ? `git commit -m "$(cat <<'EOF'\n${subject}\n\n${body}\nEOF\n)"`
  : form === 'two-m' ? `git commit -m "${subject}" -m "${body}"`
  : form === 'single' ? `git commit -m '${subject}'`
  : form === 'long-opt' ? `git commit --message="${subject}"`
  : 'git commit'

const SUBJECTS: {s: string, conventional: boolean, marker: boolean, toolGen: boolean}[] = [
  {s: 'feat: add the parser', conventional: true, marker: false, toolGen: false},
  {s: 'fix(gate): refuse git reset --har', conventional: true, marker: false, toolGen: false},
  {s: 'refactor!: drop the v1 reader', conventional: true, marker: false, toolGen: false},
  {s: 'feat: SPEC-123 add parser', conventional: true, marker: true, toolGen: false},
  {s: 'chore: phase-2 cleanup', conventional: true, marker: true, toolGen: false},
  {s: 'fix: p1 regression', conventional: true, marker: true, toolGen: false},
  {s: 'updated stuff', conventional: false, marker: false, toolGen: false},
  {s: 'Feat: capitalised type', conventional: false, marker: false, toolGen: false},
  {s: 'Merge branch main into feat/x', conventional: false, marker: false, toolGen: true},
  {s: 'fixup! feat: add the parser', conventional: false, marker: false, toolGen: true},
  {s: 'Revert feat: add the parser', conventional: false, marker: false, toolGen: true},
]

export async function bridge(): Promise<BridgeResult> {
  const t = new Tally()
  const f = commitFormat()
  const s = sandbox()
  write(s.home, {'on/kit.toml': '[gate]\ncommit_format = true\n'})
  const envs = [{gateOff: false, env: {...s.env, KIT_CONFIG_OPERATOR: `${s.home}/on`}}, {gateOff: true, env: s.env}]
  const g = rng(42)
  const run = (cmd: string, facts: Record<string, unknown>, e: typeof envs[number]) => {
    const want = f.run({...facts, gateOff: e.gateOff} as any).block ? 2 : 0
    const r = runHook('commit-format.sh', {tool_name: 'Bash', tool_input: {command: cmd}}, {env: e.env})
    t.check(r.code === want, () => ({cmd, facts, gateOff: e.gateOff, rule: want, hook: r.code, out: r.stdout.trim()}))
  }
  for (const e of envs) {
    for (const sub of SUBJECTS) for (const form of ['plain', 'heredoc', 'two-m', 'single', 'long-opt']) {
      run(msg(form, sub.s), {isCommit: true, form: form === 'heredoc' ? 'heredoc' : 'plain', toolGen: sub.toolGen, tooLong: sub.s.length > 72, marker: sub.marker, conventional: sub.conventional}, e)
    }
    run('git commit', {isCommit: true, form: 'none', toolGen: false, tooLong: false, marker: false, conventional: false}, e)
    run('git commit --no-edit --amend', {isCommit: true, form: 'none', toolGen: false, tooLong: false, marker: false, conventional: false}, e)
    run('git commit -F msg.txt', {isCommit: true, form: 'none', toolGen: false, tooLong: false, marker: false, conventional: false}, e)
    run('git status', {isCommit: false, form: 'none', toolGen: false, tooLong: false, marker: false, conventional: false}, e)
    for (let i = 0; i < 40; i++) {
      const words = Array.from({length: 1 + g.int(16)}, () => g.pick(['add', 'the', 'parser', 'gate', 'for', 'reset', 'abbreviations', 'x']))
      const type = g.pick(['feat', 'fix', 'docs', 'nope', 'chore(ci)'])
      const subj = `${type}: ${words.join(' ')}`
      const form = g.pick(['plain', 'heredoc', 'two-m'])
      run(msg(form, subj, 'x'.repeat(g.int(200))), {isCommit: true, form: form === 'heredoc' ? 'heredoc' : 'plain', toolGen: false,
        tooLong: subj.length > 72, marker: false, conventional: type !== 'nope'}, e)
    }
  }
  return t.result()
}

if (import.meta.main) console.log(JSON.stringify(await bridge(), null, 2))
