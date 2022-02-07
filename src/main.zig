const std = @import("std");
const ppm = @import("ppm.zig");

pub fn main() anyerror!void {
    const allocator = std.heap.c_allocator;

    var args = try std.process.argsAlloc(allocator);
    defer allocator.free(args);

    if (args.len < 2) return error.InvalidInput;

    const palette_file = try std.fs.cwd().openFile(args[1], .{});
    defer palette_file.close();

    const palette = try ppm.parse_file(allocator, palette_file);

    for (palette) |color| {
        std.log.info(
            "{{ {d:3} {d:3} {d:3} }}",
            .{ color.r, color.g, color.b },
        );
    }
}
