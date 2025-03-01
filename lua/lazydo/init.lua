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
        local mode = opts.args ~= "" and opts.args or nil
        local storage = require("lazydo.storage")
        storage.toggle_mode(mode)

        -- Show current storage status
        local status = storage.get_status()
        local lines = {
          "Storage Status:",
          string.format("Mode: %s", status.mode),
          string.format("Current Path: %s", status.current_path),
          string.format("Global Path: %s", status.global_path or "default"),
          string.format("Project Mode: %s", status.project_enabled and "enabled" or "disabled"),
          string.format("Git Root: %s", status.use_git_root and "enabled" or "disabled"),
          string.format("Compression: %s", status.compression and "enabled" or "disabled"),
          string.format("Encryption: %s", status.encryption and "enabled" or "disabled"),
        }

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
          return { "project", "global" }
        end,
      },
      error_msg = "Failed to toggle storage mode",
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

-- Public API Methods with improved error handling and validation

---Toggle task manager window
---@throws string when toggle operation fails
function LazyDo.toggle()
  if not LazyDo._initialized then
    vim.notify("LazyDo is not initialized", vim.log.levels.ERROR)
    return
  end

  local success, err = pcall(function()
    LazyDo._instance:toggle()
    Highlights.setup(LazyDo._config)
  end)

  if not success then
    vim.notify("Failed to toggle window: " .. tostring(err), vim.log.levels.ERROR)
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
  
  -- Return empty string if there are no tasks
  if result.total == 0 then
    return ""
  end

  local icons = {
    total = "",
    done = "",
    pending = "󱛢",
    overdue = "󰨱",
  }
  return string.format(
    "%%#Title#%s %%#Function#%d|%%#Constant#%s %%#Function#%d|%%#Error#%s %%#Function#%d|%%#String#%s %%#Function#%d",
    icons.total,
    result.total,
    icons.pending,
    result.pending,
    icons.overdue,
    result.overdue,
    icons.done,
    result.completed
  )
end

return LazyDo