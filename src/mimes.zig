// https://github.com/kivikakk/kaksikud/blob/d7a9a7764810213d5248a2372147031e1fe8ba26/src/mimes.zig
// thanks ashe!

const std = @import("std");

const Entry = struct {
    mime_type: []const u8,
    extensions: []const []const u8,
};

var entries: []const Entry = undefined;

pub fn init(allocator: std.mem.Allocator) !void {
    const data = @embedFile("mimes");
    var es = std.ArrayList(Entry).init(allocator);
    errdefer es.deinit();

    var it = std.mem.tokenizeScalar(u8, data, '\n');
    while (it.next()) |line| {
        var lit = std.mem.tokenizeAny(u8, line, " \t");

        const mime_type = lit.next() orelse continue;
        var exts = std.ArrayList([]const u8).init(allocator);
        errdefer exts.deinit();
        while (lit.next()) |ext| {
            try exts.append(ext);
        }

        try es.append(.{
            .mime_type = mime_type,
            .extensions = try exts.toOwnedSlice(),
        });
    }

    entries = try es.toOwnedSlice();
}

pub fn deinit(allocator: std.mem.Allocator) void {
    for (entries) |entry| {
        allocator.free(entry.extensions);
    }
    allocator.free(entries);
}

pub fn lookup(extension: []const u8) ?[]const u8 {
    for (entries) |entry| {
        for (entry.extensions) |ext| {
            if (std.ascii.eqlIgnoreCase(extension, ext)) {
                return entry.mime_type;
            }
        }
    }
    return null;
}
