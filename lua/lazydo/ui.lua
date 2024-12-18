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
		FOLD_OPEN = "▼",
		FOLD_CLOSED = "▶",
		PRIORITY_HIGH = "★",
		PRIORITY_MEDIUM = "☆",
		PRIORITY_LOW = "·",
	},
	PADDING = 2,
	MIN_WIDTH = 60,
	ANIMATION_MS = 50,
}

-- Add folding state to tasks
function M.toggle_fold(lazydo)
	local task = lazydo:get_current_task()
	if task then
		task.folded = not task.folded
		lazydo:refresh_display()
	end
end

-- Add this helper function at the top of ui.lua
local function find_index(list, value)
	for i, v in ipairs(list) do
		if v == value then
			return i
		end
	end
	return nil
end

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

function M.render_task_block(task, width, indent, icons)
    local lines = {}
    local block_width = width - #indent
    local inner_width = block_width - 4

    -- Enhanced box drawing characters
    local box = M.CONSTANTS.BLOCK
    local fold_indicator = task.folded and box.FOLD_CLOSED or box.FOLD_OPEN

    -- Status and priority indicators with enhanced visual hierarchy
    local status = task.done and icons.task_done
        or (task.due_date and task.due_date < os.time()) and icons.task_overdue
        or icons.task_pending

    local priority_icon = task.priority == 3 and box.PRIORITY_HIGH
        or task.priority == 2 and box.PRIORITY_MEDIUM
        or box.PRIORITY_LOW

    -- Format tags with enhanced styling
    local tags_str = #task.tags > 0
        and " " .. table.concat(
            vim.tbl_map(function(tag)
                return "#" .. tag
            end, task.tags),
            " "
        )
        or ""

    -- Top border with title and fold indicator
    local title_str = string.format(" %s %s %s %s%s ", fold_indicator, status, priority_icon, task.content, tags_str)
    local title_len = vim.fn.strdisplaywidth(title_str)
    local pad_len = math.max(0, inner_width - title_len)
    local top = indent .. box.TOP_LEFT .. title_str .. string.rep(box.HORIZONTAL, pad_len) .. box.TOP_RIGHT
    table.insert(lines, top)

    if not task.folded then
        -- Due date with visual countdown and enhanced indicators
        if task.due_date then
            local days_left = math.floor((task.due_date - os.time()) / 86400)
            local date_str = os.date("%Y-%m-%d", task.due_date)
            local countdown = days_left > 0 and string.format("(%d days left)", days_left)
                or days_left == 0 and "(Due today)"
                or string.format("(%d days overdue)", math.abs(days_left))

            -- Enhanced urgency indicator with dynamic symbols
            local urgency = days_left < 0 and "⚠" 
                or days_left == 0 and "⌛" 
                or days_left <= 2 and "⚡"
                or days_left <= 7 and "◷"
                or "○"
            
            local date_line = string.format(" %s %s %s %s ", icons.due_date, date_str, countdown, urgency)
            table.insert(lines, indent .. box.VERTICAL .. utils.pad_right(date_line, inner_width) .. box.VERTICAL)
        end

        -- Notes with improved formatting and section separator
        if task.notes then
            -- Add separator line
            table.insert(lines, indent .. box.TASK_START .. string.rep(box.HORIZONTAL, inner_width) .. box.TASK_END)
            
            -- Notes header with icon
            table.insert(
                lines,
                indent .. box.VERTICAL .. string.format(" %s Notes:", icons.note) .. string.rep(" ", inner_width - 8) .. box.VERTICAL
            )

            -- Notes content with proper wrapping
            local wrapped_notes = utils.word_wrap(task.notes, inner_width - 4)
            for _, note_line in ipairs(wrapped_notes) do
                table.insert(lines, indent .. box.VERTICAL .. "  " .. utils.pad_right(note_line, inner_width - 2) .. box.VERTICAL)
            end
        end

        -- Subtasks with enhanced progress visualization
        if #task.subtasks > 0 then
            -- Calculate completion statistics
            local total_subtasks = #task.subtasks
            local completed_subtasks = 0
            for _, subtask in ipairs(task.subtasks) do
                if subtask.done then
                    completed_subtasks = completed_subtasks + 1
                end
            end

            -- Add separator for subtasks section
            table.insert(lines, indent .. box.TASK_START .. string.rep(box.HORIZONTAL, inner_width) .. box.TASK_END)

            -- Progress bar and statistics
            local progress_width = 20
            local progress_bar = M.render_progress_bar(total_subtasks, completed_subtasks, progress_width)
            local completion_percentage = math.floor((completed_subtasks / total_subtasks) * 100)
            local progress_text = string.format(" Subtasks (%d/%d) %d%% %s ", 
                completed_subtasks, 
                total_subtasks,
                completion_percentage,
                progress_bar
            )
            table.insert(lines, indent .. box.VERTICAL .. utils.pad_right(progress_text, inner_width) .. box.VERTICAL)

            -- Render subtasks with improved hierarchy
            for i, subtask in ipairs(task.subtasks) do
                local is_last = i == #task.subtasks
                local prefix = is_last and box.SUBTASK_LAST or box.SUBTASK_BRANCH
                local subtask_status = subtask.done and icons.task_done or icons.task_pending
                local subtask_line = string.format(" %s %s %s", prefix, subtask_status, subtask.content)
                table.insert(lines, indent .. box.VERTICAL .. utils.pad_right(subtask_line, inner_width) .. box.VERTICAL)
            end
        end

        -- Metadata footer with improved layout and separators
        table.insert(lines, indent .. box.TASK_START .. string.rep(box.HORIZONTAL, inner_width) .. box.TASK_END)
        
        -- Enhanced metadata display
        local metadata = {
            string.format("%s Created: %s", icons.bullet, os.date("%Y-%m-%d", task.created_at)),
            string.format("%s Updated: %s", icons.bullet, os.date("%Y-%m-%d", task.updated_at)),
        }
        if task.last_completed then
            table.insert(metadata, string.format("%s Completed: %s", icons.bullet, os.date("%Y-%m-%d", task.last_completed)))
        end
        local metadata_str = table.concat(metadata, " " .. box.SEPARATOR .. " ")
        table.insert(lines, indent .. box.VERTICAL .. utils.pad_right(" " .. metadata_str, inner_width) .. box.VERTICAL)
    end

    -- Bottom border
    table.insert(lines, indent .. box.BOTTOM_LEFT .. string.rep(box.HORIZONTAL, inner_width) .. box.BOTTOM_RIGHT)
    table.insert(lines, "") -- Add spacing between tasks

    return lines
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
		end, { buffer = buf, desc = desc, silent = true })
	end

	safe_map(lazydo.opts.keymaps.add_task, function()
		lazydo:create_task_prompt()
	end, "Add new task")

	safe_map(lazydo.opts.keymaps.quick_add or "o", function()
		vim.ui.input({
			prompt = "Quick task: ",
		}, function(input)
			if input and input ~= "" then
				lazydo:add_task(input, { priority = 2 })
				lazydo:refresh_display()
			end
		end)
	end, "Quick add task")

	safe_map(lazydo.opts.keymaps.add_below or "O", function()
		local current = lazydo:get_current_task()
		vim.ui.input({
			prompt = "New task below: ",
		}, function(input)
			if input and input ~= "" then
				local task = lazydo:add_task(input, {
					priority = current and current.priority or 2,
				})
				if current then
					-- Move the new task to position after current task
					local current_index = vim.list_find(lazydo.tasks, function(t)
						return t.id == current.id
					end)
					if current_index then
						table.remove(lazydo.tasks)
						table.insert(lazydo.tasks, current_index + 1, task)
					end
				end
				lazydo:refresh_display()
			end
		end)
	end, "Add task below current")
	-- Task Management
	safe_map(lazydo.opts.keymaps.toggle_done, function()
		local task = lazydo:get_current_task()
		if task then
			task:toggle()
			if lazydo.opts.storage.auto_save then
				require("lazydo.storage").save_tasks(lazydo)
			end
			lazydo:refresh_display()
		end
	end, "Toggle task completion")
	safe_map(lazydo.opts.keymaps.toggle_subtask or "<C-Space>", function()
		local task = lazydo:get_current_task()
		if task then
			-- Get cursor position
			local cursor = vim.api.nvim_win_get_cursor(0)
			local current_line = vim.api.nvim_buf_get_lines(lazydo.buf, cursor[1] - 1, cursor[1], false)[1]

			-- Check if cursor is on a subtask line
			if current_line:match("└─") or current_line:match("├─") then
				-- Find which subtask we're on
				for i, subtask in ipairs(task.subtasks) do
					if current_line:find(subtask.content, 1, true) then
						subtask.done = not subtask.done
						task.updated_at = os.time()
						if lazydo.opts.storage.auto_save then
							require("lazydo.storage").save_tasks(lazydo)
						end
						lazydo:refresh_display()
						break
					end
				end
			end
		end
	end, "Toggle subtask completion")

	safe_map(lazydo.opts.keymaps.edit_task, function()
		M.show_quick_edit_menu(lazydo)
	end, "Edit task")

	safe_map(lazydo.opts.keymaps.delete_task, function()
		local task = lazydo:get_current_task()
		if task then
			vim.ui.input({
				prompt = "Delete task? (y/n): ",
			}, function(input)
				if input and input:lower() == "y" then
					lazydo:delete_task()
				end
			end)
		end
	end, "Delete task")

	-- Subtask Management
	safe_map(lazydo.opts.keymaps.add_subtask, function()
		lazydo:add_subtask()
	end, "Add subtask")

	safe_map(lazydo.opts.keymaps.edit_subtask, function()
		lazydo:edit_subtask()
	end, "Edit subtask")

	-- Task Movement
	safe_map(lazydo.opts.keymaps.move_up, function()
		local task = lazydo:get_current_task()
		if task then
			lazydo:move_task(task, -1)
		end
	end, "Move task up")

	safe_map(lazydo.opts.keymaps.move_down, function()
		local task = lazydo:get_current_task()
		if task then
			lazydo:move_task(task, 1)
		end
	end, "Move task down")

	-- Quick Actions
	safe_map(lazydo.opts.keymaps.quick_note, function()
		local task = lazydo:get_current_task()
		if task then
			lazydo:set_note(task)
		end
	end, "Add/edit note")

	safe_map(lazydo.opts.keymaps.quick_date, function()
		local task = lazydo:get_current_task()
		if task then
			lazydo:set_date(task)
		end
	end, "Set due date")

	-- Priority Management
	safe_map(lazydo.opts.keymaps.increase_priority, function()
		local task = lazydo:get_current_task()
		if task then
			task:change_priority(1)
			lazydo:refresh_display()
		end
	end, "Increase priority")

	safe_map(lazydo.opts.keymaps.decrease_priority, function()
		local task = lazydo:get_current_task()
		if task then
			task:change_priority(-1)
			lazydo:refresh_display()
		end
	end, "Decrease priority")

	-- UI Controls
	safe_map(lazydo.opts.keymaps.toggle_help, function()
		M.toggle_help(lazydo)
	end, "Toggle help")

	safe_map(lazydo.opts.keymaps.close_window, function()
		if lazydo.close_window then
			lazydo:close_window()
		end
	end, "Close window")

	safe_map(lazydo.opts.keymaps.refresh_view, function()
		lazydo:refresh_display()
	end, "Refresh view")

	-- Backup controls
	safe_map("<leader>bb", function()
		require("lazydo.storage").create_backup(lazydo)
	end, "Create backup")

	safe_map("<leader>br", function()
		require("lazydo.storage").restore_from_backup(lazydo)
		lazydo:refresh_display()
	end, "Restore from backup")

	-- Navigation improvements
	vim.keymap.set("n", "j", function()
		local line = vim.api.nvim_win_get_cursor(0)[1]
		local max_lines = vim.api.nvim_buf_line_count(buf)
		if line < max_lines then
			vim.api.nvim_win_set_cursor(0, { line + 1, 0 })
			lazydo:refresh_display()
		end
	end, { buffer = buf, desc = "Next line" })

	vim.keymap.set("n", "k", function()
		local line = vim.api.nvim_win_get_cursor(0)[1]
		if line > 1 then
			vim.api.nvim_win_set_cursor(0, { line - 1, 0 })
			lazydo:refresh_display()
		end
	end, { buffer = buf, desc = "Previous line" })
end

function M.setup_task_highlights(lazydo)
	local ns = vim.api.nvim_create_namespace("lazydo_task_highlights")
	vim.api.nvim_buf_clear_namespace(lazydo.buf, ns, 0, -1)

	local function add_hl(line, col_start, col_end, group)
		vim.api.nvim_buf_add_highlight(lazydo.buf, ns, group, line, col_start, col_end)
	end

	local current_task = lazydo:get_current_task()
	local lines = vim.api.nvim_buf_get_lines(lazydo.buf, 0, -1, false)
	local in_task = false
	local current_task_start = nil
	local current_task_end = nil
	local task_start = 0
	local header_lines = 4 -- Title + separator + stats + empty line

	-- First pass: determine the current task boundaries
	if current_task then
		local line_count = 0
		for i, line in ipairs(lines) do
			local lnum = i - 1
			if lnum < header_lines then
				goto continue
			end

			local content = line:gsub("^%s+", "")
			if content:match("^╭") then
				task_start = lnum
				if not current_task_start and current_task.line_number == task_start then
					current_task_start = lnum
				end
			elseif content:match("^╰") and current_task_start and not current_task_end then
				current_task_end = lnum
				break
			end
			::continue::
		end
	end

	-- Second pass: apply highlights
	task_start = 0
	for i, line in ipairs(lines) do
		local lnum = i - 1
		local content = line:gsub("^%s+", "")

		-- Highlight header
		if lnum < header_lines then
			if lnum == 0 then -- Title
				add_hl(lnum, 0, -1, "LazyDoHeader")
			elseif lnum == 1 then -- Separator
				add_hl(lnum, 0, -1, "LazyDoSeparator")
			elseif lnum == 2 then -- Stats
				add_hl(lnum, 0, -1, "LazyDoStatusLine")
			end
			goto continue
		end

		-- Detect task boundaries
		if content:match("^╭") then
			in_task = true
			task_start = lnum
		elseif content:match("^╰") then
			in_task = false
		end

		if in_task then
			-- Highlight active task background
			if current_task_start and current_task_end and lnum >= current_task_start and lnum <= current_task_end then
				-- Add a subtle background highlight for the active task
				add_hl(lnum, 0, #line, "LazyDoActiveTask")
			end

			-- Highlight borders
			if content:match("^[╭╮╰╯│├┤]") or content:match("[╭╮╰╯│├┤]$") then
				local indent = #line - #content
				local border_group = "LazyDoBorder"

				-- If this is the current task, use a different highlight group
				if
					current_task_start
					and current_task_end
					and lnum >= current_task_start
					and lnum <= current_task_end
				then
					border_group = "LazyDoActiveBorder"
				end

				add_hl(lnum, indent, indent + 1, border_group)
				add_hl(lnum, #line - 1, #line, border_group)
			end

			-- Highlight task components
			if content:match("^╭") then -- Task header line
				-- Highlight status icon
				local status_start = line:find(lazydo.opts.icons.task_done)
					or line:find(lazydo.opts.icons.task_pending)
					or line:find(lazydo.opts.icons.task_overdue)
				if status_start then
					local status_group = "LazyDoPending"
					if line:find(lazydo.opts.icons.task_done, status_start) then
						status_group = "LazyDoDone"
					elseif line:find(lazydo.opts.icons.task_overdue, status_start) then
						status_group = "LazyDoOverdue"
					end
					add_hl(lnum, status_start - 1, status_start + 1, status_group)
				end

				-- Highlight priority icon
				local priority_start = line:find(lazydo.opts.icons.priority.high)
					or line:find(lazydo.opts.icons.priority.medium)
					or line:find(lazydo.opts.icons.priority.low)
				if priority_start then
					local priority_group = "LazyDoPriorityMedium"
					if line:find(lazydo.opts.icons.priority.high, priority_start) then
						priority_group = "LazyDoPriorityHigh"
					elseif line:find(lazydo.opts.icons.priority.low, priority_start) then
						priority_group = "LazyDoPriorityLow"
					end
					add_hl(lnum, priority_start - 1, priority_start + 1, priority_group)
				end

				-- Highlight tags
				for tag in line:gmatch("#%w+") do
					local tag_start = line:find(tag, 1, true)
					if tag_start then
						add_hl(lnum, tag_start - 1, tag_start + #tag - 1, "LazyDoTag")
					end
				end

				-- Progress bullets highlights
				local progress_icons = {
					[M.CONSTANTS.BLOCK.PROGRESS_FULL] = "LazyDoProgressFull",
					[M.CONSTANTS.BLOCK.PROGRESS_EMPTY] = "LazyDoProgressEmpty",
				}

				for icon, hl_group in pairs(progress_icons) do
					local start_idx = 1
					while true do
						local icon_start = line:find(vim.pesc(icon), start_idx)
						if not icon_start then
							break
						end
						add_hl(lnum, icon_start - 1, icon_start + vim.fn.strdisplaywidth(icon), hl_group)
						start_idx = icon_start + 1
					end
				end

				-- Subtask bullet highlights
				if line:match("└─") or line:match("├─") then
					local bullet_start = line:find("[└├]─")
					if bullet_start then
						add_hl(lnum, bullet_start - 1, bullet_start + 2, "LazyDoSubtaskBullet")
					end
				end
			end

			-- Highlight due date line
			local date_icon = lazydo.opts.icons.due_date
			local date_start = line:find(date_icon, 1, true)
			if date_start then
				add_hl(lnum, date_start - 1, #line - 1, "LazyDoDueDate")
			end

			-- Highlight notes
			local note_icon = lazydo.opts.icons.note
			local note_start = line:find(note_icon, 1, true)
			if note_start then
				add_hl(lnum, note_start - 1, #line - 1, "LazyDoNote")
			end

			-- Highlight subtasks
			if line:match("└─") or line:match("├─") then
				local subtask_status_start = line:find(lazydo.opts.icons.task_done)
					or line:find(lazydo.opts.icons.task_pending)
				if subtask_status_start then
					local status_group = line:find(lazydo.opts.icons.task_done) and "LazyDoDone" or "LazyDoPending"
					add_hl(lnum, subtask_status_start - 1, subtask_status_start + 1, status_group)
				end
				add_hl(lnum, 0, #line, "LazyDoSubtask")
			end
		end

		::continue::
	end
end
-- In ui.lua
function M.create_help_window(lazydo)
	local help_width = math.floor(vim.o.columns * 0.5)
	local help_height = 20
	local row = math.floor((vim.o.lines - help_height) / 2)
	local col = math.floor((vim.o.columns - help_width) / 2)

	-- Create help buffer
	local help_buf = vim.api.nvim_create_buf(false, true)
	vim.api.nvim_buf_set_option(help_buf, "bufhidden", "wipe")

	-- Create help window
	local help_win = vim.api.nvim_open_win(help_buf, true, {
		relative = "editor",
		width = help_width,
		height = help_height,
		row = row,
		col = col,
		style = "minimal",
		border = lazydo.opts.ui.border or "solid",
		title = " LazyDo Help ",
		title_pos = "center",
	})

	-- Set help window options
	vim.api.nvim_win_set_option(help_win, "winblend", 10)
	vim.api.nvim_win_set_option(help_win, "cursorline", true)

	-- Add help content
	local help_lines = {
		"LazyDo Keybindings",
		string.rep("─", help_width),
		"",
		" Navigation:",
		" j/k        - Move cursor up/down",
		" h/l        - Collapse/Expand Task",
		" gg/G       - Go to top/bottom",
		" <C-u>/<C-d> - Page up/down",
		"",
		" Task Management:",
		" <Space>    - Toggle Task completion",
		" <C-Space>   - Toggle subtask completion",
		" e          - Edit Task menu",
		" dd         - Delete Task",
		" a          - Add new Task",
		" A          - Add subTask to current Task",
		" o			 - Add Quick Task",
		" O 		 - Add Quick Task below current Task",
		" n          - Add/edit note",
		" d          - Set due date",
		" >/<        - Increase/decrease priority",
		"",
		" Press q to close this window",
	}

	vim.api.nvim_buf_set_lines(help_buf, 0, -1, false, help_lines)
	vim.api.nvim_buf_set_option(help_buf, "modifiable", false)

	-- Add keymaps for help window
	vim.keymap.set("n", "q", function()
		vim.api.nvim_win_close(help_win, true)
		-- Restore focus to LazyDo window
		if lazydo.win and vim.api.nvim_win_is_valid(lazydo.win) then
			vim.api.nvim_set_current_win(lazydo.win)
		end
	end, { buffer = help_buf, nowait = true })

	return help_buf, help_win
end

-- Update the help toggle function
function M.toggle_help(lazydo)
	if lazydo.help_win and vim.api.nvim_win_is_valid(lazydo.help_win) then
		vim.api.nvim_win_close(lazydo.help_win, true)
		lazydo.help_win = nil
		lazydo.help_buf = nil
		-- Restore focus to LazyDo window
		if lazydo.win and vim.api.nvim_win_is_valid(lazydo.win) then
			vim.api.nvim_set_current_win(lazydo.win)
		end
	else
		lazydo.help_buf, lazydo.help_win = M.create_help_window(lazydo)
	end
end

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
