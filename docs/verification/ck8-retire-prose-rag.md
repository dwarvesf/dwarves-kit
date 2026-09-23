# Proof: ck8-retire-prose-rag

Date: 2026-09-23
Branch: chore/ck8-retire-prose-rag
Change: `bin/prose-rag` becomes an alias over context-kit's folded engine (`ctx index|query|hook`); config seam resolves the full ladder so a ctx-only install reads `filled`. No duplicate engine copy remained (retired in #516).

## Green run

| Command | Exit | Verdict |
|---|---|---|
| bash tests/test-prose-rag-adapter.sh (incl. new ctx PATH stub, 3 cases) | 0 | PASS 36/36 |
| bash tests/test-config-seams.sh (new cases 9e/9f) | 0 | PASS 56/56 |
| bash tests/test-bin-forwarders.sh | 0 | PASS 48/48 |
| bash tests/test-config-registry.sh | 0 | PASS 50/50 |
| bash tests/test-kit-contract.sh | 0 | PASS 25/25 |
| bash tests/test-meta.sh | 0 | PASS 854/854 |
| bash tests/test-install-clis.sh / test-install-modules.sh | 0 | PASS 22/22, 42/42 |
| env -u NO_COLOR TERM=xterm bash tests/test-hooks.sh | 0 | PASS 498/498 |
| bash tests/test-intake.sh / test-no-scattered-ids.sh / test-no-personal-paths.sh | 0 | PASS 27/27, 9/9, 3/3 |

## Live smoke (real ctx build)

Against `context-kit/.claude/worktrees/ck8-fold-engine/src/target/release/ctx` on PATH:

| Check | Result |
|---|---|
| `prose-rag index` on a temp corpus | indexed |
| `prose-rag query` | returned `[0.64] path :: heading` hit shape |
| `prose-rag hook --force` | injected the prior-notes block |
| ctx-on-PATH resolution + no-engine hint | both behave |

## Negative control

Drop the ctx/prose-rag stubs from PATH in the adapter tests → the no-engine cases (hook exit 0, unconfigured index exit 0, else hint + exit 1) still hold, proving the shim did not change the absent-engine contract. Revert restores green.

## Not proven here (gated on context-kit#14 merge)

- Re-running install.sh so `~/.claude/dwarves-kit/bin/prose-rag` picks up the forwarder.
- Live `PROSE_RAG_INJECT=1` in a real session and the launchd `prose-rag-index` job on the installed copy.

## Caveat

`ctx` on PATH is a generic name; a foreign `ctx` would be exec'd for the engine verbs. `PROSE_RAG_BIN` remains the override.
