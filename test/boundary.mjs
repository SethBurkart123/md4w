import assert from "node:assert/strict";
import { init, mdToHtml, parseWithBoundary } from "../js/index.js";

await init();
const encoder = new TextEncoder();
for (const text of [
  "π\n\nparagraph\n---\n",
  "a | b\n---|---\na | b\n",
  "- first\n\n  second\n- third\n",
  "> first\nlazy\n\nlast",
  "```js\na\n\n\nb\n```\nlast",
]) {
  const input = encoder.encode(text);
  for (let end = 0; end <= input.length; end++) {
    const { finishedBytes } = parseWithBoundary(input.subarray(0, end));
    assert.equal(mdToHtml(input.subarray(0, finishedBytes)) +
      mdToHtml(input.subarray(finishedBytes)), mdToHtml(input));
  }
}
assert.equal(parseWithBoundary("π\n\ntail").finishedBytes, 4);
assert.equal(parseWithBoundary("[x]: /target").definitionsSeen, true);
