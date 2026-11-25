// output-offload (hooks/output-offload.sh, PostToolUse all tools) as a gdp-wired decision. Always exits 0.
//
//   :23      the whole payload within OFFLOAD_MAX_TOKENS*4 chars        -> silent (fast path)
//   :31-55   the tool_response, flattened to text, within the budget    -> silent
//   :59-68   the offload dir or file cannot be written                  -> silent
//   :71-73   else the full output is saved and a pointer is injected
import {bool, fun} from 'gdp-wired'

export type Variant = 'shipped' | 'counts-input' | 'blocks-large'
export const VARIANTS: Variant[] = ['counts-input', 'blocks-large']

export function outputOffload(v: Variant = 'shipped') {
  return fun(v === 'shipped' ? 'output-offload' : `output-offload/${v}`)
    .inputs({payloadOver: bool, responseOver: bool, writable: bool})
    .assume(({payloadOver, responseOver}) => responseOver.implies(payloadOver))
    .returns(({payloadOver, responseOver, writable}) => {
      const offload = payloadOver.and(v === 'counts-input' ? payloadOver : responseOver).and(writable)
      return {offload, block: v === 'blocks-large' ? offload : offload.and(offload.not())}
    })
}
export const make = outputOffload

export function laws(f: ReturnType<typeof outputOffload>) {
  return {
    laws: [], stepLaws: [],
    decisions: [
      f.law('offloading never blocks the tool result', () => [], (o) => o.block.not()),
      f.law("only the tool's own output over the budget is offloaded", () => [], (o, e) => o.offload.implies(e.responseOver)),
      f.law('an output over the budget is offloaded when the cache is writable', (e) => [e.responseOver, e.writable], (o) => o.offload),
    ],
  }
}
