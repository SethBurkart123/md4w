import assert from "node:assert/strict";
import { createSession, init } from "../js/index.js";

await init();
assert.throws(() => createSession({ rules: [{ tag: "bad tag", prefix: "!" }] }));
const session = createSession({ rules: [
  { tag: "value", open: "{{", close: "}}" },
  { tag: "note", open: "^^", close: "^^", parsed: true },
  { tag: "line", prefix: ":: " },
  { tag: "diagram", fence: "tikz" },
] });
const { blocks } = session.append(":: <x>\n\n{{&}} ^^*hi*^^\n\n```tikz\n<b>\n```");
assert.equal(blocks[0].html, '<x-line data-start="0" data-end="6">&lt;x&gt;</x-line>');
assert.match(blocks[1].html, /<x-value [^>]+>&amp;<\/x-value>/);
assert.match(blocks[1].html, /<x-note [^>]+><em>hi<\/em><\/x-note>/);
assert.match(blocks[2].html, /<x-diagram [^>]+>&lt;b&gt;\n<\/x-diagram>/);
session.close();
