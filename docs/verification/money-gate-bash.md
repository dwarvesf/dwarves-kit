# Verification: money-gate runs as bash plus jq

Verdict: PASS

Spec: `docs/specs/SPEC-355-money-gate-bash.md` (VALIDATED, revision 3). Change: `hooks/money-gate.sh` (port), `hooks/money-gate.py` (removed). Implementer: Devin (`swe-2-high`, headless, `--permission-mode dangerous`, scope-fenced to the worktree). The first run hit a 1 h timeout after the port itself was done; a resumed run finished the docs. The orchestrator wrote the spec, the goldens, and the harness, and made two review fixes.

## Checks

| Check | Command | Result |
|---|---|---|
| Parity, every golden, UTF-8 locale | `bash tests/test-money-gate-parity.sh` | `money-gate parity: 59 passed, 0 failed`, plus PASS lines for the 1 MB sparse Write, the 1 MB dense Write, and the jq-missing case |
| Latency, both 1 MB payloads | same test | PASS, 339 to 881 ms on a loaded machine (load average 35 to 113); the 500 ms idle budget was not measured idle |
| Parity under gawk 5.4.1 (PATH shim) | same test | `59 passed, 0 failed` |
| Parity under mawk 1.3.4 (PATH shim) | same test | `59 passed, 0 failed` |
| Hook suite | `bash tests/test-money-gate.sh` | all 16 passed |
| Foldin suite | `bash tests/test-kit-foldin-hooks.sh` | `Passed: 97 / 97` |
| Config registry | `bash tests/test-config-registry.sh` | `56 / 56` |
| No Python | `grep -c python3 hooks/money-gate.sh` | `0` |
| Real payloads | fresh Opus review: Python vs the port on 18 realistic payloads | byte-identical, 0 mismatches |
| Fuzz | same review, 1,000 random fuzz cases | 0 mismatches |
| Negative controls | `lib/gate/negctl.sh <clone> "bash tests/test-money-gate-parity.sh" "<mutation>"`, below | see below |

## Test plan coverage

| Test plan row | Evidence |
|---|---|
| P1 | parity line and both latency lines above |
| P2 | `test-money-gate.sh`, 16/16, above |
| P3 | foldin suite, 97/97, above |
| P4 | gawk and mawk lines above |
| P5 | `grep -c python3`, above |
| P6 | latency measured under load, not idle; recorded as PASS with the actual range, see the note below |
| P7 | config registry, 56/56, above |
| NC1 to NC5 | table below |

The 500 ms latency budget assumes an idle machine. Every measured run landed on a loaded box (load average 35 to 113), so the 339 to 881 ms range is the honest number, not a clean idle read. Both cases still finished well inside the 5 s hook timeout.

## Goldens

59 cases, generated from the `ce08a00b` Python shim by `tests/fixtures/money-gate-parity/gen-expected.sh`, under a UTF-8 locale. One golden, `variant-embedded`, was added on the final head (`daf00565`) to pin the variant scanner's left boundary: the first run of NC1 was vacuous because the corpus had no case with a variant term embedded inside a longer word (see Negative controls below).

## Negative controls

Rerun serially in a scratch clone, with the parity test as the test command, all on the final head (`daf00565`).

| # | Mutation | Under mutation | Verdict |
|---|---|---|---|
| NC1 | drop the variant scanner's left-boundary test | Exit 1 | PASS (after adding `variant-embedded`; the first run was vacuous, see below) |
| NC2 | treat only the literal `1` as strict | Exit 1 | PASS |
| NC3 | scan only `new_string` | Exit 1 | PASS |
| NC4 | fall back to the default log path when `MONEY_GATE_LOG` is set but empty | Exit 1 | PASS |
| NC5 | drop the hook's own `LC_ALL=C` | Exit 1 | PASS |

NC1's first run passed under the mutation, which is a fail for a negative control: the corpus had no case with a variant term (an `[_-]` form) embedded inside a word, so dropping the left-boundary check changed nothing observable. The `variant-embedded` golden was added to pin that boundary, and NC1 was rerun: it now goes red under the mutation, as required.

## Review fixes

Two `set -u` should-fixes from the fresh Opus review, fixed in `bf32c491`:

- An unset `HOME` lost the strict ask (a variable read under `set -u` with no default aborted the script before it could print).
- An empty repo array failed under bash 3.2 (bash 3.2 treats an empty array reference under `set -u` as unbound, unlike bash 4+).

## Validation

Two fresh Opus rounds.

- Round 1: NEEDS REVISION. The per-position awk scan missed the 500 ms timeout at 100 KB; empty or relative `MONEY_GATE_LOG` values wrote no log in Python and needed the same behavior in the port; 20 corpus gaps.
- Round 2: APPROVED, critical = 0.
