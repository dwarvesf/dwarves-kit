# SPEC-373: shared hook-parity test harness

**Status:** DRAFT
Lane: normal
Type: spec-feature
**Proof:** `tests/test-hook-parity-lib.sh`.
References: `tests/fixtures/money-gate-parity/{run-case.sh,gen-expected.sh}`, `tests/test-money-gate-parity.sh` (unmerged, `money-gate-bash` worktree); `tests/fixtures/citation-guard-parity/{run-case.sh,gen-expected.sh}`, `tests/test-citation-guard-parity.sh` (unmerged, `citation-guard-bash` worktree) -- the two hand-built parity harnesses this spec generalizes.

## Problem

Two Python-to-bash hook ports (money-gate, citation-guard) each hand-built the same
harness: run a case through a hook under a clean sandbox, capture its exit code, stdout,
stderr, effective log line, and stray files, then diff against goldens generated from the
Python original. Four more hooks (backlog-stage, context-hints, harvest, intake-sweep)
are queued for the same port. Without a shared library, each one re-derives the sandbox,
env-null-unset, and log/stray rules from scratch, and any fix to one copy never reaches
the others.

## Contract

`tests/lib/hook-parity.sh`, a sourced bash library (bash 3.2 safe), exposes three
functions.

| Function | Does |
|---|---|
| `hp_run_case <case-json> <hook-cmd...>` | Runs one case: its own temp `HOME`, an empty temp cwd (or `HP_CWD` when the caller gives one), the hook under `env -i PATH HOME LANG=en_US.UTF-8 LC_ALL=en_US.UTF-8` plus the case's `env` object. A `null` env value unsets that var. `ROOT` in an env VALUE (never the key) expands to `HP_ROOT` when set. The log var name is `HP_LOG_VAR`; when the case's `env` omits that key, the harness injects its own default log path; when the case sets it to `null`, no log env is passed and the log field reads empty (the harness does not guess the hook's own internal fallback path). `payload` is `.payload`: a string fed verbatim with an `RAW:` prefix stripped, or a JSON object fed as compact JSON. Prints one JSON line `{name, rc, stdout, stderr, log, stray}`: `stdout` normalized with `jq -S -c .` when it parses, else raw; `log` is the effective log file's lines minus each line's first tab field, prefixed `BAD-EPOCH ` when any first field is not all-digit; `stray` lists files left under `HOME` or cwd other than the effective log, comma-joined, `LC_ALL=C` sorted. |
| `hp_gen_expected <rev> <hook-basename> <cases.jsonl> <expected.jsonl>` | Extracts `hooks/<hook-basename>.sh` and `.py` at `<rev>` into a temp dir, symlinks the resolved `python3` interpreter into a temp `PATH` dir (`env -i` would otherwise let a mise shim reinstall python per call), and runs every case in `<cases.jsonl>` through that shim via `hp_run_case`, writing `<expected.jsonl>`. `HP_KIT_ROOT` overrides the repo root the revision is read from (default: this library's own location); a real port never sets it. |
| `hp_check <cases.jsonl> <expected.jsonl> <hook-cmd...>` | Runs every case via `hp_run_case` against the given hook command, diffs each line against `<expected.jsonl>`, prints `  FAIL <name>` plus `want:`/`got:` for a mismatch, and a final `<N> passed, <M> failed` line. Returns non-zero on any failure. |

A port's own `tests/fixtures/<hook>-parity/{run-case.sh,gen-expected.sh}` collapse to a
few lines that source the library and call these three functions; hook-specific payload
shaping (a generated large file, a path rewrite) stays in the port's own fixture, not in
the shared library.

## Test plan

| # | Check | Expect |
|---|---|---|
| T1 | `bash tests/test-hook-parity-lib.sh` | all self-checks pass: null-unset, `ROOT`-in-value-only (not in the key), `BAD-EPOCH` tagging, stray-file detection, and a deliberate mismatch that `hp_check` reports as `FAIL` |
| T2 | `hp_check` against `tests/fixtures/money-gate-parity/{cases.jsonl,expected.jsonl}` (from the unmerged `money-gate-bash` worktree) with `hooks/money-gate.sh` | `<N> passed, 0 failed`, proving the shared `hp_run_case` reproduces what the hand-built `run-case.sh` already proved |

## Verification

T1 and T2 both hold, quoted in the implementation report.

## After state

`tests/lib/hook-parity.sh` exists and is documented (header comment). The two existing
hand-built harnesses are left as-is (their own spec owns any later migration); the four
queued ports (backlog-stage, context-hints, harvest, intake-sweep) source this library
instead of hand-building their own.
