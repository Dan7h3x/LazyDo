-- Enhanced Kanban Board for LazyDo
-- Author: LazyDo Team
-- License: MIT

local Utils = require("lazydo.utils")
local Task = require("lazydo.task")
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
---@field collapsed_columns table<string, boolean> Collapsed state of columns
---@field filter table? Current active filter
---@field search_term string? Current search term
---@field column_pages table<string, number> Current page for each column
---@field column_pages_info table Column pagination info
---@field column_task_counts table Task counts per column
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
  collapsed_columns = {},
  filter = nil,
  search_term = nil,
  column_pages = {},
  column_pages_info = {},
  column_task_counts = {},
}

-- Configuration with enhanced visual defaults
Kanban.config = {
  views = {
    kanban = {
      columns = {
        { id = "backlog",     title = "Backlog",     filter = { status = "pending" } },
        { id = "in_progress", title = "In Progress", filter = { status = "in_progress" } },
        { id = "blocked",     title = "Blocked",     filter = { status = "blocked" } },
        { id = "done",        title = "Done",        filter = { status = "done" } },
      },
      colors = {
        column_header = { fg = "#7dcfff", bold = true, bg = "#1a1b26" },
        column_border = { fg = "#3b4261", bg = "#1a1b26" },
        card_border = { fg = "#565f89", bg = "#1a1b26" },
        card_title = { fg = "#c0caf5", bold = true },
        card = {
          urgent = { fg = "#f7768e", bold = true, bg = "#24283b" }, -- Red
          high = { fg = "#ff9e64", bold = true, bg = "#24283b" },   -- Orange
          medium = { fg = "#e0af68", bg = "#24283b" },              -- Yellow
          low = { fg = "#9ece6a", bg = "#24283b" },                 -- Green
        },
        status = {
          done = { fg = "#9ece6a", bold = true },        -- Green
          blocked = { fg = "#f7768e", bold = true },     -- Red
          in_progress = { fg = "#7aa2f7", bold = true }, -- Blue
          pending = { fg = "#bb9af7" },                  -- Purple
        },
        metadata = {
          due_date = { fg = "#bb9af7" },             -- Purple for dates
          tags = { fg = "#2ac3de", italic = true },  -- Cyan for tags
          progress = { fg = "#7aa2f7" },             -- Blue for progress
          notes = { fg = "#a9b1d6", italic = true }, -- Light gray for notes
        },
        ui = {
          pagination = { fg = "#bb9af7", italic = true },
          icon = { fg = "#2ac3de" },
          drag_active = { fg = "#c0caf5", bg = "#3d59a1", bold = true },
        },
      },
      layout = {
        min_column_width = 35,
        max_column_width = 50,
        default_column_width = 35,
        column_spacing = 1,
        card_margin = 1,
        card_padding = 1,
        title_padding = 1,
        card_rounding = 2,
        column_rounding = 2,
        show_task_count = true,
        max_tasks_per_column = 100,
        auto_adjust_columns = true,
        dynamic_column_width = true,
        show_column_borders = true,
        show_card_borders = true,
        show_progress_bars = true,
        show_due_dates = true,
        show_tags = true,
        show_notes_preview = true,
        notes_preview_length = 50,
      },
      pagination = {
        enabled = true,
        tasks_per_page = 10,
        navigation_icons = {
          prev = "◀",
          next = "▶",
          current = "•",
        },
      },
      icons = {
        kanban = {
          column = "󰓱",
          card = "󰆼",
          move_left = "←",
          move_right = "→",
        },
        priority = {
          urgent = "󱃍",
          high = "󰳛",
          medium = "󰳜",
          low = "󰳝",
        },
        status = {
          pending = "󰄱",
          in_progress = "󰁜",
          blocked = "󰅖",
          done = "󰄲",
        },
        metadata = {
          due_date = "󰥔",
          tags = "󰓹",
          progress = "󰝦",
          notes = "󰈙",
        },
      },
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
  state.collapsed_columns = {}
  state.filter = nil
  state.search_term = nil
  state.column_pages = {}
  state.column_pages_info = {}
  state.column_task_counts = {}
end

-- Setup highlight groups with enhanced visuals
local function setup_highlights()
  -- Apply colors from config
  local colors = Kanban.config.views.kanban.colors

  -- Column highlights with improved contrast
  api.nvim_set_hl(0, "LazyDoKanbanColumnHeader", colors.column_header)
  api.nvim_set_hl(0, "LazyDoKanbanColumnBorder", colors.column_border)
  api.nvim_set_hl(0, "LazyDoKanbanColumnBg", { bg = "#1a1b26" })
  api.nvim_set_hl(0, "LazyDoKanbanSeparator", { fg = "#3b4261", bg = "#1a1b26" })
  api.nvim_set_hl(0, "LazyDoKanbanWindow", { bg = "#16161e" })
  api.nvim_set_hl(0, "LazyDoKanbanTitle", { fg = "#c0caf5", bg = "#16161e" })

  -- Card highlights by priority with more vibrant colors
  api.nvim_set_hl(0, "LazyDoKanbanCardUrgent", colors.card.urgent)
  api.nvim_set_hl(0, "LazyDoKanbanCardHigh", colors.card.high)
  api.nvim_set_hl(0, "LazyDoKanbanCardMedium", colors.card.medium)
  api.nvim_set_hl(0, "LazyDoKanbanCardLow", colors.card.low)
  api.nvim_set_hl(0, "LazyDoKanbanCardHighlight", { bg = "#3b4261" })

  -- Status highlights with distinct colors
  api.nvim_set_hl(0, "LazyDoKanbanStatusDone", colors.status.done)
  api.nvim_set_hl(0, "LazyDoKanbanStatusBlocked", colors.status.blocked)
  api.nvim_set_hl(0, "LazyDoKanbanStatusInProgress", colors.status.in_progress)
  api.nvim_set_hl(0, "LazyDoKanbanStatusPending", colors.status.pending)

  -- Task metadata highlights
  api.nvim_set_hl(0, "LazyDoKanbanDueDate", colors.metadata.due_date)
  api.nvim_set_hl(0, "LazyDoKanbanTags", colors.metadata.tags)
  api.nvim_set_hl(0, "LazyDoKanbanProgress", colors.metadata.progress)
  api.nvim_set_hl(0, "LazyDoKanbanNotes", colors.metadata.notes)

  -- Additional UI elements
  api.nvim_set_hl(0, "LazyDoKanbanPagination", colors.ui.pagination)
  api.nvim_set_hl(0, "LazyDoKanbanIcon", colors.ui.icon)
end

-- Initialize the kanban board
function Kanban.setup(config)
  if config then
    -- Deep merge the configs
    Kanban.config = vim.tbl_deep_extend("force", Kanban.config, config)
  end

  -- Apply the configuration from config.lua
  if Kanban.config.views and Kanban.config.views.kanban then
    -- Update state with configured values
    local kanban_config = Kanban.config.views.kanban

    -- Set column width from config
    if kanban_config.layout and kanban_config.layout.default_column_width then
      state.column_width = kanban_config.layout.default_column_width
    end

    -- Set columns from config
    if kanban_config.columns then
      state.columns = vim.deepcopy(kanban_config.columns)
    end

    -- Initialize pagination for each column
    if kanban_config.pagination and kanban_config.pagination.enabled then
      for _, column in ipairs(state.columns) do
        state.column_pages[column.id] = 1
      end
    end
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
    title = " 󰓱 LazyDo Kanban Board ",
    title_pos = "center",
    zindex = 50, -- Ensure it appears on top
  }

  state.win = api.nvim_open_win(state.buf, true, win_opts)

  -- Set window options
  api.nvim_win_set_option(state.win, "wrap", false)
  api.nvim_win_set_option(state.win, "cursorline", true)
  api.nvim_win_set_option(state.win, "winhighlight",
    "Normal:LazyDoKanbanWindow,FloatBorder:LazyDoKanbanTitle,CursorLine:LazyDoKanbanCardHighlight")

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
  if is_valid_window() then
    Kanban.close()
    return
  end

  -- Initialize the state with the provided tasks
  state.tasks = tasks or {}
  state.on_task_update = callback

  -- Create a local copy of the icons to ensure they're not shared or overwritten
  local icons = vim.deepcopy(Kanban.config.views.kanban.icons or {})

  -- Ensure all icon categories are defined with defaults if needed
  icons.kanban = icons.kanban or {
    column = "󰓱",
    card = "󰆼",
    move_left = "",
    move_right = "",
  }

  icons.priority = icons.priority or {
    urgent = "󱃍",
    high = "󰳛",
    medium = "󰳜",
    low = "󰳝",
  }

  -- Set task status icons with defaults
  icons.task_pending = icons.task_pending or "󰄱"
  icons.task_done = icons.task_done or "󰄲"
  icons.task_in_progress = icons.task_in_progress or "󰁜"
  icons.task_blocked = icons.task_blocked or "󰅖"

  -- Save the local icons to state for use in rendering
  state.icons = icons

  -- Set state.columns based on config if not already set
  if not state.columns or #state.columns == 0 then
    state.columns = Kanban.config.views.kanban.columns
  end

  -- Create the window and render the board
  Kanban.create_window()
  Kanban.render()

  -- Setup keymaps
  Kanban.setup_keymaps()

  -- Set cursor position
  api.nvim_win_set_cursor(state.win, { 1, 0 })
end

-- Refresh the kanban board with new tasks
function Kanban.refresh(tasks)
  if not is_valid_window() then
    return
  end

  state.tasks = tasks or state.tasks
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

-- Enhanced column header rendering with flexible rectangular borders
local function render_column_header(column, width)
  local lines = {}
  local highlights = {}
  local config = Kanban.config.views.kanban
  local layout = config.layout
  local padding = layout.title_padding or 1
  local is_collapsed = state.collapsed_columns[column.id]
  local rounding = layout.column_rounding or 2

  -- Get count of visible tasks in this column
  local tasks = filter_tasks_for_column(state.tasks, column)
  local tasks_count = #tasks
  state.column_task_counts[column.id] = tasks_count

  -- Get pagination info if enabled
  local page_info = nil
  if config.pagination and config.pagination.enabled and tasks_count > 0 then
    local tasks_per_page = config.pagination.tasks_per_page or 10
    local total_pages = math.ceil(tasks_count / tasks_per_page)
    local current_page = state.column_pages[column.id] or 1

    page_info = {
      total = total_pages,
      current = current_page,
      tasks_per_page = tasks_per_page
    }

    -- Store pagination info for this column
    state.column_pages_info[column.id] = page_info
  end

  -- Define border characters based on rounding level
  local borders = {
    [0] = { "┌", "┐", "└", "┘", "─", "│", "├", "┤", "┬", "┴" }, -- Square
    [1] = { "╭", "╮", "╰", "╯", "─", "│", "├", "┤", "┬", "┴" }, -- Slightly rounded
    [2] = { "╭", "╮", "╰", "╯", "─", "│", "├", "┤", "┬", "┴" }, -- More rounded
  }
  local b = borders[rounding]

  -- Column icon
  local column_icon = config.icons.kanban.column or "󰓱"

  -- Collapse/expand icon
  local collapse_icon = is_collapsed and "▶" or "▼"

  -- Format header text with fixed padding
  local title = column.title or column.id:gsub("_", " "):gsub("^%l", string.upper)
  local count_text = layout.show_task_count and string.format(" (%d)", tasks_count) or ""
  local title_text = string.format("%s %s %s%s", column_icon, collapse_icon, title, count_text)

  -- Calculate available width for title (accounting for borders and padding)
  local available_width = width - 3 * padding - 2 -- 2 for borders

  -- Truncate title if needed
  if #title_text > available_width then
    title_text = string.sub(title_text, 1, available_width - 3) .. "..."
  end

  -- Center the title text
  local centered_title = Utils.Str.center(title_text, available_width)

  -- Create top border
  if layout.show_column_borders then
    local top_border = b[1] .. string.rep(b[5], width - 2) .. b[2]
    table.insert(lines, top_border)
  else
    table.insert(lines, string.rep(" ", width))
  end

  -- Create header line with centered content
  local header_line = b[6] .. string.rep(" ", padding) .. centered_title .. string.rep(" ", padding) .. b[6]
  table.insert(lines, header_line)

  -- Create separator line
  if layout.show_column_borders then
    local separator = b[6] .. string.rep(b[5], width - 2) .. b[6]
    table.insert(lines, separator)
  else
    table.insert(lines, string.rep(" ", width))
  end

  -- Add highlights
  if layout.show_column_borders then
    -- Top border highlight
    table.insert(highlights, {
      line = 0,
      col = 0,
      length = width,
      group = "LazyDoKanbanColumnBorder"
    })

    -- Separator highlight
    table.insert(highlights, {
      line = 2,
      col = 0,
      length = width,
      group = "LazyDoKanbanColumnBorder"
    })
  end

  -- Header background highlight
  table.insert(highlights, {
    line = 1,
    col = 0,
    length = width,
    group = "LazyDoKanbanColumnHeader"
  })

  -- Header text highlight
  table.insert(highlights, {
    line = 1,
    col = 1 + padding,
    length = #centered_title,
    group = "LazyDoKanbanColumnHeader"
  })

  -- Add virtual text for icons and status
  local icon_start = 1 + padding
  local icon_length = #column_icon + 1 + #collapse_icon + 1
  local title_start = icon_start + icon_length
  local title_length = #title
  local count_start = title_start + title_length
  local count_length = #count_text

  -- Add icon highlight
  vim.api.nvim_buf_set_virtual_text(
    state.buf,
    ns_id,
    1,
    {
      { column_icon,                 "LazyDoKanbanIcon" },
      { " " .. collapse_icon .. " ", "LazyDoKanbanIcon" },
      { title,                       "LazyDoKanbanColumnHeader" },
      { count_text,                  "LazyDoKanbanPagination" }
    },
    {}
  )

  return lines, highlights
end

-- Enhanced task card rendering with flexible rectangular borders
local function render_task_card(task, width)
  local lines = {}
  local highlights = {}
  local config = Kanban.config.views.kanban
  local layout = config.layout
  local card_margin = layout.card_margin or 1
  local card_padding = layout.card_padding or 1
  local rounding = layout.card_rounding or 2
  local card_width = width - 2 * card_margin

  -- Get task properties
  local priority = task.priority or "medium"
  local status = task.status or "pending"
  local priority_icon = config.icons.priority[priority] or "•"
  local status_icon = config.icons.status[status] or "□"

  -- Define border characters based on rounding level
  local borders = {
    [0] = { "┌", "┐", "└", "┘", "─", "│", "├", "┤", "┬", "┴" }, -- Square
    [1] = { "╭", "╮", "╰", "╯", "─", "│", "├", "┤", "┬", "┴" }, -- Slightly rounded
    [2] = { "╭", "╮", "╰", "╯", "─", "│", "├", "┤", "┬", "┴" }, -- More rounded
  }
  local b = borders[rounding]

  -- Add left margin
  local left_margin = string.rep(" ", card_margin)

  -- Add task top border
  if layout.show_card_borders then
    local top_border = b[1] .. string.rep(b[5], card_width - 2) .. b[2]
    table.insert(lines, left_margin .. top_border)
  else
    table.insert(lines, left_margin .. string.rep(" ", card_width))
  end

  -- Add title line with fixed width
  local title_prefix = status_icon .. " " .. priority_icon .. " "
  local title = Utils.Str.truncate(task.content, card_width - #title_prefix - 4) -- -4 for border chars and padding
  local title_line = string.format("%s%s %-" .. (card_width - 4) .. "s %s", b[6], title_prefix, title, b[6])
  table.insert(lines, left_margin .. title_line)

  -- Add metadata line with fixed width
  local metadata_line = string.format("%s %-" .. (card_width - 4) .. "s %s", b[6], "", b[6])
  if layout.show_due_dates and task.due_date then
    local date_str = Utils.Date.relative(task.due_date)
    local date_icon = config.icons.metadata.due_date or "󰥔"
    metadata_line = string.format("%s %s %-" .. (card_width - 8) .. "s %s", b[6], date_icon, date_str, b[6])
  end
  table.insert(lines, left_margin .. metadata_line)

  -- Add progress bar line with fixed width
  local progress_line = string.format("%s %-" .. (card_width - 4) .. "s %s", b[6], "", b[6])
  if layout.show_progress_bars and task.subtasks and #task.subtasks > 0 then
    local progress = Task.calculate_progress(task)
    local progress_icon = config.icons.metadata.progress or "󰝦"
    local bar_width = card_width - 12 -- Fixed width for progress bar
    local filled = math.floor(bar_width * progress / 100)
    local progress_bar = string.rep("█", filled) .. string.rep("░", bar_width - filled)
    progress_line = string.format("%s %s %3d%% %s %s", b[6], progress_icon, progress, progress_bar, b[6])
  end
  table.insert(lines, left_margin .. progress_line)

  -- Add tags line with fixed width
  local tags_line = string.format("%s %-" .. (card_width - 4) .. "s %s", b[6], "", b[6])
  if layout.show_tags and task.tags and #task.tags > 0 then
    local tags_icon = config.icons.metadata.tags or "󰓹"
    local tags_str = table.concat(task.tags, ", ")
    tags_str = Utils.Str.truncate(tags_str, card_width - 8)
    tags_line = string.format("%s %s %-" .. (card_width - 8) .. "s %s", b[6], tags_icon, tags_str, b[6])
  end
  table.insert(lines, left_margin .. tags_line)

  -- Add notes line with fixed width
  local notes_line = string.format("%s %-" .. (card_width - 4) .. "s %s", b[6], "", b[6])
  if layout.show_notes_preview and task.notes and #task.notes > 0 then
    local notes_icon = config.icons.metadata.notes or "󰈙"
    local notes_preview = Utils.Str.truncate(task.notes, card_width - 8)
    notes_line = string.format("%s %s %-" .. (card_width - 8) .. "s %s", b[6], notes_icon, notes_preview, b[6])
  end
  table.insert(lines, left_margin .. notes_line)

  -- Add task bottom border
  if layout.show_card_borders then
    local bottom_border = b[3] .. string.rep(b[5], card_width - 2) .. b[4]
    table.insert(lines, left_margin .. bottom_border)
  else
    table.insert(lines, left_margin .. string.rep(" ", card_width))
  end

  -- Add highlights with enhanced visuals
  local card_highlight = "LazyDoKanbanCard" .. priority:gsub("^%l", string.upper)

  -- Add default highlight for the entire card including borders
  for i = 1, #lines do
    table.insert(highlights, {
      line = i - 1,
      col = card_margin,
      length = card_width,
      group = card_highlight
    })
  end

  -- Add special highlights for specific elements
  local line_idx = 1

  -- Status and priority icons highlight
  table.insert(highlights, {
    line = line_idx,
    col = card_margin + 2,
    length = #status_icon,
    group = "LazyDoKanbanStatus" .. status:gsub("^%l", string.upper)
  })
  table.insert(highlights, {
    line = line_idx,
    col = card_margin + 4 + #status_icon,
    length = #priority_icon,
    group = "LazyDoKanbanIcon"
  })
  line_idx = line_idx + 1

  -- Due date highlight
  if layout.show_due_dates and task.due_date then
    table.insert(highlights, {
      line = line_idx,
      col = card_margin + 2,
      length = card_width - 4,
      group = "LazyDoKanbanDueDate"
    })
  end
  line_idx = line_idx + 1

  -- Progress bar highlight
  if layout.show_progress_bars and task.subtasks and #task.subtasks > 0 then
    table.insert(highlights, {
      line = line_idx,
      col = card_margin + 2,
      length = card_width - 4,
      group = "LazyDoKanbanProgress"
    })
  end
  line_idx = line_idx + 1

  -- Tags highlight
  if layout.show_tags and task.tags and #task.tags > 0 then
    table.insert(highlights, {
      line = line_idx,
      col = card_margin + 2,
      length = card_width - 4,
      group = "LazyDoKanbanTags"
    })
  end
  line_idx = line_idx + 1

  -- Notes preview highlight
  if layout.show_notes_preview and task.notes and #task.notes > 0 then
    table.insert(highlights, {
      line = line_idx,
      col = card_margin + 2,
      length = card_width - 4,
      group = "LazyDoKanbanNotes"
    })
  end

  return lines, highlights
end

-- Render a column with its tasks
local function render_column(column, pos_x)
  local lines = {}
  local highlights = {}
  local config = Kanban.config.views.kanban
  local layout = config.layout
  local width = state.column_width
  local tasks = filter_tasks_for_column(state.tasks, column)
  local card_margin = layout.card_margin or 1
  local card_padding = layout.card_padding or 1
  local title_padding = layout.title_padding or 1

  -- Store column position
  state.column_positions[column.id] = {
    start = pos_x,
    ["end"] = pos_x + width,
    collapsed = state.collapsed_columns[column.id]
  }

  -- Render header
  local header_lines, header_highlights = render_column_header(column, width)
  for _, line in ipairs(header_lines) do
    table.insert(lines, line)
  end
  for _, hl in ipairs(header_highlights) do
    table.insert(highlights, hl)
  end

  -- Render tasks if column is not collapsed
  if not state.collapsed_columns[column.id] then
    local current_line = #lines

    -- Add a separator after header
    if layout.show_column_borders then
      table.insert(lines, string.rep("─", width))
      table.insert(highlights, {
        line = current_line,
        col = 0,
        length = width,
        group = "LazyDoKanbanSeparator"
      })
      current_line = current_line + 1
    end

    -- Calculate available height for tasks
    local win_height = api.nvim_win_get_height(state.win)
    local header_height = #header_lines
    local status_line_height = 2 -- For the bottom status line
    local available_height = win_height - header_height - status_line_height

    -- Fixed height for each task card
    local task_height = 7 -- Fixed height for each task card (including borders)
    local tasks_per_page = math.floor(available_height / task_height)
    local current_page = state.column_pages[column.id] or 1
    local start_idx = (current_page - 1) * tasks_per_page + 1
    local end_idx = math.min(start_idx + tasks_per_page - 1, #tasks)

    -- Render visible tasks
    for i = start_idx, end_idx do
      local task = tasks[i]
      if task then
        local card_lines, card_highlights = render_task_card(task, width)

        -- Store card position
        state.card_positions[task.id] = {
          col = pos_x + card_margin,
          row = current_line + 1,
          width = width - 2 * card_margin,
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
          hl.line = hl.line + current_line - #card_lines
          table.insert(highlights, hl)
        end

        -- Add separator between cards if enabled
        if i < end_idx and layout.show_card_borders then
          table.insert(lines, string.rep("─", width))
          table.insert(highlights, {
            line = current_line,
            col = 0,
            length = width,
            group = "LazyDoKanbanSeparator"
          })
          current_line = current_line + 1
        end
      end
    end

    -- Add pagination if needed
    if #tasks > tasks_per_page then
      local total_pages = math.ceil(#tasks / tasks_per_page)
      local pagination_text = string.format(
        " %s %d/%d %s ",
        config.pagination.navigation_icons.prev,
        current_page,
        total_pages,
        config.pagination.navigation_icons.next
      )
      local pagination_line = string.rep(" ", math.floor((width - #pagination_text) / 2)) .. pagination_text
      table.insert(lines, pagination_line)
      table.insert(highlights, {
        line = #lines - 1,
        col = math.floor((width - #pagination_text) / 2),
        length = #pagination_text,
        group = "LazyDoKanbanPagination"
      })
    end

    -- Add padding at the bottom of the column
    table.insert(lines, string.rep(" ", width))
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

  -- Calculate layout with flexible columns
  local win_width = api.nvim_win_get_width(state.win)
  local win_height = api.nvim_win_get_height(state.win)
  local num_columns = #state.columns
  local config = Kanban.config.views.kanban
  local layout = config.layout

  -- Calculate column widths and spacing
  local min_width = layout.min_column_width or 30
  local max_width = layout.max_column_width or 50
  local default_width = layout.default_column_width or 35
  local column_spacing = layout.column_spacing or 1
  local card_margin = layout.card_margin or 1
  local card_padding = layout.card_padding or 1

  -- Calculate optimal column width based on window size
  local total_spacing = (num_columns - 1) * column_spacing
  local available_width = win_width - total_spacing

  -- Determine column width based on configuration
  local column_width
  if layout.dynamic_column_width then
    -- Calculate width based on available space
    column_width = math.floor(available_width / num_columns)
    -- Ensure width is within bounds
    column_width = math.min(math.max(column_width, min_width), max_width)
  else
    -- Use fixed width
    column_width = default_width
  end

  -- Adjust if total width exceeds window width
  local total_width = (column_width + column_spacing) * num_columns - column_spacing
  if total_width > win_width then
    if layout.auto_adjust_columns then
      -- Reduce column width proportionally
      column_width = math.floor((win_width - total_spacing) / num_columns)
      column_width = math.max(column_width, min_width)
    else
      -- Keep fixed width but enable horizontal scrolling
      api.nvim_win_set_option(state.win, "wrap", true)
    end
  end

  state.column_width = column_width

  -- Set state.columns based on config if not already set
  if not state.columns or #state.columns == 0 then
    state.columns = config.columns
  end

  -- Render columns
  local all_lines = {}
  local all_highlights = {}
  local max_height = 0

  -- First pass: render columns and get max height
  local column_contents = {}
  for i, column in ipairs(state.columns) do
    local pos_x = (i - 1) * (column_width + column_spacing)
    local lines, highlights = render_column(column, pos_x)
    column_contents[i] = { lines = lines, highlights = highlights }
    max_height = math.max(max_height, #lines)
  end

  -- Second pass: pad columns to equal height and combine
  for i, content in ipairs(column_contents) do
    local pos_x = (i - 1) * (column_width + column_spacing)
    local lines = content.lines
    local highlights = content.highlights

    -- Add a vertical divider between columns if enabled
    if i < #column_contents and layout.show_column_borders and column_spacing == 1 then
      for j = 1, #lines do
        if lines[j] then
          lines[j] = lines[j] .. "│"
        end
      end

      -- Add highlight for the divider
      for j = 1, #lines do
        table.insert(highlights, {
          line = j - 1,
          col = column_width,
          length = 1,
          group = "LazyDoKanbanSeparator"
        })
      end
    end

    -- Pad to max height
    while #lines < max_height do
      table.insert(lines, string.rep(" ", column_width) .. (i < #column_contents and column_spacing == 1 and "│" or ""))
    end

    -- Add lines to buffer
    for j, line in ipairs(lines) do
      -- For multi-column spacing, add appropriate spacing
      local spacing = ""
      if i < #column_contents and column_spacing > 1 then
        spacing = string.rep(" ", column_spacing)
      elseif i < #column_contents and column_spacing == 0 then
        spacing = ""
      else
        spacing = "" -- Add a single space after the last column
      end

      all_lines[j] = (all_lines[j] or "") .. line .. spacing
    end

    -- Adjust highlight positions
    for _, hl in ipairs(highlights) do
      hl.col = hl.col + pos_x
      table.insert(all_highlights, hl)
    end
  end

  -- Add a bottom status line
  local status_line = string.format(
    " %s Task Count: %d | %s Done: %d | %s Pending: %d | %s Overdue: %d | ? for help",
    config.icons.status.pending or "󰄱",
    #state.tasks,
    config.icons.status.done or "󰄲",
    #vim.tbl_filter(function(t) return t.status == "done" end, state.tasks),
    config.icons.kanban.card or "󰆼",
    #vim.tbl_filter(function(t) return t.status == "pending" end, state.tasks),
    config.icons.metadata.due_date or "󰥔",
    #vim.tbl_filter(function(t) return t.status ~= "done" and t.due_date and t.due_date < os.time() end, state.tasks)
  )
  table.insert(all_lines, string.rep("─", win_width))
  table.insert(all_lines, status_line)

  -- Add status line highlight
  table.insert(all_highlights, {
    line = #all_lines - 2,
    col = 0,
    length = win_width,
    group = "LazyDoKanbanSeparator"
  })
  table.insert(all_highlights, {
    line = #all_lines - 1,
    col = 0,
    length = #status_line,
    group = "LazyDoKanbanPagination"
  })

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
  map("n", "<CR>", function()
    Kanban.toggle_task()
  end, "Drop task/Toggle status")
  map("n", "a", function() Kanban.create_task() end, "Add new task")
  map("n", "e", function() Kanban.edit_task() end, "Edit task")
  map("n", "dd", function() Kanban.delete_task() end, "Delete task")

  -- Column movement and task management
  map("n", "<", function() Kanban.move_task("left") end, "Move task left")
  map("n", ">", function() Kanban.move_task("right") end, "Move task right")
  map("n", "H", function() Kanban.move_task("left") end, "Move task left")
  map("n", "L", function() Kanban.move_task("right") end, "Move task right")
  map("n", "[p", function() Kanban.cycle_priority("up") end, "Increase priority")
  map("n", "]p", function() Kanban.cycle_priority("down") end, "Decrease priority")
  map("n", "zc", function() Kanban.toggle_column_collapse() end, "Toggle column collapse")

  -- Set task status directly
  map("n", "tp", function() Kanban.set_task_status("pending") end, "Set status: pending")
  map("n", "ti", function() Kanban.set_task_status("in_progress") end, "Set status: in progress")
  map("n", "tb", function() Kanban.set_task_status("blocked") end, "Set status: blocked")
  map("n", "td", function() Kanban.set_task_status("done") end, "Set status: done")

  -- Task dates
  map("n", "du", function() Kanban.set_due_date() end, "Set due date")
  map("n", "dc", function() Kanban.clear_due_date() end, "Clear due date")

  -- Task details
  map("n", "n", function() Kanban.edit_notes() end, "Edit notes")

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
  local config = Kanban.config.views.kanban
  local column_spacing = config.layout.column_spacing or 1
  local start_x = current_pos.col
  local end_x

  if direction == "left" then
    end_x = start_x - state.column_width - column_spacing
  else
    end_x = start_x + state.column_width + column_spacing
  end

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
    { name = "All tasks",     filter = nil },
    { name = "High priority", filter = { priority = "high" } },
    { name = "Due today",     filter = { due_today = true } },
    { name = "Overdue",       filter = { overdue = true } },
    { name = "Has subtasks",  filter = { has_subtasks = true } },
    { name = "Has notes",     filter = { has_notes = true } },
    { name = "Clear filter",  filter = nil },
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
    "  h/l         - Move left/right",
    "  j/k         - Move up/down",
    "Task Management:",
    "  <CR>        - Toggle task status",
    "  a           - Add new task",
    "  e           - Edit task",
    "  dd          - Delete task",
    "  n           - Edit notes",
    "Status Management:",
    "  tp          - Set status: Pending",
    "  ti          - Set status: In Progress",
    "  tb          - Set status: Blocked",
    "  td          - Set status: Done",
    "Task Movement:",
    "  </H         - Move task to left column",
    "  >/L         - Move task to right column",
    "  [p/]p       - Increase/decrease priority",
    "Due Dates:",
    "  du          - Set due date",
    "  dc          - Clear due date",
    "Column Management:",
    "  zc          - Toggle column collapse",
    "Filtering and Sorting:",
    "  /           - Search tasks",
    "  f           - Filter tasks",
    "  s           - Sort tasks",
    "Pagination:",
    "  [           - Previous page",
    "  ]           - Next page",
    "Other:",
    "  ?           - Show this help",
    "  q           - Close board",
  }

  -- Create help window
  local buf = api.nvim_create_buf(false, true)
  api.nvim_buf_set_lines(buf, 0, -1, false, help_text)
  api.nvim_buf_set_option(buf, "modifiable", false)
  api.nvim_buf_set_option(buf, "buftype", "nofile")
  api.nvim_buf_set_option(buf, "filetype", "help")

  local width = 60
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
    zindex = 55 -- Higher than the kanban window
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
  local config = Kanban.config.views.kanban
  local card_margin = config.layout.card_margin or 1

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
        new_col = target_pos.col + card_margin + math.floor(target_pos.width / 2)
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
        new_col = target_pos.col + card_margin + math.floor(target_pos.width / 2)
      end
    end
  elseif direction == "down" then
    -- Find the nearest task card below
    local current_task = Kanban.get_task_under_cursor()
    if current_task then
      local current_pos = state.card_positions[current_task.id]
      local target_pos = nil
      for _, pos in pairs(state.card_positions) do
        if pos.column_id == current_pos.column_id and
            pos.row > current_pos.row and
            (not target_pos or pos.row < target_pos.row) then
          target_pos = pos
        end
      end
      if target_pos then
        new_row = target_pos.row + math.floor(target_pos.height / 2)
        new_col = target_pos.col + card_margin + math.floor(target_pos.width / 2)
      end
    else
      -- If not on a task, move to the nearest task below
      local target_pos = nil
      for _, pos in pairs(state.card_positions) do
        if pos.row > row and pos.col <= col and col <= pos.col + pos.width and
            (not target_pos or pos.row < target_pos.row) then
          target_pos = pos
        end
      end
      if target_pos then
        new_row = target_pos.row + math.floor(target_pos.height / 2)
        new_col = target_pos.col + card_margin + math.floor(target_pos.width / 2)
      end
    end
  end

  -- Update cursor position
  if new_row ~= row or new_col ~= col then
    api.nvim_win_set_cursor(state.win, { new_row, new_col })
  end
end

-- Set task status directly (new function)
function Kanban.set_task_status(status)
  local task = Kanban.get_task_under_cursor()
  if not task then return end

  if task.status ~= status then
    task.status = status
    task.updated_at = os.time()

    if state.on_task_update then
      state.on_task_update(task)
    end

    Kanban.render()

    vim.notify("Task status set to: " .. status, vim.log.levels.INFO)
  end
end

-- Set task due date (new function)
function Kanban.set_due_date()
  local task = Kanban.get_task_under_cursor()
  if not task then return end

  local current_date = task.due_date and Utils.Date.format(task.due_date) or ""

  vim.ui.input({
    prompt = "Set due date (YYYY-MM-DD or 'today', 'tomorrow', '3d', '1w'): ",
    default = current_date
  }, function(input)
    if not input then return end

    if input == "" then
      task.due_date = nil
      vim.notify("Due date cleared", vim.log.levels.INFO)
    else
      local timestamp = Utils.Date.parse(input)
      if timestamp then
        task.due_date = timestamp
        vim.notify("Due date set to: " .. Utils.Date.format(timestamp), vim.log.levels.INFO)
      else
        vim.notify("Invalid date format", vim.log.levels.ERROR)
        return
      end
    end

    task.updated_at = os.time()

    if state.on_task_update then
      state.on_task_update(task)
    end

    Kanban.render()
  end)
end

-- Clear task due date (new function)
function Kanban.clear_due_date()
  local task = Kanban.get_task_under_cursor()
  if not task then return end

  if task.due_date then
    task.due_date = nil
    task.updated_at = os.time()

    if state.on_task_update then
      state.on_task_update(task)
    end

    Kanban.render()
    vim.notify("Due date cleared", vim.log.levels.INFO)
  end
end

-- Edit task notes (new function)
function Kanban.edit_notes()
  local task = Kanban.get_task_under_cursor()
  if not task then return end

  Utils.multiline_input({
    prompt = "Task Notes:",
    default = task.notes or "",
    width = 60,
    height = 10,
    title = " Edit Notes "
  }, function(notes)
    if notes == nil then return end -- User cancelled

    task.notes = notes ~= "" and notes or nil
    task.updated_at = os.time()

    if state.on_task_update then
      state.on_task_update(task)
    end

    Kanban.render()
    vim.notify("Notes updated", vim.log.levels.INFO)
  end)
end

-- Cycle task priority (new function)
function Kanban.cycle_priority(direction)
  local task = Kanban.get_task_under_cursor()
  if not task then return end

  local priorities = { "low", "medium", "high", "urgent" }
  local current_index = 1

  for i, p in ipairs(priorities) do
    if p == task.priority then
      current_index = i
      break
    end
  end

  if direction == "up" then
    current_index = math.min(current_index + 1, #priorities)
  else
    current_index = math.max(current_index - 1, 1)
  end

  task.priority = priorities[current_index]
  task.updated_at = os.time()

  if state.on_task_update then
    state.on_task_update(task)
  end

  Kanban.render()
  vim.notify("Priority set to: " .. task.priority, vim.log.levels.INFO)
end

return Kanban
