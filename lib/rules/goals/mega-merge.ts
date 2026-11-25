// The mega-lane auto-merge decision (lib/goal/mega-merge.sh merge, L403-561), as a gdp-wired decision.
// Inputs are what `merge` reads, in the order it reads them:
//   expect     --expect-head: absent, a malformed value (usage, 64), or a full SHA that matches / differs from the head
//   headOk     the PR head is readable and a bare 40-hex SHA (_pr_head)
//   excl       _merge_exclusion: clear, held (draft / hold label / title marker), or unreadable/malformed (fail closed)
//   cfg        _merge_config_guard: clear, touches the root .kit.toml, or the file list is unreadable
//   baseOk     the PR base branch is readable (_pr_base);  fetch: the pinned head and base fetched, failed, or moved
//   gate       the ship-gate on the pinned head passes (gate --head)
//   mcmd       the project merge command ([merge] command): none, custom, or unreadable
//   review     posture per-pr-review;  execute: --execute
//   baseSame   the base branch read again just before merging is unchanged
//   execOk / verified   the custom command exits 0 / GitHub then reports MERGED
// Outcomes: OUT. `gh-merge` is the plain `gh pr merge --squash --match-head-commit`; `custom-merged` the project's.
import {bool, fun, no, oneOf, when} from 'gdp-wired'

export const OUT = ['usage', 'blocked', 'head-moved', 'dry-run', 'gh-merge', 'custom-merged', 'custom-refused', 'custom-unverified'] as const
const O = (o: typeof OUT[number]) => OUT.indexOf(o)
export const Expect = oneOf('none', 'malformed', 'match', 'mismatch')
export const Excl = oneOf('clear', 'held', 'unreadable')
export const Cfg = oneOf('clear', 'touches', 'unreadable')
export const Fetch = oneOf('ok', 'fail', 'moved')
export const Mcmd = oneOf('none', 'custom', 'unreadable')

export type Variant = 'shipped' | 'gate-after-execute' | 'fallback-squash' | 'review-merges'
export const VARIANTS: Variant[] = ['gate-after-execute', 'fallback-squash', 'review-merges']

export function megaMerge(variant: Variant = 'shipped') {
  return fun(variant === 'shipped' ? 'mega-merge' : `mega-merge/${variant}`)
    .inputs({expect: Expect, headOk: bool, excl: Excl, cfg: Cfg, baseOk: bool, fetch: Fetch, gate: bool,
      mcmd: Mcmd, review: bool, execute: bool, baseSame: bool, execOk: bool, verified: bool})
    .returns(({expect, headOk, excl, cfg, baseOk, fetch, gate, mcmd, review, execute, baseSame, execOk, verified}) => {
      const gateOk = variant === 'gate-after-execute' ? gate.or(execute) : gate
      const reviewStops = variant === 'review-merges' ? no : review
      const custom = when(execOk.not(), variant === 'fallback-squash' ? O('gh-merge') : O('custom-refused'),
        when(verified, O('custom-merged'), O('custom-unverified')))
      const out = when(expect.is('malformed'), O('usage'),
        when(headOk.not(), O('blocked'),
          when(expect.is('mismatch'), O('head-moved'),
            when(excl.is('clear').not(), O('blocked'),
              when(cfg.is('clear').not(), O('blocked'),
                when(baseOk.not().or(fetch.is('ok').not()), O('blocked'),
                  when(gateOk.not(), O('blocked'),
                    when(mcmd.is('unreadable'), O('blocked'),
                      when(reviewStops.or(execute.not()), O('dry-run'),
                        when(baseSame.not(), O('blocked'),
                          when(mcmd.is('custom'), custom, O('gh-merge'))))))))))))
      return {out, merges: when(out.eq(O('gh-merge')).or(out.eq(O('custom-merged'))).or(out.eq(O('custom-unverified'))), 1, 0)}
    })
}

export type MergeFun = ReturnType<typeof megaMerge>

export function laws(f: MergeFun) {
  const merges = ({merges}: {merges: any}) => merges.eq(0)
  return [
    f.law('a PR whose ship-gate fails is never merged', ({gate}) => [gate.not()], merges),
    f.law('a held PR (draft, hold label, title marker) is never merged', ({excl}) => [excl.is('held')], merges),
    f.law('unreadable PR state fails closed: never merged', ({excl}) => [excl.is('unreadable')], merges),
    f.law('a PR touching the root .kit.toml is never auto-merged', ({cfg}) => [cfg.is('touches')], merges),
    f.law('an unreadable changed-file list fails closed', ({cfg}) => [cfg.is('unreadable')], merges),
    f.law('posture per-pr-review never merges', ({review}) => [review], merges),
    f.law('without --execute nothing is merged', ({execute}) => [execute.not()], merges),
    f.law('a head that moved since the wave join is refused with 75 and never merged', ({expect, headOk}) => [expect.is('mismatch'), headOk],
      ({out}) => out.eq(O('head-moved'))),
    f.law('a head that moved after the pin is never merged', ({fetch}) => [fetch.is('moved')], merges),
    f.law('a base retargeted after the gate is never merged', ({baseSame}) => [baseSame.not()], merges),
    f.law('a refused project merge command never falls back to the plain squash', ({mcmd}) => [mcmd.is('custom')],
      ({out}) => out.eq(O('gh-merge')).not()),
    f.law('an unreadable project merge command refuses', ({mcmd}) => [mcmd.is('unreadable')], merges),
  ]
}
