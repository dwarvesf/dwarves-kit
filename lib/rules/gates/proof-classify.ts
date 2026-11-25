// The proof gate's diff classifier (lib/gate/proof-ledger.sh:classify, :110), a gdp-wired decision, and the
// override's repo scoping (is_overridden, :278).
//
// classify facts: which kinds of path the branch changed (committed base..HEAD, plus the working tree): md/txt docs,
// .kit.toml, an asset under docs/, a board file (_meta/BACKLOG.md ...), a secret-shaped path (never a doc), a test
// file, a source file, a stateful path (db/migrations/...), a doc whose NAME holds a stateful word (docs/deploy.md);
// whether a commit subject holds a stateful word; whether an uncommitted code file sits in the tree; whether the
// committed paths are all board files. Result: inert | behavioral | stateful (proof-classes.tsv ranks).
import {bool, fun} from 'gdp-wired'

export type Variant = 'shipped' | 'subject-first' | 'board-counts-dirty'
export const VARIANTS: Variant[] = ['subject-first', 'board-counts-dirty']

export function proofClassify(variant: Variant = 'shipped') {
  return fun(variant === 'shipped' ? 'proof-classify' : `proof-classify/${variant}`)
    .inputs({md: bool, kitToml: bool, asset: bool, board: bool, secret: bool, test: bool, src: bool, statePath: bool,
      docWord: bool, subjWord: bool, dirtyCode: bool, committedBoardOnly: bool})
    .returns((e) => {
      const {md, kitToml, asset, board, secret, test, src, statePath, docWord, subjWord, dirtyCode, committedBoardOnly} = e
      const any = md.or(kitToml).or(asset).or(board).or(secret).or(test).or(src).or(statePath).or(docWord).or(dirtyCode)
      const boardOnly = variant === 'board-counts-dirty' ? committedBoardOnly.and(dirtyCode.not()) : committedBoardOnly
      const nondoc = secret.or(test).or(src).or(statePath).or(dirtyCode)
      const nontest = secret.or(src).or(statePath).or(dirtyCode)
      const subj = variant === 'subject-first' ? subjWord : nontest.and(subjWord)
      const inertNow = any.not().or(boardOnly).or(variant === 'subject-first' ? nondoc.not().and(subjWord.not()) : nondoc.not())
      const stateful = inertNow.not().and(statePath.or(docWord).or(subj))
      return {inert: inertNow, stateful, behavioral: inertNow.not().and(stateful.not())}
    })
}

export function laws(f: ReturnType<typeof proofClassify>) {
  return [
    f.law('a diff made only of docs, .kit.toml and docs assets is inert whatever the subject says',
      (e) => [e.secret.not(), e.test.not(), e.src.not(), e.statePath.not(), e.dirtyCode.not()], (o) => o.inert),
    f.law('a push whose committed paths are all board files is inert, whatever sits uncommitted', (e) => [e.committedBoardOnly], (o) => o.inert),
    f.law('a secret-shaped path is never inert unless the commits are board-only', (e) => [e.secret, e.committedBoardOnly.not()], (o) => o.inert.not()),
    f.law('a tests-only diff is classified by its paths: its subject never makes it stateful',
      (e) => [e.test, e.secret.not(), e.src.not(), e.statePath.not(), e.docWord.not(), e.dirtyCode.not(), e.committedBoardOnly.not()], (o) => o.behavioral),
    f.law('a code change whose subject says migrate or deploy is stateful', (e) => [e.src, e.subjWord, e.committedBoardOnly.not()], (o) => o.stateful),
    f.law('a stateful path is stateful', (e) => [e.statePath, e.committedBoardOnly.not()], (o) => o.stateful),
    f.law('exactly one class', () => [], (o) => o.inert.or(o.behavioral).or(o.stateful)
      .and(o.inert.and(o.behavioral).not()).and(o.inert.and(o.stateful).not()).and(o.behavioral.and(o.stateful).not())),
  ]
}

// A reviewer's law the classifier refutes (FINDINGS.md): a doc's file NAME feeds the stateful word scan.
export function refutedLaws(f: ReturnType<typeof proofClassify>) {
  return [f.law('a doc file\'s name never changes the class of a code change',
    (e) => [e.src, e.docWord, e.statePath.not(), e.subjWord.not(), e.secret.not(), e.committedBoardOnly.not()], (o) => o.behavioral)]
}

// is_overridden: the override log keys each entry by repo (the git common dir's parent) and slug, by field.
export function overrideScope() {
  return fun('proof-override-scope')
    .inputs({sameRepo: bool, sameSlug: bool, legacy: bool, forgedReason: bool})
    .returns(({sameRepo, sameSlug, legacy}) => ({overridden: sameRepo.and(sameSlug).and(legacy.not())}))
}
export function scopeLaws(f: ReturnType<typeof overrideScope>) {
  return [
    f.law('an override logged in one repo never clears the same slug in another repo', (e) => [e.sameRepo.not()], (o) => o.overridden.not()),
    f.law('a legacy override line with no repo field matches nothing (fail closed)', (e) => [e.legacy], (o) => o.overridden.not()),
    f.law('a reason that quotes another repo and slug forges nothing', (e) => [e.forgedReason, e.sameRepo.not()], (o) => o.overridden.not()),
    f.law('an override logged from any worktree of the repo clears its slug', (e) => [e.sameRepo, e.sameSlug, e.legacy.not()], (o) => o.overridden),
  ]
}
