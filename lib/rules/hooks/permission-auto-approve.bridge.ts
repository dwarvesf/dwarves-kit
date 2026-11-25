// Bridge: hold hooks/permission-auto-approve.sh to the rule over a labelled corpus of PermissionRequest payloads, run
// in a git work tree, in a plain dir, and in a dir with a bare-repo layout. `writes` is what the command really does;
// any approval of a writing command is reported.
import {permissionAutoApprove} from './permission-auto-approve.ts'
import {gitRepo, runHook, sandbox, sh, Tally, tmp, type BridgeResult} from './_bridge.ts'

type F = Record<string, unknown>
const B = (cmd: string, f: F = {}) => ({cmd, f: {tool: 'Bash', empty: false, nul: false, newline: false, safeChars: true, words: true,
  first: 'other', sub: 'other', star: false, flagsSafe: true, remoteOk: false, writes: false, ...f}})
const CORPUS = [
  B('ls -la', {first: 'fast'}), B('cat README.md', {first: 'fast'}), B('grep -rn foo src', {first: 'fast'}), B('wc -l a b', {first: 'fast'}),
  B('pwd', {first: 'pwd'}), B('pwd -P', {first: 'other'}), B('echo hello', {first: 'fast'}), B('du -sh .', {first: 'fast'}),
  B('git status', {first: 'git', sub: 'statusLs'}), B('git status --porcelain', {first: 'git', sub: 'statusLs'}), B('git ls-files', {first: 'git', sub: 'statusLs'}),
  B('git log --oneline -n 5', {first: 'git', sub: 'logDiffShow'}), B('git log -20', {first: 'git', sub: 'logDiffShow'}),
  B('git diff --stat', {first: 'git', sub: 'logDiffShow'}), B('git show HEAD', {first: 'git', sub: 'logDiffShow'}),
  B('git log --format=%G?', {first: 'git', sub: 'logDiffShow', flagsSafe: false}),
  B('git log --output=out.txt', {first: 'git', sub: 'logDiffShow', flagsSafe: false, writes: true}),
  B('git diff --ext-diff', {first: 'git', sub: 'logDiffShow', flagsSafe: false}),
  B('git log *.ts', {first: 'git', sub: 'logDiffShow', star: true}),
  B('git branch', {first: 'git', sub: 'branchTag'}), B('git branch -vv', {first: 'git', sub: 'branchTag'}),
  B('git branch newfeature', {first: 'git', sub: 'branchTag', flagsSafe: false, writes: true}),
  B('git branch -D old', {first: 'git', sub: 'branchTag', flagsSafe: false, writes: true}),
  B('git tag -l', {first: 'git', sub: 'branchTag'}), B('git tag v1', {first: 'git', sub: 'branchTag', flagsSafe: false, writes: true}),
  B('git remote', {first: 'git', sub: 'remote', remoteOk: true}), B('git remote -v', {first: 'git', sub: 'remote', remoteOk: true}),
  B('git remote add x y', {first: 'git', sub: 'remote', remoteOk: false, writes: true}),
  B('git commit -m x', {first: 'git', sub: 'other', writes: true}), B('git push', {first: 'git', sub: 'other', writes: true}),
  B('git -C /tmp log', {first: 'git', sub: 'other'}),
  B('find . -name x', {first: 'find'}), B('find . -type f -maxdepth 2', {first: 'find'}),
  B('find . -delete', {first: 'find', flagsSafe: false, writes: true}), B('find . -name *.ts', {first: 'find', star: true}),
  B('find . -newer x', {first: 'find', flagsSafe: false}), B('find . -fprint out', {first: 'find', flagsSafe: false, writes: true}),
  B('file -b x', {first: 'file'}), B('file -C -m magic', {first: 'file', flagsSafe: false, writes: true}),
  B('rm -rf x', {first: 'other', writes: true}), B('npm test', {first: 'other'}),
  B('ls > out.txt', {first: 'fast', safeChars: false, writes: true}), B('ls; rm x', {first: 'fast', safeChars: false, writes: true}),
  B('cat a | sh', {first: 'fast', safeChars: false, writes: true}), B('echo $(rm x)', {first: 'fast', safeChars: false, writes: true}),
  B('ls\nrm x', {first: 'fast', newline: true, safeChars: false, writes: true}), B('   ', {words: false, first: 'other'}),
  B('', {empty: true, words: false}),
  {cmd: null, f: {tool: 'Read', empty: true, nul: false, newline: false, safeChars: false, words: false, first: 'other', sub: 'other', star: false, flagsSafe: false, remoteOk: false, writes: false}},
  {cmd: null, f: {tool: 'Grep', empty: true, nul: false, newline: false, safeChars: false, words: false, first: 'other', sub: 'other', star: false, flagsSafe: false, remoteOk: false, writes: false}},
  {cmd: null, f: {tool: 'Other', empty: true, nul: false, newline: false, safeChars: false, words: false, first: 'other', sub: 'other', star: false, flagsSafe: false, remoteOk: false, writes: true}},
]

export async function bridge(): Promise<BridgeResult> {
  const t = new Tally()
  const f = permissionAutoApprove()
  const repo = gitRepo({'README.md': 'x'})
  const plain = tmp('kit-plain')
  const bare = tmp('kit-bare'); sh('git init -q --bare .', bare)
  const env = sandbox().env
  for (const [where, dir, worktree] of [['work tree', repo, true], ['plain dir', plain, false], ['bare layout', bare, false]] as const) {
    for (const c of CORPUS) {
      const tool = c.f.tool as string
      const name = tool === 'Other' ? 'mcp__x__y' : tool
      const payload = {hook_event_name: 'PermissionRequest', tool_name: name, tool_input: c.cmd === null ? {file_path: 'x'} : {command: c.cmd}, cwd: dir}
      const out = f.run({...c.f, worktree} as any)
      const r = runHook('permission-auto-approve.sh', payload, {env, cwd: dir})
      const approved = r.stdout.includes('"behavior":"allow"')
      const denied = /deny|block/.test(r.stdout)
      t.check(r.code === 0 && approved === out.approve && !denied, () => ({where, cmd: c.cmd, tool, facts: c.f, rule: out, hook: {code: r.code, approved, out: r.stdout}}))
      if (approved && c.f.writes) t.note(`approved a writing command: ${c.cmd ?? tool} (${where})`)
    }
  }
  return t.result()
}

if (import.meta.main) console.log(JSON.stringify(await bridge(), null, 2))
