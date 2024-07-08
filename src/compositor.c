#include <stdlib.h>
#include <unistd.h>

#include <wayland-server-core.h>

#include <wlr/util/log.h>
#include <wlr/backend.h>
#include <wlr/render/wlr_renderer.h>
#include <wlr/render/allocator.h>
#include <wlr/types/wlr_compositor.h>
#include <wlr/types/wlr_subcompositor.h>
#include <wlr/types/wlr_cursor.h>
#include <wlr/types/wlr_xcursor_manager.h>
#include <wlr/types/wlr_scene.h>
#include <wlr/types/wlr_data_device.h>

#include "input.h"
#include "xdgshell.h"
#include "output.h"
#include "cursor.h"

#include "types/server.h"
#include "types/compositor.h"


void init_server(struct hwc_server *server) {
    /* The Wayland display is managed by libwayland. It handles accepting
     * clients from the Unix socket, manging Wayland globals, and so on. */
    server->wl_display = wl_display_create();
    /* The backend is a wlroots feature which abstracts the underlying input and
     * output hardware. The autocreate option will choose the most suitable
     * backend based on the current environment, such as opening an X11 window
     * if an X11 server is running. */
    server->backend = wlr_backend_autocreate(wl_display_get_event_loop(server->wl_display), NULL);
    if (server->backend == NULL) {
        wlr_log(WLR_ERROR, "failed to create wlr_backend");
        exit(EXIT_FAILURE);
    }

    /* Autocreates a renderer, either Pixman, GLES2 or Vulkan for us. The user
     * can also specify a renderer using the WLR_RENDERER env var.
     * The renderer is responsible for defining the various pixel formats it
     * supports for shared memory, this configures that for clients. */
    server->renderer = wlr_renderer_autocreate(server->backend);
    if (server->renderer == NULL) {
        wlr_log(WLR_ERROR, "failed to create wlr_renderer");
        exit(EXIT_FAILURE);
    }

    wlr_renderer_init_wl_display(server->renderer, server->wl_display);

    /* Autocreates an allocator for us.
     * The allocator is the bridge between the renderer and the backend. It
     * handles the buffer creation, allowing wlroots to render onto the
     * screen */
    server->allocator = wlr_allocator_autocreate(server->backend, server->renderer);
    if (server->allocator == NULL) {
        wlr_log(WLR_ERROR, "failed to create wlr_allocator");
        exit(EXIT_FAILURE);
    }

    /* This creates some hands-off wlroots interfaces. The compositor is
     * necessary for clients to allocate surfaces, the subcompositor allows to
     * assign the role of subsurfaces to surfaces and the data device manager
     * handles the clipboard. Each of these wlroots interfaces has room for you
     * to dig your fingers in and play with their behavior if you want. Note that
     * the clients cannot set the selection directly without compositor approval,
     * see the handling of the request_set_selection event below.*/
    wlr_compositor_create(server->wl_display, 5, server->renderer);
    wlr_subcompositor_create(server->wl_display);
    wlr_data_device_manager_create(server->wl_display);
}

void init_compositor(struct hwc_server *server) {
    init_server(server);
    init_output(server);
    init_xdgshell(server);
    init_cursor(server);
    init_input_devices(server);
}

void start_compositor(struct hwc_server *server, char *startup_cmd) {
    /* add a unix socket to the wayland display. */
    const char *socket = wl_display_add_socket_auto(server->wl_display);
    if (!socket) {
        wlr_backend_destroy(server->backend);
        exit(EXIT_FAILURE);
    }

    /* start the backend. this will enumerate outputs and inputs, become the drm master, etc */
    if (!wlr_backend_start(server->backend)) {
        wlr_backend_destroy(server->backend);
        wl_display_destroy(server->wl_display);
        exit(EXIT_FAILURE);
    }

    /* set the wayland_display environment variable to our socket and run the
     * startup command if requested. */
    setenv("wayland_display", socket, true);

    if (startup_cmd) {
        if (fork() == 0) {
            execl("/bin/sh", "/bin/sh", "-c", startup_cmd, (void *)NULL);
        }
    }

    /* run the wayland event loop. this does not return until you exit the
     * compositor. starting the backend rigged up all of the necessary event
     * loop configuration to listen to libinput events, drm events, generate
     * frame events at the refresh rate, and so on. */
    wlr_log(WLR_INFO, "running wayland compositor on wayland_display=%s", socket);
    wl_display_run(server->wl_display);
}

void destroy_compositor(struct hwc_server *server) {
    /* once wl_display_run returns, we destroy all clients then shut down the server-> */
    wl_display_destroy_clients(server->wl_display);
    wlr_scene_node_destroy(&server->scene->tree.node);
    wlr_xcursor_manager_destroy(server->cursor_mgr);
    wlr_cursor_destroy(server->cursor);
    wlr_allocator_destroy(server->allocator);
    wlr_renderer_destroy(server->renderer);
    wlr_backend_destroy(server->backend);
    wl_display_destroy(server->wl_display);
}
