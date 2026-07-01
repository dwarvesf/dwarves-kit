# Implementation notes , meta-agent drafter (SG-05)

Delta from `ops-toolkit/_meta/megagoals/token-optim-v3/goals/05-meta-agent-drafter.md`.

## 2026-07-01 , golden fixtures ARE the run, not hand-written

The proof asks for a run-table showing the drafter produces lint-passing outputs. A subagent
definition is a prompt, so "running" it means dispatching Claude. I dispatched a subagent that
strictly follows `agents/meta-agent.md` on two real one-line descriptions; its outputs are committed
as `tests/fixtures/meta-agent/*.md` and the test lints THOSE. So the fixtures are genuine drafter
output (the run), not boilerplate I wrote, and the test is deterministically reproducible against the
committed goldens.

## 2026-07-01 , the kit's own guards forced roster sync (expected, not scope creep)

Adding `agents/meta-agent.md` + `commands/draft-agent.md` made `tests/test-meta.sh` fail 3 drift
checks: the MANUAL.md agent cross-ref, the `docs/architecture.md` V-phase inventory row-count, and
the `README.md` command count+rows. These are the kit's anti-drift guards doing their job: a new
agent/command is "not done" until the roster docs reflect it. Updated all three. This is required
for CI green, not optional polish.

## 2026-07-01 , test em-dash check uses raw UTF-8 bytes, not grep -P

macOS BSD grep has no `-P` (PCRE). The em-dash guard in `tests/test-meta-agent.sh` uses
`LC_ALL=C grep -qF "$(printf '\xe2\x80\x94')"` so it runs on both macOS and Linux CI.

## 2026-07-01 , PR base is master, not main

Goal file said `PR base: dwarves-kit main`; the repo default is `master` (confirmed via
`git symbolic-ref refs/remotes/origin/HEAD`). Based the branch + PR on `master`, matching the
POINTER_PROMPT ("SG-05/06 -> dwarves-kit master").

## 2026-07-01 , Mode C: same-run specialist dispatch (Han directive) + auto-classify in /kit:execute

The real ask behind "trigger immediately at runtime": during SDD, a task with no predefined agent
should get a specialist synthesized AND dispatched THIS run. Hard CC constraint: the subagent registry
is frozen at session start, so a file written now is not dispatchable by name until next session, the
default-install path (below) is next-session, wrong lever for this. Fix: the kit's `/kit:execute`
already dispatches each task worker as a generic Task-tool call with a prompt (no per-task role agent),
so immediacy = synthesize a role PREAMBLE in-session and inject it into that worker. Added:
- meta-agent **Mode C** (inline role spec): returns NAME / TOOLS(advisory) / PREAMBLE, writes NO file,
  no DRAFT marker. TOOLS is advisory because an inline-dispatched general worker cannot be
  tool-restricted (only a registered agent file's frontmatter can), a real limitation of the immediate
  path; the minimal set is named for the human + the cache.
- `execute.md` **2b-0**: classify each task's domain by a cheap INLINE keyword heuristic (no subagent
  hop), reuse a predefined/cached specialist if present, else dispatch Mode C, inject the preamble into
  the worker NOW, and cache the spec to `~/.claude/agents/<name>.md` (local, next-session reuse, no repo
  churn / no roster-sync burden). No-domain-match falls through to today's generic worker.

Trigger policy = **auto-classify every task** (Han chose it over spec-opt-in / complex-only). Mis-fire +
cost mitigated by: classification is inline (no LLM hop), synthesis fires only on a clear domain match,
and generic is the default fall-through, so plain tasks are unchanged. Reconciliation with the
default-install path: install-to-repo (`/kit:draft-agent`) = the deliberate, reviewed way to make a
specialist a SHARED, named kit agent; Mode C + `~/.claude/agents/` cache = the automatic, local,
immediate path. Two mechanisms, one for reuse-by-name, one for use-now.

## 2026-07-01 , default-INSTALL (Han directive, supersedes the draft-only Done=)

The SG-05 goal specced "draft-only, never installs." Han changed it post-build: he wants the
meta-agent to output an agent "triggerable immediately at runtime," and chose default-install over an
opt-in flag or a personal-dotfiles home. Implemented as: the SUBAGENT still only drafts to staging
(unchanged, stays minimal-tool), and the `/kit:draft-agent` COMMAND (running as the main agent, full
tools) installs by default , strip marker -> `agents/<name>.md` -> roster-sync (MANUAL/architecture/
README) -> `bash tests/test-meta.sh` -> `cp` to `~/.claude/agents/<name>.md`. `--draft` is the opt-out.
Why the command, not the subagent: install needs Edit/Bash for the roster rows + the runtime copy,
which the minimal subagent deliberately lacks. Runtime reality: CC discovers agents at session start,
so "immediate" = live next session/reload, not mid-conversation. Team safety preserved at the git
layer: install writes the local `~/.claude/agents/` copy + uncommitted repo edits; teammates only get
the agent when it is committed + merged (still PR-reviewed). The read-before-live gate is dropped
locally; mitigated by printing the granted tools loudly + trivial undo (`rm`). Install-promotion is
proven by a simulated test (strip marker -> lint-passing marker-free `<name>.md`).

## 2026-07-01 , staging path, never agents/ directly

The drafter writes to a `drafts/`-style staging path (the test used `tests/fixtures/meta-agent/`),
never into `agents/` or a live `goals/` dir. Writing into `agents/` would BE self-installing and
would also trip the MANUAL.md cross-ref guard. Install (move + MANUAL row + strip DRAFT marker) is
the explicit human step, documented in `commands/draft-agent.md` step 4.
