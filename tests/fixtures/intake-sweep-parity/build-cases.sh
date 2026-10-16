#!/usr/bin/env bash
# build-cases.sh -- writes cases.jsonl for the intake-sweep parity test. Each case is one JSON
# line the shared harness (tests/lib/hook-parity.sh) runs: name, env, payload, seed (files
# written first), read (files dumped after), args, touch. The repo root is @CWD@, the state
# dir @HOME@/is. A case named crash-* is one the Python crashed on; the port stages nothing
# there, as the Python shim did.
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
OUT="$HERE/cases.jsonl"
: > "$OUT"

# add <name> <env-json> <seed-json> [read-json] [args-json] [touch-json]
add() {
  local name="$1" env="$2" seed="${3:-}" read="${4:-}" args="${5:-}" touch="${6:-}"
  [ -n "$seed" ] || seed='{}'; [ -n "$read" ] || read='["cwd/_meta/backlog-staging.md","home/is/swept-keys.txt"]'
  [ -n "$args" ] || args='[]'; [ -n "$touch" ] || touch='{}'
  jq -c -n --arg n "$name" --argjson e "$env" --argjson s "$seed" --argjson r "$read" --argjson a "$args" --argjson t "$touch" \
    '{name:$n, env:$e, payload:{hook_event_name:"SessionStart"}, seed:$s, read:$r, args:$a, touch:$t}' >> "$OUT"
}

BASE='"REPO_ROOT":"@CWD@","INTAKE_SWEEP_STATE_DIR":"@HOME@/is"'
E() { printf '{%s%s}' "$BASE" "${1:+,$1}"; }
# seed builder: S key text key text ...
S() { local o='{}'; while [ $# -ge 2 ]; do o=$(jq -c --arg k "$1" --arg v "$2" '.[$k] = $v' <<<"$o"); shift 2; done; printf '%s' "$o"; }

CFG='cwd/_meta/intake-sources.json'
LINKS='cwd/data/links.jsonl'
JS='{"sources":[{"name":"links","kind":"jsonl","path":"data/links.jsonl","map":{"title":"title","url":"url","intent":"note"},"u":"hi","f":"mid","home":"ops"}]}'
L3=$'{"title":"Rust ownership","url":"https://ex.com/rust","note":"learn the borrow checker"}\n{"title":"Pick a DB","url":"https://ex.com/db","note":"compare engines"}\n{"title":"Vietnamese tax","url":"https://ex.com/tax"}\n'

# --- config gate ---
add no-config "$(E)" '{}'
add config-invalid-json "$(E)" "$(S $CFG 'not json')"
add config-list-root "$(E)" "$(S $CFG '[]')"
add config-sources-not-list "$(E)" "$(S $CFG '{"sources":{}}')"
add config-empty-sources "$(E)" "$(S $CFG '{"sources":[]}')"
add config-two-values "$(E)" "$(S $CFG '{"sources":[]} {"sources":[]}')"
add config-env-path "$(E '"INTAKE_SWEEP_CONFIG":"@CWD@/alt.json"')" "$(S cwd/alt.json "$JS" $LINKS "$L3")"
add config-env-empty-uses-default "$(E '"INTAKE_SWEEP_CONFIG":""')" "$(S $CFG "$JS" $LINKS "$L3")"
add config-env-missing-file "$(E '"INTAKE_SWEEP_CONFIG":"@CWD@/nope.json"')" "$(S $CFG "$JS" $LINKS "$L3")"

# --- the jsonl reader ---
add jsonl-basic "$(E)" "$(S $CFG "$JS" $LINKS "$L3")" '["cwd/_meta/backlog-staging.md","home/is/swept-keys.txt","home/is/last-run"]'
add jsonl-include-match "$(E)" "$(S $CFG '{"sources":[{"name":"l","kind":"jsonl","path":"data/links.jsonl","include":{"field":"verdict","equals":"keep"}}]}' $LINKS $'{"title":"A","url":"u1","verdict":"keep"}\n{"title":"B","url":"u2","verdict":"drop"}\n{"title":"C","url":"u3"}\n')"
add jsonl-include-missing-field-equals-empty "$(E)" "$(S $CFG '{"sources":[{"name":"l","kind":"jsonl","path":"data/links.jsonl","include":{"field":"zzz","equals":""}}]}' $LINKS $'{"title":"A","url":"u1"}\n{"title":"B","url":"u2","zzz":"x"}\n')"
add jsonl-include-number-equals "$(E)" "$(S $CFG '{"sources":[{"name":"l","kind":"jsonl","path":"data/links.jsonl","include":{"field":"n","equals":1}}]}' $LINKS $'{"title":"A","url":"u1","n":1}\n{"title":"B","url":"u2","n":2}\n{"title":"C","url":"u3","n":"1"}\n')"
add jsonl-include-empty-object "$(E)" "$(S $CFG '{"sources":[{"name":"l","kind":"jsonl","path":"data/links.jsonl","include":{}}]}' $LINKS $'{"title":"A","url":"u1"}\n')"
add crash-include-string "$(E)" "$(S $CFG '{"sources":[{"name":"l","kind":"jsonl","path":"data/links.jsonl","include":"keep"}]}' $LINKS $'{"title":"A","url":"u1"}\n')"
add jsonl-no-map-defaults "$(E)" "$(S $CFG '{"sources":[{"name":"l","kind":"jsonl","path":"data/links.jsonl"}]}' $LINKS $'{"title":"A","url":"u1","intent":"ignored"}\n')"
add jsonl-map-intent "$(E)" "$(S $CFG '{"sources":[{"name":"l","kind":"jsonl","path":"data/links.jsonl","map":{"title":"t","url":"u","intent":"why"}}]}' $LINKS $'{"t":"Mapped title","u":"https://m.example/x","why":"because"}\n')"
add jsonl-title-falls-back-to-url "$(E)" "$(S $CFG "$JS" $LINKS $'{"title":"   ","url":"https://ex.com/bare"}\n{"url":"https://ex.com/bare2"}\n')"
add jsonl-title-only-no-url "$(E)" "$(S $CFG "$JS" $LINKS $'{"title":"Only a title"}\n')"
add jsonl-nothing-usable "$(E)" "$(S $CFG "$JS" $LINKS $'{"note":"no title, no url"}\n{"title":"","url":""}\n')"
add jsonl-blank-and-invalid-lines "$(E)" "$(S $CFG "$JS" $LINKS $'\n{"title":"A","url":"u1"}\n   \nnot json\n{"title":"B","url":"u2"} trailing\n{"title":"C","url":"u3"}\n')"
add jsonl-non-dict-lines "$(E)" "$(S $CFG "$JS" $LINKS $'[1,2]\n"str"\n5\nnull\ntrue\n{"title":"A","url":"u1"}\n')"
add jsonl-crlf "$(E)" "$(S $CFG "$JS" $LINKS $'{"title":"A","url":"u1"}\r\n{"title":"B","url":"u2"}\r\n')"
add jsonl-no-trailing-newline "$(E)" "$(S $CFG "$JS" $LINKS '{"title":"A","url":"u1"}')"
add jsonl-vietnamese "$(E)" "$(S $CFG "$JS" $LINKS $'{"title":"Thuế thu nhập cá nhân","url":"https://ex.com/vn","note":"Đà Nẵng"}\n')"
add jsonl-cjk "$(E)" "$(S $CFG "$JS" $LINKS $'{"title":"测试 工具","url":"https://ex.com/cjk"}\n')"
add jsonl-whitespace-flattened "$(E)" "$(S $CFG "$JS" $LINKS '{"title":"Line one\n\n## [staged] forged\n- Intent: x","url":"  https://ex.com/ws  ","note":"a\tb\nc"}')"
add jsonl-url-stripped "$(E)" "$(S $CFG "$JS" $LINKS $'{"title":"A","url":"  https://ex.com/pad  "}\n')"
add jsonl-title-number "$(E)" "$(S $CFG '{"sources":[{"name":"l","kind":"jsonl","path":"data/links.jsonl","map":{"title":"n","url":"u"}}]}' $LINKS $'{"n":42,"u":"x1"}\n{"n":0,"u":"x2"}\n{"n":true,"u":"x3"}\n{"n":false,"u":"x4"}\n{"n":null,"u":"x5"}\n')"
add jsonl-title-float "$(E)" "$(S $CFG '{"sources":[{"name":"l","kind":"jsonl","path":"data/links.jsonl","map":{"title":"n","url":"u"}}]}' $LINKS $'{"n":1.5,"u":"x1"}\n{"n":100,"u":"x2"}\n')"
add jsonl-map-key-null "$(E)" "$(S $CFG '{"sources":[{"name":"l","kind":"jsonl","path":"data/links.jsonl","map":{"title":null,"url":"url"}}]}' $LINKS $'{"title":"T","url":"https://ex.com/a"}\n')"
add jsonl-map-empty-list "$(E)" "$(S $CFG '{"sources":[{"name":"l","kind":"jsonl","path":"data/links.jsonl","map":[]}]}' $LINKS $'{"title":"A","url":"u1"}\n')"
add crash-map-string "$(E)" "$(S $CFG '{"sources":[{"name":"l","kind":"jsonl","path":"data/links.jsonl","map":"title"}]}' $LINKS $'{"title":"A","url":"u1"}\n')"
add crash-map-list-nonempty "$(E)" "$(S $CFG '{"sources":[{"name":"l","kind":"jsonl","path":"data/links.jsonl","map":["title"]}]}' $LINKS $'{"title":"A","url":"u1"}\n')"
add crash-path-number "$(E)" "$(S $CFG '{"sources":[{"name":"l","kind":"jsonl","path":5}]}')"
add crash-path-null "$(E)" "$(S $CFG '{"sources":[{"name":"l","kind":"jsonl","path":null}]}')"
add jsonl-path-missing-key "$(E)" "$(S $CFG '{"sources":[{"name":"l","kind":"jsonl"}]}')"
add jsonl-path-missing-file "$(E)" "$(S $CFG '{"sources":[{"name":"l","kind":"jsonl","path":"data/none.jsonl"}]}')"
add jsonl-path-absolute "$(E)" "$(S $CFG '{"sources":[{"name":"l","kind":"jsonl","path":"@HOME@/abs.jsonl"}]}' home/abs.jsonl $'{"title":"Abs","url":"u1"}\n')"
add jsonl-path-is-directory "$(E)" "$(S $CFG '{"sources":[{"name":"l","kind":"jsonl","path":"data"}]}' cwd/data/x.jsonl 'y')"
add jsonl-path-empty "$(E)" "$(S $CFG '{"sources":[{"name":"l","kind":"jsonl","path":""}]}')"
add jsonl-u-f-home-valid "$(E)" "$(S $CFG '{"sources":[{"name":"l","kind":"jsonl","path":"data/links.jsonl","u":"mid","f":"lo","home":"tools/x"}]}' $LINKS $'{"title":"A","url":"u1"}\n')"
add jsonl-u-f-invalid "$(E)" "$(S $CFG '{"sources":[{"name":"l","kind":"jsonl","path":"data/links.jsonl","u":"urgent","f":5,"home":"  spaced \n home "}]}' $LINKS $'{"title":"A","url":"u1"}\n')"
add jsonl-u-f-defaults "$(E)" "$(S $CFG '{"sources":[{"name":"l","kind":"jsonl","path":"data/links.jsonl"}]}' $LINKS $'{"title":"A","url":"u1"}\n')"

# --- source names, kinds, and counts ---
add name-missing "$(E)" "$(S $CFG '{"sources":[{"kind":"jsonl","path":"data/links.jsonl"}]}' $LINKS $'{"title":"A","url":"u1"}\n')"
add name-number "$(E)" "$(S $CFG '{"sources":[{"name":7,"kind":"jsonl","path":"data/links.jsonl"}]}' $LINKS $'{"title":"A","url":"u1"}\n')"
add name-null "$(E)" "$(S $CFG '{"sources":[{"name":null,"kind":"jsonl","path":"data/links.jsonl"}]}' $LINKS $'{"title":"A","url":"u1"}\n')"
add unknown-kind-then-valid "$(E)" "$(S $CFG '{"sources":[{"name":"bad","kind":"rss"},{"name":"ok","kind":"jsonl","path":"data/links.jsonl"}]}' $LINKS $'{"title":"A","url":"u1"}\n')"
add missing-kind "$(E)" "$(S $CFG '{"sources":[{"name":"nokind"}]}')"
add kind-null "$(E)" "$(S $CFG '{"sources":[{"name":"k","kind":null}]}')"
add source-not-object "$(E)" "$(S $CFG '{"sources":["str",5,null,{"name":"ok","kind":"jsonl","path":"data/links.jsonl"}]}' $LINKS $'{"title":"A","url":"u1"}\n')"
add two-sources-counts "$(E)" "$(S $CFG '{"sources":[{"name":"a","kind":"jsonl","path":"data/a.jsonl"},{"name":"b","kind":"jsonl","path":"data/b.jsonl"},{"name":"empty","kind":"jsonl","path":"data/none.jsonl"}]}' cwd/data/a.jsonl $'{"title":"A1","url":"a1"}\n{"title":"A2","url":"a2"}\n' cwd/data/b.jsonl $'{"title":"B1","url":"b1"}\n')"
add two-sources-same-name "$(E)" "$(S $CFG '{"sources":[{"name":"dup","kind":"jsonl","path":"data/a.jsonl"},{"name":"dup","kind":"jsonl","path":"data/b.jsonl"}]}' cwd/data/a.jsonl $'{"title":"A1","url":"a1"}\n{"title":"A2","url":"a2"}\n' cwd/data/b.jsonl $'{"title":"B1","url":"b1"}\n')"
add two-sources-same-item "$(E)" "$(S $CFG '{"sources":[{"name":"a","kind":"jsonl","path":"data/a.jsonl"},{"name":"b","kind":"jsonl","path":"data/b.jsonl"}]}' cwd/data/a.jsonl $'{"title":"Same","url":"https://same"}\n' cwd/data/b.jsonl $'{"title":"Same","url":"https://same"}\n')"

# --- dedup ---
BOARD=$'# Board\n\n| ID | Item | Notes | Status |\n|---|---|---|---|\n| ID-1 | Rust ownership | see https://notes.example/r | queued |\n| ID-2 | Thuế thu nhập cá nhân | | shipped |\n| ID-3 | Plain | x | queued |\n'
add dup-board-title "$(E)" "$(S $CFG "$JS" $LINKS "$L3" cwd/_meta/BACKLOG.md "$BOARD")"
add dup-board-title-case "$(E)" "$(S $CFG "$JS" $LINKS $'{"title":"RUST  OWNERSHIP!","url":"u1"}\n{"title":"THUẾ THU NHẬP CÁ NHÂN","url":"u2"}\n' cwd/_meta/BACKLOG.md "$BOARD")"
add dup-board-row-without-id "$(E)" "$(S $CFG "$JS" $LINKS $'{"title":"Not a row","url":"u1"}\n' cwd/_meta/BACKLOG.md $'| Not a row | x |\n| ID | Not a row | x |\n')"
add dup-board-url-in-notes "$(E)" "$(S $CFG "$JS" $LINKS $'{"title":"Renamed row","url":"https://notes.example/r"}\n' cwd/_meta/BACKLOG.md "$BOARD")"
add dup-board-url-is-substring "$(E)" "$(S $CFG "$JS" $LINKS $'{"title":"Short url","url":"https://notes.example"}\n' cwd/_meta/BACKLOG.md "$BOARD")"
STG=$'# Backlog staging\n\n## [staged] Pick a DB\n- Intent: x\n- Source: s\n\n## [rejected] Old idea\n- Intent: y\n\n## [promoted ID-9] Shipped one\n- Source: https://ex.com/shipped\n\n'
add dup-staging-staged "$(E)" "$(S $CFG "$JS" $LINKS "$L3" cwd/_meta/backlog-staging.md "$STG")"
add dup-staging-rejected-and-promoted "$(E)" "$(S $CFG "$JS" $LINKS $'{"title":"old idea","url":"u1"}\n{"title":"Shipped one","url":"u2"}\n{"title":"New","url":"https://ex.com/shipped"}\n' cwd/_meta/backlog-staging.md "$STG")"
add dup-staging-heading-without-title "$(E)" "$(S $CFG "$JS" $LINKS $'{"title":"Intent x","url":"u1"}\n{"title":"Other","url":"u2"}\n' cwd/_meta/backlog-staging.md $'## [staged]\n- Intent: x\n\n')"
add dup-staging-heading-spaces-only "$(E)" "$(S $CFG "$JS" $LINKS $'{"title":"A","url":"u1"}\n' cwd/_meta/backlog-staging.md $'## [staged]   \n\n')"
add dup-staging-punctuation-title "$(E)" "$(S $CFG "$JS" $LINKS $'{"title":"???","url":"u1"}\n{"title":"Fine","url":"u2"}\n' cwd/_meta/backlog-staging.md $'## [staged] !!!\n\n')"
add dup-staging-crlf "$(E)" "$(S $CFG "$JS" $LINKS $'{"title":"CRLF title","url":"u1"}\n' cwd/_meta/backlog-staging.md $'## [staged] CRLF title\r\n- Intent: x\r\n')"
add dup-swept-url "$(E)" "$(S $CFG "$JS" $LINKS "$L3" home/is/swept-keys.txt $'https://ex.com/rust\n')"
add dup-swept-title-key "$(E)" "$(S $CFG "$JS" $LINKS $'{"title":"No Url Item"}\n{"title":"Other"}\n' home/is/swept-keys.txt $'no url item\n')"
add dup-swept-blank-line "$(E)" "$(S $CFG "$JS" $LINKS $'{"title":"A","url":"u1"}\n' home/is/swept-keys.txt $'\n')"
add dup-within-batch-title "$(E)" "$(S $CFG "$JS" $LINKS $'{"title":"Same Title","url":"u1"}\n{"title":"same title","url":"u2"}\n')"
add dup-within-batch-url "$(E)" "$(S $CFG "$JS" $LINKS $'{"title":"One","url":"https://same"}\n{"title":"Two","url":"https://same"}\n')"
add dup-url-substring-of-earlier "$(E)" "$(S $CFG "$JS" $LINKS $'{"title":"A","url":"https://ex.com/abc"}\n{"title":"B","url":"https://ex.com/ab"}\n')"

# --- where the files live ---
add staging-env-override "$(E '"BACKLOG_STAGE_STAGING":"@CWD@/out/stage.md"')" "$(S $CFG "$JS" $LINKS "$L3")" '["cwd/out/stage.md","home/is/swept-keys.txt"]'
add backlog-env-override "$(E '"BACKLOG_STAGE_BACKLOG":"@CWD@/other-board.md"')" "$(S $CFG "$JS" $LINKS "$L3" cwd/other-board.md "$BOARD")"
add backlog-env-empty "$(E '"BACKLOG_STAGE_BACKLOG":""')" "$(S $CFG "$JS" $LINKS "$L3" cwd/_meta/BACKLOG.md "$BOARD")"
add crash-staging-relative "$(E '"BACKLOG_STAGE_STAGING":"stage.md"')" "$(S $CFG "$JS" $LINKS "$L3")" '["cwd/stage.md","home/is/swept-keys.txt"]'
add crash-staging-empty "$(E '"BACKLOG_STAGE_STAGING":""')" "$(S $CFG "$JS" $LINKS "$L3")" '["home/is/swept-keys.txt"]'
add staging-append-existing "$(E)" "$(S $CFG "$JS" $LINKS "$L3" cwd/_meta/backlog-staging.md $'# Mine\n\n## [staged] Earlier\n- Intent: e\n\n')"
add staging-dir-is-a-file "$(E '"BACKLOG_STAGE_STAGING":"@CWD@/notadir/stage.md"')" "$(S $CFG "$JS" $LINKS "$L3" cwd/notadir 'x')" '["home/is/swept-keys.txt"]'
add staging-is-a-directory "$(E)" "$(S $CFG "$JS" $LINKS "$L3" cwd/_meta/backlog-staging.md/x 'y')" '["home/is/swept-keys.txt"]'
add root-from-cwd-fallback '{"INTAKE_SWEEP_STATE_DIR":"@HOME@/is"}' "$(S $CFG "$JS" $LINKS "$L3")"
add root-from-git '{"INTAKE_SWEEP_STATE_DIR":"@HOME@/is"}' "$(S $CFG "$JS" $LINKS "$L3" cwd/.git/HEAD $'ref: refs/heads/main\n' cwd/.git/objects/.keep '' cwd/.git/refs/.keep '')"
add root-env-empty-falls-back '{"REPO_ROOT":"","INTAKE_SWEEP_STATE_DIR":"@HOME@/is"}' "$(S $CFG "$JS" $LINKS "$L3")"

# --- the command reader ---
CMDJS() { printf '{"sources":[{"name":"cmd","kind":"command","command":%s,"map":{"title":"title","url":"url"}%s}]}' "$(jq -n --arg c "$1" '$c')" "${2:+,$2}"; }
EMIT='#!/bin/sh
printf '"'"'[{"title":"From cmd","url":"https://ex.com/cmd"},{"title":"Second","url":"https://ex.com/cmd2"},"skip me",5]'"'"'
'
add command-basic "$(E)" "$(S $CFG "$(CMDJS 'bash src/emit.sh')" cwd/src/emit.sh "$EMIT")"
add command-relative-exec "$(E)" "$(S $CFG "$(CMDJS 'bin/emit sub --flag')" cwd/bin/emit "$EMIT")"
add command-runs-in-root "$(E)" "$(S $CFG "$(CMDJS 'bash src/pwd.sh')" cwd/src/pwd.sh $'#!/bin/sh\nprintf \'[{"title":"%s","url":"u1"}]\' "$(pwd -P | sed "s|.*/||")"\n')"
add command-quoted-args "$(E)" "$(S $CFG "$(CMDJS "bash src/args.sh 'two words' \"dq arg\" plain")" cwd/src/args.sh $'#!/bin/sh\nprintf \'[{"title":"%s","url":"%s"}]\' "$1" "$2"\n')"
add command-nonzero-exit "$(E)" "$(S $CFG "$(CMDJS 'bash src/fail.sh')" cwd/src/fail.sh $'#!/bin/sh\nprintf \'[{"title":"X","url":"u"}]\'\nexit 3\n')"
add command-empty-stdout "$(E)" "$(S $CFG "$(CMDJS 'bash src/none.sh')" cwd/src/none.sh $'#!/bin/sh\ntrue\n')"
add command-stdout-object "$(E)" "$(S $CFG "$(CMDJS 'bash src/obj.sh')" cwd/src/obj.sh $'#!/bin/sh\nprintf \'{"title":"X"}\'\n')"
add command-stdout-invalid "$(E)" "$(S $CFG "$(CMDJS 'bash src/bad.sh')" cwd/src/bad.sh $'#!/bin/sh\nprintf \'not json\'\n')"
add command-stdout-two-values "$(E)" "$(S $CFG "$(CMDJS 'bash src/two.sh')" cwd/src/two.sh $'#!/bin/sh\nprintf \'[] []\'\n')"
add command-missing-binary "$(E)" "$(S $CFG "$(CMDJS 'no-such-binary-xyz arg')")"
add command-empty "$(E)" "$(S $CFG '{"sources":[{"name":"c","kind":"command","command":""}]}')"
add command-missing-key "$(E)" "$(S $CFG '{"sources":[{"name":"c","kind":"command"}]}')"
add crash-command-number "$(E)" "$(S $CFG '{"sources":[{"name":"c","kind":"command","command":5}]}')"
add crash-command-unbalanced-quote "$(E)" "$(S $CFG "$(CMDJS "bash -c 'unterminated")")"
add crash-command-trailing-backslash "$(E)" "$(S $CFG "$(CMDJS 'bash x\')")"
add crash-command-blank "$(E)" "$(S $CFG "$(CMDJS '   ')")"
add crash-after-good-source "$(E)" "$(S $CFG '{"sources":[{"name":"ok","kind":"jsonl","path":"data/links.jsonl"},{"name":"bad","kind":"command","command":"x '"'"'y"}]}' $LINKS $'{"title":"A","url":"u1"}\n')"
add command-empty-string-argv0 "$(E)" "$(S $CFG "$(CMDJS "'' arg")")"
add command-timeout-kills "$(E '"INTAKE_SWEEP_CMD_TIMEOUT":"1"')" "$(S $CFG "$(CMDJS 'bash src/slow.sh')" cwd/src/slow.sh $'#!/bin/sh\nsleep 4\nprintf \'[{"title":"Late","url":"u"}]\'\n')"
add command-timeout-env-invalid "$(E '"INTAKE_SWEEP_CMD_TIMEOUT":"abc"')" "$(S $CFG "$(CMDJS 'bash src/emit.sh')" cwd/src/emit.sh "$EMIT")"
add command-timeout-env-zero "$(E '"INTAKE_SWEEP_CMD_TIMEOUT":"0"')" "$(S $CFG "$(CMDJS 'bash src/emit.sh')" cwd/src/emit.sh "$EMIT")"
add command-timeout-env-padded "$(E '"INTAKE_SWEEP_CMD_TIMEOUT":" 5 "')" "$(S $CFG "$(CMDJS 'bash src/emit.sh')" cwd/src/emit.sh "$EMIT")"
add command-with-include-ignored "$(E)" "$(S $CFG "$(CMDJS 'bash src/emit.sh' '"include":{"field":"x","equals":"y"}')" cwd/src/emit.sh "$EMIT")"

# --- the throttle ---
add throttle-fresh-stamp "$(E)" "$(S $CFG "$JS" $LINKS "$L3" home/is/last-run '')" '["cwd/_meta/backlog-staging.md","home/is/swept-keys.txt","home/is/last-run"]'
add throttle-old-stamp "$(E)" "$(S $CFG "$JS" $LINKS "$L3" home/is/last-run '')" '["cwd/_meta/backlog-staging.md","home/is/last-run"]' '[]' '{"home/is/last-run":1500000000}'
add throttle-force-flag "$(E)" "$(S $CFG "$JS" $LINKS "$L3" home/is/last-run '')" '["cwd/_meta/backlog-staging.md"]' '["--force"]'
add throttle-interval-zero "$(E '"INTAKE_SWEEP_MIN_INTERVAL":"0"')" "$(S $CFG "$JS" $LINKS "$L3" home/is/last-run '')" '["cwd/_meta/backlog-staging.md"]'
add throttle-interval-zero-no-stamp "$(E '"INTAKE_SWEEP_MIN_INTERVAL":"0"')" "$(S $CFG "$JS" $LINKS "$L3")" '["cwd/_meta/backlog-staging.md"]'
add throttle-interval-negative "$(E '"INTAKE_SWEEP_MIN_INTERVAL":"-5"')" "$(S $CFG "$JS" $LINKS "$L3" home/is/last-run '')" '["cwd/_meta/backlog-staging.md"]'
add throttle-interval-invalid "$(E '"INTAKE_SWEEP_MIN_INTERVAL":"abc"')" "$(S $CFG "$JS" $LINKS "$L3" home/is/last-run '')" '["cwd/_meta/backlog-staging.md"]'
add throttle-interval-float "$(E '"INTAKE_SWEEP_MIN_INTERVAL":"3.5"')" "$(S $CFG "$JS" $LINKS "$L3" home/is/last-run '')" '["cwd/_meta/backlog-staging.md"]'
add throttle-interval-padded "$(E '"INTAKE_SWEEP_MIN_INTERVAL":" 60 "')" "$(S $CFG "$JS" $LINKS "$L3" home/is/last-run '')" '["cwd/_meta/backlog-staging.md"]'
add throttle-interval-small-old-stamp "$(E '"INTAKE_SWEEP_MIN_INTERVAL":"60"')" "$(S $CFG "$JS" $LINKS "$L3" home/is/last-run '')" '["cwd/_meta/backlog-staging.md"]' '[]' '{"home/is/last-run":1700000000}'
add throttle-stamp-is-directory "$(E)" "$(S $CFG "$JS" $LINKS "$L3" home/is/last-run/x 'y')" '["cwd/_meta/backlog-staging.md","home/is/swept-keys.txt"]'
add throttle-no-sources-leaves-no-stamp "$(E)" "$(S $CFG '{"sources":[]}')" '["home/is/last-run"]'
add state-dir-default '{"REPO_ROOT":"@CWD@"}' "$(S $CFG "$JS" $LINKS "$L3")" '["cwd/_meta/backlog-staging.md","home/.claude/dwarves-kit/state/intake-sweep/swept-keys.txt","home/.claude/dwarves-kit/state/intake-sweep/last-run"]'
add state-dir-empty '{"REPO_ROOT":"@CWD@","INTAKE_SWEEP_STATE_DIR":""}' "$(S $CFG "$JS" $LINKS "$L3")" '["cwd/_meta/backlog-staging.md","cwd/swept-keys.txt","cwd/last-run"]'
add state-dir-is-a-file "$(E '"INTAKE_SWEEP_STATE_DIR":"@HOME@/f/is"')" "$(S $CFG "$JS" $LINKS "$L3" home/f 'x')" '["cwd/_meta/backlog-staging.md"]'
add swept-keys-appended "$(E)" "$(S $CFG "$JS" $LINKS "$L3" home/is/swept-keys.txt $'earlier key\n')" '["cwd/_meta/backlog-staging.md","home/is/swept-keys.txt"]'

# --- --check ---
add check-no-sources "$(E)" '{}' '[]' '["--check"]'
add check-basic "$(E)" "$(S $CFG "$JS" $LINKS "$L3")" '["home/is/last-run","cwd/_meta/backlog-staging.md"]' '["--check"]'
add check-zero-items "$(E)" "$(S $CFG "$JS" $LINKS $'not json\n')" '[]' '["--check"]'
add check-missing-file "$(E)" "$(S $CFG "$JS")" '[]' '["--check"]'
add check-unknown-kind "$(E)" "$(S $CFG '{"sources":[{"name":"x","kind":"rss"},{"name":"ok","kind":"jsonl","path":"data/links.jsonl"}]}' $LINKS "$L3")" '[]' '["--check"]'
add check-non-object "$(E)" "$(S $CFG '{"sources":["s",{"name":"ok","kind":"jsonl","path":"data/links.jsonl"}]}' $LINKS "$L3")" '[]' '["--check"]'
add check-titled-and-url-counts "$(E)" "$(S $CFG "$JS" $LINKS $'{"title":"A"}\n{"url":"u"}\n{"title":" ","url":" "}\n{"title":"B","url":"u2"}\n')" '[]' '["--check"]'
add check-command-source "$(E)" "$(S $CFG "$(CMDJS 'bash src/emit.sh')" cwd/src/emit.sh "$EMIT")" '[]' '["--check"]'
add check-ignores-throttle "$(E)" "$(S $CFG "$JS" $LINKS "$L3" home/is/last-run '')" '["cwd/_meta/backlog-staging.md"]' '["--check"]'
add check-with-config-env "$(E '"INTAKE_SWEEP_CONFIG":"@CWD@/alt.json"')" '{}' '[]' '["--check"]'
add crash-check-map-string "$(E)" "$(S $CFG '{"sources":[{"name":"ok","kind":"jsonl","path":"data/links.jsonl"},{"name":"l","kind":"jsonl","path":"data/links.jsonl","map":"x"}]}' $LINKS "$L3")" '[]' '["--check"]'
add args-ignored-unknown "$(E)" "$(S $CFG "$JS" $LINKS "$L3")" '["cwd/_meta/backlog-staging.md"]' '["--whatever"]'

# --- found by the fresh review ---
add include-string-on-empty-file-then-good-source "$(E)" "$(S $CFG '{"sources":[{"name":"typo","kind":"jsonl","path":"data/empty.jsonl","include":"keep"},{"name":"ok","kind":"jsonl","path":"data/links.jsonl"}]}' cwd/data/empty.jsonl '' $LINKS $'{"title":"A","url":"u1"}\n')"
add include-string-on-non-object-lines-only "$(E)" "$(S $CFG '{"sources":[{"name":"typo","kind":"jsonl","path":"data/x.jsonl","include":"keep"},{"name":"ok","kind":"jsonl","path":"data/links.jsonl"}]}' cwd/data/x.jsonl $'[1]\n"s"\n' $LINKS $'{"title":"A","url":"u1"}\n')"
add include-string-check-on-empty-file "$(E)" "$(S $CFG '{"sources":[{"name":"typo","kind":"jsonl","path":"data/empty.jsonl","include":"keep"}]}' cwd/data/empty.jsonl '')" '[]' '["--check"]'
add include-false-is-no-filter "$(E)" "$(S $CFG '{"sources":[{"name":"l","kind":"jsonl","path":"data/links.jsonl","include":false}]}' $LINKS $'{"title":"A","url":"u1"}\n')"
add crash-kind-list-after-good-source "$(E)" "$(S $CFG '{"sources":[{"name":"ok","kind":"jsonl","path":"data/links.jsonl"},{"name":"z","kind":["jsonl"]}]}' $LINKS $'{"title":"A","url":"u1"}\n')"
add crash-name-list "$(E)" "$(S $CFG '{"sources":[{"name":["x"],"kind":"jsonl","path":"data/links.jsonl"}]}' $LINKS $'{"title":"A","url":"u1"}\n')"
add crash-map-key-list "$(E)" "$(S $CFG '{"sources":[{"name":"l","kind":"jsonl","path":"data/links.jsonl","map":{"title":["t"]}}]}' $LINKS $'{"title":"A","url":"u1"}\n')"
add map-key-list-no-items-is-fine "$(E)" "$(S $CFG '{"sources":[{"name":"l","kind":"jsonl","path":"data/links.jsonl","map":{"title":["t"]}}]}' $LINKS '')"
add crash-include-field-list "$(E)" "$(S $CFG '{"sources":[{"name":"l","kind":"jsonl","path":"data/links.jsonl","include":{"field":["v"],"equals":"x"}}]}' $LINKS $'{"title":"A","url":"u1"}\n')"
add config-bom-is-no-config "$(E)" "$(S $CFG "$(printf '\xef\xbb\xbf')$JS" $LINKS "$L3")"
add jsonl-bom-first-line-skipped "$(E)" "$(S $CFG "$JS" $LINKS "$(printf '\xef\xbb\xbf')"$'{"title":"First","url":"u1"}\n{"title":"Second","url":"u2"}\n')"
add crash-jsonl-invalid-utf8 "$(E)" "$(S $CFG "$JS" $LINKS "$(printf '{"title":"A","url":"u1"}\n{"title":"bad \xff byte","url":"u2"}\n')")"
add throttle-interval-huge "$(E '"INTAKE_SWEEP_MIN_INTERVAL":"99999999999999999999999"')" "$(S $CFG "$JS" $LINKS "$L3" home/is/last-run '')" '["cwd/_meta/backlog-staging.md"]'
add throttle-interval-plus-sign "$(E '"INTAKE_SWEEP_MIN_INTERVAL":"+60"')" "$(S $CFG "$JS" $LINKS "$L3" home/is/last-run '')" '["cwd/_meta/backlog-staging.md"]'
add root-trailing-slash '{"REPO_ROOT":"@CWD@/","INTAKE_SWEEP_STATE_DIR":"@HOME@/is"}' "$(S $CFG "$JS" $LINKS "$L3")"
add root-trailing-slash-check '{"REPO_ROOT":"@CWD@/","INTAKE_SWEEP_STATE_DIR":"@HOME@/is"}' '{}' '[]' '["--check"]'
add swept-keys-crlf "$(E)" "$(S $CFG "$JS" $LINKS "$L3" home/is/swept-keys.txt $'https://ex.com/rust\r\nhttps://ex.com/db\r\n')"
add swept-keys-vt-ff-nel "$(E)" "$(S $CFG "$JS" $LINKS "$L3" home/is/swept-keys.txt $'https://ex.com/rust\x0bhttps://ex.com/db\x0c')"
add board-cr-line-breaks "$(E)" "$(S $CFG "$JS" $LINKS "$L3" cwd/_meta/BACKLOG.md $'| ID-1 | Rust ownership | n |\r| ID-2 | Pick a DB | n |\r')"
add board-vt-line-breaks "$(E)" "$(S $CFG "$JS" $LINKS "$L3" cwd/_meta/BACKLOG.md $'| ID-1 | Rust ownership | n |\x0b| ID-2 | Pick a DB | n |\x0c')"
add staging-cr-line-breaks "$(E)" "$(S $CFG "$JS" $LINKS "$L3" cwd/_meta/backlog-staging.md $'## [staged] Rust ownership\r- Intent: x\r## [staged] Pick a DB\r')"
add url-found-across-cr-in-board "$(E)" "$(S $CFG "$JS" $LINKS $'{"title":"Fresh","url":"https://ex.com/seen"}\n' cwd/_meta/BACKLOG.md $'| ID-1 | Other | https://ex.com/seen |\r')"
add command-blank-with-invalid-timeout-is-silent "$(E '"INTAKE_SWEEP_CMD_TIMEOUT":"abc"')" "$(S $CFG "$(CMDJS '   ')")"
add command-stdout-bom-no-items "$(E)" "$(S $CFG "$(CMDJS 'bash src/bom.sh')" cwd/src/bom.sh $'#!/bin/sh\nprintf \'\\357\\273\\277[{"title":"X","url":"u"}]\'\n')"
add command-stdout-invalid-utf8-no-items "$(E)" "$(S $CFG "$(CMDJS 'bash src/bad8.sh')" cwd/src/bad8.sh $'#!/bin/sh\nprintf \'[{"title":"bad \\377","url":"u"}]\'\n')"
add command-timeout-negative-no-items "$(E '"INTAKE_SWEEP_CMD_TIMEOUT":"-3"')" "$(S $CFG "$(CMDJS 'bash src/emit.sh')" cwd/src/emit.sh "$EMIT")"
add command-argv0-with-slash-joined-to-root-trailing-slash '{"REPO_ROOT":"@CWD@/","INTAKE_SWEEP_STATE_DIR":"@HOME@/is"}' "$(S $CFG "$(CMDJS 'bin/emit sub')" cwd/bin/emit "$EMIT")"
echo "wrote $(wc -l < "$OUT" | tr -d ' ') cases"
