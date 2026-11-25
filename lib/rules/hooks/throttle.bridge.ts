// Bridge: hold the harvest throttle to the rule through the real hooks/backlog-stage.sh (SessionEnd harvest). The
// model clock is mapped onto the stamp file: before each call the stamp's mtime is set so that (real now - mtime)
// equals (model now - model stamp); a run is observed as the stamp being touched to the real now. The extractor is a
// stub (no model call). Ages within two seconds of the interval are never drawn, so a tick of the real clock cannot
// flip a comparison.
import {existsSync, statSync, utimesSync} from 'node:fs'
import {throttle} from './throttle.ts'
import {machine, rng, runHook, sandbox, stubs, Tally, write, join, type BridgeResult} from './_bridge.ts'

export async function bridge(): Promise<BridgeResult> {
  const t = new Tally()
  const g = rng(29)
  for (let run = 0; run < 10; run++) {
    const s = sandbox()
    const auto = g.next() < 0.8, interval = g.pick([0, 3600, 3600, 600])
    const stateDir = join(s.home, 'bs'), stamp = join(stateDir, 'last-run')
    const tr = join(s.home, 't.jsonl'); write(s.home, {'t.jsonl': '{"type":"user","message":{"content":"x"}}\n'})
    const bin = stubs({extract: 'cat >/dev/null; echo "[]"'})
    const env: Record<string, string> = {...s.env, BACKLOG_STAGE_STATE_DIR: stateDir, BACKLOG_STAGE_MIN_INTERVAL: String(interval), BACKLOG_STAGE_SYNC: '1',
      BACKLOG_STAGE_EXTRACTOR: join(bin, 'extract'), BACKLOG_STAGE_PREFILTER: '0', BACKLOG_STAGE_STAGING: join(s.home, 'staging.md'), BACKLOG_STAGE_BACKLOG: join(s.home, 'board.md')}
    if (auto) env.BACKLOG_STAGE_AUTO = g.pick(['1', 'yes', 'on', 'true'])
    const m = machine(throttle(), {auto, interval})
    let now = 1_000_000
    for (let k = 0; k < 6; k++) {
      const before = m.state as {has: boolean, stamp: number}
      now += g.pick([10, 300, 1200, 4000, 7200])
      if (interval > 0 && before.has && Math.abs((now - before.stamp) - interval) < 3) now += 5
      const realNow = Math.floor(Date.now() / 1000)
      if (before.has && existsSync(stamp)) { const mt = realNow - (now - before.stamp); utimesSync(stamp, mt, mt) }
      const want = m.step({now})
      const mtimeBefore = existsSync(stamp) ? Math.floor(statSync(stamp).mtimeMs / 1000) : -1
      const r = runHook('backlog-stage.sh', {hook_event_name: 'SessionEnd', session_id: 's', transcript_path: tr, cwd: s.home}, {env})
      const mtimeAfter = existsSync(stamp) ? Math.floor(statSync(stamp).mtimeMs / 1000) : -1
      const touched = mtimeAfter >= realNow - 1 && (mtimeAfter !== mtimeBefore || mtimeBefore === -1 || mtimeBefore >= realNow - 1)
      // With interval 0 the hook never stamps; a run is then every call that got past the opt-in.
      const hookRan = interval === 0 ? auto : touched
      t.check(r.code === 0 && hookRan === want.ran, () => ({run, step: k, auto, interval, now, before, rule: want, hook: {code: r.code, touched, mtimeBefore, mtimeAfter, realNow}}))
    }
  }
  return t.result()
}

if (import.meta.main) console.log(JSON.stringify(await bridge(), null, 2))
