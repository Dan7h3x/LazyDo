local M = {}
local utils = require("lazydo.utils")
-- Add animations and transitions
M.ANIMATIONS = {
	FADE_FRAMES = 10,
	FADE_DURATION_MS = 100,
	SLIDE_FRAMES = 8,
	SLIDE_DURATION_MS = 80,
}

-- Advanced Task Management Helper Functions
function M.show_search_prompt(lazydo)
	vim.ui.input({
		prompt = "Search tasks: ",
	}, function(query)
		if query and query ~= "" then
			local results = lazydo:search_tasks(query)
			-- Store original tasks and show filtered results
			lazydo._original_tasks = lazydo.tasks
			lazydo.tasks = results
			lazydo:refresh_display()
			vim.notify(string.format("Found %d matching tasks", #results))
		end
	end)
end

function M.show_filter_menu(lazydo)
	local filter_options = {
		{ text = "Status (Done/Pending/Overdue)", value = "status" },
		{ text = "Priority (High/Medium/Low)", value = "priority" },
		{ text = "Tags", value = "tags" },
	}

	vim.ui.select(filter_options, {
		prompt = "Select filter type:",
		format_item = function(item)
			return item.text
		end,
	}, function(choice)
		if not choice then
			return
		end

		if choice.value == "status" then
			vim.ui.select({ "done", "pending", "overdue" }, {
				prompt = "Select status:",
			}, function(status)
				if status then
					local filtered = lazydo:filter_tasks({ status = status })
					lazydo._original_tasks = lazydo.tasks
					lazydo.tasks = filtered
					lazydo:refresh_display()
				end
			end)
		elseif choice.value == "priority" then
			vim.ui.select({ "1", "2", "3" }, {
				prompt = "Select priority (1=Low, 2=Medium, 3=High):",
			}, function(priority)
				if priority then
					local filtered = lazydo:filter_tasks({ priority = tonumber(priority) })
					lazydo._original_tasks = lazydo.tasks
					lazydo.tasks = filtered
					lazydo:refresh_display()
				end
			end)
		elseif choice.value == "tags" then
			vim.ui.input({
				prompt = "Enter tags (comma-separated):",
			}, function(input)
				if input and input ~= "" then
					local tags = vim.split(input, ",")
					local filtered = lazydo:filter_tasks({ tags = tags })
					lazydo._original_tasks = lazydo.tasks
					lazydo.tasks = filtered
					lazydo:refresh_display()
				end
			end)
		end
	end)
end

function M.show_sort_menu(lazydo)
	local sort_options = {
		{ text = "Sort by Priority", value = "priority" },
		{ text = "Sort by Due Date", value = "due_date" },
		{ text = "Sort by Creation Date", value = "created" },
		{ text = "Sort by Last Updated", value = "updated" },
	}

	vim.ui.select(sort_options, {
		prompt = "Select sorting method:",
		format_item = function(item)
			return item.text
		end,
	}, function(choice)
		if choice then
			lazydo:sort_tasks(choice.value)
		end
	end)
end

function M.show_template_menu(lazydo)
	local task = lazydo:get_current_task()
	if not task then
		vim.notify("No task selected", vim.log.levels.WARN)
		return
	end

	local template_options = {
		{ text = "Save as template", value = "save" },
		{ text = "Create from template", value = "create" },
	}

	vim.ui.select(template_options, {
		prompt = "Template operation:",
		format_item = function(item)
			return item.text
		end,
	}, function(choice)
		if not choice then
			return
		end

		if choice.value == "save" then
			lazydo:save_as_template(task)
		else
			lazydo:create_from_template()
		end
	end)
end

function M.show_statistics(lazydo)
	local stats = lazydo:get_detailed_statistics()
	local stats_lines = {
		"Task Statistics",
		string.rep("─", 40),
		string.format("Total Tasks: %d", stats.total),
		string.format("Completion Rate: %.1f%%", stats.completion_rate),
		string.format("Average Completion Time: %.1f days", stats.average_completion_time / (24 * 60 * 60)),
		"",
		"Priority Distribution:",
		string.format("  High: %d", stats.priority.high),
		string.format("  Medium: %d", stats.priority.medium),
		string.format("  Low: %d", stats.priority.low),
		"",
		"Status:",
		string.format("  Done: %d", stats.done),
		string.format("  Pending: %d", stats.pending),
		string.format("  Overdue: %d", stats.overdue),
		"",
		"Tags:",
	}

	for tag, count in pairs(stats.tags) do
		table.insert(stats_lines, string.format("  #%s: %d", tag, count))
	end

	-- Create a temporary floating window to display statistics
	local buf = vim.api.nvim_create_buf(false, true)
	local width = 50
	local height = #stats_lines
	local win = vim.api.nvim_open_win(buf, true, {
		relative = "editor",
		width = width,
		height = height,
		row = math.floor((vim.o.lines - height) / 2),
		col = math.floor((vim.o.columns - width) / 2),
		style = "minimal",
		border = "rounded",
		title = " Statistics ",
		title_pos = "center",
	})

	vim.api.nvim_buf_set_lines(buf, 0, -1, false, stats_lines)
	vim.api.nvim_buf_set_option(buf, "modifiable", false)
	vim.api.nvim_win_set_option(win, "wrap", false)

	-- Close on any key press
	vim.keymap.set("n", "q", function()
		vim.api.nvim_win_close(win, true)
		vim.api.nvim_buf_delete(buf, { force = true })
	end, { buffer = buf, nowait = true })
end

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
		PRIORITY_HIGH = "",
		PRIORITY_MEDIUM = "",
		PRIORITY_LOW = "󰻂",
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
	lazydo:setup_highlights()

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
	local title_str = string.format(" %s Title: %s %s %s%s ", fold_indicator, status, priority_icon, task.content, tags_str)
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
			local urgency = days_left < 0 and "󰀦 "
				or days_left == 0 and "󰥕 "
				or days_left <= 2 and "󰠠 "
				or days_left <= 7 and "󰥔 "
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
				indent
					.. box.VERTICAL
					.. string.format(" %s Notes:", icons.note)
					.. string.rep(" ", inner_width - 8)
					.. box.VERTICAL
			)

			-- Smart text wrapping for notes with proper word boundaries
			local max_width = inner_width - 4 -- Account for borders and padding
			local words = vim.split(task.notes, " ")
			local current_line = ""

			for _, word in ipairs(words) do
				if #word > max_width then
					-- Word is too long, needs to be split
					if current_line ~= "" then
						table.insert(
							lines,
							indent
								.. box.VERTICAL
								.. "  "
								.. utils.pad_right(current_line, inner_width - 2)
								.. box.VERTICAL
						)
						current_line = ""
					end

					-- Split long word
					local remaining = word
					while #remaining > 0 do
						local part = remaining:sub(1, max_width)
						table.insert(
							lines,
							indent .. box.VERTICAL .. "  " .. utils.pad_right(part, inner_width - 2) .. box.VERTICAL
						)
						remaining = remaining:sub(max_width + 1)
					end
				else
					local potential_line = current_line ~= "" and (current_line .. " " .. word) or word
					if #potential_line > max_width then
						table.insert(
							lines,
							indent
								.. box.VERTICAL
								.. "  "
								.. utils.pad_right(current_line, inner_width - 2)
								.. box.VERTICAL
						)
						current_line = word
					else
						current_line = potential_line
					end
				end
			end

			if current_line ~= "" then
				table.insert(
					lines,
					indent .. box.VERTICAL .. "  " .. utils.pad_right(current_line, inner_width - 2) .. box.VERTICAL
				)
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
			local progress_text = string.format(
				" Subtasks (%d/%d) %d%% %s ",
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
				table.insert(
					lines,
					indent .. box.VERTICAL .. utils.pad_right(subtask_line, inner_width) .. box.VERTICAL
				)
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
			table.insert(
				metadata,
				string.format("%s Completed: %s", icons.bullet, os.date("%Y-%m-%d", task.last_completed))
			)
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

	-- Core task management
	vim.keymap.set("n", lazydo.opts.keymaps.add_task, function()
		lazydo:create_task_prompt()
	end, { buffer = buf, desc = "Add new task", silent = true })

	vim.keymap.set("n", lazydo.opts.keymaps.toggle_done, function()
		local task = lazydo:get_current_task()
		if task then
			task:toggle()
			if lazydo.opts.storage.auto_save then
				require("lazydo.storage").save_tasks(lazydo)
			end
			lazydo:refresh_display()
		end
	end, { buffer = buf, desc = "Toggle task completion", silent = true })

	-- Task movement
	vim.keymap.set("n", lazydo.opts.keymaps.move_up, function()
		local task = lazydo:get_current_task()
		if task then
			lazydo:move_task(task, -1)
		end
	end, { buffer = buf, desc = "Move task up", silent = true })

	vim.keymap.set("n", lazydo.opts.keymaps.move_down, function()
		local task = lazydo:get_current_task()
		if task then
			lazydo:move_task(task, 1)
		end
	end, { buffer = buf, desc = "Move task down", silent = true })

	-- Priority management
	vim.keymap.set("n", lazydo.opts.keymaps.increase_priority, function()
		local task = lazydo:get_current_task()
		if task and task.priority < 3 then
			task.priority = task.priority + 1
			task.updated_at = os.time()
			if lazydo.opts.storage.auto_save then
				require("lazydo.storage").save_tasks(lazydo)
			end
			lazydo:refresh_display()
		end
	end, { buffer = buf, desc = "Increase priority", silent = true })

	vim.keymap.set("n", lazydo.opts.keymaps.decrease_priority, function()
		local task = lazydo:get_current_task()
		if task and task.priority > 1 then
			task.priority = task.priority - 1
			task.updated_at = os.time()
			if lazydo.opts.storage.auto_save then
				require("lazydo.storage").save_tasks(lazydo)
			end
			lazydo:refresh_display()
		end
	end, { buffer = buf, desc = "Decrease priority", silent = true })

	vim.keymap.set("n", lazydo.opts.keymaps.add_subtask, function()
		lazydo:add_subtask()
	end, { buffer = buf, desc = "Add subtask", silent = true })

	vim.keymap.set("n", lazydo.opts.keymaps.edit_subtask, function()
		lazydo:edit_subtask()
	end, { buffer = buf, desc = "Edit subtask", silent = true })

	vim.keymap.set("n", lazydo.opts.keymaps.delete_task, function()
		lazydo:delete_task()
	end, { buffer = buf, desc = "Delete task", silent = true })

	-- Advanced Task Management
	vim.keymap.set("n", lazydo.opts.keymaps.search, function()
		M.show_search_prompt(lazydo)
	end, { buffer = buf, desc = "Search tasks", silent = true })

	vim.keymap.set("n", lazydo.opts.keymaps.filter, function()
		M.show_filter_menu(lazydo)
	end, { buffer = buf, desc = "Filter tasks", silent = true })

	vim.keymap.set("n", lazydo.opts.keymaps.sort_menu, function()
		M.show_sort_menu(lazydo)
	end, { buffer = buf, desc = "Sort tasks", silent = true })

	vim.keymap.set("n", lazydo.opts.keymaps.templates, function()
		M.show_template_menu(lazydo)
	end, { buffer = buf, desc = "Template operations", silent = true })

	vim.keymap.set("n", lazydo.opts.keymaps.quick_stats, function()
		M.show_statistics(lazydo)
	end, { buffer = buf, desc = "Show detailed statistics", silent = true })

	-- Reset filtered/searched results
	vim.keymap.set("n", lazydo.opts.keymaps.clear_filter, function()
		if lazydo._original_tasks then
			lazydo.tasks = lazydo._original_tasks
			lazydo._original_tasks = nil
			lazydo:refresh_display()
			vim.notify("Reset to original task list")
		end
	end, { buffer = buf, desc = "Reset to original tasks", silent = true })

	-- Quick actions
	vim.keymap.set("n", lazydo.opts.keymaps.quick_note, function()
		lazydo:set_note(lazydo:get_current_task())
	end, { buffer = buf, desc = "Add/edit note", silent = true })

	vim.keymap.set("n", lazydo.opts.keymaps.quick_date, function()
		lazydo:set_date(lazydo:get_current_task())
	end, { buffer = buf, desc = "Set due date", silent = true })

	vim.keymap.set("n", lazydo.opts.keymaps.edit_task, function()
		M.show_quick_edit_menu(lazydo)
	end, { buffer = buf, desc = "Edit task", silent = true })

	-- Task movement
	vim.keymap.set("n", lazydo.opts.keymaps.move_up, function()
		local task = lazydo:get_current_task()
		if task then
			lazydo:move_task(task, -1)
		end
	end, { buffer = buf, desc = "Move task up", silent = true })

	vim.keymap.set("n", lazydo.opts.keymaps.move_down, function()
		local task = lazydo:get_current_task()
		if task then
			lazydo:move_task(task, 1)
		end
	end, { buffer = buf, desc = "Move task down", silent = true })

	-- UI controls
	vim.keymap.set("n", lazydo.opts.keymaps.toggle_help, function()
		M.toggle_help(lazydo)
	end, { buffer = buf, desc = "Toggle help", silent = true })

	vim.keymap.set("n", lazydo.opts.keymaps.close_window, function()
		lazydo:close_window()
	end, { buffer = buf, desc = "Close window", silent = true })

	vim.keymap.set("n", lazydo.opts.keymaps.refresh_view, function()
		lazydo:refresh_display()
	end, { buffer = buf, desc = "Refresh view", silent = true })

	-- Quick add tasks
	vim.keymap.set("n", lazydo.opts.keymaps.quick_add or "o", function()
		vim.ui.input({
			prompt = "Quick task: ",
		}, function(input)
			if input and input ~= "" then
				lazydo:add_task(input, { priority = 2 })
				lazydo:refresh_display()
			end
		end)
	end, { buffer = buf, desc = "Quick add task", silent = true })

	vim.keymap.set("n", lazydo.opts.keymaps.add_below or "O", function()
		local current = lazydo:get_current_task()
		if not current then
			-- If no current task, just add at the end
			vim.ui.input({
				prompt = "New task: ",
			}, function(input)
				if input and input ~= "" then
					lazydo:add_task(input, { priority = 2 })
					lazydo:refresh_display()
				end
			end)
			return
		end

		vim.ui.input({
			prompt = "New task below: ",
		}, function(input)
			if input and input ~= "" then
				-- Find current task's index
				local current_index = nil
				for i, task in ipairs(lazydo.tasks) do
					if task.id == current.id then
						current_index = i
						break
					end
				end

				if current_index then
					-- Create new task
					local new_task = lazydo:add_task(input, {
						priority = current.priority, -- Inherit priority
						tags = vim.deepcopy(current.tags), -- Inherit tags
					})

					-- Move the new task to position after current task
					local new_index = nil
					for i, task in ipairs(lazydo.tasks) do
						if task.id == new_task.id then
							new_index = i
							break
						end
					end

					if new_index then
						-- Move the task to the position after current task
						table.remove(lazydo.tasks, new_index)
						table.insert(lazydo.tasks, current_index + 1, new_task)
					end

					-- Save and refresh
					if lazydo.opts.storage.auto_save then
						require("lazydo.storage").save_tasks(lazydo)
					end
					lazydo:refresh_display()
				end
			end
		end)
	end, { buffer = buf, desc = "Add task below current", silent = true })

	-- Toggle subtask completion
	vim.keymap.set("n", lazydo.opts.keymaps.toggle_subtask or "<C-Space>", function()
		M.toggle_subtask_completion(lazydo)
	end, { buffer = buf, desc = "Toggle subtask completion", silent = true })

	-- Backup controls
	vim.keymap.set("n", "<leader>bb", function()
		M.create_backup(lazydo)
	end, { buffer = buf, desc = "Create backup", silent = true })

	vim.keymap.set("n", "<leader>br", function()
		M.restore_from_backup(lazydo)
	end, { buffer = buf, desc = "Restore from backup", silent = true })
end

function M.setup_task_highlights(lazydo)
    local ns = vim.api.nvim_create_namespace("lazydo_task_highlights")
    vim.api.nvim_buf_clear_namespace(lazydo.buf, ns, 0, -1)

    local function add_hl(line, col_start, col_end, group)
        vim.api.nvim_buf_add_highlight(lazydo.buf, ns, group, line, col_start, col_end)
    end

    local lines = vim.api.nvim_buf_get_lines(lazydo.buf, 0, -1, false)
    local current_line = vim.api.nvim_win_get_cursor(lazydo.win)[1]
    local header_lines = 4
    
    -- Task tracking variables
    local in_task = false
    local empty_line_count = 0
    local current_task_start = nil
    local current_task_end = nil
    local task_content_start = false

    -- First pass: find the current task boundaries
    for i, line in ipairs(lines) do
        local lnum = i - 1
        if lnum < header_lines then
            goto continue
        end

        local content = line:gsub("^%s+", "")
        
        -- Track empty lines for task boundaries
        if content == "" then
            empty_line_count = empty_line_count + 1
            goto continue
        else
            empty_line_count = 0
        end

        -- Detect task start
        if content:match("^╭") then
            in_task = true
            task_content_start = true
            -- Check if this is the active task
            if current_line >= lnum and not current_task_start then
                current_task_start = lnum
            end
        -- Detect task end
        elseif content:match("^╰") then
            if current_task_start and not current_task_end and current_line <= lnum then
                current_task_end = lnum
            end
            in_task = false
            task_content_start = false
        end

        -- Apply highlights
        if in_task then
            -- Highlight active task
            -- if current_task_start and lnum >= current_task_start and (not current_task_end or lnum <= current_task_end) then
            --     add_hl(lnum, 0, #line, "LazyDoActiveTask")
            -- end

            -- Highlight task components
            if task_content_start then
                -- Title line highlights
                local title_start = line:find("Title:")
                if title_start then
                    add_hl(lnum, title_start - 1, #line, "LazyDoHeader")
                    
                    -- Status icon highlight
                    local status_start = line:find(lazydo.opts.icons.task_done)
                        or line:find(lazydo.opts.icons.task_pending)
                        or line:find(lazydo.opts.icons.task_overdue)
                    if status_start then
                        local status_group = line:find(lazydo.opts.icons.task_done) and "LazyDoDone"
                            or line:find(lazydo.opts.icons.task_overdue) and "LazyDoOverdue"
                            or "LazyDoPending"
                        add_hl(lnum, status_start - 1, status_start + 1, status_group)
                    end
                end
            end

            -- Highlight subtasks section
            if content:match("Subtasks") then
                add_hl(lnum, 0, #line, "LazyDoSubtask")
            elseif content:match("└─") or content:match("├─") then
                -- Subtask status highlight
                local status_start = line:find(lazydo.opts.icons.task_done)
                    or line:find(lazydo.opts.icons.task_pending)
                if status_start then
                    local status_group = line:find(lazydo.opts.icons.task_done) and "LazyDoDone" or "LazyDoPending"
                    add_hl(lnum, status_start - 1, status_start + 1, status_group)
                end
                
                -- Highlight current subtask line
                if lnum + 1 == current_line then
                    add_hl(lnum, 0, #line, "LazyDoActiveTask")
                end
            end

            -- Highlight progress bar
            if content:match("%%") then
                local progress_start = line:find("█")
                if progress_start then
                    local progress_end = line:find("░")
                    if progress_end then
                        add_hl(lnum, progress_start - 1, progress_end - 1, "LazyDoProgressFull")
                        add_hl(lnum, progress_end - 1, #line - 1, "LazyDoProgressEmpty")
                    end
                end
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
		" Task Management:",
		" <Return>    - Toggle Task completion",
		" <C-Return>  - Toggle subtask completion",
		" e          - Edit Task menu",
		" dd         - Delete Task",
		" a          - Add new Task",
		" A          - Add subTask to current Task",
		" o			     - Add Quick Task",
		" O 		     - Add Quick Task below current Task",
		" n          - Add/edit note",
		" d          - Set due date",
		" >/<        - Increase/decrease priority",
		" s		- Search tasks",
		" f		- Filter tasks",
		" S		- Sort tasks",
		" t     - Template operations",
		" I		- Show detailed stats",
		" R- Reset to original list",
		string.rep("─", help_width),
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

function M.render_progress_bar(total, completed, width)
	if total == 0 then
		return string.rep("░", width)
	end

	local progress = completed / total
	local filled_width = math.floor(width * progress)
	local empty_width = width - filled_width

	-- Use block characters with green for filled and white for empty
	local filled = string.rep("█", filled_width)
	local empty = string.rep("░", empty_width)

	return filled .. empty
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

	-- Define colors for different elements
	local colors = {
		separator = "#6272a4", -- Soft purple for separators
		numbers = "#bd93f9", -- Bright purple for numbers
		labels = "#f8f8f2", -- White for labels
		warning = "#ffb86c", -- Orange for warnings
		success = "#50fa7b", -- Green for success
		error = "#ff5555", -- Red for errors/overdue
	}

	-- Create styled segments
	local function styled_number(num, color)
		return string.format("%%#0x%s#%d%%#0x%s#", color:sub(2), num, colors.labels:sub(2))
	end

	local function separator()
		return string.format("%%#0x%s#│%%#0x%s#", colors.separator:sub(2), colors.labels:sub(2))
	end

	-- Format each statistic with appropriate colors
	local segments = {
		string.format(" Tasks: %s ", styled_number(stats.total, colors.numbers)),
		string.format(" Done: %s ", styled_number(stats.done, colors.success)),
		string.format(" Pending: %s ", styled_number(stats.pending, colors.warning)),
		string.format(" Overdue: %s ", styled_number(stats.overdue, colors.error)),
	}

	-- Create progress bar
	local progress_width = 20
	local progress = stats.done / (stats.total > 0 and stats.total or 1)
	local progress_bar = M.render_progress_bar(stats.total, stats.done, progress_width)

	-- Calculate completion percentage
	local percentage = math.floor(progress * 100)
	local percentage_color = percentage >= 80 and colors.success or percentage >= 50 and colors.warning or colors.error

	-- Add percentage to segments
	table.insert(segments, string.format(" Progress: %s%% ", styled_number(percentage, percentage_color)))

	-- Combine all elements with separators
	local status_line = table.concat(segments, separator())
	status_line = status_line .. separator() .. " " .. progress_bar

	-- Add task count summary if there are filtered results
	if lazydo._original_tasks then
		local filtered_count = #lazydo.tasks
		local total_count = #lazydo._original_tasks
		local filter_info = string.format(
			" %%#0x%s#(Showing %d/%d)%%#0x%s#",
			colors.warning:sub(2),
			filtered_count,
			total_count,
			colors.labels:sub(2)
		)
		status_line = status_line .. separator() .. filter_info
	end

	-- Add to virtual text with padding to fill the width
	vim.api.nvim_buf_clear_namespace(lazydo.buf, lazydo.ns.virtual, 0, -1)
	vim.api.nvim_buf_set_extmark(lazydo.buf, lazydo.ns.virtual, 0, 0, {
		virt_text = { { status_line, "LazyDoStatusLine" } },
		virt_text_pos = "overlay",
		priority = 100,
	})

	-- Add a separator line below the status line
	local separator_line = string.format("%%#0x%s#%s", colors.separator:sub(2), string.rep("─", total_width))
	vim.api.nvim_buf_set_extmark(lazydo.buf, lazydo.ns.virtual, 1, 0, {
		virt_text = { { separator_line, "LazyDoStatusLine" } },
		virt_text_pos = "overlay",
		priority = 100,
	})
end

function M.toggle_subtask_completion(lazydo)
	local task = lazydo:get_current_task()
	if not task then
		vim.notify("No task selected", vim.log.levels.WARN)
		return
	end

	-- Get cursor position and buffer content
	local cursor = vim.api.nvim_win_get_cursor(lazydo.win)
	local current_line = cursor[1]
	local lines = vim.api.nvim_buf_get_lines(lazydo.buf, 0, -1, false)
	local line_content = lines[current_line]

	-- Check if cursor is on a subtask line
	if not line_content or not (line_content:match("└─") or line_content:match("├─")) then
		vim.notify("Not on a subtask line", vim.log.levels.WARN)
		return
	end

	-- Find task boundaries and subtask section
	local task_start = nil
	local subtask_section_start = nil
	local subtask_index = 0

	-- Scan backwards to find task start and subtask section
	for i = current_line, 1, -1 do
		local line = lines[i]
		if line:match("^%s*╭") then -- Found task start
			task_start = i
			break
		elseif line:match("Subtasks") then -- Found subtask section
			subtask_section_start = i
		end
	end

	if not task_start or not subtask_section_start then
		vim.notify("Could not find task boundaries", vim.log.levels.WARN)
		return
	end

	-- Count subtasks from subtask section to current line
	for i = subtask_section_start + 1, current_line do
		local line = lines[i]
		if line:match("└─") or line:match("├─") then
			subtask_index = subtask_index + 1
			if i == current_line then
				-- Found our subtask
				if subtask_index <= #task.subtasks then
					-- Toggle the subtask completion
					task.subtasks[subtask_index].done = not task.subtasks[subtask_index].done
					task.updated_at = os.time()

					-- Save if auto-save is enabled
					if lazydo.opts.storage.auto_save then
						require("lazydo.storage").save_tasks(lazydo)
					end

					-- Refresh the display
					lazydo:refresh_display()
					return
				end
				break
			end
		end
	end

	vim.notify("Could not determine subtask position", vim.log.levels.WARN)
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

-- Create a backup of current tasks
function M.create_backup(lazydo)
	if not lazydo or not lazydo.tasks then
		vim.notify("No tasks to backup", vim.log.levels.WARN)
		return
	end

	-- Get the current tasks file path and create backup path
	local tasks_file = lazydo.opts.storage.file
	local backup_file = tasks_file .. ".backup"

	-- Create a backup table with metadata
	local backup_data = {
		timestamp = os.time(),
		tasks = vim.deepcopy(lazydo.tasks),
		metadata = {
			total_tasks = #lazydo.tasks,
			backup_date = os.date("%Y-%m-%d %H:%M:%S"),
		},
	}

	-- Save the backup
	local backup_json = vim.json.encode(backup_data)
	local file = io.open(backup_file, "w")
	if file then
		file:write(backup_json)
		file:close()
		vim.notify(string.format("Backup created with %d tasks", #lazydo.tasks), vim.log.levels.INFO)
	else
		vim.notify("Failed to create backup", vim.log.levels.ERROR)
	end
end

-- Restore tasks from backup
function M.restore_from_backup(lazydo)
	-- Get the backup file path
	local tasks_file = lazydo.opts.storage.file
	local backup_file = tasks_file .. ".backup"

	-- Check if backup exists
	local file = io.open(backup_file, "r")
	if not file then
		vim.notify("No backup file found", vim.log.levels.WARN)
		return
	end

	-- Read and parse backup data
	local content = file:read("*all")
	file:close()

	local ok, backup_data = pcall(vim.json.decode, content)
	if not ok or not backup_data or not backup_data.tasks then
		vim.notify("Invalid backup file", vim.log.levels.ERROR)
		return
	end

	-- Confirm restoration with user
	local backup_date = backup_data.metadata and backup_data.metadata.backup_date or "unknown date"
	local msg = string.format("Restore %d tasks from backup (%s)?", #backup_data.tasks, backup_date)

	vim.ui.select({ "Yes", "No" }, {
		prompt = msg,
	}, function(choice)
		if choice == "Yes" then
			-- Restore tasks
			lazydo.tasks = backup_data.tasks
			if lazydo.opts.storage.auto_save then
				require("lazydo.storage").save_tasks(lazydo)
			end
			lazydo:refresh_display()
			vim.notify(string.format("Restored %d tasks from backup", #backup_data.tasks), vim.log.levels.INFO)
		end
	end)
end

return M
