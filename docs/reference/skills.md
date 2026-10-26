# Skills (Claude-triggered)

Skills have no slash command. Claude loads one when your intent matches its description. The hook inventory lives in [`hooks.md`](hooks.md), every command in the [command reference](../MANUAL.md#command-reference-the-kit-invokes-these-from-your-intent-you-rarely-type-them), and every agent in the [agents table](../MANUAL.md#agents-dispatched-not-invoked). The generated one-row-per-feature view is [`FEATURES.md`](FEATURES.md).

| Skill | What it does |
|-------|-------------|
| backlog-reconcile | Audits a repo's `_meta/BACKLOG.md` Active queue (audit-loop instance, general-purpose): row `Status` verdicted against its `Target artifact` spec's own `Status:` header or a git-log match, fixes behind a PR gate |
| doc-drift | Whole-estate doc audit (audit-loop instance): enumerates every living doc, verdicts each claim against the live repo, fixes drift behind a PR gate |
| ci-drift | Whole-estate CI audit (audit-loop instance): enumerates every workflow + GitHub-side state (enabled, secrets/vars, runners, releases, environment policy), verdicts each against the live repo, fixes drift behind a PR gate |
| gauntlet-proof-audit | Audits committed gauntlet run records (audit-loop instance, general-purpose): markers well-formed, recorded verdict vs committed `checker-output.txt`, findings-count reconciliation, scrub clean, run-dir grammar; REMOVE disallowed, report-first |
| repo-hygiene | Whole-repo decay audit (audit-loop instance, general-purpose): detectors over one checkout (unreferenced doc, stale staging drop, record parked in a control surface, log past its documented budget, large cold gitignored dir), each finding carrying its evidence inline, `git mv` the only fix it ever applies, PR-gated. Repo-scoped: the machine surface belongs to ops-toolkit `tools/disk-reclaim` |
| topology-drift | **Maintainer-only** (dwarves-kit repo dev only): audits THIS KIT's own feature estate (audit-loop instance), cross-checks the generated `docs/reference/FEATURES.md` registry against the `docs/reference/workflow-paths.md` path index both directions, re-places only delta features on the topology, PR-gated. To inventory a project the kit is pointed at, use `/kit:feature-map` instead |
| web-drift | Live-website agent-readiness audit (audit-loop instance, general-purpose): probes every site in `WEB_DRIFT_SITES` with `lib/webcheck` over read-only HTTP (groundwork, page, API tiers), verdicts each `(site, check)` pair, and files fixes as board rows in the repo that owns the site's source. Inert until the consumer declares its sites |
| get-api-docs | Fetches curated API docs via Context Hub before coding |
| loop-engineering | Designs a new bounded loop for the kit's orchestration: the gate (should this be a loop), then the anatomy (artifact / scanner / reviser / stop condition) on the generic bounded-revise engine |
| memory-tidy | Audits a repo's `.claude/memory` store: evidence-gated verdicts, PR-gated merges/deletions, index rebuild (judgment half of `stats memory-sweep`) |
| observe | Queries/renders the control plane (runs, gate verdicts, conformance, spend/cache economics, replay, dashboard) via the lib/bench CLIs |
| skill-review | Reviews + promotes skill drafts staged by skill-curator |
| stats | Queries/renders the ledger read plane (kept out of the stats library dir so it actually installs) |
| system-design | Owns a repo's `docs/SYSTEM-DESIGN.md` and renders it as a UML drawing set with the delta against a base ref marked new, changed or removed (engine: `lib/system-design/`) |

<!-- provenance: ADR-0034 -->
