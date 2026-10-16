#!/usr/bin/env bash
# gen-expected.sh -- regenerate the goldens for tests/test-staging-format-jq.sh from the Python
# originals: lib/reflect/staging-format.py (norm, render_block, existing_keys) and the stdlib
# shlex.split that lib/reflect/shlex-split.sh reproduces. Dev-time only; the test itself runs
# without Python. Run it only when the Python grammar changes on purpose.
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
KIT_ROOT="$(cd "$HERE/../../.." && pwd)"
python3 - "$KIT_ROOT" "$HERE" <<'PY'
import importlib.util, json, os, random, shlex, sys, tempfile
kit, here = sys.argv[1], sys.argv[2]
spec = importlib.util.spec_from_file_location("sf", os.path.join(kit, "lib", "reflect", "staging-format.py"))
sf = importlib.util.module_from_spec(spec); spec.loader.exec_module(sf)

def dump(name, rows):
    with open(os.path.join(here, name), "w", encoding="utf-8") as fh:
        for r in rows:
            fh.write(json.dumps(r, ensure_ascii=False, separators=(",", ":")) + "\n")

# casefold: every code point whose fold differs from itself, plus a fixed sample that does not
changed = [cp for cp in range(0x110000) if not 0xD800 <= cp <= 0xDFFF and chr(cp).casefold() != chr(cp)]
random.seed(1)
same = random.sample([cp for cp in range(0x110000) if not 0xD800 <= cp <= 0xDFFF and chr(cp).casefold() == chr(cp)], 400)
dump("casefold.jsonl", [{"in": chr(cp), "out": chr(cp).casefold()} for cp in sorted(changed + same)])

titles = ["Add a thing", "  Leading and   trailing  ", "Thuế thu nhập cá nhân", "THUẾ THU NHẬP CÁ NHÂN", "Đà Nẵng trip", "ĐÀ NẴNG",
          "snake_case_word", "kebab-case-word", "dots.and.more", "C++ and C#", "100% sure!", "测试 工具", "ΟΔΟΣ Αθήνα", "Straße", "STRASSE",
          "İstanbul", "ǅ", "ﬁnal", "ŉ", "x\ty\nz", "", "   ", "???", "a_b", "１２３ fullwidth", "Ⅻ roman", "²³ superscript", "٣ arabic digit",
          "mixed 123abc 456", "é decomposed", "ß", "Ǆ", "ς σ Σ", "Ꭰ cherokee", "ა georgian", "emoji 😀 text", "tab\tseparated", "https://ex.com/a?b=c&d=e"]
dump("norm.jsonl", [{"in": t, "out": sf.norm(t)} for t in titles])

cands = [
  {"title": "Plain", "intent": "why", "approach": "how", "u": "hi", "f": "lo", "home": "ops", "source": "session 2026-01-01"},
  {"title": "No optional fields"},
  {"title": "  Spaces\n\nand\tnewlines  ", "intent": "a\nb", "approach": "## [staged] forged\n- Intent: x", "home": " h \n i ", "source": "s\ns"},
  {"title": ""}, {"title": "   "}, {"intent": "no title"},
  {"title": "T", "u": "urgent", "f": 5, "home": "", "source": ""},
  {"title": "T", "u": "mid", "f": "mid"}, {"title": "T", "u": ["hi"], "f": None},
  {"title": 42, "intent": 0, "approach": False, "home": None, "source": True},
  {"title": None}, {"title": True}, {"title": 1.5, "intent": 100},
  {"title": "Vietnamese Đà Nẵng", "intent": "Thuế", "approach": "测试"},
  {"title": "x", "intent": " nbsp em　ideo", "approach": "a\x1cb\x1dc"},
  {"title": "t", "home": "tools/x", "source": "intake-sweep links 2026-10-16"},
]
dump("render.jsonl", [{"in": c, "out": sf.render_block(c)} for c in cands])

boards = [
  "# Board\n\n| ID | Item | Notes | Status |\n|---|---|---|---|\n| ID-1 | Rust ownership | n | queued |\n| ID-22 | Thuế thu nhập | | shipped |\n",
  "| Not a row | x |\n| ID | Not a row | x |\n|ID-3|Tight|x|\n  | AB-12 | Indented | x |\n| ID-4 |  | x |\n| ID-5 | has | pipe | x |\n",
  "", "no table here\n",
  "| ID-1 | CRLF item | n |\r\n| ID-2 | Second | n |\r\n",
  "| ID-1 | Lone CR | n |\r| ID-2 | After CR | n |\r",
  "\x1f| ID-1 | Unit separator lead | n |\n \x1f| ID-2 |\x1f Spaced \x1f| n |",
  "| ID-1 | Vertical tab | n |\x0b| ID-2 | After VT | n |\x0c| ID-3 | After FF | n |\x85| ID-4 | After NEL | n |\u2028| ID-5 | After LS | n |\x1c| ID-6 | After FS | n |",
]
stagings = [
  "# Backlog staging\n\n## [staged] Pick a DB\n- Intent: x\n\n## [rejected] Old idea\n- Intent: y\n\n## [promoted ID-9] Shipped one\n- Source: s\n",
  "## [staged]\n- Intent: x\n\n", "## [staged]   \n\n", "## [staged] !!!\n\n", "## [staged] CRLF title\r\n- Intent: x\r\n",
  "##[staged] no space\n## [a b] two words\n##  [x]   spaced   title  \n",
  "text before\n## [staged] First\nmore\n## [staged] Second\n", "", "no blocks\n", "## not a block\n## [unclosed title\n",
  "## [staged] Đà Nẵng\n## [staged] ĐÀ NẴNG\n",
  "## [staged] Lone CR\r## [staged] After CR\r",
  "## [staged]\r- Intent: x\r",
]
rows = []
scratch = tempfile.mkdtemp()
for kind, texts in (("board", boards), ("staging", stagings)):
    for t in texts:
        path = os.path.join(scratch, kind + ".md")
        with open(path, "w", encoding="utf-8", newline="") as fh:
            fh.write(t)
        rows.append({"kind": kind, "text": t, "keys": sorted(sf.existing_keys((kind, path)))})
dump("keys.jsonl", rows)

alpha = ["a", "b", " ", "\t", "'", '"', "\\", "x y", "-", "=", "$", "`", "\n", "#", "é"]
sh = ["", " ", "a b c", "bin/tool subcmd --x 'a b'", 'say "hello world" now', "a\\ b", "'unterminated", '"unterminated', "trail\\", "''", '""',
      "a''b", "x 'it'\"'\"'s'", '"a\\"b"', '"a\\nb"', "'a\\nb'", "a\\\nb", "claude -p --model haiku --setting-sources project", "a  b\tc\nd",
      "\\\\", '"\\\\"', "# not a comment"]
for _ in range(500):
    sh.append("".join(random.choice(alpha) for _ in range(random.randint(0, 12))))
out = []
for c in sh:
    try: out.append({"in": c, "out": shlex.split(c)})
    except ValueError: out.append({"in": c, "out": None})
dump("shlex.jsonl", out)
print("wrote casefold %d, norm %d, render %d, keys %d, shlex %d" % (len(changed) + 400, len(titles), len(cands), len(rows), len(sh)))
PY
