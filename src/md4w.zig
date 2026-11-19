const std = @import("std");
const c = @cImport({
    @cInclude("session.h");
});

const rule_spec = @import("rules.zig");
const Rule = rule_spec.Rule;
const allocator = std.heap.wasm_allocator;

// js functions
const js = struct {
    pub extern fn beginBlock(offset: u32) void;
    pub extern fn emitChunk(ptr_len: u64) void;
    pub extern fn emitCodeBlock(language_ptr_len: u64, code_ptr_len: u64) void;
};

/// slugCharMap is a map of ASCII characters to their corresponding slug character.
/// copied from https://github.com/rsms/markdown-wasm/blob/0d99d1151ff4d929a8ac8f3a191bfec54a10a869/src/fmt_html.c#L120C1-L138C3
const slugCharMap = [256]u8{
    '-', '-', '-', '-', '-', '-', '-', '-', '-', '-', '-', '-', '-', '-', '-', '-', // <CTRL> ...
    '-', '-', '-', '-', '-', '-', '-', '-', '-', '-', '-', '-', '-', '-', '-', '-', // <CTRL> ...
    '-', '-', '-', '-', '-', '-', '-', '-', '-', '-', '-', '-', '-', '-', '.', '-', //   ! " # $ % & ' ( ) * + , - . /
    '0', '1', '2', '3', '4', '5', '6', '7', '8', '9', '-', '-', '-', '-', '-', '-', // 0 1 2 3 4 5 6 7 8 9 : ; < = > ?
    '-', 'a', 'b', 'c', 'd', 'e', 'f', 'g', 'h', 'i', 'j', 'k', 'l', 'm', 'n', 'o', // @ A B C D E F G H I J K L M N O
    'p', 'q', 'r', 's', 't', 'u', 'v', 'w', 'x', 'y', 'z', '-', '-', '-', '-', '_', // P Q R S T U V W X Y Z [ \ ] ^ _
    '-', 'a', 'b', 'c', 'd', 'e', 'f', 'g', 'h', 'i', 'j', 'k', 'l', 'm', 'n', 'o', // ` a b c d e f g h i j k l m n o
    'p', 'q', 'r', 's', 't', 'u', 'v', 'w', 'x', 'y', 'z', '-', '-', '-', '-', '-', // p q r s t u v w x y z { | } ~ <DEL>
    '-', '-', '-', '-', '-', '-', '-', '-', '-', '-', '-', '-', '-', '-', '-', '-', // <CTRL> ...
    '-', '-', '-', '-', '-', '-', '-', '-', '-', '-', '-', '-', '-', '-', '-', '-', // <CTRL> ...
    '-', '-', '-', '-', '-', '-', '-', '-', '-', '-', '-', '-', '-', '-', '-', '-', // <NBSP> ¡ ¢ £ ¤ ¥ ¦ § ¨ © ª « ¬ <SOFTHYPEN> ® ¯
    '-', '-', '-', '-', '-', '-', '-', '-', '-', '-', '-', '-', '-', '-', '-', '-', // ° ± ² ³ ´ µ ¶ · ¸ ¹ º » ¼ ½ ¾ ¿
    'a', 'a', 'a', 'a', 'a', 'a', 'a', 'c', 'e', 'e', 'e', 'e', 'i', 'i', 'i', 'i', // À Á Â Ã Ä Å Æ Ç È É Ê Ë Ì Í Î Ï
    'd', 'n', 'o', 'o', 'o', 'o', 'o', 'x', 'o', 'u', 'u', 'u', 'u', 'y', '-', 's', // Ð Ñ Ò Ó Ô Õ Ö × Ø Ù Ú Û Ü Ý Þ ß
    'a', 'a', 'a', 'a', 'a', 'a', 'a', 'c', 'e', 'e', 'e', 'e', 'i', 'i', 'i', 'i', // à á â ã ä å æ ç è é ê ë ì í î ï
    'd', 'n', 'o', 'o', 'o', 'o', 'o', '-', 'o', 'u', 'u', 'u', 'u', 'y', '-', 'y', // ð ñ ò ó ô õ ö ÷ ø ù ú û ü ý þ ÿ
};

/// The writer handles the output of the md4c parser
const Writer = struct {
    rules: []const Rule = &.{},
    missing_close_end: [64]usize = [_]usize{0} ** 64,
    missing_close_start: [64]usize = [_]usize{0} ** 64,
    link_depth: usize = 0,
    blocks: bool = false,
    boundary: u32 = 0,
    proof: u32 = 0,
    definitions: bool = false,
    buf: []u8 = undefined,
    len: usize = 0,
    slug: []u8 = undefined,
    slug_len: usize = 0,
    code: []u8 = undefined,
    code_len: usize = 0,
    code_no_lang: bool = false,
    current_block: c.MD_BLOCKTYPE = 0,
    image_nesting_level: usize = 0,
    has_code_highlighter: bool = false,
    pub fn init(buffer_size: usize, has_code_highlighter: bool) Writer {
        var writer = Writer{
            .buf = allocator.alloc(u8, buffer_size) catch unreachable,
            .slug = allocator.alloc(u8, 512) catch unreachable,
            .has_code_highlighter = has_code_highlighter,
        };
        if (has_code_highlighter) {
            writer.code = allocator.alloc(u8, 1024) catch unreachable;
        }
        return writer;
    }
    pub fn deinit(self: *Writer) void {
        allocator.free(self.buf);
        allocator.free(self.slug);
        if (self.has_code_highlighter) {
            allocator.free(self.code);
        }
    }
    pub fn flush(self: *Writer) void {
        js.emitChunk(toPtrLen(self.buf[0..self.len]));
        self.len = 0;
    }
    pub fn writeByte(self: *Writer, byte: u8) void {
        if (self.len >= self.buf.len) {
            self.flush();
        }
        self.buf[self.len] = byte;
        self.len += 1;
    }
    pub fn write(self: *Writer, chunk: []const u8) void {
        if (chunk.len >= self.buf.len) {
            if (self.len > 0) {
                self.flush();
            }
            js.emitChunk(toPtrLen(chunk));
            return;
        }
        if (self.len + chunk.len > self.buf.len) {
            self.flush();
        }
        std.mem.copyForwards(u8, self.buf[self.len..], chunk);
        self.len += chunk.len;
    }
    pub fn writeNumber(self: *Writer, number: anytype) void {
        var buffer: [20]u8 = undefined;
        const buf = buffer[0..];
        self.write(std.fmt.bufPrintIntToSlice(buf, number, 10, .lower, .{}));
    }
    fn writeListStart(self: *Writer, start: usize) void {
        // Preserve the four-digit list starts emitted by the original renderer.
        var prefix = start;
        while (prefix >= 10000) prefix /= 10;
        self.writeNumber(prefix);
    }

    fn safeWriteChar(self: *Writer, ch: u8) void {
        switch (ch) {
            '<' => self.write("&lt;"),
            '>' => self.write("&gt;"),
            '&' => self.write("&amp;"),
            '"' => self.write("&quot;"),
            else => self.writeByte(ch),
        }
    }
    pub fn safeWrite(self: *Writer, chunk: []const u8) void {
        var start: usize = 0;
        while (true) {
            var i = start;
            loop: while (i < chunk.len) {
                switch (chunk[i]) {
                    '<', '>', '&', '"' => break :loop,
                    else => i += 1,
                }
            }
            self.write(chunk[start..i]);
            if (i == chunk.len) {
                break;
            }
            self.safeWriteChar(chunk[i]);
            start = i + 1;
        }
    }
    fn safeWriteUrlChar(self: *Writer, ch: u8) void {
        switch (ch) {
            'A'...'Z', 'a'...'z', '0'...'9', '_', '$', '@', ':', '+', '-', '*', '/', '.', ',', ';', '~', '=', '?', '!', '#', '&', '%', '(', ')', '[', ']' => self.writeByte(ch),
            else => {
                var buf: [2]u8 = undefined;
                _ = std.fmt.bufPrint(&buf, "{X:0>2}", .{ch}) catch unreachable;
                self.writeByte('%');
                self.writeByte(buf[0]);
                self.writeByte(buf[1]);
            },
        }
    }
    pub fn safeWriteUrl(self: *Writer, input: []const u8) void {
        for (input) |ch| {
            self.safeWriteUrlChar(ch);
        }
    }
    pub fn updateSlug(self: *Writer, ch: u8) void {
        // skip if the last character is already a hyphen
        if (ch == '-' and (self.slug_len == 0 or self.slug[self.slug_len - 1] == '-')) {
            return;
        }
        if (self.slug_len < self.slug.len) {
            self.slug[self.slug_len] = ch;
            self.slug_len += 1;
        }
    }
    pub fn getSlug(self: *Writer) []const u8 {
        // strip trailing hyphen
        if (self.slug_len > 0 and self.slug[self.slug_len - 1] == '-') {
            return self.slug[0 .. self.slug_len - 1];
        }
        return self.slug[0..self.slug_len];
    }
    pub fn updateCode(self: *Writer, chunk: []const u8) void {
        const new_size = self.code_len + chunk.len;
        if (new_size > self.code.len) {
            self.code = allocator.realloc(self.code, new_size + 1024) catch unreachable;
        }
        std.mem.copyForwards(u8, self.code[self.code_len..], chunk);
        self.code_len = new_size;
    }
    pub fn writeJSONType(self: *Writer, typ: c.MD_BLOCKTYPE) void {
        self.write("{\"type\":");
        self.writeNumber(@as(u8, @intCast(typ)));
    }
    pub fn writeJSONChildren(self: *Writer) void {
        self.write(",\"children\":[");
    }
    pub fn writeJSONTypeAndChildren(self: *Writer, typ: c.MD_BLOCKTYPE) void {
        self.writeJSONType(typ);
        self.writeJSONChildren();
    }
    pub fn writeJSONProps(self: *Writer) void {
        self.write(",\"props\":{");
    }
    pub fn writeJSONString(self: *Writer, input: []const u8, escape: u2) void {
        for (input) |ch| switch (ch) {
            '"', '\\' => {
                self.writeByte('\\');
                self.writeByte(ch);
            },
            '\n' => self.write("\\n"),
            '\r' => self.write("\\r"),
            '\t' => self.write("\\t"),
            else => switch (escape) {
                0 => self.writeByte(ch),
                1 => self.safeWriteChar(ch),
                2 => self.safeWriteUrlChar(ch),
                else => unreachable,
            },
        };
    }
    pub fn stripTrailingComma(self: *Writer) void {
        if (self.buf[self.len - 1] == ',') {
            self.len -= 1;
        }
    }
};

/// Render markdown to html
const HTMLRenderer = struct {
    pub fn enterBlock(
        typ: c.MD_BLOCKTYPE,
        detail: ?*anyopaque,
        userdata: ?*anyopaque,
    ) callconv(.C) c_int {
        const w: *Writer = @ptrCast(@alignCast(userdata));
        w.current_block = typ;

        switch (typ) {
            c.MD_BLOCK_DOC => {
                // skip
            },
            c.MD_BLOCK_QUOTE => w.write("<blockquote>\n"),
            c.MD_BLOCK_UL => w.write("<ul>\n"),
            c.MD_BLOCK_OL => {
                const ol: *c.MD_BLOCK_OL_DETAIL = @ptrCast(@alignCast(detail));
                if (ol.start > 1) {
                    w.write("<ol start=\"");
                    w.writeListStart(@intCast(ol.start));
                    w.write("\">\n");
                } else {
                    w.write("<ol>\n");
                }
            },
            c.MD_BLOCK_LI => {
                const li: *c.MD_BLOCK_LI_DETAIL = @ptrCast(@alignCast(detail));
                if (li.is_task > 0) {
                    w.write("<li class=\"task-list-item\"><input type=\"checkbox\" class=\"task-list-item-checkbox\"");
                    if (li.task_mark == 'x' or li.task_mark == 'X') {
                        w.write(" checked");
                    }
                    w.write(" disabled>");
                } else {
                    w.write("<li>");
                }
            },
            c.MD_BLOCK_HR => w.write("<hr>\n"),
            c.MD_BLOCK_H => {
                const h: *c.MD_BLOCK_H_DETAIL = @ptrCast(@alignCast(detail));
                w.write("<h");
                w.writeByte('0' + @as(u8, @intCast(h.level)));
                w.writeByte('>');
            },
            c.MD_BLOCK_CODE => {
                const code: *c.MD_BLOCK_CODE_DETAIL = @ptrCast(@alignCast(detail));
                w.code_no_lang = code.lang.size == 0;
                if (!w.has_code_highlighter or w.code_no_lang) {
                    w.write("<pre><code");
                    if (code.lang.size > 0) {
                        const lang = @as([*]const u8, @ptrCast(code.lang.text))[0..code.lang.size];
                        w.write(" class=\"language-");
                        w.writeJSONString(lang, 1);
                        w.writeByte('"');
                    }
                    w.writeByte('>');
                }
            },
            c.MD_BLOCK_HTML => {
                // skip
            },
            c.MD_BLOCK_P => w.write("<p>"),
            c.MD_BLOCK_TABLE => w.write("<table>\n"),
            c.MD_BLOCK_THEAD => w.write("<thead>\n"),
            c.MD_BLOCK_TBODY => w.write("<tbody>\n"),
            c.MD_BLOCK_TR => w.write("<tr>\n"),
            c.MD_BLOCK_TH, c.MD_BLOCK_TD => {
                const td: *c.MD_BLOCK_TD_DETAIL = @ptrCast(@alignCast(detail));
                if (typ == c.MD_BLOCK_TH) {
                    w.write("<th");
                } else {
                    w.write("<td");
                }
                switch (td.@"align") {
                    c.MD_ALIGN_LEFT => w.write(" align=\"left\">"),
                    c.MD_ALIGN_CENTER => w.write(" align=\"center\">"),
                    c.MD_ALIGN_RIGHT => w.write(" align=\"right\">"),
                    else => w.writeByte('>'),
                }
            },
            else => {},
        }

        return 0;
    }

    pub fn leaveBlock(
        typ: c.MD_BLOCKTYPE,
        detail: ?*anyopaque,
        userdata: ?*anyopaque,
    ) callconv(.C) c_int {
        const w: *Writer = @ptrCast(@alignCast(userdata));
        w.current_block = 0;

        switch (typ) {
            c.MD_BLOCK_DOC => {
                // skip
            },
            c.MD_BLOCK_QUOTE => w.write("</blockquote>\n"),
            c.MD_BLOCK_UL => w.write("</ul>\n"),
            c.MD_BLOCK_OL => w.write("</ol>\n"),
            c.MD_BLOCK_LI => w.write("</li>\n"),
            c.MD_BLOCK_HR => {
                // skip
            },
            c.MD_BLOCK_H => {
                const h: *c.MD_BLOCK_H_DETAIL = @ptrCast(@alignCast(detail));
                const slug = w.getSlug();
                w.write(" <a class=\"anchor\" aria-hidden=\"true\" id=\"");
                w.safeWriteUrl(slug);
                w.write("\" href=\"#");
                w.safeWriteUrl(slug);
                w.write("\"></a></h");
                w.writeByte('0' + @as(u8, @intCast(h.level)));
                w.write(">\n");
                w.slug_len = 0;
            },
            c.MD_BLOCK_CODE => {
                const code: *c.MD_BLOCK_CODE_DETAIL = @ptrCast(@alignCast(detail));
                if (!w.has_code_highlighter or code.lang.size == 0) {
                    w.write("</code></pre>\n");
                } else if (w.code_len > 0) {
                    const lang = @as([*]const u8, @ptrCast(code.lang.text))[0..code.lang.size];
                    if (w.len > 0) {
                        // flush the buffer if not empty
                        w.flush();
                    }
                    js.emitCodeBlock(toPtrLen(lang), toPtrLen(w.code[0..w.code_len]));
                    w.code_len = 0;
                }
                w.code_no_lang = false;
            },
            c.MD_BLOCK_HTML => {
                // skip
            },
            c.MD_BLOCK_P => w.write("</p>\n"),
            c.MD_BLOCK_TABLE => w.write("</table>\n"),
            c.MD_BLOCK_THEAD => w.write("</thead>\n"),
            c.MD_BLOCK_TBODY => w.write("</tbody>\n"),
            c.MD_BLOCK_TR => w.write("</tr>\n"),
            c.MD_BLOCK_TH => w.write("</th>\n"),
            c.MD_BLOCK_TD => w.write("</td>\n"),
            else => {},
        }

        return 0;
    }

    pub fn enterSpan(
        typ: c.MD_SPANTYPE,
        detail: ?*anyopaque,
        userdata: ?*anyopaque,
    ) callconv(.C) c_int {
        const w: *Writer = @ptrCast(@alignCast(userdata));
        const inside_img = w.image_nesting_level > 0;

        if (typ == c.MD_SPAN_IMG)
            w.image_nesting_level += 1;
        if (inside_img)
            return 0;

        switch (typ) {
            c.MD_SPAN_EM => w.write("<em>"),
            c.MD_SPAN_STRONG => w.write("<strong>"),
            c.MD_SPAN_A => {
                w.link_depth += 1;
                if (w.link_depth > 1) return 0;
                const a: *c.MD_SPAN_A_DETAIL = @ptrCast(@alignCast(detail));
                w.write("<a href=\"");
                w.safeWriteUrl(@as([*]const u8, @ptrCast(a.href.text))[0..a.href.size]);
                if (a.title.size > 0) {
                    w.write("\" title=\"");
                    w.safeWrite(@as([*]const u8, @ptrCast(a.title.text))[0..a.title.size]);
                }
                w.write("\">");
            },
            c.MD_SPAN_IMG => {
                const img: *c.MD_SPAN_IMG_DETAIL = @ptrCast(@alignCast(detail));
                w.write("<img src=\"");
                w.safeWriteUrl(@as([*]const u8, @ptrCast(img.src.text))[0..img.src.size]);
                w.write("\" alt=\""); // alt text will be added in the text callback
            },
            c.MD_SPAN_CODE => w.write("<code>"),
            c.MD_SPAN_DEL => w.write("<del>"),
            c.MD_SPAN_LATEXMATH => w.write("<x-equation>"),
            c.MD_SPAN_LATEXMATH_DISPLAY => w.write("<x-equation type=\"display\">"),
            c.MD_SPAN_WIKILINK => {
                const wikilink: *c.MD_SPAN_WIKILINK_DETAIL = @ptrCast(@alignCast(detail));
                w.write("<x-wikilink data-target=\"");
                w.safeWriteUrl(@as([*]const u8, @ptrCast(wikilink.target.text))[0..wikilink.target.size]);
                w.write("\">");
            },
            c.MD_SPAN_U => w.write("<u>"),
            else => {},
        }

        return 0;
    }

    pub fn leaveSpan(
        typ: c.MD_SPANTYPE,
        detail: ?*anyopaque,
        userdata: ?*anyopaque,
    ) callconv(.C) c_int {
        const w: *Writer = @ptrCast(@alignCast(userdata));

        if (typ == c.MD_SPAN_IMG)
            w.image_nesting_level -= 1;
        if (w.image_nesting_level > 0)
            return 0;

        switch (typ) {
            c.MD_SPAN_EM => w.write("</em>"),
            c.MD_SPAN_STRONG => w.write("</strong>"),
            c.MD_SPAN_A => {
                w.link_depth -= 1;
                if (w.link_depth == 0) w.write("</a>");
            },
            c.MD_SPAN_IMG => {
                const img: *c.MD_SPAN_IMG_DETAIL = @ptrCast(@alignCast(detail));
                if (img.title.size > 0) {
                    w.write("\" title=\"");
                    w.safeWrite(@as([*]const u8, @ptrCast(img.title.text))[0..img.title.size]);
                }
                w.write("\">");
            },
            c.MD_SPAN_CODE => w.write("</code>"),
            c.MD_SPAN_DEL => w.write("</del>"),
            c.MD_SPAN_LATEXMATH, c.MD_SPAN_LATEXMATH_DISPLAY => w.write("</x-equation>"),
            c.MD_SPAN_WIKILINK => w.write("</x-wikilink>"),
            c.MD_SPAN_U => w.write("</u>"),
            else => {},
        }

        return 0;
    }

    pub fn text(
        typ: c.MD_TEXTTYPE,
        ptr: [*c]const c.MD_CHAR,
        len: c.MD_SIZE,
        userdata: ?*anyopaque,
    ) callconv(.C) c_int {
        const w: *Writer = @ptrCast(@alignCast(userdata));

        if (w.current_block == c.MD_BLOCK_H and typ == c.MD_TEXT_NORMAL) {
            var i: usize = 0;
            while (i < len) {
                const textContent = @as([*]const u8, @ptrCast(ptr));
                const ch = textContent[i];
                const code_point_len = std.unicode.utf8ByteSequenceLength(ch) catch 0;
                if (code_point_len == 0 or code_point_len > len - i or
                    !std.unicode.utf8ValidateSlice(textContent[i .. i + code_point_len]))
                {
                    w.updateSlug('-');
                    i += 1;
                    continue;
                }
                if (code_point_len == 1) {
                    w.updateSlug(slugCharMap[ch]);
                } else {
                    // we keep the original character for non-ASCII characters
                    for (textContent[i .. i + code_point_len]) |code| {
                        w.updateSlug(code);
                    }
                }
                i += code_point_len;
            }
        }

        switch (typ) {
            c.MD_TEXT_NULLCHAR => w.writeByte(0),
            c.MD_TEXT_BR => w.write(if (w.image_nesting_level == 0) "<br>\n" else " "),
            c.MD_TEXT_SOFTBR => w.writeByte(if (w.image_nesting_level == 0) '\n' else ' '),
            // todo: decode entities
            c.MD_TEXT_ENTITY, c.MD_TEXT_HTML => w.write(@as([*]const u8, @ptrCast(ptr))[0..len]),
            c.MD_TEXT_CODE => {
                const code = @as([*]const u8, @ptrCast(ptr))[0..len];
                if (w.has_code_highlighter and w.current_block == c.MD_BLOCK_CODE and !w.code_no_lang) {
                    w.updateCode(code);
                } else {
                    w.safeWrite(code);
                }
            },
            c.MD_TEXT_NORMAL, c.MD_TEXT_LATEXMATH => {
                w.safeWrite(@as([*]const u8, @ptrCast(ptr))[0..len]);
            },
            else => {},
        }

        return 0;
    }
};

/// Render markdown to JSON
const JOSNRenderer = struct {
    pub fn enterBlock(
        typ: c.MD_BLOCKTYPE,
        detail: ?*anyopaque,
        userdata: ?*anyopaque,
    ) callconv(.C) c_int {
        const w: *Writer = @ptrCast(@alignCast(userdata));

        // skip the document block
        if (typ == c.MD_BLOCK_DOC) {
            return 0;
        }
        w.current_block = typ;

        switch (typ) {
            c.MD_BLOCK_OL => {
                const ol: *c.MD_BLOCK_OL_DETAIL = @ptrCast(@alignCast(detail));
                w.writeJSONType(typ);
                if (ol.start > 1) {
                    w.writeJSONProps();
                    w.write("\"start\":");
                    w.writeListStart(@intCast(ol.start));
                    w.writeByte('}');
                }
                w.writeJSONChildren();
            },
            c.MD_BLOCK_LI => {
                const li: *c.MD_BLOCK_LI_DETAIL = @ptrCast(@alignCast(detail));
                w.writeJSONType(typ);
                if (li.is_task > 0) {
                    w.writeJSONProps();
                    w.write("\"isTask\":true,\"done\":");
                    w.write(if (li.task_mark == 'x' or li.task_mark == 'X') "true" else "false");
                    w.writeByte('}');
                }
                w.writeJSONChildren();
            },
            c.MD_BLOCK_HR => w.write("{\"type\":5}"),
            c.MD_BLOCK_H => {
                const h: *c.MD_BLOCK_H_DETAIL = @ptrCast(@alignCast(detail));
                w.writeJSONTypeAndChildren(20 + h.level);
            },
            c.MD_BLOCK_CODE => {
                const code: *c.MD_BLOCK_CODE_DETAIL = @ptrCast(@alignCast(detail));
                w.writeJSONType(typ);
                if (code.lang.size > 0) {
                    w.writeJSONProps();
                    w.write("\"lang\":\"");
                    w.writeJSONString(@as([*]const u8, @ptrCast(code.lang.text))[0..code.lang.size], 1);
                    w.write("\"}");
                }
                w.writeJSONChildren();
            },
            c.MD_BLOCK_TH, c.MD_BLOCK_TD => {
                const td: *c.MD_BLOCK_TD_DETAIL = @ptrCast(@alignCast(detail));
                w.writeJSONType(typ);
                w.writeJSONProps();
                w.write("\"align\":\"");
                switch (td.@"align") {
                    c.MD_ALIGN_LEFT => w.write("left"),
                    c.MD_ALIGN_CENTER => w.write("center"),
                    c.MD_ALIGN_RIGHT => w.write("right"),
                    else => {},
                }
                w.write("\"}");
                w.writeJSONChildren();
            },
            else => w.writeJSONTypeAndChildren(typ),
        }

        return 0;
    }

    pub fn leaveBlock(
        typ: c.MD_BLOCKTYPE,
        detail: ?*anyopaque,
        userdata: ?*anyopaque,
    ) callconv(.C) c_int {
        const w: *Writer = @ptrCast(@alignCast(userdata));
        _ = detail;

        // skip the document block
        if (typ == c.MD_BLOCK_DOC) {
            return 0;
        }
        w.current_block = 0;

        if (typ == c.MD_BLOCK_HR) {
            w.writeByte(',');
        } else {
            w.stripTrailingComma();
            w.write("]},");
        }

        return 0;
    }

    pub fn enterSpan(
        typ: c.MD_SPANTYPE,
        detail: ?*anyopaque,
        userdata: ?*anyopaque,
    ) callconv(.C) c_int {
        const w: *Writer = @ptrCast(@alignCast(userdata));
        const inside_img = w.image_nesting_level > 0;

        if (typ == c.MD_SPAN_IMG)
            w.image_nesting_level += 1;
        if (inside_img)
            return 0;

        switch (typ) {
            c.MD_SPAN_A => {
                const a: *c.MD_SPAN_A_DETAIL = @ptrCast(@alignCast(detail));
                w.writeJSONType(30 + typ);
                w.writeJSONProps();
                w.write("\"href\":\"");
                w.writeJSONString(@as([*]const u8, @ptrCast(a.href.text))[0..a.href.size], 2);
                if (a.title.size > 0) {
                    w.write("\",\"title\":");
                    w.writeJSONString(@as([*]const u8, @ptrCast(a.title.text))[0..a.title.size], 1);
                }
                w.write("\"}");
                w.writeJSONChildren();
            },
            c.MD_SPAN_IMG => {
                const img: *c.MD_SPAN_IMG_DETAIL = @ptrCast(@alignCast(detail));
                w.writeJSONType(30 + typ);
                w.writeJSONProps();
                w.write("\"src\":\"");
                w.writeJSONString(@as([*]const u8, @ptrCast(img.src.text))[0..img.src.size], 2);
                w.write("\",\"alt\":"); // alt text will be added in the text callback
            },
            c.MD_SPAN_WIKILINK => {
                const wikilink: *c.MD_SPAN_WIKILINK_DETAIL = @ptrCast(@alignCast(detail));
                w.writeJSONType(30 + typ);
                w.writeJSONProps();
                w.write("\"target\":\"");
                w.writeJSONString(@as([*]const u8, @ptrCast(wikilink.target.text))[0..wikilink.target.size], 2);
                w.write("\"}");
                w.writeJSONChildren();
            },
            else => w.writeJSONTypeAndChildren(30 + typ),
        }

        return 0;
    }

    pub fn leaveSpan(
        typ: c.MD_SPANTYPE,
        detail: ?*anyopaque,
        userdata: ?*anyopaque,
    ) callconv(.C) c_int {
        const w: *Writer = @ptrCast(@alignCast(userdata));

        if (typ == c.MD_SPAN_IMG)
            w.image_nesting_level -= 1;
        if (w.image_nesting_level > 0)
            return 0;

        if (typ == c.MD_SPAN_IMG) {
            const img: *c.MD_SPAN_IMG_DETAIL = @ptrCast(@alignCast(detail));
            if (w.buf[w.len - 1] == ':') {
                w.write("\"\","); // no alt text
            }
            if (img.title.size > 0) {
                w.write("\"title\":\"");
                w.writeJSONString(@as([*]const u8, @ptrCast(img.title.text))[0..img.title.size], 1);
                w.write("\"");
            } else {
                w.stripTrailingComma();
            }
            w.write("}},");
        } else {
            w.stripTrailingComma();
            w.write("]},");
        }

        return 0;
    }

    pub fn text(
        typ: c.MD_TEXTTYPE,
        ptr: [*c]const c.MD_CHAR,
        len: c.MD_SIZE,
        userdata: ?*anyopaque,
    ) callconv(.C) c_int {
        const w: *Writer = @ptrCast(@alignCast(userdata));

        if (typ == c.MD_TEXT_NULLCHAR) {
            // ignore null character
            return 0;
        }

        switch (typ) {
            c.MD_TEXT_BR => {
                if (w.image_nesting_level == 0) {
                    w.writeJSONTypeAndChildren(c.MD_BLOCK_HTML);
                    w.write("\"<br>\\n\"]},");
                } else {
                    w.write("\" \",");
                }
            },
            c.MD_TEXT_SOFTBR => {
                if (w.image_nesting_level == 0) {
                    w.write("\"\\n\",");
                } else {
                    w.write("\" \",");
                }
            },
            c.MD_TEXT_HTML => {
                if (w.current_block == c.MD_BLOCK_HTML) {
                    w.writeByte('"');
                    w.writeJSONString(@as([*]const u8, @ptrCast(ptr))[0..len], 0);
                    w.write("\",");
                } else {
                    w.writeJSONTypeAndChildren(c.MD_BLOCK_HTML);
                    w.writeByte('"');
                    w.writeJSONString(@as([*]const u8, @ptrCast(ptr))[0..len], 0);
                    w.write("\"]},");
                }
            },
            else => {
                const escape: u2 = if ((typ == c.MD_TEXT_CODE and w.current_block == c.MD_BLOCK_CODE) or typ == c.MD_TEXT_ENTITY) 0 else 1;
                w.writeByte('"');
                w.writeJSONString(@as([*]const u8, @ptrCast(ptr))[0..len], escape);
                w.write("\",");
            },
        }

        return 0;
    }
};

/// allow the host to allocate memory
export fn allocMem(length: u32) u64 {
    return @as(u64, @bitCast([2]u32{
        @intFromPtr((allocator.alloc(u8, length) catch unreachable).ptr),
        length,
    }));
}

export fn md4w_rule_chars(w: *Writer, map: [*]u8) void {
    for (w.rules) |rule| {
        if (rule.open.len > 0) map[rule.open[0]] = 1;
    }
}

export fn md4w_match(w: *Writer, kind: c_int, ptr: [*]const u8, len: usize, matched: *u32) c_int {
    const text = ptr[0..len];
    for (w.rules, 0..) |rule, i| {
        const token = switch (kind) {
            0 => rule.open,
            1 => rule.prefix,
            else => rule.fence,
        };
        if (token.len == 0 or !std.mem.startsWith(u8, text, token)) continue;
        if (kind == 2 and token.len != len) continue;
        if (kind == 0) {
            const start = @intFromPtr(ptr);
            const end = start + len;
            if (start >= w.missing_close_start[i] and end <= w.missing_close_end[i]) continue;
            const index = std.mem.indexOfPos(u8, text, token.len, rule.close) orelse {
                w.missing_close_start[i] = start;
                w.missing_close_end[i] = end;
                continue;
            };
            matched.* = index + rule.close.len;
        } else matched.* = token.len;
        return @intCast(i);
    }
    return -1;
}

export fn md4w_inner(w: *Writer, id: c_int, _: [*]const u8, _: usize, left: *u32, right: *u32) c_int {
    const rule = w.rules[@intCast(id)];
    left.* = rule.open.len;
    right.* = rule.close.len;
    return @intFromBool(rule.parsed);
}

export fn md4w_tag(w: *Writer, id: c_int, start: u32, end: u32, closing: c_int) void {
    if (w.image_nesting_level > 0) return;
    w.write(if (closing != 0) "</x-" else "<x-");
    w.write(w.rules[@intCast(id)].tag);
    if (closing == 0) {
        w.write(" data-start=\"");
        w.writeNumber(start);
        w.write("\" data-end=\"");
        w.writeNumber(end);
        w.write("\"");
    }
    w.write(">");
}

export fn md4w_block(writer: *Writer, offset: u32) void {
    if (writer.blocks) {
        writer.flush();
        js.beginBlock(offset);
    }
}

export fn md4w_boundary(userdata: *Writer, offset: u32, proof: u32) void {
    userdata.boundary = offset;
    userdata.proof = proof;
}

export fn md4w_definitions(userdata: *Writer) void {
    userdata.definitions = true;
}

var last_proof: u32 = 0;
export fn boundaryProof() u32 {
    return last_proof;
}

var last_boundary: u64 = 0;

export fn parseBoundary() u64 {
    return last_boundary;
}

/// the main function to render markdown to html
export fn render(ptr_len: u64, flags: usize, buffer_size: usize, has_code_highlighter: usize, output_type: usize) u64 {
    const md = toSlice(ptr_len);
    defer allocator.free(md);

    return renderDocument(md, flags, buffer_size, has_code_highlighter, output_type, null, 0, &.{});
}

const Session = struct {
    source: std.ArrayList(u8),
    cache: *c.MD4W_SESSION,
    rules: ?std.json.Parsed([]Rule) = null,
};

export fn openSession() *Session {
    const session = allocator.create(Session) catch unreachable;
    session.* = .{ .source = std.ArrayList(u8).init(allocator), .cache = c.md4w_open().? };
    return session;
}

export fn setRules(session: *Session, ptr_len: u64) bool {
    const bytes = toSlice(ptr_len);
    defer allocator.free(bytes);
    const parsed = std.json.parseFromSlice([]Rule, allocator, bytes, .{ .allocate = .alloc_always }) catch return false;
    if (parsed.value.len <= 64) {
        for (parsed.value) |rule| {
            if (!rule_spec.valid(rule)) break;
        } else {
            session.rules = parsed;
            return true;
        }
    }
    parsed.deinit();
    return false;
}

export fn resizeSource(session: *Session, length: usize) [*]u8 {
    session.source.resize(length) catch unreachable;
    return session.source.items.ptr;
}

export fn closeSession(session: *Session) void {
    c.md4w_close(session.cache);
    session.source.deinit();
    if (session.rules) |rules| rules.deinit();
    allocator.destroy(session);
}

fn lastScalar(bytes: []const u8) ?u21 {
    if (bytes.len == 0) return null;
    var i = bytes.len - 1;
    while (i > 0 and bytes.len - i < 4 and bytes[i] & 0xc0 == 0x80) i -= 1;
    const width = std.unicode.utf8ByteSequenceLength(bytes[i]) catch return null;
    if (width != bytes.len - i) return null;
    return std.unicode.utf8Decode(bytes[i..]) catch null;
}

fn visibleEmojiEnd(tail: []const u8) usize {
    const last = lastScalar(tail) orelse return tail.len;
    switch (last) {
        0x200d => return tail.len - 3,
        0x20e3 => {
            var base = tail[0 .. tail.len - 3];
            if (lastScalar(base) == 0xfe0f) base = base[0 .. base.len - 3];
            if (base.len == 0 or std.mem.indexOfScalar(u8, "#*0123456789", base[base.len - 1]) == null)
                return tail.len - 3;
        },
        0x1f1e6...0x1f1ff => {
            var i = tail.len - 4;
            while (lastScalar(tail[0..i])) |previous| {
                if (previous < 0x1f1e6 or previous > 0x1f1ff) break;
                i -= 4;
            }
            if ((tail.len - i) % 8 != 0) return tail.len - 4;
        },
        else => {},
    }
    return tail.len;
}

export fn renderSession(session: *Session, start: u32, flags: u32, highlight: u32, visible_len: u32) u64 {
    var source = session.source.items[0..visible_len];
    if (flags & 0x10000000 != 0 and source.len > start) {
        var i = source.len - 1;
        while (i > start and source.len - i < 4 and source[i] & 0xc0 == 0x80) i -= 1;
        const width = std.unicode.utf8ByteSequenceLength(source[i]) catch 0;
        if (width > source.len - i) source = source[0..i];
        source = source[0 .. start + visibleEmojiEnd(source[start..])];
    }
    return renderDocument(source, flags, 4096, highlight, 3, session.cache, start, if (session.rules) |r| r.value else &.{});
}

fn renderDocument(md: []const u8, flags: usize, buffer_size: usize, has_code_highlighter: usize, output_type: usize, cache: ?*c.MD4W_SESSION, start: u32, rules: []const Rule) u64 {
    // todo: use global writer
    var writer = Writer.init(buffer_size, has_code_highlighter > 0);
    defer writer.deinit();

    var parser = c.MD_PARSER{
        .abi_version = 0,
        .flags = flags,
        .enter_block = HTMLRenderer.enterBlock,
        .leave_block = HTMLRenderer.leaveBlock,
        .enter_span = HTMLRenderer.enterSpan,
        .leave_span = HTMLRenderer.leaveSpan,
        .text = HTMLRenderer.text,
        .debug_log = null,
        .syntax = null,
    };

    writer.rules = rules;
    writer.boundary = start;
    writer.blocks = output_type == 3;
    const output_json = output_type == 2;
    if (output_json) {
        parser.enter_block = JOSNRenderer.enterBlock;
        parser.leave_block = JOSNRenderer.leaveBlock;
        parser.enter_span = JOSNRenderer.enterSpan;
        parser.leave_span = JOSNRenderer.leaveSpan;
        parser.text = JOSNRenderer.text;
    }

    if (output_json) {
        writer.writeByte('[');
    }

    const status = c.md4w_parse(
        md.ptr,
        @intCast(md.len),
        &parser,
        @ptrFromInt(@intFromPtr(&writer)),
        cache,
        start,
    );

    if (output_json) {
        writer.stripTrailingComma();
        writer.writeByte(']');
    }

    last_proof = writer.proof;
    last_boundary = @as(u64, @intFromBool(writer.definitions)) << 32 | writer.boundary;

    if (status < 0) unreachable;
    if (status > 0) return 0xffffffffffffffff;
    writer.flush();
    return 0;
}

/// get a slice from the pointer and length
fn toSlice(ptr_len: u64) []const u8 {
    const s = @as([2]u32, @bitCast(ptr_len));
    return @as([*]u8, @ptrFromInt(s[0]))[0..s[1]];
}

/// convert a slice to its pointer and length
fn toPtrLen(data: []const u8) u64 {
    return @as(u64, @bitCast([2]u32{
        @as(u32, @intFromPtr(data.ptr)),
        data.len,
    }));
}

// add libc compatibility layer for wasm target
usingnamespace @import("libc.zig");
