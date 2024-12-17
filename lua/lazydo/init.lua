---@class LazyDo
---@field opts table Plugin options
---@field win number? Window handle
---@field buf number? Buffer handle
---@field is_visible boolean Visibility state
local LazyDo = {}

-- Move default options to the top of the file, before any function definitions
LazyDo.default_opts = {
  icons = {
    task_pending = "󰄱",
    task_done = "󰄵",
    task_overdue = "󰄮",
    due_date = "󰃰",
    note = "󰏫",
    priority = {
      high = "󰀦",
      medium = "󰀧",
      low = "󰀨",
    },
    checkbox = {
      unchecked = "[ ]",
      checked = "[x]",
      overdue = "[!]",
    },
    bullet = "•",
    expand = "▸",
    collapse = "▾",
  },
  colors = {
    header = "#89b4fa",
    pending = "#cba6f7",
    done = "#a6e3a1",
    overdue = "#f38ba8",
    note = "#94e2d5",
    due_date = "#fab387",
    priority = {
      high = "#f38ba8",
      medium = "#fab387",
      low = "#a6e3a1",
    },
    bullet = "#89b4fa",
    checkbox = "#cba6f7",
    expand = "#fab387",
  },
  keymaps = {
    toggle_done = "<Space>",
    edit_task = "e",
    delete_task = "d",
    add_task = "a",
    add_subtask = "o",
    search_tasks = "/",
    sort_by_date = "sd",
    sort_by_priority = "sp",
    toggle_expand = "<Tab>",
    move_up = "K",
    move_down = "J",
    increase_priority = ">",
    decrease_priority = "<",
    quick_note = "n",
    quick_date = "D",
  },
  storage = {
    path = vim.fn.stdpath("data") .. "/lazydo/tasks.json",
    auto_save = true,    -- Save on every change
    backup = true,       -- Keep backup file
  },
  create_keymaps = true, -- Enable/disable default keymaps
  render = {
    use_markdown = true,  -- Use markdown-style rendering
    show_empty_state = true,  -- Show message when no tasks
    show_help = true,    -- Show keybindings help
    compact_view = false, -- Compact view mode
  },
}

-- Add visibility state
LazyDo.is_visible = false

-- Add setup function for initialization
---@param opts? table
function LazyDo.setup(opts)
  -- Create singleton instance if it doesn't exist
  if not LazyDo.instance then
    local self = setmetatable({}, { __index = LazyDo })
    self.opts = vim.tbl_deep_extend("force", LazyDo.default_opts, opts or {})
    self.tasks = {}
    self.is_visible = false
    self.buf = nil
    self.win = nil
    LazyDo.instance = self

    -- Initialize storage
    self:ensure_storage_dir(self.opts.storage.path)
    self:load_tasks()

    -- Create commands and keymaps
    self:create_commands()

    -- Setup highlights
    self:setup_highlights()
  end

  return LazyDo.instance
end

-- Add toggle function
function LazyDo:toggle()
  if self.is_visible and self.win and vim.api.nvim_win_is_valid(self.win) then
    local ok, err = pcall(vim.api.nvim_win_close, self.win, true)
    if not ok then
      vim.notify("Failed to close window: " .. err, vim.log.levels.ERROR)
    end
    self.is_visible = false
  else
    self:show()
  end
end

-- Add show function
function LazyDo:show()
  -- Ensure buffer is set up
  if not self.buf or not vim.api.nvim_buf_is_valid(self.buf) then
    local ok, buf = pcall(vim.api.nvim_create_buf, false, true)
    if not ok then
      vim.notify("Failed to create buffer: " .. buf, vim.log.levels.ERROR)
      return false
    end
    self.buf = buf -- Store the buffer number

    -- Set buffer options
    ok, err = pcall(function()
      vim.api.nvim_buf_set_option(self.buf, 'buftype', 'nofile')
      vim.api.nvim_buf_set_option(self.buf, 'bufhidden', 'hide')
      vim.api.nvim_buf_set_option(self.buf, 'swapfile', false)
      vim.api.nvim_buf_set_option(self.buf, 'filetype', 'lazydo')
      vim.api.nvim_buf_set_option(self.buf, 'modifiable', true)
    end)
    if not ok then
      vim.notify("Failed to set buffer options: " .. err, vim.log.levels.ERROR)
      return false
    end
    self:setup_highlights()
  end

  -- Verify buffer is valid before creating window
  if not vim.api.nvim_buf_is_valid(self.buf) then
    vim.notify("Invalid buffer", vim.log.levels.ERROR)
    return
  end

  -- Create or reuse window
  if not self.win or not vim.api.nvim_win_is_valid(self.win) then
    local width = math.floor(vim.o.columns * 0.8)
    local height = math.floor(vim.o.lines * 0.8)
    local row = math.floor((vim.o.lines - height) / 2)
    local col = math.floor((vim.o.columns - width) / 2)

    local opts = {
      relative = 'editor',
      width = width,
      height = height,
      row = row,
      col = col,
      style = 'minimal',
      border = 'rounded',
    }

    local ok, win_or_err = pcall(vim.api.nvim_open_win, self.buf, true, opts)
    if not ok then
      vim.notify("Failed to create window: " .. win_or_err, vim.log.levels.ERROR)
      return
    end

    self.win = win_or_err
    self:setup_window_options()
  end

  self.is_visible = true
  self:render()
end

-- Add window options setup
function LazyDo:setup_window_options()
  if not self.win or not vim.api.nvim_win_is_valid(self.win) then
    return
  end

  local ok, err = pcall(function()
    -- Set window-local options
    vim.wo[self.win].number = false
    vim.wo[self.win].relativenumber = false
    vim.wo[self.win].cursorline = true
    vim.wo[self.win].signcolumn = "no"
    vim.wo[self.win].wrap = false

    -- Add autocmd to close on certain events
    vim.api.nvim_create_autocmd({ "BufLeave", "BufWinLeave" }, {
      buffer = self.buf,
      callback = function()
        if self.is_visible then
          self:toggle()
        end
      end,
    })

    -- Add autocmd for auto-save
    if self.opts.storage.auto_save then
      vim.api.nvim_create_autocmd("BufLeave", {
        buffer = self.buf,
        callback = function()
          self:save_tasks()
        end
      })
    end
  end)

  if not ok then
    vim.notify("Failed to setup window options: " .. err, vim.log.levels.ERROR)
  end
end

-- Add global commands and keymaps
function LazyDo:create_commands()
  local self = self -- Capture self reference

  -- Create user commands
  local ok, err = pcall(function()
    vim.api.nvim_create_user_command("LazyDoToggle", function()
      self:toggle()
    end, {})

    vim.api.nvim_create_user_command("LazyDoQuickAdd", function()
      self:quick_add_task()
    end, {})

    -- Create default keymaps if enabled
    if self.opts.create_keymaps ~= false then
      vim.keymap.set('n', '<leader>td', function()
        self:toggle()
      end, { desc = "Toggle LazyDo" })

      vim.keymap.set('n', '<leader>ta', function()
        self:quick_add_task()
      end, { desc = "Quick Add Task" })
    end
  end)

  if not ok then
    vim.notify("Failed to create commands: " .. err, vim.log.levels.ERROR)
  end
end

-- Add quick add task function
function LazyDo:quick_add_task()
  vim.ui.input({ prompt = "Quick add task: " }, function(content)
    if content and content ~= "" then
      local task = self:create_task(content)
      table.insert(self.tasks, task)
      if self.opts.storage.auto_save then
        self:save_tasks()
      end
      -- Show notification
      vim.notify("Task added: " .. content, vim.log.levels.INFO)
    end
  end)
end

---Creates a new instance of LazyDo
---@param opts? table Optional user configuration
---@return LazyDo
function LazyDo.new(opts)
  local self = setmetatable({}, { __index = LazyDo })
  self.opts = vim.tbl_deep_extend("force", LazyDo.default_opts, opts or {})
  LazyDo.wrap_with_auto_save(self)
  self:setup()
  return self
end

---Sets up syntax highlights
function LazyDo:setup_highlights()
  local highlights = {
    LazyDoHeader = { fg = self.opts.colors.header, bold = true },
    LazyDoPending = { fg = self.opts.colors.pending },
    LazyDoDone = { fg = self.opts.colors.done },
    LazyDoOverdue = { fg = self.opts.colors.overdue },
    LazyDoNote = { fg = self.opts.colors.note },
    LazyDoDueDate = { fg = self.opts.colors.due_date },
    LazyDoPriorityHigh = { fg = self.opts.colors.priority.high },
    LazyDoPriorityMedium = { fg = self.opts.colors.priority.medium },
    LazyDoPriorityLow = { fg = self.opts.colors.priority.low },
  }

  for name, attrs in pairs(highlights) do
    vim.api.nvim_set_hl(0, name, attrs)
  end
end

---Sets up keymaps for the LazyDo buffer
function LazyDo:setup_keymaps()
  local function map(key, func)
    vim.keymap.set('n', key, func, { buffer = self.buf, silent = true })
  end

  map(self.opts.keymaps.toggle_done, function() self:toggle_task() end)
  map(self.opts.keymaps.edit_task, function() self:edit_task() end)
  map(self.opts.keymaps.delete_task, function() self:delete_task() end)
  map(self.opts.keymaps.add_task, function() self:add_task() end)
  map(self.opts.keymaps.add_subtask, function() self:add_subtask() end)
  map(self.opts.keymaps.search_tasks, function() self:search_tasks() end)
  map(self.opts.keymaps.sort_by_date, function() self:sort_by_date() end)
  map(self.opts.keymaps.sort_by_priority, function() self:sort_by_priority() end)
  map(self.opts.keymaps.toggle_expand, function() self:toggle_expand() end)
  map(self.opts.keymaps.move_up, function() self:move_task_up() end)
  map(self.opts.keymaps.move_down, function() self:move_task_down() end)
  map(self.opts.keymaps.increase_priority, function() self:change_priority(1) end)
  map(self.opts.keymaps.decrease_priority, function() self:change_priority(-1) end)
  map(self.opts.keymaps.quick_note, function() self:quick_note() end)
  map(self.opts.keymaps.quick_date, function() self:quick_date() end)
  map("<CR>", function() self:quick_actions() end)
end

---@class Task
---@field id string Unique identifier
---@field content string Task content
---@field done boolean Completion status
---@field due_date? number Unix timestamp
---@field priority number 1 (high) to 3 (low)
---@field notes? string Additional notes
---@field subtasks Task[] Nested subtasks
---@field indent number Indentation level
local Task = {}

---@type Task[]
LazyDo.tasks = {}

---Creates a new task
---@param content string Task content
---@param opts? table Additional task options
---@return Task
function LazyDo:create_task(content, opts)
  opts = opts or {}
  local task = {
    id = tostring(os.time()) .. math.random(1000, 9999),
    content = content,
    done = false,
    priority = opts.priority or 2,
    due_date = opts.due_date,
    notes = opts.notes,
    subtasks = {},
    indent = opts.indent or 0
  }
  return task
end

---Adds a new task
function LazyDo:add_task()
  vim.ui.input({ prompt = "New task: " }, function(content)
    if not content or content == "" then return end

    -- Show input for additional details
    local function show_task_details(callback)
      local items = {
        { text = "Set Priority", value = "priority" },
        { text = "Set Due Date", value = "due_date" },
        { text = "Add Notes",    value = "notes" },
      }

      vim.ui.select(items, {
        prompt = "Add task details:",
        format_item = function(item) return item.text end
      }, function(choice)
        if not choice then
          callback({})
          return
        end

        if choice.value == "priority" then
          vim.ui.select({ "High", "Medium", "Low" }, {
            prompt = "Select priority:"
          }, function(pri)
            local priority_map = { High = 1, Medium = 2, Low = 3 }
            callback({ priority = priority_map[pri] })
          end)
        elseif choice.value == "due_date" then
          vim.ui.input({ prompt = "Due date (YYYY-MM-DD): " }, function(date)
            if date then
              local timestamp = os.time(os.date("*t", os.time({
                year = tonumber(date:sub(1, 4)),
                month = tonumber(date:sub(6, 7)),
                day = tonumber(date:sub(9, 10))
              })))
              callback({ due_date = timestamp })
            end
          end)
        elseif choice.value == "notes" then
          vim.ui.input({ prompt = "Notes: " }, function(notes)
            callback({ notes = notes })
          end)
        end
      end)
    end

    show_task_details(function(opts)
      local task = self:create_task(content, opts)
      table.insert(self.tasks, task)
      self:render()
    end)
  end)
end

---Toggles task completion status
function LazyDo:toggle_task()
  local cursor = vim.api.nvim_win_get_cursor(self.win)
  local task = self:get_task_at_line(cursor[1])
  if task then
    task.done = not task.done
    self:render()
  end
end

---Gets task at specified line number
---@param line_nr number
---@return Task?
function LazyDo:get_task_at_line(line_nr)
  -- Account for header lines
  line_nr = line_nr - 4
  if line_nr < 1 or line_nr > #self.tasks then
    return nil
  end
  return self.tasks[line_nr]
end

---Renders tasks in markdown-style format
function LazyDo:render_tasks()
  local lines = {}
  local highlights = {}
  
  if #self.tasks == 0 and self.opts.render.show_empty_state then
    table.insert(lines, "No tasks yet! Press " .. self.opts.keymaps.add_task .. " to add one.")
    return lines, highlights
  }

  for i, task in ipairs(self.tasks) do
    local indent = string.rep("  ", task.indent)
    local checkbox = task.done and self.opts.icons.checkbox.checked or
      (not task.done and task.due_date and task.due_date < os.time()) and 
        self.opts.icons.checkbox.overdue or
        self.opts.icons.checkbox.unchecked

    local has_subtasks = #task.subtasks > 0
    local expand_icon = has_subtasks and 
      (task.expanded and self.opts.icons.collapse or self.opts.icons.expand) or
      self.opts.icons.bullet

    local priority_marker = string.rep("!", task.priority == 1 and 3 or task.priority == 2 and 2 or 1)
    
    -- Markdown-style or plain rendering
    local line
    if self.opts.render.use_markdown then
      line = string.format("%s%s %s **%s** %s", 
        indent, expand_icon, checkbox, task.content, priority_marker)
    else
      line = string.format("%s%s %s %s %s",
        indent, expand_icon, checkbox, task.content, priority_marker)
    end

    -- Add metadata
    if task.due_date then
      local date_str = os.date("📅 %Y-%m-%d", task.due_date)
      line = line .. " " .. date_str
    end

    if task.notes then
      local note_preview = string.sub(task.notes, 1, 30)
      if #task.notes > 30 then note_preview = note_preview .. "..." end
      line = line .. string.format(" 📝 %s", note_preview)
    end

    table.insert(lines, line)

    -- Add highlights for the new rendering
    local hl_group = task.done and "LazyDoDone" or
        (task.due_date and task.due_date < os.time()) and "LazyDoOverdue" or
        "LazyDoPending"

    local priority_hl = task.priority == 1 and "LazyDoPriorityHigh" or
        task.priority == 2 and "LazyDoPriorityMedium" or
        "LazyDoPriorityLow"

    table.insert(highlights, {
      line = i + 3, -- Account for header
      hl_group = hl_group,
      col_start = #indent,
      col_end = #indent + 1
    })

    table.insert(highlights, {
      line = i + 3,
      hl_group = priority_hl,
      col_start = #indent + 3,
      col_end = #indent + 4
    })
  end

  return lines, highlights
end

---Updates the render method to include tasks
function LazyDo:render()
  -- Ensure we have a valid buffer
  if not self.buf or not vim.api.nvim_buf_is_valid(self.buf) then
    vim.notify("Invalid buffer for rendering", vim.log.levels.ERROR)
    return
  end

  local ok, err = pcall(function()
    -- Make buffer modifiable
    vim.api.nvim_buf_set_option(self.buf, 'modifiable', true)

    -- Clear buffer
    vim.api.nvim_buf_set_lines(self.buf, 0, -1, false, {})

    -- Render header
    local header = [[
╭──────────────────╮
│      LazyDo      │
╰──────────────────╯
]]
    local header_lines = vim.split(header, "\n")
    vim.api.nvim_buf_set_lines(self.buf, 0, #header_lines, false, header_lines)

    -- Render tasks
    local lines, highlights = self:render_tasks()
    vim.api.nvim_buf_set_lines(self.buf, 3, -2, false, lines)

    -- Render footer
    local footer = "Press: " ..
        self.opts.keymaps.add_task .. " to add task | " ..
        self.opts.keymaps.toggle_done .. " to toggle | " ..
        self.opts.keymaps.search_tasks .. " to search"

    vim.api.nvim_buf_set_lines(self.buf, -1, -1, false, { footer })

    -- Make buffer non-modifiable again
    vim.api.nvim_buf_set_option(self.buf, 'modifiable', false)
  end)

  if not ok then
    vim.notify("Failed to render buffer: " .. err, vim.log.levels.ERROR)
  end
end

---Adds a subtask to the current task
function LazyDo:add_subtask()
  local cursor = vim.api.nvim_win_get_cursor(self.win)
  local parent_task = self:get_task_at_line(cursor[1])
  if not parent_task then return end

  vim.ui.input({ prompt = "New subtask: " }, function(content)
    if not content or content == "" then return end

    local subtask = self:create_task(content, {
      indent = parent_task.indent + 1
    })

    -- Find the correct position to insert the subtask
    local insert_pos = self:find_subtask_position(parent_task)
    table.insert(self.tasks, insert_pos, subtask)
    self:render()
  end)
end

---Finds the correct position to insert a subtask
---@param parent_task Task
---@return number
function LazyDo:find_subtask_position(parent_task)
  local parent_index = self:get_task_index(parent_task)
  if not parent_index then return #self.tasks + 1 end

  -- Find the last subtask of this parent
  local pos = parent_index + 1
  while pos <= #self.tasks and self.tasks[pos].indent > parent_task.indent do
    pos = pos + 1
  end
  return pos
end

---Edits an existing task
function LazyDo:edit_task()
  local cursor = vim.api.nvim_win_get_cursor(self.win)
  local task = self:get_task_at_line(cursor[1])
  if not task then return end

  local items = {
    { text = "Edit Content", value = "content" },
    { text = "Set Priority", value = "priority" },
    { text = "Set Due Date", value = "due_date" },
    { text = "Edit Notes",   value = "notes" },
  }

  vim.ui.select(items, {
    prompt = "Edit task:",
    format_item = function(item) return item.text end
  }, function(choice)
    if not choice then return end

    if choice.value == "content" then
      vim.ui.input({
        prompt = "Edit task: ",
        default = task.content
      }, function(new_content)
        if new_content and new_content ~= "" then
          task.content = new_content
          self:render()
        end
      end)
    elseif choice.value == "priority" then
      vim.ui.select({ "High", "Medium", "Low" }, {
        prompt = "Select priority:"
      }, function(pri)
        if pri then
          local priority_map = { High = 1, Medium = 2, Low = 3 }
          task.priority = priority_map[pri]
          self:render()
        end
      end)
    elseif choice.value == "due_date" then
      local current_date = task.due_date and os.date("%Y-%m-%d", task.due_date) or ""
      vim.ui.input({
        prompt = "Due date (YYYY-MM-DD): ",
        default = current_date
      }, function(date)
        if date == "" then
          task.due_date = nil
        elseif date then
          task.due_date = os.time(os.date("*t", os.time({
            year = tonumber(date:sub(1, 4)),
            month = tonumber(date:sub(6, 7)),
            day = tonumber(date:sub(9, 10))
          })))
        end
        self:render()
      end)
    elseif choice.value == "notes" then
      vim.ui.input({
        prompt = "Notes: ",
        default = task.notes or ""
      }, function(notes)
        task.notes = notes ~= "" and notes or nil
        self:render()
      end)
    end
  end)
end

---Searches tasks using fzf-lua
function LazyDo:search_tasks()
  local ok, fzf = pcall(require, 'fzf-lua')
  if not ok then
    vim.notify("fzf-lua is required for task search", vim.log.levels.ERROR)
    return
  end

  local tasks = {}
  for _, task in ipairs(self.tasks) do
    local status = task.done and "[Done]" or
        (task.due_date and task.due_date < os.time()) and "[Overdue]" or
        "[Pending]"

    local priority = task.priority == 1 and "⚡High" or
        task.priority == 2 and "●Medium" or
        "○Low"

    local due = task.due_date and os.date(" (due: %Y-%m-%d)", task.due_date) or ""
    local indent = string.rep("  ", task.indent)

    table.insert(tasks, {
      display = string.format("%s%s [%s]%s %s",
        indent, status, priority, due, task.content),
      task = task,
      line = self:get_task_index(task)
    })
  end

  fzf.fzf_exec(
    vim.tbl_map(function(t) return t.display end, tasks),
    {
      prompt = "Search Tasks> ",
      actions = {
        ["default"] = function(selected)
          local idx = selected[1].idx
          local task_line = tasks[idx].line
          -- Jump to the task line
          vim.api.nvim_win_set_cursor(self.win, { task_line + 4, 0 })
        end
      }
    }
  )
end

---Sort tasks by due date
function LazyDo:sort_by_date()
  local function sort_func(a, b)
    -- Keep subtasks with their parents
    if a.indent ~= b.indent then
      return a.indent < b.indent
    end

    -- Sort by due date
    if not a.due_date and not b.due_date then return false end
    if not a.due_date then return false end
    if not b.due_date then return true end
    return a.due_date < b.due_date
  end

  table.sort(self.tasks, sort_func)
  self:render()
end

---Sort tasks by priority
function LazyDo:sort_by_priority()
  local function sort_func(a, b)
    -- Keep subtasks with their parents
    if a.indent ~= b.indent then
      return a.indent < b.indent
    end

    -- Sort by priority (1=high to 3=low)
    return a.priority < b.priority
  end

  table.sort(self.tasks, sort_func)
  self:render()
end

---Gets the index of a task in the tasks array
---@param task Task
---@return number?
function LazyDo:get_task_index(task)
  for i, t in ipairs(self.tasks) do
    if t.id == task.id then
      return i
    end
  end
  return nil
end

---@class Storage
---@field path string Path to storage file
local Storage = {}

---Ensures storage directory exists
---@param path string
function LazyDo:ensure_storage_dir(path)
  local dir = vim.fn.fnamemodify(path, ":h")
  if vim.fn.isdirectory(dir) == 0 then
    vim.fn.mkdir(dir, "p")
  end
end

---Saves tasks to storage
---@param self LazyDo
function LazyDo:save_tasks()
  LazyDo.ensure_storage_dir(self.opts.storage.path)

  -- Create backup if enabled
  if self.opts.storage.backup and vim.fn.filereadable(self.opts.storage.path) == 1 then
    local backup_path = self.opts.storage.path .. ".bak"
    vim.fn.rename(self.opts.storage.path, backup_path)
  end

  -- Prepare tasks for serialization
  local serializable_tasks = vim.deepcopy(self.tasks)

  -- Write to file
  local file = io.open(self.opts.storage.path, "w")
  if file then
    file:write(vim.json.encode(serializable_tasks))
    file:close()
  end
end

---Loads tasks from storage
---@param self LazyDo
function LazyDo:load_tasks()
  if vim.fn.filereadable(self.opts.storage.path) == 0 then
    self.tasks = {}
    return
  end

  local file = io.open(self.opts.storage.path, "r")
  if not file then
    self.tasks = {}
    return
  end

  local content = file:read("*all")
  file:close()

  local ok, decoded = pcall(vim.json.decode, content)
  if ok then
    self.tasks = decoded
  else
    -- Try to load from backup if main file is corrupted
    local backup_path = self.opts.storage.path .. ".bak"
    if vim.fn.filereadable(backup_path) == 1 then
      file = io.open(backup_path, "r")
      if file then
        content = file:read("*all")
        file:close()
        ok, decoded = pcall(vim.json.decode, content)
        if ok then
          self.tasks = decoded
          -- Save recovered data to main file
          self:save_tasks()
          vim.notify("Recovered tasks from backup file", vim.log.levels.INFO)
          return
        end
      end
    end
    self.tasks = {}
    vim.notify("Failed to load tasks: " .. decoded, vim.log.levels.ERROR)
  end
end

-- Update task modification functions to auto-save
function LazyDo:with_auto_save(self, func, ...)
  local result = func(...)
  if self.opts.storage.auto_save then
    self:save_tasks()
  end
  return result
end

-- Wrap task modification functions with auto-save
function LazyDo:wrap_with_auto_save(self)
  local functions_to_wrap = {
    "add_task",
    "add_subtask",
    "edit_task",
    "toggle_task",
    "delete_task",
    "sort_by_date",
    "sort_by_priority"
  }

  for _, func_name in ipairs(functions_to_wrap) do
    local original = self[func_name]
    self[func_name] = function(...)
      return LazyDo.with_auto_save(self, original, ...)
    end
  end
end

---Deletes a task
function LazyDo:delete_task()
  local cursor = vim.api.nvim_win_get_cursor(self.win)
  local task = self:get_task_at_line(cursor[1])
  if not task then return end

  vim.ui.select({ "Yes", "No" }, {
    prompt = "Delete task?",
  }, function(choice)
    if choice == "Yes" then
      local index = self:get_task_index(task)
      if index then
        -- Also remove any subtasks
        local i = index + 1
        while i <= #self.tasks and self.tasks[i].indent > task.indent do
          table.remove(self.tasks, i)
        end
        table.remove(self.tasks, index)
        self:render()
      end
    end
  end)
end

-- Add cleanup function
function LazyDo:cleanup()
  if self.win and vim.api.nvim_win_is_valid(self.win) then
    vim.api.nvim_win_close(self.win, true)
  end

  if self.buf and vim.api.nvim_buf_is_valid(self.buf) then
    vim.api.nvim_buf_delete(self.buf, { force = true })
  end

  self.win = nil
  self.buf = nil
  self.is_visible = false
end

---Quick actions menu for task manipulation
function LazyDo:quick_actions()
  local cursor = vim.api.nvim_win_get_cursor(self.win)
  local task = self:get_task_at_line(cursor[1])
  if not task then return end

  local actions = {
    { text = "Toggle Status", value = "toggle" },
    { text = "Edit Content", value = "edit" },
    { text = "Set Priority", value = "priority" },
    { text = "Set Due Date", value = "due_date" },
    { text = "Add/Edit Note", value = "note" },
    { text = "Add Subtask", value = "subtask" },
    { text = "Delete Task", value = "delete" },
    { text = "Move Up", value = "move_up" },
    { text = "Move Down", value = "move_down" },
  }

  vim.ui.select(actions, {
    prompt = "Task Actions:",
    format_item = function(item) return item.text end
  }, function(choice)
    if not choice then return end
    
    if choice.value == "toggle" then
      self:toggle_task()
    elseif choice.value == "edit" then
      self:edit_task()
    elseif choice.value == "priority" then
      self:change_priority(0)
    elseif choice.value == "due_date" then
      self:quick_date()
    elseif choice.value == "note" then
      self:quick_note()
    elseif choice.value == "subtask" then
      self:add_subtask()
    elseif choice.value == "delete" then
      self:delete_task()
    elseif choice.value == "move_up" then
      self:move_task_up()
    elseif choice.value == "move_down" then
      self:move_task_down()
    end
  end)
end

-- Add new task movement functions
function LazyDo:move_task_up()
  local cursor = vim.api.nvim_win_get_cursor(self.win)
  local current_idx = cursor[1] - 4 -- Adjust for header
  
  if current_idx > 1 then
    local task = self.tasks[current_idx]
    local target_idx = current_idx - 1
    
    -- Ensure we don't break task hierarchy
    if self.tasks[target_idx].indent < task.indent and current_idx > 1 then
      target_idx = target_idx - 1
    end
    
    if target_idx > 0 then
      table.remove(self.tasks, current_idx)
      table.insert(self.tasks, target_idx, task)
      self:render()
      vim.api.nvim_win_set_cursor(self.win, {target_idx + 4, cursor[2]})
    end
  end
end

function LazyDo:move_task_down()
  local cursor = vim.api.nvim_win_get_cursor(self.win)
  local current_idx = cursor[1] - 4
  
  if current_idx < #self.tasks then
    local task = self.tasks[current_idx]
    local target_idx = current_idx + 1
    
    -- Ensure we don't break task hierarchy
    if self.tasks[target_idx].indent < task.indent and target_idx < #self.tasks then
      target_idx = target_idx + 1
    end
    
    if target_idx <= #self.tasks then
      table.remove(self.tasks, current_idx)
      table.insert(self.tasks, target_idx, task)
      self:render()
      vim.api.nvim_win_set_cursor(self.win, {target_idx + 4, cursor[2]})
    end
  end
end

-- Add quick note function
function LazyDo:quick_note()
  local cursor = vim.api.nvim_win_get_cursor(self.win)
  local task = self:get_task_at_line(cursor[1])
  if not task then return end

  vim.ui.input({
    prompt = "Add/Edit Note: ",
    default = task.notes or "",
    completion = "file"
  }, function(input)
    if input then
      task.notes = input ~= "" and input or nil
      self:render()
    end
  end)
end

-- Add quick date function with calendar integration
function LazyDo:quick_date()
  local cursor = vim.api.nvim_win_get_cursor(self.win)
  local task = self:get_task_at_line(cursor[1])
  if not task then return end

  -- Try to use calendar.nvim if available
  local has_calendar, _ = pcall(require, "calendar")
  if has_calendar then
    vim.cmd("Calendar")
    -- Set up autocmd to capture selected date
    vim.api.nvim_create_autocmd("User", {
      pattern = "CalendarSelect",
      callback = function()
        local date = vim.fn["calendar#day#today#get"]()
        task.due_date = os.time({
          year = date.year,
          month = date.month,
          day = date.day
        })
        self:render()
        vim.cmd("quit") -- Close calendar
      end,
      once = true
    })
  else
    -- Fallback to manual input
    local current = task.due_date and os.date("%Y-%m-%d", task.due_date) or ""
    vim.ui.input({
      prompt = "Set Due Date (YYYY-MM-DD): ",
      default = current
    }, function(input)
      if input then
        if input == "" then
          task.due_date = nil
        else
          local year, month, day = input:match("(%d%d%d%d)-(%d%d)-(%d%d)")
          if year and month and day then
            task.due_date = os.time({
              year = tonumber(year),
              month = tonumber(month),
              day = tonumber(day)
            })
          end
        end
        self:render()
      end
    end)
  end
end

-- Add priority management
function LazyDo:change_priority(delta)
  local cursor = vim.api.nvim_win_get_cursor(self.win)
  local task = self:get_task_at_line(cursor[1])
  if not task then return end

  task.priority = math.max(1, math.min(3, task.priority + delta))
  self:render()
end

-- Add task expansion toggle
function LazyDo:toggle_expand()
  local cursor = vim.api.nvim_win_get_cursor(self.win)
  local task = self:get_task_at_line(cursor[1])
  if not task or #task.subtasks == 0 then return end

  task.expanded = not task.expanded
  self:render()
end

-- Enhanced UI rendering with task filtering and sorting
function LazyDo:filter_tasks(filter)
  local filtered = {}
  for _, task in ipairs(self.tasks) do
    if filter(task) then
      table.insert(filtered, task)
    end
  end
  return filtered
end

-- Add task filtering options
function LazyDo:show_filters()
  local filters = {
    { text = "All Tasks", value = function(t) return true end },
    { text = "Pending Tasks", value = function(t) return not t.done end },
    { text = "Completed Tasks", value = function(t) return t.done end },
    { text = "Overdue Tasks", value = function(t) 
      return not t.done and t.due_date and t.due_date < os.time() 
    end },
    { text = "High Priority", value = function(t) return t.priority == 1 end },
    { text = "No Due Date", value = function(t) return not t.due_date end },
  }

  vim.ui.select(filters, {
    prompt = "Filter Tasks:",
    format_item = function(item) return item.text end
  }, function(choice)
    if choice then
      self.current_filter = choice.value
      self:render()
    end
  end)
end

-- Add statistics display
function LazyDo:render_statistics()
  local total = #self.tasks
  local completed = #self:filter_tasks(function(t) return t.done end)
  local overdue = #self:filter_tasks(function(t) 
    return not t.done and t.due_date and t.due_date < os.time()
  end)
  local high_priority = #self:filter_tasks(function(t) return t.priority == 1 end)

  return string.format(
    "📊 Total: %d | ✅ Done: %d | ⏰ Overdue: %d | ⚡ High Priority: %d",
    total, completed, overdue, high_priority
  )
end

-- Enhanced render function with statistics and help
function LazyDo:render()
  if not self.buf or not vim.api.nvim_buf_is_valid(self.buf) then return end

  local lines = {}
  local highlights = {}

  -- Add header
  table.insert(lines, "╭" .. string.rep("─", 50) .. "╮")
  table.insert(lines, "│" .. string.center("LazyDo Task Manager", 50) .. "│")
  table.insert(lines, "╰" .. string.rep("─", 50) .. "╯")

  -- Add statistics
  table.insert(lines, "")
  table.insert(lines, self:render_statistics())
  table.insert(lines, "")

  -- Filter tasks if needed
  local tasks_to_render = self.current_filter and 
    self:filter_tasks(self.current_filter) or self.tasks

  -- Render tasks
  local task_lines, task_highlights = self:render_tasks(tasks_to_render)
  vim.list_extend(lines, task_lines)
  vim.list_extend(highlights, task_highlights)

  -- Add help footer if enabled
  if self.opts.render.show_help then
    table.insert(lines, "")
    table.insert(lines, "── Commands ──")
    table.insert(lines, string.format(
      "%s:Toggle | %s:Edit | %s:Add | %s:Delete | %s:Filter | %s:Sort",
      self.opts.keymaps.toggle_done,
      self.opts.keymaps.edit_task,
      self.opts.keymaps.add_task,
      self.opts.keymaps.delete_task,
      self.opts.keymaps.search_tasks,
      self.opts.keymaps.sort_by_priority
    ))
  end

  -- Update buffer content
  vim.api.nvim_buf_set_option(self.buf, 'modifiable', true)
  vim.api.nvim_buf_set_lines(self.buf, 0, -1, false, lines)
  vim.api.nvim_buf_set_option(self.buf, 'modifiable', false)

  -- Apply highlights
  for _, hl in ipairs(highlights) do
    vim.api.nvim_buf_add_highlight(
      self.buf, -1, hl.hl_group, hl.line, hl.col_start, hl.col_end
    )
  end
end

-- Add task tags and categories
function LazyDo:add_tag()
  local cursor = vim.api.nvim_win_get_cursor(self.win)
  local task = self:get_task_at_line(cursor[1])
  if not task then return end

  task.tags = task.tags or {}
  vim.ui.input({
    prompt = "Add Tag: ",
    completion = function(_, cmdline)
      -- Provide completion from existing tags
      local existing_tags = {}
      for _, t in ipairs(self.tasks) do
        if t.tags then
          for tag in pairs(t.tags) do
            existing_tags[tag] = true
          end
        end
      end
      return vim.tbl_filter(function(tag)
        return tag:match("^" .. cmdline)
      end, vim.tbl_keys(existing_tags))
    end
  }, function(input)
    if input and input ~= "" then
      task.tags[input] = true
      self:render()
    end
  end)
end

-- Add task dependencies
function LazyDo:manage_dependencies()
  local cursor = vim.api.nvim_win_get_cursor(self.win)
  local task = self:get_task_at_line(cursor[1])
  if not task then return end

  local actions = {
    { text = "Add Dependency", value = "add" },
    { text = "Remove Dependency", value = "remove" },
    { text = "View Dependencies", value = "view" },
  }

  vim.ui.select(actions, {
    prompt = "Manage Dependencies:",
    format_item = function(item) return item.text end
  }, function(choice)
    if not choice then return end

    if choice.value == "add" then
      self:select_task_as_dependency(task)
    elseif choice.value == "remove" then
      self:remove_dependency(task)
    elseif choice.value == "view" then
      self:view_dependencies(task)
    end
  end)
end

-- Add recurring tasks
function LazyDo:set_recurrence()
  local cursor = vim.api.nvim_win_get_cursor(self.win)
  local task = self:get_task_at_line(cursor[1])
  if not task then return end

  local patterns = {
    { text = "Daily", value = "daily" },
    { text = "Weekly", value = "weekly" },
    { text = "Monthly", value = "monthly" },
    { text = "Custom...", value = "custom" },
  }

  vim.ui.select(patterns, {
    prompt = "Set Recurrence Pattern:",
    format_item = function(item) return item.text end
  }, function(choice)
    if not choice then return end

    if choice.value == "custom" then
      vim.ui.input({
        prompt = "Enter cron pattern (*/2 * * * *): ",
      }, function(input)
        if input and input ~= "" then
          task.recurrence = { pattern = input, type = "cron" }
        end
      end)
    else
      task.recurrence = { pattern = choice.value, type = "preset" }
    end
    self:render()
  end)
end

-- Add task templates
function LazyDo:manage_templates()
  local actions = {
    { text = "Save as Template", value = "save" },
    { text = "Load Template", value = "load" },
    { text = "Delete Template", value = "delete" },
  }

  vim.ui.select(actions, {
    prompt = "Manage Templates:",
    format_item = function(item) return item.text end
  }, function(choice)
    if not choice then return end

    if choice.value == "save" then
      self:save_template()
    elseif choice.value == "load" then
      self:load_template()
    elseif choice.value == "delete" then
      self:delete_template()
    end
  end)
end

-- Add task export/import
function LazyDo:export_tasks(format)
  format = format or "json"
  local exporters = {
    json = function(tasks)
      return vim.json.encode(tasks)
    end,
    markdown = function(tasks)
      local lines = {}
      for _, task in ipairs(tasks) do
        local indent = string.rep("  ", task.indent)
        local status = task.done and "x" or " "
        local line = string.format("%s- [%s] %s", indent, status, task.content)
        if task.due_date then
          line = line .. " (Due: " .. os.date("%Y-%m-%d", task.due_date) .. ")"
        end
        table.insert(lines, line)
      end
      return table.concat(lines, "\n")
    end,
    csv = function(tasks)
      local lines = {"Content,Status,Due Date,Priority,Notes"}
      for _, task in ipairs(tasks) do
        local line = string.format('"%s",%s,%s,%d,"%s"',
          task.content:gsub('"', '""'),
          task.done and "Done" or "Pending",
          task.due_date and os.date("%Y-%m-%d", task.due_date) or "",
          task.priority,
          (task.notes or ""):gsub('"', '""')
        )
        table.insert(lines, line)
      end
      return table.concat(lines, "\n")
    end
  }

  if exporters[format] then
    local content = exporters[format](self.tasks)
    vim.ui.input({
      prompt = "Export filename: ",
      default = "tasks." .. format
    }, function(filename)
      if filename then
        local file = io.open(filename, "w")
        if file then
          file:write(content)
          file:close()
          vim.notify("Tasks exported to " .. filename, vim.log.levels.INFO)
        end
      end
    end)
  end
end

-- Add task search with preview
function LazyDo:advanced_search()
  local has_telescope, telescope = pcall(require, "telescope.builtin")
  if not has_telescope then
    return self:basic_search()
  end

  local search_items = {}
  for _, task in ipairs(self.tasks) do
    table.insert(search_items, {
      task = task,
      display = string.format("%s %s %s",
        task.done and "✓" or "☐",
        task.content,
        task.due_date and os.date("(Due: %Y-%m-%d)", task.due_date) or ""
      )
    })
  end

  telescope.custom_finder({
    results = search_items,
    entry_maker = function(entry)
      return {
        value = entry,
        display = entry.display,
        ordinal = entry.task.content,
        preview_command = function(entry, bufnr)
          local lines = {
            "Task Details:",
            "─────────────",
            "Content: " .. entry.task.content,
            "Status: " .. (entry.task.done and "Completed" or "Pending"),
            "Priority: " .. string.rep("!", entry.task.priority),
            entry.task.due_date and "Due Date: " .. os.date("%Y-%m-%d", entry.task.due_date) or "",
            entry.task.notes and "Notes: " .. entry.task.notes or "",
          }
          vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, lines)
        end
      }
    end,
    attach_mappings = function(prompt_bufnr, map)
      map("i", "<CR>", function()
        local selection = require("telescope.actions.state").get_selected_entry()
        require("telescope.actions").close(prompt_bufnr)
        if selection then
          local task = selection.value.task
          local task_idx = self:get_task_index(task)
          if task_idx then
            self:show()
            vim.api.nvim_win_set_cursor(self.win, {task_idx + 4, 0})
          end
        end
      end)
      return true
    end
  })
end

-- Add task statistics and analytics
function LazyDo:show_analytics()
  local stats = {
    total = #self.tasks,
    completed = 0,
    overdue = 0,
    priority = {high = 0, medium = 0, low = 0},
    due_today = 0,
    due_this_week = 0,
    tags = {},
    completion_rate = 0,
  }

  local today = os.time()
  local week_end = today + (7 * 24 * 60 * 60)

  for _, task in ipairs(self.tasks) do
    if task.done then stats.completed = stats.completed + 1 end
    if not task.done and task.due_date and task.due_date < today then
      stats.overdue = stats.overdue + 1
    end

    if task.priority == 1 then stats.priority.high = stats.priority.high + 1
    elseif task.priority == 2 then stats.priority.medium = stats.priority.medium + 1
    else stats.priority.low = stats.priority.low + 1 end

    if task.due_date then
      if os.date("%Y-%m-%d", task.due_date) == os.date("%Y-%m-%d", today) then
        stats.due_today = stats.due_today + 1
      elseif task.due_date <= week_end then
        stats.due_this_week = stats.due_this_week + 1
      end
    end

    if task.tags then
      for tag in pairs(task.tags) do
        stats.tags[tag] = (stats.tags[tag] or 0) + 1
      end
    end
  end

  stats.completion_rate = stats.total > 0 and 
    (stats.completed / stats.total * 100) or 0

  -- Create a new buffer for analytics
  local buf = vim.api.nvim_create_buf(false, true)
  local lines = {
    "Task Analytics",
    "═════════════",
    "",
    string.format("Total Tasks: %d", stats.total),
    string.format("Completion Rate: %.1f%%", stats.completion_rate),
    string.format("Completed: %d", stats.completed),
    string.format("Overdue: %d", stats.overdue),
    "",
    "Priority Distribution:",
    string.format("  High: %d", stats.priority.high),
    string.format("  Medium: %d", stats.priority.medium),
    string.format("  Low: %d", stats.priority.low),
    "",
    "Timeline:",
    string.format("  Due Today: %d", stats.due_today),
    string.format("  Due This Week: %d", stats.due_this_week),
    "",
    "Popular Tags:",
  }

  -- Add tag statistics
  local sorted_tags = vim.tbl_keys(stats.tags)
  table.sort(sorted_tags, function(a, b)
    return stats.tags[a] > stats.tags[b]
  end)
  for _, tag in ipairs(sorted_tags) do
    table.insert(lines, string.format("  #%s: %d", tag, stats.tags[tag]))
  end

  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  vim.api.nvim_buf_set_option(buf, 'modifiable', false)
  vim.api.nvim_buf_set_option(buf, 'filetype', 'lazydo-analytics')

  -- Show in a new window
  local width = math.floor(vim.o.columns * 0.4)
  local height = math.floor(vim.o.lines * 0.8)
  local row = math.floor((vim.o.lines - height) / 2)
  local col = math.floor(vim.o.columns - width)

  vim.api.nvim_open_win(buf, true, {
    relative = 'editor',
    width = width,
    height = height,
    row = row,
    col = col,
    style = 'minimal',
    border = 'rounded',
  })
end

return LazyDo
