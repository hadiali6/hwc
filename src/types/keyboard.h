#ifndef KEYBOARD_T_H
#define KEYBOARD_T_H

#include <wayland-server-core.h>
#include <wlr/types/wlr_keyboard.h>

struct hwc_keyboard {
    struct wl_list link;
    struct hwc_server *server;
    struct wlr_keyboard *wlr_keyboard;

    struct wl_listener modifiers;
    struct wl_listener key;
    struct wl_listener destroy;
};

#endif /* end of include guard: KEYBOARD_T_H */

