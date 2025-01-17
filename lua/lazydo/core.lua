-- core.lua
local Task = require("lazydo.task")
local Storage = require("lazydo.storage")
local Actions = require("lazydo.actions")
local Utils = require("lazydo.utils")
local UI = require("lazydo.ui")

---@class LazyDoCore
---@field private config LazyDoConfig
---@field private tasks Task[]
---@field private _ui_visible boolean
---@field private _last_search string?
---@field private _last_filter table?
---@field private _last_sort string?
---@field private _template_cache table<string, table>
---@field private _reminder_timer any
local Core = {}
Core.__index = Core

function Core.new(config)
  if not config then
    error("Configuration is required")
  end

  local self = setmetatable({
    config = config,
    tasks = {},
    _ui_visible = false,
    _pin_visible = false,
    _pin_position = config.pin_window and config.pin_window.position or "topright",
    _last_search = nil,
    _last_filter = nil,
    _last_sort = nil,
    _template_cache = {},
    _last_ui_state = nil,
    _pin_window_state = {
      visible = false,
      position = config.pin_window and config.pin_window.position or "topright",
      last_update = os.time(),
    },
  }, Core)

  -- Load tasks
  local success, loaded_tasks = pcall(Storage.load)
  if success and loaded_tasks then
    self.tasks = loaded_tasks
    self:apply_saved_view()
  end

  -- Initialize pin window if configured to show on startup
  if config.pin_window and config.pin_window.enabled and config.pin_window.show_on_startup then
    self:toggle_pin_view(self._pin_position)
  end

  return self
end

---Apply saved view settings (filters, sorts)
function Core:apply_saved_view()
  if self._last_sort then
    self:sort_tasks(self._last_sort)
  end
end

---Export tasks to markdown
---@param filepath string
function Core:export_to_markdown(filepath)
  Actions.export_to_markdown(self.tasks, filepath)
end

---Toggle task manager window
-- In core.lua, enhance the toggle function:
function Core:toggle()
  local prev_win_state = Utils.Window.save_state()

  if self._ui_visible then
    self._last_ui_state = {
      cursor = vim.api.nvim_win_get_cursor(0),
      tasks = Utils.deep_copy(self.tasks),
      scroll = vim.fn.winsaveview(),
    }
    UI.close()
    self._ui_visible = false
    Utils.Window.restore_state(prev_win_state)
  else
    self.tasks = self.tasks or {}
    UI.toggle(self.tasks, function(task)
      if task and task.id then
        self:update_task(task.id, task)
        UI.refresh()
        -- self:refresh_ui()
      end
    end, self.config, self._last_ui_state)
    self._ui_visible = true
  end
end

function Core:is_visible()
  return self._ui_visible and UI.is_valid()
end

---Refresh UI display
function Core:refresh_ui()
  if self._ui_visible then
    -- Ensure UI state is properly updated
    UI.toggle(self.tasks, function(task)
      if task and task.id then
        self:update_task(task.id, task)
      end
    end, self.config)
  end
end

---Get all tasks
---@return Task[]
function Core:get_tasks()
  -- Ensure tasks is initialized
  self.tasks = self.tasks or {}
  return Utils.deep_copy(self.tasks)
end

---Search tasks
---@param query string
---@return Task[]
function Core:search(query)
  -- Ensure tasks is initialized
  self.tasks = self.tasks or {}

  if not query or query == "" then
    return {}
  end

  self._last_search = query

  local function matches(task)
    if not task or not task.content then
      return false
    end
    return task.content:lower():find(query:lower()) ~= nil
        or (task.notes and task.notes:lower():find(query:lower()) ~= nil)
  end

  local function search_in_list(tasks)
    if not tasks then
      return {}
    end

    local results = {}
    for _, task in ipairs(tasks) do
      if matches(task) then
        table.insert(results, Utils.deep_copy(task))
      end
      if task.subtasks and #task.subtasks > 0 then
        local subtask_matches = search_in_list(task.subtasks)
        vim.list_extend(results, subtask_matches)
      end
    end
    return results
  end

  return search_in_list(self.tasks)
end

---Get task statistics
---@return table
function Core:get_statistics()
  local stats = {
    total = 0,
    completed = 0,
    pending = 0,
    overdue = 0,
    priority = {
      high = 0,
      medium = 0,
      low = 0,
    },
  }

  local function count_task(task)
    stats.total = stats.total + 1
    if task.status == "done" then
      stats.completed = stats.completed + 1
    else
      stats.pending = stats.pending + 1
      if Task.is_overdue(task) then
        stats.overdue = stats.overdue + 1
      end
    end
    stats.priority[task.priority] = stats.priority[task.priority] + 1

    if task.subtasks then
      for _, subtask in ipairs(task.subtasks) do
        count_task(subtask)
      end
    end
  end

  for _, task in ipairs(self.tasks) do
    count_task(task)
  end

  return stats
end

function Core:get_task_statistics()
  local tasks = self:get_tasks() -- Retrieve all tasks
  local stats = {
    total = 0,
    completed = 0,
    pending = 0,
    overdue = 0,
    high_priority = 0,
    medium_priority = 0,
    low_priority = 0,
  }

  for _, task in ipairs(tasks) do
    stats.total = stats.total + 1

    if task.status == "done" then
      stats.completed = stats.completed + 1
    elseif task.status == "pending" then
      stats.pending = stats.pending + 1
    end

    if Task.is_overdue(task) then
      stats.overdue = stats.overdue + 1
    end

    if task.priority == "high" then
      stats.high_priority = stats.high_priority + 1
    elseif task.priority == "medium" then
      stats.medium_priority = stats.medium_priority + 1
    elseif task.priority == "low" then
      stats.low_priority = stats.low_priority + 1
    end
  end

  return stats
end

--- API Functions

---Cleanup resources
function Core:cleanup()
  -- Ensure tasks is initialized
  self.tasks = self.tasks or {}
  Storage.save(self.tasks)
  UI.close()
end

---Update task
---@param task_id string
---@param fields table
function Core:update_task(task_id, fields)
  Actions.update_task(self.tasks, task_id, fields, function(tasks)
    Storage.save_debounced(tasks)
    self:refresh_ui()
  end)
end

---Delete task
---@param task_id string
function Core:delete_task(task_id)
  Actions.delete_task(self.tasks, task_id, function(tasks)
    Storage.save_debounced(tasks)
    self:refresh_ui()
  end)
end

---Move task up in the list
---@param task_id string
function Core:move_task_up(task_id)
  Actions.move_task_up(self.tasks, task_id, function(tasks)
    Storage.save_debounced(tasks)
    self:refresh_ui()
  end)
end

---Move task down in the list
---@param task_id string
function Core:move_task_down(task_id)
  Actions.move_task_down(self.tasks, task_id, function(tasks)
    Storage.save_debounced(tasks)
    self:refresh_ui()
  end)
end

---Convert task to subtask
---@param task_id string
---@param parent_id string
function Core:convert_to_subtask(task_id, parent_id)
  Actions.convert_to_subtask(self.tasks, task_id, parent_id, function(tasks)
    Storage.save_debounced(tasks)
    self:refresh_ui()
  end)
end

---Sort tasks
---@param criteria string
function Core:sort_tasks(criteria)
  if not criteria then
    return
  end
  self._last_sort = criteria
  Actions.sort_tasks(self.tasks, criteria, function(sorted_tasks)
    self.tasks = sorted_tasks
    self:refresh_ui()
  end)
end

-- Add to Core class
function Core:get_active_tasks()
  local active_tasks = {}
  for _, task in ipairs(self.tasks) do
    if task.status ~= "done" then
      table.insert(active_tasks, {
        content = task.content,
        status = task.status,
        due_date = task.due_date,
        priority = task.priority,
      })
    end
  end
  return active_tasks
end

function Core:toggle_pin_view(position)
  -- Update position if provided
  if position then
    self._pin_position = position
    self._pin_window_state.position = position
  end

  if self._pin_visible then
    UI.close_pin_window()
    self._pin_visible = false
    self._pin_window_state.visible = false
  else
    UI.create_pin_window(self:get_active_tasks(), self._pin_position)
    self._pin_visible = true
    self._pin_window_state.visible = true
    self._pin_window_state.last_update = os.time()
  end
end

function Core:is_pin_visible()
  return self._pin_visible
end

function Core:get_pin_state()
  return {
    visible = self._pin_visible,
    position = self._pin_position,
    last_update = self._pin_window_state.last_update,
  }
end

return Core
