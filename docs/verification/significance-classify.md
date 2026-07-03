# Proof of done -- significance-classify (SPEC-123)

## Acceptance criteria

| # | Criterion | Result |
|---|---|---|
| AC1 | significant AND worthy change taps | PASS |
| AC2 | NEGATIVE CONTROL: significant-but-low-worthiness is WAVED, not tapped (anti-fatigue) | PASS |
| AC3 | obvious change is not-significant | PASS |
| AC4 | impl-note entry raises worthiness (FEED) | PASS |
| AC5 | each verdict writes the debt-ledger marker, additive (never masquerades as a GATE line) | PASS |
| AC6 | determinism: same input -> same output | PASS |
| review-fix | 4/7 previously-untested regex triggers now individually asserted; tunable knob tested; lane-classify subprocess failure now fails loud, not silent | PASS |
| regression | full corpus suite (`test-meta.sh`) unaffected | PASS |

## Confirmation run

```
$ bash tests/test-significance-classify.sh
=== significance-classify: worthy-tap (AC1) ===
  PASS AC1 significant + worthy (data model + primitive) -> tap (tap)

=== significance-classify: anti-fatigue NEGATIVE CONTROL (AC2) ===
  PASS AC2 [NC] significant-but-low-worthiness is WAVED, not tapped (wave)

=== significance-classify: obvious change (AC3) ===
  PASS AC3 obvious/cosmetic change is not-significant (not-significant)

=== significance-classify: impl-notes FEED (AC4) ===
  PASS AC4a no impl-note entries -> still waved (wave)
  PASS AC4b non-empty impl-note flips worthiness low->high -> tap (tap)

=== significance-classify: per-trigger regex coverage (review MEDIUM fix) ===
  PASS design-bearing trigger fires significance (fired: significance: high (design-bearing))
  PASS new-public-surface trigger fires significance (fired: significance: high (new-public-surface))
  PASS novel trigger fires worthiness (asserted by name, not incidental) (fired: worthiness: high (novel))
  PASS blast-radius trigger fires worthiness (fired: worthiness: high (blast-radius))
  PASS must-explain trigger fires worthiness (fired: worthiness: high (must-explain))

=== significance-classify: tunable knob SIGNIFICANCE_WORTHINESS_MIN (review MEDIUM fix) ===
  PASS default SIGNIFICANCE_WORTHINESS_MIN=1: one trigger -> tap
  PASS SIGNIFICANCE_WORTHINESS_MIN=2: one trigger no longer enough -> wave

=== significance-classify: edge cases (review LOW fix) ===
  PASS empty description classifies not-significant, does not error
  PASS --impl-notes pointing at a nonexistent file degrades to no-signal (wave, not a crash)
  PASS record auto-creates a nonexistent log dir (mkdir -p), does not error

=== significance-classify: gate-ledger debt marker (AC5) ===
  PASS AC5a three record calls append exactly three | DEBT | lines
  PASS AC5b the tap verdict's marker carries significance=high worthiness=high verdict=tap
  PASS AC5c the wave verdict's marker carries significance=high worthiness=low verdict=wave
  PASS AC5d the not-significant verdict's marker carries significance=low verdict=not-significant
  PASS AC5e DEBT marker never masquerades as a | GATE | line

=== significance-classify: determinism (AC6) ===
  PASS AC6a classify: same input -> same output (tap)
  PASS AC6b explain: same input -> byte-identical output

=== significance-classify: coverage delta ===
  PASS coverage delta: DEBT-marker assertions went from 0 to 11 in this suite

=== significance-classify: wiring sanity ===
  PASS lib/significance-classify.sh exists and is executable
  PASS lib/gate-ledger.sh exposes a 'debt' subcommand

=== 25/25 passed, 0 failed ===
Exit: 0
```

```
$ bash tests/test-meta.sh | tail -3
=== Results ===
Passed: 662 / 662
All meta tests passed.
Exit: 0
```

## Run detail

- Repo: `dwarves-kit`, worktree `.claude/worktrees/ug-02`, branch `feat/ug-02-worthiness`.
- Environment: macOS, bash 5.x (via `/opt/homebrew/bin/bash` per shebang resolution), no network,
  no LLM calls inside the classifier itself (pure `grep -qE` regex matching + one subprocess call
  to the sibling `lane-classify.sh`).
- `tests/test-significance-classify.sh` isolates every ledger write into a `mktemp -d` directory
  via `DWARVES_KIT_LOG_DIR`; no writes land in the real `~/.claude/dwarves-kit/logs` (or its
  durable-dir equivalent) during the test run.
- Multi-lens review (SPEC-069, `lib/` touch): security 9/10, architecture 8/10, test-coverage
  7/10 pre-fix -> 25/25 post-fix (see `docs/implementation-notes/significance-classify.md` for
  the fix log). Fresh re-run of both suites above confirms no regression after the fixes.

## Reproduce

```bash
cd dwarves-kit   # or the ug-02 worktree
bash tests/test-significance-classify.sh
bash tests/test-meta.sh
```
