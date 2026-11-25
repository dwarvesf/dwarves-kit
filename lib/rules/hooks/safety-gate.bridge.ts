// Bridge: hold hooks/safety-gate.sh to the safety-gate rule.
//
// Each corpus entry is a command string and the facts it REALLY carries, one record per segment that runs (labelled
// by hand from what bash and git would do, not from what the hook parses). The rule decides each segment; the
// command should be refused when any segment is. The real hook runs on the command as a PreToolUse payload, with the
// config the rule says must not matter varied around it (DWARVES_KIT_DEBUG, every [gate] key off in a committed
// .kit.toml, the spine's module off, an autonomy phrase in the environment).
//
// Two kinds of known difference are reported, not counted as divergences:
//   hole      a destructive command the hook's header lists as an accepted, fail-open hole (a ref in a variable, a
//             script from a file, a wrapper outside its table), backstopped by branch protection or ship-gate.
//   failSafe  a harmless command the naive pass refuses on purpose (prose that looks like a command inside quotes).
// Seeded random commands are built from parts whose facts are known by construction.
import {safetyGate} from './safety-gate.ts'
import {gitRepo, rng, runHook, sandbox, Tally, write, type BridgeResult} from './_bridge.ts'

type Seg = Parameters<ReturnType<typeof safetyGate>['run']>[0]
const base: Seg = {bin: 'other', rmR: false, rmF: false, rmSafe: false, findDel: 'none', findSafe: false, gitSub: 'other',
  force: 'none', spread: 'none', mainRef: 'none', hard: 'none', kdelete: 'none', dropTable: false, autonomy: 'low', debug: false, gatesOff: false}
const other = (): Seg => ({...base})
const rm = (rmR: boolean, rmF: boolean, rmSafe: boolean): Seg => ({...base, bin: 'rm', rmR, rmF, rmSafe})
const find = (findDel: string, findSafe: boolean): Seg => ({...base, bin: 'find', findDel, findSafe})
const push = (p: {force?: string, spread?: string, mainRef?: string} = {}): Seg => ({...base, bin: 'git', gitSub: 'push', ...p})
const reset = (hard: string): Seg => ({...base, bin: 'git', gitSub: 'reset', hard})
const git = (): Seg => ({...base, bin: 'git'})
const kube = (kdelete: string): Seg => ({...base, bin: 'kubectl', kdelete})
const sql = (dropTable: boolean): Seg => ({...base, bin: 'sql', dropTable})

type Case = {cmd: string, segs: Seg[], hole?: string, failSafe?: string}
export const CORPUS: Case[] = [
  // rm
  {cmd: 'rm -rf /tmp/foo', segs: [rm(true, true, false)]},
  {cmd: 'rm -rf node_modules', segs: [rm(true, true, true)]},
  {cmd: 'rm -rf ./dist build/ .next/cache', segs: [rm(true, true, true)]},
  {cmd: 'rm -rf node_modules /', segs: [rm(true, true, false)]},
  {cmd: 'rm -rf node_modules/../..', segs: [rm(true, true, false)]},
  {cmd: 'rm -r -f src', segs: [rm(true, true, false)]},
  {cmd: 'rm -fR ~', segs: [rm(true, true, false)]},
  {cmd: 'rm --recursive --force docs', segs: [rm(true, true, false)]},
  {cmd: 'rm -rfv -- "$HOME/x"', segs: [rm(true, true, false)]},
  {cmd: 'rm -rf', segs: [rm(true, true, false)]},
  {cmd: 'rm -f a.txt', segs: [rm(false, true, false)]},
  {cmd: 'rm -r build', segs: [rm(true, false, true)]},
  {cmd: '/bin/rm -rf /', segs: [rm(true, true, false)]},
  {cmd: '\\rm -rf src', segs: [rm(true, true, false)]},
  {cmd: "r'm' -rf src", segs: [rm(true, true, false)]},
  {cmd: 'command rm -rf src', segs: [rm(true, true, false)]},
  {cmd: 'sudo -u root rm -rf /var/lib/x', segs: [rm(true, true, false)]},
  {cmd: 'env -i FOO=1 rm -rf src', segs: [rm(true, true, false)]},
  {cmd: 'FOO=1 BAR="a b" rm -rf src', segs: [rm(true, true, false)]},
  {cmd: 'nice -n 10 rm -rf src', segs: [rm(true, true, false)]},
  {cmd: 'timeout 5m rm -rf src', segs: [rm(true, true, false)]},
  {cmd: 'cd /tmp && rm -rf x', segs: [other(), rm(true, true, false)]},
  {cmd: 'ls; rm -rf x', segs: [other(), rm(true, true, false)]},
  {cmd: 'true || rm -rf x', segs: [other(), rm(true, true, false)]},
  {cmd: 'find . -name x | xargs rm -rf', segs: [find('none', false), rm(true, true, false)]},
  {cmd: 'echo "$(rm -rf src)"', segs: [other(), rm(true, true, false)]},
  {cmd: 'x=`rm -rf src`', segs: [rm(true, true, false)]},
  {cmd: '( cd sub && rm -rf data )', segs: [other(), rm(true, true, false)]},
  {cmd: 'if true; then rm -rf data; fi', segs: [other(), rm(true, true, false), other()]},
  {cmd: 'bash -c "rm -rf data"', segs: [rm(true, true, false)]},
  {cmd: 'rm -rf data # cleanup', segs: [rm(true, true, false)]},
  {cmd: 'echo hi # rm -rf data', segs: [other()]},
  {cmd: 'cat <<EOF > notes.md\nrm -rf / is how you lose a disk\nEOF', segs: [other()]},
  {cmd: "cat <<'EOF' | psql\nselect 1;\nEOF\nrm -rf data", segs: [other(), sql(false), rm(true, true, false)]},
  {cmd: 'bash -s <<EOF\nrm -rf "/tmp/x"\nEOF\necho done', segs: [rm(true, true, false), other()], hole: 'a heredoc body is data to the hook, even when bash -s runs it (test-hooks.sh FP3 pins this)'},
  {cmd: 'FOO="a b" rm -rf src', segs: [rm(true, true, false)]},
  {cmd: "env MSG='hello world' rm -rf src", segs: [rm(true, true, false)]},
  {cmd: 'GIT_SSH_COMMAND="ssh -i ~/.ssh/deploy" git push -f origin feat/x', segs: [push({force: 'force'})]},
  {cmd: 'git -c user.name="A B" push --force origin feat/x', segs: [push({force: 'force'})]},
  {cmd: 'git -c core.sshCommand="ssh -v" reset --hard', segs: [reset('exact')]},
  {cmd: 'echo "a b" X="a b" rm -rf src', segs: [other()]},
  {cmd: "bash -c \"A='x y' rm -rf z\"", segs: [rm(true, true, false)]},
  {cmd: '2>/dev/null rm -rf src', segs: [rm(true, true, false)]},
  {cmd: 'rm -rf src > /dev/null 2>&1', segs: [rm(true, true, false)]},
  {cmd: 'xargs -0 rm -rf < list.txt', segs: [rm(true, true, false)]},
  {cmd: 'watch -n 1 rm -rf tmpdir', segs: [rm(true, true, false)]},
  {cmd: 'git push --set-upstream origin main', segs: [push({mainRef: 'named'})]},
  {cmd: 'git push origin HEAD:refs/heads/main --force-with-lease', segs: [push({force: 'lease', mainRef: 'named'})]},
  {cmd: 'git reset HEAD~1 --hard', segs: [reset('exact')]},
  {cmd: 'git commit -m "fix: stop rm -rf from wiping the cache"', segs: [git()]},
  {cmd: 'git commit -m "chore: x; rm -rf y"', segs: [git()], failSafe: 'the naive pass splits quoted prose on ;'},
  {cmd: 'B=/; rm -rf $B', segs: [other(), rm(true, true, false)]},
  {cmd: 'ssh host rm -rf /srv', segs: [rm(true, true, false)], hole: 'ssh is outside the segment-start wrapper table'},
  {cmd: 'bash cleanup.sh', segs: [rm(true, true, false)], hole: 'a script run from a file is not read'},
  {cmd: 'timeout -s KILL 5 rm -rf src', segs: [rm(true, true, false)], hole: 'a wrapper flag operand the table does not list (timeout -s SIG)'},
  // find
  {cmd: 'find ~/.cache/.bun -mindepth 1 -delete', segs: [find('delete', false)]},
  {cmd: 'find node_modules -name "*.map" -delete', segs: [find('delete', true)]},
  {cmd: 'find . -name "*.pyc" -delete', segs: [find('delete', false)]},
  {cmd: 'find -delete', segs: [find('delete', false)]},
  {cmd: 'find . -type f -exec rm {} \\;', segs: [find('execRm', false)]},
  {cmd: 'find . -execdir /bin/rm -f {} +', segs: [find('execRm', false)]},
  {cmd: 'find src -exec /opt/homebrew/bin/rm -f {} +', segs: [find('execPathRm', false)]},
  {cmd: 'find src -exec /usr/local/bin/rm {} \\;', segs: [find('execPathRm', false)]},
  {cmd: "find src -exec sh -c 'rm -rf \"$1\"' _ {} \\;", segs: [find('execRm', false)]},
  {cmd: 'find . -name "*.ts" -print', segs: [find('none', false)]},
  {cmd: 'find dist -exec rm -rf {} +', segs: [find('execRm', true)]},
  // git push
  {cmd: 'git push origin main', segs: [push({mainRef: 'named'})]},
  {cmd: 'git push origin master', segs: [push({mainRef: 'named'})]},
  {cmd: 'git push origin HEAD:main', segs: [push({mainRef: 'named'})]},
  {cmd: 'git push origin feat/x:refs/heads/master', segs: [push({mainRef: 'named'})]},
  {cmd: 'git push origin "main"', segs: [push({mainRef: 'named'})]},
  {cmd: 'git push origin ma\\in', segs: [push({mainRef: 'named'})]},
  {cmd: "git push origin $'main'", segs: [push({mainRef: 'named'})]},
  {cmd: 'git push --delete origin main', segs: [push({mainRef: 'named'})]},
  {cmd: 'git push origin :main', segs: [push({mainRef: 'named'})]},
  {cmd: 'git -C repo push origin main', segs: [push({mainRef: 'named'})]},
  {cmd: 'git -c push.default=current push origin main', segs: [push({mainRef: 'named'})]},
  {cmd: 'git push -o "ci.skip;x" origin main', segs: [push({mainRef: 'named'})]},
  {cmd: 'git push origin refs/tags/v1.0:refs/heads/main', segs: [push({mainRef: 'behindTag'})]},
  {cmd: 'git push origin refs/tags/v1.0', segs: [push()]},
  {cmd: 'git push origin "refs/tags/*"', segs: [push()]},
  {cmd: 'git push origin main:feature', segs: [push()]},
  {cmd: 'git push -u origin feat/login', segs: [push()]},
  {cmd: 'git push -u origin HEAD', segs: [push()]},
  {cmd: 'git push --force-with-lease origin feat/x', segs: [push({force: 'lease'})]},
  {cmd: 'git push --force-with-lease=feat/x:abc origin feat/x', segs: [push({force: 'lease'})]},
  {cmd: 'git push --force-if-includes --force-with-lease origin feat/x', segs: [push({force: 'lease'})]},
  {cmd: 'git push --force origin feat/x', segs: [push({force: 'force'})]},
  {cmd: 'git push -f origin feat/x', segs: [push({force: 'force'})]},
  {cmd: 'git push -uf origin feat/x', segs: [push({force: 'force'})]},
  {cmd: 'git push origin +feat/x', segs: [push({force: 'plus'})]},
  {cmd: 'git push --force-with-lease origin main', segs: [push({force: 'lease', mainRef: 'named'})]},
  {cmd: 'git push --mirror origin', segs: [push({spread: 'mirror'})]},
  {cmd: 'git push --all origin', segs: [push({spread: 'all'})]},
  {cmd: "git push origin 'refs/heads/*:refs/heads/*'", segs: [push({spread: 'glob'})]},
  {cmd: 'git push origin {a,b}', segs: [push({spread: 'glob'})]},
  {cmd: 'git push --branches origin', segs: [push({spread: 'branches'})]},
  {cmd: 'git push --mirr origin', segs: [push({spread: 'abbrev'})]},
  {cmd: 'git push --al origin', segs: [push({spread: 'abbrev'})]},
  {cmd: 'git push --br origin', segs: [push({spread: 'abbrev'})]},
  {cmd: 'git push --m origin', segs: [push({spread: 'abbrev'})]},
  {cmd: 'git push --b origin', segs: [push({spread: 'abbrev'})]},
  {cmd: 'git push --tags origin', segs: [push()]},
  {cmd: 'git push -q && gh pr edit 41 --base master', segs: [push(), other()]},
  {cmd: 'gh pr create --base main --title "feat: x"', segs: [other()]},
  {cmd: 'git log origin/main..HEAD', segs: [git()]},
  {cmd: 'git checkout main', segs: [git()]},
  {cmd: 'git merge -X ours -q -m "merge upstream default branch" ca3e5b8', segs: [git()]},
  {cmd: 'B=main; git push origin $B', segs: [other(), push({mainRef: 'named'})], hole: 'a ref hidden in a variable is not resolved'},
  {cmd: "printf 'git push origin main' | bash", segs: [other(), push({mainRef: 'named'})], hole: 'a script fed through a pipe is not read'},
  // git reset
  {cmd: 'git reset --hard', segs: [reset('exact')]},
  {cmd: 'git reset --hard HEAD~3', segs: [reset('exact')]},
  {cmd: 'git -C sub reset --hard origin/main', segs: [reset('exact')]},
  {cmd: 'git reset --har HEAD~1', segs: [reset('abbrev')]},
  {cmd: 'git reset --ha', segs: [reset('abbrev')]},
  {cmd: 'git reset --h', segs: [reset('abbrev')]},
  {cmd: 'git reset --soft HEAD~1', segs: [reset('none')]},
  {cmd: 'git reset --keep HEAD~1', segs: [reset('none')]},
  {cmd: 'git stash && git reset --hard', segs: [git(), reset('exact')]},
  // kubectl
  {cmd: 'kubectl delete pod x', segs: [kube('plain')]},
  {cmd: 'kubectl -n prod delete deploy api', segs: [kube('plain')]},
  {cmd: 'kubectl --context=prod delete ns x', segs: [kube('plain')]},
  {cmd: 'kubectl -v 6 delete pod x', segs: [kube('afterValueFlag')]},
  {cmd: 'kubectl --request-timeout 5s delete pod x', segs: [kube('afterValueFlag')]},
  {cmd: 'kubectl get pods -l app=delete', segs: [kube('none')]},
  {cmd: 'kubectl logs job/delete-old', segs: [kube('none')]},
  // SQL
  {cmd: 'psql -c "DROP TABLE users"', segs: [sql(true)]},
  {cmd: 'psql -c "drop  table users"', segs: [sql(true)]},
  {cmd: 'PGPASSWORD=x psql -h db -c "DROP TABLE IF EXISTS t"', segs: [sql(true)]},
  {cmd: 'echo "DROP TABLE t;" | mysql prod', segs: [other(), sql(true)]},
  {cmd: 'sqlite3 app.db <<SQL\nDROP TABLE t;\nSQL', segs: [sql(true)]},
  {cmd: 'psql -c "select 1"', segs: [sql(false)]},
  {cmd: 'echo "DROP TABLE is dangerous"', segs: [other()]},
  {cmd: 'docker exec db psql -c "DROP TABLE users"', segs: [sql(true)], hole: 'docker exec is outside the segment-start wrapper table'},
]

// Parts for random commands: a core whose facts are known, a wrapper or prefix, a quoting style, a neighbour.
const CORES: {text: string, seg: Seg}[] = [
  {text: 'rm -rf src', seg: rm(true, true, false)}, {text: 'rm -rf dist', seg: rm(true, true, true)},
  {text: 'rm -f x', seg: rm(false, true, false)}, {text: 'find /tmp/x -delete', seg: find('delete', false)},
  {text: 'git push origin main', seg: push({mainRef: 'named'})}, {text: 'git push -u origin feat/y', seg: push()},
  {text: 'git push -f origin feat/y', seg: push({force: 'force'})}, {text: 'git push --force-with-lease origin feat/y', seg: push({force: 'lease'})},
  {text: 'git reset --hard', seg: reset('exact')}, {text: 'git status', seg: git()},
  {text: 'kubectl delete pod p', seg: kube('plain')}, {text: 'kubectl get pod p', seg: kube('none')},
  {text: 'ls -la', seg: other()}, {text: 'npm test', seg: other()},
]
const WRAPS = ['', 'sudo ', 'env A=1 ', 'A=1 ', 'command ', 'nice -n 5 ', 'timeout 30 ', 'nohup ', 'time ']
const NEIGHBOURS = ['ls', 'echo ok', 'cd /tmp', 'npm run build', 'git status']
const JOINS = [' && ', ' ; ', ' || ', '\n']

const ENVS = ['DWARVES_KIT_DEBUG', 'KIT_AUTONOMY'] as const
function variantsOfConfig(): {name: string, env: Record<string, string>, cwd?: string}[] {
  const s = sandbox()
  const off = gitRepo({'.kit.toml': '[gate]\nunderstanding_gate = false\ncommit_format = false\nboard_row_gate = false\nproof_of_done = false\nlane_gates = false\n[modules]\nspine = false\n'})
  write(s.home, {'.config/dwarves-kit/kit.toml': '[modules]\nspine = false\n'})
  return [
    {name: 'plain', env: s.env},
    {name: 'debug + max autonomy phrase', env: {...s.env, [ENVS[0]]: '1', [ENVS[1]]: 'max'}},
    {name: 'every gate and the spine module off', env: s.env, cwd: off},
  ]
}

export async function bridge(): Promise<BridgeResult> {
  const t = new Tally()
  const f = safetyGate()
  const configs = variantsOfConfig()
  const decide = (segs: Seg[]) => segs.some((s) => f.run(s).block)
  const holes: string[] = [], failSafes: string[] = []
  const one = (c: Case, cfg: typeof configs[number]) => {
    const want = decide(c.segs) ? 2 : 0
    const r = runHook('safety-gate.sh', {tool_name: 'Bash', tool_input: {command: c.cmd}}, {env: cfg.env, cwd: cfg.cwd})
    if (c.hole && r.code === 0 && want === 2) { holes.push(`${JSON.stringify(c.cmd)}: ${c.hole}`); return }
    if (c.failSafe && r.code === 2 && want === 0) { failSafes.push(`${JSON.stringify(c.cmd)}: ${c.failSafe}`); return }
    t.check(r.code === want, () => ({cmd: c.cmd, config: cfg.name, rule: want, hook: r.code, stderr: r.stderr.trim(), facts: c.segs}))
  }
  for (const c of CORPUS) for (const cfg of configs) one(c, cfg)
  const g = rng(20261125)
  for (let i = 0; i < 150; i++) {
    const core = g.pick(CORES), wrap = g.pick(WRAPS), n = g.pick(NEIGHBOURS), j = g.pick(JOINS)
    const before = g.bool()
    const cmd = before ? `${n}${j}${wrap}${core.text}` : `${wrap}${core.text}${j}${n}`
    const nSeg = n.startsWith('git') ? git() : other()
    one({cmd, segs: [nSeg, core.seg]}, configs[g.int(configs.length)])
  }
  for (const h of [...new Set(holes)]) t.note(`documented hole (hook allows): ${h}`)
  for (const h of [...new Set(failSafes)]) t.note(`fail-safe over-block (hook refuses): ${h}`)
  return t.result()
}

if (import.meta.main) console.log(JSON.stringify(await bridge(), null, 2))
