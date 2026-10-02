import { expect, test } from 'claude-code/testing'

import {
  STALE_DAYS,
  countStaleWorktrees,
  detachedHeads,
  nextPrompt,
  parseDefaultBranch,
  parseNext,
  parseRefAges,
  parseRefList,
  parseWorktrees,
  rankNext,
} from '../hooks/parse'

const DAY = 86_400
const NOW_S = 100 * DAY
const NOW_MS = NOW_S * 1000

const porcelain = (...entries: string[][]) => entries.map(lines => lines.join('\n')).join('\n\n') + '\n'
const MAIN = ['worktree /w/app', 'HEAD a1', 'branch refs/heads/main']
const linked = (name: string, branch?: string, head = name) => [`worktree /w/app/.claude/worktrees/${name}`, `HEAD ${head}`, branch ? `branch refs/heads/${branch}` : 'detached']

test('porcelain parses into path, head and branch, skipping bare entries', () => {
  expect(parseWorktrees(porcelain(MAIN, linked('x', 'feat/x', 'b2'), ['worktree /w/bare.git', 'bare']))).toEqual([
    { path: '/w/app', head: 'a1', branch: 'main' },
    { path: '/w/app/.claude/worktrees/x', head: 'b2', branch: 'feat/x' },
  ])
})

test('the main checkout is never counted, even when it is merged and old', () => {
  const merged = ['main']
  const ages = new Map([['main', NOW_S - 90 * DAY]])
  expect(countStaleWorktrees(porcelain(MAIN), merged, ages, new Map(), NOW_MS)).toBe(0)
})

test('a branch merged into the default branch is stale however fresh its tip', () => {
  const ages = new Map([['feat/x', NOW_S - DAY]])
  expect(countStaleWorktrees(porcelain(MAIN, linked('x', 'feat/x')), ['feat/x'], ages, new Map(), NOW_MS)).toBe(1)
})

test('an unmerged branch is stale only past the age limit', () => {
  const ages = new Map([
    ['feat/old', NOW_S - (STALE_DAYS + 1) * DAY],
    ['feat/edge', NOW_S - STALE_DAYS * DAY],
    ['feat/new', NOW_S - DAY],
  ])
  const out = porcelain(MAIN, linked('old', 'feat/old'), linked('edge', 'feat/edge'), linked('new', 'feat/new'))
  expect(countStaleWorktrees(out, [], ages, new Map(), NOW_MS)).toBe(1)
})

test('a detached worktree counts by its HEAD commit age only', () => {
  const out = porcelain(MAIN, linked('loose-old', undefined, 'o1'), linked('loose-new', undefined, 'n1'), linked('loose-unknown', undefined, 'u1'))
  const detached = new Map([
    ['o1', NOW_S - 30 * DAY],
    ['n1', NOW_S - DAY],
  ])
  expect(detachedHeads(out)).toEqual(['o1', 'n1', 'u1'])
  expect(countStaleWorktrees(out, ['o1', 'n1'], new Map(), detached, NOW_MS)).toBe(1)
})

test('a branch with no known tip age and no merge is not stale', () => {
  expect(countStaleWorktrees(porcelain(MAIN, linked('x', 'feat/x')), [], new Map(), new Map(), NOW_MS)).toBe(0)
})

test('git output parsers', () => {
  expect(parseDefaultBranch('origin/main\n')).toBe('main')
  expect(parseDefaultBranch('origin/release/1\n')).toBe('release/1')
  expect(parseDefaultBranch('')).toBeUndefined()
  expect(parseDefaultBranch('HEAD\n')).toBeUndefined()
  expect(parseRefList('main\n feat/x \n\n')).toEqual(['main', 'feat/x'])
  expect([...parseRefAges('main 100\nfeat/x 200\nbroken\n')]).toEqual([
    ['main', 100],
    ['feat/x', 200],
  ])
})

const PRIORITY = [
  '=== app-one ===',
  'IN FLIGHT        1',
  '  ID-5     fifth thing  [executing]',
  'DO NOW           (u-hi  f-hi)         1',
  '  ID-1     first thing #u-hi #f-hi  #ship  [deadline]',
  'URGENT, HARDER   (u-hi  f-mid|lo)     1',
  '  ID-2     second thing',
  'QUICK WINS       (u-lo|mid  f-hi)     1',
  '  ID-3     third thing',
  'THE REST         (other queued)       1',
  '  ID-4     fourth thing',
  '(1 queued row(s) missing #u/#f -- classify them)',
  '',
  '=== app-two [STALE: 2 behind upstream] ===',
  'DO NOW           (u-hi  f-hi)         1',
  '  AT-1     other thing',
  '',
].join('\n')

test('the priority view parses into ranked picks and drops in-flight and the rest', () => {
  const rows = parseNext(PRIORITY)
  expect(rows).toEqual([
    { kind: 'now', id: 'ID-1', title: 'first thing', repo: 'app-one' },
    { kind: 'urgent', id: 'ID-2', title: 'second thing', repo: 'app-one' },
    { kind: 'quick', id: 'ID-3', title: 'third thing', repo: 'app-one' },
    { kind: 'now', id: 'AT-1', title: 'other thing', repo: 'app-two' },
  ])
  expect(rankNext(rows, '').map(row => row.id)).toEqual(['ID-1', 'AT-1', 'ID-2', 'ID-3'])
})

test('rankNext caps at five and the prompt names the repo only when it is not the current one', () => {
  const many = Array.from({ length: 8 }, (_, k) => ({ kind: 'now' as const, id: `ID-${k + 1}`, title: `t${k + 1}`, repo: 'app-one' }))
  expect(rankNext(many, '')).toHaveLength(5)
  const first = { kind: 'now' as const, id: 'ID-1', title: 't1', repo: 'app-one' }
  const away = { name: 'app-one', isCurrent: false, behind: 0, items: [] }
  expect(nextPrompt(first, [away])).toBe('Work on ID-1 in app-one')
  expect(nextPrompt(first, [{ ...away, isCurrent: true }])).toBe('Work on ID-1')
})
