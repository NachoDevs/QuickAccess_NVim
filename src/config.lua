-- lua/notesPlugin/config.lua
local M = {}

-- Files
M.LOG_FILE = vim.fn.stdpath("config") .. "/log.txt"
M.WORKSPACE_FILE = vim.fn.stdpath("config") .. "/workspace.json"

-- UI Configuration
M.window_border = "rounded"
M.window_style = "minimal"
M.default_min_height = 8
M.default_max_height = 30
M.default_width = 110

return M
