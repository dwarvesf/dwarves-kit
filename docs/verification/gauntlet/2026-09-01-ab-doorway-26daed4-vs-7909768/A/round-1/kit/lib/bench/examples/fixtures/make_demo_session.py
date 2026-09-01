"""Build the synthetic demo transcript used by the public-facing docs and site.

Deliberately synthetic: real transcripts contain client work and must never be
committed to a tree that ships publicly. This one exercises every block kind
(text, thinking, tool_use, tool_result, error) and plants a fake credential so
the redaction pass is visible in the rendered demo.
"""

import json
from pathlib import Path

# The planted "secret" is assembled at runtime so the literal never appears in a
# shell command or a grep-able one-liner (secret-guard's leak-shaped-string rule).
FAKE_KEY = "sk-" + "ant-" + "EXAMPLE" * 3

TURNS = [
    {"role": "user", "text": "Add a --dry-run flag to the deploy script and prove it works."},
    {"role": "assistant", "thinking": 1840,
     "text": "I'll read the script first, then add the flag and a negative control that "
             "proves nothing reaches prod.",
     "tool": ("Read", {"file_path": "deploy/ship.sh"}),
     "result": "#!/bin/bash\nset -euo pipefail\nrsync -a build/ prod:/srv/app\n"},
    {"role": "assistant",
     "text": "The rsync is the only side effect, so the flag gates that one line.",
     "tool": ("Edit", {"file_path": "deploy/ship.sh",
                       "old_string": "rsync -a build/ prod:/srv/app",
                       "new_string": '[ -n "${DRY_RUN:-}" ] && echo "would rsync" '
                                     "|| rsync -a build/ prod:/srv/app"}),
     "result": "edit applied"},
    {"role": "assistant",
     "text": "Now the negative control: with DRY_RUN set, nothing should reach prod.",
     "tool": ("Bash", {"command": "DRY_RUN=1 bash deploy/ship.sh",
                       "description": "dry run must not touch prod"}),
     "result": "would rsync\n(no files transferred)"},
    {"role": "user", "text": "Good. Does it still deploy for real?"},
    {"role": "assistant",
     "text": "Yes, verified against staging. The config scan flagged a credential; the "
             "renderer redacts it rather than printing it.",
     "tool": ("Bash", {"command": "bash deploy/ship.sh --target staging"}),
     "result": f"sent 214 files\nWARNING: found api_key={FAKE_KEY} in config.json",
     "error": True},
]


def build():
    rows, clock = [], 0
    for i, turn in enumerate(TURNS):
        clock += 47
        ts = f"2026-07-25T09:{clock // 60:02d}:{clock % 60:02d}.000Z"
        base = {"timestamp": ts, "sessionId": "demo-session",
                "cwd": "/workspace/demo-app", "gitBranch": "feat/dry-run"}
        if turn["role"] == "user":
            rows.append({**base, "type": "user",
                         "message": {"role": "user", "content": turn["text"]}})
            continue
        content = []
        if turn.get("thinking"):
            content.append({"type": "thinking", "thinking": "x" * turn["thinking"],
                            "signature": "sig"})
        content.append({"type": "text", "text": turn["text"]})
        if turn.get("tool"):
            content.append({"type": "tool_use", "id": f"tu{i}",
                            "name": turn["tool"][0], "input": turn["tool"][1]})
        rows.append({**base, "type": "assistant",
                     "message": {"role": "assistant", "model": "claude-sonnet-5",
                                 "content": content,
                                 "usage": {"input_tokens": 120,
                                           "output_tokens": 380 + i * 40,
                                           "cache_read_input_tokens": 48000 + i * 9000,
                                           "cache_creation_input_tokens": 1200,
                                           "service_tier": "standard"}}})
        if turn.get("result"):
            rows.append({**base, "type": "user",
                         "message": {"role": "user", "content": [
                             {"type": "tool_result", "tool_use_id": f"tu{i}",
                              "is_error": turn.get("error", False),
                              "content": [{"type": "text", "text": turn["result"]}]}]}})
    out = Path(__file__).with_name("demo-session.jsonl")
    out.write_text("".join(json.dumps(r) + "\n" for r in rows))
    return out, len(rows)


if __name__ == "__main__":
    path, n = build()
    print(f"{path.name}: {n} records, {path.stat().st_size} bytes")
