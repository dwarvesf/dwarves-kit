"""Anomaly detection over the SG-02 lens + a PROPOSE-not-autofile stager.

The feedback loop that stops the ledgers being write-only: ledgers -> lens -> anomaly ->
PROPOSED backlog row -> operator gate -> improvement.

Two hard contracts:

1. ONE DATA PATH. Every detector reads ONLY through `materialize.query` (the SG-02 lens).
   This module imports `materialize`; it never opens DuckDB itself and never reads a raw
   ledger file. Detection is pure read: `detect()` writes nothing.

2. PROPOSE, NEVER AUTO-FILE. When an anomaly fires, `stage_proposals` appends a `## [staged]`
   block to the cc-backlog STAGING BUFFER (`_meta/backlog-staging.md`, env `CC_BACKLOG_STAGING`)
   in the exact format `tools/cc-backlog` writes and `board promote` consumes. It opens the board
   `BACKLOG.md` READ-ONLY (for dedup) and NEVER writes it. The operator promotes via the existing
   `board promote` human gate (ex `add-backlog`, ADR-0034). This tool has no path to a board row.

Thresholds (open-fork 3) are defensible-default scaffolds + one `--threshold KEY=VALUE` flag to
tune. The two min-sample floors (`cost_window`, `misfire_min_runs`) are the load-bearing
false-positive guards: thin / noise-floor data proposes nothing.
"""

from __future__ import annotations

import datetime as _dt
import math
import os
import re
import statistics
import sys
from dataclasses import dataclass

from . import materialize

# --- thresholds (open-fork 3: defensible scaffolds, tune via --threshold) ----------------
# Every key is overridable by the single repeatable `--threshold KEY=VALUE` CLI flag. These
# are deliberately loose-ish scaffolds to be tightened after real ledger data accrues.
DEFAULTS: dict[str, float] = {
    "debt_max": 5.0,          # >5 accumulated waved gates (overrides) = debt piling up
    "cost_window": 5.0,       # rolling-median window AND min-sample floor for a cost spike
    "cost_multiplier": 3.0,   # latest cost > 3x the recent median = a spike, not variance
    "misfire_rate_max": 0.25,  # >25% of runs misrouting is signal, not noise
    "misfire_min_runs": 4.0,  # <4 runs => a rate is meaningless (1-of-1 = 100% false positive)
    "deviation_window": 5.0,      # rolling-median window AND min-sample floor (SPEC-133)
    "deviation_median_max": 2.0,  # rolling median n_deviations over this = unknown-density fire
    "ceremony_min_ran": 5.0,          # min-sample floor (SPEC-134): the gate's ran+override
                                      # count AND the evidence-sufficiency floor for
                                      # caught_known/bridged below -- NEVER conditioned on
                                      # skip-rate, see _detect_ceremony
    "serial_min_minutes_saved": 10.0,  # min plausible minutes-saved before the
                                       # serial-when-parallel advisor bothers proposing (a
                                       # 1-2 min saving is real-corpus noise, not worth a row)
    "token_budget_max": 50_000_000.0,  # per-session token-runaway budget (SPEC-135): total
                                       # input+output+cache tokens across a whole session's
                                       # transcript. Loose on purpose (open-fork 3 convention):
                                       # cache-read tokens are billed PER assistant turn, not
                                       # once, so even a normal long session can legitimately
                                       # sum into the tens of millions; tune down via
                                       # --threshold once real sessions data accrues.
    "memory_min_notes": 5.0,             # min-sample floor (SPEC-136): thin data proposes
                                          # nothing, same convention as cost_window/deviation_window
    "memory_dead_ref_rate_max": 0.15,    # >15% of memory units carrying >=1 dead ref is signal
    "review_fp_min_n": 5.0,       # dual min-sample floor (SPEC-137): BOTH a lens's own
                                  # n_rejected AND the global raised denominator must clear
                                  # this before the rate means anything -- same convention as
                                  # `review-yield --min-n`'s own low_n floor
    "review_fp_rate_max": 0.5,    # >50% of the (approximated) raised total attributed to one
                                  # lens's rejections is disproportionate, signal not noise
}


@dataclass
class Anomaly:
    key: str          # stable detector key
    title: str        # stable, COUNT-FREE (live numbers live in intent/approach, not here)
    intent: str
    approach: str
    tags: str         # e.g. "#u-mid #f-mid"
    home: str         # repo owning the signal (a note; the operator re-homes on promote)
    metric: str       # the observed value, for the report


# --- detectors: each reads ONLY via materialize.query (one data path) --------------------

def _detect_debt(th: dict) -> Anomaly | None:
    """Unpaid understanding-debt: SUM(kit_runs.gates_ovr). A gate override is a consciously
    WAVED gate = unpaid debt (the signal materialized in the lens today; see SPEC-129 DEC-004)."""
    _cols, rows = materialize.query("SELECT COALESCE(SUM(gates_ovr), 0) AS n FROM kit_runs")
    n = int(rows[0][0] or 0) if rows else 0
    if n <= th["debt_max"]:
        return None
    return Anomaly(
        key="debt",
        title="Feedback: unpaid understanding-debt over threshold",
        intent=(f"Pay down accumulated understanding debt: {n} waved gates (kit gate overrides) "
                f"exceed the threshold of {int(th['debt_max'])}."),
        approach=("Review the kit runs carrying gate overrides (kit_runs.gates_ovr) and engage the "
                  "deferred/waved items (weekend debt-paydown). Detected via `ledger anomalies`."),
        tags="#u-mid #f-mid",
        home="dwarves-kit",
        metric=f"gates_ovr_sum={n}",
    )


def _detect_cost_spike(th: dict) -> Anomaly | None:
    """Token-cost spike: the latest tide tier-B call cost vs the rolling median of the prior
    `cost_window` calls. The window is also the min-sample floor (no median => no fire)."""
    window = int(th["cost_window"])
    _cols, rows = materialize.query(
        "SELECT cost_usd FROM tide_tier_b_calls WHERE cost_usd IS NOT NULL ORDER BY id"
    )
    series = [float(r[0]) for r in rows if r[0] is not None]
    if len(series) < window + 1:  # min-sample floor: need `window` prior calls + the latest
        return None
    latest = series[-1]
    prior = series[-1 - window:-1]
    med = statistics.median(prior)
    if med <= 0 or latest <= med * th["cost_multiplier"]:
        return None
    return Anomaly(
        key="cost_spike",
        title="Feedback: token-cost spike vs rolling median",
        intent=(f"Investigate a token-cost spike: the latest call cost ${latest:.4f}, "
                f"{latest / med:.1f}x the rolling median ${med:.4f} of the prior {window} calls."),
        approach=("Check tide_tier_b_calls for the expensive call's backend/model; confirm it is "
                  "intended, not a runaway. Detected via `ledger anomalies`."),
        tags="#u-hi #f-mid",
        home="ops-toolkit",
        metric=f"latest={latest:.4f} median={med:.4f} mult={latest / med:.2f}",
    )


def _detect_misfire(th: dict) -> Anomaly | None:
    """Gate/proof misfire rate: fraction of kit runs with a routing misfire
    (lane_misroute/type_misroute). `misfire_min_runs` is the min-sample floor."""
    _cols, rows = materialize.query(
        "SELECT count(*) AS total, "
        "count(*) FILTER (WHERE lane_misroute > 0 OR type_misroute > 0) AS misfires "
        "FROM kit_runs"
    )
    total = int(rows[0][0] or 0) if rows else 0
    misfires = int(rows[0][1] or 0) if rows else 0
    if total < th["misfire_min_runs"]:  # min-sample floor
        return None
    rate = misfires / total if total else 0.0
    if rate <= th["misfire_rate_max"]:
        return None
    return Anomaly(
        key="misfire",
        title="Feedback: gate/proof misfire-rate over threshold",
        intent=(f"Investigate a climbing gate/proof misfire rate: {misfires} of {total} kit runs "
                f"misrouted ({rate:.0%}), over the {th['misfire_rate_max']:.0%} threshold."),
        approach=("Review kit_runs rows with lane_misroute/type_misroute set; check lane-classify + "
                  "the type registry for the misrouting pattern. Detected via `ledger anomalies`."),
        tags="#u-mid #f-mid",
        home="dwarves-kit",
        metric=f"misfires={misfires} total={total} rate={rate:.2f}",
    )


def _detect_unknown_density(th: dict) -> Anomaly | None:
    """Unknown-density (SPEC-133): rolling median `n_deviations` over the last
    `deviation_window` implementation-notes files (`impl_notes`), the upstream half of the
    benchmark bridge. Ordered by `first_ts` (a zero-marker file with no logged entry has no
    `first_ts` and sorts first via a sentinel -- the schema carries no filesystem mtime by
    design, see SPEC-133 -- a stated approximation, not true wall-clock order for those rows).
    `deviation_window` doubles as the min-sample floor (thin data proposes nothing, same
    convention as `cost_spike`'s `cost_window`)."""
    window = int(th["deviation_window"])
    _cols, rows = materialize.query(
        "SELECT repo, n_deviations FROM impl_notes "
        "ORDER BY COALESCE(first_ts, '0000-00-00 00:00'), slug"
    )
    if len(rows) < window:  # min-sample floor
        return None
    recent = rows[-window:]
    series = [int(r[1] or 0) for r in recent]
    med = statistics.median(series)
    if med <= th["deviation_median_max"]:
        return None
    home = recent[-1][0] if recent else "ops-toolkit"
    return Anomaly(
        key="unknown_density",
        title="Feedback: implementation-notes deviation density over threshold",
        intent=(f"Condition grill ON for {home}: the rolling median deviation count over the "
                f"last {window} implementation-notes files is {med:g}, over the "
                f"{th['deviation_median_max']:g} threshold."),
        approach=("Review the recent implementation-notes files (impl_notes.n_deviations) for "
                  "repeated mid-run deviations; the unknown-density conditioning design "
                  "(research/2026-07-04-fable-unknowns-absorption.md Design 1) proposes firing "
                  "grill for this repo/domain when density is high. Detected via `ledger "
                  "anomalies`."),
        tags="#u-mid #f-mid",
        home=home,
        metric=f"median={med:g} window={window}",
    )


# conventional-commit fix() subject, same convention cli.py's defect-correlation/deviation-rate
# use (a small deliberate duplication of that private literal, not a new shared module -- see
# SPEC-134 "After state").
_FIX_SUBJECT_RE = r"^fix(\(.*\))?!?:"


def _detect_ceremony(th: dict) -> Anomaly | None:
    """Ceremony (SPEC-134): a kit gate that structurally never mattered. Reads `kit_gates`
    (gate-yield's own GROUP BY gate shape) joined to a PER-GATE generalization of
    defect-correlation's rid-to-git bridge (SPEC-132 DEC-001's two-stage bridge: a textual
    rid-in-subject match once, then genuine file-equality thereafter -- same technique, applied
    to every gate's rids instead of only `gate='ship'`).

    Two conditioning signals, checked in priority order, NEVER a bare skip-rate (the FP-NC
    this guards against: a gate can be skipped ~86% of the time for an entirely legitimate
    reason -- e.g. `ui-design` skipped on every non-UI run on the real corpus -- and that alone
    must never look like ceremony):

    1. HARD (`caught`): when a gate has >= `ceremony_min_ran` ran+override rows carrying a
       KNOWN (non-NULL) `caught` value and NONE of them is true, propose CUT (definitive: real
       evidence it never caught anything).
    2. SOFT (fix-correlation proxy), only when `caught` is unknown/too-thin for that gate
       (`caught_known < ceremony_min_ran` -- true for the whole real corpus today, kit's OUTCOME
       bracket barely emits yet): if >= `ceremony_min_ran` of the gate's rids bridge to git AND
       NONE of the bridged files was later touched by a fix() commit, propose CONDITION (weaker
       confidence -- absence of a later fix is a proxy for "never mattered", not proof).

    Both floors gate on RAN+OVERRIDE evidence volume, never on how often the gate was skipped.
    Gates are checked in alphabetical order (deterministic); the FIRST one meeting either
    condition fires. Returns None if no gate has sufficient evidence either way (honest empty,
    same convention as `_detect_unknown_density`)."""
    min_ran = th["ceremony_min_ran"]
    sql = f"""
    WITH gate_agg AS (
        SELECT gate,
               count(*) FILTER (WHERE outcome IN ('ran', 'override')) AS ran,
               count(*) FILTER (WHERE outcome IN ('ran', 'override') AND caught) AS caught_true,
               count(*) FILTER (WHERE outcome IN ('ran', 'override') AND caught IS NOT NULL)
                   AS caught_known
        FROM kit_gates
        GROUP BY gate
    ),
    candidates AS (
        SELECT DISTINCT gate, rid FROM kit_gates WHERE outcome IN ('ran', 'override')
    ),
    mentions AS (
        SELECT DISTINCT c.gate, c.rid, g.sha, g.ts, g.files
        FROM candidates c
        JOIN git_fixes g ON contains(lower(g.subject), lower(c.rid))
    ),
    first_mention AS (
        SELECT gate, rid, min(ts) AS mention_ts FROM mentions GROUP BY gate, rid
    ),
    mention_files AS (
        SELECT m.gate, m.rid, fm.mention_ts, m.files AS file
        FROM mentions m
        JOIN first_mention fm ON fm.gate = m.gate AND fm.rid = m.rid AND m.ts = fm.mention_ts
    ),
    later_fix AS (
        SELECT sha, ts, files AS file FROM git_fixes WHERE regexp_matches(subject, '{_FIX_SUBJECT_RE}')
    ),
    fix_corr AS (
        -- count(DISTINCT mf.rid), NEVER count(*): mention_files is (gate, rid, file) grain --
        -- a single rid whose bridged commit touched N files must count as ONE sample of
        -- evidence, not N (a real over-test finding: counting file-rows lets one multi-file
        -- commit fake evidence-sufficiency for a gate with only one real invocation).
        SELECT mf.gate,
               count(DISTINCT mf.rid) FILTER (WHERE lf.sha IS NOT NULL) AS fix_followed,
               count(DISTINCT mf.rid) AS bridged
        FROM mention_files mf
        LEFT JOIN later_fix lf
            ON lf.file = mf.file
            AND CAST(lf.ts AS TIMESTAMPTZ) > CAST(mf.mention_ts AS TIMESTAMPTZ)
            AND CAST(lf.ts AS TIMESTAMPTZ) <= CAST(mf.mention_ts AS TIMESTAMPTZ) + INTERVAL (30) DAY
        GROUP BY mf.gate
    )
    SELECT ga.gate, ga.ran, ga.caught_true, ga.caught_known,
           COALESCE(fc.bridged, 0) AS bridged, COALESCE(fc.fix_followed, 0) AS fix_followed
    FROM gate_agg ga
    LEFT JOIN fix_corr fc ON fc.gate = ga.gate
    ORDER BY ga.gate
    """
    _cols, rows = materialize.query(sql)
    for gate, ran, caught_true, caught_known, bridged, fix_followed in rows:
        ran = int(ran or 0)
        if ran < min_ran:
            continue
        caught_true = int(caught_true or 0)
        caught_known = int(caught_known or 0)
        bridged = int(bridged or 0)
        fix_followed = int(fix_followed or 0)
        if caught_true > 0:
            continue  # real evidence it DID catch something (even thin) -- never ceremony,
                       # hard OR soft path (code-review MAJOR finding: this used to live only
                       # inside the caught_known>=floor branch, so a THIN-but-real catch left
                       # the soft/fix-correlation path free to fire CONDITION anyway)
        if caught_known >= min_ran:
            return Anomaly(
                key="ceremony",
                title="Feedback: gate ran but never caught anything (ceremony)",
                intent=(f"Consider cutting gate '{gate}': it ran {ran} times, {caught_known} "
                        "of those carrying a known caught result, and NONE caught anything."),
                approach=("Review whether this gate structurally cannot fail for this repo's "
                          "work; if so, cut it. Detected via `ledger anomalies` (gate-yield's "
                          "caught signal, never a bare skip-rate)."),
                tags="#u-mid #f-mid",
                home="dwarves-kit",
                metric=(f"gate={gate} ran={ran} caught_known={caught_known} caught_true=0 "
                        "action=CUT"),
            )
        if bridged >= min_ran and fix_followed == 0:
            return Anomaly(
                key="ceremony",
                title="Feedback: gate ran but no later fix ever correlated (ceremony proxy)",
                intent=(f"Consider conditioning gate '{gate}': it ran {ran} times, bridged to "
                        f"{bridged} shipped file(s) via git, and NONE needed a later fix() -- "
                        "a weaker proxy than `caught` (absence of a later fix is not proof of "
                        "ceremony), so CONDITION, not CUT."),
                approach=("Narrow when this gate runs (a named trigger) rather than cutting "
                          "outright; revisit once `caught` data lands for this gate. Detected "
                          "via `ledger anomalies`."),
                tags="#u-mid #f-lo",
                home="dwarves-kit",
                metric=(f"gate={gate} ran={ran} bridged={bridged} fix_followed=0 "
                        "action=CONDITION"),
            )
    return None


def _detect_token_runaway(th: dict) -> Anomaly | None:
    """Token-runaway (SPEC-135: ARMED). Reads ONLY the `sessions` table (numbers-only,
    `materialize.query()`, the one-data-path contract every detector in this module follows):
    flags the single highest-total session (input+output+cache_read+cache_creation tokens) when
    it exceeds `token_budget_max`. `None` when the top session is at/under budget, or when
    `sessions` is empty (no data, no fire -- same honest-empty convention `unknown_density`/
    `ceremony` already use).

    A flat per-session threshold, NOT a per-rid budget (SPEC-135 DEC-004): `sessions` carries no
    rid/repo column in v1 (a session transcript has no structural link to a kit rid), so
    attributing cost to a specific sub-goal would need the SAME time-containment bridge
    `ledger digest`'s cost-per-verified-outcome JOIN already builds -- duplicating that bridge
    inside a detector for marginal benefit over a single-shot, worst-offender check. Matches
    every other single-shot detector's shape (first/worst match, one Anomaly per call)."""
    _cols, rows = materialize.query(
        "SELECT session_id, project_slug, "
        "input_tokens + output_tokens + cache_read_tokens + cache_creation_tokens AS total "
        "FROM sessions ORDER BY total DESC LIMIT 1"
    )
    if not rows:
        return None
    session_id, project_slug, total = rows[0]
    total = int(total or 0)
    if total <= th["token_budget_max"]:
        return None
    return Anomaly(
        key="token_runaway",
        title="Feedback: a session's token footprint over budget",
        intent=(f"Session '{session_id}' ({project_slug}) used {total} total tokens "
                f"(input+output+cache), over the {int(th['token_budget_max'])} token_budget_max "
                "threshold."),
        approach=("Check the sessions table for what ran long/expensive in that session; "
                  "consider splitting the work across sessions or /clear-ing more often. "
                  "Detected via `ledger anomalies`/`ledger digest`."),
        tags="#u-mid #f-mid",
        home="ops-toolkit",
        metric=f"session_id={session_id} project_slug={project_slug} total_tokens={total}",
    )


def _seconds_between(start: str, end: str) -> float | None:
    """Parse two ISO8601 timestamps into a duration in seconds. Returns None on anything
    unparsable rather than raising -- a malformed timestamp proposes nothing, never crashes
    detection."""
    try:
        a = _dt.datetime.fromisoformat(str(start).replace("Z", "+00:00"))
        b = _dt.datetime.fromisoformat(str(end).replace("Z", "+00:00"))
    except (ValueError, AttributeError, TypeError):
        return None
    return abs((b - a).total_seconds())


def _detect_serial_when_parallel(th: dict) -> Anomaly | None:
    """Time-to-done advisor, serial-when-parallel (SPEC-134): two candidate rids (any rid seen
    in `kit_gates`) bridged to git the same way `defect-correlation`/`_detect_ceremony` bridge
    (textual rid-in-subject match), windowed by `MIN(ts)..MAX(ts)` across ALL of a rid's own
    bridged commits.

    DELIBERATELY anchored on `git_fixes.ts`, NEVER `kit_runs.first_ts/last_ts` (the HANDOFF
    windowing lesson, reconfirmed this sub-goal: `kit_runs` returns 0 rows in this local
    environment -- the `kit_runs` adapter's own subprocess into the installed
    `lane-telemetry.sh` returns nothing here, a pre-existing, out-of-scope issue per
    `_meta/megagoals/harness-observatory/DECISIONS.md` -- and `kit_gates.start_ts/end_ts` is
    100% NULL on the real corpus). This
    also means the bridge draws its rid universe from EVERY `kit_gates` rid (no `gate='ship'`
    filter -- `kit_gates` carries no per-run "did this ship" column to filter on for this
    purpose, unlike `defect-correlation`'s own bridge which specifically starts from shipped
    rids).

    Two rids are a serial-when-parallel candidate when ALL of:
    1. Both have >= 1 bridged commit (an evidence floor -- a rid with ZERO git correlation has
       no real evidence it was independent, so it is never a candidate; this mirrors
       `_detect_ceremony`'s own "abstain on thin evidence" philosophy).
    2. Their `[MIN(ts), MAX(ts)]` windows do NOT overlap (ran in separate waves, one strictly
       after the other).
    3. They share NO touched file across ALL their bridged commits (a dependency-INDEPENDENCE
       proxy, not a real dep-graph read -- no new adapter in scope; SPEC-134 DEC-002). ANY
       shared file means genuinely dependent, correctly serial, never propose.

    Proposes collapsing the two waves into one, with the shorter rid's own window duration as
    the plausible minutes-saved estimate (parallel wall time is max(dur_a, dur_b), so the
    saving is min(dur_a, dur_b)). `serial_min_minutes_saved` is a magnitude floor: a trivial
    saving proposes nothing.

    Only the serial-when-parallel signal is implemented: slow-gate ranking, kill-churn, and
    discovery-heavy (also named in the goal file's Outcome paragraph) need per-session data that
    lands with the sessions table (sub-goal 05) and are deliberately left for then, not faked
    here (SPEC-134 "Out of Scope")."""
    min_save = th["serial_min_minutes_saved"]
    sql = """
    WITH candidates AS (
        SELECT DISTINCT rid FROM kit_gates
    ),
    bridge AS (
        SELECT DISTINCT c.rid, g.ts, g.files AS file
        FROM candidates c
        JOIN git_fixes g ON contains(lower(g.subject), lower(c.rid))
    ),
    windows AS (
        SELECT rid, min(ts) AS win_start, max(ts) AS win_end, count(DISTINCT ts) AS n_commits
        FROM bridge
        GROUP BY rid
    )
    SELECT w1.rid AS rid_a, w1.win_start AS a_start, w1.win_end AS a_end,
           w2.rid AS rid_b, w2.win_start AS b_start, w2.win_end AS b_end,
           EXISTS (
               SELECT 1 FROM bridge b1 JOIN bridge b2 ON b1.file = b2.file
               WHERE b1.rid = w1.rid AND b2.rid = w2.rid
           ) AS shares_file
    FROM windows w1 JOIN windows w2 ON w1.rid < w2.rid
    WHERE (CAST(w1.win_end AS TIMESTAMPTZ) <= CAST(w2.win_start AS TIMESTAMPTZ)
        OR CAST(w2.win_end AS TIMESTAMPTZ) <= CAST(w1.win_start AS TIMESTAMPTZ))
    ORDER BY w1.rid, w2.rid
    """
    _cols, rows = materialize.query(sql)
    for rid_a, a_start, a_end, rid_b, b_start, b_end, shares_file in rows:
        if shares_file:
            continue  # genuinely dependent -- correctly serial, never propose
        dur_a = _seconds_between(a_start, a_end)
        dur_b = _seconds_between(b_start, b_end)
        if dur_a is None or dur_b is None:
            continue
        saved_min = min(dur_a, dur_b) / 60.0
        if saved_min < min_save:
            continue
        return Anomaly(
            key="serial_when_parallel",
            title="Feedback: dep-independent runs executed in separate serial waves",
            intent=(f"'{rid_a}' and '{rid_b}' ran back-to-back with no shared bridged file "
                    f"(a dependency-independence proxy), ~{saved_min:.1f} min of wall time "
                    "could collapse to one wave."),
            approach=("Check whether these two sub-goals/runs are truly independent; if so, "
                      "dispatch them in the same wave next time. Detected via `ledger "
                      "anomalies` (the git-bridge window + file-overlap proxy)."),
            tags="#u-lo #f-mid",
            home="dwarves-kit",
            metric=f"rid_a={rid_a} rid_b={rid_b} minutes_saved={saved_min:.1f}",
        )
    return None


def _detect_memory_hygiene(th: dict) -> Anomaly | None:
    """Memory hygiene (SPEC-136): dead-ref RATE over the `memories` lens table, the v1
    retrieval-precision proxy for "stale-but-confident" memory notes (a note that reads as
    confidently as ever but points at a path/command that no longer exists). Reads ONLY
    `materialize.query()` (the one-data-path contract every detector in this module follows --
    never calls `memory_lens` directly). `memory_min_notes` is the min-sample floor, same
    convention as `misfire`/`unknown_density`: thin data proposes nothing."""
    _cols, rows = materialize.query(
        "SELECT count(*) AS total, "
        "count(*) FILTER (WHERE dead_ref_count > 0) AS with_dead FROM memories"
    )
    total = int(rows[0][0] or 0) if rows else 0
    with_dead = int(rows[0][1] or 0) if rows else 0
    if total < th["memory_min_notes"]:  # min-sample floor
        return None
    rate = with_dead / total if total else 0.0
    if rate <= th["memory_dead_ref_rate_max"]:
        return None
    return Anomaly(
        key="memory_hygiene",
        title="Feedback: memory dead-reference rate over threshold",
        intent=(f"Pay down stale memory notes: {with_dead} of {total} memory units carry >=1 "
                f"dead reference ({rate:.0%}), over the "
                f"{th['memory_dead_ref_rate_max']:.0%} threshold."),
        approach=("Review the `memories` lens table (WHERE dead_ref_count > 0); run `ledger "
                  "memory-sweep` for the full per-reference paydown detail. NEVER auto-fix or "
                  "delete a memory -- propose only, a human confirms or dismisses each row. "
                  "Detected via `ledger anomalies`."),
        tags="#u-mid #f-lo",
        home="ops-toolkit",
        metric=f"with_dead={with_dead} total={total} rate={rate:.2f}",
    )


def _detect_review_fp(th: dict) -> Anomaly | None:
    """Review-yield FP-rate anomaly (SPEC-137, gate-review-absorptions SG-04): a review lens
    whose (repo, lens) `rejected_findings` count is disproportionate against the run-level
    `raised` denominator -- the SAME approximation `review-yield` itself reports (a per-lens
    numerator over a per-run, not per-lens, denominator; `kit_gates` carries no lens column,
    SPEC-137 DEC-002), read via the identical SQL shape, not a second detection path.
    `review_fp_min_n` is a DUAL min-sample floor (both `n_rejected` and `raised` must clear
    it), the same convention `review-yield --min-n`'s own `low_n` column uses -- thin data on
    either side proposes nothing, same discipline as every other detector's floor.

    `suppressed=` is never read here either (SPEC-137 DEC-003, same as `review-yield` itself).
    Reads ONLY `materialize.query()` (the one-data-path contract every detector in this module
    follows). Gates are checked in (repo, lens) alphabetical order (deterministic); the FIRST
    row over threshold fires. Returns `None` on honest-empty (no row clears the dual floor, or
    none exceeds the rate), same convention as `_detect_unknown_density`/`_detect_ceremony`."""
    min_n = th["review_fp_min_n"]
    sql = f"""
    WITH review_rows AS (
        SELECT
            try_cast(regexp_extract(reason, 'findings=(-?[0-9]+)', 1) AS INTEGER) AS findings,
            try_cast(regexp_extract(reason, 'rejected=(-?[0-9]+)', 1) AS INTEGER) AS rejected
        FROM kit_gates
        WHERE gate = 'review' AND outcome IN ('ran', 'override')
    ),
    review_agg AS (
        SELECT COALESCE(sum(findings), 0) + COALESCE(sum(rejected), 0) AS raised
        FROM review_rows
    )
    SELECT rf.repo, rf.lens, rf.n_rejected, ra.raised
    FROM rejected_findings rf CROSS JOIN review_agg ra
    WHERE rf.n_rejected >= {min_n} AND ra.raised >= {min_n}
    ORDER BY rf.repo, rf.lens
    """
    _cols, rows = materialize.query(sql)
    for repo, lens, n_rejected, raised in rows:
        n_rejected = int(n_rejected or 0)
        raised = int(raised or 0)
        rate = n_rejected / raised if raised else 0.0
        if rate <= th["review_fp_rate_max"]:
            continue
        return Anomaly(
            key="review_fp",
            title="Feedback: review lens FP-rate over threshold (approx)",
            intent=(f"Condition or narrow lens '{lens}' in {repo}: its rejected-finding count "
                    f"({n_rejected}) is {rate:.0%} of the run-level raised total ({raised}), an "
                    "APPROXIMATION (per-lens numerator over a per-run denominator; kit_gates "
                    f"carries no lens column) over the {th['review_fp_rate_max']:.0%} "
                    "threshold."),
            approach=("Review the rejected-findings.md rows for this lens; if the same defect "
                      "shape keeps getting rejected, narrow or retire that lens's trigger. "
                      "Detected via `ledger anomalies` (review-yield's rejected/raised "
                      "approximation, never a bare skip-rate)."),
            tags="#u-mid #f-mid",
            home=repo,
            metric=f"repo={repo} lens={lens} n_rejected={n_rejected} raised={raised} rate={rate:.2f}",
        )
    return None


DETECTORS = (
    _detect_debt, _detect_cost_spike, _detect_misfire, _detect_unknown_density,
    _detect_ceremony, _detect_token_runaway, _detect_serial_when_parallel,
    _detect_memory_hygiene, _detect_review_fp,
)


def detect(thresholds: dict | None = None) -> list[Anomaly]:
    """Run every detector over the lens (read-only). Returns the fired anomalies, in
    DETECTORS order. Deterministic for a given lens state + thresholds."""
    th = dict(DEFAULTS)
    if thresholds:
        th.update(thresholds)
    fired: list[Anomaly] = []
    for d in DETECTORS:
        a = d(th)
        if a is not None:
            fired.append(a)
    return fired


def parse_thresholds(pairs: list[str]) -> dict:
    """Parse `KEY=VALUE` overrides. Unknown key or non-numeric value raises ValueError.

    Rejects non-finite values (`nan`/`inf`/`-inf`) explicitly (a `kit:code-reviewer` LOW
    finding on `_detect_review_fp`, SPEC-137): `float("nan")` parses successfully in Python,
    so an unvalidated override would splice a bare `nan`/`inf` token into
    `_detect_review_fp`'s f-string SQL (`... WHERE rf.n_rejected >= {min_n} ...`) rather than
    the intended "disable this floor" behavior. Not an injection (no quote-breaking is
    possible via a float-cast value), but a confusing DuckDB parse error instead of a clean
    CLI error. `_detect_review_fp` is the first detector to interpolate a threshold VALUE
    (as opposed to a Typer-`int`-typed CLI option) directly into SQL text, so this floor
    applies to every threshold key, not only the new one."""
    th: dict[str, float] = {}
    for p in pairs:
        if "=" not in p:
            raise ValueError(f"bad --threshold {p!r}: expected KEY=VALUE")
        k, v = p.split("=", 1)
        k = k.strip()
        if k not in DEFAULTS:
            raise ValueError(f"unknown threshold key {k!r}; valid: {', '.join(sorted(DEFAULTS))}")
        try:
            parsed = float(v)
        except ValueError:
            raise ValueError(f"threshold {k} must be numeric, got {v!r}")
        if not math.isfinite(parsed):
            raise ValueError(f"threshold {k} must be finite, got {v!r}")
        th[k] = parsed
    return th


# --- the PROPOSE path: stage into the cc-backlog buffer, NEVER a board -------------------

_STAGING_HEADER = (
    "# Backlog staging (auto, via cc-backlog)\n\n"
    "Candidates auto-extracted from sessions. Review + promote with `board promote`.\n"
    "Gitignored: may name unfiled work. NEVER the source of truth.\n"
)


def _ops_toolkit_root() -> str | None:
    """ops-toolkit-specific (05K move): cc-backlog's staging buffer + board both live in
    ops-toolkit's `_meta/`, a foreign repo now that this tool lives in dwarves-kit. No
    hardcoded personal-path default post-move -- an unset `OPS_TOOLKIT` means "not
    configured", not "guess the fallback and maybe write to the wrong place"."""
    return os.environ.get("OPS_TOOLKIT")


def _staging_env(canonical: str, legacy: str) -> str | None:
    """Read the canonical env name, falling back to the pre-SPEC-200 `CC_*` name with
    a one-line deprecation on stderr. The kit's naming invariant bans host-agent
    prefixes (docs/verification/kit-foldin-hooks.md renamed CC_BACKLOG_* ->
    BACKLOG_STAGE_* once already); stats entered the kit after that sweep and kept the
    banned name, so board/learn/hooks/session-audit and stats addressed the SAME two
    files under different env names. Canonical wins; the alias keeps existing setups
    working for one release."""
    v = os.environ.get(canonical)
    if v:
        return v
    v = os.environ.get(legacy)
    if v:
        print(f"stats: {legacy} is deprecated, use {canonical} (SPEC-200)", file=sys.stderr)
        return v
    return None


def staging_path() -> str | None:
    """The staging buffer (the PROPOSAL surface, the ONLY write target of `--propose`).
    Canonical env `BACKLOG_STAGE_STAGING` (deprecated alias `CC_BACKLOG_STAGING`), the
    same name board/learn/hooks/session-audit read. None when neither it nor
    `OPS_TOOLKIT` is set (05K: ops-toolkit-specific, required-explicit post-move);
    `stage_proposals` refuses to write rather than silently resolving a bogus relative
    path off an empty root."""
    explicit = _staging_env("BACKLOG_STAGE_STAGING", "CC_BACKLOG_STAGING")
    if explicit:
        return explicit
    root = _ops_toolkit_root()
    return os.path.join(root, "_meta/backlog-staging.md") if root else None


def backlog_path() -> str | None:
    """The board (read ONLY, for dedup; never written by this tool). Canonical env
    `BACKLOG_STAGE_BACKLOG` (deprecated alias `CC_BACKLOG_BACKLOG`). None under the same
    conditions as `staging_path()`; `_existing_titles` is already None-safe (a missing
    dedup source just means nothing to dedup against)."""
    explicit = _staging_env("BACKLOG_STAGE_BACKLOG", "CC_BACKLOG_BACKLOG")
    if explicit:
        return explicit
    root = _ops_toolkit_root()
    return os.path.join(root, "_meta/BACKLOG.md") if root else None


def _norm(s: str) -> str:
    """cc-backlog's title normalization: lowercase alphanumeric words joined by a space."""
    return " ".join(re.findall(r"[a-z0-9]+", str(s).lower()))


def _existing_titles(backlog: str | None, staging: str | None) -> set[str]:
    """Normalized titles already on the board (Item col) OR already staged. Mirrors
    cc-backlog's `existing_titles` exactly, so a proposal never duplicates a board row or a
    prior staged proposal. Both files are opened READ-ONLY."""
    titles: set[str] = set()
    if backlog and os.path.isfile(backlog):
        with open(backlog, encoding="utf-8") as fh:
            for line in fh:
                m = re.match(r"\s*\|\s*[A-Z]+-\d+\s*\|\s*([^|]+)\|", line)
                if m:
                    titles.add(_norm(m.group(1)))
    if staging and os.path.isfile(staging):
        with open(staging, encoding="utf-8") as fh:
            for line in fh:
                m = re.match(r"##\s*\[[^\]]+\]\s*(.+)", line)
                if m:
                    titles.add(_norm(m.group(1)))
    return titles


def render_block(a: Anomaly, date: str) -> str:
    """A `## [staged]` block, byte-format-identical to cc-backlog's `render_candidate`, so the
    existing `board promote` human gate consumes it with no second convention."""
    home = f"- Home: {a.home}\n" if a.home else ""
    return (
        f"## [staged] {a.title}\n"
        f"- Intent: {a.intent}\n"
        f"- Approach: {a.approach}\n"
        f"- Tags: {a.tags}\n"
        f"{home}"
        f"- Source: stats anomalies {date}\n\n"
    )


def _today() -> str:
    return _dt.date.today().isoformat()


def stage_proposals(anomalies: list[Anomaly], staging: str | None, backlog: str | None,
                    date: str | None = None) -> tuple[list[Anomaly], list[Anomaly]]:
    """Append a `## [staged]` block per NON-duplicate anomaly to the staging buffer. Returns
    (staged, skipped_as_duplicate). Dedup is by normalized title vs the board AND the staging
    file, so re-runs are idempotent and an already-promoted/rejected anomaly never re-stages.

    The ONLY write is to `staging`. `backlog` is read-only (dedup). This is the
    propose-not-autofile guarantee (proven byte-identical in the test suite).

    `staging`/`backlog` are None when no destination is configured (05K: ops-toolkit-
    specific, required-explicit post-move -- see `staging_path()`/`backlog_path()`). A
    None `backlog` is harmless (nothing to dedup against, `_existing_titles` already
    treats it that way). A None `staging` is fine too UNLESS there is something new to
    actually write: raising here, instead of silently resolving a relative path off an
    empty root, is the fix for the exact failure mode this function must never produce
    (a `--propose` writing a stray `_meta/backlog-staging.md` relative to whatever the
    caller's cwd happens to be)."""
    date = date or _today()
    existing = _existing_titles(backlog, staging)
    staged: list[Anomaly] = []
    skipped: list[Anomaly] = []
    new_blocks: list[str] = []
    for a in anomalies:
        key = _norm(a.title)
        if key in existing:
            skipped.append(a)
            continue
        existing.add(key)  # dedup within this batch too
        new_blocks.append(render_block(a, date))
        staged.append(a)
    if new_blocks:
        if staging is None:
            raise RuntimeError(
                "ledger anomalies --propose has a proposal to stage but no destination is "
                "configured: set BACKLOG_STAGE_STAGING (or OPS_TOOLKIT) to an explicit "
                "absolute path (ops-toolkit-specific source, no default post-05K move)"
            )
        _append_blocks(staging, new_blocks)
    return staged, skipped


def _append_blocks(staging: str, blocks: list[str]) -> None:
    """Append blocks to the staging buffer (create with the cc-backlog header if new)."""
    exists = os.path.isfile(staging)
    parent = os.path.dirname(staging)
    if parent:
        os.makedirs(parent, exist_ok=True)
    with open(staging, "a", encoding="utf-8") as fh:
        if not exists:
            fh.write(_STAGING_HEADER + "\n")
        fh.write("".join(blocks))
