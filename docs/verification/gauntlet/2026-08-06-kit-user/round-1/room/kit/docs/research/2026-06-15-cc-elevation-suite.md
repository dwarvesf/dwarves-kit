---
title: Claude Code Elevation Suite, Operator Guide
date: 2026-06-15
purpose: >
  The operator manual for the cc-elevation tool suite (rounds 1 + 2): every feature,
  how it fires or how to invoke it, the enable/disable knobs, the deploy model, and the
  known decisions. Use when operating, enabling, disabling, or debugging any cc-* tool.
source_repos: [ops-toolkit, dotfiles]
refresh_cadence: as-needed
next_review: 2026-09-15
status: active
---

# Claude Code Elevation Suite, Operator Guide

12 tools + 3 saved workflows that push the Claude Code harness past guard/format/notify/inject
into self-knowledge, retrieval, correctness, and proactive agency. Built across two mega-goals
(`cc-elevation` round 1, `cc-elevation-r2` round 2). Analysis: `2026-06-14-claude-code-events-tools-elevation.md`.

## At a glance

| Tool | Type | Fires / invoke | What it does | PR |
|---|---|---|---|---|
| cc-context-hooks | hook: UserPromptSubmit | every prompt | temporal line (session elapsed + idle) + JIT skill hints (keyword -> skill, 69-key map) | #274, seed #275 |
| prose-rag | hook: UserPromptSubmit (opt-in) + CLI | recall prompts; `prose-rag query` | semantic search over til + research + ledger (local fastembed + sqlite-vec) | #265, gate #277 |
| cc-citation-guard | hook: Stop | end of every turn | flags hallucinated `file:line` citations in the last message | #263 |
| cc-money-gate | hook: PreToolUse(Edit\|Write) | money-file edits | gates edits to family-office / trading paths | #273 |
| cc-harvest | hook: PreCompact (+ SessionEnd) | compaction; session end | PreCompact: stage durable learnings to the ledger (Haiku). SessionEnd `--lab-log`: draft a LAB_LOG entry | #267, lab-log #290 |
| cc-observe | CLI + skill | "how am I using Claude Code" | usage + latency from session transcripts | #261 |
| repo-sweep | CLI + skill | "repo health / drift" | 6 read-only cross-repo sweeps + triage + learning-flush | #268/#269 |
| verify-claim | CLI + skill | "is that true / fact-check" | adversarial skeptic panel, majority HOLDS/REFUTED | #272 |
| meta-agent | CLI | "make a subagent for X" | generate a valid, scoped subagent spec from a description | #287 |
| cc-worktree-provision | CLI (manual; NOT a hook) | `--base <path>` | symlink a worktree's gitignored env + optional install | #278 |
| cc-intel | scheduled (launchd) + CLI | weekly Mon 09:00; `cc-intel run` | digest: cc-observe + repo-sweep + synthesis + repeat-detect | #282 |
| cc-workflows | saved Workflows + skills | by name | review-branch / research-sweep / cross-repo-sweep fan-outs | #280 |

## Hooks wired (live in ~/.claude/settings.json)

| Event | Command | Notes |
|---|---|---|
| UserPromptSubmit | `cc-context` | temporal + JIT hints (sub-ms) |
| UserPromptSubmit | `prose-rag hook` | recall-gated; only fires on "have I / did I / what did I conclude" shaped prompts |
| Stop | `cc-citation-guard` | log-only by default |
| PreToolUse(Edit\|Write) | `cc-money-gate` | family-office / trading paths |
| PreCompact | `cc-harvest` | ledger harvest |
| SessionEnd | `cc-harvest --lab-log` | only in repos with `_meta/`; drafts to that repo's `.lab-log-draft.md` |

There is deliberately **no WorktreeCreate hook** (see Known decisions).

## Enable / disable cheatsheet

All via env (set in `~/.claude/settings.json` `env`, or per-invocation):

| Knob | Default | Effect |
|---|---|---|
| `PROSE_RAG_INJECT=1` | on (set) | enables the prose-rag inject hook; unset = inert |
| `PROSE_RAG_NO_GATE=1` | off | bypass the recall gate (inject on every prompt) |
| `CC_CONTEXT_TEMPORAL=0` | off | drop the temporal line (keep skill hints) |
| `CC_CITATION_STRICT=1` | off (log-only) | block the turn on a bad citation instead of warning |
| `CC_MONEY_STRICT=1` | off (warn) | turn the money gate into an ask/block |
| `CC_HARVEST_LABLOG_DRAFT=FILE` | `<repo>/_meta/.lab-log-draft.md` | where the SessionEnd LAB_LOG draft is staged |
| `CC_HARVEST_EXTRACTOR=CMD` | `claude -p --model haiku` | the harvest LLM call |

To fully disable a hook: remove its entry from the `dotfiles` overlay (`home/dot_claude/modify_settings.json`) + `chezmoi apply`.

## Deploy model (branch-independent snapshot)

Deployed tools live at `~/.local/share/cc-elevation/` (a snapshot of `origin/main`), symlinked into
`~/.local/bin` + `~/.claude/workflows`. This is intentional: auto-firing hooks must not depend on
which branch the dev checkout happens to be on.

- **Re-deploy after editing + pushing a tool:** `bash ~/.local/share/cc-elevation/redeploy.sh`
- **Schedule:** `~/Library/LaunchAgents/cc-intel-weekly.plist` (BTM-friendly; ProgramArguments points at the snapshot launcher).
- **prose-rag** reuses the existing uv venv (fastembed + sqlite-vec); index at `~/.claude/prose-rag/index.db` (rebuild: `prose-rag index`).
- **cc-context** is deployed as a wrapper (not a symlink) so Python's `__file__` resolves and it finds its co-located `skills-map.json`.

## Known decisions

- **WorktreeCreate is not a provisioner hook.** The event is a creation-DELEGATE: the hook is expected
  to create the worktree and echo its path. Wiring a post-hoc provisioner there makes `EnterWorktree`
  fail. So `cc-worktree-provision` is a MANUAL tool (`cc-worktree-provision --base <path>`), and the
  overlay carries a `del(.hooks.WorktreeCreate)` guard so a provisioner can never be re-wired there.
- **Deterministic over LLM where a proposal suffices.** cc-intel synthesis + repeat-detect and the
  meta-agent scaffold are deterministic (testable, no API dependency); a human reviews the proposals.
- **No mini.ollama.** Embeddings = local fastembed on the Air; reasoning = Claude Haiku only.
- **Propose-don't-dispose.** cc-harvest, cc-intel, repo-sweep never write durable homes
  (ledger / LAB_LOG / GLOSSARY / til / boards); they stage or digest, the human commits.

## cc-notify (resolved 2026-06-15, native)

- **cc-notify** (phone push, BACKLOG ID-085): resolved by enabling **native push** (`agentPushNotifEnabled`
  + `inputNeededNotifEnabled` = true). Caveat: native push reaches the phone only when **Remote Control is
  active**; for terminal / mosh-to-Mini sessions it stays desktop-only. No extra tool built (Han's call). If
  Remote-Control coverage proves insufficient, the fallback is a `Notification`-hook `tools/cc-notify/`
  posting to Discord or ntfy (channel-independent); not built.
