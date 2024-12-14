---@meta

hwc = {}

---Terminate the compositor.
function hwc.exit() end

---Reload configuration file.
function hwc.reload() end

---@param cmd string # command to run.
---@param request_pid boolean? # if true, get pid of created process.
---@param request_stdin_fd boolean? # if true, get file descriptor of the process stdin.
---@param request_stdout_fd boolean? # if true, get file descriptor of the process stdout.
---@param request_stderr_fd boolean? # if true, get file descriptor of the process stderr.
---@return integer? # pid if requested.
---@return integer? # stdin_fd if requested.
---@return integer? # stdout_fd if requested.
---@return integer? # stderr_fd if requested.
function hwc.spawn(cmd, request_pid, request_stdin_fd, request_stdout_fd, request_stderr_fd) end

---@param key string # key.
---@param modifiers string # modifiers.
---@param is_repeat boolean # repeated if held.
---@param is_on_release boolean # executed on release instead of press.
---@param layout_index integer? # xkb layout index.
---@param callback fun() # callback called when keybind is pressed.
---@return integer # integer ID representing index inside keybind list.
function hwc.add_keybind(key, modifiers, is_repeat, is_on_release, layout_index, callback) end

---@param id integer # integer ID representing index inside keybind list.
---@return boolean # true if removed, false if not removed.
function hwc.remove_keybind_by_id(id) end

---@param key string # key.
---@param modifiers string # modifiers.
---@return boolean # true if removed, false if not removed.
function hwc.remove_keybind(key, modifiers) end

---**Create a new output.**
---> Only available in Wayland, Headless, and X11 backends.
---> Generally intended for developer use for testing multi-monitor functionality.
---> Headless outputs can also be useful when dealing with VNC applications.
---
---Under the hood, this uses the following wlroots functions for their corresponding backends:
---```c
---struct wlr_output *wlr_headless_add_output(struct wlr_backend *backend, unsigned int width, unsigned int height);
---```
---```c
---struct wlr_output *wlr_wl_output_create(struct wlr_backend *backend);
---```
---```c
---struct wlr_output *wlr_x11_output_create(struct wlr_backend *backend);
---```
---
---@param width integer|1920 # Only applies to headless backend. Defaults to 1920
---@param height integer|1080 # Only applies to headless backend. Defaults to 1080
function hwc.create_output(width, height) end
