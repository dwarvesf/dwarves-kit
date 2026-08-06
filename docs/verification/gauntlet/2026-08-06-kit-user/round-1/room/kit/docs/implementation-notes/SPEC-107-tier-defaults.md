# Implementation notes: SPEC-107 tier-defaults

Delta from the spec. References, does not restate.

## 2026-07-03 spec-validate findings resolved (wiring gate + honest "one stance")

- **Context:** the adversarial spec-validate returned CHANGES-REQUIRED. Two HIGH findings:
  (#1) the first-draft fixture re-encoded the sonnet-default rule inside the test (a
  tautology), not exercising a real dispatch reader, so it failed the mega-goal's binding
  WIRING GATE 04 ("the DEFAULT tier is actually APPLIED at dispatch; `_route`/execute reads
  it"); (#2) `_route()` (orchestrate.sh:396-403) treats an omitted goal-file `Model:` as
  INHERIT, not sonnet, so a naive "one stance = sonnet default" claim was a fresh contradiction.
- **Decision:** do NOT modify `_route()`. Goal-file 04 lists exactly three surfaces and says
  "Not: a fourth tier surface"; `_route` is the dispatch engine, not a surface. The sonnet
  default is a **write-time** default (surfaces 2+3 bake `Model: sonnet` INTO goal files); the
  existing `_route` reader then honors that explicit line at dispatch. The "positive default
  applied at dispatch, `_route` reads it" proof is the EXISTING test-orchestrate.sh:187-206
  fixture (a goal file carrying `Model: sonnet` -> orchestrator dispatches `--model sonnet`),
  cited, not re-encoded.
- **Why:** reconciles the goal-file's "Not: a fourth tier surface" with the ROADMAP wiring
  gate's "`_route`/execute reads it" without a `lib/` edit (keeps `normal` lane) and without a
  behavior change to core orchestrate routing. `_route`'s absent->inherit fallback is unchanged
  and IS the "deliberate OMIT = inherit" path assumption 04 wants preserved.
- **Honest split (finding #2):** the spec now names it explicitly , sonnet is the WRITE-TIME
  default (surfaces write the line); `_route`'s READ-TIME behavior on a hand-omitted line stays
  inherit. "One stance" is scoped to the authoring surfaces, not a claim that `_route` was
  changed.
- **Findings #3/#4 folded in:** verification gains a NEGATIVE grep proving the old meta-agent
  contradiction text ("human's call, not a silent auto-write") is GONE, not just that new text
  was added; and the spec adds no re-encoded `^Model:` grep (the `_route` reader is the single
  source, no divergent duplicate).
- **Surface-2 (dotfiles) is a LOCAL proof, not kit CI:** the template lives in the dotfiles
  repo (absolute `~/workspace/<owner>/dotfiles/...`), unreadable by kit CI, so its grep is a
  proof-table row run locally, never a `tests/` assertion.
