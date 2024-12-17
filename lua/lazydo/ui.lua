local M = {}
local utils = require("lazydo.utils")
-- Add animations and transitions
M.ANIMATIONS = {
	FADE_FRAMES = 10,
	FADE_DURATION_MS = 100,
	SLIDE_FRAMES = 8,
	SLIDE_DURATION_MS = 80,
}

-- Enhanced UI constants
M.CONSTANTS = {
	BLOCK = {
		TOP_LEFT = "╭",
		TOP_RIGHT = "╮",
		BOTTOM_LEFT = "╰",
		BOTTOM_RIGHT = "╯",
		HORIZONTAL = "─",
		VERTICAL = "│",
		TASK_START = "├",
		TASK_END = "┤",
		SUBTASK_BRANCH = "├─",
		SUBTASK_LAST = "└─",
		PROGRESS_EMPTY = "○",
		PROGRESS_FULL = "●",
		SEPARATOR = "•",
	},
	PADDING = 2,
	MIN_WIDTH = 60,
	ANIMATION_MS = 50,
}

function M.create_buffer(lazydo)
	local buf = vim.api.nvim_create_buf(false, true)

	-- Set buffer options
	local buf_opts = {
		modifiable = false,
		modified = false,
		readonly = false,
		buftype = "nofile",
		bufhidden = "hide",
		swapfile = false,
		filetype = "lazydo",
	}

	for opt, val in pairs(buf_opts) do
		vim.api.nvim_buf_set_option(buf, opt, val)
	end

	-- Setup buffer-specific keymaps
	M.setup_buffer_keymaps(lazydo, buf)

	return buf
end

function M.create_window(lazydo)
	if not lazydo then
		vim.notify("LazyDo instance not available", vim.log.levels.ERROR)
		return nil
	end

	local width = math.floor(vim.o.columns * (lazydo.opts.ui.width or 0.8))
	local height = math.floor(vim.o.lines * (lazydo.opts.ui.height or 0.8))
	local row = math.floor((vim.o.lines - height) / 2)
	local col = math.floor((vim.o.columns - width) / 2)

	local win = vim.api.nvim_open_win(lazydo.buf, true, {
		relative = "editor",
		width = width,
		height = height,
		row = row,
		col = col,
		style = "minimal",
		border = lazydo.opts.ui.border or "rounded",
		title = lazydo.opts.ui.title or " LazyDo ",
		title_pos = "center",
	})

	if win then
		lazydo.win = win
		vim.api.nvim_win_set_option(win, "winblend", lazydo.opts.ui.winblend or 0)
		M.setup_buffer_keymaps(lazydo, lazydo.buf)
		M.setup_auto_save(lazydo)

		vim.keymap.set("n", "?", function()
			lazydo.show_help = not lazydo.show_help
			lazydo:refresh_display()
		end, { buffer = lazydo.buf, desc = "Toggle help" })
	end

	return win
end

-- Add render functions
function M.render_task_block(task, width, indent, icons)
	local lines = {}
	local highlights = {}

	-- Calculate task completion for subtasks
	local total_subtasks = #task.subtasks
	local completed_subtasks = 0
	for _, subtask in ipairs(task.subtasks) do
		if subtask.done then
			completed_subtasks = completed_subtasks + 1
		end
	end

	-- Status and priority indicators with better visual hierarchy
	local status = task.done and icons.task_done
		or (task.due_date and task.due_date < os.time()) and icons.task_overdue
		or icons.task_pending

	local priority_icon = task.priority == 3 and icons.priority.high
		or task.priority == 2 and icons.priority.medium
		or icons.priority.low

	-- Add visual tags
	local tags_str = ""
	if #task.tags > 0 then
		tags_str = " "
			.. table.concat(
				vim.tbl_map(function(tag)
					return "#" .. tag
				end, task.tags),
				" "
			)
	end

	-- Enhanced block borders with better spacing
	local block_width = width - #indent
	local top = indent
		.. M.CONSTANTS.BLOCK.TOP_LEFT
		.. string.rep(M.CONSTANTS.BLOCK.HORIZONTAL, block_width - 2)
		.. M.CONSTANTS.BLOCK.TOP_RIGHT

	-- Task header with improved layout
	local header = indent
		.. M.CONSTANTS.BLOCK.VERTICAL
		.. utils.pad_right(string.format(" %s %s %s%s", status, priority_icon, task.content, tags_str), block_width - 2)
		.. M.CONSTANTS.BLOCK.VERTICAL

	table.insert(lines, top)
	table.insert(lines, header)

	-- Due date with countdown
	if task.due_date then
		local days_left = math.floor((task.due_date - os.time()) / 86400)
		local date_str = os.date("Due: %Y-%m-%d", task.due_date)
		local countdown = days_left > 0 and string.format("(%d days left)", days_left)
			or days_left == 0 and "(Due today)"
			or string.format("(%d days overdue)", math.abs(days_left))

		local date_line = indent
			.. M.CONSTANTS.BLOCK.VERTICAL
			.. utils.pad_right(string.format("  %s %s %s", icons.due_date, date_str, countdown), block_width - 2)
			.. M.CONSTANTS.BLOCK.VERTICAL
		table.insert(lines, date_line)
	end

	-- -- Notes with better formatting
	-- if task.notes then
	-- 	local wrapped_notes = utils.word_wrap(task.notes, block_width - 6)
	-- 	table.insert(
	-- 		lines,
	-- 		indent
	-- 			.. M.CONSTANTS.BLOCK.VERTICAL
	-- 			.. utils.pad_right("  " .. icons.note .. " Notes:", block_width - 2)
	-- 			.. M.CONSTANTS.BLOCK.VERTICAL
	-- 	)

	-- 	for _, note_line in ipairs(wrapped_notes) do
	-- 		table.insert(
	-- 			lines,
	-- 			indent
	-- 				.. M.CONSTANTS.BLOCK.VERTICAL
	-- 				.. utils.pad_right("    " .. note_line, block_width - 2)
	-- 				.. M.CONSTANTS.BLOCK.VERTICAL
	-- 		)
	-- 	end
	-- end

	-- Notes with better formatting (multiline support)
	if task.notes then
		local wrapped_notes = utils.word_wrap(task.notes, block_width - 6)
		table.insert(
			lines,
			indent
				.. M.CONSTANTS.BLOCK.VERTICAL
				.. utils.pad_right("  " .. icons.note .. " Notes:", block_width - 2)
				.. M.CONSTANTS.BLOCK.VERTICAL
		)

		for _, note_line in ipairs(wrapped_notes) do
			table.insert(
				lines,
				indent
					.. M.CONSTANTS.BLOCK.VERTICAL
					.. utils.pad_right("    " .. note_line, block_width - 2)
					.. M.CONSTANTS.BLOCK.VERTICAL
			)
		end
	end
	-- Subtasks with progress bar
	if #task.subtasks > 0 then
		-- Add subtask header with progress
		local progress_width = 20
		local progress_bar = M.render_progress_bar(total_subtasks, completed_subtasks, progress_width)
		local progress_text = string.format("Subtasks (%d/%d) ", completed_subtasks, total_subtasks)

		table.insert(
			lines,
			indent
				.. M.CONSTANTS.BLOCK.VERTICAL
				.. utils.pad_right("  " .. progress_text .. progress_bar, block_width - 2)
				.. M.CONSTANTS.BLOCK.VERTICAL
		)

		-- Render subtasks
		for i, subtask in ipairs(task.subtasks) do
			local is_last = i == #task.subtasks
			local prefix = is_last and M.CONSTANTS.BLOCK.SUBTASK_LAST or M.CONSTANTS.BLOCK.SUBTASK_BRANCH
			local subtask_status = subtask.done and icons.task_done or icons.task_pending

			local subtask_line = indent
				.. M.CONSTANTS.BLOCK.VERTICAL
				.. utils.pad_right("  " .. prefix .. " " .. subtask_status .. " " .. subtask.content, block_width - 2)
				.. M.CONSTANTS.BLOCK.VERTICAL
			table.insert(lines, subtask_line)
		end
	end

	-- Add task metadata
	local metadata = {
		string.format("Created: %s", os.date("%Y-%m-%d", task.created_at)),
		string.format("Updated: %s", os.date("%Y-%m-%d", task.updated_at)),
	}
	if task.last_completed then
		table.insert(metadata, string.format("Completed: %s", os.date("%Y-%m-%d", task.last_completed)))
	end

	local metadata_str = table.concat(metadata, " " .. M.CONSTANTS.BLOCK.SEPARATOR .. " ")
	table.insert(
		lines,
		indent
			.. M.CONSTANTS.BLOCK.VERTICAL
			.. utils.pad_right("  " .. metadata_str, block_width - 2)
			.. M.CONSTANTS.BLOCK.VERTICAL
	)

	-- Block footer
	local bottom = indent
		.. M.CONSTANTS.BLOCK.BOTTOM_LEFT
		.. string.rep(M.CONSTANTS.BLOCK.HORIZONTAL, block_width - 2)
		.. M.CONSTANTS.BLOCK.BOTTOM_RIGHT
	table.insert(lines, bottom)
	table.insert(lines, "") -- Spacing

	return lines, highlights
end

function M.setup_buffer_keymaps(lazydo, buf)
	if not lazydo or not buf then
		vim.notify("Invalid arguments for setup_buffer_keymaps", vim.log.levels.ERROR)
		return
	end

	local function safe_map(key, fn, desc)
		vim.keymap.set("n", key, function()
			local status, err = pcall(fn)
			if not status then
				vim.notify("LazyDo action failed: " .. tostring(err), vim.log.levels.ERROR)
			end
		end, { buffer = buf, desc = desc })
	end

	-- Add keymaps with error handling
	safe_map(lazydo.opts.keymaps.toggle_done or "<Space>", function()
		local task = lazydo:get_current_task()
		if task then
			task:toggle()
			if lazydo.opts.storage.auto_save then
				require("lazydo.storage").save_tasks(lazydo)
			end
			lazydo:refresh_display()
		end
	end, "Toggle task done")

	safe_map(lazydo.opts.keymaps.edit_task or "e", function()
		M.show_quick_edit_menu(lazydo)
	end, "Edit task")

	safe_map(lazydo.opts.keymaps.add_task or "a", function()
		vim.cmd("LazyDoAdd")
	end, "Add task")
	safe_map(lazydo.opts.keymaps.add_subtask or "A", function()
		local task = lazydo.get_current_task(lazydo)
		if task then
			lazydo.add_subtask(lazydo, task)
		else
			vim.notify("No active task to add a subtask to", vim.log.levels.WARN)
		end
	end, "Add subtask")
	safe_map(lazydo.opts.keymaps.add_subtask or "E", function()
		local task = lazydo.get_current_task(lazydo)
		if task then
			lazydo.edit_subtask(lazydo, task)
		else
			vim.notify("No active task to add a subtask to", vim.log.levels.WARN)
		end
	end, "Edit subtask")
	safe_map(lazydo.opts.keymaps.move_up or "K", function()
		local task = lazydo.get_current_task(lazydo)
		if task then
			lazydo.move_task(lazydo, task, 1)
		else
			vim.notify("No active task selected", vim.log.levels.WARN)
		end
	end, "Move task down")
	safe_map(lazydo.opts.keymaps.move_down or "J", function()
		local task = lazydo.get_current_task(lazydo)
		if task then
			lazydo.move_task(lazydo, task, -1)
		else
			vim.notify("No active task selected", vim.log.levels.WARN)
		end
	end, "Move task up")
	safe_map(lazydo.opts.keymaps.quick_note or "n", function()
		local task = lazydo.get_current_task(lazydo)
		if task then
			lazydo.set_note(lazydo, task)
		else
			vim.notify("No active task selected", vim.log.levels.WARN)
		end
	end, "Add Note")
	safe_map(lazydo.opts.keymaps.quick_date or "D", function()
		local task = lazydo.get_current_task(lazydo)
		if task then
			lazydo.set_date(lazydo, task)
		else
			vim.notify("No active task selected", vim.log.levels.WARN)
		end
	end, "Add Date")
	safe_map(lazydo.opts.keymaps.delete_task or "d", function()
		lazydo:delete_task()
	end, "Delete task")

	safe_map("q", function()
		if lazydo.close_window then
			lazydo:close_window()
		end
	end, "Close window")
end

-- Add highlight groups for task components
function M.setup_task_highlights(lazydo)
	local ns = vim.api.nvim_create_namespace("lazydo_task_highlights")

	-- Clear existing highlights
	vim.api.nvim_buf_clear_namespace(self.buf, ns, 0, -1)

	-- Get current task block bounds
	local current_task = self:get_current_active_task()
	local cursor_line = vim.api.nvim_win_get_cursor(self.win)[1] + 1

	-- Iterate through lines and add highlights
	local lines = vim.api.nvim_buf_get_lines(self.buf, 0, -1, false)
	local in_task_block = false
	local block_indent = 0
	local task_start_line = 0

	for i, line in ipairs(lines) do
		local line_idx = i - 1
		local content = line:gsub("^%s+", "")

		-- Detect task block boundaries
		if content:match("^" .. M.CONSTANTS.BLOCK.TOP_LEFT) then
			in_task_block = true
			block_indent = #line - #content
			task_start_line = line_idx
		elseif content:match("^" .. M.CONSTANTS.BLOCK.BOTTOM_LEFT) then
			in_task_block = false
		end

		if in_task_block then
			-- Highlight block borders
			vim.api.nvim_buf_add_highlight(self.buf, ns, "LazyDoBorder", line_idx, block_indent, block_indent + 1)
			vim.api.nvim_buf_add_highlight(self.buf, ns, "LazyDoBorder", line_idx, #line + 1, #line)

			-- Highlight task status icon
			local status_match = content:match("([󰄱󰄵󰄮])")
			if status_match then
				local icon_start = line:find(status_match, 1, true)
				if icon_start then
					local hl_group = "LazyDoPending"
					if status_match == self.opts.icons.task_done then
						hl_group = "LazyDoDone"
					elseif status_match == self.opts.icons.task_overdue then
						hl_group = "LazyDoOverdue"
					end
					vim.api.nvim_buf_add_highlight(
						self.buf,
						ns,
						hl_group,
						line_idx,
						icon_start - 1,
						icon_start + #status_match - 1
					)
				end
			end

			-- Highlight priority
			local priority_start = line:find("!")
			if priority_start then
				local priority_count = line:match("!+"):len()
				local hl_group = "LazyDoPriorityMedium"
				if priority_count == 3 then
					hl_group = "LazyDoPriorityHigh"
				elseif priority_count == 1 then
					hl_group = "LazyDoPriorityLow"
				end
				vim.api.nvim_buf_add_highlight(
					self.buf,
					ns,
					hl_group,
					line_idx,
					priority_start - 1,
					priority_start + priority_count - 1
				)
			end

			-- Highlight due date
			local date_icon = self.opts.icons.due_date
			local date_start = line:find(date_icon, 1, true)
			if date_start then
				vim.api.nvim_buf_add_highlight(
					self.buf,
					ns,
					"LazyDoDueDate",
					line_idx,
					date_start - 1,
					date_start + #date_icon - 1
				)
				local date_text_start = date_start + #date_icon + 1
				vim.api.nvim_buf_add_highlight(self.buf, ns, "LazyDoDueDate", line_idx, date_text_start - 1, #line - 1)
			end

			-- Highlight notes
			local note_icon = self.opts.icons.note
			local note_start = line:find(note_icon, 1, true)
			if note_start then
				vim.api.nvim_buf_add_highlight(
					self.buf,
					ns,
					"LazyDoNote",
					line_idx,
					note_start - 1,
					note_start + #note_icon - 1
				)
				local note_text_start = note_start + #note_icon + 1
				vim.api.nvim_buf_add_highlight(self.buf, ns, "LazyDoNote", line_idx, note_text_start - 1, #line - 1)
			end

			-- Highlight subtasks
			if line:match("Subtasks:") then
				vim.api.nvim_buf_add_highlight(self.buf, ns, "LazyDoSubtask", line_idx, block_indent + 2, #line - 1)
			elseif line:match(M.CONSTANTS.BLOCK.SUBTASK_BRANCH) or line:match(M.CONSTANTS.BLOCK.SUBTASK_LAST) then
				vim.api.nvim_buf_add_highlight(self.buf, ns, "LazyDoSubtask", line_idx, block_indent + 2, #line - 1)
			end

			-- Highlight current task block
			if current_task and line_idx >= task_start_line and cursor_line >= task_start_line then
				vim.api.nvim_buf_add_highlight(self.buf, ns, "Visual", line_idx, 0, #line)
			end
		end
	end
end
-- function M.setup_task_highlights(lazydo)
-- 	local ns = vim.api.nvim_create_namespace("lazydo_task_highlights")

-- 	-- Clear existing highlights
-- 	vim.api.nvim_buf_clear_namespace(lazydo.buf, ns, 0, -1)

-- 	local function add_highlight(line, col_start, col_end, hl_group)
-- 		vim.api.nvim_buf_add_highlight(lazydo.buf, ns, hl_group, line, col_start, col_end)
-- 	end

-- 	-- Get current task block bounds
-- 	local current_task = lazydo:get_current_task()
-- 	local cursor_line = vim.api.nvim_win_get_cursor(lazydo.win)[1] + 1

-- 	-- Iterate through lines and add highlights
-- 	local lines = vim.api.nvim_buf_get_lines(lazydo.buf, 0, -1, false)
-- 	local in_task_block = false
-- 	local block_indent = 0
-- 	local task_start_line = 0

-- 	for i, line in ipairs(lines) do
-- 		local line_idx = i - 1
-- 		local content = line:gsub("^%s+", "")

-- 		-- Detect task block boundaries
-- 		if content:match("^" .. M.CONSTANTS.BLOCK.TOP_LEFT) then
-- 			in_task_block = true
-- 			block_indent = #line - #content
-- 			task_start_line = line_idx
-- 		elseif content:match("^" .. M.CONSTANTS.BLOCK.BOTTOM_LEFT) then
-- 			in_task_block = false
-- 		end

-- 		if in_task_block then
-- 			-- Highlight block borders
-- 			add_highlight(line_idx, block_indent, block_indent + 1, "LazyDoBorder")
-- 			add_highlight(line_idx, #line + 1, #line, "LazyDoBorder")

-- 			-- Highlight task status icon
-- 			local status_match = content:match("([󰄱󰄵󰄮])")
-- 			if status_match then
-- 				local icon_start = line:find(status_match, 1, true)
-- 				if icon_start then
-- 					local hl_group = "LazyDoPending"
-- 					if status_match == lazydo.opts.icons.task_done then
-- 						hl_group = "LazyDoDone"
-- 					elseif status_match == lazydo.opts.icons.task_overdue then
-- 						hl_group = "LazyDoOverdue"
-- 					end
-- 					add_highlight(line_idx, icon_start - 1, icon_start + #status_match - 1, hl_group)
-- 				end
-- 			end

-- 			-- Highlight priority
-- 			local priority_start = line:find("!")
-- 			if priority_start then
-- 				local priority_count = line:match("!+"):len()
-- 				local hl_group = "LazyDoPriorityMedium"
-- 				if priority_count == 3 then
-- 					hl_group = "LazyDoPriorityHigh"
-- 				elseif priority_count == 1 then
-- 					hl_group = "LazyDoPriorityLow"
-- 				end
-- 				add_highlight(line_idx, priority_start - 1, priority_start + priority_count - 1, hl_group)
-- 			end

-- 			-- Highlight due date
-- 			local date_icon = lazydo.opts.icons.due_date
-- 			local date_start = line:find(date_icon, 1, true)
-- 			if date_start then
-- 				add_highlight(line_idx, date_start - 1, date_start + #date_icon - 1, "LazyDoDueDate")
-- 				local date_text_start = date_start + #date_icon + 1
-- 				add_highlight(line_idx, date_text_start - 1, #line - 1, "LazyDoDueDate")
-- 			end

-- 			-- Highlight notes
-- 			local note_icon = lazydo.opts.icons.note
-- 			local note_start = line:find(note_icon, 1, true)
-- 			if note_start then
-- 				add_highlight(line_idx, note_start - 1, note_start + #note_icon - 1, "LazyDoNote")
-- 				local note_text_start = note_start + #note_icon + 1
-- 				add_highlight(line_idx, note_text_start - 1, #line - 1, "LazyDoNote")
-- 			end

-- 			-- Highlight subtasks
-- 			if line:match("Subtasks:") then
-- 				add_highlight(line_idx, block_indent + 2, #line - 1, "LazyDoSubtask")
-- 			elseif line:match(M.CONSTANTS.BLOCK.SUBTASK_BRANCH) or line:match(M.CONSTANTS.BLOCK.SUBTASK_LAST) then
-- 				add_highlight(line_idx, block_indent + 2, #line - 1, "LazyDoSubtask")
-- 			end

-- 			-- Highlight current task block
-- 			if current_task and line_idx >= task_start_line and cursor_line >= task_start_line then
-- 				add_highlight(line_idx, 0, #line, "Visual")
-- 			end
-- 		end
-- 	end
-- end

-- Add edit task functionality
function M.edit_task_component(lazydo, component)
	if not lazydo or not lazydo.buf then
		vim.notify("LazyDo instance not available", vim.log.levels.ERROR)
		return
	end

	local task = lazydo:get_current_task()
	if not task then
		vim.notify("No task selected", vim.log.levels.WARN)
		return
	end

	local callback = function(input)
		if input == nil then
			return
		end -- User cancelled

		if component == "content" then
			task.content = input
		elseif component == "note" then
			task.notes = input
		elseif component == "due_date" then
			task.due_date = utils.parse_date(input)
			if not task.due_date then
				vim.notify("Invalid date format", vim.log.levels.WARN)
				return
			end
		elseif component == "priority" then
			local priority = tonumber(input)
			if priority and priority >= 1 and priority <= 3 then
				task.priority = priority
			else
				vim.notify("Priority must be between 1 and 3", vim.log.levels.WARN)
				return
			end
		end

		task.updated_at = os.time()
		if lazydo.opts.storage.auto_save then
			require("lazydo.storage").save_tasks(lazydo)
		end
		lazydo:refresh_display()
	end

	local current_value = ""
	if component == "content" then
		current_value = task.content
	elseif component == "note" then
		current_value = task.notes or ""
	elseif component == "due_date" then
		current_value = task.due_date and utils.format_date(task.due_date) or ""
	elseif component == "priority" then
		current_value = tostring(task.priority)
	end

	vim.ui.input({
		prompt = string.format("Edit %s: ", component),
		default = current_value,
	}, callback)
end

-- Add quick edit menu
function M.show_quick_edit_menu(lazydo)
	if not lazydo then
		vim.notify("LazyDo instance not available", vim.log.levels.ERROR)
		return
	end

	local task = lazydo:get_current_task()
	if not task then
		vim.notify("No task selected", vim.log.levels.WARN)
		return
	end

	local items = {
		{ text = "Edit Content", value = "content" },
		{ text = "Edit Note", value = "note" },
		{ text = "Set Due Date", value = "due_date" },
		{ text = "Change Priority", value = "priority" },
		{ text = "Toggle Done", value = "toggle" },
		{ text = "Delete Task", value = "delete" },
		{ text = "Add Subtask", value = "add_subtask" },
		{ text = "Edit Subtask", value = "edit_subtask" },
	}

	vim.ui.select(items, {
		prompt = "Edit Task:",
		format_item = function(item)
			return item.text
		end,
	}, function(choice)
		if not choice then
			return
		end

		if choice.value == "toggle" then
			task:toggle()
			if lazydo.opts.storage.auto_save then
				require("lazydo.storage").save_tasks(lazydo)
			end
		elseif choice.value == "delete" then
			lazydo:delete_task()
		elseif choice.value == "add_subtask" then
			lazydo:add_subtask() -- Call the method to add a subtask
		elseif choice.value == "edit_subtask" then
			lazydo:edit_subtask() -- Call the method to edit a subtask
		else
			M.edit_task_component(lazydo, choice.value)
		end

		lazydo:refresh_display()
	end)
end

-- Add progress bar rendering
function M.render_progress_bar(total, completed, width)
	local progress = completed / total
	local filled_width = math.floor(width * progress)
	local empty_width = width - filled_width

	return string.rep(M.CONSTANTS.BLOCK.PROGRESS_FULL, filled_width)
		.. string.rep(M.CONSTANTS.BLOCK.PROGRESS_EMPTY, empty_width)
end

-- Add floating window animations
function M.animate_window_open(win, opts)
	local start_width = math.floor(opts.width * 0.5)
	local start_height = math.floor(opts.height * 0.5)
	local width_step = (opts.width - start_width) / M.ANIMATIONS.SLIDE_FRAMES
	local height_step = (opts.height - start_height) / M.ANIMATIONS.SLIDE_FRAMES

	for i = 1, M.ANIMATIONS.SLIDE_FRAMES do
		local current_width = math.floor(start_width + (width_step * i))
		local current_height = math.floor(start_height + (height_step * i))

		vim.api.nvim_win_set_config(win, {
			width = current_width,
			height = current_height,
		})

		vim.cmd("redraw")
		vim.loop.sleep(M.ANIMATIONS.SLIDE_DURATION_MS / M.ANIMATIONS.SLIDE_FRAMES)
	end
end

-- Add status line
function M.render_status_line(lazydo)
	local stats = lazydo:get_task_statistics()
	local total_width = vim.api.nvim_win_get_width(lazydo.win)

	-- Create progress bar
	local progress_width = 20
	local progress = stats.done / (stats.total > 0 and stats.total or 1)
	local progress_bar = M.render_progress_bar(stats.total, stats.done, progress_width)

	-- Format statistics
	local stats_text = string.format(
		"Tasks: %d │ Done: %d │ Pending: %d │ Overdue: %d │ Progress: ",
		stats.total,
		stats.done,
		stats.pending,
		stats.overdue
	)

	-- Combine elements
	local status_line = stats_text .. progress_bar

	-- Add to virtual text
	vim.api.nvim_buf_clear_namespace(lazydo.buf, lazydo.ns.virtual, 0, -1)
	vim.api.nvim_buf_set_extmark(lazydo.buf, lazydo.ns.virtual, 0, 0, {
		virt_text = { { status_line, "LazyDoStatusLine" } },
		virt_text_pos = "overlay",
	})
end

function M.setup_auto_save(lazydo)
	-- Save on buffer leave
	vim.api.nvim_create_autocmd({ "BufLeave", "VimLeavePre" }, {
		buffer = lazydo.buf,
		callback = function()
			require("lazydo.storage").save_tasks(lazydo)
		end,
	})

	-- Save periodically (every 30 seconds)
	if not lazydo.auto_save_timer then
		lazydo.auto_save_timer = vim.loop.new_timer()
		lazydo.auto_save_timer:start(
			30000,
			30000,
			vim.schedule_wrap(function()
				if lazydo.tasks_modified then
					require("lazydo.storage").save_tasks(lazydo)
					lazydo.tasks_modified = false
				end
			end)
		)
	end
end

return M
