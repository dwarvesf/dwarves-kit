// The overnight queue's runaway guards for one slug (lib/queue/queue.sh + lib/queue/watch-board.sh), as a gdp-wired rule.
//
// State is what `<log-dir>/queue-runs/<slug>.{beat,guard}` and the journal hold for the slug:
//   beat                 the heartbeat file exists (the in-flight claim)
//   stalls, np, se       guard counters stalls / noprogress / sameerror
//   hasRetry, retry      guard retry_after (empty, or an epoch second); empty with stalls >= maxStalls IS quarantine
//   hasCool, cool        guard cooldown_until
//   last                 the slug's last journal verdict (_journal_last_verdict)
//   planned              the watcher's last decision for the slug (an output of `plan`)
//
// Requests (one per thing that happens to the slug):
//   plan    watch-board.sh cmd_watch: the terminal-verdict rule (L279-284) then _guard_skip_reason (L181-206)
//   launch  queue.sh cmd_run reaching _launch_once for the slug: `_beat` (L631)
//   finish  the conductor's end of a run: _breaker_apply (L878-920), then the journal row and _beat_clear (L1124-1126).
//           `v` is the run's verdict, `ev` what _progress_evidence found, `delta` what _run_delta found.
//   reap    watch-board.sh _reap_stale_runs on a beat past QUEUE_BEAT_DEAD_SECS (L135-174); `sig` = EXIT_SIGNAL true
// `t` is the clock (epoch seconds), `j` the jitter draw of _schedule_retry ((RANDOM % SPAN) + MIN minutes, L928).
import {bool, type Cond, nat, no, oneOf, rule, when, yes} from 'gdp-wired'

const sel = (c: Cond, a: Cond, b: Cond) => c.and(a).or(c.not().and(b))

export const VERDICTS = ['none', 'done', 'gated', 'stalled', 'error', 'skipped'] as const
export const Verdict = oneOf(...VERDICTS)
export const Run = oneOf('done', 'gated', 'stalled', 'error')
export const Evidence = oneOf('verified', 'reported', 'freeze', 'none')
export const Op = oneOf('plan', 'launch', 'finish', 'reap')

// 'error-unbounded' is _breaker_apply as it was found: a tripped breaker on an `error` row cooled it down but never
// climbed the stall ladder, so the row was re-planned after every cooldown and never quarantined (FINDINGS.md F3).
export type Variant = 'shipped' | 'error-unbounded' | 'self-report-clears' | 'no-quarantine-gate' | 'no-beat-gate' | 'stall-unbumped'
export const VARIANTS: Variant[] = ['error-unbounded', 'self-report-clears', 'no-quarantine-gate', 'no-beat-gate', 'stall-unbumped']

export function queueGuard(variant: Variant = 'shipped') {
  return rule(variant === 'shipped' ? 'queue-guard' : `queue-guard/${variant}`)
    .params({maxStalls: nat, npTrip: nat, seTrip: nat, coolSecs: nat, jMin: nat, jSpan: nat})
    .pre(({jSpan, maxStalls, npTrip, seTrip}) => jSpan.atLeast(1).and(maxStalls.atLeast(1)).and(npTrip.atLeast(1)).and(seTrip.atLeast(1)))
    .inputs({op: Op, v: Run, ev: Evidence, delta: bool, sig: bool, t: nat, j: nat})
    .assume(({j, jSpan}) => j.lt(jSpan))
    .state({beat: bool.from(false), stalls: 0, np: 0, se: 0, hasRetry: bool.from(false), retry: 0,
      hasCool: bool.from(false), cool: 0, last: Verdict.from('none'), planned: bool.from(false)})
    .flags(({op, v, ev, delta, sig, t, maxStalls, npTrip, seTrip, beat, stalls, np, se, hasRetry, retry, hasCool, cool, last}) => {
      const terminal = last.is('done').or(last.is('gated'))
      const quarantined = stalls.atLeast(maxStalls).and(hasRetry.not())
      const backingOff = hasRetry.and(t.lt(retry))
      const cooling = hasCool.and(t.lt(cool))
      const plans = op.is('plan').and(terminal.not())
        .and(variant === 'no-beat-gate' ? yes : beat.not())
        .and(variant === 'no-quarantine-gate' ? yes : quarantined.not())
        .and(backingOff.not()).and(cooling.not())
      // cmd_run skips a slug whose last verdict is terminal before any window opens (L1063-1066).
      const launches = op.is('launch').and(terminal.not())
      // A finish is the end of a run this conductor launched: it holds the beat.
      const fin = op.is('finish').and(beat)
      const keepsTerminal = fin.and(v.is('done').or(v.is('gated')))               // L882-885: _guard_clear, verdict kept
      const verified = fin.and(keepsTerminal.not()).and(ev.is('verified'))         // L889-897: every counter zeroed
      const reported = fin.and(keepsTerminal.not()).and(ev.is('reported'))
      const freeze = fin.and(keepsTerminal.not()).and(ev.is('freeze'))
      const bare = fin.and(keepsTerminal.not()).and(ev.is('none'))
      const np1 = np.plus(1), se1 = when(v.is('error'), se.plus(1), se)
      const trips = bare.and(np1.atLeast(npTrip).or(se1.atLeast(seTrip)))           // L914-918: stagnation_detected
      // _stall_bump (L873-879) runs for a stalled verdict on every non-verified path, and for a tripped breaker
      // whatever the verdict (the fix, L917-919); the reaper climbs on a dead conductor that never claimed completion
      // (watch-board.sh L157-166).
      const tripBumps = variant === 'error-unbounded' ? no : trips
      const bumps = variant === 'stall-unbumped'
        ? bare.and(v.is('stalled'))
        : reported.or(freeze).or(bare).and(v.is('stalled')).or(tripBumps).or(op.is('reap').and(beat).and(sig.not()))
      const clearsAll = keepsTerminal.or(op.is('reap').and(beat).and(sig))
        .or(variant === 'self-report-clears' ? reported : no)
      return {plans, launches, fin, keepsTerminal, verified, reported, bare, trips, bumps, clearsAll, reaps: op.is('reap').and(beat)}
    })
    .step(({op, v, delta, sig, t, j, maxStalls, coolSecs, jMin, beat, stalls, np, se, hasRetry, retry, hasCool, cool, last, planned,
      plans, launches, fin, keepsTerminal, verified, reported, bare, trips, bumps, clearsAll, reaps}) => {
      const st1 = stalls.plus(1)
      // The journal verdict: the breaker may rewrite a non-terminal verdict to error; a done with no git delta is
      // gated (L1113-1115); the reaper's verdict is done only on a verified delta, else gated, or stalled (L140-167).
      const runVerdict = when(trips, last.of('error'),
        when(v.is('done').and(delta.not()), last.of('gated'),
          when(v.is('done'), last.of('done'), when(v.is('gated'), last.of('gated'), when(v.is('stalled'), last.of('stalled'), last.of('error'))))))
      const reapVerdict = when(sig.and(delta), last.of('done'), when(sig, last.of('gated'), last.of('stalled')))
      return {
        beat: sel(launches, yes, sel(fin.or(reaps), no, beat)),
        planned: sel(op.is('plan'), plans, planned),
        stalls: when(clearsAll.or(verified), 0, when(bumps, st1, stalls)),
        np: when(clearsAll.or(verified).or(reported), 0, when(bare, np.plus(1), np)),
        se: when(clearsAll.or(verified).or(reported), 0, when(bare.and(v.is('error')), se.plus(1), se)),
        hasRetry: sel(clearsAll.or(verified), no, sel(bumps, st1.lt(maxStalls), hasRetry)),
        retry: when(bumps.and(st1.lt(maxStalls)), t.plus(jMin.plus(j).times(60)), retry),
        hasCool: sel(clearsAll, no, sel(trips, yes, hasCool)),
        cool: when(trips, t.plus(coolSecs), cool),
        last: when(fin, runVerdict, when(reaps, reapVerdict, last)),
      }
    })
}

export type GuardRule = ReturnType<typeof queueGuard>

export function laws(r: GuardRule) {
  return {
    laws: [
      r.law('a stall count at the ceiling never carries a retry alarm (that empty alarm is the quarantine)',
        ({stalls, maxStalls, hasRetry}) => stalls.atLeast(maxStalls).implies(hasRetry.not())),
      r.law('a slug below the stall ceiling with stalls on record always has a retry alarm',
        ({stalls, maxStalls, hasRetry}) => stalls.atLeast(1).and(stalls.lt(maxStalls)).implies(hasRetry)),
      r.law('past the breaker threshold every run without progress is on the stall ladder',
        ({np, stalls, npTrip}) => np.plus(1).atMost(stalls.plus(npTrip)).or(np.eq(0))),
      // Promised by the watch-board.sh header (rule 5: "retryable" is bounded, with a backoff and a ceiling).
      r.law('a slug with maxStalls + npTrip runs in a row without progress is quarantined',
        ({np, stalls, maxStalls, npTrip, hasRetry}) => np.atLeast(maxStalls.plus(npTrip)).implies(stalls.atLeast(maxStalls).and(hasRetry.not()))),
    ],
    stepLaws: [
      r.stepLaw('a quarantined slug is never planned', (b, a) => a.planned.not(),
        (b) => b.op.is('plan').and(b.stalls.atLeast(b.maxStalls)).and(b.hasRetry.not())),
      r.stepLaw('a slug with a live heartbeat is never planned', (b, a) => a.planned.not(), (b) => b.op.is('plan').and(b.beat)),
      r.stepLaw('a slug whose last verdict is done or gated is never planned again', (b, a) => a.planned.not(),
        (b) => b.op.is('plan').and(b.last.is('done').or(b.last.is('gated')))),
      r.stepLaw('a slug is never planned before its stall backoff is over', (b, a) => a.planned.not(),
        (b) => b.op.is('plan').and(b.hasRetry).and(b.t.lt(b.retry))),
      r.stepLaw('a slug is never planned inside its breaker cooldown', (b, a) => a.planned.not(),
        (b) => b.op.is('plan').and(b.hasCool).and(b.t.lt(b.cool))),
      r.stepLaw('a self-report never clears the stall ladder of an unfinished run', (b, a) => a.stalls.atLeast(b.stalls),
        (b) => b.op.is('finish').and(b.v.is('stalled').or(b.v.is('error'))).and(b.ev.is('reported').or(b.ev.is('freeze')))),
      r.stepLaw('a stalled run with no verified repo delta climbs the stall ladder', (b, a) => a.stalls.eq(b.stalls.plus(1)),
        (b) => b.fin.and(b.v.is('stalled')).and(b.ev.is('verified').not())),
      r.stepLaw('a dead conductor that never claimed completion climbs the stall ladder', (b, a) => a.stalls.eq(b.stalls.plus(1)),
        (b) => b.op.is('reap').and(b.beat).and(b.sig.not())),
      r.stepLaw('a retry alarm lands inside the jitter window', (b, a) =>
        a.retry.atLeast(b.t.plus(b.jMin.times(60))).and(a.retry.lt(b.t.plus(b.jMin.plus(b.jSpan).times(60)))),
        (b) => b.bumps.and(b.stalls.plus(1).lt(b.maxStalls))),
      r.stepLaw('the breaker never rewrites a done or gated run', (b, a) => a.last.is('done').or(a.last.is('gated')),
        (b) => b.fin.and(b.v.is('done').or(b.v.is('gated')))),
      r.stepLaw('a run is journaled done only with a verified git delta', (b, a) => a.last.is('done').implies(b.delta),
        (b) => b.fin.or(b.reaps)),
      r.stepLaw('a run ends its in-flight claim', (b, a) => a.beat.not(), (b) => b.op.is('finish').or(b.op.is('reap'))),
      r.stepLaw('a slug already done or gated is never launched again', (b, a) => a.beat.iff(b.beat),
        (b) => b.op.is('launch').and(b.last.is('done').or(b.last.is('gated')))),
    ],
  }
}
