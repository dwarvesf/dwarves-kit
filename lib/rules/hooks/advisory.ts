// "An advisory hook never blocks" (docs/reference/hooks.md, docs/guides/gates-and-proof.md: "Almost everything in
// the kit advises. A short list of rules blocks.") as a gdp-wired decision over every advisory hook in hooks/.
//
// Claude Code reads exit 2 as a block on PreToolUse, UserPromptSubmit and Stop (and as an error on the others), so an
// advisory hook must never exit 2, whatever it is fed. Several run under `set -e`, where a failing grep, sed or awk
// (exit 2) ends the hook with that same code. slop-cleaner did exactly that on an unreadable recent source file
// (fixed; 'pre-fix' keeps it). The block of each advisory hook is therefore an output that the rule says is never on.
import {bool, fun, oneOf} from 'gdp-wired'

export const ADVISORY = ['spec-drift-guard', 'money-gate', 'batch-debt-warn', 'output-offload', 'context-budget', 'context-hints',
  'prose-rag', 'slop-cleaner', 'citation-guard', 'context-readiness', 'post-compact-reinject', 'codebase-index', 'kit-update-notice',
  'pre-compact-backup', 'auto-format', 'notification', 'permission-auto-approve', 'backlog-stage', 'harvest', 'intake-sweep'] as const
export const Hook = oneOf(...ADVISORY)
export const Feed = oneOf('normal', 'empty', 'garbage', 'wrongTypes', 'unreadableFile')

export type Variant = 'shipped' | 'pre-fix'
export const VARIANTS: Variant[] = ['pre-fix']

export function advisory(v: Variant = 'shipped') {
  return fun(v === 'shipped' ? 'advisory-hooks' : `advisory-hooks/${v}`)
    .inputs({hook: Hook, feed: Feed, citationStrict: bool})
    .returns(({hook, feed, citationStrict}) => {
      const slopCrash = v === 'pre-fix' ? hook.is('slop-cleaner').and(feed.is('unreadableFile')) : feed.is('normal').and(feed.is('normal').not())
      return {block: slopCrash}
    })
}
export const make = advisory

export function laws(f: ReturnType<typeof advisory>) {
  return {
    laws: [], stepLaws: [],
    decisions: [
      f.law('an advisory hook never blocks, whatever it is fed', () => [], (o) => o.block.not()),
    ],
  }
}
