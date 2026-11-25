// verify-loop.cli.ts -- steps the PROVEN verify-loop rule (verify-loop.ts) for one run and prints the next action.
// bin/verify-loop is the only caller. The decision is the compiled rule's step: this file only loads and saves the
// state, refuses a state outside the laws' domain, and words the transition for the lead.
//
//   node verify-loop.cli.ts event <state-file> <max> <event>   step the run, save it, print the action
//   node verify-loop.cli.ts status <state-file> <max>          print the run's phase and spent fix cycles
import {existsSync, readFileSync, renameSync, writeFileSync} from 'node:fs'
import {EVENTS, PHASES, verifyLoop} from './verify-loop.ts'

const [verb, file, maxArg, ev] = process.argv.slice(2)
const max = Number(maxArg)
if (!file || !Number.isInteger(max) || max < 0 || (verb !== 'event' && verb !== 'status') || (verb === 'event' && !EVENTS.includes(ev as never))) {
  console.error(`usage: verify-loop.cli.ts event <state-file> <max> <${EVENTS.join('|')}> | status <state-file> <max>`)
  process.exit(64)
}

const r = verifyLoop()
const run = r.compiled()
const params = r.encodeParams({max})
let st = run.init(params)
if (existsSync(file)) {
  const saved = JSON.parse(readFileSync(file, 'utf8'))
  const {phase, retries} = saved.scalars ?? {}
  // The laws are proven from every state they allow; a state outside them (hand-edited, or saved under a larger
  // cap) is refused rather than stepped, because no proof covers it.
  if (!Number.isInteger(phase) || phase < 0 || phase >= PHASES.length || !Number.isInteger(retries) || retries < 0 || retries > max) {
    console.error(`verify-loop: refusing state ${JSON.stringify(saved.scalars)} in ${file}: outside the proven domain (retries 0..${max})`)
    process.exit(3)
  }
  st = {scalars: {phase, retries}, maps: {}}
}

const before = r.decode(st) as {phase: string, retries: number}
if (verb === 'status') {
  console.log(`phase=${before.phase} retries=${before.retries} max=${max}`)
  process.exit(0)
}

const next = run.step(params, st, r.encodeInput({ev: ev as (typeof EVENTS)[number]}, {max}))
const after = r.decode(next) as {phase: string, retries: number}
const tmp = `${file}.tmp`
writeFileSync(tmp, JSON.stringify({scalars: next.scalars}) + '\n')
renameSync(tmp, file)

function action(): string {
  if (before.phase !== 'open') return `none: the run already ended ${before.phase}`
  switch (after.phase) {
    case 'passed': return 'continue: the end verifiers passed'
    case 'escalated': return ev === 'cannot_fix' ? 'stop: the fix-agent cannot fix it; escalate to the human' : 'stop: FAIL:escalate goes to the human; do not retry'
    case 'closed': return 'stop: close the spec (the reason names the spec as wrong or not worth building)'
    case 'partial': return `stop: ${max} fix cycles spent; apply the PARTIAL rule`
  }
  if (after.retries > before.retries) return `dispatch kit:fix-agent, then re-run the failing end verifier(s) (fix cycle ${after.retries} of ${max})`
  if (ev === 'known') return 're-run the verifiers: a known failure spends no fix cycle'
  if (ev === 'silent_grace') return 'resume the silent builder with SendMessage: no fix cycle spent'
  if (ev === 'lost') return 'start a new attempt with a fresh builder: not a fix cycle'
  return 'none'
}
console.log(`phase=${after.phase} retries=${after.retries} max=${max} action=${action()}`)
