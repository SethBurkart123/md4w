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

const underline = createSession({ streaming: true, parseFlags: ["UNDERLINE"] });
assert.equal(underline.append("_word").blocks[0].html, "<p><u>word</u></p>\n");
underline.close();

const pending = createSession({ streaming: true });
pending.append("first\n\n");
assert.deepEqual(pending.append("\n").blocks, []);
assert.deepEqual(pending.append("!").blocks, []);
assert.equal(pending.append("yes").blocks[0].html, "<p>!yes</p>\n");
pending.reset("first\n\n!");
assert.equal(pending.finish().blocks[0].html, "<p>!</p>\n");
pending.close();

for (const [source, expected] of [
  ["`", ""], ["``", ""], ["```js", "<pre><code class=\"language-js\"></code></pre>\n"],
  ["[x][ref", "<p>x</p>\n"], ["[x][ref] after", "<p>x after</p>\n"],
  ["- [", "<ul>\n<li></li>\n</ul>\n"], ["- [ ", "<ul>\n<li></li>\n</ul>\n"],
  ["- [X", "<ul>\n<li></li>\n</ul>\n"], ["- [x]", mdToHtml("- [x]")],
  ["text -", "<p>text </p>\n"], ["text +", "<p>text </p>\n"],
  ["text ==", "<p>text </p>\n"], ["a\\", "<p>a</p>\n"], ["a <", "<p>a </p>\n"],
  ["👩‍", "<p>👩</p>\n"], ["👩‍💻", mdToHtml("👩‍💻")],
  ["🇦", ""], ["🇦🇺", mdToHtml("🇦🇺")], ["\u20e3", ""], ["3️⃣", mdToHtml("3️⃣")],
  ["a :smil", "<p>a :smil</p>\n"],
]) {
  const session = createSession({ streaming: true });
  assert.equal(session.append(source).blocks.map(b => b.html).join(""), expected, source);
  assert.equal(session.finish().blocks.map(b => b.html).join(""), mdToHtml(source));
  session.close();
}
const header = mdToHtml("| a | b |\n|---|---|");
for (const source of ["| a | b |", "| a | b |\n", "| a | b", "| a | b |\n|-", "| a | b |\n|---|", "| a | b |\n|---|---|"]) {
  const session = createSession({ streaming: true });
  assert.equal(session.append(source).blocks[0].html, header, source);
  assert.equal(session.finish().blocks[0].html, mdToHtml(source), source);
  session.close();
}
for (const [source, options] of [
  ["| `a|b` | c |", {}], ["| {{a|b}} | c |", { rules: [{ open: "{{", close: "}}", tag: "value" }] }],
]) {
  const session = createSession({ streaming: true, ...options });
  assert.equal(session.append(source).blocks[0].html.match(/<th>/g).length, 2, source);
  session.close();
}
for (const [source, cell] of [["| *hello", "<em>hello</em>"], ["| [label](https://exam", "label"]]) {
  const session = createSession({ streaming: true });
  assert.ok(session.append(source).blocks[0].html.includes(`<th>${cell}</th>`), source);
  session.close();
}
for (const source of ["text\n| a | b |", "|", "| |", "a | b\n---|---"]) {
  const session = createSession({ streaming: true });
  assert.equal(session.append(source).blocks.map(b => b.html).join(""), mdToHtml(source), source);
  session.close();
}
for (const chunks of [["\ud83d", "\ude00"], [Uint8Array.of(0xf0, 0x9f), Uint8Array.of(0x98, 0x80)]]) {
  const session = createSession({ streaming: true });
  assert.deepEqual(session.append(chunks[0]).blocks, []);
  assert.equal(session.append(chunks[1]).blocks[0].html, "<p>😀</p>\n");
  session.close();
}
