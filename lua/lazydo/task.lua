local M = {}

M.Task = {}
M.Task.__index = M.Task

function M.Task.new(content, opts)
	opts = opts or {}
	local self = setmetatable({}, M.Task)
	self.id = tostring(os.time()) .. math.random(1000, 9999)
	self.content = content
	self.done = false
	self.priority = opts.priority or 2
	self.due_date = opts.due_date
	self.notes = opts.notes
	self.subtasks = {}
	self.indent = opts.indent or 0
	self.created_at = os.time()
	self.updated_at = os.time()
	self.tags = opts.tags or {}
	self.recurrence = opts.recurrence -- daily, weekly, monthly, custom
	self.last_completed = nil
	return self
end

-- Task management methods
function M.Task:update(data)
	for k, v in pairs(data) do
		if k ~= "id" and k ~= "created_at" then
			self[k] = v
		end
	end
	self.updated_at = os.time()
end

function M.Task:toggle()
	self.done = not self.done
	if self.done then
		self.last_completed = os.time()
		-- Handle recurring tasks
		if self.recurrence then
			self:schedule_next_occurrence()
		end
	end
	self.updated_at = os.time()
end

function M.Task:add_subtask(content, opts)
	opts = opts or {}
	opts.indent = self.indent + 1
	local subtask = M.Task.new(content, opts)
	subtask.hidden = true -- Set the hidden property to true by default
	table.insert(self.subtasks, subtask)
	self.updated_at = os.time()
	return subtask
end

function M.Task:remove_subtask(id)
	for i, subtask in ipairs(self.subtasks) do
		if subtask.id == id then
			table.remove(self.subtasks, i)
			self.updated_at = os.time()
			return true
		end
	end
	return false
end

function M.Task:is_overdue()
	return self.due_date and not self.done and self.due_date < os.time()
end

function M.Task:schedule_next_occurrence()
	if not self.recurrence then
		return
	end

	local next_date = os.time()
	if self.recurrence == "daily" then
		next_date = next_date + 86400 -- 24 hours
	elseif self.recurrence == "weekly" then
		next_date = next_date + (7 * 86400)
	elseif self.recurrence == "monthly" then
		-- Approximate month (30 days)
		next_date = next_date + (30 * 86400)
	elseif type(self.recurrence) == "number" then
		-- Custom interval in days
		next_date = next_date + (self.recurrence * 86400)
	end

	self.due_date = next_date
	self.done = false
	self.updated_at = os.time()
end

function M.Task:add_tag(tag)
	if not vim.tbl_contains(self.tags, tag) then
		table.insert(self.tags, tag)
		self.updated_at = os.time()
	end
end

function M.Task:remove_tag(tag)
	for i, t in ipairs(self.tags) do
		if t == tag then
			table.remove(self.tags, i)
			self.updated_at = os.time()
			return true
		end
	end
	return false
end

function M.Task:set_due_date(date)
	self.due_date = date
	self.updated_at = os.time()
end

function M.Task:set_note(note)
	self.notes = note
	self.updated_at = os.time()
end

function M.Task:change_priority(delta)
	self.priority = math.max(1, math.min(3, self.priority + delta))
	self.updated_at = os.time()
end

-- Additional methods to manage hidden subtasks
function M.Task:toggle_subtask_visibility(index)
	if self.subtasks[index] then
		self.subtasks[index].hidden = not self.subtasks[index].hidden
	end
end

function M.Task:get_visible_subtasks()
	local visible_subtasks = {}
	for _, subtask in ipairs(self.subtasks) do
		if not subtask.hidden then
			table.insert(visible_subtasks, subtask)
		end
	end
	return visible_subtasks
end

-- Serialization
function M.Task:serialize()
	return {
		id = self.id,
		content = self.content,
		done = self.done,
		priority = self.priority,
		due_date = self.due_date,
		notes = self.notes,
		subtasks = vim.tbl_map(function(st)
			return st:serialize()
		end, self.subtasks),
		indent = self.indent,
		created_at = self.created_at,
		updated_at = self.updated_at,
		tags = self.tags,
		recurrence = self.recurrence,
		last_completed = self.last_completed,
	}
end

function M.Task.deserialize(data)
	local task = M.Task.new(data.content, {
		priority = data.priority,
		due_date = data.due_date,
		notes = data.notes,
		indent = data.indent,
		tags = data.tags,
		recurrence = data.recurrence,
	})

	task.id = data.id
	task.done = data.done
	task.created_at = data.created_at
	task.updated_at = data.updated_at
	task.last_completed = data.last_completed

	-- Deserialize subtasks
	for _, subtask_data in ipairs(data.subtasks or {}) do
		local subtask = M.Task.deserialize(subtask_data)
		subtask.hidden = true -- Ensure deserialized subtasks are hidden by default
		table.insert(task.subtasks, subtask)
	end

	return task
end

return M
