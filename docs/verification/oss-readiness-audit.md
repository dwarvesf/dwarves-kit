# Open-source readiness audit: secrets and history

Audit date: 2026-11-25. Target: the public `dwarvesf/dwarves-kit` repository and everything a stranger can reach from it. The audit was read-only: it changed no ref, file, setting, PR or comment.

## Scope

| # | Surface | What was scanned |
|---|---|---|
| 1 | Public tree | A clean `git archive` export of `master` (2,371 files) |
| 2 | Public history | A bare mirror clone: `master`, 5 other branches, 15 tags and 1,179 `refs/pull/*` refs (4,967 non-merge commits, 280 MB of patches) |
| 3 | The release squash | Public `master` compared with the private archive tag of the pre-release history |
| 4 | GitHub-side text | 1,177 PR titles and bodies, 6 issues, 27 issue comments, 0 review comments, 8 releases |
| 5 | Actions | The one workflow file, the repo Actions settings, and the logs of 2 recent runs |
| 6 | Residual reach | Forks, dangling objects kept by GitHub, third-party caches (listed, not scanned) |

## Method

Tools: gitleaks 8.30.1 (default ruleset), git 2.56.1, gh 2.104.0, ripgrep 15.2.0.

Secret scan commands:

```bash
git clone --mirror git@github.com:dwarvesf/dwarves-kit.git mirror.git
git -C mirror.git archive master | tar -x -C tree
gitleaks dir tree --redact -f json -r gl-tree.json
gitleaks git mirror.git --redact --log-opts="--all" -f json -r gl-history.json
gh pr list -R dwarvesf/dwarves-kit --state all --limit 1300 --json number,title,body > prs.json
gh issue list -R dwarvesf/dwarves-kit --state all --limit 500 --json number,title,body > issues.json
gh api repos/dwarvesf/dwarves-kit/issues/comments --paginate > issue-comments.json
gh api repos/dwarvesf/dwarves-kit/pulls/comments --paginate > pr-review-comments.json
gh api repos/dwarvesf/dwarves-kit/releases --paginate > releases.json
gitleaks dir gh-text --redact -f json -r gl-gh.json   # one file per PR, issue, comment, release
gh run view <id> -R dwarvesf/dwarves-kit --log > run-<id>.log; gitleaks dir runlogs --redact
```

Privacy-gate greps ran with ripgrep over the tree, the GitHub text, the files removed before release, and every added line in all history. Classes: email addresses, `op://` references, 32-hex ids (Cloudflare account, Notion), 17 to 20 digit Discord snowflakes, Telegram chat ids, webhook URLs, IPv4 addresses, `*.ts.net` names, `/Users/<name>` and `/home/<name>` paths, operator handles and hostnames, tenant names, money amounts, and family, finance and client keywords.

Triage: each gitleaks hit was deduplicated by rule and masked value, then read in context (file purpose, fake markers, entropy, repeated patterns, whether the same value sits in a fixture). No credential was tested by use.

## Results

| Surface | Items scanned | gitleaks hits | Fixture or fake | Placeholder or not a credential | Revoked or rotated | Possibly live | Privacy should-fix | Privacy cosmetic |
|---|---|---|---|---|---|---|---|---|
| 1. Public tree | 2,371 files | 22 (22 distinct) | 18 | 4 | 0 | 0 | 3 classes | 6 classes |
| 2. Public history, all refs | 4,967 commits, 1,179 PR refs | 69 (27 distinct) | 16 | 11 | 0 | 0 | 2 classes | 4 classes |
| 3. Release squash | 1 comparison | n/a | n/a | n/a | n/a | n/a | 1 (doc claim does not match the history) | 0 |
| 4. GitHub-side text | 1,218 text items | 0 | 0 | 0 | 0 | 0 | 1 class | 3 classes |
| 5. Actions | 1 workflow, 2 run logs | 0 | 0 | 0 | 0 | 0 | 0 | 0 |
| 6. Residual reach | not scannable | NOT SCANNED | | | | | | |

Notes on the results:

- Every vendor-shaped hit (AWS, GitHub, Stripe, curl auth) sits in a test fixture built to exercise the kit's own leak guards. The placeholder hits are the gate-ledger verdict syntax and a local round nonce, which match the generic-key rule but carry no credential.
- The GitHub-side text and the sampled run logs hold no credential-shaped strings.
- Fixed in the same change as this report: `docs/HISTORY.md` said the public history was squashed, which it was not, and one proof record quoted file paths from a private repo. The remaining privacy items are cosmetic or need a maintainer decision.
- The privacy findings are operator-specific paths, vault and item names in `op://` pointers, the owner's email in test fixtures, names of private sibling repos, and pre-release internal planning files that the release prune removed from the tree but not from history. None holds a credential, an account id or a client name. The maintainer has the locations privately.

Actions posture: the workflow runs only on manual dispatch and `v*` tag pushes, never on `pull_request` or `pull_request_target`. It uses GitHub-hosted runners only (`ubuntu-latest`, `macos-latest`), the token is `contents: read`, it references no secrets, and the repo has 0 repository secrets and 0 self-hosted runners. A fork PR cannot reach a secret or a runner through it.

## Verdict

zero live secrets found

## Residual risks

- Forks: 2 public forks keep the history as it was on the day they were forked (May and June 2026); a change here does not reach them.
- PR refs: GitHub keeps `refs/pull/N/head` for all 1,176 PRs, read-only and outside any force-push; only GitHub Support can remove them.
- Dangling objects: commits removed by a future force-push stay fetchable by SHA through the fork network and cached views until GitHub garbage-collects them.
- Third-party caches: Software Heritage, GH Archive, code-search indexes and web caches may hold copies; they cannot be scanned or recalled from here.
- Org-level Actions secrets were not listed; the workflow references none, so they are out of its reach.
- gitleaks default rules miss some formats; privacy greps are pattern-based and catch shapes, not meaning.

## What a maintainer reruns before a release

```bash
git clone --mirror git@github.com:dwarvesf/dwarves-kit.git /tmp/kit-audit.git
gitleaks git /tmp/kit-audit.git --redact --log-opts="--all" -f json -r /tmp/kit-history.json
bash tests/test-no-personal-paths.sh
gh pr list -R dwarvesf/dwarves-kit --state all --limit 2000 --json number,title,body > /tmp/prs.json && gitleaks dir /tmp/prs.json --redact
```

Triage any new hit as fixture, placeholder, rotated or possibly live before tagging the release.
