// Bridge: hold hooks/citation-guard.sh to the rule with temp transcripts whose last assistant message cites real
// files at real or impossible lines (and citations inside code fences or URLs, which do not count).
import {citationGuard} from './citation-guard.ts'
import {rng, runHook, sandbox, Tally, tmp, write, join, type BridgeResult} from './_bridge.ts'

export async function bridge(): Promise<BridgeResult> {
  const t = new Tally()
  const f = citationGuard()
  const g = rng(43)
  for (let i = 0; i < 50; i++) {
    const s = sandbox(), dir = tmp('kit-cite')
    write(dir, {'src/a.ts': 'one\ntwo\nthree\n'})
    const parts = (['good', 'badline', 'nofile', 'fenced', 'url'] as const).filter(() => g.next() < 0.4)
    const say: Record<string, string> = {good: 'see src/a.ts:2', badline: 'see src/a.ts:40', nofile: 'see src/missing.ts:1',
      fenced: '```\nsrc/missing.ts:9\n```', url: 'https://x.io/src/missing.ts:3'}
    const text = parts.map((p) => say[p]).join('\n') || 'no refs'
    const tr = join(s.home, 't.jsonl')
    write(s.home, {'t.jsonl': JSON.stringify({type: 'assistant', message: {content: [{type: 'text', text}]}}) + '\n'})
    const strict = g.bool()
    const facts = {active: false, transcript: true, refs: parts.some((p) => p === 'good' || p === 'badline' || p === 'nofile'),
      unresolved: parts.includes('badline') || parts.includes('nofile'), strict}
    const out = f.run(facts)
    const env = {...s.env, CITATION_GUARD_LOG: join(s.home, 'cg.log'), ...(strict ? {CITATION_GUARD_STRICT: '1'} : {})}
    const r = runHook('citation-guard.sh', {hook_event_name: 'Stop', transcript_path: tr, cwd: dir, session_id: 's'}, {env})
    t.check(r.code === (out.block ? 2 : 0), () => ({case: i, text, facts, rule: out, hook: {code: r.code, stderr: r.stderr}}))
  }
  // The refuted law, against the real hook: a Stop already continuing (stop_hook_active) is still blocked.
  {
    const s = sandbox(), dir = tmp('kit-cite')
    write(dir, {'src/a.ts': 'one\n'})
    write(s.home, {'t.jsonl': JSON.stringify({type: 'assistant', message: {content: [{type: 'text', text: 'see src/a.ts:40'}]}}) + '\n'})
    const payload = {hook_event_name: 'Stop', transcript_path: join(s.home, 't.jsonl'), cwd: dir, session_id: 's', stop_hook_active: true}
    const r = runHook('citation-guard.sh', payload, {env: {...s.env, CITATION_GUARD_STRICT: '1', CITATION_GUARD_LOG: ''}})
    const want = f.run({active: true, transcript: true, refs: true, unresolved: true, strict: true}).block ? 2 : 0
    t.check(r.code === want, () => ({case: 'stop_hook_active', rule: want, hook: r.code}))
    if (r.code === 2) t.note('confirmed: strict mode blocks a Stop that is already continuing (stop_hook_active: true), exit 2')
  }
  return t.result()
}

if (import.meta.main) console.log(JSON.stringify(await bridge(), null, 2))
