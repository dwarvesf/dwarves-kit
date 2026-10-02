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

type Failing = 'board' | 'git' | 'gh' | 'fs'

const result = (exitCode: number, stdout: string) => ({
  value: { exitCode, stdout, stderr: '', isStdoutTruncated: false, isStderrTruncated: false },
})

const setup = async ($: Params[0], on: Params[1], failing: readonly Failing[] = []) => {
  const calls: string[] = []
  const opened: string[] = []
  const clock = mock.clock(on, { now: 0 })
  mock.env(on, { DWARVES_KIT: '/opt/kit' })
  on('command.register', (_$, e) => ({ value: { command: e.name } }))
  on('session.start', (_$, e) => ({ cwd: e.cwd }))
  on('session.cwd', () => ({ value: '/work/app-one' }))
  on('turn.complete', () => ({ text: '' }))
  on('process.run', (_$, e) => {
    const name = e.argv[0] === '/opt/kit/bin/board' ? 'board' : (e.argv[0] ?? '')
    calls.push(name)
    if (name === 'board') return failing.includes('board') ? result(1, '') : result(0, BOARD_OUT)
    if (name === 'git') return failing.includes('git') ? result(128, '') : result(0, PORCELAIN)
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
  on('ui.panes', () => ({ value: [] }))
  // The engine's own band, beneath the plugin: what next(e) reaches when the mod draws nothing.
  on('ui.render', ($$, e) => {
    const { Box } = $$.ui.resolve(e)
    return <Box />
  })
  await $.session.start({ cwd: '/work/app-one', surface: 'terminal', isInteractive: true })
  return { calls, opened, clock }
}

const mountBand = ($: Params[0], props = BAND) =>
  $.ui.mount({ plugin: 'board-pane', surface: 'terminal', component: 'AbovePrompt', props })

const turnComplete = ($: Params[0], agentId?: string) =>
  $.turn.complete({ answer: '', durationMs: 1, isAborted: false, turnId: 't1', reason: 'answer', agentId })

test('the band shows every segment with the right counts', async ($, on) => {
  await setup($, on)
  const ui = await mountBand($)
  expect((await ui.find({ key: 'seg-tasks' }))?.text).toBe('tasks 2 queued · 1 executing')
  expect((await ui.find({ key: 'seg-handoffs' }))?.text).toBe('2 handoffs')
  expect((await ui.find({ key: 'seg-worktrees' }))?.text).toBe('2 worktrees')
  expect((await ui.find({ key: 'seg-prs' }))?.text).toBe('2 PRs open')
  await ui.unmount()
})

test('a failing source drops only its own segment', async ($, on) => {
  await setup($, on, ['board', 'gh'])
  const ui = await mountBand($)
  expect(await ui.find({ key: 'seg-tasks' })).toBeUndefined()
  expect(await ui.find({ key: 'seg-prs' })).toBeUndefined()
  expect((await ui.find({ key: 'seg-handoffs' }))?.text).toBe('2 handoffs')
  expect((await ui.find({ key: 'seg-worktrees' }))?.text).toBe('2 worktrees')
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

test('pressing tasks opens the pane in repo mode', async ($, on) => {
  const { opened, calls } = await setup($, on)
  const ui = await mountBand($)
  const before = calls.filter(name => name === 'board').length
  await ui.press({ key: 'band-tasks' })
  expect(opened).toEqual(['board'])
  expect(calls.filter(name => name === 'board').length).toBe(before + 1)
  await ui.unmount()
})
