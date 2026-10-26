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

# README and guide figures: render docs/figures/MODEL.md to docs/figures/<id>.png, or check they are fresh (no browser)
bash lib/system-design/doc-figures render
bash lib/system-design/doc-figures check

# Theme-aware SVG figures (light and dark in one file), labels drawn 1.3 times larger
bash lib/system-design/doc-figures render --format svg --fz 1.3 <model> <outdir>
```

### Figure output: PNG or SVG

`render` writes PNG by default. `--format svg` (or `DOC_FIGURES_FORMAT=svg`) writes one standalone `<id>.svg` per sheet instead. Each SVG carries the template's light tokens, its `prefers-color-scheme: dark` tokens, and only the drawing rules the figure uses, so the file follows the reader's theme inside a plain `<img>` or Markdown image. Its `width` and `height` equal the `viewBox` (times `fz`). An SVG shown as an image fetches nothing, so the web fonts the layout was measured with (Archivo, IBM Plex Sans and Mono) are embedded as data URIs, subset to the figure's own characters through the Google Fonts `text` parameter; the kit's own figures land at 20 to 45 KB. `shots.mjs` warns on a figure over 150 KB, and fails one whose web font it cannot embed rather than ship labels measured in another face. Embed an SVG as an image, never inline: inlined, its `:root` rules would restyle the host page.

### Label size: `fz`

`--fz N`, or `fz: N` in the model's front matter (the flag wins), draws every figure at N times its natural size: a 10.5 px edge label reads at 10.5 times N, so 1.3 gives about 13.5 px. It scales the laid-out drawing as a whole, not the template's `--fz` font variable, which grows the glyphs inside fixed-pixel boxes and line pitches and overflows component notes. A figure PNG keeps its drawing at natural size: a drawing wider than the 938 px page column widens the canvas instead of shrinking into it, and a narrower one keeps the column width. A reading page narrower than the figure still scales it down. `--style FILE` passes a style fragment through to `build`.

`build` needs bash and git only. The model format is `FORMAT.md`. The build refuses a model that contains `</script` or a build placeholder.

## Files

| File | Role |
|---|---|
| `build` | Bash entry: splices the model, the base, `delta.js` and `layout.js` into `template.html`. Resolves its siblings from its own directory. |
| `template.html` | The page: parses the model in the browser (js-yaml 4.1.0 from cdnjs, pinned with SRI) and draws each sheet. |
| `delta.js` | Parses a model and diffs two of them. Pure functions. |
| `layout.js` | Grid placement, orthogonal routing, edge label placement. Pure functions. |
| `shots.mjs` | Headless Chrome over the DevTools protocol, one PNG per sheet; with `SHOT_CLIP=figure`, `SHOT_FORMAT=svg` writes a standalone SVG instead and `SHOT_ZOOM` scales the figure. |
| `doc-figures` | Bash entry for the README and guide figures. `render` runs `build --shots` over `docs/figures/MODEL.md` with `SHOT_CLIP=figure`, writes `<id>.png` (or `<id>.svg`) and `MANIFEST.tsv` (id and the first 16 hex of the sha256 of that sheet's uml block; a full 64-hex manifest from before still checks). `check` needs no browser: it fails when a sheet changed without a re-render, a figure is missing, a sheet has both a PNG and a rendered SVG, or a `figures/<id>.png` reference in `README.md` or `docs/**/*.md` names no manifest id. |
| `test.mjs` | Smoke test over `examples/marketplace/`. |
| `FORMAT.md` | The model format and layout hints. |

## Test

```bash
bash tests/test-system-design.sh     # build, refusal, and (with node and network) test.mjs
bash tests/test-doc-figures.sh       # doc-figures check on the committed state and on mutated temp copies; render when a browser is present
```

`node` is an optional runtime here: only `test.mjs` and `--shots` use it. No hook depends on it.
