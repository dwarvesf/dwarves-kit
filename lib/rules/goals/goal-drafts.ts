// The goal-draft lifecycle for one draft (lib/goal/goal-drafts.sh drafts_archive, L101-134), as a gdp-wired rule.
// The directory is the state: `top` = .claude/goals/<slug>.md exists, `done` = .claude/goals/done/<slug>.md exists.
// The draft's target is fixed for a run (`target`): no SPEC-NNN token (specless), a token whose spec file is missing
// (unresolvable), or a resolvable spec. `shipped` is that spec's Status (lib/spec/spec-status.sh get), which moves
// on its own (`ship` / `reopen`).
//   archive   move the draft into done/ when its spec is SHIPPED and done/ holds no copy (never clobber)
//   dry       archive --dry-run: report only
import {bool, oneOf, rule, type Cond, yes, no} from 'gdp-wired'

const sel = (c: Cond, a: Cond, b: Cond) => c.and(a).or(c.not().and(b))

export type Variant = 'shipped' | 'clobber' | 'archive-unshipped' | 'dry-moves'
export const VARIANTS: Variant[] = ['clobber', 'archive-unshipped', 'dry-moves']

export function goalDrafts(variant: Variant = 'shipped') {
  return rule(variant === 'shipped' ? 'goal-drafts' : `goal-drafts/${variant}`)
    .params({target: oneOf('specless', 'unresolvable', 'spec')})
    .inputs({op: oneOf('archive', 'dry', 'ship', 'reopen')})
    .state({top: bool.from(true), done: bool.from(false), shipped: bool.from(false)})
    .flags(({op, target, top, done, shipped}) => {
      const eligible = target.is('spec').and(variant === 'archive-unshipped' ? yes : shipped)
      const free = variant === 'clobber' ? yes : done.not()
      const archives = top.and(eligible).and(free).and(op.is('archive').or(variant === 'dry-moves' ? op.is('dry') : no))
      return {archives}
    })
    .step(({op, top, done, shipped, archives}) => ({
      top: sel(archives, no, top),
      done: sel(archives, yes, done),
      shipped: sel(op.is('ship'), yes, sel(op.is('reopen'), no, shipped)),
    }))
}

export type DraftsRule = ReturnType<typeof goalDrafts>

export function laws(r: DraftsRule) {
  return {
    laws: [
      r.law('a draft is never deleted: it sits at the top level or in done/', ({top, done}) => top.or(done)),
    ],
    stepLaws: [
      r.stepLaw('a draft is archived only when its target spec is SHIPPED', (b, a) => b.top.and(a.top.not()).implies(b.shipped.and(b.target.is('spec')))),
      r.stepLaw('archiving never overwrites an archived copy', (b, a) => a.top, (b) => b.top.and(b.done)),
      r.stepLaw('a dry run moves nothing', (b, a) => a.top.iff(b.top).and(a.done.iff(b.done)), (b) => b.op.is('dry')),
      r.stepLaw('a specless or unresolvable draft stays where it is', (b, a) => a.top.iff(b.top), (b) => b.target.is('spec').not()),
      r.stepLaw('archiving twice moves nothing the second time', (b, a) => a.top.iff(b.top), (b) => b.op.is('archive').and(b.top.not().or(b.done))),
    ],
  }
}
