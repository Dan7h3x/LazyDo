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
		self:highlight_active_task()

		-- Add help if enabled
		if self.show_help then
			vim.list_extend(lines, self:render_help())
		end

		-- Add footer
		ui.render_footer(self)

		-- Update buffer
		vim.api.nvim_buf_set_lines(self.buf, 0, -1, false, lines)
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
		local task_lines = ui.render_task_block(task, width, "", self.opts.icons)
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

	local cursor = vim.api.nvim_win_get_cursor(self.win)[1] - 1
	local lines = vim.api.nvim_buf_get_lines(self.buf, 0, -1, false)
	local line_nr = cursor

	-- Skip header (title + separator + stats + empty line)
	if line_nr <= 4 then
		return nil
	end

	for i, line in ipairs(lines) do
		if line:match("^%s*%*") then
			if i == cursor then
				return self.tasks[i]
			end
		end
	end
	return nil

	-- local current_task = nil
	-- local current_line = line_nr
	-- local task_start = 5 -- First task starts after header

	-- for _, task in ipairs(self.tasks) do
	-- 	local task_height = self:get_task_block_height(task)
	-- 	if current_line >= task_start and current_line < task_start + task_height then
	-- 		current_task = task
	-- 		break
	-- 	end
	-- 	task_start = task_start + task_height + 1 -- +1 for spacing
	-- end

	-- return current_task
end

function LazyDo:highlight_active_task()
	local task = self:get_current_task()
	if not task then
		return
	end

	-- Clear previous highlights
	vim.api.nvim_buf_clear_namespace(self.buf, self.ns.highlight, 0, -1)

	-- Highlight the active task block
	local task_line = task.line_number -- Assuming each task has a line_number property
	local task_end_line = task_line + task.subtask_count -- Adjust based on how many lines the task spans

	vim.api.nvim_buf_add_highlight(self.buf, self.ns.highlight, "LazyDoActiveTask", task_line, 0, -1)
	vim.api.nvim_buf_add_highlight(self.buf, self.ns.highlight, "LazyDoActiveTask", task_end_line, 0, -1)
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
	-- Ensure we have opts and colors
	if not self.opts then
		self.opts = config.defaults
	end

	local colors = self.opts.colors
	if not colors then
		-- Fallback colors if none provided
		colors = {
			header = "#7aa2f7",
			border = "#3b4261",
			pending = "#7aa2f7",
			done = "#9ece6a",
			overdue = "#f7768e",
			note = "#e0af68",
			due_date = "#bb9af7",
			priority = {
				high = "#f7768e",
				medium = "#e0af68",
				low = "#9ece6a",
			},
			subtask = "#7dcfff",
		}
	end

	-- Define highlight groups with error handling
	local highlights = {
		LazyDoBorder = { fg = colors.border },
		LazyDoHeader = { fg = colors.header, bold = true },
		LazyDoPending = { fg = colors.pending },
		LazyDoDone = { fg = colors.done },
		LazyDoOverdue = { fg = colors.overdue },
		LazyDoNote = { fg = colors.note },
		LazyDoDueDate = { fg = colors.due_date },
		LazyDoPriorityHigh = { fg = colors.priority and colors.priority.high or colors.overdue },
		LazyDoPriorityMedium = { fg = colors.priority and colors.priority.medium or colors.note },
		LazyDoPriorityLow = { fg = colors.priority and colors.priority.low or colors.done },
		LazyDoSubtask = { fg = colors.subtask },
		LazyDoStatusLine = { fg = colors.header },
		LazyDoKey = { fg = colors.header, bold = true },
		LazyDoSeparator = { fg = colors.border },
		LazyDoHelp = { fg = colors.note },
		LazyDoHelpHeader = { fg = colors.header, bold = true },
		LazyDoFooter = { fg = colors.border },
	}

	-- Safely set highlights
	for group, settings in pairs(highlights) do
		pcall(vim.api.nvim_set_hl, 0, group, settings)
	end
end

function LazyDo:create_commands()
	vim.api.nvim_create_user_command("LazyDoToggle", function()
		self:toggle()
	end, {})

	vim.api.nvim_create_user_command("LazyDoAdd", function(opts)
		self:add_task(opts.args)
	end, { nargs = "?" })
end

function LazyDo:render_help()
	if not self.show_help then
		return {}
	end

	local width = vim.api.nvim_win_get_width(self.win)
	local lines = {}

	-- Help header
	table.insert(lines, string.rep("─", width))
	table.insert(lines, utils.center(" Help ", width))
	table.insert(lines, string.rep("─", width))

	-- Help content
	local help_sections = {
		{
			title = "Navigation",
			content = {
				"j/k        - Move cursor up/down",
				"h/l        - Collapse/Expand task",
				"gg/G       - Go to top/bottom",
				"<C-u>/<C-d> - Page up/down",
			},
		},
		{
			title = "Task Management",
			content = {
				"<Space>    - Toggle task completion",
				"e         - Edit task",
				"dd        - Delete task",
				"a         - Add new task",
				"A         - Add subtask to current task",
			},
		},
		{
			title = "Quick Actions",
			content = {
				"n         - Add/edit note",
				"d         - Set due date",
				">/<       - Increase/decrease priority",
				"t         - Add tag",
				"s         - Sort tasks",
				"f         - Filter tasks",
			},
		},
		{
			title = "Other",
			content = {
				"q         - Close window",
				"?         - Toggle this help",
				":LazyDoAdd - Add task from command line",
				":LazyDoToggle - Toggle window",
			},
		},
	}

	-- Render help sections
	for _, section in ipairs(help_sections) do
		table.insert(lines, "")
		table.insert(lines, " " .. section.title)
		table.insert(lines, " " .. string.rep("─", #section.title))
		for _, line in ipairs(section.content) do
			table.insert(lines, "   " .. line)
		end
	end

	table.insert(lines, "")
	table.insert(lines, string.rep("─", width))
	return lines
end

return LazyDo
