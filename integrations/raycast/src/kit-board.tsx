import { runInTerminal } from "./lib/runInTerminal";

export default async function Command() {
  await runInTerminal(
    '${DWARVES_KIT:-$HOME/.claude/dwarves-kit}/bin/board board',
    "Kit: Board"
  );
}
