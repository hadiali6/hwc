const std = @import("std");
const log = std.log.scoped(.seat);
const assert = std.debug.assert;

const wayland = @import("wayland");
const wl = wayland.server.wl;
const wlr = @import("wlroots");

const hwc = @import("../hwc.zig");
const util = @import("../util.zig");

const server = &@import("root").server;

/// List of all text input objects for the seat.
/// Multiple text input objects may be created per seat, even multiple from the same client.
/// However, only one text input per seat may be enabled at a time.
text_inputs: wl.list.Head(TextInput, .link),

input_popups: wl.list.Head(Popup, .link),

/// The input method currently in use for this seat.
/// Only one input method per seat may be used at a time and if one is
/// already in use new input methods are ignored.
/// If this is null, no text input enter events will be sent.
wlr_input_method: ?*wlr.InputMethodV2 = null,

/// The currently enabled text input for the currently focused surface.
/// Always null if there is no input method.
text_input: ?*TextInput = null,

commit: wl.Listener(*wlr.InputMethodV2) = wl.Listener(*wlr.InputMethodV2).init(handleCommit),
destroy: wl.Listener(*wlr.InputMethodV2) =
    wl.Listener(*wlr.InputMethodV2).init(handleDestroy),

new_popup: wl.Listener(*wlr.InputPopupSurfaceV2) =
    wl.Listener(*wlr.InputPopupSurfaceV2).init(handleNewInputPopup),

grab_keyboard: wl.Listener(*wlr.InputMethodV2.KeyboardGrab) =
    wl.Listener(*wlr.InputMethodV2.KeyboardGrab).init(handleGrabKeyboard),
grab_keyboard_destroy: wl.Listener(*wlr.InputMethodV2.KeyboardGrab) =
    wl.Listener(*wlr.InputMethodV2.KeyboardGrab).init(handleGrabKeyboardDestroy),

pub fn init(self: *hwc.input.Relay) void {
    self.* = .{
        .text_inputs = undefined,
        .input_popups = undefined,
    };

    self.text_inputs.init();
    self.input_popups.init();
}

pub fn newInputMethod(
    self: *hwc.input.Relay,
    wlr_input_method: *wlr.InputMethodV2,
) void {
    const seat: *hwc.input.Seat = @fieldParentPtr("relay", self);

    if (seat.wlr_seat != wlr_input_method.seat) {
        return;
    }

    log.debug("new input method on seat {s}", .{seat.wlr_seat.name});

    // Only one input_method can be bound to a seat.
    if (self.wlr_input_method != null) {
        log.info("seat {s} already has an input method", .{seat.wlr_seat.name});
        wlr_input_method.sendUnavailable();
        return;
    }

    self.wlr_input_method = wlr_input_method;

    wlr_input_method.events.commit.add(&self.commit);
    wlr_input_method.events.destroy.add(&self.destroy);
    wlr_input_method.events.grab_keyboard.add(&self.grab_keyboard);
    wlr_input_method.events.new_popup_surface.add(&self.new_popup);

    if (seat.focused == .toplevel) {
        self.focus(seat.focused.wlrSurface().?);
    }
}

pub fn newTextInput(
    self: *hwc.input.Relay,
    wlr_text_input: *wlr.TextInputV3,
) !void {
    const text_input = try util.allocator.create(TextInput);
    errdefer util.allocator.destroy(text_input);

    log.debug("new text input on seat {s}", .{wlr_text_input.seat.name});

    text_input.init(wlr_text_input);

    self.text_inputs.append(text_input);
}

pub fn disableTextInput(self: *hwc.input.Relay) void {
    assert(self.text_input != null);

    self.text_input = null;

    if (self.wlr_input_method) |wlr_input_method| {
        wlr_input_method.sendDeactivate();
        wlr_input_method.sendDone();
    }
}

pub fn sendInputMethodState(self: *hwc.input.Relay) void {
    const wlr_input_method = self.wlr_input_method orelse return;
    const text_input = self.text_input orelse return;
    const wlr_text_input = text_input.wlr_text_input;

    if (wlr_text_input.active_features.surrounding_text) {
        if (wlr_text_input.current.surrounding.text) |text| {
            wlr_input_method.sendSurroundingText(
                text,
                wlr_text_input.current.surrounding.cursor,
                wlr_text_input.current.surrounding.anchor,
            );
        }
    }

    wlr_input_method.sendTextChangeCause(wlr_text_input.current.text_change_cause);

    if (wlr_text_input.active_features.content_type) {
        wlr_input_method.sendContentType(
            wlr_text_input.current.content_type.hint,
            wlr_text_input.current.content_type.purpose,
        );
    }

    wlr_input_method.sendDone();
}

pub fn focus(self: *hwc.input.Relay, new_focus: ?*wlr.Surface) void {
    // Send leave events
    {
        var iterator = self.text_inputs.iterator(.forward);
        while (iterator.next()) |text_input| {
            if (text_input.wlr_text_input.focused_surface) |surface| {
                // This function should not be called unless focus changes
                assert(surface != new_focus);
                text_input.wlr_text_input.sendLeave();
            }
        }
    }

    // Clear currently enabled text input
    if (self.text_input != null) {
        self.disableTextInput();
    }

    // Send enter events if we have an input method.
    // No text input for the new surface should be enabled yet as the client
    // should wait until it receives an enter event.
    if (new_focus) |wlr_surface| {
        if (self.wlr_input_method != null) {
            var iterator = self.text_inputs.iterator(.forward);
            while (iterator.next()) |text_input| {
                if (text_input.wlr_text_input.resource.getClient() == wlr_surface.resource.getClient()) {
                    text_input.wlr_text_input.sendEnter(wlr_surface);
                }
            }
        }
    }
}

fn handleCommit(
    listener: *wl.Listener(*wlr.InputMethodV2),
    wlr_input_method: *wlr.InputMethodV2,
) void {
    const relay: *hwc.input.Relay = @fieldParentPtr("commit", listener);
    assert(wlr_input_method == relay.wlr_input_method);

    if (!wlr_input_method.client_active) {
        return;
    }

    const text_input = relay.text_input orelse return;

    if (wlr_input_method.current.preedit.text) |preedit_text| {
        text_input.wlr_text_input.sendPreeditString(
            preedit_text,
            wlr_input_method.current.preedit.cursor_begin,
            wlr_input_method.current.preedit.cursor_end,
        );
    }

    if (wlr_input_method.current.commit_text) |commit_text| {
        text_input.wlr_text_input.sendCommitString(commit_text);
    }

    if (wlr_input_method.current.delete.before_length != 0 or
        wlr_input_method.current.delete.after_length != 0)
    {
        text_input.wlr_text_input.sendDeleteSurroundingText(
            wlr_input_method.current.delete.before_length,
            wlr_input_method.current.delete.after_length,
        );
    }

    text_input.wlr_text_input.sendDone();
}

fn handleDestroy(
    listener: *wl.Listener(*wlr.InputMethodV2),
    _: *wlr.InputMethodV2,
) void {
    const relay: *hwc.input.Relay = @fieldParentPtr("destroy", listener);

    relay.commit.link.remove();
    relay.grab_keyboard.link.remove();
    relay.destroy.link.remove();
    relay.new_popup.link.remove();

    relay.wlr_input_method = null;
}

fn handleGrabKeyboard(
    listener: *wl.Listener(*wlr.InputMethodV2.KeyboardGrab),
    keyboard_grab: *wlr.InputMethodV2.KeyboardGrab,
) void {
    const relay: *hwc.input.Relay = @fieldParentPtr("grab_keyboard", listener);
    const seat: *hwc.input.Seat = @fieldParentPtr("relay", relay);

    const active_keyboard = seat.wlr_seat.getKeyboard();

    keyboard_grab.setKeyboard(active_keyboard);
    keyboard_grab.events.destroy.add(&relay.grab_keyboard_destroy);
}

fn handleGrabKeyboardDestroy(
    listener: *wl.Listener(*wlr.InputMethodV2.KeyboardGrab),
    keyboard_grab: *wlr.InputMethodV2.KeyboardGrab,
) void {
    const relay: *hwc.input.Relay = @fieldParentPtr("grab_keyboard", listener);
    relay.grab_keyboard_destroy.link.remove();

    if (keyboard_grab.keyboard) |wlr_keyboard| {
        keyboard_grab.input_method.seat.keyboardNotifyModifiers(&wlr_keyboard.modifiers);
    }
}

fn handleNewInputPopup(
    listener: *wl.Listener(*wlr.InputPopupSurfaceV2),
    wlr_input_popup: *wlr.InputPopupSurfaceV2,
) void {
    const relay: *hwc.input.Relay = @fieldParentPtr("new_popup", listener);

    Popup.create(relay, wlr_input_popup) catch |err| {
        log.err("{s}: {}", .{ @src().fn_name, err });
        return;
    };
}

const TextInput = struct {
    link: wl.list.Link,

    wlr_text_input: *wlr.TextInputV3,

    enable: wl.Listener(*wlr.TextInputV3) =
        wl.Listener(*wlr.TextInputV3).init(TextInput.handleEnable),
    commit: wl.Listener(*wlr.TextInputV3) =
        wl.Listener(*wlr.TextInputV3).init(TextInput.handleCommit),
    disable: wl.Listener(*wlr.TextInputV3) =
        wl.Listener(*wlr.TextInputV3).init(TextInput.handleDisable),
    destroy: wl.Listener(*wlr.TextInputV3) =
        wl.Listener(*wlr.TextInputV3).init(TextInput.handleDestroy),

    fn init(self: *TextInput, wlr_text_input: *wlr.TextInputV3) void {
        self.* = .{
            .link = undefined,
            .wlr_text_input = wlr_text_input,
        };
    }

    fn handleEnable(listener: *wl.Listener(*wlr.TextInputV3), _: *wlr.TextInputV3) void {
        const text_input: *TextInput = @fieldParentPtr("enable", listener);
        const seat: *hwc.input.Seat = @ptrFromInt(text_input.wlr_text_input.seat.data);

        if (text_input.wlr_text_input.focused_surface == null) {
            log.err("client requested to enable text input without focus, ignoring request", .{});
            return;
        }

        // The same text_input object may be enabled multiple times consecutively
        // without first disabling it. Enabling a different text input object without
        // first disabling the current one is disallowed by the protocol however.
        if (seat.relay.text_input) |currently_enabled| {
            if (text_input != currently_enabled) {
                log.err("client requested to enable more than one text input on a single seat, ignoring request", .{});
                return;
            }
        }

        seat.relay.text_input = text_input;

        if (seat.relay.wlr_input_method) |wlr_input_method| {
            wlr_input_method.sendActivate();
            seat.relay.sendInputMethodState();
        }
    }

    fn handleCommit(listener: *wl.Listener(*wlr.TextInputV3), _: *wlr.TextInputV3) void {
        const text_input: *TextInput = @fieldParentPtr("commit", listener);
        const seat: *hwc.input.Seat = @ptrFromInt(text_input.wlr_text_input.seat.data);

        if (seat.relay.text_input != text_input) {
            log.err("inactive text input tried to commit an update, client bug?", .{});
            return;
        }

        if (seat.relay.wlr_input_method != null) {
            seat.relay.sendInputMethodState();
        }
    }

    fn handleDisable(listener: *wl.Listener(*wlr.TextInputV3), _: *wlr.TextInputV3) void {
        const text_input: *TextInput = @fieldParentPtr("disable", listener);
        const seat: *hwc.input.Seat = @ptrFromInt(text_input.wlr_text_input.seat.data);

        if (seat.relay.text_input == text_input) {
            seat.relay.disableTextInput();
        }
    }

    fn handleDestroy(listener: *wl.Listener(*wlr.TextInputV3), _: *wlr.TextInputV3) void {
        const text_input: *TextInput = @fieldParentPtr("destroy", listener);
        const seat: *hwc.input.Seat = @ptrFromInt(text_input.wlr_text_input.seat.data);

        if (seat.relay.text_input == text_input) {
            seat.relay.disableTextInput();
        }

        text_input.enable.link.remove();
        text_input.commit.link.remove();
        text_input.disable.link.remove();
        text_input.destroy.link.remove();

        text_input.link.remove();

        util.allocator.destroy(text_input);
    }
};

const Popup = struct {
    link: wl.list.Link,

    relay: *hwc.input.Relay,
    wlr_input_popup: *wlr.InputPopupSurfaceV2,
    surface_tree: *wlr.SceneTree,

    destroy: wl.Listener(void) = wl.Listener(void).init(Popup.handleDestroy),
    map: wl.Listener(void) = wl.Listener(void).init(Popup.handleMap),
    unmap: wl.Listener(void) = wl.Listener(void).init(Popup.handleUnmap),
    commit: wl.Listener(*wlr.Surface) = wl.Listener(*wlr.Surface).init(Popup.handleCommit),

    fn create(relay: *hwc.input.Relay, wlr_input_popup: *wlr.InputPopupSurfaceV2) !void {
        const input_popup = try util.allocator.create(Popup);
        errdefer util.allocator.destroy(input_popup);

        input_popup.* = .{
            .link = undefined,
            .relay = relay,
            .wlr_input_popup = wlr_input_popup,
            .surface_tree = try server.hidden.createSceneSubsurfaceTree(wlr_input_popup.surface),
        };

        relay.input_popups.append(input_popup);

        input_popup.wlr_input_popup.events.destroy.add(&input_popup.destroy);
        input_popup.wlr_input_popup.surface.events.map.add(&input_popup.map);
        input_popup.wlr_input_popup.surface.events.unmap.add(&input_popup.unmap);
        input_popup.wlr_input_popup.surface.events.commit.add(&input_popup.commit);

        input_popup.update();
    }

    fn handleDestroy(listener: *wl.Listener(void)) void {
        const input_popup: *Popup = @fieldParentPtr("destroy", listener);

        input_popup.destroy.link.remove();
        input_popup.map.link.remove();
        input_popup.unmap.link.remove();
        input_popup.commit.link.remove();
        input_popup.link.remove();

        util.allocator.destroy(input_popup);
    }

    fn handleMap(listener: *wl.Listener(void)) void {
        const input_popup: *Popup = @fieldParentPtr("map", listener);

        input_popup.update();
    }

    fn handleUnmap(listener: *wl.Listener(void)) void {
        const input_popup: *Popup = @fieldParentPtr("unmap", listener);

        input_popup.surface_tree.node.reparent(server.hidden);
    }

    fn handleCommit(listener: *wl.Listener(*wlr.Surface), _: *wlr.Surface) void {
        const input_popup: *Popup = @fieldParentPtr("commit", listener);

        input_popup.update();
    }

    fn update(self: *Popup) void {
        const text_input: *TextInput = self.relay.text_input orelse {
            self.surface_tree.node.reparent(server.hidden);
            return;
        };

        if (!self.wlr_input_popup.surface.mapped) {
            return;
        }

        // This seems like it could be null if the focused surface is destroyed
        const focused_surface = text_input.wlr_text_input.focused_surface orelse return;

        // Focus should never be sent to subsurfaces
        assert(focused_surface.getRootSurface() == focused_surface);

        const focusable = hwc.Focusable.fromSurface(focused_surface) orelse return;
        const focused_wlr_scene_node = focusable.wlrSceneNode() orelse return;

        const wlr_output: *wlr.Output = switch (focusable.*) {
            .toplevel => |toplevel| toplevel.getActiveOutput().?,
            .none => unreachable,
        };

        const popup_scene_tree: *wlr.SceneTree = switch (focusable.*) {
            .toplevel => |toplevel| toplevel.popup_scene_tree,
            .none => unreachable,
        };

        self.surface_tree.node.reparent(popup_scene_tree);

        if (!text_input.wlr_text_input.current.features.cursor_rectangle) {
            // If the text-input client does not inform us where in the surface
            // the active text input is there's not much we can do. Placing the
            // popup at the top left corner of the window is nice and simple
            // while not looking terrible.
            self.surface_tree.node.setPosition(0, 0);
            return;
        }

        var focused_x: c_int = undefined;
        var focused_y: c_int = undefined;
        _ = focused_wlr_scene_node.coords(&focused_x, &focused_y);

        var output_box: wlr.Box = undefined;
        server.output_layout.getBox(wlr_output, &output_box);

        var cursor_box = text_input.wlr_text_input.current.cursor_rectangle;

        // Adjust to be relative to the output
        cursor_box.x += focused_x - output_box.x;
        cursor_box.y += focused_y - output_box.y;

        // Choose popup x/y relative to the output:

        // Align the left edge of the popup with the left edge of the cursor.
        // If the popup wouldn't fit on the output instead align the right edge
        // of the popup with the right edge of the cursor.
        const popup_x = blk: {
            const popup_width = self.wlr_input_popup.surface.current.width;
            if (output_box.width - cursor_box.x >= popup_width) {
                break :blk cursor_box.x;
            } else {
                break :blk cursor_box.x + cursor_box.width - popup_width;
            }
        };

        // Align the top edge of the popup with the bottom edge of the cursor.
        // If the popup wouldn't fit on the output instead align the bottom edge
        // of the popup with the top edge of the cursor.
        const popup_y = blk: {
            const popup_height = self.wlr_input_popup.surface.current.height;
            if (output_box.height - (cursor_box.y + cursor_box.height) >= popup_height) {
                break :blk cursor_box.y + cursor_box.height;
            } else {
                break :blk cursor_box.y + popup_height;
            }
        };

        // Scene node position is relative to the parent so adjust popup x/y to
        // be relative to the focused surface.
        self.surface_tree.node.setPosition(popup_x - focused_x + output_box.x, popup_x - focused_y + output_box.y);

        // The text input rectangle sent to the input method is relative to the popup.
        cursor_box.x -= popup_x;
        cursor_box.y -= popup_y;
        self.wlr_input_popup.sendTextInputRectangle(&cursor_box);
    }
};
