// Bridge: lib/session/handoffs.sh (the real script) against handoff-archive and handoff-liveness.
//
// Archive: a clone of a bare origin (so the default branch resolves), on main or on a feature branch; every
// sequence of length 1..3 over create / archive / archiveAgain, with the handoff tracked (committed on create) or
// not. After each request the bridge reads which copies exist (_meta/handoffs/<name> and archive/<name>) and
// compares with the rule's state.
// Liveness: one repo with no origin (the working-tree board), a _meta/BACKLOG.md and BACKLOG-archive.md holding
// rows in live, terminal (shipped, dropped) and archive-word (done, Resolved) states, and seeded handoff files
// citing 0..4 IDs (some twice, some with no row). `handoffs.sh list --limit 0` prints one verdict per file.
import {mkdirSync, writeFileSync} from 'node:fs'
import {join} from 'node:path'
import {bash, KIT, rng, sandbox, sequences, type BridgeResult} from './bridge-util.ts'
import {handoffArchive, handoffLiveness, OPS, verdict} from './handoffs.ts'

const H = `${KIT}/lib/session/handoffs.sh`

async function archiveBridge(sb: ReturnType<typeof sandbox>): Promise<BridgeResult> {
  const seqs = sequences(OPS as readonly string[], 3)
  let agree = 0
  for (const tracked of [false, true]) for (const onDefault of [false, true]) {
    const r = handoffArchive(), it = r.interpreter(), p = r.encodeParams({tracked, onDefault})
    const script = seqs.map((seq, i) => {
      const d = join(sb.dir, `a-${tracked ? 't' : 'u'}${onDefault ? 'd' : 'b'}-${i}`)
      const ops = seq.map((op) => {
        const act = op === 'create'
          ? `[ -e "$HD/h.md" ] || { printf '# handoff\\n## Next\\ngo\\n' > "$HD/h.md"; ${tracked ? 'git -C "$R" add -A; git -C "$R" commit -q -m handoff;' : ''} }`
          : op === 'archive' ? `bash '${H}' archive --repo "$R" "$HD/h.md" >/dev/null 2>&1`
          : `bash '${H}' archive --repo "$R" "$HD/archive/h.md" >/dev/null 2>&1`
        return `${act}; echo "STEP $([ -e "$HD/h.md" ] && echo 1 || echo 0)$([ -e "$HD/archive/h.md" ] && echo 1 || echo 0)"`
      }).join('\n')
      return `( D='${d}'; git init -q -b main "$D/seed"; git -C "$D/seed" commit -q --allow-empty -m base
        git clone -q --bare "$D/seed" "$D/origin.git"; git clone -q "$D/origin.git" "$D/repo"; R="$D/repo"
        ${onDefault ? '' : 'git -C "$R" checkout -q -b feat'}
        HD="$R/_meta/handoffs"; mkdir -p "$HD"
        echo "CASE ${i}"
        ${ops} ) </dev/null`
    }).join('\n')
    const out = bash(script, sb.env, sb.dir, 300_000).stdout
    const blocks = out.split('CASE ').slice(1)
    for (let i = 0; i < seqs.length; i++) {
      const steps = (blocks[i] ?? '').split('\n').filter((l) => l.startsWith('STEP ')).map((l) => l.slice(5))
      let st = it.init(p)
      for (let k = 0; k < seqs[i].length; k++) {
        st = it.step(p, st, r.encodeInput({op: seqs[i][k]}))
        const d = r.decode(st) as {top: boolean, arch: boolean}
        const want = `${d.top ? 1 : 0}${d.arch ? 1 : 0}`
        if (steps[k] !== want) return {agree, diverge: {rule: 'handoff-archive', tracked, onDefault, requests: seqs[i].slice(0, k + 1), bash: steps[k], want}}
      }
      agree++
    }
  }
  return {agree, diverge: null}
}

async function livenessBridge(sb: ReturnType<typeof sandbox>, seed: number): Promise<BridgeResult> {
  const rand = rng(seed)
  const R = join(sb.dir, 'live')
  mkdirSync(join(R, '_meta', 'handoffs'), {recursive: true})
  const backlog: string[] = ['| ID | Title | Status |', '|---|---|---|']
  const archive: string[] = ['| ID | Title | Status |', '|---|---|---|']
  const files: {name: string, sts: string[]}[] = []
  let next = 1
  for (let f = 0; f < 120; f++) {
    const k = rand.int(5), sts: string[] = [], ids: string[] = []
    for (let j = 0; j < k; j++) {
      const id = `HO-${next++}`
      const st = rand.pick(['open', 'closed', 'missing'] as const)
      if (st === 'open') backlog.push(`| ${id} | t | ${rand.pick(['queued', 'executing', 'parked (waiting)', 'claimed'])} |`)
      if (st === 'closed') (rand.next() < 0.5 ? backlog : archive).push(`| ${id} | t | ${rand.pick(['shipped', 'dropped', 'done', 'Resolved [x]'])} |`)
      sts.push(st); ids.push(id)
    }
    const text = `# handoff ${f}\n\n## Next\nfollow up\n\n${ids.map((id) => `- see ${id}${rand.next() < 0.3 ? ` and again ${id}` : ''}`).join('\n')}\n`
    writeFileSync(join(R, '_meta', 'handoffs', `h${f}.md`), text)
    files.push({name: `h${f}.md`, sts})
  }
  writeFileSync(join(R, '_meta', 'BACKLOG.md'), backlog.join('\n') + '\n')
  writeFileSync(join(R, '_meta', 'BACKLOG-archive.md'), archive.join('\n') + '\n')
  const out = bash(`git init -q '${R}'; bash '${H}' list --repo '${R}' --limit 0`, sb.env, sb.dir, 120_000).stdout
  const r = handoffLiveness(), it = r.interpreter(), p = r.encodeParams({})
  let agree = 0
  for (const f of files) {
    const line = out.split('\n').find((l) => l.includes(`_meta/handoffs/${f.name} `)) ?? ''
    let st = it.init(p)
    for (const s of f.sts) st = it.step(p, st, r.encodeInput({st: s}))
    const d = r.decode(st) as {n: number, openN: number}
    const v = verdict(d)
    const real = /(LIVE|DEAD|UNCITED)(?: \((\d+) open| \(all (\d+) cited)?/.exec(line)
    const realV = real?.[1], realN = Number(real?.[2] ?? real?.[3] ?? 0)
    const wantN = v === 'LIVE' ? d.openN : v === 'DEAD' ? d.n : 0
    if (realV !== v || realN !== wantN) return {agree, diverge: {rule: 'handoff-liveness', file: f.name, statuses: f.sts, bash: line, rule_verdict: v, count: wantN}}
    agree++
  }
  return {agree, diverge: null}
}

export async function bridge(opts: {seed?: number} = {}): Promise<BridgeResult> {
  const sb = sandbox('handoffs')
  try {
    const a = await archiveBridge(sb)
    if (a.diverge) return a
    const l = await livenessBridge(sb, opts.seed ?? 3)
    return {agree: a.agree + l.agree, diverge: l.diverge, notes: [`archive ${a.agree}`, `liveness ${l.agree}`]}
  } finally { sb.cleanup() }
}

if (import.meta.url === `file://${process.argv[1]}`) console.log(JSON.stringify(await bridge(), null, 1))
