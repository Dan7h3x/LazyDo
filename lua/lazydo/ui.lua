local M = {}
local utils = require('lazydo.utils')

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
    buftype = 'nofile',
    bufhidden = 'hide',
    swapfile = false,
    filetype = 'lazydo'
  }
  
  for opt, val in pairs(buf_opts) do
    vim.api.nvim_buf_set_option(buf, opt, val)
  end

  -- Setup buffer-specific keymaps
  M.setup_buffer_keymaps(lazydo, buf)
  
  return buf
end

function M.create_window(lazydo)
  local width = math.max(M.CONSTANTS.MIN_WIDTH,
    math.floor(vim.o.columns * 0.8))
  local height = math.floor(vim.o.lines * 0.8)
  local row = math.floor((vim.o.lines - height) / 2)
  local col = math.floor((vim.o.columns - width) / 2)

  local win_opts = {
    relative = 'editor',
    width = width,
    height = height,
    row = row,
    col = col,
    style = 'minimal',
    border = 'rounded',
    title = ' LazyDo ',
    title_pos = 'center'
  }

  local win = vim.api.nvim_open_win(lazydo.buf, true, win_opts)
  
  -- Set window options
  local win_opts = {
    wrap = false,
    cursorline = true,
    number = false,
    relativenumber = false,
    signcolumn = "no"
  }

  for opt, val in pairs(win_opts) do
    vim.api.nvim_win_set_option(win, opt, val)
  end

  return win
end

-- Add render functions
function M.render_task_block(task, width, indent, icons)
  local lines = {}
  local highlights = {}
  local block_start = #lines + 1
  
  -- Status and priority indicators
  local status = task.done and icons.task_done or
      (task.due_date and task.due_date < os.time()) and icons.task_overdue or
      icons.task_pending

  local priority = string.rep("!", task.priority)
  
  -- Block borders
  local block_width = width - #indent
  local top = indent .. M.CONSTANTS.BLOCK.TOP_LEFT ..
      string.rep(M.CONSTANTS.BLOCK.HORIZONTAL, block_width - 2) ..
      M.CONSTANTS.BLOCK.TOP_RIGHT

  -- Task header
  local header = indent .. M.CONSTANTS.BLOCK.VERTICAL ..
      utils.pad_right(string.format(" %s %s %s",
        status, priority, task.content), block_width - 2) ..
      M.CONSTANTS.BLOCK.VERTICAL

  table.insert(lines, top)
  table.insert(lines, header)

  -- Due date
  if task.due_date then
    local date_str = os.date("Due: %Y-%m-%d", task.due_date)
    local date_line = indent .. M.CONSTANTS.BLOCK.VERTICAL ..
        utils.pad_right("  " .. icons.due_date .. " " .. date_str,
        block_width - 2) .. M.CONSTANTS.BLOCK.VERTICAL
    table.insert(lines, date_line)
  end

  -- Notes
  if task.notes then
    local wrapped_notes = utils.word_wrap(task.notes, block_width - 6)
    for _, note_line in ipairs(wrapped_notes) do
      local note = indent .. M.CONSTANTS.BLOCK.VERTICAL ..
          utils.pad_right("  " .. icons.note .. " " .. note_line,
          block_width - 2) .. M.CONSTANTS.BLOCK.VERTICAL
      table.insert(lines, note)
    end
  end

  -- Subtasks
  if #task.subtasks > 0 then
    table.insert(lines, indent .. M.CONSTANTS.BLOCK.VERTICAL ..
        utils.pad_right("  Subtasks:", block_width - 2) ..
        M.CONSTANTS.BLOCK.VERTICAL)
    
    for i, subtask in ipairs(task.subtasks) do
      local is_last = i == #task.subtasks
      local prefix = is_last and M.CONSTANTS.BLOCK.SUBTASK_LAST or
          M.CONSTANTS.BLOCK.SUBTASK_BRANCH
      local subtask_status = subtask.done and icons.task_done or
          icons.task_pending
      
      local subtask_line = indent .. M.CONSTANTS.BLOCK.VERTICAL ..
          utils.pad_right("  " .. prefix .. " " .. subtask_status ..
          " " .. subtask.content, block_width - 2) ..
          M.CONSTANTS.BLOCK.VERTICAL
      table.insert(lines, subtask_line)
    end
  end

  -- Block footer
  local bottom = indent .. M.CONSTANTS.BLOCK.BOTTOM_LEFT ..
      string.rep(M.CONSTANTS.BLOCK.HORIZONTAL, block_width - 2) ..
      M.CONSTANTS.BLOCK.BOTTOM_RIGHT
  table.insert(lines, bottom)
  table.insert(lines, "") -- Spacing

  return lines, highlights, block_start
end

function M.setup_buffer_keymaps(lazydo, buf)
  local function safe_map(key, fn, desc)
    vim.keymap.set('n', key, function()
      if vim.api.nvim_get_current_buf() == buf then
        if lazydo.is_ui_busy then return end
        local ok, err = pcall(fn)
        if not ok then
          vim.notify("LazyDo action failed: " .. err, vim.log.levels.ERROR)
        end
      end
    end, {
      buffer = buf,
      silent = true,
      nowait = true,
      desc = desc
    })
  end

  -- Core task management
  safe_map(lazydo.opts.keymaps.toggle_done, function() lazydo:toggle_task() end, "Toggle task")
  safe_map(lazydo.opts.keymaps.edit_task, function() lazydo:edit_task() end, "Edit task")
  safe_map(lazydo.opts.keymaps.delete_task, function() lazydo:delete_task() end, "Delete task")
  safe_map(lazydo.opts.keymaps.add_task, function() lazydo:add_task() end, "Add task")
  safe_map(lazydo.opts.keymaps.add_subtask, function() lazydo:add_subtask() end, "Add subtask")

  -- Task organization
  safe_map(lazydo.opts.keymaps.move_up, function() lazydo:move_task_up() end, "Move up")
  safe_map(lazydo.opts.keymaps.move_down, function() lazydo:move_task_down() end, "Move down")
  safe_map(lazydo.opts.keymaps.increase_priority, function() lazydo:change_priority(1) end, "Increase priority")
  safe_map(lazydo.opts.keymaps.decrease_priority, function() lazydo:change_priority(-1) end, "Decrease priority")

  -- Task properties
  safe_map(lazydo.opts.keymaps.quick_note, function() lazydo:quick_note() end, "Quick note")
  safe_map(lazydo.opts.keymaps.quick_date, function() lazydo:quick_date() end, "Set due date")

  -- Navigation and view
  safe_map(lazydo.opts.keymaps.toggle_expand, function() lazydo:toggle_expand() end, "Toggle expand")
  safe_map(lazydo.opts.keymaps.search_tasks, function() lazydo:search_tasks() end, "Search tasks")
  safe_map('?', function() lazydo:show_help() end, "Show help")
  safe_map('q', function() lazydo:close_window() end, "Close LazyDo")

  -- Add quick edit menu
  safe_map('<CR>', function()
    M.show_quick_edit_menu(lazydo)
  end, "Quick edit menu")
end

function M.setup_highlights(lazydo)
  local highlights = {
    LazyDoHeader = { fg = lazydo.opts.colors.header, bold = true },
    LazyDoPending = { fg = lazydo.opts.colors.pending },
    LazyDoDone = { fg = lazydo.opts.colors.done },
    LazyDoOverdue = { fg = lazydo.opts.colors.overdue },
    LazyDoNote = { fg = lazydo.opts.colors.note },
    LazyDoDueDate = { fg = lazydo.opts.colors.due_date },
    LazyDoPriorityHigh = { fg = lazydo.opts.colors.priority.high },
    LazyDoPriorityMedium = { fg = lazydo.opts.colors.priority.medium },
    LazyDoPriorityLow = { fg = lazydo.opts.colors.priority.low },
    LazyDoBorder = { fg = lazydo.opts.colors.border },
    LazyDoSubtask = { fg = lazydo.opts.colors.subtask },
  }

  for name, attrs in pairs(highlights) do
    vim.api.nvim_set_hl(0, name, attrs)
  end
end

function M.show_help(lazydo)
  if lazydo.help_win and vim.api.nvim_win_is_valid(lazydo.help_win) then
    vim.api.nvim_win_close(lazydo.help_win, true)
    lazydo.help_win = nil
    return
  end

  local help_lines = {
    "LazyDo Keybindings",
    "═════════════════",
    "",
    "Task Management:",
    string.format("  %s - Toggle task completion", lazydo.opts.keymaps.toggle_done),
    string.format("  %s - Edit task", lazydo.opts.keymaps.edit_task),
    string.format("  %s - Add new task", lazydo.opts.keymaps.add_task),
    string.format("  %s - Delete task", lazydo.opts.keymaps.delete_task),
    string.format("  %s - Add subtask", lazydo.opts.keymaps.add_subtask),
    "",
    "Organization:",
    string.format("  %s - Move task up", lazydo.opts.keymaps.move_up),
    string.format("  %s - Move task down", lazydo.opts.keymaps.move_down),
    string.format("  %s - Toggle expand/collapse", lazydo.opts.keymaps.toggle_expand),
    "",
    "Properties:",
    string.format("  %s - Increase priority", lazydo.opts.keymaps.increase_priority),
    string.format("  %s - Decrease priority", lazydo.opts.keymaps.decrease_priority),
    string.format("  %s - Add/edit note", lazydo.opts.keymaps.quick_note),
    string.format("  %s - Set due date", lazydo.opts.keymaps.quick_date),
    "",
    "Navigation & Search:",
    string.format("  %s - Search tasks", lazydo.opts.keymaps.search_tasks),
    string.format("  %s - Sort by date", lazydo.opts.keymaps.sort_by_date),
    string.format("  %s - Sort by priority", lazydo.opts.keymaps.sort_by_priority),
    "",
    "Other:",
    "  <CR> - Quick actions menu",
    "  ?    - Toggle this help window",
    "  q    - Close window",
  }

  -- Create help buffer
  if not lazydo.help_buf or not vim.api.nvim_buf_is_valid(lazydo.help_buf) then
    lazydo.help_buf = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_buf_set_lines(lazydo.help_buf, 0, -1, false, help_lines)
    
    local help_opts = {
      modifiable = false,
      modified = false,
      readonly = true,
      buftype = 'nofile',
      bufhidden = 'wipe',
      swapfile = false,
      filetype = 'lazydo-help'
    }
    
    for opt, val in pairs(help_opts) do
      vim.api.nvim_buf_set_option(lazydo.help_buf, opt, val)
    end
  end

  -- Calculate window dimensions
  local width = 60
  local height = #help_lines
  local row = math.floor((vim.o.lines - height) / 2)
  local col = math.floor((vim.o.columns - width) / 2)

  -- Create help window
  local win_opts = {
    relative = 'editor',
    width = width,
    height = height,
    row = row,
    col = col,
    style = 'minimal',
    border = 'rounded',
    title = ' LazyDo Help ',
    title_pos = 'center',
  }

  lazydo.help_win = vim.api.nvim_open_win(lazydo.help_buf, false, win_opts)

  -- Set help window options
  local win_options = {
    wrap = false,
    cursorline = true,
    winblend = 10,
    number = false,
    relativenumber = false,
    signcolumn = "no"
  }

  for opt, val in pairs(win_options) do
    vim.api.nvim_win_set_option(lazydo.help_win, opt, val)
  end

  -- Set help window keymaps
  local function set_help_keymap(key, action)
    vim.keymap.set('n', key, action, { buffer = lazydo.help_buf, silent = true, nowait = true })
  end

  set_help_keymap('q', function() 
    if lazydo.help_win and vim.api.nvim_win_is_valid(lazydo.help_win) then
      vim.api.nvim_win_close(lazydo.help_win, true)
      lazydo.help_win = nil
    end
  end)
  
  set_help_keymap('<Esc>', function() 
    if lazydo.help_win and vim.api.nvim_win_is_valid(lazydo.help_win) then
      vim.api.nvim_win_close(lazydo.help_win, true)
      lazydo.help_win = nil
    end
  end)
end

-- Add highlight groups for task components
function M.setup_task_highlights(lazydo)
  local ns = vim.api.nvim_create_namespace('lazydo_task_highlights')
  
  -- Clear existing highlights
  vim.api.nvim_buf_clear_namespace(lazydo.buf, ns, 0, -1)
  
  local function add_highlight(line, col_start, col_end, hl_group)
    vim.api.nvim_buf_add_highlight(lazydo.buf, ns, hl_group, line, col_start, col_end)
  end

  -- Get current task block bounds
  local current_task = lazydo:get_current_task()
  local cursor_line = vim.api.nvim_win_get_cursor(lazydo.win)[1] - 1

  -- Iterate through lines and add highlights
  local lines = vim.api.nvim_buf_get_lines(lazydo.buf, 0, -1, false)
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
      add_highlight(line_idx, block_indent, block_indent + 1, "LazyDoBorder")
      add_highlight(line_idx, #line - 1, #line, "LazyDoBorder")

      -- Highlight task status icon
      local status_match = content:match("([󰄱󰄵󰄮])")
      if status_match then
        local icon_start = line:find(status_match, 1, true)
        if icon_start then
          local hl_group = "LazyDoPending"
          if status_match == lazydo.opts.icons.task_done then
            hl_group = "LazyDoDone"
          elseif status_match == lazydo.opts.icons.task_overdue then
            hl_group = "LazyDoOverdue"
          end
          add_highlight(line_idx, icon_start - 1, icon_start + #status_match - 1, hl_group)
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
        add_highlight(line_idx, priority_start - 1, priority_start + priority_count - 1, hl_group)
      end

      -- Highlight due date
      local date_icon = lazydo.opts.icons.due_date
      local date_start = line:find(date_icon, 1, true)
      if date_start then
        add_highlight(line_idx, date_start - 1, date_start + #date_icon - 1, "LazyDoDueDate")
        local date_text_start = date_start + #date_icon + 1
        add_highlight(line_idx, date_text_start - 1, #line - 1, "LazyDoDueDate")
      end

      -- Highlight notes
      local note_icon = lazydo.opts.icons.note
      local note_start = line:find(note_icon, 1, true)
      if note_start then
        add_highlight(line_idx, note_start - 1, note_start + #note_icon - 1, "LazyDoNote")
        local note_text_start = note_start + #note_icon + 1
        add_highlight(line_idx, note_text_start - 1, #line - 1, "LazyDoNote")
      end

      -- Highlight subtasks
      if line:match("Subtasks:") then
        add_highlight(line_idx, block_indent + 2, #line - 1, "LazyDoSubtask")
      elseif line:match(M.CONSTANTS.BLOCK.SUBTASK_BRANCH) or line:match(M.CONSTANTS.BLOCK.SUBTASK_LAST) then
        add_highlight(line_idx, block_indent + 2, #line - 1, "LazyDoSubtask")
      end

      -- Highlight current task block
      if current_task and line_idx >= task_start_line and cursor_line >= task_start_line then
        add_highlight(line_idx, 0, #line, "Visual")
      end
    end
  end
end

-- Add interactive editing functions
function M.edit_task_component(lazydo, component)
  local task = lazydo:get_current_task()
  if not task then return end

  local function callback(input)
    if input and input ~= "" then
      if component == "content" then
        task.content = input
      elseif component == "note" then
        task:set_note(input)
      elseif component == "due_date" then
        local timestamp = utils.parse_date(input)
        if timestamp then
          task:set_due_date(timestamp)
        else
          vim.notify("Invalid date format", vim.log.levels.ERROR)
          return
        end
      elseif component == "priority" then
        local priority = tonumber(input)
        if priority and priority >= 1 and priority <= 3 then
          task.priority = priority
        else
          vim.notify("Priority must be between 1 and 3", vim.log.levels.ERROR)
          return
        end
      end
      
      if lazydo.opts.storage.auto_save then
        lazydo:save_tasks()
      end
      lazydo:refresh_display()
    end
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

  local prompt = string.format("Edit %s: ", component)
  vim.ui.input({
    prompt = prompt,
    default = current_value,
  }, callback)
end

-- Add quick edit menu
function M.show_quick_edit_menu(lazydo)
  local task = lazydo:get_current_task()
  if not task then return end

  local items = {
    { text = "Edit Content", value = "content" },
    { text = "Edit Note", value = "note" },
    { text = "Set Due Date", value = "due_date" },
    { text = "Change Priority", value = "priority" },
    { text = "Toggle Done", value = "toggle" },
    { text = "Delete Task", value = "delete" },
  }

  vim.ui.select(items, {
    prompt = "Edit Task:",
    format_item = function(item)
      return item.text
    end,
  }, function(choice)
    if not choice then return end
    
    if choice.value == "toggle" then
      task:toggle()
    elseif choice.value == "delete" then
      lazydo:delete_task()
    else
      M.edit_task_component(lazydo, choice.value)
    end
  end)
end

return M 