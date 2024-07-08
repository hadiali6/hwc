#include <getopt.h>
#include <stdio.h>
#include <stdlib.h>

#include <wlr/util/log.h>

const char help[] =
    "Usage: %s [options]\n"
    "Options:\n"
    "-v --version                      Display version.\n"
    "-V --verbosity <level>            Set verbosity level. 0 = silent, 1 = error, 2 = info, 3 = debug.\n"
    "-h --help                         Display this help message.\n"
    "-c --config <path-to-config-file> Specify a config file.\n"
    "-s --startup <command>            Specify a command to run at startup.\n";

static const struct option long_options[] = {
    { "version",   no_argument,       NULL, 'v' },
    { "verbosity", required_argument, NULL, 'V' },
    { "help",      no_argument,       NULL, 'h' },
    { "config",    required_argument, NULL, 'c' },
    { "startup",   required_argument, NULL, 's' },
    { 0, 0, 0, 0 }
};

#define DEFAULT_HWC_CONFIG_PATH "~/.config/hwc/conifg"
#define HWC_VERSION "0.01-alpha"

#include "compositor.h"
#include "types/compositor.h"
#include "types/server.h"

static void hwc_set_verbosity(
    enum wlr_log_importance *verbosity,
    enum wlr_log_importance value
) {
    *verbosity = value;
    if (
        (*verbosity != WLR_SILENT) &&
        (*verbosity != WLR_ERROR) &&
        (*verbosity != WLR_INFO) &&
        (*verbosity != WLR_DEBUG)
    ) {
        fprintf(stderr, "Invalid verbosity level!\n");
        exit(EXIT_FAILURE);
    }
    fprintf(stdout, "Verbosity level set to %d\n", *verbosity);
}

int main(int argc, char *argv[]) {
    char *startup_cmd = NULL;
    char *config_path = DEFAULT_HWC_CONFIG_PATH;

#ifdef DEBUG
    enum wlr_log_importance verbosity = WLR_DEBUG;
#else
    enum wlr_log_importance verbosity = WLR_SILENT;
#endif

    int option_index = 0;
    int option;
    while ((option = getopt_long(argc, argv, "vV:hc:s:", long_options, &option_index)) != -1) {
        switch (option) {
            case 'v': fprintf(stdout, "hwc version: %s\n", HWC_VERSION); exit(EXIT_SUCCESS);
            case 'V': hwc_set_verbosity(&verbosity, atoi(optarg)); break;
            case 'h': fprintf(stdout, help, argv[0]); exit(EXIT_SUCCESS);
            case 'c': config_path = optarg; fprintf(stdout, "Config path set to: %s\n", config_path); break;
            case 's': startup_cmd = optarg; break;
            default: fprintf(stdout, help, argv[0]); exit(EXIT_SUCCESS);
        }
    }
    if (optind < argc) {
        fprintf(stdout, help, argv[0]);
        return EXIT_SUCCESS;
    }
    wlr_log_init(verbosity, NULL);

    struct hwc_compositor compositor = { 0 };

    init_compositor(&compositor.server);
    start_compositor(&compositor.server, startup_cmd); // starts event loop
    destroy_compositor(&compositor.server);

    return EXIT_SUCCESS;
}
