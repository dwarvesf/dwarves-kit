# Implementation notes: token capture under delegation (SPEC-117)

Delta from the spec + ADR-0032 §3. Reference, don't restate.

## 2026-07-03 11:30 Reuse over rebuild: the silent stream-to-file path already exists

Context: The goal said "VERIFY what is there, then close the specific gap." Audit found
SPEC-110 already ships the whole extraction+ledger chain:
- `lib/handoff/handoff_gen.py sum-usage <file>`, assistant-only usage extraction from a stream-json FILE.
- `lib/gate-ledger.sh tokens <rid> ...`, the `| TOKENS |` additive marker.
- `lib/orchestrate.sh` token hook (cmd_run ~L1245), gated on `$slog` non-empty → sum-usage → record TOKENS.
- `_run_one_session` already has BOTH a tee-to-conductor branch (`--stream`, L621) AND a
  silent `> "$slog"` stream-to-FILE branch (the `else` under `DETERMINISTIC_HANDOFF=1`, L623).

Decision: Do NOT add a new file, a new marker, or a new extractor. The only real gap is that
the LEAN silent-stream-to-file capture is reachable ONLY by turning on `DETERMINISTIC_HANDOFF`
(a heavier, unrelated feature, handoff regeneration). Add ONE decoupled trigger,
`CAPTURE_TOKENS` env + `--capture-tokens` flag, that takes the SAME silent branch purely for
usage extraction.

Why: ADR-0032 §5 lists "Token-capture stream-to-file (item 3)" as a gap to close as first-class.
`--stream` is the forbidden bloat path (it tees the child stream to the conductor); operators
need a lean token-capture knob that is neither `--stream` nor `DETERMINISTIC_HANDOFF`.

Impact: ~3-line change to `_run_one_session`'s elif trigger + flag/env wiring in cmd_run. The
downstream hook is untouched (already `$slog`-gated). The default (no-flag) path stays
byte-identical (honest usage=?).

## 2026-07-03 File naming: reuse `<id>.stream.jsonl`, not a new `child.jsonl`

ADR-0032 §3 writes `claude -p --stream > child.jsonl` conceptually. The existing per-sub-goal
capture file is `.orchestrate/<id>.stream.jsonl`. Reuse it (do not invent a second file
convention), the "child.jsonl" in the ADR is the concept, `<id>.stream.jsonl` is the instance.

## 2026-07-03 11:50 spec-validate dispositions (adversarial pass)

An adversarial spec-validate lens attacked SPEC-117 pre-code. Dispositions:

- **BLOCKER (wave-path token hook missing):** RESOLVED by correcting the over-claim. The token
  hook lives only on the SERIAL `cmd_run` path; `_wave_run` never had one (nor did SPEC-110).
  My Done= is the serial single-child delegate (ADR-0032 §3 `claude -p --stream > child.jsonl`).
  Scoped the wave-path per-sub-goal ledger extraction OUT explicitly (declared gap, like SPEC-110's
  watchdog gap; single wiring point at orchestrate.sh:862). The child.jsonl IS still written
  lean-to-file under waves (global inherits into the subshell), so only the extraction is deferred.
  Dep-chained / Touches-less mega-goals run the serial path anyway (ready set size-1).
- **MAJOR (global vs positional):** ACCEPTED. `CAPTURE_TOKENS` is a script GLOBAL read inside
  `_run_one_session` (mirroring `DETERMINISTIC_HANDOFF`), NOT a positional arg. Zero signature
  change, zero `_wave_run` call-site touch, composes through the wave subshell on fork.
  `--capture-tokens` just sets the global in `cmd_run`.
- **MINOR (stderr leak):** the transcript (the accumulation trap) is fd1 (`claude -p` stdout) and
  is redirected to the file. `--verbose` stderr is diagnostic-only (no usage/turn content) and the
  driver is non-LLM bash. Test proves the property that matters by capturing child stdout and
  stderr SEPARATELY and asserting the transcript sentinel is absent from fd1. Redirecting stderr too
  is a deferred hardening (would silence real errors on this opt-in path). `# ponytail:` noted at code.
- **MINOR (flag-parse ordering):** ACCEPTED. `--capture-tokens)` arm goes before the `--*)` catchall.
- **LOW (completeness):** usage header + `main()` usage string + `--dry-run` advisory updated.
- **LOW (env+flag asymmetry):** kept both; the flag simply sets the env-global. Env is the wave-subshell
  inheritance mechanism; flag is interactive/scripted sugar.

## 2026-07-03 `--verbose` on the child is NOT a hard-rule violation

The hard rule (ADR-0032 §1) forbids `--stream`/`--verbose` piped TO THE CONDUCTOR. In the
silent branch the `--output-format stream-json --verbose` output is redirected `> "$slog"` (the
FILE), never the conductor's stdout. Only the `--stream` tee branch violates the rule, that is
exactly what the false-bloat NC guards.
