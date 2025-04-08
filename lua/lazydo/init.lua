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

        -- If LazyDo is initialized, just toggle the UI
        LazyDo.toggle()
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
        local success, _ = pcall(function()
          LazyDo._instance:toggle_storage_mode(mode)
        end)

        if not success then
          vim.notify("Failed to toggle storage mode", vim.log.levels.ERROR)
          return
        end

        -- Refresh UI if it's open
        if LazyDo._instance:is_visible() then
          -- Reload tasks from the new storage
          local reload_success, _ = pcall(function()
            local tasks = LazyDo._instance:reload_tasks()
            LazyDo._instance:refresh_ui(tasks)
          end)

          if not reload_success then
            vim.notify("Failed to refresh UI with new storage", vim.log.levels.WARN)
          end
        end

        -- Show current storage status
        local status = LazyDo._instance:get_storage_status()
        local lines = {
          "Storage Status:",
          string.format("Mode: %s", status.mode),
          string.format("Current Path: %s", status.current_path),
          string.format("Global Path: %s", status.global_path or "default"),
          string.format("Project Mode: %s", status.project_enabled and "enabled" or "disabled"),
        }

        if status.mode == "project" or status.selected_storage == "custom" then
          table.insert(lines, string.format("Project Root: %s", status.project_root or "N/A"))
          if status.custom_project_name then
            table.insert(lines, string.format("Custom Project: %s", status.custom_project_name))
          end
        end

        vim.api.nvim_echo(
          vim.tbl_map(function(line)
            return { line .. "\n", "Normal" }
          end, lines),
          true,
          {}
        )
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
        if LazyDo._instance:get_current_view() ~= "kanban" then
          LazyDo._instance:toggle_view()
        else
          LazyDo.toggle()
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
    -- if LazyDo._config.storage.startup_detect then
    --   vim.api.nvim_create_autocmd("VimEnter", {
    --     group = augroup,
    --     callback = function()
    --       if LazyDo._instance then
    --         -- Ensure we're using the correct storage mode on startup
    --         local success, _ = pcall(function()
    --           LazyDo._instance:toggle_storage_mode("auto")
    --         end)
    --
    --         if not success then
    --           vim.notify("Failed to auto-detect project storage mode on startup", vim.log.levels.WARN)
    --         end
    --       end
    --     end,
    --   })
    -- end

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
---@param mode? "project"|"global"|"auto" Optional mode to set directly
---@throws string when toggle operation fails
function LazyDo.toggle_storage_mode(mode)
  if not LazyDo._initialized then
    vim.notify("LazyDo is not initialized", vim.log.levels.ERROR)
    return
  end

  local success, err = pcall(function()
    LazyDo._instance:toggle_storage_mode(mode)
  end)

  if not success then
    vim.notify("Failed to toggle storage mode: " .. tostring(err), vim.log.levels.ERROR)
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

  local success, result = pcall(function()
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

return LazyDo
