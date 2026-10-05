#!/usr/bin/env bash
# board-digest.sh: turn the captured stdout of `board sync` into change-only
# digest payloads, one per cluster (a cluster is one notify destination, named
# by the `rail=<name>` column of the registry). Pure parse and build: it never
# posts. lib/sync/sweep/board-sweep-post.sh hands each payload to the poster
# command and then calls --mark-posted or --mark-failed here.
#
# Modes:
#   --repo <name>
#     stdin: one repo's captured `board sync` stdout (all its spoke apps).
#     Parses it and writes this repo's change set and flap-tracking ids into
#     the state file. Never prints a payload.
#   --emit --cluster <name>
#     Merges every repo mapped to that cluster and prints ONE payload on
#     stdout when there is anything to report (this sweep's parsed changes,
#     merged with any carried-forward `unsent`). Never mutates `unsent`.
#   --mark-posted --cluster <name>
#     Clears `unsent` for every repo in the cluster (call after a confirmed
#     post).
#   --mark-failed --cluster <name> [--reason TEXT | --reason-file F]
#     Recomputes the cluster's merged change set (same as --emit) and writes
#     it back into each repo's `unsent`, carried forward to the next sweep.
#     The reason is stashed as `_cluster_errors[<cluster>]`, rides the NEXT
#     successful --emit as `carried_error` plus a severity bump to warn, and
#     --mark-posted clears it.
#   --list-clusters
#     Prints the cluster names, one per line, in sweep order.
#
# Flags shared by every mode:
#   --registry F       boards registry (name path [bridge] [rail=<rail>] ...)
#   --state-file F     digest state (default ~/.cache/backlog-sync/digest-state.json)
#   --cluster-map M    `cluster=rail,cluster=rail`. With a map only the listed
#                      rails are valid and the map order is the sweep order.
#                      Without one, each distinct rail in the registry is its
#                      own cluster, named after the rail.
#   --crit-prefix P    an adopted row whose title starts with P makes the
#                      payload severity `crit` (default: none)
#   --field-cap N      cap on one field value, in UTF-16 units (default 1024)
#
# The payload (stdout of --emit, one JSON line):
#   {cluster, rail, key, severity: info|warn|crit, title, fields: [{name, value}],
#    carried_error?}
# `key` is a content hash of the plain change tuples, so the same set of
# changes always carries the same key (the poster's idempotency key).
#
# stderr: `digest: ...` log lines (ERROR/WARN/parsed/skipped/would-post).
# Exit code: 0 on a normal run. Parse, rail, state, and post problems are
# reported on stderr, never through the exit code, so a digest problem cannot
# flip the sweep's exit code. A usage error (bad flags, missing jq) exits
# non-zero.
set -uo pipefail

MODE="repo"
REPO=""
CLUSTER=""
REASON=""
REGISTRY=""
CLUSTER_MAP=""
CRIT_PREFIX=""
FIELD_CAP="1024"
STATE_FILE="${HOME}/.cache/backlog-sync/digest-state.json"

while [ $# -gt 0 ]; do case "$1" in
  --repo) REPO="$2"; MODE="repo"; shift 2;;
  --emit) MODE="emit"; shift;;
  --mark-posted) MODE="mark-posted"; shift;;
  --mark-failed) MODE="mark-failed"; shift;;
  --list-clusters) MODE="list-clusters"; shift;;
  --cluster) CLUSTER="$2"; shift 2;;
  --cluster-map) CLUSTER_MAP="$2"; shift 2;;
  --crit-prefix) CRIT_PREFIX="$2"; shift 2;;
  --field-cap) FIELD_CAP="$2"; shift 2;;
  --reason) REASON="$2"; shift 2;;
  --reason-file) REASON="$(cat "$2" 2>/dev/null)"; shift 2;;
  --registry) REGISTRY="$2"; shift 2;;
  --state-file) STATE_FILE="$2"; shift 2;;
  *) echo "unknown arg: $1" >&2; exit 64;;
esac; done

command -v jq >/dev/null || { echo "need jq" >&2; exit 1; }
[ -n "$REGISTRY" ] || { echo "need --registry <file>" >&2; exit 64; }

log() { echo "digest: $*" >&2; }

# --- cluster <-> rail ---------------------------------------------------------
# With --cluster-map the pairs are the whole truth. Without it a cluster is its
# rail, so the registry alone decides what exists.
map_pairs() {  # -> "cluster rail" lines
  local pair
  [ -n "$CLUSTER_MAP" ] || return 0
  local IFS=,
  for pair in $CLUSTER_MAP; do
    [ -n "$pair" ] && printf '%s %s\n' "${pair%%=*}" "${pair#*=}"
  done
}

registry_rail_of() {  # <registry-row-rest> -> the rail= token, or empty
  local tok rail=""
  for tok in $1; do case "$tok" in rail=*) rail="${tok#rail=}";; esac; done
  printf '%s' "$rail"
}

valid_rail() {  # <rail>
  [ -n "$1" ] || return 1
  [ -n "$CLUSTER_MAP" ] || return 0
  map_pairs | awk -v r="$1" '$2 == r { found = 1 } END { exit found ? 0 : 1 }'
}

rail_for_cluster() {  # <cluster> -> rail, or empty when unknown
  if [ -n "$CLUSTER_MAP" ]; then
    map_pairs | awk -v c="$1" '$1 == c { print $2; exit }'
  elif [ -n "$(repos_for_rail "$1")" ]; then
    printf '%s\n' "$1"
  fi
}

list_clusters() {
  local name _path rest rail seen=" "
  if [ -n "$CLUSTER_MAP" ]; then
    map_pairs | awk '{ print $1 }'
    return 0
  fi
  [ -f "$REGISTRY" ] || return 0
  while read -r name _path rest; do
    case "$name" in ''|\#*) continue;; esac
    rail="$(registry_rail_of "$rest")"
    [ -n "$rail" ] || continue
    case "$seen" in *" $rail "*) continue;; esac
    seen="$seen$rail "
    printf '%s\n' "$rail"
  done < "$REGISTRY"
}

# --- rail lookup for one repo (scan every trailing token for rail=<name>,
# tolerant of the bridge column and any ordering) ------------------------------
rail_for_repo() {  # <repo>
  local repo="$1" rail="" name _path rest
  [ -f "$REGISTRY" ] || { echo ""; return; }
  while read -r name _path rest; do
    case "$name" in ''|\#*) continue;; esac
    [ "$name" = "$repo" ] || continue
    rail="$(registry_rail_of "$rest")"
    break
  done < "$REGISTRY"
  valid_rail "$rail" && echo "$rail" || echo ""
}

# --- every repo whose registry rail matches <rail> ----------------------------
repos_for_rail() {  # <rail>
  local rail="$1" name _path rest r
  [ -f "$REGISTRY" ] || return 0
  while read -r name _path rest; do
    case "$name" in ''|\#*) continue;; esac
    r="$(registry_rail_of "$rest")"
    valid_rail "$r" || r=""
    [ "$r" = "$rail" ] && echo "$name"
  done < "$REGISTRY"
}

# --- state read/write (jq-driven; tmp + mv -f for a crash-safe write) ---------
state_read() {  # -> stdout: whole state object, "{}" if missing/corrupt
  if [ -f "$STATE_FILE" ] && jq -e . "$STATE_FILE" >/dev/null 2>&1; then
    cat "$STATE_FILE"
  else
    echo "{}"
  fi
}

# macOS ships lockf, Linux ships flock; with neither the write goes unguarded.
with_state_lock() {  # <cmd...>
  if command -v lockf >/dev/null 2>&1; then
    lockf -k -t 30 "$STATE_FILE.lock" "$@"
  elif command -v flock >/dev/null 2>&1; then
    flock -w 30 "$STATE_FILE.lock" "$@"
  else
    "$@"
  fi
}

state_write() {  # <new-json-object-on-stdin> -- merges shallowly over the existing file
  # The state carries upstream error text (_cluster_errors), so the new JSON
  # travels via a 0600 temp file, never argv (macOS shows other users' argv),
  # and the state file itself is written under umask 077 + chmod 600.
  local newf; newf="$(mktemp)"; chmod 600 "$newf"
  cat > "$newf"
  mkdir -p "$(dirname "$STATE_FILE")"
  # Two concurrent --repo runs (or a run racing --mark-posted/--mark-failed)
  # must not clobber each other's read-modify-write.
  with_state_lock bash -c '
    set -u
    umask 077
    state_file="$1" new_file="$2" base="{}"
    if [ -f "$state_file" ] && jq -e . "$state_file" >/dev/null 2>&1; then
      base="$(cat "$state_file")"
    fi
    jq -s ".[0] * .[1]" <(printf "%s" "$base") "$new_file" > "$state_file.tmp" \
      && mv -f "$state_file.tmp" "$state_file" && chmod 600 "$state_file"
  ' _ "$STATE_FILE" "$newf" \
    || log "ERROR(state lock failed) $STATE_FILE"
  rm -f "$newf"
}

# --- Python repr() decoding. describe() wraps a title/item in repr() for the
# three lines that echo free text back (~ spoke ... title ->, ~ board ... item
# ->, + board ... <-). repr() picks single quotes unless the text has an
# apostrophe and no double quote, in which case it switches to double quotes;
# either way this decodes both forms. Ceiling: it does not decode repr's
# control-char escapes (\n, \xNN); board titles are single-line prose.
unrepr() {  # <repr'd-string-with-outer-quotes>
  local s="$1" q="${1:0:1}"
  s="${s:1:${#s}-2}"
  case "$q" in
    \'|\") printf '%s' "$s" | sed -E 's/\\(.)/\1/g';;
    *) printf '%s' "$1";;
  esac
}

# =============================================================================
# --repo: parse one repo's captured stdout into its change set
# =============================================================================
do_repo_mode() {
  [ -n "$REPO" ] || { echo "need --repo <name>" >&2; exit 64; }

  local rail; rail="$(rail_for_repo "$REPO")"

  local state; state="$(state_read)"
  local prev_ids_json unsent_json
  prev_ids_json="$(jq -c --arg r "$REPO" '.[$r].ids // []' <<<"$state")"
  unsent_json="$(jq -c --arg r "$REPO" '.[$r].unsent // []' <<<"$state")"
  if [ -f "$STATE_FILE" ] && ! jq -e . "$STATE_FILE" >/dev/null 2>&1; then
    log "WARN state file corrupt at $STATE_FILE, treating as first sweep"
  elif [ ! -f "$STATE_FILE" ]; then
    log "WARN state file missing at $STATE_FILE, treating as first sweep"
  fi

  local tmp_records; tmp_records="$(mktemp)"
  trap 'rm -f "$tmp_records"' RETURN

  local parse_degraded=0
  emit() {  # kind sub id tostate title
    jq -n -c --arg kind "$1" --arg sub "$2" --arg id "$3" --arg tostate "$4" --arg title "$5" \
      '{kind:$kind, sub:$sub, id:$id, tostate:$tostate, title:$title}' >> "$tmp_records"
  }

  while IFS= read -r line || [ -n "$line" ]; do
    case "$line" in
      ''|'#'*) continue;;
      'WARNING:'*) continue;;
      'dry-run '*|'synced '*) continue;;
      '  (nothing to do)') continue;;  # sync_core.py describe()'s empty-plan literal
    esac
    local sym word rest
    if [[ "$line" =~ ^\ \ ([^[:space:]]+)[[:space:]]+([^[:space:]]+)[[:space:]]+(.*)$ ]]; then
      sym="${BASH_REMATCH[1]}"; word="${BASH_REMATCH[2]}"; rest="${BASH_REMATCH[3]}"
    else
      continue  # not an indented action line
    fi

    case "$sym $word" in
      "+ spoke")
        local id=""
        [[ "$rest" =~ ([A-Z]+-[0-9]+) ]] && id="${BASH_REMATCH[1]}"
        emit created "" "$id" "" "$rest"
        ;;
      "~ spoke")
        local rid="${rest%% *}" tail="${rest#* }"
        if [[ "$tail" =~ ^-\>\ (.+)$ ]]; then
          emit move "" "$rid" "${BASH_REMATCH[1]}" ""
        elif [[ "$tail" =~ ^title\ -\>\ (\'.*\'|\".*\")$ ]]; then
          emit other title-update "$rid" "" "$(unrepr "${BASH_REMATCH[1]}")"
        elif [ "$tail" = "notes updated from board" ]; then
          emit other notes-update "$rid" "" ""
        else
          emit other unknown "$rid" "" ""; parse_degraded=1
        fi
        ;;
      "✓ board")
        local bid="${rest%% *}" tail="${rest#* }"
        if [[ "$tail" =~ ^-\>\ (.+)$ ]]; then
          emit move "" "$bid" "${BASH_REMATCH[1]}" ""
        else
          emit other unknown "$bid" "" ""; parse_degraded=1
        fi
        ;;
      "~ board")
        local bid2="${rest%% *}" tail2="${rest#* }"
        if [[ "$tail2" =~ ^item\ -\>\ (\'.*\'|\".*\")$ ]]; then
          emit other item-edit "$bid2" "" "$(unrepr "${BASH_REMATCH[1]}")"
        else
          emit other unknown "$bid2" "" ""; parse_degraded=1
        fi
        ;;
      "+ board")
        local bid3="${rest%% *}" tail3="${rest#* }"
        if [[ "$tail3" =~ ^\(([^\)]+)\)\ \<-\ (\'.*\'|\".*\")$ ]]; then
          emit adopted "" "$bid3" "${BASH_REMATCH[1]}" "$(unrepr "${BASH_REMATCH[2]}")"
        else
          emit other unknown "$bid3" "" ""; parse_degraded=1
        fi
        ;;
      "⏸ tombstone")
        emit other tombstone "$rest" "" ""
        ;;
      "⤫ app")
        emit other scope-exit "${rest%% *}" "" ""
        ;;
      "↩ app")
        emit other scope-reenter "${rest%% *}" "" ""
        ;;
      "! conflict")
        local cid=""
        [[ "$rest" =~ ([A-Z]+-[0-9]+) ]] && cid="${BASH_REMATCH[1]}"
        emit other conflict "$cid" "" ""
        ;;
      "· note")
        : # explicitly not a change
        ;;
      *)
        local uid=""
        [[ "$rest" =~ ([A-Z]+-[0-9]+) ]] && uid="${BASH_REMATCH[1]}"
        # no id extracted -> pass the raw line as the title fallback (below)
        # so two distinct unrecognized lines never dedup-collide on id="".
        emit other unknown "$uid" "" "$line"; parse_degraded=1
        ;;
    esac
  done

  if [ "$parse_degraded" -eq 1 ]; then
    log "WARN parse-degraded: one or more describe() lines did not match a known kind for $REPO"
  fi

  local digest_json
  digest_json="$(jq -s -c --arg repo "$REPO" --argjson prev_ids "$prev_ids_json" '
    def keyfor:
      if (.kind=="created" or .kind=="adopted") then
        (.kind + "|" + (if .id=="" then .title else .id end))
      else
        (.kind + "|" + .sub + "|" + (if .id=="" then .title else .id end) + "|" + .tostate)
      end;
    ([ .[] ] | group_by(keyfor) | map(.[0]) | sort_by(keyfor)) as $deduped |
    ($deduped | [.[] | select(.id != "") | .id] | unique | sort) as $current_ids |
    ($current_ids | map(select(. as $x | $prev_ids | index($x) != null))) as $flapping_ids |
    {
      created: [ $deduped[] | select(.kind=="created") ],
      adopted: [ $deduped[] | select(.kind=="adopted") ],
      moves:   [ $deduped[] | select(.kind=="move") ],
      others:  [ $deduped[] | select(.kind=="other") ],
      current_ids: $current_ids,
      flapping_ids: $flapping_ids
    }
  ' "$tmp_records")"
  rm -f "$tmp_records"

  local current_ids_json; current_ids_json="$(jq -c '.current_ids' <<<"$digest_json")"
  local n; n="$(jq '[.created,.adopted,.moves,.others] | map(length) | add' <<<"$digest_json")"

  local pending; pending="$(jq -c --arg rail "$rail" --argjson degraded "$([ "$parse_degraded" -eq 1 ] && echo true || echo false)" \
    '. + {rail:$rail, parse_degraded:$degraded}' <<<"$digest_json")"

  jq -n --arg r "$REPO" --argjson ids "$current_ids_json" --argjson pending "$pending" --argjson unsent "$unsent_json" \
    '{($r): {ids:$ids, pending:$pending, unsent:$unsent}}' | state_write

  local unsent_n; unsent_n="$(jq 'length' <<<"$unsent_json")"
  if [ "$n" -eq 0 ] && [ "$unsent_n" -eq 0 ]; then
    log "skipped(no-change) $REPO"
  elif [ -z "$rail" ]; then
    log "ERROR(no rail mapped) $REPO"
  else
    log "parsed $REPO changes=$n rail=$rail"
  fi
}

# =============================================================================
# shared: merge every repo in a cluster's rail into one deduped record set,
# used by --emit (to build the payload) and --mark-failed (to persist it).
# Returns on stdout: {"tuples":[...], "by_repo":{"<repo>":{created,adopted,
# moves,others,flapping_ids}}, "has_crit":bool}
# =============================================================================
merge_cluster() {  # <rail>
  local rail="$1" repo state pending unsent merged_repo repos
  state="$(state_read)"
  repos="$(repos_for_rail "$rail")"

  local acc="{}"
  local tuples_acc="[]"
  local has_crit="false"
  while IFS= read -r repo; do
    [ -n "$repo" ] || continue
    pending="$(jq -c --arg r "$repo" '.[$r].pending // {created:[],adopted:[],moves:[],others:[],flapping_ids:[]}' <<<"$state")"
    unsent="$(jq -c --arg r "$repo" '.[$r].unsent // []' <<<"$state")"
    merged_repo="$(jq -n -c --argjson p "$pending" --argjson u "$unsent" '
      def keyfor:
        if (.kind=="created" or .kind=="adopted") then
          (.kind + "|" + (if .id=="" then .title else .id end))
        else
          (.kind + "|" + .sub + "|" + (if .id=="" then .title else .id end) + "|" + .tostate)
        end;
      (($p.created + $p.adopted + $p.moves + $p.others) + $u) as $all |
      ($all | group_by(keyfor) | map(.[0]) | sort_by(keyfor)) as $deduped |
      {
        created: [ $deduped[] | select(.kind=="created") ],
        adopted: [ $deduped[] | select(.kind=="adopted") ],
        moves:   [ $deduped[] | select(.kind=="move") ],
        others:  [ $deduped[] | select(.kind=="other") ],
        flapping_ids: ($p.flapping_ids // [])
      }
    ')"
    acc="$(jq -c --arg r "$repo" --argjson m "$merged_repo" '.[$r] = $m' <<<"$acc")"
    local repo_tuples; repo_tuples="$(jq -c --arg repo "$repo" '
      [ (.created + .adopted + .moves + .others)[] |
        ($repo + "\t" + .id + "\t" + .kind + (if .sub=="" then "" else ":" + .sub end) + "\t" + .tostate) ]
    ' <<<"$merged_repo")"
    tuples_acc="$(jq -c -n --argjson a "$tuples_acc" --argjson b "$repo_tuples" '$a + $b')"
    local repo_crit
    repo_crit="$(jq -r --arg p "$CRIT_PREFIX" '$p != "" and ([.adopted[] | select(.title | startswith($p))] | length > 0)' <<<"$merged_repo")"
    [ "$repo_crit" = "true" ] && has_crit="true"
  done <<<"$repos"

  jq -c --argjson has_crit "$([ "$has_crit" = "true" ] && echo true || echo false)" \
    --argjson tuples "$(jq -c 'sort' <<<"$tuples_acc")" \
    '{by_repo:., tuples:$tuples, has_crit:$has_crit}' <<<"$acc"
}

# =============================================================================
# ticket-link: wrap each field value's LEADING per-line board-row id
# ([A-Z]+-[0-9]+) in a Discord masked link, `<>`-suppressed so it never
# expands a preview embed. The URL comes from the owning repo's own git remote
# (registry path -> repo root -> `origin`); a repo with no github remote is
# left unlinked, never a broken link. It runs on the already-built display
# TEXT only, after the idempotency key is computed from merge_cluster's plain
# tuples (id/kind/tostate, never title text), so linkification can never
# perturb the content-derived key.
# =============================================================================
registry_path_for() {  # <repo> -> BACKLOG.md path, ~-expanded
  local repo="$1" name path rest
  [ -f "$REGISTRY" ] || return 0
  while read -r name path rest; do
    case "$name" in ''|\#*) continue;; esac
    [ "$name" = "$repo" ] || continue
    printf '%s\n' "${path/#\~/$HOME}"
    return
  done < "$REGISTRY"
}

normalize_github_url() {  # <git-remote-url> -> https://github.com/<owner>/<repo>, or empty
  local remote="$1" rest=""
  case "$remote" in
    git@github.com:*) rest="${remote#git@github.com:}";;
    ssh://git@github.com/*) rest="${remote#ssh://git@github.com/}";;
    https://github.com/*) rest="${remote#https://github.com/}";;
    http://github.com/*) rest="${remote#http://github.com/}";;
    *) return 0;;
  esac
  rest="${rest%.git}"; rest="${rest%/}"
  [ -n "$rest" ] && printf 'https://github.com/%s' "$rest"
}

repo_github_url() {  # <repo> -> https://github.com/<owner>/<repo>, or empty
  local repo="$1" backlog_path repo_root remote url=""
  backlog_path="$(registry_path_for "$repo")"
  if [ -n "$backlog_path" ]; then
    repo_root="$(git -C "$(dirname "$backlog_path")" rev-parse --show-toplevel 2>/dev/null)"
    if [ -n "$repo_root" ]; then
      remote="$(git -C "$repo_root" remote get-url origin 2>/dev/null)"
      [ -n "$remote" ] && url="$(normalize_github_url "$remote")"
    fi
  fi
  printf '%s' "$url"
}

linkify_field_value() {  # <repo> <value> -> value, each line's leading id masked-linked
  local repo="$1" value="$2" url
  url="$(repo_github_url "$repo")"
  [ -n "$url" ] || { printf '%s' "$value"; return; }
  jq -rn --arg v "$value" --arg base "${url}/blob/main/_meta/BACKLOG.md" '
    $v | split("\n") | map(
      sub("^(?<pre>(• )?)(?<id>[A-Z]+-[0-9]+)"; "\(.pre)[\(.id)](<\($base)#:~:text=\(.id)>)")
    ) | join("\n")
  '
}

require_cluster() {  # -> sets RAIL, exits 64 on a missing or unknown cluster
  [ -n "$CLUSTER" ] || { echo "need --cluster <name>" >&2; exit 64; }
  RAIL="$(rail_for_cluster "$CLUSTER")"
  [ -n "$RAIL" ] || { echo "unknown --cluster: $CLUSTER" >&2; exit 64; }
}

# =============================================================================
# --emit: build + print the one payload for a cluster
# =============================================================================
do_emit_mode() {
  require_cluster
  local rail="$RAIL"
  local state; state="$(state_read)"

  local merged; merged="$(merge_cluster "$rail")"
  local tuples_n; tuples_n="$(jq '.tuples | length' <<<"$merged")"
  if [ "$tuples_n" -eq 0 ]; then
    log "skipped(no-change) $CLUSTER"
    return 0
  fi

  local key; key="$(jq -r '.tuples | join("\n")' <<<"$merged" | shasum -a 256 | cut -c1-32)"

  local fields_json; fields_json="$(jq -c '
    def flapsuffix($id; flap): if ($id != "" and (flap | index($id) != null)) then " (FLAPPING)" else "" end;
    def flaplist(f; flap): ([f[] | select(.id != "") | .id] | unique) as $ids |
      ([$ids[] | select(. as $x | flap | index($x) != null)]) as $hit |
      if ($hit | length) > 0 then "; FLAPPING: " + ($hit | join(", ")) else "" end;
    [ .by_repo | to_entries[] |
      . as $e | $e.value as $v | ($v.flapping_ids // []) as $flap |
      {
        repo: $e.key,
        lines: (
          [
            (if ($v.created | length) > 0 then
              "✨ created\n" + ([ $v.created[] | "• " + .title + flapsuffix(.id; $flap) ] | join("\n"))
            else empty end),
            (if ($v.adopted | length) > 0 then
              "📥 adopted\n" + ([ $v.adopted[] | "• " + .id + " · " + .tostate + " · " + .title + flapsuffix(.id; $flap) ] | join("\n"))
            else empty end),
            (if ($v.moves | length) > 0 then
              "🔀 " + (($v.moves | length | tostring) + " status move" + (if ($v.moves|length)==1 then "" else "s" end) + " (" + ([$v.moves[] | select(.tostate=="shipped")] | length | tostring) + " shipped)" + flaplist($v.moves; $flap))
            else empty end),
            (if ($v.others | length) > 0 then
              "✏️ " + (($v.others | length | tostring) + " other change" + (if ($v.others|length)==1 then "" else "s" end) + flaplist($v.others; $flap))
            else empty end)
          ]
        )
      } |
      select(.lines | length > 0) |
      {name: .repo, value: (.lines | join("\n"))}
    ]
  ' <<<"$merged")"

  # ticket-link pass (never touches $key above, computed from $merged's plain
  # tuples, not from this display text).
  if [ "$(jq 'length' <<<"$fields_json")" -gt 0 ]; then
    local linked_fields="[]" field frepo fvalue flinked
    while IFS= read -r field; do
      frepo="$(jq -r '.name' <<<"$field")"
      fvalue="$(jq -r '.value' <<<"$field")"
      flinked="$(linkify_field_value "$frepo" "$fvalue")"
      linked_fields="$(jq -c --argjson acc "$linked_fields" --arg name "$frepo" --arg value "$flinked" \
        '$acc + [{name:$name, value:$value}]' <<<null)"
    done < <(jq -c '.[]' <<<"$fields_json")
    fields_json="$linked_fields"
  fi

  # severity: a crit-prefixed adopted row always wins (content-level truth); a
  # bare carry-forward is a pipeline-level alert (warn); otherwise routine
  # (info). Never touches $key (already fixed from the plain tuples).
  local has_crit; has_crit="$(jq -r '.has_crit' <<<"$merged")"
  local last_error; last_error="$(jq -r --arg c "$CLUSTER" '._cluster_errors[$c] // empty' <<<"$state")"
  local severity="info"
  [ -n "$last_error" ] && severity="warn"
  [ "$has_crit" = "true" ] && severity="crit"
  local title="Board sync · $CLUSTER"

  # Discord caps an embed field's value at 1024, an embed at 6000 total and 25
  # fields; an accumulated digest (29 changes) built a 1662-char value and the
  # whole post 400'd downstream. Cap each field by whole lines with a "+N more"
  # tail, then cap the EMBED (many dirty repos can 400 on the total even with
  # per-field caps). Lengths count UTF-16 units (codepoints + one extra per
  # astral char), Discord's own unit. Display-only: the idempotency key is
  # computed from the plain tuples above, never from this text. A non-numeric
  # --field-cap falls back to 1024.
  local cap="$FIELD_CAP"
  case "$cap" in ''|*[!0-9]*) cap=1024;; esac
  fields_json="$(jq -c --argjson cap "$cap" '
    def ulen($s): ($s | length) + ([$s | explode[] | select(. > 65535)] | length);
    def capped($v): if ulen($v) <= $cap then $v else
      ($v | split("\n")) as $ls |
      (reduce range(0; $ls | length) as $i ({keep: 0, len: 0, stop: 0};
        if .stop == 1 then .
        elif (.len + ulen($ls[$i]) + 1) <= ($cap - 34) then {keep: ($i + 1), len: (.len + ulen($ls[$i]) + 1), stop: 0}
        else .stop = 1 end)) as $a |
      if $a.keep == 0 then
        (($ls[0] | .[:($cap - 40)]) + "\n… +" + ((($ls | length) - 1) | tostring) + " more (see the board)")
      else
        (($ls[:$a.keep] | join("\n")) + "\n… +" + ((($ls | length) - $a.keep) | tostring) + " more (see the board)")
      end end;
    def embed_budget($fs):
      (reduce range(0; $fs | length) as $i ({keep: 0, len: 0, stop: 0};
        if .stop == 1 then .
        elif .keep >= 24 or (.len + ulen($fs[$i].name) + ulen($fs[$i].value)) > 5400 then .stop = 1
        else {keep: ($i + 1), len: (.len + ulen($fs[$i].name) + ulen($fs[$i].value)), stop: 0} end)) as $b |
      if $b.keep >= ($fs | length) then $fs
      else $fs[:$b.keep] + [{name: "…", value: ("+" + ((($fs | length) - $b.keep) | tostring) + " more repos truncated (see the boards)")}]
      end;
    [ .[] | .value = capped(.value) ] | embed_budget(.)' <<<"$fields_json")"

  # Carried-forward reason from a previous failed post (set by --mark-failed
  # --reason, cleared by --mark-posted): it rides the payload as
  # `carried_error`, and a "retry" field marks the post as a retry.
  if [ -n "$last_error" ]; then
    fields_json="$(jq -c '. + [{name:"↻ retry", value:"carried forward after a failed post"}]' <<<"$fields_json")"
  fi

  local payload
  payload="$(jq -n -c --arg cluster "$CLUSTER" --arg rail "$rail" --arg key "$key" \
    --arg severity "$severity" --arg title "$title" --argjson fields "$fields_json" --arg carried "$last_error" \
    '{cluster:$cluster, rail:$rail, key:$key, severity:$severity, title:$title, fields:$fields}
     + (if $carried == "" then {} else {carried_error:$carried} end)')"

  printf '%s\n' "$payload"
  log "would-post $CLUSTER rail=$rail key=$key"
}

# =============================================================================
# --mark-posted / --mark-failed: state mutation after an actual post attempt
# (owned by the poster layer, never by --repo/--emit)
# =============================================================================
do_mark_posted() {
  require_cluster
  local repo repos; repos="$(repos_for_rail "$RAIL")"
  while IFS= read -r repo; do
    [ -n "$repo" ] || continue
    jq -n --arg r "$repo" '{($r): {unsent: []}}' | state_write
  done <<<"$repos"
  jq -n --arg c "$CLUSTER" '{_cluster_errors: {($c): null}}' | state_write
  log "$CLUSTER unsent cleared (posted)"
}

do_mark_failed() {
  require_cluster
  local merged; merged="$(merge_cluster "$RAIL")"
  local repo repos; repos="$(repos_for_rail "$RAIL")"
  while IFS= read -r repo; do
    [ -n "$repo" ] || continue
    local carried; carried="$(jq -c --arg r "$repo" '.by_repo[$r] // {created:[],adopted:[],moves:[],others:[]} | (.created+.adopted+.moves+.others)' <<<"$merged")"
    jq -n --arg r "$repo" --argjson u "$carried" '{($r): {unsent: $u}}' | state_write
  done <<<"$repos"
  [ -n "$REASON" ] && jq -n --arg c "$CLUSTER" --arg r "$REASON" '{_cluster_errors: {($c): $r}}' | state_write
  log "$CLUSTER carried to unsent (post failed)"
}

case "$MODE" in
  repo) do_repo_mode ;;
  emit) do_emit_mode ;;
  mark-posted) do_mark_posted ;;
  mark-failed) do_mark_failed ;;
  list-clusters) list_clusters ;;
esac
