# hwc
Hadi's Wayland Compositor

# dependencies
libwayland
libxkbcommon
pixman
wayland-protocols
wlroots (0.18)
libc

# build
`zig build` or to build and run `zig build run -- <args>`

# run
`hwc <arg command>`

# help
`hwc -h`


# binds
`Alt+Escape`: Terminate the compositor
`Alt+F1`: Cycle between windows
`Alt+m`: Minimize current window
`Alt+Shift+m`: Maximize current window
`Alt+f`: Fullscreen current window
