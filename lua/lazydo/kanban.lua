-- Enhanced Kanban Board for LazyDo
-- Author: LazyDo Team
-- License: MIT

local Utils = require("lazydo.utils")
local Task = require("lazydo.task")
local Actions = require("lazydo.actions")
local api = vim.api
local ns_id = api.nvim_create_namespace("LazyDoKanban")

---@class Kanban
---@field private config table Configuration options
---@field private state KanbanState Current state of the kanban board
local Kanban = {}

---@class KanbanState
---@field buf number Buffer handle
---@field win number Window handle
---@field tasks Task[] Current tasks
---@field cursor_pos table {col: number, row: number}
---@field columns table[] Kanban columns
---@field column_width number Width of each column
---@field column_positions table<string, {start: number, end: number}>
---@field card_positions table<string, {col: number, row: number, width: number, height: number}>
---@field on_task_update function?
---@field drag_active boolean Whether drag operation is active
---@field drag_task string? ID of task being dragged
---@field collapsed_columns table<string, boolean> Collapsed state of columns
---@field filter table? Current active filter
---@field search_term string? Current search term
---@field column_pages table<string, number> Current page for each column
---@field column_pages_info table Column pagination info
---@field column_task_counts table Task counts per column
---@field animations table<string, table> Active animations
local state = {
    buf = nil,
    win = nil,
    tasks = {},
    cursor_pos = { col = 1, row = 1 },
    columns = {},
    column_width = 30,
    column_positions = {},
    card_positions = {},
    on_task_update = nil,
    drag_active = false,
    drag_task = nil,
    collapsed_columns = {},
    filter = nil,
    search_term = nil,
    column_pages = {},
    column_pages_info = {},
    column_task_counts = {},
    animations = {},
}

-- Configuration with defaults
Kanban.config = {
    views = {
        kanban = {
            columns = {
                { id = "backlog", title = "Backlog", filter = { status = "pending" } },
                { id = "in_progress", title = "In Progress", filter = { status = "in_progress" } },
                { id = "blocked", title = "Blocked", filter = { status = "blocked" } },
                { id = "done", title = "Done", filter = { status = "done" } },
            },
            colors = {
                column_header = { fg = "#7dcfff", bold = true },
                column_border = { fg = "#3b4261" },
                card_border = { fg = "#565f89" },
                card_title = { fg = "#c0caf5", bold = true },
            },
            card_width = 30,
            show_task_count = true,
            drag_and_drop = true,
            max_tasks_per_column = 100,
        },
    },
}

-- Utility functions
local function is_valid_window()
    return state.win and api.nvim_win_is_valid(state.win)
end

local function is_valid_buffer()
    return state.buf and api.nvim_buf_is_valid(state.buf)
end

function Kanban.is_valid()
    return is_valid_window() and is_valid_buffer()
end

local function clear_state()
    state.buf = nil
    state.win = nil
    state.tasks = {}
    state.cursor_pos = { col = 1, row = 1 }
    state.columns = {}
    state.column_positions = {}
    state.card_positions = {}
    state.drag_active = false
    state.drag_task = nil
    state.collapsed_columns = {}
    state.filter = nil
    state.search_term = nil
    state.column_pages = {}
    state.column_pages_info = {}
    state.column_task_counts = {}
    state.animations = {}
end

-- Setup highlight groups
local function setup_highlights()
    local colors = Kanban.config.views.kanban.colors
    
    -- Column highlights
    api.nvim_set_hl(0, "LazyDoKanbanColumnHeader", colors.column_header)
    api.nvim_set_hl(0, "LazyDoKanbanColumnBorder", colors.column_border)
    
    -- Card highlights by priority
    api.nvim_set_hl(0, "LazyDoKanbanCardUrgent", { fg = "#ff0000", bold = true })
    api.nvim_set_hl(0, "LazyDoKanbanCardHigh", { fg = "#ff7700", bold = true })
    api.nvim_set_hl(0, "LazyDoKanbanCardMedium", { fg = "#ffff00" })
    api.nvim_set_hl(0, "LazyDoKanbanCardLow", { fg = "#00ff00" })
    
    -- Status highlights
    api.nvim_set_hl(0, "LazyDoKanbanStatusDone", { fg = "#00ff00", bold = true })
    api.nvim_set_hl(0, "LazyDoKanbanStatusBlocked", { fg = "#ff0000", bold = true })
    
    -- Drag highlight
    api.nvim_set_hl(0, "LazyDoKanbanDragActive", { fg = "#ffffff", bg = "#7aa2f7", bold = true })
end

-- Initialize the kanban board
function Kanban.setup(config)
    if config then
        -- Deep merge the configs
        Kanban.config = vim.tbl_deep_extend("force", Kanban.config, config)
    end
    setup_highlights()
end

-- Create or update the kanban window
function Kanban.create_window()
    if is_valid_window() then
        return state.win
    end

    -- Calculate window dimensions
    local width = math.floor(vim.o.columns * 0.9)
    local height = math.floor(vim.o.lines * 0.8)
    local row = math.floor((vim.o.lines - height) / 2)
    local col = math.floor((vim.o.columns - width) / 2)

    -- Create buffer if needed
    if not is_valid_buffer() then
        state.buf = api.nvim_create_buf(false, true)
        api.nvim_buf_set_option(state.buf, "bufhidden", "wipe")
        api.nvim_buf_set_option(state.buf, "buftype", "nofile")
        api.nvim_buf_set_option(state.buf, "swapfile", false)
        api.nvim_buf_set_option(state.buf, "filetype", "lazydo-kanban")
    end

    -- Create window with fancy border
    local win_opts = {
        relative = "editor",
        width = width,
        height = height,
        row = row,
        col = col,
        style = "minimal",
        border = "rounded",
        title = " LazyDo Kanban Board ",
        title_pos = "center",
    }

    state.win = api.nvim_open_win(state.buf, true, win_opts)

    -- Set window options
    api.nvim_win_set_option(state.win, "wrap", false)
    api.nvim_win_set_option(state.win, "cursorline", true)
    api.nvim_win_set_option(state.win, "winhighlight", "Normal:LazyDoNormal,FloatBorder:LazyDoBorder")

    return state.win
end

-- Close the kanban board
function Kanban.close()
    if is_valid_window() then
        api.nvim_win_close(state.win, true)
    end
    
    if is_valid_buffer() then
        api.nvim_buf_delete(state.buf, { force = true })
    end
    
    clear_state()
end

-- Toggle the kanban board
function Kanban.toggle(tasks, callback)
    state.tasks = tasks or {}
    state.on_task_update = callback
    
    if is_valid_window() then
        Kanban.close()
        return
    end
    
    Kanban.create_window()
    Kanban.setup_keymaps()
    Kanban.render()
end

-- Enhanced task filtering with support for complex queries
local function filter_tasks_for_column(tasks, column)
    local filter = column.filter or {}
    local max_tasks = Kanban.config.views.kanban.max_tasks_per_column or 100
    local current_page = state.column_pages[column.id] or 1
    local filtered_tasks = {}

    -- Apply column filter and global filter
    for _, task in ipairs(tasks) do
        local matches = true
        
        -- Apply column filter
        for key, value in pairs(filter) do
            if task[key] ~= value then
                matches = false
                break
            end
        end

        -- Apply global filter if exists
        if matches and state.filter then
            for key, value in pairs(state.filter) do
                if key == "due_today" then
                    local today = os.date("%Y-%m-%d")
                    matches = task.due_date == today
                elseif key == "overdue" then
                    local today = os.date("%Y-%m-%d")
                    matches = task.due_date and task.due_date < today
                elseif key == "has_subtasks" then
                    matches = task.subtasks and #task.subtasks > 0
                elseif key == "has_notes" then
                    matches = task.notes and #task.notes > 0
                else
                    matches = task[key] == value
                end
                if not matches then break end
            end
        end

        -- Apply search term if exists
        if matches and state.search_term then
            local term = state.search_term:lower()
            matches = task.content:lower():find(term, 1, true) ~= nil
                or (task.notes and task.notes:lower():find(term, 1, true) ~= nil)
        end

        if matches then
            table.insert(filtered_tasks, task)
        end
    end

    -- Sort tasks
    table.sort(filtered_tasks, function(a, b)
        -- Sort by status first (pending tasks first)
        if a.status ~= b.status then
            if a.status == "done" then return false end
            if b.status == "done" then return true end
        end

        -- Then by priority
        local priority_order = { urgent = 0, high = 1, medium = 2, low = 3 }
        if a.priority ~= b.priority then
            return priority_order[a.priority] < priority_order[b.priority]
        end

        -- Then by due date if available
        if a.due_date and b.due_date then
            return a.due_date < b.due_date
        elseif a.due_date then
            return true
        elseif b.due_date then
            return false
        end

        -- Finally by creation date
        return (a.created_at or 0) < (b.created_at or 0)
    end)

    -- Apply pagination
    local total_tasks = #filtered_tasks
    local start_idx = (current_page - 1) * max_tasks + 1
    local end_idx = math.min(start_idx + max_tasks - 1, total_tasks)

    local paginated_tasks = {}
    for i = start_idx, end_idx do
        if filtered_tasks[i] then
            table.insert(paginated_tasks, filtered_tasks[i])
        end
    end

    -- Update pagination info
    state.column_task_counts[column.id] = total_tasks
    state.column_pages_info[column.id] = {
        current = current_page,
        total = math.ceil(total_tasks / max_tasks)
    }

    return paginated_tasks
end

-- Enhanced rendering functions with beautiful UI elements
local function render_column_header(column, width, pos_x)
    local lines = {}
    local highlights = {}
    local config = Kanban.config.views.kanban

    -- Create fancy header
    local title = column.title
    local task_count = state.column_task_counts[column.id] or 0
    local page_info = state.column_pages_info[column.id]
    
    -- Add collapse indicator and task count
    local collapse_icon = state.collapsed_columns[column.id] and "▼" or "▶"
    local header_text = string.format(" %s %s (%d)", collapse_icon, title, task_count)
    
    -- Add pagination if needed
    if page_info and page_info.total > 1 then
        header_text = header_text .. string.format(" [%d/%d]", page_info.current, page_info.total)
    end

    -- Center the header text
    local padding = math.floor((width - vim.fn.strwidth(header_text)) / 2)
    local header = string.rep(" ", padding) .. header_text .. string.rep(" ", width - padding - vim.fn.strwidth(header_text))

    table.insert(lines, header)
    table.insert(highlights, {
        line = 0,
        col = 0,
        length = #header,
        group = "LazyDoKanbanColumnHeader"
    })

    -- Add a fancy separator
    local separator = string.rep("─", width)
    table.insert(lines, separator)
    table.insert(highlights, {
        line = 1,
        col = 0,
        length = #separator,
        group = "LazyDoKanbanColumnBorder"
    })

    return lines, highlights
end

-- Enhanced task card rendering with modern design
local function render_task_card(task, width)
    local lines = {}
    local highlights = {}
    local card_width = width - 2
    local config = Kanban.config.views.kanban

    -- Get task properties
    local priority = task.priority or "medium"
    local status = task.status or "pending"
    local is_dragged = state.drag_active and state.drag_task == task.id

    -- Define border characters based on priority
    local borders = {
        urgent = { "╔", "╗", "╚", "╝", "═", "║" },
        high =   { "┏", "┓", "┗", "┛", "━", "┃" },
        medium = { "┌", "┐", "└", "┘", "─", "│" },
        low =    { "╭", "╮", "╰", "╯", "─", "│" }
    }
    local b = borders[priority]

    -- Create top border with priority indicator
    local priority_icon = config.icons.priority[priority] or ""
    local status_icon = config.icons["task_" .. status] or ""
    
    -- Create title with icons
    local title_line = string.format("%s %s %s %s", b[6], status_icon, priority_icon,
        Utils.Str.truncate(task.content, card_width - 8))
    
    -- Add task border
    table.insert(lines, b[1] .. string.rep(b[5], card_width - 2) .. b[2])
    table.insert(lines, title_line)

    -- Add metadata if available
    if task.due_date then
        local date_line = string.format("%s Due: %s %s", b[6], task.due_date,
            string.rep(" ", card_width - 11 - #task.due_date) .. b[6])
        table.insert(lines, date_line)
    end

    -- Add progress bar if task has subtasks
    if task.subtasks and #task.subtasks > 0 then
        local completed = 0
        for _, subtask in ipairs(task.subtasks) do
            if subtask.status == "done" then
                completed = completed + 1
            end
        end
        
        local progress = math.floor((completed / #task.subtasks) * 100)
        local bar_width = card_width - 12
        local filled = math.floor(bar_width * progress / 100)
        local progress_bar = string.rep("█", filled) .. string.rep("░", bar_width - filled)
        local progress_line = string.format("%s %3d%% %s %s", b[6], progress, progress_bar, b[6])
        
        table.insert(lines, progress_line)
    end

    -- Add bottom border
    table.insert(lines, b[3] .. string.rep(b[5], card_width - 2) .. b[4])

    -- Add highlights
    local highlight_group = is_dragged and "LazyDoKanbanDragActive" or "LazyDoKanbanCard" .. priority:gsub("^%l", string.upper)
    for i = 1, #lines do
        table.insert(highlights, {
            line = i - 1,
            col = 0,
            length = #lines[i],
            group = highlight_group
        })
    end

    return lines, highlights
end

-- Render a column with its tasks
local function render_column(column, pos_x)
    local lines = {}
    local highlights = {}
    local width = state.column_width
    local tasks = filter_tasks_for_column(state.tasks, column)

    -- Store column position
    state.column_positions[column.id] = {
        start = pos_x,
        ["end"] = pos_x + width,
        collapsed = state.collapsed_columns[column.id]
    }

    -- Render header
    local header_lines, header_highlights = render_column_header(column, width, pos_x)
    for _, line in ipairs(header_lines) do
        table.insert(lines, line)
    end
    for _, hl in ipairs(header_highlights) do
        table.insert(highlights, hl)
    end

    -- If column is not collapsed, render tasks
    if not state.collapsed_columns[column.id] then
        local current_line = #lines
        for _, task in ipairs(tasks) do
            local card_lines, card_highlights = render_task_card(task, width)
            
            -- Store card position
            state.card_positions[task.id] = {
                col = pos_x,
                row = current_line + 1,
                width = width,
                height = #card_lines,
                column_id = column.id
            }
            
            -- Add card lines
            for _, line in ipairs(card_lines) do
                table.insert(lines, line)
                current_line = current_line + 1
            end
            
            -- Add card highlights
            for _, hl in ipairs(card_highlights) do
                hl.line = hl.line + current_line
                table.insert(highlights, hl)
            end
            
            -- Add spacing between cards
            table.insert(lines, string.rep(" ", width))
            current_line = current_line + 1
        end
    end

    return lines, highlights
end

-- Render the entire board
function Kanban.render()
    if not is_valid_buffer() or not is_valid_window() then
        return
    end

    -- Clear existing highlights
    api.nvim_buf_clear_namespace(state.buf, ns_id, 0, -1)

    -- Calculate layout
    local win_width = api.nvim_win_get_width(state.win)
    local num_columns = #state.columns
    local column_width = math.floor((win_width - num_columns - 1) / num_columns)
    state.column_width = column_width

    -- Render columns
    local all_lines = {}
    local all_highlights = {}
    local max_height = 0

    -- First pass: render columns and get max height
    local column_contents = {}
    for i, column in ipairs(state.columns) do
        local pos_x = (i - 1) * (column_width + 1)
        local lines, highlights = render_column(column, pos_x)
        column_contents[i] = { lines = lines, highlights = highlights }
        max_height = math.max(max_height, #lines)
    end

    -- Second pass: pad columns to equal height and combine
    for i, content in ipairs(column_contents) do
        local pos_x = (i - 1) * (column_width + 1)
        local lines = content.lines
        local highlights = content.highlights

        -- Pad to max height
        while #lines < max_height do
            table.insert(lines, string.rep(" ", column_width))
        end

        -- Add lines to buffer
        for j, line in ipairs(lines) do
            all_lines[j] = (all_lines[j] or "") .. line .. " "
        end

        -- Adjust highlight positions
        for _, hl in ipairs(highlights) do
            hl.col = hl.col + pos_x
            table.insert(all_highlights, hl)
        end
    end

    -- Set lines and apply highlights
    api.nvim_buf_set_lines(state.buf, 0, -1, false, all_lines)
    for _, hl in ipairs(all_highlights) do
        api.nvim_buf_add_highlight(state.buf, ns_id, hl.group, hl.line, hl.col, hl.col + hl.length)
    end
end

-- Setup keymaps for the kanban board
function Kanban.setup_keymaps()
    if not is_valid_buffer() then
        return
    end

    local function map(mode, lhs, rhs, desc)
        vim.keymap.set(mode, lhs, rhs, {
            buffer = state.buf,
            noremap = true,
            silent = true,
            desc = desc
        })
    end

    -- Navigation
    map("n", "h", function() Kanban.navigate("left") end, "Move left")
    map("n", "l", function() Kanban.navigate("right") end, "Move right")
    map("n", "j", function() Kanban.navigate("down") end, "Move down")
    map("n", "k", function() Kanban.navigate("up") end, "Move up")
    
    -- Task management
    map("n", "<CR>", function() Kanban.toggle_task() end, "Toggle task status")
    map("n", "a", function() Kanban.create_task() end, "Add new task")
    map("n", "e", function() Kanban.edit_task() end, "Edit task")
    map("n", "dd", function() Kanban.delete_task() end, "Delete task")
    
    -- Column management
    map("n", "<", function() Kanban.move_task("left") end, "Move task left")
    map("n", ">", function() Kanban.move_task("right") end, "Move task right")
    map("n", "zc", function() Kanban.toggle_column_collapse() end, "Toggle column collapse")
    
    -- Filtering and sorting
    map("n", "/", function() Kanban.search() end, "Search tasks")
    map("n", "f", function() Kanban.filter() end, "Filter tasks")
    map("n", "s", function() Kanban.sort() end, "Sort tasks")
    
    -- Pagination
    map("n", "[", function() Kanban.prev_page() end, "Previous page")
    map("n", "]", function() Kanban.next_page() end, "Next page")
    
    -- Misc
    map("n", "?", function() Kanban.show_help() end, "Show help")
    map("n", "q", function() Kanban.close() end, "Close board")
    map("n", "<Esc>", function() 
        if state.drag_active then
            Kanban.cancel_drag()
        else
            Kanban.close()
        end
    end, "Cancel drag/Close")
end

-- Task management functions
function Kanban.get_task_under_cursor()
    local cursor = api.nvim_win_get_cursor(state.win)
    local row = cursor[1]
    local col = cursor[2]

    for task_id, pos in pairs(state.card_positions) do
        if row >= pos.row and row <= pos.row + pos.height - 1 and
           col >= pos.col and col <= pos.col + pos.width - 1 then
            for _, task in ipairs(state.tasks) do
                if task.id == task_id then
                    return task
                end
            end
        end
    end
    return nil
end

function Kanban.get_column_under_cursor()
    local cursor = api.nvim_win_get_cursor(state.win)
    local col = cursor[2]

    for column_id, pos in pairs(state.column_positions) do
        if col >= pos.start and col <= pos["end"] then
            for _, column in ipairs(state.columns) do
                if column.id == column_id then
                    return column
                end
            end
        end
    end
    return nil
end

function Kanban.toggle_task()
    local task = Kanban.get_task_under_cursor()
    if not task then return end

    task.status = task.status == "done" and "pending" or "done"
    task.updated_at = os.time()

    if state.on_task_update then
        state.on_task_update(task)
    end

    Kanban.render()
end

function Kanban.create_task()
    local column = Kanban.get_column_under_cursor()
    if not column then
        column = state.columns[1] -- Default to first column
    end

    vim.ui.input({ prompt = "New task: " }, function(input)
        if not input or input == "" then return end

        local task = Task.new(input)
        task.status = column.filter.status or "pending"
        
        table.insert(state.tasks, task)
        
        if state.on_task_update then
            state.on_task_update(task)
        end
        
        Kanban.render()
    end)
end

function Kanban.edit_task()
    local task = Kanban.get_task_under_cursor()
    if not task then return end

    vim.ui.input({ 
        prompt = "Edit task: ",
        default = task.content
    }, function(input)
        if not input or input == "" then return end

        task.content = input
        task.updated_at = os.time()

        if state.on_task_update then
            state.on_task_update(task)
        end

        Kanban.render()
    end)
end

function Kanban.delete_task()
    local task = Kanban.get_task_under_cursor()
    if not task then return end

    vim.ui.select({ "Yes", "No" }, {
        prompt = "Delete task?"
    }, function(choice)
        if choice ~= "Yes" then return end

        for i, t in ipairs(state.tasks) do
            if t.id == task.id then
                table.remove(state.tasks, i)
                break
            end
        end

        if state.on_task_update then
            state.on_task_update(task)
        end

        Kanban.render()
    end)
end

function Kanban.move_task(direction)
    local task = Kanban.get_task_under_cursor()
    if not task then return end

    local current_pos = state.card_positions[task.id]
    if not current_pos then return end

    local current_column
    for _, col in ipairs(state.columns) do
        if col.id == current_pos.column_id then
            current_column = col
            break
        end
    end

    if not current_column then return end

    local target_column
    for i, col in ipairs(state.columns) do
        if col.id == current_column.id then
            if direction == "left" and i > 1 then
                target_column = state.columns[i - 1]
            elseif direction == "right" and i < #state.columns then
                target_column = state.columns[i + 1]
            end
            break
        end
    end

    if not target_column then return end

    -- Animate the movement
    local start_x = current_pos.col
    local end_x = direction == "left" and start_x - state.column_width - 1 or start_x + state.column_width + 1
    local steps = 10
    local step = 0

    local timer = vim.loop.new_timer()
    timer:start(0, 20, vim.schedule_wrap(function()
        step = step + 1
        local progress = step / steps
        local current_x = start_x + (end_x - start_x) * progress

        -- Update card position
        state.card_positions[task.id].col = math.floor(current_x)
        
        -- Render the board
        Kanban.render()

        if step >= steps then
            timer:stop()
            timer:close()

            -- Update task status based on target column
            task.status = target_column.filter.status or task.status
            task.updated_at = os.time()

            if state.on_task_update then
                state.on_task_update(task)
            end

            Kanban.render()
        end
    end))
end

function Kanban.toggle_column_collapse()
    local column = Kanban.get_column_under_cursor()
    if not column then return end

    state.collapsed_columns[column.id] = not state.collapsed_columns[column.id]
    Kanban.render()
end

function Kanban.search()
    vim.ui.input({
        prompt = "Search tasks: "
    }, function(input)
        if not input then return end

        state.search_term = input ~= "" and input or nil
        Kanban.render()
    end)
end

function Kanban.filter()
    local filter_options = {
        { name = "All tasks", filter = nil },
        { name = "High priority", filter = { priority = "high" } },
        { name = "Due today", filter = { due_today = true } },
        { name = "Overdue", filter = { overdue = true } },
        { name = "Has subtasks", filter = { has_subtasks = true } },
        { name = "Clear filter", filter = nil },
    }

    vim.ui.select(
        vim.tbl_map(function(opt) return opt.name end, filter_options),
        { prompt = "Select filter:" },
        function(choice, idx)
            if not choice then return end

            state.filter = filter_options[idx].filter
            Kanban.render()
        end
    )
end

function Kanban.sort()
    local column = Kanban.get_column_under_cursor()
    if not column then return end

    local sort_options = {
        "Priority",
        "Due date",
        "Creation date",
        "Title",
    }

    vim.ui.select(sort_options, {
        prompt = "Sort by:"
    }, function(choice)
        if not choice then return end

        local tasks = filter_tasks_for_column(state.tasks, column)
        table.sort(tasks, function(a, b)
            if choice == "Priority" then
                local priority_order = { urgent = 0, high = 1, medium = 2, low = 3 }
                return priority_order[a.priority or "low"] < priority_order[b.priority or "low"]
            elseif choice == "Due date" then
                if not a.due_date then return false end
                if not b.due_date then return true end
                return a.due_date < b.due_date
            elseif choice == "Creation date" then
                return (a.created_at or 0) < (b.created_at or 0)
            else -- Title
                return a.content < b.content
            end
        end)

        Kanban.render()
    end)
end

function Kanban.prev_page()
    local column = Kanban.get_column_under_cursor()
    if not column then return end

    local page_info = state.column_pages_info[column.id]
    if not page_info or page_info.current <= 1 then return end

    state.column_pages[column.id] = page_info.current - 1
    Kanban.render()
end

function Kanban.next_page()
    local column = Kanban.get_column_under_cursor()
    if not column then return end

    local page_info = state.column_pages_info[column.id]
    if not page_info or page_info.current >= page_info.total then return end

    state.column_pages[column.id] = page_info.current + 1
    Kanban.render()
end

function Kanban.show_help()
    local help_text = {
        "LazyDo Kanban Board Help",
        "",
        "Navigation:",
        "  h/l - Move left/right",
        "  j/k - Move up/down",
        "",
        "Task Management:",
        "  <CR> - Toggle task status",
        "  a    - Add new task",
        "  e    - Edit task",
        "  dd   - Delete task",
        "",
        "Column Management:",
        "  <    - Move task left",
        "  >    - Move task right",
        "  zc   - Toggle column collapse",
        "",
        "Filtering and Sorting:",
        "  /    - Search tasks",
        "  f    - Filter tasks",
        "  s    - Sort tasks",
        "",
        "Pagination:",
        "  [    - Previous page",
        "  ]    - Next page",
        "",
        "Other:",
        "  ?    - Show this help",
        "  q    - Close board",
        "  <Esc> - Cancel drag/Close",
    }

    -- Create help window
    local buf = api.nvim_create_buf(false, true)
    api.nvim_buf_set_lines(buf, 0, -1, false, help_text)
    api.nvim_buf_set_option(buf, "modifiable", false)
    api.nvim_buf_set_option(buf, "buftype", "nofile")
    api.nvim_buf_set_option(buf, "filetype", "help")

    local width = 40
    local height = #help_text
    local row = math.floor((vim.o.lines - height) / 2)
    local col = math.floor((vim.o.columns - width) / 2)

    local win = api.nvim_open_win(buf, true, {
        relative = "editor",
        width = width,
        height = height,
        row = row,
        col = col,
        style = "minimal",
        border = "rounded",
        title = " Kanban Help ",
        title_pos = "center",
    })

    -- Close help with q or <Esc>
    vim.keymap.set("n", "q", function()
        api.nvim_win_close(win, true)
        api.nvim_buf_delete(buf, { force = true })
    end, { buffer = buf, noremap = true })
    vim.keymap.set("n", "<Esc>", function()
        api.nvim_win_close(win, true)
        api.nvim_buf_delete(buf, { force = true })
    end, { buffer = buf, noremap = true })
end

-- Navigation functions
function Kanban.navigate(direction)
    if not is_valid_window() then return end

    local cursor = api.nvim_win_get_cursor(state.win)
    local row, col = cursor[1], cursor[2]
    local new_row, new_col = row, col

    if direction == "left" then
        -- Find the nearest column to the left
        local target_col = nil
        local target_pos = nil
        for column_id, pos in pairs(state.column_positions) do
            if pos.start < col and (not target_pos or pos.start > target_pos.start) then
                target_pos = pos
            end
        end
        if target_pos then
            new_col = target_pos.start + math.floor(state.column_width / 2)
        end
    elseif direction == "right" then
        -- Find the nearest column to the right
        local target_col = nil
        local target_pos = nil
        for column_id, pos in pairs(state.column_positions) do
            if pos.start > col and (not target_pos or pos.start < target_pos.start) then
                target_pos = pos
            end
        end
        if target_pos then
            new_col = target_pos.start + math.floor(state.column_width / 2)
        end
    elseif direction == "up" then
        -- Find the nearest task card above
        local current_task = Kanban.get_task_under_cursor()
        if current_task then
            local current_pos = state.card_positions[current_task.id]
            local target_task = nil
            local target_pos = nil
            for task_id, pos in pairs(state.card_positions) do
                if pos.column_id == current_pos.column_id and
                   pos.row < current_pos.row and
                   (not target_pos or pos.row > target_pos.row) then
                    target_pos = pos
                end
            end
            if target_pos then
                new_row = target_pos.row + math.floor(target_pos.height / 2)
            end
        else
            -- If not on a task, move to the nearest task above
            local target_pos = nil
            for task_id, pos in pairs(state.card_positions) do
                if pos.row < row and pos.col <= col and col <= pos.col + pos.width and
                   (not target_pos or pos.row > target_pos.row) then
                    target_pos = pos
                end
            end
            if target_pos then
                new_row = target_pos.row + math.floor(target_pos.height / 2)
                new_col = target_pos.col + math.floor(target_pos.width / 2)
            end
        end
    elseif direction == "down" then
        -- Find the nearest task card below
        local current_task = Kanban.get_task_under_cursor()
        if current_task then
            local current_pos = state.card_positions[current_task.id]
            local target_task = nil
            local target_pos = nil
            for task_id, pos in pairs(state.card_positions) do
                if pos.column_id == current_pos.column_id and
                   pos.row > current_pos.row and
                   (not target_pos or pos.row < target_pos.row) then
                    target_pos = pos
                end
            end
            if target_pos then
                new_row = target_pos.row + math.floor(target_pos.height / 2)
            end
        else
            -- If not on a task, move to the nearest task below
            local target_pos = nil
            for task_id, pos in pairs(state.card_positions) do
                if pos.row > row and pos.col <= col and col <= pos.col + pos.width and
                   (not target_pos or pos.row < target_pos.row) then
                    target_pos = pos
                end
            end
            if target_pos then
                new_row = target_pos.row + math.floor(target_pos.height / 2)
                new_col = target_pos.col + math.floor(target_pos.width / 2)
            end
        end
    end

    -- Update cursor position
    if new_row ~= row or new_col ~= col then
        api.nvim_win_set_cursor(state.win, { new_row, new_col })
    end
end

-- Cancel drag operation
function Kanban.cancel_drag()
    if not state.drag_active then return end

    state.drag_active = false
    state.drag_task = nil
    Kanban.render()
end

return Kanban
