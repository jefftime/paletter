const std = @import("std");
const Color = @import("image_types.zig").Color;
const ppm = @import("ppm.zig");
const PpmData = ppm.PpmData;

fn find_best_match(target: Color, palette: []Color) usize {
    var match: usize = 0;
    var min_dist: usize = std.math.maxInt(usize);

    const pow = std.math.pow;
    for (palette) |color, i| {
        // The square root in the Euclidean distance can be removed here because
        // we just care about relative distances
        const r1 = @intCast(i64, color.r);
        const r2 = @intCast(i64, target.r);
        const g1 = @intCast(i64, color.g);
        const g2 = @intCast(i64, target.g);
        const b1 = @intCast(i64, color.b);
        const b2 = @intCast(i64, target.b);
        var dist = pow(i64, r1 - r2, 2);
        dist += pow(i64, g1 - g2, 2);
        dist += pow(i64, b1 - b2, 2);

        if (dist < min_dist) {
            match = i;
            min_dist = @intCast(usize, dist);
        }
    }

    return match;
}

fn generate_lut(
    allocator: std.mem.Allocator,
    palette: PpmData,
    n_shades: u32,
) !PpmData {
    var colormap = std.AutoHashMap(Color, bool).init(allocator);
    var lut = try allocator.alloc(
        Color,
        palette.width * palette.height * n_shades,
    );
    var index: usize = 0;

    for (palette.data) |color| {
        try colormap.put(color, true);

        var i = n_shades;
        while (i > 0) : (i -= 1) {
            const r: u32 = (color.r * i + (n_shades / 4)) / (n_shades / 2);
            const g: u32 = (color.g * i + (n_shades / 4)) / (n_shades / 2);
            const b: u32 = (color.b * i + (n_shades / 4)) / (n_shades / 2);

            var target = Color{
                .r = @intCast(u8, std.math.clamp(r, 0, 255)),
                .g = @intCast(u8, std.math.clamp(g, 0, 255)),
                .b = @intCast(u8, std.math.clamp(b, 0, 255)),
            };
            lut[index] = palette.data[find_best_match(target, palette.data)];
            index += 1;
        }
    }

    var result = PpmData{
        .allocator = allocator,
        .width = n_shades,
        .height = palette.width * palette.height,
        .depth = palette.depth,
        .data = lut,
    };

    return result;
}

pub fn main() anyerror!void {
    const allocator = std.heap.c_allocator;

    var args = try std.process.argsAlloc(allocator);
    defer allocator.free(args);

    if (args.len < 2) return error.InvalidInput;

    const palette_file = try std.fs.cwd().openFile(args[1], .{});
    defer palette_file.close();

    const palette = try ppm.parse_file(allocator, palette_file);
    defer palette.deinit();

    const lut = try generate_lut(allocator, palette, 64);
    defer lut.deinit();

    const out_file = try std.fs.cwd().createFile("lut.ppm", .{});
    defer out_file.close();
    try ppm.write_file(allocator, out_file, &lut);
}
