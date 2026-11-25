// Bridge: hold hooks/kit-update-notice.sh to the kit-update-notice rule with the network stubbed: `curl` is a stub that
// logs each call and answers from a file (or fails), and `date +%s` answers a clock the bridge moves (forward, by a day,
// backwards). The installed VERSION sits in a temp plugin root.
import {existsSync, readFileSync, rmSync, writeFileSync} from 'node:fs'
import {kitUpdateNotice} from './kit-update-notice.ts'
import {machine, rng, runHook, sandbox, stubs, Tally, tmp, write, join, type BridgeResult} from './_bridge.ts'

const V = (n: number) => `1.${Math.floor(n / 10)}.${n % 10}`  // 1..99 -> 1.0.1 .. 1.9.9, ordered like the naturals

export async function bridge(): Promise<BridgeResult> {
  const t = new Tally()
  const g = rng(13)
  for (let run = 0; run < 12; run++) {
    const s = sandbox()
    const ctl = tmp('kit-ctl')
    const bin = stubs({
      curl: `echo call >> "${ctl}/calls"; [ -f "${ctl}/remote" ] || exit 22; cat "${ctl}/remote"`,
      date: `if [ "\${1:-}" = "+%s" ]; then cat "${ctl}/now"; else exec /bin/date "$@"; fi`,
    })
    const installed = 10 + g.int(80), off = g.next() < 0.15
    const root = tmp('kit-root'); write(root, {VERSION: `${V(installed)}\n`})
    const env: Record<string, string> = {...s.env, PATH: `${bin}:${s.env.PATH}`, CLAUDE_PLUGIN_ROOT: root, KIT_UPDATE_STATE_DIR: join(s.home, 'un'), KIT_UPDATE_CHECK_URL: 'https://example.invalid/VERSION'}
    if (off) env.KIT_UPDATE_CHECK = '0'
    const m = machine(kitUpdateNotice(), {off, installed})
    let now = 1_800_000_000
    for (let k = 0; k < 6; k++) {
      now += g.pick([60, 3600, 86400, 90000, -7200])
      const ok = g.next() < 0.7, remote = g.pick([installed - 1, installed, installed + 1, installed + 5].filter((x) => x > 0 && x < 100))
      writeFileSync(join(ctl, 'now'), String(now))
      if (ok) writeFileSync(join(ctl, 'remote'), `${V(remote)}\n`); else rmSync(join(ctl, 'remote'), {force: true})
      const before = existsSync(join(ctl, 'calls')) ? readFileSync(join(ctl, 'calls'), 'utf8').split('\n').length : 0
      const want = m.step({now, ok, remote: ok ? remote : 0})
      const r = runHook('kit-update-notice.sh', {hook_event_name: 'SessionStart', source: 'startup'}, {env})
      const after = existsSync(join(ctl, 'calls')) ? readFileSync(join(ctl, 'calls'), 'utf8').split('\n').length : 0
      const hook = {fetched: after > before, notified: r.stdout.includes('is available')}
      t.check(r.code === 0 && hook.fetched === want.fetched && hook.notified === want.notified, () => ({run, step: k, now, ok, remote, installed, off, rule: want, hook}))
    }
  }
  return t.result()
}

if (import.meta.main) console.log(JSON.stringify(await bridge(), null, 2))
