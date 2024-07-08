#ifndef TOPLEVEL_T_H
#define TOPLEVEL_T_H

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


#endif /* end of include guard: TOPLEVEL_T_H */
