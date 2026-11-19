const std = @import("std");

pub fn build(b: *std.Build) void {
    const patch = b.addSystemCommand(&.{ "patch", "-s", "-o" });
    const source = patch.addOutputFileArg("md4c.c");
    patch.addFileArg(.{ .path = "vendor/md4c/src/md4c.c" });
    patch.addFileArg(.{ .path = "patches/boundary.patch" });
    buildWasm(b, source, .ReleaseFast, "md4w-fast.wasm");
    buildWasm(b, source, .ReleaseSmall, "md4w-small.wasm");
}

pub fn buildWasm(b: *std.Build, source: std.Build.LazyPath, optimize: std.builtin.Mode, comptime wasm_name: []const u8) void {
    const lib = b.addSharedLibrary(.{
        .name = "md4w",
        .version = .{ .major = 0, .minor = 0, .patch = 1 },
        .root_source_file = .{ .path = "src/md4w.zig" },
        .target = .{ .cpu_arch = .wasm32, .os_tag = .freestanding },
        .optimize = optimize,
    });
    lib.addCSourceFile(.{ .file = source, .flags = &.{} });
    lib.addIncludePath(.{ .path = "vendor/md4c/src" });
    lib.addIncludePath(.{ .path = "src" });
    lib.linkLibC();
    lib.rdynamic = true;
    b.installArtifact(lib);

    const copy = b.addInstallFileWithDir(lib.getEmittedBin(), .prefix, "../js/" ++ wasm_name);
    b.default_step.dependOn(&copy.step);
}
