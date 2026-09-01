#!/usr/bin/env bash
# lib/sync/deploy/macos/install tests (kit board ID-289: sync.mode = cron).
# Covers the sync.mode gate (manual refuses, cron proceeds, a bad value is
# rejected cleanly -- the negative control), the apps-not-configured guard,
# both board conventions, --interval-secs validation, dry-run vs --apply (a
# stubbed launchctl proves dry-run never mutates and --apply calls it with
# the right verbs/args), and label/slug uniqueness across two repos.
set -uo pipefail
KIT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
INSTALL="$KIT_ROOT/lib/sync/deploy/macos/install"
PASS=0; FAIL=0
ok()   { PASS=$((PASS+1)); printf '  PASS %s\n' "$1"; }
bad()  { FAIL=$((FAIL+1)); printf '  FAIL %s\n' "$1"; }
check(){ if eval "$2"; then ok "$1"; else bad "$1 -- got: $3"; fi; }

d="$(mktemp -d)"; trap 'rm -rf "$d"' EXIT

# fake $HOME so the script never touches the real ~/Library, and a fake
# kit-root kit.toml so kit_config_get's second precedence level is inert.
export HOME="$d/home"; mkdir -p "$HOME"
export KIT_CONFIG_ROOT="$d/kitroot"; mkdir -p "$KIT_CONFIG_ROOT"
printf '[sync]\nmode = "manual"\n' > "$KIT_CONFIG_ROOT/kit.toml"

# a stub launchctl that logs every invocation, so dry-run-never-mutates and
# apply-calls-it-correctly are both directly provable (not inferred).
mkdir -p "$d/bin"
LAUNCHCTL_LOG="$d/launchctl.log"
cat > "$d/bin/launchctl" <<STUB
#!/usr/bin/env bash
printf '%s\n' "\$*" >> "$LAUNCHCTL_LOG"
# mimic real launchctl print: echo something containing the label so the
# install script's own best-effort confirmation grep has something to match.
[ "\$1" = "print" ] && printf 'service = %s\n' "\${2##*/}"
exit 0
STUB
chmod +x "$d/bin/launchctl"
export PATH="$d/bin:$PATH"

mk_repo() {
  local dir="$1" convention="$2"
  mkdir -p "$dir"
  git -C "$dir" init -q
  if [ "$convention" = "meta" ]; then
    mkdir -p "$dir/_meta"; touch "$dir/_meta/BACKLOG.md"
  else
    touch "$dir/BACKLOG.md"
  fi
}

# --- repo A: no [sync] section at all (mode defaults to manual) -----------
mk_repo "$d/repoA" meta
out="$(bash "$INSTALL" --repo "$d/repoA" 2>&1)"; rc=$?
check "unset mode (default manual) refuses, exit 2" '[ "$rc" -eq 2 ]' "rc=$rc"
check "unset mode: message points at mode = \"cron\"" \
  '[[ "$out" == *'"'"'mode = "cron"'"'"'* ]]' "$out"
check "unset mode: no launchctl.log written (nothing attempted)" \
  '[ ! -f "$LAUNCHCTL_LOG" ]' "$(cat "$LAUNCHCTL_LOG" 2>/dev/null)"

# --- repo B: mode explicitly "manual" ---------------------------------------
mk_repo "$d/repoB" meta
printf '[sync]\napps = "reminders"\nmode = "manual"\n' > "$d/repoB/.kit.toml"
out="$(bash "$INSTALL" --repo "$d/repoB" 2>&1)"; rc=$?
check "explicit mode=manual refuses, exit 2" '[ "$rc" -eq 2 ]' "rc=$rc"

# --- repo C: NEGATIVE CONTROL -- a bad mode value is rejected cleanly ------
mk_repo "$d/repoC" meta
printf '[sync]\napps = "reminders"\nmode = "biweekly"\n' > "$d/repoC/.kit.toml"
out="$(bash "$INSTALL" --repo "$d/repoC" 2>&1)"; rc=$?
check "bad mode value ('biweekly') rejected, exit 2 (not a crash)" '[ "$rc" -eq 2 ]' "rc=$rc"
check "bad mode value: message names the offending value" \
  '[[ "$out" == *"mode='"'"'biweekly'"'"'"* ]]' "$out"
check "bad mode value: no launchctl invocation" \
  '[ ! -s "$LAUNCHCTL_LOG" ]' "$(cat "$LAUNCHCTL_LOG" 2>/dev/null)"

# --- repo D: mode=cron but no apps configured ------------------------------
mk_repo "$d/repoD" meta
printf '[sync]\nmode = "cron"\n' > "$d/repoD/.kit.toml"
out="$(bash "$INSTALL" --repo "$d/repoD" 2>&1)"; rc=$?
check "mode=cron with no apps refuses, exit 2" '[ "$rc" -eq 2 ]' "rc=$rc"
check "mode=cron/no-apps: message names the missing apps key" \
  '[[ "$out" == *"apps"* ]]' "$out"

# --- repo E: mode=cron + apps, DRY-RUN (default) ---------------------------
mk_repo "$d/repoE" meta
printf '[sync]\napps = "reminders,notion"\nmode = "cron"\n' > "$d/repoE/.kit.toml"
out="$(bash "$INSTALL" --repo "$d/repoE" 2>&1)"; rc=$?
check "mode=cron + apps, dry-run exits 0" '[ "$rc" -eq 0 ]' "rc=$rc"
check "dry-run: prints the rendered ProgramArguments (backlog path)" \
  '[[ "$out" == *"$d/repoE/_meta/BACKLOG.md"* ]]' "$out"
check "dry-run: prints the label" \
  '[[ "$out" == *"board-sync-"* ]]' "$out"
check "dry-run: prints the exact launchctl bootstrap command to run" \
  '[[ "$out" == *"launchctl bootstrap"* ]]' "$out"
check "dry-run NEVER calls the real launchctl (no mutation)" \
  '[ ! -s "$LAUNCHCTL_LOG" ]' "$(cat "$LAUNCHCTL_LOG" 2>/dev/null)"
check "dry-run: no plist written to \$HOME/Library/LaunchAgents" \
  '[ ! -d "$HOME/Library/LaunchAgents" ] || [ -z "$(ls -A "$HOME/Library/LaunchAgents" 2>/dev/null)" ]' \
  "$(ls "$HOME/Library/LaunchAgents" 2>/dev/null)"

# --- repo E again, root-level BACKLOG.md convention, --interval-secs -------
mk_repo "$d/repoF" root
printf '[sync]\napps = "hermes"\nmode = "cron"\n' > "$d/repoF/.kit.toml"
out="$(bash "$INSTALL" --repo "$d/repoF" --interval-secs 900 2>&1)"; rc=$?
check "root-level BACKLOG.md convention resolves" \
  '[[ "$rc" -eq 0 && "$out" == *"$d/repoF/BACKLOG.md"* ]]' "rc=$rc $out"
check "custom --interval-secs is rendered into the plist" \
  '[[ "$out" == *"<integer>900</integer>"* ]]' "$out"

# --- --interval-secs validation --------------------------------------------
out="$(bash "$INSTALL" --repo "$d/repoE" --interval-secs abc 2>&1)"; rc=$?
check "non-numeric --interval-secs rejected cleanly, exit 2" '[ "$rc" -eq 2 ]' "rc=$rc"

# --- repo E, APPLY: stubbed launchctl proves the real mutation path --------
out="$(bash "$INSTALL" --repo "$d/repoE" --apply 2>&1)"; rc=$?
check "mode=cron + apps, --apply exits 0" '[ "$rc" -eq 0 ]' "rc=$rc"
check "--apply writes a plist under \$HOME/Library/LaunchAgents" \
  '[ -n "$(ls "$HOME/Library/LaunchAgents"/board-sync-*.plist 2>/dev/null)" ]' \
  "$(ls "$HOME/Library/LaunchAgents" 2>/dev/null)"
plist_written="$(ls "$HOME/Library/LaunchAgents"/board-sync-*.plist 2>/dev/null | head -1)"
check "written plist references the repo's own board-sync-cron launcher + backlog path" \
  '[[ -f "$plist_written" && "$(cat "$plist_written")" == *"lib/sync/deploy/macos/board-sync-cron"* && "$(cat "$plist_written")" == *"$d/repoE/_meta/BACKLOG.md"* ]]' \
  "$plist_written"
check "--apply invoked launchctl bootout then bootstrap" \
  '[ "$(grep -c "^bootout\|^bootstrap" "$LAUNCHCTL_LOG")" -ge 2 ]' "$(cat "$LAUNCHCTL_LOG")"

# --- label uniqueness across two differently-named repos ------------------
mk_repo "$d/repoG" meta
printf '[sync]\napps = "reminders"\nmode = "cron"\n' > "$d/repoG/.kit.toml"
out_e="$(bash "$INSTALL" --repo "$d/repoE" 2>&1)"
out_g="$(bash "$INSTALL" --repo "$d/repoG" 2>&1)"
label_e="$(printf '%s\n' "$out_e" | grep -oE 'board-sync-[a-zA-Z0-9-]+' | head -1)"
label_g="$(printf '%s\n' "$out_g" | grep -oE 'board-sync-[a-zA-Z0-9-]+' | head -1)"
check "two different repos render two different LaunchAgent labels" \
  '[ -n "$label_e" ] && [ -n "$label_g" ] && [ "$label_e" != "$label_g" ]' \
  "e=$label_e g=$label_g"

# --- sync.interval_secs config default (no --interval-secs flag) ----------
mk_repo "$d/repoH" meta
printf '[sync]\napps = "reminders"\nmode = "cron"\ninterval_secs = 1800\n' > "$d/repoH/.kit.toml"
out="$(bash "$INSTALL" --repo "$d/repoH" 2>&1)"; rc=$?
check "sync.interval_secs from .kit.toml is used when --interval-secs is omitted" \
  '[ "$rc" -eq 0 ] && [[ "$out" == *"<integer>1800</integer>"* ]]' "$out"
out="$(bash "$INSTALL" --repo "$d/repoH" --interval-secs 60 2>&1)"; rc=$?
check "--interval-secs flag overrides sync.interval_secs" \
  '[ "$rc" -eq 0 ] && [[ "$out" == *"<integer>60</integer>"* ]]' "$out"

# --- label-collision guard: two repos whose slugs collapse to the SAME
# label (mktemp -d, . and - both collapse to one '-') must not silently
# clobber each other's installed job. ---------------------------------------
mk_repo "$d/collide-one" meta
mk_repo "$d/collide.one" meta
printf '[sync]\napps = "reminders"\nmode = "cron"\n' > "$d/collide-one/.kit.toml"
printf '[sync]\napps = "reminders"\nmode = "cron"\n' > "$d/collide.one/.kit.toml"
slug_a="$(printf '%s' "$d/collide-one/_meta/BACKLOG.md" | sed -E 's/[^a-zA-Z0-9]+/-/g; s/^-+//; s/-+$//')"
slug_b="$(printf '%s' "$d/collide.one/_meta/BACKLOG.md" | sed -E 's/[^a-zA-Z0-9]+/-/g; s/^-+//; s/-+$//')"
if [ "$slug_a" = "$slug_b" ]; then
  bash "$INSTALL" --repo "$d/collide-one" --apply >/dev/null 2>&1
  out="$(bash "$INSTALL" --repo "$d/collide.one" 2>&1)"; rc=$?
  check "colliding slug from a DIFFERENT repo's backlog is refused, exit 2" \
    '[ "$rc" -eq 2 ]' "rc=$rc $out"
  check "collision message names both the existing and the new backlog path" \
    '[[ "$out" == *"$d/collide-one/_meta/BACKLOG.md"* && "$out" == *"$d/collide.one/_meta/BACKLOG.md"* ]]' "$out"
  out="$(bash "$INSTALL" --repo "$d/collide.one" --apply 2>&1)"; rc=$?
  check "colliding slug also refused under --apply (never silently takes over)" \
    '[ "$rc" -eq 2 ]' "rc=$rc $out"
  out="$(bash "$INSTALL" --repo "$d/collide-one" 2>&1)"; rc=$?
  check "re-installing the SAME repo over its own existing plist is fine (not a collision)" \
    '[ "$rc" -eq 0 ]' "rc=$rc $out"
else
  bad "label-collision fixture assumption ('.' and '-' collapse identically) -- got: slug_a=$slug_a slug_b=$slug_b"
fi

printf '=== %d/%d passed ===\n' "$PASS" "$((PASS+FAIL))"
[ "$FAIL" -eq 0 ]
