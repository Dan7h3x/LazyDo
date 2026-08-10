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
  selected_storage = nil,    -- Track user selected storage
  custom_project_name = nil, -- Store custom project name
  custom_projects = {},      -- Cache available custom projects
  last_scan = nil            -- Track last scan time
}

-- Metadata file for persisting storage preferences
local METADATA_FILENAME = "storage_metadata.json"

---Save metadata about storage preferences
---@return boolean success Whether the save was successful
local function save_metadata()
  if not config then
    return false
  end

  local metadata = {
    selected_storage = cache.selected_storage,
    custom_project_name = cache.custom_project_name,
    project_root = cache.project_root,
    last_used = os.time()
  }

  -- Always save in global directory
  local global_dir = vim.fn.fnamemodify(
    vim.fn.expand(config.storage.global_path or Utils.get_data_dir() .. "/tasks.json"),
    ":h"
  )
  local metadata_path = global_dir .. "/" .. METADATA_FILENAME

  -- Ensure directory exists
  pcall(Utils.ensure_dir, global_dir)

  -- Encode and save
  local json_ok, json_data = pcall(vim.fn.json_encode, metadata)
  if not json_ok or not json_data then
    return false
  end

  local write_ok = pcall(function()
    vim.fn.writefile({ json_data }, metadata_path)
  end)

  return write_ok
end

---Load metadata about storage preferences
---@return boolean success Whether the load was successful
local function load_metadata()
  if not config then
    return false
  end

  -- Determine metadata location
  local global_dir = vim.fn.fnamemodify(
    vim.fn.expand(config.storage.global_path or Utils.get_data_dir() .. "/tasks.json"),
    ":h"
  )
  local metadata_path = global_dir .. "/" .. METADATA_FILENAME

  -- Check if file exists
  if not Utils.path_exists(metadata_path) then
    return false
  end

  -- Load and parse
  local lines = vim.fn.readfile(metadata_path)
  if not lines or #lines == 0 then
    return false
  end

  local success, metadata = pcall(vim.fn.json_decode, lines[1])
  if not success or not metadata then
    return false
  end

  -- Apply metadata to cache
  cache.selected_storage = metadata.selected_storage
  cache.custom_project_name = metadata.custom_project_name
  cache.project_root = metadata.project_root

  -- Verify the custom project still exists
  if cache.selected_storage == "custom" and cache.custom_project_name then
    local tasks_path = cache.project_root .. "/tasks.json"
    if not Utils.path_exists(tasks_path) then
      -- Custom project no longer exists
      cache.selected_storage = "global"
      cache.custom_project_name = nil
      return false
    end
  end

  return true
end

--- Setup storage with configuration
---@param user_config LazyDoConfig
---@return nil
function Storage.setup(user_config)
  if not user_config then
    error("Storage configuration is required")
  end

  -- Set configuration
  config = user_config

  -- Initialize cache with defaults
  cache = {
    data = nil,
    project_root = nil,
    last_save = nil,
    is_dirty = false,
    selected_storage = nil,
    custom_project_name = nil,
    custom_projects = {},
    last_scan = nil
  }

  -- Load previous storage metadata if enabled
  if user_config.storage.persist_selection ~= false then
    local loaded = load_metadata()

    -- If loaded successfully, set project config based on metadata
    if loaded and cache.selected_storage then
      if cache.selected_storage == "global" then
        config.storage.project.enabled = false
      else
        config.storage.project.enabled = true
      end
    end
  end

  -- Auto-save when leaving vim if enabled
  if user_config.storage.auto_save_on_exit ~= false then
    -- Create an autocommand group for LazyDo
    vim.api.nvim_create_augroup("LazyDoStorage", { clear = true })

    -- Add autocommand to save storage on VimLeave
    vim.api.nvim_create_autocmd("VimLeave", {
      group = "LazyDoStorage",
      callback = function()
        -- Save any dirty data before exiting
        if cache.is_dirty and cache.data then
          Storage.save_immediate(cache.data)
        end
        -- Always save metadata
        save_metadata()
      end,
    })
  end

  -- Auto-detect projects on setup if enabled
  if user_config.storage.project.auto_detect then
    vim.defer_fn(function()
      Storage.auto_detect_project()
    end, 0)
  end
end

---Get storage path with reliable error handling
---@param force_mode? "project"|"global"|"custom" Optional mode to force path for
---@return string storage_path, boolean is_project
function Storage:get_storage_path(force_mode)
  if not config then
    error("Storage not initialized. Call setup() first")
  end

  -- Handle custom project storage path
  if (force_mode == "custom" or cache.selected_storage == "custom") and cache.custom_project_name then
    -- For custom projects, use tasks.json in the project root directly
    local project_path = cache.project_root .. "/tasks.json"
    return vim.fn.expand(project_path), true
  end

  -- Check for project mode
  local use_project = force_mode == "project" or
      (force_mode ~= "global" and config.storage.project.enabled)

  if use_project and cache.project_root and cache.project_root ~= "Global" then
    -- Create .lazydo directory inside project root
    local lazydo_dir = cache.project_root .. "/.lazydo"
    local dir_ok = pcall(Utils.ensure_dir, lazydo_dir)
    if not dir_ok then
      vim.notify("Failed to create .lazydo directory: " .. lazydo_dir, vim.log.levels.WARN)
      -- Fallback to global storage
      return Storage:get_storage_path("global")
    end

    -- Store tasks.json inside the .lazydo directory
    local project_path = lazydo_dir .. "/tasks.json"
    return vim.fn.expand(project_path), true
  end

  -- Fallback to global storage
  local global_path = vim.fn.expand(config.storage.global_path or Utils.get_data_dir() .. "/tasks.json")

  -- Ensure directory exists
  local dir = vim.fn.fnamemodify(global_path, ":h")
  local dir_ok = pcall(Utils.ensure_dir, dir)
  if not dir_ok then
    -- If we can't create the directory, fallback to current directory
    vim.notify("Failed to create global storage directory, falling back to current directory", vim.log.levels.WARN)
    return vim.fn.getcwd() .. "/tasks.json", false
  end

  return global_path, false
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
  local storage_path, is_project = Storage:get_storage_path(force_mode)

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

    -- If we're looking for a custom project but the file doesn't exist yet, create empty file
    if is_custom_project then
      local write_ok = pcall(function()
        vim.fn.writefile({ "[]" }, storage_path)
      end)

      if write_ok then
        vim.notify("Created new task list for custom project: " .. cache.custom_project_name, vim.log.levels.INFO)
        return {}, true
      else
        vim.notify("Failed to create tasks file for custom project", vim.log.levels.ERROR)
        return {}, false
      end
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

  -- Process data (decrypt/decompress if enabled)
  if config.storage.encryption then
    local decrypt_ok, decrypted = pcall(Storage.decrypt_data, data)
    if decrypt_ok then data = decrypted end
  end

  if config.storage.compression then
    local decomp_ok, decompressed = pcall(Storage.decompress_data, data)
    if decomp_ok then data = decompressed end
  end

  -- Parse JSON
  local success, parsed = pcall(vim.fn.json_decode, data)
  if not success or not parsed then
    vim.notify("Error parsing tasks data, using empty task list", vim.log.levels.ERROR)
    return {}, false
  end

  -- Update cache with loaded data
  cache.data = parsed
  cache.is_dirty = false

  return parsed, true
end

---Save tasks to storage with improved reliability
---@param tasks table Tasks to save
---@param force_mode? "project"|"global"|"custom" Optional mode to force
---@return boolean success Whether the save was successful
function Storage.save_immediate(tasks, force_mode)
  if not config then
    error("Storage not initialized. Call setup() first")
  end

  -- Use custom project if selected but not forced
  if not force_mode and cache.selected_storage == "custom" and cache.custom_project_name then
    force_mode = "custom"
  end

  -- Get storage path
  local storage_path, is_project = Storage:get_storage_path(force_mode)

  -- Ensure directory exists
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

  -- Process data (compress/encrypt if enabled)
  if config.storage.compression then
    local comp_ok, compressed = pcall(Storage.compress_data, json_data)
    if comp_ok then json_data = compressed end
  end

  if config.storage.encryption then
    local encrypt_ok, encrypted = pcall(Storage.encrypt_data, json_data)
    if encrypt_ok then json_data = encrypted end
  end

  -- Write to file directly with atomic file write pattern
  local temp_file = storage_path .. ".tmp"
  local write_ok, write_err = pcall(function()
    return vim.fn.writefile({ json_data }, temp_file)
  end)

  if not write_ok or write_err ~= 0 then
    vim.notify("Error writing to temporary file", vim.log.levels.ERROR)
    return false
  end

  -- Atomic rename for safer file writes
  local rename_ok = pcall(function()
    os.rename(temp_file, storage_path)
  end)

  if not rename_ok then
    vim.notify("Error during file rename operation", vim.log.levels.ERROR)
    return false
  end

  -- Update cache
  cache.data = tasks
  cache.last_save = os.time()
  cache.is_dirty = false

  return true
end

-- Create debounced save function
Storage.save = function(tasks, force_mode)
  if config and config.storage.auto_backup then
    pcall(function() Storage:create_backup() end)
  end
  return Storage.save_immediate(tasks, force_mode)
end

-- Create debounced version of save
Storage.save_debounced = Utils.debounce(Storage.save, 1000)

---Set custom project directly with improved validation
---@param project_name string The name of the custom project
---@param base_dir? string Optional base directory (defaults to cwd)
---@return boolean success Whether the operation was successful
function Storage.set_custom_project(project_name, base_dir)
  if not config then
    error("Storage not initialized. Call setup() first")
  end

  if not project_name or project_name == "" then
    vim.notify("Invalid project name", vim.log.levels.ERROR)
    return false
  end

  -- Set project mode
  cache.selected_storage = "custom"
  cache.custom_project_name = project_name
  config.storage.project.enabled = true

  -- Use provided base_dir or current directory if project root not set
  base_dir = base_dir or vim.fn.getcwd()
  cache.project_root = base_dir

  -- Create tasks.json directly in the project directory
  local tasks_path = string.format("%s/tasks.json", cache.project_root)
  
  -- Create empty tasks.json if needed
  if not Utils.path_exists(tasks_path) then
    local write_ok = pcall(function()
      vim.fn.writefile({ "[]" }, tasks_path)
    end)
    if not write_ok then
      vim.notify("Failed to create tasks.json for custom project", vim.log.levels.WARN)
      return false
    end
  end

  -- Save metadata for next session
  save_metadata()
  vim.notify("Now using custom project: " .. project_name, vim.log.levels.INFO)

  return true
end

---Toggle between project and global storage with improved handling
---@param mode? "project"|"global"|"auto"|"custom" Optional mode to set directly
---@return boolean is_project_mode
function Storage.toggle_mode(mode)
  if not config then
    error("Storage not initialized. Call setup() first")
  end

  -- Auto-detect mode if requested
  if mode == "auto" then
    -- Collect all available storage options
    local options = {}
    local storage_info = {}

    -- Add global option
    table.insert(options, "Global Storage")
    table.insert(storage_info, { type = "global" })

    -- Add project options
    local project_markers = Storage:find_project_markers()
    for _, project in ipairs(project_markers) do
      local display_name = "Project: " .. vim.fn.fnamemodify(project.path, ":~:.")
      table.insert(options, display_name)
      table.insert(storage_info, {
        type = "project",
        path = project.path,
        name = project.name
      })
    end

    -- Add custom project options
    local custom_projects = Storage.get_custom_projects(true, true)
    
    -- Filter and prioritize projects in current directory
    local filtered_projects = Storage:filter_and_sort_projects(custom_projects, true)
    
    -- Flag to highlight if we have custom projects in current directory
    local has_cwd_projects = false
    local cwd = vim.fn.getcwd()
    
    for _, project in ipairs(filtered_projects) do
      -- Determine display format based on location
      local location_prefix = ""
      if project.base_dir == cwd then
        location_prefix = "📍 " -- Use an emoji marker for current directory projects
        has_cwd_projects = true
      else
        location_prefix = "   " -- Indent other projects for visual hierarchy
      end
      
      local display_name = location_prefix .. "Custom Project: [" .. project.name .. "]"
      if project.base_dir ~= cwd then
        display_name = display_name .. " (" .. vim.fn.fnamemodify(project.base_dir, ":~:.") .. ")"
      end
      
      table.insert(options, display_name)
      table.insert(storage_info, {
        type = "custom",
        name = project.name,
        path = project.base_dir
      })
    end

    -- Add option to create new custom project
    table.insert(options, "Create New Project in Current Directory")
    table.insert(storage_info, { type = "new_custom_cwd" })

    -- Add option for new project with custom location
    table.insert(options, "Create New Project in Custom Location")
    table.insert(storage_info, { type = "new_custom_location" })

    -- Show selection UI
    vim.ui.select(options, {
      prompt = "Select storage mode:",
      format_item = function(item)
        return item
      end,
    }, function(choice, idx)
      if not choice then return config.storage.project.enabled end

      -- Process selection
      local selected = storage_info[idx]

      if selected.type == "global" then
        -- Switch to global storage
        cache.selected_storage = "global"
        config.storage.project.enabled = false
        cache.custom_project_name = nil
        save_metadata()
        vim.notify("Switched to global storage", vim.log.levels.INFO)
        return false
      elseif selected.type == "project" then
        -- Switch to project storage
        cache.selected_storage = "project"
        config.storage.project.enabled = true
        cache.project_root = selected.path
        cache.custom_project_name = nil

        -- Create .lazydo directory if needed
        local lazydo_dir = selected.path .. "/.lazydo"
        pcall(Utils.ensure_dir, lazydo_dir)

        save_metadata()
        vim.notify("Switched to project storage: " .. selected.path, vim.log.levels.INFO)
        return true
      elseif selected.type == "custom" then
        -- Switch to custom project
        cache.selected_storage = "custom"
        cache.custom_project_name = selected.name
        cache.project_root = selected.path
        config.storage.project.enabled = true
        save_metadata()
        vim.notify("Switched to custom project: " .. selected.name, vim.log.levels.INFO)
        -- Force reload of tasks
        Storage.load("custom")
        return true
      elseif selected.type == "new_custom_cwd" then
        -- Create new custom project in current directory
        vim.ui.input({
          prompt = "Enter new custom project name: ",
        }, function(project_name)
          if not project_name or project_name == "" then
            vim.notify("Invalid project name", vim.log.levels.WARN)
            return false
          end

          return Storage.set_custom_project(project_name)
        end)
        return true
      elseif selected.type == "new_custom_location" then
        -- Create project with custom location
        vim.ui.input({
          prompt = "Enter new custom project name: ",
        }, function(project_name)
          if not project_name or project_name == "" then
            vim.notify("Invalid project name", vim.log.levels.WARN)
            return false
          end

          -- Allow selecting a different base directory
          vim.ui.input({
            prompt = "Enter base directory (leave empty for current directory): ",
            default = vim.fn.getcwd(),
          }, function(base_dir)
            if not base_dir or base_dir == "" then
              base_dir = vim.fn.getcwd()
            end

            -- Expand the path to make sure it's valid
            base_dir = vim.fn.expand(base_dir)

            -- Verify directory exists
            if vim.fn.isdirectory(base_dir) ~= 1 then
              vim.notify("Invalid directory: " .. base_dir, vim.log.levels.WARN)
              return false
            end

            return Storage.set_custom_project(project_name, base_dir)
          end)
        end)
        return true
      end
    end)

    return config.storage.project.enabled
  end

  -- Handle global mode
  if mode == "global" then
    cache.selected_storage = "global"
    config.storage.project.enabled = false
    cache.custom_project_name = nil
    save_metadata()
    vim.notify("Switched to global storage", vim.log.levels.INFO)
    return false
  end

  -- Handle project mode
  if mode == "project" then
    -- Find project markers
    local project_markers = Storage:find_project_markers()

    if #project_markers > 0 then
      -- Use the highest priority project
      local project = project_markers[1]
      cache.selected_storage = "project"
      config.storage.project.enabled = true
      cache.project_root = project.path
      cache.custom_project_name = nil

      -- Create .lazydo directory
      local lazydo_dir = project.path .. "/.lazydo"
      pcall(Utils.ensure_dir, lazydo_dir)

      save_metadata()
      vim.notify("Switched to project storage: " .. project.path, vim.log.levels.INFO)
      return true
    else
      -- No project markers found - ask user if they want to create a project
      vim.ui.select({
        "Create project in current directory",
        "Create custom project",
        "Use global storage"
      }, {
        prompt = "No project markers found. What would you like to do?",
      }, function(choice)
        if not choice then
          return false
        end

        if choice == "Create project in current directory" then
          -- Create .lazydo directory in current directory
          local current_dir = vim.fn.getcwd()
          local lazydo_dir = current_dir .. "/.lazydo"
          local dir_ok = pcall(Utils.ensure_dir, lazydo_dir)

          if dir_ok then
            cache.selected_storage = "project"
            config.storage.project.enabled = true
            cache.project_root = current_dir
            cache.custom_project_name = nil
            save_metadata()
            vim.notify("Created project in current directory: " .. current_dir, vim.log.levels.INFO)
            return true
          else
            vim.notify("Failed to create project directory", vim.log.levels.ERROR)
            return false
          end
        elseif choice == "Create custom project" then
          -- Prompt for custom project name
          vim.ui.input({
            prompt = "Enter custom project name: ",
          }, function(project_name)
            if not project_name or project_name == "" then
              vim.notify("Invalid project name", vim.log.levels.WARN)
              return false
            end

            return Storage.set_custom_project(project_name)
          end)
          return true
        else
          -- Use global storage
          cache.selected_storage = "global"
          config.storage.project.enabled = false
          cache.custom_project_name = nil
          save_metadata()
          vim.notify("Using global storage", vim.log.levels.INFO)
          return false
        end
      end)
    end
  end

  -- Handle custom mode
  if mode == "custom" then
    -- Get available custom projects
    local custom_projects = Storage.get_custom_projects(true, true)

    -- Prepare selection list
    local options = {}
    local projects_info = {}

    -- Flag to highlight if we have custom projects in current directory
    local has_cwd_projects = false
    local cwd = vim.fn.getcwd()

    -- Filter and prioritize projects in current directory
    local filtered_projects = Storage:filter_and_sort_projects(custom_projects, true)

    -- First add a header if we have projects in current directory
    for _, project in ipairs(filtered_projects) do
      -- Determine display format based on location
      local location_prefix = ""
      if project.base_dir == cwd then
        location_prefix = "📍 " -- Use an emoji marker for current directory projects
        has_cwd_projects = true
      else
        location_prefix = "   " -- Indent other projects for visual hierarchy
      end

      local display_name = location_prefix .. "Custom Project: [" .. project.name .. "]"
      if project.base_dir ~= cwd then
        display_name = display_name .. " (" .. vim.fn.fnamemodify(project.base_dir, ":~:.") .. ")"
      end

      table.insert(options, display_name)
      table.insert(projects_info, {
        name = project.name,
        path = project.base_dir,
        tasks_path = project.tasks_path
      })
    end

    -- Add option for new project in current directory
    table.insert(options, "Create New Project in Current Directory")
    table.insert(projects_info, { is_create_cwd = true })

    -- Add option for new project with custom location
    table.insert(options, "Create New Project in Custom Location")
    table.insert(projects_info, { is_create_custom = true })

    -- Show selection UI
    vim.ui.select(options, {
      prompt = "Select or create a custom project:",
      format_item = function(item) return item end,
    }, function(choice, idx)
      if not choice then return config.storage.project.enabled end

      local selected = projects_info[idx]

      if selected.is_create_cwd then
        -- Create new project in current directory
        vim.ui.input({
          prompt = "Enter new custom project name: ",
        }, function(project_name)
          if not project_name or project_name == "" then
            vim.notify("Invalid project name", vim.log.levels.WARN)
            return false
          end

          return Storage.set_custom_project(project_name)
        end)
      elseif selected.is_create_custom then
        -- Create project with custom location
        vim.ui.input({
          prompt = "Enter new custom project name: ",
        }, function(project_name)
          if not project_name or project_name == "" then
            vim.notify("Invalid project name", vim.log.levels.WARN)
            return false
          end

          -- Allow selecting a different base directory
          vim.ui.input({
            prompt = "Enter base directory (leave empty for current directory): ",
            default = vim.fn.getcwd(),
          }, function(base_dir)
            if not base_dir or base_dir == "" then
              base_dir = vim.fn.getcwd()
            end

            -- Expand the path to make sure it's valid
            base_dir = vim.fn.expand(base_dir)

            -- Verify directory exists
            if vim.fn.isdirectory(base_dir) ~= 1 then
              vim.notify("Invalid directory: " .. base_dir, vim.log.levels.WARN)
              return false
            end

            return Storage.set_custom_project(project_name, base_dir)
          end)
        end)
      else
        -- Selected existing project
        cache.selected_storage = "custom"
        cache.custom_project_name = selected.name
        cache.project_root = selected.path
        config.storage.project.enabled = true
        save_metadata()
        vim.notify("Switched to custom project: " .. selected.name, vim.log.levels.INFO)
        -- Force reload of tasks
        Storage.load("custom")
        return true
      end
    end)

    return config.storage.project.enabled
  end

  -- Default toggle behavior
  if not mode then
    if cache.selected_storage == "custom" or config.storage.project.enabled then
      -- Switch to global
      cache.selected_storage = "global"
      config.storage.project.enabled = false
      cache.custom_project_name = nil
      save_metadata()
      vim.notify("Switched to global storage", vim.log.levels.INFO)
      return false
    else
      -- Run auto detection
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

  local storage_path, is_project = Storage:get_storage_path()

  return {
    mode = is_project and "project" or "global",
    current_path = storage_path,
    global_path = config.storage.global_path,
    project_enabled = config.storage.project.enabled,
    selected_storage = cache.selected_storage,
    custom_project_name = cache.custom_project_name,
    project_root = cache.project_root,
    file_exists = Utils.path_exists(storage_path)
  }
end

---Scan for available custom projects
---@param force_scan boolean Force a fresh scan instead of using cache
---@param recursive boolean Whether to scan recursively for projects in subdirectories
---@return table List of available custom projects
function Storage.get_custom_projects(force_scan, recursive)
  if not config then
    error("Storage not initialized. Call setup() first")
  end

  -- Use cache if recent (less than 5 minutes old) and not forced scan
  if not force_scan and cache.last_scan and (os.time() - cache.last_scan) < 300 then
    return cache.custom_projects
  end

  -- Set scan depth
  local max_depth = recursive and 3 or 1 -- Default to depth 3 for recursive scan

  -- Perform scan
  local projects = {}
  local scanned_paths = {}

  -- Helper function to scan a directory
  local function scan_dir(base_path, current_depth)
    -- Check max depth and avoid duplicates
    if current_depth > max_depth or scanned_paths[base_path] then
      return
    end
    scanned_paths[base_path] = true

    -- Look for tasks.json files directly in directories
    local tasks_path = base_path .. "/tasks.json"
    if Utils.path_exists(tasks_path) then
      -- Get the directory name as the project name
      local dir_name = vim.fn.fnamemodify(base_path, ":t")
      
      table.insert(projects, {
        name = dir_name,
        path = base_path,
        tasks_path = tasks_path,
        base_dir = base_path,
      })
    end

    -- Scan subdirectories if recursive
    if current_depth < max_depth then
      local ok, subdirs = pcall(vim.fn.glob, base_path .. "/*/", true, true)
      if ok and subdirs then
        for _, subdir in ipairs(subdirs) do
          -- Skip hidden and system directories
          local dir_name = vim.fn.fnamemodify(subdir, ":t")
          if not dir_name:match("^%.") and dir_name ~= "node_modules" then
            scan_dir(subdir:sub(1, -2), current_depth + 1) -- Remove trailing slash
          end
        end
      end
    end
  end

  -- Start scan from current directory
  scan_dir(vim.fn.getcwd(), 1)

  -- Sort projects alphabetically
  table.sort(projects, function(a, b)
    return a.name < b.name
  end)

  -- Update cache
  cache.custom_projects = projects
  cache.last_scan = os.time()

  return projects
end

---Find project markers in the current directory tree
---@return table project_markers List of potential project directories
function Storage:find_project_markers()
  local cwd = vim.fn.getcwd()
  if not config then
    error("Storage not initialized. Call setup() first")
  end

  -- Get configured markers with defaults
  local markers = vim.tbl_extend("keep",
    config.storage.project.markers or {},
    {
      ".git", ".lazydo", "package.json", "Cargo.toml", "go.mod",
      "pom.xml", "build.gradle", "CMakeLists.txt", "Makefile",
      ".project", ".idea", ".vscode"
    }
  )

  local project_markers = {}
  local seen_paths = {} -- Track seen paths to avoid duplicates

  -- Add marker with deduplication
  local function add_marker(marker)
    if not seen_paths[marker.path] then
      seen_paths[marker.path] = true
      table.insert(project_markers, marker)
    end
  end

  -- Check for git root first (highest priority)
  local git_root = Storage:get_git_root()
  if git_root then
    add_marker({
      path = git_root,
      name = "Git Project: " .. vim.fn.fnamemodify(git_root, ":t"),
      type = "git",
      priority = 1,
      depth = 0
    })
  end

  -- Check for LazyDo marker with parent directory search
  local check_path = cwd
  local depth = 0
  while check_path and check_path ~= "" and depth < 10 do
    local lazydo_path = check_path .. "/.lazydo"
    if vim.fn.filereadable(lazydo_path) == 1 or vim.fn.isdirectory(lazydo_path) == 1 then
      add_marker({
        path = check_path,
        name = "LazyDo Project: " .. vim.fn.fnamemodify(check_path, ":t"),
        type = "lazydo",
        priority = 2,
        depth = depth
      })
      break
    end

    -- Move up to parent directory
    local parent_path = vim.fn.fnamemodify(check_path, ":h")
    if parent_path == check_path then break end
    check_path = parent_path
    depth = depth + 1
  end

  -- Check for other project markers in current directory
  for _, marker in ipairs(markers) do
    if marker ~= ".git" and marker ~= ".lazydo" then
      local marker_path = cwd .. "/" .. marker
      if vim.fn.filereadable(marker_path) == 1 or vim.fn.isdirectory(marker_path) == 1 then
        add_marker({
          path = cwd,
          name = "Project (" .. marker .. "): " .. vim.fn.fnamemodify(cwd, ":t"),
          type = "marker",
          priority = 3,
          depth = 0,
          marker = marker
        })
      end
    end
  end

  -- Sort markers by priority and depth
  table.sort(project_markers, function(a, b)
    if a.priority == b.priority then
      return a.depth < b.depth -- Prefer shallower paths when priority is equal
    end
    return a.priority < b.priority
  end)

  return project_markers
end

---Get project root with improved detection
---@return string
function Storage:get_project_root()
  if not config then
    error("Storage not initialized. Call setup() first")
  end

  -- If we have a cached project root and it's still valid, use it
  if cache.project_root and vim.fn.isdirectory(cache.project_root) == 1 then
    local lazydo_dir = cache.project_root .. "/.lazydo"
    if vim.fn.isdirectory(lazydo_dir) == 1 then
      return cache.project_root
    end
  end

  -- Try to detect project root
  local project_markers = Storage:find_project_markers()
  if #project_markers > 0 then
    return project_markers[1].path
  end

  -- Fallback to current working directory if configured
  if config.storage.project.fallback_to_cwd then
    return vim.fn.getcwd()
  end

  return "Global"
end

---@return string|nil
function Storage:get_git_root()
  if not config then
    error("Storage not initialized. Call setup() first")
  end

  -- Only try git root if configured
  if not (config.storage.project.enabled and config.storage.project.use_git_root) then
    return nil
  end

  -- Try to get git root
  local git_cmd = "git rev-parse --show-toplevel 2>/dev/null"
  local ok, result = pcall(vim.fn.systemlist, git_cmd)

  if not ok or vim.v.shell_error ~= 0 or not result or #result == 0 then
    return nil
  end

  -- Validate the returned path
  local git_root = result[1]
  if not git_root or git_root == "" or not vim.fn.isdirectory(git_root) then
    return nil
  end

  return git_root
end

---Auto-detect project with improved handling
---@return boolean is_project Whether a project was detected
function Storage.auto_detect_project()
  if not config then
    error("Storage not initialized. Call setup() first")
  end

  -- Only auto-detect if enabled
  if not config.storage.project.auto_detect then
    return false
  end

  -- Get current status before detection
  local prev_status = Storage.get_status()

  -- First check if we have metadata from a previous session
  if cache.selected_storage then
    if cache.selected_storage == "global" then
      config.storage.project.enabled = false
      return false
    elseif cache.selected_storage == "custom" and cache.custom_project_name then
      -- Verify the custom project exists
      local project_dir = string.format("%s/.lazydo/%s",
        cache.project_root or vim.fn.getcwd(),
        cache.custom_project_name)

      local tasks_path = project_dir .. "/tasks.json"
      if Utils.path_exists(tasks_path) then
        config.storage.project.enabled = true
        return true
      end
    elseif cache.selected_storage == "project" and cache.project_root then
      -- Verify project root exists
      if vim.fn.isdirectory(cache.project_root) == 1 then
        config.storage.project.enabled = true
        return true
      end
    end
  end

  -- Look for project markers
  local project_markers = Storage:find_project_markers()

  -- If we found project markers, use the highest priority one
  if #project_markers > 0 then
    local project = project_markers[1]
    cache.selected_storage = "project"
    config.storage.project.enabled = true
    cache.project_root = project.path

    -- Create .lazydo directory if it doesn't exist
    local lazydo_dir = project.path .. "/.lazydo"
    pcall(Utils.ensure_dir, lazydo_dir)

    -- Save metadata for next session
    save_metadata()

    -- Get new status after detection
    local new_status = Storage.get_status()

    -- Notify if storage location changed
    if prev_status.current_path ~= new_status.current_path then
      vim.notify("Auto-detected project storage: " .. new_status.current_path, vim.log.levels.INFO)
    end

    return true
  end

  -- No project markers found - use global storage
  cache.selected_storage = "global"
  config.storage.project.enabled = false

  -- Save metadata
  save_metadata()

  return false
end

---Compress data for storage
---@param data string Data to compress
---@return string Compressed data
function Storage:compress_data(data)
  -- Simple implementation that preserves JSON structure
  local compressed = data:gsub("([%s%p])%1+", function(s)
    local count = #s
    if count > 3 then
      return string.format("##%d##%s", count, s:sub(1, 1))
    end
    return s
  end)

  return compressed
end

---Decompress data from storage
---@param data string Compressed data
---@return string Decompressed data
function Storage:decompress_data(data)
  -- Restore compressed patterns
  local decompressed = data:gsub("##(%d+)##(.)", function(count, char)
    return string.rep(char, tonumber(count))
  end)

  return decompressed
end

---Basic encryption
---@param data string Data to encrypt
---@return string Encrypted data
function Storage:encrypt_data(data)
  local result = {}
  for i = 1, #data do
    local byte = data:byte(i)
    table.insert(result, string.char((byte + 7) % 256))
  end
  return table.concat(result)
end

---Basic decryption
---@param data string Data to decrypt
---@return string Decrypted data
function Storage:decrypt_data(data)
  local result = {}
  for i = 1, #data do
    local byte = data:byte(i)
    table.insert(result, string.char((byte - 7) % 256))
  end
  return table.concat(result)
end

---Create backup of current storage
---@return nil
function Storage:create_backup()
  if not config or not config.storage.auto_backup then
    return
  end

  local current_file = Storage:get_storage_path()
  if not Utils.path_exists(current_file) then
    return
  end

  local dir = vim.fn.fnamemodify(current_file, ":h")
  local base = vim.fn.fnamemodify(current_file, ":t:r")
  local backup_file = string.format("%s/%s.backup.%s.json", dir, base, os.date("%Y%m%d%H%M%S"))

  -- Create the backup
  pcall(vim.fn.writefile, vim.fn.readfile(current_file), backup_file)
  
  -- Check if backup_count is set and greater than 0
  local backup_count = config.storage.backup_count or 0
  if backup_count > 0 then
    -- Get all backup files for this storage
    local pattern = string.format("%s/%s.backup.*.json", dir, base) 
    local ok, backup_files = pcall(vim.fn.glob, pattern, false, true)
    
    if ok and backup_files and #backup_files > backup_count then
      -- Sort backup files by modification time (newest first)
      table.sort(backup_files, function(a, b)
        return vim.fn.getftime(a) > vim.fn.getftime(b)
      end)
      
      -- Remove older backups beyond the backup_count limit
      for i = backup_count + 1, #backup_files do
        pcall(os.remove, backup_files[i])
      end
    end
  end
end

---Filter and sort custom projects with improved prioritization
---@param projects table List of custom projects
---@param prioritize_cwd boolean Whether to prioritize projects in current directory
---@return table Filtered and sorted projects
function Storage:filter_and_sort_projects(projects, prioritize_cwd)
  if #projects == 0 then
    return {}
  end

  local cwd = vim.fn.getcwd()
  local filtered = {}
  local cwd_projects = {}
  local other_projects = {}

  -- Separate projects by location
  for _, project in ipairs(projects) do
    if project.base_dir == cwd then
      table.insert(cwd_projects, project)
    else
      table.insert(other_projects, project)
    end
  end

  -- Sort each group by name
  table.sort(cwd_projects, function(a, b) return a.name < b.name end)
  table.sort(other_projects, function(a, b) return a.name < b.name end)

  -- Combine according to prioritization
  if prioritize_cwd then
    for _, project in ipairs(cwd_projects) do
      table.insert(filtered, project)
    end
    
    for _, project in ipairs(other_projects) do
      table.insert(filtered, project)
    end
  else
    -- Just sort all by name if not prioritizing
    for _, project in ipairs(projects) do
      table.insert(filtered, project)
    end
    table.sort(filtered, function(a, b) return a.name < b.name end)
  end

  return filtered
end

---Clear storage data with selection UI
---@param mode? "auto"|"global"|"project"|"custom" Optional mode to target specific storage
---@return boolean success Whether the operation was successful
function Storage.clear_storage(mode)
  if not config then
    error("Storage not initialized. Call setup() first")
  end

  if mode == "global" then
    -- Clear global storage
    local global_path = Storage:get_storage_path("global")
    if Utils.path_exists(global_path) then
      local write_ok = pcall(function()
        vim.fn.writefile({ "[]" }, global_path)
      end)
      if write_ok then
        vim.notify("Global storage cleared", vim.log.levels.INFO)
        cache.data = {}
        cache.is_dirty = false
        return true
      else
        vim.notify("Failed to clear global storage", vim.log.levels.ERROR)
        return false
      end
    else
      vim.notify("Global storage file doesn't exist", vim.log.levels.WARN)
      return false
    end
  elseif mode == "project" then
    -- Clear project storage
    local project_path, is_project = Storage:get_storage_path("project")
    if is_project and Utils.path_exists(project_path) then
      local write_ok = pcall(function()
        vim.fn.writefile({ "[]" }, project_path)
      end)
      if write_ok then
        vim.notify("Project storage cleared", vim.log.levels.INFO)
        cache.data = {}
        cache.is_dirty = false
        return true
      else
        vim.notify("Failed to clear project storage", vim.log.levels.ERROR)
        return false
      end
    else
      vim.notify("Project storage file doesn't exist", vim.log.levels.WARN)
      return false
    end
  elseif mode == "custom" then
    -- Get available custom projects
    local custom_projects = Storage.get_custom_projects(true, true)
    local filtered_projects = Storage:filter_and_sort_projects(custom_projects, true)
    
    if #filtered_projects == 0 then
      vim.notify("No custom projects found", vim.log.levels.WARN)
      return false
    end
    
    -- Prepare selection list
    local options = {}
    local projects_info = {}
    local cwd = vim.fn.getcwd()
    
    -- Add option to clear all custom projects
    table.insert(options, "🔄 Clear ALL Custom Projects")
    table.insert(projects_info, { clear_all = true })
    
    -- Add individual custom projects
    for _, project in ipairs(filtered_projects) do
      -- Determine display format based on location
      local location_prefix = ""
      if project.base_dir == cwd then
        location_prefix = "📍 " -- Use an emoji marker for current directory projects
      else
        location_prefix = "   " -- Indent other projects for visual hierarchy
      end
      
      local display_name = location_prefix .. "Clear: [" .. project.name .. "]"
      if project.base_dir ~= cwd then
        display_name = display_name .. " (" .. vim.fn.fnamemodify(project.base_dir, ":~:.") .. ")"
      end
      
      table.insert(options, display_name)
      table.insert(projects_info, {
        name = project.name,
        path = project.base_dir,
        tasks_path = project.tasks_path
      })
    end
    
    -- Show selection UI
    vim.ui.select(options, {
      prompt = "Select custom project to clear:",
      format_item = function(item) return item end,
    }, function(choice, idx)
      if not choice then return false end
      
      local selected = projects_info[idx]
      
      if selected.clear_all then
        -- Clear all custom projects
        local cleared_count = 0
        for _, project in ipairs(filtered_projects) do
          if Utils.path_exists(project.tasks_path) then
            local write_ok = pcall(function()
              vim.fn.writefile({ "[]" }, project.tasks_path)
            end)
            if write_ok then
              cleared_count = cleared_count + 1
            end
          end
        end
        
        -- Update cache if current project was cleared
        if cache.selected_storage == "custom" then
          cache.data = {}
          cache.is_dirty = false
        end
        
        vim.notify("Cleared " .. cleared_count .. " custom projects", vim.log.levels.INFO)
        return cleared_count > 0
      else
        -- Clear individual project
        if Utils.path_exists(selected.tasks_path) then
          local write_ok = pcall(function()
            vim.fn.writefile({ "[]" }, selected.tasks_path)
          end)
          
          if write_ok then
            vim.notify("Cleared custom project: " .. selected.name, vim.log.levels.INFO)
            
            -- Update cache if current project was cleared
            if cache.selected_storage == "custom" and 
               cache.custom_project_name == selected.name and
               cache.project_root == selected.path then
              cache.data = {}
              cache.is_dirty = false
            end
            
            return true
          else
            vim.notify("Failed to clear custom project", vim.log.levels.ERROR)
            return false
          end
        else
          vim.notify("Custom project file doesn't exist", vim.log.levels.WARN)
          return false
        end
      end
    end)
    
    return true
  elseif mode == "auto" or not mode then
    -- Show selection for all storage types
    vim.ui.select({
      "Global Storage",
      "Project Storage",
      "Custom Projects",
      "ALL Storage Types"
    }, {
      prompt = "Select storage type to clear:",
    }, function(choice)
      if not choice then return false end
      
      if choice == "Global Storage" then
        return Storage.clear_storage("global")
      elseif choice == "Project Storage" then
        return Storage.clear_storage("project")
      elseif choice == "Custom Projects" then
        return Storage.clear_storage("custom")
      elseif choice == "ALL Storage Types" then
        -- Clear all storage types
        local global_ok = Storage.clear_storage("global")
        local project_ok = Storage.clear_storage("project")
        local custom_ok = Storage.clear_storage("custom")
        
        return global_ok or project_ok or custom_ok
      end
    end)
    
    return true
  end
  
  return false
end

return Storage
