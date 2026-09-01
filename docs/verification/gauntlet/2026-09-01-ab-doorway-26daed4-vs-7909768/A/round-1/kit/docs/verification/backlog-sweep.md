# Proof of done: backlog reconcile sweep

Type: reconcile. Contract (`proof-gate.sh contract`): inventory with a verdict per item +
reference-fix diff; a seeded drifted item is caught.

## Scope

Audited every `queued` (53 rows) and `executing` (8 rows) Active-queue row in
`_meta/BACKLOG.md` against merged-PR / commit evidence. Rows already covered by a
labeled historical section (`## Parked`, the "Terminal -- shipped / dropped ... audit
trail" block) were out of scope: that section is a deliberate kept record, not a
schema violation.

## Inventory with verdict per item

| ID | Verdict | Evidence |
|----|---------|----------|
| ID-402 | FIX -> shipped | PR #389 merged 2026-08-11 (`0e4388b`), `agents/slop-stripper.md` added + wired into `/kit:review-team` |
| ID-404 | FIX -> shipped | PR #388 merged 2026-08-11 (`fbfed00`), `commands/grill.md` carries the facts-vs-decisions split |
| ID-481 | FIX -> shipped | PR #427 merged 2026-08-26 (`f9b8874`), `lib/sync/sync_core.py` carries the `UNTRUSTED_PREFIX` marking on intake-born rows |
| ID-459 | FIX -> shipped | PR #333 merged 2026-07-31, SPEC-223 `sanitize_cell` pipeline landed |
| ID-460 | FIX -> shipped | PR #330 merged 2026-07-31, three runaway guards (stale-window watchdog, circuit breaker, dual-condition exit gate) landed |
| ID-461 | FIX -> shipped | PR #334 merged 2026-07-31, draft-PR-by-default + per-row spend ceiling landed |
| ID-390, ID-421, ID-424, ID-425, ID-438 | OK, kept executing | Each row's own status-cell annotation names concrete remaining work (e.g. ID-438: "REMAINING: wire the doctor line into /forge:start"); no merged-PR evidence contradicts that |
| ID-100, ID-298, ID-305, ID-307, ID-308 | OK, kept queued | Spot-checked via `git log --all -i --grep` on the row's distinguishing terms; zero hits |
| ID-423 | OK, kept queued | Partial: one commit unparks its L3 layer only; L1/L2 of the row's 3-layer ask are unbuilt, so the row is not closable yet |
| ID-431 | OK, kept queued | One commit landed design docs only (`docs(fleet): commit the fleet design set`); the row asks for the registry + sync engine itself, unbuilt |
| Remaining ~46 queued rows | OK, kept queued | No `git log --grep <ID>` hit; these are 2026-07-25-dated forward-looking roadmap/product items, several explicitly HAN-GATED, consistent with the zero-hit spot check above |

## Green run

```
$ grep -E "^\| ID-(402|404|481|459|460|461) \|" _meta/BACKLOG.md | awk -F'|' '{print $1, $(NF-1)}'
  shipped [PR #389 merged 2026-08-11, agents/slop-stripper.md + review-team wiring]
  shipped [PR #388 merged 2026-08-11, commands/grill.md facts-vs-decisions split landed]
  shipped [PR #427 merged 2026-08-26 (f9b8874), lib/sync/sync_core.py UNTRUSTED_PREFIX marking on intake-born rows]
  shipped [PR #333 merged 2026-07-31, SPEC-223 sanitize_cell pipeline landed]
  shipped [PR #330 merged 2026-07-31 (SPEC-220/221 runaway guards: stale-window watchdog + circuit breaker + dual-condition exit gate)]
  shipped [PR #334 merged 2026-07-31 (SPEC-224: draft-PR-by-default + per-row spend ceiling)]
```

Exit: 0. Verdict: PASS, all six rows carry `shipped` plus the evidence note.

## Negative control

Reverted `ID-402` back to its pre-sweep `queued` state with the mutation tool itself
(`bash lib/board/backlog.sh set ID-402 queued`), then re-ran the same evidence check:

```
$ grep -E "^\| ID-402 \|" _meta/BACKLOG.md | awk -F'|' '{print $(NF-1)}'
  queued [PR #389 merged 2026-08-11, agents/slop-stripper.md + review-team wiring]

$ git log --oneline --all --grep="ID-402" -F
0e4388b feat(agents): slop-stripper behavior-preserving slop strip pass (kit ID-402) (#389)
```

MISMATCH: board says `queued`, merged commit `0e4388b` (PR #389, 2026-08-11) already
implements the row -> RED, correctly caught. Restored with the same mutation tool:

```
$ bash lib/board/backlog.sh set ID-402 shipped "PR #389 merged 2026-08-11, agents/slop-stripper.md + review-team wiring"
ID-402 -> shipped
```

`git diff _meta/BACKLOG.md` after the restore shows zero residual difference against the
committed state (verified: the restore round-trips byte-for-byte).

## Apply mechanics

The only mutation used was `bash lib/board/backlog.sh set <ID> shipped "<evidence note>"`
per row, six calls total. No row was hand-deleted or hand-edited outside that tool; no
row outside the six above was touched.
