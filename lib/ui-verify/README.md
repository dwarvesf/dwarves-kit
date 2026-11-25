# ui-verify

A runner that opens a pull request's preview in a pinned headless Chromium, runs a lead-written scenario file against it, and judges every row itself. The `kit:ui-acceptance-verifier` agent calls it and reports the result in the battery grammar. The runner works without the agent: `node lib/ui-verify/run.mjs scenario --scenario <file> --out <dir>`.

The runner refuses to run before it starts a browser when anything about the scenario file, the output directory or the hosts looks unsafe (exit 3). It never installs anything, never logs in, and writes only under `--out` (it creates that directory when it does not exist).

## First slice: scenario layer only

This slice runs a lead-written scenario against a preview and nothing more. These layers are not built: token conformance, layout invariants, an accessibility scan, pixel baselines, a vision pass, preview discovery from the pull request, a login or storage state, and a `--ui-only` flag. They are named follow-up slices in the spec under `docs/specs/`, and none starts before one consumer pull request has run this slice.

A page that needs a sign-in cannot be verified here. Write a `skip` entry for that criterion. Its row is NO-CHECK, and the agent maps any NO-CHECK to `FAIL:escalate`, so the merged verdict is never SHIP-clean for it.

PASS proves what the page showed the runner. A hostile page can detect an automated browser and show it something else (cloaking), and the runner cannot see that.

The whole surface is provisional until one consumer repo has run it: `schema: 1`, the exit codes (runner 0 to 4, 130 and 143, doctor 20 to 22), the doctor output lines, `UI_VERIFY_HOME`, the stdout row grammar and the `result.json` fields can change. Evolution rule: a new layer bumps `schema`, and the runner refuses a `schema` it does not know (exit 3).

## Prerequisites

- Node 22 or newer. An older node makes the runner exit 4, and the doctor prints the node version it found.
- Playwright and one Chromium build in the install root (next section).
- A preview URL for the head commit under test. The lead reads it from the pull request (the preview comment or the deployments list) and writes it into `target.url`. The runner does not look for it.

## Where the runner lives

The agent needs the absolute path of the kit's own runner. Never use a path inside the target repo.

| Install | Runner path |
|---|---|
| Claude Code plugin | `~/.claude/plugins/cache/dwarves-marketplace/kit/<version>/lib/ui-verify/run.mjs` (find it with `ls -d ~/.claude/plugins/cache/dwarves-marketplace/kit/*/lib/ui-verify/run.mjs`) |
| `install.sh` | `~/.claude/dwarves-kit/lib/ui-verify/run.mjs` |
| kit checkout | `lib/ui-verify/run.mjs` in the checkout (kit maintainers) |

Where to run it: a scenario run refuses (exit 3) when the runner's own real path sits inside the git work tree of the current directory. A plugin or `install.sh` copy sits outside any work tree, so it runs from anywhere. The kit checkout is a work tree that holds its own runner, so run a checkout copy from another directory. `--doctor` skips that check and runs from any directory.

## Install (an operator step)

The runner needs Playwright and one Chromium build in an install root outside the kit checkout and outside the target repo. The root comes from `UI_VERIFY_HOME`, else from `bash lib/config/data-path.sh path cache ui-verify`. The doctor prints the root, the pinned and installed versions, the pin age and the one install command, and exits 0 when the install is ready. The runner imports code from the install root, so it uses a root only when it is trusted: not inside a git work tree, owned by the current user, and not writable by group or others. Otherwise every row that would run is NO-CHECK `install root not trusted: <why>`, and the doctor prints `NOT READY: install root not trusted: <why>` (the why is `inside a git work tree`, `not owned by the current user` or `writable by group or others`). The check reads the root itself, not what is inside it.

```bash
node <runner path> --doctor
```

The install command it prints single-quotes every path, makes the root with `mkdir -p`, runs `chmod go-w` on it (a root made under umask 002 would otherwise be group-writable and refused), copies `package.json` and `package-lock.json` into it, runs `npm ci --ignore-scripts` there, then runs the local `playwright install chromium` with `PLAYWRIGHT_BROWSERS_PATH` set to `<install root>/browsers`. Expect about 23 MB of npm packages and about 586 MB of browsers, and about 3 minutes the first time.

| Doctor exit | Meaning |
|---|---|
| 0 | ready (the `state:` line may add `pin older than 120 days: bump it`; that never changes the exit) |
| 20 | Playwright is not installed in the install root, or the root is not trusted (the `state:` line says why) |
| 21 | the installed Playwright version differs from the pin |
| 22 | the browser is missing |

`--doctor` only reads the install. It skips the own-path check and every scenario guard.

## Run

```bash
node <runner path> scenario --scenario <file> --out <dir> [--step-timeout-ms N] [--scenario-timeout-ms N] [--run-budget-ms N]
```

Each timeout flag takes a positive whole number at or below its default (step 10 s, scenario 30 s, run 300 s); a larger value is refused, never clamped. `--step-timeout-ms` must also be at least 500, because `expect_no_text` needs a 500 ms window (a smaller value is refused, exit 3). There is no flag for the URL, hosts, loopback, install root, viewports or the sandbox: every trust input rides in the scenario file. Both the scenario file and `--out` must sit outside any git work tree, and `--out` must not exist or must be empty.

| Exit | Meaning |
|---|---|
| 0 | every row PASS, at least one row |
| 1 | at least one row FAIL |
| 2 | no FAIL and at least one NO-CHECK, or no rows (`no AC`) |
| 3 | usage error or a guard refused (an `--out` that cannot be created or read included); no browser started and nothing was written to `--out` |
| 4 | internal error (an uncaught exception), or a node older than 22 |
| 130 | SIGINT: the runner closed the browser first; no `result.json` is written |
| 143 | SIGTERM: the runner closed the browser first; no `result.json` is written |

## Reading the result

Once every guard has passed, the runner prints `ui-verify: run <run id>` on stderr, so a caller that must stop a run can find its browser by the `--kit-ui-verify=<run id>` marker on the browser's command line. On SIGTERM or SIGINT the runner closes the browser, kills any process that still carries the run id and prints `ui-verify: interrupted, browser closed` on stderr. Evidence lives only under `--out`: `result.json` and one screenshot per `screenshot` step, named `ac-<n>[-neg]-<width>-<name>.png`. Nothing is uploaded or committed. The same facts print on stdout:

```
ui-verify: head <sha40> scenario-sha256 <first 16 hex> preview-identity <matched|unverified|mismatch> playwright <version> run <run id>
ui-verify: counts PASS <p> FAIL <f> NO-CHECK <n> runner-verdict <PASS|FAIL|NO-CHECK>
row <id> [neg] | <PASS|FAIL|NO-CHECK> | <reason> | <evidence names>
observed <id> [neg]: <sanitized text>
```

In `result.json`, each row has a `status` of `PASS`, `FAIL` or `NO-CHECK`. A `NO-CHECK` row always carries a reason and never counts as `PASS`. The top-level `verdict` is `PASS` only when there is at least one row and every row is `PASS`. `observed` is page text with control, format and separator characters turned into spaces, a backtick turned into an apostrophe, a pipe turned into a slash, and a cut at 200 characters. `blocked_requests` lists what the runner refused to reach, so a lead who forgot an API host can see why a page looks empty. An entry is the host, or `<host>:<port>` for an allowed host on a port the runner refused. The list holds at most 50 entries, each cut at 100 characters, and `blocked_requests_truncated` is true when a further name was dropped. `identity.seen` is sanitized like `observed`. `browser.pids` records the browser processes found by the run id the runner puts on the browser command line. After the browser closes, the runner kills any process that still carries the run id, and `browser.leftover_pids` records the ones that survived even that. `browser.env_keys` lists the environment variable names the browser got (`HOME`, `PATH`).

## Residuals

- Cloaking: PASS proves what the page showed the runner. A page can detect an automated browser and show it something else.
- Another port of an allowed name: the request guards hold the port (see the allowed hosts rule below), but the browser's resolver rules carry no port and a redirect hop is not shown to the runner. A redirect from an allowed origin to another port of the same allowed name is followed, and that one request is sent. A top-level hop is then caught as NO-CHECK `redirected off an allowed host`; a sub-resource hop is not detected. A redirected POST arrives as a GET. The guards do not compare the scheme.
- The install-root trust check reads the root, not the files inside it.
- The browser's minimal environment and `--no-proxy-server` were checked on macOS only; a Linux host was not run.

## The scenario hash

The lead computes the hash when it writes the scenario file and puts it in the brief. The agent compares it with the one the runner prints.

```bash
shasum -a 256 <scenario file> | cut -c1-16
```

The result is the first 16 hex characters of the file's SHA-256 (`sha256sum` gives the same on a host without `shasum`). The first stdout line shows the same 16 after `scenario-sha256`, and `result.json` holds all 64.

## Preview identity

The runner can tell which build a preview serves only if the app says so. The app sends its build id in a response header on the document at `target.url` (name the header in `identity.header`) or in a `<meta name>` tag (name it in `identity.meta`). The value must be the commit SHA, 7 to 40 hex characters (the runner trims it and ignores case). The runner compares it with `head_sha`: `matched` when `head_sha` starts with it, `mismatch` when it does not (every row is then NO-CHECK `preview is not the head`).

Anything else is `unverified`: no `identity` key, no such header or meta, or a value that is not 7 to 40 hex characters (a UUID, a semver). The rows still run, and a stale preview can pass. The stdout line and the agent's report print `unverified` so a reader sees the gap, and nothing else flags it. A plain Cloudflare preview exposes no build id, so expect `unverified` there until the app adds a header or meta tag.

## Keeping the pin fresh

The kit maintainers own the pin. Playwright is pinned exactly in `package.json` (with a `pinnedOn` date) and `package-lock.json`. Bump the pin at least every 120 days and on any Playwright security release. The age check is the doctor's `pin age` and `state:` lines (`state:` says to bump the pin once it is older than 120 days), and `commands/kit-health.md` runs the doctor when the install root exists. To bump: edit both files, rerun `tests/test-ui-acceptance-verifier.sh` with `UI_VERIFY_REQUIRE=1`, and re-record the live dispatch in `docs/verification/ui-acceptance-verifier.md` in the same pull request. Make the lockfile with `npm install --package-lock-only --ignore-scripts` in a scratch copy of `package.json`, never inside the kit checkout.

## Removing it (the orphan list)

All runtime state sits under one install root. A removal reports these paths and deletes none by script:

- the install root directory (`bash lib/config/data-path.sh path cache ui-verify`: the npm install and the browsers together)
- `lib/ui-verify/` (this runner, `package.json`, `package-lock.json`, this README)
- `agents/ui-acceptance-verifier.md` and its row in the "Lens escalation" table of `commands/battery.md`
- the `cache ui-verify` entry in `lib/config/data-path.sh` and the `UI_VERIFY_HOME` row in `lib/config/module-registry.md`
- the doc rows (`docs/MANUAL.md`, `docs/reference/architecture.md`, `docs/reference/workflow-paths.md`, `docs/reference/FEATURES.md`, `commands/kit-health.md`, `docs/reference/PHILOSOPHY.md`, `CHANGELOG.md`)
- `tests/fixtures/ui-verify/` and `tests/test-ui-acceptance-verifier.sh`
- `docs/verification/ui-acceptance-verifier.md`

## Writing a scenario

The lead writes the scenario file from the acceptance criteria, into a fresh `mktemp -d` directory outside any git work tree. One entry per criterion, and one more per named negative case (a case that must be refused or must not happen).

```json
{
  "schema": 1,
  "target": {
    "url": "https://pr-12.preview.example.dev/",
    "head_sha": "0123456789abcdef0123456789abcdef01234567",
    "allow_hosts": ["pr-12.preview.example.dev", "api.example.dev"],
    "allow_loopback": false
  },
  "viewports": [390, 768, 1280],
  "ready": { "text": "Dashboard" },
  "identity": { "header": "x-build-sha" },
  "scenarios": [
    { "id": "AC-1", "kind": "criterion", "title": "member saves a profile",
      "steps": [
        { "do": "goto", "path": "/settings" },
        { "do": "fill", "role": "textbox", "name": "Display name", "value": "Ada" },
        { "do": "click", "role": "button", "name": "Save" },
        { "do": "expect_text", "text": "Saved" },
        { "do": "screenshot", "name": "after-save" }
      ] },
    { "id": "AC-1", "kind": "negative", "title": "empty name is refused",
      "steps": [
        { "do": "goto", "path": "/settings" },
        { "do": "click", "role": "button", "name": "Save" },
        { "do": "expect_text", "text": "Name is required" },
        { "do": "expect_no_text", "text": "Saved" }
      ] },
    { "id": "AC-2", "kind": "criterion", "title": "signed-in only page",
      "skip": "needs a signed-in session; storage state is a later slice" }
  ]
}
```

Fields:

- Unknown keys anywhere are refused. `schema` must be `1`. Every string is at most 200 characters.
- `target.url` must be `https:`. `http:` is accepted only with `allow_loopback` true and a host of `127.0.0.1`, `localhost` or `[::1]` (the fixture suite does this; a real run never does).
- `target.allow_hosts` holds 1 to 8 exact hostnames, no wildcards, and must include the URL's host. It bounds redirects and every subresource and WebSocket request. Add the API host a real preview calls. The port is held too: the host of `target.url` may use the port of `target.url`, and every other allowed host may use only the default port of the request's scheme (80 or 443). A request to an allowed host on any other port is refused and listed in `blocked_requests` as `<host>:<port>`, so a second host on a non-default port cannot be allowed in this slice.
- `target.head_sha` is the 40 lowercase hex commit under test.
- `ready.text` is 1 to 100 characters that only the real app renders, never a login wall.
- `viewports` is optional: up to 4 integers from 200 to 3000, default `[390, 768, 1280]`. The height is 900 for every width.
- `identity` is optional and holds exactly one of `header` (a response header name) or `meta` (a `<meta name>`). A value that looks like a build id (7 to 40 hex characters, any case) is compared with `head_sha`; see Preview identity above.
- `scenarios` holds at most 12 entries. `id` is `AC-<digits>`, `kind` is `criterion` or `negative`, and the pair is unique. An entry has `steps` (1 to 20) or `skip` (a reason), never both.
- A scenario with steps must hold at least one `expect_text`, `expect_no_text` or `expect_url` step. Without one it is not run and its row is NO-CHECK `scenario asserts nothing`; the other entries still run.

Step verbs, the only ones accepted:

| Step | Fields | Passes when |
|---|---|---|
| `goto` | `path` (starts with exactly one `/`) | the page reaches `load` and `document.fonts.ready`; a navigation error is NO-CHECK `page did not settle` |
| `click` | `role`, `name` | exactly one element matches `getByRole(role, { name, exact: true })` |
| `fill` | `role`, `name`, `value` | the same locator matches exactly one element; an action error that is not a timeout (a `fill` on a button) is FAIL `element not actionable: role=<role> name=<name>` |
| `expect_text` | `text`, optional `within: {role, name}` | `text` is a case-sensitive substring of the whitespace-collapsed `innerText` of the `within` element, else of `<body>`, polled until the step timeout; the last part of the step (up to 1 s, at most half) is kept for the `observed` read |
| `expect_no_text` | `text` | the page was read at least once inside an unbroken 500 ms window and `text` was absent on every read; no read in the window is NO-CHECK `page did not settle` |
| `expect_url` | `path` | `location.pathname + location.search` equals `path`, polled until the step timeout |
| `screenshot` | `name` (`a-z`, `0-9`, `-` only) | always; writes the PNG under `--out` |

Step semantics:

- `click` and `fill`: zero matches, or more than one, after the step timeout is FAIL. `observed` is `element not found: role=<role> name=<name>` or `ambiguous: <n> matches`. A `within` element that is missing is FAIL `element not found: role=<role> name=<name>`.
- `observed` on a failed expect is the sanitized text, cut at 200 characters, of the `within` element, else of the first `[role=alert]` or `[role=status]` element, else of `<main>`, else of `<body>`.
- The scenario clock also caps a step in flight: a step waits at most the smallest of the step timeout, the scenario time left and the run budget left. When the scenario clock is the one that ran out, the row is NO-CHECK `scenario timeout`; when the run budget is, `run budget spent`.
- The browser starts with `--no-proxy-server` and an environment of only `PATH` and a temporary `HOME`, so the runner's own tokens and proxy settings never reach it.
- The browser resolves only the allowed hosts, each to the address checked at startup (`--host-resolver-rules`, recorded in `browser.args`); every other name or IP literal fails at name resolution. That is what stops a redirect to an unlisted host and a name that re-resolves to a private address. A blocked top-level hop is NO-CHECK `redirected off an allowed host`; a blocked subresource or hop changes no row status and is listed in `blocked_requests`.
- No step runs longer than its limit. A step that fails while a top-level navigation was blocked, or after which the page URL has a host or port off the allowed set, is NO-CHECK `redirected off an allowed host`, not FAIL.
- A FAIL scenario is retried once per scenario and viewport in a fresh context. A row that failed once and passed on the retry is `PASS` with `flaky: true`. A NO-CHECK scenario is not retried.
- A row's status is the worst over its viewports (FAIL over NO-CHECK over PASS).

The twelve roles: `button`, `link`, `textbox`, `checkbox`, `radio`, `combobox`, `heading`, `tab`, `menuitem`, `dialog`, `alert`, `status`.

Refusals (exit 3, one line on stderr, nothing written to `--out`):

- a usage error, an unknown argument, a timeout flag that is not a positive whole number at or below its default, or a `--step-timeout-ms` under 500
- an `--out` that cannot be created or read (an unwritable parent included)
- a `--scenario` path that cannot be read or is not valid JSON, or that sits inside a git work tree
- `--out` inside a git work tree, or `--out` that exists and is not empty
- the runner's own real path sitting inside the git work tree of the current directory
- an unknown key, a missing required key, `schema` other than 1, a wrong type, a string over its limit, or more than 12 scenarios, 20 steps, 4 viewports or 8 hosts
- a `target.url` that is not `https:` (or `http:` on a loopback host with `allow_loopback`), carries credentials, or has a host missing from `allow_hosts`
- an allowed host that resolves to a loopback (without `allow_loopback`), private, link-local, shared (100.64.0.0/10, the tailnet range), unique-local, site-local (`fec0::/10`) or IPv6 transition (`64:ff9b::/96`, `2002::/16`, `::/96`) address
- an unknown step verb (a name like `constructor` or `__proto__` included), a `goto` or `expect_url` path that does not start with exactly one `/`, a role outside the twelve, a duplicate (`id`, `kind`) pair, an entry with both `steps` and `skip`, or an `identity` with both keys

An allowed host that does not resolve at all is not a refusal: every row is NO-CHECK `preview unreachable` and the exit is 2.
