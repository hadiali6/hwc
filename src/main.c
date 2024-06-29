#define _POSIX_C_SOURCE 200809L
/*#define _POSIX_C_SOURCE 200112L*/
#include <getopt.h>
#include <stdio.h>
#include <stdlib.h>

#include <wlr/util/log.h>

#include "macros.h"
#include "server.h"

const char help[] =
    "Usage: %s [options]\n"
    "Options:\n"
    "-v --version                      Display version.\n"
    "-V --verbosity <level>            Set verbosity level. 0 = silent, 1 = error, 2 = info, 3 = debug.\n"
    "-h --help                         Display this help message.\n"
    "-c --config <path-to-config-file> Specify a config file.\n"
    "-s --startup <command>            Specify a command to run at startup.\n";

static const struct option long_options[] = {
    {"version", no_argument, null, 'v'},       {"verbosity", required_argument, null, 'V'},
    {"help", no_argument, null, 'h'},          {"config", required_argument, null, 'c'},
    {"startup", required_argument, null, 's'}, {0, 0, 0, 0}
};

int main(int argc, char *argv[]) {
    char *startup_cmd = null;
    char *config_path = "~/.config/hwc/config.yml";
    enum wlr_log_importance verbosity = WLR_ERROR;

    int option_index = 0;
    int option;
    while ((option = getopt_long(argc, argv, "vV:hc:s:", long_options, &option_index)) != -1) {
        switch (option) {
        case 'v':
            fprintf(stdout, "hwc version: %s\n", "0.01-alpha");
            return EXIT_SUCCESS;
        case 'V':
            verbosity = atoi(optarg);
            if (verbosity != WLR_SILENT && verbosity != WLR_ERROR && verbosity != WLR_INFO && verbosity != WLR_DEBUG) {
                fprintf(stderr, "Invalid verbosity level!\n");
                return EXIT_FAILURE;
            }
            fprintf(stdout, "Verbosity level set to %d\n", verbosity);
            break;
        case 'h':
            fprintf(stdout, help, argv[0]);
            return EXIT_SUCCESS;
        case 'c':
            config_path = optarg;
            fprintf(stdout, "Config path set to: %s\n", config_path);
            break;
        case 's':
            startup_cmd = optarg;
            break;
        default:
            fprintf(stdout, "Usage: %s [-s startup command]\n", argv[0]);
            return EXIT_SUCCESS;
        }
    }
    if (optind < argc) {
        fprintf(stdout, "Usage: %s [-s startup command]\n", argv[0]);
        return EXIT_SUCCESS;
    }
    wlr_log_init(verbosity, null);
    init_server(startup_cmd);
    return EXIT_SUCCESS;
}
