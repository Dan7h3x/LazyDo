-- actions.lua
local Utils = require("lazydo.utils")
local Task = require("lazydo.task")

---@class Actions
local Actions = {}

-- Task Management Actions
function Actions.add_task(tasks, content, opts, on_update)
  if not content or content == "" then
    vim.notify("Task content cannot be empty", vim.log.levels.WARN)
    return nil
  end

  local task = Task.new(content, opts)
  table.insert(tasks, task)

  if on_update then
    on_update(tasks)
  end

  return task
end

function Actions.update_task(tasks, task_id, fields, on_update)
  if not task_id or not fields then
    return
  end

  local function update_in_list(tasks_list)
    for i, task in ipairs(tasks_list) do
      if task.id == task_id then
        tasks_list[i] = Task.update(task, fields)
        return true
      end
      if task.subtasks and #task.subtasks > 0 then
        if update_in_list(task.subtasks) then
          return true
        end
      end
    end
    return false
  end

  if update_in_list(tasks) and on_update then
    on_update(tasks)
  end
end

function Actions.toggle_pin(tasks, task_id, on_update)
  local function toggle_in_list(tasks_list)
    for _, task in ipairs(tasks_list) do
      if task.id == task_id then
        task.pinned = not task.pinned
        task.updated_at = os.time()
        return true
      end
      if task.subtasks and #task.subtasks > 0 then
        if toggle_in_list(task.subtasks) then
          return true
        end
      end
    end
    return false
  end

  if toggle_in_list(tasks) and on_update then
    on_update(tasks)
  end
end

function Actions.delete_task(tasks, task_id, on_update)
  if not task_id then
    return
  end

  local function remove_from_list(tasks_list)
    for i, task in ipairs(tasks_list) do
      if task.id == task_id then
        table.remove(tasks_list, i)
        return true
      end
      if task.subtasks and #task.subtasks > 0 then
        if remove_from_list(task.subtasks) then
          return true
        end
      end
    end
    return false
  end

  if remove_from_list(tasks) and on_update then
    on_update(tasks)
  end
end

-- Task Movement Actions
function Actions.move_task_up(tasks, task_id, on_update)
  local function move_up_in_list(tasks_list)
    for i, task in ipairs(tasks_list) do
      if task.id == task_id and i > 1 then
        tasks_list[i], tasks_list[i - 1] = tasks_list[i - 1], tasks_list[i]
        return true
      end
      if task.subtasks and #task.subtasks > 0 then
        if move_up_in_list(task.subtasks) then
          return true
        end
      end
    end
    return false
  end

  if move_up_in_list(tasks) and on_update then
    on_update(tasks)
  end
end

function Actions.move_task_down(tasks, task_id, on_update)
  local function move_down_in_list(tasks_list)
    for i, task in ipairs(tasks_list) do
      if task.id == task_id and i < #tasks_list then
        tasks_list[i], tasks_list[i + 1] = tasks_list[i + 1], tasks_list[i]
        return true
      end
      if task.subtasks and #task.subtasks > 0 then
        if move_down_in_list(task.subtasks) then
          return true
        end
      end
    end
    return false
  end

  if move_down_in_list(tasks) and on_update then
    on_update(tasks)
  end
end

-- function Actions.filter_tasks(tasks, criteria, on_update)
-- 	if not criteria then
-- 		return tasks
-- 	end
--
-- 	local filtered = tasks
-- 	if criteria.status then
-- 		filtered = Task.filter_by_status(filtered, criteria.status)
-- 	end
-- 	if criteria.priority then
-- 		filtered = Task.filter_by_priority(filtered, criteria.priority)
-- 	end
-- 	if criteria.date_range then
-- 		filtered = Task.filter_by_date_range(filtered, criteria.date_range.start, criteria.date_range.finish)
-- 	end
-- 	if criteria.tag then
-- 		filtered = Task.filter_by_tag(filtered, criteria.tag)
-- 	end
--
-- 	if on_update then
-- 		on_update(filtered)
-- 	end
-- 	return filtered
-- end

-- Add new sort actions
function Actions.sort_tasks(tasks, criteria, on_update)
  if not criteria then
    return tasks
  end

  local sorted = vim.deepcopy(tasks)
  if criteria == "priority" then
    Task.sort_by_priority(sorted)
  elseif criteria == "due_date" then
    Task.sort_by_due_date(sorted)
  elseif criteria == "status" then
    Task.sort_by_status(sorted)
  end

  if on_update then
    on_update(sorted)
  end
  return sorted
end

function Actions.set_reccuring(tasks, pattern)
  if not pattern then
    return
  end
  Task.set_recurring(tasks, pattern)
end

-- Add new group actions
function Actions.group_tasks(tasks, criteria, on_update)
  if not criteria then
    return tasks
  end

  local grouped
  if criteria == "status" then
    grouped = Task.group_by_status(tasks)
  elseif criteria == "priority" then
    grouped = Task.group_by_priority(tasks)
  end

  if on_update then
    on_update(grouped)
  end
  return grouped
end

-- Task Hierarchy Actions
function Actions.convert_to_subtask(tasks, task_id, parent_id, on_update)
  local function find_task(tasks_list, id)
    for _, task in ipairs(tasks_list) do
      if task.id == id then
        return task
      end
      if task.subtasks and #task.subtasks > 0 then
        local found = find_task(task.subtasks, id)
        if found then
          return found
        end
      end
    end
    return nil
  end

  local function remove_task(tasks_list, id)
    for i, task in ipairs(tasks_list) do
      if task.id == id then
        return table.remove(tasks_list, i)
      end
      if task.subtasks and #task.subtasks > 0 then
        local removed = remove_task(task.subtasks, id)
        if removed then
          return removed
        end
      end
    end
    return nil
  end

  local task_to_move = find_task(tasks, task_id)
  local parent_task = find_task(tasks, parent_id)

  if task_to_move and parent_task then
    remove_task(tasks, task_id)
    parent_task.subtasks = parent_task.subtasks or {}
    table.insert(parent_task.subtasks, task_to_move)
    if on_update then
      on_update(tasks)
    end
  end
end

function Actions.promote_subtask(tasks, task_id, on_update)
  local function find_parent_and_task(tasks_list, id, parent)
    for i, task in ipairs(tasks_list) do
      if task.id == id then
        return parent, i
      end
      if task.subtasks and #task.subtasks > 0 then
        local p, idx = find_parent_and_task(task.subtasks, id, task)
        if p then
          return p, idx
        end
      end
    end
    return nil, nil
  end

  local parent, index = find_parent_and_task(tasks, task_id)
  if parent and index then
    local task = table.remove(parent.subtasks, index)
    table.insert(tasks, task)
    if on_update then
      on_update(tasks)
    end
  end
end

-- Task Status Actions
function Actions.toggle_status(tasks, task_id, on_update)
  local function toggle_in_list(tasks_list)
    for _, task in ipairs(tasks_list) do
      if task.id == task_id then
        task.status = task.status == "done" and "pending" or "done"
        return true
      end
      if task.subtasks and #task.subtasks > 0 then
        if toggle_in_list(task.subtasks) then
          return true
        end
      end
    end
    return false
  end

  if toggle_in_list(tasks) and on_update then
    on_update(tasks)
  end
end

function Actions.toggle_subtasks_status(tasks, task_id, on_update)
  local function find_and_toggle(tasks_list)
    for _, task in ipairs(tasks_list) do
      if task.id == task_id then
        local new_status = task.status == "done" and "pending" or "done"
        task.status = new_status
        if task.subtasks then
          for _, subtask in ipairs(task.subtasks) do
            subtask.status = new_status
          end
        end
        return true
      end
      if task.subtasks and #task.subtasks > 0 then
        if find_and_toggle(task.subtasks) then
          return true
        end
      end
    end
    return false
  end

  if find_and_toggle(tasks) and on_update then
    on_update(tasks)
  end
end

-- Task Priority Actions
function Actions.cycle_priority(tasks, task_id, on_update)
  local priorities = { "low", "medium", "high" }

  local function cycle_in_list(tasks_list)
    for _, task in ipairs(tasks_list) do
      if task.id == task_id then
        local current_index = vim.tbl_contains(priorities, task.priority)
            and vim.fn.index(priorities, task.priority) + 1
            or 0
        task.priority = priorities[(current_index % 3) + 1]
        return true
      end
      if task.subtasks and #task.subtasks > 0 then
        if cycle_in_list(task.subtasks) then
          return true
        end
      end
    end
    return false
  end

  if cycle_in_list(tasks) and on_update then
    on_update(tasks)
  end
end

-- Task Due Date Actions
function Actions.set_due_date(tasks, task_id, date_str, on_update)
  local function set_in_list(tasks_list)
    for _, task in ipairs(tasks_list) do
      if task.id == task_id then
        if date_str == "" then
          task.due_date = nil
        else
          local timestamp = Utils.Date.parse(date_str)
          if timestamp then
            task.due_date = timestamp
            task.updated_at = os.time()
          else
            vim.notify(
              "Invalid date format. Use YYYY-MM-DD, MM/DD, Nd, Nw, or keywords (today, tomorrow, next week, next month)",
              vim.log.levels.WARN)
            return false
          end
        end
        return true
      end
      if task.subtasks and #task.subtasks > 0 then
        if set_in_list(task.subtasks) then
          return true
        end
      end
    end
    return false
  end

  if set_in_list(tasks) and on_update then
    on_update(tasks)
  end
end

function Actions.delete_note(tasks, task_id, on_update)
  local function delete_from_list(tasks_list)
    for _, task in ipairs(tasks_list) do
      if task.id == task_id then
        task.notes = nil
        return true
      end
      if task.subtasks and #task.subtasks > 0 then
        if delete_from_list(task.subtasks) then
          return true
        end
      end
    end
    return false
  end
  if delete_from_list(tasks) and on_update then
    on_update(tasks)
  end
end

-- Task Notes Actions
function Actions.set_notes(tasks, task_id, notes, on_update)
  local function set_in_list(tasks_list)
    for _, task in ipairs(tasks_list) do
      if task.id == task_id then
        task.notes = notes ~= "" and notes or nil
        return true
      end
      if task.subtasks and #task.subtasks > 0 then
        if set_in_list(task.subtasks) then
          return true
        end
      end
    end
    return false
  end

  if set_in_list(tasks) and on_update then
    on_update(tasks)
  end
end

-- Task Export Actions
function Actions.export_to_markdown(tasks, filepath)
  local function task_to_markdown(task, level)
    local indent = string.rep("  ", level)
    local status = task.status == "done" and "x" or " "
    local priority = string.format("[%s]", task.priority:sub(1, 1):upper())
    local due = task.due_date and " due:" .. Utils.Date.format(task.due_date) or ""
    local notes = task.notes and "\n" .. indent .. "  > " .. task.notes or ""

    local lines = {
      string.format("%s- [%s] %s %s%s%s", indent, status, priority, task.content, due, notes),
    }

    if task.subtasks and #task.subtasks > 0 then
      for _, subtask in ipairs(task.subtasks) do
        vim.list_extend(lines, task_to_markdown(subtask, level + 1))
      end
    end

    return lines
  end

  local lines = {
    "# Tasks",
    "Generated by LazyDo on " .. os.date("%Y-%m-%d %H:%M:%S"),
    "",
  }

  for _, task in ipairs(tasks) do
    vim.list_extend(lines, task_to_markdown(task, 0))
  end

  vim.fn.writefile(lines, filepath)
end

-- Task Filter Actions
-- function Actions.filter_tasks(tasks, criteria, on_update)
-- 	local function matches_filter(task)
-- 		if criteria.status and task.status ~= criteria.status then
-- 			return false
-- 		end
-- 		if criteria.priority and task.priority ~= criteria.priority then
-- 			return false
-- 		end
-- 		if criteria.due_date then
-- 			if not task.due_date then
-- 				return false
-- 			end
-- 			local now = os.time()
-- 			if criteria.due_date == "overdue" and task.due_date > now then
-- 				return false
-- 			elseif criteria.due_date == "today" and not Utils.Date.is_same_day(task.due_date, now) then
-- 				return false
-- 			elseif criteria.due_date == "upcoming" and task.due_date <= now then
-- 				return false
-- 			end
-- 		end
-- 		return true
-- 	end
--
-- 	local filtered = vim.tbl_filter(matches_filter, Utils.deep_copy(tasks))
-- 	if on_update then
-- 		on_update(filtered)
-- 	end
-- 	return filtered
-- end

-- Task Sort Actions
-- function Actions.sort_tasks(tasks, criteria, on_update)
-- 	local function compare(a, b)
-- 		if criteria == "priority" then
-- 			local priority_order = { high = 1, medium = 2, low = 3 }
-- 			return priority_order[a.priority] < priority_order[b.priority]
-- 		elseif criteria == "due_date" then
-- 			if not a.due_date and not b.due_date then
-- 				return false
-- 			end
-- 			if not a.due_date then
-- 				return false
-- 			end
-- 			if not b.due_date then
-- 				return true
-- 			end
-- 			return a.due_date < b.due_date
-- 		elseif criteria == "created_at" then
-- 			return a.created_at < b.created_at
-- 		end
-- 		return false
-- 	end
--
-- 	table.sort(tasks, compare)
-- 	if on_update then
-- 		on_update(tasks)
-- 	end
-- end

return Actions
