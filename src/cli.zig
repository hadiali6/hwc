const std = @import("std");
const log = std.log.scoped(.cli);
const mem = std.mem;
const builtin = std.builtin;

pub const Flag = struct {
    name: [:0]const u8,
    kind: enum { boolean, arg },
};

pub fn parser(comptime Arg: type, comptime flags: []const Flag) type {
    switch (Arg) {
        // TODO consider allowing []const u8
        [:0]const u8, [*:0]const u8 => {}, // ok
        else => @compileError("invalid argument type: " ++ @typeName(Arg)),
    }
    return struct {
        pub const Result = struct {
            /// Remaining args after the recognized flags
            args: []const Arg,
            /// Data obtained from parsed flags
            flags: Flags,

            pub const Flags = flags_type: {
                var fields: []const builtin.Type.StructField = &.{};
                for (flags) |flag| {
                    const field: builtin.Type.StructField = switch (flag.kind) {
                        .boolean => .{
                            .name = flag.name,
                            .type = bool,
                            .default_value = &false,
                            .is_comptime = false,
                            .alignment = @alignOf(bool),
                        },
                        .arg => .{
                            .name = flag.name,
                            .type = ?[:0]const u8,
                            .default_value = &@as(?[:0]const u8, null),
                            .is_comptime = false,
                            .alignment = @alignOf(?[:0]const u8),
                        },
                    };
                    fields = fields ++ [_]builtin.Type.StructField{field};
                }
                break :flags_type @Type(.{ .Struct = .{
                    .layout = .auto,
                    .fields = fields,
                    .decls = &.{},
                    .is_tuple = false,
                } });
            };
        };

        pub fn parse(args: []const Arg) !Result {
            var result_flags: Result.Flags = .{};

            var i: usize = 0;
            outer: while (i < args.len) : (i += 1) {
                const arg = switch (Arg) {
                    [*:0]const u8 => mem.sliceTo(args[i], 0),
                    [:0]const u8 => args[i],
                    else => unreachable,
                };
                inline for (flags) |flag| {
                    if (mem.eql(u8, "-" ++ flag.name, arg)) {
                        switch (flag.kind) {
                            .boolean => @field(result_flags, flag.name) = true,
                            .arg => {
                                i += 1;
                                if (i == args.len) {
                                    log.err("option '-" ++ flag.name ++
                                        "' requires an argument but none was provided!", .{});
                                    return error.MissingFlagArgument;
                                }
                                @field(result_flags, flag.name) = switch (Arg) {
                                    [*:0]const u8 => mem.sliceTo(args[i], 0),
                                    [:0]const u8 => args[i],
                                    else => unreachable,
                                };
                            },
                        }
                        continue :outer;
                    }
                }
                break;
            }

            return Result{
                .args = args[i..],
                .flags = result_flags,
            };
        }
    };
}
