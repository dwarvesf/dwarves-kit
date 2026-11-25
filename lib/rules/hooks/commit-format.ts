// commit-format (hooks/commit-format.sh, PreToolUse Bash) as a gdp-wired decision.
//
//   :20      the command does not mention git ... commit          -> exit 0
//   :25-34   gate-policy says commit_format is off (exit 1 only)  -> exit 0 (the gate is opt-in: off by default)
//   :37-43   no first -m/--message quoted value (editor, -F, --no-edit) -> exit 0
//   :45-49   the subject is the value's first line; a -m "$(cat <<'EOF' ...)" value's subject is the heredoc
//            body's first line (fixed; 'pre-fix' read the "$(cat <<'EOF'" line itself and refused every such commit)
//   :52-54   Merge / fixup! / squash! / Revert subjects pass
//   :67-74   over 72 chars, a SPEC-/TASK-/TICKET-/pN/phase-N marker, or not a Conventional Commit -> exit 2
import {bool, fun, oneOf} from 'gdp-wired'

export const Form = oneOf('none', 'plain', 'heredoc')
export type Variant = 'shipped' | 'pre-fix' | 'no-length-cap' | 'gate-ignored'
export const VARIANTS: Variant[] = ['pre-fix', 'no-length-cap', 'gate-ignored']

export function commitFormat(v: Variant = 'shipped') {
  return fun(v === 'shipped' ? 'commit-format' : `commit-format/${v}`)
    .inputs({isCommit: bool, gateOff: bool, form: Form, toolGen: bool, tooLong: bool, marker: bool, conventional: bool})
    .returns(({isCommit, gateOff, form, toolGen, tooLong, marker, conventional}) => {
      const on = isCommit.and(v === 'gate-ignored' ? isCommit : gateOff.not()).and(form.is('none').not())
      const misread = v === 'pre-fix' ? form.is('heredoc') : form.is('none').and(form.is('heredoc'))
      const bad = (v === 'no-length-cap' ? marker : tooLong.or(marker)).or(conventional.not())
      return {block: on.and(misread.or(toolGen.not().and(bad)))}
    })
}

export function laws(f: ReturnType<typeof commitFormat>) {
  const linted = (e: any) => [e.isCommit, e.gateOff.not(), e.form.is('none').not(), e.toolGen.not()]
  return {
    laws: [], stepLaws: [],
    decisions: [
      f.law('a Conventional subject within 72 chars and no marker is allowed, however the message is passed',
        (e) => [e.conventional, e.tooLong.not(), e.marker.not()], (o) => o.block.not()),
      f.law('a subject over 72 chars is refused while the gate is on', (e) => [...linted(e), e.tooLong], (o) => o.block),
      f.law('a spec, ticket or phase marker in the subject is refused while the gate is on', (e) => [...linted(e), e.marker], (o) => o.block),
      f.law('a non-Conventional subject is refused while the gate is on', (e) => [...linted(e), e.conventional.not()], (o) => o.block),
      f.law('commit_format off never blocks', (e) => [e.gateOff], (o) => o.block.not()),
      f.law('a commit with no -m subject is never blocked', (e) => [e.form.is('none')], (o) => o.block.not()),
      f.law('a merge, fixup, squash or revert subject passes', (e) => [e.toolGen], (o) => o.block.not()),
      f.law('a command that is not a git commit is never blocked', (e) => [e.isCommit.not()], (o) => o.block.not()),
    ],
  }
}
export const make = commitFormat
