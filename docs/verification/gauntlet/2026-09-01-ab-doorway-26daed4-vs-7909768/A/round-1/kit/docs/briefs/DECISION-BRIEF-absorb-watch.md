# Decision Brief: absorb-watch (upstream skill-repo tracking with zero new infra)

Date: 2026-07-25 · Source: operator ask ("even if they have a slight improvement on the skill, we
need to take care of it") + the skills-repo delta read. Status: DRAFT (feeds ID-403). Consuming
row: ID-403. Record: `docs/research/2026-07-25-skills-repos-onboarding-absorption.md` §5.

## Verified current state

/kit:absorb already exists (maintainer-run upstream-sources audit: Credits drift + seed rescan,
proposal-only, scored by docs/ABSORPTION.md). What it lacks: per-seed WATCH SIGNALS and last-seen
markers, so every rescan is a cold re-read and rescans happen on vibes.

## The design (decisions made)

1. **Watch the curated signal, never the commit feed.** Per seed, register the cheapest
   high-signal index the upstream author already maintains:
   - mattpocock/skills: `CHANGELOG.md` version. MINOR bump = re-read that entry; PATCH = skim.
     Also any commit subject matching `Add|graduate|promote|rename .* skill|ship.*plugin`.
     Cadence: monthly. Last seen 2026-07-25: v1.2 (ADR-0002 plugin ship).
   - zvadaadam/az-skills: closed-PR titles (`Add * skill`) or any PR touching
     `scripts/install.sh` / `.githooks/` (install-mechanism changes alter how absorbing works).
     Cadence: quarterly. Last seen 2026-07-25: PR #21.
2. **Markers live in the absorption record** (the research file's watch-markers table), updated
   after each check, so the next check is a diff, not a re-read.
3. **No daemon, no cron.** The check is two URL fetches inside the existing /kit:absorb rescan
   (or the operator's periodic sweep). Minimum-infra rule: a watch earns automation only when
   manual checks demonstrably lapse (that failure, if it happens, unparks a patrol row).
4. Dedup discipline unchanged: a fired signal routes through the absorb pipeline (VERDICTS gate
   first); a watch hit is a REASON to read, never an auto-absorb.

## North-star conformance (§6)

N6 (the framework improves because upstream moved, with a measurable trigger, not vibes);
defer-don't-own (the upstream author's CHANGELOG/PR titles ARE the index; we build none).

## Exit criteria

1. ABSORPTION.md carries both seeds with signal + cadence + last-seen columns.
2. A /kit:absorb rescan against unchanged upstreams completes with zero deep reads (the marker
   short-circuit works).
3. A simulated MINOR bump (marker rolled back by hand) correctly flags exactly one entry to read.
