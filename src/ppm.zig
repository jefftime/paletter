const std = @import("std");
const Color = @import("image_types.zig").Color;

fn validate_header(reader: anytype) !u8 {
    var buf: [2]u8 = undefined;
    const len = try reader.read(&buf);
    if (len < buf.len) return error.BadFile;

    if (buf[0] != 'P' or buf[1] != '6') return error.BadHeader;

    return reader.readByte();
}

fn skip_whitespace_and_comments(in_ch: u8, reader: anytype) !u8 {
    var ch = in_ch;
    while (std.ascii.isSpace(ch) or ch == '#') : (ch = try reader.readByte()) {
        var comment_buf: [128]u8 = undefined;

        if (ch == '#') {
            _ = try reader.readUntilDelimiter(&comment_buf, '\n');
            continue;
        }
    }

    return ch;
}

fn parse_digit(in_ch: u8, reader: anytype, out_result: *u32) !u8 {
    var ch = in_ch;
    var result: u32 = 0;
    while (std.ascii.isDigit(ch)) : (ch = try reader.readByte()) {
        result = (result * 10) + (ch - '0');
    }

    out_result.* = result;

    return ch;
}

fn get_file_info(
    reader: anytype,
    out_width: *u32,
    out_height: *u32,
    out_depth: *u32,
) !u8 {
    var ch = try validate_header(reader);

    ch = try skip_whitespace_and_comments(ch, reader);
    ch = try parse_digit(ch, reader, out_width);
    ch = try skip_whitespace_and_comments(ch, reader);
    ch = try parse_digit(ch, reader, out_height);
    ch = try skip_whitespace_and_comments(ch, reader);
    ch = try parse_digit(ch, reader, out_depth);

    return ch;
}

fn convert_data_to_colors(palette_data: []u8, palette: []Color) !void {
    if (palette_data.len != (palette.len * 3)) return error.BadConversion;
    if ((palette_data.len % 3) != 0) return error.BadPaletteData;

    var data = palette_data[0..palette_data.len];
    var counter: usize = 0;
    while (data.len > 0) : ({
        data = data[3..data.len];
        counter += 1;
    }) {
        palette[counter] = Color{
            .r = data[0],
            .g = data[1],
            .b = data[2],
        };
    }
}

pub fn parse_file(allocator: std.mem.Allocator, file: std.fs.File) ![]Color {
    const reader = file.reader();

    var width: u32 = undefined;
    var height: u32 = undefined;
    var depth: u32 = undefined;

    var ch = try get_file_info(reader, &width, &height, &depth);
    std.log.info("width: {}", .{width});
    std.log.info("height: {}", .{height});
    std.log.info("depth: {}", .{depth});

    var palette_data: []u8 = try allocator.alloc(u8, width * height * 3);
    defer allocator.free(palette_data);

    var palette: []Color = try allocator.alloc(Color, width * height);

    ch = try skip_whitespace_and_comments(ch, reader);
    palette_data[0] = ch;
    var read = try reader.read(palette_data[1..palette_data.len]);
    if ((read + 1) != palette_data.len) {
        for (palette_data[read + 1 .. palette_data.len]) |*byte| {
            byte.* = 0;
        }
    }

    try convert_data_to_colors(palette_data, palette);

    return palette;
}
