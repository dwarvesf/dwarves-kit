// Bridge: hold hooks/spec-drift-guard.sh to the spec-drift-guard rule in temp repos with open and shipped specs.
import {specDriftGuard} from './spec-drift-guard.ts'
import {gitRepo, rng, runHook, sandbox, Tally, type BridgeResult} from './_bridge.ts'

const PATHS: {p: string, skipped: boolean}[] = [
  {p: 'src/parser.ts', skipped: false}, {p: 'src/lexer.ts', skipped: false}, {p: 'lib/new/thing.go', skipped: false},
  {p: 'tools/x.py', skipped: false}, {p: 'main.rs', skipped: false}, {p: 'README.md', skipped: true},
  {p: 'config/app.yaml', skipped: true}, {p: 'node_modules/x/index.js', skipped: true}, {p: 'dist/out.js', skipped: true},
  {p: '.claude/notes.ts', skipped: true}, {p: 'package.json', skipped: true}, {p: 'shipped/old.ts', skipped: false},
]

export async function bridge(): Promise<BridgeResult> {
  const t = new Tally()
  const f = specDriftGuard()
  const g = rng(5)
  for (let i = 0; i < 24; i++) {
    const open = g.int(3)
    const files: Record<string, string> = {}
    const named = new Set<string>()
    for (let k = 0; k < open; k++) {
      const mention = g.pick(['src/parser.ts', 'lexer.ts', 'lib/new', 'nothing'])
      named.add(mention)
      files[`docs/specs/SPEC-00${k + 1}-s${k}.md`] = `# SPEC\nStatus: ${g.pick(['DRAFT', 'VALIDATED', 'APPROVED'])}\n\nTouches ${mention}.\n`
    }
    files['docs/specs/SPEC-090-old.md'] = '# old\nStatus: SHIPPED\n\nTouches shipped/old.ts and src/lexer.ts.\n'
    const dir = gitRepo(files)
    const env = sandbox().env
    for (const {p, skipped} of PATHS) {
      const base = p.split('/').pop()!, dirn = p.includes('/') ? p.slice(0, p.lastIndexOf('/')) : '.'
      const mentioned = [...named].some((m) => m.includes(p) || m.includes(base) || (dirn !== '.' && m.includes(dirn)))
      const out = f.run({hasPath: true, skipped, specs: open > 0, mentioned})
      const r = runHook('spec-drift-guard.sh', {tool_name: 'Write', tool_input: {file_path: p, content: 'x'}}, {env, cwd: dir})
      const warned = r.stdout.includes('is not in any active spec')
      t.check(r.code === 0 && warned === out.warn, () => ({case: i, path: p, open, named: [...named], rule: out, hook: {code: r.code, warned}}))
    }
  }
  return t.result()
}

if (import.meta.main) console.log(JSON.stringify(await bridge(), null, 2))
