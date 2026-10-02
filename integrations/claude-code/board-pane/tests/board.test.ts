import { expect, test } from 'claude-code/testing'
import type { TestBody } from 'claude-code/testing'

type Params = Parameters<TestBody>

const PANE = {
  title: 'Board',
  isFocused: false,
  bodyColumns: 100,
  placement: 'dock' as const,
  scroll: { offset: 0, bodyRows: 30 },
  view: {},
}

const runInput = (args: string) => ({
  command: 'board',
  args,
  origin: { kind: 'composer' as const },
  presentation: { isFullscreen: false, columns: 120 },
})

const setup = async (
  $: Params[0],
  on: Params[1],
  result: { exitCode: number; stdout: string; stderr: string },
) => {
  const argvs: string[][] = []
  on('command.register', (_$, e) => ({ value: { command: e.name } }))
  on('session.start', (_$, e) => ({ cwd: e.cwd }))
  on('session.cwd', () => ({ value: '/work/app-one' }))
  on('env.get', (_$, e) => ({ value: e.name === 'DWARVES_KIT' ? '/opt/kit' : undefined }))
  on('process.run', (_$, e) => {
    argvs.push([...e.argv])
    return { value: { ...result, isStdoutTruncated: false, isStderrTruncated: false } }
  })
  on('ui.open', () => ({ value: { isPlaced: true as const } }))
  await $.session.start({ cwd: '/work/app-one', surface: 'terminal', isInteractive: true })
  return argvs
}

test('/board runs the single-repo render in the session cwd', async ($, on) => {
  const argvs = await setup($, on, { exitCode: 0, stdout: 'app-one ID-1\n', stderr: '' })
  const ran = await $.command.run(runInput(''))
  expect(ran.text).toContain('Board pane opened')
  expect(argvs[0]?.slice(1)).toEqual(['board', '--backlog-file', '/work/app-one/_meta/BACKLOG.md'])
  const ui = await $.ui.mount({ plugin: 'board-pane', surface: 'terminal', component: 'Pane', props: PANE, requestId: 'board' })
  expect((await ui.find({ type: 'Text', text: /app-one ID-1/ }))?.props).toMatchObject({ dimColor: false })
  await ui.unmount()
  expect(argvs[0]?.[0]).toBe('/opt/kit/bin/board')
})

test('/board all runs the registry view with --repo-root', async ($, on) => {
  const argvs = await setup($, on, { exitCode: 0, stdout: 'app-one ID-1\n', stderr: '' })
  await $.command.run(runInput('all'))
  expect(argvs[0]?.slice(1)).toEqual(['all', 'next', '--repo-root', '/work/app-one'])
})

test('a non-zero exit shows stderr dimmed in the pane', async ($, on) => {
  await setup($, on, { exitCode: 1, stdout: '', stderr: 'board: no BACKLOG.md at /work/app-one/_meta/BACKLOG.md\n' })
  const ran = await $.command.run(runInput(''))
  expect(ran.text).toContain('Board pane opened')
  const ui = await $.ui.mount({ plugin: 'board-pane', surface: 'terminal', component: 'Pane', props: PANE, requestId: 'board' })
  const hit = await ui.find({ type: 'Text', text: /no BACKLOG\.md/ })
  expect(hit?.props).toMatchObject({ dimColor: true })
  await ui.unmount()
})

test('Refresh re-runs the same mode', async ($, on) => {
  const argvs = await setup($, on, { exitCode: 0, stdout: 'app-one ID-1\n', stderr: '' })
  await $.command.run(runInput('all'))
  const ui = await $.ui.mount({ plugin: 'board-pane', surface: 'terminal', component: 'Pane', props: PANE, requestId: 'board' })
  await ui.press({ key: 'refresh' })
  expect(argvs).toHaveLength(2)
  expect(argvs[1]?.slice(1)).toEqual(['all', 'next', '--repo-root', '/work/app-one'])
  await ui.unmount()
})
