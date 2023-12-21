// some bits of code were taken from
// https://github.com/frmdstryr/zhp/blob/0e0d87a313a81c112dc2a9aab41f2ea4e7d179d7/src/forms.zig

const std = @import("std");
const mem = std.mem;
const log = std.log.scoped(.forms);

const string = []const u8;

const WS = " \t\r\n";
const CRLF = "\r\n";

const FormError = error{ MultipartBoundaryTooLong, MultipartFinalBoundaryMissing, PartNotFound, MultipartFormDataMissingHeaders, ContentDispoitionNotFormData };

pub const File = struct {
    const Self = @This();

    name: string,
    data: string,
    content_type: string,

    fn default() Self {
        return Self{
            .name = "",
            .content_type = "",
            .data = "",
        };
    }
};

pub fn getFirstField(name: string, content_type: string, data: string) !File {
    var file = File.default();

    const boundary = getBoundary(content_type).?;
    var bounds = boundary[0..];
    if (mem.startsWith(u8, boundary, "\"") and mem.endsWith(u8, boundary, "\"")) {
        bounds = boundary[1 .. bounds.len - 1];
    }
    if (bounds.len > 70) {
        return FormError.MultipartBoundaryTooLong;
    }

    var buf: [74]u8 = undefined;
    const final_boundary = try std.fmt.bufPrint(&buf, "--{s}--", .{bounds});
    const final_boundary_index = mem.lastIndexOf(u8, data, final_boundary);
    if (final_boundary_index == null) {
        log.warn("Invalid multipart/form-data: no final boundary", .{});
        return FormError.MultipartFinalBoundaryMissing;
    }

    const separator = try std.fmt.bufPrint(&buf, "--{s}\r\n", .{bounds});

    var fields = mem.splitSequence(u8, data[0..final_boundary_index.?], separator);

    outer: while (fields.next()) |part| {
        if (part.len == 0) {
            continue;
        }
        const headers_sep = "\r\n\r\n";
        const eoh = mem.lastIndexOf(u8, part, headers_sep);
        if (eoh == null) {
            log.warn("multipart/form-data missing headers: {s}", .{part});
            return FormError.MultipartFormDataMissingHeaders;
        }

        var headers = part[0 .. eoh.? + headers_sep.len];

        if (!std.mem.containsAtLeast(u8, headers, 1, "Content-Type")) {
            continue;
        }

        const value = part[headers.len..part.len];

        headers = headers[0 .. headers.len - 2];
        const disp_eol = mem.indexOf(u8, headers, CRLF);
        const disp_header = headers[0..disp_eol.?];
        const disp_key = "Content-Disposition: ";
        const disp_params = disp_header[disp_key.len..disp_header.len];

        var iter = mem.splitSequence(u8, disp_params, "; ");
        const content_disp = iter.next().?;
        if (!mem.eql(u8, content_disp, "form-data")) {
            log.warn("Content-Disposition is not form-data: {s}", .{content_disp});
            return FormError.ContentDispoitionNotFormData;
        }

        while (iter.next()) |param| {
            var it = mem.splitScalar(u8, param, '=');
            const param_key = it.next().?;
            const param_value = mem.trim(u8, it.next().?, "\"");

            if (mem.eql(u8, param_key, "name")) {
                if (mem.eql(u8, param_value, name)) {
                    continue;
                } else {
                    continue :outer;
                }
            } else if (mem.eql(u8, param_key, "filename")) {
                file.name = param_value;
            }
        }

        const content_type_key = "Content-Type: ";
        const file_content_type = headers[disp_header.len + CRLF.len + content_type_key.len .. headers.len - CRLF.len];
        file.content_type = file_content_type;
        file.data = mem.trimRight(u8, value, CRLF);

        return file;
    }
    return FormError.PartNotFound;
}

fn getBoundary(content_type: string) ?string {
    var iter = mem.splitScalar(u8, content_type, ';');
    while (iter.next()) |part| {
        const pair = mem.trim(u8, part, WS);
        const key = "boundary=";
        if (pair.len > key.len and mem.startsWith(u8, pair, key)) {
            const boundary = pair[key.len..];
            return boundary;
        }
    }
    return null;
}

test getFirstField {
    const content_type = "multipart/form-data; boundary=------------------------NYwnjKIWPWEnWtSMopADWj";
    const body =
        "--------------------------NYwnjKIWPWEnWtSMopADWj\r\n" ++
        "Content-Disposition: form-data; name=\"file\"; filename=\"important.txt\"\r\n" ++
        "Content-Type: application/octet-stream\r\n" ++
        "\r\n" ++
        "nya\r\n" ++
        "--------------------------NYwnjKIWPWEnWtSMopADWj--\r\n";
    const file = try getFirstField("file", content_type, body);

    try std.testing.expectEqualStrings("important.txt", file.name);
    try std.testing.expectEqualStrings("application/octet-stream", file.content_type);
    try std.testing.expectEqualStrings("nya", file.data);
}
