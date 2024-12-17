-- Main entry point
local LazyDo = require('lazydo.core')
local setup = require('lazydo.setup')

-- Create the setup function that lazy.nvim will call
local M = {
  _instance = nil
}

-- Add wrap_with_auto_save function
function LazyDo:wrap_with_auto_save(instance)
  local functions_to_wrap = {
    'add_task',
    'delete_task',
    'move_task',
    'toggle',
    'set_due_date',
    'set_note',
    'change_priority',
    'add_subtask',
    'remove_subtask',
    'add_tag',
    'remove_tag'
  }

  for _, func_name in ipairs(functions_to_wrap) do
    if instance[func_name] then
      local original = instance[func_name]
      instance[func_name] = function(self, ...)
        local result = original(self, ...)
        -- Auto-save if enabled and the function succeeded
        if result ~= false and self.opts and self.opts.storage.auto_save then
          require('lazydo.storage').save_tasks(self)
        end
        -- Refresh display after modification
        if self.is_visible then
          self:refresh_display()
        end
        return result
      end
    end
  end

  return instance
end

function M.setup(opts)
  if not M._instance then
    local instance = LazyDo:new()
    instance = LazyDo.wrap_with_auto_save(instance)
    M._instance = setup(opts)
  end
  return M._instance
end

-- Add convenience methods
function M.toggle()
  if M._instance then
    M._instance:toggle()
  end
end

function M.show()
  if M._instance then
    M._instance:show()
  end
end

function M.close()
  if M._instance then
    M._instance:close_window()
  end
end

-- Add convenience methods for task management
function M.add_task(content, opts)
  if M._instance then
    return M._instance:add_task(content, opts)
  end
end

function M.delete_task()
  if M._instance then
    return M._instance:delete_task()
  end
end

function M.get_tasks()
  if M._instance then
    return M._instance.tasks
  end
  return {}
end

-- Add error handling wrapper
local function safe_call(method, ...)
  if not M._instance then
    vim.notify("LazyDo is not initialized. Call setup() first.", vim.log.levels.ERROR)
    return nil
  end

  local ok, result = pcall(method, M._instance, ...)
  if not ok then
    vim.notify("LazyDo error: " .. tostring(result), vim.log.levels.ERROR)
    return nil
  end

  return result
end

-- Add wrapped methods for external use
M.add_subtask = function(content, opts)
  return safe_call(M._instance.add_subtask, content, opts)
end

M.set_due_date = function(task_id, date)
  return safe_call(M._instance.set_due_date, task_id, date)
end

M.set_note = function(task_id, note)
  return safe_call(M._instance.set_note, task_id, note)
end

M.change_priority = function(task_id, delta)
  return safe_call(M._instance.change_priority, task_id, delta)
end

M.add_tag = function(task_id, tag)
  return safe_call(M._instance.add_tag, task_id, tag)
end

M.remove_tag = function(task_id, tag)
  return safe_call(M._instance.remove_tag, task_id, tag)
end

-- Re-export the module
return M
