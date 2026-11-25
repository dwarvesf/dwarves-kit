# Verification -- precedent reads a whole memory note

`note_frontmatter` read only the first 8 KB of a memory note, while its docstring promised the whole body. A reference card (ops-toolkit `tools/ref-library/cards/*.md`, about 14 KB) carried its only match for "design" past that cap, so `precedent find --surface inventory "design a bouncy toggle animation"` missed the card. The reader now reads up to 64 KB, the cap other iterators in `inventory.py` already use.

## Red before the fix

The new fixture `kappa.md` is a 9 KB note whose unique term sits on its last line.

```
Command: bash tests/test-precedent.sh
Exit: 1
Output:
  FAIL long memory note: a term past the first 8 KB still matches
  82/83 passed
Verdict: FAIL (expected)
```

## Green after the fix

```
Command: bash tests/test-precedent.sh
Exit: 0
Output:
  PASS long memory note: a term past the first 8 KB still matches
  83/83 passed
Verdict: PASS
```

```
Command: bash tests/test-precedent-index.sh
Exit: 0
Output:
  59/59 passed
Verdict: PASS
```

## Live check

With the ref-library cards row in the registry, the real card now hits:

```
Command: precedent find --surface inventory "design a bouncy toggle animation"
Output (memory section):
  sakuga-vfx.md  , Sakuga VFX, playful anime-style web UI controls (button, toggle, slider, ...
```
