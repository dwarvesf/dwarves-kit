// What `[merge] command` resolves to (lib/config/merge-command.sh: kit_merge_command 161-185, _kit_mc_resolve
// 129-140, _kit_mc_finish 153-159, _kit_mc_emit 142-151, _kit_mc_shape 98-127).
//
// Each config file is reduced to one class:
//   none      absent or empty (`[ -s ]` false): skipped
//   nokey     a file with no [merge] command (or `command = ""`, read as empty): continue to the next layer
//   value     a plain double-quoted one-command value: this layer wins, exit 0
//   meta      a value with ; & | < > backtick $( : this layer wins, then the emit refuses, exit 2
//   bad       a form the shape check refuses (dotted key, inline table, [[merge]], single/triple quotes, repeated
//             key, `#` in the value): exit 2 the moment the walk reaches it
//   quoted    a quoted table name, `["merge"]` or `['merge']`, legal TOML for [merge] with a command under it.
//             Before the fix the shape check unquoted the header and passed it, while the reader (_kit_toml_get)
//             kept the quotes, matched no section, and answered empty: the walk went on as if no command were set,
//             and with no other layer the kit ran the plain squash. Kept as variant 'quoted-header-unset'.
// Walk (base resolvable): committed project file, operator, kit-root. Base not resolvable: operator, kit-root, and
// then a working-tree project file that names a command (or fails the shape check) refuses (2), else unset (1).
//
// Exit codes 0 set / 1 unset / 2 refuse; src 0 none, 1 kit-root, 2 operator, 3 project.
import {bool, fun, oneOf, when} from 'gdp-wired'

export const CLASSES = ['none', 'nokey', 'value', 'meta', 'bad', 'quoted'] as const
const Cls = oneOf(...CLASSES)

export type Variant = 'shipped' | 'quoted-header-unset' | 'bad-skipped' | 'working-tree-read' | 'nonexistent-path'
export const VARIANTS: Variant[] = ['quoted-header-unset', 'bad-skipped', 'working-tree-read', 'nonexistent-path']

export function mergeCommand(variant: Variant = 'shipped') {
  return fun(variant === 'shipped' ? 'merge-command' : `merge-command/${variant}`)
    // hostDir: the host has a directory at /nonexistent (Debian-style `nobody` home). Before the fix the no-base walk
    // started at the literal path /nonexistent, `[ -s ]` is true for a directory, and the shape check failed on it.
    .inputs({baseOk: bool, proj: Cls, work: Cls, op: Cls, root: Cls, hostDir: bool})
    .returns(({baseOk, proj, work, op, root, hostDir}) => {
      const refuses = (c: typeof proj) => variant === 'bad-skipped' ? c.is('quoted')
        : variant === 'quoted-header-unset' ? c.is('bad') : c.is('bad').or(c.is('quoted'))
      const sets = (c: typeof proj) => c.is('value').or(c.is('meta'))
      // The project layer the walk reads: the committed copy when the base resolves (the working tree with the
      // 'working-tree-read' bug).
      const p = variant === 'working-tree-read' ? work : proj
      const pAt = baseOk
      // Walk: first layer that refuses or sets ends it. The 'nonexistent-path' bug: with no base, a directory at
      // /nonexistent stands in the project slot and refuses.
      const phantom = variant === 'nonexistent-path' ? baseOk.not().and(hostDir) : baseOk.and(baseOk.not())
      const pEnds = pAt.and(refuses(p).or(sets(p))).or(phantom)
      const oEnds = op.is('none').not().and(refuses(op).or(sets(op)))
      const rEnds = root.is('none').not().and(refuses(root).or(sets(root)))
      const at = when(pEnds, 3, when(oEnds, 2, when(rEnds, 1, 0)))
      const cls = (c: typeof proj) => when(refuses(c), 2, when(c.is('meta'), 2, 0))
      const walked = when(phantom, 2, when(at.eq(3), cls(p), when(at.eq(2), cls(op), when(at.eq(1), cls(root), 1))))
      // No base: a working-tree file that names a command, or fails the shape check, refuses.
      const workNames = sets(work).or(work.is('bad')).or(variant === 'quoted-header-unset' ? work.is('bad') : work.is('quoted'))
      const rc = when(baseOk.not().and(walked.eq(1)).and(workNames), 2, walked)
      return {rc, src: when(rc.eq(0), at, 0)}
    })
}

export function laws(f: ReturnType<typeof mergeCommand>) {
  return {
    laws: [], stepLaws: [],
    decisions: [
      f.law('a committed project command wins over the operator and kit-root files',
        ({baseOk, proj}) => [baseOk, proj.is('value')], (o) => o.rc.eq(0).and(o.src.eq(3))),
      f.law('the operator file wins over the kit root',
        ({baseOk, proj, op}) => [baseOk, proj.is('none').or(proj.is('nokey')), op.is('value')], (o) => o.src.eq(2)),
      f.law('a value that is not one simple command refuses, never runs', ({baseOk, proj}) => [baseOk, proj.is('meta')], (o) => o.rc.eq(2)),
      f.law('a form the reader cannot read refuses the merge, never reads as unset',
        ({baseOk, proj}) => [baseOk, proj.is('bad')], (o) => o.rc.eq(2)),
      // The doc: "a key it cannot read ... make[s] the kit refuse to merge; it never reads them as 'not set'".
      f.law('a project file that names [merge] with a command is never read as unset',
        ({baseOk, proj}) => [baseOk, proj.is('quoted')], (o) => o.rc.eq(1).not()),
      f.law('with no default-branch commit, a working-tree command refuses rather than reading as unset',
        ({baseOk, work, op, root}) => [baseOk.not(), work.is('value'), op.is('none'), root.is('none')], (o) => o.rc.eq(2)),
      f.law('with no default-branch commit and no command anywhere, the answer is unset (exit 1), on any host',
        ({baseOk, work, op, root}) => [baseOk.not(), work.is('none').or(work.is('nokey')), op.is('none').or(op.is('nokey')), root.is('none').or(root.is('nokey'))],
        (o) => o.rc.eq(1)),
      f.law('the plain merge (unset) only when no layer names a command',
        () => [], (o, {baseOk, proj, op, root}) => o.rc.eq(1).implies(
          baseOk.implies(proj.is('value').not().and(proj.is('meta').not()))
            .and(op.is('value').not()).and(op.is('meta').not()).and(root.is('value').not()).and(root.is('meta').not()))),
      f.relate('with the default branch readable, the working tree never changes the answer',
        (a, b) => [a.baseOk, b.baseOk, a.proj.eq(b.proj), a.op.eq(b.op), a.root.eq(b.root)],
        (x, y) => x.rc.eq(y.rc).and(x.src.eq(y.src))),
    ],
  }
}
