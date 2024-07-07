#ifndef KEYBOARD_H
#define KEYBOARD_H

#include <stdbool.h>
#include <wayland-server-core.h>
#include <xkbcommon/xkbcommon.h>
#include <wlr/types/wlr_keyboard.h>
#include <wlr/types/wlr_input_device.h>

#include "server.h"

struct hwc_keyboard {
    struct wl_list link;
    struct hwc_server *server;
    struct wlr_keyboard *wlr_keyboard;

    struct wl_listener modifiers;
    struct wl_listener key;
    struct wl_listener destroy;
};

void keyboard_handle_modifiers(struct wl_listener *listener, void *data);
bool handle_keybinding(struct hwc_server *server, xkb_keysym_t sym);
void keyboard_handle_key(struct wl_listener *listener, void *data);
void keyboard_handle_destroy(struct wl_listener *listener, void *data);
void server_new_keyboard(
    struct hwc_server *server,
    struct wlr_input_device *device
);
#endif /* end of include guard: KEYBOARD_H */
