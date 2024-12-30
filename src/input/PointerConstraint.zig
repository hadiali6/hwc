const std = @import("std");
const log = std.log.scoped(.pointer_constraint);
const assert = std.debug.assert;

const wayland = @import("wayland");
const wl = wayland.server.wl;
const wlr = @import("wlroots");

const hwc = @import("../hwc.zig");
const util = @import("../util.zig");

const server = &@import("root").server;

const State = union(enum) {
    inactive,
    active: struct {
        /// Node of the active constraint surface in the scene graph.
        node: *wlr.SceneNode,
        /// Coordinates of the pointer on activation in the surface coordinate system.
        sx: f64,
        sy: f64,
    },
};

wlr_pointer_constraint: *wlr.PointerConstraintV1,
state: State,

commit: wl.Listener(*wlr.Surface) =
    wl.Listener(*wlr.Surface).init(handleCommit),
destroy: wl.Listener(*wlr.PointerConstraintV1) =
    wl.Listener(*wlr.PointerConstraintV1).init(handleDestroy),
node_destroy: wl.Listener(void) = wl.Listener(void).init(handleNodeDestroy),

pub fn create(wlr_pointer_constraint: *wlr.PointerConstraintV1) !void {
    const seat: *hwc.input.Seat = @ptrFromInt(wlr_pointer_constraint.seat.data);

    const constraint = try util.allocator.create(hwc.input.PointerConstraint);
    errdefer util.allocator.destroy(constraint);

    constraint.* = .{
        .wlr_pointer_constraint = wlr_pointer_constraint,
        .state = .inactive,
    };

    wlr_pointer_constraint.data = @intFromPtr(constraint);

    wlr_pointer_constraint.events.destroy.add(&constraint.destroy);
    wlr_pointer_constraint.surface.events.commit.add(&constraint.commit);

    if (seat.wlr_seat.keyboard_state.focused_surface) |wlr_surface| {
        if (wlr_surface == wlr_pointer_constraint.surface) {
            assert(seat.cursor.constraint == null);
            seat.cursor.constraint = constraint;
            constraint.maybeActivate();
        }
    }
}

pub fn maybeActivate(self: *hwc.input.PointerConstraint) void {
    const seat: *hwc.input.Seat = @ptrFromInt(self.wlr_pointer_constraint.seat.data);

    assert(seat.cursor.constraint == self);

    if (self.state == .active) {
        return;
    }

    if (seat.cursor.mode == .move or seat.cursor.mode == .resize) {
        return;
    }

    const result = server.toplevelAt(seat.cursor.wlr_cursor.x, seat.cursor.wlr_cursor.y) orelse return;

    if (result.surface != self.wlr_pointer_constraint.surface) {
        return;
    }

    const sx: i32 = @intFromFloat(result.sx);
    const sy: i32 = @intFromFloat(result.sy);

    if (!self.wlr_pointer_constraint.region.containsPoint(sx, sy, null)) {
        return;
    }

    assert(self.state == .inactive);

    self.state = .{
        .active = .{
            .node = result.node,
            .sx = result.sx,
            .sy = result.sy,
        },
    };

    result.node.events.destroy.add(&self.node_destroy);

    log.info("activating pointer constraint", .{});

    self.wlr_pointer_constraint.sendActivated();
}

pub fn confine(self: *hwc.input.PointerConstraint, dx: *f64, dy: *f64) void {
    assert(self.state == .active);
    assert(self.wlr_pointer_constraint.type == .confined);

    const region = &self.wlr_pointer_constraint.region;
    const sx = self.state.active.sx;
    const sy = self.state.active.sy;

    var new_sx: f64 = undefined;
    var new_sy: f64 = undefined;
    assert(wlr.region.confine(region, sx, sy, dx.*, dy.*, &new_sx, &new_sy));

    dx.* = new_sx - sx;
    dy.* = new_sy - sy;

    self.state.active.sx = new_sx;
    self.state.active.sy = new_sy;
}

pub fn deactivate(self: *hwc.input.PointerConstraint) void {
    const seat: *hwc.input.Seat = @ptrFromInt(self.wlr_pointer_constraint.seat.data);

    assert(seat.cursor.constraint == self);
    assert(self.state == .active);

    if (self.wlr_pointer_constraint.current.cursor_hint.enabled) {
        self.warpToHint();
    }

    self.state = .inactive;
    self.node_destroy.link.remove();
    self.wlr_pointer_constraint.sendDeactivated();
}

pub fn warpToHint(self: *hwc.input.PointerConstraint) void {
    const seat: *hwc.input.Seat = @ptrFromInt(self.wlr_pointer_constraint.seat.data);

    var lx: i32 = undefined;
    var ly: i32 = undefined;
    _ = self.state.active.node.coords(&lx, &ly);

    const sx = self.wlr_pointer_constraint.current.cursor_hint.x;
    const sy = self.wlr_pointer_constraint.current.cursor_hint.y;

    _ = seat.cursor.wlr_cursor.warp(
        null,
        @as(f64, @floatFromInt(lx)) + sx,
        @as(f64, @floatFromInt(ly)) + sy,
    );

    _ = seat.wlr_seat.pointerWarp(sx, sy);
}

// It is necessary to listen for the commit event rather than the set_region
// event as the latter is not triggered by wlroots when the input region of
// the surface changes.
fn handleCommit(
    listener: *wl.Listener(*wlr.Surface),
    _: *wlr.Surface,
) void {
    const constraint: *hwc.input.PointerConstraint = @fieldParentPtr("commit", listener);
    const seat: *hwc.input.Seat = @ptrFromInt(constraint.wlr_pointer_constraint.seat.data);

    switch (constraint.state) {
        .active => |state| {
            const sx: i32 = @intFromFloat(state.sx);
            const sy: i32 = @intFromFloat(state.sy);

            if (!constraint.wlr_pointer_constraint.region.containsPoint(sx, sy, null)) {
                log.info("deactivating pointer constraint, (input) region change left pointer outside constraint", .{});
                constraint.deactivate();
            }
        },
        .inactive => {
            if (seat.cursor.constraint == constraint) {
                constraint.maybeActivate();
            }
        },
    }
}

fn handleDestroy(
    listener: *wl.Listener(*wlr.PointerConstraintV1),
    _: *wlr.PointerConstraintV1,
) void {
    const constraint: *hwc.input.PointerConstraint = @fieldParentPtr("destroy", listener);
    const seat: *hwc.input.Seat = @ptrFromInt(constraint.wlr_pointer_constraint.seat.data);

    if (constraint.state == .active) {
        // We can't simply call deactivate() here as it calls sendDeactivated(),
        // which could in the case of a oneshot constraint lifetime recursively
        // destroy the constraint.
        if (constraint.wlr_pointer_constraint.current.cursor_hint.enabled) {
            constraint.warpToHint();
        }
        constraint.node_destroy.link.remove();
    }

    constraint.destroy.link.remove();
    constraint.commit.link.remove();

    if (seat.cursor.constraint == constraint) {
        seat.cursor.constraint = null;
    }

    util.allocator.destroy(constraint);
}

fn handleNodeDestroy(listener: *wl.Listener(void)) void {
    const constraint: *hwc.input.PointerConstraint = @fieldParentPtr("node_destroy", listener);

    log.info("deactivating pointer constraint, scene node destroyed", .{});

    constraint.deactivate();
}
