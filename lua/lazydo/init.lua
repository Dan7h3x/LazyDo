-- lua/lazydo/init.lua

---@class LazyDo A task management plugin for Neovim
---@field tasks Task[] List of tasks
---@field buf number Buffer ID for the LazyDo window
---@field win number Window ID for the LazyDo window
---@field config table Configuration options
---@field namespace number Namespace ID for highlights
---@field selected_task_index number? Currently selected task index
local LazyDo = {}
LazyDo.__index = LazyDo

-- Core dependencies
local api = vim.api
local fn = vim.fn
local notify = vim.notify

---@class Task Represents a single task item
---@field id string Unique identifier
---@field title string Task title
---@field notes string Additional notes
---@field status "PENDING"|"DONE" Task status
---@field priority "HIGH"|"MEDIUM"|"LOW"|"NONE" Task priority
---@field due_date string? Due date in YYYY-MM-DD format
---@field tags string[] List of tags
---@field created_at number Unix timestamp of creation
---@field folded boolean Whether the task is folded in display
---@field subtasks Task[] List of subtasks
local Task = {}
Task.__index = Task

-- Default color scheme (Tokyonight dark)
local DEFAULT_COLORS = {
	task = {
		done = "#9ece6a", -- Green
		pending = "#e0af68", -- Yellow
		high_priority = "#f7768e", -- Red
		medium_priority = "#e0af68", -- Yellow
		low_priority = "#9ece6a", -- Green
		no_priority = "#565f89", -- Gray
	},
	due_date = {
		normal = "#7aa2f7", -- Blue
		overdue = "#f7768e", -- Red
		today = "#e0af68", -- Yellow
	},
	notes = "#7dcfff", -- Cyan
	subtask = "#bb9af7", -- Purple
	ui = {
		border = "#3b4261",
		title = "#c0caf5",
		header = "#7aa2f7",
		stats = "#565f89",
		help = "#565f89",
	},
}

-- Updated configuration with style and color options
local DEFAULT_CONFIG = {
	window = {
		width_ratio = 0.8,
		height_ratio = 0.8,
		min_width = 60,
		min_height = 10,
		border = "rounded",
	},
	appearance = {
		style = "block", -- "block" or "md"
		padding = 1,
		indent = "    ",
		highlight_current = true,
		show_icons = true,
	},
	colors = DEFAULT_COLORS, -- User can override colors
	icons = {
		task_pending = "",
		task_done = "",
		priority = {
			HIGH = " ",
			MEDIUM = " ",
			LOW = " ",
			NONE = "",
		},
		note = "󰎞",
		due_date = " ",
		fold = {
			expanded = "▾",
			collapsed = "▸",
		},
		subtask = "󰘍",
	},
	storage = {
		data_path = string.format("%s/lazydo_tasks.json", fn.stdpath("data")),
		backup = true, -- Enable backup option
		backup_path = string.format("%s/lazydo_backups", fn.stdpath("data")), -- Backup directory
	},
}

---Creates a new task instance
---@param title string Task title
---@param notes? string Optional notes
---@param due_date? string Optional due date
---@return Task
function Task.new(title, notes, due_date)
	return setmetatable({
		id = string.format("%d_%d", os.time(), math.random(1000, 9999)),
		title = title or "",
		notes = notes or "",
		due_date = due_date or "",
		status = "PENDING",
		priority = "NONE",
		tags = {},
		created_at = os.time(),
		folded = false,
		subtasks = {},
	}, Task)
end

---Creates a new LazyDo instance
---@param config? table Optional configuration override
---@return LazyDo
function LazyDo.new(config)
	local self = setmetatable({}, LazyDo)
	self.config = vim.tbl_deep_extend("force", DEFAULT_CONFIG, config or {})
	self.tasks = {}
	self.namespace = api.nvim_create_namespace("LazyDo")
	self:setup_highlights()
	self:setup_icon_highlights()
	self:load_tasks()
	return self
end

---Validates if the LazyDo instance and its buffer are valid
---@param self LazyDo
---@return boolean
function LazyDo:is_valid_instance()
	if not self or not self.buf or not api.nvim_buf_is_valid(self.buf) then
		notify("Invalid LazyDo instance or buffer", vim.log.levels.ERROR)
		return false
	end
	return true
end

---Creates content for a task based on selected style
---@param task Task
---@param width number
---@param is_selected boolean
---@return table lines
---@return table highlights
function LazyDo:create_task_content(task, width, is_selected)
	if self.config.appearance.style == "md" then
		return self:render_task_markdown(task, width, is_selected)
	else
		return self:render_task_block(task, width, is_selected)
	end
end

---Renders task in markdown style with defined colors and no background
---@param task Task
---@param width number
---@param is_selected boolean
---@return table lines
---@return table highlights
function LazyDo:render_task_markdown(task, width, is_selected)
	local lines = {}
	local highlights = {}
	local indent = self.config.appearance.indent

	-- Add separator above the task
	table.insert(lines, string.rep("─", width))
	table.insert(highlights, { "LazyDoBorder", #lines - 1, 0, width })

	-- Task header with checkbox and priority
	local status_mark = task.status == "DONE" and "✔️" or "❌"
	local priority_icon = self.config.icons.priority[task.priority] or "⚪"
	local header = string.format(" %s [%s] %s ", status_mark, priority_icon, task.title)
	table.insert(lines, header)

	-- Add header highlights
	local status_hl = task.status == "DONE" and "LazyDoTaskDone" or "LazyDoTaskPending"
	table.insert(highlights, { status_hl, #lines - 1, 0, 5 })
	table.insert(highlights, { "LazyDoIcon" .. (task.priority or "NoPriority"), #lines - 1, 6, 7 })

	-- Due date
	if task.due_date and task.due_date ~= "" then
		local due_line = string.format("%s Due: %s", indent, task.due_date)
		table.insert(lines, due_line)
		table.insert(highlights, { "LazyDoDueDate", #lines - 1, #indent, -1 })
	end

	-- Notes
	if task.notes and task.notes ~= "" then
		table.insert(lines, string.format("%s📝 Notes:", indent))
		for _, note_line in ipairs(vim.split(task.notes, "\n")) do
			table.insert(lines, string.format("%s%s%s", indent, indent, note_line))
		end
	end

	-- Add empty line for spacing
	table.insert(lines, "")
	-- Add separator below the task
	table.insert(lines, string.rep("─", width))
	table.insert(highlights, { "LazyDoBorder", #lines - 1, 0, width })

	return lines, highlights
end

---Renders task in block style with defined colors and no background
---@param task Task
---@param width number
---@param is_selected boolean
---@return table lines
---@return table highlights
function LazyDo:render_task_block(task, width, is_selected)
	local lines = {}
	local highlights = {}

	-- Add a virtual block around the active task
	local block_border = "─" .. string.rep("─", width - 2) .. "─"
	table.insert(lines, block_border)

	-- Title line with status, priority, and due date
	local status_icon = task.status == "DONE" and "✔️" or "❌"
	local priority_icon = self.config.icons.priority[task.priority] or "⚪"
	local due_date_str = task.due_date and task.due_date ~= "" and string.format(" Due: %s", task.due_date) or ""

	local title_line = string.format(" %s %s %s%s ", status_icon, priority_icon, task.title, due_date_str)
	table.insert(lines, title_line .. string.rep(" ", width - #title_line - 1))

	-- Add empty line for spacing
	table.insert(lines, "")
	table.insert(lines, block_border)

	return lines, highlights
end

---Updates due date highlight based on status
---@param due_date string
---@return string highlight_group
function LazyDo:get_due_date_highlight(due_date)
	if not due_date or due_date == "" then
		return "LazyDoDueDate"
	end

	local today = os.date("%Y-%m-%d")
	if due_date < today then
		return "LazyDoDueOverdue"
	elseif due_date == today then
		return "LazyDoDueToday"
	end
	return "LazyDoDueDate"
end

---Loads tasks from storage
function LazyDo:load_tasks()
	local file = io.open(self.config.storage.data_path, "r")
	if not file then
		return
	end

	local content = file:read("*all")
	file:close()

	local ok, data = pcall(vim.json.decode, content)
	if ok and data then
		self.tasks = data
	else
		notify("Failed to load tasks", vim.log.levels.WARN)
		self.tasks = {}
	end
end

---Saves tasks to storage
function LazyDo:save_tasks()
	local file = io.open(self.config.storage.data_path, "w")
	if not file then
		notify("Failed to open tasks file for writing", vim.log.levels.ERROR)
		return
	end

	local ok, content = pcall(vim.json.encode, self.tasks)
	if ok then
		file:write(content)
		file:close()
		notify("Tasks saved successfully")
	else
		notify("Failed to save tasks", vim.log.levels.ERROR)
	end
end

-- Task Operations

---Adds a new task with user input
---@param self LazyDo
function LazyDo:add_task()
	vim.ui.input({ prompt = "Task title: " }, function(title)
		if not title or title == "" then
			return
		end

		local new_task = Task.new(title)
		table.insert(self.tasks, new_task)
		self:save_tasks()
		self:refresh_buffer()
		notify("Task added successfully")
	end)
end

---Edits the task at current cursor position
---@param self LazyDo
function LazyDo:edit_task()
	local task = self:get_task_at_cursor()
	if not task then
		return
	end

	local options = {
		"Edit title",
		"Edit notes",
		"Set priority",
		"Set due date",
		"Add tags",
	}

	vim.ui.select(options, { prompt = "Edit task:" }, function(choice)
		if not choice then
			return
		end

		if choice == "Edit title" then
			self:edit_task_title(task)
		elseif choice == "Edit notes" then
			self:edit_task_notes(task)
		elseif choice == "Set priority" then
			self:edit_task_priority(task)
		elseif choice == "Set due date" then
			self:edit_task_due_date(task)
		elseif choice == "Add tags" then
			self:edit_task_tags(task)
		end
	end)
end

---Edits task title
---@param task Task
function LazyDo:edit_task_title(task)
	vim.ui.input({
		prompt = "Edit title: ",
		default = task.title,
	}, function(new_title)
		if new_title and new_title ~= "" then
			task.title = new_title
			self:save_tasks()
			self:refresh_buffer()
		end
	end)
end

---Edits task notes
---@param task Task
function LazyDo:edit_task_notes(task)
	vim.ui.input({
		prompt = "Edit notes: ",
		default = task.notes,
	}, function(new_notes)
		if new_notes then
			task.notes = new_notes
			self:save_tasks()
			self:refresh_buffer()
		end
	end)
end

---Edits task priority
---@param task Task
function LazyDo:edit_task_priority(task)
	vim.ui.select({ "HIGH", "MEDIUM", "LOW", "NONE" }, { prompt = "Select priority:" }, function(new_priority)
		if new_priority then
			task.priority = new_priority
			self:save_tasks()
			self:refresh_buffer()
		end
	end)
end

---Edits task due date with today as default
---@param task Task
function LazyDo:edit_task_due_date(task)
	local today = os.date("%Y-%m-%d")
	vim.ui.input({
		prompt = "Due date (YYYY-MM-DD) [Today: " .. today .. "]: ",
		default = task.due_date or today,
		completion = "customlist,v:lua.require'lazydo'.complete_date",
	}, function(new_date)
		if not new_date then
			return
		end

		-- Validate date format
		if new_date:match("^%d%d%d%d%-%d%d%-%d%d$") then
			task.due_date = new_date
			self:save_tasks()
			self:refresh_buffer()
			notify("Due date updated", vim.log.levels.INFO)
		else
			notify("Invalid date format. Use YYYY-MM-DD", vim.log.levels.ERROR)
		end
	end)
end

---Edits task tags
---@param task Task
function LazyDo:edit_task_tags(task)
	vim.ui.input({
		prompt = "Tags (comma-separated): ",
		default = table.concat(task.tags or {}, ", "),
	}, function(new_tags)
		if new_tags then
			task.tags = vim.split(new_tags:gsub("%s+", ""), ",")
			self:save_tasks()
			self:refresh_buffer()
		end
	end)
end

---Toggles task status between DONE and PENDING
---@param self LazyDo
function LazyDo:toggle_task()
	local task = self:get_task_at_cursor()
	if not task then
		return
	end

	-- Toggle the task status
	task.status = task.status == "DONE" and "PENDING" or "DONE"
	self:save_tasks()

	-- Refresh the buffer without changing the cursor position
	local cursor_pos = api.nvim_win_get_cursor(self.win)[1] -- Get current cursor line
	self:refresh_buffer()
	api.nvim_win_set_cursor(self.win, { cursor_pos, 0 }) -- Restore cursor position
end

---Deletes the task at cursor position
---@param self LazyDo
function LazyDo:delete_task()
	local task_index = self:get_task_index_at_cursor()
	if not task_index then
		return
	end

	vim.ui.select({ "Yes", "No" }, { prompt = "Delete this task?" }, function(choice)
		if choice == "Yes" then
			table.remove(self.tasks, task_index)
			self:save_tasks()
			self:refresh_buffer()
			notify("Task deleted")
		end
	end)
end

---Gets the task at current cursor position
---@return Task?
function LazyDo:get_task_at_cursor()
	local index = self:get_task_index_at_cursor()
	return index and self.tasks[index] or nil
end

---Gets the task index at current cursor position
---@return number?
function LazyDo:get_task_index_at_cursor()
	if not LazyDo:is_valid_instance() then
		return nil
	end

	local cursor = api.nvim_win_get_cursor(self.win)
	local cursor_line = cursor[1] - 1

	for i, box in ipairs(self.task_boxes or {}) do
		if cursor_line >= box.start_line and cursor_line <= box.end_line then
			return i
		end
	end
	return nil
end

-- Window Management and UI Rendering

---Creates and opens the LazyDo window
---@param self LazyDo
function LazyDo:create_window()
	-- Calculate window dimensions
	local width = math.max(self.config.window.min_width, math.floor(vim.o.columns * self.config.window.width_ratio))
	local height = math.max(self.config.window.min_height, math.floor(vim.o.lines * self.config.window.height_ratio))
	local row = math.floor((vim.o.lines - height) / 2)
	local col = math.floor((vim.o.columns - width) / 2)

	-- Create buffer with options
	self.buf = api.nvim_create_buf(false, true)
	api.nvim_buf_set_option(self.buf, "bufhidden", "wipe")
	api.nvim_buf_set_option(self.buf, "filetype", "lazydo")
	api.nvim_buf_set_option(self.buf, "modifiable", false)

	-- Create window with options
	self.win = api.nvim_open_win(self.buf, true, {
		relative = "editor",
		width = width,
		height = height,
		row = row,
		col = col,
		style = "minimal",
		border = self.config.window.border,
		title = " LazyDo ",
		title_pos = "center",
	})

	-- Set window options
	api.nvim_win_set_option(self.win, "wrap", false)
	api.nvim_win_set_option(self.win, "number", false)
	api.nvim_win_set_option(self.win, "cursorline", false)

	self:setup_keymaps()
	self:setup_highlights()
	self:render()
end

---Main render function for the UI
---@param self LazyDo
function LazyDo:render()
	if not LazyDo:is_valid_instance() then
		return
	end

	api.nvim_buf_set_option(self.buf, "modifiable", true)

	local width = api.nvim_win_get_width(self.win)
	local lines = {}
	local highlights = {}
	self.task_boxes = {}

	-- Render header
	local header = self:create_header(width)
	vim.list_extend(lines, header.lines)
	vim.list_extend(highlights, header.highlights)

	-- Render tasks
	if #self.tasks > 0 then
		for i, task in ipairs(self.tasks) do
			-- Add spacing between tasks
			if i > 1 then
				table.insert(lines, "")
			end

			-- Track task box position
			self.task_boxes[i] = { start_line = #lines }

			-- Create task content
			local task_lines, task_highlights = self:create_task_content(task, width, i == self.selected_task_index)

			vim.list_extend(lines, task_lines)
			vim.list_extend(highlights, task_highlights)

			self.task_boxes[i].end_line = #lines - 1
		end
	else
		-- Show empty state message
		table.insert(lines, "")
		table.insert(
			lines,
			string.format("%s No tasks yet. Press 'a' to add a task.", string.rep(" ", math.floor((width - 36) / 2)))
		)
	end

	-- Render footer
	local footer = self:create_footer(width)
	vim.list_extend(lines, footer.lines)
	vim.list_extend(highlights, footer.highlights)

	-- Apply content and highlights
	api.nvim_buf_set_lines(self.buf, 0, -1, false, lines)
	api.nvim_buf_clear_namespace(self.buf, self.namespace, 0, -1)

	-- Apply highlights
	for _, hl in ipairs(highlights) do
		api.nvim_buf_add_highlight(self.buf, self.namespace, hl[1], hl[2], hl[3], hl[4])
	end

	api.nvim_buf_set_option(self.buf, "modifiable", false)
end

---Creates the header section
---@param width number
---@return table
function LazyDo:create_header(width)
	local header = {
		lines = {},
		highlights = {},
	}

	-- Add title with decorative elements
	local title = " 🌟 LazyDo Task Manager 🌟 "
	local padding = math.floor((width - #title) / 2)
	table.insert(header.lines, string.rep(" ", padding) .. title)
	table.insert(header.highlights, {
		"LazyDoHeader",
		#header.lines - 1,
		padding,
		padding + #title,
	})

	-- Add separator with decorative elements
	local separator = string.rep("═", width)
	table.insert(header.lines, separator)
	table.insert(header.highlights, {
		"LazyDoBorder",
		#header.lines - 1,
		0,
		width,
	})

	return header
end

---Creates the footer section with comprehensive keymap hints
---@param width number
---@return table
function LazyDo:create_footer(width)
	local footer = {
		lines = {},
		highlights = {},
	}

	-- Add separator
	table.insert(footer.lines, string.rep("─", width))
	table.insert(footer.highlights, {
		"LazyDoBorder",
		#footer.lines - 1,
		0,
		width,
	})

	-- Add keymap hints in sections
	local keymap_sections = {
		"Navigation: [j/k]Move [gg/G]First/Last",
		"Tasks: [a]Add [d]Del [e]Edit [⏎/SPC]Toggle",
		"Subtasks: [S]Manage [C-a]Add [C-e]Edit [C-d]Del [C-t]Toggle",
		"Notes: [n]Edit [za]Fold [zo/zc]Open/Close",
		"Sort: [sp]Priority [sd]Date [ss]Status [f]Filter",
		"General: [s]Save [q]Quit",
	}

	for _, section in ipairs(keymap_sections) do
		local padding = math.floor((width - #section) / 2)
		table.insert(footer.lines, string.rep(" ", padding) .. section)
		table.insert(footer.highlights, { "LazyDoHelp", #footer.lines - 1, padding, padding + #section })
	end

	return footer
end

-- Keymaps and User Interactions

---Sets up all keymaps for the LazyDo window
---@param self LazyDo
function LazyDo:setup_keymaps()
	local function map(mode, key, action, desc)
		vim.keymap.set(mode, key, action, {
			buffer = self.buf,
			silent = true,
			nowait = true,
			desc = desc,
		})
	end

	-- Task navigation
	map("n", "j", function()
		self:navigate_tasks("down")
	end, "Next task")
	map("n", "k", function()
		self:navigate_tasks("up")
	end, "Previous task")
	map("n", "gg", function()
		self:navigate_tasks("first")
	end, "First task")
	map("n", "G", function()
		self:navigate_tasks("last")
	end, "Last task")

	-- Task management
	map("n", "a", function()
		self:add_task()
	end, "Add task")
	map("n", "d", function()
		self:delete_task()
	end, "Delete task")
	map("n", "e", function()
		self:edit_task()
	end, "Edit task")
	map("n", "<CR>", function()
		self:toggle_task()
	end, "Toggle task status")
	map("n", "<Space>", function()
		self:toggle_task()
	end, "Toggle task status")

	-- Search tasks
	map("n", "f", function()
		self:search_tasks()
	end, "Search tasks")

	-- Subtask management
	map("n", "S", function()
		local task = self:get_current_task()
		if task then
			self:manage_subtasks(task)
		end
	end, "Manage subtasks")
	map("n", "<C-a>", function()
		local task = self:get_current_task()
		if task then
			self:add_subtask()
		end
	end, "Add subtask")
	map("n", "<C-e>", function()
		local task = self:get_current_task()
		if task then
			self:edit_subtask(task)
		end
	end, "Edit subtask")
	map("n", "<C-d>", function()
		local task = self:get_current_task()
		if task then
			self:delete_subtask(task)
		end
	end, "Delete subtask")
	map("n", "<C-t>", function()
		local task = self:get_current_task()
		if task then
			self:toggle_subtask(task)
		end
	end, "Toggle subtask")

	-- Notes management
	map("n", "n", function()
		local task = self:get_current_task()
		if task then
			self:manage_notes(task)
		end
	end, "Manage notes")

	-- -- Folding
	-- map("n", "za", function()
	-- 	self:toggle_fold()
	-- end, "Toggle fold")
	-- map("n", "zo", function()
	-- 	self:open_fold()
	-- end, "Open fold")
	-- map("n", "zc", function()
	-- 	self:close_fold()
	-- end, "Close fold")
	map("n", "zR", function()
		self:open_all_folds()
	end, "Open all folds")
	map("n", "zM", function()
		self:close_all_folds()
	end, "Close all folds")

	-- Sorting and filtering
	map("n", "sp", function()
		self:sort_by_priority()
	end, "Sort by priority")
	map("n", "sd", function()
		self:sort_by_due_date()
	end, "Sort by due date")
	map("n", "ss", function()
		self:sort_by_status()
	end, "Sort by status")
	map("n", "f", function()
		self:filter_tasks()
	end, "Filter tasks")

	-- Save and quit
	map("n", "s", function()
		self:save_tasks()
	end, "Save tasks")
	map("n", "q", function()
		self:close_window()
	end, "Close window")
	map("n", "<Esc>", function()
		self:close_window()
	end, "Close window")

	-- Add keymap for inserting a template task
	map("n", "<C-t>", function()
		self:add_template_task()
	end, "Insert template task")

	-- Add keymap for filtering tasks by tag
	map("n", "ft", function()
		self:filter_tasks_by_tag()
	end, "Filter tasks by tag")
end

---Navigates between tasks
---@param self LazyDo
---@param direction "up"|"down"|"first"|"last"
function LazyDo:navigate_tasks(direction)
	if #self.tasks == 0 then
		return
	end

	local current = self.selected_task_index or 1

	if direction == "down" then
		current = math.min(current + 1, #self.tasks)
	elseif direction == "up" then
		current = math.max(current - 1, 1)
	elseif direction == "first" then
		current = 1
	elseif direction == "last" then
		current = #self.tasks
	end

	self.selected_task_index = current
	self:ensure_task_visible(current)
	self:refresh_buffer()
end

---Ensures the selected task is visible in the window
---@param task_index number
function LazyDo:ensure_task_visible(task_index)
	if not self.task_boxes or not self.task_boxes[task_index] then
		return
	end

	local task_start = self.task_boxes[task_index].start_line
	local task_end = self.task_boxes[task_index].end_line
	local win_height = api.nvim_win_get_height(self.win)
	local current_top = api.nvim_win_get_cursor(self.win)[1] - 1

	-- Scroll if task is not fully visible
	if task_start < current_top then
		vim.cmd(string.format("normal! %dgg", task_start + 1))
	elseif task_end > current_top + win_height then
		vim.cmd(string.format("normal! %dgg", task_end - win_height + 2))
	end
end

---Opens all task folds
function LazyDo:open_all_folds()
	for _, task in ipairs(self.tasks) do
		task.folded = false
	end
	self:render()
end

---Closes all task folds
function LazyDo:close_all_folds()
	for _, task in ipairs(self.tasks) do
		task.folded = true
	end
	self:render()
end

---Sorts tasks by priority
function LazyDo:sort_by_priority()
	local priority_order = { HIGH = 1, MEDIUM = 2, LOW = 3, NONE = 4 }
	table.sort(self.tasks, function(a, b)
		return priority_order[a.priority or "NONE"] < priority_order[b.priority or "NONE"]
	end)
	self:render()
end

---Sorts tasks by due date
function LazyDo:sort_by_due_date()
	table.sort(self.tasks, function(a, b)
		if not a.due_date then
			return false
		end
		if not b.due_date then
			return true
		end
		return a.due_date < b.due_date
	end)
	self:render()
end

---Sorts tasks by status
function LazyDo:sort_by_status()
	table.sort(self.tasks, function(a, b)
		if a.status == b.status then
			return a.created_at < b.created_at
		end
		return a.status == "PENDING"
	end)
	self:render()
end

---Opens the filter menu
function LazyDo:filter_tasks()
	local options = {
		"All tasks",
		"Pending tasks",
		"Completed tasks",
		"Due today",
		"Overdue tasks",
		"High priority",
		"By tag",
	}

	vim.ui.select(options, {
		prompt = "Filter tasks:",
	}, function(choice)
		if not choice then
			return
		end
		self:apply_filter(choice)
	end)
end

---Applies the selected filter
---@param filter_type string
function LazyDo:apply_filter(filter_type)
	local today = os.date("%Y-%m-%d")

	local filters = {
		["All tasks"] = function(task)
			return true
		end,
		["Pending tasks"] = function(task)
			return task.status == "PENDING"
		end,
		["Completed tasks"] = function(task)
			return task.status == "DONE"
		end,
		["Due today"] = function(task)
			return task.due_date == today
		end,
		["Overdue tasks"] = function(task)
			return task.status == "PENDING" and task.due_date and task.due_date < today
		end,
		["High priority"] = function(task)
			return task.priority == "HIGH"
		end,
	}

	if filter_type == "By tag" then
		self:filter_by_tag()
		return
	end

	local filter_fn = filters[filter_type]
	if filter_fn then
		self.filtered_tasks = vim.tbl_filter(filter_fn, self.tasks)
		self:render()
	end
end

---Opens tag filter selection
function LazyDo:filter_by_tag()
	local tags = {}
	for _, task in ipairs(self.tasks) do
		for _, tag in ipairs(task.tags) do
			if not vim.tbl_contains(tags, tag) then
				table.insert(tags, tag)
			end
		end
	end

	if #tags == 0 then
		notify("No tags found", vim.log.levels.INFO)
		return
	end

	vim.ui.select(tags, {
		prompt = "Select tag to filter by:",
	}, function(tag)
		if tag then
			self.filtered_tasks = vim.tbl_filter(function(task)
				return vim.tbl_contains(task.tags, tag)
			end, self.tasks)
			self:render()
		end
	end)
end

---Closes the LazyDo window
function LazyDo:close_window()
	if self.win and api.nvim_win_is_valid(self.win) then
		api.nvim_win_close(self.win, true)
	end
end

-- -- Module setup function
-- ---@param opts? table
-- function LazyDo.setup(opts)
--   local instance = LazyDo.new(opts)
--
--   -- Create user command
--   vim.api.nvim_create_user_command('LazyDo', function()
--     instance:create_window()
--   end, {})
--
--   return instance
-- end

-- Subtask and Notes Management

---@class Subtask
---@field id string
---@field title string
---@field status "PENDING"|"DONE"
---@field created_at number

---@class Task
---@field subtasks Subtask[]
---@field notes string[]

---Creates a new subtask
---@param title string
---@return Subtask
function LazyDo:create_subtask(title)
	return {
		id = string.format("subtask_%d_%d", os.time(), math.random(1000, 9999)),
		title = title,
		status = "PENDING",
		created_at = os.time(),
	}
end

---Safely get task at cursor
---@return Task?
function LazyDo:get_current_task()
	local task_index = self:get_task_index_at_cursor()
	if not task_index or not self.tasks[task_index] then
		notify("No task selected", vim.log.levels.WARN)
		return nil
	end
	return self.tasks[task_index]
end

---Manage subtasks with error handling
function LazyDo:manage_subtasks()
	local current_task = self:get_current_task()
	if not current_task then
		return
	end

	-- Initialize subtasks if nil
	current_task.subtasks = current_task.subtasks or {}

	local actions = {
		"Add subtask",
		"Edit subtask",
		"Delete subtask",
		"Toggle subtask status",
		"Reorder subtasks",
	}

	vim.ui.select(actions, {
		prompt = "Manage subtasks:",
		format_item = function(item)
			return item
		end,
	}, function(choice)
		if not choice then
			return
		end

		if choice == "Add subtask" then
			self:add_subtask(current_task)
		elseif choice == "Edit subtask" then
			self:edit_subtask(current_task)
		elseif choice == "Delete subtask" then
			self:delete_subtask(current_task)
		elseif choice == "Toggle subtask status" then
			self:toggle_subtask(current_task)
		elseif choice == "Reorder subtasks" then
			self:reorder_subtasks(current_task)
		end
	end)
end

---Add subtask with error handling
---@param task Task
function LazyDo:add_subtask(task)
	if not task then
		return
	end

	vim.ui.input({
		prompt = "New subtask: ",
	}, function(input)
		if not input or input == "" then
			return
		end

		task.subtasks = task.subtasks or {}
		table.insert(task.subtasks, LazyDo:create_subtask(input))

		self:save_tasks()
		self:refresh_buffer()
		notify("Subtask added successfully")
	end)
end

---Edit subtask with error handling
---@param task Task
function LazyDo:edit_subtask(task)
	if not task or not task.subtasks or #task.subtasks == 0 then
		notify("No subtasks to edit", vim.log.levels.WARN)
		return
	end

	local subtask_choices = vim.tbl_map(function(st)
		return string.format("%s %s", st.status == "DONE" and "✔️" or "❌", st.title)
	end, task.subtasks)

	vim.ui.select(subtask_choices, {
		prompt = "Select subtask to edit:",
	}, function(choice, idx)
		if not choice or not idx then
			return
		end

		vim.ui.input({
			prompt = "Edit subtask:",
			default = task.subtasks[idx].title,
		}, function(new_title)
			if new_title and new_title ~= "" then
				task.subtasks[idx].title = new_title
				self:save_tasks()
				self:refresh_buffer()
				notify("Subtask updated", vim.log.levels.INFO)
			end
		end)
	end)
end

---Delete subtask with error handling
---@param task Task
function LazyDo:delete_subtask(task)
	if not task or not task.subtasks or #task.subtasks == 0 then
		notify("No subtasks to delete", vim.log.levels.WARN)
		return
	end

	local subtask_choices = vim.tbl_map(function(st)
		return string.format("%s %s", st.status == "DONE" and "✔️" or "❌", st.title)
	end, task.subtasks)

	vim.ui.select(subtask_choices, {
		prompt = "Select subtask to delete:",
	}, function(choice, idx)
		if not choice or not idx then
			return
		end

		vim.ui.select({ "Yes", "No" }, { prompt = "Delete this subtask?" }, function(confirm)
			if confirm == "Yes" then
				table.remove(task.subtasks, idx)
				self:save_tasks()
				self:refresh_buffer()
				notify("Subtask deleted", vim.log.levels.INFO)
			end
		end)
	end)
end

---Toggle subtask status with error handling
---@param task Task
function LazyDo:toggle_subtask(task)
	if not task or not task.subtasks or #task.subtasks == 0 then
		notify("No subtasks to toggle", vim.log.levels.WARN)
		return
	end

	local subtask_choices = vim.tbl_map(function(st)
		return string.format("%s %s", st.status == "DONE" and "✔️" or "❌", st.title)
	end, task.subtasks)

	vim.ui.select(subtask_choices, {
		prompt = "Select subtask to toggle:",
	}, function(choice, idx)
		if not choice or not idx then
			return
		end

		task.subtasks[idx].status = task.subtasks[idx].status == "DONE" and "PENDING" or "DONE"
		self:save_tasks()
		self:refresh_buffer()
		notify("Subtask status toggled", vim.log.levels.INFO)
	end)
end

---Reorder subtasks with error handling
---@param task Task
function LazyDo:reorder_subtasks(task)
	if not task or not task.subtasks or #task.subtasks < 2 then
		notify("Not enough subtasks to reorder", vim.log.levels.WARN)
		return
	end

	local subtask_choices = vim.tbl_map(function(st)
		return string.format("%s %s", st.status == "DONE" and "✔️" or "❌", st.title)
	end, task.subtasks)

	vim.ui.select(subtask_choices, {
		prompt = "Select subtask to move:",
	}, function(choice, idx)
		if not choice or not idx then
			return
		end

		vim.ui.select({ "Move up", "Move down" }, { prompt = "Move direction:" }, function(direction)
			if not direction then
				return
			end

			if direction == "Move up" and idx > 1 then
				local temp = task.subtasks[idx]
				task.subtasks[idx] = task.subtasks[idx - 1]
				task.subtasks[idx - 1] = temp
				self:save_tasks()
				self:refresh_buffer()
			elseif direction == "Move down" and idx < #task.subtasks then
				local temp = task.subtasks[idx]
				task.subtasks[idx] = task.subtasks[idx + 1]
				task.subtasks[idx + 1] = temp
				self:save_tasks()
				self:refresh_buffer()
			end
		end)
	end)
end

---Enhanced notes management
---@param task Task
function LazyDo:manage_notes(task)
	-- Create a new buffer for notes editing
	local buf = api.nvim_create_buf(false, true)
	local win_width = math.floor(vim.o.columns * 0.8)
	local win_height = math.floor(vim.o.lines * 0.8)

	-- Set up the notes buffer
	api.nvim_buf_set_option(buf, "filetype", "markdown")
	api.nvim_buf_set_lines(buf, 0, -1, false, task.notes or { "" })

	-- Create notes window
	local win = api.nvim_open_win(buf, true, {
		relative = "editor",
		width = win_width,
		height = win_height,
		row = math.floor((vim.o.lines - win_height) / 2),
		col = math.floor((vim.o.columns - win_width) / 2),
		style = "minimal",
		border = "rounded",
		title = " Notes ",
		title_pos = "center",
	})

	-- Set up notes window options
	api.nvim_win_set_option(win, "wrap", true)
	api.nvim_win_set_option(win, "conceallevel", 2)
	api.nvim_win_set_option(win, "foldenable", false)

	-- Set up autocommands for saving notes
	local group = api.nvim_create_augroup("LazyDoNotes", { clear = true })
	api.nvim_create_autocmd("BufLeave", {
		group = group,
		buffer = buf,
		callback = function()
			local lines = api.nvim_buf_get_lines(buf, 0, -1, false)
			task.notes = vim.tbl_filter(function(line)
				return line ~= ""
			end, lines)
			self:save_tasks()
			self:render()
			api.nvim_win_close(win, true)
		end,
	})

	-- Set up keymaps for the notes buffer
	local function map(key, action, desc)
		vim.keymap.set("n", key, action, {
			buffer = buf,
			silent = true,
			desc = desc,
		})
	end

	map("<Esc>", function()
		vim.cmd("write | quit")
	end, "Save and close notes")

	map("<C-s>", function()
		local lines = api.nvim_buf_get_lines(buf, 0, -1, false)
		task.notes = vim.tbl_filter(function(line)
			return line ~= ""
		end, lines)
		self:save_tasks()
		notify("Notes saved", vim.log.levels.INFO)
	end, "Save notes")
end

-- Proper setup method compatible with lazy.nvim

---@class LazyDoConfig
---@field window table Window configuration
---@field appearance table Appearance settings
---@field icons table Icon settings
---@field storage table Storage settings
---@field keymaps table? Custom keymap settings
---@field hooks table? Callback hooks for events

---Default configuration

---Setup function compatible with lazy.nvim
---@param opts? LazyDoConfig
function LazyDo.setup(opts)
	-- Create instance with merged configuration
	local config = vim.tbl_deep_extend("force", DEFAULT_CONFIG, opts or {})
	local instance = LazyDo.new(config)

	-- Create autocommands group
	local group = api.nvim_create_augroup("LazyDo", { clear = true })

	-- Auto-save on exit
	api.nvim_create_autocmd("VimLeavePre", {
		group = group,
		callback = function()
			instance:save_tasks()
		end,
	})

	-- Backup management
	if config.storage.backup then
		api.nvim_create_autocmd("VimLeavePre", {
			group = group,
			callback = function()
				instance:create_backup()
			end,
		})
	end

	-- Create user commands
	api.nvim_create_user_command("LazyDo", function()
		instance:create_window()
	end, {})

	api.nvim_create_user_command("LazyDoQuickAdd", function()
		instance:quick_add_task()
	end, {})

	-- Register module globally
	_G.LazyDo = instance

	return instance
end

---Creates a backup of tasks
function LazyDo:create_backup()
	if not self.config.storage.backup then
		return
	end

	local backup_dir = self.config.storage.backup_path
	vim.fn.mkdir(backup_dir, "p")

	local backup_file = string.format("%s/tasks_%s.json", backup_dir, os.date("%Y%m%d_%H%M%S"))

	local content = vim.fn.readfile(self.config.storage.data_path)
	vim.fn.writefile(content, backup_file)
end

---Quick add task without opening the window
function LazyDo:quick_add_task()
	vim.ui.input({
		prompt = "Quick add task: ",
	}, function(title)
		if not title or title == "" then
			return
		end

		local task = Task.new(title)
		table.insert(self.tasks, task)
		self:save_tasks()
		notify("Task added: " .. title, vim.log.levels.INFO)
	end)
end

-- Date completion helper
---@param arg string
---@return string[]
function LazyDo.complete_date(arg)
	local today = os.date("*t")
	local dates = {
		os.date("%Y-%m-%d"), -- today
		os.date("%Y-%m-%d", os.time({ year = today.year, month = today.month, day = today.day + 1 })), -- tomorrow
		os.date("%Y-%m-%d", os.time({ year = today.year, month = today.month, day = today.day + 7 })), -- next week
	}
	return vim.tbl_filter(function(date)
		return date:match(arg)
	end, dates)
end

-- Define highlighting for icons and corresponding text
function LazyDo:setup_icon_highlights()
	local colors = DEFAULT_COLORS.task
	local highlights = {
		LazyDoIconPending = { fg = colors.pending },
		LazyDoIconDone = { fg = colors.done },
		LazyDoIconHighPriority = { fg = colors.high_priority },
		LazyDoIconMediumPriority = { fg = colors.medium_priority },
		LazyDoIconLowPriority = { fg = colors.low_priority },
		LazyDoIconNoPriority = { fg = colors.no_priority },
	}

	for name, attrs in pairs(highlights) do
		api.nvim_set_hl(0, name, attrs)
	end
end

---Search tasks using fzf-lua
function LazyDo:search_tasks()
	local fzf = require("fzf-lua")
	local task_titles = vim.tbl_map(function(task)
		return task.title
	end, self.tasks)

	fzf.fzf_exec(task_titles, {
		prompt = "Search Tasks: ",
		actions = {
			["default"] = function(selected)
				local task = self.tasks[selected[1]]
				if task then
					self.selected_task_index = selected[1]
					self:ensure_task_visible(self.selected_task_index)
					self:render()
				end
			end,
		},
	})
end

--- Creates a template task with complete sections
---@return Task
function LazyDo:template_task()
	return Task.new("New Task Title", "Add your notes here.", os.date("%Y-%m-%d")):set_priority("NONE"):set_tags({})
end

--- Sets the priority for the task
---@param priority string
function Task:set_priority(priority)
	self.priority = priority
	return self
end

--- Sets the tags for the task
---@param tags table
function Task:set_tags(tags)
	self.tags = tags
	return self
end

--- Adds a new task using the template
function LazyDo:add_template_task()
	local new_task = self:template_task()
	table.insert(self.tasks, new_task)
	self:save_tasks()
	self:refresh_buffer()
	notify("Template task added successfully")
end

---Safely refresh the LazyDo buffer
function LazyDo:refresh_buffer()
	if not LazyDo:is_valid_instance() then
		return
	end

	api.nvim_buf_set_option(self.buf, "modifiable", true)
	api.nvim_buf_set_lines(self.buf, 0, -1, false, {}) -- Clear the buffer

	local width = api.nvim_win_get_width(self.win) -- Get the current window width
	local lines = {}
	local highlights = {}

	-- Render only visible tasks
	local tasks_to_render = self.filtered_tasks or self.tasks
	for _, task in ipairs(tasks_to_render) do
		if not task.folded then
			-- Render task if not folded
			local task_lines, task_highlights = self:create_task_content(task, width, false)
			vim.list_extend(lines, task_lines)
			vim.list_extend(highlights, task_highlights)
		end
	end

	-- If no tasks are visible, show a message
	if #lines == 0 then
		table.insert(lines, "No tasks to display. Press 'a' to add a task.")
	end

	-- Apply content and highlights
	api.nvim_buf_set_lines(self.buf, 0, -1, false, lines)
	api.nvim_buf_clear_namespace(self.buf, self.namespace, 0, -1)

	-- Apply highlights
	for _, hl in ipairs(highlights) do
		api.nvim_buf_add_highlight(self.buf, self.namespace, hl[1], hl[2], hl[3], hl[4])
	end

	api.nvim_buf_set_option(self.buf, "modifiable", false)
end

---Sets up highlight groups for the LazyDo plugin
function LazyDo:setup_highlights()
	-- Define highlight groups
	local highlights = {
		-- Task status
		LazyDoTaskDone = { fg = self.config.colors.task_done },
		LazyDoTaskPending = { fg = self.config.colors.task_pending },

		-- Priority
		LazyDoPriorityHIGH = { fg = self.config.colors.task_high_priority },
		LazyDoPriorityMEDIUM = { fg = self.config.colors.task_medium_priority },
		LazyDoPriorityLOW = { fg = self.config.colors.task_low_priority },
		LazyDoPriorityNONE = { fg = self.config.colors.task_no_priority },

		-- Due dates
		LazyDoDueDate = { fg = self.config.colors.due_date_normal },
		LazyDoDueOverdue = { fg = self.config.colors.due_date_overdue },
		LazyDoDueToday = { fg = self.config.colors.due_date_today },

		-- Notes and subtasks
		LazyDoNote = { fg = self.config.colors.task_no_priority },
		LazyDoSubtaskDone = { fg = self.config.colors.task_done },
		LazyDoSubtaskPending = { fg = self.config.colors.task_pending },

		-- UI elements
		LazyDoHeader = { fg = self.config.colors.ui_header, bold = true },
		LazyDoBorder = { fg = self.config.colors.ui_border },
		LazyDoTitle = { fg = self.config.colors.ui_title },
		LazyDoStats = { fg = self.config.colors.ui_stats },
		LazyDoHelp = { fg = self.config.colors.ui_help, italic = true },
	}

	-- Apply highlights
	for name, attrs in pairs(highlights) do
		api.nvim_set_hl(0, name, attrs)
	end
end

--- Toggles the fold state of a task
---@param task Task
function LazyDo:toggle_fold(task)
	if not task then
		return
	end
	task.folded = not task.folded
	self:render()
end

--- Opens all folds for tasks
function LazyDo:open_folds()
	for _, task in ipairs(self.tasks) do
		task.folded = false
	end
	self:render()
end

--- Closes all folds for tasks
function LazyDo:close_folds()
	for _, task in ipairs(self.tasks) do
		task.folded = true
	end
	self:render()
end

--- Filters tasks by tag
function LazyDo:filter_tasks_by_tag()
	local tags = {}
	for _, task in ipairs(self.tasks) do
		for _, tag in ipairs(task.tags) do
			if not vim.tbl_contains(tags, tag) then
				table.insert(tags, tag)
			end
		end
	end

	if #tags == 0 then
		notify("No tags found", vim.log.levels.INFO)
		return
	end

	vim.ui.select(tags, {
		prompt = "Select tag to filter by:",
	}, function(tag)
		if tag then
			self.filtered_tasks = vim.tbl_filter(function(task)
				return vim.tbl_contains(task.tags, tag)
			end, self.tasks)
			self:render()
		end
	end)
end

return LazyDo
