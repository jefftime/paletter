const std = @import("std");
const Color = @import("image_types.zig").Color;

pub const PpmData = struct {
    allocator: std.mem.Allocator,
    width: u32,
    height: u32,
    depth: u32,
    data: []Color,

    pub fn init(
        self: *PpmData,
        allocator: std.mem.Allocator,
        width: u32,
        height: u32,
        depth: u32,
        data: []Color,
    ) !void {
        self.* = PpmData{
            .allocator = allocator,
            .width = width,
            .height = height,
            .depth = depth,
            .data = data,
        };
    }

    pub fn deinit(self: *const PpmData) void {
        self.allocator.free(self.data);
    }
};

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

fn convert_data_to_colors(color_data: []u8, colors: []Color) !void {
    if (color_data.len != (colors.len * 3)) return error.BadConversion;
    if ((color_data.len % 3) != 0) return error.BadColorData;

    var data = color_data[0..color_data.len];
    var counter: usize = 0;
    while (data.len > 0) : ({
        data = data[3..data.len];
        counter += 1;
    }) {
        colors[counter] = Color{
            .r = data[0],
            .g = data[1],
            .b = data[2],
        };
    }
}

fn convert_colors_to_data(colors: []Color, color_data: []u8) !void {
    if (color_data.len != (colors.len * 3)) return error.BadConversion;
    if ((color_data.len % 3) != 0) return error.BadColorData;

    for (colors) |color, i| {
        color_data[(i * 3) + 0] = color.r;
        color_data[(i * 3) + 1] = color.g;
        color_data[(i * 3) + 2] = color.b;
    }
}

pub fn parse_file(allocator: std.mem.Allocator, file: std.fs.File) !PpmData {
    const reader = file.reader();

    var width: u32 = undefined;
    var height: u32 = undefined;
    var depth: u32 = undefined;

    var ch = try get_file_info(reader, &width, &height, &depth);

    var color_data: []u8 = try allocator.alloc(u8, width * height * 3);
    defer allocator.free(color_data);

    var colors: []Color = try allocator.alloc(Color, width * height);

    ch = try skip_whitespace_and_comments(ch, reader);
    color_data[0] = ch;
    var read = try reader.read(color_data[1..color_data.len]);
    if ((read + 1) != color_data.len) {
        for (color_data[read + 1 .. color_data.len]) |*byte| {
            byte.* = 0;
        }
    }

    try convert_data_to_colors(color_data, colors);

    var result: PpmData = undefined;
    try result.init(allocator, width, height, depth, colors);

    return result;
}

pub fn write_file(
    allocator: std.mem.Allocator,
    file: std.fs.File,
    data: *const PpmData,
) !void {
    const writer = file.writer();

    var color_data = try allocator.alloc(u8, data.width * data.height * 3);
    try convert_colors_to_data(data.data, color_data);

    try std.fmt.format(
        writer,
        "P6 {} {} {} ",
        .{ data.width, data.height, data.depth },
    );
    _ = try writer.write(color_data);
}
