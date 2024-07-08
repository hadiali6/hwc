#ifndef POPUP_H
#define POPUP_H

#include <wayland-server-core.h>
#include <wlr/types/wlr_xdg_shell.h>

struct hwc_popup {
    struct wlr_xdg_popup *xdg_popup;
    struct wl_listener commit;
    struct wl_listener destroy;
};

#endif /* end of include guard: POPUP_H */
