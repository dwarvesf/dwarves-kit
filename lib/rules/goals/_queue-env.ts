// A throwaway overnight-queue environment, the one tests/test-runaway-guards.sh builds: KIT_LEDGER_DIR in a temp
// dir, the shipped fake mux (tests/fixtures/queue/fake-mux) behind MUX_CMD with a per-slug `.during` hook, a board
// repo with one `#auto` row (slug fixboard__ID-001), a separate run repo, `gh` stubbed to fail, and a `date` stub that
// answers `date +%s` from FAKE_NOW.
import {existsSync, mkdirSync, readFileSync, writeFileSync} from 'node:fs'
import {join} from 'node:path'
import {git, initRepo, KIT, lib, sh, stub} from './_bridge.ts'

export const SLUG = 'fixboard__ID-001'

export function queueEnv(work: string, knobs: Record<string, string> = {}) {
  const qstub = join(work, 'stub'), bin = join(work, 'bin')
  const ledger = join(work, 'ledger'), runDir = join(ledger, 'queue-runs'), journal = join(work, 'journal.tsv')
  mkdirSync(qstub, {recursive: true}); mkdirSync(bin, {recursive: true}); mkdirSync(runDir, {recursive: true}); writeFileSync(journal, '')
  stub(bin, 'gh', 'exit 1')
  stub(bin, 'date', 'if [ "$*" = "+%s" ] && [ -n "${FAKE_NOW:-}" ]; then echo "$FAKE_NOW"; else exec /bin/date "$@"; fi')
  const mux = stub(work, 'mux', `if [ "\${1:-}" = capture-pane ]; then\n  for a in "$@"; do case "$a" in *:*) s="\${a##*:}" ;; esac; done\n  [ -n "\${s:-}" ] && [ -f "$QSTUB/$s.during" ] && . "$QSTUB/$s.during"\nfi\nexec "${KIT}/tests/fixtures/queue/fake-mux" "$@"`)
  const board = join(work, 'fixboard'), repo = join(work, 'run')
  mkdirSync(join(board, '_meta/megagoals/pilot'), {recursive: true})
  writeFileSync(join(board, '_meta/megagoals/pilot/POINTER_PROMPT.md'), 'pointer body\n')
  writeFileSync(join(board, '_meta/BACKLOG.md'), '# Backlog\n\n| ID | Item | Notes & source | Status |\n|---|---|---|---|\n| ID-001 | auto + pointer | pilot row #auto #queue{repo=fixboard,pointer=_meta/megagoals/pilot/POINTER_PROMPT.md} | queued |\n')
  initRepo(repo)
  const pointer = join(work, 'p.txt'); writeFileSync(pointer, 'p\n')
  const verbs = join(qstub, 'verbs.log'); writeFileSync(verbs, '')
  const env = (extra: Record<string, string> = {}) => ({
    KIT_LEDGER_DIR: ledger, QUEUE_JOURNAL: journal, MUX_CMD: mux, TERMINAL_MUX: 'tmux', QSTUB: qstub, QLOG: verbs,
    QUEUE_POLL_SECS: '0', QUEUE_TIMEOUT_SECS: '0', QUEUE_RETRY_SLEEP_SECS: '0', QUEUE_STARTUP_SECS: '0', QUEUE_SUBMIT_SETTLE_SECS: '0',
    QUEUE_BEAT_STALE_SECS: '1000000000000', QUEUE_BEAT_DEAD_SECS: '1000000000000',
    PATH: `${bin}:${process.env.PATH}`, ...knobs, ...extra,
  })
  const watch = (extra: Record<string, string> = {}) => sh('bash', [lib('queue/watch-board.sh'), '--board', join(board, '_meta/BACKLOG.md'),
    '--repo-root', board, '--repo-name', 'fixboard', '--journal', journal], {env: {...env(extra), WATCH_QUEUE_CMD: 'true'}})
  const run = (rows: string[][], extra: Record<string, string> = {}, flags: string[] = []) => {
    const tsv = join(work, 'q.tsv'); writeFileSync(tsv, rows.map(r => r.join('\t')).join('\n') + '\n')
    return sh('bash', [lib('queue/queue.sh'), 'run', tsv, ...flags], {env: env(extra)})
  }
  const journalRows = (slug?: string) => readFileSync(journal, 'utf8').split('\n').filter(Boolean).map(l => l.split('\t'))
    .filter(r => slug === undefined || r[1] === slug)
  const windows = () => readFileSync(verbs, 'utf8').split('\n').filter(l => l.startsWith('new-window')).map(l => l.slice('new-window slug='.length))
  const beat = (slug = SLUG) => existsSync(join(runDir, `${slug}.beat`))
  return {qstub, runDir, journal, board, repo, pointer, verbs, env, watch, run, journalRows, windows, beat, head: () => git(repo, 'rev-parse', 'HEAD')}
}
