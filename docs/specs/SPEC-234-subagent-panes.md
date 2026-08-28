# Spec: subagent panes (read-only jsonl-tail panes for subagent-delegate waves)
Generated: 2026-08-28
Status: VALIDATED
Lane: full

## Problem

The kit has two mega-goal run modes with pane visibility and one without. DELEGATE
(`claude -p` via `orchestrate.sh run`) gets full tmux panes (SPEC-119: watch + `send-keys`
intervene) plus viewer push (SPEC-121). The DEFAULT mode -- the conductor dispatching
sub-goals as parallel background SUBAGENTS per `commands/mega.md` "Run mode" -- gets task
notifications and gate-ledger progress strips only. The operator cannot watch a subagent
work; the transcript exists (each background subagent writes a live JSONL to
`~/.claude/projects/<slug>/<session>/subagents/agent-<id>.jsonl`, verified on the
2026-07-03 probe) but nothing renders it.

Operator decision 2026-07-03 (orchestrate-hardening `NOTES.md` event log, 18:25 entry, NOT
proposed-additions item 9 which became SPEC-121): subagent workers get READ-ONLY panes --
a pane tailing the transcript through a small jq formatter gives watch-only visibility;
intervention routes through the conductor (SendMessage), never the pane. Backlogged as
ops-toolkit ID-272; Han re-confirmed the pickup 2026-08-28.

## Design

### Approaches considered

1. **Hook `_wave_run` to spawn tail panes.** Dead end: `_wave_run` only executes under
   DELEGATE mode. Subagent-delegate dispatch happens inside the conductor's live Claude
   Code session via the Agent tool; `orchestrate.sh` never sees it. There is no dispatch
   loop to hook.
2. **A watcher daemon polling the subagents dir.** Rejected: a daemon for a display
   affordance violates minimum-infra; the conductor already knows when it dispatches a
   worker and can invoke a one-shot command at that moment.
3. **One-shot subcommand the conductor shells out to (CHOSEN).** A new public
   `orchestrate.sh panes <megadir> <target>...` spawns one read-only tmux window per
   transcript, each running `tail -F | jq` via a hidden re-entry subcommand (the
   SPEC-119 `_pane-exec` pattern: tmux cannot express a pipe as exec-direct argv, so the
   pane re-enters our own script, which builds the pipe internally from argv tokens --
   no shell string ever re-parsed). Idempotent: re-invoking for the same transcript
   pre-cleans and respawns its window, so the conductor may call it per worker or per
   wave without bookkeeping.

### Chosen approach

Two subcommands in `lib/queue/orchestrate.sh` plus one jq program file:

- **`cmd_panes` (public: `orchestrate.sh panes <megadir> <target>...`).** Each `<target>`
  after `<megadir>` is one of (validate-findings 2/12: the conductor cannot name
  `agent-<id>` paths at dispatch time, so bare paths alone make the feature unreachable):
  - a jsonl file path -- used directly;
  - a directory -- expands to its `agent-*.jsonl` members (empty dir: warning, move on);
  - `--latest` -- derives the conductor's own subagents dir: slugify `$PWD` the way the
    harness names project dirs (`/` and `.` -> `-`), pick the newest-mtime
    `~/.claude/projects/<slug>/*/subagents` directory, expand as above (DEC-007; the
    derivation is a pure helper, testable under a fake `$HOME`).

  For each resolved transcript: skip with a stderr warning unless it is a readable
  regular file whose basename matches `agent-*.jsonl` (an unexpanded-glob literal like
  `agent-*.jsonl` therefore also skips cleanly); normalize the path to absolute before
  any argv is built (a leading-dash path must never reach another command's arg parser);
  derive the window name from the basename (`agent-<id>.jsonl` -> `sa-<id>`, sanitized
  through the `_mux_session_name` charset); ensure the shared per-megagoal tmux session
  exists (same `has-session || new-session -d` dance as `_pane_spawn`); `kill-window`
  the name best-effort (idempotent respawn); `new-window -d` with exec-direct argv
  re-entering `orchestrate.sh _pane-tail <jsonl> <formatter>`. The formatter path is
  resolved from `$PANE_TAIL_JQ` HERE and passed as an argv token (validate-finding 3:
  exported env does not cross the tmux server boundary; an env-only seam would be a
  false-green in direct-call tests). `_viewer_open <megadir>` is called ONLY when this
  invocation created the session (`has-session` failed) -- `_VIEWER_OPENED` is
  process-local and every `panes` call is a fresh process, so the SPEC-121 once-per-run
  guard cannot dedupe across calls (validate-finding 4).

  **rc contract: always 0** (validate-finding 6). Skips and tmux failures warn on stderr
  and are counted in a final `[panes] spawned N, skipped M` summary line; the most common
  real case (transcript not yet written by a just-dispatched subagent) must not read as a
  failure to an LLM conductor. A pane is a visibility affordance; nothing downstream may
  fail on it (SPEC-121 DEC-003 stance).
- **`cmd_pane_tail` (hidden: `orchestrate.sh _pane-tail <jsonl> <formatter>`).** Refuses
  (exit 64, stderr) unless: the jsonl is a readable regular file, NOT a symlink, basename
  matching `agent-*.jsonl` (re-checked here, not only in `cmd_panes` -- the re-entry
  subcommand must not be repurposable to tail arbitrary files); the formatter is a
  readable file (a missing formatter otherwise dies as a bare jq usage error). Note: tmux
  closes a window whose command exits, so a refusal is invisible in the pane itself; the
  `cmd_panes`-side checks are the operator-visible gate, this one is defense-in-depth.
  Then prints a
  `[panes] tailing <basename> -- read-only; steer via the conductor (SendMessage)` header
  and runs `tail -n 200 -F -- "$jsonl" | jq -R -r --unbuffered "$PROGRAM"` where the
  program is loaded from the formatter file. `-n 200` not `-n +1`: idempotent respawns
  would replay an entire long transcript into a fresh pane (validate-finding 9). `-R` is
  load-bearing (validate-finding 1, BLOCKING): jq's own input parser aborts the whole
  process on a malformed/truncated line (verified: rc=5, later valid lines never render),
  and `tail -F` can deliver a half-written append; raw mode + `fromjson? // empty` in the
  program makes bad lines render nothing instead of killing the pipe.
- **`lib/queue/pane-tail.jq`.** A lossy-but-readable line formatter for the subagent
  transcript schema (per the 2026-07-02 process-audit notes: assistant messages span
  multiple lines sharing `message.id`, content blocks typed `text`/`tool_use`/
  `tool_result`, attachment lines for system-reminders). First line of the program:
  `fromjson? // empty |`. Renders assistant text verbatim, tool_use as one
  `-> <name> <compact-input-prefix>` line, tool_result as one `<- result (<n> chars)`
  line (count-only is a DELIBERATE data-exposure control -- tool results carry file
  contents and command output; a richer substitute formatter must not regress this
  silently), drops attachments and unknown types via `empty`. Every emitted string
  passes, LAST at the emit site (so a future field addition cannot bypass it), through:
  - a control-character strip `def viz: gsub("[\\u0000-\\u0008\\u000b-\\u001f\\u007f-\\u009f]"; "");`
    (security H1: transcript content is model-generated; a JSON `\u001b` becomes a real
    ESC byte under `jq -r`, and OSC 52 clipboard writes / title sets / DCS passthrough
    would reach the operator's real terminal through tmux). Tab and newline survive;
  - a length cap (`.[0:2000]` + a `...[truncated]` marker) so a single multi-MB line
    cannot wedge the pane (security M2).

**Read-only by construction:** the window's process tree is `tail | jq` -- there is no
shell and no REPL to type into; stray keys are inert. No `send-keys` helper is added for
`sa-*` windows, and none of the existing helpers target them.

### Security (non-negotiable, the SPEC-119 #143 pattern)

- Every tmux/viewer invocation is exec-direct argv (`--` separated tokens), never a
  joined string. The jsonl path -- treat the whole path as untrusted -- is passed as a
  single argv token end to end, absolute-normalized, and never interpolated into a shell
  string or jq program text (the program is a file; the transcript is stdin data).
- Transcript CONTENT is the one genuinely untrusted input reaching a sink (the
  operator's terminal); the formatter's `viz` strip + length cap are the render-side
  counterpart of #143's shell-side rule. Substituting `PANE_TAIL_JQ` disables both --
  the strip is a property of the shipped formatter, not the pipe; the seam doc says so.
- Window names are charset-gated to `[A-Za-z0-9_-]` by construction (tr -c sanitize of
  the basename-derived id). The SESSION name is not derived here: an operator-set
  `$TMUX_SESSION` passes through `_mux_session_name` unsanitized (pre-existing SPEC-119
  shape). `cmd_panes` never places `$mux` in a string context -- argv positions only --
  and the viewer sinks are covered by `_viewer_open`'s existing charset re-gate
  (security M3; pinned by a test).
- `_pane-tail` refuses non-regular files, symlinks, and non-`agent-*.jsonl` basenames
  (security L4: `[ -f ]` follows symlinks; a link named `agent-x.jsonl` at a private key
  is not a real exfil channel -- it renders to the operator's own screen -- but the
  defense costs two lines).

### Seams

`TMUX_CMD` (existing) mocks tmux; `VIEWER_CMD`/`PANE_VIEWER` (existing) govern push.
`PANE_TAIL_JQ` (new, default `$ORCH_DIR/pane-tail.jq`) is resolved by `cmd_panes` and
handed to the pane as an argv token (see above; not an env read inside the pane). No new
config keys: the feature activates only when the conductor invokes `panes`, so there is
nothing to toggle.

## After state

The conductor (mega.md Run mode, subagent-delegate default) MAY, after dispatching
background subagents, run `bash lib/queue/orchestrate.sh panes <megadir> --latest` (or
pass the subagents dir / explicit paths) to grow one read-only tmux window per worker
under the megagoal's `orch-<slug>` session. The operator attaches with
`tmux attach -t orch-<slug>` (pull); SPEC-121 push fires when the session is newly
created AND a viewer resolves -- under the conductor's Bash tool stderr is not a TTY, so
`PANE_VIEWER=auto` correctly degrades to pull there, and an operator who wants push from
a headless invocation sets an explicit `PANE_VIEWER=<name>` (DEC-005 intent rule;
validate-finding 5 -- the spec does not claim push works headless). Watching a subagent
is read-only; steering still routes through the conductor.

## Test plan

`tests/test-subagent-panes.sh`, sourcing orchestrate.sh with a `TMUX_CMD` mock (the
`test-pane-viewer.sh` template: poisoned-mock negative controls, security-pin argv
assertions). Proportionate budget (validate-finding 11): the real-tmux behavioral run
lives in Verification, not here.

| # | Category | Case |
|---|---|---|
| T1 | unit | 2 fixture transcripts -> 2 `sa-<id>` windows, session ensured once; re-invoke -> `kill-window` precedes each respawn (idempotence) |
| T2 | security-pin | `new-window` argv: `--` present, re-entry tokens separate argv items, jsonl + formatter paths absolute, never a joined string |
| T3 | unit | skip behavior: missing file, wrong basename, unexpanded `agent-*.jsonl` literal, empty dir -> warnings + summary line, rc=0, valid siblings still spawn; `<2` args -> usage on stderr, rc=0 |
| T4 | unit | directory target expands to members; `--latest` derives slug+newest-mtime under a fake `$HOME` (DEC-007) |
| T5 | negative | `_pane-tail` refusals, each exit 64 + named stderr: directory, unreadable, symlink, wrong basename, missing formatter |
| T6 | formatter | fixture drives: assistant text verbatim, `->`/`<-` lines, attachment dropped, malformed line + truncated-JSON line survived (later lines still render), ESC/OSC-52 bytes stripped (assert exact output), >2000-char line capped with `…[truncated]` (multi-MB shares the code path) |
| T7 | integration | viewer: `_viewer_open` fires only on session creation (second `panes` call: no viewer exec); `TMUX_SESSION='a b; touch pwned'` -> tmux argv tokens stay separate, `_viewer_open` refuses via its charset gate, rc still 0 |

## Verification

```
bash tests/test-subagent-panes.sh
bash tests/test-multiplexer.sh && bash tests/test-pane-viewer.sh \
  && bash tests/test-orchestrate.sh && bash tests/test-orchestrate-wavefront.sh \
  && bash tests/test-orchestrate-hardening.sh && bash tests/test-docs-wiring.sh
shellcheck -S error lib/queue/orchestrate.sh tests/test-subagent-panes.sh
```

Plus (behavioral, primary-flow): one REAL run against a live fixture transcript in a real
tmux server -- spawn, `capture-pane -p` shows the header + formatted output, append a line
to the fixture, capture again shows it (the `-F` follow property) -- recorded in
`docs/verification/subagent-panes.md` with a negative control (revert the formatter
wiring -> RED -> restore). Visual-first: the `capture-pane -p` text capture IS the visible
surface and is the committed artifact.

## Edge cases

- Transcript not yet created when the conductor calls `panes`: skipped with a warning,
  rc=0; the conductor re-invokes (idempotent). NOT handled by waiting -- no daemon, no
  sleep loops.
- `tail -F` survives rotation/truncation; a transcript that stops growing goes quiet
  (pane shows recent history; harmless). The tail processes THEMSELVES outlive the
  megagoal until the operator kills the `orch-<slug>` session -- killing the session
  reaps every `sa-*` window and its `tail|jq` pipe; documented as the cleanup path
  (accepted leak until then; no reaper built).
- Lossy sanitize collision (`agent-a!b` / `agent-a?b` -> same `sa-a-b` window): accepted;
  the second respawn replaces the first. Harness-generated agent ids are hex, where this
  cannot occur.
- Operator closes a window by hand: nothing re-spawns it unless `panes` is re-invoked.
  `_wave_abort` only targets DELEGATE windows by sub-goal id and ignores `sa-*` ones.
- bash 3.2: positional loops only, no assoc arrays/mapfile (CI macOS matrix enforces).

## Out of scope

- Any write path into subagent sessions (send-keys stays DELEGATE-only, per the operator
  decision this spec implements).
- A cmux dispatch driver (SPEC-119 DEC-001 tmux-only rationale carries over; cmux remains
  a viewer surface via SPEC-121 push; the NOTES.md "tmux vs cmux driver fork" is resolved
  the same way for the tailer).
- Documenting subagent-delegate mode fully in WORKFLOW.md's "Mega-goal delegate
  execution" (pre-existing doc gap, flagged to the operator; this spec adds only the
  panes subsection it owes).

## Touches

- `lib/queue/orchestrate.sh` (new: `cmd_panes`, `cmd_pane_tail`, `PANE_TAIL_JQ` env, main()
  dispatch entries + usage string, top-of-file doc block)
- `lib/queue/pane-tail.jq` (new)
- `tests/test-subagent-panes.sh` (new)
- `.github/workflows/test.yml` (add the new test)
- `README.md` (orchestrate.sh row: document `panes` + `PANE_TAIL_JQ`)
- `docs/WORKFLOW.md` (subsection under Mega-goal delegate execution) +
  `tests/test-docs-wiring.sh` AC pair. Validate-finding 7: `panes` has no in-kit caller,
  so the live-call-site half of the AC greps `commands/mega.md` for
  `orchestrate.sh panes` (the real invoker is conductor prose, named exemption) plus the
  `main()` dispatch entry in orchestrate.sh; the doc-presence half greps WORKFLOW.md as
  AC1-AC9 do.
- `commands/mega.md` (one sentence in Run mode pointing the conductor at `panes`)
- `docs/verification/subagent-panes.md` (proof of done)

## Decision log

- DEC-001: one-shot subcommand over `_wave_run` hook or watcher daemon (no dispatch loop
  exists for subagent mode; minimum infra).
- DEC-002: re-entry `_pane-tail` subcommand over inline `tmux new-window 'tail | jq'`
  string (the #143 exec-direct rule; a pipe needs a process of our own, not `$SHELL -c`).
- DEC-003: read-only enforced by process shape (`tail | jq`, no shell in the pane), not
  by tmux key-table configuration (simpler, nothing to misconfigure).
- DEC-004: `sa-` window-name prefix namespaces subagent panes away from the `SG-NN`
  sub-goal-id windows mega.md generates (collision-free for those; an operator who names
  a sub-goal `sa-01` by hand defeats it -- accepted). The prefix also guarantees the name
  is never all-digits, which tmux would resolve as a window INDEX (intentional).
- DEC-005: formatter is a separate `.jq` file behind `PANE_TAIL_JQ`, not an inline string
  (testable against fixtures, operator-substitutable, keeps orchestrate.sh smaller);
  resolved caller-side and passed as argv because env does not cross the tmux boundary.
- DEC-006: tmux stays the only driver (SPEC-119 DEC-001 rationale restated for the
  tailer; resolves the NOTES.md open fork).
- DEC-007: `--latest` session-dir derivation (slugified `$PWD`, newest-mtime
  `subagents/` dir) lives in the kit, because the conductor demonstrably cannot name
  the transcript paths itself (Agent-tool dispatch returns no path); a pure helper,
  fake-`$HOME` testable.
