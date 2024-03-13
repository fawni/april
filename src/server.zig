const std = @import("std");
const multipart = @import("multipart.zig");
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
    token: string,
    allocator: Allocator,
};

pub fn run(options: Options) !void {
    var server = http.Server.init(options.allocator, .{ .reuse_address = true });
    defer server.deinit();

    const address = try net.Address.parseIp(options.address, options.port);
    try server.listen(address);
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

            try handleRequest(options.allocator, &response, options.token);
        }
    }
}

pub fn handleRequest(allocator: Allocator, response: *http.Server.Response, token: string) !void {
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
            // return try reply(response, "poke :3", .ok);
            return try home(response);
        } else if (req.method == .POST) {
            if (req.headers.getFirstEntry("Authorization")) |auth| {
                if (!std.mem.eql(u8, auth.value, token)) {
                    log.warn("Invalid token used: {s}", .{auth.value});

                    return try reply(response, "Invalid token", .forbidden);
                }
            } else return try reply(response, "No token provided", .forbidden);

            const content_type_header = req.headers.getFirstEntry("content-type");
            if (content_type_header == null) {
                return log.warn("attempted to upload without a file", .{});
            }
            const content_type = content_type_header.?.value;

            const uploaded_file = multipart.getFirstField("file", content_type, body) catch |err| {
                var status: http.Status = .bad_request;
                var message: string = undefined;
                switch (err) {
                    error.PartNotFound => {
                        message = "No file with the paramater name 'file' supplied.";
                        status = .not_found;
                    },
                    error.MultipartBoundaryTooLong => message = "Multipart boundary is too long.",
                    error.MultipartFinalBoundaryMissing => message = "Multipart final boundary is missing.",
                    error.MultipartFormDataMissingHeaders => message = "Multipart form data is missing headers",
                    error.ContentDispoitionNotFormData => message = "Content-Disposition is not 'form-data'.",
                    else => message = try std.fmt.allocPrint(allocator, "{}", .{err}),
                }
                log.warn("error while uploading a file: {s}", .{message});

                return try reply(response, message, status);
            };

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

            return try reply(response, file_name, .ok);
        }
    } else if (req.method == .GET or req.method == .HEAD) {
        const path = try std.fmt.allocPrint(allocator, "uploads/{s}", .{cleanPath(req.target)});
        defer allocator.free(path);

        const file = fs.cwd().openFile(path, .{}) catch |err| {
            switch (err) {
                error.FileNotFound, error.IsDir => return try reply(response, "error: not found", .not_found),
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

        try response.do();

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

    return logRequest(response);
}

fn home(response: *http.Server.Response) !void {
    const html =
        \\  <!DOCTYPE html>
        \\  <html>
        \\  <head>
        \\      <title>~april</title>
        \\
        \\      <link rel="preconnect" href="https://fonts.googleapis.com">
        \\      <link rel="preconnect" href="https://fonts.gstatic.com" crossorigin>
        \\      <link href="https://fonts.googleapis.com/css2?family=JetBrains+Mono&display=swap" rel="stylesheet">
        \\
        \\      <style>
        \\          * {
        \\              font-family: "JetBrains Mono", monospace;
        \\          }
        \\
        \\          body {
        \\              background-color: #151515;
        \\              color: #d8d0d5;
        \\              font-size: 11pt;
        \\              line-height: 1.65em;
        \\              max-width: 38em;
        \\              padding-top: 3em;
        \\              margin: auto;
        \\          }
        \\
        \\          h1 {
        \\              font-size: 2.35em;
        \\          }
        \\
        \\          input {
        \\              margin-bottom: 10px;
        \\          }
        \\
        \\          button[type="submit"] {
        \\              background-color: #202020;
        \\              color: #d8d0d5;
        \\              border: solid 1px #d8d0d5;
        \\              border-radius: 8px;
        \\              padding: 0.3em 1em 0.3em 1em;
        \\          }
        \\      </style>
        \\  </head>
        \\
        \\  <body>
        \\      <h1><span style="color: #d895ee;">~</span>april</h1>
        \\      <form id="upload-form" enctype="multipart/form-data">
        \\          <label for="file">File:</label>
        \\          <br/>
        \\          <input id="file" type="file"/>
        \\          <br/>
        \\          <label for="token">Token:</label>
        \\          <br/>
        \\          <input id="token" type="password">
        \\          <br/>
        \\          <button type="submit">Upload</button>
        \\      </form>
        \\      <script>
        \\          const form = document.getElementById("upload-form");
        \\          const formData = new FormData();
        \\
        \\          const handleSubmit = async (event) => {
        \\              event.preventDefault();
        \\
        \\              const token = document.getElementById("token").value;
        \\              const file = document.getElementById("file").files.item(0);
        \\
        \\              formData.append("file", file);
        \\
        \\              let res = await fetch("/", {
        \\                  method: "POST",
        \\                  body: formData,
        \\                  headers: {
        \\                      "Authorization": token,
        \\                  },
        \\              }).catch((e) => console.error("error uploading file", e));
        \\
        \\              window.location.href = "/" + await res.text();
        \\          };
        \\
        \\          form.addEventListener("submit", handleSubmit);
        \\      </script>
        \\  </body>
        \\  </html>
    ;

    try send(response, html, .ok, "text/html");
}

fn reply(response: *http.Server.Response, msg: string, status: http.Status) !void {
    try send(response, msg, status, "text/plain");
}

fn send(response: *http.Server.Response, msg: string, status: http.Status, content_type: string) !void {
    response.status = status;
    response.transfer_encoding = .{ .content_length = msg.len };
    try response.headers.append("Content-Type", content_type);
    try response.do();

    if (response.request.method != .HEAD) {
        try response.writeAll(msg);
    }

    try response.finish();
    logRequest(response);
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
