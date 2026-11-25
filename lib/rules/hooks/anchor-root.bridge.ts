// Bridge: hold hooks/anchor-root.sh to the anchor-root rule. The real wrapper runs a stub hook (in a temp dir, under
// the real hook's name) that exits 2 or 0; the module switch is set false or true in the operator kit.toml, in a
// committed project .kit.toml, or left at the table default. The stub never runs a real hook.
import {spawnSync} from 'node:child_process'
import {anchorRoot} from './anchor-root.ts'
import {HOOKS, gitRepo, rng, sandbox, Tally, tmp, write, join, type BridgeResult} from './_bridge.ts'

// hook -> [kind, module, opt-in default off?]
const HOOKS_T: [string, 'spine' | 'module' | 'unlisted', string, boolean][] = [
  ['safety-gate.sh', 'spine', 'spine', false], ['secrets-guard.sh', 'spine', 'spine', false], ['ship-gate.sh', 'spine', 'spine', false],
  ['anti-rationalization.sh', 'spine', 'spine', false], ['commit-format.sh', 'spine', 'spine', false], ['spec-drift-guard.sh', 'spine', 'spine', false],
  ['money-gate.sh', 'module', 'money_gate', true], ['context-budget.sh', 'module', 'session', true], ['tool-policy-guard.sh', 'module', 'advisor', true],
  ['board-row-gate.sh', 'module', 'board', false], ['kit-update-notice.sh', 'module', 'update_check', false], ['slop-cleaner.sh', 'module', 'cosmetic', true],
  ['made-up-hook.sh', 'unlisted', '', false],
]

export async function bridge(): Promise<BridgeResult> {
  const t = new Tally()
  const f = anchorRoot()
  const g = rng(47)
  for (let i = 0; i < 80; i++) {
    const [hook, kind, mod, optIn] = g.pick(HOOKS_T)
    const where = g.pick(['default', 'operator', 'project'] as const)
    const value = g.bool()
    const s = sandbox()
    const files: Record<string, string> = {}
    if (where === 'project' && mod) files['.kit.toml'] = `[modules]\n${mod} = ${value}\n`
    const repo = gitRepo(files)
    if (where === 'operator' && mod) write(s.home, {'op/kit.toml': `[modules]\n${mod} = ${value}\n`})
    const env = {...s.env, KIT_CONFIG_OPERATOR: join(s.home, 'op'), KIT_CONFIG_ROOT: join(s.home, 'kitroot')}
    const blocks = g.bool()
    const stubDir = tmp('kit-stub')
    write(stubDir, {[hook]: `cat >/dev/null; exit ${blocks ? 2 : 0}\n`})
    const moduleOff = kind === 'module' && (where === 'default' || !mod ? optIn : !value)
    const out = f.run({kind, moduleOff, hookBlocks: blocks})
    const r = spawnSync('bash', [join(HOOKS, 'anchor-root.sh'), join(stubDir, hook)], {input: '{}', env, cwd: repo, encoding: 'utf8'})
    t.check(r.status === (out.block ? 2 : 0), () => ({case: i, hook, kind, where, value, blocks, moduleOff, rule: out, hook_exit: r.status, stderr: r.stderr}))
  }
  return t.result()
}

if (import.meta.main) console.log(JSON.stringify(await bridge(), null, 2))
