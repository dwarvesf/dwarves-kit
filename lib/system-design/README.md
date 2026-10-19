# system-design

The engine behind the `system-design` skill. It renders a repo's `docs/SYSTEM-DESIGN.md` (Markdown prose plus fenced `uml` YAML blocks) as one self-contained HTML drawing set, and marks every element `new`, `changed` or `removed` against a base git ref or base file. `/kit:design` uses it to review a feature as a UML delta. The skill (`skills/system-design/SKILL.md`) owns the workflow; this directory owns the code.

## Use

```bash
# Against the branch's merge-base
bash lib/system-design/build --model docs/SYSTEM-DESIGN.md --base "$(git merge-base HEAD origin/master)" --out /tmp/uml.html

# No git history to diff: a base file
bash lib/system-design/build --model lib/system-design/examples/marketplace/SYSTEM-DESIGN.md \
  --base-file lib/system-design/examples/marketplace/SYSTEM-DESIGN.base.md --out /tmp/uml.html

# Also one PNG per sheet (needs node 22+ and Chrome; CHROME overrides the macOS path)
bash lib/system-design/build --model <model> --out /tmp/uml.html --shots /tmp/shots
```

`build` needs bash and git only. The model format is `FORMAT.md`. The build refuses a model that contains `</script` or a build placeholder.

## Files

| File | Role |
|---|---|
| `build` | Bash entry: splices the model, the base, `delta.js` and `layout.js` into `template.html`. Resolves its siblings from its own directory. |
| `template.html` | The page: parses the model in the browser (js-yaml 4.1.0 from cdnjs, pinned with SRI) and draws each sheet. |
| `delta.js` | Parses a model and diffs two of them. Pure functions. |
| `layout.js` | Grid placement, orthogonal routing, edge label placement. Pure functions. |
| `shots.mjs` | Headless Chrome over the DevTools protocol, one PNG per sheet. |
| `test.mjs` | Smoke test over `examples/marketplace/`. |
| `FORMAT.md` | The model format and layout hints. |

## Test

```bash
bash tests/test-system-design.sh     # build, refusal, and (with node and network) test.mjs
```

`node` is an optional runtime here: only `test.mjs` and `--shots` use it. No hook depends on it.
