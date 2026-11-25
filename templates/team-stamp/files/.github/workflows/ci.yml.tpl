# CI for pull requests. Every job runs on a self-hosted runner: this file never names a
# GitHub-hosted runner label, because the team pays for no hosted minutes. A repo with a named
# runner pool edits runs-on in its own copy. Until a runner is attached, a run waits in the queue
# and never starts; bash scripts/check.sh runs the same checks on your machine.
#
# Where this binds. GitHub runs the workflow file of a pull request from the pull request's own
# merge commit, so a pull request can edit THIS file. "Gate scripts from the base revision" protects
# the scripts, not the workflow. What binds the workflow is scripts/pr-merge.sh: it merges only when
# both checks `changes` and `pr-shape` passed on the head it judged, each from the workflow named CI,
# and a pull request that touches .github/workflows/ is a door that needs a second person's approval.
#
# Runners. Nothing in this file executes a file from a pull request: both jobs run only scripts
# copied from the base revision. A job that runs the pull request's own code (tests, builds) belongs
# on a separate runner label or in a container job, never on the runner that runs `changes` and
# `pr-shape`: a long-lived runner keeps what a pull request's code writes, for the next run, the next
# pull request and the other repos on that host. Not for public repos. A pull request from a fork
# does not run here: the two jobs carry the `if:` guard below. A skipped job leaves its check
# missing, and the merge guard then refuses. scripts/check.sh runs the generated script tests on
# your own machine.
#
# Jobs
#   changes    scripts/check-owners.sh (every script and workflow has an owner), then a path filter
#              whose output "product" is true when a product path or this file changed. The repo's
#              own build and test jobs hang off it (see the end of the file).
#              scripts/pr-merge.sh waits for this job to pass, so keep the job name changes.
#   pr-shape   scripts/pr-shape.sh with the title and body of the pull request (title, proof file,
#              board link, changelog tag, shellcheck, rule parity).
#
# `changes` and `pr-shape` run ONLY scripts copied from the base revision. They never execute a file
# from the pull request head; shellcheck reads changed files and does not run them.
#
# The gate scripts (check-owners.sh and pr-shape.sh) are the copies from the BASE revision, so a pull
# request cannot weaken the checks it is judged by. A gate script the base does not have yet (the
# pull request that introduces the stamp) fails the job: merge that first pull request by hand.
# The title and body reach pr-shape.sh through env: entries and never through script text.
#
# Twin set: the commands below are the gate commands. scripts/check.sh runs each of them with the
# same inputs. Keep this list and the same list at the top of scripts/check.sh in step with the jobs.
#   twin: check-owners.sh
#   twin: pr-shape.sh env PR_TITLE PR_BODY BASE_SHA HEAD_SHA
#
# Pins. Every action is pinned by a full commit sha, with its release tag in the comment after it.
# The shellcheck release is pinned by tag and by the sha256 of each build; a download whose digest
# differs fails the job. To move a pin, read the release metadata:
#   gh api repos/actions/checkout/releases/latest --jq .tag_name
#   gh api repos/actions/checkout/git/ref/tags/<tag> --jq .object.sha
#   gh api repos/koalaman/shellcheck/releases/tags/<tag> --jq '.assets[] | [.name, .digest] | @tsv'
# Pinned here: shellcheck v0.11.0, one .tar.gz build per platform. A shell step picks the build by
# uname -s and uname -m, and checks the digest with sha256sum, or shasum -a 256 when sha256sum is absent.
name: CI

on:
  pull_request:
    types: [opened, synchronize, reopened, edited]

permissions:
  contents: read

jobs:
  changes:
    if: github.event.pull_request.head.repo.full_name == github.repository
    runs-on: [self-hosted]
    outputs:
      product: ${{ steps.filter.outputs.product }}
    steps:
      - uses: actions/checkout@3d3c42e5aac5ba805825da76410c181273ba90b1 # v7.0.1
        with:
          fetch-depth: 0
          persist-credentials: false

      - name: Take the owners check from the base revision
        env:
          BASE_SHA: ${{ github.event.pull_request.base.sha }}
        run: |
          set -euo pipefail
          gate="$RUNNER_TEMP/gate"
          mkdir -p "$gate"
          git cat-file -e "$BASE_SHA^{commit}" || { echo "gate: base $BASE_SHA is not in this checkout" >&2; exit 1; }
          f=check-owners.sh
          if git cat-file -e "$BASE_SHA:scripts/$f" 2>/dev/null; then
            git show "$BASE_SHA:scripts/$f" > "$gate/$f"
            echo "gate: scripts/$f is the copy from base $BASE_SHA"
          else
            echo "gate: base has no scripts/$f: this is the pull request that introduces the stamp. Merge it by hand (a second person reads it first); no check can judge it." >&2
            exit 1
          fi
          [ -s "$gate/$f" ] || { echo "gate: $f is empty" >&2; exit 1; }

      # check-owners.sh works in the folder above its own path. The copy sits outside the checkout,
      # so it is read as text and told its path is scripts/check-owners.sh of this checkout.
      - name: Every script and workflow has an owner
        run: bash -c "$(cat "$RUNNER_TEMP/gate/check-owners.sh")" "$PWD/scripts/check-owners.sh"

      - name: Path filter
        id: filter
        env:
          BASE_SHA: ${{ github.event.pull_request.base.sha }}
          HEAD_SHA: ${{ github.event.pull_request.head.sha }}
        run: |
          set -euo pipefail
          self='^\.github/workflows/ci\.yml$'
          product_re='{{PRODUCT_ERE}}'
          files="$(git diff --name-only "$BASE_SHA...$HEAD_SHA")"
          if grep -Eq "$self|$product_re" <<<"$files"; then
            echo "product=true" >> "$GITHUB_OUTPUT"
          else
            echo "product=false" >> "$GITHUB_OUTPUT"
          fi
          cat "$GITHUB_OUTPUT"

  pr-shape:
    if: github.event.pull_request.head.repo.full_name == github.repository
    runs-on: [self-hosted]
    steps:
      - uses: actions/checkout@3d3c42e5aac5ba805825da76410c181273ba90b1 # v7.0.1
        with:
          fetch-depth: 0
          persist-credentials: false

      - name: Install pinned shellcheck
        env:
          SHELLCHECK_VERSION: "0.11.0"
        run: |
          set -euo pipefail
          case "$(uname -s)-$(uname -m)" in
            Linux-x86_64) platform="linux.x86_64"; want="sha256=b7af85e41cc99489dcc21d66c6d5f3685138f06d34651e6d34b42ec6d54fe6f6" ;;
            Linux-aarch64 | Linux-arm64) platform="linux.aarch64"; want="sha256=68a8133197a50beb8803f8d42f9908d1af1c5540d4bb05fdfca8c1fa47decefc" ;;
            Darwin-x86_64) platform="darwin.x86_64"; want="sha256=c2c15e08df0e8fbc374c335b230a7ee958c313fa5714817a59aa59f1aa594f51" ;;
            Darwin-arm64 | Darwin-aarch64) platform="darwin.aarch64"; want="sha256=339b930feb1ea764467013cc1f72d09cd6b869ebf1013296ba9055ab2ffbd26f" ;;
            *) echo "shellcheck: no pinned build for $(uname -s) $(uname -m)" >&2; exit 1 ;;
          esac
          asset="shellcheck-v${SHELLCHECK_VERSION}.${platform}.tar.gz"
          dir="$RUNNER_TEMP/shellcheck-install"
          mkdir -p "$dir"
          curl -fsSL --retry 3 -o "$dir/$asset" \
            "https://github.com/koalaman/shellcheck/releases/download/v${SHELLCHECK_VERSION}/${asset}"
          if command -v sha256sum >/dev/null 2>&1; then
            got="$(sha256sum "$dir/$asset")"
          else
            got="$(shasum -a 256 "$dir/$asset")"
          fi
          got="${got%% *}"
          if [ "$got" != "${want#sha256=}" ]; then
            echo "shellcheck: the digest of $asset is sha256=$got, not the pinned ${want}" >&2
            exit 1
          fi
          tar -xzf "$dir/$asset" -C "$dir"
          echo "$dir/shellcheck-v${SHELLCHECK_VERSION}" >> "$GITHUB_PATH"
          "$dir/shellcheck-v${SHELLCHECK_VERSION}/shellcheck" --version

      - name: Take the PR shape check from the base revision
        env:
          BASE_SHA: ${{ github.event.pull_request.base.sha }}
        run: |
          set -euo pipefail
          gate="$RUNNER_TEMP/gate"
          mkdir -p "$gate"
          git cat-file -e "$BASE_SHA^{commit}" || { echo "gate: base $BASE_SHA is not in this checkout" >&2; exit 1; }
          f=pr-shape.sh
          if git cat-file -e "$BASE_SHA:scripts/$f" 2>/dev/null; then
            git show "$BASE_SHA:scripts/$f" > "$gate/$f"
            echo "gate: scripts/$f is the copy from base $BASE_SHA"
          else
            echo "gate: base has no scripts/$f: this is the pull request that introduces the stamp. Merge it by hand (a second person reads it first); no check can judge it." >&2
            exit 1
          fi
          [ -s "$gate/$f" ] || { echo "gate: $f is empty" >&2; exit 1; }

      - name: PR shape
        env:
          PR_TITLE: ${{ github.event.pull_request.title }}
          PR_BODY: ${{ github.event.pull_request.body }}
          BASE_SHA: ${{ github.event.pull_request.base.sha }}
          HEAD_SHA: ${{ github.event.pull_request.head.sha }}
        run: bash "$RUNNER_TEMP/gate/pr-shape.sh"

  # The repo's own build and test jobs go here, one per toolchain, as a stub for now. A job that runs
  # the pull request's own code belongs on a SEPARATE runner label or in a container job, never on
  # the runner that runs `changes` and `pr-shape`. Each one waits for the filter:
  #   needs: changes
  #   if: needs.changes.outputs.product == 'true'
  # pins every action by full commit sha, and passes no pull request text into a run: line (use an
  # env: entry). It does not run on [self-hosted] alone: give it its own label.
