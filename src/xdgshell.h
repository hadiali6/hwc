#ifndef TOPLEVEL_H
#define TOPLEVEL_H

#include <wayland-server-core.h>
#include <wlr/types/wlr_compositor.h>

#include "types/server.h"
#include "types/toplevel.h"

void focus_toplevel(struct hwc_toplevel *toplevel, struct wlr_surface *surface);
struct hwc_toplevel *desktop_toplevel_at(
    struct hwc_server *server,
    double lx,
    double ly,
    struct wlr_surface **surface,
    double *sx,
    double *sy
);
void init_xdgshell(struct hwc_server *server);

#endif /* end of include guard: TOPLEVEL_H */
