#ifndef TOPLEVEL_H
#define TOPLEVEL_H

#include <wayland-server-core.h>
#include <wlr/types/wlr_xdg_shell.h>
#include <wlr/types/wlr_scene.h>

#include "server.h"

struct hwc_toplevel {
    struct wl_list link;
    struct hwc_server *server;
    struct wlr_xdg_toplevel *xdg_toplevel;
    struct wlr_scene_tree *scene_tree;
    struct wl_listener map;
    struct wl_listener unmap;
    struct wl_listener commit;
    struct wl_listener destroy;
    struct wl_listener request_move;
    struct wl_listener request_resize;
    struct wl_listener request_maximize;
    struct wl_listener request_fullscreen;
};

struct hwc_popup {
    struct wlr_xdg_popup *xdg_popup;
    struct wl_listener commit;
    struct wl_listener destroy;
};

void focus_toplevel(struct hwc_toplevel *toplevel, struct wlr_surface *surface);
struct hwc_toplevel *desktop_toplevel_at(
        struct hwc_server *server, double lx, double ly,
        struct wlr_surface **surface, double *sx, double *sy
);
void xdg_toplevel_map(struct wl_listener *listener, void *data);
void xdg_toplevel_unmap(struct wl_listener *listener, void *data);
void xdg_toplevel_destroy(struct wl_listener *listener, void *data);
void begin_interactive(
    struct hwc_toplevel *toplevel,
    enum hwc_cursor_mode mode,
    uint32_t edges
);
void xdg_toplevel_request_move(struct wl_listener *listener, void *data);
void xdg_toplevel_request_resize(struct wl_listener *listener, void *data);
void xdg_toplevel_request_maximize(struct wl_listener *listener, void *data);
void xdg_toplevel_request_fullscreen(struct wl_listener *listener, void *data);

void server_new_xdg_popup(struct wl_listener *listener, void *data);
void server_new_xdg_toplevel(struct wl_listener *listener, void *data);
#endif /* end of include guard: TOPLEVEL_H */
