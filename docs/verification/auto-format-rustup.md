# Proof of done: auto-format hook uses rustup toolchain rustfmt (ID-297)

**Change class:** behavioral (`hooks/auto-format.sh`).

**Claim:** the `*.rs` branch of the auto-format hook formats via the rustup
toolchain (`rustup run "${RUSTFMT_TOOLCHAIN:-stable}" rustfmt "$FILE"`) so results
match CI (which runs stable), instead of whatever `rustfmt` is first on PATH (the
brew rustfmt that shadowed the rustup proxy and caused import-order churn in zedra).
It defaults to `stable`, lets a consumer repo pin a different channel via
`RUSTFMT_TOOLCHAIN`, and falls back to plain `rustfmt` only when rustup is absent.
When rustup is present but the pinned toolchain is missing, it SKIPS formatting
rather than silently reverting to the divergent PATH rustfmt. The hook still never
blocks (`|| true`, exit 0 always).

## Review disposition (review-team + fable advisor)

| Finding | Lens | Applied? |
|---|---|---|
| Silent inner fallback (`\|\| rustfmt`) re-opens the divergence it fixes, with no signal | fable advisor | Applied, inner fallback removed; missing toolchain now skips formatting |
| Hardcoded `stable` overrides a consumer repo's toolchain pin | architecture (MEDIUM) | Applied, `RUSTFMT_TOOLCHAIN` env override, `stable` default |
| Comment said "edition"; bare rustfmt ignores Cargo edition | fable advisor | Applied, comment now says "toolchain VERSION", accurate to the fix |
| Inner-fallback PATH-collision with the rustup proxy | architecture (LOW) | Mooted, the inner fallback was removed |
| `$FILE` quoting / injection / PATH-pollution | security | Clean (10/10), no change needed |

## Acceptance criteria

| # | Criterion | Result |
|---|---|---|
| 1 | rustup present -> `rustup run stable rustfmt <file>` (default) | PASS |
| 2 | rustup present but toolchain invoke fails -> SKIP, no PATH-rustfmt fallthrough | PASS |
| 3 | `RUSTFMT_TOOLCHAIN` override honored (`rustup run nightly rustfmt`) | PASS |
| 4 | rustup absent, rustfmt present -> plain `rustfmt` | PASS |
| 5 | neither tool present -> no formatter runs, exit 0 (negative control) | PASS |
| 6 | full hook suite green (no regression) | PASS |

## Coverage (branch enumeration)

Bash has no line-coverage tool in this repo, so coverage is satisfied by
enumeration. The diff's `*.rs` case has exactly these decision paths, each exercised
by at least one test in `tests/test-hooks.sh`: rustup-present-default (B1a),
rustup-present-invoke-fails (B1b), rustup-present-override (B1c), rustup-absent (B2),
neither (B3). All changed branches covered = 100% of the changed decision paths.

## Confirmation run

| Check | Command | Exit | Verdict |
|---|---|---|---|
| Hook suite (incl. 13 new .rs assertions) | `bash tests/test-hooks.sh` | 0 | PASS |
| Meta suite | `bash tests/test-meta.sh` | 0 | PASS (698/698) |

## Run detail

The tests mock `rustup`/`rustfmt` on a controlled PATH (each logs its own argv) and
assert which formatter the hook invoked:

```
PASS .rs: rustup present -> 'rustup run stable rustfmt <file>'
PASS .rs: rustup success does NOT also call plain rustfmt
PASS .rs: rustup-stable attempted
PASS .rs: rustup failure does NOT fall through to PATH rustfmt
PASS .rs: RUSTFMT_TOOLCHAIN honored -> 'rustup run nightly rustfmt'
PASS .rs: override does not fall back to stable
PASS .rs: rustup absent -> plain rustfmt
PASS .rs: rustup absent -> no rustup call
PASS .rs: neither tool present exits 0 (negative control)
PASS .rs: negative control invokes no formatter
```

## NEGATIVE CONTROL

Two load-bearing negatives, both encoded as tests:

1. **B3** (neither tool present): no formatter is invoked, exit 0, confirms the
   never-block contract holds on the empty path.
2. **B1b** (rustup present, toolchain invoke fails): the log shows the rustup
   attempt but NOT a plain `rustfmt` call, confirms the fix does not silently
   revert to the divergent PATH rustfmt. Against the earlier inner-fallback
   version this assertion was RED, so it is load-bearing on the applied fix.

**Verdict: PASS.**

## Reproduce

```
bash tests/test-hooks.sh      # includes the .rs B1a/B1b/B1c/B2/B3 cases
bash tests/test-meta.sh       # 698/698
```

**Rollback:** `git revert` this commit restores the plain-`rustfmt` `*.rs` branch;
the change is a self-contained hook edit plus tests, no state or data step.
