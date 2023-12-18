const std = @import("std");
const log = std.log.scoped(.hash);

const Algo = std.crypto.hash.blake2.Blake2b(64);
const string = []const u8;

pub fn hash(allocator: std.mem.Allocator, bytes: string) !string {
    var out: [Algo.digest_length]u8 = undefined;
    Algo.hash(bytes, &out, .{});
    return std.fmt.allocPrint(allocator, "{s}", .{std.fmt.fmtSliceHexLower(&out)});
}
