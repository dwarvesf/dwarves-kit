// Bridge: compose task descriptions from phrases that each fire exactly one of lane-classify.sh's features
// (backfill, tiny, a hard-gate subject, a kit-machinery mention, doc-bootstrap, bug, 0-5 soft flags), pick --files
// (none, plain, a lib/ file, a migration), a configured default lane (operator kit.toml), a chosen and a current
// lane; run the real `classify`, `risk`, `check` and `escalate` (escalate reads the spec text with no --files);
// compare with the rule's decisions (lane-classify.ts).
import {mkdirSync, writeFileSync} from 'node:fs'
import {join} from 'node:path'
import {LANES, laneClassify} from './lane-classify.ts'
import {KIT, run, seeded, tmp, type BridgeResult} from './util.ts'

const SH = join(KIT, 'lib/classify/lane-classify.sh')
const SOFT = ['cross-platform', 'existing behavior', 'untested', 'multi-domain', 'race condition']
const FILES: [string | null, boolean, boolean][] = [[null, false, false], ['src/app.ts', false, false], ['lib/x.sh', false, true],
  ['db/migrations/001.sql', true, false], ['lib/x.sh db/migrations/001.sql', true, true]]
const DEFS = ['normal', 'full', 'bug', 'backfill'] as const

type Case = {backfill: boolean, tiny: boolean, hardText: boolean, machText: boolean, docBoot: boolean, bug: boolean, soft: number,
  files: number, def: number, chosen: string, current: string}

export async function bridge(): Promise<BridgeResult> {
  const f = laneClassify()
  const t = tmp('lane')
  let agree = 0
  try {
    const one = (c: Case, n: number) => {
      const desc = [c.backfill && 'backfill the operating layer docs', c.tiny && 'fix typo', c.hardText && 'rotate the jwt',
        c.machText && 'edit gate-ledger', c.docBoot && 'markdown-only notes', c.bug && 'crash on start', ...SOFT.slice(0, c.soft), 'add widget']
        .filter(Boolean).join(' and ')
      const op = join(t.dir, `op${n}`); mkdirSync(op)
      writeFileSync(join(op, 'kit.toml'), `[lanes]\ndefault = "${DEFS[c.def]}"\n`)
      const spec = join(t.dir, `spec${n}.md`); writeFileSync(spec, desc + '\n')
      const env = {KIT_CONFIG_OPERATOR: op, KIT_PROJECT_ROOT: t.dir, KIT_LEDGER_DIR: join(t.dir, 'ledger'), HOME: t.dir}
      const [fl, hardPath, machFile] = FILES[c.files]
      const fa = fl === null ? [] : ['--files', fl]
      const lane = run(['bash', SH, 'classify', ...fa, desc], {cwd: t.dir, env}).out.trim()
      const risk = run(['bash', SH, 'risk', ...fa, desc], {cwd: t.dir, env}).out.trim()
      const check = run(['bash', SH, 'check', ...fa, c.chosen, desc], {cwd: t.dir, env})
      const esc = run(['bash', SH, 'escalate', c.current, spec], {cwd: t.dir, env})
      const base = {backfill: c.backfill, tiny: c.tiny, hardText: c.hardText, machText: c.machText, docBoot: c.docBoot, bug: c.bug, soft: c.soft,
        def: DEFS[c.def], chosen: LANES.includes(c.chosen as never) ? c.chosen : 'unknown', current: LANES.includes(c.current as never) ? c.current : 'unknown'}
      const m = f.run({...base, filesSet: fl !== null, hardPath, machFile} as never) as {lane: string, risk: string, downgrade: boolean}
      const me = f.run({...base, filesSet: false, hardPath: false, machFile: false} as never) as {decision: string, lane: string}
      const escWord = esc.err.includes('LANE-UNKNOWN') ? 'UNKNOWN' : esc.out.trim().split(' ')[0]
      const bash = {lane, risk, downgrade: check.err.includes('LANE-DOWNGRADE'), decision: escWord}
      const want = {lane: m.lane, risk: m.risk, downgrade: m.downgrade, decision: me.decision}
      if (bash.lane !== want.lane || bash.risk !== want.risk || bash.downgrade !== want.downgrade || bash.decision !== want.decision)
        return {desc, files: fl, def: DEFS[c.def], chosen: c.chosen, current: c.current, bash, rule: want}
      agree++
      return null
    }
    const rand = seeded(50), b = (k = 2) => rand(k) === 0
    const lanes = [...LANES, 'weird']
    let n = 0
    // each feature alone, under each --files choice
    for (let k = 0; k < 7; k++) for (let fi = 0; fi < FILES.length; fi++) {
      const c: Case = {backfill: k === 0, tiny: k === 1, hardText: k === 2, machText: k === 3, docBoot: k === 4, bug: k === 5, soft: k === 6 ? 4 : 0,
        files: fi, def: 0, chosen: 'tiny', current: 'tiny'}
      const x = one(c, n++); if (x) return {agree, diverge: x}
    }
    for (let i = 0; i < 70; i++) {
      const c: Case = {backfill: b(5), tiny: b(5), hardText: b(3), machText: b(3), docBoot: b(4), bug: b(4), soft: rand(6),
        files: rand(FILES.length), def: rand(DEFS.length), chosen: lanes[rand(lanes.length)], current: lanes[rand(lanes.length)]}
      const x = one(c, n++); if (x) return {agree, diverge: x}
    }
    return {agree, diverge: null}
  } finally { t.done() }
}

// The refuted reviewer law on the real bash: a cosmetic task whose --files hold a migration is tiny, risk tiny.
export async function confirm() {
  const t = tmp('lane-cx')
  try {
    const env = {KIT_CONFIG_OPERATOR: join(t.dir, 'none'), KIT_PROJECT_ROOT: t.dir, KIT_LEDGER_DIR: join(t.dir, 'ledger'), HOME: t.dir}
    const a = run(['bash', SH, 'risk', '--files', 'db/migrations/001.sql', 'fix typo in the migration'], {cwd: t.dir, env}).out.trim()
    const b = run(['bash', SH, 'risk', '--files', 'db/migrations/001.sql', 'backfill the operating layer docs'], {cwd: t.dir, env}).out.trim()
    return [{law: 'a hard path in --files always makes the risk full',
      repro: "bash lib/classify/lane-classify.sh risk --files db/migrations/001.sql 'fix typo in the migration'",
      reproduced: a === 'tiny' && b === 'backfill', tinyRisk: a, backfillRisk: b}]
  } finally { t.done() }
}

if (import.meta.url === `file://${process.argv[1]}`) console.log(JSON.stringify({bridge: await bridge(), confirm: await confirm()}, null, 1))
