CC=clang
WAYLAND_PROTOCOLS=$(shell pkg-config --variable=pkgdatadir wayland-protocols)
WAYLAND_SCANNER=$(shell pkg-config --variable=wayland_scanner wayland-scanner)
LIBS=\
	 $(shell pkg-config --cflags --libs "wlroots-0.18") \
	 $(shell pkg-config --cflags --libs wayland-server) \
	 $(shell pkg-config --cflags --libs xkbcommon)

# wayland-scanner is a tool which generates C headers and rigging for Wayland
# protocols, which are specified in XML. wlroots requires you to rig these up
# to your build system yourself and provide them in the include path.
xdg-shell-protocol.h:
	$(WAYLAND_SCANNER) server-header \
		$(WAYLAND_PROTOCOLS)/stable/xdg-shell/xdg-shell.xml ./build/protocols/$@

hwc: src/*.c src/macros.h xdg-shell-protocol.h
	$(CC) $(CFLAGS) \
		-g -Werror -Wundef -Wno-unused-parameter -Wno-error=uninitialized \
		-DWLR_USE_UNSTABLE \
		-Ibuild/protocols \
		-o build/$@ $< \
		$(LIBS)

clean:
	rm -f build/hwc build/protocols/xdg-shell-protocol.h build/protocols/xdg-shell-protocol.c

.DEFAULT_GOAL=hwc
.PHONY: clean
