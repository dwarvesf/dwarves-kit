# Decision Brief: sanitize board-sourced prompt text before an autonomous agent reads it

Run: autonomous. The six forcing questions were self-answered with the recommended answer and
ledgered as `verdict=wave` debt, one row per question. No human was at the keyboard.

## Verdict: BUILD (narrow)

## Core thesis
The `#auto` path types file text into a `--dangerously-skip-permissions` Claude session, and the
board row that selects that file is the only thing deciding which text. Sanitize the text at the
one place it enters the prompt, before a second board editor makes the question urgent.

## The six questions

**Q1: What is the real user pain?** Honestly, none today. One operator edits the board, and that
operator writes the `#auto` marker by hand. The pain is latent: the moment a second person can
edit `_meta/BACKLOG.md`, or the loop ingests a GitHub issue body, a row can steer an unattended
privileged session. OpenHands shipped that shape and got CVE-2026-33718 plus two published
exfiltration chains for it. The honest framing is defense-in-depth on a schedule, not a fire.

**Q2: What is the 10x version?** gh-aw's structural separation: the agent runs read-only, emits
NDJSON safe-outputs, and a separate permission-controlled job writes after a model-judge threat
detector returns a `safe` verdict. Then even a fully compromised agent cannot modify state.

**Q3: What is the simplest version that proves the thesis?** One ordered `sanitize_cell()` over the
text before it is typed, one XPIA preamble in front of it, and one post-run check on protected
paths. All three are bash, all three are testable today with real injection fixtures.

**Q4: What will you cut?** Homoglyph mapping (TR#39 confusables), the domain allow-list, mention and
GitHub-reference neutralization, template-delimiter escaping, bot-trigger rate limiting,
min-integrity author trust, NDJSON safe-outputs, and the model-judge threat-detection job. Every
one of them costs more than it buys on a single-operator markdown board.

**Q5: What breaks at scale?** Not throughput: one sanitize pass per launched row, on a file of a few
kilobytes. The real break is the size cap. Real pointer prompts in this repo run to 4 KB and one
notes file reaches 15 KB, so a cap set at a board-cell scale would silently truncate legitimate
work. The cap must sit well above real content and must leave a visible marker.

**Q6: What is the exit criteria?** The injection-fixture suite is green, including a negative
control, and the shipped watcher and queue tests stay green. Failing either means the guard either
does not work or broke the loop it protects.

## Strongest argument for
The whole layer is one small bash function plus two call sites, and the day the threat becomes real
is the day it is too late to add it calmly.

## Strongest argument against
Nothing can currently exploit it, and a sanitizer that mangles a legitimate goal prompt breaks a
working loop to defend against a hypothetical. This is why the transforms are limited to ones that
cannot change the meaning of honest text, and why the cap is generous.

## Two material corrections the interrogation produced

1. **The Notes cell is not the text that reaches the model.** `parse-board.sh` already reduces a
   row to a charset-gated `#queue{repo=,pointer=}` token; the row's prose never leaves the parser.
   What actually reaches the prompt is the POINTER FILE BODY, read by `_goal_line` in
   `lib/queue/queue.sh` and typed into the session. Sanitizing the Notes cell would sanitize a
   string nobody reads. The real surface is the pointer body on the untrusted path, and the board
   row is what selects it.
2. **A deny-glob cannot prevent a write.** The launched session runs with
   `--dangerously-skip-permissions`; no bash wrapper can intercept its file writes. The deny-glob
   can be stated in the prompt as a rule, and it can be DETECTED after the run and converted into a
   `gated` verdict that reaches a human. Claiming prevention would be a lie.

## Recommended scope for v1
`sanitize_cell()` with the ordered pipeline, the XPIA preamble, the post-run protected-path check.
The safe-outputs separation is deferred behind a named tripwire.
