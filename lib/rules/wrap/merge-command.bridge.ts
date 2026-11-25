// Bridge: lib/config/merge-command.sh:kit_merge_command (the real function, its real git reads) against
// merge-command. For each class of the COMMITTED project .kit.toml there is a bare origin holding it on main and a
// clone; the clone's working-tree .kit.toml, the operator file and the kit-root file are rewritten per case. A
// repo with no origin covers "the default branch cannot be read". Each class is written in several concrete shapes
// (seeded), e.g. `bad` is a dotted key, an inline table, [[merge]], a single-quoted value, a repeated key or a `#`
// in the value; `quoted` is `["merge"]` or `['merge']` over a valid command line.
// `source: 'head'` runs the committed merge-command.sh (before the fix) against the 'quoted-header-unset' variant.
import {mkdirSync, writeFileSync} from 'node:fs'
import {join} from 'node:path'
import {bash, KIT, rng, sandbox, type BridgeResult} from './bridge-util.ts'
import {CLASSES, mergeCommand, type Variant} from './merge-command.ts'

type C = typeof CLASSES[number]

function text(rand: ReturnType<typeof rng>, c: C, who: string): string | null {
  const cmd = `bash scripts/${who}.sh`
  switch (c) {
    case 'none': return rand.pick([null, ''])
    case 'nokey': return rand.pick(['[wrap]\ndistill = false\n', '[merge]\ncommand = ""\n', '# [merge]\n# command = "x"\n'])
    case 'value': return rand.pick([`[merge]\ncommand = "${cmd}"\n`, `# project\n[merge]   # how we merge\n  command  =  "${cmd}"   # note\n[wrap]\ndistill = false\n`])
    case 'meta': return rand.pick([`[merge]\ncommand = "${cmd}; rm -rf x"\n`, `[merge]\ncommand = "${cmd} | tee log"\n`, `[merge]\ncommand = "$(${cmd})"\n`])
    case 'bad': return rand.pick([`merge.command = "${cmd}"\n`, `merge = { command = "${cmd}" }\n`, `[[merge]]\ncommand = "${cmd}"\n`,
      `[merge]\ncommand = '${cmd}'\n`, `[merge]\ncommand = "${cmd}"\ncommand = "${cmd}"\n`, `[merge]\ncommand = "${cmd} #1"\n`, `[merge.x]\ncommand = "${cmd}"\n`])
    case 'quoted': return rand.pick([`["merge"]\ncommand = "${cmd}"\n`, `['merge']\ncommand = "${cmd}"\n`, `[ "merge" ]\ncommand = "${cmd}"\n`])
  }
}
const srcOf = (v: string) => v.includes('scripts/p.sh') ? 3 : v.includes('scripts/o.sh') ? 2 : v.includes('scripts/r.sh') ? 1 : 0

export async function bridge(opts: {source?: 'work' | 'head', seed?: number} = {}): Promise<BridgeResult> {
  // The committed code has two bugs: the quoted header, and the /nonexistent path (which shows only on a host with
  // that directory, so not on macOS where `head` runs: there it is the quoted-header variant).
  const variant: Variant = opts.source === 'head' ? 'quoted-header-unset' : 'shipped'
  const f = mergeCommand(variant)
  const rand = rng(opts.seed ?? 5)
  const sb = sandbox('merge-command')
  try {
    // The committed copy sits beside kit-config.sh, which it sources by its own directory.
    const lib = opts.source === 'head' ? join(KIT, 'lib/config/.merge-command-head.sh') : join(KIT, 'lib/config/merge-command.sh')
    if (opts.source === 'head') bash(`git -C '${KIT}' show HEAD:lib/config/merge-command.sh > '${lib}'`, sb.env)
    // One origin per committed class.
    let setup = ''
    const repos: Record<string, string> = {}
    for (const c of CLASSES) {
      const seed = join(sb.dir, `seed-${c}`), bare = join(sb.dir, `bare-${c}.git`), clone = join(sb.dir, `clone-${c}`)
      const t = text(rand, c, 'p')
      setup += `git init -q -b main '${seed}'; mkdir -p '${seed}/scripts'; echo ok > '${seed}/scripts/p.sh'\n`
      if (t !== null) setup += `printf '%s' '${t.replace(/'/g, `'\\''`)}' > '${seed}/.kit.toml'\n`
      setup += `git -C '${seed}' add -A; git -C '${seed}' commit -q -m base; git clone -q --bare '${seed}' '${bare}'; git clone -q '${bare}' '${clone}'\n`
      repos[c] = clone
    }
    const lone = join(sb.dir, 'lone')
    setup += `git init -q -b main '${lone}'; git -C '${lone}' commit -q --allow-empty -m base\n`
    bash(setup, sb.env, sb.dir, 120_000)

    type Case = {baseOk: boolean, proj: C, work: C, op: C, root: C, repo: string, cfg: string}
    const cases: Case[] = []
    const mk = (baseOk: boolean, proj: C, work: C, op: C, root: C) => {
      const cfg = join(sb.dir, `cfg${cases.length}`)
      for (const [sub, cls, who] of [['o', op, 'o'], ['r', root, 'r'], ['w', work, 'p']] as const) {
        mkdirSync(join(cfg, sub), {recursive: true})
        const t = text(rand, cls, who)
        if (t !== null) writeFileSync(join(cfg, sub, sub === 'w' ? '.kit.toml' : 'kit.toml'), t)
      }
      cases.push({baseOk, proj, work, op, root, repo: baseOk ? repos[proj] : lone, cfg})
    }
    for (const proj of CLASSES) for (const op of CLASSES) for (const root of CLASSES) mk(true, proj, rand.pick(CLASSES), op, root)
    for (const work of CLASSES) for (const op of CLASSES) for (const root of CLASSES) mk(false, 'none', work, op, root)

    // Whether this host has a directory at /nonexistent (the home of `nobody` on some Linux images).
    const hostDir = bash('[ -d /nonexistent ]', sb.env).status === 0
    const out = bash(`source '${lib}'
      while IFS='|' read -r repo cfg; do
        rm -f "$repo/.kit.toml"; [ -f "$cfg/w/.kit.toml" ] && cp "$cfg/w/.kit.toml" "$repo/.kit.toml"
        v="$(KIT_CONFIG_OPERATOR="$cfg/o" KIT_CONFIG_ROOT="$cfg/r" kit_merge_command "$repo" 2>/dev/null </dev/null)"; rc=$?
        echo "$rc|$v"
      done <<'ROWS'
${cases.map((c) => `${c.repo}|${c.cfg}`).join('\n')}
ROWS`, sb.env, sb.dir, 600_000)
    const rows = out.stdout.trim().split('\n')
    let agree = 0
    for (let i = 0; i < cases.length; i++) {
      const c = cases[i]
      const [rc, v] = (rows[i] ?? '').split('|')
      const real = {rc: Number(rc), src: Number(rc) === 0 ? srcOf(v ?? '') : 0}
      const want = f.run({baseOk: c.baseOk, proj: c.proj, work: c.work, op: c.op, root: c.root, hostDir})
      if (real.rc !== want.rc || real.src !== want.src) {
        return {agree, diverge: {hostDir, case: {baseOk: c.baseOk, committedProject: c.proj, workingTree: c.work, operator: c.op, kitRoot: c.root}, bash: {rc, value: v}, rule: want, cfg: c.cfg}}
      }
      agree++
    }
    return {agree, diverge: null}
  } finally {
    if (!process.env.KEEP) sb.cleanup()
    if (opts.source === 'head') bash(`rm -f '${join(KIT, 'lib/config/.merge-command-head.sh')}'`, {PATH: '/usr/bin:/bin'})
  }
}

if (import.meta.url === `file://${process.argv[1]}`) {
  console.log(JSON.stringify(await bridge({source: process.argv[2] === 'head' ? 'head' : 'work'})))
}
