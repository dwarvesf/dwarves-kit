# docs: correct shout README example to use --upper flag

## Summary
The README's Usage example documents `node cli.js --uppercase hello`, but the CLI only accepts `--upper`. Running the documented command fails with a usage error.

## Change
Update the README example to the actual flag:

    node cli.js --upper hello   # prints HELLO

## Verification
Tiny-lane change (docs only, no behavior change). Confirmed the corrected command runs:

    $ node cli.js --upper hello
    HELLO

Lane: tiny. Lane gates recorded in the run ledger (build, review).
