# Proof of done: auto-format hook uses rustup stable rustfmt (ID-297)

**Change class:** behavioral (`hooks/auto-format.sh`).

**Claim:** the `*.rs` branch of the auto-format hook formats with the rustup-pinned
`stable` toolchain (`rustup run stable rustfmt`) so results match CI (which runs
stable), instead of whatever `rustfmt` is first on PATH (the brew rustfmt that caused
import-order churn in zedra). It falls back gracefully to plain `rustfmt` when rustup
is absent, and to plain `rustfmt` if the stable invocation itself fails. The hook
still never blocks (`|| true`, exit 0 always).

## Acceptance criteria

| # | Criterion | Result |
|---|---|---|
| 1 | rustup present -> hook invokes `rustup run stable rustfmt <file>` | PASS |
| 2 | rustup present but stable invocation fails -> inner fallback to plain `rustfmt` | PASS |
| 3 | rustup absent, rustfmt present -> plain `rustfmt`, no rustup call | PASS |
| 4 | neither tool present -> no formatter runs, exit 0 (negative control) | PASS |
| 5 | full hook suite green (no regression) | PASS (477/477) |

## Coverage (branch enumeration)

Bash has no line-coverage tool in this repo, so coverage is satisfied by
enumeration: the diff adds exactly the four behavior branches above, and each is
exercised by at least one test (`tests/test-hooks.sh`, cases B1a / B1b / B2 / B3).
All four changed branches are covered = 100% of the changed decision paths.

## Confirmation run

| Check | Command | Exit | Verdict |
|---|---|---|---|
| Hook suite (incl. 11 new .rs assertions) | `bash tests/test-hooks.sh` | 0 | PASS (477/477) |
| Meta suite | `bash tests/test-meta.sh` | 0 | PASS (698/698) |

## Run detail

The tests mock `rustup`/`rustfmt` on a controlled PATH (each logs its own argv) and
assert which formatter the hook invoked:

```
PASS .rs: rustup present -> 'rustup run stable rustfmt <file>'
PASS .rs: rustup success does NOT also call plain rustfmt
PASS .rs: rustup attempted before fallback
PASS .rs: rustup failure falls back to plain rustfmt
PASS .rs: rustup absent -> plain rustfmt
PASS .rs: rustup absent -> no rustup call
PASS .rs: neither tool present exits 0 (negative control)
PASS .rs: negative control invokes no formatter
...
Passed: 477 / 477
```

## NEGATIVE CONTROL

Run the pre-change hook body (plain `rustfmt` only) against the same mocked PATH:

```
# current hook, rustup present:
formatter invoked -> rustup run stable rustfmt /tmp/.../x.rs   # GREEN

# pre-change hook (plain rustfmt only), same mocked PATH:
formatter invoked -> rustfmt /tmp/.../x.rs                     # RED for AC1/AC2
```

The pre-change hook never reaches the rustup-stable toolchain, so the `rustup run
stable rustfmt` assertions fail against it: the tests are load-bearing on the change,
not tautological.

**Verdict: PASS.**

## Reproduce

```
bash tests/test-hooks.sh      # 477/477, includes the .rs B1a/B1b/B2/B3 cases
bash tests/test-meta.sh       # 698/698
```

**Rollback:** `git revert` this commit restores the plain-`rustfmt` `*.rs` branch;
the change is a self-contained hook edit plus tests, no state or data step.
