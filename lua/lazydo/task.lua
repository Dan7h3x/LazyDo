-- task.lua
local Utils = require("lazydo.utils")

---@class Task
---@field id string Unique identifier
---@field content string Task content
---@field status "pending"|"in_progress"|"blocked"|"done"|"cancelled" Task status
---@field priority "urgent"|"high"|"medium"|"low" Task priority
---@field due_date? number Due date timestamp
---@field notes? string Additional notes
---@field subtasks Task[] List of subtasks
---@field created_at number Creation timestamp
---@field updated_at number Last update timestamp
---@field parent_id? string Parent task ID
---@field collapsed boolean Whether subtasks are hidden
---@field tags string[] Task tags
---@field metadata table Additional metadata
---@field attachments Attachment[] List of attachments
---@field relations Relation[] Task relations
---@field reminders Reminder[] Task reminders
---@field template? string Template name used
local Task = {}

---@class Attachment
---@field id string Unique identifier
---@field name string File name
---@field path string File path
---@field type string MIME type
---@field size number File size in bytes
---@field created_at number Creation timestamp

---@class Relation
---@field type string Relation type (blocks|depends_on|related_to|duplicates)
---@field target_id string Related task ID
---@field metadata? table Additional relation metadata

---@class Reminder
---@field id string Unique identifier
---@field time number Reminder timestamp
---@field offset table Notification offset
---@field urgency string Priority level
---@field message? string Custom reminder message

---Create new task
---@param content string
---@param opts? table
---@return Task
function Task.new(content, opts)
  opts = opts or {}
  return {
    id = Utils.generate_id(),
    content = content,
    status = opts.status or "pending",
    priority = opts.priority or "medium",
    due_date = opts.due_date,
    notes = opts.notes,
    subtasks = opts.subtasks or {},
    created_at = os.time(),
    updated_at = os.time(),
    parent_id = opts.parent_id,
    collapsed = false,
    tags = opts.tags or {},
    metadata = opts.metadata or {},
  }
end

---Update task fields
---@param task Task
---@param fields table
---@return Task
function Task.update(task, fields)
  local updated = Utils.deep_copy(task)
  for k, v in pairs(fields) do
    if k ~= "id" and k ~= "created_at" then
      updated[k] = v
    end
  end
  updated.updated_at = os.time()
  return updated
end

-- Add new helper functions
function Task.toggle_collapsed(task)
  task.collapsed = not task.collapsed
end

function Task.add_tag(task, tag)
  task.tags = task.tags or {}
  if not vim.tbl_contains(task.tags, tag) then
    table.insert(task.tags, tag)
  end
end

function Task.remove_tag(task, tag)
  if task.tags then
    for i, t in ipairs(task.tags) do
      if t == tag then
        table.remove(task.tags, i)
        break
      end
    end
  end
end

function Task.set_metadata(task, key, value)
  task.metadata = task.metadata or {}
  task.metadata[key] = value
end

-- Enhance progress calculation
function Task.calculate_progress(task)
  if not task.subtasks or #task.subtasks == 0 then
    return task.status == "done" and 100 or 0
  end

  local total_weight = 0
  local completed_weight = 0

  for _, subtask in ipairs(task.subtasks) do
    local weight = subtask.priority == "high" and 3 or subtask.priority == "medium" and 2 or 1
    total_weight = total_weight + weight

    if subtask.status == "done" then
      completed_weight = completed_weight + weight
    elseif subtask.subtasks and #subtask.subtasks > 0 then
      completed_weight = completed_weight + (Task.calculate_progress(subtask) / 100 * weight)
    end
  end

  return math.floor((completed_weight / total_weight) * 100)
end

---Check if task is overdue
---@param task Task
---@return boolean
function Task.is_overdue(task)
  if not task.due_date then
    return false
  end
  return os.time() > task.due_date
end

---Check if task is due today
---@param task Task
---@return boolean
function Task.is_due_today(task)
  if not task.due_date then
    return false
  end

  -- Get today's start and end timestamps
  local today = os.date("*t")
  today.hour = 0
  today.min = 0
  today.sec = 0
  local day_start = os.time(today)

  today.hour = 23
  today.min = 59
  today.sec = 59
  local day_end = os.time(today)

  -- Check if due_date falls within today
  return task.due_date >= day_start and task.due_date <= day_end
end

---Get task due date as relative string
---@param task Task
---@return string
function Task.get_due_date_relative(task)
  if not task.due_date then
    return ""
  end
  return Utils.Date.relative(task.due_date)
end

---Convert task to string representation
---@param task Task
---@return string
function Task.to_string(task)
  local status = task.status == "done" and "✓" or "□"
  local priority = string.format("[%s]", task.priority:sub(1, 1):upper())
  local due = task.due_date and " due:" .. Task.get_due_date_relative(task) or ""

  return string.format("%s %s %s%s", status, priority, task.content, due)
end

function Task.set_recurring(task, pattern)
  task.recurring = pattern      -- "daily", "weekly", "monthly"
  task.next_due = task.due_date -- Store original due date
end

function Task.clone(task)
  local new_task = Utils.deep_copy(task)
  new_task.id = Utils.generate_id()
  new_task.created_at = os.time()
  new_task.updated_at = os.time()
  return new_task
end

function Task.filter_by_status(tasks, status)
  return vim.tbl_filter(function(task)
    return task.status == status
  end, tasks)
end

function Task.filter_by_priority(tasks, priority)
  return vim.tbl_filter(function(task)
    return task.priority == priority
  end, tasks)
end

function Task.filter_by_date_range(tasks, start_date, end_date)
  return vim.tbl_filter(function(task)
    if not task.due_date then
      return false
    end
    return task.due_date >= start_date and task.due_date <= end_date
  end, tasks)
end

function Task.filter_by_tag(tasks, tag)
  return vim.tbl_filter(function(task)
    return task.tags and vim.tbl_contains(task.tags, tag)
  end, tasks)
end

-- Add new task sorting methods
function Task.sort_by_priority(tasks)
  local priority_order = { urgent = 0, high = 1, medium = 2, low = 3 }
  table.sort(tasks, function(a, b)
    -- First compare priority
    if priority_order[a.priority] ~= priority_order[b.priority] then
      return priority_order[a.priority] < priority_order[b.priority]
    end
    -- Then compare due dates if priorities are equal
    if a.due_date and b.due_date then
      return a.due_date < b.due_date
    end
    -- Tasks with due dates come before tasks without
    return a.due_date and not b.due_date
  end)

  -- Sort subtasks recursively
  for _, task in ipairs(tasks) do
    if task.subtasks and #task.subtasks > 0 then
      Task.sort_by_priority(task.subtasks)
    end
  end

  return tasks
end

function Task.sort_by_due_date(tasks)
  table.sort(tasks, function(a, b)
    -- Tasks with due dates come first
    if a.due_date and not b.due_date then
      return true
    end
    if not a.due_date and b.due_date then
      return false
    end
    if not a.due_date and not b.due_date then
      -- If no due dates, sort by priority
      local priority_order = { urgent = 0, high = 1, medium = 2, low = 3 }
      return priority_order[a.priority] < priority_order[b.priority]
    end
    -- Compare due dates
    return a.due_date < b.due_date
  end)

  -- Sort subtasks recursively
  for _, task in ipairs(tasks) do
    if task.subtasks and #task.subtasks > 0 then
      Task.sort_by_due_date(task.subtasks)
    end
  end

  return tasks
end

function Task.sort_by_status(tasks)
  local status_order = { pending = 1, in_progress = 2, blocked = 3, done = 4 }
  table.sort(tasks, function(a, b)
    return status_order[a.status] < status_order[b.status]
  end)
  return tasks
end

-- Add task grouping methods
function Task.group_by_status(tasks)
  local groups = {}
  for _, task in ipairs(tasks) do
    groups[task.status] = groups[task.status] or {}
    table.insert(groups[task.status], task)
  end
  return groups
end

function Task.group_by_priority(tasks)
  local groups = {}
  for _, task in ipairs(tasks) do
    groups[task.priority] = groups[task.priority] or {}
    table.insert(groups[task.priority], task)
  end
  return groups
end

-- Add task statistics methods
function Task.get_statistics(tasks)
  local stats = {
    total = #tasks,
    completed = 0,
    pending = 0,
    overdue = 0,
    high_priority = 0,
    has_notes = 0,
    has_subtasks = 0,
  }

  for _, task in ipairs(tasks) do
    if task.status == "done" then
      stats.completed = stats.completed + 1
    end
    if task.status == "pending" then
      stats.pending = stats.pending + 1
    end
    if Task.is_overdue(task) then
      stats.overdue = stats.overdue + 1
    end
    if task.priority == "high" then
      stats.high_priority = stats.high_priority + 1
    end
    if task.notes then
      stats.has_notes = stats.has_notes + 1
    end
    if task.subtasks and #task.subtasks > 0 then
      stats.has_subtasks = stats.has_subtasks + 1
    end
  end

  return stats
end

-- Add attachment to task
---@param task Task
---@param file_path string
---@return boolean success
---@return string? error
function Task.add_attachment(task, file_path)
  if not task.attachments then
    task.attachments = {}
  end

  -- Validate file
  local file_info = vim.loop.fs_stat(file_path)
  if not file_info then
    return false, "File not found"
  end

  -- Check file size
  if file_info.size > config.features.attachments.max_size then
    return false, "File too large"
  end

  -- Create attachment
  local attachment = {
    id = Utils.generate_id(),
    name = vim.fn.fnamemodify(file_path, ":t"),
    path = file_path,
    type = vim.fn.system("file --mime-type -b " .. vim.fn.shellescape(file_path)):gsub("\n", ""),
    size = file_info.size,
    created_at = os.time(),
  }

  table.insert(task.attachments, attachment)
  return true
end

-- Add relation between tasks
---@param task Task
---@param target_id string
---@param relation_type string
function Task.add_relation(task, target_id, relation_type)
  if not task.relations then
    task.relations = {}
  end

  -- Define default relation types if config is not available
  local valid_relation_types = {
    "blocks",
    "depends_on",
    "related_to",
    "duplicates",
  }

  -- Validate relation type
  if not vim.tbl_contains(valid_relation_types, relation_type) then
    return false, "Invalid relation type"
  end

  -- Check for existing relation to prevent duplicates
  for _, rel in ipairs(task.relations) do
    if rel.target_id == target_id and rel.type == relation_type then
      return false, "Relation already exists"
    end
  end

  local relation = {
    type = relation_type,
    target_id = target_id,
    metadata = {},
  }

  table.insert(task.relations, relation)
  return true
end

-- Add helper function to get relation types
function Task.get_relation_types()
  return {
    "blocks",
    "depends_on",
    "related_to",
    "duplicates",
  }
end

-- Add helper function to validate relation type
function Task.is_valid_relation_type(relation_type)
  return vim.tbl_contains(Task.get_relation_types(), relation_type)
end

-- Add reminder to task
---@param task Task
---@param time number
---@param offset table
---@param urgency string
---@param message? string
function Task.add_reminder(task, time, offset, urgency, message)
  if not task.reminders then
    task.reminders = {}
  end

  local reminder = {
    id = Utils.generate_id(),
    time = time,
    offset = offset,
    urgency = urgency,
    message = message,
  }

  table.insert(task.reminders, reminder)
  return true
end

-- -- Apply template to task
-- ---@param task Task
-- ---@param template_name string
-- function Task.apply_template(task, template_name)
-- 	local template_path = config.features.templates.path .. "/" .. template_name .. ".json"
-- 	local template = Utils.read_json_file(template_path)
--
-- 	if template then
-- 		-- Merge template data with task
-- 		for k, v in pairs(template) do
-- 			if k ~= "id" and k ~= "created_at" then
-- 				task[k] = v
-- 			end
-- 		end
-- 		task.template = template_name
-- 		return true
-- 	end
-- 	return false
-- end

-- Update task workflow status
-- @param task Task
-- @param new_status string
-- function Task.update_status(task, new_status)
-- 	if not config.features.workflow.enabled then
-- 		task.status = new_status
-- 		return true
-- 	end
--
-- 	-- Validate status transition
-- 	local allowed_transitions = config.features.workflow.transitions[task.status]
-- 	if not allowed_transitions or not vim.tbl_contains(allowed_transitions, new_status) then
-- 		return false, "Invalid status transition"
-- 	end
--
-- 	task.status = new_status
-- 	task.updated_at = os.time()
-- 	return true
-- end

-- Check if task has active reminders
---@param task Task
---@return boolean
function Task.has_active_reminders(task)
  if not task.reminders then
    return false
  end

  local now = os.time()
  for _, reminder in ipairs(task.reminders) do
    if reminder.time > now then
      return true
    end
  end
  return false
end

-- Get task urgency level
---@param task Task
---@return string
function Task.get_urgency_level(task)
  if task.priority == "urgent" then
    return "critical"
  elseif task.priority == "high" then
    return "high"
  elseif task.priority == "medium" then
    return "normal"
  else
    return "low"
  end
end

return Task
