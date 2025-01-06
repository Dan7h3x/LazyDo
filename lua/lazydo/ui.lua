-- ui.lua
local Utils = require("lazydo.utils")
local Task = require("lazydo.task")
local Actions = require("lazydo.actions")

---@class UI
local UI = {}

-- Add config as a module-level variable
local config = nil

local ns_id = vim.api.nvim_create_namespace("LazyDo")
local buf_name = "LazyDo"

---@class UIState
---@field buf number Buffer handle
---@field win number Window handle
---@field tasks Task[] Current tasks
---@field cursor_task? Task Task under cursor
---@field line_to_task table<number, {task: Task, mapping: table}>
---@field task_to_line table<string, number>
---@field on_task_update function?
local state = {
	buf = nil,
	win = nil,
	tasks = {},
	cursor_task = nil,
	line_to_task = {}, -- Map line numbers to tasks
	task_to_line = {}, -- Map task IDs to line numbers
	on_task_update = nil,
	search_results = {},
	current_search = nil,
	show_task_info = false,
}

local function ensure_number(value, default)
	if type(value) == "number" then
		return value
	end
	return default or 0
end

local function get_safe_window_width()
	if not state.win then
		return 80 -- Default width
	end
	local ok, width = pcall(vim.api.nvim_win_get_width, state.win)
	return ok and width or 80
end

local function create_task_separator(level, has_subtasks, is_collapsed, width)
	level = level or 0
	width = width or get_safe_window_width()

	local indent = string.rep("  ", level)
	local separator_char = level == 0 and "░"
	local separator_width = math.max(0, width - #indent - 2) -- Ensure non-negative
	local separator = indent
	if has_subtasks then
		separator = separator
			.. (is_collapsed and config.features.folding.icons.folded or config.features.folding.icons.unfolded)
	else
		separator = separator .. "  "
	end

	separator = separator .. string.rep(separator_char, separator_width)

	if level == 0 then
		-- Add fancy ends for top-level tasks
		separator = indent .. "" .. string.rep(separator_char, separator_width) .. ""
	end

	return separator
end

local function highlight_search_results()
	if not state.search_results or #state.search_results == 0 then
		return
	end

	for _, result in ipairs(state.search_results) do
		local line = state.task_to_line[result.id]
		if line then
			-- Highlight the matched text
			vim.api.nvim_buf_add_highlight(
				state.buf,
				ns_id,
				"LazyDoSearchMatch",
				line - 1,
				result.match_start,
				result.match_end
			)

			-- Add a sign to make it easier to spot
			vim.fn.sign_place(0, "LazyDoSearch", "LazyDoSearchSign", state.buf, { lnum = line, priority = 10 })
		end
	end
end

local function is_valid_window()
	return state.win and vim.api.nvim_win_is_valid(state.win)
end

local function is_valid_buffer()
	return state.buf and vim.api.nvim_buf_is_valid(state.buf)
end
function UI.is_valid()
	return is_valid_window() and is_valid_buffer()
end
---Validate task data structure
---@param task table
---@return boolean
---@return string? error
local function validate_task(task)
	if type(task) ~= "table" then
		return false, "Task must be a table"
	end

	-- Check required fields
	local required_fields = {
		"id",
		"content",
		"status",
		"priority",
		"created_at",
		"updated_at",
	}

	for _, field in ipairs(required_fields) do
		if task[field] == nil then
			return false, string.format("Missing required field: %s", field)
		end
	end

	-- Validate status
	if not vim.tbl_contains({ "pending", "done" }, task.status) then
		return false, "Invalid status value"
	end

	-- Validate priority
	if not vim.tbl_contains({ "low", "medium", "high" }, task.priority) then
		return false, "Invalid priority value"
	end

	-- Validate dates
	if task.due_date and type(task.due_date) ~= "number" then
		return false, "Invalid due_date format"
	end

	-- Validate subtasks recursively
	if task.subtasks then
		if type(task.subtasks) ~= "table" then
			return false, "Subtasks must be a table"
		end
		for _, subtask in ipairs(task.subtasks) do
			local valid, err = validate_task(subtask)
			if not valid then
				return false, "Invalid subtask: " .. err
			end
		end
	end

	-- Validate tags
	if task.tags and type(task.tags) ~= "table" then
		return false, "Tags must be an array"
	end

	-- Validate metadata
	if task.metadata and type(task.metadata) ~= "table" then
		return false, "Metadata must be a table"
	end

	return true
end

local function clear_state()
	state.buf = nil
	state.win = nil
	state.tasks = {}
	state.cursor_task = nil
	state.line_to_task = {}
	state.task_to_line = {}
end

local function validate_config()
	if not config then
		return false, "Configuration is missing"
	end

	local required_sections = {
		"theme",
		"icons",
		"features",
		"layout",
	}

	for _, section in ipairs(required_sections) do
		if not config[section] then
			return false, string.format("Missing required configuration section: %s", section)
		end
	end

	-- Validate theme colors
	if not config.theme.colors then
		return false, "Missing theme colors configuration"
	end

	-- Validate icons
	if not config.icons.task_pending or not config.icons.task_done then
		return false, "Missing required task status icons"
	end

	return true
end

-- Improve window creation with proper validation
local function create_window()
	-- Validate configuration first
	local valid, err = validate_config()
	if not valid then
		error("Invalid configuration: " .. err)
		return nil
	end

	-- Create buffer
	local buf = vim.api.nvim_create_buf(false, true)
	vim.api.nvim_buf_set_name(buf, buf_name)

	local buf_opts = {
		modifiable = false,
		buftype = "nofile",
		swapfile = false,
		bufhidden = "wipe",
		filetype = "lazydo",
	}

	for opt, val in pairs(buf_opts) do
		vim.api.nvim_buf_set_option(buf, opt, val)
	end

	local size = Utils.get_window_size()

	-- Enhanced window options
	local win_opts = {
		relative = "editor",
		width = size.width,
		height = size.height,
		row = size.row,
		col = size.col,
		style = "minimal",
		border = config.theme.border or "rounded",
		title = " LazyDo Panel ",
		title_pos = "center",
		footer = " [a/A]dd task/subtask, [d]elete, [D]ate, [e]dit task, [K/J]move, [i]nfo, [m/M]etadata, [n]ote, [t/T]ag, [z]fold, [p]riority, [?]help ",
		footer_pos = "center",
		zindex = 50, -- Ensure window stays on top
	}
	local win = vim.api.nvim_open_win(buf, true, win_opts)

	-- Set window options
	local win_local_opts = {
		wrap = false,
		number = false,
		relativenumber = false,
		cursorline = false,
		signcolumn = "no",
		foldcolumn = "0",
		spell = false,
		list = false,
	}

	for opt, val in pairs(win_local_opts) do
		vim.api.nvim_win_set_option(win, opt, val)
	end

	return buf, win
end

function UI.restore_window_state(state)
	if not state then
		return
	end

	-- Restore cursor position
	if state.cursor then
		pcall(vim.api.nvim_win_set_cursor, state.win, state.cursor)
	end

	-- Restore scroll position
	if state.scroll then
		vim.fn.winrestview(state.scroll)
	end
end

local function render_progress_bar(progress, width)
	local style = config.theme.progress_bar.style
	local bar_width = config.theme.progress_bar.width or width
	local filled = math.floor(bar_width * progress / 100)
	local empty = bar_width - filled
	progress = progress or 0
	width = width or 10 -- Default reasonable width

	-- 󰪞󰪟󰪠󰪡󰪢󰪣󰪤󰪥
	-- Enhanced progress icons based on percentage
	local progress_icon = progress == 100 and config.icons.task_done
		or progress >= 75 and "󰪣 "
		or progress >= 50 and "󰪡 "
		or progress >= 25 and "󰪟 "
		or progress > 0 and "󰪞 "
		or "󰪥 "

	if style == "modern" then
		return string.format(
			"%s[%s%s]%d%%",
			progress_icon,
			string.rep(config.theme.progress_bar.filled, filled),
			string.rep(config.theme.progress_bar.empty, empty),
			progress
		)
	elseif style == "minimal" then
		return string.format("%s %d%%", progress_icon, progress)
	else -- classic
		return string.format(
			"%s%s %d%%",
			string.rep(config.theme.progress_bar.filled, filled),
			string.rep(config.theme.progress_bar.empty, empty),
			progress
		)
	end
end

local function render_note_section(note, indent_level, is_subtask)
	if not note or note == "" then
		return {}, {}
	end

	local indent = string.rep("  ", indent_level)
	local width = get_safe_window_width() - #indent - 4
	local lines = {}
	local regions = {}
	local current_line = 0

	local note_icon = config.icons.note or "󰍨"

	-- Different connectors and styling for parent vs child tasks
	local connectors = {
		parent = {
			top_left = "╭",
			top_right = "╮",
			vertical = "│",
			bottom_left = "╰",
			bottom_right = "╯",
			horizontal = "─",
		},
		child = {
			top_left = "├",
			top_right = "╮",
			vertical = "│",
			bottom_left = "└",
			bottom_right = "╯",
			horizontal = "─",
		},
	}

	local style = is_subtask and connectors.child or connectors.parent

	-- Render header with icon and title
	local header =
		string.format("%s%s%s%s %s Note: ", indent, style.top_left, style.horizontal, style.horizontal, note_icon)
	local header_padding = string.rep(style.horizontal, width - vim.fn.strwidth(header) + #indent)
	header = header .. header_padding .. style.top_right

	table.insert(lines, header)

	-- Add header highlights
	table.insert(regions, {
		line = current_line,
		col = #indent,
		length = #indent + 7, -- connector length
		hl_group = "LazyDoNotesBorder",
	})
	table.insert(regions, {
		line = current_line,
		col = #indent + 8,
		length = 6,
		hl_group = "LazyDoNotesIcon",
	})
	-- table.insert(regions, {
	-- 	line = current_line,
	-- 	col = #indent + #note_icon + 4,
	-- 	length = 6, -- "Note" text
	-- 	hl_group = "LazyDoNotesIcon",
	-- })
	table.insert(regions, {
		line = current_line,
		col = #indent + 19,
		length = #header_padding + 9,
		hl_group = "LazyDoNotesBorder",
	})

	current_line = current_line + 1

	-- Render note content with proper padding and borders
	local content_line = string.format("%s%s %s ", indent, style.vertical, note)

	-- Add padding to align with width
	-- local content_padding = width - vim.fn.strwidth(note) - 2
	-- if content_padding > 0 then
	-- 	content_line = content_line:sub(1, -2) .. string.rep(" ", content_padding) .. style.vertical
	-- end

	table.insert(lines, content_line)

	-- Add content highlights
	table.insert(regions, {
		line = current_line,
		col = #indent,
		length = 1,
		hl_group = "LazyDoNotesBorder",
	})
	table.insert(regions, {
		line = current_line,
		col = #indent + 2,
		length = #note + #indent,
		hl_group = "LazyDoNotesBody",
	})
	table.insert(regions, {
		line = current_line,
		col = #content_line - 1,
		length = 1,
		hl_group = "LazyDoNotesBorder",
	})

	current_line = current_line + 1

	-- Render footer
	local footer = string.format(
		"%s%s%s%s",
		indent,
		style.bottom_left,
		string.rep(style.horizontal, width - 1),
		style.bottom_right
	)

	table.insert(lines, footer)

	-- Add footer highlights
	table.insert(regions, {
		line = current_line,
		col = #indent,
		length = #footer - #indent,
		hl_group = "LazyDoNotesBorder",
	})

	return lines, regions
end
local function render_task_info(task, indent_level)
	if not state.show_task_info then
		return "", {}
	end
	local indent = string.rep("  ", indent_level + 1)
	local lines = {}
	local regions = {}

	-- Format timestamps with icons
	local created_icon = config.icons.created or "󰃰"
	local updated_icon = config.icons.updated or "󰦒"
	local recurring_icon = "󰑖"

	local created_at = os.date("%Y-%m-%d/%H:%M", task.created_at)
	local updated_at = task.updated_at > task.created_at and os.date("%Y-%m-%d/%H:%M", task.updated_at) or nil

	-- Add creation time with proper highlighting
	local created_line = string.format("%s%s Created: %s", indent, created_icon, created_at)
	table.insert(lines, created_line)
	table.insert(regions, {
		line = #lines - 1,
		col = #indent,
		length = #created_line - #indent,
		hl_group = "LazyDoTaskInfo",
	})

	-- Add update time if different
	if updated_at then
		local updated_line = string.format("%s Updated: %s", updated_icon, updated_at)
		table.insert(lines, updated_line)
		table.insert(regions, {
			line = #lines - 1,
			col = #indent,
			length = #updated_line - #indent,
			hl_group = "LazyDoTaskInfo",
		})
	end

	-- Add recurring info if present
	if task.recurring then
		local recurring_line = string.format("%s %s", recurring_icon, task.recurring)
		table.insert(lines, recurring_line)
		table.insert(regions, {
			line = #lines - 1,
			col = #indent,
			length = #recurring_line - #indent,
			hl_group = "LazyDoTaskInfo",
		})
	end
	local single_lines = table.concat(lines, "|")
	return single_lines, regions
end

local function render_tags(task)
	if not config.features.tags.enabled or not task.tags or #task.tags == 0 then
		return "", {}
	end

	local tags = {}
	local regions = {}
	local start_col = 0

	for _, tag in ipairs(task.tags) do
		local formatted_tag = config.features.tags.prefix .. tag
		table.insert(tags, formatted_tag)

		-- Add highlight for each tag
		table.insert(regions, {
			col = start_col + 1,
			length = #formatted_tag,
			hl_group = "LazyDoTags",
		})
		start_col = start_col + #formatted_tag + 1
	end

	return " " .. table.concat(tags, " "), regions
end

local function render_task_header(task, level, is_last)
	if not task then
		return "", {}
	end

	-- local base_indent = string.rep(" ", ensure_number(level, 0) * ensure_number(config.theme.indent.size, 2))
	local base_indent = string.rep(" ", ensure_number(level, 0) * 2)
	local regions = {}
	local current_col = #base_indent

	-- Helper function to add region
	local function add_region(length, hl_group, offset)
		table.insert(regions, {
			col = current_col + (offset or 0),
			length = ensure_number(length, 0) + 1,
			hl_group = hl_group or "Normal",
		})
		current_col = current_col + ensure_number(length, 0) + (offset or 0)
	end

	-- Build header components
	local components = {
		indent = base_indent,
		connector = "",
		status = "",
		priority = "",
		fold = "",
		content = task.content or "",
		tags = "",
		due = "",
		overdue = "",
		recurring = "",
		progress = "",
		info = "",
	}

	-- Add connector for subtasks
	if level > 0 then
		components.connector = is_last and config.theme.indent.last_connector or config.theme.indent.connector
		add_region(#components.connector, "LazyDoConnector")
	end

	-- Add status icon
	local status_icon = task.status == "done" and config.icons.task_done or config.icons.task_pending
	local status_hl = task.status == "done" and "LazyDoTaskDone"
		or (
			Task.is_overdue(task) and "LazyDoTaskOverdue"
			or (
				task.status == "blocked" and "LazyDoTaskBlocked"
				or (task.status == "in_progress" and "LazyDoTaskInProgress" or "LazyDoTaskPending")
			)
		)

	components.status = " " .. status_icon .. " "
	add_region(#status_icon, status_hl, 1)

	-- Add priority icon
	if config.icons.priority and config.icons.priority[task.priority] then
		local priority_icon = config.icons.priority[task.priority]
		components.priority = priority_icon .. " "
		add_region(#priority_icon, "LazyDoPriority" .. task.priority:sub(1, 1):upper() .. task.priority:sub(2))
	end

	-- Add folding indicator
	if config.features.folding.enabled and task.subtasks and #task.subtasks > 0 then
		components.fold = (
			task.collapsed and config.features.folding.icons.folded or config.features.folding.icons.unfolded
		) .. " "
		add_region(#components.fold - 1, "LazyDoFoldIcon", 1)
	end

	-- Add task content
	add_region(#components.content, status_hl, 1)

	-- Add tags
	if config.features.tags.enabled and task.tags and #task.tags > 0 then
		local tags_str, tag_regions = render_tags(task)
		if tags_str then
			components.tags = tags_str
			for _, region in ipairs(tag_regions) do
				add_region(region.length, region.hl_group, 1)
			end
		end
	end

	-- Add due date
	if task.due_date then
		local due_text = string.format(" %s %s", config.icons.due_date or "", Task.get_due_date_relative(task))
		components.due = due_text

		local days_until_due = math.floor((task.due_date - os.time()) / (24 * 60 * 60))
		local due_hl = days_until_due < 0 and "LazyDoDueDateOverdue"
			or days_until_due <= 2 and "LazyDoDueDateNear"
			or "LazyDoDueDate"

		add_region(#due_text, due_hl, 1)
	end

	-- Add progress bar
	if config.theme.progress_bar and config.theme.progress_bar.enabled then
		local progress = Task.calculate_progress(task)
		local progress_bar = render_progress_bar(progress, config.theme.progress_bar.width)
		if progress_bar then
			local spacer = " | "
			components.progress = spacer .. progress_bar

			local progress_hl = progress == 100 and "LazyDoProgressComplete"
				or progress > 0 and "LazyDoProgressPartial"
				or "LazyDoProgressNone"

			add_region(#progress_bar, progress_hl, #spacer)
		end
	end
	if config.features.task_info and config.features.task_info.enabled then
		local info_lines = render_task_info(task, 0)
		if info_lines then
			components.info = info_lines
			add_region(#info_lines, "LazyDoTaskInfo", 4)
		end
	end

	-- Construct final header line
	local header_line = table.concat({
		components.indent,
		components.connector,
		components.status,
		components.priority,
		components.fold,
		components.content,
		components.tags,
		components.due,
		components.recurring,
		components.overdue,
		components.progress,
		components.info,
	})

	return header_line, regions
end

local function render_task(task, level, current_line, is_last)
	if not task then
		return {}, {}, {}
	end

	level = ensure_number(level, 0)
	current_line = ensure_number(current_line, 0)

	local lines = {}
	local regions = {}
	local mappings = {}

	-- Render task header
	local header_line, header_regions = render_task_header(task, level, is_last)
	table.insert(lines, header_line)

	-- Add header highlights
	for _, region in ipairs(header_regions) do
		table.insert(regions, {
			line = current_line,
			start = ensure_number(region.col, 0),
			length = ensure_number(region.length, 0),
			hl_group = region.hl_group or "Normal",
		})
	end

	-- Store task mapping
	if task.content then
		mappings[current_line + 1] = {
			task = task,
			mapping = {
				start_line = current_line,
				content_start = #header_line - #task.content,
				content_end = #header_line,
			},
		}
	end

	current_line = current_line + 1

	if task.notes then
		local note_lines, note_regions = render_note_section(task.notes, level + 1, level > 0)
		if note_lines and #note_lines > 0 then
			-- Add note lines
			for _, line in ipairs(note_lines) do
				table.insert(lines, line)
			end

			-- Add note highlights with proper line offsets
			for _, region in ipairs(note_regions) do
				table.insert(regions, {
					line = current_line + region.line,
					start = ensure_number(region.col, 0),
					length = ensure_number(region.length, 0),
					hl_group = region.hl_group,
				})
			end

			current_line = current_line + #note_lines
		end
	end

	-- Add spacing for top-level tasks
	if level == 2 then
		table.insert(lines, "")
		current_line = current_line + 1
	end

	-- Render subtasks
	if task.subtasks and #task.subtasks > 0 and not task.collapsed then
		for i, subtask in ipairs(task.subtasks) do
			local sub_lines, sub_regions, sub_mappings =
				render_task(subtask, level + 1, current_line, i == #task.subtasks)

			vim.list_extend(lines, sub_lines)
			vim.list_extend(regions, sub_regions)

			for line_nr, mapping in pairs(sub_mappings) do
				mappings[line_nr] = mapping
			end

			current_line = current_line + #sub_lines
		end
	end

	current_line = current_line + 1
	if
		config.features.metadata
		and config.features.metadata.enabled
		and task.metadata
		and not vim.tbl_isempty(task.metadata)
	then
		local metadata_lines, metadata_regions = UI.render_metadata(task, level + 1)
		if metadata_lines and #metadata_lines > 0 then
			-- Add metadata lines
			for _, line in ipairs(metadata_lines) do
				table.insert(lines, line)
			end

			-- Add metadata highlights with proper line offsets
			for _, region in ipairs(metadata_regions) do
				table.insert(regions, {
					line = current_line + region.line,
					start = ensure_number(region.start, 0),
					length = ensure_number(region.length, 0),
					hl_group = region.hl_group,
				})
			end

			current_line = current_line + #metadata_lines
		end
	end
	if task.relations and #task.relations > 0 then
		local relation_lines, relation_regions = UI.render_relations_section(task, level + 1)
		if relation_lines and #relation_lines > 0 then
			-- Add relation lines
			for _, line in ipairs(relation_lines) do
				table.insert(lines, line)
			end

			-- Add relation highlights with proper line offsets
			for _, region in ipairs(relation_regions) do
				table.insert(regions, {
					line = current_line + region.line,
					start = region.start,
					length = region.length,
					hl_group = region.hl_group,
				})
			end

			current_line = current_line + #relation_lines
		end
	end
	-- Add separator for top-level tasks
	if level == 0 then
		local separator =
			create_task_separator(level, task.subtasks and #task.subtasks > 0, task.collapsed, get_safe_window_width())
		table.insert(lines, separator)
		table.insert(regions, {
			line = current_line,
			start = 0,
			length = #separator,
			hl_group = "LazyDoTaskBorder",
		})
		current_line = current_line + 1
	end

	return lines, regions, mappings
end

local function ensure_valid_window()
	if not state.win then
		error("Window handle is nil")
		return false
	end
	if not vim.api.nvim_win_is_valid(state.win) then
		error("Invalid window handle")
		return false
	end
	return true
end

function UI.render()
	if not state.buf or not state.win then
		return
	end
	if not ensure_valid_window() then
		return
	end

	vim.api.nvim_buf_clear_namespace(state.buf, ns_id, 0, -1)

	local lines = {}
	local all_regions = {}
	local current_line = 0

	-- Get window width for proper centering and layout
	local width = get_safe_window_width()

	-- Render header section
	local title = config.title or " LazyDo Tasks "
	local centered_title = Utils.Str.center(title, width)
	local header_separator = "╭" .. string.rep("━", width - 2) .. "╮"

	-- Add header components
	table.insert(lines, centered_title)
	table.insert(all_regions, {
		line = current_line,
		start = math.floor((width - #title) / 2),
		length = #title,
		hl_group = "LazyDoTitle",
	})
	current_line = current_line + 1

	-- Add separator after title
	table.insert(lines, header_separator)
	table.insert(all_regions, {
		line = current_line,
		start = 0,
		length = #header_separator,
		hl_group = "LazyDoHeaderSeparator",
	})
	current_line = current_line + 1

	-- Add empty line after header
	table.insert(lines, "")
	current_line = current_line + 1

	-- Reset task mappings
	state.line_to_task = {}
	state.task_to_line = {}

	-- Render tasks
	local tasks_to_render = state.filtered_tasks or state.tasks
	for i, task in ipairs(tasks_to_render) do
		-- Add spacing between tasks based on config
		if i > 1 and config.layout.spacing > 0 then
			for _ = 1, config.layout.spacing do
				table.insert(lines, "")
				current_line = current_line + 1
			end
		end

		-- Render task and its components
		local task_lines, task_regions, task_mappings = render_task(
			task,
			0, -- start at root level
			current_line,
			false -- not last by default
		)

		-- Add task content
		vim.list_extend(lines, task_lines)
		vim.list_extend(all_regions, task_regions)

		-- Update task mappings
		for line_nr, mapping in pairs(task_mappings) do
			state.line_to_task[line_nr] = mapping
			state.task_to_line[mapping.task.id] = line_nr
		end

		current_line = current_line + #task_lines
	end

	-- Add footer if no tasks
	if #tasks_to_render == 0 then
		local empty_msg = "No tasks found. Press 'a' to add a new task."
		local centered_msg = Utils.Str.center(empty_msg, width)
		table.insert(lines, "")
		table.insert(lines, centered_msg)
		table.insert(all_regions, {
			line = current_line + 1,
			start = math.floor((width - #empty_msg) / 2),
			length = #empty_msg,
			hl_group = "LazyDoEmptyMessage",
		})
	end

	-- Add final separator
	local footer_separator = "╰" .. string.rep("━", width - 2) .. "╯"
	table.insert(lines, footer_separator)
	table.insert(all_regions, {
		line = #lines - 1,
		start = 0,
		length = #footer_separator,
		hl_group = "LazyDoHeaderSeparator",
	})

	-- Update buffer content
	vim.api.nvim_buf_set_option(state.buf, "modifiable", true)
	vim.api.nvim_buf_set_lines(state.buf, 0, -1, false, lines)

	-- Group regions by line for more efficient highlighting
	local grouped_regions = {}
	for _, region in ipairs(all_regions) do
		if region.line and region.start and region.length and region.hl_group then
			grouped_regions[region.line] = grouped_regions[region.line] or {}
			table.insert(grouped_regions[region.line], {
				start = region.start,
				length = region.length,
				hl_group = region.hl_group,
			})
		end
	end

	-- Apply highlights efficiently by line
	for line, regions in pairs(grouped_regions) do
		-- Sort regions by start position to ensure proper layering
		table.sort(regions, function(a, b)
			return a.start < b.start
		end)

		for _, region in ipairs(regions) do
			pcall(
				vim.api.nvim_buf_add_highlight,
				state.buf,
				ns_id,
				region.hl_group,
				line,
				region.start,
				region.start + region.length
			)
		end
	end

	-- Apply search highlights if any
	if #(state.search_results or {}) > 0 then
		highlight_search_results()
	end

	-- Lock buffer after rendering
	vim.api.nvim_buf_set_option(state.buf, "modifiable", false)

	-- Update status line if configured
	if config.features.statusline and config.features.statusline.enabled then
		vim.api.nvim_command("redrawstatus!")
	end
end
local function show_help()
	local help_text = {
		"LazyDo Keybindings:",
		"",
		"Task Management:",
		" <CR>      Toggle task status",
		" a         Add new task",
		" A         Add subtask",
		"<leader>a      Quick task",
		" d         Delete task",
		" e         Edit task",
		"",
		"Task Properties:",
		" p         Cycle priority",
		" n         Add/edit notes",
		" D         Set due date",
		" t         Add tags",
		" T         Edit tags",
		"<leader>t   Remove tags",
		" m         Add metadata",
		" M         Edit metadata",
		"<leader>md   Remove metadata",
		" i         Toggle info",
		"",
		"Task Organization:",
		" K         Move task up",
		" J         Move task down",
		" z         Toggle fold",
		"<leader>x  Convert to subtask",
		"<leader>X  Convert to Task",
		"",
		"Links and Relations",
		"<leader>l  Show relations",
		"<leader>L  Add relation",
		"",
		"Filtering and Sorting:",
		" <leader>sp Sort by priority",
		" <leader>sd Sort by due date",
		" <leader>ss Sort by status",
		"",
		"Export/Import:",
		" <leader>m  Save to markdown file",
		"",
		"Other:",
		" ?         Show this help",
	}

	local buf = vim.api.nvim_create_buf(false, true)
	local width = math.min(60, vim.o.columns - 4)
	local height = #help_text
	local row = math.floor((vim.o.lines - height) / 2)
	local col = math.floor((vim.o.columns - width) / 2)

	vim.api.nvim_buf_set_lines(buf, 0, -1, false, help_text)
	vim.api.nvim_buf_set_option(buf, "modifiable", false)
	vim.api.nvim_buf_set_option(buf, "buftype", "nofile")

	local win = vim.api.nvim_open_win(buf, true, {
		relative = "editor",
		width = width,
		height = height,
		row = row,
		col = col,
		style = "minimal",
		border = "rounded",
		title = " Help ",
		title_pos = "center",
	})

	-- Close help window on any key press
	vim.api.nvim_buf_set_keymap(buf, "n", "q", "", {
		callback = function()
			vim.api.nvim_win_close(win, true)
			vim.api.nvim_buf_delete(buf, { force = true })
		end,
		noremap = true,
		silent = true,
	})
end

---Refresh the UI display
function UI.refresh()
	if is_valid_window() and is_valid_buffer() then
		local pos = vim.api.nvim_win_get_cursor(state.win)
		UI.render()
		pcall(vim.api.nvim_win_set_cursor, state.win, pos)
	end
end

-- Wrap action callback to ensure UI refresh
local function wrap_action_callback(fn)
	return function(...)
		local result = fn(...)
		UI.refresh()
		return result
	end
end

-- ui.lua

function UI.setup_keymaps()
	local function map(key, fn, desc)
		vim.api.nvim_buf_set_keymap(state.buf, "n", key, "", {
			callback = wrap_action_callback(fn),
			noremap = true,
			silent = true,
			desc = "LazyDo: " .. desc,
		})
	end

	-- Task Movement
	map("K", function()
		local task = UI.get_task_under_cursor()
		if task then
			Actions.move_task_up(state.tasks, task.id, state.on_task_update)
		end
	end, "Move Task Up")

	map("J", function()
		local task = UI.get_task_under_cursor()
		if task then
			Actions.move_task_down(state.tasks, task.id, state.on_task_update)
		end
	end, "Move Task Down")

	-- Task Status
	map("<CR>", function()
		local task = UI.get_task_under_cursor()
		if task then
			Actions.toggle_status(state.tasks, task.id, state.on_task_update)
			UI.refresh()
		end
	end, "Toggle Task")

	-- Task Management
	map("d", function()
		local task = UI.get_task_under_cursor()
		if task then
			Actions.delete_task(state.tasks, task.id, state.on_task_update)
			UI.refresh()
		end
	end, "Delete Task")
	map("i", function()
		UI.toggle_task_info()
	end, "Toggle Task Info")
	map("e", function()
		local task = UI.get_task_under_cursor()
		if task then
			vim.ui.input({
				prompt = "Edit task:",
				default = task.content,
			}, function(new_content)
				if new_content and new_content ~= "" then
					Actions.update_task(state.tasks, task.id, { content = new_content }, state.on_task_update)
					UI.refresh()
				end
			end)
		end
	end, "Edit Task")

	-- Task Properties
	map("p", function()
		local task = UI.get_task_under_cursor()
		if task then
			Actions.cycle_priority(state.tasks, task.id, state.on_task_update)
			UI.refresh()
		end
	end, "Toggle Priority")

	map("n", function()
		local task = UI.get_task_under_cursor()
		if task then
			vim.ui.input({
				prompt = "Add note:",
				default = task.notes or "",
			}, function(notes)
				if notes then
					Actions.set_notes(state.tasks, task.id, notes, state.on_task_update)
					UI.refresh()
				end
			end)
		end
	end, "Set Note")

	map("D", function()
		local task = UI.get_task_under_cursor()
		if task then
			vim.ui.input({
				prompt = "Set due (YYYY-MM-DD/today/tomorrow/Nd):",
				default = task.due_date and Utils.Date.format(task.due_date) or "",
			}, function(date_str)
				if date_str then
					Actions.set_due_date(state.tasks, task.id, date_str, state.on_task_update)
					UI.refresh()
				end
			end)
		end
	end, "Set Date")

	-- Task Hierarchy
	map("<leader>x", function()
		local task = UI.get_task_under_cursor()
		if task then
			vim.ui.select(state.tasks, {
				prompt = "Select parent task:",
				format_item = function(t)
					return t.content
				end,
			}, function(parent)
				if parent and parent.id ~= task.id then
					Actions.convert_to_subtask(state.tasks, task.id, parent.id, state.on_task_update)
					UI.refresh()
				end
			end)
		end
	end, "Convert To SubTask")
	map("<leader>X", function()
		local task = UI.get_task_under_cursor()
		if not task then
			UI.show_feedback("No task selected", "warn")
			return
		end

		-- Find the parent task by traversing all tasks
		local function find_parent_and_remove(tasks, target_id)
			for _, t in ipairs(tasks) do
				if t.subtasks then
					for i, subtask in ipairs(t.subtasks) do
						if subtask.id == target_id then
							-- Found the subtask, remove it from parent
							table.remove(t.subtasks, i)
							return true
						end
					end
					-- Recursively check nested subtasks
					if find_parent_and_remove(t.subtasks, target_id) then
						return true
					end
				end
			end
			return false
		end

		-- Try to find and remove the task from its parent
		if find_parent_and_remove(state.tasks, task.id) then
			-- Add the task to main tasks list
			table.insert(state.tasks, task)

			if state.on_task_update then
				state.on_task_update(state.tasks)
			end
			UI.show_feedback("Converted subtask to main task")
			UI.refresh()
		else
			UI.show_feedback("Task is not a subtask", "warn")
		end
	end, "Convert SubTask to Task")
	map("<leader>m", function()
		local task = UI.get_task_under_cursor()
		if task then
			vim.ui.input({
				prompt = "Set filename to save tasks in .md:",
				default = vim.fn.expand("%") or "",
			}, function(name)
				if name then
					Actions.export_to_markdown(state.tasks, name)
					UI.show_feedback("The tasks saved in " .. name, "info")
					UI.refresh()
				end
			end)
		end
	end, "Export to markdown")

	map("?", function()
		show_help()
	end, "Help Window")

	-- Add task creation keymap
	map("a", function()
		UI.add_task()
	end, "Add Task")
	map("A", function()
		UI.add_subtask()
	end, "Add SubTask")
	map("<leader>a", function()
		vim.ui.input({
			prompt = "Quick task:",
		}, function(content)
			if content and content ~= "" then
				local task = Actions.add_task(state.tasks, content, {
					priority = "medium",
					due_date = nil,
				}, state.on_task_update)
				if task then
					UI.refresh()
					UI.show_feedback("Quick task added")
				end
			end
		end)
	end, "Quick Add Task")

	map("z", function()
		UI.toggle_fold()
	end, "Toggle Fold")

	map("t", function()
		UI.add_tag()
	end, "Add Tag")
	map("T", function()
		UI.edit_tag()
	end, "Edit Tag")
	map("<leader>t", function()
		UI.remove_tag()
	end, "Remove Tag")
	map("m", function()
		UI.set_metadata()
	end, "Set MetaData")
	map("M", function()
		UI.edit_metadata()
	end, "Edit Metadata")
	map("<leader>md", function()
		local task = UI.get_task_under_cursor()
		if not task then
			UI.show_feedback("No task selected", "warn")
			return
		end

		if not task.metadata or vim.tbl_isempty(task.metadata) then
			UI.show_feedback("No metadata to delete", "warn")
			return
		end

		local metadata_keys = vim.tbl_keys(task.metadata)
		table.sort(metadata_keys)

		vim.ui.select(metadata_keys, {
			prompt = "Select metadata to delete:",
			format_item = function(key)
				return string.format("%s: %s", key, tostring(task.metadata[key]))
			end,
		}, function(choice)
			if choice then
				task.metadata[choice] = nil
				if vim.tbl_isempty(task.metadata) then
					task.metadata = nil
				end
				if state.on_task_update then
					state.on_task_update(state.tasks)
				end
				UI.show_feedback("Metadata deleted")
				UI.refresh()
			end
		end)
	end, "Delete Metadata")
	map("<leader>l", function()
		UI.show_relations()
	end, "Show Relations")
	map("<leader>L", function()
		local task = UI.get_task_under_cursor()
		if task then
			vim.ui.select(state.tasks, {
				prompt = "Select target task:",
				format_item = function(t)
					return t.content
				end,
			}, function(target)
				if target then
					vim.ui.select({ "blocks", "depends_on", "related_to", "duplicates" }, {
						prompt = "Relation type:",
					}, function(rel_type)
						if rel_type then
							Task.add_relation(task, target.id, rel_type)
							UI.refresh()
						end
					end)
				end
			end)
		end
	end, "Add Relation")

	-- Add sort keymaps
	map("<leader>sp", function()
		if #state.tasks == 0 then
			UI.show_feedback("No tasks to sort", "warn")
			return
		end
		Task.sort_by_priority(state.tasks)
		if state.on_task_update then
			state.on_task_update(state.tasks)
		end
		UI.show_feedback("Tasks sorted by priority")
		UI.refresh()
	end, "Sort by Priority")

	map("<leader>sd", function()
		if #state.tasks == 0 then
			UI.show_feedback("No tasks to sort", "warn")
			return
		end
		Task.sort_by_due_date(state.tasks)
		if state.on_task_update then
			state.on_task_update(state.tasks)
		end
		UI.show_feedback("Tasks sorted by due date")
		UI.refresh()
	end, "Sort by Due")

	-- Add new sort by status keymap
	map("<leader>ss", function()
		if #state.tasks == 0 then
			UI.show_feedback("No tasks to sort", "warn")
			return
		end
		Task.sort_by_status(state.tasks)
		if state.on_task_update then
			state.on_task_update(state.tasks)
		end
		UI.show_feedback("Tasks sorted by status")
		UI.refresh()
	end, "Sort by Status")
end
---Show feedback to user
---@param message string Message to show
---@param level? "info"|"warn"|"error" Feedback level
function UI.show_feedback(message, level)
	level = level or "info"
	local levels = {
		info = vim.log.levels.INFO,
		warn = vim.log.levels.WARN,
		error = vim.log.levels.ERROR,
	}

	vim.notify(message, levels[level], {
		title = "LazyDo",
		icon = "󱃔 ",
		timeout = 2000,
	})
end
function UI.toggle_task_info()
	state.show_task_info = not state.show_task_info
	UI.refresh()
	UI.show_feedback(state.show_task_info and "Task info shown" or "Task info hidden")
end
function UI.filter_tasks(filter_fn)
	if not state.tasks then
		return
	end
	local filtered = vim.tbl_filter(filter_fn, state.tasks)
	state.filtered_tasks = filtered
	UI.refresh()
end

-- Quick filters
UI.filters = {
	today = function()
		UI.filter_tasks(function(task)
			return Task.is_due_today(task)
		end)
		UI.refresh()
	end,
	overdue = function()
		UI.filter_tasks(function(task)
			return Task.is_overdue(task)
		end)
		UI.refresh()
	end,
	high_priority = function()
		UI.filter_tasks(function(task)
			return task.priority == "high"
		end)
		UI.refresh()
	end,
}

-- Task sorting capabilities
function UI.sort_tasks(sort_fn)
	if not state.tasks then
		return
	end
	table.sort(state.tasks, sort_fn)
	UI.refresh()
end

-- Quick sorts
UI.sorts = {
	by_priority = function()
		local priority_order = { low = 1, medium = 2, high = 3 }
		UI.sort_tasks(function(a, b)
			return priority_order[a.priority] > priority_order[b.priority]
		end)
		UI.refresh()
	end,
	by_due_date = function()
		UI.sort_tasks(function(a, b)
			-- If both tasks have no due date, maintain current order
			if not a.due_date and not b.due_date then
				return false
			end
			-- Tasks without due dates go to the end
			if not a.due_date then
				return false
			end
			if not b.due_date then
				return true
			end
			-- Compare actual dates
			return a.due_date < b.due_date
		end)
		UI.refresh()
	end,
}
-- Task grouping
function UI.group_tasks(group_fn)
	if not state.tasks then
		return
	end
	local groups = {}
	for _, task in ipairs(state.tasks) do
		local group = group_fn(task)
		groups[group] = groups[group] or {}
		table.insert(groups[group], task)
	end
	return groups
end

-- Quick groups
UI.groups = {
	by_status = function()
		return UI.group_tasks(function(task)
			return task.status
		end)
	end,
	by_priority = function()
		return UI.group_tasks(function(task)
			return task.priority
		end)
	end,
}

-- Task export capabilities
function UI.export_tasks(format)
	local exporters = {
		markdown = function(tasks)
			local lines = {}
			local function add_task(task, level)
				local indent = string.rep("  ", level)
				local status = task.status == "done" and "[x]" or "[ ]"
				local line = string.format("%s%s %s", indent, status, task.content)
				table.insert(lines, line)
				if task.subtasks then
					for _, subtask in ipairs(task.subtasks) do
						add_task(subtask, level + 1)
					end
				end
			end
			for _, task in ipairs(tasks) do
				add_task(task, 0)
			end
			return table.concat(lines, "\n")
		end,
		json = function(tasks)
			return vim.fn.json_encode(tasks)
		end,
	}

	local exporter = exporters[format]
	if exporter then
		return exporter(state.tasks)
	end
end
function UI.add_task()
	vim.ui.input({
		prompt = "Task content:",
	}, function(content)
		if not content or content == "" then
			UI.show_feedback("Task content cannot be empty", "warn")
			return
		end

		vim.ui.select({ "low", "medium", "high" }, {
			prompt = "Select priority:",
			format_item = function(item)
				return string.format("%s Priority", item:sub(1, 1):upper() .. item:sub(2))
			end,
		}, function(priority)
			if not priority then
				return
			end

			vim.ui.input({
				prompt = "Due (YYYY-MM-DD/today/tomorrow/Nd, optional):",
			}, function(due_date)
				local timestamp = due_date and due_date ~= "" and Utils.Date.parse(due_date)

				vim.ui.input({
					prompt = "Notes (optional):",
					completion = "file",
				}, function(notes)
					local task = Actions.add_task(state.tasks, content, {
						priority = priority,
						due_date = timestamp,
						notes = notes ~= "" and notes or nil,
					}, state.on_task_update)

					if task then
						UI.refresh()
						UI.show_feedback("Task added successfully")
					end
				end)
			end)
		end)
	end)
end

function UI.toggle_task()
	local task = UI.get_task_under_cursor()
	if not task then
		return
	end

	Actions.toggle_status(state.tasks, task.id, function(tasks)
		if state.on_task_update then
			state.on_task_update(tasks)
		end
		-- Recalculate progress after status change
		local progress = Task.calculate_progress(task)
		UI.show_feedback(string.format("Task marked as %s (%d%% complete)", task.status, progress))
	end)
	UI.refresh()
end

function UI.edit_task()
	local task = UI.get_task_under_cursor()
	if not task then
		return
	end

	vim.ui.input({
		prompt = "Edit task:",
		default = task.content,
	}, function(new_content)
		if new_content and new_content ~= "" then
			Actions.update_task(state.tasks, task.id, { content = new_content }, state.on_task_update)
		end
	end)
	UI.refresh()
end

function UI.add_note()
	local task = UI.get_task_under_cursor()
	if not task then
		return
	end

	vim.ui.input({
		prompt = "Add note:",
		default = task.notes or "",
	}, function(notes)
		if notes then
			Actions.set_notes(state.tasks, task.id, notes, state.on_task_update)
		end
	end)
	UI.refresh()
end

function UI.cycle_priority()
	local task = UI.get_task_under_cursor()
	if not task then
		return
	end

	Actions.cycle_priority(state.tasks, task.id, state.on_task_update)
end

function UI.set_due_date()
	local task = UI.get_task_under_cursor()
	if not task then
		return
	end

	vim.ui.input({
		prompt = "Set due date (YYYY-MM-DD/today/tomorrow/Nd):",
		default = task.due_date and Utils.Date.format(task.due_date) or "",
	}, function(date_str)
		if date_str then
			Actions.set_due_date(state.tasks, task.id, date_str, state.on_task_update)
		end
	end)
	UI.refresh()
end

function UI.get_task_under_cursor()
	if not state.win or not state.buf then
		return nil
	end

	-- Get current cursor position
	local cursor = vim.api.nvim_win_get_cursor(state.win)
	local line_nr = cursor[1]

	-- Find the task for current line by checking line range
	for task_line, line_info in pairs(state.line_to_task) do
		local task_end_line = task_line
		-- Find end of task section (next task start or end of buffer)
		for i = task_line + 1, vim.api.nvim_buf_line_count(state.buf) do
			local next_line_info = state.line_to_task[i]
			if next_line_info then
				task_end_line = i - 1
				break
			end
			task_end_line = i
		end

		-- Check if cursor is within task range
		if line_nr >= task_line and line_nr <= task_end_line then
			state.cursor_task = line_info.task
			return line_info.task
		end
	end

	return nil
end

function UI.update_task(task)
	if not validate_task(task) then
		UI.show_feedback("Cannot update invalid task", "error")
		return
	end

	if state.on_task_update then
		local success, err = pcall(state.on_task_update, task)
		if not success then
			UI.show_feedback("Failed to update task: " .. tostring(err), "error")
			return
		end
	end

	UI.refresh()
end

function UI.update_task_status(task_id, new_status)
	local task = UI.find_task_by_id(task_id)
	if not task then
		UI.show_feedback("Task not found", "error")
		return
	end

	local old_status = task.status
	task.status = new_status
	task.updated_at = os.time()

	-- Calculate progress
	local progress = Task.calculate_progress(task)

	-- Update parent task progress if exists
	if task.parent_id then
		local parent = UI.find_task_by_id(task.parent_id)
		if parent then
			parent.progress = Task.calculate_progress(parent)
		end
	end

	-- Show feedback with progress
	UI.show_feedback(
		string.format("Task status changed from %s to %s (%d%% complete)", old_status, new_status, progress)
	)

	UI.refresh()
end
function UI.find_task_by_id(task_id)
	local function search_tasks(tasks)
		for _, task in ipairs(tasks) do
			if task.id == task_id then
				return task
			end
			if task.subtasks then
				local found = search_tasks(task.subtasks)
				if found then
					return found
				end
			end
		end
		return nil
	end

	return search_tasks(state.tasks)
end

-- Add task folding support
function UI.toggle_fold()
	local task = UI.get_task_under_cursor()
	if task and task.subtasks and #task.subtasks > 0 then
		local cursor_pos = vim.api.nvim_win_get_cursor(state.win)
		task.collapsed = not task.collapsed
		UI.refresh()
		vim.api.nvim_win_set_cursor(state.win, cursor_pos)
	end
end
-- Add task tags support
function UI.add_tag()
	local task = UI.get_task_under_cursor()
	if task then
		vim.ui.input({
			prompt = "Add tag:",
		}, function(tag)
			if tag and tag ~= "" then
				Task.add_tag(task, tag)
				if state.on_task_update then
					state.on_task_update(state.tasks)
				end
				UI.refresh()
			end
		end)
	end
end
function UI.edit_tag()
	local task = UI.get_task_under_cursor()
	if not task or not task.tags or #task.tags == 0 then
		UI.show_feedback("No tags to edit", "warn")
		return
	end

	vim.ui.select(task.tags, {
		prompt = "Select tag to edit:",
	}, function(selected_tag)
		if selected_tag then
			vim.ui.input({
				prompt = "Edit tag:",
				default = selected_tag,
			}, function(new_tag)
				if new_tag and new_tag ~= "" then
					Task.remove_tag(task, selected_tag)
					Task.add_tag(task, new_tag)
					if state.on_task_update then
						state.on_task_update(state.tasks)
					end
					UI.refresh()
				end
			end)
		end
	end)
end
function UI.remove_tag()
	local task = UI.get_task_under_cursor()

	if not task or not task.tags or #task.tags == 0 then
		UI.show_feedback("No tags to remove", "warn")
		return
	end

	vim.ui.select(task.tags, {
		prompt = "Select tag to remove:",
		format_item = function(tag)
			return tag
		end,
	}, function(selected_tag)
		if selected_tag then
			Task.remove_tag(task, selected_tag)
		end
		if state.on_task_update then
			state.on_task_update(state.tasks)
		end
		UI.refresh()
	end)
end

function UI.add_subtask()
	local parent_task = UI.get_task_under_cursor()
	if not parent_task then
		UI.show_feedback("No task selected", "warn")
		return
	end

	-- Get content first
	vim.ui.input({
		prompt = "Subtask content:",
		default = "",
	}, function(content)
		if not content or content == "" then
			UI.show_feedback("Subtask content cannot be empty", "warn")
			return
		end

		-- Then get priority
		vim.ui.select({ "low", "medium", "high" }, {
			prompt = "Select priority:",
			format_item = function(item)
				return string.format("%s Priority", item:sub(1, 1):upper() .. item:sub(2))
			end,
			default = "medium",
		}, function(priority)
			if not priority then
				return
			end

			-- Get due date
			vim.ui.input({
				prompt = "Due date (YYYY-MM-DD/today/tomorrow/Nd, optional):",
			}, function(due_date)
				local timestamp = due_date and due_date ~= "" and Utils.Date.parse(due_date)

				-- Finally get notes
				vim.ui.input({
					prompt = "Notes (optional):",
					completion = "file",
				}, function(notes)
					-- Create and add the subtask
					local subtask = Task.new(content, {
						priority = priority,
						parent_id = parent_task.id,
						due_date = timestamp,
						notes = notes ~= "" and notes or nil,
					})

					-- Initialize subtasks array if needed
					parent_task.subtasks = parent_task.subtasks or {}
					table.insert(parent_task.subtasks, subtask)

					-- Update state and UI
					if state.on_task_update then
						state.on_task_update(state.tasks)
					end

					-- Show success message and refresh
					UI.show_feedback(string.format("Added subtask to '%s'", parent_task.content))
					UI.refresh()

					-- Ensure parent task is unfolded to show new subtask
					if parent_task.collapsed then
						parent_task.collapsed = false
						UI.refresh()
					end
				end)
			end)
		end)
	end)
end

-- Add task metadata support
function UI.set_metadata()
	local task = UI.get_task_under_cursor()
	if task then
		vim.ui.input({
			prompt = "Metadata key:",
		}, function(key)
			if key and key ~= "" then
				vim.ui.input({
					prompt = "Metadata value:",
				}, function(value)
					if value then
						Task.set_metadata(task, key, value)
						if state.on_task_update then
							state.on_task_update(state.tasks)
						end
						UI.refresh()
					end
				end)
			end
		end)
	end
end
function UI.edit_metadata()
	local task = UI.get_task_under_cursor()
	if not task or not task.metadata or vim.tbl_isempty(task.metadata) then
		UI.show_feedback("No metadata to edit", "warn")
		return
	end

	local metadata_keys = vim.tbl_keys(task.metadata)
	vim.ui.select(metadata_keys, {
		prompt = "Select metadata to edit:",
	}, function(selected_key)
		if selected_key then
			vim.ui.input({
				prompt = "Edit metadata value:",
				default = tostring(task.metadata[selected_key]),
			}, function(new_value)
				if new_value then
					Task.set_metadata(task, selected_key, new_value)
					if state.on_task_update then
						state.on_task_update(state.tasks)
					end
					UI.refresh()
				end
			end)
		end
	end)
end

function UI.render_metadata(task, indent)
	if not task.metadata or vim.tbl_isempty(task.metadata) then
		return {}, {}
	end

	local lines = {}
	local regions = {}
	local indent_str = string.rep(" ", indent + 2)

	-- Sort metadata keys for consistent display
	local sorted_keys = vim.tbl_keys(task.metadata)
	table.sort(sorted_keys)

	for _, key in ipairs(sorted_keys) do
		local value = task.metadata[key]
		local line = string.format("%s%s: %s", indent_str, key, tostring(value))
		table.insert(lines, line)

		-- Add highlights for key and value
		table.insert(regions, {
			line = #lines - 1,
			start = #indent_str,
			length = #key,
			hl_group = "LazyDoMetadataKey",
		})
		table.insert(regions, {
			line = #lines - 1,
			start = #indent_str + #key + 2,
			length = #tostring(value),
			hl_group = "LazyDoMetadataValue",
		})
	end

	-- Add separator lines
	if #lines > 0 then
		table.insert(lines, 1, string.rep(" ", indent) .. "┌" .. string.rep("─", 40) .. "┐")
		table.insert(lines, string.rep(" ", indent) .. "└" .. string.rep("─", 40) .. "┘")
	end

	return lines, regions
end
---Close UI window
function UI.close()
	if is_valid_window() then
		pcall(vim.api.nvim_win_close, state.win, true)
	end
	if is_valid_buffer() then
		pcall(vim.api.nvim_buf_delete, state.buf, { force = true })
	end
	clear_state()
end

---Toggle UI visibility
---@param tasks Task[] Current tasks
---@param on_task_update? function Callback for task updates
---@param lazy_config? table Configuration to use if not initialized
function UI.toggle(tasks, on_task_update, lazy_config, last_state)
	if lazy_config then
		config = lazy_config
	end

	if not config then
		error("UI not properly initialized: config is missing")
		return
	end

	if is_valid_window() then
		UI.close()
		return
	end

	clear_state()
	state.tasks = type(tasks) == "table" and tasks or {}
	state.on_task_update = on_task_update

	local success, buf_or_err, win_or_err = pcall(create_window)
	if not success then
		error("Failed to create UI: " .. tostring(buf_or_err))
		return
	end

	if not buf_or_err or not win_or_err then
		error("Failed to create window or buffer")
		return
	end

	state.buf = buf_or_err
	state.win = win_or_err

	UI.setup_keymaps()
	UI.refresh()

	if last_state then
		UI.restore_window_state(last_state)
	end

	-- Set up essential autocommands
	if state.buf then
		vim.api.nvim_create_autocmd("WinLeave", {
			buffer = state.buf,
			callback = function()
				if state.win then
					state.last_position = {
						cursor = vim.api.nvim_win_get_cursor(state.win),
						scroll = vim.fn.winsaveview(),
					}
				end
			end,
		})

		vim.api.nvim_create_autocmd("VimResized", {
			buffer = state.buf,
			callback = function()
				if is_valid_window() then
					local size = Utils.get_window_size()
					vim.api.nvim_win_set_config(state.win, {
						width = size.width,
						height = size.height,
						row = size.row,
						col = size.col,
					})
					UI.refresh()
				end
			end,
		})
	end
end
-- Add new UI components for attachments
-- function UI.show_attachments()
-- 	local task = UI.get_task_under_cursor()
-- 	if not task or not task.attachments then
-- 		return
-- 	end
--
-- 	local items = {}
-- 	for _, att in ipairs(task.attachments) do
-- 		table.insert(items, string.format("%s (%s)", att.name, Utils.format_size(att.size)))
-- 	end
--
-- 	vim.ui.select(items, {
-- 		prompt = "Task Attachments:",
-- 		format_item = function(item)
-- 			return item
-- 		end,
-- 	}, function(choice)
-- 		if choice then
-- 			-- Handle attachment selection
-- 			local idx = vim.tbl_contains(items, choice)
-- 			local attachment = task.attachments[idx]
-- 			vim.fn.system(string.format("xdg-open %s", vim.fn.shellescape(attachment.path)))
-- 		end
-- 	end)
-- end

-- Add new UI components for relations
function UI.show_relations()
	local task = UI.get_task_under_cursor()
	if not task then
		UI.show_feedback("No task selected", "warn")
		return
	end

	if not task.relations or #task.relations == 0 then
		UI.show_feedback("No relations found", "warn")
		return
	end

	local relation_items = {}
	for _, rel in ipairs(task.relations) do
		local target = UI.find_task_by_id(rel.target_id)
		if target then
			local status_icon = target.status == "done" and config.icons.task_done or config.icons.task_pending
			table.insert(relation_items, {
				relation = rel,
				target = target,
				display = string.format(
					"%s %s → [%s] %s",
					(config.icons.relations or "󱒖"),
					rel.type:gsub("_", " "):upper(),
					status_icon,
					target.content
				),
			})
		end
	end

	vim.ui.select(relation_items, {
		prompt = "Task Relations:",
		format_item = function(item)
			return item.display
		end,
	}, function(choice)
		if choice then
			vim.ui.select({
				"View Target Task",
				"Remove Relation",
				"Edit Relation Type",
			}, {
				prompt = "Relation Action:",
			}, function(action)
				if action == "Remove Relation" then
					for i, rel in ipairs(task.relations) do
						if rel.target_id == choice.relation.target_id and rel.type == choice.relation.type then
							table.remove(task.relations, i)
							if state.on_task_update then
								state.on_task_update(state.tasks)
							end
							UI.show_feedback("Relation removed")
							UI.refresh()
							break
						end
					end
				elseif action == "Edit Relation Type" then
					vim.ui.select(Task.get_relation_types(), {
						prompt = "Select new relation type:",
						format_item = function(item)
							return item:gsub("_", " "):upper()
						end,
					}, function(new_type)
						if new_type then
							for _, rel in ipairs(task.relations) do
								if rel.target_id == choice.relation.target_id then
									rel.type = new_type
									if state.on_task_update then
										state.on_task_update(state.tasks)
									end
									UI.show_feedback("Relation type updated")
									UI.refresh()
									break
								end
							end
						end
					end)
				elseif action == "View Target Task" then
					-- TODO: Implement jump to target task
					UI.show_feedback("Viewing target task (not implemented)")
				end
			end)
		end
	end)
end
function UI.render_relations_section(task, indent_level)
	if not task.relations or #task.relations == 0 then
		return {}, {}
	end

	local lines = {}
	local regions = {}
	local indent = string.rep("  ", indent_level)
	local base_indent = indent .. "    " -- 4 spaces after base indent
	local box_width = 50 -- Increased width for better visual appeal

	-- Add section header with icon
	local title = " Relations "
	local header = indent .. "┌─" .. title .. string.rep("─", box_width - #title - 2) .. "┐"
	table.insert(lines, header)

	-- Add title highlight
	table.insert(regions, {
		line = #lines - 1,
		start = #indent + 2,
		length = #title,
		hl_group = "LazyDoSectionTitle",
	})

	-- Add border highlight
	table.insert(regions, {
		line = #lines - 1,
		start = #indent,
		length = box_width + 2, -- +2 for left and right borders
		hl_group = "LazyDoNoteBorder",
	})

	-- Group relations by type
	local relations_by_type = {}
	for _, rel in ipairs(task.relations) do
		relations_by_type[rel.type] = relations_by_type[rel.type] or {}
		local target = UI.find_task_by_id(rel.target_id)
		if target then
			table.insert(relations_by_type[rel.type], {
				relation = rel,
				target = target,
			})
		end
	end

	-- Render relations grouped by type
	local types = vim.tbl_keys(relations_by_type)
	table.sort(types)

	for type_idx, type in ipairs(types) do
		-- Add relation type header with icon (safely handle missing icon)
		local type_header = type:gsub("_", " "):upper()
		local relation_icon = (config.icons and config.icons.relations) or "→"
		local type_line = indent .. "│ " .. relation_icon .. " " .. type_header .. ":"
		table.insert(lines, type_line)

		-- Add type highlight
		table.insert(regions, {
			line = #lines - 1,
			start = #base_indent + 4, -- After border and icon
			length = #type_header,
			hl_group = "LazyDoRelationType",
		})

		-- Add relation targets
		for _, rel_info in ipairs(relations_by_type[type]) do
			local status_icon = rel_info.target.status == "done" and (config.icons and config.icons.task_done or "✓")
				or (config.icons and config.icons.task_pending or "·")
			local target_line = indent .. "│   • [" .. status_icon .. "] " .. rel_info.target.content

			table.insert(lines, target_line)

			-- Add target task highlight
			table.insert(regions, {
				line = #lines - 1,
				start = #base_indent + 8, -- After border, bullet, and status
				length = #rel_info.target.content,
				hl_group = "LazyDoRelationTarget",
			})
		end

		-- Add separator between types unless it's the last one
		if type_idx < #types then
			table.insert(lines, indent .. "│" .. string.rep("─", box_width - 4))
		end
	end

	-- Add section footer
	table.insert(lines, indent .. "└" .. string.rep("─", box_width) .. "┘")

	-- Add footer border highlight
	table.insert(regions, {
		line = #lines - 1,
		start = #indent,
		length = box_width + 2,
		hl_group = "LazyDoNoteBorder",
	})

	return lines, regions
end
-- Add new UI components for reminders
function UI.add_reminder()
	local task = UI.get_task_under_cursor()
	if not task then
		return
	end

	vim.ui.input({
		prompt = "Reminder time (YYYY-MM-DD HH:MM):",
	}, function(time_str)
		if time_str then
			local timestamp = Utils.Date.parse(time_str)
			if timestamp then
				vim.ui.select({ "low", "normal", "high", "critical" }, {
					prompt = "Select urgency level:",
				}, function(urgency)
					if urgency then
						Task.add_reminder(task, timestamp, {
							days = 0,
							hours = 1,
							minutes = 0,
						}, urgency)
						UI.show_feedback("Reminder added")
						UI.refresh()
					end
				end)
			end
		end
	end)
end

return UI
