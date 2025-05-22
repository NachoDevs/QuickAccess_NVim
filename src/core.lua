-- lua/notesPlugin/core.lua
local Core = {}

local Workspace = require("QuickAccess_NVim.src.workspace")
local UI = require("QuickAccess_NVim.src.ui")
local Config = require("QuickAccess_NVim.src.config") -- Though direct usage might be minimal

function Core.add_to_workspace(tree_path_str)
  local abs_path = vim.fn.expand("%:p")
  if not abs_path or abs_path == "" then
    vim.notify("Cannot add an unnamed buffer to workspace.", vim.log.levels.WARN)
    return
  end
  local filename = vim.fn.fnamemodify(abs_path, ":t")
  
  local path_parts
  if tree_path_str == nil or tree_path_str == "" then
    path_parts = {}
  else
    path_parts = vim.split(tree_path_str, "/", { trimempty = true })
  end

  local data = Workspace.load_workspace()
  local modified_data, msg = Workspace.add_item(data, path_parts, filename, abs_path)

  if modified_data then
    if Workspace.save_workspace(modified_data) then
      vim.notify(msg or "File added to workspace")
      -- If UI is open, refresh it
      if UI.current_win and vim.api.nvim_win_is_valid(UI.current_win) then
        UI.refresh(modified_data)
      end
    else
      vim.notify("Failed to save workspace after adding file.", vim.log.levels.ERROR)
    end
  else
    vim.notify(msg or "Failed to add file", vim.log.levels.WARN)
  end
end

function Core.remove_current_file_from_workspace()
  local abs_path = vim.fn.expand("%:p")
  if not abs_path or abs_path == "" then
    vim.notify("Current buffer has no path, cannot remove.", vim.log.levels.WARN)
    return
  end

  local data = Workspace.load_workspace()
  local modified_data, msg = Workspace.remove_file_by_abs_path(data, abs_path)

  if modified_data then
    if Workspace.save_workspace(modified_data) then -- Ensure save_workspace returns true on success
      vim.notify(msg or "File removed from workspace")
      -- Refresh UI if open
      if UI and UI.refresh and UI.current_win and vim.api.nvim_win_is_valid(UI.current_win) then
        UI.refresh(modified_data)
      end
    else
      vim.notify("Failed to save workspace after removing file.", vim.log.levels.ERROR)
    end
  else
    vim.notify(msg or "Failed to remove file", vim.log.levels.WARN)
  end
end

function Core.open_workspace()
  local current_workspace_data = Workspace.load_workspace()

  local function handle_ui_input(event)
    if not event or not event.type then return end

    if event.type == "file" and event.data and event.data.path then
      UI.close()
      vim.cmd("edit " .. vim.fn.fnameescape(event.data.path))
    elseif event.type == "folder" and event.data and event.data.node then
      event.data.node.expanded = not event.data.node.expanded
      -- The event.data.node is a reference within current_workspace_data,
      -- so current_workspace_data is already modified.
      if Workspace.save_workspace(current_workspace_data) then
        UI.refresh(current_workspace_data)
      else
        vim.notify("Failed to save workspace after toggling folder.", vim.log.levels.ERROR)
        -- Optionally, revert the toggle if save fails and refresh
        -- event.data.node.expanded = not event.data.node.expanded
        -- UI.refresh(current_workspace_data)
      end
    elseif event.type == "close" then
      UI.close()
    end
  end

  UI.open(current_workspace_data, handle_ui_input)
end

return Core
