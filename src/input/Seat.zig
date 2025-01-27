const std = @import("std");
const log = std.log.scoped(.@"input.Seat");
const meta = std.meta;

const wayland = @import("wayland");
const wl = wayland.server.wl;
const wlr = @import("wlroots");

const hwc = @import("hwc");
const server = &hwc.server;

wlr_seat: *wlr.Seat,
cursor: hwc.input.Cursor,
focused: hwc.desktop.Focusable = .none,

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
        .cursor = undefined,
    };

    self.wlr_seat.data = @intFromPtr(self);

    try self.cursor.init();

    self.wlr_seat.events.destroy.add(&self.destroy);
    self.wlr_seat.events.request_set_cursor.add(&self.request_set_cursor);
    self.wlr_seat.events.request_set_primary_selection.add(&self.request_set_primary_selection);
    self.wlr_seat.events.request_start_drag.add(&self.request_start_drag);
    self.wlr_seat.events.start_drag.add(&self.start_drag);

    log.info("{s}: name='{s}'", .{ @src().fn_name, name });
}

pub fn focus(self: *hwc.input.Seat, target: hwc.desktop.Focusable) void {
    if (meta.eql(self.focused, target)) {
        return;
    }

    {
        var focused_buffer: [1024]u8 = undefined;
        var target_buffer: [1024]u8 = undefined;

        log.info("{s}: {s}{s} -> {s}{s}", .{
            @src().fn_name,
            @tagName(self.focused),
            self.focused.status(&focused_buffer) catch "unknown",
            @tagName(target),
            target.status(&target_buffer) catch "unknown",
        });
    }

    switch (self.focused) {
        .toplevel => |toplevel| {
            _ = toplevel.wlr_xdg_toplevel.setActivated(false);
            toplevel.destroyPopups();
        },
        // TODO
        .layer_surface => |layer_surface| {
            _ = layer_surface;
        },
        .none => {},
    }

    self.focused = target;

    switch (target) {
        .toplevel => |toplevel| {
            toplevel.surface_tree.node.raiseToTop();
            _ = toplevel.wlr_xdg_toplevel.setActivated(true);
        },
        // TODO
        .layer_surface => |layer_surface| {
            _ = layer_surface;
        },
        .none => {
            self.wlr_seat.keyboardClearFocus();
        },
    }

    if (target.wlrSurface()) |wlr_surface| {
        self.keyboardNotifyEnter(wlr_surface);
    }
}

pub fn keyboardNotifyEnter(self: *hwc.input.Seat, wlr_surface: *wlr.Surface) void {
    if (self.wlr_seat.getKeyboard()) |wlr_keyboard| {
        self.wlr_seat.keyboardNotifyEnter(
            wlr_surface,
            wlr_keyboard.keycodes[0..wlr_keyboard.num_keycodes],
            &wlr_keyboard.modifiers,
        );
    } else {
        self.wlr_seat.keyboardNotifyEnter(wlr_surface, &.{}, null);
    }
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

    log.info("{s}: name='{s}': keyboard={} pointer={} touch={}", .{
        @src().fn_name,
        self.wlr_seat.name,
        capabilities.keyboard,
        capabilities.pointer,
        capabilities.touch,
    });
}

fn handleDestroy(listener: *wl.Listener(*wlr.Seat), wlr_seat: *wlr.Seat) void {
    const seat: *hwc.input.Seat = @fieldParentPtr("destroy", listener);

    seat.cursor.deinit();

    seat.destroy.link.remove();
    seat.request_set_cursor.link.remove();
    seat.request_set_primary_selection.link.remove();
    seat.request_start_drag.link.remove();
    seat.start_drag.link.remove();

    log.info("{s}: name='{s}'", .{ @src().fn_name, wlr_seat.name });
}

fn handleRequestSetCursor(
    listener: *wl.Listener(*wlr.Seat.event.RequestSetCursor),
    event: *wlr.Seat.event.RequestSetCursor,
) void {
    const seat: *hwc.input.Seat = @fieldParentPtr("request_set_cursor", listener);

    if (seat.wlr_seat.pointer_state.focused_client == event.seat_client) {
        log.info("{s}: {*} set cursor", .{ @src().fn_name, event.seat_client });

        seat.cursor.wlr_cursor.setSurface(event.surface, event.hotspot_x, event.hotspot_y);
    }
}

fn handleRequestSetSelection(
    listener: *wl.Listener(*wlr.Seat.event.RequestSetSelection),
    event: *wlr.Seat.event.RequestSetSelection,
) void {
    const seat: *hwc.input.Seat = @fieldParentPtr("request_set_selection", listener);

    seat.wlr_seat.setSelection(event.source, event.serial);
}

fn handleRequestSetPrimarySelection(
    listener: *wl.Listener(*wlr.Seat.event.RequestSetPrimarySelection),
    event: *wlr.Seat.event.RequestSetPrimarySelection,
) void {
    const seat: *hwc.input.Seat = @fieldParentPtr("request_set_primary_selection", listener);

    seat.wlr_seat.setPrimarySelection(event.source, event.serial);
}

// TODO
fn handleRequestStartDrag(
    listener: *wl.Listener(*wlr.Seat.event.RequestStartDrag),
    event: *wlr.Seat.event.RequestStartDrag,
) void {
    const seat: *hwc.input.Seat = @fieldParentPtr("request_start_drag", listener);
    _ = seat;
    _ = event;
}

// TODO
fn handleStartDrag(
    listener: *wl.Listener(*wlr.Drag),
    wlr_drag: *wlr.Drag,
) void {
    const seat: *hwc.input.Seat = @fieldParentPtr("start_drag", listener);
    _ = seat;
    _ = wlr_drag;
}

// TODO
fn handleDragDestroy(
    listener: *wl.Listener(*wlr.Drag),
    wlr_drag: *wlr.Drag,
) void {
    const seat: *hwc.input.Seat = @fieldParentPtr("drag_destroy", listener);
    _ = seat;
    _ = wlr_drag;
}
