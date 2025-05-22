-- lua/QuickAccess_NVim/init.lua
local M = {}

-- Require the core logic module from the notesPlugin subdirectory
local Core = require("QuickAccess_NVim.src.core")

-- Define public functions that delegate to the Core module
function M.open_workspace()
  Core.open_workspace()
end

function M.add_to_workspace(tree_path)
  Core.add_to_workspace(tree_path)
end

function M.remove_current_file_from_workspace()
  Core.remove_current_file_from_workspace() -- Will match renamed Core function
end

-- Define user commands
-- These commands should refer to the 'QuickAccess_NVim' module,
-- which is this file itself.
vim.api.nvim_create_user_command("OpenNotes", function()
  require("QuickAccess_NVim").open_workspace()
end, {})

vim.api.nvim_create_user_command("AddToNotes", function(opts)
  require("QuickAccess_NVim").add_to_workspace(opts.args)
end, { nargs = '?' })

vim.api.nvim_create_user_command("RemoveFromNotes", function()
  require("QuickAccess_NVim").remove_current_file_from_workspace()
end, { nargs = 0 })

return M
