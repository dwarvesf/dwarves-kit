# Sub-goal 05: vps-mon bridge + /status surface

**Time budget:** ~4-5h · **Depends on:** none (channel decided) · **Branch:** feat/cc-elev-r3-05-vps-mon-bridge · **PR base:** main

## Outcome

The weekly cc-intel / cc-observe intelligence stops being a file Han must open and instead reaches
him through the **already-built vps-mon channel**: the digest's key metrics are **ingested by
vps-mon** and the summary is **surfaced on the public `/status` page**. This closes the deferred
channel decision (resolved 2026-06-15 = vps-mon + `/status`, NOT Discord/Notion) and supersedes
`cc-elevation-r2` SG-01 (cc-notify).

## Quality bar

Minimum-infra: reuse vps-mon's existing heartbeat/ingest + `/status` render (SPEC-065/066/067); do
NOT stand up a new listener or dashboard. cc-intel already runs weekly on the Air, so the bridge is
the cc-intel launcher POSTing `cc-observe report --json` (or a distilled subset) to vps-mon's ingest
endpoint, plus a `/status` section. Secrets via `op://` / existing vps-mon token; never hardcoded.
Read-only producer (cc-observe/cc-intel stay read-only); only vps-mon stores.

## How to close the loop

- Decide the payload: the full `--json` is large; distill to the headline metrics (subagent per100 + mix, top friction signals, hook-error count, cost-by-model). Define the ingest shape with vps-mon.
- Wire the cc-intel weekly launcher to POST after it writes the digest file (append to the launcher, keep the file write).
- Add a `/status` section (or a vps-mon catalog entry) rendering the latest digest summary; route by the right channel/account per vps-mon's model.
- **Monitoring-onboarding:** per the `job-monitoring-onboarding` rule, the new POST/ingest path itself must show `monitored` (a stale-digest heartbeat: if no digest in >8 days, vps-mon flags it).
- Verify: trigger cc-intel once (`launchctl kickstart -k ... cc-intel-weekly` or `cc-intel run` + POST), confirm the metric lands in vps-mon and renders on `/status`; negative control: a missing/old digest shows as a gap/stale, not silently green.

**Done =** the weekly digest's headline metrics are POSTed to vps-mon and visible on the public `/status` page, the ingest path is itself monitored (stale-digest heartbeat), proven by one real run + a stale negative control; r2 SG-01 marked closed; on PR #NN.

## Scope edges

**In:** payload distillation, the cc-intel->vps-mon POST, the `/status` section, the stale-digest heartbeat, closing r2 SG-01.
**Out:** the signals themselves (01-04 produce them; 05 only delivers what exists); Discord/Notion channels (rejected); native OTel (SG-06).
**Not:** a new daemon/listener; a new dashboard; hardcoded secrets; making cc-observe write state.

## Where to look

`tools/vps-mon/` (ingest + heartbeat + `/status` render, SPEC-065/066/067; memory `vps-mon-two-instances` , two Worker deployments, pick the right one), cc-intel deploy launcher `tools/cc-intel/deploy/macos/cc-intel-weekly`, `cc-observe report --json` shape, the `job-monitoring-onboarding` skill, `op://` for the vps-mon ingest token, `cc-elevation-r2/goals/01-cc-notify.md` (the superseded channel sub-goal).

## PR body

Outcome: weekly cc-intel/cc-observe metrics ingested by vps-mon + shown on the public `/status`; closes the deferred channel decision (vps-mon + /status) and r2 SG-01.
Verify: one real run lands a metric on /status; stale-digest negative control shows a gap not green; ingest path is itself monitored.
Roadmap: `_meta/megagoals/cc-elevation-r3/ROADMAP.md` (sub-goal 05).
