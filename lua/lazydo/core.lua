local LazyDo = {}
local utils = require("lazydo.utils")
local ui = require("lazydo.ui")
local storage = require("lazydo.storage")
local Tasker = require("lazydo.task")
local config = require("lazydo.config")




-- Core functionality and state management
LazyDo.instance = nil
LazyDo.is_visible = false
LazyDo.is_processing = false
LazyDo.is_ui_busy = false

function LazyDo:new()
	local instance = setmetatable({}, { __index = LazyDo })
	instance.tasks = {}
	instance.buf = nil
	instance.win = nil
	instance.help_win = nil
	instance.help_buf = nil
	instance.ns = {
		render = vim.api.nvim_create_namespace("lazydo_render"),
		highlight = vim.api.nvim_create_namespace("lazydo_highlight"),
		virtual = vim.api.nvim_create_namespace("lazydo_virtual"),
	}
	return instance
end

function LazyDo:toggle()
	if self.is_visible then
		self:close_window()
	else
		self:show()
	end
end

function LazyDo:show()
	if not self.buf or not vim.api.nvim_buf_is_valid(self.buf) then
		self.buf = ui.create_buffer(self)
	end

	if not self.win or not vim.api.nvim_win_is_valid(self.win) then
		self.win = ui.create_window(self)
	end

	self.is_visible = true
	self:setup_live_refresh()
	self:refresh_display()
end

function LazyDo:close_window()
	if self.is_ui_busy then
		return
	end

	if self.refresh_timer then
		self.refresh_timer:stop()
		self.refresh_timer:close()
		self.refresh_timer = nil
	end

	if self.win and vim.api.nvim_win_is_valid(self.win) then
		vim.api.nvim_win_close(self.win, true)
	end

	self.win = nil
	self.is_visible = false
end

function LazyDo:set_ui_busy(busy)
	self.is_ui_busy = busy
	if self.buf and vim.api.nvim_buf_is_valid(self.buf) then
		vim.api.nvim_buf_set_option(self.buf, "modifiable", not busy)
	end
end

function LazyDo:setup_live_refresh()
	if not self.refresh_timer then
		self.refresh_timer = vim.loop.new_timer()
	end

	self.refresh_timer:start(
		0,
		100,
		vim.schedule_wrap(function()
			if self.is_visible and not self.is_processing then
				self:refresh_display()
			end
		end)
	)
end

function LazyDo:refresh_display()
	if not self.buf or not vim.api.nvim_buf_is_valid(self.buf) then
		return
	end

	self.is_processing = true
	local ok = pcall(function()
		local cursor = vim.api.nvim_win_get_cursor(self.win)
		self:render_content()

		if cursor[1] <= vim.api.nvim_buf_line_count(self.buf) then
			vim.api.nvim_win_set_cursor(self.win, cursor)
		end

		ui.setup_task_highlights(self)
		-- self:highlight_active_task()

		-- Update buffer
	end)
	self.is_processing = false
end

function LazyDo:render_content()
	if not self.buf or not vim.api.nvim_buf_is_valid(self.buf) then
		return
	end

	vim.api.nvim_buf_set_option(self.buf, "modifiable", true)

	local width = vim.api.nvim_win_get_width(self.win)
	local lines = {}

	-- Add header
	table.insert(lines, utils.center(" {  LazyDo  } ", width))
	table.insert(lines, string.rep("═", width))

	-- Add statistics
	local stats = self:get_task_statistics()
	local stats_line = string.format(
		" Total: %d | Done: %d | Pending: %d | Overdue: %d ",
		stats.total,
		stats.done,
		stats.pending,
		stats.overdue
	)
	table.insert(lines, utils.center(stats_line, width))
	table.insert(lines, "")

	-- Render tasks
	for _, task in ipairs(self.tasks) do
		local task_lines = ui.render_task_block(task, width, "  ", self.opts.icons)
		vim.list_extend(lines, task_lines)
	end

	vim.api.nvim_buf_set_lines(self.buf, 0, -1, false, lines)
	vim.api.nvim_buf_set_option(self.buf, "modifiable", false)
end

function LazyDo:get_task_statistics()
	local stats = {
		total = #self.tasks,
		done = 0,
		pending = 0,
		overdue = 0,
	}

	local now = os.time()
	for _, task in ipairs(self.tasks) do
		if task.done then
			stats.done = stats.done + 1
		else
			stats.pending = stats.pending + 1
			if task.due_date and task.due_date < now then
				stats.overdue = stats.overdue + 1
			end
		end
	end

	return stats
end

function LazyDo:get_current_task()
	if not self.win or not vim.api.nvim_win_is_valid(self.win) then
		return nil
	end

	local cursor = vim.api.nvim_win_get_cursor(self.win)
	local line_nr = cursor[1]
	local header_lines = 4 -- Title + separator + stats + empty line

	-- Skip header
	if line_nr <= header_lines then
		return nil
	end

	local current_line = line_nr
	local task_start = header_lines + 1
	local found_task = nil

	for _, task in ipairs(self.tasks) do
		local task_height = self:get_task_block_height(task)
		local task_end = task_start + task_height

		if current_line >= task_start and current_line <= task_end then
			found_task = task
			task.line_number = task_start -- Store line number for highlighting
			break
		end

		task_start = task_end + 3 -- +1 for spacing between tasks
	end

	return found_task
end

function LazyDo:get_task_block_height(task)
	local height = 3 -- Minimum height (top border + content + bottom border)

	if task.due_date then
		height = height + 1
	end
	if task.notes then
		local wrapped_notes = utils.word_wrap(task.notes, vim.api.nvim_win_get_width(self.win) - 6)
		height = height + #wrapped_notes
	end
	if #task.subtasks > 0 then
		height = height + 1 + #task.subtasks -- Header + subtasks
	end

	return height
end

function LazyDo:add_task(content, opts)
	local task = Tasker.Task.new(content, opts)
	table.insert(self.tasks, task)
	if self.opts.storage.auto_save then
		storage.save_tasks(self)
	end
	self:refresh_display()
	return task
end

function LazyDo:delete_task()
	local task = self:get_current_task()
	if not task then
		return
	end

	for i, t in ipairs(self.tasks) do
		if t.id == task.id then
			table.remove(self.tasks, i)
			if self.opts.storage.auto_save then
				storage.save_tasks(self)
			end
			self:refresh_display()
			return true
		end
	end
	return false
end

function LazyDo:set_note(task)
	if not task then
		vim.notify("No task selected", vim.log.levels.WARN)
		return
	end

	vim.ui.input({ prompt = "Set note: ", default = task.notes or "" }, function(input)
		if input ~= nil then
			task.notes = input -- Set the note for the active task
			task.updated_at = os.time() -- Update the timestamp
			if self.opts.storage.auto_save then
				require("lazydo.storage").save_tasks(self)
			end
			self:refresh_display() -- Refresh the display to show the updated task
		end
	end)
end

function LazyDo:add_subtask()
	local task = self:get_current_task()
	if not task then
		vim.notify("No task selected", vim.log.levels.WARN)
		return
	end

	local function create_subtask(input)
		if not input or input == "" then
			return
		end

		local subtask = task:add_subtask(input, {
			priority = task.priority,
			tags = vim.deepcopy(task.tags),
		})

		if self.opts.storage.auto_save then
			require("lazydo.storage").save_tasks(self)
		end
		self:refresh_display()
	end

	-- Show input dialog with placeholder
	vim.ui.input({
		prompt = "New subtask: ",
		default = "",
		completion = "customlist,SubtaskComplete",
	}, create_subtask)
end

function LazyDo:edit_subtask()
	local task = self:get_current_task()
	if not task then
		vim.notify("No task selected", vim.log.levels.WARN)
		return
	end

	if #task.subtasks == 0 then
		vim.notify("No subtasks to edit. Add a subtask first.", vim.log.levels.INFO)
		self:add_subtask()
		return
	end

	-- Create selection items for subtasks
	local items = {}
	for i, subtask in ipairs(task.subtasks) do
		table.insert(items, {
			text = string.format("[%s] %s", subtask.done and "✓" or " ", subtask.content),
			value = i,
			subtask = subtask,
		})
	end

	-- Show subtask selection menu
	vim.ui.select(items, {
		prompt = "Select subtask to edit:",
		format_item = function(item)
			return item.text
		end,
	}, function(choice)
		if not choice then
			return
		end

		-- Show edit menu for selected subtask
		local edit_items = {
			{ text = "Edit content", value = "edit" },
			{ text = "Toggle completion", value = "toggle" },
			{ text = "Delete subtask", value = "delete" },
			{ text = "Move up", value = "up" },
			{ text = "Move down", value = "down" },
		}

		vim.ui.select(edit_items, {
			prompt = "Choose action:",
			format_item = function(item)
				return item.text
			end,
		}, function(action)
			if not action then
				return
			end

			if action.value == "edit" then
				-- Edit subtask content
				vim.ui.input({
					prompt = "Edit subtask: ",
					default = items[choice.value].subtask.content,
				}, function(new_content)
					if new_content and new_content ~= "" then
						task:edit_subtask(choice.value, new_content)
						if self.opts.storage.auto_save then
							require("lazydo.storage").save_tasks(self)
						end
						self:refresh_display()
					end
				end)
			elseif action.value == "toggle" then
				task:toggle_subtask(choice.value)
				if self.opts.storage.auto_save then
					require("lazydo.storage").save_tasks(self)
				end
				self:refresh_display()
			elseif action.value == "delete" then
				task:remove_subtask(choice.value)
				if self.opts.storage.auto_save then
					require("lazydo.storage").save_tasks(self)
				end
				self:refresh_display()
			elseif action.value == "up" or action.value == "down" then
				local idx = choice.value
				local new_idx = action.value == "up" and idx - 1 or idx + 1
				if new_idx >= 1 and new_idx <= #task.subtasks then
					task.subtasks[idx], task.subtasks[new_idx] = task.subtasks[new_idx], task.subtasks[idx]
					task.subtasks[idx].index = idx
					task.subtasks[new_idx].index = new_idx
					if self.opts.storage.auto_save then
						require("lazydo.storage").save_tasks(self)
					end
					self:refresh_display()
				end
			end
		end)
	end)
end

function LazyDo:set_date(task)
	if not task then
		vim.notify("No task selected", vim.log.levels.WARN)
		return
	end

	vim.ui.input({
		prompt = "Set due date (YYYY-MM-DD or 'today'): ",
		default = task.due_date and os.date("%Y-%m-%d", task.due_date) or "",
	}, function(input)
		if input ~= nil then
			if input == "today" then
				task.due_date = os.time() -- Set due date to today
			else
				task.due_date = utils.parse_date(input) -- Use your existing date parsing logic
				if not task.due_date then
					vim.notify("Invalid date format", vim.log.levels.WARN)
					return
				end
			end
			task.updated_at = os.time() -- Update the timestamp
			if self.opts.storage.auto_save then
				require("lazydo.storage").save_tasks(self)
			end
			self:refresh_display() -- Refresh the display to show the updated task
		end
	end)
end

function LazyDo:move_task(task, direction)
	for i, t in ipairs(self.tasks) do
		if t.id == task.id then
			local new_pos = i + direction
			if new_pos >= 1 and new_pos <= #self.tasks then
				self.tasks[i], self.tasks[new_pos] = self.tasks[new_pos], self.tasks[i]
				if self.opts.storage.auto_save then
					storage.save_tasks(self)
				end
				self:refresh_display()
				return true
			end
			break
		end
	end
	return false
end

function LazyDo:setup_highlights()
	local colors = self.opts.colors or config.defaults.colors

	local highlights = {
		-- Basic UI elements
		LazyDoBorder = { fg = colors.border },
		LazyDoHeader = { fg = colors.header, bold = true },
		LazyDoSeparator = { fg = colors.border },
		LazyDoStatusLine = { fg = colors.header },

		-- Task states
		LazyDoPending = { fg = colors.pending },
		LazyDoDone = { fg = colors.done },
		LazyDoOverdue = { fg = colors.overdue },

		-- Task components
		LazyDoNote = { fg = colors.note },
		LazyDoDueDate = { fg = colors.due_date },
		LazyDoTag = { fg = colors.tag, italic = true },
		LazyDoMetadata = { fg = colors.metadata },

		-- Priority levels
		LazyDoPriorityHigh = {
			fg = colors.priority.high,
			bold = true,
			italic = true,
		},
		LazyDoPriorityMedium = {
			fg = colors.priority.medium,
			bold = true,
		},
		LazyDoPriorityLow = {
			fg = colors.priority.low,
		},
		-- Progress indicators
		LazyDoProgressFull = {
			fg = colors.done,
			bold = true,
		},
		LazyDoProgressEmpty = {
			fg = colors.border,
			nocombine = true,
		},

		-- Subtask elements
		LazyDoSubtaskBullet = {
			fg = colors.subtask,
			bold = true,
		},
		LazyDoSubtaskProgress = {
			fg = colors.done,
			bold = true,
		},

		-- Subtasks
		LazyDoSubtask = { fg = colors.subtask },
		LazyDoSubtaskDone = { fg = colors.done },

		-- Active task
		LazyDoActiveTask = {
			bg = colors.activetask,
			blend = self.opts.ui.highlight.blend or 10,
		},

		-- Help window
		LazyDoHelp = { fg = colors.note },
		LazyDoHelpHeader = { fg = colors.header, bold = true },
		LazyDoHelpKey = { fg = colors.header, bold = true },
	}

	for group, settings in pairs(highlights) do
		pcall(vim.api.nvim_set_hl, 0, group, settings)
	end
end

-- Search functionality
function LazyDo:search_tasks(query)
	if not query or query == "" then
		return self.tasks
	end

	local results = {}
	local query_lower = query:lower()

	for _, task in ipairs(self.tasks) do
		if
			task.content:lower():find(query_lower)
			or (task.notes and task.notes:lower():find(query_lower))
			or vim.tbl_contains(
				vim.tbl_map(function(tag)
					return tag:lower()
				end, task.tags),
				query_lower
			)
		then
			table.insert(results, task)
		end
	end

	return results
end

-- Advanced filtering
function LazyDo:filter_tasks(filters)
	local filtered = vim.deepcopy(self.tasks)

	if filters.status then
		filtered = vim.tbl_filter(function(task)
			return (filters.status == "done" and task.done)
				or (filters.status == "pending" and not task.done)
				or (filters.status == "overdue" and task:is_overdue())
		end, filtered)
	end

	if filters.priority then
		filtered = vim.tbl_filter(function(task)
			return task.priority == filters.priority
		end, filtered)
	end

	if filters.tags and #filters.tags > 0 then
		filtered = vim.tbl_filter(function(task)
			for _, tag in ipairs(filters.tags) do
				if not vim.tbl_contains(task.tags, tag) then
					return false
				end
			end
			return true
		end, filtered)
	end

	return filtered
end

-- Task sorting
function LazyDo:sort_tasks(method)
	local sorters = {
		priority = function(a, b)
			return a.priority > b.priority
		end,
		due_date = function(a, b)
			if not a.due_date then
				return false
			end
			if not b.due_date then
				return true
			end
			return a.due_date < b.due_date
		end,
		created = function(a, b)
			return a.created_at > b.created_at
		end,
		updated = function(a, b)
			return a.updated_at > b.updated_at
		end,
	}

	if sorters[method] then
		table.sort(self.tasks, sorters[method])
		self:refresh_display()
	end
end

-- Task templates
function LazyDo:save_as_template(task)
	if not self.templates then
		self.templates = {}
	end

	local template = vim.deepcopy(task)
	template.id = nil
	template.created_at = nil
	template.updated_at = nil

	vim.ui.input({
		prompt = "Template name: ",
	}, function(name)
		if name and name ~= "" then
			self.templates[name] = template
			storage.mark_dirty()
			vim.notify("Template saved: " .. name)
		end
	end)
end

function LazyDo:create_from_template()
	if not self.templates or vim.tbl_isempty(self.templates) then
		vim.notify("No templates available")
		return
	end

	local template_names = vim.tbl_keys(self.templates)
	vim.ui.select(template_names, {
		prompt = "Select template:",
	}, function(choice)
		if choice then
			local new_task = vim.deepcopy(self.templates[choice])
			new_task.created_at = os.time()
			new_task.updated_at = os.time()
			new_task.id = tostring(os.time()) .. math.random(1000, 9999)
			table.insert(self.tasks, new_task)
			self:refresh_display()
		end
	end)
end

-- Task statistics
function LazyDo:get_detailed_statistics()
	local stats = {
		total = #self.tasks,
		done = 0,
		pending = 0,
		overdue = 0,
		priority = { high = 0, medium = 0, low = 0 },
		tags = {},
		completion_rate = 0,
		average_completion_time = 0,
	}

	local completion_times = {}

	for _, task in ipairs(self.tasks) do
		if task.done then
			stats.done = stats.done + 1
			if task.last_completed and task.created_at then
				table.insert(completion_times, task.last_completed - task.created_at)
			end
		else
			stats.pending = stats.pending + 1
			if task:is_overdue() then
				stats.overdue = stats.overdue + 1
			end
		end

		-- Priority stats
		if task.priority == 3 then
			stats.priority.high = stats.priority.high + 1
		elseif task.priority == 2 then
			stats.priority.medium = stats.priority.medium + 1
		else
			stats.priority.low = stats.priority.low + 1
		end

		-- Tag stats
		for _, tag in ipairs(task.tags) do
			stats.tags[tag] = (stats.tags[tag] or 0) + 1
		end
	end

	-- Calculate completion rate and average time
	stats.completion_rate = stats.total > 0 and (stats.done / stats.total) * 100 or 0
	if #completion_times > 0 then
		local sum = 0
		for _, time in ipairs(completion_times) do
			sum = sum + time
		end
		stats.average_completion_time = sum / #completion_times
	end

	return stats
end

-- Performance optimization for task operations
function LazyDo:wrap_with_auto_save()
	local original_add = self.add_task
	local original_delete = self.delete_task
	local original_move = self.move_task

	self.add_task = function(self, ...)
		local result = original_add(self, ...)
		storage.mark_dirty()
		return result
	end

	self.delete_task = function(self, ...)
		local result = original_delete(self, ...)
		storage.mark_dirty()
		return result
	end

	self.move_task = function(self, ...)
		local result = original_move(self, ...)
		storage.mark_dirty()
		return result
	end
end

function LazyDo:create_commands()
	vim.api.nvim_create_user_command("LazyDoToggle", function()
		self:toggle()
	end, {})

	vim.api.nvim_create_user_command("LazyDoAdd", function(opts)
		self:add_task(opts.args)
	end, { nargs = "?" })

	vim.api.nvim_create_user_command("LazyDoSearch", function(opts)
		self:search_tasks(opts.args)
	end, { nargs = "?" })

	vim.api.nvim_create_user_command("LazyDoSort", function(opts)
		self:sort_tasks(opts.args)
	end, { nargs = 1, complete = function()
		return { "priority", "due_date", "created", "updated" }
	end })

	vim.api.nvim_create_user_command("LazyDoTemplate", function(opts)
		if opts.args == "save" then
			self:save_as_template(self:get_current_task())
		else
			self:create_from_template()
		end
	end, { nargs = "?", complete = function()
		return { "save", "load" }
	end })
end

function LazyDo:create_task_prompt()
	local function create_task(input)
		if not input or input == "" then
			return
		end

		-- Parse priority from input (e.g., "!high Task description" or "!3 Task description")
		local priority = 2 -- default medium priority
		local content = input

		-- Priority patterns: !high/!h, !medium/!m, !low/!l or !3, !2, !1
		local prio_pattern = "^!(%w+)%s+(.+)$"
		local prio_str, rest = input:match(prio_pattern)

		if prio_str then
			content = rest
			if prio_str:match("^[hH]") or prio_str == "3" then
				priority = 3
			elseif prio_str:match("^[lL]") or prio_str == "1" then
				priority = 1
			end
		end

		-- Parse tags from content (e.g., "Task description #tag1 #tag2")
		local tags = {}
		content = content
			:gsub("#(%w+)", function(tag)
				table.insert(tags, tag)
				return ""
			end)
			:gsub("%s+$", "") -- Remove trailing spaces

		-- Create the task
		local task = self:add_task(content, {
			priority = priority,
			tags = tags,
		})

		-- Optionally prompt for due date
		vim.ui.input({
			prompt = "Set due date? (YYYY-MM-DD/today/Xd/n): ",
		}, function(date_input)
			if date_input and date_input ~= "" and date_input ~= "n" then
				local due_date = require("lazydo.utils").parse_date(date_input)
				if due_date then
					task.due_date = due_date
					self:refresh_display()
				else
					vim.notify("Invalid date format", vim.log.levels.WARN)
				end
			end
		end)

		self:refresh_display()
	end

	vim.ui.input({
		prompt = "New task (!high/!medium/!low or !3/!2/!1 for priority): ",
		completion = "customlist,TaskComplete",
	}, create_task)
end
return LazyDo
