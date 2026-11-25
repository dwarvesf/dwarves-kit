// Bridge: hold hooks/board-row-gate.sh to the board-row-gate rule in temp repos with a board. Each case stages (or
// not) a new row or a status flip, then commits in one of the ways the hook parses; the facts say what git would
// really take into the commit.
import {boardRowGate} from './board-row-gate.ts'
import {gitRepo, runHook, sandbox, sh, Tally, write, type BridgeResult} from './_bridge.ts'

const BOARD = '| ID | title | status |\n|---|---|---|\n| ID-1 | first | queued |\n'
const NEWROW = BOARD + '| ID-2 | second | queued |\n'
const FLIP = '| ID | title | status |\n|---|---|---|\n| ID-1 | first | done |\n'

type Case = {name: string, edit: string, stage: boolean, cmd: string, newRow: boolean, rowChanged: boolean, marker: boolean, commit?: boolean, special?: boolean}
const CASES: Case[] = [
  {name: 'staged new row, plain -m', edit: NEWROW, stage: true, cmd: 'git commit -m "feat: x"', newRow: true, rowChanged: true, marker: false},
  {name: 'staged new row, marker as second -m', edit: NEWROW, stage: true, cmd: 'git commit -m "feat: x" -m "board-row-ok: operator asked"', newRow: true, rowChanged: true, marker: true},
  {name: 'staged new row, marker in heredoc', edit: NEWROW, stage: true, cmd: "git commit -F- <<'EOF'\nfeat: x\n\nboard-row-ok: blocker outside\nEOF", newRow: true, rowChanged: true, marker: true},
  {name: 'unstaged new row, plain commit', edit: NEWROW, stage: false, cmd: 'git commit -m "feat: x"', newRow: false, rowChanged: false, marker: false},
  {name: 'unstaged new row, -am', edit: NEWROW, stage: false, cmd: 'git commit -am "feat: x"', newRow: true, rowChanged: true, marker: false},
  {name: 'unstaged new row, add then commit', edit: NEWROW, stage: false, cmd: 'git add _meta/BACKLOG.md && git commit -m "feat: x"', newRow: true, rowChanged: true, marker: false},
  {name: 'unstaged new row, add -A then commit', edit: NEWROW, stage: false, cmd: 'git add -A && git commit -m "feat: x"', newRow: true, rowChanged: true, marker: false},
  {name: 'unstaged new row, pathspec covers board', edit: NEWROW, stage: false, cmd: 'git commit -m "feat: x" -- _meta/BACKLOG.md', newRow: true, rowChanged: true, marker: false},
  {name: 'staged new row, pathspec elsewhere', edit: NEWROW, stage: true, cmd: 'git commit -m "feat: x" -- README.md', newRow: false, rowChanged: false, marker: false},
  {name: 'status flip only', edit: FLIP, stage: true, cmd: 'git commit -m "chore: flip"', newRow: false, rowChanged: true, marker: false},
  {name: 'marker after && belongs to a later command', edit: NEWROW, stage: true, cmd: 'git commit -m "feat: x" && echo "board-row-ok: nope"', newRow: true, rowChanged: true, marker: false},
  {name: 'not a commit', edit: NEWROW, stage: true, cmd: 'git status', newRow: true, rowChanged: true, marker: false, commit: false},
  {name: 'quoted prose mentions git commit', edit: NEWROW, stage: true, cmd: 'echo "run git commit later"', newRow: true, rowChanged: true, marker: false, commit: false},
]

export async function bridge(): Promise<BridgeResult> {
  const t = new Tally()
  const f = boardRowGate()
  for (const mode of ['default', 'kill', 'optout', 'merging'] as const) {
    for (const c of CASES) {
      const files: Record<string, string> = {'_meta/BACKLOG.md': BOARD, 'README.md': 'x\n'}
      if (mode === 'optout') files['.kit.toml'] = '[gate]\nboard_row_gate = false\n'
      const dir = gitRepo(files)
      write(dir, {'_meta/BACKLOG.md': c.edit, 'README.md': 'y\n'})
      sh('git add README.md', dir)
      if (c.stage) sh('git add _meta/BACKLOG.md', dir)
      if (mode === 'merging') sh('git rev-parse HEAD > .git/MERGE_HEAD', dir)
      const s = sandbox()
      const env = mode === 'kill' ? {...s.env, DWARVES_KIT_SKIP_BOARD_ROW_GATE: '1'} : s.env
      const facts = {skip: mode === 'kill', commit: c.commit ?? true, board: true, special: mode === 'merging', head: true,
        newRow: c.newRow, rowChanged: c.rowChanged, off: mode === 'optout', marker: c.marker}
      const want = f.run(facts).block ? 2 : 0
      const r = runHook('board-row-gate.sh', {tool_name: 'Bash', tool_input: {command: c.cmd}, cwd: dir}, {env, cwd: dir})
      t.check(r.code === want, () => ({mode, case: c.name, cmd: c.cmd, facts, rule: want, hook: r.code, stderr: r.stderr.slice(0, 300)}))
    }
  }
  return t.result()
}

if (import.meta.main) console.log(JSON.stringify(await bridge(), null, 2))
