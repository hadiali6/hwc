# hwc
Hadi's Wayland Compositor

**Note:**
This is not in a usable state right now and I am only creating this for learning/fun purposes.
Go use a good compositor like [hyprland](https://github.com/hyprwm/Hyprland), [sway](https://github.com/swaywm/sway) or [river](https://codeberg.org/river/river)

# Building

**Install the following dependencies:**

- [zig](https://ziglang.org/download/) 0.13
- lua (5.1, 5.2, 5.3, 5.4, LuaJIT)
- wayland
- wayland-protocols
- [wlroots](https://gitlab.freedesktop.org/wlroots/wlroots) 0.18
- xkbcommon
- libevdev
- libinput
- pixman
- pkg-config

**Then run:**
```
zig build -Doptimize=ReleaseSafe --prefix ~/.local/ install
```

**Note:** Traditionally, most programs install under the `/usr` prefix, requiring admin privileges. Feel free to do that to install hwc as a system binary.
In the above, `~/.local/bin` will be where the hwc binary will live. You many need to update your `$PATH` to include `~/.local/bin`
