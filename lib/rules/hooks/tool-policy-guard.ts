// tool-policy-guard (hooks/tool-policy-guard.sh, PreToolUse all tools) as a gdp-wired decision.
//
//   :18-24   no policy file (KIT_TOOL_POLICY, else the config data path)      -> exit 0, silent
//   :34-48   unreadable/invalid policy or payload, no tool_name, a non-object  -> exit 0 (fail open)
//   :59-74   the FIRST rule (domains in file order, rules then providers) whose `match` is a substring of the tool
//            name decides: deny -> exit 2; ask -> exit 0 with a warning; allow -> exit 0. No match -> exit 0.
import {bool, fun, oneOf} from 'gdp-wired'

export const Action = oneOf('none', 'allow', 'ask', 'deny')
export type Variant = 'shipped' | 'ask-blocks' | 'fail-closed'
export const VARIANTS: Variant[] = ['ask-blocks', 'fail-closed']

export function toolPolicyGuard(v: Variant = 'shipped') {
  return fun(v === 'shipped' ? 'tool-policy-guard' : `tool-policy-guard/${v}`)
    .inputs({file: bool, valid: bool, first: Action})
    .returns(({file, valid, first}) => {
      const live = file.and(valid)
      const blocks = v === 'ask-blocks' ? first.is('deny').or(first.is('ask')) : first.is('deny')
      return {block: v === 'fail-closed' ? file.and(valid.not().or(blocks)) : live.and(blocks), warn: live.and(first.is('ask'))}
    })
}

export function laws(f: ReturnType<typeof toolPolicyGuard>) {
  return {
    laws: [], stepLaws: [],
    decisions: [
      f.law('without a policy file the guard is silent', (e) => [e.file.not()], (o) => o.block.not().and(o.warn.not())),
      f.law('a broken policy never blocks a tool', (e) => [e.valid.not()], (o) => o.block.not()),
      f.law('a deny match blocks the tool', (e) => [e.file, e.valid, e.first.is('deny')], (o) => o.block),
      f.law('an ask match warns and never blocks', (e) => [e.file, e.valid, e.first.is('ask')], (o) => o.block.not().and(o.warn)),
      f.law('only a deny blocks', () => [], (o, e) => o.block.implies(e.first.is('deny'))),
    ],
  }
}
export const make = toolPolicyGuard
