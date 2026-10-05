#!/usr/bin/env bash
# test-affected-replay.sh -- the guard for bin/test-affected's selection.
#
# Replays the last N merged PRs. For each one it recreates the changed-path set against the merge
# parent (`git diff --name-only <merge>^1 <merge>`), runs `<copy> --list --base <merge>^1` on a
# detached scratch worktree at the merge commit, and checks the pick against an independent "touched"
# rule. A MISS is a suite the touched rule says must run that the selection omitted.
#
# Touched rule (deterministic, no model call). A suite is touched by a PR when any of these holds:
#   - the PR edited the suite itself (tests/test-*.sh changed);
#   - a CI check run on the merge commit that FAILED names the suite (best effort, needs gh);
#   - a non-comment line of the suite runs or sources a changed source file: `bash|sh|source|. <path>`,
#     `$VAR/<path>`, a direct call, by repo path or by a basename over 5 chars;
#   - a changed non-source file (docs, fixtures) is named by its full repo path;
#   - kit.toml changed and the suite names kit.toml and a changed section or key (a hunk that no
#     section owns touches every suite naming kit.toml).
#
# Usage: test-affected-replay.sh [--n N] [--ta PATH] [--compare PATH] [--repo OWNER/NAME]
#   --n N          merged PRs to replay (default 30)
#   --ta PATH      the bin/test-affected copy under test (default: bin/test-affected of this checkout)
#   --compare PATH a second copy (for example master's); adds its picked count as the "before" column
#   --repo R       GitHub repo for `gh pr list` (default dwarvesf/dwarves-kit)
# Env: TA_REPLAY_PRS_FILE=<file of "<pr> <merge sha>" lines> skips gh (offline replay, the unit tests).
# Exit: 0 no MISS, 1 any MISS, 2 usage or setup trouble.
set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$HERE/../.." && pwd)"

die() { echo "test-affected-replay: $*" >&2; exit 2; }

N=30 TA="$ROOT/bin/test-affected" CMP="" REPO="dwarvesf/dwarves-kit"
while [ $# -gt 0 ]; do
  case "$1" in
    --n) [ $# -ge 2 ] || die "--n needs a number"; N="$2"; shift 2 ;;
    --ta) [ $# -ge 2 ] || die "--ta needs a path"; TA="$2"; shift 2 ;;
    --compare) [ $# -ge 2 ] || die "--compare needs a path"; CMP="$2"; shift 2 ;;
    --repo) [ $# -ge 2 ] || die "--repo needs OWNER/NAME"; REPO="$2"; shift 2 ;;
    -h|--help) sed -n '2,/^set -uo/p' "$0" | sed '$d;s/^# \{0,1\}//'; exit 0 ;;
    *) die "unknown argument: $1 (see --help)" ;;
  esac
done
case "$N" in ''|*[!0-9]*|0) die "--n must be a positive number" ;; esac
[ -f "$TA" ] || die "no such file: $TA"
[ -z "$CMP" ] || [ -f "$CMP" ] || die "no such file: $CMP"
TA="$(cd "$(dirname "$TA")" && pwd)/$(basename "$TA")"
[ -z "$CMP" ] || CMP="$(cd "$(dirname "$CMP")" && pwd)/$(basename "$CMP")"
cd "$ROOT" || die "cannot enter $ROOT"

WORK="$(mktemp -d "${TMPDIR:-/tmp}/ta-replay.XXXXXX")" || die "mktemp failed"
SCR="$WORK/wt"
cleanup() { git -C "$ROOT" worktree remove --force "$SCR" >/dev/null 2>&1 || true; git -C "$ROOT" worktree prune >/dev/null 2>&1 || true; rm -rf "$WORK"; }
trap cleanup EXIT

# --- the PR list: "<pr> <merge sha>", newest first ---
if [ -n "${TA_REPLAY_PRS_FILE:-}" ]; then
  cp "$TA_REPLAY_PRS_FILE" "$WORK/prs"
else
  command -v gh >/dev/null 2>&1 || die "gh not found (set TA_REPLAY_PRS_FILE for an offline replay)"
  gh pr list --repo "$REPO" --state merged -L "$N" --json number,mergeCommit \
    --jq '.[] | select(.mergeCommit != null) | "\(.number) \(.mergeCommit.oid)"' >"$WORK/prs" 2>"$WORK/gh.err" \
    || die "gh pr list failed: $(cat "$WORK/gh.err")"
fi
[ -s "$WORK/prs" ] || die "no merged PRs found"

# A merge commit that this clone lacks cannot be replayed; say so rather than skip silently.
first="$(head -1 "$WORK/prs" | cut -d' ' -f2)"
git cat-file -e "$first^{commit}" 2>/dev/null || die "merge commit $first is not in this clone (git fetch first)"
git worktree add -q --detach "$SCR" "$first" 2>"$WORK/wt.err" || die "worktree add failed: $(cat "$WORK/wt.err")"

# --- the touched rule, one perl pass per PR; paths and tokens come as files, suites as args ---
# args: <changed-paths file> <kit.toml tokens file> <suites...>; prints the touched suites.
read -r -d '' TOUCHED_PL <<'PERL' || true
my $pf = shift @ARGV; my $kf = shift @ARGV;
my (@paths, @ktok, $kfallback);
open(my $ph, "<", $pf) or exit 0; while (<$ph>) { chomp; push @paths, $_ if length; } close $ph;
if (open(my $kh, "<", $kf)) { while (<$kh>) { chomp; next unless length; if ($_ eq "?") { $kfallback = 1; next } my ($t, $x) = split /\t/, $_, 2; push @ktok, [$t, $x]; } close $kh; }
my %changed = map { $_ => 1 } @paths;
sub is_src { my $p = shift; return $p =~ m{^(?:lib/.*\.sh|tests/lib/.*\.sh|hooks/|bin/|commands/.*\.md|skills/.*\.md|agents/.*\.md)} }
my $cmd = qr{(?:bash|sh|source|\.|exec)};
SUITE: for my $s (@ARGV) {
  if ($changed{$s}) { print "$s\n"; next }
  open(my $h, "<", $s) or next;
  my @lines = grep { !/^\s*#/ } <$h>; close $h;
  my $text = join("", @lines);
  for my $p (@paths) {
    next if $p =~ m{^tests/test-[^/]*\.sh$};
    if ($p eq "kit.toml") {
      next unless $text =~ m{(?<![\w./-])kit\.toml(?![\w-])};
      if ($kfallback || !@ktok) { print "$s\n"; next SUITE }
      for my $k (@ktok) {
        my ($t, $x) = @$k; my $q = quotemeta($x);
        my $re = $t eq "k" ? qr{(?<![\w-])$q(?![\w-])}
               : $t eq "u" ? qr{$q}
               : $t eq "b" ? qr{\[$q\]}
               :             qr{(?<![\w.-])$q\.\w};
        if ($text =~ $re) { print "$s\n"; next SUITE }
      }
      next;
    }
    my $qp = quotemeta($p);
    if (!is_src($p)) {
      if ($text =~ m{(?<![\w.-])$qp(?![\w-])}) { print "$s\n"; next SUITE }
      next;
    }
    (my $b = $p) =~ s{.*/}{};
    my $qb = quotemeta($b);
    for my $l (@lines) {
      if ($l =~ m{(?:^|[\s;&|(`"=])$cmd\s+(?:-\w+\s+)*["\x27]?[^\s"\x27]*$qp(?![\w-])}) { print "$s\n"; next SUITE }
      if ($l =~ m{\$\{?\w+\}?/$qp(?![\w-])}) { print "$s\n"; next SUITE }
      if ($l =~ m{(?<![\w.-])$qp(?![\w-])} && $l =~ m{(?:^\s*|[;&|(]\s*|\bthen\s+|\bdo\s+)["\x27]?\S*$qp(?![\w-])}) { print "$s\n"; next SUITE }
      next unless length($b) > 5;
      if ($l =~ m{(?:^|[\s;&|(`"=])$cmd\s+(?:-\w+\s+)*["\x27]?(?:[^\s"\x27]*/)?$qb(?![\w.-])}) { print "$s\n"; next SUITE }
      if ($l =~ m{\$\{?\w+\}?/(?:[\w.-]+/)*$qb(?![\w.-])}) { print "$s\n"; next SUITE }
      if ($l =~ m{(?:^\s*|[;&|(]\s*|\bthen\s+|\bdo\s+)["\x27]?(?:\S*/)?$qb["\x27]?(?:\s|$|[;&|)])}) { print "$s\n"; next SUITE }
    }
  }
}
PERL

# kit.toml tokens for one PR: an independent reimplementation of the section/key attribution.
# args: <old kit.toml> <new kit.toml> on files; the unified -U0 diff on stdin. Prints "k\t<key>",
# "u\tKIT_<KEY>", "b\t<section>", "d\t<section>", or "?" when a hunk has no section.
read -r -d '' KTOK_PL <<'PERL' || true
my ($old, $new) = @ARGV;
sub scan {
  my ($f) = @_; my (@sec, @key); my ($cs, $ck) = ("", "");
  open(my $h, "<", $f) or return (\@sec, \@key);
  my $i = 0;
  while (<$h>) {
    $i++;
    if (/^\s*\[([^\]\n]+)\]/) { $cs = $1; $ck = ""; $sec[$i] = $cs; $key[$i] = ""; next }
    if (/^\s*#?\s{0,2}([A-Za-z_][\w-]*)\s*=/) { $ck = $1; }
    $sec[$i] = $cs; $key[$i] = $ck;
  }
  return (\@sec, \@key);
}
my %side = (old => [scan($old)], new => [scan($new)]);
my %out; my $unattr = 0;
my $any = 0;
while (<STDIN>) {
  next unless /^@@ -(\d+)(?:,(\d+))? \+(\d+)(?:,(\d+))? @@/;
  my ($a, $b, $c, $d) = ($1, defined $2 ? $2 : 1, $3, defined $4 ? $4 : 1);
  $any = 1;
  for my $pair ([old => $a, $b], [new => $c, $d]) {
    my ($w, $st, $n) = @$pair;
    for my $ln ($st .. $st + $n - 1) {
      next if $n == 0;
      my ($sec, $key) = ($side{$w}[0][$ln], $side{$w}[1][$ln]);
      if (!defined $sec || $sec eq "") { $unattr = 1; next }
      if (defined $key && length $key) { $out{"k\t$key"} = 1; (my $u = uc $key) =~ s/-/_/g; $out{"u\tKIT_$u"} = 1; }
      else { $out{"b\t$sec"} = 1; $out{"d\t$sec"} = 1; }
    }
  }
}
print "?\n" if $unattr || !$any;
print "$_\n" for sort keys %out;
PERL

mkdir -p "$WORK/o"
total_before=0 total_after=0 total_miss=0 nprs=0
printf '%-6s %5s %7s %6s %7s %5s\n' PR files before after touched MISS >"$WORK/table"
: >"$WORK/missdetail"
while IFS=' ' read -r pr sha; do
  [ -n "$pr" ] || continue
  git cat-file -e "$sha^{commit}" 2>/dev/null || { printf '%-6s %s\n' "#$pr" "SKIPPED (merge commit not in this clone)" >>"$WORK/table"; continue; }
  par="$sha^1"
  git rev-parse --verify --quiet "$par^{commit}" >/dev/null || { printf '%-6s %s\n' "#$pr" "SKIPPED (no parent)" >>"$WORK/table"; continue; }
  git -C "$SCR" checkout -q --detach "$sha" 2>/dev/null || { printf '%-6s %s\n' "#$pr" "SKIPPED (checkout failed)" >>"$WORK/table"; continue; }
  git -C "$ROOT" -c core.quotepath=off diff --name-only "$par" "$sha" | grep -v '^$' | sort -u >"$WORK/paths"
  nfiles="$(wc -l <"$WORK/paths" | tr -d ' ')"

  pick() {  # $1 = copy; prints the sorted unique suites its --list selects in the scratch worktree
    ( cd "$SCR" && bash "$1" --list --base "$par" 2>/dev/null ) | sed -n 's/^  \(tests\/test-[^ ]*\.sh\)  (.*/\1/p' | sort -u
  }
  pick "$TA" >"$WORK/after.sel"
  after="$(wc -l <"$WORK/after.sel" | tr -d ' ')"
  before="-"
  if [ -n "$CMP" ]; then pick "$CMP" >"$WORK/before.sel"; before="$(wc -l <"$WORK/before.sel" | tr -d ' ')"; total_before=$((total_before + before)); fi

  : >"$WORK/ktok"
  if grep -qx 'kit.toml' "$WORK/paths"; then
    git -C "$ROOT" show "$par:kit.toml" >"$WORK/kit.old" 2>/dev/null || : >"$WORK/kit.old"
    git -C "$ROOT" show "$sha:kit.toml" >"$WORK/kit.new" 2>/dev/null || : >"$WORK/kit.new"
    if [ -s "$WORK/kit.old" ] && [ -s "$WORK/kit.new" ]; then
      git -C "$ROOT" diff -U0 "$par" "$sha" -- kit.toml | perl -e "$KTOK_PL" "$WORK/kit.old" "$WORK/kit.new" >"$WORK/ktok"
    else
      echo '?' >"$WORK/ktok"
    fi
  fi
  suites=()
  while IFS= read -r t; do suites+=("$t"); done < <(cd "$SCR" && ls tests/test-*.sh 2>/dev/null)
  ( cd "$SCR" && perl -e "$TOUCHED_PL" "$WORK/paths" "$WORK/ktok" "${suites[@]}" ) | sort -u >"$WORK/touched"
  # A CI check run that failed on the merge commit and names a suite counts too (best effort).
  if [ -z "${TA_REPLAY_PRS_FILE:-}" ] && command -v gh >/dev/null 2>&1; then
    gh api "repos/$REPO/commits/$sha/check-runs?per_page=100" \
      --jq '.check_runs[] | select(.conclusion == "failure") | .name' 2>/dev/null \
      | grep -o 'test-[A-Za-z0-9_-]*' | sed 's|^|tests/|;s|$|.sh|' >>"$WORK/touched" || true
    sort -u -o "$WORK/touched" "$WORK/touched"
  fi
  # Only suites that still exist at the merge commit can be required.
  while IFS= read -r t; do [ -f "$SCR/$t" ] && echo "$t"; done <"$WORK/touched" >"$WORK/touched.ok"
  comm -23 "$WORK/touched.ok" "$WORK/after.sel" >"$WORK/miss"
  nmiss="$(wc -l <"$WORK/miss" | tr -d ' ')"; ntouched="$(wc -l <"$WORK/touched.ok" | tr -d ' ')"
  total_after=$((total_after + after)); total_miss=$((total_miss + nmiss)); nprs=$((nprs + 1))
  printf '%-6s %5s %7s %6s %7s %5s\n' "#$pr" "$nfiles" "$before" "$after" "$ntouched" "$nmiss" >>"$WORK/table"
  if [ "$nmiss" -gt 0 ]; then sed "s|^|  MISS #$pr |" "$WORK/miss" >>"$WORK/missdetail"; fi
done <"$WORK/prs"

cat "$WORK/table"
if [ -s "$WORK/missdetail" ]; then echo; cat "$WORK/missdetail"; fi
echo
if [ -n "$CMP" ]; then
  echo "test-affected-replay: $nprs PRs, picked $total_before before, $total_after after, $total_miss MISS"
else
  echo "test-affected-replay: $nprs PRs, picked $total_after, $total_miss MISS"
fi
[ "$total_miss" -eq 0 ]
