const std = @import("std");
const log = std.log.scoped(.StatusManager);

const wayland = @import("wayland");
const wl = wayland.server.wl;
const hwcp = wayland.server.hwc;
const wlr = @import("wlroots");

const hwc = @import("hwc");
const server = &hwc.server;

global: *wl.Global,
server_destroy: wl.Listener(*wl.Server) = wl.Listener(*wl.Server).init(handleServerDestroy),

pub fn init(self: *hwc.StatusManager) !void {
    self.* = .{
        .global = try wl.Global.create(server.wl_server, hwcp.StatusManager, 1, ?*anyopaque, null, bind),
    };

    server.wl_server.addDestroyListener(&self.server_destroy);
}

fn handleServerDestroy(listener: *wl.Listener(*wl.Server), _: *wl.Server) void {
    const status_manager: *hwc.StatusManager = @fieldParentPtr("server_destroy", listener);

    status_manager.global.destroy();
}

fn bind(wl_client: *wl.Client, _: ?*anyopaque, version: u32, id: u32) void {
    const status_manager = hwcp.StatusManager.create(wl_client, version, id) catch |err| {
        wl_client.postNoMemory();
        log.err("{s} failed: '{}'", .{ @src().fn_name, err });
        return;
    };
    status_manager.setHandler(?*anyopaque, handleRequest, null, null);
}

fn handleRequest(
    status_manager: *hwcp.StatusManager,
    request: hwcp.StatusManager.Request,
    _: ?*anyopaque,
) void {
    log.debug("{s}: {s}", .{ @src().fn_name, @tagName(request) });

    switch (request) {
        .destroy => status_manager.destroy(),
        .get_output_status => |req| {
            const wlr_output = wlr.Output.fromWlOutput(req.output) orelse return;
            const output: *hwc.desktop.Output = @ptrFromInt(wlr_output.data);

            log.debug("{s}: {*} name='{s}'", .{ @src().fn_name, output, wlr_output.name });
        },
        .get_seat_status => |req| {
            const wlr_seat_client = wlr.Seat.Client.fromWlSeat(req.seat) orelse return;
            const seat: *hwc.input.Seat = @ptrFromInt(wlr_seat_client.seat.data);

            log.debug(
                "{s}: {*} name='{s}'",
                .{ @src().fn_name, seat, wlr_seat_client.seat.name },
            );
        },
        .get_scene_status => {
            // TODO
        },
    }
}
