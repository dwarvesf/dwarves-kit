# Spec: ship-clean distribution (remove Han-specific tooling from the adopter path)
Generated: 2026-09-01
Status: VALIDATED
Lane: normal
References: the distribution audit (this session, opus) that classified every Tier-3 leak; `tests/gauntlet/cleanroom/run-remote.sh` (the two runtime traps); `docs/guides/gauntlet-tutorial.md` (the correctly-marked precedent to imitate for SPEC-238's banner).

## Problem

When an external engineer adopts the kit on their own machine, three shipped surfaces reference Han-specific tooling as if it were the default, so the adopter either fails or is silently steered onto a tool they do not have. The audit confirmed the DEFAULT path is already clean (default gauntlet probe is Tier-1 `claude -p`, not omp; bg-run and the omp recipe are marked optional). Three MAJOR leaks remain, all on opt-in paths, all fixable by reframing to a Tier-1 default with the personal instance as a marked example.

1. `run-remote.sh` hardcodes `op://Toolkit/anthropic-api-key/credential` (Han's 1Password vault) as the default `probe_key_ref`, and `colima start` as the docker-down fallback (Han's runtime; an adopter may run Docker Desktop / OrbStack).
2. `agents/devops-triage.md` frontmatter pre-wires `Bash(wl-query*)` + `Bash(bash */cf-worker-state.sh*)` (ops-toolkit CLIs) and assumes Cloudflare Workers, despite prose telling the reader to swap them.
3. `SPEC-238-prepared-room.md` presents omp as first-class baked room toolchain with no "optional cheap-probe only" scoping, reading as if omp is standard kit infra.

## Solution

### Approaches considered

1. **Reframe each leak to a Tier-1 default + marked personal example** (chosen). No behavior removed; the default becomes universal, the personal instance stays as a documented example.
2. Delete the personal references entirely. Rejected: the omp/NW recipe and the Cloudflare triage are genuinely useful to Han and to any adopter with the same stack; the fix is framing, not deletion.
3. Move the personal bits out to ops-toolkit. Rejected: they are examples IN kit docs, not tools; relocating loses the teaching value.

### Chosen approach + why

Approach 1. Each fix makes the default work for anyone and keeps the personal instance visible as "example, substitute yours".

### Extensibility & boundaries

- The pattern is a distribution rule the kit should hold going forward: any shipped surface names a Tier-1 default first, a personal tool only as a marked example. Worth one line in the honesty section of PHILOSOPHY or the doc that governs shipped-surface hygiene.
- Boundary: this spec touches only the three audited surfaces; it does not re-audit the whole kit (the audit already did).

### Architecture

Doc/config reframes only; no new component. See `## Design`.

## Picture

```
 SHIPPED SURFACE          today (leaks)              after
 run-remote.sh     probe_key_ref = op://Toolkit  → op://<vault>/anthropic-api-key
                   docker down → colima start    → docker down → clear "start docker" error
 devops-triage.md  tools: wl-query, cf-worker    → generic log-query grant + "Cloudflare
                                                    example; swap your log CLI" scoping
 SPEC-238          omp baked as room toolchain   → banner: default probe = claude CLI;
                                                    omp/NW is the OPTIONAL cheap-probe bake
```

## Design

**Ordering:** the two runtime traps in run-remote.sh first (an adopter hits them), then the agent grant, then the spec framing.

### Approaches considered + chosen
Per `## Solution`.

### Diagram

```
 run-remote.sh probe_key_ref resolution:
   kit.toml [gauntlet] probe_key_ref  (operator sets THEIR ref)
     └─ unset → op://<vault>/anthropic-api-key/credential  (placeholder, not Han's Toolkit)
                 └─ still unset/fails → clear error naming the config key to set
 docker check:
   docker info >/dev/null 2>&1 || { echo "start your docker runtime (Docker Desktop / OrbStack / colima), then re-run"; exit 1; }
```

### ADR link(s)
None; reversible reframes.

### Boundaries & failure modes
Docs/config only; see `## Failure modes`.

## Technical Design

### Interfaces (I/O contract)

- `run-remote.sh`: default `probe_key_ref` becomes a neutral placeholder (`op://<vault>/anthropic-api-key/credential`) with the comment stating the operator sets it in `kit.toml [gauntlet]`; the docker-down branch becomes a runtime-agnostic error, not `colima start`. `secret-cache-read` stays (already falls back to `op read`; guard with `command -v` for clarity). Behavior for Han unchanged (his kit.toml sets the real ref).
- `agents/devops-triage.md`: the frontmatter `tools:` grant generalizes the log-query bash pattern (or the agent gains a one-line "Cloudflare Workers example; substitute your platform's log CLI + state script" scoping at the top so the pre-wired grants read as the example they are). The pre-wired `wl-query`/`cf-worker-state.sh` stay as the worked Cloudflare instance, clearly labeled.
- `SPEC-238`: a scoping banner near the top, the DEFAULT gauntlet probe is the Tier-1 claude CLI; this spec's omp bake is the OPTIONAL cheap-probe toolchain for an operator who runs the omp/OpenAI-compatible recipe, never forced on an adopter.
- Invariants: no default path requires a Han-only tool; every personal reference reads as a marked example; Han's own runs are unchanged (his kit.toml + estate supply the real values).

### Data model changes
None.
### API changes
None.
### UI changes
None.
### Infrastructure changes
None.

## Task Breakdown

### Phase 1
- [ ] TASK-001 (`tests/gauntlet/cleanroom/run-remote.sh`): neutral placeholder default for `probe_key_ref` + a comment pointing at `kit.toml [gauntlet]`; runtime-agnostic docker-down error replacing `colima start`; `command -v secret-cache-read` guard around that optional path. Acceptance: `grep -c 'op://Toolkit' run-remote.sh` = 0; `grep -c 'colima' run-remote.sh` = 0; `bash -n` + `shellcheck -S warning` clean; the local-runner leg (runner_host=local) is unaffected.
- [ ] TASK-002 (`agents/devops-triage.md`): a scoping line at the top marking it a Cloudflare-Workers example whose `wl-query`/`cf-worker-state.sh` grants are the worked instance to substitute; frontmatter description notes the platform assumption. Acceptance: the first body paragraph names "example, substitute your log CLI"; `grep -c 'wl-query' agents/devops-triage.md` unchanged (kept as the labeled example, not deleted).
- [ ] TASK-003 (`docs/specs/SPEC-238-prepared-room.md`): a scoping banner after the title stating the default probe is claude CLI and this omp bake is the optional cheap-probe toolchain. Acceptance: a line matching `default.*claude` appears in the first 15 lines; no logic/task change to the spec's body.
- [ ] TASK-004 (`docs/PHILOSOPHY.md` or the shipped-surface hygiene doc): one honesty-rule line: a shipped surface names a Tier-1 default first, a personal tool only as a marked example. Acceptance: the line exists and names "Tier-1 default" + "marked example".

## After state

- [ ] No shipped default path requires omp / bg-run / colima / an `op://Toolkit` ref. Checkable: `grep -rn 'op://Toolkit\|colima start' tests/gauntlet commands agents docs/guides docs/specs` returns nothing outside a marked-example context.
- [ ] `run-remote.sh` runs on any docker runtime with the operator's own key ref. (Today: hardcoded to Han's vault + colima.)
- [ ] devops-triage reads as a Cloudflare example, not a universal default. (Today: pre-wired, prose-caveated only.)
- [ ] SPEC-238 scopes omp as optional. (Today: reads as baked kit infra.)

## Acceptance Criteria (global)

- [ ] `bash tests/test-meta.sh` failure set stays a subset of master's
- [ ] `shellcheck -S warning tests/gauntlet/cleanroom/run-remote.sh` clean
- [ ] The After-state greps pass

## Verification

```
cd <worktree>
grep -c 'op://Toolkit' tests/gauntlet/cleanroom/run-remote.sh   # 0
grep -c 'colima' tests/gauntlet/cleanroom/run-remote.sh          # 0
shellcheck -S warning tests/gauntlet/cleanroom/run-remote.sh
grep -iE 'default.*claude' docs/specs/SPEC-238-prepared-room.md  # >=1
bash tests/test-meta.sh
```

## Edge Cases
1. Han's own remote run: his `kit.toml [gauntlet] probe_key_ref` sets the real ref, so the neutral key default is never reached; key behavior unchanged. The docker-down branch DOES change for everyone (it no longer auto-runs `colima start`); a runner host is expected to keep its docker runtime up, and a clear error beats silently starting one specific runtime, so this is an accepted uniform change, NOT config-gated (battery follow-up correction).
2. An adopter with no kit.toml ref and no key: the clear error names the config key to set, instead of silently failing on a missing Han vault.
3. An adopter on Docker Desktop: the runtime-agnostic docker-down message applies; colima is one named option among several.
4. devops-triage on a non-Cloudflare stack: the scoping line tells them to substitute; the agent does not silently assume Workers.

## Failure modes
| Failure class | Detection signal | Mitigation / recovery |
|---|---|---|
| A reframe changes Han's own behavior | edge case 1 + the local-runner test | the KEY default is config-gated (his kit.toml pre-empts it); the docker-down branch changes uniformly by design (no auto-colima), accepted since a runner keeps docker up |
| Deleting instead of reframing loses teaching value | ACs keep wl-query/omp as labeled examples | grep counts assert they stay |

## Out of Scope
- Re-auditing the whole kit (the audit already classified every hit; OK-tier items stay).
- Provenance/lineage refs in specs (`Source:`/`Board:` pointing at ops-toolkit paths), they never break a run, only point at repos an adopter cannot open; noted, not fixed.
- Moving any tool between repos.

## Review

### Verdict: SHIP (battery, first cold /kit:battery run, post-merge on #463)

### Findings (disjoint arms, the battery's own thesis reproduced)

- Leg 1 acceptance-verify (fresh Sonnet): PASS 4/4 tasks + 3/3 global; caught an ENVIRONMENTAL contamination re-execution alone reveals: local gauntlet-campaign room debris (`J*/kit/`, `J*/fixture-repo/`) carries nested `test-meta.sh` copies that trip the SPEC-031 stale-string check, showing 8 fails locally vs the true 7 in a clean worktree. Debris cleared from the working tree.
- Leg 2 review + advisor + folded security angle (fresh Opus): SHIP, 2 MINOR honesty-gaps a static read reveals: (a) the docker-down branch changes uniformly, not config-gated as the Failure-modes table claimed; (b) the empty-key error named "1P session", not `gauntlet.probe_key_ref`. Both fixed on the follow-up branch.
- One AC-wording note (leg 1): TASK-002's literal "wl-query count unchanged" moved 3->4 because the new scope sentence itself names the CLI; DEC-001's intent (keep as labeled example, don't delete) held. AC wording, not a defect.
- No BLOCKER/MAJOR; no new Tier-3 leak reachable on the default path (neighborhood grep clean).

Disagreement between arms IS the result: each caught a class the other structurally could not (contamination vs prose-honesty).

## Decision Log
- DEC-001: reframe, never delete; the personal instances teach.
- DEC-002: defaults become Tier-1 (claude CLI, neutral op:// placeholder, runtime-agnostic docker check); personal values come from the operator's kit.toml/estate.
- DEC-003: the audit's OK-tier items (provenance comments, parameterized `<owner>` paths, dormant hooks, optional-marked recipes) need no change; only the 3 MAJOR + the 1 hygiene-rule line are in scope.

## Open questions
(none)
