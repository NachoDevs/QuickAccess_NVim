-- lua/notesPlugin/ui.lua
local UI = {}

local config = require("QuickAccess_NVim.src.config")

-- Module-level variables for UI state
UI.current_buf = nil
UI.current_win = nil
UI.line_items = {} -- Stores the metadata for each line in the UI window
UI.prev_win_id = nil
UI.on_input_callback_ref = nil -- Stores the callback function

-- Internal function to render content to the buffer
function UI.render_content(data_tree)
  if not UI.current_buf or not vim.api.nvim_buf_is_valid(UI.current_buf) then
    -- Or handle error: vim.notify("UI buffer is not valid for rendering", vim.log.levels.ERROR)
    return
  end

  UI.line_items = {} -- Clear previous items

  local function collect_lines_recursive(nodes, indent_level)
    for _, node in ipairs(nodes) do
      if node.path and node.name then -- It's a file
        table.insert(UI.line_items, {
          type = "file",
          name = node.name,
          path = node.path,
          indent = indent_level,
          node = node, -- Keep a reference to the original node
        })
      elseif node.children and node.name then -- It's a folder
        table.insert(UI.line_items, {
          type = "folder",
          name = node.name,
          indent = indent_level,
          node = node, -- Keep a reference to the original node
        })
        if node.expanded then
          collect_lines_recursive(node.children, indent_level + 1)
        end
      end
    end
  end

  collect_lines_recursive(data_tree, 0)

  local lines_to_display = {}
  for _, item in ipairs(UI.line_items) do
    local icon
    if item.type == "file" then
      icon = "📄"
    else -- folder
      icon = item.node.expanded and "📂" or "📁"
    end
    local line_text = string.rep("  ", item.indent) .. icon .. " " .. item.name
    if item.type == "file" then
      line_text = line_text .. "  -  " .. item.path
    end
    table.insert(lines_to_display, line_text)
  end

  -- Keep buffer loaded for modification if it was unloaded
  vim.api.nvim_buf_set_option(UI.current_buf, 'bufhidden', 'hide')
  vim.api.nvim_buf_set_option(UI.current_buf, "modifiable", true)
  vim.api.nvim_buf_set_lines(UI.current_buf, 0, -1, false, lines_to_display)
  vim.api.nvim_buf_set_option(UI.current_buf, "modifiable", false)
end

function UI.open(initial_data_tree, on_input_callback)
  if UI.current_win and vim.api.nvim_win_is_valid(UI.current_win) then
    vim.api.nvim_win_set_focus(UI.current_win)
    return
  end

  UI.on_input_callback_ref = on_input_callback
  UI.prev_win_id = vim.api.nvim_get_current_win()

  -- Calculate window dimensions
  local num_items = #UI.line_items -- Assuming render_content was called or will be called by this function.
                                  -- For dynamic height, we might need to pre-calculate lines based on initial_data_tree
  local temp_line_items_for_height = {}
  local function count_lines_recursive(nodes)
    local count = 0
    for _, node in ipairs(nodes) do
      count = count + 1 -- for the node itself
      if node.children and node.expanded then
        count = count + count_lines_recursive(node.children)
      end
    end
    return count
  end
  num_items = count_lines_recursive(initial_data_tree)


  local height = math.min(math.max(num_items, config.default_min_height), config.default_max_height)
  local width = config.default_width
  local row = math.floor((vim.o.lines - height) / 2)
  local col = math.floor((vim.o.columns - width) / 2)

  UI.current_buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_option(UI.current_buf, 'bufhidden', 'wipe') -- Wipe buffer when window is closed

  UI.current_win = vim.api.nvim_open_win(UI.current_buf, true, {
    relative = "editor",
    row = row,
    col = col,
    width = width,
    height = height,
    border = config.window_border or "rounded", -- Default to "rounded" if nil
    style = config.window_style or "minimal",   -- Default to "minimal" if nil
    title = "Notes Workspace",
    title_pos = "center",
  })

  UI.render_content(initial_data_tree) -- Draw the content

  -- Set up keymaps
  vim.keymap.set("n", "<CR>", function()
    local current_line_num = vim.fn.line(".")
    local item = UI.line_items[current_line_num]
    if item and UI.on_input_callback_ref then
      UI.on_input_callback_ref({ type = item.type, data = item, line_num = current_line_num })
    end
  end, { buffer = UI.current_buf, noremap = true, silent = true })

  vim.keymap.set("n", "q", function()
    if UI.on_input_callback_ref then
      UI.on_input_callback_ref({ type = "close" })
    end
  end, { buffer = UI.current_buf, noremap = true, silent = true })

  vim.keymap.set("n", "<Esc>", function()
    if UI.on_input_callback_ref then
      UI.on_input_callback_ref({ type = "close" })
    end
  end, { buffer = UI.current_buf, noremap = true, silent = true })

  -- Set buffer options for the UI window
  vim.bo[UI.current_buf].buftype = "nofile"
  vim.bo[UI.current_buf].swapfile = false
  vim.bo[UI.current_buf].filetype = "NotesPluginUI" -- For potential syntax highlighting or ftplugins
  vim.bo[UI.current_buf].modifiable = false
end

function UI.close()
  if UI.current_win and vim.api.nvim_win_is_valid(UI.current_win) then
    vim.api.nvim_win_close(UI.current_win, true) -- Force close
  end
  -- Reset UI state
  UI.current_buf = nil
  UI.current_win = nil
  UI.line_items = {}
  UI.on_input_callback_ref = nil -- Clear the callback

  if UI.prev_win_id and vim.api.nvim_win_is_valid(UI.prev_win_id) then
    vim.api.nvim_set_current_win(UI.prev_win_id)
  end
  UI.prev_win_id = nil
end

function UI.refresh(updated_data_tree)
  if UI.current_buf and vim.api.nvim_buf_is_valid(UI.current_buf) and
     UI.current_win and vim.api.nvim_win_is_valid(UI.current_win) then
    local current_cursor = vim.api.nvim_win_get_cursor(UI.current_win) -- [row, col]
    local old_line_count = #UI.line_items

    UI.render_content(updated_data_tree)

    local new_line_count = #UI.line_items

    -- Attempt to restore cursor position
    if new_line_count > 0 then
      local new_cursor_line = current_cursor[1]
      if new_cursor_line > new_line_count then
        new_cursor_line = new_line_count -- Adjust if cursor was beyond the new content
      end
      -- Ensure the line number is at least 1
      new_cursor_line = math.max(1, new_cursor_line)
      vim.api.nvim_win_set_cursor(UI.current_win, { new_cursor_line, current_cursor[2] })
    end
  else
    -- Optional: Notify if UI is not active
    -- vim.notify("UI not active, cannot refresh.", vim.log.levels.WARN)
  end
end

return UI
