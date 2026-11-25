// The push gate's decision chain (hooks/ship-gate.sh), as a gdp-wired decision over what each rule it calls decided,
// plus the full-lane implementation-notes rule's ledger fold, which lives in the hook itself.
//
// The chain, in the hook's order (each fact is one sub-rule's verdict; the sub-rules with their own bridges are
// review-verdict, fixture-identities, proof-check, lane-effective, lane-gate-check):
//   no repo / no branch                                  -> allow (fail open)
//   ship-rules.sh fails to load: a kit lib exists        -> BLOCK; no kit lib at all -> allow
//   a heredoc or here-string fed to a shell holds a push -> BLOCK when _fc_applies (adopted + lane_gates at the
//                                                           default branch), else allow (exit 0, nothing else runs)
//   push-refs.sh: @@DEFAULT-PUSH                         -> BLOCK unless KIT_ALLOW_DEFAULT_PUSH=1 in the hook env
//                 @@FORCE / @@DEFAULT (gh head)          -> allow (force pushes are safety-gate's business)
//                 @@BLOCK, no answer, several branches   -> BLOCK when _fc_applies, else go on with the current branch
//   fixture identity (ship_rule_identities)              -> BLOCK
//   proof of done (proof-ledger.sh check)                -> BLOCK
//   kit-repo projections (doc projection, registry, pin) -> BLOCK
//   no spec                                              -> the hard-path floor decides
//   review verdict (ship_rule_review_verdict)            -> BLOCK
//   no lane: adopted repo with lane_gates on             -> BLOCK, else the floor decides
//   lane_gates off at the merge base                     -> the floor decides
//   missing required gate or MISSING-NOTES               -> BLOCK
//   a large normal-lane spec with no validate            -> BLOCK
//   the hard-path floor (ship_rule_floor)                -> BLOCK, else allow
import {bool, fun, oneOf, rule} from 'gdp-wired'

export const REFS = ['one', 'many', 'block', 'empty', 'defaultPush', 'force'] as const
export const Refs = oneOf(...REFS)
export const RULES_LOAD = ['ok', 'brokenWithLib', 'brokenNoLib'] as const
export const RulesLoad = oneOf(...RULES_LOAD)

export type Variant = 'shipped' | 'default-needs-adoption' | 'review-after-lane' | 'floor-only-with-spec'
export const VARIANTS: Variant[] = ['default-needs-adoption', 'review-after-lane', 'floor-only-with-spec']

export function shipGate(variant: Variant = 'shipped') {
  return fun(variant === 'shipped' ? 'ship-gate' : `ship-gate/${variant}`)
    .inputs({inRepo: bool, rules: RulesLoad, shellHd: bool, refs: Refs, allowEnv: bool, fc: bool, fixture: bool,
      proofBlocks: bool, kitBlock: bool, spec: bool, review: bool, laneEmpty: bool, adopted: bool, laneOn: bool,
      gapOrNotes: bool, largeSpec: bool, floorBlocks: bool})
    .returns((e) => {
      const {inRepo, rules, shellHd, refs, allowEnv, fc, fixture, proofBlocks, kitBlock, spec, review, laneEmpty, adopted,
        laneOn, gapOrNotes, largeSpec, floorBlocks} = e
      // the chain from the spec on, once every earlier rule passed
      const floor = variant === 'floor-only-with-spec' ? spec.and(floorBlocks) : floorBlocks
      const reviewNow = variant === 'review-after-lane' ? spec.and(review).and(laneEmpty.not()).and(laneOn) : spec.and(review)
      const laneChain = laneEmpty.and(adopted).and(laneOn)
        .or(laneEmpty.not().and(laneOn).and(gapOrNotes.or(largeSpec)))
      const afterRefs = fixture.or(proofBlocks).or(kitBlock).or(reviewNow).or(spec.and(laneChain)).or(floor)
      const defaultBlocks = variant === 'default-needs-adoption' ? allowEnv.not().and(fc) : allowEnv.not()
      const refsBlock = refs.is('block').or(refs.is('empty')).or(refs.is('many')).and(fc)
      const refsAllow = refs.is('force').or(refs.is('defaultPush').and(defaultBlocks.not()))
      const block = inRepo.and(
        rules.is('brokenWithLib').or(rules.is('ok').and(
          shellHd.and(fc).or(shellHd.not().and(
            refs.is('defaultPush').and(defaultBlocks).or(refsBlock).or(refsAllow.not().and(afterRefs)))))))
      return {block}
    })
}

// The chain reaches the rules after push-refs: a repo, the helper loaded, no shell heredoc, and neither an allowed
// default push nor a force push.
const reaches = (e: any) => [e.inRepo, e.rules.is('ok'), e.shellHd.not(), e.refs.is('force').not(), e.refs.is('defaultPush').not()]

export function laws(f: ReturnType<typeof shipGate>) {
  return [
    f.law('a push that lands on a default branch is refused in every repo unless the hook env allows it',
      (e) => [e.inRepo, e.rules.is('ok'), e.shellHd.not(), e.refs.is('defaultPush'), e.allowEnv.not()], (o) => o.block),
    f.law('a push the parser cannot account for is refused in an adopted repo with lane gates on',
      (e) => [e.inRepo, e.rules.is('ok'), e.fc, e.shellHd.or(e.refs.is('block')).or(e.refs.is('empty')).or(e.refs.is('many'))], (o) => o.block),
    f.law('a ship-rules helper that fails to load never opens the gate while a kit lib exists',
      (e) => [e.inRepo, e.rules.is('brokenWithLib')], (o) => o.block),
    f.law('a fixture git identity refuses the push', (e) => [...reaches(e), e.fixture], (o) => o.block),
    f.law('a DO NOT SHIP or mismatched review verdict refuses the push whatever the lane or lane_gates say',
      (e) => [...reaches(e), e.spec, e.review], (o) => o.block),
    f.law('a spec with no Lane header is refused in an adopted repo with lane gates on',
      (e) => [...reaches(e), e.spec, e.laneEmpty, e.adopted, e.laneOn], (o) => o.block),
    f.law('a missing required gate or implementation-notes file refuses the push while lane gates are on',
      (e) => [...reaches(e), e.spec, e.laneEmpty.not(), e.laneOn, e.gapOrNotes], (o) => o.block),
    f.law('the hard-path floor applies with or without a spec, whatever lane it names',
      (e) => [...reaches(e), e.floorBlocks], (o) => o.block),
    f.law('outside a git repo the gate never blocks', (e) => [e.inRepo.not()], (o) => o.block.not()),
  ]
}

// A reviewer's law the shipped chain refutes (FINDINGS.md): two documented fail-open exits skip the floor.
export function refutedLaws(f: ReturnType<typeof shipGate>) {
  return [
    f.law('every push the hook lets through has passed the hard-path floor (bar a human-allowed default push)',
      (e) => [e.inRepo, e.rules.is('ok'), e.floorBlocks, e.refs.is('defaultPush').not(), e.refs.is('force').not()], (o) => o.block),
  ]
}

// ---- the implementation-notes override, read from the run ledger (hooks/ship-gate.sh, the full-lane notes rule) ---
// Rows: override = `GATE | impl-notes | override`, other = another impl-notes GATE row (ran, skipped, rejected),
// forged = an additive line (ACTION, DEBT, ...) whose text holds "| GATE | impl-notes | override |", noise = any
// other line. `cleared`: the notes rule is waived. Before the fix the hook grepped the whole ledger for that
// substring, so a forged line cleared it (variant `substring-grep`).
export const ROWS = ['override', 'other', 'forged', 'noise'] as const
export const Row = oneOf(...ROWS)
export type NotesVariant = 'shipped' | 'substring-grep'
export const NOTES_VARIANTS: NotesVariant[] = ['substring-grep']

export function implNotes(variant: NotesVariant = 'shipped') {
  return rule(variant === 'shipped' ? 'impl-notes' : `impl-notes/${variant}`)
    .inputs({row: Row})
    .state({cleared: bool.from(false)})
    .step(({row, cleared}) => ({
      cleared: cleared.or(row.is('override')).or(variant === 'substring-grep' ? row.is('forged') : row.is('forged').and(row.is('override'))),
    }))
}

export function notesLaws(r: ReturnType<typeof implNotes>) {
  return {
    laws: [],
    stepLaws: [
      r.stepLaw('only a GATE impl-notes override row clears the notes rule; an additive line never does',
        (b, a) => a.cleared.implies(b.cleared.or(b.row.is('override')))),
      r.stepLaw('a logged impl-notes override clears the notes rule', (b, a) => a.cleared, (b) => b.row.is('override')),
    ],
  }
}

// A reviewer's law the shipped fold refutes: check() reads a phase's LATEST row, the notes rule reads any row.
export function notesRefuted(r: ReturnType<typeof implNotes>) {
  return {laws: [], stepLaws: [
    r.stepLaw('a later impl-notes row in another state undoes the override, as check() reads the latest row',
      (b, a) => a.cleared.not(), (b) => b.row.is('other')),
  ]}
}
