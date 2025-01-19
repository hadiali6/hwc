all: run

build:
    clear && zig build -Dtarget=x86_64-linux-gnu -Dcpu=x86_64 --search-prefix /usr -freference-trace

run:
    clear && zig build run -Dtarget=x86_64-linux-gnu -Dcpu=x86_64 --search-prefix /usr -freference-trace

valgrind:
    clear && valgrind --leak-check=full ./zig-out/bin/hwc

clean:
    rm vgcore.*
