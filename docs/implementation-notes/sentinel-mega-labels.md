# Delta: sentinel meaning and mega labels (branch fix/sentinel-mega-labels)

## Migrate sentinel
- The brief offered "copy through the link or record a reason". I chose refuse plus record. Copying through a symlink is the exfiltration the guard exists to stop.
- A symlinked legacy dir now writes `.migrate-refused` (reason, path) and no `.migrated`. A later run with a real dir migrates and clears the marker.
- The scout said a hostile link is "re-scanned every command". It is not: migration runs only from install and adopt, and `kit_note_unmigrated` already stays silent for a symlinked legacy dir. So dropping the sentinel costs one stderr line per install.
- Pinned root: left as is. The header contract says the caller owns a pinned path, so no corpus sentinel and a silent note are by design, not a gap.
- `lib/telemetry/tests/smoke.sh` case 6d asserted the old sentinel; it now asserts the marker.
