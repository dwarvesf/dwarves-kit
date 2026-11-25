// Bridge: hold hooks/slop-cleaner.sh to the slop-cleaner rule for one file in a temp git repo: a seeded run of Stops
// in which the file is rewritten (bloated or not, same or new content), made unreadable, or left alone.
import {chmodSync, utimesSync, writeFileSync} from 'node:fs'
import {createHash} from 'node:crypto'
import {slopCleaner} from './slop-cleaner.ts'
import {gitRepo, machine, rng, runHook, sandbox, Tally, join, type BridgeResult} from './_bridge.ts'

export async function bridge(): Promise<BridgeResult> {
  const t = new Tally()
  const g = rng(37)
  for (let run = 0; run < 10; run++) {
    const dir = gitRepo({'README.md': 'x'})
    const s = sandbox()
    const marker = join(s.home, 'marker')
    const env = {...s.env, DWARVES_KIT_SESSION_MARKER: marker}
    const m = machine(slopCleaner())
    const file = join(dir, 'big.py')
    const hashes = new Map<string, number>()
    let content = '', recent = false, readable = true
    for (let k = 0; k < 6; k++) {
      const act = g.pick(['bloat', 'bloat2', 'small', 'same', 'lock'])
      if (act !== 'same' && act !== 'lock') {
        content = act === 'small' ? 'x = 1\n' : Array.from({length: 320}, (_, i) => `v${i} = ${act === 'bloat' ? 1 : 2}\n`).join('')
        chmodSync(dir, 0o755); try { chmodSync(file, 0o644) } catch {}
        writeFileSync(file, content); readable = true; recent = true
      }
      if (act === 'lock' && content) { chmodSync(file, 0o000); readable = false }
      if (recent) { const future = Date.now() / 1000 + 5; utimesSync(file, future, future) }
      const active = g.next() < 0.15
      const h = createHash('sha1').update(content).digest('hex')
      if (!hashes.has(h)) hashes.set(h, hashes.size + 1)
      const facts = {active, git: true, recent: recent && content !== '', readable, bloated: content.split('\n').length > 300, hash: hashes.get(h)!}
      const want = m.step(facts)
      const r = runHook('slop-cleaner.sh', {hook_event_name: 'Stop', session_id: `slop-${run}`, stop_hook_active: active}, {env, cwd: dir})
      const reported = r.stdout.includes('big.py')
      t.check(r.code !== 2 && reported === want.reported, () => ({run, step: k, act, facts, rule: want, hook: {code: r.code, reported}}))
    }
    try { chmodSync(file, 0o644) } catch {}
  }
  return t.result()
}

if (import.meta.main) console.log(JSON.stringify(await bridge(), null, 2))
