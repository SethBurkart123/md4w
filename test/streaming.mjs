import assert from "node:assert/strict";
import { createSession, init, mdToHtml } from "../js/index.js";

await init();
for (const [text, inner] of [
  ["*outer **inner", "<em>outer <strong>inner</strong></em>"],
  ["*outer **", "<em>outer </em>"],
  ["a `code", "a <code>code</code>"],
  ["a $x", "a <x-equation>x</x-equation>"],
  ["a ~~word", "a <del>word</del>"],
  ["[label](https://exam", "label"],
  ["word *", "word "],
]) {
  const options = { streaming: true, parseFlags: ["LATEX_MATH_SPANS", "STRIKETHROUGH"] };
  const session = createSession(options);
  assert.equal(session.append(text).blocks[0].html, "<p>" + inner + "</p>\n");
  assert.equal(session.finish().blocks[0].html, mdToHtml(text, options));
  session.close();
}
