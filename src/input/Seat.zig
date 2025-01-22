const std = @import("std");
const log = std.log.scoped(.@"input.Seat");

const wayland = @import("wayland");
const wl = wayland.server.wl;
const wlr = @import("wlroots");

const hwc = @import("root");
const server = &hwc.server;

wlr_seat: *wlr.Seat,

destroy: wl.Listener(*wlr.Seat) = wl.Listener(*wlr.Seat).init(handleDestroy),
request_set_cursor: wl.Listener(*wlr.Seat.event.RequestSetCursor) =
    wl.Listener(*wlr.Seat.event.RequestSetCursor).init(handleRequestSetCursor),
request_set_selection: wl.Listener(*wlr.Seat.event.RequestSetSelection) =
    wl.Listener(*wlr.Seat.event.RequestSetSelection).init(handleRequestSetSelection),
request_set_primary_selection: wl.Listener(*wlr.Seat.event.RequestSetPrimarySelection) =
    wl.Listener(*wlr.Seat.event.RequestSetPrimarySelection).init(handleRequestSetPrimarySelection),

request_start_drag: wl.Listener(*wlr.Seat.event.RequestStartDrag) =
    wl.Listener(*wlr.Seat.event.RequestStartDrag).init(handleRequestStartDrag),
start_drag: wl.Listener(*wlr.Drag) = wl.Listener(*wlr.Drag).init(handleStartDrag),
drag_destroy: wl.Listener(*wlr.Drag) = wl.Listener(*wlr.Drag).init(handleDragDestroy),

pub fn init(self: *hwc.input.Seat, name: [*:0]const u8) !void {
    self.* = .{
        .wlr_seat = try wlr.Seat.create(server.wl_server, name),
    };

    self.wlr_seat.events.destroy.add(&self.destroy);
    self.wlr_seat.events.request_set_cursor.add(&self.request_set_cursor);
    self.wlr_seat.events.request_set_primary_selection.add(&self.request_set_primary_selection);
    self.wlr_seat.events.request_start_drag.add(&self.request_start_drag);
    self.wlr_seat.events.start_drag.add(&self.start_drag);

    log.info("{s}: '{s}'", .{ @src().fn_name, name });
}

pub fn updateCapabilities(self: *hwc.input.Seat) void {
    var capabilities = wl.Seat.Capability{};

    var it = server.input_manager.devices.iterator(.forward);
    while (it.next()) |device| {
        switch (device.wlr_input_device.type) {
            .keyboard => capabilities.keyboard = true,
            .pointer => capabilities.pointer = true,
            .touch => capabilities.touch = true,
            .tablet_pad, .tablet, .@"switch" => {},
        }
    }

    self.wlr_seat.setCapabilities(capabilities);

    log.info(
        "{s}: keyboard={} pointer={} touch={}",
        .{ @src().fn_name, capabilities.keyboard, capabilities.pointer, capabilities.touch },
    );
}

fn handleDestroy(listener: *wl.Listener(*wlr.Seat), wlr_seat: *wlr.Seat) void {
    const seat: *hwc.input.Seat = @fieldParentPtr("destroy", listener);
    _ = wlr_seat;

    seat.destroy.link.remove();
    seat.request_set_cursor.link.remove();
    seat.request_set_primary_selection.link.remove();
    seat.request_start_drag.link.remove();
    seat.start_drag.link.remove();
}

fn handleRequestSetCursor(
    listener: *wl.Listener(*wlr.Seat.event.RequestSetCursor),
    event: *wlr.Seat.event.RequestSetCursor,
) void {
    const seat: *hwc.input.Seat = @fieldParentPtr("request_set_cursor", listener);
    _ = seat;
    _ = event;
}

fn handleRequestSetSelection(
    listener: *wl.Listener(*wlr.Seat.event.RequestSetSelection),
    event: *wlr.Seat.event.RequestSetSelection,
) void {
    const seat: *hwc.input.Seat = @fieldParentPtr("request_set_selection", listener);
    _ = seat;
    _ = event;
}

fn handleRequestSetPrimarySelection(
    listener: *wl.Listener(*wlr.Seat.event.RequestSetPrimarySelection),
    event: *wlr.Seat.event.RequestSetPrimarySelection,
) void {
    const seat: *hwc.input.Seat = @fieldParentPtr("request_set_primary_selection", listener);
    _ = seat;
    _ = event;
}

fn handleRequestStartDrag(
    listener: *wl.Listener(*wlr.Seat.event.RequestStartDrag),
    event: *wlr.Seat.event.RequestStartDrag,
) void {
    const seat: *hwc.input.Seat = @fieldParentPtr("request_start_drag", listener);
    _ = seat;
    _ = event;
}

fn handleStartDrag(
    listener: *wl.Listener(*wlr.Drag),
    wlr_drag: *wlr.Drag,
) void {
    const seat: *hwc.input.Seat = @fieldParentPtr("start_drag", listener);
    _ = seat;
    _ = wlr_drag;
}

fn handleDragDestroy(
    listener: *wl.Listener(*wlr.Drag),
    wlr_drag: *wlr.Drag,
) void {
    const seat: *hwc.input.Seat = @fieldParentPtr("drag_destroy", listener);
    _ = seat;
    _ = wlr_drag;
}
