# Proof of done: subagent panes (SPEC-234)

Read-only jsonl-tail panes for the DEFAULT mega-goal run mode (background subagents dispatched
via the conductor's own Agent tool, `commands/mega.md` "Run mode"), which has no dispatch loop
of its own to attach a tmux window to. `orchestrate.sh panes <megadir> <target>...` is a one-shot
subcommand the conductor shells out to after dispatching: each resolved transcript (a jsonl
path, a directory of them, or `--latest` to derive the conductor's own subagents dir) grows a
tmux window running `tail -F | jq` via the hidden `_pane-tail` re-entry (SPEC-119 #143
exec-direct pattern). Read-only by construction (no shell in the pane); steering a subagent
still routes through the conductor (SendMessage), never the pane.

## Acceptance criteria

| # | Criterion | Result |
|---|---|---|
| T1 | 2 fixture transcripts -> 2 `sa-<id>` windows; tmux session ensured exactly once; re-invoke -> `kill-window` precedes each respawn (idempotence) | PASS |
| T2 | `new-window` argv is exec-direct: `--` separator present, re-entry tokens (`orchestrate.sh`, `_pane-tail`, jsonl, formatter) are 4 SEPARATE argv items, jsonl + formatter paths absolute | PASS |
| T3 | Skips (missing file, wrong basename, unexpanded `agent-*.jsonl` glob literal, empty dir) each warn on stderr and are counted in `[panes] spawned N, skipped M`; rc 0 throughout; a valid sibling still spawns; `<2` total args -> usage on stderr, rc 0 | PASS |
| T3b | Review-round fix: a transcript FILENAME carrying embedded ESC/OSC bytes never reaches the operator's terminal raw (combined stdout+stderr has zero ESC bytes; the warning/summary line shows the `_panes_show`-sanitized `?`-replaced name instead); a symlinked target is skipped with its own named warning (not spawned then invisibly killed by `_pane-tail`'s `-L` gate) and counted in the skip tally | PASS |
| T4 | A directory target expands to its members; `--latest` derives slug + newest-mtime subagents dir under a fake `$HOME` (DEC-007); a `--latest` miss (no project dir) is a clean warn, rc 0, spawns nothing | PASS |
| T5 | `_pane-tail` refuses a directory, an unreadable file, a symlink, a wrong-basename file, and a missing formatter -- each exit 64 with a distinct named stderr message [NEGATIVE CONTROL] | PASS |
| T6 | Formatter: assistant text verbatim, `tool_use` -> `-> <name> <input prefix>`, `tool_result` -> count-only `<- result (N chars)`, attachments dropped, a malformed line and a truncated-JSON line render nothing (later valid lines still render), ESC/OSC-52 control bytes stripped with an EXACT output match, a >2000-char line capped with `...[truncated]` | PASS |
| T7 | SPEC-121 viewer push fires only on session CREATION (a second `panes` call against the same session opens no additional viewer); a metachar `TMUX_SESSION` is refused by `_viewer_open`'s pre-existing charset gate -- no host command runs, rc still 0 [SECURITY NEGATIVE CONTROL] | PASS |
| R | Regressions unedited: `test-multiplexer.sh`, `test-pane-viewer.sh`, `test-orchestrate-hardening.sh`, `test-docs-wiring.sh` green (+2 new AC pinning the `commands/mega.md` call site and the `panes` `main()` dispatch entry); `test-orchestrate-wavefront.sh` is PRE-EXISTING TIMING-FLAKY on this tree (see below, NOT claimed green); `shellcheck -S error lib/queue/orchestrate.sh tests/test-subagent-panes.sh` clean | PASS (wavefront excluded, pre-existing) |
| B1 | BEHAVIORAL (real tmux server, no mocks): `panes` spawns a real window; `capture-pane -p` shows the `[panes] tailing ...` header + the formatted text | PASS |
| B2 | BEHAVIORAL: appending a line to the live transcript makes it appear on the next `capture-pane` (the `tail -F` follow property) | PASS |
| B3 | BEHAVIORAL NEGATIVE CONTROL: pointing `PANE_TAIL_JQ` at a broken formatter (`.`, no `fromjson`) renders raw JSON for the transcript line, while the header line still prints correctly (RED, faithfully re-run 2026-08-28); restoring the real formatter and re-invoking `panes` on the same session renders correctly again (GREEN) | PASS |

`test-orchestrate.sh` carries two pre-existing failures (`dry-run SG-02 inherit wrong`, `SG-02
got an unexpected --model`) unrelated to this change -- confirmed via `git stash` on this branch:
identical failures on the pre-SPEC-234 tree.

**`test-orchestrate-wavefront.sh` is PRE-EXISTING TIMING-FLAKY, not a regression from this
change** (fresh recheck, 2026-08-28): 6 consecutive re-runs on this tree failed 6/6 on
`wave_run g` ("concurrency NOT proven"), 3/6 also failed `wave_run h2` ("both mock sessions
never started"), one run hung outright waiting on its own mock barrier, and the reviewer's
separate pass additionally caught `dispatch k` failing intermittently ("wave not taken/failed").
All three (`wave_run g`, `dispatch k`, `wave_run h2`) are mock-barrier concurrency assertions in
the same suite, none of which this diff's code touches (`cmd_panes`/`cmd_pane_tail`/`_panes_*`
are new, additive functions; nothing in `_wave_run`/`_wave_gate`/the mock-barrier plumbing
changed). A clean checkout of the pre-change commit `599ee97` reproduces the identical failure
signature (`wave_run g` + `wave_run h2`) under the same system load, and a clean pre-change run
under lighter load passes -- consistent with a load-sensitive timing race in the suite's mock
barrier, present before this branch. This suite is never claimed green in the Run/Regression
table below; it is excluded from the required-green set per this fix.

## Run table

```
$ bash tests/test-subagent-panes.sh
=== T1: 2 fixtures -> 2 sa-<id> windows, session ensured once; re-invoke -> kill-window precedes respawn ===
PASS T1: cmd_panes rc 0
PASS T1: two sa-<id> windows created for two fixtures
PASS T1: tmux session ensured exactly once
PASS T1: summary line 'spawned 2, skipped 0'
PASS T1: re-invoke reuses the existing session (no second new-session)
PASS T1: re-invoke issues one kill-window per window (idempotent pre-clean)
PASS T1: kill-window precedes new-window for the respawned window (idempotence)
=== T2: new-window argv is exec-direct with a -- separator; re-entry tokens separate; paths absolute ===
PASS T2: new-window argv includes a -- separator
PASS T2: re-entry argv is 4 SEPARATE tokens (script, _pane-tail, jsonl, formatter)
PASS T2: argv[0] is orchestrate.sh's own path
PASS T2: argv[1] is the bare re-entry subcommand
PASS T2: jsonl path is absolute
PASS T2: formatter path is absolute
=== T3: skips (missing, wrong basename, unexpanded glob, empty dir) warn + count; rc 0; siblings still spawn ===
PASS T3: rc 0 despite multiple skips
PASS T3: missing-file skip warns
PASS T3: wrong-basename skip warns
PASS T3: empty-dir warns
PASS T3: summary counts 1 spawned / 3 skipped (valid sibling still spawns)
PASS T3: <2 total args -> usage on stderr, rc 0
=== T3b: ESC-embedded filename is sanitized on display; symlink target is skipped, never spawned ===
PASS T3b: no raw ESC byte in combined output
PASS T3b: ESC-embedded filename rendered sanitized ('?' replacement)
PASS T3b: symlink target skipped with its own warning (not spawned then ghost-killed)
PASS T3b: no window created for the symlink target
PASS T3b: summary counts symlink as skipped (2 spawned: badname + real)
=== T4: --latest derives slug + newest-mtime subagents dir under a fake $HOME (DEC-007) ===
PASS T4: --latest picked the NEWEST-mtime subagents dir
PASS T4: --latest did NOT also spawn the older session's window
PASS T4: summary reflects exactly one resolved transcript
PASS T4: --latest with no project dir is a clean miss (warns, rc 0, spawns nothing)
=== T5: _pane-tail refuses each hazard shape, exit 64, named stderr ===
PASS T5a: a directory is refused, exit 64
PASS T5b: an unreadable file is refused, exit 64
PASS T5c: a symlink is refused, exit 64 [SECURITY L4]
PASS T5d: a wrong-basename file is refused, exit 64
PASS T5e: a missing formatter is refused, exit 64
=== T6: formatter -- verbatim text, ->/<- lines, drops, malformed/truncated survive, ESC/OSC-52 stripped, cap ===
PASS T6: attachment/malformed/truncated-json lines dropped (6 rendered from 9 input lines)
PASS T6: assistant text renders verbatim
PASS T6: tool_use renders as -> <name> <input prefix>
PASS T6: tool_result renders as count-only <- result (N chars)
PASS T6: ESC/OSC-52 control bytes stripped, EXACT output match [SECURITY H1]
PASS T6: a long line is capped at 2000 chars + ...[truncated] marker
PASS T6: a later valid line still renders after the malformed/truncated ones
=== T7: viewer fires only on session creation; a metachar TMUX_SESSION is refused by the charset gate ===
PASS T7: first panes call (session creation) opens exactly one viewer surface
PASS T7: second panes call against the SAME already-running session opens no additional viewer
PASS T7: a metachar TMUX_SESSION still returns rc 0
PASS T7: no host command ran [SECURITY NC]: viewer never invoked, no injection via TMUX_SESSION
PASS T7: the refusal names the charset gate (loud)
----
ALL PASS
```

Regression (all rc 0): `test-multiplexer.sh`, `test-pane-viewer.sh`, `test-orchestrate-hardening.sh`,
`test-docs-wiring.sh` (25/25, including the 2 new AC); `shellcheck -S error lib/queue/orchestrate.sh
tests/test-subagent-panes.sh` clean. `test-orchestrate-wavefront.sh` is PRE-EXISTING TIMING-FLAKY
(see the acceptance-criteria table above) and is deliberately NOT included in this green set.

## Behavioral run (real tmux server, no mocks)

```
$ TMUX_SESSION=orch-behav bash lib/queue/orchestrate.sh panes /tmp/mega /tmp/agent-realtest.jsonl
[panes] spawned sa-realtest <- agent-realtest.jsonl
[panes] spawned 1, skipped 0

$ tmux capture-pane -p -t orch-behav:2
[panes] tailing agent-realtest.jsonl -- read-only; steer via the conductor (Send
Message)
hello from the real pane

# append a line to the live transcript, then capture again (the -F follow property):
$ jq -nc '{type:"assistant",message:{content:[{type:"tool_use",name:"Bash",input:{command:"echo live-append-test"}}]}}' >> /tmp/agent-realtest.jsonl
$ tmux capture-pane -p -t orch-behav:2
[panes] tailing agent-realtest.jsonl -- read-only; steer via the conductor (Send
Message)
hello from the real pane
-> Bash {"command":"echo live-append-test"}

# NEGATIVE CONTROL: point PANE_TAIL_JQ at a broken formatter (no fromjson) -> RED
$ echo '.' > /tmp/broken.jq
$ TMUX_SESSION=orch-behav-nc PANE_TAIL_JQ=/tmp/broken.jq bash lib/queue/orchestrate.sh panes /tmp/mega-nc /tmp/agent-realtest.jsonl
$ tmux capture-pane -p -t orch-behav-nc:2
[panes] tailing agent-realtest.jsonl -- read-only; steer via the conductor (Send
Message)
{"type":"assistant","message":{"content":[{"type":"text","text":"hello from the
real pane"}]}}
# RED confirmed: the header line is unaffected (echoed by the `_pane-tail` wrapper before it
# execs `tail | jq`, not by jq itself), and the transcript renders as raw JSON instead of the
# formatted text -- proves capture-pane is reading the actual formatter wiring, not a
# cached/hardcoded pane. (Corrected from an earlier over-trimmed excerpt that dropped the
# header line and implied jq alone controls the pane's full content.)

# restore the real formatter on the SAME session (idempotent respawn) -> GREEN
$ TMUX_SESSION=orch-behav-nc bash lib/queue/orchestrate.sh panes /tmp/mega-nc /tmp/agent-realtest.jsonl
$ tmux capture-pane -p -t orch-behav-nc:2
[panes] tailing agent-realtest.jsonl -- read-only; steer via the conductor (Send
Message)
hello from the real pane
```

Note: `tmux capture-pane -t <session>:<window-name>` (name-based targeting) resolved to the
wrong window in this tmux 3.7c install during ad hoc verification; `<session>:<index>` (numeric)
targeted correctly. This is a manual-verification quirk of the interactive `tmux` CLI's own
target-parsing, not a code path `cmd_panes` exercises -- the implementation only ever targets
`kill-window`/`new-window` by name for its own idempotent create/replace pairing (proven by T1's
kill-precedes-respawn assertion), never reads state back via name-based `capture-pane`.

## Reproduce

```
cd <dwarves-kit>
bash tests/test-subagent-panes.sh          # ALL PASS (T1-T7, mocked tmux/viewer, CI-safe)
bash tests/test-multiplexer.sh tests/test-pane-viewer.sh \
  tests/test-orchestrate-hardening.sh tests/test-docs-wiring.sh   # regression
shellcheck -S error lib/queue/orchestrate.sh tests/test-subagent-panes.sh
# tests/test-orchestrate-wavefront.sh is PRE-EXISTING TIMING-FLAKY (see acceptance-criteria
# table); run it separately if needed, do not fold it into the required-green set.
```

The mocked suite needs no real tmux server (CI-safe, mirrors the SPEC-119/121 discipline); the
behavioral block above needs a real `tmux` + `jq` on PATH (both present on the dev machine used).

## Coverage delta

- **Covered:** window spawn + idempotent respawn (T1) · exec-direct argv security pin (T2) ·
  every named skip shape + the usage path (T3) · a filename-embedded-ESC display sanitize and a
  symlink-target skip (T3b, review-round) · directory expansion + `--latest` derivation
  including its clean-miss case (T4) · every `_pane-tail` refusal shape (T5) · the formatter's
  full render/drop/strip/cap behavior against generated fixtures, including the malformed-line
  survival property (T6) · viewer-push once-per-session-creation + the charset-gate negative
  control (T7) · a real tmux server end-to-end, including the `-F` follow property and a
  formatter-swap negative control (B1-B3) -- SPEC-119/121 declared this last category
  uncovered; SPEC-234 does not.
- **Uncovered (declared):** a genuinely multi-MB transcript line (the cap logic is proven at
  2500 chars, the same code path as multi-MB, per SPEC-234's own T6 proportionality note) ·
  the conductor's own Agent-tool dispatch producing a real subagent transcript end-to-end (out
  of `orchestrate.sh`'s testable surface; `commands/mega.md`'s prose pointer is the wiring,
  pinned by `test-docs-wiring.sh` AC11) · cmux as a pane viewer surface for `panes` specifically
  (reuses `_viewer_open` unchanged, already covered by `test-pane-viewer.sh`'s own cmux tests).

## Test plan coverage

| Row | Run / skip reason |
|---|---|
| T1 | tests/test-subagent-panes.sh T1 block (spawn x2, session ensured once, kill-window-before-respawn); rerun in the fresh recheck re-audit |
| T2 | T2 block, exec-direct argv pin (4 discrete tokens incl. abs jsonl + abs formatter); independently re-verified by the security lens via a mock argv dump |
| T3 | T3 block (missing file, wrong basename, glob literal, empty dir, <2 args, rc=0 + summary) + T3b (ESC-embedded filename sanitize, symlink skip; added in the review round) |
| T4 | T4 block, fake-$HOME `--latest` derivation incl. newest-mtime pick and clean-miss |
| T5 | T5 block, every `_pane-tail` refusal shape exit 64 (dir, unreadable, symlink, wrong basename, missing formatter) |
| T6 | T6 block, generated fixtures: render/drop, malformed + truncated-line survival, ESC/OSC-52 strip exact-match, >2000-char cap; formatter also re-verified empirically by the security lens |
| T7 | T7 block, viewer-on-session-creation first-vs-second-call distinction + TMUX_SESSION charset-gate poison pin; B1-B3 real-tmux runs cover the live half |
