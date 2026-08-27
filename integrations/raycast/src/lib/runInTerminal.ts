import { execFileSync } from "child_process";
import { closeMainWindow, showHUD } from "@raycast/api";

/** Open Terminal.app and run `command`, then close Raycast. Shared by every kit-* command.
 * Uses execFileSync (argv array, no shell) so `command` never passes through a shell parse;
 * only AppleScript's own string-literal escaping applies. */
export async function runInTerminal(command: string, label: string) {
  await closeMainWindow();
  const escaped = command.replace(/\\/g, "\\\\").replace(/"/g, '\\"');
  try {
    execFileSync("osascript", [
      "-e",
      'tell application "Terminal" to activate',
      "-e",
      `tell application "Terminal" to do script "${escaped}"`,
    ]);
    await showHUD(`Running: ${label}`);
  } catch (error) {
    await showHUD(`Failed to launch ${label}: ${String(error)}`);
  }
}
