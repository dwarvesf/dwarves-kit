// codex-hook-adapter (hooks/codex-hook-adapter.sh, the Codex runtime's entry to the shared policies) as a gdp-wired
// decision. Unlike the Claude Code path it fails CLOSED.
//
//   :15-18  no event and no policy: the `{}` smoke payload -> 0 (anything else unreadable -> 2)
//   :20-26  a target outside the five supported pairs     -> 2
//   :28-31  no jq                                         -> 2
//   :38-52  input not the event's shape                   -> 2
//   :54-58  the policy script missing or not executable   -> 2
//   :73-91  run the shared policy (Stop: last_assistant_message mapped onto assistant_response); its non-zero exit -> 2
//   :102-117 secrets-guard on Bash also runs every path-like token through the Read policy
import {bool, fun} from 'gdp-wired'

export type Variant = 'shipped' | 'fails-open-without-jq' | 'unsupported-runs'
export const VARIANTS: Variant[] = ['fails-open-without-jq', 'unsupported-runs']

export function codexAdapter(v: Variant = 'shipped') {
  return fun(v === 'shipped' ? 'codex-hook-adapter' : `codex-hook-adapter/${v}`)
    .inputs({supported: bool, jq: bool, valid: bool, policy: bool, policyBlocks: bool})
    .returns(({supported, jq, valid, policy, policyBlocks}) => {
      const sup = v === 'unsupported-runs' ? supported.or(supported.not()) : supported
      const j = v === 'fails-open-without-jq' ? jq.or(jq.not()) : jq
      const pre = sup.and(j).and(valid).and(policy)
      const nojqOpen = v === 'fails-open-without-jq' ? jq.not() : jq.and(jq.not())
      return {block: pre.not().and(nojqOpen.not()).or(pre.and(policyBlocks).and(nojqOpen.not()))}
    })
}
export const make = codexAdapter

export function laws(f: ReturnType<typeof codexAdapter>) {
  return {
    laws: [], stepLaws: [],
    decisions: [
      f.law('an unsupported hook target is refused', (e) => [e.supported.not()], (o) => o.block),
      f.law('a missing jq or policy fails closed', (e) => [e.jq.not().or(e.policy.not())], (o) => o.block),
      f.law('malformed input fails closed', (e) => [e.valid.not()], (o) => o.block),
      f.law("a shared policy's block always reaches Codex", (e) => [e.policyBlocks], (o) => o.block),
      f.law('a well-formed call the policy allows goes through', (e) => [e.supported, e.jq, e.valid, e.policy, e.policyBlocks.not()], (o) => o.block.not()),
    ],
  }
}
