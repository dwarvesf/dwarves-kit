#!/usr/bin/env bash
# Over-test for the render skill (SPEC-128 test plan): trigger-fires, queries-via-02
# (mocked JSON in, formatted surface out, no re-read), both surfaces, and the
# load-bearing single-data-path negative control. render.py is pure (no I/O, no
# imports from materialize/adapters/duckdb) so most cases run against a hand-written
# fixture, no live ledgers, no DuckDB rebuild needed.
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT" || exit 1

PASS=0; FAIL=0
ok()   { printf 'PASS  %s\n' "$1"; PASS=$((PASS+1)); }
bad()  { printf 'FAIL  %s\n' "$1"; FAIL=$((FAIL+1)); }
has()  { case "$3" in *"$2"*) ok "$1";; *) bad "$1 (missing: $2)";; esac; }
hasnt(){ case "$3" in *"$2"*) bad "$1 (unexpected: $2)";; *) ok "$1";; esac; }

SKILL="skill/SKILL.md"

echo "== R-trigger: the frontmatter description carries the required trigger phrases =="
DESC="$(awk '/^description:/{f=1} f{print} /^---$/ && f && NR>2{exit}' "$SKILL" | head -1)"
# frontmatter is single-line YAML (name: / description: / --- close); pull the raw file
# instead so a wrapped description still matches.
RAW="$(sed -n '1,/^---$/p' "$SKILL" | sed -n '2,$p')"
has "R-trigger 'show me the ledger state'" 'show me the ledger state' "$RAW"
has "R-trigger 'my debt'"                  'my debt'                  "$RAW"
has "R-trigger 'telemetry'"                'telemetry'                "$RAW"
has "R-trigger 'token cost'"               'token cost'               "$RAW"
has "R-trigger NOT-case present"           'NOT for'                  "$RAW"

# Regression guard: the frontmatter must actually PARSE as YAML, not just grep-match.
# An earlier draft had an unquoted colon ("bot-reply-formatting: tables") inside the
# description value, which is a valid-looking grep target but breaks the YAML scanner
# outright (a skill with unparseable frontmatter cannot load at all) -- caught in
# self-review, not by the grep checks above, so it earns its own assertion.
YAML_CHECK="$(uv run --with pyyaml python3 - "$SKILL" <<'PY' 2>&1
import sys, yaml
text = open(sys.argv[1]).read()
fm = text.split('---')[1]
data = yaml.safe_load(fm)
assert isinstance(data, dict) and 'name' in data and 'description' in data
print("YAML_PARSE_OK")
PY
)"
has "R-trigger frontmatter parses as valid YAML" 'YAML_PARSE_OK' "$YAML_CHECK"

echo "== R-queries-via-02: mocked --json input in, formatted surface out, no re-read =="
# render.py imports nothing from materialize/adapters/duckdb -- assert that structurally
# (a re-read would show up as one of these imports), then exercise it with a MOCKED
# ledger-query-shaped JSON blob (this is literally the `--json` output shape).
RENDER_PY="src/stats/render.py"
hasnt "R-queries-via-02 no materialize import" 'import materialize' "$(cat "$RENDER_PY")"
hasnt "R-queries-via-02 no adapters import"    'import adapters'    "$(cat "$RENDER_PY")"
hasnt "R-queries-via-02 no duckdb import"      'import duckdb'      "$(cat "$RENDER_PY")"

MOCK_OUT="$(uv run python3 - <<'PY'
import json
from stats import render

# A mocked `ledger query --json` output: exactly the shape the real CLI emits.
mocked_json = '[{"rid": "fixture-rid-001", "lane": "normal", "gates_ran": 4}]'
rows = json.loads(mocked_json)

term = render.render_terminal(rows, "mocked")
art = render.render_artifact(rows, "mocked")
print("TERM_OK" if "fixture-rid-001" in term else "TERM_FAIL")
print("ART_OK" if "fixture-rid-001" in art else "ART_FAIL")
PY
)"
has "R-queries-via-02 terminal formatted from mocked json" 'TERM_OK' "$MOCK_OUT"
has "R-queries-via-02 artifact formatted from mocked json" 'ART_OK'  "$MOCK_OUT"

echo "== R-terminal: bot-reply-formatting-shaped code-block table/bar surface =="
TERM_OUT="$(uv run python3 - <<'PY'
from stats import render
rows = [
    {"lane": "normal", "success_pct": 85},
    {"lane": "full", "success_pct": 12},
]
print(render.render_terminal(rows, "Lane success"))
print("---EMPTY---")
print(render.render_terminal([], "Nothing"))
PY
)"
has "R-terminal fenced code block"      '```' "$TERM_OUT"
has "R-terminal has bold title"         '**Lane success**' "$TERM_OUT"
has "R-terminal right-aligned bar-fill" '▓▓▓▓▓▓▓▓░░' "$TERM_OUT"
has "R-terminal row count footer"       '(2 rows)' "$TERM_OUT"
has "R-terminal empty-rows placeholder" '(0 rows)' "$TERM_OUT"

echo "== R-artifact: valid self-contained Artifact HTML =="
ART_OUT="$(uv run python3 - <<'PY'
from stats import render
rows = [{"item": "a <script>alert(1)</script> value", "status": "queued"}]
print(render.render_artifact(rows, "XSS check"))
PY
)"
has "R-artifact doctype"           '<!doctype html>' "$ART_OUT"
has "R-artifact inline style"      '<style>' "$ART_OUT"
hasnt "R-artifact no external script" '<script src=' "$ART_OUT"
hasnt "R-artifact no external link"   '<link href="http' "$ART_OUT"
has "R-artifact dark-mode aware"   'prefers-color-scheme' "$ART_OUT"
has "R-artifact table present"     '<table>' "$ART_OUT"
has "R-artifact escapes a raw tag" '&lt;script&gt;' "$ART_OUT"
hasnt "R-artifact does not leak raw script tag" '<script>alert(1)</script>' "$ART_OUT"

echo "== R-nc: single-data-path negative control (SAME rows object, both surfaces) =="
NC_OUT="$(uv run python3 - <<'PY'
from stats import render

# ONE row set (as if freshly fetched from `ledger query --json`).
rows = [{"rid": "nc-fixture-777", "cost_usd": 4.2}]

term = render.render_terminal(rows, "NC")
art = render.render_artifact(rows, "NC")
same_value_both = ("nc-fixture-777" in term) and ("nc-fixture-777" in art)
print("SAME_VALUE_BOTH_OK" if same_value_both else "SAME_VALUE_BOTH_FAIL")

# Mutate the SAME object and re-render both -- if a formatter cached/derived from a
# second source, the mutation would not show up. It must show up in BOTH.
rows[0]["rid"] = "nc-fixture-mutated-999"
term2 = render.render_terminal(rows, "NC")
art2 = render.render_artifact(rows, "NC")
mutation_both = ("nc-fixture-mutated-999" in term2) and ("nc-fixture-mutated-999" in art2)
print("MUTATION_REFLECTED_BOTH_OK" if mutation_both else "MUTATION_REFLECTED_BOTH_FAIL")

no_stale = ("nc-fixture-777" not in term2) and ("nc-fixture-777" not in art2)
print("NO_STALE_VALUE_OK" if no_stale else "NO_STALE_VALUE_FAIL")
PY
)"
has "R-nc same fixture value in both surfaces"     'SAME_VALUE_BOTH_OK'       "$NC_OUT"
has "R-nc a mutation reflects in both surfaces"    'MUTATION_REFLECTED_BOTH_OK' "$NC_OUT"
has "R-nc no stale value survives the mutation"    'NO_STALE_VALUE_OK'        "$NC_OUT"

echo "== R-cli: the ledger render subcommand wires to the SAME materialize read path =="
CLI_PY="src/stats/cli.py"
has "R-cli render command present"        'def render(' "$(cat "$CLI_PY")"
has "R-cli reuses materialize.show"       'materialize.show' "$(cat "$CLI_PY")"
has "R-cli reuses materialize.query"      'materialize.query' "$(cat "$CLI_PY")"

echo ""
echo "== $PASS passed, $FAIL failed =="
[ "$FAIL" -eq 0 ]
