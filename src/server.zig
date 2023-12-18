const std = @import("std");
const form = @import("form.zig");
const hasher = @import("hash.zig");
const mimes = @import("mimes.zig");

const http = std.http;
const net = std.net;
const mem = std.mem;
const fs = std.fs;

const log = std.log.scoped(.server);
const string = []const u8;

const Options = struct {
    host: string,
    port: u16,
    allocator: mem.Allocator,
};

pub fn run(options: Options) !void {
    var server = http.Server.init(options.allocator, .{ .reuse_address = true });
    defer server.deinit();

    const address = try net.Address.parseIp(options.host, options.port);
    try server.listen(address);
    log.info("Server is running at {s}:{d}", .{ options.host, options.port });
    while (true) {
        var response = try server.accept(.{
            .allocator = options.allocator,
        });
        defer response.deinit();

        if (response.reset() != .closing) {
            response.wait() catch |err| switch (err) {
                error.HttpHeadersInvalid => continue,
                error.EndOfStream => continue,
                else => return err,
            };

            try handleRequest(&response, options.allocator);
        }
    }
}

pub fn handleRequest(response: *http.Server.Response, allocator: mem.Allocator) !void {
    const body = try response.reader().readAllAlloc(allocator, std.math.maxInt(usize));
    defer allocator.free(body);

    if (response.request.headers.contains("connection")) {
        try response.headers.append("connection", "keep-alive");
    }

    if (std.mem.eql(u8, response.request.target, "/")) {
        if (response.request.method != .POST) {
            response.status = .ok;
            try response.headers.append("content-type", "text/plain");
            try response.send();
            if (response.request.method != .HEAD) {
                response.transfer_encoding = .{ .content_length = 8 };
                try response.writeAll("poke :3\n");
            }
            try response.finish();
            logRequest(response);
            return;
        } else {
            // TODO: actually upload
            // TODO: check for a token and validate before uploading
            const content_type = response.request.headers.getFirstEntry("Content-Type").?.value;
            const uploaded_file = try form.getField("file", content_type, body);

            const hash = try hasher.hash(allocator, uploaded_file.data);
            defer allocator.free(hash);

            const ext = fs.path.extension(uploaded_file.name);
            const uploads_path = try fs.cwd().realpathAlloc(allocator, "./uploads");
            defer allocator.free(uploads_path);
            const file_name = try std.fmt.allocPrint(allocator, "{s}{s}", .{ hash, ext });
            defer allocator.free(file_name);
            const file_path = try std.fmt.allocPrint(allocator, "{s}/{s}", .{ uploads_path, file_name });
            defer allocator.free(file_path);

            const file = try fs.createFileAbsolute(file_path, .{ .read = true, .truncate = true });
            defer file.close();
            try file.writeAll(uploaded_file.data);

            response.status = .ok;
            response.transfer_encoding = .{ .content_length = file_name.len };
            try response.send();
            try response.writeAll(file_name);
            try response.finish();

            logRequest(response);
            return;
        }
    }

    if (response.request.method == .GET or response.request.method == .HEAD) {
        const path = try std.fmt.allocPrint(allocator, "uploads/{s}", .{cleanPath(response.request.target)});
        defer allocator.free(path);
        const file = fs.cwd().openFile(path, .{}) catch |err| {
            switch (err) {
                error.FileNotFound, error.IsDir => {
                    response.status = .not_found;
                    try response.headers.append("content-type", "text/plain");
                    try response.send();
                    if (response.request.method != .HEAD) {
                        response.transfer_encoding = .{ .content_length = 17 };
                        try response.writeAll("error: not found\n");
                        try response.finish();
                    }
                    logRequest(response);
                    return;
                },
                else => return err,
            }
        };
        defer file.close();

        response.status = .ok;
        response.transfer_encoding = .chunked;

        const ext = fs.path.extension(path);
        const mime_type = mimes.lookup(ext[1..]);

        if (mime_type == null) {
            log.warn("unrecognized file extension: {s}", .{ext});
        }

        try response.headers.append("content-type", mime_type.?);

        try response.send();

        var buf: [4096]u8 = undefined;

        while (true) {
            const read = try file.reader().read(&buf);
            if (read == 0) {
                break;
            }
            _ = try response.write(buf[0..read]);
        }

        try response.finish();
    }

    logRequest(response);
    return;
}

fn logRequest(response: *http.Server.Response) void {
    log.info("\x1b[32m{d} {s} \x1b[35m{s} {s} {s}\x1b[0m", .{
        @intFromEnum(response.status),
        response.status.phrase().?,
        @tagName(response.request.method),
        response.request.target,
        @tagName(response.request.version),
    });
}

fn cleanPath(path: string) string {
    if (mem.indexOfScalar(u8, path, '?')) |idx| {
        return path[1..idx];
    }
    return path[1..];
}
