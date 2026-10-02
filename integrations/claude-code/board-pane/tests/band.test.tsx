import { expect, mock, test } from 'claude-code/testing'
import type { TestBody } from 'claude-code/testing'

type Params = Parameters<TestBody>

const BAND = {
  hasSurvey: false,
  isWorking: false,
  maxRows: 6,
  bodyColumns: 120,
  scroll: { offset: 0, bodyRows: 6 },
  view: {},
}

const BOARD_OUT = 'queued:\n  ID-1  first\n  ID-2  second\nclaimed:\n  ID-3  third\nexecuting:\n  ID-4  fourth\n'
const PORCELAIN = 'worktree /work/app-one\nHEAD abc\n\nworktree /work/app-one/.claude/worktrees/a\nHEAD def\n\nworktree /work/app-one/.claude/worktrees/b\nHEAD fed\n'
const ENTRIES = [
  { name: 'one.md', kind: 'file' as const, size: 1, mtimeMs: 0, isLink: false },
  { name: 'two.md', kind: 'file' as const, size: 1, mtimeMs: 0, isLink: false },
  { name: 'notes.txt', kind: 'file' as const, size: 1, mtimeMs: 0, isLink: false },
  { name: 'archive', kind: 'dir' as const, size: 0, mtimeMs: 0, isLink: false },
]
const FIVE_MIN = 5 * 60_000
const DAY = 86_400
// A clock far from zero, so commit ages in seconds read naturally.
const NOW_MS = 100 * DAY * 1000

type Failing = 'board' | 'git' | 'gitStale' | 'gh' | 'fs'

type Options = {
  now?: number
  porcelain?: string
  merged?: string
  ages?: string
  detached?: Record<string, string>
  // The default-branch lookup answer; a non-zero exit sends the helper to its main/master guesses.
  defaultBranch?: { exitCode: number; stdout: string }
  // Merged-list lookups that fail for these branch names.
  mergedFails?: readonly string[]
}

const result = (exitCode: number, stdout: string) => ({
  value: { exitCode, stdout, stderr: '', isStdoutTruncated: false, isStderrTruncated: false },
})

const setup = async ($: Params[0], on: Params[1], failing: readonly Failing[] = [], options: Options = {}) => {
  const calls: string[] = []
  const gitArgs: string[] = []
  const filled: string[] = []
  const submitted: string[] = []
  const opened: string[] = []
  const closed: string[] = []
  const panes: { id: string; title: string; isShown: boolean; isFocused: boolean; isPlaced: boolean }[] = []
  const clock = mock.clock(on, { now: options.now ?? 0 })
  mock.env(on, { DWARVES_KIT: '/opt/kit' })
  on('command.register', (_$, e) => ({ value: { command: e.name } }))
  on('session.start', (_$, e) => ({ cwd: e.cwd }))
  on('session.cwd', () => ({ value: '/work/app-one' }))
  on('turn.complete', () => ({ text: '' }))
  on('process.run', (_$, e) => {
    const name = e.argv[0] === '/opt/kit/bin/board' ? 'board' : (e.argv[0] ?? '')
    calls.push(name)
    if (name === 'board') return failing.includes('board') ? result(1, '') : result(0, BOARD_OUT)
    if (name === 'git') {
      if (failing.includes('git')) return result(128, '')
      const verb = e.argv[3] ?? ''
      gitArgs.push(e.argv.slice(3).join(' '))
      if (verb === 'worktree') return result(0, options.porcelain ?? PORCELAIN)
      if (failing.includes('gitStale')) return result(128, '')
      if (verb === 'rev-parse') {
        const lookup = options.defaultBranch ?? { exitCode: 0, stdout: 'origin/main\n' }
        return result(lookup.exitCode, lookup.stdout)
      }
      if (verb === 'for-each-ref' && (e.argv[4] ?? '').startsWith('--merged=')) {
        const branch = (e.argv[4] ?? '').slice('--merged='.length)
        return options.mergedFails?.includes(branch) ? result(128, '') : result(0, options.merged ?? '')
      }
      if (verb === 'for-each-ref') return result(0, options.ages ?? '')
      if (verb === 'log') return result(0, `${options.detached?.[e.argv[6] ?? ''] ?? String((options.now ?? 0) / 1000)}\n`)
      return result(1, '')
    }
    return failing.includes('gh') ? result(1, '') : result(0, '[{"number":7},{"number":9}]')
  })
  on('fs.list', () => {
    if (failing.includes('fs')) throw new Error('no such directory')
    return { value: ENTRIES }
  })
  on('ui.open', (_$, e) => {
    opened.push(e.id)
    return { value: { isPlaced: true as const } }
  })
  on('ui.panes', () => ({ value: [...panes] }))
  on('prompt.fill', (_$, e) => {
    filled.push(e.text)
    return { isFilled: true }
  })
  on('prompt.submit', (_$, e) => {
    submitted.push(e.text)
    return { text: e.text }
  })
  on('ui.close', (_$, e) => {
    closed.push(e.id)
    return { value: undefined }
  })
  // The engine's own band, beneath the plugin: what next(e) reaches when the mod draws nothing.
  on('ui.render', ($$, e) => {
    const { Box } = $$.ui.resolve(e)
    return <Box />
  })
  await $.session.start({ cwd: '/work/app-one', surface: 'terminal', isInteractive: true })
  return { calls, gitArgs, filled, submitted, opened, closed, panes, clock }
}

const mountBand = ($: Params[0], props = BAND) =>
  $.ui.mount({ plugin: 'board-pane', surface: 'terminal', component: 'AbovePrompt', props })

const turnComplete = ($: Params[0], agentId?: string) =>
  $.turn.complete({ answer: '', durationMs: 1, isAborted: false, turnId: 't1', reason: 'answer', agentId })

test('the band shows every segment with the right counts', async ($, on) => {
  await setup($, on)
  const ui = await mountBand($)
  expect((await ui.find({ key: 'seg-tasks' }))?.text).toBe('tasks 2q 1act')
  expect((await ui.find({ key: 'seg-handoffs' }))?.text).toBe('2ho')
  expect((await ui.find({ key: 'seg-worktrees' }))?.text).toBe('2wt')
  expect((await ui.find({ key: 'seg-prs' }))?.text).toBe('2pr')
  await ui.unmount()
})

test('a failing source drops only its own segment', async ($, on) => {
  await setup($, on, ['board', 'gh'])
  const ui = await mountBand($)
  expect(await ui.find({ key: 'seg-tasks' })).toBeUndefined()
  expect(await ui.find({ key: 'seg-prs' })).toBeUndefined()
  expect((await ui.find({ key: 'seg-handoffs' }))?.text).toBe('2ho')
  expect((await ui.find({ key: 'seg-worktrees' }))?.text).toBe('2wt')
  await ui.unmount()
})

test('a missing handoffs folder and a failing git drop those segments', async ($, on) => {
  await setup($, on, ['fs', 'git'])
  const ui = await mountBand($)
  expect(await ui.find({ key: 'seg-handoffs' })).toBeUndefined()
  expect(await ui.find({ key: 'seg-worktrees' })).toBeUndefined()
  expect(await ui.find({ key: 'seg-tasks' })).toBeDefined()
  await ui.unmount()
})

test('with every source failing the band draws nothing of its own', async ($, on) => {
  await setup($, on, ['board', 'git', 'gh', 'fs'])
  const ui = await mountBand($)
  expect(await ui.find({ key: 'seg-tasks' })).toBeUndefined()
  expect(await ui.find({ type: 'Text' })).toBeUndefined()
  await ui.unmount()
})

test('a survey takes the row, so the band steps aside', async ($, on) => {
  await setup($, on)
  const ui = await mountBand($, { ...BAND, hasSurvey: true })
  expect(await ui.find({ key: 'seg-tasks' })).toBeUndefined()
  await ui.unmount()
})

test('the PR lookup is cached for five minutes across turns', async ($, on) => {
  const { calls, clock } = await setup($, on)
  const ghCalls = () => calls.filter(name => name === 'gh').length
  expect(ghCalls()).toBe(1)
  await turnComplete($)
  await turnComplete($)
  expect(ghCalls()).toBe(1)
  await clock.advance(FIVE_MIN)
  await turnComplete($)
  expect(ghCalls()).toBe(2)
})

test('a subagent turn does not refresh the band', async ($, on) => {
  const { calls } = await setup($, on)
  const before = calls.length
  await turnComplete($, 'agent-1')
  expect(calls).toHaveLength(before)
  await turnComplete($)
  expect(calls.length).toBeGreaterThan(before)
})

test('pressing tasks opens the pane in repo mode, hotkey b', async ($, on) => {
  const { opened, calls } = await setup($, on)
  const ui = await mountBand($)
  const before = calls.filter(name => name === 'board').length
  await ui.press({ key: 'band-tasks' })
  expect(opened).toEqual(['board'])
  expect(calls.filter(name => name === 'board').length).toBe(before + 1)
  await ui.unmount()
})

test('pressing tasks again while the pane is open closes it', async ($, on) => {
  const { opened, closed, panes } = await setup($, on)
  const ui = await mountBand($)
  expect((await ui.find({ key: 'band-tasks' }))?.props).toMatchObject({ hotkey: 'b' })
  panes.push({ id: 'board', title: 'Board', isShown: true, isFocused: false, isPlaced: true })
  await ui.press({ key: 'band-tasks' })
  expect(closed).toEqual(['board'])
  expect(opened).toEqual([])
  await ui.unmount()
})

test('ho, wt and pr are buttons with hotkeys h, w, p; each press fills the prompt and never submits', async ($, on) => {
  const { filled, submitted } = await setup($, on)
  const ui = await mountBand($)
  expect((await ui.find({ key: 'band-handoffs' }))?.props).toMatchObject({ plain: true, hotkey: 'h', label: 'ho' })
  expect((await ui.find({ key: 'band-worktrees' }))?.props).toMatchObject({ plain: true, hotkey: 'w', label: 'wt' })
  expect((await ui.find({ key: 'band-prs' }))?.props).toMatchObject({ plain: true, hotkey: 'p', label: 'pr' })
  expect((await ui.find({ key: 'band-tasks' }))?.props).toMatchObject({ hotkey: 'b' })
  await ui.press({ key: 'band-worktrees' })
  await ui.press({ key: 'band-handoffs' })
  await ui.press({ key: 'band-prs' })
  expect(filled).toEqual([
    'Tidy the stale worktrees in this repo: list each with its branch and last commit, then remove the ones whose branch is merged',
    'List the open handoffs in .claude/handoffs/ with a one-line summary each, oldest first',
    'Review my open PRs in this repo: state, checks, and what each needs to merge',
  ])
  expect(submitted).toEqual([])
  await ui.unmount()
})

const STALE_PORCELAIN = [
  'worktree /work/app-one',
  'HEAD aaa',
  'branch refs/heads/main',
  '',
  'worktree /work/app-one/.claude/worktrees/merged',
  'HEAD bbb',
  'branch refs/heads/feat/merged',
  '',
  'worktree /work/app-one/.claude/worktrees/old',
  'HEAD ccc',
  'branch refs/heads/feat/old',
  '',
  'worktree /work/app-one/.claude/worktrees/fresh',
  'HEAD ddd',
  'branch refs/heads/feat/fresh',
  '',
  'worktree /work/app-one/.claude/worktrees/loose-old',
  'HEAD eee',
  'detached',
  '',
  'worktree /work/app-one/.claude/worktrees/loose-fresh',
  'HEAD fff',
  'detached',
  '',
].join('\n')
const NOW_S = NOW_MS / 1000
const STALE_OPTIONS: Options = {
  now: NOW_MS,
  porcelain: STALE_PORCELAIN,
  merged: 'main\nfeat/merged\n',
  ages: `main ${NOW_S - DAY}\nfeat/merged ${NOW_S - DAY}\nfeat/old ${NOW_S - 20 * DAY}\nfeat/fresh ${NOW_S - DAY}\n`,
  detached: { eee: String(NOW_S - 30 * DAY), fff: String(NOW_S - DAY) },
}

test('the worktree segment shows how many are stale: merged, old, detached-old, never the main checkout', async ($, on) => {
  await setup($, on, [], STALE_OPTIONS)
  const ui = await mountBand($)
  expect((await ui.find({ key: 'seg-worktrees' }))?.text).toBe('5wt (3 stale)')
  await ui.unmount()
})

test('no stale part when nothing is stale', async ($, on) => {
  await setup($, on, [], { ...STALE_OPTIONS, merged: 'main\n', ages: `main ${NOW_S - DAY}\n`, detached: { eee: String(NOW_S - DAY), fff: String(NOW_S - DAY) } })
  const ui = await mountBand($)
  expect((await ui.find({ key: 'seg-worktrees' }))?.text).toBe('5wt')
  await ui.unmount()
})

test('a failing staleness lookup drops only the stale part, never the count', async ($, on) => {
  await setup($, on, ['gitStale'], STALE_OPTIONS)
  const ui = await mountBand($)
  expect((await ui.find({ key: 'seg-worktrees' }))?.text).toBe('5wt')
  await ui.unmount()
})

test('without origin/HEAD the merged lookup falls back to main, then master', async ($, on) => {
  const first = await setup($, on, [], { ...STALE_OPTIONS, defaultBranch: { exitCode: 128, stdout: '' } })
  expect(first.gitArgs.filter(args => args.includes('--merged=')).map(args => args.split(' ')[1])).toEqual(['--merged=main'])
})

test('a repo whose default branch is master is found by the second guess', async ($, on) => {
  const { gitArgs } = await setup($, on, [], { ...STALE_OPTIONS, defaultBranch: { exitCode: 128, stdout: '' }, mergedFails: ['main'] })
  expect(gitArgs.filter(args => args.includes('--merged=')).map(args => args.split(' ')[1])).toEqual(['--merged=main', '--merged=master'])
  const ui = await mountBand($)
  expect((await ui.find({ key: 'seg-worktrees' }))?.text).toBe('5wt (3 stale)')
  await ui.unmount()
})
