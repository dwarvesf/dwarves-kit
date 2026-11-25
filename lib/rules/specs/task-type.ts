// The work-type classifier, lib/classify/task-type-classify.sh (task_type_classify): first match wins, in the
// order 1 incident, 2 learning, 3 planning, 4 operate, 4b the absorb guard (absorb + kit/skill/command ->
// spec-feature), 5 eval, 6 research, 6b review (a code-review phrase and no act-on-feedback phrase), 8 doc,
// 9 migration, 9b reconcile, 10 data-tool, 11 spec-feature (the default). Each input is "this rule's regex fires".
// The header's precedence promises are the laws.
import {bool, fun, when} from 'gdp-wired'
import {pick} from './util.ts'

export const TYPES = ['incident', 'learning', 'planning', 'operate', 'eval', 'research', 'review', 'doc', 'migration', 'reconcile', 'data-tool', 'spec-feature'] as const
export const FEATURES = ['incident', 'learning', 'planning', 'operate', 'absorb', 'kitCo', 'eval', 'research', 'reviewPos', 'reviewNeg', 'doc', 'migration', 'reconcile', 'dataTool'] as const
export type Variant = 'shipped' | 'doc-before-research' | 'tool-before-migration' | 'no-absorb-guard'
export const VARIANTS: Variant[] = ['doc-before-research', 'tool-before-migration', 'no-absorb-guard']

export function taskType(variant: Variant = 'shipped') {
  return fun(variant === 'shipped' ? 'task-type' : `task-type/${variant}`)
    .inputs(Object.fromEntries(FEATURES.map(k => [k, bool])) as Record<(typeof FEATURES)[number], typeof bool>)
    .returns((e: any) => {
      const guard = variant === 'no-absorb-guard' ? e.absorb.and(e.absorb.not()) : e.absorb.and(e.kitCo)
      const review = e.reviewPos.and(e.reviewNeg.not())
      // [condition, type index] in the script's order
      const rules: [any, number][] = [
        [e.incident, 0], [e.learning, 1], [e.planning, 2], [e.operate, 3], [guard, 11],
        ...(variant === 'doc-before-research' ? [[e.doc, 7], [e.eval, 4], [e.research, 5]] as [any, number][] : [[e.eval, 4], [e.research, 5]] as [any, number][]),
        [review, 6],
        ...(variant === 'doc-before-research' ? [] : [[e.doc, 7]] as [any, number][]),
        ...(variant === 'tool-before-migration' ? [[e.dataTool, 10], [e.migration, 8]] as [any, number][] : [[e.migration, 8]] as [any, number][]),
        [e.reconcile, 9],
        ...(variant === 'tool-before-migration' ? [] : [[e.dataTool, 10]] as [any, number][]),
      ]
      const idx = rules.reduceRight((acc: any, [c, k]) => when(c, k, acc), 11)
      return {type: pick(TYPES, idx)}
    })
}

export function laws(f: ReturnType<typeof taskType>) {
  const earlier = (e: any, ...ks: string[]) => ks.map(k => e[k].not()).reduce((a: any, b: any) => a.and(b), e.incident.or(e.incident.not()))
  const head = ['incident', 'learning', 'planning', 'operate']
  const noGuard = (e: any) => e.absorb.and(e.kitCo).not()
  return {
    laws: [], stepLaws: [],
    decisions: [
      f.law('alert language is always an incident, never research or doc', (e: any) => e.incident, (o: any) => o.type.is('incident')),
      f.law('absorbing mechanics into the kit is implementation (spec-feature), never an eval',
        (e: any) => [earlier(e, ...head), e.absorb, e.kitCo], (o: any) => o.type.is('spec-feature')),
      f.law('eval and research win over doc: their deliverable is a report but the work is measurement or investigation',
        (e: any) => [earlier(e, ...head), noGuard(e), e.eval.or(e.research), e.doc], (o: any) => o.type.is('eval').or(o.type.is('research'))),
      f.law('a doc about a tool is still a doc: doc wins over migration and data-tool',
        (e: any) => [earlier(e, ...head, 'eval', 'research'), noGuard(e), e.reviewPos.and(e.reviewNeg.not()).not(), e.doc],
        (o: any) => o.type.is('doc')),
      f.law('migration wins over data-tool and reconcile: the classifier errs strict',
        (e: any) => [earlier(e, ...head, 'eval', 'research', 'doc'), noGuard(e), e.reviewPos.and(e.reviewNeg.not()).not(), e.migration],
        (o: any) => o.type.is('migration')),
      f.law('acting on review feedback is build work, never a review',
        (e: any) => e.reviewNeg, (o: any) => o.type.is('review').not()),
      f.law('a task no rule recognizes is a spec-feature',
        (e: any) => FEATURES.filter(k => k !== 'kitCo' && k !== 'reviewNeg').map(k => e[k].not()), (o: any) => o.type.is('spec-feature')),
    ],
  }
}
