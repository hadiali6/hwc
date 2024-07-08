#ifndef OUTPUT_T_H
#define OUTPUT_T_H

#include <wayland-server-core.h>
#include <wlr/types/wlr_output.h>

#include "server.h"

struct hwc_output {
    struct wl_list link;
    struct hwc_server *server;
    struct wlr_output *wlr_output;
    struct wl_listener frame;
    struct wl_listener request_state;
    struct wl_listener destroy;
};

#endif /* end of include guard: OUTPUT_T_H */
