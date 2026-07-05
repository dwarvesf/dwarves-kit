# Implementation notes: cc-self-improve Phase B (cc-elevation-r4 sub-goal 03)

Delta from SPEC-103 (TASK-006..010) + goal `03-promote-and-surface.md`. Only what the spec/goal
does NOT already pin.

## 2026-06-19, promote core is `lib/promote.sh` + `bin/skill-review`; SKILL.md is thin
- The testable promote logic (list / promote / reject / secret-scan / refuse-overwrite) lives in
  `lib/promote.sh` behind a `bin/skill-review` CLI so the guard tests can drive it without a model.
  `skills/skill-review/SKILL.md` is the human slash-command: it runs the writing-skills checklist
  then calls the CLI. The skill does NOT reimplement writing-skills (goal quality bar).

## 2026-06-19, reject MOVES to `_rejected/`, never `rm`
- "reject discards" is implemented as a move to `skill-proposals/_rejected/<slug>/`, not a delete,
  to honor propose-don't-dispose + never-delete-without-ask (same posture as the curator's
  git-mv-never-rm). Recoverable; keeps the active list clean.

## 2026-06-19, staging-gate test proves path-safety, not a live CC load
- TASK-006 part 1 ("a proposal is not auto-invocable by CC") can't be unit-tested without launching
  Claude Code. The test asserts the STRUCTURAL gate: `proposals_dir != skills_dir` and a staged
  draft lands only under proposals/. Part 2 ("reviewer can't write under skills/ on an adversarial
  transcript") is tested concretely: a mock draft with a path-traversal slug (`../../skills/evil`)
  is sanitized by `safe_slug` so it cannot escape proposals/; plus the source pins `--allowedTools
  ""` (the model has no write at all).

## 2026-06-19, install/uninstall operate on CC_SI_SETTINGS (tests), default ~/.claude/settings.json
- `deploy/install.sh` / `uninstall.sh` read-merge-write a settings.json via jq, keyed on the
  command path containing `cc-self-improve` (idempotent: twice = no dup entries), backup first.
  `CC_SI_SETTINGS` overrides the target so tests run against a temp file. **Not run against the live
  ~/.claude/settings.json in this loop** (host change + a concurrent loop is using this machine);
  delivered + tested, the operator runs it.

## 2026-06-19, SessionStart surfacing reads cc-harvest's ledger for the memory count
- The surfacing line = staged-memory count (cc-harvest `_meta/learned-ledger.md` queued rows) +
  skill-draft count (proposals dir) + 7-day loop spend (cc-self-improve ledger). The memory source
  path is `CC_SI_MEMORY_LEDGER` (default the ops-toolkit learned-ledger). Emits the SessionStart
  `hookSpecificOutput.additionalContext` JSON shape.

## 2026-06-19, auto_promote knob: minimal + SAFE (references-add only), default OFF
- The OPTIONAL knob is implemented as plumbing with the lowest-risk eligibility: auto-pass ONLY a
  proposal explicitly tagged `cc-si-kind: references-add` whose named umbrella ALREADY EXISTS under
  skills/ and which passes the secret scan; it writes `references/<topic>.md` INTO the existing
  umbrella, never a new skill, never a SKILL.md-body edit. 02's reviewer does not yet emit
  references-add drafts, so by default nothing auto-promotes even when the knob is on , it is
  forward-looking, and structurally cannot auto-create or auto-edit a skill body. Documented in the
  config comment.
