-- lua/QuickAccess_NVim/src/workspace.lua
local Workspace = {}

local config = require("QuickAccess_NVim.src.config")

-- Load JSON from file
function Workspace.load_workspace()
  local file = io.open(config.WORKSPACE_FILE, "r")
  if not file then return {} end
  local content = file:read("*a")
  file:close()
  local ok, data = pcall(vim.fn.json_decode, content)
  return ok and data or {}
end

-- Save JSON to file
function Workspace.save_workspace(data)
  local json = vim.fn.json_encode(data)
  local file = io.open(config.WORKSPACE_FILE, "w")
  if not file then
    vim.notify("Failed to write workspace", vim.log.levels.ERROR)
    return false
  end
  file:write(json)
  file:close()
  return true
end

-- Recursive helper function to find an item and its parent context
local function find_item_and_parent_context(nodes_list, target_abs_path, current_parent_path_parts)
  for i, item in ipairs(nodes_list) do
    -- Check if it's a file and matches the target path
    if item.path and item.path == target_abs_path then
      return {
        item = item,
        parent_list = nodes_list,
        item_index = i,
        path_parts_to_parent = current_parent_path_parts
      }
    end
    -- If it's a folder, recurse
    if item.children then
      local next_path_parts = vim.deepcopy(current_parent_path_parts)
      table.insert(next_path_parts, item.name)
      local found_in_child = find_item_and_parent_context(item.children, target_abs_path, next_path_parts)
      if found_in_child then
        return found_in_child
      end
    end
  end
  return nil -- Item not found in this list or its children
end

-- Add an item to the workspace data
function Workspace.add_item(data_tree, tree_path_parts, file_name, file_abs_path)
  local current_level_children = data_tree
  -- local current_parent_table = data_tree -- Keep track of the table containing current_level_children -- Not actually used

  for _, part in ipairs(tree_path_parts) do
    local found_node = nil
    for _, item in ipairs(current_level_children) do
      if item.name == part and item.children then
        found_node = item
        break
      end
    end

    if not found_node then
      local new_folder = {
        name = part,
        expanded = true,
        children = {}
      }
      table.insert(current_level_children, new_folder)
      -- current_parent_table = current_level_children -- Not needed
      current_level_children = new_folder.children
    else
      -- current_parent_table = current_level_children -- Not needed
      current_level_children = found_node.children
    end
  end

  -- Check if file already exists in the target node's children
  for _, item in ipairs(current_level_children) do
    if item.path == file_abs_path then
      return nil, "File already exists"
    end
  end

  -- Insert the new file item
  table.insert(current_level_children, { name = file_name, path = file_abs_path })
  return data_tree, "File added"
end

-- Remove a file by its absolute path from the workspace data
function Workspace.remove_file_by_abs_path(data_tree, file_abs_path)
  local found_context = find_item_and_parent_context(data_tree, file_abs_path, {})
  
  if found_context then
    table.remove(found_context.parent_list, found_context.item_index)
    Workspace.cleanup_empty_folders(data_tree, found_context.path_parts_to_parent)
    return data_tree, "File removed successfully."
  else
    return nil, "File not found in workspace."
  end
end

-- Function to cleanup empty folders recursively
function Workspace.cleanup_empty_folders(data_tree_root, path_to_folder_parts)
  if not path_to_folder_parts or #path_to_folder_parts == 0 then
    return false -- Base case: nothing to clean at the root or if path is empty
  end

  local parent_list_of_folder_to_check
  local folder_name_to_check = path_to_folder_parts[#path_to_folder_parts]
  local grandparent_path_parts = vim.list_slice(path_to_folder_parts, 1, #path_to_folder_parts - 1)

  if #grandparent_path_parts == 0 then
    parent_list_of_folder_to_check = data_tree_root
  else
    -- Navigate to the grandparent to find the parent list
    local current_level = data_tree_root
    for _, part_name in ipairs(grandparent_path_parts) do
      local found_next_level = nil
      if current_level and type(current_level) == "table" then
        for _, node in ipairs(current_level) do
          if node.name == part_name and node.children then
            found_next_level = node.children
            break
          end
        end
      end
      current_level = found_next_level
      if not current_level then
        return false -- Grandparent path is invalid
      end
    end
    parent_list_of_folder_to_check = current_level
  end
  
  if not parent_list_of_folder_to_check then
      return false -- Could not find parent list
  end

  local folder_index_to_remove = -1
  local folder_to_check = nil

  for i, item in ipairs(parent_list_of_folder_to_check) do
    if item.name == folder_name_to_check and item.children then
      folder_to_check = item
      folder_index_to_remove = i
      break
    end
  end

  if folder_to_check and #folder_to_check.children == 0 then
    table.remove(parent_list_of_folder_to_check, folder_index_to_remove)
    -- Recursively call cleanup for the parent of the folder just removed
    Workspace.cleanup_empty_folders(data_tree_root, grandparent_path_parts)
    return true -- Cleanup occurred
  end

  return false -- No cleanup occurred at this level
end


return Workspace
