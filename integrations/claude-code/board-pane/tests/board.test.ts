import { expect, mock, test } from 'claude-code/testing'
import type { TestBody } from 'claude-code/testing'

import { buildOverview, mergeRepos, parseAllBoard, parseRegistry, parseSingleBoard } from '../hooks/parse'

type Params = Parameters<TestBody>

const paneProps = (bodyColumns: number) => ({
  title: 'Board',
  isFocused: false,
  bodyColumns,
  placement: 'dock' as const,
  scroll: { offset: 0, bodyRows: 30 },
  view: {},
})
const OPEN_PANE = { id: 'board', title: 'Board', isShown: true, isFocused: false, isPlaced: true }

const REGISTRY = [
  '# registry',
  'app-one    /work/app-one/_meta/BACKLOG.md    rail=work',
  'app-two    /work/app-two/_meta/BACKLOG.md    rail=work',
  'app-three  /work/app-three/_meta/BACKLOG.md  rail=home',
  'app-four   ~/app-four/_meta/BACKLOG.md',
  'app-five   /work/app-five/_meta/BACKLOG.md   rail=home',
  'app-six    /work/app-six/_meta/BACKLOG.md',
  '',
].join('\n')

const ALL_BOARD = [
  '',
  '=== app-one ===',
  'queued:',
  '  ID-1  first thing',
  '  ID-2  second thing',
  '',
  '=== app-two [STALE: 3 behind upstream] ===',
  'queued:',
  '  ID-3  third thing',
  'claimed:',
  '  ID-4  fourth thing',
  'speccing:',
  '  ID-5  fifth thing',
  'validated:',
  '  ID-6  sixth thing',
  'executing:',
  '  ID-7  seventh thing',
  'shipped:',
  '  ID-8  eighth thing',
  '',
  '=== app-three ===',
  'queued:',
  '  ID-9  ninth thing',
  '',
  '=== app-four ===',
  'shipped:',
  '  ID-10  tenth thing',
  '',
  '=== app-five ===',
  '',
  '=== app-six ===',
  'queued:',
  '  ID-11  eleventh thing',
  '',
  'STALE CHECKOUTS, rows above may be out of date: app-two(3 behind)',
  '',
].join('\n')

const PRIORITY_OUT = [
  '',
  '=== app-one ===',
  'IN FLIGHT        1',
  '  ID-5     fifth thing  [executing]',
  '',
  'DO NOW           (u-hi  f-hi)         2',
  '  ID-1     first thing #u-hi #f-hi  #ship',
  '  ID-2     second thing #u-hi #f-hi',
  'URGENT, HARDER   (u-hi  f-mid|lo)     1',
  '  ID-3     third thing  [deadline]',
  'QUICK WINS       (u-lo|mid  f-hi)     2',
  '  ID-4     fourth thing',
  '  ID-12    twelfth thing',
  'THE REST         (other queued)       1',
  '  ID-6     sixth thing',
  '',
  '=== app-two [STALE: 3 behind upstream] ===',
  'DO NOW           (u-hi  f-hi)         1',
  '  ID-7     seventh thing',
  'URGENT, HARDER   (u-hi  f-mid|lo)     1',
  '  ID-8     eighth thing',
  'QUICK WINS       (u-lo|mid  f-hi)     1',
  '  ID-9     ninth thing',
  'THE REST         (other queued)       0',
  '',
].join('\n')

const SINGLE_BOARD = 'queued:\n  ID-1  first thing\nexecuting:\n  ID-2  second thing\n'

const runInput = (args: string) => ({
  command: 'board',
  args,
  origin: { kind: 'composer' as const },
  presentation: { isFullscreen: false, columns: 120 },
})

const mountPane = ($: Params[0], columns = 100) =>
  $.ui.mount({ plugin: 'board-pane', surface: 'terminal', component: 'Pane', props: paneProps(columns), requestId: 'board' })

type Options = {
  // Undefined: the registry file is unreadable.
  registry?: string
  allBoard?: string
  allExit?: number
  priority?: string
  priorityExit?: number
  singleExit?: number
  singleStderr?: string
  env?: Record<string, string>
}

const setup = async ($: Params[0], on: Params[1], options: Options = {}) => {
  const { registry, allBoard = ALL_BOARD, allExit = 0, priority = '', priorityExit = 0, singleExit = 0, singleStderr = '', env = {} } = options
  const argvs: string[][] = []
  // The priority call rides every refresh beside `all board`; tests of the pane's own runs count `argvs` only.
  const priorities: string[][] = []
  const reads: string[] = []
  const submitted: string[] = []
  const filled: string[] = []
  const closed: string[] = []
  const panes = [OPEN_PANE]
  const clock = mock.clock(on, { now: Date.UTC(2026, 0, 1, 10, 30) })
  mock.env(on, { DWARVES_KIT: '/opt/kit', HOME: '/home/dev', ...env })
  on('command.register', (_$, e) => ({ value: { command: e.name } }))
  on('session.start', (_$, e) => ({ cwd: e.cwd }))
  on('session.cwd', () => ({ value: '/work/app-two' }))
  on('fs.read', (_$, e) => {
    reads.push(e.path)
    if (registry === undefined) throw new Error('no such file')
    return { value: registry }
  })
  on('process.run', (_$, e) => {
    ;(e.argv[2] === 'priority' ? priorities : argvs).push([...e.argv])
    const done = (exitCode: number, stdout: string, stderr = '') => ({
      value: { exitCode, stdout, stderr, isStdoutTruncated: false, isStderrTruncated: false },
    })
    if (e.argv[1] === 'all' && e.argv[2] === 'priority') return done(priorityExit, priorityExit === 0 ? priority : '', priorityExit === 0 ? '' : 'board: priority failed')
    if (e.argv[1] === 'all') return done(allExit, allExit === 0 ? allBoard : '', allExit === 0 ? '' : 'board: all failed')
    if (e.argv[1] === 'board') return done(singleExit, singleExit === 0 ? SINGLE_BOARD : '', singleStderr)
    return done(1, '')
  })
  on('ui.open', () => ({ value: { isPlaced: true as const } }))
  on('ui.panes', () => ({ value: [...panes] }))
  on('ui.close', (_$, e) => {
    closed.push(e.id)
    return { value: undefined }
  })
  on('prompt.submit', (_$, e) => {
    submitted.push(e.text)
    return { text: e.text }
  })
  on('prompt.fill', (_$, e) => {
    filled.push(e.text)
    return { isFilled: true }
  })
  await $.session.start({ cwd: '/work/app-two', surface: 'terminal', isInteractive: true })
  priorities.length = 0
  argvs.length = 0 // session.start refreshes the summary band; these tests count the pane's own runs
  reads.length = 0
  return { argvs, priorities, reads, submitted, filled, closed, panes, clock }
}

test('/board runs `all board` over the registry in the session cwd', async ($, on) => {
  const { argvs, reads } = await setup($, on, { registry: REGISTRY })
  const ran = await $.command.run(runInput(''))
  expect(ran.text).toContain('Board pane opened')
  expect(reads).toEqual(['/work/app-two/_meta/boards.txt'])
  expect(argvs[0]).toEqual([
    '/opt/kit/bin/board', 'all', 'board', '--registry', '/work/app-two/_meta/boards.txt', '--repo-root', '/work/app-two',
  ])
})

test('BOARD_REGISTRY wins over the cwd registry, with ~ expanded', async ($, on) => {
  const { argvs, reads } = await setup($, on, { registry: REGISTRY, env: { BOARD_REGISTRY: '~/regs/boards.txt' } })
  await $.command.run(runInput(''))
  expect(reads).toEqual(['/home/dev/regs/boards.txt'])
  expect(argvs[0]?.slice(3, 5)).toEqual(['--registry', '/home/dev/regs/boards.txt'])
})

test('the overview groups repos by rail, leads with the current repo and totals the header', async ($, on) => {
  await setup($, on, { registry: REGISTRY })
  await $.command.run(runInput(''))
  const ui = await mountPane($)
  expect((await ui.find({ key: 'header' }))?.text).toBe('Board · 6 repos · 4 in flight · 5 queued')
  expect((await ui.find({ key: 'rail-WORK' }))?.text).toMatch(/^WORK/)
  expect(await ui.find({ key: 'rail-HOME' })).toBeDefined()
  expect(await ui.find({ key: 'rail-OTHER' })).toBeDefined()
  const current = await ui.find({ key: 'repo-app-two' })
  expect(current?.props).toMatchObject({
    plain: true,
    hotkey: '1',
    label: '◉ app-two    4 active  1 queued  ↓3  ID-7 seventh thing',
  })
  expect((await ui.find({ key: 'repo-app-one' }))?.props).toMatchObject({
    hotkey: '2',
    label: '  app-one    0 active  2 queued  ID-1 first thing',
  })
  expect((await ui.find({ key: 'repo-app-three' }))?.props).toMatchObject({ hotkey: '3' })
  expect((await ui.find({ key: 'repo-app-six' }))?.props).toMatchObject({ hotkey: '4' })
  await ui.unmount()
})

test('idle repos fold into one dim row at the end', async ($, on) => {
  await setup($, on, { registry: REGISTRY })
  await $.command.run(runInput(''))
  const ui = await mountPane($)
  expect((await ui.find({ key: 'idle' }))?.text).toBe('idle  app-four · app-five')
  expect(await ui.find({ key: 'repo-app-four' })).toBeUndefined()
  expect(await ui.find({ key: 'repo-app-five' })).toBeUndefined()
  await ui.unmount()
})

test('a narrow pane drops the trailing next-item column', async ($, on) => {
  await setup($, on, { registry: REGISTRY })
  await $.command.run(runInput(''))
  const ui = await mountPane($, 60)
  expect((await ui.find({ key: 'repo-app-two' }))?.props).toMatchObject({ label: '◉ app-two    4 active  1 queued  ↓3' })
  await ui.unmount()
})

test('pressing a repo opens its view and back returns to the overview', async ($, on) => {
  await setup($, on, { registry: REGISTRY })
  await $.command.run(runInput(''))
  const ui = await mountPane($)
  expect(await ui.find({ key: 'back' })).toBeUndefined()
  await ui.press({ key: 'repo-app-one' })
  expect((await ui.find({ key: 'repo-title' }))?.text).toBe('app-one')
  expect((await ui.find({ key: 'back' }))?.props).toMatchObject({ hotkey: 'b' })
  await ui.press({ key: 'back' })
  expect(await ui.find({ key: 'repo-title' })).toBeUndefined()
  expect(await ui.find({ key: 'header' })).toBeDefined()
  await ui.unmount()
})

test('the repo view shows the stale part, lists in-flight work first with glyphs and tones', async ($, on) => {
  await setup($, on, { registry: REGISTRY })
  await $.command.run(runInput('here'))
  const ui = await mountPane($)
  expect((await ui.find({ key: 'repo-title' }))?.text).toBe('app-two   ↓3 behind upstream')
  const labels = await Promise.all([1, 2, 3, 4, 5].map(async k => (await ui.find({ key: `item-${k}` }))?.props))
  // Whitespace is collapsed: the label pads the state word to the right edge.
  const text = labels.map(props => (typeof props?.label === 'string' ? props.label.replace(/\s+/g, ' ') : undefined))
  expect(text).toEqual([
    '▶ ID-7 seventh thing executing',
    '◆ ID-6 sixth thing validated',
    '◆ ID-5 fifth thing speccing',
    '● ID-4 fourth thing claimed',
    '○ ID-3 third thing',
  ])
  expect(labels.map(props => props?.hotkey)).toEqual(['1', '2', '3', '4', '5'])
  const tints = await ui.findAll({ type: 'Text', text: /^\* $/ })
  expect(tints.map(t => t.props)).toEqual([{ color: 'cyan' }, { color: 'magenta' }, { color: 'magenta' }, { color: 'yellow' }])
  await ui.unmount()
})

test('a narrow repo view drops the state word', async ($, on) => {
  await setup($, on, { registry: REGISTRY })
  await $.command.run(runInput('here'))
  const ui = await mountPane($, 60)
  expect((await ui.find({ key: 'item-1' }))?.props).toMatchObject({ label: '▶ ID-7  seventh thing' })
  await ui.unmount()
})

test('shipped, parked and dropped items stay hidden', async ($, on) => {
  await setup($, on, { registry: REGISTRY })
  await $.command.run(runInput('here'))
  const ui = await mountPane($)
  expect(await ui.find({ key: 'item-6' })).toBeUndefined()
  await ui.unmount()
})

test('queued shows eight, then + N more reveals the rest', async ($, on) => {
  const queued = Array.from({ length: 10 }, (_, k) => `  ID-${k + 1}  thing ${k + 1}`).join('\n')
  await setup($, on, { registry: REGISTRY, allBoard: `=== app-two ===\nqueued:\n${queued}\n` })
  await $.command.run(runInput('here'))
  const ui = await mountPane($)
  expect(await ui.find({ key: 'item-8' })).toBeDefined()
  expect(await ui.find({ key: 'item-9' })).toBeUndefined()
  expect((await ui.find({ key: 'more' }))?.props).toMatchObject({ label: '+ 2 more' })
  await ui.press({ key: 'more' })
  expect(await ui.find({ key: 'item-10' })).toBeDefined()
  expect(await ui.find({ key: 'more' })).toBeUndefined()
  await ui.unmount()
})

test('the filter narrows repos in the overview and items in a repo view', async ($, on) => {
  await setup($, on, { registry: REGISTRY })
  await $.command.run(runInput(''))
  const ui = await mountPane($)
  expect((await ui.find({ key: 'filter' }))?.props).toMatchObject({ placeholder: 'filter repos, IDs, titles' })
  await ui.input({ key: 'filter', text: 'ninth', kind: 'change' })
  expect(await ui.find({ key: 'repo-app-three' })).toBeDefined()
  expect(await ui.find({ key: 'repo-app-one' })).toBeUndefined()
  expect(await ui.find({ key: 'repo-app-two' })).toBeUndefined()
  await ui.input({ key: 'filter', text: '', kind: 'change' })
  await ui.press({ key: 'repo-app-two' })
  await ui.input({ key: 'filter', text: 'sixth', kind: 'change' })
  expect((await ui.find({ key: 'item-1' }))?.props).toMatchObject({ label: expect.stringContaining('ID-6') })
  expect(await ui.find({ key: 'item-2' })).toBeUndefined()
  await ui.unmount()
})

test('pressing an item fills the prompt, never submits', async ($, on) => {
  const { submitted, filled } = await setup($, on, { registry: REGISTRY })
  await $.command.run(runInput('here'))
  const ui = await mountPane($)
  await ui.press({ key: 'item-1' })
  expect(filled).toEqual(['Work on ID-7'])
  await ui.press({ key: 'back' })
  await ui.press({ key: 'repo-app-one' })
  await ui.press({ key: 'item-1' })
  expect(filled).toEqual(['Work on ID-7', 'Work on ID-1 in app-one'])
  expect(submitted).toEqual([])
  await ui.unmount()
})

test('/board <name> opens that repo, and an unknown name opens the overview', async ($, on) => {
  await setup($, on, { registry: REGISTRY })
  await $.command.run(runInput('app-three'))
  let ui = await mountPane($)
  expect((await ui.find({ key: 'repo-title' }))?.text).toBe('app-three')
  await ui.unmount()
  await $.command.run(runInput('nope'))
  ui = await mountPane($)
  expect(await ui.find({ key: 'repo-title' })).toBeUndefined()
  expect(await ui.find({ key: 'header' })).toBeDefined()
  await ui.unmount()
})

test('Refresh re-runs the same call and carries the r hotkey', async ($, on) => {
  const { argvs } = await setup($, on, { registry: REGISTRY })
  await $.command.run(runInput(''))
  const ui = await mountPane($)
  expect((await ui.find({ key: 'refresh' }))?.props).toMatchObject({ hotkey: 'r' })
  await ui.press({ key: 'refresh' })
  expect(argvs).toHaveLength(2)
  expect(argvs[1]).toEqual(argvs[0])
  await ui.unmount()
})

test('Close shuts the pane and carries the q hotkey', async ($, on) => {
  const { closed } = await setup($, on, { registry: REGISTRY })
  await $.command.run(runInput(''))
  const ui = await mountPane($)
  expect((await ui.find({ key: 'close' }))?.props).toMatchObject({ hotkey: 'q', role: 'dismiss' })
  await ui.press({ key: 'close' })
  expect(closed).toEqual(['board'])
  await ui.unmount()
})

test('the pane refreshes every 60s while open and stops once it closes', async ($, on) => {
  const { argvs, panes, clock } = await setup($, on, { registry: REGISTRY })
  await $.command.run(runInput(''))
  expect(argvs).toHaveLength(1)
  await clock.advance(60_000)
  expect(argvs).toHaveLength(2)
  panes.length = 0
  await clock.advance(60_000)
  await clock.advance(60_000)
  expect(argvs).toHaveLength(2)
})

test('without a registry the pane shows the session repo with a hint', async ($, on) => {
  const { argvs } = await setup($, on)
  await $.command.run(runInput(''))
  expect(argvs[0]).toEqual(['/opt/kit/bin/board', 'board', '--backlog-file', '/work/app-two/_meta/BACKLOG.md'])
  const ui = await mountPane($)
  expect(await ui.find({ type: 'Text', text: /^no registry: set BOARD_REGISTRY for the cross-repo view$/ })).toBeDefined()
  expect((await ui.find({ key: 'repo-title' }))?.text).toBe('app-two')
  expect(await ui.find({ key: 'back' })).toBeUndefined()
  expect((await ui.find({ key: 'item-1' }))?.props).toMatchObject({ label: expect.stringContaining('ID-2') })
  await ui.unmount()
})

test('a failing `all board` falls back to the session repo', async ($, on) => {
  const { argvs } = await setup($, on, { registry: REGISTRY, allExit: 1 })
  await $.command.run(runInput(''))
  expect(argvs.map(argv => argv[1])).toEqual(['all', 'board'])
  const ui = await mountPane($)
  expect(await ui.find({ type: 'Text', text: /^no registry/ })).toBeDefined()
  await ui.unmount()
})

test('a failing fallback shows stderr dimmed', async ($, on) => {
  await setup($, on, { singleExit: 1, singleStderr: 'board: no BACKLOG.md at /work/app-two/_meta/BACKLOG.md\n' })
  const ran = await $.command.run(runInput(''))
  expect(ran.text).toContain('Board pane opened')
  const ui = await mountPane($)
  const hit = await ui.find({ type: 'Text', text: /no BACKLOG\.md/ })
  expect(hit?.props).toMatchObject({ dimColor: true })
  await ui.unmount()
})

test('registry rows parse names, paths and a rail in any column', () => {
  expect(parseRegistry(REGISTRY, '/home/dev')).toEqual([
    { name: 'app-one', path: '/work/app-one/_meta/BACKLOG.md', rail: 'work' },
    { name: 'app-two', path: '/work/app-two/_meta/BACKLOG.md', rail: 'work' },
    { name: 'app-three', path: '/work/app-three/_meta/BACKLOG.md', rail: 'home' },
    { name: 'app-four', path: '/home/dev/app-four/_meta/BACKLOG.md', rail: undefined },
    { name: 'app-five', path: '/work/app-five/_meta/BACKLOG.md', rail: 'home' },
    { name: 'app-six', path: '/work/app-six/_meta/BACKLOG.md', rail: undefined },
  ])
  expect(parseRegistry('app-x rail=home /x/_meta/BACKLOG.md', undefined)[0]?.rail).toBe('home')
})

test('`all board` output parses into repos with stale counts and items by state', () => {
  const repos = parseAllBoard(ALL_BOARD)
  expect(repos.map(repo => [repo.name, repo.behind, repo.items.length])).toEqual([
    ['app-one', 0, 2],
    ['app-two', 3, 6],
    ['app-three', 0, 1],
    ['app-four', 0, 1],
    ['app-five', 0, 0],
    ['app-six', 0, 1],
  ])
  expect(repos[1]?.items[3]).toEqual({ id: 'ID-6', title: 'sixth thing', state: 'validated' })
  expect(parseSingleBoard(SINGLE_BOARD, 'solo').items.map(item => item.state)).toEqual(['queued', 'executing'])
})

test('the current repo is the one whose BACKLOG sits under cwd or whose root is cwd', () => {
  const registry = parseRegistry(REGISTRY, '/home/dev')
  const parsed = parseAllBoard(ALL_BOARD)
  expect(mergeRepos(parsed, registry, '/work/app-two').filter(repo => repo.isCurrent).map(repo => repo.name)).toEqual(['app-two'])
  expect(mergeRepos(parsed, registry, '/work/app-two/sub').filter(repo => repo.isCurrent)).toEqual([])
  expect(mergeRepos(parsed, registry, '/work').filter(repo => repo.isCurrent).map(repo => repo.name)).toEqual([
    'app-one', 'app-two', 'app-three', 'app-five', 'app-six',
  ])
})

test('the overview builder groups, orders and folds idle repos', () => {
  const repos = mergeRepos(parseAllBoard(ALL_BOARD), parseRegistry(REGISTRY, '/home/dev'), '/work/app-two')
  const overview = buildOverview(repos, '')
  expect(overview.groups.map(group => [group.rail, group.repos.map(repo => repo.name)])).toEqual([
    ['WORK', ['app-two', 'app-one']],
    ['HOME', ['app-three']],
    ['OTHER', ['app-six']],
  ])
  expect(overview.idle).toEqual(['app-four', 'app-five'])
  expect(buildOverview(repos, 'home').groups.map(group => group.rail)).toEqual(['HOME'])
})

const NEXT_ORDER = [
  '! ID-1 first thing  app-one',
  '! ID-2 second thing  app-one',
  '! ID-7 seventh thing  app-two',
  '▲ ID-3 third thing  app-one',
  '▲ ID-8 eighth thing  app-two',
]

test('NEXT runs the priority view beside `all board`', async ($, on) => {
  const { priorities } = await setup($, on, { registry: REGISTRY, priority: PRIORITY_OUT })
  await $.command.run(runInput(''))
  expect(priorities[0]).toEqual([
    '/opt/kit/bin/board', 'all', 'priority', 'overview', '--registry', '/work/app-two/_meta/boards.txt', '--repo-root', '/work/app-two',
  ])
})

test('NEXT lists DO NOW, then URGENT, then QUICK WINS, capped at five, above the repos', async ($, on) => {
  await setup($, on, { registry: REGISTRY, priority: PRIORITY_OUT })
  await $.command.run(runInput(''))
  const ui = await mountPane($)
  expect((await ui.find({ key: 'next' }))?.text).toMatch(/^NEXT/)
  const labels = await Promise.all([1, 2, 3, 4, 5].map(async k => (await ui.find({ key: `next-${k}` }))?.props))
  expect(labels.map(props => props?.label)).toEqual(NEXT_ORDER)
  expect(labels.map(props => props?.hotkey)).toEqual(['1', '2', '3', '4', '5'])
  expect(await ui.find({ key: 'next-6' })).toBeUndefined()
  await ui.unmount()
})

test('NEXT rows take the first hotkeys and the repo rows follow in order', async ($, on) => {
  await setup($, on, { registry: REGISTRY, priority: PRIORITY_OUT })
  await $.command.run(runInput(''))
  const ui = await mountPane($)
  expect((await ui.find({ key: 'repo-app-two' }))?.props).toMatchObject({ hotkey: '6' })
  expect((await ui.find({ key: 'repo-app-one' }))?.props).toMatchObject({ hotkey: '7' })
  expect((await ui.find({ key: 'repo-app-three' }))?.props).toMatchObject({ hotkey: '8' })
  expect((await ui.find({ key: 'repo-app-six' }))?.props).toMatchObject({ hotkey: '9' })
  await ui.unmount()
})

test('pressing a NEXT row fills the prompt, with the repo named unless it is the current one, never submits', async ($, on) => {
  const { filled, submitted } = await setup($, on, { registry: REGISTRY, priority: PRIORITY_OUT })
  await $.command.run(runInput(''))
  const ui = await mountPane($)
  await ui.press({ key: 'next-1' })
  await ui.press({ key: 'next-3' })
  expect(filled).toEqual(['Work on ID-1 in app-one', 'Work on ID-7'])
  expect(submitted).toEqual([])
  await ui.unmount()
})

test('NEXT is hidden when the priority view has no rows', async ($, on) => {
  await setup($, on, { registry: REGISTRY, priority: 'DO NOW  0\n' })
  await $.command.run(runInput(''))
  const ui = await mountPane($)
  expect(await ui.find({ key: 'next' })).toBeUndefined()
  expect(await ui.find({ key: 'repo-app-two' })).toBeDefined()
  await ui.unmount()
})

test('a failing priority view keeps the pane, minus NEXT', async ($, on) => {
  await setup($, on, { registry: REGISTRY, priority: PRIORITY_OUT, priorityExit: 1 })
  await $.command.run(runInput(''))
  const ui = await mountPane($)
  expect(await ui.find({ key: 'next' })).toBeUndefined()
  expect((await ui.find({ key: 'header' }))?.text).toBe('Board · 6 repos · 4 in flight · 5 queued')
  expect((await ui.find({ key: 'repo-app-two' }))?.props).toMatchObject({ hotkey: '1' })
  await ui.unmount()
})

test('the filter narrows NEXT too', async ($, on) => {
  await setup($, on, { registry: REGISTRY, priority: PRIORITY_OUT })
  await $.command.run(runInput(''))
  const ui = await mountPane($)
  await ui.input({ key: 'filter', text: 'eighth', kind: 'change' })
  expect((await ui.find({ key: 'next-1' }))?.props).toMatchObject({ label: '▲ ID-8 eighth thing  app-two' })
  expect(await ui.find({ key: 'next-2' })).toBeUndefined()
  await ui.unmount()
})
