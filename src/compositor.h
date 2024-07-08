#ifndef COMPOSITOR_H
#define COMPOSITOR_H

#include "types/server.h"

void init_compositor(struct hwc_server *server);
void start_compositor(struct hwc_server *server, char *startup_cmd);
void destroy_compositor(struct hwc_server *server);

#endif /* end of include guard: COMPOSITOR_H */
