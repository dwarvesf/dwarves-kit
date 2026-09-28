# Implementation notes -- citation-guard-bash

Deltas from SPEC-356. Nothing here repeats what the spec already states.

## 2026-09-29 Line counts come from a streaming jq, not wc + tail + od

- Context: the spec's design note assumed the shell counts lines ("the shell only counts lines"), which implies `wc -l` plus a last-byte check under `LC_ALL=C`.
- Decision/Change: `jq -Rn 'reduce inputs as $_ (0; . + 1)'` counts the file. `jq -R` yields one input per line and counts a trailing partial line, which is Python's line-iteration count exactly, including the `\r`-never-ends-a-line rule.
- Why: one tool the hook already requires, no locale pin to remember (the spec's `LC_ALL=C` list is awk/tr/wc/sort, and this uses none of them), and no separate empty-file or last-byte branches.
- Alternatives considered: `wc -l` + `tail -c 1` + `od` (rejected: three tools, three `LC_ALL=C` prefixes, three failure modes to map onto `unreadable`).

## 2026-09-29 Crash classes are a flag in the reduce, not an abort

- Context: the spec says the port "exits 0 silently as soon as it meets" a shape the Python crashed on.
- Decision/Change: the transcript walk is a single `reduce (inputs | fromjson?)` whose state is `{t, ok}`. A crash shape sets `ok=false` and every later line is a no-op; the final emit is `if .ok then .t else ""`, which falls through to the same empty-text exit.
- Why: `reduce` cannot break early, and reading the rest of the file while ignoring it is cheaper than a `label`/`break` and produces the identical result: the text the crash discarded is never checked.
- Impact: `crash-nonobject-line` keeps "old nope.md:1" in `.t` internally but reports nothing, matching the Python's die-at-the-line behavior.

## 2026-09-29 Python truthiness needed a jq def, not `//`

- Context: `o.get("message") or {}` and `payload.get("sessionId") or ...` are Python truthiness: `""`, `0`, `[]`, `{}`, `false`, `null` all fall through.
- Decision/Change: a shared `def truthy: . != null and . != false and . != 0 and . != "" and . != [] and . != {};` is used for `message` and for `sessionId`/`session_id`. jq's `//` only maps `null` and `false`, so `message: ""` or `sessionId: ""` would have behaved wrong (`session-empty-falls-back` pins the second).
- Impact: `message: ""`, `message: []`, `message: 0` skip like the Python; `sessionId: ""` falls through to `session_id`.

## 2026-09-29 Non-string `transcript_path` / `cwd` fall through via `strings`

- Context: the Python crashed (TypeError, exit 1) on a truthy non-string `transcript_path` or `cwd`.
- Decision/Change: `.transcript_path | strings` and `.cwd | strings` treat them as absent, so `transcript_path` exits 0 and `cwd` falls to `$PWD`.
- Why: same divergence family the spec already records for crash shapes (exit 0 instead of the Python's exit 1), and the corpus does not pin it.

## 2026-09-29 The `root-override` case never reached the env branch (harness bug, fixed)

- Context: the implementer found that `run-case.sh` substituted `ROOT` across the whole `KEY=VALUE`, which also rewrote the name `CITATION_GUARD_ROOT`; `env` dropped the mangled variable, so neither the Python nor the port ever saw it and the golden pinned the payload-cwd path instead.
- Decision/Change: the orchestrator fixed the harness to expand `ROOT` in the value only, regenerated the goldens from the `ce08a00b` shim (`root-override` now flags `a.md:1 (no such file)` and resolves `b.py:3` under `sub/`), and re-ran the port: every case passes unchanged.
- Impact: the env-then-cwd-then-PWD chain is now pinned by the corpus.

## 2026-09-29 Exactly one JSON object on stdin (orchestrator review fix)

- Context: the first cut checked `type == "object"` with `jq -e`, which streams `{...} {}` as two values and passes; `json.load` rejects trailing data, so the Python returned early.
- Decision/Change: `jq -se 'length == 1 and (.[0] | type) == "object"'`.
- Impact: a concatenated payload exits 0 silently, as the Python did. Not in the corpus (Claude Code sends one object).

## 2026-09-29 Dedupe emits normalized digits

- Context: refs dedupe on (path, integer value) and print without leading zeros.
- Decision/Change: jq normalizes each number with `sub("^0+"; "") | sub("^$"; "0")` at extraction, then emits `path<TAB>num` lines; the dedupe key IS the emitted pair, so `nope.md:07`/`nope.md:7`/`nope.md:00` collapse and print as `7`/`0`. The past-EOF test is a digit-string compare (longer wins, equal length lexical), so `a.md:99999999999999999999` never touches `tonumber`.
- Alternatives considered: emitting raw `scan` pairs and normalizing in bash (rejected: dedupe would need a second normalization pass and associative arrays just to keep first-seen order).

## 2026-09-29 `unreadable` is a failed jq, not a `-r` test

- Context: the Python's `unreadable` means `open()` raised OSError on an existing regular file.
- Decision/Change: `[ -f ]` gates `no such file`; the line-count jq's own failure (redirect or read error) maps to `unreadable`. A separate `-r` test was dropped because under `set -e` the jq probe has to exist anyway, and `-r` lies for root.
- Impact: the corpus has no unreadable case; the mapping is one `if ! n=$(...)` and nothing else can produce a stray non-zero exit.

## 2026-09-29 Left for the orchestrator

- `tests/fixtures/citation-guard-parity/gen-expected.sh` still references `hooks/citation-guard.py` at the pinned revision; it regenerates goldens from `git show ce08a00b:...`, so it still works after the deletion and I left it untouched per the do-not-edit rule.
- `docs/verification/kit-foldin-hooks.md` and `docs/specs/SPEC-334-session-state-root.md` name `citation-guard.py` as dated records; left as written.
