import { expect, mock, test } from 'claude-code/testing'
import type { TestBody } from 'claude-code/testing'

import { parseAllRows, parseRepoRows } from '../hooks/parse'

type Params = Parameters<TestBody>

const PANE = {
  title: 'Board',
  isFocused: false,
  bodyColumns: 100,
  placement: 'dock' as const,
  scroll: { offset: 0, bodyRows: 30 },
  view: {},
}
const OPEN_PANE = { id: 'board', title: 'Board', isShown: true, isFocused: false, isPlaced: true }

const REPO_OUT = 'queued:\n  ID-1  first thing\nclaimed:\n  ID-2  second thing\nexecuting:\n  ID-3  third thing\n'
const ALL_OUT = [
  'app-one        ID-1',
  'app-two        ID-2 [STALE: 3 behind upstream]',
  'app-three      (no queued items)',
  'app-four       (no queued items)',
  '',
  'STALE CHECKOUTS, rows above may be out of date: app-two(3 behind)',
  '',
].join('\n')

const runInput = (args: string) => ({
  command: 'board',
  args,
  origin: { kind: 'composer' as const },
  presentation: { isFullscreen: false, columns: 120 },
})

const mountPane = ($: Params[0]) =>
  $.ui.mount({ plugin: 'board-pane', surface: 'terminal', component: 'Pane', props: PANE, requestId: 'board' })

const setup = async (
  $: Params[0],
  on: Params[1],
  result: { exitCode: number; stdout: string; stderr: string },
) => {
  const argvs: string[][] = []
  const submitted: string[] = []
  const panes = [OPEN_PANE]
  const clock = mock.clock(on, { now: Date.UTC(2026, 0, 1, 10, 30) })
  mock.env(on, { DWARVES_KIT: '/opt/kit' })
  on('command.register', (_$, e) => ({ value: { command: e.name } }))
  on('session.start', (_$, e) => ({ cwd: e.cwd }))
  on('session.cwd', () => ({ value: '/work/app-one' }))
  on('process.run', (_$, e) => {
    argvs.push([...e.argv])
    return { value: { ...result, isStdoutTruncated: false, isStderrTruncated: false } }
  })
  on('ui.open', () => ({ value: { isPlaced: true as const } }))
  on('ui.panes', () => ({ value: [...panes] }))
  const closed: string[] = []
  on('ui.close', (_$, e) => {
    closed.push(e.id)
    return { value: undefined }
  })
  on('prompt.submit', (_$, e) => {
    submitted.push(e.text)
    return { text: e.text }
  })
  const filled: string[] = []
  on('prompt.fill', (_$, e) => {
    filled.push(e.text)
    return { isFilled: true }
  })
  await $.session.start({ cwd: '/work/app-one', surface: 'terminal', isInteractive: true })
  return { argvs, submitted, filled, panes, clock, closed }
}

test('/board runs the single-repo render in the session cwd', async ($, on) => {
  const { argvs } = await setup($, on, { exitCode: 0, stdout: REPO_OUT, stderr: '' })
  const ran = await $.command.run(runInput(''))
  expect(ran.text).toContain('Board pane opened')
  expect(argvs[0]?.slice(1)).toEqual(['board', '--backlog-file', '/work/app-one/_meta/BACKLOG.md'])
  expect(argvs[0]?.[0]).toBe('/opt/kit/bin/board')
  const ui = await mountPane($)
  expect((await ui.find({ type: 'Text', text: /^queued:$/ }))?.props).toMatchObject({ bold: true })
  await ui.unmount()
})

test('/board all runs the registry view with --repo-root', async ($, on) => {
  const { argvs } = await setup($, on, { exitCode: 0, stdout: ALL_OUT, stderr: '' })
  await $.command.run(runInput('all'))
  expect(argvs[0]?.slice(1)).toEqual(['all', 'next', '--repo-root', '/work/app-one'])
})

test('a non-zero exit shows stderr dimmed in the pane', async ($, on) => {
  await setup($, on, { exitCode: 1, stdout: '', stderr: 'board: no BACKLOG.md at /work/app-one/_meta/BACKLOG.md\n' })
  const ran = await $.command.run(runInput(''))
  expect(ran.text).toContain('Board pane opened')
  const ui = await mountPane($)
  const hit = await ui.find({ type: 'Text', text: /no BACKLOG\.md/ })
  expect(hit?.props).toMatchObject({ dimColor: true })
  await ui.unmount()
})

test('Refresh re-runs the same mode and carries the r hotkey', async ($, on) => {
  const { argvs } = await setup($, on, { exitCode: 0, stdout: ALL_OUT, stderr: '' })
  await $.command.run(runInput('all'))
  const ui = await mountPane($)
  expect((await ui.find({ key: 'refresh' }))?.props).toMatchObject({ hotkey: 'r' })
  await ui.press({ key: 'refresh' })
  expect(argvs).toHaveLength(2)
  expect(argvs[1]?.slice(1)).toEqual(['all', 'next', '--repo-root', '/work/app-one'])
  await ui.unmount()
})

test('pressing an item fills the prompt with Work on <ID> in repo mode, never submits', async ($, on) => {
  const { submitted, filled } = await setup($, on, { exitCode: 0, stdout: REPO_OUT, stderr: '' })
  await $.command.run(runInput(''))
  const ui = await mountPane($)
  expect((await ui.find({ key: 'item-1' }))?.props).toMatchObject({ plain: true, hotkey: '1' })
  await ui.press({ key: 'item-1' })
  expect(filled).toEqual(['Work on ID-1'])
  expect(submitted).toEqual([])
  await ui.unmount()
})

test('pressing an item fills the prompt with Work on <ID> in <repo> in all mode', async ($, on) => {
  const { submitted, filled } = await setup($, on, { exitCode: 0, stdout: ALL_OUT, stderr: '' })
  await $.command.run(runInput('all'))
  const ui = await mountPane($)
  await ui.press({ key: 'item-2' })
  expect(filled).toEqual(['Work on ID-2 in app-two'])
  expect(submitted).toEqual([])
  await ui.unmount()
})

test('all mode shows the refresh time, dims stale rows with ?, drops the trailer, folds idle repos', async ($, on) => {
  await setup($, on, { exitCode: 0, stdout: ALL_OUT, stderr: '' })
  await $.command.run(runInput('all'))
  const ui = await mountPane($)
  expect(await ui.find({ type: 'Text', text: /· \d\d:\d\d$/ })).toBeDefined()
  expect((await ui.find({ key: 'item-2' }))?.props).toMatchObject({ label: 'app-two  ID-2 ?', dimColor: true })
  expect((await ui.find({ key: 'item-1' }))?.props).toMatchObject({ dimColor: false })
  expect(await ui.find({ type: 'Text', text: /STALE/ })).toBeUndefined()
  expect((await ui.find({ type: 'Text', text: /^\+2 idle: app-three, app-four$/ }))?.props).toMatchObject({ dimColor: true })
  await ui.unmount()
})

test('repo mode tints executing cyan and claimed yellow', async ($, on) => {
  await setup($, on, { exitCode: 0, stdout: REPO_OUT, stderr: '' })
  await $.command.run(runInput(''))
  const ui = await mountPane($)
  const tints = await ui.findAll({ type: 'Text', text: /^\* $/ })
  expect(tints.map(t => t.props)).toEqual([{ color: 'yellow' }, { color: 'cyan' }])
  await ui.unmount()
})

test('the pane refreshes every 60s while open and stops once it closes', async ($, on) => {
  const { argvs, panes, clock } = await setup($, on, { exitCode: 0, stdout: REPO_OUT, stderr: '' })
  await $.command.run(runInput(''))
  expect(argvs).toHaveLength(1)
  await clock.advance(60_000)
  expect(argvs).toHaveLength(2)
  panes.length = 0
  await clock.advance(60_000)
  await clock.advance(60_000)
  expect(argvs).toHaveLength(2)
})

test('repo rows parse headers, items and tones', () => {
  const rows = parseRepoRows(REPO_OUT.trimEnd().split('\n'))
  expect(rows[0]).toEqual({ kind: 'text', text: 'queued:', isDim: false, isBold: true })
  expect(rows[1]).toEqual({ kind: 'item', id: 'ID-1', text: 'ID-1  first thing', tone: undefined, isDim: false })
  expect(rows[3]).toMatchObject({ kind: 'item', id: 'ID-2', tone: 'yellow' })
  expect(rows[5]).toMatchObject({ kind: 'item', id: 'ID-3', tone: 'cyan' })
})

test('all rows parse items, stale tags and idle repos', () => {
  const rows = parseAllRows(ALL_OUT.split('\n'))
  expect(rows).toEqual([
    { kind: 'item', id: 'ID-1', repo: 'app-one', text: 'app-one  ID-1', isDim: false },
    { kind: 'item', id: 'ID-2', repo: 'app-two', text: 'app-two  ID-2 ?', isDim: true },
    { kind: 'text', text: '+2 idle: app-three, app-four', isDim: true, isBold: false },
  ])
})

test('Close shuts the pane and carries the q hotkey', async ($, on) => {
  const { closed } = await setup($, on, { exitCode: 0, stdout: REPO_OUT, stderr: '' })
  await $.command.run(runInput(''))
  const ui = await mountPane($)
  expect((await ui.find({ key: 'close' }))?.props).toMatchObject({ hotkey: 'q', role: 'dismiss' })
  await ui.press({ key: 'close' })
  expect(closed).toEqual(['board'])
  await ui.unmount()
})
