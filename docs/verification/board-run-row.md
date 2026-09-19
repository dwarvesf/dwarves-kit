# Verification -- board-run-row

`board run <ID>` is the single-board-row dispatch path: it reads the row's Item +
Notes through a new `backlog.sh row` verb, scaffolds the minimal mega-goal dir
`lib/queue/orchestrate.sh` expects (one `- [ ] SG-01 <item> , auto` ROADMAP line,
POINTER_PROMPT.md seeded from the row, a `goals/01-*.md` contract, HANDOFF.md +
DECISIONS.md stubs) under the repo's megagoals convention, and prints the exact
`orchestrate.sh run <dir>` command. It never launches a session; `--exec`
composes the launch and forwards args after `--`.

## Green run
```
Command: bash tests/test-board-run.sh
Exit: 0
Verdict: 35/35 assertions pass -- scaffold shape (ROADMAP SG-01 auto line,
  POINTER_PROMPT seeds item + notes verbatim, goals/01 contract carries routable
  Model: + **Branch:** headers, HANDOFF/DECISIONS stubs), `orchestrate.sh next
  <dir>` reads the SG row back (`SG-01\tauto`, dry-run-level proof, no claude
  launch), the printed run command, --dir override, megagoal_root: hint,
  in-use-root detection (docs/megagoals, .claude/goals with a megadir child;
  drafts-only .claude/goals correctly falls to the _meta default), --exec
  passthrough to `orchestrate.sh run --dry-run`, idempotent re-run, the 6-col
  row shape, and the four negative cases (absent ID, duplicate ID, missing
  board, terminal-state row warn-and-proceed).
```

```
Command: bash tests/test-board.sh
Exit: 0
Verdict: 50 pass, 0 fail, 1 skip (NC-e ops-toolkit sibling render, absent in
  this environment by design). Existing board verbs unchanged: the `run` case
  is a new dispatch branch, cmd_board_single is untouched.
```

```
Command: bash tests/test-orchestrate.sh && bash tests/test-board-set-note.sh && bash tests/test-board-dedupe-all.sh && bash tests/test-stable-interface.sh && bash tests/test-bin-forwarders.sh
Exit: 0 (all five)
Verdict: test-orchestrate ALL PASS; test-board-set-note ALL PASS;
  test-board-dedupe-all ALL PASS; stable-interface PASS; bin-forwarders 48/48.
```

```
Command: bash tests/test-hooks.sh && bash tests/test-meta.sh
Exit: 0 (test-hooks 498/498; test-meta 852/853 before FEATURES regen, fresh after)
Verdict: the lone test-meta failure was the docs/FEATURES.md freshness pin
  (SPEC-219) on the new test file's trigger refs; `feature-registry.sh check
  --fix` regenerated it and `check` now exits 0.
```

## Negative control
```
## Negative control (negctl)
Command: bash tests/test-board-run.sh
Exit: 0 (green before mutation)
Mutation: sed -i '' '/    row)        row/ s/^    row/    XXXrow/' lib/board/backlog.sh
Changed: lib/board/backlog.sh
Exit: 1 (under mutation, RED expected)
Restore: git checkout HEAD -- lib/board/backlog.sh
Exit: 0 (green after restore)
Verdict: PASS
```

## Not proven
- No real `claude -p` session was launched: every orchestrate touchpoint is
  `next` or `run --dry-run` (and `--exec -- --dry-run` in AC8). The end-to-end
  launch path is unchanged orchestrate machinery, not new code.
- The `megagoal_root:` hint is honored only from the repo's CLAUDE.md, matching
  commands/mega.md's documented precedence; a hint in AGENTS.md is not read.
