import assert from "node:assert/strict";
import { createSession, init, mdToHtml } from "../js/index.js";

await init();
const documents = [
  "😀\n\n> quote\n> next\n\n- one\n\n- two\n\nend",
  "[before][x]\n\n[x]: /one\n  'title'\n\n[after][x]\n\n[x]: /two\n",
  "[x]: /target\n\n[x]\n\nparagraph\n\n[x]",
];
for (const doc of documents) {
  const a = createSession();
  const b = createSession();
  let blocks = [];
  for (let end = 1; end <= doc.length; end++) {
    const patch = a.append(doc.slice(end - 1, end));
    assert.deepEqual(b.update(doc.slice(0, end)), patch);
    blocks = blocks.filter(block => block.offset < patch.replaceFrom).concat(patch.blocks);
    assert.equal(blocks.map(block => block.html).join(""), mdToHtml(doc.slice(0, end)));
  }
  a.close();
  b.close();
}
