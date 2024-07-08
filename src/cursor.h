#ifndef CURSOR_H
#define CURSOR_H

#include <wayland-server-core.h>
#include <wlr/types/wlr_input_device.h>

#include "types/server.h"

void seat_request_cursor(struct wl_listener *listener, void *data);
void seat_request_set_selection(struct wl_listener *listener, void *data);
void server_new_pointer(struct hwc_server *server, struct wlr_input_device *device);
void reset_cursor_mode(struct hwc_server *server);
void init_cursor(struct hwc_server *server);

#endif /* end of include guard: CURSOR_H */
