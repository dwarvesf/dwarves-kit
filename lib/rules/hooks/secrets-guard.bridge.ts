// Bridge: hold hooks/secrets-guard.sh to the secrets-guard rule over a corpus of payloads in a temp HOME, with real
// files and symlinks on disk. Facts are labelled from the documented glob and token lists (hooks/secrets-guard.sh
// :39-50, :107-108); `secretFile` says whether the target is a credential in fact, and every corpus entry where that
// differs from the lists is reported as a coverage note.
import {secretsGuard} from './secrets-guard.ts'
import {runHook, sandbox, symlinkSync, Tally, tmp, write, join, type BridgeResult} from './_bridge.ts'

type C = {tool: string, path?: string, cmd?: string, lexSecret?: boolean, resSecret?: boolean, resAllowed?: boolean, lexAllowed?: boolean,
  readerWord?: boolean, secretToken?: boolean, secretFile?: boolean, rel?: boolean}

export async function bridge(): Promise<BridgeResult> {
  const t = new Tally()
  const s = sandbox(), H = s.home
  const proj = tmp('kit-proj')
  write(H, {'.ssh/id_rsa': 'k', '.ssh/config': 'Host x', '.aws/credentials': 'k', '.npmrc': 'k', '.config/gh/hosts.yml': 'k', '.kube/config': 'k'})
  write(proj, {'.env': 'K=1', '.env.local': 'K=1', '.env.example': 'K=', '.env.staging': 'K=1', '.envrc': 'export K=1', 'cert.pem': 'k',
    'src/app.ts': 'x', 'notes.txt': 'x'})
  symlinkSync(join(proj, '.env'), join(proj, 'innocent.txt'))
  symlinkSync(join(proj, '.env'), join(proj, 'fake.env.example'))
  symlinkSync(join(proj, '.env.example'), join(proj, 'template-link'))
  const S = (o: C): C => ({lexSecret: false, resSecret: false, resAllowed: false, lexAllowed: false, readerWord: false, secretToken: false, secretFile: false, ...o})
  const cases: C[] = [
    S({tool: 'Read', path: `${H}/.ssh/id_rsa`, lexSecret: true, resSecret: true, secretFile: true}),
    S({tool: 'Read', path: '~/.ssh/id_rsa', lexSecret: true, resSecret: true, secretFile: true}),
    S({tool: 'Read', path: '$HOME/.aws/credentials', lexSecret: true, resSecret: true, secretFile: true}),
    S({tool: 'Read', path: `${H}/.ssh/config`, lexSecret: true, resSecret: true}),
    S({tool: 'Edit', path: `${H}/.npmrc`, lexSecret: true, resSecret: true, secretFile: true}),
    S({tool: 'Read', path: `${H}/.config/gh/hosts.yml`, lexSecret: true, resSecret: true, secretFile: true}),
    S({tool: 'Read', path: `${proj}/.env`, lexSecret: true, resSecret: true, secretFile: true}),
    S({tool: 'Read', path: `${proj}/src/../.env`, lexSecret: true, resSecret: true, secretFile: true}),
    S({tool: 'Read', path: '.env', rel: true, lexSecret: true, resSecret: true, secretFile: true}),
    S({tool: 'Read', path: `${proj}/.env.local`, lexSecret: true, resSecret: true, secretFile: true}),
    S({tool: 'Read', path: `${proj}/.env.example`, resAllowed: true, lexAllowed: true}),
    S({tool: 'Read', path: `${proj}/template-link`, resAllowed: true}),
    S({tool: 'Read', path: `${proj}/innocent.txt`, resSecret: true, secretFile: true}),
    S({tool: 'Read', path: `${proj}/fake.env.example`, lexAllowed: true, resSecret: true, secretFile: true}),
    S({tool: 'Read', path: `${proj}/cert.pem`, lexSecret: true, resSecret: true, secretFile: true}),
    S({tool: 'Read', path: `${proj}/.env.staging`, secretFile: true}),
    S({tool: 'Read', path: `${proj}/.envrc`, secretFile: true}),
    S({tool: 'Read', path: `${proj}/src/app.ts`}),
    S({tool: 'Write', path: `${proj}/.env`, secretFile: true}),
    S({tool: 'Grep', path: `${proj}/.env`, secretFile: true}),
    S({tool: 'Bash', cmd: 'cat ~/.ssh/id_rsa', readerWord: true, secretToken: true, secretFile: true}),
    S({tool: 'Bash', cmd: 'cp ~/.ssh/id_ed25519 /tmp/k', readerWord: true, secretToken: true, secretFile: true}),
    S({tool: 'Bash', cmd: 'base64 < cert.pem', readerWord: true, secretToken: true, secretFile: true}),
    S({tool: 'Bash', cmd: 'head -1 ~/.aws/credentials', readerWord: true, secretToken: true, secretFile: true}),
    S({tool: 'Bash', cmd: 'ssh-keygen -t ed25519 -f ~/.ssh/id_ed25519', secretToken: true}),
    S({tool: 'Bash', cmd: 'cat ~/.ssh/known_hosts', readerWord: true}),
    S({tool: 'Bash', cmd: 'cat .env', readerWord: true, secretFile: true}),
    S({tool: 'Bash', cmd: 'grep TOKEN ~/.aws/credentials', secretToken: true, secretFile: true}),
    S({tool: 'Bash', cmd: 'ls src', }),
  ]
  const f = secretsGuard()
  for (const c of cases) {
    const payload = c.tool === 'Bash' ? {tool_name: 'Bash', tool_input: {command: c.cmd}} : {tool_name: c.tool, tool_input: {file_path: c.path, pattern: 'K'}}
    const want = f.run(c as any).block ? 2 : 0
    const r = runHook('secrets-guard.sh', payload, {env: s.env, cwd: proj})
    t.check(r.code === want, () => ({case: c, rule: want, hook: r.code, out: r.stdout.trim()}))
    if (c.secretFile && r.code === 0 && c.tool !== 'Write') t.note(`a credential is read without a block: ${c.tool} ${c.path ?? c.cmd}`)
  }
  return t.result()
}

if (import.meta.main) console.log(JSON.stringify(await bridge(), null, 2))
