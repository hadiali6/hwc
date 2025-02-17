const std = @import("std");
const assert = std.debug.assert;
const log = std.log.scoped(.@"api.output");

const wlr = @import("wlroots");

const hwc = @import("hwc");

const CreateOutputError = error{
    OutOfMemory,
    InvalidBackend,
};

const Data = struct {
    status: union(enum) {
        fail: CreateOutputError,
        success: *wlr.Output,
    },
    width: c_uint,
    height: c_uint,
};

fn handleBackend(backend: *wlr.Backend, data: ?*anyopaque) callconv(.C) void {
    const result: *Data = if (data) |d|
        @alignCast(@ptrCast(d))
    else
        unreachable;

    if (wlr.config.has_drm_backend and backend.isDrm()) {
        result.status = .{ .fail = CreateOutputError.InvalidBackend };
        return;
    }

    if (backend.isHeadless()) {
        const wlr_output = backend.headlessAddOutput(result.width, result.height) catch |err| {
            result.status = .{ .fail = err };
            return;
        };

        result.status = .{ .success = wlr_output };
        return;
    }

    if (backend.isWl()) {
        const wlr_output = backend.wlOuputCreate() catch |err| {
            result.status = .{ .fail = err };
            return;
        };

        result.status = .{ .success = wlr_output };
        return;
    }

    if (wlr.config.has_x11_backend and backend.isX11()) {
        const wlr_output = backend.x11OutputCreate() catch |err| {
            result.status = .{ .fail = err };
            return;
        };

        result.status = .{ .success = wlr_output };
        return;
    }
}

pub fn create(server: *hwc.Server, width: c_uint, height: c_uint) !*wlr.Output {
    assert(server.wlr_backend.isMulti());

    var result = Data{
        .status = undefined,
        .width = width,
        .height = height,
    };

    server.wlr_backend.multiForEachBackend(handleBackend, &result);

    if (result.status == .fail) {
        log.err(
            "{s} failed: '{}': output can only be created on Wayland, X11, and headless backends",
            .{ @src().fn_name, result.status.fail },
        );
        return result.status.fail;
    }

    return result.status.success;
}
