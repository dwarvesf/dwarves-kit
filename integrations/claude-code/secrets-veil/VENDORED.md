# Vendored

Source: github.com/yonatangross/orchestkit, `mods/secrets-veil`, commit `1cf7bb4` (MIT, `LICENSE` beside this file).

Read in full before vendoring: no process, network or file calls; it masks secret-shaped values in tool results and fails closed.

Only runtime files are kept (manifest, `hooks/`, `src/`, `tsconfig.json`); the upstream tests and npm tooling stay upstream.
To update: re-read the diff against this commit, then copy the same files.

Local patch: `hooks/register.ts` drops the `$.ui.status` "N masked this session" line (a status entry holds a row under the prompt); the per-mask toast stays.

Local patch: `maskDeep` in `hooks/register.ts` passes encoded file bytes through untouched (`base64` in image/pdf/document blocks, and `data` beside `type: "base64"` or `type: "image"`). Upstream masked image base64 as a high-entropy token, so every image a tool returned reached the API as `••••••••` and the request failed. Pinned by `tests/binary-payload.test.ts`, the only local tests.

Local patch: `answerFor` in `hooks/register.ts` answers a masked errored run (`isError: true`) as `{ deny }`, ported from upstream `ef7dbb6`. Before it, a failing command whose output held a secret reached the model as an output-shape error. Pinned by `tests/errored-run.test.ts`.
