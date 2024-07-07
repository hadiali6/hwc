#ifndef CURSOR_H
#define CURSOR_H

#include <stdint.h>
#include <wayland-server-core.h>
#include <wlr/types/wlr_input_device.h>
#include <wlr/types/wlr_compositor.h>

#include "server.h"

void server_new_pointer(struct hwc_server *server, struct wlr_input_device *device);
void seat_request_cursor(struct wl_listener *listener, void *data);
void seat_request_set_selection(struct wl_listener *listener, void *data);
void reset_cursor_mode(struct hwc_server *server);
void process_cursor_move(struct hwc_server *server, uint32_t time);
void process_cursor_resize(struct hwc_server *server, uint32_t time);
void process_cursor_motion(struct hwc_server *server, uint32_t time);
void server_cursor_motion(struct wl_listener *listener, void *data);
void server_cursor_motion_absolute(struct wl_listener *listener, void *data);
void server_cursor_button(struct wl_listener *listener, void *data);
void server_cursor_axis(struct wl_listener *listener, void *data);
void server_cursor_frame(struct wl_listener *listener, void *data);

#endif /* end of include guard: CURSOR_H */
