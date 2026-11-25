#!/usr/bin/env bash
# digest.sh -- lib/proof: the one parser for the sha256 field of a proof-asset manifest.
#
# WHY: a committed manifest that holds a bare 64-hex run is refused by a commit-time
# secret scan, which cannot tell a digest from a private key. The writer therefore
# records "sha256:<hex>"; the scan exempts a run right after that marker. Records
# written before the change hold the bare hex, so every reader goes through
# proof_digest_hex and accepts both shapes.
#
# Sourced, not run. Pure bash, no output but the result.

# proof_digest_fmt <hex> -> the recorded shape, sha256:<hex>.
proof_digest_fmt() { printf 'sha256:%s' "$1"; }

# proof_digest_hex <recorded> -> the bare hex, whether the record holds sha256:<hex> or
# the older bare <hex>. Only one exact lowercase prefix is stripped; anything else comes
# back untouched, so a malformed record still fails a comparison against real bytes.
proof_digest_hex() { printf '%s' "${1#sha256:}"; }
