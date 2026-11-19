const std = @import("std");

pub const Rule = struct {
    tag: []const u8,
    open: []const u8 = "",
    close: []const u8 = "",
    prefix: []const u8 = "",
    fence: []const u8 = "",
    parsed: bool = false,
};

pub fn valid(rule: Rule) bool {
    if (rule.tag.len == 0 or rule.tag.len > 64 or !std.ascii.isLower(rule.tag[0])) return false;
    for (rule.tag) |ch| {
        if (!std.ascii.isLower(ch) and !std.ascii.isDigit(ch) and ch != '-') return false;
    }
    const kinds = @as(u8, @intFromBool(rule.open.len != 0)) +
        @as(u8, @intFromBool(rule.prefix.len != 0)) + @as(u8, @intFromBool(rule.fence.len != 0));
    return kinds == 1 and (rule.open.len == 0) == (rule.close.len == 0);
}
