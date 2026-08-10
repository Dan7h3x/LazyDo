local Config = require("lazydo.config")
local Core = require("lazydo.core")
local Highlights = require("lazydo.highlights")

---@class LazyDo
---@field private _instance LazyDoCore?
---@field public _config LazyDoConfig
---@field private _initialized boolean
local LazyDo = {
  _instance = nil,
  _config = nil,
  _initialized = false,
}

-- Utility function for safe command execution
local function safe_execute(callback, error_msg)
  return function(...)
    if not LazyDo._initialized then
      vim.notify("LazyDo is not initialized. Call setup() first.", vim.log.levels.ERROR)
      return
    end
    local success, result = pcall(callback, ...)
    if not success then
      vim.notify(error_msg .. ": " .. tostring(result), vim.log.levels.ERROR)
    end
    return result
  end
end

-- Create commands with improved error handling and feedback
local function create_commands()
  -- Command definitions with validation and feedback
  local commands = {
    {
      name = "LazyDoToggle",
      callback = function()
        -- Auto-initialize if not already initialized
        if not LazyDo._initialized then
          vim.notify("Initializing LazyDo for the first time", vim.log.levels.INFO)
          local init_success, _ = pcall(LazyDo.setup, {})
          if not init_success then
            vim.notify("Failed to initialize LazyDo automatically", vim.log.levels.ERROR)
            return
          end

          -- After initialization, activate the smart project detection
          LazyDo._instance:toggle_storage_mode("auto")
        end

        -- If LazyDo is initialized, open/close using the panel command
        LazyDo.open_panel()
      end,
      opts = {},
      error_msg = "Failed to toggle LazyDo window",
    },

    {
      name = "LazyDoPin",
      callback = function(opts)
        LazyDo._instance:toggle_pin_view(opts.args)
      end,
      opts = {
        nargs = "?",
        complete = function()
          return { "topleft", "topright", "bottomleft", "bottomright" }
        end,
      },
      error_msg = "Failed to toggle corner view",
    },
    {
      name = "LazyDoToggleStorage",
      callback = function(opts)
        -- Initialize if not already initialized
        if not LazyDo._initialized then
          vim.notify("Initializing LazyDo for storage toggle", vim.log.levels.INFO)
          local init_success, _ = pcall(LazyDo.setup, {})
          if not init_success then
            vim.notify("Failed to initialize LazyDo automatically", vim.log.levels.ERROR)
            return
          end
        end

        local mode = opts.args ~= "" and opts.args or nil

        -- Toggle storage mode
        local success, result = pcall(function()
          return LazyDo._instance:toggle_storage_mode(mode)
        end)

        if not success then
          vim.notify("Failed to toggle storage mode: " .. tostring(result), vim.log.levels.ERROR)
          return
        end

        -- Refresh UI if it's open
        if LazyDo._instance:is_visible() then
          -- Reload tasks from the new storage
          local reload_success, tasks = pcall(function()
            return LazyDo._instance:reload_tasks()
          end)

          if not reload_success then
            vim.notify("Failed to reload tasks from new storage", vim.log.levels.WARN)
            return
          end

          -- Refresh UI with new tasks
          pcall(function()
            LazyDo._instance:refresh_ui(tasks)
          end)
        end

        -- Display storage status with improved feedback
        local status = LazyDo._instance:get_storage_status()
        local mode_str

        if status.selected_storage == "custom" and status.custom_project_name then
          mode_str = "Custom Project: " .. status.custom_project_name
        else
          mode_str = status.mode == "project" and
              "Project: " .. vim.fn.fnamemodify(status.project_root or "", ":t") or
              "Global"
        end

        vim.notify("Storage: " .. mode_str .. " (" .. status.current_path .. ")", vim.log.levels.INFO)
      end,
      opts = {
        nargs = "?",
        complete = function()
          return { "project", "global", "auto", "custom" }
        end,
      },
      error_msg = "Failed to toggle storage mode",
    },
    {
      name = "LazyDoClearStorage",
      callback = function(opts)
        -- Auto-initialize if not already initialized
        if not LazyDo._initialized then
          vim.notify("Initializing LazyDo for storage clearing", vim.log.levels.INFO)
          local init_success, _ = pcall(LazyDo.setup, {})
          if not init_success then
            vim.notify("Failed to initialize LazyDo automatically", vim.log.levels.ERROR)
            return
          end
        end
        
        local mode = opts.args ~= "" and opts.args or nil
        
        -- Call the clear_storage function
        local success, result = pcall(function()
          return LazyDo._instance:clear_storage(mode)
        end)
        
        if not success then
          vim.notify("Failed to clear storage: " .. tostring(result), vim.log.levels.ERROR)
          return
        end
        
        -- Refresh UI if it's open after clearing
        if LazyDo._instance:is_visible() then
          pcall(function()
            local tasks = LazyDo._instance:reload_tasks()
            LazyDo._instance:refresh_ui(tasks)
          end)
        end
      end,
      opts = {
        nargs = "?",
        complete = function()
          return { "global", "project", "custom", "auto" }
        end,
      },
      error_msg = "Failed to clear storage",
    },
    {
      name = "LazyDoToggleView",
      callback = function()
        LazyDo._instance:toggle_view()
        local current_view = LazyDo._instance:get_current_view()
        vim.notify("Switched to " .. current_view .. " view", vim.log.levels.INFO)
      end,
      opts = {},
      error_msg = "Failed to toggle view",
    },
    {
      name = "LazyDoKanban",
      callback = function()
        -- Auto-initialize if not already initialized
        if not LazyDo._initialized then
          vim.notify("Initializing LazyDo for the first time", vim.log.levels.INFO)
          local init_success, _ = pcall(LazyDo.setup, {})
          if not init_success then
            vim.notify("Failed to initialize LazyDo automatically", vim.log.levels.ERROR)
            return
          end

          -- After initialization, activate the smart project detection
          LazyDo._instance:toggle_storage_mode("auto")
        end

        -- Open kanban view directly
        if LazyDo._instance:get_current_view() ~= "kanban" then
          LazyDo._instance:toggle_view()
        end

        -- Ensure the panel is visible
        if not LazyDo._instance:is_visible() then
          LazyDo.open_panel("kanban")
        end
      end,
      opts = {},
      error_msg = "Failed to open Kanban view",
    },
  }

  -- Register commands with error handling
  for _, cmd in ipairs(commands) do
    local wrapped_callback = safe_execute(cmd.callback, cmd.error_msg)
    vim.api.nvim_create_user_command(cmd.name, wrapped_callback, cmd.opts)
  end
end

---Initialize LazyDo with user configuration
---@param opts? table User configuration
---@return LazyDo
---@throws string when configuration is invalid
function LazyDo.setup(opts)
  -- Prevent multiple initialization with proper cleanup
  if LazyDo._initialized then
    vim.notify("LazyDo is already initialized", vim.log.levels.WARN)
    return LazyDo
  end

  -- Setup with error handling
  local success, result = pcall(function()
    LazyDo._config = Config.setup(opts)

    -- Setup highlights with error handling
    local hl_success, hl_err = pcall(Highlights.setup, LazyDo._config)
    if not hl_success then
      error(string.format("Failed to setup highlights: %s", hl_err))
    end

    -- Initialize core with error handling
    LazyDo._instance = Core.new(LazyDo._config)
    if not LazyDo._instance then
      error("Failed to initialize core instance")
    end

    -- Setup autocommands with proper cleanup
    local augroup = vim.api.nvim_create_augroup("LazyDo", { clear = true })
    local function setup_signs()
      vim.fn.sign_define("LazyDoSearchSign", {
        text = "",
        texthl = "LazyDoSearchMatch",
        numhl = "LazyDoSearchMatch",
      })
    end
    setup_signs()

    -- Cleanup on exit
    vim.api.nvim_create_autocmd("VimLeave", {
      group = augroup,
      callback = function()
        if LazyDo._instance then
          LazyDo._instance:cleanup()
        end
      end,
    })

    -- Refresh highlights on colorscheme change
    vim.api.nvim_create_autocmd("ColorScheme", {
      group = augroup,
      callback = function()
        Highlights.setup(LazyDo._config)
        if LazyDo._instance then
          LazyDo._instance:refresh_ui()
        end
      end,
    })

    -- Auto-detect projects on startup and directory change
    if LazyDo._config.storage.project.auto_detect then
      -- Auto-detect on directory change
      vim.api.nvim_create_autocmd("DirChanged", {
        group = augroup,
        callback = function()
          if LazyDo._instance then
            LazyDo._instance:toggle_storage_mode("auto")
          end
        end,
      })
    end

    if LazyDo._config.storage.startup_detect then
      vim.api.nvim_create_autocmd("VimEnter", {
        group = augroup,
        callback = function()
          if LazyDo._instance then
            -- Use a slight delay to ensure UI is ready
            vim.defer_fn(function()
              local success, _ = pcall(function()
                LazyDo._instance:toggle_storage_mode("auto")
              end)

              if not success then
                vim.notify("Failed to auto-detect project storage mode on startup", vim.log.levels.WARN)
              end
            end, 100) -- 100ms delay
          end
        end,
      })
    end

    -- Create commands
    create_commands()

    LazyDo._initialized = true
  end)

  if not success then
    vim.notify("Failed to initialize LazyDo: " .. tostring(result), vim.log.levels.ERROR)
    return LazyDo
  end

  return LazyDo
end

---Toggle LazyDo window visibility
---@param view? "list"|"kanban" Optional view to open
function LazyDo.toggle(view)
  if not LazyDo._initialized then
    vim.notify("LazyDo is not initialized. Call setup() first.", vim.log.levels.ERROR)
    return
  end

  local toggle_success, err = pcall(function()
    LazyDo._instance:toggle(view)
  end)

  if not toggle_success then
    vim.notify("Error toggling LazyDo: " .. tostring(err), vim.log.levels.ERROR)
  end
end

---Toggle between list and kanban view
---@throws string when toggle operation fails
function LazyDo.toggle_view()
  if not LazyDo._initialized then
    vim.notify("LazyDo is not initialized", vim.log.levels.ERROR)
    return
  end

  local success, err = pcall(function()
    LazyDo._instance:toggle_view()
  end)

  if not success then
    vim.notify("Failed to toggle view: " .. tostring(err), vim.log.levels.ERROR)
  end
end

---Toggle storage mode between project and global
---@param mode? "project"|"global"|"auto"|"custom" Optional mode to set directly
function LazyDo.toggle_storage_mode(mode)
  if not LazyDo._initialized then
    vim.notify("LazyDo is not initialized. Call setup() first.", vim.log.levels.ERROR)
    return
  end

  -- Get current status before toggle
  local prev_status = {}
  pcall(function()
    prev_status = LazyDo._instance:get_storage_status()
  end)

  local success, result = pcall(function()
    return LazyDo._instance:toggle_storage_mode(mode)
  end)

  if not success then
    vim.notify("Failed to toggle storage mode: " .. tostring(result), vim.log.levels.ERROR)
    return
  end

  -- If UI is visible, reload data and refresh
  if LazyDo._instance:is_visible() then
    pcall(function()
      local tasks = LazyDo._instance:reload_tasks()
      LazyDo._instance:refresh_ui(tasks)
    end)
  end

  -- Get new status after toggle for comparison
  local new_status = {}
  pcall(function()
    new_status = LazyDo._instance:get_storage_status()
  end)

  -- Only show additional notification if status changed and no other notification was shown
  if new_status.current_path and new_status.current_path ~= prev_status.current_path then
    local mode_str = ""
    if new_status.selected_storage == "custom" and new_status.custom_project_name then
      mode_str = "Custom Project: " .. new_status.custom_project_name
    else
      mode_str = new_status.mode == "project" and
          "Project: " .. vim.fn.fnamemodify(new_status.project_root or "", ":t") or
          "Global"
    end

    vim.notify("Now using " .. mode_str .. " storage", vim.log.levels.INFO)
  end
end

---Get all tasks with error handling
---@return Task[] List of tasks
---@throws string when task retrieval fails
function LazyDo.get_tasks()
  if not LazyDo._initialized then
    vim.notify("LazyDo is not initialized", vim.log.levels.ERROR)
    return {}
  end

  local success, result = pcall(function()
    return LazyDo._instance:get_tasks()
  end)

  if not success then
    vim.notify("Failed to get tasks: " .. tostring(result), vim.log.levels.ERROR)
    return {}
  end

  return result or {}
end

function LazyDo.get_lualine_stats()
  if not LazyDo._initialized then
    return "LazyDo not initialized"
  end

  local success, result, storage = pcall(function()
    return LazyDo._instance:get_statistics()
  end)

  if not success then
    return "Error retrieving stats"
  end





  local icons = {
    total = "",
    done = "",
    pending = "󱛢",
    overdue = "󰨱",
  }
  if result.total ~= 0 then
    return string.format(
      "%%#LazyDoStorageMode#" ..
      storage ..
      "%%#LazyDoTitle#%s %%#Function#%d|%%#LazyDoDueDateNear#%s %%#Function#%d|%%#LazyDoTaskOverDue#%s %%#Function#%d|%%#String#%s %%#Function#%d",
      icons.total,
      result.total,
      icons.pending,
      result.pending,
      icons.overdue,
      result.overdue,
      icons.done,
      result.completed
    )
  else
    return ""
  end
end

---New function to open the panel with selected storage
---@param view? "list"|"kanban" Optional view to open
function LazyDo.open_panel(view)
  if not LazyDo._initialized then
    vim.notify("LazyDo is not initialized. Call setup() first.", vim.log.levels.ERROR)
    return
  end

  local toggle_success, err = pcall(function()
    -- If already visible, close it (toggle behavior)
    if LazyDo._instance:is_visible() then
      LazyDo._instance:toggle() -- Use toggle to close
      return
    end

    -- Reload tasks from current storage
    LazyDo._instance:reload_tasks()

    -- Set view if specified
    if view and LazyDo._instance:get_current_view() ~= view then
      LazyDo._instance:toggle_view()
    end

    -- Open the panel using toggle
    LazyDo._instance:toggle()
  end)

  if not toggle_success then
    vim.notify("Error opening LazyDo panel: " .. tostring(err), vim.log.levels.ERROR)
  end
end

---Clear storage data with selection UI
---@param mode? "auto"|"global"|"project"|"custom" Optional mode to target specific storage
function LazyDo.clear_storage(mode)
  if not LazyDo._initialized then
    vim.notify("LazyDo is not initialized. Call setup() first.", vim.log.levels.ERROR)
    return false
  end

  local success, result = pcall(function()
    return LazyDo._instance:clear_storage(mode)
  end)

  if not success then
    vim.notify("Failed to clear storage: " .. tostring(result), vim.log.levels.ERROR)
    return false
  end

  -- If UI is visible, reload data and refresh
  if LazyDo._instance:is_visible() then
    pcall(function()
      local tasks = LazyDo._instance:reload_tasks()
      LazyDo._instance:refresh_ui(tasks)
    end)
  end

  return result
end

return LazyDo
