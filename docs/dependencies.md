# Dependencies

## Required (kit won't work without these)

| Tool | Why | Install |
|------|-----|---------|
| jq | Parse JSON in hook scripts, merge settings.json | `brew install jq` (macOS) / `apt install jq` (Linux) |
| git | Branch detection, diff for review, commit for ship | Pre-installed on most systems |
| Claude Code | The agent runtime the kit extends | `npm install -g @anthropic-ai/claude-code` |

## Recommended (kit works without, but better with)

| Tool | Why | Install |
|------|-----|---------|
| Context Hub (chub) | Curated API docs prevent hallucinated APIs | `npm install -g @aisuite/chub` |
| Context7 | Library docs via MCP (React, Next.js, etc.) | MCP server, connect in Claude Code settings |
| codebase-memory-mcp | AST-level codebase indexing for large projects | MCP server, connect in Claude Code settings |
| trash (macos-trash) | Safe delete alternative (safety-gate suggests it) | `brew install macos-trash` |

## Formatters (auto-format hook detects and uses what's available)

| Formatter | Languages | Install |
|-----------|-----------|---------|
| prettier | JS, TS, CSS, JSON, MD, HTML | `npm install -g prettier` or project-level |
| gofmt | Go | Bundled with Go |
| ruff | Python | `uv tool install ruff` or `pip install ruff` |
| black | Python (fallback if ruff not found) | `pip install black` |
| rustfmt | Rust | Bundled with Rust toolchain |
