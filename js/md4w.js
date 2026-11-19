const enc = new TextEncoder();
const dec = new TextDecoder();

let wasm;
let emit;
let highlighter;

/**
 * ParseFlags is a set of flags for md4c parser.
 */
export const ParseFlags = Object.freeze({
  /** Collapse non-trivial whitespace into single space. */
  COLLAPSE_WHITESPACE: 0x0001,
  /** Do not require space in ATX headers ( ###header ) */
  PERMISSIVE_ATX_HEADERS: 0x0002,
  /** Recognize URLs as links. */
  PERMISSIVE_URL_AUTO_LINKS: 0x0004,
  /** Recognize e-mails as links.*/
  PERMISSIVE_EMAIL_AUTO_LINKS: 0x0008,
  /** Disable indented code blocks. (Only fenced code works.) */
  NO_INDENTED_CODE_BLOCKS: 0x0010,
  /** Disable raw HTML blocks. */
  NO_HTML_BLOCKS: 0x0020,
  /** Disable raw HTML (inline). */
  NO_HTML_SPANS: 0x0040,
  /** Support GitHub-style tables. */
  TABLES: 0x0100,
  /** Support strike-through spans (text enclosed in tilde marks, e.g. ~foo bar~). */
  STRIKETHROUGH: 0x0200,
  /** Support WWW autolinks (without proto; just 'www.') */
  PERMISSIVE_WWW_AUTO_LINKS: 0x0400,
  /** Support GitHub-style task lists. */
  TASKLISTS: 0x0800,
  /** Support LaTeX math spans ($...$) and LaTeX display math spans ($$...$$) are supported. (Note though that the HTML renderer outputs them verbatim in a custom tag <x-equation>.) */
  LATEX_MATH_SPANS: 0x1000,
  /** Support wiki-style links ([[link label]] and [[target article|link label]]) are supported. (Note that the HTML renderer outputs them in a custom tag <x-wikilink>.) */
  WIKI_LINKS: 0x2000,
  /** Denotes an underline instead of an ordinary emphasis or strong emphasis. */
  UNDERLINE: 0x4000,
  /** Using hard line breaks. */
  HARD_SOFT_BREAKS: 0x8000,
  /** Shorthand for NO_HTML_BLOCKS | NO_HTML_SPANS */
  NO_HTML: 0x00200 | 0x0040,
  /** Default flags: COLLAPSE_WHITESPACE | PERMISSIVE_ATX_HEADERS | PERMISSIVE_URL_AUTO_LINKS | STRIKETHROUGH | TABLES | TASK_LISTS */
  DEFAULT: 0x0001 | 0x0002 | 0x0004 | 0x0100 | 0x0200 | 0x0800,
});

/**
 * NodeType is a type of the markdown node.
 */
export const NodeType = Object.freeze({
  QUOTE: 1,
  UL: 2,
  OL: 3,
  LI: 4,
  HR: 5,
  CODE_BLOCK: 7,
  HTML: 8,
  P: 9,
  TABLE: 10,
  THEAD: 11,
  TBODY: 12,
  TR: 13,
  TH: 14,
  TD: 15,
  H1: 21,
  H2: 22,
  H3: 23,
  H4: 24,
  H5: 25,
  H6: 26,
  EM: 30,
  STRONG: 31,
  A: 32,
  IMG: 33,
  CODE_SPAN: 34,
  DEL: 35,
  LATEXMATH: 36,
  LATEXMATH_DISPLAY: 37,
  WIKILINK: 38,
  U: 39,
});

/**
 * Validates the parse flags.
 * @param {number | object} parseFlags
 * @returns {number} validated parse flags
 */
function validateParseFlags(parseFlags) {
  if (typeof parseFlags === "number") {
    return parseFlags;
  }
  if (typeof parseFlags === "object" && parseFlags !== null) {
    const keys = (Array.isArray(parseFlags)
      ? parseFlags
      : Object.entries(parseFlags).filter(([, v]) =>
        !!v
      ).map(([k]) => k)).filter((k) => k in ParseFlags);
    return keys.reduce((acc, k) => acc | ParseFlags[k], 0);
  }
  return ParseFlags.DEFAULT;
}

/**
 * readMem returns a Uint8Array view of the wasm memory.
 *
 * @param {bigint} ptrLen pointer(32-bit) and length(32-bit) encoded as a single 64-bit int (BigInt)
 * @returns {Uint8Array} view of the wasm memory
 */
const readMem = (ptrLen) => {
  const ptr = Number(ptrLen & 0xffffffffn);
  const len = Number(ptrLen >> 32n);
  return new Uint8Array(wasm.memory.buffer, ptr, len);
};

/**
 * allocMem allocates memory in Zig and copies the data into it
 *
 * @param {Uint8Array} data data to be copied into the memory
 * @returns {bigint} pointer(32-bit) and length(32-bit) encoded as a single 64-bit int (BigInt)
 */
const allocMem = (data) => {
  const ptrLen = wasm.allocMem(data.length); // ask Zig to allocate memory with the given data length
  if (!data.length) return ptrLen;
  const mem = readMem(ptrLen);
  mem.set(data);
  return ptrLen;
};

/**
 * Render markdown to string.
 * @param {string | Uint8Array} input markdown input
 * @param {import("./md4w").Options} options parse options
 * @param {number} renderer 0 for html, 2 for json
 * @returns {string}
 */
export function renderToString(input, options = {}, renderer = 0) {
  const data = typeof input === "string" ? enc.encode(input) : input;
  if (!(data instanceof Uint8Array)) {
    throw new TypeError("input must be a string or Uint8Array");
  }
  const estHtmlSize = Math.ceil(data.length * 1.5);
  return collectOutput(renderer, estHtmlSize, () => wasm.render(
    allocMem(data), validateParseFlags(options.parseFlags), Math.max(estHtmlSize, 512),
    typeof highlighter === "function" ? 1 : 0, renderer,
  ));
}

function collectOutput(renderer, estHtmlSize, render) {
  let buffer = new Uint8Array(estHtmlSize);
  let len = 0;
  const starts = [];
  if (renderer === 3) beginBlock = offset => starts.push({ offset, index: len });
  emit = (chunk) => {
    const chunkSize = chunk.length;
    if (len + chunkSize > buffer.length) {
      const newBuffer = new Uint8Array(Math.ceil((len + chunkSize) * 1.5));
      newBuffer.set(buffer.subarray(0, len));
      buffer = newBuffer;
    }
    buffer.set(chunk, len);
    len += chunkSize;
  };
  const ptrLen = render();
  if (ptrLen === -1n) {
    emit = beginBlock = null;
    return null;
  }
  if (ptrLen) emit(readMem(ptrLen));
  emit = null;
  if (renderer === 3) {
    beginBlock = null;
    return starts.map(({ offset, index }, i) => {
      const next = starts[i + 1];
      const html = dec.decode(buffer.subarray(index, next ? next.index : len));
      const bytes = buffer.subarray(index, next ? next.index : len);
      let hash = 2166136261;
      for (const byte of bytes) hash = Math.imul(hash ^ byte, 16777619);
      return { offset, id: offset + "-" + (hash >>> 0).toString(16), html };
    });
  }
  return dec.decode(buffer.subarray(0, len));
}

/**
 * Converts markdown to html.
 * @param {string | Uint8Array} input markdown input
 * @param {import("./md4w").Options} options parse options
 * @returns {string} html output
 */
export function mdToHtml(input, options = {}) {
  return renderToString(input, options);
}

/**
 * Converts markdown to html as a readable stream.
 * @param {string | Uint8Array} input markdown input
 * @param {import("./md4w").Options} options parse options
 * @returns {ReadableStream<Uint8Array>} readable stream of html output
 */
export function mdToReadableHtml(input, options = {}) {
  return new ReadableStream({
    start(controller) {
      Promise.resolve().then(() => {
        emit = (chunk) => controller.enqueue(new Uint8Array(chunk));
        const ptrLen = wasm.render(
          allocMem(typeof input === "string" ? enc.encode(input) : input),
          validateParseFlags(options.parseFlags),
          Math.max(1024, Number(options.bufferSize) || 4 * 1024),
          typeof highlighter === "function" ? 1 : 0,
          0, // html
        );
        emit(new Uint8Array(readMem(ptrLen)));
        emit = null;
        controller.close();
      });
    },
  });
}

/**
 * Converts markdown to json.
 * @param {string | Uint8Array} input markdown input
 * @param {import("./md4w").Options} options parse options
 * @returns {import("./md4w").MDTree} json output
 */
export function mdToJSON(input, options = {}) {
  const output = renderToString(input, options, 2);
  const children = JSON.parse(output);
  return { children };
}

/**
 * Sets the code highlighter for the code blocks.
 * @param {import("./md4w").CodeHighlighter} codeHighlighter
 * @returns {void}
 */
export function setCodeHighlighter(codeHighlighter) {
  highlighter = codeHighlighter;
}

/**
 * Initializes the wasm module.
 * @param {WebAssembly.Module | { allocMem: CallableFunction }} wasmModule
 * @returns {void}
 */
let beginBlock;

export function initWasm(wasmModule) {
  const env = {
    beginBlock: offset => beginBlock(offset),
    emitChunk: (ptrLen) => {
      emit(readMem(ptrLen));
    },
    emitCodeBlock: (languagePtrLen, codePtrLen) => {
      const language = readMem(languagePtrLen);
      const code = readMem(codePtrLen);
      const output = highlighter(dec.decode(language), dec.decode(code));
      emit(enc.encode(output));
    },
  };
  if (wasmModule instanceof WebAssembly.Module) {
    const instance = new WebAssembly.Instance(wasmModule, { env });
    wasm = instance.exports;
  } else if (wasmModule.default && wasmModule.allocMem) {
    // unwasm specific
    wasmModule.default(env);
    wasm = wasmModule;
  }
}

export function parseWithBoundary(input, options) {
  const html = mdToHtml(input, options);
  const result = wasm.parseBoundary();
  return { html, finishedBytes: Number(result & 0xffffffffn), definitionsSeen: result >> 32n !== 0n };
}

export function parseBlocks(input, options) {
  return renderToString(input, options, 3);
}

export function createSession(options = {}) {
  const instance = wasm;
  let handle = instance.openSession();
  let length = 0;
  let boundary = 0;
  let stringLength = 0;
  let highSurrogate = "";
  const flags = validateParseFlags(options.parseFlags);

  function write(input, from) {
    if (!handle || wasm !== instance) throw new Error("Inactive markdown session");
    const bytes = typeof input === "string" ? enc.encode(input) : input;
    if (!(bytes instanceof Uint8Array)) throw new TypeError("Expected markdown text or bytes");
    length = from + bytes.length;
    const ptr = instance.resizeSource(handle, length);
    if (bytes.length) new Uint8Array(instance.memory.buffer, ptr + from, bytes.length).set(bytes);
    let replaceFrom = boundary <= from ? boundary : 0;
    const render = () => collectOutput(3, Math.max(256, length - replaceFrom), () =>
      instance.renderSession(handle, replaceFrom, flags, typeof highlighter === "function" ? 1 : 0));
    let blocks = render();
    const rebuild = blocks === null;
    if (rebuild) {
      replaceFrom = 0;
      blocks = render();
    }
    const result = instance.parseBoundary();
    boundary = Number(result & 0xffffffffn);
    return { replaceFrom, finishedBytes: boundary, definitionsSeen: rebuild || result >> 32n !== 0n,
      blocks, finishedIds: blocks.filter(b => b.offset < boundary).map(b => b.id) };
  }

  function append(input) {
    let from = length;
    if (typeof input === "string") {
      if (stringLength !== null) stringLength += input.length;
      if (highSurrogate) {
        input = highSurrogate + input;
        from -= 3;
      }
      const last = input.charCodeAt(input.length - 1);
      highSurrogate = last >= 0xd800 && last <= 0xdbff ? input.slice(-1) : "";
    } else {
      stringLength = null;
      highSurrogate = "";
    }
    return write(input, from);
  }

  return {
    append,
    update(full) {
      if (typeof full === "string" && stringLength === null) throw new Error("Use reset to switch input types");
      const end = typeof full === "string" ? stringLength : length;
      return full.length < end ? this.reset(full) : append(full.slice(end));
    },
    edit(from, input) {
      if (!Number.isInteger(from) || from < 0 || from > length) throw new RangeError("Invalid source byte offset");
      stringLength = null;
      highSurrogate = "";
      return write(input, from);
    },
    reset(input) {
      length = boundary = stringLength = 0;
      highSurrogate = "";
      return append(input);
    },
    close() {
      if (handle) instance.closeSession(handle);
      handle = 0;
    },
  };
}
