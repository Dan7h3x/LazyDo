-- lua/lazydo/init.lua

-- Core dependencies
local api = vim.api
local fn = vim.fn
local notify = vim.notify

-- Utility functions
local function safe_require(module)
	local ok, result = pcall(require, module)
	if not ok then
		notify(string.format("Failed to load %s: %s", module, result), vim.log.levels.ERROR)
		return nil
	end
	return result
end

-- Class definitions
---@class Task
---@field id string
---@field title string
---@field notes string
---@field due_date string
---@field status string
---@field subtasks Task[]
---@field priority string
---@field tags string[]
---@field created_at number
---@field folded boolean
local Task = {}
Task.__index = Task

function Task.new(title, notes, due_date)
	return setmetatable({
		id = tostring(os.time()) .. math.random(1000, 9999),
		title = title or "",
		notes = notes or "",
		due_date = due_date or "",
		status = "PENDING",
		subtasks = {},
		priority = "NONE",
		tags = {},
		created_at = os.time(),
		folded = false,
	}, Task)
end

-- Default template task
local template_task = {
	title = "New Task",
	notes = "Task Description\n- Point 1\n- Point 2",
	due_date = os.date("%Y-%m-%d"),
	status = "PENDING",
	priority = "MEDIUM",
	tags = { "work" },
	subtasks = {
		{
			title = "Subtask Example",
			notes = "Subtask description",
			due_date = os.date("%Y-%m-%d"),
			status = "PENDING",
		},
	},
}

---@class LazyDo
---@field tasks Task[]
---@field buf number
---@field win number
---@field opts table
local LazyDo = {}
LazyDo.__index = LazyDo

-- Core dependencies
local api = vim.api
local notify = vim.notify

-- Utility functions
local function safe_notify(msg, level)
	notify(string.format("LazyDo: %s", msg), level or vim.log.levels.INFO)
end

local function safe_json_encode(data)
	local status, result = pcall(vim.json.encode, data)
	if not status then
		safe_notify("Failed to encode JSON: " .. result, vim.log.levels.ERROR)
		return nil
	end
	return result
end

local function safe_json_decode(str)
	local status, result = pcall(vim.json.decode, str)
	if not status then
		safe_notify("Failed to decode JSON: " .. result, vim.log.levels.ERROR)
		return nil
	end
	return result
end

-- File operations with error handling
local function read_file(path)
	local file = io.open(path, "r")
	if not file then
		return nil
	end

	local content = file:read("*all")
	file:close()
	return content
end

local function write_file(path, content)
	local file = io.open(path, "w")
	if not file then
		safe_notify("Failed to open file for writing: " .. path, vim.log.levels.ERROR)
		return false
	end

	local success = pcall(function()
		file:write(content)
	end)
	file:close()
	return success
end

-- Default configuration with improved icons and colors
local DEFAULT_CONFIG = {
	width = 0.8,
	height = 0.8,
	min_width = 60,
	min_height = 10,
	border = "rounded",
	indent = "    ",
	icons = {
		pending = "", -- Nerd Font icon for pending
		done = "", -- Nerd Font icon for done
		priority = {
			HIGH = "", -- Nerd Font icon for high priority
			MEDIUM = "", -- Nerd Font icon for medium priority
			LOW = "", -- Nerd Font icon for low priority
			NONE = "", -- Nerd Font icon for no priority
		},
		note = "", -- Nerd Font icon for notes
		due = "", -- Nerd Font icon for due date
		subtask = "", -- Nerd Font icon for subtasks
		tag = "", -- Nerd Font icon for tags
		section = "", -- Nerd Font icon for sections
		separator = "─", -- Separator line character
	},
	colors = {
		done = "#859900", -- Green for done tasks
		pending = "#dc322f", -- Red for pending tasks
		note = "#268bd2", -- Blue for notes
		due = {
			normal = "#cb4b16", -- Orange for normal due dates
			overdue = "#dc322f", -- Red for overdue tasks
			done = "#859900", -- Green for done tasks
		},
		header = "#6c71c4", -- Purple for headers
		priority = {
			HIGH = "#dc322f", -- Red for high priority
			MEDIUM = "#b58900", -- Yellow for medium priority
			LOW = "#859900", -- Green for low priority
			NONE = "#93a1a1", -- Grey for no priority
		},
		selected = {
			bg = "#073642", -- Dark background for selected tasks
			fg = "#fdf6e3", -- Light foreground for selected tasks
		},
		box = {
			border = "#839496", -- Grey for box borders
			shadow = "#586e75", -- Darker grey for shadows
			title = "#268bd2", -- Blue for box titles
			selected_border = "#b58900", -- Yellow for selected box borders
		},
		subtask = {
			done = "#859900", -- Green for done subtasks
			pending = "#dc322f", -- Red for pending subtasks
			indent = "#586e75", -- Dark grey for subtask indent
		},
		tag = "#6c71c4", -- Purple for tags
		footer = "#93a1a1", -- Grey for footer
		due_date = "#cb4b16", -- Orange for due dates
		task_title = "#268bd2", -- Blue for task titles
		subtask_title = "#b58900", -- Yellow for subtask titles
		separator = "#586e75", -- Dark grey for separator lines
	},
	box = {
		style = {
			tl = "╭",
			tr = "╮",
			bl = "╰",
			br = "╯",
			h = "─",
			v = "│",
		},
		padding = 1,
		margin = 1,
	},
	fold = {
		marker_open = "▼",
		marker_closed = "▶",
	},
	ui = {
		dynamic_padding = true,
		animate_fold = true,
		smooth_scroll = true,
		auto_resize = true,
		min_task_width = 40,
		max_task_width = 120,
	},
}

-- Setup highlights using highlight groups
local function setup_highlights()
	local highlights = {
		LazyDoDone = { fg = DEFAULT_CONFIG.colors.done },
		LazyDoPending = { fg = DEFAULT_CONFIG.colors.pending },
		LazyDoNote = { fg = DEFAULT_CONFIG.colors.note },
		LazyDoDue = { fg = DEFAULT_CONFIG.colors.due.normal },
		LazyDoOverdue = { fg = DEFAULT_CONFIG.colors.due.overdue },
		LazyDoHeader = { fg = DEFAULT_CONFIG.colors.header },
		LazyDoPriorityHigh = { fg = DEFAULT_CONFIG.colors.priority.HIGH },
		LazyDoPriorityMedium = { fg = DEFAULT_CONFIG.colors.priority.MEDIUM },
		LazyDoPriorityLow = { fg = DEFAULT_CONFIG.colors.priority.LOW },
		LazyDoPriorityNone = { fg = DEFAULT_CONFIG.colors.priority.NONE },
		LazyDoSelected = { bg = DEFAULT_CONFIG.colors.selected.bg, fg = DEFAULT_CONFIG.colors.selected.fg },
		LazyDoBoxBorder = { fg = DEFAULT_CONFIG.colors.box.border },
		LazyDoBoxShadow = { fg = DEFAULT_CONFIG.colors.box.shadow },
		LazyDoBoxTitle = { fg = DEFAULT_CONFIG.colors.box.title },
		LazyDoBoxSelectedBorder = { fg = DEFAULT_CONFIG.colors.box.selected_border },
		LazyDoSubtaskDone = { fg = DEFAULT_CONFIG.colors.subtask.done },
		LazyDoSubtaskPending = { fg = DEFAULT_CONFIG.colors.subtask.pending },
		LazyDoSubtaskIndent = { fg = DEFAULT_CONFIG.colors.subtask.indent },
		LazyDoTag = { fg = DEFAULT_CONFIG.colors.tag },
		LazyDoFooter = { fg = DEFAULT_CONFIG.colors.footer },
		LazyDoDueDate = { fg = DEFAULT_CONFIG.colors.due_date }, -- Highlight for due dates
		LazyDoTaskTitle = { fg = DEFAULT_CONFIG.colors.task_title }, -- Highlight for task titles
		LazyDoSubtaskTitle = { fg = DEFAULT_CONFIG.colors.subtask_title }, -- Highlight for subtask titles
		LazyDoSeparator = { fg = DEFAULT_CONFIG.colors.separator }, -- Highlight for separator lines
	}

	for name, attrs in pairs(highlights) do
		local status, err = pcall(api.nvim_set_hl, 0, name, attrs)
		if not status then
			notify(string.format("Failed to set highlight %s: %s", name, err), vim.log.levels.ERROR)
		end
	end
end

-- Constructor with proper error handling
function LazyDo.new(config)
	local self = setmetatable({}, LazyDo)
	self.config = vim.tbl_deep_extend("force", DEFAULT_CONFIG, config or {})
	self.data_file = string.format("%s/lazydo_tasks.json", vim.fn.stdpath("data"))
	self.tasks = {}
	self.namespace = api.nvim_create_namespace("LazyDo")

	local status, err = pcall(setup_highlights)
	if not status then
		notify(string.format("Failed to setup highlights: %s", err), vim.log.levels.ERROR)
	end

	self:load_tasks()
	return self
end

-- Setup function
function LazyDo.setup(opts)
	local instance = LazyDo.new(opts)
	api.nvim_create_user_command("LazyDo", function()
		instance:create_window()
	end, {})
	return instance
end

-- Load tasks from file
function LazyDo:load_tasks()
	local file = io.open(self.data_file, "r")
	if file then
		local content = file:read("*all")
		file:close()
		local ok, data = pcall(vim.json.decode, content)
		if ok and data then
			self.tasks = data
		else
			self.tasks = {}
			notify("Failed to load tasks, starting fresh", vim.log.levels.WARN)
		end
	else
		self.tasks = {}
	end
end

-- Save tasks to file
function LazyDo:save_tasks()
	local file = io.open(self.data_file, "w")
	if file then
		local ok, content = pcall(vim.json.encode, self.tasks)
		if ok then
			file:write(content)
			file:close()
			notify("Tasks saved successfully")
		else
			notify("Failed to save tasks", vim.log.levels.ERROR)
		end
	else
		notify("Failed to open tasks file for writing", vim.log.levels.ERROR)
	end
end

-- Window creation
function LazyDo:create_window()
	local width = math.max(self.config.min_width, math.floor(vim.o.columns * self.config.width))
	local height = math.max(self.config.min_height, math.floor(vim.o.lines * self.config.height))
	local row = math.floor((vim.o.lines - height) / 2)
	local col = math.floor((vim.o.columns - width) / 2)

	-- Create buffer
	self.buf = api.nvim_create_buf(false, true)
	api.nvim_buf_set_option(self.buf, "bufhidden", "wipe")
	api.nvim_buf_set_option(self.buf, "filetype", "lazydo")
	api.nvim_buf_set_option(self.buf, "modifiable", false)

	-- Create window
	self.win = api.nvim_open_win(self.buf, true, {
		relative = "editor",
		width = width,
		height = height,
		row = row,
		col = col,
		style = "minimal",
		border = self.config.border,
		title = " LazyDo ",
		title_pos = "center",
	})

	-- Set window options
	api.nvim_win_set_option(self.win, "wrap", true)
	api.nvim_win_set_option(self.win, "number", false)
	api.nvim_win_set_option(self.win, "cursorline", true)

	self:setup_keymaps()
	self:render()
end

-- Task operations
function LazyDo:add_task()
	vim.ui.input({ prompt = "New task: " }, function(input)
		if input and input ~= "" then
			table.insert(self.tasks, {
				title = input,
				status = "PENDING",
				priority = "NONE",
				notes = "",
				subtasks = {},
				created_at = os.time(),
			})
			self:save_tasks()
			self:render()
		end
	end)
end

-- Improved task detection using extmarks
function LazyDo:setup_task_marks()
	if not self.buf or not api.nvim_buf_is_valid(self.buf) then
		return
	end

	-- Clear existing marks
	api.nvim_buf_clear_namespace(self.buf, self.namespace, 0, -1)

	-- Store task positions with extmarks
	self.task_marks = {}
	for i, task in ipairs(self.tasks) do
		local start_line = self.task_boxes[i].start_line
		local end_line = self.task_boxes[i].end_line

		local mark_id = api.nvim_buf_set_extmark(self.buf, self.namespace, start_line, 0, {
			end_line = end_line,
			end_col = 0,
			strict = false,
		})

		self.task_marks[mark_id] = {
			task = task,
			index = i,
			start_line = start_line,
			end_line = end_line,
		}
	end
end

-- Enhanced task detection using extmarks
function LazyDo:get_task_at_cursor()
	if not self.win or not api.nvim_win_is_valid(self.win) then
		return nil
	end

	local cursor = api.nvim_win_get_cursor(self.win)
	local cursor_line = cursor[1] - 1

	-- Get marks at cursor position
	local marks = api.nvim_buf_get_extmarks(
		self.buf,
		self.namespace,
		{ cursor_line, 0 },
		{ cursor_line, -1 },
		{ details = true }
	)

	for _, mark in ipairs(marks) do
		local mark_id = mark[1]
		if self.task_marks[mark_id] then
			return self.task_marks[mark_id]
		end
	end

	return nil
end

function LazyDo:toggle_task()
	local task_info = self:get_task_at_cursor()
	if task_info then
		task_info.task.status = task_info.task.status == "DONE" and "PENDING" or "DONE"
		self:save_tasks()
		self:render()
	end
end

function LazyDo:delete_task()
	local task_info = self:get_task_at_cursor()
	if task_info then
		table.remove(self.tasks, task_info.index)
		self:save_tasks()
		self:render()
	end
end

-- Enhanced task operations
function LazyDo:edit_task()
	local task_info = self:get_task_at_cursor()
	if not task_info then
		return
	end

	local task = task_info.task
	local options = {
		"Edit title",
		"Edit notes",
		"Set priority",
		"Set due date",
		"Add subtask",
		"Add tags",
	}

	vim.ui.select(options, {
		prompt = "Edit task:",
	}, function(choice)
		if not choice then
			return
		end

		if choice == "Edit title" then
			vim.ui.input({
				prompt = "Edit title: ",
				default = task.title,
			}, function(input)
				if input and input ~= "" then
					task.title = input
					self:save_tasks()
					self:render()
				end
			end)
		elseif choice == "Edit notes" then
			vim.ui.input({
				prompt = "Edit notes: ",
				default = task.notes or "",
			}, function(input)
				if input then
					task.notes = input
					self:save_tasks()
					self:render()
				end
			end)
		elseif choice == "Set priority" then
			vim.ui.select({ "HIGH", "MEDIUM", "LOW", "NONE" }, {
				prompt = "Select priority:",
			}, function(priority)
				if priority then
					task.priority = priority
					self:save_tasks()
					self:render()
				end
			end)
		elseif choice == "Set due date" then
			vim.ui.input({
				prompt = "Due date (YYYY-MM-DD): ",
				default = task.due_date or os.date("%Y-%m-%d"),
			}, function(input)
				if input and input:match("^%d%d%d%d%-%d%d%-%d%d$") then
					task.due_date = input
					self:save_tasks()
					self:render()
				end
			end)
		elseif choice == "Add subtask" then
			vim.ui.input({
				prompt = "New subtask: ",
			}, function(input)
				if input and input ~= "" then
					task.subtasks = task.subtasks or {}
					table.insert(task.subtasks, {
						title = input,
						status = "PENDING",
					})
					self:save_tasks()
					self:render()
				end
			end)
		elseif choice == "Add tags" then
			vim.ui.input({
				prompt = "Tags (comma-separated): ",
				default = table.concat(task.tags or {}, ", "),
			}, function(input)
				if input then
					task.tags = vim.split(input:gsub("%s+", ""), ",")
					self:save_tasks()
					self:render()
				end
			end)
		end
	end)
end

-- Task box creation helper
function LazyDo:create_task_box(task, width, is_selected)
	local box = {}
	local highlights = {}
	local border_color = is_selected and "LazyDoBoxSelectedBorder" or "LazyDoBoxBorder"

	-- Box top
	local top = string.format(
		"%s%s%s",
		self.config.box.style.tl,
		string.rep(self.config.box.style.h, width - 2),
		self.config.box.style.tr
	)
	table.insert(box, top)
	table.insert(highlights, { border_color, #box - 1, 0, -1 })

	-- Task title with status and priority
	local status_icon = task.status == "DONE" and self.config.icons.done or self.config.icons.pending
	local priority_icon = self.config.icons.priority[task.priority or "NONE"]
	local fold_marker = task.folded and self.config.fold.marker_closed or self.config.fold.marker_open

	local title_line = string.format(" %s %s %s %s", fold_marker, status_icon, priority_icon, task.title)

	-- Add due date if exists
	if task.due_date then
		local today = os.date("%Y-%m-%d")
		local due_color = task.status == "DONE" and "LazyDoDueDone"
			or (task.due_date < today and "LazyDoDueOverdue" or "LazyDoDue")
		title_line = title_line .. string.format(" %s %s", self.config.icons.due, task.due_date)
		table.insert(highlights, { due_color, #box, #title_line - 10, -1 })
	end

	local padded_title = string.format(
		"%s%s%s",
		self.config.box.style.v,
		title_line .. string.rep(" ", width - #title_line - 2),
		self.config.box.style.v
	)
	table.insert(box, padded_title)
	table.insert(highlights, { border_color, #box - 1, 0, 1 })
	table.insert(highlights, { border_color, #box - 1, width - 1, width })

	if not task.folded then
		-- Notes
		if task.notes and task.notes ~= "" then
			for _, line in ipairs(vim.split(task.notes, "\n")) do
				local note_line = string.format(
					"%s %s %s",
					self.config.box.style.v,
					self.config.icons.note .. " " .. line,
					string.rep(" ", width - #line - 5) .. self.config.box.style.v
				)
				table.insert(box, note_line)
				table.insert(highlights, { "LazyDoNote", #box - 1, 2, -2 })
				table.insert(highlights, { border_color, #box - 1, 0, 1 })
				table.insert(highlights, { border_color, #box - 1, width - 1, width })
			end
		end

		-- Subtasks
		if task.subtasks and #task.subtasks > 0 then
			for _, subtask in ipairs(task.subtasks) do
				local status = subtask.status == "DONE" and self.config.icons.done or self.config.icons.pending
				local subtask_line = string.format(
					"%s %s %s %s",
					self.config.box.style.v,
					self.config.icons.subtask,
					status,
					subtask.title
				)
				local padded_subtask = subtask_line
					.. string.rep(" ", width - #subtask_line - 1)
					.. self.config.box.style.v
				table.insert(box, padded_subtask)

				local status_color = subtask.status == "DONE" and "LazyDoSubtaskDone" or "LazyDoSubtaskPending"
				table.insert(
					highlights,
					{ status_color, #box - 1, #self.config.box.style.v + 3, #self.config.box.style.v + 4 }
				)
				table.insert(highlights, { "LazyDoSubtask", #box - 1, #self.config.box.style.v + 1, -2 })
				table.insert(highlights, { border_color, #box - 1, 0, 1 })
				table.insert(highlights, { border_color, #box - 1, width - 1, width })
			end
		end

		-- Tags
		if task.tags and #task.tags > 0 then
			local tags_line =
				string.format("%s %s %s", self.config.box.style.v, self.config.icons.tag, table.concat(task.tags, ", "))
			local padded_tags = tags_line .. string.rep(" ", width - #tags_line - 1) .. self.config.box.style.v
			table.insert(box, padded_tags)
			table.insert(highlights, { "LazyDoTag", #box - 1, 2, -2 })
			table.insert(highlights, { border_color, #box - 1, 0, 1 })
			table.insert(highlights, { border_color, #box - 1, width - 1, width })
		end
	end

	-- Box bottom
	local bottom = string.format(
		"%s%s%s",
		self.config.box.style.bl,
		string.rep(self.config.box.style.h, width - 2),
		self.config.box.style.br
	)
	table.insert(box, bottom)
	table.insert(highlights, { border_color, #box - 1, 0, -1 })

	return box, highlights
end

-- Color blending helper
function LazyDo:blend_colors(color1, color2, factor)
	local function hex_to_rgb(hex)
		hex = hex:gsub("#", "")
		return tonumber("0x" .. hex:sub(1, 2)), tonumber("0x" .. hex:sub(3, 4)), tonumber("0x" .. hex:sub(5, 6))
	end

	local function rgb_to_hex(r, g, b)
		return string.format("#%02x%02x%02x", r, g, b)
	end

	local r1, g1, b1 = hex_to_rgb(color1)
	local r2, g2, b2 = hex_to_rgb(color2)

	local r = math.floor(r1 + (r2 - r1) * factor)
	local g = math.floor(g1 + (g2 - g1) * factor)
	local b = math.floor(b1 + (b2 - b1) * factor)

	return rgb_to_hex(r, g, b)
end

-- Enhanced render function
function LazyDo:render()
	if not self.buf or not api.nvim_buf_is_valid(self.buf) then
		return
	end

	api.nvim_buf_set_option(self.buf, "modifiable", true)

	local win_width = api.nvim_win_get_width(self.win)
	local task_width =
		math.min(math.max(math.floor(win_width * 0.8), self.config.ui.min_task_width), self.config.ui.max_task_width)

	local lines = {}
	local highlights = {}
	self.task_boxes = {}

	-- Render header
	local header = self:create_header(task_width)
	vim.list_extend(lines, header.lines)
	vim.list_extend(highlights, header.highlights)

	-- Render tasks
	if self.tasks and #self.tasks > 0 then
		for i, task in ipairs(self.tasks) do
			if i > 1 then
				table.insert(lines, "")
			end

			self.task_boxes[i] = {
				start_line = #lines,
			}

			-- Create task content
			local task_lines, task_highlights =
				self:create_task_content(task, task_width, self.selected_task_index == i)

			vim.list_extend(lines, task_lines)
			vim.list_extend(highlights, task_highlights)

			self.task_boxes[i].end_line = #lines - 1
		end
	else
		table.insert(lines, "")
		table.insert(lines, "  No tasks yet. Press 'a' to add a task.")
	end

	-- Render footer
	local footer = self:create_footer(task_width)
	vim.list_extend(lines, footer.lines)
	vim.list_extend(highlights, footer.highlights)

	-- Apply content and highlights
	api.nvim_buf_set_lines(self.buf, 0, -1, false, lines)
	api.nvim_buf_clear_namespace(self.buf, self.namespace, 0, -1)

	-- Setup task marks for detection
	self:setup_task_marks()

	-- Apply highlights
	for _, hl in ipairs(highlights) do
		pcall(api.nvim_buf_add_highlight, self.buf, self.namespace, hl[1], hl[2], hl[3], hl[4])
	end

	api.nvim_buf_set_option(self.buf, "modifiable", false)
end

-- Create header with proper styling
function LazyDo:create_header(width)
	local lines = {
		"",
		string.format("  %s LazyDo Task Manager", self.config.icons.section),
		string.rep(self.config.box.style.h, width),
		"",
	}

	local highlights = {
		{ "LazyDoHeader", 1, 0, -1 },
		{ "LazyDoHeader", 2, 0, -1 },
	}

	return { lines = lines, highlights = highlights }
end

-- Create footer with proper styling
function LazyDo:create_footer(width)
	local lines = {
		"",
		string.rep(self.config.box.style.h, width),
		self:get_keymap_help(),
	}

	local highlights = {
		{ "LazyDoFooter", #lines - 1, 0, -1 },
		{ "LazyDoFooter", #lines, 0, -1 },
	}

	return { lines = lines, highlights = highlights }
end

-- Create task content with centered alignment
function LazyDo:create_task_content(task, width, is_selected)
	local lines = {}
	local highlights = {}

	-- Center the task title
	local title = string.format("%s %s", self.config.icons.pending, task.title)
	local centered_title = string.format("%s%s", string.rep(" ", math.floor((width - #title) / 2)), title)

	-- Add title line to task content
	table.insert(lines, centered_title)
	table.insert(highlights, { "LazyDoTaskTitle", #lines - 1, 0, -1 }) -- Highlight for task title

	-- Due date highlighting
	if task.due_date then
		local due_line = string.format(" %s %s", self.config.icons.due, task.due_date)
		local centered_due = string.format("%s%s", string.rep(" ", math.floor((width - #due_line) / 2)), due_line)
		table.insert(lines, centered_due)
		table.insert(highlights, { "LazyDoDueDate", #lines - 1, 0, -1 }) -- Highlight for due date
	end

	-- Notes
	if task.notes and task.notes ~= "" then
		for _, note in ipairs(vim.split(task.notes, "\n")) do
			local note_line = string.format(" %s %s", self.config.icons.note, note)
			local centered_note =
				string.format("%s%s", string.rep(" ", math.floor((width - #note_line) / 2)), note_line)
			table.insert(lines, centered_note)
			table.insert(highlights, { "LazyDoNote", #lines - 1, 0, -1 })
		end
	end

	-- Subtasks
	if task.subtasks and #task.subtasks > 0 then
		for _, subtask in ipairs(task.subtasks) do
			local subtask_icon = subtask.status == "DONE" and self.config.icons.done or self.config.icons.pending
			local subtask_line = string.format(" %s %s", subtask_icon, subtask.title)
			local centered_subtask =
				string.format("%s%s", string.rep(" ", math.floor((width - #subtask_line) / 2)), subtask_line)
			table.insert(lines, centered_subtask)
			table.insert(highlights, { "LazyDoSubtaskTitle", #lines - 1, 0, -1 }) -- Highlight for subtask title
		end
	end

	-- Add a separator line
	table.insert(lines, string.rep(self.config.icons.separator, width))
	table.insert(highlights, { "LazyDoSeparator", #lines - 1, 0, -1 }) -- Highlight for separator line

	return lines, highlights
end

-- Toggle fold state
function LazyDo:toggle_fold()
	local task_info = self:get_task_at_cursor()
	if task_info then
		task_info.task.folded = not task_info.task.folded
		self:render()
	end
end

-- Global methods for footer actions
LazyDo.actions = {
	add_task = function(self)
		vim.ui.input({ prompt = "New task: " }, function(input)
			if input and input ~= "" then
				table.insert(self.tasks, {
					title = input,
					status = "PENDING",
					priority = "NONE",
					notes = "",
					subtasks = {},
					created_at = os.time(),
					folded = false,
					tags = {},
				})
				self:save_tasks()
				self:render()
			end
		end)
	end,

	edit_task = function(self)
		local task_info = self:get_task_at_cursor()
		if not task_info then
			return
		end

		local task = task_info.task
		local options = {
			"Edit title",
			"Edit notes",
			"Set priority",
			"Set due date",
			"Add subtask",
			"Add tags",
		}

		vim.ui.select(options, {
			prompt = "Edit task:",
			kind = "lazydo",
		}, function(choice)
			if not choice then
				return
			end

			if choice == "Edit title" then
				vim.ui.input({
					prompt = "Edit title: ",
					default = task.title,
				}, function(input)
					if input and input ~= "" then
						task.title = input
						self:save_tasks()
						self:render()
					end
				end)
			elseif choice == "Edit notes" then
				vim.ui.input({
					prompt = "Edit notes: ",
					default = task.notes or "",
				}, function(input)
					if input then
						task.notes = input
						self:save_tasks()
						self:render()
					end
				end)
			elseif choice == "Set priority" then
				vim.ui.select({ "HIGH", "MEDIUM", "LOW", "NONE" }, {
					prompt = "Select priority:",
				}, function(priority)
					if priority then
						task.priority = priority
						self:save_tasks()
						self:render()
					end
				end)
			elseif choice == "Set due date" then
				vim.ui.input({
					prompt = "Due date (YYYY-MM-DD): ",
					default = task.due_date or os.date("%Y-%m-%d"),
				}, function(input)
					if input and input:match("^%d%d%d%d%-%d%d%-%d%d$") then
						task.due_date = input
						self:save_tasks()
						self:render()
					end
				end)
			elseif choice == "Add subtask" then
				self.actions.add_subtask(self)
			elseif choice == "Add tags" then
				vim.ui.input({
					prompt = "Tags (comma-separated): ",
					default = table.concat(task.tags or {}, ", "),
				}, function(input)
					if input then
						task.tags = vim.split(input:gsub("%s+", ""), ",")
						self:save_tasks()
						self:render()
					end
				end)
			end
		end)
	end,

	delete_task = function(self)
		local task_info = self:get_task_at_cursor()
		if task_info then
			vim.ui.select({ "Yes", "No" }, {
				prompt = "Delete task?",
			}, function(choice)
				if choice == "Yes" then
					table.remove(self.tasks, task_info.index)
					self:save_tasks()
					self:render()
				end
			end)
		end
	end,

	add_subtask = function(self)
		local task_info = self:get_task_at_cursor()
		if not task_info then
			return
		end

		vim.ui.input({
			prompt = "New subtask: ",
		}, function(input)
			if input and input ~= "" then
				task_info.task.subtasks = task_info.task.subtasks or {}
				table.insert(task_info.task.subtasks, {
					title = input,
					status = "PENDING",
				})
				self:save_tasks()
				self:render()
			end
		end)
	end,

	add_note = function(self)
		local task_info = self:get_task_at_cursor()
		if not task_info then
			return
		end

		vim.ui.input({
			prompt = "Add note: ",
			default = task_info.task.notes or "",
		}, function(input)
			if input then
				task_info.task.notes = input
				self:save_tasks()
				self:render()
			end
		end)
	end,

	set_due_date = function(self)
		local task_info = self:get_task_at_cursor()
		if not task_info then
			return
		end

		vim.ui.input({
			prompt = "Due date (YYYY-MM-DD): ",
			default = task_info.task.due_date or os.date("%Y-%m-%d"),
		}, function(input)
			if input and input:match("^%d%d%d%d%-%d%d%-%d%d$") then
				task_info.task.due_date = input
				self:save_tasks()
				self:render()
			end
		end)
	end,

	toggle_status = function(self)
		local task_info = self:get_task_at_cursor()
		if task_info then
			task_info.task.status = task_info.task.status == "DONE" and "PENDING" or "DONE"
			self:save_tasks()
			self:render()
		end
	end,
}

-- Update keymap setup with all actions
function LazyDo:setup_keymaps()
	local opts = { buffer = self.buf, noremap = true, silent = true }
	local keymaps = {
		{
			"n",
			"a",
			function()
				self.actions.add_task(self)
			end,
		},
		{
			"n",
			"d",
			function()
				self.actions.delete_task(self)
			end,
		},
		{
			"n",
			"e",
			function()
				self.actions.edit_task(self)
			end,
		},
		{
			"n",
			"t",
			function()
				self.actions.toggle_status(self)
			end,
		},
		{
			"n",
			"<CR>",
			function()
				self:toggle_fold()
			end,
		},
		{
			"n",
			"s",
			function()
				self.actions.add_subtask(self)
			end,
		},
		{
			"n",
			"T",
			function()
				self:toggle_subtask()
			end,
		},
		{
			"n",
			"n",
			function()
				self.actions.add_note(self)
			end,
		},
		{
			"n",
			"D",
			function()
				self.actions.set_due_date(self)
			end,
		},
		{
			"n",
			"/",
			function()
				self:search_tasks()
			end,
		},
		{
			"n",
			"sd",
			function()
				self:sort_tasks("due")
			end,
		},
		{
			"n",
			"sp",
			function()
				self:sort_tasks("priority")
			end,
		},
		{
			"n",
			"q",
			function()
				self:close()
			end,
		},
		{
			"n",
			"m",
			function()
				self:edit_template_task()
			end,
		},
	}

	for _, map in ipairs(keymaps) do
		vim.keymap.set(map[1], map[2], map[3], opts)
	end
end

-- Helper function for keymap help
function LazyDo:get_keymap_help()
	return " [a]dd [d]elete [e]dit [t]oggle [<CR>]fold [s]ubtask [n]ote [D]ue [/]search [sd]sort due [sp]sort priority [q]uit [m]odify template"
end

function LazyDo:close()
	if self.win and api.nvim_win_is_valid(self.win) then
		api.nvim_win_close(self.win, true)
	end
	if self.buf and api.nvim_buf_is_valid(self.buf) then
		api.nvim_buf_delete(self.buf, { force = true })
	end
end

-- Add sorting functions
function LazyDo:sort_tasks(criterion)
	if criterion == "due" then
		table.sort(self.tasks, function(a, b)
			if not a.due_date then
				return false
			end
			if not b.due_date then
				return true
			end
			return a.due_date < b.due_date
		end)
	elseif criterion == "priority" then
		local priority_order = { HIGH = 1, MEDIUM = 2, LOW = 3, NONE = 4 }
		table.sort(self.tasks, function(a, b)
			return priority_order[a.priority or "NONE"] < priority_order[b.priority or "NONE"]
		end)
	end
	self:render()
end

-- Add search functionality
function LazyDo:search_tasks()
	if not pcall(require, "fzf-lua") then
		notify("fzf-lua is required for search functionality", vim.log.levels.ERROR)
		return
	end

	local tasks_with_info = {}
	for i, task in ipairs(self.tasks) do
		local status = task.status == "DONE" and "✓" or "☐"
		local priority = self.config.icons.priority[task.priority or "NONE"]
		local due = task.due_date and (" 📅 " .. task.due_date) or ""
		local display = string.format("%s %s %s%s", status, priority, task.title, due)
		table.insert(tasks_with_info, {
			display = display,
			index = i,
			task = task,
		})
	end

	require("fzf-lua").fzf_exec(
		vim.tbl_map(function(t)
			return t.display
		end, tasks_with_info),
		{
			prompt = "Search Tasks > ",
			actions = {
				["default"] = function(selected)
					local idx = selected[1].idx
					local task_info = tasks_with_info[idx]
					if task_info then
						-- Highlight and scroll to the selected task
						self:focus_task(task_info.index)
					end
				end,
			},
		}
	)
end

-- Add task focusing
function LazyDo:focus_task(index)
	if not self.win or not api.nvim_win_is_valid(self.win) then
		return
	end

	-- Calculate line number for the task
	local line = 5 -- Header offset
	for i = 1, index - 1 do
		local task = self.tasks[i]
		line = line + 1 -- Task title
		if task.due_date then
			line = line + 1
		end
		if task.notes and task.notes ~= "" then
			line = line + #vim.split(task.notes, "\n")
		end
		if task.subtasks and #task.subtasks > 0 then
			line = line + #task.subtasks
		end
		if task.tags and #task.tags > 0 then
			line = line + 1
		end
		line = line + 1 -- Empty line
	end

	-- Move cursor to task
	api.nvim_win_set_cursor(self.win, { line, 0 })
	-- Center the view on the task
	api.nvim_command("normal! zz")
end

-- Toggle subtask status
function LazyDo:toggle_subtask()
	local task_info = self:get_task_at_cursor()
	if not task_info then
		return
	end

	local cursor = api.nvim_win_get_cursor(self.win)
	local cursor_line = cursor[1]

	-- Check if cursor is on a subtask line
	local subtask_start = task_info.start_line + 3 -- After box top and title
	if task_info.task.notes and task_info.task.notes ~= "" then
		subtask_start = subtask_start + #vim.split(task_info.task.notes, "\n")
	end

	local subtask_index = cursor_line - subtask_start
	if subtask_index >= 0 and subtask_index < #(task_info.task.subtasks or {}) then
		local subtask = task_info.task.subtasks[subtask_index + 1]
		subtask.status = subtask.status == "DONE" and "PENDING" or "DONE"
		self:save_tasks()
		self:render()
	end
end

-- Add smooth scrolling
function LazyDo:scroll_to_task(task_info)
	if not task_info or not self.win or not api.nvim_win_is_valid(self.win) then
		return
	end

	local win_height = api.nvim_win_get_height(self.win)
	local current_line = api.nvim_win_get_cursor(self.win)[1]
	local target_line = math.floor((task_info.start_line + task_info.end_line) / 2)

	-- Smooth scroll animation
	if self.config.ui.smooth_scroll then
		local steps = 5
		local delay = 5
		local line_diff = target_line - current_line
		local step_size = math.floor(line_diff / steps)

		for i = 1, steps do
			vim.defer_fn(function()
				if api.nvim_win_is_valid(self.win) then
					local new_line = current_line + (step_size * i)
					api.nvim_win_set_cursor(self.win, { new_line, 0 })
					vim.cmd("normal! zz")
				end
			end, delay * i)
		end
	else
		api.nvim_win_set_cursor(self.win, { target_line, 0 })
		vim.cmd("normal! zz")
	end
end

-- Add autocmd for cursor movement
function LazyDo:setup_autocommands()
	local group = api.nvim_create_augroup("LazyDo", { clear = true })

	api.nvim_create_autocmd("CursorMoved", {
		group = group,
		buffer = self.buf,
		callback = function()
			local task_info = self:get_task_at_cursor()
			if task_info then
				if self.selected_task_index ~= task_info.index then
					self.selected_task_index = task_info.index
					self:render()
				end
			end
		end,
	})
end

-- Edit template task
function LazyDo:edit_template_task()
	local options = {
		"Edit title",
		"Edit notes",
		"Set priority",
		"Set due date",
		"Add subtask",
		"Add tags",
	}

	vim.ui.select(options, {
		prompt = "Edit template task:",
	}, function(choice)
		if not choice then
			return
		end

		if choice == "Edit title" then
			vim.ui.input({
				prompt = "Edit title: ",
				default = template_task.title,
			}, function(input)
				if input and input ~= "" then
					template_task.title = input
					notify("Template task title updated.")
				end
			end)
		elseif choice == "Edit notes" then
			vim.ui.input({
				prompt = "Edit notes: ",
				default = template_task.notes or "",
			}, function(input)
				if input then
					template_task.notes = input
					notify("Template task notes updated.")
				end
			end)
		elseif choice == "Set priority" then
			vim.ui.select({ "HIGH", "MEDIUM", "LOW", "NONE" }, {
				prompt = "Select priority:",
			}, function(priority)
				if priority then
					template_task.priority = priority
					notify("Template task priority updated.")
				end
			end)
		elseif choice == "Set due date" then
			vim.ui.input({
				prompt = "Due date (YYYY-MM-DD): ",
				default = template_task.due_date or os.date("%Y-%m-%d"),
			}, function(input)
				if input and input:match("^%d%d%d%d%-%d%d%-%d%d$") then
					template_task.due_date = input
					notify("Template task due date updated.")
				end
			end)
		elseif choice == "Add subtask" then
			vim.ui.input({
				prompt = "New subtask: ",
			}, function(input)
				if input and input ~= "" then
					template_task.subtasks = template_task.subtasks or {}
					table.insert(template_task.subtasks, {
						title = input,
						status = "PENDING",
					})
					notify("Template task subtask added.")
				end
			end)
		elseif choice == "Add tags" then
			vim.ui.input({
				prompt = "Tags (comma-separated): ",
				default = table.concat(template_task.tags or {}, ", "),
			}, function(input)
				if input then
					template_task.tags = vim.split(input:gsub("%s+", ""), ",")
					notify("Template task tags updated.")
				end
			end)
		end
	end)
end

return LazyDo
