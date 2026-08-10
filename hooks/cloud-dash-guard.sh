#!/usr/bin/env bash
# cloud-dash-guard.sh -- strip em and en dashes from a prose file a cloud session wrote.
#
# PostToolUse hook, matcher: Write|Edit|MultiEdit.
#
# A style hook that lives in the operator's own machine config never reaches a
# cloud VM, so a cloud session breaks the house no-dash rule with nothing to
# catch it. This is the cloud backstop, and it fires only when the cloud module
# is enabled, so a project that permits dashes never installs it.
#
# SAFETY, the reason this version is narrow: a wider dash rewriter has corrupted
# source files by rewriting a literal dash inside code that legitimately handles
# one, which produced false-green tests. This version only opens a file whose
# extension is on the prose allowlist, and inside that file it leaves fenced
# code blocks and inline code spans alone. A file with unbalanced fences is
# skipped whole. A missed dash is cheap. A corrupted source file is not.
#
# Known gap: only FENCED code is understood. A dash inside a 4-space indented
# code block in markdown is still rewritten.
#
# Silent on success. Always exits 0.
set -uo pipefail

# Cloud test: the documented signal, not a repo probe. CLAUDE_CODE_REMOTE is set
# to "true" in remote web environments and is not set in the local CLI. An
# earlier gate probed for a sibling checkout, which a cloud session is told to
# clone, so cloning it disabled this guard mid-session.
[ "${CLAUDE_CODE_REMOTE:-}" = "true" ] || exit 0          # local CLI: user hooks run
[ "$(uname -s)" = "Linux" ] || exit 0                     # macOS: nothing to do
command -v python3 >/dev/null 2>&1 || exit 0

TMP="$(mktemp "${TMPDIR:-/tmp}/cloud-dash.XXXXXX")" || exit 0
trap 'rm -f "$TMP"' EXIT
cat >"$TMP"

python3 - "$TMP" <<'PY' 2>/dev/null || exit 0
import json, os, re, sys, tempfile

# The dash characters are built at runtime. A literal one in this file would be
# a target for any dash-rewriting hook, including this one.
EM, EN = chr(0x2014), chr(0x2013)
PROSE = (".md", ".markdown", ".txt")

try:
    with open(sys.argv[1], encoding="utf-8") as f:
        data = json.load(f)
except Exception:
    sys.exit(0)

ti = data.get("tool_input") or {}
path = ti.get("file_path") or (data.get("tool_response") or {}).get("filePath")
if not path or os.path.splitext(path)[1].lower() not in PROSE:
    sys.exit(0)                       # prose only: a source file is never touched

try:
    with open(path, encoding="utf-8") as f:
        text = f.read()
except (OSError, UnicodeDecodeError):
    sys.exit(0)

if EM not in text and EN not in text:
    sys.exit(0)

# Unbalanced fences mean the code regions cannot be trusted. Skip the file.
if len(re.findall(r"(?m)^\s*```", text)) % 2:
    sys.exit(0)

CODE = re.compile(r"(?ms)(^\s*```.*?^\s*```|`[^`\n]+`)")

# HORIZONTAL whitespace only. A `\s` class here matches newlines, so a dash at
# the end of a paragraph swallowed the blank line and the following heading,
# collapsing `prose <dash>\n\n## Heading` into `prose, ## Heading`. That
# destroyed markdown structure. `[ \t]` can never cross a line.
H = r"[ \t]*"
CHARS = "[" + EM + EN + "]"
DASH_EOL = re.compile(H + CHARS + H + r"(?=\r?\n|\Z)")   # end of line: no trailing space
DASH = re.compile(H + CHARS + H)

segs = CODE.split(text)               # odd indices are code, left untouched
hits = 0
for i in range(0, len(segs), 2):
    segs[i], a = DASH_EOL.subn(",", segs[i])
    segs[i], b = DASH.subn(", ", segs[i])
    if a + b:
        segs[i] = re.sub(r",[ \t]*,", ",", segs[i])
        hits += a + b
if not hits:
    sys.exit(0)

fd, tmp = tempfile.mkstemp(prefix=".cloud-dash-", dir=os.path.dirname(path) or ".")
try:
    with os.fdopen(fd, "w", encoding="utf-8") as f:
        f.write("".join(segs))
    os.replace(tmp, path)
except Exception:
    try:
        os.unlink(tmp)
    except OSError:
        pass
PY

exit 0
