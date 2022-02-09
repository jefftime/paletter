const std = @import("std");
const Color = @import("image_types.zig").Color;
const ppm = @import("ppm.zig");
const PpmData = ppm.PpmData;
const opts = @import("opts.zig");
const Options = opts.Options;

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

fn process_palette(
    allocator: std.mem.Allocator,
    options: Options,
    filename: []const u8,
) !void {
    const palette_file = try std.fs.cwd().openFile(filename, .{});
    defer palette_file.close();

    const palette = try ppm.parse_file(allocator, palette_file);
    defer palette.deinit();

    const lut = try generate_lut(allocator, palette, options.n_shades);
    defer lut.deinit();

    if (options.out_file) |out_filename| {
        const out_file = try std.fs.cwd().createFile(out_filename, .{});
        defer out_file.close();
        try ppm.write_file(allocator, out_file, &lut);
    } else {
        // TODO: Print to stdout
    }
}

fn cosine_ramp(a: f32, b: f32, c: f32, d: f32, t: f32) f32 {
    return a + (b * std.math.cos(2 * std.math.pi * ((c * t) + d)));
}

pub fn main() anyerror!void {
    const allocator = std.heap.c_allocator;

    var args = try std.process.argsAlloc(allocator);
    defer allocator.free(args);
    const options = try opts.process(args[1..args.len]);

    if (options.print_help) {
        std.log.info("Help goes here!", .{});
        return;
    }

    if (options.in_file) |file| {
        std.log.info("file: {s}", .{file});
        try process_palette(allocator, options, file);
    }

    if (options.ramp_gen) {
        const width: u32 = 512;
        const height: u32 = 70;

        var ramp: []Color = try allocator.alloc(Color, width * height);
        defer allocator.free(ramp);

        var i: u32 = 0;
        while (i < width) : (i += 1) {
            const vec = struct {
                x: f32,
                y: f32,
                z: f32,

                const Self = @This();

                pub fn init(x: f32, y: f32, z: f32) Self {
                    return Self{ .x = x, .y = y, .z = z };
                }
            };

            const steps = options.n_steps;
            const ii = i * steps / width;
            const ww = steps;
            const t = @intToFloat(f32, ii) / @intToFloat(f32, ww);
            const A = vec.init(0.7, 0.5, 0.5);
            const B = vec.init(0.1, 0.5, 0.5);
            const C = vec.init(1.0, 1.0, 1.0);
            const D = vec.init(1.0, 1.2, 1.3);

            const r = cosine_ramp(A.x, B.x, C.x, D.x, t) * 255.0;
            const g = cosine_ramp(A.y, B.y, C.y, D.y, t) * 255.0;
            const b = cosine_ramp(A.z, B.z, C.z, D.z, t) * 255.0;

            var final_color = Color{
                .r = @floatToInt(u8, std.math.clamp(r, 0, 255)),
                .g = @floatToInt(u8, std.math.clamp(g, 0, 255)),
                .b = @floatToInt(u8, std.math.clamp(b, 0, 255)),
            };

            var j: u8 = 0;
            while (j < height) : (j += 1) {
                if (options.in_file) |filename| {
                    const file = try std.fs.cwd().openFile(filename, .{});
                    defer file.close();
                    const palette = try ppm.parse_file(allocator, file);
                    defer palette.deinit();

                    final_color = palette.data[
                        find_best_match(
                            final_color,
                            palette.data,
                        )
                    ];
                }

                ramp[(j * width) + i] = final_color;
            }
        }

        const ramp_file = try std.fs.cwd().createFile("ramp.ppm", .{});
        defer ramp_file.close();
        const data = PpmData{
            .allocator = allocator,
            .width = width,
            .height = height,
            .depth = 255,
            .data = ramp,
        };
        try ppm.write_file(allocator, ramp_file, &data);
    }
}
