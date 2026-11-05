import { expect, mock, test } from 'claude-code/testing';
import type { On } from 'claude-code';

import { isTrustedRoot, normalizePath, parseMemory, parseTrustedRoots } from '../src/memory';

type Node = { kind: 'file' | 'dir'; text?: string; size?: number };

/** An in-memory file system under the plugins; `files` maps absolute paths to text, `dirs` lists folders. */
function world(on: On, home: string, files: Record<string, string | { text: string; size: number }>, dirs: string[]) {
  const nodes = new Map<string, Node>();
  for (const d of dirs) nodes.set(d, { kind: 'dir' });
  for (const [path, v] of Object.entries(files)) {
    nodes.set(path, typeof v === 'string' ? { kind: 'file', text: v, size: v.length } : { kind: 'file', text: v.text, size: v.size });
  }
  mock.env(on, { HOME: home });
  on('session.start', (_$, e) => ({ cwd: e.cwd }));
  on('command.register', (_$, e) => ({ value: { command: e.name } }));
  on('ui.log', () => ({ value: undefined }));
  on('fs.exists', (_$, e) => ({ value: nodes.has(e.path) }));
  on('fs.read', (_$, e) => {
    const n = nodes.get(e.path);
    return n?.kind === 'file' ? { value: n.text ?? '' } : { deny: 'missing' };
  });
  on('fs.list', (_$, e) => {
    if (nodes.get(e.path)?.kind !== 'dir') return { deny: 'missing' };
    const prefix = e.path.replace(/\/+$/, '') + '/';
    const out = [];
    for (const [path, n] of nodes) {
      if (!path.startsWith(prefix) || path.slice(prefix.length).includes('/')) continue;
      out.push({ name: path.slice(prefix.length), kind: n.kind, size: n.size ?? 0, mtimeMs: 0 });
    }
    return { value: out };
  });
}

const memory = (name: string) => `---\nname: ${name}\ndescription: about ${name}\ntype: feedback\n---\nbody of ${name}\n`;

async function statsFor($: any, cwd: string): Promise<string> {
  await $.session.start({ cwd, surface: 'terminal', isInteractive: true });
  const r = await $.command.run({ command: 'memory-lens', args: '', origin: { kind: 'composer' }, presentation: { isFullscreen: true, columns: 120 } });
  return JSON.stringify(r);
}

const HOME = '/home/u';

/** A trusted-roots file that allowlists ~/workspace/acme/, with the folders `fs.list` walks to reach it. */
const TRUST_ACME = {
  files: { [`${HOME}/.claude/memory-lens/trusted-roots`]: '# test\n~/workspace/acme/\n' },
  dirs: [`${HOME}/.claude`, `${HOME}/.claude/memory-lens`],
};

test('a repo under a trusted root gets its per-repo store', async ($, on) => {
  const repo = `${HOME}/workspace/acme/app`;
  world(on, HOME, { ...TRUST_ACME.files, [`${repo}/.claude/memory/a.md`]: memory('alpha') }, [...TRUST_ACME.dirs, `${repo}`, `${repo}/.git`, `${repo}/.claude`, `${repo}/.claude/memory`]);
  const stats = await statsFor($, repo);
  expect(stats).toContain(`${repo}/.claude/memory`);
  expect(stats).toContain('1 memories');
});

for (const root of ['acme', 'dwarvesf']) {
  test(`with no trusted-roots file nothing is trusted: ~/workspace/${root}`, async ($, on) => {
    const repo = `${HOME}/workspace/${root}/app`;
    world(on, HOME, { [`${repo}/.claude/memory/a.md`]: memory('planted') }, [`${repo}`, `${repo}/.git`, `${repo}/.claude`, `${repo}/.claude/memory`]);
    const stats = await statsFor($, repo);
    expect(stats).not.toContain('.claude/memory');
    expect(stats).toContain('0 memories');
  });
}

test('a cwd under a non-allowlisted root gets no repo store', async ($, on) => {
  const repo = `${HOME}/Downloads/cloned/app`;
  world(on, HOME, { [`${repo}/.claude/memory/a.md`]: memory('planted') }, [`${repo}`, `${repo}/.git`, `${repo}/.claude`, `${repo}/.claude/memory`]);
  const stats = await statsFor($, repo);
  expect(stats).not.toContain('.claude/memory');
  expect(stats).toContain('0 memories');
});

test('the lookup stops at the git root: a store above it is not taken', async ($, on) => {
  const outer = `${HOME}/workspace/acme`;
  const repo = `${outer}/app`;
  world(on, HOME, { ...TRUST_ACME.files, [`${outer}/.claude/memory/a.md`]: memory('above') }, [...TRUST_ACME.dirs, outer, `${outer}/.claude`, `${outer}/.claude/memory`, repo, `${repo}/.git`]);
  expect(await statsFor($, `${repo}/src`)).not.toContain(`${outer}/.claude/memory`);
});

test('no git root gets no repo store', async ($, on) => {
  const dir = `${HOME}/workspace/acme/loose`;
  world(on, HOME, { ...TRUST_ACME.files, [`${dir}/.claude/memory/a.md`]: memory('loose') }, [...TRUST_ACME.dirs, dir, `${dir}/.claude`, `${dir}/.claude/memory`]);
  expect(await statsFor($, dir)).not.toContain(`${dir}/.claude/memory`);
});

test('a cwd outside HOME gets no repo store', async ($, on) => {
  const repo = '/srv/code/app';
  world(on, HOME, { [`${repo}/.claude/memory/a.md`]: memory('outside') }, [repo, `${repo}/.git`, `${repo}/.claude`, `${repo}/.claude/memory`]);
  expect(await statsFor($, repo)).not.toContain(`${repo}/.claude/memory`);
});

test('a trusted-roots file replaces the defaults', async ($, on) => {
  const repo = `${HOME}/elsewhere/app`;
  world(
    on,
    HOME,
    { [`${repo}/.claude/memory/a.md`]: memory('mine'), [`${HOME}/.claude/memory-lens/trusted-roots`]: '# mine\n~/elsewhere/\n' },
    [repo, `${repo}/.git`, `${repo}/.claude`, `${repo}/.claude/memory`, `${HOME}/.claude`, `${HOME}/.claude/memory-lens`],
  );
  expect(await statsFor($, repo)).toContain(`${repo}/.claude/memory`);
});

test('a 1 MB memory file is skipped and indexing stays fast', async ($, on) => {
  const repo = `${HOME}/workspace/acme/big`;
  const dir = `${repo}/.claude/memory`;
  const huge = 'a'.repeat(1_000_000);
  world(
    on,
    HOME,
    {
      ...TRUST_ACME.files,
      [`${dir}/ok.md`]: memory('ok'),
      [`${dir}/huge.md`]: huge,
      // lies about its size in the listing: the length after the read still rules it out
      [`${dir}/liar.md`]: { text: huge, size: 10 },
    },
    [...TRUST_ACME.dirs, repo, `${repo}/.git`, `${repo}/.claude`, dir],
  );
  const t0 = performance.now();
  const stats = await statsFor($, repo);
  expect(performance.now() - t0).toBeLessThan(1500);
  expect(stats).toContain('1 memories');
});

test('the image scan is linear on a long path-like run', async () => {
  const text = `---\nname: x\n---\n${'a'.repeat(7000)}`;
  const t0 = performance.now();
  parseMemory('/m/x.md', text);
  expect(performance.now() - t0).toBeLessThan(50);
});

test('path helpers: normalising, trusted prefixes, no sibling-prefix match', () => {
  expect(normalizePath('/a/b/../c//d/.')).toBe('/a/c/d');
  expect(normalizePath('/../x')).toBe('');
  const roots = parseTrustedRoots('# c\n~/workspace/acme\n/srv/code/\nrelative/ignored\n', '/home/u');
  expect(roots).toEqual(['/home/u/workspace/acme/', '/srv/code/']);
  expect(isTrustedRoot('/home/u/workspace/acme/app', roots)).toBe(true);
  expect(isTrustedRoot('/home/u/workspace/acme-evil/app', roots)).toBe(false);
  expect(isTrustedRoot('/srv/code', roots)).toBe(true);
});
