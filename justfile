all: run_no_llvm

test:
    clear && zig build test -Dtarget=x86_64-linux-gnu -Dcpu=x86_64 --search-prefix /usr -freference-trace --summary all 

build:
    clear && zig build -Dtarget=x86_64-linux-gnu -Dcpu=x86_64 --search-prefix /usr -freference-trace

run_no_llvm:
    clear && zig build run -Dno-llvm -Dtarget=x86_64-linux-gnu -Dcpu=x86_64 --search-prefix /usr -freference-trace

run_llvm:
    clear && zig build run -Dtarget=x86_64-linux-gnu -Dcpu=x86_64 --search-prefix /usr -freference-trace

valgrind:
    clear && valgrind --leak-check=full ./zig-out/bin/hwc

clean:
    rm vgcore.*
