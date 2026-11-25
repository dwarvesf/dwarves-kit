// The fixture-identity rule of the ship-gate (lib/gate/ship-rules.sh:ship_rule_identities and _sr_fixture_email).
//
// _sr_fixture_email is a classifier over an email's shape; ship_rule_identities folds it over every new commit
// (base..head): author, committer and every Co-authored-by trailer. The rule's state is `bad`, "some new commit
// carries a fixture identity"; the decision at the end blocks (return 2) when the check runs and `bad` holds.
import {bool, fun, oneOf, rule} from 'gdp-wired'

// Shapes, in the order _sr_fixture_email tests them (lowercased first):
//   empty        ""                                   not a fixture (return 1)
//   noAt         "jane"                               fixture
//   bareHost     "x@x", "user@Host"                  fixture
//   tdev         "t@t.dev"                            fixture;   testExample "test@example.com"  fixture
//   exampleDom   "a@example.org"                      fixture;   reservedTld "a@b.test", ".invalid", ".localhost", ".local", ".example"
//   real         "jane@dwarves.foundation"            not;       noreply "1+jane@users.noreply.github.com"  not
export const SHAPES = ['empty', 'noAt', 'bareHost', 'tdev', 'testExample', 'exampleDom', 'reservedTld', 'real', 'noreply'] as const
export const Shape = oneOf(...SHAPES)

export type EmailVariant = 'shipped' | 'local-allowed'
// The one classification both the email decision and the commit fold use.
export const isFixture = (e: any, variant: EmailVariant = 'shipped') =>
  e.is('noAt').or(e.is('bareHost')).or(e.is('tdev')).or(e.is('testExample')).or(e.is('exampleDom'))
    .or(variant === 'local-allowed' ? e.is('noAt').and(e.is('bareHost')) : e.is('reservedTld'))
export function fixtureEmail(variant: EmailVariant = 'shipped') {
  return fun(variant === 'shipped' ? 'fixture-email' : `fixture-email/${variant}`).inputs({e: Shape})
    .returns(({e}) => ({fixture: isFixture(e, variant)}))
}

export function emailLaws(f: ReturnType<typeof fixtureEmail>) {
  return [
    f.law('a GitHub noreply address is never a fixture', (x) => [x.e.is('noreply')], (o) => o.fixture.not()),
    f.law('a real address is never a fixture', (x) => [x.e.is('real')], (o) => o.fixture.not()),
    f.law('a bare-hostname address (x@x, user@Host) is a fixture', (x) => [x.e.is('bareHost')], (o) => o.fixture),
    f.law('a reserved test domain (.test, .invalid, .localhost, .local, example.*) is a fixture',
      (x) => [x.e.is('reservedTld').or(x.e.is('exampleDom'))], (o) => o.fixture),
    f.law('an empty email is not a fixture', (x) => [x.e.is('empty')], (o) => o.fixture.not()),
  ]
}

// The fold over new commits. Params: origin (an origin remote exists), on ([gate] fixture_identities at the
// merge base), ranged (a base and a head, and they differ).
export type FoldVariant = 'shipped' | 'author-only'
export function identities(variant: FoldVariant = 'shipped') {
  const fx = (s: any) => isFixture(s)
  return rule(variant === 'shipped' ? 'fixture-identities' : `fixture-identities/${variant}`)
    .params({origin: bool, on: bool, ranged: bool})
    .inputs({author: Shape, committer: Shape, coauthor: Shape})
    .state({bad: bool.from(false), n: 0})
    .step(({author, committer, coauthor, bad, n}) => ({
      bad: bad.or(fx(author)).or(variant === 'author-only' ? fx(author) : fx(committer).or(fx(coauthor))),
      n: n.plus(1),
    }))
}
// The decision at the end of the fold: block (return 2) only with an origin, the switch on and a real range.
export const blockDecision = fun('fixture-identities-block').inputs({origin: bool, on: bool, ranged: bool, bad: bool})
  .returns(({origin, on, ranged, bad}) => ({block: origin.and(on).and(ranged).and(bad)}))
export const blockLaws = [
  blockDecision.law('a push whose new commits carry a fixture identity is refused while the check is on',
    (e) => [e.origin, e.on, e.ranged, e.bad], (o) => o.block),
  blockDecision.law('a repo with no origin is never refused for identities', (e) => [e.origin.not()], (o) => o.block.not()),
  blockDecision.law('fixture_identities = false at the merge base switches the check off', (e) => [e.on.not()], (o) => o.block.not()),
]

export function foldLaws(r: ReturnType<typeof identities>) {
  return {
    laws: [],
    stepLaws: [
      r.stepLaw('a commit with a fixture author, committer or Co-authored-by marks the push', (b, a) => a.bad,
        (b) => b.committer.is('bareHost').or(b.author.is('reservedTld')).or(b.coauthor.is('tdev'))),
      r.stepLaw('a marked push stays marked whatever later commits carry', (b, a) => a.bad, (b) => b.bad),
      r.stepLaw('clean identities never mark a push', (b, a) => a.bad.implies(b.bad),
        (b) => b.author.is('real').and(b.committer.is('noreply')).and(b.coauthor.is('empty'))),
    ],
  }
}
