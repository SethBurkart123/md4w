import assert from "node:assert/strict";
import { init, mdToHtml, parseBlocks } from "../js/index.js";

await init();
const text = "π\n\n- first\n- second\n\n> quoted\n\nlast";
const blocks = parseBlocks(text);
assert.equal(blocks.map(block => block.html).join(""), mdToHtml(text));
assert.deepEqual(blocks.map(block => block.offset), [0, 4, 22, 32]);
assert.deepEqual(parseBlocks(text + "!").slice(0, -1), blocks.slice(0, -1));
