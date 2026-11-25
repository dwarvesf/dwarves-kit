// permission-auto-approve (hooks/permission-auto-approve.sh, PermissionRequest) as a gdp-wired decision.
//
//   :74-78   Read Glob Grep WebSearch WebFetch                     -> allow
//   :80-83   not Bash, or an empty command                          -> no decision (the normal prompt)
//   :87-92   a NUL byte in the decoded command                      -> no decision
//   :96-101  a newline                                              -> no decision
//   :105-109 a character outside [A-Za-z0-9 ./_=:,@%+*~-]           -> no decision
//   :113-118 no words                                               -> no decision
//   :132-139 first word git and not inside a work tree              -> no decision (before any git approval)
//   :142-159 ls cat head tail wc echo which type stat du df grep; git status|ls-files; exactly `pwd` -> allow
//   :162-169 anything but find, git, file                           -> no decision
//   :250-296 find/file: no `*` in a word and every flag in its safe set -> allow; git log|diff|show likewise;
//            git branch|tag: every word in the safe set; git remote [-v|--verbose|show] -> allow; else no decision
// It never emits a deny.
import {bool, fun, oneOf} from 'gdp-wired'

export const Tool = oneOf('Read', 'Glob', 'Grep', 'WebSearch', 'WebFetch', 'Bash', 'Other')
export const First = oneOf('fast', 'pwd', 'git', 'find', 'file', 'other')
export const Sub = oneOf('statusLs', 'logDiffShow', 'branchTag', 'remote', 'other')
export type Variant = 'shipped' | 'git-before-worktree' | 'denies-unknown' | 'flags-unchecked'
export const VARIANTS: Variant[] = ['git-before-worktree', 'denies-unknown', 'flags-unchecked']

export function permissionAutoApprove(v: Variant = 'shipped') {
  return fun(v === 'shipped' ? 'permission-auto-approve' : `permission-auto-approve/${v}`)
    .inputs({
      tool: Tool, empty: bool, nul: bool, newline: bool, safeChars: bool, words: bool,
      first: First, worktree: bool, sub: Sub,
      star: bool,      // a word holds `*` (find, file, git log/diff/show)
      flagsSafe: bool, // every `-` word is in the tool's safe set (git branch/tag: every word is)
      remoteOk: bool,  // git remote with nothing, or one of -v --verbose show
      writes: bool,    // what the command really does (labelled in the bridge); the hook never reads it
    })
    .returns((e) => {
      const readTool = e.tool.is('Read').or(e.tool.is('Glob')).or(e.tool.is('Grep')).or(e.tool.is('WebSearch')).or(e.tool.is('WebFetch'))
      const scanned = e.tool.is('Bash').and(e.empty.not()).and(e.nul.not()).and(e.newline.not()).and(e.safeChars).and(e.words)
      const gitOk = v === 'git-before-worktree' ? e.first.is('git').or(e.first.is('git').not()) : e.first.is('git').not().or(e.worktree)
      const check = v === 'flags-unchecked' ? e.star.not() : e.star.not().and(e.flagsSafe)
      const bash = scanned.and(gitOk).and(
        e.first.is('fast').or(e.first.is('pwd'))
          .or(e.first.is('git').and(e.sub.is('statusLs')))
          .or(e.first.is('find').or(e.first.is('file')).and(check))
          .or(e.first.is('git').and(e.sub.is('logDiffShow')).and(check))
          .or(e.first.is('git').and(e.sub.is('branchTag')).and(v === 'flags-unchecked' ? e.words : e.flagsSafe))
          .or(e.first.is('git').and(e.sub.is('remote')).and(e.remoteOk)))
      const approve = readTool.or(bash)
      return {approve, deny: v === 'denies-unknown' ? approve.not() : approve.and(approve.not())}
    })
}
export const make = permissionAutoApprove

export function laws(f: ReturnType<typeof permissionAutoApprove>) {
  return {
    laws: [], stepLaws: [],
    decisions: [
      f.law('it never denies: what it cannot confirm goes to the normal prompt', () => [], (o) => o.deny.not()),
      f.law('read-only tools are always approved', (e) => [e.tool.is('Read').or(e.tool.is('Grep')).or(e.tool.is('Glob'))], (o) => o.approve),
      f.law('a Bash command with a character outside the allowlist is never approved', (e) => [e.tool.is('Bash'), e.safeChars.not()], (o) => o.approve.not()),
      f.law('a multi-line Bash command is never approved', (e) => [e.tool.is('Bash'), e.newline], (o) => o.approve.not()),
      f.law('no git command is approved outside a work tree', (e) => [e.tool.is('Bash'), e.first.is('git'), e.worktree.not()], (o) => o.approve.not()),
      f.law('find, file and git log are approved only with every flag in the safe set and no glob',
        (e) => [e.tool.is('Bash'), e.first.is('find').or(e.first.is('file')).or(e.first.is('git').and(e.sub.is('logDiffShow')))], (o, e) => o.approve.implies(e.flagsSafe.and(e.star.not()))),
      f.law('an unknown tool or command is never approved', (e) => [e.tool.is('Other').or(e.tool.is('Bash').and(e.first.is('other')))], (o) => o.approve.not()),
    ],
  }
}
