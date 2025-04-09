-- storage.lua
local Utils = require("lazydo.utils")

---@class Storage
local Storage = {}

-- Private config variable
local config = nil
local cache = {
  data = nil,
  project_root = nil,
  last_save = nil,
  is_dirty = false,
  selected_storage = nil,   -- New field to track user selected storage
  custom_project_name = nil -- New field to store custom project name
}

---Setup storage with configuration
---@param user_config LazyDoConfig
---@return nil
function Storage.setup(user_config)
  if not user_config then
    error("Storage configuration is required")
  end
  config = user_config
  -- Reset cache on setup
  cache = {
    data = nil,
    project_root = nil,
    last_save = nil,
    is_dirty = false,
    selected_storage = nil,
    custom_project_name = nil
  }
end

---@return string
local function get_git_root()
  if not config then
    error("Storage not initialized. Call setup() first")
  end

  -- Only try git root if configured
  if not (config.storage.project.enabled and config.storage.project.use_git_root) then
    return nil
  end

  local git_cmd = "git rev-parse --show-toplevel"
  local ok, result = pcall(vim.fn.systemlist, git_cmd)
  if not ok or not result or #result == 0 or result[1]:match("^fatal:") then
    -- Not a git directory or git command failed
    return nil
  end
  return result[1]
end

---Find all potential project markers in the current working directory
---@return table project_markers List of potential project directories with marker info
local function find_project_markers()
  local cwd = vim.fn.getcwd()
  if not config then
    error("Storage not initialized. Call setup() first")
  end

  local markers = config.storage.project.markers or { ".git", ".lazydo", "package.json", "Cargo.toml", "go.mod" }
  local project_markers = {}

  -- Check for git root first
  local git_root = get_git_root()
  if git_root then
    table.insert(project_markers, {
      path = git_root,
      name = "Git Project: " .. vim.fn.fnamemodify(git_root, ":t"),
      type = "git",
      priority = 1
    })
  end

  -- Check for specific LazyDo marker
  local check_path = cwd
  while check_path and check_path ~= "" do
    local lazydo_path = check_path .. "/.lazydo"
    if vim.fn.filereadable(lazydo_path) == 1 or vim.fn.isdirectory(lazydo_path) == 1 then
      table.insert(project_markers, {
        path = check_path,
        name = "LazyDo Project: " .. vim.fn.fnamemodify(check_path, ":t"),
        type = "lazydo",
        priority = 2
      })
      break
    end

    -- Move up to parent directory
    local parent_path = vim.fn.fnamemodify(check_path, ":h")
    if parent_path == check_path then
      break -- We've reached the root
    end
    check_path = parent_path
  end

  -- Check for other project markers in current directory
  for _, marker in ipairs(markers) do
    if marker ~= ".git" and marker ~= ".lazydo" then
      local marker_path = cwd .. "/" .. marker
      if vim.fn.filereadable(marker_path) == 1 or vim.fn.isdirectory(marker_path) == 1 then
        table.insert(project_markers, {
          path = cwd,
          name = "Project (" .. marker .. "): " .. vim.fn.fnamemodify(cwd, ":t"),
          type = "marker",
          priority = 3,
          marker = marker
        })
        break
      end
    end
  end

  -- Sort by priority
  table.sort(project_markers, function(a, b) return a.priority < b.priority end)

  return project_markers
end
local function get_project_root()
  if not config then
    error("Storage not initialized. Call setup() first")
  end
  return cache.project_root or "Global"
end
---Smart project detection with interactive UI for selection
---@param force_prompt boolean Force prompting even if a storage is already selected
---@return boolean is_project_mode, string? project_path
function Storage.smart_project_detection(force_prompt)
  if not config then
    error("Storage not initialized. Call setup() first")
  end

  -- If user already made a selection and we're not forcing a prompt, use that
  if cache.selected_storage and not force_prompt then
    if cache.selected_storage == "global" then
      return false, nil
    elseif cache.selected_storage == "custom" and cache.custom_project_name then
      return true, cache.project_root
    elseif cache.project_root then
      return true, cache.project_root
    end
  end

  -- Get all potential project markers
  local project_markers = find_project_markers()

  -- Prepare selection options
  local options = {}
  local paths = {}

  -- Add global option
  table.insert(options, "Global Storage (accessible from everywhere)")
  table.insert(paths, { type = "global" })

  -- Add project options
  for _, marker in ipairs(project_markers) do
    table.insert(options, marker.name .. " (" .. marker.path .. ")")
    table.insert(paths, { type = "project", path = marker.path })
  end

  -- Add custom project option
  table.insert(options, "Custom Project Name (create new project storage)")
  table.insert(paths, { type = "custom" })

  -- Show selection UI
  vim.ui.select(options, {
    prompt = "Select LazyDo storage mode:",
    format_item = function(item) return item end
  }, function(choice, idx)
    if not choice or not idx then
      -- User cancelled, default to global
      cache.selected_storage = "global"
      return false, nil
    end

    local selected = paths[idx]

    if selected.type == "global" then
      -- User selected global storage
      cache.selected_storage = "global"
      config.storage.project.enabled = false
      cache.project_root = nil
      vim.notify("Using global storage for LazyDo", vim.log.levels.INFO)
      return false, nil
    elseif selected.type == "project" then
      -- User selected an existing project
      cache.selected_storage = "project"
      config.storage.project.enabled = true
      cache.project_root = selected.path

      -- Create .lazydo marker if configured
      if config.storage.project.create_marker then
        local marker_path = selected.path .. "/.lazydo"
        if vim.fn.filereadable(marker_path) ~= 1 and vim.fn.isdirectory(marker_path) ~= 1 then
          pcall(function() vim.fn.mkdir(marker_path, "p") end)
        end
      end

      vim.notify("Using project storage at: " .. selected.path, vim.log.levels.INFO)
      return true, selected.path
    elseif selected.type == "custom" then
      -- User wants to create a custom project
      vim.ui.input({
        prompt = "Enter project name: ",
      }, function(project_name)
        if not project_name or project_name == "" then
          -- User cancelled, default to global
          cache.selected_storage = "global"
          config.storage.project.enabled = false
          vim.notify("Using global storage for LazyDo", vim.log.levels.INFO)
          return false, nil
        end

        -- Set custom project name
        cache.selected_storage = "custom"
        cache.custom_project_name = project_name
        config.storage.project.enabled = true

        -- Store in the current directory
        cache.project_root = vim.fn.getcwd()

        -- Create .lazydo marker and directory
        local marker_path = cache.project_root .. "/.lazydo"
        pcall(function() vim.fn.mkdir(marker_path, "p") end)

        -- Create project-specific directory
        local project_dir = cache.project_root .. "/.lazydo/" .. project_name
        pcall(function() vim.fn.mkdir(project_dir, "p") end)

        vim.notify("Created new project storage: " .. project_name, vim.log.levels.INFO)
        return true, cache.project_root
      end)
    end
  end)

  -- Return default value while waiting for async selection
  return config.storage.project.enabled, cache.project_root
end

---Migrate tasks from old locations to new .lazydo directory structure
---@param project_root string The project root directory
---@return boolean success Whether migration succeeded
local function migrate_legacy_tasks(project_root)
  if not project_root or project_root == "" then
    return false
  end

  -- Define possible old locations
  local old_locations = {
    project_root .. "/tasks.json",                                                                     -- Direct in project root
    project_root .. "/.tasks.json",                                                                    -- Hidden in project root
    vim.fn.expand("~/.config/nvim/lazydo/tasks_" .. vim.fn.fnamemodify(project_root, ":t") .. ".json") -- Old nvim convention
  }

  -- Check each location
  for _, old_path in ipairs(old_locations) do
    if Utils.path_exists(old_path) then
      -- Define new location
      local new_dir = project_root .. "/.lazydo"
      pcall(Utils.ensure_dir, new_dir)

      local new_path = new_dir .. "/tasks.json"

      -- Don't overwrite existing files
      if Utils.path_exists(new_path) then
        vim.notify("Skipping migration: Target file already exists: " .. new_path, vim.log.levels.INFO)
        return false
      end

      -- Copy the file
      local lines = vim.fn.readfile(old_path)
      if lines and #lines > 0 then
        local write_ok = pcall(function()
          vim.fn.writefile(lines, new_path)
        end)

        if write_ok then
          vim.notify("Migrated tasks from " .. old_path .. " to " .. new_path, vim.log.levels.INFO)

          -- Optionally create a backup of the old file
          pcall(function()
            vim.fn.writefile(lines, old_path .. ".backup")
          end)

          return true
        end
      end
    end
  end

  return false
end

---Auto-detect project and switch storage mode if needed with improved directory handling
---@return boolean is_project_mode
function Storage.auto_detect_project()
  if not config then
    error("Storage not initialized. Call setup() first")
  end

  -- First check for any existing custom projects in the current directory
  local cwd = vim.fn.getcwd()
  local lazydo_dir = cwd .. "/.lazydo"

  -- If .lazydo directory exists, check for custom project folders
  if Utils.path_exists(lazydo_dir) then
    -- Get all subdirectories in .lazydo
    local ok, subdirs = pcall(vim.fn.glob, lazydo_dir .. "/*/", true, true)

    if ok and subdirs and #subdirs > 0 then
      -- We have custom projects, list them for selection
      local options = {}
      local projects = {}

      -- Add option for standard project storage
      table.insert(options, "Standard Project Storage (.lazydo/tasks.json)")
      table.insert(projects, { type = "project", path = cwd })

      -- Add all custom projects
      for _, subdir in ipairs(subdirs) do
        local project_name = vim.fn.fnamemodify(subdir, ":t")
        local custom_tasks_path = subdir .. "tasks.json"

        if Utils.path_exists(custom_tasks_path) then
          table.insert(options, "Custom Project: " .. project_name)
          table.insert(projects, {
            type = "custom",
            path = cwd,
            name = project_name
          })
        end
      end

      -- Add global option
      table.insert(options, "Global Storage (accessible from everywhere)")
      table.insert(projects, { type = "global" })

      -- If we have more than just the standard and global options, show the selection UI
      if #options > 2 then
        vim.ui.select(options, {
          prompt = "Detected custom projects in this directory. Select storage to use:",
          format_item = function(item) return item end
        }, function(choice, idx)
          if not choice or not idx then
            -- User cancelled, default to standard project
            cache.selected_storage = "project"
            config.storage.project.enabled = true
            cache.project_root = cwd
            return true, cwd
          end

          local selected = projects[idx]

          if selected.type == "global" then
            cache.selected_storage = "global"
            config.storage.project.enabled = false
            cache.project_root = nil
            vim.notify("Using global storage for LazyDo", vim.log.levels.INFO)
            return false, nil
          elseif selected.type == "project" then
            cache.selected_storage = "project"
            config.storage.project.enabled = true
            cache.project_root = cwd
            vim.notify("Using standard project storage at: " .. cwd, vim.log.levels.INFO)
            return true, cwd
          elseif selected.type == "custom" then
            cache.selected_storage = "custom"
            cache.custom_project_name = selected.name
            config.storage.project.enabled = true
            cache.project_root = cwd
            vim.notify("Using custom project storage: " .. selected.name, vim.log.levels.INFO)
            return true, cwd
          end
        end)

        -- If we showed the UI, return default while waiting for async selection
        return true, cwd
      end
    end
  end

  -- If no custom projects found, use standard detection
  local is_project, project_root = Storage.smart_project_detection(false)

  -- Update configuration based on detection
  config.storage.project.enabled = is_project
  if is_project and project_root then
    cache.project_root = project_root

    -- Try to migrate tasks from old locations
    local migrated = migrate_legacy_tasks(project_root)
    if migrated then
      vim.notify("Successfully migrated tasks to the new .lazydo directory structure", vim.log.levels.INFO)
    end

    -- Ensure the project storage directory exists
    if cache.custom_project_name then
      -- Create the .lazydo directory
      local lazydo_dir = cache.project_root .. "/.lazydo"
      pcall(Utils.ensure_dir, lazydo_dir)

      -- Create custom project directory
      local project_dir = lazydo_dir .. "/" .. cache.custom_project_name
      local dir_ok = pcall(Utils.ensure_dir, project_dir)

      if not dir_ok then
        vim.notify("Failed to create custom project directory: " .. project_dir, vim.log.levels.WARN)
      end
    else
      -- Create standard .lazydo directory in project root
      local lazydo_dir = cache.project_root .. "/.lazydo"
      local dir_ok = pcall(Utils.ensure_dir, lazydo_dir)

      if not dir_ok then
        vim.notify("Failed to create .lazydo directory in project root: " .. lazydo_dir, vim.log.levels.WARN)
      end
    end
  end

  return is_project
end

---Get the storage path with improved project handling
---@param force_mode? "project"|"global"|"custom" Optional mode to force path for
---@return string storage_path, boolean is_project
local function get_storage_path(force_mode)
  if not config then
    error("Storage not initialized. Call setup() first")
  end

  -- Handle custom project storage path
  if (force_mode == "custom" or cache.selected_storage == "custom") and cache.custom_project_name then
    local project_dir = string.format("%s/.lazydo/%s",
      cache.project_root or vim.fn.getcwd(),
      cache.custom_project_name)

    -- Ensure the project directory exists
    pcall(Utils.ensure_dir, project_dir)

    -- Return path to tasks.json within the project directory
    local project_path = project_dir .. "/tasks.json"
    return project_path, true
  end

  -- Check for project mode (use forced mode if provided)
  local use_project = force_mode == "project" or
      (force_mode ~= "global" and config.storage.project.enabled)

  if use_project and cache.project_root and cache.project_root ~= "Global" then
    -- Create .lazydo directory inside project root
    local lazydo_dir = cache.project_root .. "/.lazydo"
    pcall(Utils.ensure_dir, lazydo_dir)

    -- Store tasks.json inside the .lazydo directory, not outside
    local project_path = lazydo_dir .. "/tasks.json"
    return project_path, true
  end

  -- Fallback to global storage
  local global_path = vim.fn.expand(config.storage.global_path or Utils.get_data_dir() .. "/tasks.json")

  -- Ensure directory exists
  local dir = vim.fn.fnamemodify(global_path, ":h")
  pcall(Utils.ensure_dir, dir)

  return global_path, false
end

---@param timestamp? string
---@return string
local function get_backup_path(timestamp)
  local storage_path = get_storage_path()
  local dir = vim.fn.fnamemodify(storage_path, ":h")
  local base = vim.fn.fnamemodify(storage_path, ":t:r")
  return string.format("%s/%s.backup.%s.json", dir, base, timestamp or os.date("%Y%m%d%H%M%S"))
end

---Create backup of current storage
---@return nil
local function create_backup()
  if not config or not config.storage.auto_backup then
    return
  end

  local current_file = get_storage_path()
  if not Utils.path_exists(current_file) then
    return
  end

  local backup_file = get_backup_path()
  vim.fn.writefile(vim.fn.readfile(current_file), backup_file)

  -- Cleanup old backups
  local dir = vim.fn.fnamemodify(current_file, ":h")
  local pattern = vim.fn.fnamemodify(current_file, ":t:r") .. ".backup.*.json"
  local backups = vim.fn.glob(dir .. "/" .. pattern, true, true)
  table.sort(backups)

  -- Keep only the configured number of backups
  while #backups > config.storage.backup_count do
    vim.fn.delete(backups[1])
    table.remove(backups, 1)
  end
end

---Compress data using improved compression
---@param data string
---@return string
local function compress_data(data)
  -- More robust compression that preserves repeated patterns and whitespace
  local compressed = data:gsub("([%s%p])%1+", function(s)
    local count = #s
    if count > 3 then
      return string.format("##%d##%s", count, s:sub(1, 1))
    end
    return s
  end)

  -- Preserve JSON structure markers and common patterns
  compressed = compressed:gsub('([{}%[%]":])', function(marker)
    return string.format("##JSON##%s", marker)
  end)

  -- Compress common task patterns
  compressed = compressed:gsub('"priority":%s*"(%w+)"', function(p)
    return string.format('"p":"%s"', p:sub(1, 1))
  end)
  compressed = compressed:gsub('"status":%s*"(%w+)"', function(s)
    return string.format('"s":"%s"', s:sub(1, 1))
  end)

  return compressed
end

---Decompress data with improved safety
---@param data string
---@return string
local function decompress_data(data)
  -- First restore JSON structure markers
  local decompressed = data:gsub("##JSON##(.)", "%1")

  -- Then decompress repeated patterns
  decompressed = decompressed:gsub("##(%d+)##(.)", function(count, char)
    return string.rep(char, tonumber(count))
  end)

  return decompressed
end

---Basic encryption
---@param data string
---@return string
local function encrypt_data(data)
  local result = {}
  for i = 1, #data do
    local byte = data:byte(i)
    table.insert(result, string.char((byte + 7) % 256))
  end
  return table.concat(result)
end

---Basic decryption
---@param data string
---@return string
local function decrypt_data(data)
  local result = {}
  for i = 1, #data do
    local byte = data:byte(i)
    table.insert(result, string.char((byte - 7) % 256))
  end
  return table.concat(result)
end

---Toggle between project and global storage with improved handling and UI
---@param mode? "project"|"global"|"auto"|"custom" Optional mode to set directly
---@return boolean is_project_mode
function Storage.toggle_mode(mode)
  if not config then
    error("Storage not initialized. Call setup() first")
  end

  -- Auto-detect mode with UI prompt if requested
  if mode == "auto" then
    return Storage.auto_detect_project()
  end

  -- Handle explicit mode changes
  if mode == "global" then
    cache.selected_storage = "global"
    config.storage.project.enabled = false
    cache.project_root = nil
    cache.custom_project_name = nil
    vim.notify("Switched to global storage", vim.log.levels.INFO)
    return false
  elseif mode == "project" then
    -- Check for project markers
    local project_markers = find_project_markers()

    if #project_markers > 0 then
      -- Use the highest priority project
      local project = project_markers[1]
      cache.selected_storage = "project"
      config.storage.project.enabled = true
      cache.project_root = project.path
      cache.custom_project_name = nil

      -- Create .lazydo directory within the project root
      local lazydo_dir = project.path .. "/.lazydo"
      local dir_ok = pcall(Utils.ensure_dir, lazydo_dir)
      if not dir_ok then
        vim.notify("Failed to create .lazydo directory in project", vim.log.levels.WARN)
      end

      vim.notify("Switched to project storage: " .. project.path, vim.log.levels.INFO)
      return true
    else
      -- No project markers found, prompt for custom project
      vim.ui.input({
        prompt = "No project markers found. Enter a custom project name or leave empty for global storage: ",
      }, function(project_name)
        if not project_name or project_name == "" then
          cache.selected_storage = "global"
          config.storage.project.enabled = false
          cache.custom_project_name = nil
          vim.notify("Using global storage for LazyDo", vim.log.levels.INFO)
          return false
        end

        -- Create custom project
        cache.selected_storage = "custom"
        cache.custom_project_name = project_name
        config.storage.project.enabled = true
        cache.project_root = vim.fn.getcwd()

        -- Create project directory structure
        local marker_path = cache.project_root .. "/.lazydo"
        pcall(function() vim.fn.mkdir(marker_path, "p") end)

        local project_dir = marker_path .. "/" .. project_name
        pcall(function() vim.fn.mkdir(project_dir, "p") end)

        vim.notify("Created new project storage: " .. project_name, vim.log.levels.INFO)
        return true
      end)
    end
  elseif mode == "custom" then
    -- First check if there are existing custom projects
    local cwd = vim.fn.getcwd()
    local lazydo_dir = cwd .. "/.lazydo"

    if Utils.path_exists(lazydo_dir) then
      -- Check for subdirectories which might be custom projects
      local ok, subdirs = pcall(vim.fn.glob, lazydo_dir .. "/*/", true, true)

      if ok and subdirs and #subdirs > 0 then
        -- Create list of existing projects
        local options = {}
        local projects = {}

        for _, subdir in ipairs(subdirs) do
          local project_name = vim.fn.fnamemodify(subdir, ":t")
          local custom_tasks_path = subdir .. "tasks.json"

          -- Add to options regardless of whether tasks.json exists
          table.insert(options, project_name)
          table.insert(projects, project_name)
        end

        -- Add option for new project
        table.insert(options, "Create New Custom Project")

        -- Show selection UI
        vim.ui.select(options, {
          prompt = "Select or create a custom project:",
          format_item = function(item) return item end
        }, function(choice, idx)
          if not choice then
            -- User cancelled, keep current mode
            vim.notify("Custom project selection cancelled", vim.log.levels.INFO)
            return config.storage.project.enabled
          end

          if choice == "Create New Custom Project" then
            -- Prompt for new project name
            vim.ui.input({
              prompt = "Enter new custom project name: ",
            }, function(project_name)
              if not project_name or project_name == "" then
                vim.notify("Invalid project name, keeping current storage mode", vim.log.levels.WARN)
                return config.storage.project.enabled
              end

              -- Create custom project
              cache.selected_storage = "custom"
              cache.custom_project_name = project_name
              config.storage.project.enabled = true
              cache.project_root = cwd

              -- Create directories
              local marker_path = cache.project_root .. "/.lazydo"
              pcall(function() vim.fn.mkdir(marker_path, "p") end)

              local project_dir = marker_path .. "/" .. project_name
              pcall(function() vim.fn.mkdir(project_dir, "p") end)

              vim.notify("Created new custom project storage: " .. project_name, vim.log.levels.INFO)
              return true
            end)
          else
            -- User selected an existing project
            local project_name = projects[idx]

            -- Check if the project directory exists
            local project_dir = lazydo_dir .. "/" .. project_name
            if not Utils.path_exists(project_dir) then
              pcall(function() vim.fn.mkdir(project_dir, "p") end)
            end

            -- Set the custom project
            cache.selected_storage = "custom"
            cache.custom_project_name = project_name
            config.storage.project.enabled = true
            cache.project_root = cwd

            vim.notify("Switched to custom project: " .. project_name, vim.log.levels.INFO)
            return true
          end
        end)
      else
        -- No existing custom projects, prompt for new one
        vim.ui.input({
          prompt = "Enter custom project name: ",
        }, function(project_name)
          if not project_name or project_name == "" then
            vim.notify("Invalid project name, keeping current storage mode", vim.log.levels.WARN)
            return config.storage.project.enabled
          end

          -- Create custom project
          cache.selected_storage = "custom"
          cache.custom_project_name = project_name
          config.storage.project.enabled = true
          cache.project_root = cwd

          -- Create directories
          local marker_path = cache.project_root .. "/.lazydo"
          pcall(function() vim.fn.mkdir(marker_path, "p") end)

          local project_dir = marker_path .. "/" .. project_name
          pcall(function() vim.fn.mkdir(project_dir, "p") end)

          vim.notify("Created new custom project storage: " .. project_name, vim.log.levels.INFO)
          return true
        end)
      end
    else
      -- No .lazydo directory, prompt for new custom project
      vim.ui.input({
        prompt = "Enter custom project name: ",
      }, function(project_name)
        if not project_name or project_name == "" then
          vim.notify("Invalid project name, keeping current storage mode", vim.log.levels.WARN)
          return config.storage.project.enabled
        end

        -- Create custom project
        cache.selected_storage = "custom"
        cache.custom_project_name = project_name
        config.storage.project.enabled = true
        cache.project_root = cwd

        -- Create directories
        local marker_path = cache.project_root .. "/.lazydo"
        pcall(function() vim.fn.mkdir(marker_path, "p") end)

        local project_dir = marker_path .. "/" .. project_name
        pcall(function() vim.fn.mkdir(project_dir, "p") end)

        vim.notify("Created new custom project storage: " .. project_name, vim.log.levels.INFO)
        return true
      end)
    end
  else
    -- Toggle between current modes
    if cache.selected_storage == "custom" then
      -- When toggling from custom, go to global
      cache.selected_storage = "global"
      config.storage.project.enabled = false
      cache.custom_project_name = nil
      vim.notify("Switched to global storage from custom project", vim.log.levels.INFO)
      return false
    elseif config.storage.project.enabled then
      -- Toggle from project to global
      cache.selected_storage = "global"
      config.storage.project.enabled = false
      cache.custom_project_name = nil
      vim.notify("Switched to global storage", vim.log.levels.INFO)
      return false
    else
      -- Run smart detection to determine the project
      return Storage.auto_detect_project()
    end
  end

  return config.storage.project.enabled
end

---Get current storage status
---@return table status Storage status information
function Storage.get_status()
  if not config then
    error("Storage not initialized. Call setup() first")
  end

  local storage_path, is_project = get_storage_path()
  local lazydo_dir = is_project and (cache.project_root .. "/.lazydo") or nil

  return {
    mode = is_project and "project" or "global",
    current_path = storage_path,
    global_path = config.storage.global_path,
    project_enabled = config.storage.project.enabled,
    use_git_root = config.storage.project.use_git_root,
    auto_detect = config.storage.project.auto_detect,
    compression = config.storage.compression,
    encryption = config.storage.encryption,
    selected_storage = cache.selected_storage,
    custom_project_name = cache.custom_project_name,
    project_root = cache.project_root,
    lazydo_directory = lazydo_dir,
    file_exists = Utils.path_exists(storage_path)
  }
end

---Load tasks from storage with improved handling
---@param force_mode? "project"|"global"|"custom" Optional mode to force
---@return table,boolean Tasks from storage and success flag
function Storage.load(force_mode)
  if not config then
    error("Storage not initialized. Call setup() first")
  end

  -- Check if we have a custom project selected in cache
  if not force_mode and cache.selected_storage == "custom" and cache.custom_project_name then
    force_mode = "custom"
  end

  -- Get storage path for the specified mode
  local storage_path, is_project = get_storage_path(force_mode)

  -- Check if path is for custom project
  local is_custom_project = (force_mode == "custom" or cache.selected_storage == "custom") and cache.custom_project_name

  -- Check if file exists
  if not Utils.path_exists(storage_path) then
    -- Create directory if it doesn't exist
    local dir = vim.fn.fnamemodify(storage_path, ":h")
    local dir_ok = pcall(Utils.ensure_dir, dir)
    if not dir_ok then
      vim.notify("Failed to create storage directory: " .. dir, vim.log.levels.ERROR)
      return {}, false
    end

    -- If we're looking for a custom project but the file doesn't exist yet, return empty tasks
    if is_custom_project then
      vim.notify("Creating new task list for custom project: " .. cache.custom_project_name, vim.log.levels.INFO)
      return {}, true
    end

    -- Return empty task list - file doesn't exist yet
    return {}, true
  end

  -- Read file
  local lines, read_err = vim.fn.readfile(storage_path)
  if not lines or #lines == 0 then
    if read_err then
      vim.notify("Error reading storage file: " .. read_err, vim.log.levels.ERROR)
    end
    return {}, false
  end

  local data = table.concat(lines)

  -- Decrypt if enabled
  if config.storage.encryption then
    local decrypt_ok, decrypted = pcall(decrypt_data, data)
    if decrypt_ok then
      data = decrypted
    else
      vim.notify("Error decrypting data, using original data", vim.log.levels.WARN)
    end
  end

  -- Decompress if enabled
  if config.storage.compression then
    local decomp_ok, decompressed = pcall(decompress_data, data)
    if decomp_ok then
      data = decompressed
    else
      vim.notify("Error decompressing data, using original data", vim.log.levels.WARN)
    end
  end

  -- Parse JSON
  local success, parsed = pcall(vim.fn.json_decode, data)
  if not success or not parsed then
    -- Try to load from backup
    vim.notify("Error loading tasks, trying backup", vim.log.levels.WARN)
    local backup_ok, backup_tasks = pcall(Storage.load_latest_backup)
    if backup_ok and backup_tasks then
      return backup_tasks, true
    else
      vim.notify("Failed to load from backup, using empty task list", vim.log.levels.ERROR)
      return {}, false
    end
  end

  -- Update cache with loaded data
  cache.data = parsed

  -- Return tasks and success flag
  return parsed, true
end

---Save tasks to storage with improved reliability
---@param tasks table Tasks to save
---@param force_mode? "project"|"global"|"custom" Optional mode to force
---@return boolean success Whether the save was successful
function Storage.save(tasks, force_mode)
  if not config then
    error("Storage not initialized. Call setup() first")
  end

  -- Check if custom project is selected but not forced mode
  if not force_mode and cache.selected_storage == "custom" and cache.custom_project_name then
    force_mode = "custom"
  end

  -- Create backup before saving if configured
  if config.storage.auto_backup then
    local backup_ok = pcall(create_backup)
    if not backup_ok then
      vim.notify("Failed to create backup before saving", vim.log.levels.WARN)
    end
  end

  -- Get storage path for the specified mode
  local storage_path, is_project = get_storage_path(force_mode)

  -- Ensure the directory exists
  local dir = vim.fn.fnamemodify(storage_path, ":h")
  local dir_ok = pcall(Utils.ensure_dir, dir)
  if not dir_ok then
    vim.notify("Failed to create storage directory: " .. dir, vim.log.levels.ERROR)
    return false
  end

  -- Convert tasks to JSON
  local json_ok, json_data = pcall(vim.fn.json_encode, tasks)
  if not json_ok or not json_data then
    vim.notify("Error encoding tasks to JSON", vim.log.levels.ERROR)
    return false
  end

  -- Apply compression if enabled
  if config.storage.compression then
    local comp_ok, compressed = pcall(compress_data, json_data)
    if comp_ok then
      json_data = compressed
    else
      vim.notify("Error compressing data", vim.log.levels.WARN)
    end
  end

  -- Apply encryption if enabled
  if config.storage.encryption then
    local encrypt_ok, encrypted = pcall(encrypt_data, json_data)
    if encrypt_ok then
      json_data = encrypted
    else
      vim.notify("Error encrypting data", vim.log.levels.WARN)
    end
  end

  -- Write to temporary file first
  local temp_file = storage_path .. ".tmp"
  local write_ok, write_err = pcall(function()
    return vim.fn.writefile({ json_data }, temp_file)
  end)

  if not write_ok or write_err ~= 0 then
    vim.notify("Error writing to temporary file", vim.log.levels.ERROR)
    return false
  end

  -- Rename temporary file to final file
  local rename_ok = pcall(function()
    os.rename(temp_file, storage_path)
  end)

  if not rename_ok then
    vim.notify("Error during file rename operation", vim.log.levels.ERROR)
    return false
  end

  -- Update cache with saved data
  cache.data = tasks
  cache.last_save = os.time()
  cache.is_dirty = false

  local mode_str = is_project and "project" or "global"
  if cache.selected_storage == "custom" and cache.custom_project_name then
    mode_str = "custom project '" .. cache.custom_project_name .. "'"
  end

  -- vim.notify("Tasks saved to " .. mode_str .. " storage", vim.log.levels.INFO)
  return true
end

---Save tasks immediately without debouncing
---@param tasks table Tasks to save
---@param force_mode? "project"|"global"|"custom" Optional mode to force
---@return boolean success Whether the save was successful
function Storage.save_immediate(tasks, force_mode)
  if not config then
    error("Storage not initialized. Call setup() first")
  end

  -- Check if custom project is selected but not forced mode
  if not force_mode and cache.selected_storage == "custom" and cache.custom_project_name then
    force_mode = "custom"
  end

  -- Get storage path for the specified mode
  local storage_path, is_project = get_storage_path(force_mode)

  -- Ensure the directory exists
  local dir = vim.fn.fnamemodify(storage_path, ":h")
  local dir_ok = pcall(Utils.ensure_dir, dir)
  if not dir_ok then
    vim.notify("Failed to create storage directory: " .. dir, vim.log.levels.ERROR)
    return false
  end

  -- Convert tasks to JSON
  local json_ok, json_data = pcall(vim.fn.json_encode, tasks)
  if not json_ok or not json_data then
    vim.notify("Error encoding tasks to JSON", vim.log.levels.ERROR)
    return false
  end

  -- Apply compression if enabled
  if config.storage.compression then
    local comp_ok, compressed = pcall(compress_data, json_data)
    if comp_ok then
      json_data = compressed
    else
      vim.notify("Error compressing data", vim.log.levels.WARN)
    end
  end

  -- Apply encryption if enabled
  if config.storage.encryption then
    local encrypt_ok, encrypted = pcall(encrypt_data, json_data)
    if encrypt_ok then
      json_data = encrypted
    else
      vim.notify("Error encrypting data", vim.log.levels.WARN)
    end
  end

  -- Write to file directly
  local write_ok, write_err = pcall(function()
    return vim.fn.writefile({ json_data }, storage_path)
  end)

  if not write_ok or write_err ~= 0 then
    vim.notify("Error writing to file: " .. storage_path, vim.log.levels.ERROR)
    return false
  end

  -- Update cache with saved data
  cache.data = tasks
  cache.last_save = os.time()
  cache.is_dirty = false

  local mode_str = is_project and "project" or "global"
  if cache.selected_storage == "custom" and cache.custom_project_name then
    mode_str = "custom project '" .. cache.custom_project_name .. "'"
  end

  return true
end

---Load the latest backup
---@return table,boolean tasks and success flag
function Storage.load_latest_backup()
  if not config then
    error("Storage not initialized. Call setup() first")
  end

  local storage_path = get_storage_path()
  local dir = vim.fn.fnamemodify(storage_path, ":h")
  local pattern = vim.fn.fnamemodify(storage_path, ":t:r") .. ".backup.*.json"
  local backups = vim.fn.glob(dir .. "/" .. pattern, true, true)

  if #backups == 0 then
    vim.notify("No backup files found", vim.log.levels.WARN)
    return {}, false
  end

  -- Sort backups by date (newest first)
  table.sort(backups, function(a, b) return a > b end)

  -- Try to load from newest backup
  local lines = vim.fn.readfile(backups[1])
  if not lines or #lines == 0 then
    vim.notify("Backup file is empty", vim.log.levels.WARN)
    return {}, false
  end

  local data = table.concat(lines)

  -- Decrypt if enabled
  if config.storage.encryption then
    local decrypt_ok, decrypted = pcall(decrypt_data, data)
    if decrypt_ok then
      data = decrypted
    else
      vim.notify("Error decrypting backup data", vim.log.levels.WARN)
    end
  end

  -- Decompress if enabled
  if config.storage.compression then
    local decomp_ok, decompressed = pcall(decompress_data, data)
    if decomp_ok then
      data = decompressed
    else
      vim.notify("Error decompressing backup data", vim.log.levels.WARN)
    end
  end

  -- Parse JSON
  local success, parsed = pcall(vim.fn.json_decode, data)
  if not success or not parsed then
    vim.notify("Error parsing backup data as JSON", vim.log.levels.ERROR)
    return {}, false
  end

  vim.notify("Successfully loaded from backup: " .. backups[1], vim.log.levels.INFO)
  return parsed, true
end

---Restore from backup
---@param backup_date? string Optional backup date in format YYYYMMDDHHMMSS
---@return boolean success
function Storage.restore_backup(backup_date)
  if not config then
    error("Storage not initialized. Call setup() first")
  end

  local backup_file
  if backup_date then
    backup_file = get_backup_path(backup_date)
    if not Utils.path_exists(backup_file) then
      vim.notify("Backup not found: " .. backup_file, vim.log.levels.ERROR)
      return false
    end
  else
    -- Find most recent backup
    local data_dir = Utils.get_data_dir()
    local backups = vim.fn.glob(data_dir .. "/tasks.backup.*.json", true, true)
    table.sort(backups)
    backup_file = backups[#backups]
    if not backup_file then
      vim.notify("No backups found", vim.log.levels.ERROR)
      return false
    end
  end

  local current_file = get_storage_path()
  local success = pcall(vim.fn.writefile, vim.fn.readfile(backup_file), current_file)
  if success then
    vim.notify("Successfully restored from backup", vim.log.levels.INFO)
    return true
  else
    vim.notify("Failed to restore from backup", vim.log.levels.ERROR)
    return false
  end
end

---Get project information
---@return table
function Storage.get_project_info()
  if not config then
    error("Storage not initialized. Call setup() first")
  end

  local root = get_project_root()
  local is_global = root == "Global"

  return {
    enabled = config.storage.project.enabled,
    root = is_global and nil or root,
    storage_path = get_storage_path(),
    is_project_based = not is_global and config.storage.project.enabled,
  }
end

-- Create debounced save function
Storage.save_debounced = Utils.debounce(Storage.save, 1000)

---Save tasks immediately without debouncing
---@param tasks table Tasks to save
---@param force_mode? "project"|"global" Optional mode to force saving to
---@return boolean success
-- function Storage.save_immediate(tasks, force_mode)
--   -- Call the regular save function but bypass the debounce mechanism
--   local success = Storage.save(tasks, force_mode)
--   return success
-- end

---Set custom project directly
---@param project_name string The name of the custom project
---@return boolean success Whether the operation was successful
function Storage.set_custom_project(project_name)
  if not config then
    error("Storage not initialized. Call setup() first")
  end

  if not project_name or project_name == "" then
    vim.notify("Invalid project name", vim.log.levels.ERROR)
    return false
  end

  -- Set custom project mode
  cache.selected_storage = "custom"
  cache.custom_project_name = project_name
  config.storage.project.enabled = true

  -- If project root not set, use current directory
  if not cache.project_root then
    cache.project_root = vim.fn.getcwd()
  end

  -- Make sure custom project directory exists
  local project_dir = string.format("%s/.lazydo/%s",
    cache.project_root,
    project_name)

  local dir_ok = pcall(Utils.ensure_dir, project_dir)
  if not dir_ok then
    vim.notify("Failed to create custom project directory: " .. project_dir, vim.log.levels.WARN)
    return false
  end

  return true
end

return Storage
