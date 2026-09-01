import { runInTerminal } from "./lib/runInTerminal";

export default async function Command() {
  await runInTerminal('claude "/kit:ship"', "Kit: Ship");
}
