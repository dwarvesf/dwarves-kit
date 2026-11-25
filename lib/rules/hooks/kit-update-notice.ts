// kit-update-notice (hooks/kit-update-notice.sh, SessionStart startup) as a gdp-wired rule. Always exits 0.
//
// State: <state dir>/cache.json = {checked_at, latest}, reloaded at every start (:56-60; a non-numeric checked_at is 0).
//   :41      KIT_UPDATE_CHECK=0                          -> nothing
//   :62      fetch when now - checked_at >= 86400, or checked_at is in the future (a clock that went back)
//   :63-71   a fetch records checked_at = now even when it fails; a good semver replaces latest, a failure keeps it
//   :74-83   notify when latest > installed
// Versions are compared as naturals here (semver_gt is a lexicographic compare of three numbers; 0 = no version).
import {bool, nat, rule, when} from 'gdp-wired'

export const INTERVAL = 86400
export type Variant = 'shipped' | 'fetch-every-start' | 'notify-equal'
export const VARIANTS: Variant[] = ['fetch-every-start', 'notify-equal']

export function kitUpdateNotice(v: Variant = 'shipped') {
  return rule(v === 'shipped' ? 'kit-update-notice' : `kit-update-notice/${v}`)
    .params({off: bool, installed: nat})
    .inputs({now: nat, ok: bool, remote: nat})
    .state({checkedAt: 0, latest: 0, fetched: bool.from(false), notified: bool.from(false)})
    .flags(({off, now, checkedAt}) => ({
      fetch: off.not().and(v === 'fetch-every-start' ? off.not() : now.minus(checkedAt).atLeast(INTERVAL).or(checkedAt.gt(now))),
    }))
    .step(({off, installed, now, ok, remote, checkedAt, latest, fetch}) => {
      const latest2 = when(fetch.and(ok).and(remote.gt(0)), remote, latest)
      return {
        checkedAt: when(fetch, now, checkedAt),
        latest: latest2,
        fetched: fetch,
        notified: off.not().and(installed.gt(0)).and(v === 'notify-equal' ? latest2.atLeast(installed).and(latest2.gt(0)) : latest2.gt(installed)),
      }
    })
}
export const make = kitUpdateNotice

export function laws(r: ReturnType<typeof kitUpdateNotice>) {
  return {
    laws: [],
    stepLaws: [
      r.stepLaw('the network is touched at most once per 24 hours of the recorded clock',
        (b, a) => a.fetched.implies(b.now.minus(b.checkedAt).atLeast(INTERVAL).or(b.checkedAt.gt(b.now)))),
      r.stepLaw('a fetch is recorded even when it fails', (b, a) => a.checkedAt.eq(b.now), (b) => b.off.not().and(b.now.minus(b.checkedAt).atLeast(INTERVAL))),
      r.stepLaw('with the check off nothing is fetched or shown', (b, a) => a.fetched.not().and(a.notified.not()), (b) => b.off),
      r.stepLaw('a notice means the latest release is newer than the installed one', (b, a) => a.notified.implies(a.latest.gt(b.installed))),
      r.stepLaw('a failed fetch keeps the last known release', (b, a) => a.latest.eq(b.latest), (b) => b.ok.not()),
    ],
  }
}
