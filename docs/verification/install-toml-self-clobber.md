# Proof of done: install.sh no longer clobbers its own kit.toml

Change under proof:

1. `install.sh` `kit_render_install_toml()` renders to `$dst.tmp.$$` and `mv`s it
   into place, instead of redirecting straight to `> "$dst"`.
2. `tests/test-install-modules.sh` gains an `NC in-place layout` case (6 checks)
   covering the `src == dst` install shape that every existing case misses.

## The bug

`kit_render_install_toml "$KIT_DIR/kit.toml" "$KIT_TOML"` (install.sh L672) is
handed the SAME path twice under README Option 2, which clones the kit to
`~/.claude/dwarves-kit` and installs from there: `KIT_DIR` and
`$CLAUDE_DIR/dwarves-kit` are one directory.

The shell sets up `> "$dst"` — truncating the file — before `awk` opens `src`.
`echo` then writes the 5-line header into that now-empty file, `awk` opens the
same path, reads back the header it just wrote, and passes it through its
catch-all `{ print }`. Net effect of ONE install run: a 160-line, 9-section
`kit.toml` becomes a 12-line stub holding the header twice. Every non-`[modules]`
key stops resolving; `kit_config_get` silently falls through to each caller's
hardcoded default, so nothing errors and nothing warns.

Why CI never caught it: every existing case in `tests/test-install-modules.sh`
installs FROM this checkout INTO a temp `HOME` (`HOME="$H1" bash
"$KIT_DIR/install.sh"`), so `src != dst` and the truncation is harmless. The
documented user-facing layout was the one shape untested.

## Confirmation run-table

| # | Check | Command | Result | Verdict |
|---|---|---|---|---|
| 1 | New case passes with the fix | `bash tests/test-install-modules.sh` | 43 passed, 0 failed | PASS |
| 2 | New case FAILS without the fix (`git stash push install.sh`) | `bash tests/test-install-modules.sh` | 37 passed, **6 failed** | PASS (fails as designed) |
| 3 | Plugin-compat path unchanged | `bash tests/test-install-compat.sh` | `PASS: install compat` | PASS |
| 4 | Contract deploy unchanged | `bash tests/test-install-contract.sh` | `PASS=4 FAIL=0` | PASS |
| 5 | CLI shims unchanged | `bash tests/test-install-clis.sh` | all 20 passed | PASS |
| 6 | Resolver unchanged | `bash tests/test-config.sh` | `PASS kit-config selftest` | PASS |
| 7 | Reserved-key guard unchanged | `bash tests/test-reserved-config-guard.sh` | 9 run, 9 passed | PASS |
| 8 | Sync cron install unchanged | `bash tests/test-sync-cron-install.sh` | 29/29 passed | PASS |

`tests/test-config-registry.sh` reports 17/19 both with and without this change
(`0 orphans on the live tree`, `TIER4_CLOSE strips the annotation`) — pre-existing
on a clean `1f7209c`, untouched here.

## Negative control

Row 2 is the negative control, and it is the load-bearing one: with `install.sh`
stashed back to the buggy version, all 6 new checks fail with the exact clobber
signature, so the test cannot pass vacuously.

```
FAIL  in-place install: rendered kit.toml keeps every section (missing: [ledger] [mega] [gate] [features] [sync])
FAIL  in-place install: kit.toml did not shrink (160 -> 12 lines)
FAIL  in-place install: render header appears exactly once (got 2)
FAIL  in-place install: resolver still reads a non-[modules] key (mega.wave_cap=<unset>)
FAIL  in-place install: [modules] recomputed from --with board (board=true)
FAIL  in-place install: [modules] recomputed from --with board (stats=false)
```

With the fix, the same 6 report `160 -> 166 lines`, header count 1, and
`mega.wave_cap=2`.

## Reproduce

```bash
SB=$(mktemp -d); mkdir -p "$SB/home/.claude"
git clone -q https://github.com/dwarvesf/dwarves-kit.git "$SB/home/.claude/dwarves-kit"
wc -l "$SB/home/.claude/dwarves-kit/kit.toml"            # 160
cd "$SB/home/.claude/dwarves-kit"
env HOME="$SB/home" CLAUDE_DIR="$SB/home/.claude" bash install.sh >/dev/null 2>&1
wc -l "$SB/home/.claude/dwarves-kit/kit.toml"            # 12 before the fix, 166 after
```

## Recovery for an already-clobbered install

The checkout is a git repo and `kit.toml` is tracked, so the stub is one command
away from repaired — no reinstall needed:

```bash
git -C ~/.claude/dwarves-kit checkout -- kit.toml
```
