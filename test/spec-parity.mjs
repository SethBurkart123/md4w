import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import { resolve } from "node:path";
import { pathToFileURL } from "node:url";
import { init, parseBlocks } from "../js/index.js";

const release = pathToFileURL(resolve(process.argv[2], "js/index.js"));
const reference = await import(release);
await Promise.all([init(), reference.init()]);
const suites = [
  ["spec", 0], ["spec-tables", 0x100], ["spec-strikethrough", 0x200],
  ["spec-tasklists", 0x800], ["spec-permissive-autolinks", 0x40c],
];
for (const [name, parseFlags] of suites) {
  const file = new URL("../vendor/md4c/test/" + name + ".txt", import.meta.url);
  const spec = await readFile(file, "utf8");
  let count = 0;
  for (const match of spec.matchAll(/^`{32} example[^\n]*\n([\s\S]*?)^\.\n[\s\S]*?^`{32}$/gm)) {
    const input = match[1].replaceAll("→", "\t");
    const blocks = parseBlocks(input, { parseFlags });
    assert.equal(blocks.map(b => b.html).join(""), reference.mdToHtml(input, { parseFlags }), name + " " + ++count);
  }
  assert.ok(count > 0, name);
}
