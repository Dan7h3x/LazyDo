-- core.lua
local Task = require("lazydo.task")
local Storage = require("lazydo.storage")
local Actions = require("lazydo.actions")
local Utils = require("lazydo.utils")
local UI = require("lazydo.ui")
local Kanban = require("lazydo.kanban")

---@class LazyDoCore
---@field public config LazyDoConfig
---@field private tasks Task[]
---@field private _ui_visible boolean
---@field private _last_search string?
---@field private _last_filter table?
---@field private _last_sort string?
---@field private _template_cache table<string, table>
---@field private _reminder_timer any
---@field private _current_view string
local Core = {}
Core.__index = Core

function Core.new(config)
  if not config then
    error("Configuration is required")
  end

  Storage.setup(config)

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
    _last_task_load_time = nil,
    _current_view = config.views and config.views.default_view or "list",
    _pin_window_state = {
      visible = false,
      position = config.pin_window and config.pin_window.position or "topright",
      last_update = os.time(),
    },
  }, Core)

  -- Auto-detect project if configured
  if config.storage.project.auto_detect then
    Storage.auto_detect_project()
  end

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

---Toggle task manager window with improved project storage handling
---@param view? "list"|"kanban" Optional view to open
function Core:toggle(view)
  local prev_win_state = Utils.Window.save_state()

  -- If view is specified, set it as current view
  if view and (view == "list" or view == "kanban") then
    self._current_view = view
  end

  -- Handle closing if UI is visible
  if self._ui_visible then
    -- Save current state before closing
    self._last_ui_state = {
      cursor = vim.api.nvim_win_get_cursor(0),
      scroll = vim.fn.winsaveview(),
      view = self._current_view
    }

    -- Save tasks state immediately to ensure nothing is lost
    local save_success = Storage.save_immediate(self.tasks)
    if not save_success then
      vim.notify("Warning: Failed to save task data when closing window", vim.log.levels.WARN)
    end

    -- Close current view
    if self._current_view == "kanban" then
      Kanban.close()
    else
      UI.close()
    end

    self._ui_visible = false
    Utils.Window.restore_state(prev_win_state)
    return
  end

  -- First check if we have cached tasks that we can use
  local should_load = true

  -- Only load from storage if tasks are empty or not recently loaded
  if self.tasks and #self.tasks > 0 and self._last_task_load_time and
      (os.time() - self._last_task_load_time < 5) then -- Use cached tasks if loaded within last 5 seconds
    should_load = false
  end

  if should_load then
    -- Load tasks with error handling
    local load_ok, loaded_tasks = pcall(Storage.load)

    if load_ok and loaded_tasks then
      self.tasks = loaded_tasks
      self._last_task_load_time = os.time()
    else
      -- If loading fails but we have tasks in memory, preserve them
      if not self.tasks or #self.tasks == 0 then
        vim.notify("Error loading tasks. Initializing with empty task list.", vim.log.levels.WARN)
        self.tasks = {}
      else
        vim.notify("Error loading tasks from storage. Using previously loaded tasks.", vim.log.levels.WARN)
      end
    end
  end

  -- Open the appropriate view with task modification callbacks
  if self._current_view == "kanban" then
    local on_task_update = function(task)
      if task and task.id then
        self:update_task(task.id, task)
        -- Save tasks immediately after any modification
        Storage.save_immediate(self.tasks)
        Kanban.refresh(self.tasks)
      end
    end

    -- local on_task_delete = function(task_id)
    --   if task_id then
    --     self:delete_task(task_id)
    --     -- Save tasks immediately after deletion
    --     Storage.save_immediate(self.tasks)
    --     Kanban.refresh(self.tasks)
    --   end
    -- end

    Kanban.toggle(self.tasks, on_task_update)
  else
    local on_task_update = function(task)
      if task and task.id then
        self:update_task(task.id, task)
        -- Save tasks immediately after any modification
        Storage.save_immediate(self.tasks)
        UI.refresh()
      end
    end

    -- local on_task_delete = function(task_id)
    --   if task_id then
    --     self:delete_task(task_id)
    --     -- Save tasks immediately after deletion
    --     Storage.save_immediate(self.tasks)
    --     UI.refresh()
    --   end
    -- end

    UI.toggle(self.tasks, on_task_update, self.config, self._last_ui_state, self)
  end

  self._ui_visible = true

  -- Get storage status for notification
  if self.config.storage.silent then
    local status = Storage.get_status()
    local mode_str = ""

    if status.selected_storage == "custom" and status.custom_project_name then
      mode_str = "custom project '" .. status.custom_project_name .. "'"
    else
      mode_str = status.mode == "project" and "project" or "global"
    end

    vim.notify("Using " .. mode_str .. " storage: " .. status.current_path, vim.log.levels.INFO)
  end
end

---Toggle between list and kanban view
function Core:toggle_view()
  if not self._ui_visible then
    -- Just set the view for next open
    self._current_view = self._current_view == "list" and "kanban" or "list"
    return
  end

  -- Save current storage mode and tasks
  local storage_status = Storage.get_status()
  local current_tasks = Utils.deep_copy(self.tasks)

  -- Close current view
  if self._current_view == "kanban" then
    Kanban.close()
  else
    UI.close()
  end

  -- Toggle view
  self._current_view = self._current_view == "list" and "kanban" or "list"

  -- Ensure we're using the same storage mode as before
  if storage_status.mode == "project" and not Storage.get_status().project_enabled then
    Storage.toggle_mode("project")
  elseif storage_status.mode == "global" and Storage.get_status().project_enabled then
    Storage.toggle_mode("global")
  end

  -- Ensure we have the latest tasks
  self.tasks = current_tasks

  -- Open new view
  self:toggle()
end

---Get current view
---@return string
function Core:get_current_view()
  return self._current_view
end

function Core:is_visible()
  return self._ui_visible and (
    (self._current_view == "list" and UI.is_valid()) or
    (self._current_view == "kanban" and Kanban.is_valid())
  )
end

---Refresh UI with tasks
---@param tasks? table Optional tasks to use for refresh
function Core:refresh_ui(tasks)
  if tasks then
    self.tasks = tasks
  end

  if not self._ui_visible then
    return
  end

  -- Get latest storage status to ensure UI title is up-to-date
  local status = Storage.get_status()

  if self._current_view == "kanban" then
    Kanban.refresh(self.tasks)
  else
    UI.refresh()
  end

  if self._pin_window_state.visible then
    self:update_pin_window()
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

  local storage = UI:get_storage_mode_info()
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

  return stats, storage
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

---Update a task by ID and save immediately
---@param task_id string
---@param fields table
function Core:update_task(task_id, fields)
  Actions.update_task(self.tasks, task_id, fields, function(tasks)
    -- First save immediately to ensure data is not lost
    local immediate_save_success = Storage.save_immediate(tasks)
    if not immediate_save_success then
      vim.notify("Warning: Failed to save task update immediately", vim.log.levels.WARN)
    end

    -- Then schedule a debounced save as a backup
    Storage.save_debounced(tasks)

    -- Refresh the UI
    self:refresh_ui()
  end)
end

---Delete task and save immediately
---@param task_id string
function Core:delete_task(task_id)
  Actions.delete_task(self.tasks, task_id, function(tasks)
    -- First save immediately to ensure data is not lost
    local immediate_save_success = Storage.save_immediate(tasks)
    if not immediate_save_success then
      vim.notify("Warning: Failed to save task deletion immediately", vim.log.levels.WARN)
    end

    -- Then schedule a debounced save as a backup
    Storage.save_debounced(tasks)

    -- Refresh the UI
    self:refresh_ui()
  end)
end

---Add a new task and save immediately
---@param content string Task content
---@param opts? table Optional task properties
---@return Task? The created task
function Core:add_task(content, opts)
  if not content or content == "" then
    vim.notify("Task content cannot be empty", vim.log.levels.WARN)
    return nil
  end

  local task = Actions.add_task(self.tasks, content, opts or {}, function(tasks)
    -- First save immediately to ensure data is not lost
    local immediate_save_success = Storage.save_immediate(tasks)
    if not immediate_save_success then
      vim.notify("Warning: Failed to save new task immediately", vim.log.levels.WARN)
    end

    -- Then schedule a debounced save as a backup
    Storage.save_debounced(tasks)

    -- Refresh the UI
    self:refresh_ui()
  end)

  return task
end

---Move task up in the list and save immediately
---@param task_id string
function Core:move_task_up(task_id)
  Actions.move_task_up(self.tasks, task_id, function(tasks)
    -- First save immediately to ensure data is not lost
    local immediate_save_success = Storage.save_immediate(tasks)
    if not immediate_save_success then
      vim.notify("Warning: Failed to save task move immediately", vim.log.levels.WARN)
    end

    -- Then schedule a debounced save as a backup
    Storage.save_debounced(tasks)

    -- Refresh the UI
    self:refresh_ui()
  end)
end

---Move task down in the list and save immediately
---@param task_id string
function Core:move_task_down(task_id)
  Actions.move_task_down(self.tasks, task_id, function(tasks)
    -- First save immediately to ensure data is not lost
    local immediate_save_success = Storage.save_immediate(tasks)
    if not immediate_save_success then
      vim.notify("Warning: Failed to save task move immediately", vim.log.levels.WARN)
    end

    -- Then schedule a debounced save as a backup
    Storage.save_debounced(tasks)

    -- Refresh the UI
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

---Toggle storage mode with UI refresh
---@param mode? "project"|"global"|"auto"|"custom" Optional mode to set directly
function Core:toggle_storage_mode(mode)
  -- Save current tasks before switching
  local current_tasks = self.tasks

  -- Get current status to detect changes
  local prev_status = Storage.get_status()

  -- Toggle storage mode
  local is_project = Storage.toggle_mode(mode)

  -- Get new status after toggling
  local new_status = Storage.get_status()

  -- If storage didn't change (user cancelled), don't reload tasks
  if prev_status.current_path == new_status.current_path and
      prev_status.selected_storage == new_status.selected_storage and
      prev_status.custom_project_name == new_status.custom_project_name then
    return is_project
  end

  -- Reload tasks from new storage location
  local load_ok, loaded_tasks = pcall(Storage.load)

  if load_ok and loaded_tasks then
    -- Update tasks with new storage data
    self.tasks = loaded_tasks

    -- Process task relations to ensure they're properly maintained
    -- Loop through all tasks to fix any potential relation issues
    for _, task in ipairs(self.tasks) do
      if task.relations then
        for i = #task.relations, 1, -1 do
          local relation = task.relations[i]
          -- Check if related task still exists
          local target_exists = false
          for _, potential_target in ipairs(self.tasks) do
            if potential_target.id == relation.target_id then
              target_exists = true
              break
            end
          end
          -- Remove relation if target doesn't exist in new storage
          if not target_exists then
            table.remove(task.relations, i)
          end
        end
      end
    end

    -- Refresh UI if visible
    if self._ui_visible then
      if self._current_view == "kanban" then
        Kanban.refresh(self.tasks)
      else
        UI.refresh()
      end

      -- Get storage status for notification
      local status = Storage.get_status()
      local mode_str

      if status.selected_storage == "custom" and status.custom_project_name then
        mode_str = "custom project '" .. status.custom_project_name .. "'"
      else
        mode_str = status.mode == "project" and "project" or "global"
      end

      vim.notify("Switched to " .. mode_str .. " storage: " .. status.current_path, vim.log.levels.INFO)
    end
  else
    -- Handle loading error
    vim.notify("Error loading tasks from new storage. Would you like to initialize with empty task list?",
      vim.log.levels.WARN)

    -- Prompt for initialization
    vim.ui.select({ "Yes", "No" }, {
      prompt = "Initialize with empty task list?"
    }, function(choice)
      if choice == "Yes" then
        -- Initialize with empty task list
        self.tasks = {}

        -- Save empty task list to new storage
        pcall(Storage.save_immediate, self.tasks)

        -- Refresh UI if visible
        if self._ui_visible then
          if self._current_view == "kanban" then
            Kanban.refresh(self.tasks)
          else
            UI.refresh()
          end
        end
      else
        -- Revert to previous storage mode
        local revert_mode = prev_status.mode == "project" and "global" or "project"
        local revert_ok = pcall(Storage.toggle_mode, revert_mode)
        if revert_ok then
          vim.notify("Reverted to previous storage mode", vim.log.levels.INFO)
        end

        -- Restore original tasks
        self.tasks = current_tasks

        -- Refresh UI if visible
        if self._ui_visible then
          if self._current_view == "kanban" then
            Kanban.refresh(self.tasks)
          else
            UI.refresh()
          end
        end
      end
    end)
  end

  -- Update and refresh pin window if visible
  if self._pin_visible then
    self:update_pin_window()
  end

  return is_project
end

---Reload tasks from current storage
---@return table tasks The loaded tasks
function Core:reload_tasks()
  local load_ok, loaded_tasks = pcall(Storage.load)

  if load_ok and loaded_tasks then
    self.tasks = loaded_tasks
  end

  return self.tasks
end

---Get storage status
---@return table status Storage status information
function Core:get_storage_status()
  return Storage.get_status()
end

---Open task manager window in the specified view
---@param view? "list"|"kanban" Optional view to open
function Core:open(view)
  -- If already visible, just refresh
  if self._ui_visible then
    if view and self._current_view ~= view then
      -- Switch to specified view if different
      self._current_view = view
      self:refresh_ui()
    else
      -- Just refresh current view
      self:refresh_ui()
    end
    return
  end

  -- If view is specified, set it as current view
  if view and (view == "list" or view == "kanban") then
    self._current_view = view
  end

  -- Load tasks if needed
  local should_load = true
  if self.tasks and #self.tasks > 0 and self._last_task_load_time and
      (os.time() - self._last_task_load_time < 5) then
    should_load = false
  end

  if should_load then
    local load_ok, loaded_tasks = pcall(Storage.load)
    if load_ok and loaded_tasks then
      self.tasks = loaded_tasks
      self._last_task_load_time = os.time()
    else
      if not self.tasks or #self.tasks == 0 then
        vim.notify("Error loading tasks. Initializing with empty task list.", vim.log.levels.WARN)
        self.tasks = {}
      else
        vim.notify("Error loading tasks from storage. Using previously loaded tasks.", vim.log.levels.WARN)
      end
    end
  end

  -- Open appropriate view
  if self._current_view == "kanban" then
    local on_task_update = function(task)
      if task and task.id then
        self:update_task(task.id, task)
        Storage.save_immediate(self.tasks)
        Kanban.refresh(self.tasks)
      end
    end

    Kanban.toggle(self.tasks, on_task_update, self.config)
  else
    local on_task_update = function(task)
      if task and task.id then
        self:update_task(task.id, task)
        Storage.save_immediate(self.tasks)
        UI.refresh()
      end
    end

    UI.toggle(self.tasks, on_task_update, self.config, self._last_ui_state, self)
  end

  self._ui_visible = true

  -- Get storage status for notification
  local status = Storage.get_status()
  local mode_str = status.selected_storage == "custom" and status.custom_project_name
      and "custom project '" .. status.custom_project_name .. "'"
      or (status.mode == "project" and "project" or "global")

  vim.notify("Using " .. mode_str .. " storage: " .. status.current_path, vim.log.levels.INFO)
end

---Close task manager window
function Core:close()
  if not self._ui_visible then
    return
  end

  -- Save current state before closing
  self._last_ui_state = {
    cursor = vim.api.nvim_win_get_cursor(0),
    scroll = vim.fn.winsaveview(),
    view = self._current_view
  }

  -- Save tasks state immediately
  local save_success = Storage.save_immediate(self.tasks)
  if not save_success then
    vim.notify("Warning: Failed to save task data when closing window", vim.log.levels.WARN)
  end

  -- Close current view
  if self._current_view == "kanban" then
    Kanban.close()
  else
    UI.close()
  end

  self._ui_visible = false
end

---Clear storage data with selection UI
---@param mode? "auto"|"global"|"project"|"custom" Optional mode to target specific storage
---@return boolean success Whether the operation was successful
function Core:clear_storage(mode)
  local success, result = pcall(function()
    return Storage.clear_storage(mode)
  end)

  if not success then
    return false
  end

  -- If we cleared the current storage, reload tasks
  if result then
    -- Reload tasks from storage
    local load_ok, loaded_tasks = pcall(Storage.load)
    if load_ok and loaded_tasks then
      self.tasks = loaded_tasks
      self._last_task_load_time = os.time()
      
      -- Refresh UI if visible
      if self._ui_visible then
        if self._current_view == "kanban" then
          Kanban.refresh(self.tasks)
        else
          UI.refresh()
        end
      end
    end
  end

  return result
end

return Core
