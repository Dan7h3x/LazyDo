-- Main entry point
local LazyDo = require('lazydo.core')
local config = require('lazydo.config')

-- Create the setup function that lazy.nvim will call
local M = {
  _instance = nil,
  -- Default configuration that can be overridden by lazy.nvim opts
  default_opts = {
    storage = {
      path = vim.fn.stdpath("data") .. "/lazydo/tasks.json",
      backup = true,
      auto_save = true,
    },
    ui = {
      width = 0.8,
      height = 0.8,
      border = "rounded",
      winblend = 0,
      title = " LazyDo ",
    },
    features = {
      recurring_tasks = true,
      task_notes = true,
      subtasks = true,
      priorities = true,
      due_dates = true,
      tags = true,
      sorting = true,
      filtering = true,
    },
  }
}

-- Simplified wrap_with_auto_save function
local function wrap_with_auto_save(instance)
  if not instance then return nil end

  local functions_to_wrap = {
    'add_task', 'delete_task', 'move_task', 'toggle',
    'set_due_date', 'set_note', 'change_priority',
    'add_subtask', 'remove_subtask', 'add_tag', 'remove_tag'
  }

  return setmetatable({}, {
    __index = function(_, key)
      local original = instance[key]
      if type(original) == 'function' and vim.tbl_contains(functions_to_wrap, key) then
        return function(self, ...)
          local result = original(instance, ...)
          if result ~= false and instance.opts and instance.opts.storage.auto_save then
            require('lazydo.storage').save_tasks(instance)
          end
          if instance.is_visible then
            instance:refresh_display()
          end
          return result
        end
      end
      return original
    end
  })
end

-- Simplified setup function that works with lazy.nvim
function M.setup(opts)
  -- Return existing instance if already initialized
  if M._instance then
    return M._instance
  end

  -- Create new instance
  local instance = LazyDo:new()
  if not instance then
    error("Failed to create LazyDo instance")
  end

  -- Merge configurations
  instance.opts = vim.tbl_deep_extend("force", M.default_opts, opts or {})

  -- Initialize storage
  local storage = require('lazydo.storage')
  local storage_dir = vim.fn.fnamemodify(instance.opts.storage.path, ":h")
  if vim.fn.isdirectory(storage_dir) == 0 then
    vim.fn.mkdir(storage_dir, "p")
  end

  -- Wrap instance with auto-save
  instance = wrap_with_auto_save(instance)
  if not instance then
    error("Failed to wrap instance with auto-save")
  end

  -- Load existing tasks
  storage.load_tasks(instance)

  -- Setup highlights and commands
  instance:setup_highlights()
  instance:create_commands()

  M._instance = instance
  return instance
end

-- Simplified API methods
function M.toggle()
  if M._instance then M._instance:toggle() end
end

function M.show()
  if M._instance then M._instance:show() end
end

function M.close()
  if M._instance then M._instance:close_window() end
end

function M.add_task(content, opts)
  if M._instance then return M._instance:add_task(content, opts) end
end

function M.delete_task()
  if M._instance then return M._instance:delete_task() end
end

function M.get_tasks()
  return M._instance and M._instance.tasks or {}
end

return M
