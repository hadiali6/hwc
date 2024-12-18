# hwc
Hadi's Wayland Compositor

# Building

**Install the following dependencies:**

- [zig](https://ziglang.org/download/) 0.13
- wayland
- wayland-protocols
- [wlroots](https://gitlab.freedesktop.org/wlroots/wlroots) 0.18
- xkbcommon
- libevdev
- pixman
- pkg-config

**Then run:**
```
zig build -Doptimize=ReleaseSafe --prefix ~/.local/ install
```

**Note:** Traditionally, most programs install under the `/usr` prefix, requiring admin privileges. Feel free to do that to install hwc as a system binary.
In the above, `~/.local/bin` will be where the hwc binary will live. You many need to update your `$PATH` to include `~/.local/bin`
