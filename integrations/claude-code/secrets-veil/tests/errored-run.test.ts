import { expect, test } from 'claude-code/testing';
import { answerFor } from '../hooks/register.ts';

// Local patch (see VENDORED.md): upstream ef7dbb6. A masked errored run is answered as { deny }.

test('a masked errored run comes back as deny with the masked text, no result, no ref', () => {
  const text = 'Bash failed: exit 2\nFAKE_TOKEN=••••••••';
  const out = answerFor({ isError: true, ref: 3, result: text, text }, true) as Record<string, unknown>;
  expect(out).toEqual({ deny: text });
});

test('a masked errored run with only a string result still yields a non-empty deny', () => {
  const out = answerFor({ isError: true, ref: 1, result: 'boom ••••••••' }, true);
  expect(out).toEqual({ deny: 'boom ••••••••' });
});

test('an errored run with nothing masked is returned as is', () => {
  const run = { isError: true, ref: 3, result: 'Exit code 1\nplain failure', text: 'Exit code 1\nplain failure' };
  expect(answerFor(run, false)).toEqual(run);
});
