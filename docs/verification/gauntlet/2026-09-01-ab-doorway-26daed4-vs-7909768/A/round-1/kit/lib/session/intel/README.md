# session-intel

A weekly read-only intelligence digest for my Claude Code + repos. One dated file, four sections, proposals only (it never edits the ledger, GLOSSARYs, til, or boards). No LLM, no mini.ollama: synthesis + repeat-detect are deterministic heuristics a human reviews.

Part of `cc-elevation-r2` (sub-goal 06). Folds the cc-elevation Axis-6 sweeps (#3) + cross-session synthesis (#4) + repeat-sequence detection (#5).

## What it assembles

| Section | Source | What |
|---|---|---|
| Claude Code usage | `session-observe report` | skill / tool / hook usage + latency |
| Repo health | `repo-sweep run` | cross-repo deterministic sweeps |
| Merge proposals | ledger + GLOSSARYs | concept names that repeat (normalized) -> merge candidates |
| Repeated sequences | recent transcripts | bash 3-grams repeated >= N -> extract-workflow candidates |

session-observe / repo-sweep are shelled out and degrade to `_unavailable_` if missing.

## Use

```bash
session-intel run                 # write ~/.claude/intel/intel-YYYY-MM-DD.md
session-intel synthesis           # just the merge proposals (stdout)
session-intel repeat --min 3      # just the repeated-sequence proposals
session-intel propose             # the SAME two proposal classes, staged for the Learn gate
session-intel propose --dry-run   # print the blocks, write nothing
```

## Schedule (weekly)

Deploy artifacts in `deploy/macos/` (BTM-friendly launcher + rendered plist +
installer; optional consumer bridge hook). See `deploy/macos/README.md`.
Minimum-infra: a LaunchAgent calling the existing CLIs, no new daemon or listener.

## Test

```bash
bash tests/smoke.sh          # -> smoke: all 6 passed
```

## Notes

- Propose-don't-dispose: writes only the digest; the human acts on the proposals.
- Deterministic by choice (no Haiku): cheaper, testable, no API dependency, and a human reviews the proposals anyway.
- Env (tests): `SESSION_INTEL_OBSERVE_CMD`, `SESSION_INTEL_SWEEP_CMD`, `SESSION_INTEL_DATE`.
