# Sub-goal 03: plannotator-gate-trial (the human-gate surface, wrapper + ledger emit + live trial)

**Merge policy:** gate
**Time budget:** 1.5-2 hours of loop work + one Han hands-on review window
**Proof:** recorded live run: one REAL gate artifact (THIS sub-goal's own held PR/diff: the trial IS the review, deliberately self-referential; do not hunt for an unrelated pending gate) reviewed through the wrapper end-to-end (browser annotate -> decision JSON -> gate-ledger line with the verdict + feedback digest); wrapper test suite green incl. the fail-open NC; the phone-over-Tailscale checkpoint result (works / does not, with the observed behavior); verdict paragraph (adopt / park) in the experiment README.
**Design:** bearing
**Depends on:** 05 (stacked on it in the ops chain; no semantic dependency).
Model: sonnet
**Branch:** `feat/plannotator-gate-trial`
**PR base:** `docs/ops-review-contracts`
**Over-test: yes** (the wrapper sits in the human-gate path; a silent failure here fakes or drops a gate decision)

## Outcome

ID-262 / A1: `experiments/plannotator-gate/` per experiments/README.md (frontmatter, INDEX.md row, LAB_LOG line):

(a) **Verified install**: download the pinned release binary, verify checksum/SLSA attestation (NEVER curl|bash), record version + hashes in the README.
(b) **Wrapper `pl-gate <file> [--rid <rid>]`**: runs `plannotator annotate <file> --gate --json`; on decision, appends a gate-ledger line (`GATE | human-gate | ran | reason=<approved|denied> findings=... actor=<git user.name> feedback digest`, grammar consistent with 02's KV style) and saves the full decision JSON under the experiment's gitignored data dir. Deny feedback is printed in the OPERATE.md triage-first contract frame (05's contract) ready to hand to a worker.
(c) **Live trial**: Han reviews one real held gate artifact through it during the gate window for THIS sub-goal's PR (the trial is the review).
(d) **Phone checkpoint**: attempt the same review from the iPhone over Tailscale against the fixed-port remote mode; record reachability + usability honestly.
(e) **Verdict**: adopt (wire into the mega gate flow as the default surface) or park (reasons), written in the README; adoption itself is a FOLLOW-ON row, not this sub-goal.

## Quality bar

ONE wrapper deep, swappable (bus-factor-1 upstream, commercial trajectory): the kit/mega flow never learns plannotator's name, it calls `pl-gate`. Fail-open surface, fail-visible log: plannotator missing, non-zero exit, or malformed JSON = fall back to the manual gate flow with a visible warning; NEVER a fabricated ledger line, NEVER a silent pass. No secrets to the binary; loopback bind by default (Tailscale reach tested as a checkpoint, not shipped as default config).

## How to close the loop

- Wrapper tests (bats or plain bash asserts): approve path emits the ledger line; deny path carries the feedback digest + contract frame; malformed JSON -> fallback warning, NO ledger line; missing binary -> same; NC proven load-bearing by deliberate break (feed garbage JSON, assert no ledger write).
- Live capture: the real decision JSON (redacted if needed) + the ledger line + `kit_gates` parsing it.
- Phone checkpoint: one honest paragraph + screenshot path if it works.
- Immediately before opening the gate window: re-check the sibling-overlap condition (one `git log`/`gh pr list` glance at OPERATE.md + the kit review commands since this mega's own merges; advisor P6: the draft-time guard check does not cover mid-run drift, and the live trial is this mega's one unrepeatable moment).
- Verdict carries a NUMBER: one honest low-n sample of manual-baseline vs pl-gate time-to-decision (or turns-to-decision), per the n-rule 05 just landed; adopt/park is argued from it, not vibes (advisor P6).
- Experiment hygiene: frontmatter, INDEX.md row, gitignore for decision data.

**Done =** wrapper tests green incl. break-NC, one real gate decision recorded end-to-end in the ledger, phone checkpoint recorded, verdict written.

## Handoff on completion

1. Flip ROADMAP box + PR #. 2. HOT `HANDOFF.md`: next is 04-review-yield-lens (confirm 02 merged first; hand it 02's grammar note). 3. `DECISIONS.md`: pinned version + hashes, ledger-line grammar, verdict. 4. EXIT.

## Scope edges

**In:** `experiments/plannotator-gate/` (README, wrapper, tests, gitignore), INDEX.md row, LAB_LOG line.
**Out:** wiring the wrapper into OPERATE.md/mega as the default gate surface (follow-on row on an adopt verdict); the compound/feedback-mining loop (ID-266, parked).
**Not:** plannotator's plan-mode hook (we do not adopt ExitPlanMode interception; the kit's gates are file artifacts); any auto-approve; feeding it secret-bearing files; a daemon (the server lives only for the review session).

## Where to look

`research/2026-07-04-pxpipe-plannotator-improve-absorption.md` §2 (A1, caveats incl. the approve-with-notes gap); plannotator docs for `annotate --gate --json` + remote/SSH mode (fixed port 19432); SPEC-002 mobile pilot notes for the Tailscale path.

## PR body

plannotator gate-surface trial: verified pinned install, `pl-gate` wrapper (annotate --gate --json -> gate-ledger line + saved decision JSON, triage-first deny frame), fail-open NC proven by deliberate break, live gate review recorded, phone-over-Tailscale checkpoint, adopt/park verdict. GATE: the trial is Han's hands-on review. Covers ID-262.

## Notes
