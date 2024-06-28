CC = clang
CFLAGS = -g -Wall -Wextra -DWLR_USE_UNSTABLE
WAYLAND_PROTOCOLS = $(shell pkg-config --variable=pkgdatadir wayland-protocols)
WAYLAND_SCANNER = $(shell pkg-config --variable=wayland_scanner wayland-scanner)
LIBS = $(shell pkg-config --cflags --libs "wlroots-0.18" wayland-server xkbcommon)

BUILD_DIR = build
PROTOCOL_DIR = $(BUILD_DIR)/protocols

PROTOCOL_SRC = $(WAYLAND_PROTOCOLS)/stable/xdg-shell/xdg-shell.xml
PROTOCOL_HEADER = xdg-shell-protocol.h
TARGET = hwc
SRCS = src/main.c src/server.c

.DEFAULT_GOAL = $(TARGET)

.PHONY: all clean

all: $(TARGET)

$(BUILD_DIR):
	mkdir -p $(BUILD_DIR) $(PROTOCOL_DIR)

$(PROTOCOL_DIR)/$(PROTOCOL_HEADER): $(PROTOCOL_SRC) | $(BUILD_DIR)
	$(WAYLAND_SCANNER) server-header $< $@

$(TARGET): $(SRCS) $(PROTOCOL_DIR)/$(PROTOCOL_HEADER) | $(BUILD_DIR)
	$(CC) $(CFLAGS) -I$(PROTOCOL_DIR) -o $(BUILD_DIR)/$@ $(SRCS) $(LIBS)

clean:
	rm -rf $(BUILD_DIR)

src/main.o: src/main.c
src/server.o: src/server.c
