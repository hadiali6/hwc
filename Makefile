CC = clang
CFLAGS = -g -Wall -Wextra -fdiagnostics-color=always -DWLR_USE_UNSTABLE -D_POSIX_C_SOURCE=200809L -std=c11 -DDEBUG
WAYLAND_PROTOCOLS = $(shell pkg-config --variable=pkgdatadir wayland-protocols)
WAYLAND_SCANNER = $(shell pkg-config --variable=wayland_scanner wayland-scanner)
LIBS = $(shell pkg-config --cflags --libs "wlroots-0.18" wayland-server xkbcommon)

BUILD_DIR = build
PROTOCOL_DIR = $(BUILD_DIR)/protocols

PROTOCOL_SRC = $(WAYLAND_PROTOCOLS)/stable/xdg-shell/xdg-shell.xml
PROTOCOL_HEADER = xdg-shell-protocol.h
TARGET = hwc
SRCS = src/main.c src/compositor.c src/input.c src/output.c src/cursor.c src/keyboard.c src/xdgshell.c

.DEFAULT_GOAL = $(TARGET)

.PHONY: all clean

all: $(TARGET)

$(BUILD_DIR):
	mkdir -p $(BUILD_DIR) $(PROTOCOL_DIR)

$(PROTOCOL_DIR)/$(PROTOCOL_HEADER): $(PROTOCOL_SRC) | $(BUILD_DIR)
	$(WAYLAND_SCANNER) server-header $< $@

$(TARGET): $(SRCS) $(PROTOCOL_DIR)/$(PROTOCOL_HEADER) | $(BUILD_DIR)
	$(CC) $(CFLAGS) -I$(PROTOCOL_DIR) $(SRCS) $(LIBS) -o $(BUILD_DIR)/$@

clean:
	rm -rf $(BUILD_DIR)
