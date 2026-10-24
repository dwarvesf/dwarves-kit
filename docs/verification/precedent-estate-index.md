# Verification -- precedent-estate-index

`precedent` becomes the one index for skills and tools: new registry kinds (`exec`, `commands`, `agents`), nested skill trees with a source label, `estate` metadata from three declaration spellings, exact-name lookup before keyword scoring, `--layer/--cluster/--kind` filters, and a `precedent index` markdown page. Lane: normal, behavioral (a CLI output surface, headless: no UI capture).

## Green run

New suite, 59 cases (registry grammar, each new kind, frontmatter present/absent/malformed, tool.toml and script-header estate, exact-name ranking, filters, index render, explain):

```
Command: bash tests/test-precedent-index.sh
Exit: 0
Output:
  PASS registry: exec/commands/agents kinds and label=/depth= options parse
  PASS registry: unknown kind exits 64 and names the new kinds
  PASS registry: a non-numeric depth= exits 64
  PASS registry: an unknown option key exits 64
  PASS exec: a depth-2 executable is indexed with its header summary
  PASS exec: the header comment is the summary
  ... (59 case lines in all, no FAIL)
== summary ==
  59/59 passed
```

Existing precedent suite, unchanged, regression check:

```
Command: bash tests/test-precedent.sh
Exit: 0
Output:
== summary ==
  82/82 passed
```

Diff-scoped regression run over every suite the change touches (hooks, config registry, kit contract, wrap, no-personal-paths, no-scattered-ids, modules table, precedent):

```
Command: bash tests/run-all.sh --changed --time
Exit: 0
Output:
run-all: all 22 suites passed, 0 skipped for missing tooling
```

## Negative control

Both load-bearing behaviours reverted together (exact-name ranking returns nothing; the three estate parsers return nothing), committed tree, restored with `git checkout HEAD --`:

```
## Negative control (negctl)
Command: bash tests/test-precedent-index.sh
Exit: 0 (green before mutation)
Output:
    PASS index: rows carry name, summary, path, owner and source
    PASS index: clusters sort alphabetically and (blank) comes last
    PASS index: a header line counts the items still missing a field
    PASS index: skill, tool, script, command and agent kinds all appear
    PASS index: a decoy the scan skips never reaches the page
    PASS index: --out writes the page to a file
    PASS index: two runs over the same tree print the same page
  
  == summary ==
    59/59 passed

Mutation: python3 <mutation script, see Reproduce>
Changed: lib/precedent/inventory.py
Exit: 1 (under mutation, RED expected)
Output:
    FAIL index: clusters sort alphabetically and (blank) comes last
        (blank),
    PASS index: a header line counts the items still missing a field
    PASS index: skill, tool, script, command and agent kinds all appear
    PASS index: a decoy the scan skips never reaches the page
    PASS index: --out writes the page to a file
    PASS index: two runs over the same tree print the same page
  
  == summary ==
    41/59 passed

Restore: git checkout HEAD -- lib/precedent/inventory.py
Exit: 0 (green after restore)
Verdict: PASS
```

Failing cases per mutation, run separately:

```
exact-name ranking reverted: 51/58 passed (earlier suite revision), failing:
  exact-name: a query equal to an item name returns that item first, in an exact section
  exact-name: the match is case-insensitive
  exact-name: a skill is found by its frontmatter name
  exact-name: a command is found by its file stem
  exact-name: a script under a tool is found by its file name
  exact-name: kit:<name> finds the kit's own command
  exact-name: --json carries an 'exact' key right after the data marker
estate parse reverted: 47/58 passed (earlier suite revision), failing:
  estate: SKILL.md metadata.estate lands the skill under its cluster and layer
  estate: the owner column shows the declared owner
  estate: another harness's metadata block beside estate does not hide the estate block
  estate: tool.toml [estate] lands the tool under its cluster and layer
  estate: a script under a tool inherits the tool's estate fields
  estate: a script header line '# estate: k=v ...' is read
  estate: an agent definition's frontmatter estate block is read
  filter: --cluster keeps only items declaring that cluster
  filter: --layer keeps only items declaring that layer
  filter: the index honours --cluster and --kind
  index: clusters sort alphabetically and (blank) comes last
```

## Reproduce

The mutation script patches `lib/precedent/inventory.py` in place:

```
# exact-name ranking: insert `return []` after the exact_matches docstring
# estate parse: insert `return {}` after the docstring of estate_from_frontmatter,
#   estate_from_toml and estate_from_script
bash lib/gate/negctl.sh "$PWD" "bash tests/test-precedent-index.sh" "<script applying both>"
```

## Not proven

- Latency on a very large registry: a registry of about 90 sources and 2,200 items indexes in about 2 seconds here; no budget is asserted.
- A live-estate run is recorded on the PR that adds the registry rows, not here: the kit carries no tenant paths or names.
- `Layer`, `cluster` and `owner` values are free text. Nothing yet checks them against a cluster list or checks that a `drives` or `parent` target exists.
