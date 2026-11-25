// safety-gate (hooks/safety-gate.sh, PreToolUse Bash) as a gdp-wired decision.
//
// The hook splits a command into segments (the awk walk plus the naive pass, safety-gate.sh:68-180), finds each
// segment's real binary past wrappers, env assignments and redirections (:205-251), and then decides per binary
// (:253-343). A command is refused (exit 2) when ANY segment is refused; otherwise it exits 0. This rule is that per
// segment decision over the facts the hook reads from a segment's argv. Parsing a command into those facts is the
// part a prover cannot see; safety-gate.bridge.ts holds the real hook to this rule over a corpus of command strings
// labelled with the facts they really carry, so a parse that loses a fact shows up there as a divergence.
//
// The hook reads no config at all: no env knob, no [gate] key, no autonomy position (and anchor-root.sh never skips
// it, see anchor-root.ts). The rule takes those as inputs anyway, so the law "the decision never depends on them" is
// a claim the prover checks, and the bridge varies them against the real hook.
import {bool, fun, oneOf} from 'gdp-wired'
import {iff} from './_kit.ts'

export const Bin = oneOf('rm', 'find', 'git', 'kubectl', 'sql', 'other')
// find's delete verbs: -delete, -exec rm, or -exec naming rm by a path (/opt/homebrew/bin/rm).
export const FindDel = oneOf('none', 'delete', 'execRm', 'execPathRm')
export const GitSub = oneOf('push', 'reset', 'other')
// How a push overwrites: --force / -f (cluster), a +refspec, or only --force-with-lease / --force-if-includes.
export const Force = oneOf('none', 'force', 'plus', 'lease')
// A push that can carry every branch: --mirror, --all, a glob or brace refspec, --branches (git 2.46's --all), or an
// abbreviation git accepts for one of them (--mirr, --al, --br).
export const Spread = oneOf('none', 'mirror', 'all', 'glob', 'branches', 'abbrev')
// A refspec that lands on main or master: named plainly (main, HEAD:main, refs/heads/master), or with a tag as its
// source (refs/tags/v1:refs/heads/main), which the hook's tag allowance used to swallow.
export const MainRef = oneOf('none', 'named', 'behindTag')
// git reset --hard, or an abbreviation git accepts (--ha, --har).
export const Hard = oneOf('none', 'exact', 'abbrev')
// kubectl delete, plainly or after a global flag that takes a separate value (kubectl -v 6 delete ...).
export const KDelete = oneOf('none', 'plain', 'afterValueFlag')
export const Autonomy = oneOf('propose', 'low', 'high', 'max')

export type Variant = 'shipped' | 'pre-fix' | 'lease-is-force' | 'no-allowlist' | 'reads-autonomy'
export const VARIANTS: Variant[] = ['pre-fix', 'lease-is-force', 'no-allowlist', 'reads-autonomy']

export function safetyGate(variant: Variant = 'shipped') {
  const old = variant === 'pre-fix'
  return fun(variant === 'shipped' ? 'safety-gate' : `safety-gate/${variant}`)
    .inputs({
      bin: Bin,
      rmR: bool, rmF: bool, rmSafe: bool,             // rm: -r/-R/--recursive, -f/--force, every operand allowlisted
      findDel: FindDel, findSafe: bool,               // find: a delete verb, every path operand allowlisted
      gitSub: GitSub, force: Force, spread: Spread, mainRef: MainRef, hard: Hard,
      kdelete: KDelete,
      dropTable: bool,                                // psql/mysql/sqlite3 and DROP TABLE anywhere in the command
      autonomy: Autonomy, debug: bool, gatesOff: bool, // config the hook must not read
    })
    .returns(({bin, rmR, rmF, rmSafe, findDel, findSafe, gitSub, force, spread, mainRef, hard, kdelete, dropTable, autonomy}) => {
      // rm (:254-270): -r and -f together, and some operand outside the build-artifact allowlist (:185-203).
      const rmRf = bin.is('rm').and(rmR).and(rmF).and(variant === 'no-allowlist' ? rmR.or(rmR.not()) : rmSafe.not())
      // find (:271-293): -delete or -exec/-execdir/-ok/-okdir with rm, outside the allowlist.
      const findVerb = old ? findDel.is('delete').or(findDel.is('execRm')) : findDel.is('none').not()
      const findDelete = bin.is('find').and(findVerb).and(findSafe.not())
      const push = bin.is('git').and(gitSub.is('push'))
      // git push (:306-318): a force without the lease, a spread, a main ref.
      const forced = force.is('force').or(force.is('plus')).or(variant === 'lease-is-force' ? force.is('lease') : force.is('force').and(force.is('plus')))
      const spreads = old ? spread.is('mirror').or(spread.is('all')).or(spread.is('glob')) : spread.is('none').not()
      const mains = old ? mainRef.is('named') : mainRef.is('none').not()
      const pushBlocks = push.and(forced.or(spreads).or(mains))
      // git reset --hard (:319-323).
      const hardReset = bin.is('git').and(gitSub.is('reset')).and(old ? hard.is('exact') : hard.is('none').not())
      // kubectl delete (:326-338).
      const kube = bin.is('kubectl').and(old ? kdelete.is('plain') : kdelete.is('none').not())
      // DROP TABLE through a SQL client (:339-342).
      const drop = bin.is('sql').and(dropTable)
      const any = rmRf.or(findDelete).or(pushBlocks).or(hardReset).or(kube).or(drop)
      const waived = variant === 'reads-autonomy' ? autonomy.is('max') : autonomy.is('max').and(autonomy.is('max').not())
      return {block: any.and(waived.not())}
    })
}

export function laws(f: ReturnType<typeof safetyGate>) {
  return {
    laws: [], stepLaws: [],
    decisions: [
      f.law('a recursive forced rm of anything but build artefacts is refused',
        ({bin, rmR, rmF, rmSafe}) => [bin.is('rm'), rmR, rmF, rmSafe.not()], (o) => o.block),
      f.law('a recursive forced rm of build artefacts only is allowed',
        ({bin, rmSafe}) => [bin.is('rm'), rmSafe], (o) => o.block.not()),
      f.law('find with a delete verb outside build artefacts is refused',
        ({bin, findDel, findSafe}) => [bin.is('find'), findDel.is('none').not(), findSafe.not()], (o) => o.block),
      f.law('a force push without the lease is refused',
        ({bin, gitSub, force}) => [bin.is('git'), gitSub.is('push'), force.is('force').or(force.is('plus'))], (o) => o.block),
      f.law('a push that can carry every branch is refused',
        ({bin, gitSub, spread}) => [bin.is('git'), gitSub.is('push'), spread.is('none').not()], (o) => o.block),
      f.law('a push naming main or master as a destination is refused',
        ({bin, gitSub, mainRef}) => [bin.is('git'), gitSub.is('push'), mainRef.is('none').not()], (o) => o.block),
      f.law('a force-with-lease push of one feature branch is allowed',
        ({bin, gitSub, force, spread, mainRef}) => [bin.is('git'), gitSub.is('push'), force.is('lease').or(force.is('none')), spread.is('none'), mainRef.is('none')],
        (o) => o.block.not()),
      f.law('git reset --hard is refused', ({bin, gitSub, hard}) => [bin.is('git'), gitSub.is('reset'), hard.is('none').not()], (o) => o.block),
      f.law('kubectl delete is refused', ({bin, kdelete}) => [bin.is('kubectl'), kdelete.is('none').not()], (o) => o.block),
      f.law('DROP TABLE through a SQL client is refused', ({bin, dropTable}) => [bin.is('sql'), dropTable], (o) => o.block),
      f.law('a segment that runs none of these is allowed', ({bin}) => [bin.is('other')], (o) => o.block.not()),
      f.relate('the decision never depends on config or the autonomy position',
        (a, b) => [a.bin.eq(b.bin), iff(a.rmR, b.rmR), iff(a.rmF, b.rmF), iff(a.rmSafe, b.rmSafe), a.findDel.eq(b.findDel),
          iff(a.findSafe, b.findSafe), a.gitSub.eq(b.gitSub), a.force.eq(b.force), a.spread.eq(b.spread), a.mainRef.eq(b.mainRef),
          a.hard.eq(b.hard), a.kdelete.eq(b.kdelete), iff(a.dropTable, b.dropTable)],
        (x, y) => iff(x.block, y.block)),
    ],
  }
}
export const make = safetyGate
