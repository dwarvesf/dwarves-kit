import { expect, mock, test } from 'claude-code/testing';
import type { On } from 'claude-code';

// Local patch (see VENDORED.md): encoded file bytes pass through; text beside them is still masked.

/** Deterministic random string over an alphabet (no literal secret in the source). */
function noise(length: number, alphabet: string, seed: number): string {
  let s = seed;
  let out = '';
  for (let i = 0; i < length; i++) {
    s = (Math.imul(s, 1103515245) + 12345) >>> 0;
    out += alphabet[(s >>> 16) % alphabet.length];
  }
  return out;
}

const B64 = noise(4000, 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/', 7);
const TOKEN = noise(40, 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789', 11);

/** Arm the veil with no named values, answer every tool call with `result`, return what the model would see. */
async function run($: any, on: On, result: unknown): Promise<string> {
  mock.env(on, {});
  on('session.start', (_$, e) => ({ cwd: e.cwd }));
  on('ui.toast', () => ({ value: undefined }));
  on('ui.notice', () => ({ value: undefined }));
  on('ui.log', () => ({ value: undefined }));
  on('tool.call', () => ({ result }) as never);
  await $.session.start({ cwd: '/work', surface: 'terminal', isInteractive: true });
  return JSON.stringify(await $.tool.call({ tool: 'Read', file_path: '/work/a.png' } as never));
}

test('control: the same bytes as plain text are masked, so the fixtures look secret', async ($, on) => {
  const seen = await run($, on, { content: [{ type: 'text', text: `${B64} ${TOKEN}` }] });
  expect(seen.includes(B64)).toBe(false);
  expect(seen.includes(TOKEN)).toBe(false);
});

test('Read image result keeps its base64 bytes', async ($, on) => {
  const seen = await run($, on, {
    type: 'image',
    file: { base64: B64, type: 'image/png', originalSize: 3000, dimensions: { originalWidth: 10, originalHeight: 10 } },
  });
  expect(seen.includes(B64)).toBe(true);
});

test('API image source and Read pdf keep their bytes', async ($, on) => {
  const seen = await run($, on, {
    content: [
      { type: 'image', source: { type: 'base64', media_type: 'image/jpeg', data: B64 } },
      { type: 'pdf', file: { base64: B64, filePath: '/work/a.pdf', originalSize: 3000 } },
    ],
  });
  expect(seen.split(B64).length - 1).toBe(2);
});

test('a token in text beside an image is still masked', async ($, on) => {
  const seen = await run($, on, {
    content: [
      { type: 'text', text: `key ${TOKEN}` },
      { type: 'image', source: { type: 'base64', media_type: 'image/png', data: B64 } },
    ],
  });
  expect(seen.includes(TOKEN)).toBe(false);
  expect(seen.includes(B64)).toBe(true);
});

test('a token in a text document source is still masked', async ($, on) => {
  const seen = await run($, on, {
    content: [{ type: 'document', source: { type: 'text', media_type: 'text/plain', data: `key ${TOKEN}` } }],
  });
  expect(seen.includes(TOKEN)).toBe(false);
});
