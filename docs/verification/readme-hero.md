# Proof of done: README hero + parity pin (SPEC-113, kit-face wave)

The README hero is a native mermaid lifecycle (replacing the ASCII), the directory-layout counts
match live reality (24 agents, 17 hooks), and a new test-meta parity pin makes the agents-count
drift class die like the hooks/commands pins did.

## Acceptance criteria

| # | Criterion | Result |
|---|---|---|
| 1 | Mermaid hero (6 phases + gate classes) replaces the ASCII lifecycle | PASS |
| 2 | GitHub renders the mermaid fence as a diagram (not a code block) | PASS (gh markdown API tags it `highlight-source-mermaid`) |
| 3 | Two gate classes named (blocking / advisory) | PASS |
| 4 | Trust-story sentence (re-audit + advisor + deployable-done), not 5 bullets | PASS |
| 5 | Directory-layout counts corrected: agents 24, hooks 17 | PASS |
| 6 | NEW parity pin: README agents/hooks layout counts == live file counts (computed) | PASS |
| 7 | WORKFLOW.md keeps ASCII canon + gains the `docs/v-model.svg` link | PASS |
| 8 | Credits intact; test-meta + all 12 CI green | PASS |

## Implementation

- `README.md`: ```mermaid flowchart (goal -> think -> spec -> execute -> review -> ship -> retro,
  edges labeled advisory / BLOCKING) + a two-gate-classes sentence + the trust-story sentence;
  `agents/ (24 files)`, `hooks/ (17 scripts)`; old ASCII hero removed; Credits untouched.
- `WORKFLOW.md`: a blockquote linking `docs/v-model.svg` before "## The V-model lens"; ASCII V unchanged.
- `tests/test-meta.sh`: a README directory-layout parity pin , `README agents/ count == ls agents/*.md`
  and `README hooks/ count == ls hooks/*.sh` (computed, mirrors the architecture inventory pin). The
  agents pin is NEW (hooks already had a SPEC-085 pin; the AGENTS directory-layout count had none ,
  which is exactly why it drifted to 11).

## Confirmation run-table

| Case | Command | Expected | Observed |
|---|---|---|---|
| mermaid hero | `grep -qF '```mermaid' README.md` | match | match |
| old ASCII gone | `grep -qF 'goal --> think --> spec --> execute' README.md` | no match | absent |
| counts corrected | `grep -qE 'agents/ *\(24 files\)'` / `'hooks/ *\(17 '` | match | match |
| parity pin | `bash tests/test-meta.sh` (README agents/hooks layout count == live) | 24==24, 17==17 | PASS |
| gate classes | `grep blocking && grep advisory` README.md | both | both |
| WORKFLOW svg | `grep -qF 'v-model.svg' WORKFLOW.md` | match | match |
| GitHub render | `gh api -X POST /markdown -f text=<hero>` | mermaid recognized | `class="highlight highlight-source-mermaid"` |
| suite | `bash tests/test-meta.sh` | green | 661/661 |
| all CI | 12 suites | green | all pass |

## Run detail (captured 2026-07-03)

```
$ bash tests/test-meta.sh
  PASS README agents/ layout count == live agents (24 == 24)
  PASS README hooks/ layout count == live hooks (17 == 17)
Passed: 661 / 661 ; All meta tests passed.
$ gh api -X POST /markdown -f text="$(sed -n '10,30p' README.md)" | grep -o 'highlight-source-mermaid'
highlight-source-mermaid        # GitHub renders the fence as a mermaid diagram
```

## Reproduce

```bash
cd dwarves-kit
bash tests/test-meta.sh
grep -qF '```mermaid' README.md && grep -qE 'agents/ *\(24 files\)' README.md
grep -qF 'v-model.svg' WORKFLOW.md
```
