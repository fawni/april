const std = @import("std");
const form = @import("form.zig");
const hasher = @import("hash.zig");
const mimes = @import("mimes.zig");

const http = std.http;
const net = std.net;
const mem = std.mem;
const fs = std.fs;

const log = std.log.scoped(.server);
const Allocator = mem.Allocator;
const string = []const u8;

const Options = struct {
    address: string,
    port: u16,
    allocator: Allocator,
};

pub fn run(options: Options) !void {
    var server = http.Server.init(options.allocator, .{ .reuse_address = true });
    defer server.deinit();

    const address = try net.Address.parseIp(options.address, options.port);
    try server.listen(address);
    log.info("Server is running at {s}:{d}", .{ options.address, options.port });
    while (true) {
        var response = try server.accept(.{
            .allocator = options.allocator,
        });
        defer response.deinit();

        if (response.reset() != .closing) {
            response.wait() catch |err| switch (err) {
                error.HttpHeadersInvalid, error.EndOfStream => continue,
                else => {},
            };

            try handleRequest(&response, options.allocator);
        }
    }
}

pub fn handleRequest(response: *http.Server.Response, allocator: Allocator) !void {
    const req = response.request;
    const body = try response.reader().readAllAlloc(allocator, std.math.maxInt(usize));
    defer allocator.free(body);

    if (req.headers.getFirstEntry("Connection")) |connection| {
        if (std.mem.eql(u8, connection.value, "keep-alive")) {
            try response.headers.append("Connection", "keep-alive");
        } else {
            try response.headers.append("Connection", "close");
        }
    }

    if (std.mem.eql(u8, req.target, "/")) {
        if (req.method == .GET or req.method == .HEAD) {
            response.status = .ok;

            response.transfer_encoding = .{ .content_length = 8 };

            try response.headers.append("Content-Type", "text/plain");
            try response.send();

            if (req.method != .HEAD) {
                try response.writeAll("poke :3\n");
            }

            try response.finish();
            logRequest(response);

            return;
        } else if (req.method == .POST) {
            // TODO: check for a token and validate before uploading
            const content_type_header = req.headers.getFirstEntry("content-type");
            if (content_type_header == null) {
                log.warn("attempted to upload without a file", .{});
                return;
            }
            const content_type = content_type_header.?.value;

            const uploaded_file = try form.getField("file", content_type, body);

            const hash = try hasher.hash(allocator, uploaded_file.data);
            defer allocator.free(hash);

            const uploads_path = try fs.cwd().realpathAlloc(allocator, "./uploads");
            defer allocator.free(uploads_path);

            const file_name = try std.fmt.allocPrint(allocator, "{s}{s}", .{ hash, fs.path.extension(uploaded_file.name) });
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
    } else if (req.method == .GET or req.method == .HEAD) {
        const path = try std.fmt.allocPrint(allocator, "uploads/{s}", .{cleanPath(req.target)});
        defer allocator.free(path);

        const file = fs.cwd().openFile(path, .{}) catch |err| {
            switch (err) {
                error.FileNotFound, error.IsDir => {
                    response.status = .not_found;
                    response.transfer_encoding = .{ .content_length = 17 };
                    try response.headers.append("Content-Type", "text/plain");
                    try response.send();

                    if (req.method != .HEAD) {
                        try response.writeAll("error: not found\n");
                    }

                    try response.finish();
                    logRequest(response);

                    return;
                },
                else => return err,
            }
        };
        defer file.close();
        const md = try file.metadata();

        response.status = .ok;
        response.transfer_encoding = .{ .content_length = md.size() };

        const ext = fs.path.extension(path);
        const mime_type = mimes.lookup(mem.trimLeft(u8, ext, "."));
        if (mime_type) |mime| {
            try response.headers.append("Content-Type", mime);
        } else {
            log.warn("unrecognized file extension: {s}", .{ext});
        }

        try response.send();

        var buf: [4096]u8 = undefined;
        if (req.method != .HEAD) {
            while (true) {
                const read = try file.reader().read(&buf);
                if (read == 0) {
                    break;
                }
                _ = try response.write(buf[0..read]);
            }
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
        &mem.toBytes(response.request.method),
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
