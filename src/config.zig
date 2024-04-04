const std = @import("std");

const string = []const u8;

const Config = struct { host: string, port: u16, token: string };

pub fn read(allocator: std.mem.Allocator) !Config {
    const file = try std.fs.cwd().readFileAlloc(allocator, "config.json", 4096);
    var parsed = try std.json.parseFromSlice(Config, allocator, file, .{});
    defer parsed.deinit();
    return parsed.value;
}
