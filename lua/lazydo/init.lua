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
    }
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
    }
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
  },
  storage = {
    path = vim.fn.stdpath("data") .. "/lazydo/tasks.json",
    auto_save = true,    -- Save on every change
    backup = true,       -- Keep backup file
  },
  create_keymaps = true, -- Enable/disable default keymaps
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
    vim.api.nvim_win_close(self.win, true)
    self.is_visible = false
  else
    self:show()
  end
end

-- Add show function
function LazyDo:show()
  -- Ensure buffer is set up
  if not self.buf or not vim.api.nvim_buf_is_valid(self.buf) then
    self:setup()
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

    self.win = vim.api.nvim_open_win(self.buf, true, opts)
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

  -- Set window-local options
  vim.wo[self.win].number = false
  vim.wo[self.win].relativenumber = false
  vim.wo[self.win].cursorline = true
  vim.wo[self.win].signcolumn = "no"
  vim.wo[self.win].wrap = false

  -- Add autocmd to close on certain events
  vim.api.nvim_create_autocmd({"BufLeave", "BufWinLeave"}, {
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
end

-- Add global commands and keymaps
function LazyDo:create_commands()
  local self = self -- Capture self reference

  -- Create user commands
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

---Renders tasks in the buffer
function LazyDo:render_tasks()
  local lines = {}
  local highlights = {}

  for i, task in ipairs(self.tasks) do
    local indent = string.rep("  ", task.indent)
    local status_icon = task.done and self.opts.icons.task_done or self.opts.icons.task_pending
    if not task.done and task.due_date and task.due_date < os.time() then
      status_icon = self.opts.icons.task_overdue
    end

    local priority_icon = self.opts.icons.priority[
    task.priority == 1 and "high" or
    task.priority == 2 and "medium" or "low"
    ]

    local line = string.format("%s%s %s %s", indent, status_icon, priority_icon, task.content)
    table.insert(lines, line)

    -- Add highlights
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

    -- Render due date if exists
    if task.due_date then
      local date_str = os.date("%Y-%m-%d", task.due_date)
      line = line .. string.format(" %s %s", self.opts.icons.due_date, date_str)
    end

    -- Render notes if exists
    if task.notes and task.notes ~= "" then
      line = line .. string.format(" %s %s", self.opts.icons.note, task.notes)
    end
  end

  -- Insert tasks after header
  vim.api.nvim_buf_set_lines(self.buf, 3, -2, false, lines)

  -- Apply highlights
  for _, hl in ipairs(highlights) do
    vim.api.nvim_buf_add_highlight(
      self.buf,
      -1,
      hl.hl_group,
      hl.line,
      hl.col_start,
      hl.col_end
    )
  end
end

---Updates the render method to include tasks
function LazyDo:render()
  -- Ensure we have a valid buffer
  if not self.buf or not vim.api.nvim_buf_is_valid(self.buf) then
    return
  end

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
  self:render_tasks()

  -- Render footer
  local footer = "Press: " ..
      self.opts.keymaps.add_task .. " to add task | " ..
      self.opts.keymaps.toggle_done .. " to toggle | " ..
      self.opts.keymaps.search_tasks .. " to search"

  vim.api.nvim_buf_set_lines(self.buf, -1, -1, false, { footer })

  -- Make buffer non-modifiable again
  vim.api.nvim_buf_set_option(self.buf, 'modifiable', false)
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

return LazyDo
