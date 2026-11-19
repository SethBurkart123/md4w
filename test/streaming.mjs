import assert from "node:assert/strict";
import { createSession, init, mdToHtml, mdToJSON } from "../js/index.js";

await init();
for (const [text, inner] of [
  ["*outer **inner", "<em>outer <strong>inner</strong></em>"],
  ["*outer **", "<em>outer</em>"],
  ["a `code", "a <code>code</code>"],
  ["a $x", "a <x-equation>x</x-equation>"],
  ["a ~~word", "a <del>word</del>"],
  ["[a half-wri", "<a>a half-wri</a>"],
  ["[label](https://exam", "<a>label</a>"],
  ["[label]", "<a>label</a>"],
  ["[a] and", "[a] and"],
  ["[a] [b", "[a] <a>b</a>"],
  ["see ![alt", "see"],
  ["see ![alt](https://x.test/a", "see"],
  ["![alt] and", "![alt] and"],
  ["see https://exam", "see https://exam"],
  ["see <https://exam", "see &lt;https://exam"],
  ["word *", "word"],
]) {
  const options = { streaming: true, parseFlags: ["LATEX_MATH_SPANS", "STRIKETHROUGH", "PERMISSIVE_URL_AUTO_LINKS"] };
  const session = createSession(options);
  assert.equal(session.append(text).blocks[0].html, "<p>" + inner + "</p>\n");
  assert.equal(session.finish().blocks[0].html, mdToHtml(text, options));
  session.close();
}

assert.deepEqual(mdToJSON("[a half", { parseFlags: 0x10000000 }), mdToJSON("[a half"));

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
  ["[x][ref", "<p><a>x</a></p>\n"], ["[x][ref] after", "<p><a>x</a> after</p>\n"],
  ["[a *b][ref] after", "<p><a>a *b</a> after</p>\n"], ["[a `b](https://x", "<p><a>a `b</a></p>\n"],
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
for (const [source, cell] of [["| *hello", "<em>hello</em>"], ["| [label](https://exam", "<a>label</a>"]]) {
  const session = createSession({ streaming: true });
  assert.ok(session.append(source).blocks[0].html.includes(`<th>${cell}</th>`), source);
  session.close();
}
for (const source of ["|", "| ", "| |"]) {
  const session = createSession({ streaming: true });
  assert.deepEqual(session.append(source).blocks, [], source);
  assert.equal(session.finish().blocks.map(b => b.html).join(""), mdToHtml(source), source);
  session.close();
}
for (const [source, options] of [["|", { parseFlags: 0 }], ["# |", {}]]) {
  const session = createSession({ streaming: true, ...options });
  assert.equal(session.append(source).blocks[0].html, mdToHtml(source, options), source);
  session.close();
}
const afterText = createSession({ streaming: true });
assert.equal(afterText.append("text\n\n|").blocks.map(b => b.html).join(""), "<p>text</p>\n");
afterText.close();
for (const source of ["text\n| a | b |", "a | b\n---|---"]) {
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
