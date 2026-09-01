# SPEC-002, Sync mesh: multi-source, multi-object, audience-filtered sync

Status: DRAFT 2026-07-16, thinking model for review. Successor/generalization
of SPEC-001 (hub-and-app todo sync) and SPEC-147 (bridge cockpit mirror);
implements kit board row ID-290 and extends it with audience filtering.

## The model: everything is a PROFILE

One engine (lib/sync), many configured profiles. A profile is one
named pipe between the hub and a destination, carrying its own five
answers (graph-theory readers: an edge). Terminology: the far end of a
profile is a SURFACE (a place the same task shows up: Reminders, Notion,
a Hermes board, Multica); hub-and-spoke readers know it as a spoke, and
the config key is `apps` (legacy aliases `surfaces`, `sources`); the
profile's HUB-side inputs are `boards`/`registry`, so the two sides
never share a word:

```
profile = (source-set, target, direction, object-filter, audience-filter)
```

```
   SOURCES (hubs, git-owned truth)          TARGETS (apps / cockpits)
   ┌────────────────────────────┐           ┌──────────────────────────┐
   │ repo BACKLOG.md (×13)      │ profiles  │ Apple Reminders (device) │
   │ _meta/megagoals/*/ROADMAP  │ ────────▶ │ Notion DB (work-visible) │
   │ .claude/goals/* (goal file)│ ◀──────── │ Hermes kanban (per-HOME: │
   │ _meta/backlog-staging.md   │           │  personal/family/cockpit)│
   └────────────────────────────┘           └──────────────────────────┘
```

Today's two features are just two profile shapes:
- SPEC-001 sync = profile(1 repo board → N personal apps, two-way, todo, all)
- SPEC-147 bridge = profile(N repo boards + megagoals → 1 cockpit board,
  mirror-out + status-writeback, todo+megagoal, all)

## Dimension 1, object types (identity, truth, natural direction)

| Type | Identity (origin key) | Truth lives in | Natural direction | App shape |
|---|---|---|---|---|
| todo (board row) | `<repo>:ID-NNN` (origin field lands in the ENGINE at P2; today's engine keys bare `ID-NNN`, safe only while profiles stay single-repo) | BACKLOG.md | two-way (status/title/notes) | task/card/reminder |
| mega-goal | `megagoals:<repo>/<slug>` | git (ROADMAP + goals/) | mirror-out only in v1; a app-side "done" gets a comment ("close via git"), never a writeback (ROADMAP completion is emergent from checkboxes, no single field to flip) | progress card |
| goal (single /goal) | `goal:<repo>/<file>` | `.claude/goals/` , which is GITIGNORED per-machine scratch, NOT git truth | DEFERRED past P3; if ever wired, refused for shared/multi-writer apps (two machines would fight under one key and leak session scratch) | progress card |
| staged candidate | `staging:<repo>/<n>` | backlog-staging.md | NOT synced (pre-intake; promote first) | none |

Type transition case: a todo that graduates into a mega-goal keeps its row
(pointing at the megagoal). The row stays the synced object; the megagoal
card is a SECOND object with its own origin key. No re-link magic needed.

## Dimension 2, direction per profile

| Direction | Meaning | Conflict rule |
|---|---|---|
| two-way | full SPEC-001 semantics | hub wins; app deletions tombstone |
| mirror-out | create/update/close on target; target edits ignored (except below) | hub always wins |
| status-writeback | mirror-out + the ONE reverse path: target done/archived → hub status flip | as SPEC-001 status logic |
| intake-only | target additions become hub inbox rows; nothing pushed out | n/a |

## Dimension 3, audience filter (the sync-down / sync-up question)

Filters are per (profile, app), applied at plan time, both directions.

**Down (hub → app): which rows may appear on this app at all.**
Predicates, AND-combined; all optional:
- `status`: default `active` (today's behavior)
- `tags_include` / `tags_exclude`: e.g. Notion (Dwarves-visible) gets
  `tags_exclude = "family,personal-finance"`; a family-bot profile gets
  `tags_include = "family"`
- `assignee` (RESERVED until the board grows an assignee convention; hermes
  kanban and Notion people-props can hold it, BACKLOG.md cannot yet)

**Up (app → hub): which foreign items may become board rows.**
- `intake`: `all` (today) | `tagged:<tag>` | `none`. A shared app (family
  hermes board) with `intake = tagged:ops` only imports items the family
  explicitly marked for Han; the rest of their board never touches his hub.

**Scope-exit rule** (a mirrored row stops matching the down-filter, e.g. it
gains `#family` and the app excludes family): reverse-status resolution
runs FIRST (a app-side "done" still flips the hub row before the exit),
then the app item is closed/archived, state link kept (re-opens if it
re-enters scope). Guard: if one (profile, app) run would scope-exit more than
`scope_exit_cap` items (default 20), abort THAT app with a report; the
override for legitimate bulk exits (first filter rollout, registry
shrinkage) is `--allow-scope-exit N`, and `--filter-preview` reports the
would-exit list read-only so the operator raises the cap consciously.

**Untagged-row quarantine** (the privacy race: a row intaken on one app is
untagged, so nothing excludes it from a shared app on the very next profile):
intake-born rows get `#inbox` appended to their Notes automatically; shared
apps ship with `tags_exclude = "inbox"` in their suggested config, so
nothing propagates until first human triage removes the tag.

**Privacy invariant** (the reason up-filters exist): a profile to a shared
app must never receive rows excluded by its down-filter, and never
propagate another app's private items (apps never talk to each other;
everything routes through the hub, which applies each profile's own filter).

## Dimension 4, topology / multi-source

A cockpit profile reads MANY sources (the boards.txt registry + megagoal
folders). Identity is the origin key (repo-prefixed), which is exactly how
bridge already keys its snapshot, migration is a key-format map. Two profiles
may share one physical target (cockpit board receives todo cards and
megagoal cards); origin keys keep them disjoint.

## Config sketch (ADR-0034 layer, flat keys per parser)

```toml
[sync]
profiles = "personal,cockpit"

[sync.profile.personal]                # today's SPEC-001 behavior, named
apps = "reminders,notion,hermes"
objects = "todo"
notion_exclude_tags = "family"      # per-app down-filter
reminders_intake = "all"
hermes_intake = "all"

[sync.profile.cockpit]                 # bridge, ported (ID-290)
registry = "_meta/boards.txt"
objects = "todo,megagoal"
direction = "status-writeback"
hermes_home = "~/.hermes"
hermes_board = "megagoals"
```

(Parser note: `[sync.profile.personal]` section names work with the existing
`_kit_toml_get` because sections match literally; `kit_config_get`'s
first-dot split needs a helper for 3-level keys, small resolver addition,
or flatten to `profile_personal_*` keys if we refuse to touch the resolver.)

## Case checklist (to be adversarially extended)

| # | Case | Covered by |
|---|---|---|
| 1 | app deletion | tombstone (SPEC-001, unchanged) |
| 2 | both-sides edit | hub wins + conflict report (unchanged) |
| 3 | row leaves audience scope | scope-exit rule + cap guard |
| 4 | row re-enters scope | state link kept → reopen |
| 5 | foreign item on shared app | intake filter |
| 6 | same row via two apps changed differently | profiles run sequentially against the hub; second profile sees first's result; board file lock serializes |
| 7 | two profiles, one physical target | CONFIG-REJECTED: one physical target belongs to at most ONE profile per object type (validation at load); origin keys only separate object TYPES on a shared cockpit, they do not make cross-profile writes safe |
| 8 | todo ↔ megagoal transition | separate objects; row keeps pointing |
| 9 | mega-goal card edited on app | per-app capability: Notion mirror-out overwrites next run; HERMES CANNOT (no title/body edit verb) → append a correcting comment, original text stays; documented |
| 10 | repo renamed / board moved | origin keys break → treated as delete+create; documented, accepted |
| 11 | filter typo mass-archive | scope_exit_cap abort + --allow-scope-exit override + --filter-preview |
| 12 | state loss | title-prefix / idempotency-key adoption (SPEC-001, proven) |
| 13 | bare-ID collision across repos pooled on one app | P2 engine gains an `origin` field in items + snapshot entries; bare-ID matching allowed only for single-repo profiles |
| 14 | untagged intake row leaks to a shared app before triage | `#inbox` quarantine tag + shared-app `tags_exclude=inbox` default |
| 15 | first-rollout / registry-shrink mass scope-exit | `--filter-preview` then `--allow-scope-exit N` (cap is per profile+app) |
| 16 | scope-exit and app-side "done" in the same run | reverse-status resolves first, then exit |
| 17 | bridge snapshot migration | NOT a key map: bridge NDJSON stores only origin/hermes_id/hash + a 4-state vocab; P2 migrates by FRESH EXTRACT seeding (adopt-by-origin), and the terminal-retention change (bridge drops done rows, sync keeps links for reopen) is called out as intended |
| 18 | multi-profile partial failure | profiles are independent + idempotent; a failed profile is reported and the run continues; per-profile board writes are already atomic + self-healing on retry |
| 19 | config shape drift P1→P2 | P1 filter keys land flat under `[sync]` and become the implicit `default` profile when P2 introduces `[sync.profile.*]`; flat keys stay as aliases |
| 20 | 3-level config keys | resolve pre-P2: `kit_config_get` splits on the LAST dot (behavior-identical for all existing 2-level callers) |

## Implementation phases (each independently shippable)

1. **P1, audience filters on today's profile** (tags/status down-filter +
   intake up-filter + scope-exit rule + cap): small, pure-planner change +
   config keys; immediately fixes "personal rows visible in the Dwarves
   Notion workspace".
2. **P2, named profiles + multi-source extract + cockpit port** (ID-290):
   bridge retires to thin aliases; snapshot migration.
   - FIRST SLICE LANDED (`lib/sync/cockpit.py`): the two deterministic legs,
     multi-source EXTRACT (registry rows + active mega-goals, origin-prefixed
     identity) and the keyed `row_hash` git-wins TRANSFORM/diff (CREATE /
     UNCHANGED / CHANGE / COMPLETE). Carries over the reachable-state map
     `{triage, ready, blocked, done}` and the git-wins rule. Reachable via
     `board mirror --engine sync --dry-run`; legacy stays the default.
   - STILL DEFERRED: the live Hermes LOAD leg, two-way writeback (SPEC-149),
     snapshot state-shape migration, named-profile config (`[sync.profile.*]`),
     and retiring `mirror`/`status`/`writeback` to thin aliases. The legacy
     engine (board-mirror.sh + board-writeback.sh) stays runnable until then.
     SECURITY CARRY-OVER for the LOAD leg: it MUST wrap every card title/body/
     comment built from board content through `cockpit.mark_untrusted_title` /
     `mark_untrusted_body` (the ported `MIRROR_UNTRUSTED_*` markers), so the
     prompt-injection boundary the legacy engine set is not dropped.
3. **P3, megagoal + goal object types** (progress-card mapper, mirror-out).
4. **P4, assignee predicate** (blocked on a board assignee convention).
