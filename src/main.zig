const std = @import("std");
const server = @import("server.zig");
const mimes = @import("mimes.zig");
const config = @import("config.zig");

const log = std.log.scoped(.main);

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer std.debug.assert(gpa.deinit() == .ok);

    const allocator = gpa.allocator();

    try mimes.init(allocator);
    defer mimes.deinit(allocator);

    const cfg = try config.read(allocator);

    log.info("Server is running at {s}:\x1b[1;36m{d}\x1b[0m", .{ cfg.host, cfg.port });
    server.run(.{ .host = cfg.host, .port = cfg.port, .token = cfg.token, .allocator = allocator }) catch |err| {
        log.err("server error: {}\n", .{err});
        if (@errorReturnTrace()) |trace| {
            std.debug.dumpStackTrace(trace.*);
        }
        std.os.exit(1);
    };
}

test {
    std.testing.refAllDecls(@This());
}
