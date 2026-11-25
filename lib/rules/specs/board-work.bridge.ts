// Bridge: one temp repo with a board row BK-1, a draft (id BK-1, slug feat-x), the branch feat/feat-x checked out
// in a worktree; per case a board status, run-ledger GATE lines (validate, execute/build, battery/review, ship), an
// orca stub (absent, a working terminal, an idle live terminal of a given age, a terminal with no live session),
// --now and --idle-min. The real lib/board/work.sh --json; BK-1's rung and flags against the rule (board-work.ts).
import {chmodSync, mkdirSync, rmSync, writeFileSync} from 'node:fs'
import {join} from 'node:path'
import {AGENTS, LEADS, boardWork, type Variant} from './board-work.ts'
import {KIT, run, seeded, tmp, type BridgeResult} from './util.ts'

const SH = join(KIT, 'lib/board/work.sh')
const NOW = 1_800_000_000

export async function bridge(variant: Variant = 'shipped'): Promise<BridgeResult> {
  const f = boardWork(variant)
  const t = tmp('board-work')
  let agree = 0
  try {
    const repo = join(t.dir, 'repo'), wt = join(t.dir, 'wt'), ledger = join(t.dir, 'ledger')
    mkdirSync(join(repo, '_meta'), {recursive: true}); mkdirSync(join(repo, '.claude/goals'), {recursive: true})
    const g = (...a: string[]) => run(['git', '-C', repo, '-c', 'user.email=t@t', '-c', 'user.name=t', '-c', 'commit.gpgsign=false', ...a])
    g('init', '-q', '-b', 'main'); writeFileSync(join(repo, 'README.md'), 'x\n'); g('add', '.'); g('commit', '-q', '-m', 'init')
    g('branch', 'feat/feat-x'); g('worktree', 'add', '-q', wt, 'feat/feat-x')
    writeFileSync(join(repo, '.claude/goals/feat-x.md'), '---\nid: BK-1\nslug: feat-x\n---\n# goal\n')
    const orca = join(t.dir, 'orca')
    const rand = seeded(20), b = () => rand(2) === 1
    for (let i = 0; i < 45; i++) {
      const c = {validate: b(), build: b(), review: rand(3) === 0, ship: rand(3) === 0, lead: LEADS[rand(LEADS.length)],
        agent: AGENTS[i < 4 ? i : rand(AGENTS.length)], age: [0, 59, 60, 61, 1199, 1200, 1201, 5000][rand(8)], idleMin: [0, 1, 20][rand(3)],
        buildWord: b() ? 'execute' : 'build', reviewWord: b() ? 'battery' : 'review'}
      writeFileSync(join(repo, '_meta/BACKLOG.md'), `| ID | Item | Notes | Status |\n|---|---|---|---|\n| BK-1 | thing | n | ${c.lead} [x] |\n`)
      rmSync(ledger, {recursive: true, force: true}); mkdirSync(join(ledger, 'runs'), {recursive: true})
      const lines = [c.validate && 'validate', c.build && c.buildWord, c.review && c.reviewWord, c.ship && 'ship', 'think']
        .filter(Boolean).map(p => `2026-11-25T00:00:00Z | GATE | ${p} | ran | evidence`)
      lines.push('2026-11-25T00:00:00Z | GATE | spec | skipped | not this one')
      writeFileSync(join(ledger, 'runs/feat-x.log'), lines.join('\n') + '\n')
      const row = c.agent === 'working' ? {status: 'working', liveTerminalCount: 1}
        : c.agent === 'idleLive' ? {status: 'inactive', liveTerminalCount: 1, lastOutputAt: (NOW - c.age) * 1000}
          : {status: 'inactive', liveTerminalCount: 0}
      writeFileSync(orca, `#!/usr/bin/env bash\ncat <<'J'\n${JSON.stringify({result: {truncated: false, worktrees: [{path: wt, branch: 'refs/heads/feat/feat-x', hostId: 'local', agents: [], ...row}]}})}\nJ\n`)
      chmodSync(orca, 0o755)
      const res = run(['bash', SH, '--json', '--repo-root', repo, '--now', String(NOW), '--idle-min', String(c.idleMin)],
        {cwd: repo, env: {ORCA_BIN: c.agent === 'absent' ? join(t.dir, 'no-orca') : orca, KIT_LEDGER_DIR: ledger, HOME: t.dir, GOAL_REGISTRY_SH: '/dev/null'}})
      let item: any
      try { item = JSON.parse(res.out).items.find((x: any) => x.item === 'BK-1') } catch { return {agree, diverge: {case: c, exit: res.code, stderr: res.err.slice(0, 400)}} }
      const m = f.run({validate: c.validate, build: c.build, review: c.review, ship: c.ship, lead: c.lead, agent: c.agent, age: c.age, idleMin: c.idleMin} as never) as any
      const bash = {rung: item?.rung, parked: item?.flags.includes('PARKED'), doneUnseen: item?.flags.includes('DONE-UNSEEN'),
        indeterminate: item?.flags.includes('INDETERMINATE'), state: item?.agent.state}
      const want = {rung: m.rung, parked: m.parked, doneUnseen: m.doneUnseen, indeterminate: m.indeterminate, state: m.state}
      if (JSON.stringify(bash) !== JSON.stringify(want)) return {agree, diverge: {case: c, bash, rule: want, item}}
      agree++
    }
    return {agree, diverge: null}
  } finally { t.done() }
}

if (import.meta.url === `file://${process.argv[1]}`) console.log(JSON.stringify({bridge: await bridge((process.argv[2] ?? 'shipped') as Variant)}, null, 1))
