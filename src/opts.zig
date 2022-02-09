const std = @import("std");
const c = @cImport({
    @cInclude("stdio.h");
});

pub const Options = struct {
    in_file: ?[]const u8,
    out_file: ?[]const u8,
    ramp_gen: bool,
    n_shades: u32,
    n_steps: u32,
    print_help: bool,

    fn defaults() Options {
        return Options{
            .in_file = null,
            .out_file = null,
            .ramp_gen = false,
            .n_shades = 64,
            .n_steps = 16,
            .print_help = false,
        };
    }
};

pub fn process(args: []const []const u8) !Options {
    var result = Options.defaults();

    var skip_next: u32 = 0;
    for (args) |arg, i| {
        if (skip_next > 0) {
            skip_next -= 1;
            continue;
        }

        if (arg[0] == '-') {
            switch (arg[1]) {
                'o' => {
                    result.out_file = args[i + 1];
                    skip_next = 1;
                },

                'r' => result.ramp_gen = true,

                's' => {
                    var n_steps: u32 = undefined;
                    _ = c.sscanf(args[i + 1].ptr, "%u", &n_steps);
                    result.n_steps = n_steps;
                    skip_next = 1;
                },

                'h' => result.print_help = true,

                else => continue,
            }
        } else {
            result.in_file = arg;
        }
    }

    return result;
}
