const std = @import("std");
const assert = std.debug.assert;
const log = std.log.scoped(.@"api.output");

const wlr = @import("wlroots");

const hwc = @import("hwc");

const Data = struct {
    status: union(enum) {
        fail: anyerror,
        success: *wlr.Output,
    },
    width: c_uint,
    height: c_uint,

    fn handleEachBackend(backend: *wlr.Backend, data: ?*anyopaque) callconv(.C) void {
        const result: *Data = if (data) |d|
            @alignCast(@ptrCast(d))
        else
            unreachable;

        if (backend.isWl()) {
            const wlr_output = backend.wlOuputCreate() catch |err| {
                log.debug("wl", .{});
                result.status = .{ .fail = err };
                return;
            };

            result.status = .{ .success = wlr_output };
        } else if (backend.isHeadless()) {
            const wlr_output = backend.headlessAddOutput(result.width, result.height) catch |err| {
                log.debug("headless", .{});
                result.status = .{ .fail = err };
                return;
            };

            result.status = .{ .success = wlr_output };
        } else if (wlr.config.has_x11_backend and backend.isX11()) {
            const wlr_output = backend.x11OutputCreate() catch |err| {
                log.debug("x11", .{});
                result.status = .{ .fail = err };
                return;
            };

            result.status = .{ .success = wlr_output };
        }
    }
};

pub fn createOutput(server: *hwc.Server, width: c_uint, height: c_uint) !*wlr.Output {
    assert(server.wlr_backend.isMulti());

    var result = Data{
        .status = undefined,
        .width = width,
        .height = height,
    };

    server.wlr_backend.multiForEachBackend(Data.handleEachBackend, &result);

    if (result.status == .fail) {
        log.err(
            "{s} failed: '{}': output can only be created on Wayland, X11, and headless backends",
            .{ @src().fn_name, result.status.fail },
        );
        return result.status.fail;
    }

    return result.status.success;
}
