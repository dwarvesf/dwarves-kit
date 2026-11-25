// secrets-guard (hooks/secrets-guard.sh, PreToolUse Read|Edit|Bash) as a gdp-wired decision.
//
//   :92-102  Read|Edit: normalize the path (~, $HOME, ../), resolve symlinks when it exists (is_secret :74-90);
//            an ALLOW glob on the RESOLVED path exempts; a SECRET glob on the lexical OR resolved path blocks (exit 2).
//   :103-113 Bash: a reader word (cat less more head tail xxd strings od tac nl base64 cp) AND a secret token
//            (.ssh/id_, id_rsa, id_ed25519, .aws/credentials, .gnupg/, .git-credentials, .pem, .p12, .kube/config,
//            .npmrc) anywhere in the command -> exit 2.
//   any other tool -> exit 0. Unparseable input fails open (exit 0).
import {bool, fun, oneOf} from 'gdp-wired'

export const Tool = oneOf('Read', 'Edit', 'Bash', 'Grep', 'Write', 'Other')
export type Variant = 'shipped' | 'lexical-allow' | 'resolved-only'
export const VARIANTS: Variant[] = ['lexical-allow', 'resolved-only']

export function secretsGuard(v: Variant = 'shipped') {
  return fun(v === 'shipped' ? 'secrets-guard' : `secrets-guard/${v}`)
    .inputs({
      tool: Tool,
      lexSecret: bool,      // the normalized path matches a SECRET glob
      resSecret: bool,      // the symlink-resolved path matches a SECRET glob
      resAllowed: bool,     // the resolved path matches an ALLOW glob (.env.example, .env.sample, .env.template)
      lexAllowed: bool,     // the lexical path matches an ALLOW glob (must not exempt anything)
      readerWord: bool, secretToken: bool,
      secretFile: bool,     // the target really is one of the documented secret files
    })
    .returns(({tool, lexSecret, resSecret, resAllowed, lexAllowed, readerWord, secretToken}) => {
      const allowed = v === 'lexical-allow' ? resAllowed.or(lexAllowed) : resAllowed
      const secret = v === 'resolved-only' ? resSecret : lexSecret.or(resSecret)
      const path = tool.is('Read').or(tool.is('Edit')).and(allowed.not()).and(secret)
      const bash = tool.is('Bash').and(readerWord).and(secretToken)
      return {block: path.or(bash)}
    })
}

export function laws(f: ReturnType<typeof secretsGuard>) {
  return {
    laws: [], stepLaws: [],
    decisions: [
      f.law('a Read or Edit of a secret path is refused unless it resolves to an allowlisted template',
        ({tool, lexSecret, resSecret, resAllowed}) => [tool.is('Read').or(tool.is('Edit')), lexSecret.or(resSecret), resAllowed.not()], (o) => o.block),
      f.law('a symlink with an innocent name that resolves to a secret is refused',
        ({tool, resSecret, resAllowed}) => [tool.is('Read'), resSecret, resAllowed.not()], (o) => o.block),
      f.law('a template name does not exempt a link whose target is a secret',
        ({tool, lexAllowed, resSecret, resAllowed}) => [tool.is('Read'), lexAllowed, resSecret, resAllowed.not()], (o) => o.block),
      f.law('an allowlisted template that resolves to itself is never refused',
        ({tool, resAllowed}) => [tool.is('Read').or(tool.is('Edit')), resAllowed], (o) => o.block.not()),
      f.law('a Bash reader of an ssh key, cloud credentials or a .pem is refused',
        ({tool, readerWord, secretToken}) => [tool.is('Bash'), readerWord, secretToken], (o) => o.block),
      f.law('Write and other tools are never refused', ({tool}) => [tool.is('Write').or(tool.is('Other'))], (o) => o.block.not()),
    ],
    // Not promised by the hook (its header says the Read/Edit deny plus settings.json permissions.deny are the
    // reliable layer), but promised in spirit by hooks.md ("targets a secret file"): a Grep of a secret file reads it.
    refutedDecisions: [
      f.law('a Grep of a secret path is refused like a Read of it',
        ({tool, lexSecret, resAllowed}) => [tool.is('Grep'), lexSecret, resAllowed.not()], (o) => o.block),
    ],
  }
}
export const make = secretsGuard
