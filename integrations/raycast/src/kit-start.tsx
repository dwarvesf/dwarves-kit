import { runInTerminal } from "./lib/runInTerminal";

export default async function Command() {
  await runInTerminal('claude "/kit:start"', "Kit: Start");
}
