const std = @import("std");
const server = @import("server.zig");
const mimes = @import("mimes.zig");
const http = std.http;

const log = std.log.scoped(.main);
const Args = [][:0]u8;

const AprilError = error{
    ArgsMismatch,
};

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer std.debug.assert(gpa.deinit() == .ok);

    const allocator = gpa.allocator();

    try mimes.init(allocator);
    defer mimes.deinit(allocator);

    const args = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, args);

    if (args.len != 3) {
        printUsage(args);
        return AprilError.ArgsMismatch;
    }

    const host = args[1];
    const port = std.fmt.parseUnsigned(u16, args[2], 10) catch |err| {
        printUsage(args);
        return err;
    };

    server.run(.{ .host = host, .port = port, .allocator = allocator }) catch |err| {
        log.err("server error: {}\n", .{err});
        if (@errorReturnTrace()) |trace| {
            std.debug.dumpStackTrace(trace.*);
        }
        std.os.exit(1);
    };
}

fn printUsage(args: Args) void {
    const out = std.io.getStdOut().writer();
    out.print("Usage: {s} <host> <port>\n", .{args[0]}) catch {};
}
