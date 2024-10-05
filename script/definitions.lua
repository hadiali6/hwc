---@meta

---@param cmd string # command to run.
---@param request_pid boolean? # if true, get pid of created process.
---@param request_stdin_fd boolean? # if true, get file descriptor of the process stdin.
---@param request_stdout_fd boolean? # if true, get file descriptor of the process stdout.
---@param request_stderr_fd boolean? # if true, get file descriptor of the process stderr.
---@return integer? # pid if requested.
---@return integer? # stdin_fd if requested.
---@return integer? # stdout_fd if requested.
---@return integer? # stderr_fd if requested.
function spawn(cmd, request_pid, request_stdin_fd, request_stdout_fd, request_stderr_fd) end
