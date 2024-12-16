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

local BOX_STYLES = {
  modern = {
    tl = "╭",
    tr = "╮",
    bl = "╰",
    br = "╯",
    h = "─",
    v = "│",
    ltee = "├",
    rtee = "┤",
    ttee = "┬",
    btee = "┴",
    cross = "┼"
  },
  double = {
    tl = "╔",
    tr = "╗",
    bl = "╚",
    br = "╝",
    h = "═",
    v = "║",
    ltee = "╠",
    rtee = "╣",
    ttee = "╦",
    btee = "╩",
    cross = "╬"
  },
  rounded = {
    tl = "╭",
    tr = "╮",
    bl = "╰",
    br = "╯",
    h = "─",
    v = "│",
    ltee = "├",
    rtee = "┤",
    ttee = "┬",
    btee = "┴",
    cross = "┼"
  },
  minimal = {
    tl = "┌",
    tr = "┐",
    bl = "└",
    br = "┘",
    h = "─",
    v = "│",
    ltee = "├",
    rtee = "┤",
    ttee = "┬",
    btee = "┴",
    cross = "┼"
  }
}

-- Enhanced default configuration with better icons and colors
local DEFAULT_CONFIG = {
  width = 0.8,
  height = 0.8,
  min_width = 60,
  min_height = 10,
  border = "rounded",
  indent = "    ",
  icons = {
    pending = "◆",
    done = "✓",
    priority = {
      HIGH = "🔴",
      MEDIUM = "🟡",
      LOW = "🟢",
      NONE = "⚪",
    },
    note = "📝",
    due = "📅",
    subtask = "└",
    tag = "🏷️",
    section = "◈",
    separator = "━",
    fold = {
      open = "▾",
      closed = "▸"
    }
  },
  colors = {
    -- Nord theme-inspired colors
    primary = "#88C0D0",
    secondary = "#81A1C1",
    success = "#A3BE8C",
    warning = "#EBCB8B",
    error = "#BF616A",
    info = "#B48EAD",
    background = "#2E3440",
    foreground = "#ECEFF4",
    muted = "#4C566A",
    border = "#434C5E",
    highlight = "#5E81AC",
    gradient = {
      start = "#88C0D0",
      middle = "#81A1C1",
      finish = "#5E81AC"
    },
  },
  box = {
    style = "modern", -- can be "modern", "double", "rounded", or "minimal"
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
  effects = {
    fade_inactive = true,
    highlight_current = true,
    smooth_scroll = true,
    animate_changes = true,
    shadow = true
  },
}

-- Setup highlights using highlight groups
local function setup_highlights()
  local highlights = {
    LazyDoDone = { fg = DEFAULT_CONFIG.colors.success },
    LazyDoPending = { fg = DEFAULT_CONFIG.colors.warning },
    LazyDoNote = { fg = DEFAULT_CONFIG.colors.info },
    LazyDoDue = { fg = DEFAULT_CONFIG.colors.primary },
    LazyDoOverdue = { fg = DEFAULT_CONFIG.colors.error },
    LazyDoHeader = { fg = DEFAULT_CONFIG.colors.highlight },
    LazyDoPriorityHigh = { fg = DEFAULT_CONFIG.colors.error },
    LazyDoPriorityMedium = { fg = DEFAULT_CONFIG.colors.warning },
    LazyDoPriorityLow = { fg = DEFAULT_CONFIG.colors.success },
    LazyDoPriorityNone = { fg = DEFAULT_CONFIG.colors.muted },
    LazyDoSelected = { bg = DEFAULT_CONFIG.colors.background, fg = DEFAULT_CONFIG.colors.foreground },
    LazyDoBoxBorder = { fg = DEFAULT_CONFIG.colors.border },
    LazyDoBoxShadow = { fg = DEFAULT_CONFIG.colors.muted },
    LazyDoBoxTitle = { fg = DEFAULT_CONFIG.colors.primary },
    LazyDoBoxSelectedBorder = { fg = DEFAULT_CONFIG.colors.highlight },
    LazyDoSubtaskDone = { fg = DEFAULT_CONFIG.colors.success },
    LazyDoSubtaskPending = { fg = DEFAULT_CONFIG.colors.warning },
    LazyDoSubtaskIndent = { fg = DEFAULT_CONFIG.colors.muted },
    LazyDoTag = { fg = DEFAULT_CONFIG.colors.info },
    LazyDoFooter = { fg = DEFAULT_CONFIG.colors.muted },
    LazyDoDueDate = { fg = DEFAULT_CONFIG.colors.primary },         -- Highlight for due dates
    LazyDoTaskTitle = { fg = DEFAULT_CONFIG.colors.foreground },    -- Highlight for task titles
    LazyDoSubtaskTitle = { fg = DEFAULT_CONFIG.colors.foreground }, -- Highlight for subtask titles
    LazyDoSeparator = { fg = DEFAULT_CONFIG.colors.muted },         -- Highlight for separator lines
    LazyDoGradient = { fg = DEFAULT_CONFIG.colors.gradient.start, bg = DEFAULT_CONFIG.colors.gradient.finish },
    LazyDoStats = { fg = DEFAULT_CONFIG.colors.foreground },
    LazyDoGlow = { fg = DEFAULT_CONFIG.colors.highlight },
    LazyDoTooltip = { fg = DEFAULT_CONFIG.colors.foreground, bg = DEFAULT_CONFIG.colors.background },
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
  local padding = string.rep(" ", self.config.box.padding)
  local box_style = BOX_STYLES[self.config.box.style]

  -- Box top
  local top = string.format("%s%s%s",
    box_style.tl,
    string.rep(box_style.h, width - 2),
    box_style.tr
  )
  table.insert(box, top)
  table.insert(highlights, { border_color, #box - 1, 0, -1 })

  -- Task header with status, priority, and title
  local status_icon = task.status == "DONE" and self.config.icons.done or self.config.icons.pending
  local priority_icon = self.config.icons.priority[task.priority or "NONE"]
  local header = string.format("%s%s %s %s %s",
    box_style.v,
    padding,
    status_icon,
    priority_icon,
    task.title
  )

  -- Add dynamic highlights for status and priority
  local status_color = task.status == "DONE" and "LazyDoDone" or "LazyDoPending"
  local priority_color = "LazyDoPriority" .. (task.priority or "NONE")

  table.insert(box, header .. string.rep(" ", width - #header - 1) .. box_style.v)
  table.insert(highlights, { status_color, #box - 1, #box_style.v + #padding + 1, #box_style.v + #padding + 2 })
  table.insert(highlights, { priority_color, #box - 1, #box_style.v + #padding + 3, #box_style.v + #padding + 4 })
  table.insert(highlights, { "LazyDoTaskTitle", #box - 1, #box_style.v + #padding + 5, -2 })

  -- Due date section with dynamic highlighting
  if task.due_date then
    local due_str = string.format("%s%s %s %s",
      box_style.v,
      padding,
      self.config.icons.due,
      task.due_date
    )
    table.insert(box, due_str .. string.rep(" ", width - #due_str - 1) .. box_style.v)

    local due_color = self:get_due_date_color(task)
    table.insert(highlights, { due_color, #box - 1, #box_style.v + #padding, -2 })
  end

  -- Add remaining sections only if not folded
  if not task.folded then
    -- Notes section
    if task.notes and task.notes ~= "" then
      for _, line in ipairs(vim.split(task.notes, "\n")) do
        local note_line = string.format("%s%s%s %s",
          box_style.v,
          padding,
          self.config.icons.note,
          line
        )
        table.insert(box, note_line .. string.rep(" ", width - #note_line - 1) .. box_style.v)
        table.insert(highlights, { "LazyDoNote", #box - 1, #box_style.v + #padding, -2 })
      end
    end

    -- Subtasks section
    if task.subtasks and #task.subtasks > 0 then
      for _, subtask in ipairs(task.subtasks) do
        local subtask_status = subtask.status == "DONE" and self.config.icons.done or self.config.icons.pending
        local subtask_line = string.format("%s%s%s %s %s",
          box_style.v,
          padding,
          self.config.icons.subtask,
          subtask_status,
          subtask.title
        )
        table.insert(box, subtask_line .. string.rep(" ", width - #subtask_line - 1) .. box_style.v)

        local subtask_color = subtask.status == "DONE" and "LazyDoSubtaskDone" or "LazyDoSubtaskPending"
        table.insert(highlights,
          { subtask_color, #box - 1, #box_style.v + #padding + #self.config.icons.subtask + 1, #box_style.v + #padding +
          #self.config.icons.subtask + 2 })
        table.insert(highlights,
          { "LazyDoSubtaskTitle", #box - 1, #box_style.v + #padding + #self.config.icons.subtask + 3, -2 })
      end
    end

    -- Tags section
    if task.tags and #task.tags > 0 then
      local tags_line = string.format("%s%s%s %s",
        box_style.v,
        padding,
        self.config.icons.tag,
        table.concat(task.tags, ", ")
      )
      table.insert(box, tags_line .. string.rep(" ", width - #tags_line - 1) .. box_style.v)
      table.insert(highlights, { "LazyDoTag", #box - 1, #box_style.v + #padding, -2 })
    end
  end

  -- Box bottom
  local bottom = string.format("%s%s%s",
    box_style.bl,
    string.rep(box_style.h, width - 2),
    box_style.br
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
  local header = self:create_fancy_header(task_width)
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

function LazyDo:animate_change(old_lines, new_lines, callback)
  if not self.config.effects.animate_changes then
    callback()
    return
  end

  local frames = 5
  local delay = 20 -- milliseconds

  for i = 1, frames do
    vim.defer_fn(function()
      if not api.nvim_buf_is_valid(self.buf) then return end

      local alpha = i / frames
      local current_lines = {}

      for j = 1, math.max(#old_lines, #new_lines) do
        if i == frames then
          current_lines[j] = new_lines[j] or ""
        else
          local old = old_lines[j] or ""
          local new = new_lines[j] or ""
          current_lines[j] = self:blend_lines(old, new, alpha)
        end
      end

      api.nvim_buf_set_option(self.buf, "modifiable", true)
      api.nvim_buf_set_lines(self.buf, 0, -1, false, current_lines)
      api.nvim_buf_set_option(self.buf, "modifiable", false)

      if i == frames then
        callback()
      end
    end, delay * i)
  end
end

function LazyDo:blend_lines(old_line, new_line, alpha)
  -- Simple crossfade effect
  if alpha >= 1 then return new_line end
  if alpha <= 0 then return old_line end

  local len = math.max(#old_line, #new_line)
  local result = {}

  for i = 1, len do
    local old_char = old_line:sub(i, i)
    local new_char = new_line:sub(i, i)
    result[i] = math.random() < alpha and new_char or old_char
  end

  return table.concat(result)
end

function LazyDo:add_box_effects(box, is_selected)
  if not self.config.effects.shadow then return box end

  local shadow_lines = {}
  local width = #box[1]

  for i, line in ipairs(box) do
    if i == #box then
      -- Bottom shadow
      table.insert(shadow_lines, string.rep(" ", 2) .. string.rep("▁", width))
    end
    -- Right shadow
    shadow_lines[i] = line .. "▊"
  end

  if is_selected and self.config.effects.highlight_current then
    -- Add glow effect for selected box
    for i, line in ipairs(shadow_lines) do
      local highlight = string.rep("•", width + 1)
      table.insert(self.highlights, {
        "LazyDoGlow", #self.lines + i - 1, 0, #highlight
      })
    end
  end

  return shadow_lines
end

function LazyDo:create_progress_bar(task)
  local width = 20
  local progress = 0

  if task.subtasks and #task.subtasks > 0 then
    local done = #vim.tbl_filter(function(st) return st.status == "DONE" end, task.subtasks)
    progress = done / #task.subtasks
  end

  local filled = math.floor(progress * width)
  local empty = width - filled

  return string.format(
    "█%s%s█ %d%%",
    string.rep("■", filled),
    string.rep("□", empty),
    progress * 100
  )
end

function LazyDo:create_status_badge(task)
  local badges = {
    DONE = "✓ DONE",
    PENDING = "◌ PENDING",
    OVERDUE = "! OVERDUE"
  }

  local status = task.status
  if status == "PENDING" and task.due_date and task.due_date < os.date("%Y-%m-%d") then
    status = "OVERDUE"
  end

  return badges[status] or badges.PENDING
end

function LazyDo:show_tooltip(text, row, col)
  if not self.tooltip_ns then
    self.tooltip_ns = api.nvim_create_namespace('lazydo_tooltip')
  end

  -- Clear existing tooltips
  api.nvim_buf_clear_namespace(self.buf, self.tooltip_ns, 0, -1)

  -- Create virtual text
  api.nvim_buf_set_extmark(self.buf, self.tooltip_ns, row, col, {
    virt_text = { { text, "LazyDoTooltip" } },
    virt_text_pos = "overlay",
    priority = 100,
  })

  -- Clear tooltip after delay
  vim.defer_fn(function()
    if api.nvim_buf_is_valid(self.buf) then
      api.nvim_buf_clear_namespace(self.buf, self.tooltip_ns, 0, -1)
    end
  end, 2000)
end

local function safe_file_operation(operation, ...)
  local ok, result = pcall(operation, ...)
  if not ok then
    vim.notify(
      string.format("LazyDo: File operation failed - %s", result),
      vim.log.levels.ERROR
    )
    return nil
  end
  return result
end

local function validate_config(config)
  local schema = {
    width = "number",
    height = "number",
    min_width = "number",
    min_height = "number",
    border = "string",
    indent = "string",
    icons = "table",
    colors = "table",
    box = "table",
    fold = "table",
    ui = "table",
    effects = "table",
  }

  for key, expected_type in pairs(schema) do
    if type(config[key]) ~= expected_type then
      error(string.format(
        "LazyDo: Invalid configuration - expected %s for %s, got %s",
        expected_type,
        key,
        type(config[key])
      ))
    end
  end
end

function LazyDo:cleanup()
  if self.buf and vim.api.nvim_buf_is_valid(self.buf) then
    vim.api.nvim_buf_delete(self.buf, { force = true })
  end
  if self.tooltip_ns then
    vim.api.nvim_buf_clear_namespace(0, self.tooltip_ns, 0, -1)
  end
end

vim.api.nvim_create_autocmd("VimLeavePre", {
  callback = function()
    if LazyDo.instance then
      LazyDo.instance:cleanup()
    end
  end,
})

function LazyDo:ensure_valid_window()
  if not self.win or not vim.api.nvim_win_is_valid(self.win) then
    self:create_window()
    return false
  end
  return true
end

-- Use this before window operations
function LazyDo:some_window_operation()
  if not self:ensure_valid_window() then
    return
  end
  -- Proceed with operation
end


function LazyDo.setup(opts)
  if not opts then
    opts = {}
  end
  
  -- Create new instance with error handling
  local ok, instance = pcall(LazyDo.new, opts)
  if not ok then
    vim.notify("Failed to create LazyDo instance: " .. tostring(instance), vim.log.levels.ERROR)
    return
  end
  
  LazyDo.instance = instance
end

function LazyDo.open()
  if not LazyDo.instance then
    vim.notify("LazyDo not initialized. Call setup() first.", vim.log.levels.ERROR)
    return
  end
  
  LazyDo.instance:create_window()
end

function LazyDo:setup_keymaps()
  local function map(mode, key, action)
    vim.keymap.set(mode, key, action, {
      buffer = self.buf,
      silent = true,
      nowait = true,
    })
  end

  -- Basic navigation
  map('n', 'j', function() self:navigate('down') end)
  map('n', 'k', function() self:navigate('up') end)
  map('n', '<CR>', function() self:toggle_task() end)
  
  -- Task management
  map('n', 'a', function() self:add_task() end)
  map('n', 'd', function() self:delete_task() end)
  map('n', 'e', function() self:edit_task() end)
  map('n', '<space>', function() self:toggle_task() end)
  
  -- Folding
  map('n', 'za', function() self:toggle_fold() end)
  map('n', 'zo', function() self:open_fold() end)
  map('n', 'zc', function() self:close_fold() end)
  
  -- Window control
  map('n', 'q', function() 
    if self.win and vim.api.nvim_win_is_valid(self.win) then
      vim.api.nvim_win_close(self.win, true)
    end
  end)
  map('n', '<Esc>', function()
    if self.win and vim.api.nvim_win_is_valid(self.win) then
      vim.api.nvim_win_close(self.win, true)
    end
  end)

  -- Save
  map('n', 's', function() self:save_tasks() end)
end

function LazyDo:navigate(direction)
  if #self.tasks == 0 then return end
  
  local current = self.selected_task_index or 1
  if direction == 'down' then
    current = math.min(current + 1, #self.tasks)
  else
    current = math.max(current - 1, 1)
  end
  
  self.selected_task_index = current
  self:render()
end

function LazyDo:toggle_fold()
  local task_info = self:get_task_at_cursor()
  if task_info then
    task_info.task.folded = not task_info.task.folded
    self:render()
  end
end

function LazyDo:open_fold()
  local task_info = self:get_task_at_cursor()
  if task_info then
    task_info.task.folded = false
    self:render()
  end
end

function LazyDo:close_fold()
  local task_info = self:get_task_at_cursor()
  if task_info then
    task_info.task.folded = true
    self:render()
  end
end

-- Return the module
return LazyDo
