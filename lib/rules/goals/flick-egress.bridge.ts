// Bridge: `bin/flick body` (no network, no token: the provider body the egress guard lets through) against
// flickEgress(), with the config fenced the way tests/test-flick.sh fences it (FLICK_TEST=1, KIT_CONFIG_OPERATOR /
// KIT_CONFIG_ROOT in a temp dir, a clean env). Seeded random requests of one to three questions, each candidate built
// from segment classes (a dev word, a kit-public name, a dictionary word, a 2-letter unknown, an unknown word, the deny
// word), each hit public, unknown or malformed, under random [decide] configs. The candidates present in the body are
// compared with the questions the rule lets leave the host.
import {mkdirSync, writeFileSync} from 'node:fs'
import {join} from 'node:path'
import {flickEgress} from './flick-egress.ts'
import {cleanup, KIT, rng, sh, tmp, type BridgeResult} from './_bridge.ts'

const SEGS = {dev: 'api', pub: 'board', word: 'apple', short: 'xq', none: 'zorblax', deny: 'secret'} as const

export async function bridge(opts: {cases?: number, seed?: number} = {}): Promise<BridgeResult> {
  const cases = opts.cases ?? 120
  const g = rng(opts.seed ?? 13)
  const f = flickEgress()
  const root = tmp('flick-')
  mkdirSync(join(root, 'op')); mkdirSync(join(root, 'root')); mkdirSync(join(root, 'home'))
  writeFileSync(join(root, 'dict'), 'apple\nzebra\nsecret\n')
  let agree = 0, diverge: BridgeResult['diverge'] = null
  try {
    for (let c = 0; c < cases && !diverge; c++) {
      const cfg = {backendOn: g.next() < 0.85, pointOn: g.next() < 0.85, denySet: g.next() < 0.85, gateOn: g.next() < 0.6, dictOk: g.next() < 0.8}
      writeFileSync(join(root, 'op', 'kit.toml'), `[decide]\nbackend = "${cfg.backendOn ? 'jev' : 'none'}"\npoints = "${cfg.pointOn ? 'wrap-7b' : 'other-point'}"\n` +
        `deny_words = "${cfg.denySet ? 'secret' : ''}"\nword_gate = "${cfg.gateOn ? 'on' : 'off'}"\ndict_file = "${cfg.dictOk ? join(root, 'dict') : 'dict'}"\n`)
      const qs = Array.from({length: 1 + g.int(3)}, (_, i) => {
        const n = g.pick([1, 2, 3])
        const kinds = Array.from({length: n}, () => g.pick(['dev', 'pub', 'word', 'word', 'short', 'none', 'deny'] as const))
        let cand = kinds.map(k => SEGS[k]).join('-')
        const upper = g.next() < 0.1; if (upper) cand = cand[0].toUpperCase() + cand.slice(1)
        const hit = g.pick(['board', 'board', 'wrap', 'nothing-here', 'bad hit'] as const)
        return {id: `p${i + 1}`, cand, hit, kinds, upper}
      })
      const req = JSON.stringify({point: 'wrap-7b', questions: qs.map(q => ({id: q.id, candidate: q.cand, hit: q.hit}))})
      const res = sh('env', ['-i', `PATH=${process.env.PATH}`, `HOME=${join(root, 'home')}`, `KIT_CONFIG_ROOT=${join(root, 'root')}`, `KIT_CONFIG_OPERATOR=${join(root, 'op')}`,
        'FLICK_TEST=1', join(KIT, 'bin/flick'), 'body'], {input: req})
      let body: any = {}; try { body = JSON.parse(res.out) } catch { /* not JSON */ }
      const sent = body.questions ? Object.values(body.questions as Record<string, {instructions: string}>).map(v => /candidate (.*)\?$/.exec(v.instructions)?.[1]) : []
      const got = qs.filter(q => sent.includes(q.cand)).map(q => q.id)
      const want = qs.filter(q => {
        const segClass = (k: string) => k === 'deny' ? 'word' : k
        const cls = q.kinds.map(segClass)
        const out = f.run({...cfg, candShape: /^[a-z0-9-]{3,40}$/.test(q.cand), hitShape: q.hit !== 'bad hit', denyHit: q.kinds.includes('deny'),
          hitPublic: q.hit === 'board' || q.hit === 'wrap', n: q.kinds.length,
          s1: cls[0] ?? 'none', s2: cls[1] ?? 'none', s3: cls[2] ?? 'none'} as never) as {sends: number}
        return out.sends === 1
      }).map(q => q.id)
      if (JSON.stringify(want) !== JSON.stringify(got)) diverge = {config: cfg, questions: qs.map(q => ({id: q.id, candidate: q.cand, hit: q.hit})), rule_sends: want, bash_sends: got, out: res.out.slice(0, 300)}
      else agree++
    }
  } finally { cleanup(root) }
  return {agree, diverge}
}

if (import.meta.url === `file://${process.argv[1]}`) {
  const t0 = Date.now()
  const res = await bridge({cases: Number(process.env.CASES ?? 120), seed: Number(process.env.SEED ?? 13)})
  console.log(JSON.stringify(res, null, 1), `${Date.now() - t0}ms`)
  process.exit(res.diverge ? 1 : 0)
}
