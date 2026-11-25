// Bridge: hold hooks/money-gate.sh to the money-gate rule: payloads with and without money terms, inside and outside a
// named repo, under each MONEY_GATE_STRICT spelling; the log file and the "ask" JSON are read back.
import {existsSync, readFileSync} from 'node:fs'
import {moneyGate} from './money-gate.ts'
import {rng, runHook, sandbox, Tally, join, type BridgeResult} from './_bridge.ts'

const STRICT: [string | undefined, boolean][] = [[undefined, false], ['', false], ['1', true], [' TRUE ', true], ['yes', true], ['On', true], ['0', false], ['off', false], ['maybe', false]]
const CONTENT: [string, boolean][] = [['const amount = 5', true], ['payroll_rows.push(x)', true], ['let x = 1', false], ['API_KEY=abc', true],
  ['render(<Button/>)', false], ['the ledgers', true], ['net-worth calc', true], ['amountOfThings', false]]

export async function bridge(): Promise<BridgeResult> {
  const t = new Tally()
  const f = moneyGate()
  const g = rng(11)
  for (let i = 0; i < 120; i++) {
    const s = sandbox()
    const repos = g.pick([undefined, '', 'books', 'books:family-office'])
    const [strictV, strict] = g.pick(STRICT)
    const where = g.pick(['/w/books/src/a.ts', '/w/family-office/x.py', '/w/other/books.ts', '/w/books'])
    const [content, hits] = g.pick(CONTENT)
    const tool = g.pick(['Edit', 'Write', 'MultiEdit'])
    const ti = tool === 'Edit' ? {file_path: where, old_string: content, new_string: 'y'} : tool === 'Write' ? {file_path: where, content}
      : {file_path: where, edits: [{old_string: 'a', new_string: content}]}
    const cwd = g.pick(['/tmp/nowhere', '/w/books', '/w/family-office/sub', '/w/bookshelf'])
    const payload = {tool_name: tool, tool_input: ti, cwd}
    const named = (repos ?? '').split(':').filter(Boolean)
    // The hook matches /<name>/ anywhere in "path\ncwd", or /<name> at the very end (the cwd's end).
    const inRepo = named.some((r) => where.includes(`/${r}/`) || cwd.includes(`/${r}/`) || cwd.endsWith(`/${r}`))
    const log = join(s.home, 'mg.log')
    const env: Record<string, string> = {...s.env, MONEY_GATE_LOG: log}
    if (repos !== undefined) env.MONEY_GATE_REPOS = repos
    if (strictV !== undefined) env.MONEY_GATE_STRICT = strictV
    const out = f.run({repos: !!repos, payloadOk: true, inRepo, hits, strict})
    const r = runHook('money-gate.sh', payload, {env})
    const asked = r.stdout.includes('"permissionDecision": "ask"')
    const logged = existsSync(log) && readFileSync(log, 'utf8').length > 0
    t.check(r.code === 0 && asked === out.ask && logged === out.log, () => ({case: i, payload, repos, strictV, rule: out, hook: {code: r.code, asked, logged}}))
  }
  // A payload that is not one JSON object is inert.
  const s = sandbox()
  const r = runHook('money-gate.sh', '{"tool_input":{"file_path":"/w/books/a.ts","content":"amount"}} {}', {env: {...s.env, MONEY_GATE_REPOS: 'books', MONEY_GATE_STRICT: '1'}})
  t.check(r.code === 0 && r.stdout === '' && !f.run({repos: true, payloadOk: false, inRepo: true, hits: true, strict: true}).ask, () => ({case: 'two JSON values', hook: r}))
  return t.result()
}

if (import.meta.main) console.log(JSON.stringify(await bridge(), null, 2))
