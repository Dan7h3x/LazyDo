local M = {}
local utils = require('lazydo.utils')
local Task = require('lazydo.task').Task

function M.save_tasks(lazydo)
  local ok, err = pcall(function()
    -- Ensure storage directory exists
    local dir = vim.fn.fnamemodify(lazydo.opts.storage.path, ":h")
    if vim.fn.isdirectory(dir) == 0 then
      vim.fn.mkdir(dir, "p")
    end

    -- Prepare backup if enabled
    if lazydo.opts.storage.backup then
      local backup_path = lazydo.opts.storage.path .. ".bak"
      if vim.fn.filereadable(lazydo.opts.storage.path) == 1 then
        -- Remove old backup if exists
        if vim.fn.filereadable(backup_path) == 1 then
          vim.fn.delete(backup_path)
        end
        -- Create new backup
        vim.fn.rename(lazydo.opts.storage.path, backup_path)
      end
    end

    -- Prepare data for saving
    local save_data = {
      version = lazydo.opts.version,
      last_modified = os.time(),
      tasks = vim.tbl_map(function(task)
        return task:serialize()
      end, lazydo.tasks)
    }

    -- Write atomically using temporary file
    local temp_path = lazydo.opts.storage.path .. ".tmp"
    local file = io.open(temp_path, "w")
    if not file then
      error("Could not open temporary file for writing: " .. temp_path)
    end

    local json_str = vim.json.encode(save_data)
    file:write(json_str)
    file:close()

    -- Atomic rename
    if vim.fn.rename(temp_path, lazydo.opts.storage.path) ~= 0 then
      error("Failed to rename temporary file")
    end
  end)

  if not ok then
    vim.notify("Failed to save tasks: " .. err, vim.log.levels.ERROR)
    return false
  end
  return true
end

function M.load_tasks(lazydo)
  local ok, err = pcall(function()
    local path = lazydo.opts.storage.path
    local backup_path = path .. ".bak"

    -- Try loading main file first
    local file = io.open(path, "r")
    if not file and vim.fn.filereadable(backup_path) == 1 then
      -- Try backup if main file fails
      file = io.open(backup_path, "r")
      if file then
        vim.notify("Loading from backup file", vim.log.levels.WARN)
      end
    end

    if not file then
      lazydo.tasks = {}
      return
    end

    local content = file:read("*all")
    file:close()

    local data = vim.json.decode(content)
    if not data or not data.tasks then
      error("Invalid data format")
    end

    -- Version check and migration if needed
    if data.version ~= lazydo.opts.version then
      data = M.migrate_data(data, lazydo.opts.version)
    end

    -- Deserialize tasks
    lazydo.tasks = vim.tbl_map(function(task_data)
      return Task.deserialize(task_data)
    end, data.tasks)
  end)

  if not ok then
    vim.notify("Failed to load tasks: " .. err, vim.log.levels.ERROR)
    lazydo.tasks = {}
    return false
  end
  return true
end

function M.migrate_data(data, target_version)
  -- Add migration logic here when needed
  return data
end

return M 