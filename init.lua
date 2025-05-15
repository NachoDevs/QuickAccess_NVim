-- ~/.config/nvim/lua/notesPlugin/init.lua
local M = {}

local LOG_FILE = vim.fn.stdpath("config") .. "/log.txt"
local WORKSPACE_FILE = vim.fn.stdpath("config") .. "/workspace.json"

-- Load JSON from file
local function load_workspace()
  local file = io.open(WORKSPACE_FILE, "r")
  if not file then return {} end
  local content = file:read("*a")
  file:close()
  local ok, data = pcall(vim.fn.json_decode, content)
  return ok and data or {}
end

-- Save JSON to file
local function save_workspace(data)
  local json = vim.fn.json_encode(data)
  local file = io.open(WORKSPACE_FILE, "w")
  if not file then
    vim.notify("Failed to write workspace", vim.log.levels.ERROR)
    return
  end
  file:write(json)
  file:close()
end

-- Find or create nested node based on path
local function find_node_at_path(tree, path)
  local node = tree
  for _, part in ipairs(path) do
    local found = nil
    for _, item in ipairs(node) do
      if item.name == part and item.children then
        found = item.children
        break
      end
    end
    if not found then return nil end
    node = found
  end
  return node
end

function M.add_to_workspace(tree_path)
  local data = load_workspace()
  local abs_path = vim.fn.expand("%:p")
  local filename = vim.fn.fnamemodify(abs_path, ":t")
  local path_parts = vim.split(tree_path, "/", { trimempty = true })

  local node = data
  for _, part in ipairs(path_parts) do
    local found = vim.tbl_filter(function(item)
      return item.name == part and item.children
    end, node)[1]

    if not found then
      local new = {
        name = part,
        expanded = true,
        children = {} }
      table.insert(node, new)
      node = new.children
    else
      node = found.children
    end
  end

  for _, item in ipairs(node) do
    if item.path == abs_path then
      vim.notify("File already exists", vim.log.levels.WARN)
      return
    end
  end

  table.insert(node, { name = filename, path = abs_path })
  save_workspace(data)
  vim.notify("Added file to workspace")
end

function M.remove_from_workspace(tree_path)
  local data = load_workspace()
  local abs_path = vim.fn.expand("%:p")
  local path_parts = vim.split(tree_path, "/", { trimempty = true })

  local node = find_node_at_path(data, path_parts)
  if not node then
    vim.notify("Path not found", vim.log.levels.ERROR)
    return
  end

  local new_children = vim.tbl_filter(function(item)
    return item.path ~= abs_path
  end, node)

  if #new_children == #node then
    vim.notify("File not found in this path", vim.log.levels.WARN)
  else
    local parent = find_node_at_path(data, vim.list_slice(path_parts, 1, #path_parts - 1))
    if parent then
      for _, item in ipairs(parent) do
        if item.name == path_parts[#path_parts] then
          item.children = new_children
        end
      end
    else
      data = new_children
    end
    save_workspace(data)
    vim.notify("Removed file from workspace")
  end
end

function M.open_workspace()
  local log = io.open(LOG_FILE, "w")
  if not log then
    vim.notify("Failed to open log file", vim.log.levels.ERROR)
    return
  end

  local prev_win = vim.api.nvim_get_current_win()
  local buf = vim.api.nvim_create_buf(false, true)

  local data = load_workspace()
  local line_items = {}

  -- Build the list first (no rendering yet)
  local function collect_node_lines(node, indent)
    if node.path then
      table.insert(line_items, { type = "file", name = node.name, path = node.path, indent = indent, node = node })
    elseif node.children then
      table.insert(line_items, { type = "folder", name = node.name, indent = indent, node = node })
      if node.expanded then
        for _, child in ipairs(node.children) do
          collect_node_lines(child, indent + 1)
        end
      end
    end
  end

  for _, node in ipairs(data) do
    collect_node_lines(node, 0)
  end

  -- Calculate height from lines
  local min_height = 8
  local max_height = 30
  local height = math.min(#line_items > min_height and #line_items or min_height, max_height)

  -- Calculate window position
  local width = 110
  local row = math.floor((vim.o.lines - height) / 2)
  local col = math.floor((vim.o.columns - width) / 2)

  log:write("height: ", height, '\n')
  log:write("rows: ", tostring(row), '\n')

  -- Create window
  local win = vim.api.nvim_open_win(buf, true, {
    relative = "editor",
    row = row,
    col = col,
    width = width,
    height = height,
    border = "rounded",
    style = "minimal",
  })

  line_items = {}

  local function render_node(node, indent)
    if node.path then
      table.insert(line_items, {
        type = "file",
        path = node.path,
        name = node.name,
        indent = indent,
        node = node,
      })
    elseif node.children then
      table.insert(line_items, {
        type = "folder",
        path = node.name,
        name = node.name,
        indent = indent,
        node = node,
      })

      if node.expanded then
        for _, child in ipairs(node.children) do
          render_node(child, indent + 1)
        end
      end
    end
  end

  local function redraw(data)
    line_items = {}
    for _, node in ipairs(data) do
      render_node(node, 0)
    end

    local lines = {}
    --log:write("Tree:", '\n')
    for i, item in ipairs(line_items) do
      local line
      local icon = item.type == "file" and "📄" or (item.node.expanded and "📂" or "📁")
      --table.insert(lines, string.rep("  ", item.indent) .. icon .. " " .. item.name)
      if item.type == "file" then
        line = string.rep("  ", item.indent) .. icon .. " " .. item.name .. "  -  " .. item.path
      else
        line = string.rep("  ", item.indent) .. icon .. " " .. item.name
      end
      table.insert(lines, line)

      --log:write(i)
      --log:write(" ", item.type)
      --log:write(" ", item.name)
      --log:write('\n')
    end

    vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  end

  local data = load_workspace()
  redraw(data)

  vim.keymap.set("n", "<CR>", function()
    --local innerlog = io.open(LOG_FILE, "w")
    --if not innerlog then
    --  vim.notify("Failed to open log file", vim.log.levels.ERROR)
    --  return
    --end

    local line = vim.fn.line(".")
    --innerlog:write(tostring(line), "\n")
    local item = line_items[line]

    -- Debug
    --for i, debugitem in ipairs(line_items) do
      --print(i, debugitem.type, debugitem.name)
      --innerlog:write(tostring(i))
      --innerlog:write(" ", debugitem.name)
      --innerlog:write('\n')
    --end
    -- Debug

    if not item then return end

    if item.type == "file" then
      vim.api.nvim_set_current_win(prev_win)
      vim.cmd("edit " .. vim.fn.fnameescape(item.path))
      vim.api.nvim_win_close(win, true)
    elseif item.type == "folder" then
      item.node.expanded = not item.node.expanded
      save_workspace(data)
      redraw(data)
      vim.api.nvim_win_set_cursor(win, { line, 0 })
    end
    --innerlog:close()
  end, { buffer = buf, noremap = true, silent = true })

  vim.keymap.set("n", "q", function()
    vim.api.nvim_win_close(win, true)
  end, { buffer = buf, noremap = true, silent = true })

  vim.keymap.set("n", "<Esc>", function()
    vim.api.nvim_win_close(win, true)
  end, { buffer = buf, noremap = true, silent = true })


  log:close()
end

-- Commands
vim.api.nvim_create_user_command("OpenNotes", function()
  require("notesPlugin").open_workspace()
end, {})

vim.api.nvim_create_user_command("AddToNotes", function(opts)
  require("notesPlugin").add_to_workspace(opts.args)
end, { nargs = 1 })

vim.api.nvim_create_user_command("RemoveFromNotes", function(opts)
  require("notesPlugin").remove_from_workspace(opts.args)
end, { nargs = 1 })

return M
