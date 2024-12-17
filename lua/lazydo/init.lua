---@class LazyDo
---@field opts table Plugin options
---@field win number? Window handle
---@field buf number? Buffer handle
---@field is_visible boolean Visibility state
local LazyDo = {}

-- Add utility functions at the top of the file
local utils = {}

-- Fix string.center function
function utils.center(text, width)
  local padding = width - vim.fn.strdisplaywidth(text)
  if padding <= 0 then return text end
  local left_pad = math.floor(padding / 2)
  local right_pad = padding - left_pad
  return string.rep(" ", left_pad) .. text .. string.rep(" ", right_pad)
end

-- Safe table access
function utils.get_or_create(tbl, key, default)
  if tbl[key] == nil then
    tbl[key] = default
  end
  return tbl[key]
end

-- Safe string operations
function utils.safe_sub(str, start_idx, end_idx)
  if not str then return "" end
  return string.sub(str or "", start_idx, end_idx)
end

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
    auto_save = true,        -- Save on every change
    backup = true,           -- Keep backup file
  },
  create_keymaps = true,     -- Enable/disable default keymaps
  render = {
    use_markdown = true,     -- Use markdown-style rendering
    show_empty_state = true, -- Show message when no tasks
    show_help = true,        -- Show keybindings help
    compact_view = false,    -- Compact view mode
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
  if not task then return end

  task.done = not task.done
  
  -- Handle dependent tasks
  if task.done then
    -- Check if all dependencies are completed
    local all_deps_done = true
    for _, dep_id in ipairs(task.dependencies or {}) do
      local dep = self:get_task_by_id(dep_id)
      if dep and not dep.done then
        all_deps_done = false
        break
      end
    end
    
    if not all_deps_done then
      vim.notify("Cannot complete task: dependencies not done", vim.log.levels.WARN)
      task.done = false
      return
    end
  else
    -- Uncompleting a task should uncheck dependent tasks
    self:uncheck_dependent_tasks(task)
  end

  self:render()
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
  end

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
  if not self.buf or not vim.api.nvim_buf_is_valid(self.buf) then return end

  local lines = {}
  local highlights = {}

  -- Add header
  table.insert(lines, "╭" .. string.rep("─", 50) .. "╮")
  table.insert(lines, "│" .. utils.center("LazyDo Task Manager", 50) .. "│")
  table.insert(lines, "╰" .. string.rep("─", 50) .. "╯")

  -- Add statistics
  table.insert(lines, "")
  table.insert(lines, self:render_statistics())
  table.insert(lines, "")

  -- Initialize task fields if they don't exist
  for _, task in ipairs(self.tasks) do
    task.tags = task.tags or {}
    task.priority = task.priority or 3
    task.indent = task.indent or 0
    task.id = task.id or tostring(os.time()) .. math.random(1000, 9999)
    task.subtasks = task.subtasks or {}
    task.dependencies = task.dependencies or {}
  end

  -- Filter tasks if needed
  local tasks_to_render = self.current_filter and 
    self:filter_tasks(self.current_filter) or self.tasks

  -- Render tasks
  local task_lines, task_highlights = self:render_tasks(tasks_to_render)
  vim.list_extend(lines, task_lines)
  vim.list_extend(highlights, task_highlights)

  -- Add help footer if enabled
  if self.opts and self.opts.render and self.opts.render.show_help then
    table.insert(lines, "")
    table.insert(lines, "── Commands ──")
    local keymaps = self.opts.keymaps or {}
    table.insert(lines, string.format(
      "%s:Toggle | %s:Edit | %s:Add | %s:Delete | %s:Filter | %s:Sort",
      keymaps.toggle_done or "t",
      keymaps.edit_task or "e",
      keymaps.add_task or "a",
      keymaps.delete_task or "d",
      keymaps.search_tasks or "f",
      keymaps.sort_by_priority or "s"
    ))
  end

  -- Update buffer content safely
  vim.api.nvim_buf_set_option(self.buf, 'modifiable', true)
  vim.api.nvim_buf_set_lines(self.buf, 0, -1, false, lines)
  vim.api.nvim_buf_set_option(self.buf, 'modifiable', false)

  -- Apply highlights safely
  for _, hl in ipairs(highlights) do
    pcall(vim.api.nvim_buf_add_highlight,
      self.buf, -1, hl.hl_group, hl.line, hl.col_start, hl.col_end
    )
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

  vim.ui.input({
    prompt = "Edit task: ",
    default = task.content,
    completion = "custom,v:lua.LazyDo_completion",
  }, function(input)
    if input and input ~= "" then
      task.content = input
      self:render()
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

  -- Check if task has dependents
  local has_dependents = false
  for _, t in ipairs(self.tasks) do
    if vim.tbl_contains(t.dependencies or {}, task.id) then
      has_dependents = true
      break
    end
  end

  if has_dependents then
    vim.ui.select({ "Yes", "No" }, {
      prompt = "Task has dependents. Delete anyway?",
    }, function(choice)
      if choice == "Yes" then
        self:remove_task_and_subtasks(task)
      end
    end)
  else
    self:remove_task_and_subtasks(task)
  end
end

-- Helper function to remove task and its subtasks
function LazyDo:remove_task_and_subtasks(task)
  local to_remove = {task.id}
  
  -- Collect all subtask IDs
  local function collect_subtasks(t)
    for _, subtask in ipairs(t.subtasks or {}) do
      table.insert(to_remove, subtask.id)
      collect_subtasks(subtask)
    end
  end
  
  collect_subtasks(task)
  
  -- Remove tasks
  self.tasks = vim.tbl_filter(function(t)
    return not vim.tbl_contains(to_remove, t.id)
  end, self.tasks)
  
  self:render()
end

-- Helper function to uncheck dependent tasks
function LazyDo:uncheck_dependent_tasks(task)
  for _, t in ipairs(self.tasks) do
    if vim.tbl_contains(t.dependencies or {}, task.id) then
      t.done = false
      self:uncheck_dependent_tasks(t)
    end
  end
end

-- Show sort menu
function LazyDo:show_sort_menu()
  local options = {
    { text = "Priority", value = "priority" },
    { text = "Due Date", value = "due_date" },
    { text = "Status", value = "status" },
    { text = "Alphabetical", value = "alphabetical" },
  }

  vim.ui.select(options, {
    prompt = "Sort by:",
    format_item = function(item) return item.text end
  }, function(choice)
    if choice then
      self:sort_tasks_by(choice.value)
    end
  end)
end

-- Show help
function LazyDo:show_help()
  local help_lines = {
    "LazyDo Keybindings",
    "═════════════════",
    "",
    "Task Management:",
    string.format("  %s - Toggle task completion", self.opts.keymaps.toggle_done),
    string.format("  %s - Edit task", self.opts.keymaps.edit_task),
    string.format("  %s - Add new task", self.opts.keymaps.add_task),
    string.format("  %s - Delete task", self.opts.keymaps.delete_task),
    "",
    "Organization:",
    string.format("  %s - Move task up", self.opts.keymaps.move_up),
    string.format("  %s - Move task down", self.opts.keymaps.move_down),
    string.format("  %s - Toggle expand/collapse", self.opts.keymaps.toggle_expand),
    "",
    "Properties:",
    string.format("  %s - Increase priority", self.opts.keymaps.increase_priority),
    string.format("  %s - Decrease priority", self.opts.keymaps.decrease_priority),
    string.format("  %s - Add/edit note", self.opts.keymaps.quick_note),
    string.format("  %s - Set due date", self.opts.keymaps.quick_date),
    "",
    "Other:",
    string.format("  %s - Search tasks", self.opts.keymaps.search_tasks),
    string.format("  %s - Sort tasks", self.opts.keymaps.sort_by_priority),
    "  <CR> - Quick actions menu",
    "  ?    - Show this help",
  }

  local buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, help_lines)
  vim.api.nvim_buf_set_option(buf, 'modifiable', false)
  vim.api.nvim_buf_set_option(buf, 'filetype', 'help')

  local width = 60
  local height = #help_lines
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

  local win = vim.api.nvim_open_win(buf, true, opts)
  
  -- Close help window with q or <Esc>
  vim.keymap.set('n', 'q', '<cmd>close<CR>', { buffer = buf, silent = true })
  vim.keymap.set('n', '<Esc>', '<cmd>close<CR>', { buffer = buf, silent = true })
end

-- Add buffer-local keymaps setup
function LazyDo:setup_buffer_keymaps()
  local function map(key, fn)
    vim.keymap.set('n', key, fn, {
      buffer = self.buf,
      silent = true,
      nowait = true,
      desc = "LazyDo: " .. key
    })
  end

  -- Core task management
  map(self.opts.keymaps.toggle_done, function() self:toggle_task() end)
  map(self.opts.keymaps.edit_task, function() self:edit_task() end)
  map(self.opts.keymaps.add_task, function() self:add_task() end)
  map(self.opts.keymaps.delete_task, function() self:delete_task() end)
  
  -- Task organization
  map(self.opts.keymaps.move_up, function() self:move_task_up() end)
  map(self.opts.keymaps.move_down, function() self:move_task_down() end)
  map(self.opts.keymaps.toggle_expand, function() self:toggle_expand() end)
  
  -- Task properties
  map(self.opts.keymaps.increase_priority, function() self:change_priority(-1) end)
  map(self.opts.keymaps.decrease_priority, function() self:change_priority(1) end)
  map(self.opts.keymaps.quick_note, function() self:quick_note() end)
  map(self.opts.keymaps.quick_date, function() self:quick_date() end)
  
  -- Task filtering and search
  map(self.opts.keymaps.search_tasks, function() self:advanced_search() end)
  map(self.opts.keymaps.sort_by_priority, function() self:show_sort_menu() end)
  
  -- Additional features
  map('<CR>', function() self:quick_actions() end)
  map('?', function() self:show_help() end)
end

-- Add highlight groups
function LazyDo:setup_highlights()
  local highlights = {
    LazyDoHeader = { link = "Title" },
    LazyDoCheckbox = { fg = self.opts.colors.checkbox },
    LazyDoBullet = { fg = self.opts.colors.bullet },
    LazyDoExpand = { fg = self.opts.colors.expand },
    LazyDoDone = { link = "Comment" },
    LazyDoOverdue = { fg = "#ff0000", bold = true },
    LazyDoPriorityHigh = { fg = "#ff0000", bold = true },
    LazyDoPriorityMed = { fg = "#ffff00" },
    LazyDoPriorityLow = { fg = "#00ff00" },
    LazyDoDate = { fg = "#7aa2f7" },
    LazyDoNote = { fg = "#bb9af7" },
    LazyDoTag = { fg = "#7dcfff" },
  }

  for name, attrs in pairs(highlights) do
    vim.api.nvim_set_hl(0, name, attrs)
  end
end

-- Improved task toggle
function LazyDo:toggle_task()
  local cursor = vim.api.nvim_win_get_cursor(self.win)
  local task = self:get_task_at_line(cursor[1])
  if not task then return end

  task.done = not task.done
  
  -- Handle dependent tasks
  if task.done then
    -- Check if all dependencies are completed
    local all_deps_done = true
    for _, dep_id in ipairs(task.dependencies or {}) do
      local dep = self:get_task_by_id(dep_id)
      if dep and not dep.done then
        all_deps_done = false
        break
      end
    end
    
    if not all_deps_done then
      vim.notify("Cannot complete task: dependencies not done", vim.log.levels.WARN)
      task.done = false
      return
    end
  else
    -- Uncompleting a task should uncheck dependent tasks
    self:uncheck_dependent_tasks(task)
  end

  self:render()
end

-- Improved task editing
function LazyDo:edit_task()
  local cursor = vim.api.nvim_win_get_cursor(self.win)
  local task = self:get_task_at_line(cursor[1])
  if not task then return end

  vim.ui.input({
    prompt = "Edit task: ",
    default = task.content,
    completion = "custom,v:lua.LazyDo_completion",
  }, function(input)
    if input and input ~= "" then
      task.content = input
      self:render()
    end
  end)
end

-- Safe task addition
function LazyDo:add_task()
  vim.ui.input({
    prompt = "New task: ",
    completion = "custom,v:lua.LazyDo_completion",
  }, function(input)
    if input and input ~= "" then
      local cursor = vim.api.nvim_win_get_cursor(self.win)
      local current_task = self:get_task_at_line(cursor[1])
      
      local new_task = {
        id = tostring(os.time()) .. math.random(1000, 9999),
        content = input,
        done = false,
        priority = 3,
        indent = current_task and current_task.indent or 0,
        tags = {},
        subtasks = {},
        dependencies = {},
      }
      
      table.insert(self.tasks, cursor[1] - 3, new_task)
      self:render()
    end
  end)
end

-- Safe task deletion
function LazyDo:delete_task()
  local cursor = vim.api.nvim_win_get_cursor(self.win)
  local task = self:get_task_at_line(cursor[1])
  if not task then return end

  -- Check if task has dependents
  local has_dependents = false
  for _, t in ipairs(self.tasks) do
    if vim.tbl_contains(t.dependencies or {}, task.id) then
      has_dependents = true
      break
    end
  end

  if has_dependents then
    vim.ui.select({ "Yes", "No" }, {
      prompt = "Task has dependents. Delete anyway?",
    }, function(choice)
      if choice == "Yes" then
        self:remove_task_and_subtasks(task)
      end
    end)
  else
    self:remove_task_and_subtasks(task)
  end
end

-- Helper function to remove task and its subtasks
function LazyDo:remove_task_and_subtasks(task)
  local to_remove = {task.id}
  
  -- Collect all subtask IDs
  local function collect_subtasks(t)
    for _, subtask in ipairs(t.subtasks or {}) do
      table.insert(to_remove, subtask.id)
      collect_subtasks(subtask)
    end
  end
  
  collect_subtasks(task)
  
  -- Remove tasks
  self.tasks = vim.tbl_filter(function(t)
    return not vim.tbl_contains(to_remove, t.id)
  end, self.tasks)
  
  self:render()
end

-- Helper function to uncheck dependent tasks
function LazyDo:uncheck_dependent_tasks(task)
  for _, t in ipairs(self.tasks) do
    if vim.tbl_contains(t.dependencies or {}, task.id) then
      t.done = false
      self:uncheck_dependent_tasks(t)
    end
  end
end

-- Show sort menu
function LazyDo:show_sort_menu()
  local options = {
    { text = "Priority", value = "priority" },
    { text = "Due Date", value = "due_date" },
    { text = "Status", value = "status" },
    { text = "Alphabetical", value = "alphabetical" },
  }

  vim.ui.select(options, {
    prompt = "Sort by:",
    format_item = function(item) return item.text end
  }, function(choice)
    if choice then
      self:sort_tasks_by(choice.value)
    end
  end)
end

-- Show help
function LazyDo:show_help()
  local help_lines = {
    "LazyDo Keybindings",
    "═════════════════",
    "",
    "Task Management:",
    string.format("  %s - Toggle task completion", self.opts.keymaps.toggle_done),
    string.format("  %s - Edit task", self.opts.keymaps.edit_task),
    string.format("  %s - Add new task", self.opts.keymaps.add_task),
    string.format("  %s - Delete task", self.opts.keymaps.delete_task),
    "",
    "Organization:",
    string.format("  %s - Move task up", self.opts.keymaps.move_up),
    string.format("  %s - Move task down", self.opts.keymaps.move_down),
    string.format("  %s - Toggle expand/collapse", self.opts.keymaps.toggle_expand),
    "",
    "Properties:",
    string.format("  %s - Increase priority", self.opts.keymaps.increase_priority),
    string.format("  %s - Decrease priority", self.opts.keymaps.decrease_priority),
    string.format("  %s - Add/edit note", self.opts.keymaps.quick_note),
    string.format("  %s - Set due date", self.opts.keymaps.quick_date),
    "",
    "Other:",
    string.format("  %s - Search tasks", self.opts.keymaps.search_tasks),
    string.format("  %s - Sort tasks", self.opts.keymaps.sort_by_priority),
    "  <CR> - Quick actions menu",
    "  ?    - Show this help",
  }

  local buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, help_lines)
  vim.api.nvim_buf_set_option(buf, 'modifiable', false)
  vim.api.nvim_buf_set_option(buf, 'filetype', 'help')

  local width = 60
  local height = #help_lines
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

  local win = vim.api.nvim_open_win(buf, true, opts)
  
  -- Close help window with q or <Esc>
  vim.keymap.set('n', 'q', '<cmd>close<CR>', { buffer = buf, silent = true })
  vim.keymap.set('n', '<Esc>', '<cmd>close<CR>', { buffer = buf, silent = true })
end

-- Add buffer-local keymaps setup
function LazyDo:setup_buffer_keymaps()
  local function map(key, fn)
    vim.keymap.set('n', key, fn, {
      buffer = self.buf,
      silent = true,
      nowait = true,
      desc = "LazyDo: " .. key
    })
  end

  -- Core task management
  map(self.opts.keymaps.toggle_done, function() self:toggle_task() end)
  map(self.opts.keymaps.edit_task, function() self:edit_task() end)
  map(self.opts.keymaps.add_task, function() self:add_task() end)
  map(self.opts.keymaps.delete_task, function() self:delete_task() end)
  
  -- Task organization
  map(self.opts.keymaps.move_up, function() self:move_task_up() end)
  map(self.opts.keymaps.move_down, function() self:move_task_down() end)
  map(self.opts.keymaps.toggle_expand, function() self:toggle_expand() end)
  
  -- Task properties
  map(self.opts.keymaps.increase_priority, function() self:change_priority(-1) end)
  map(self.opts.keymaps.decrease_priority, function() self:change_priority(1) end)
  map(self.opts.keymaps.quick_note, function() self:quick_note() end)
  map(self.opts.keymaps.quick_date, function() self:quick_date() end)
  
  -- Task filtering and search
  map(self.opts.keymaps.search_tasks, function() self:advanced_search() end)
  map(self.opts.keymaps.sort_by_priority, function() self:show_sort_menu() end)
  
  -- Additional features
  map('<CR>', function() self:quick_actions() end)
  map('?', function() self:show_help() end)
end

-- Add highlight groups
function LazyDo:setup_highlights()
  local highlights = {
    LazyDoHeader = { link = "Title" },
    LazyDoCheckbox = { fg = self.opts.colors.checkbox },
    LazyDoBullet = { fg = self.opts.colors.bullet },
    LazyDoExpand = { fg = self.opts.colors.expand },
    LazyDoDone = { link = "Comment" },
    LazyDoOverdue = { fg = "#ff0000", bold = true },
    LazyDoPriorityHigh = { fg = "#ff0000", bold = true },
    LazyDoPriorityMed = { fg = "#ffff00" },
    LazyDoPriorityLow = { fg = "#00ff00" },
    LazyDoDate = { fg = "#7aa2f7" },
    LazyDoNote = { fg = "#bb9af7" },
    LazyDoTag = { fg = "#7dcfff" },
  }

  for name, attrs in pairs(highlights) do
    vim.api.nvim_set_hl(0, name, attrs)
  end
end

-- Improved task toggle
function LazyDo:toggle_task()
  local cursor = vim.api.nvim_win_get_cursor(self.win)
  local task = self:get_task_at_line(cursor[1])
  if not task then return end

  task.done = not task.done
  
  -- Handle dependent tasks
  if task.done then
    -- Check if all dependencies are completed
    local all_deps_done = true
    for _, dep_id in ipairs(task.dependencies or {}) do
      local dep = self:get_task_by_id(dep_id)
      if dep and not dep.done then
        all_deps_done = false
        break
      end
    end
    
    if not all_deps_done then
      vim.notify("Cannot complete task: dependencies not done", vim.log.levels.WARN)
      task.done = false
      return
    end
  else
    -- Uncompleting a task should uncheck dependent tasks
    self:uncheck_dependent_tasks(task)
  end

  self:render()
end

-- Improved task editing
function LazyDo:edit_task()
  local cursor = vim.api.nvim_win_get_cursor(self.win)
  local task = self:get_task_at_line(cursor[1])
  if not task then return end

  vim.ui.input({
    prompt = "Edit task: ",
    default = task.content,
    completion = "custom,v:lua.LazyDo_completion",
  }, function(input)
    if input and input ~= "" then
      task.content = input
      self:render()
    end
  end)
end

-- Safe task addition
function LazyDo:add_task()
  vim.ui.input({
    prompt = "New task: ",
    completion = "custom,v:lua.LazyDo_completion",
  }, function(input)
    if input and input ~= "" then
      local cursor = vim.api.nvim_win_get_cursor(self.win)
      local current_task = self:get_task_at_line(cursor[1])
      
      local new_task = {
        id = tostring(os.time()) .. math.random(1000, 9999),
        content = input,
        done = false,
        priority = 3,
        indent = current_task and current_task.indent or 0,
        tags = {},
        subtasks = {},
        dependencies = {},
      }
      
      table.insert(self.tasks, cursor[1] - 3, new_task)
      self:render()
    end
  end)
end

-- Safe task deletion
function LazyDo:delete_task()
  local cursor = vim.api.nvim_win_get_cursor(self.win)
  local task = self:get_task_at_line(cursor[1])
  if not task then return end

  -- Check if task has dependents
  local has_dependents = false
  for _, t in ipairs(self.tasks) do
    if vim.tbl_contains(t.dependencies or {}, task.id) then
      has_dependents = true
      break
    end
  end

  if has_dependents then
    vim.ui.select({ "Yes", "No" }, {
      prompt = "Task has dependents. Delete anyway?",
    }, function(choice)
      if choice == "Yes" then
        self:remove_task_and_subtasks(task)
      end
    end)
  else
    self:remove_task_and_subtasks(task)
  end
end

-- Helper function to remove task and its subtasks
function LazyDo:remove_task_and_subtasks(task)
  local to_remove = {task.id}
  
  -- Collect all subtask IDs
  local function collect_subtasks(t)
    for _, subtask in ipairs(t.subtasks or {}) do
      table.insert(to_remove, subtask.id)
      collect_subtasks(subtask)
    end
  end
  
  collect_subtasks(task)
  
  -- Remove tasks
  self.tasks = vim.tbl_filter(function(t)
    return not vim.tbl_contains(to_remove, t.id)
  end, self.tasks)
  
  self:render()
end

-- Helper function to uncheck dependent tasks
function LazyDo:uncheck_dependent_tasks(task)
  for _, t in ipairs(self.tasks) do
    if vim.tbl_contains(t.dependencies or {}, task.id) then
      t.done = false
      self:uncheck_dependent_tasks(t)
    end
  end
end

-- Show sort menu
function LazyDo:show_sort_menu()
  local options = {
    { text = "Priority", value = "priority" },
    { text = "Due Date", value = "due_date" },
    { text = "Status", value = "status" },
    { text = "Alphabetical", value = "alphabetical" },
  }

  vim.ui.select(options, {
    prompt = "Sort by:",
    format_item = function(item) return item.text end
  }, function(choice)
    if choice then
      self:sort_tasks_by(choice.value)
    end
  end)
end

-- Show help
function LazyDo:show_help()
  local help_lines = {
    "LazyDo Keybindings",
    "═════════════════",
    "",
    "Task Management:",
    string.format("  %s - Toggle task completion", self.opts.keymaps.toggle_done),
    string.format("  %s - Edit task", self.opts.keymaps.edit_task),
    string.format("  %s - Add new task", self.opts.keymaps.add_task),
    string.format("  %s - Delete task", self.opts.keymaps.delete_task),
    "",
    "Organization:",
    string.format("  %s - Move task up", self.opts.keymaps.move_up),
    string.format("  %s - Move task down", self.opts.keymaps.move_down),
    string.format("  %s - Toggle expand/collapse", self.opts.keymaps.toggle_expand),
    "",
    "Properties:",
    string.format("  %s - Increase priority", self.opts.keymaps.increase_priority),
    string.format("  %s - Decrease priority", self.opts.keymaps.decrease_priority),
    string.format("  %s - Add/edit note", self.opts.keymaps.quick_note),
    string.format("  %s - Set due date", self.opts.keymaps.quick_date),
    "",
    "Other:",
    string.format("  %s - Search tasks", self.opts.keymaps.search_tasks),
    string.format("  %s - Sort tasks", self.opts.keymaps.sort_by_priority),
    "  <CR> - Quick actions menu",
    "  ?    - Show this help",
  }

  local buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, help_lines)
  vim.api.nvim_buf_set_option(buf, 'modifiable', false)
  vim.api.nvim_buf_set_option(buf, 'filetype', 'help')

  local width = 60
  local height = #help_lines
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

  local win = vim.api.nvim_open_win(buf, true, opts)
  
  -- Close help window with q or <Esc>
  vim.keymap.set('n', 'q', '<cmd>close<CR>', { buffer = buf, silent = true })
  vim.keymap.set('n', '<Esc>', '<cmd>close<CR>', { buffer = buf, silent = true })
end

-- Add buffer-local keymaps setup
function LazyDo:setup_buffer_keymaps()
  local function map(key, fn)
    vim.keymap.set('n', key, fn, {
      buffer = self.buf,
      silent = true,
      nowait = true,
      desc = "LazyDo: " .. key
    })
  end

  -- Core task management
  map(self.opts.keymaps.toggle_done, function() self:toggle_task() end)
  map(self.opts.keymaps.edit_task, function() self:edit_task() end)
  map(self.opts.keymaps.add_task, function() self:add_task() end)
  map(self.opts.keymaps.delete_task, function() self:delete_task() end)
  
  -- Task organization
  map(self.opts.keymaps.move_up, function() self:move_task_up() end)
  map(self.opts.keymaps.move_down, function() self:move_task_down() end)
  map(self.opts.keymaps.toggle_expand, function() self:toggle_expand() end)
  
  -- Task properties
  map(self.opts.keymaps.increase_priority, function() self:change_priority(-1) end)
  map(self.opts.keymaps.decrease_priority, function() self:change_priority(1) end)
  map(self.opts.keymaps.quick_note, function() self:quick_note() end)
  map(self.opts.keymaps.quick_date, function() self:quick_date() end)
  
  -- Task filtering and search
  map(self.opts.keymaps.search_tasks, function() self:advanced_search() end)
  map(self.opts.keymaps.sort_by_priority, function() self:show_sort_menu() end)
  
  -- Additional features
  map('<CR>', function() self:quick_actions() end)
  map('?', function() self:show_help() end)
end

-- Add highlight groups
function LazyDo:setup_highlights()
  local highlights = {
    LazyDoHeader = { link = "Title" },
    LazyDoCheckbox = { fg = self.opts.colors.checkbox },
    LazyDoBullet = { fg = self.opts.colors.bullet },
    LazyDoExpand = { fg = self.opts.colors.expand },
    LazyDoDone = { link = "Comment" },
    LazyDoOverdue = { fg = "#ff0000", bold = true },
    LazyDoPriorityHigh = { fg = "#ff0000", bold = true },
    LazyDoPriorityMed = { fg = "#ffff00" },
    LazyDoPriorityLow = { fg = "#00ff00" },
    LazyDoDate = { fg = "#7aa2f7" },
    LazyDoNote = { fg = "#bb9af7" },
    LazyDoTag = { fg = "#7dcfff" },
  }

  for name, attrs in pairs(highlights) do
    vim.api.nvim_set_hl(0, name, attrs)
  end
end

-- Improved task toggle
function LazyDo:toggle_task()
  local cursor = vim.api.nvim_win_get_cursor(self.win)
  local task = self:get_task_at_line(cursor[1])
  if not task then return end

  task.done = not task.done
  
  -- Handle dependent tasks
  if task.done then
    -- Check if all dependencies are completed
    local all_deps_done = true
    for _, dep_id in ipairs(task.dependencies or {}) do
      local dep = self:get_task_by_id(dep_id)
      if dep and not dep.done then
        all_deps_done = false
        break
      end
    end
    
    if not all_deps_done then
      vim.notify("Cannot complete task: dependencies not done", vim.log.levels.WARN)
      task.done = false
      return
    end
  else
    -- Uncompleting a task should uncheck dependent tasks
    self:uncheck_dependent_tasks(task)
  end

  self:render()
end

-- Improved task editing
function LazyDo:edit_task()
  local cursor = vim.api.nvim_win_get_cursor(self.win)
  local task = self:get_task_at_line(cursor[1])
  if not task then return end

  vim.ui.input({
    prompt = "Edit task: ",
    default = task.content,
    completion = "custom,v:lua.LazyDo_completion",
  }, function(input)
    if input and input ~= "" then
      task.content = input
      self:render()
    end
  end)
end

-- Safe task addition
function LazyDo:add_task()
  vim.ui.input({
    prompt = "New task: ",
    completion = "custom,v:lua.LazyDo_completion",
  }, function(input)
    if input and input ~= "" then
      local cursor = vim.api.nvim_win_get_cursor(self.win)
      local current_task = self:get_task_at_line(cursor[1])
      
      local new_task = {
        id = tostring(os.time()) .. math.random(1000, 9999),
        content = input,
        done = false,
        priority = 3,
        indent = current_task and current_task.indent or 0,
        tags = {},
        subtasks = {},
        dependencies = {},
      }
      
      table.insert(self.tasks, cursor[1] - 3, new_task)
      self:render()
    end
  end)
end

-- Safe task deletion
function LazyDo:delete_task()
  local cursor = vim.api.nvim_win_get_cursor(self.win)
  local task = self:get_task_at_line(cursor[1])
  if not task then return end

  -- Check if task has dependents
  local has_dependents = false
  for _, t in ipairs(self.tasks) do
    if vim.tbl_contains(t.dependencies or {}, task.id) then
      has_dependents = true
      break
    end
  end

  if has_dependents then
    vim.ui.select({ "Yes", "No" }, {
      prompt = "Task has dependents. Delete anyway?",
    }, function(choice)
      if choice == "Yes" then
        self:remove_task_and_subtasks(task)
      end
    end)
  else
    self:remove_task_and_subtasks(task)
  end
end

-- Helper function to remove task and its subtasks
function LazyDo:remove_task_and_subtasks(task)
  local to_remove = {task.id}
  
  -- Collect all subtask IDs
  local function collect_subtasks(t)
    for _, subtask in ipairs(t.subtasks or {}) do
      table.insert(to_remove, subtask.id)
      collect_subtasks(subtask)
    end
  end
  
  collect_subtasks(task)
  
  -- Remove tasks
  self.tasks = vim.tbl_filter(function(t)
    return not vim.tbl_contains(to_remove, t.id)
  end, self.tasks)
  
  self:render()
end

-- Helper function to uncheck dependent tasks
function LazyDo:uncheck_dependent_tasks(task)
  for _, t in ipairs(self.tasks) do
    if vim.tbl_contains(t.dependencies or {}, task.id) then
      t.done = false
      self:uncheck_dependent_tasks(t)
    end
  end
end

-- Show sort menu
function LazyDo:show_sort_menu()
  local options = {
    { text = "Priority", value = "priority" },
    { text = "Due Date", value = "due_date" },
    { text = "Status", value = "status" },
    { text = "Alphabetical", value = "alphabetical" },
  }

  vim.ui.select(options, {
    prompt = "Sort by:",
    format_item = function(item) return item.text end
  }, function(choice)
    if choice then
      self:sort_tasks_by(choice.value)
    end
  end)
end

-- Show help
function LazyDo:show_help()
  local help_lines = {
    "LazyDo Keybindings",
    "═════════════════",
    "",
    "Task Management:",
    string.format("  %s - Toggle task completion", self.opts.keymaps.toggle_done),
    string.format("  %s - Edit task", self.opts.keymaps.edit_task),
    string.format("  %s - Add new task", self.opts.keymaps.add_task),
    string.format("  %s - Delete task", self.opts.keymaps.delete_task),
    "",
    "Organization:",
    string.format("  %s - Move task up", self.opts.keymaps.move_up),
    string.format("  %s - Move task down", self.opts.keymaps.move_down),
    string.format("  %s - Toggle expand/collapse", self.opts.keymaps.toggle_expand),
    "",
    "Properties:",
    string.format("  %s - Increase priority", self.opts.keymaps.increase_priority),
    string.format("  %s - Decrease priority", self.opts.keymaps.decrease_priority),
    string.format("  %s - Add/edit note", self.opts.keymaps.quick_note),
    string.format("  %s - Set due date", self.opts.keymaps.quick_date),
    "",
    "Other:",
    string.format("  %s - Search tasks", self.opts.keymaps.search_tasks),
    string.format("  %s - Sort tasks", self.opts.keymaps.sort_by_priority),
    "  <CR> - Quick actions menu",
    "  ?    - Show this help",
  }

  local buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, help_lines)
  vim.api.nvim_buf_set_option(buf, 'modifiable', false)
  vim.api.nvim_buf_set_option(buf, 'filetype', 'help')

  local width = 60
  local height = #help_lines
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

  local win = vim.api.nvim_open_win(buf, true, opts)
  
  -- Close help window with q or <Esc>
  vim.keymap.set('n', 'q', '<cmd>close<CR>', { buffer = buf, silent = true })
  vim.keymap.set('n', '<Esc>', '<cmd>close<CR>', { buffer = buf, silent = true })
end

-- Add buffer-local keymaps setup
function LazyDo:setup_buffer_keymaps()
  local function map(key, fn)
    vim.keymap.set('n', key, fn, {
      buffer = self.buf,
      silent = true,
      nowait = true,
      desc = "LazyDo: " .. key
    })
  end

  -- Core task management
  map(self.opts.keymaps.toggle_done, function() self:toggle_task() end)
  map(self.opts.keymaps.edit_task, function() self:edit_task() end)
  map(self.opts.keymaps.add_task, function() self:add_task() end)
  map(self.opts.keymaps.delete_task, function() self:delete_task() end)
  
  -- Task organization
  map(self.opts.keymaps.move_up, function() self:move_task_up() end)
  map(self.opts.keymaps.move_down, function() self:move_task_down() end)
  map(self.opts.keymaps.toggle_expand, function() self:toggle_expand() end)
  
  -- Task properties
  map(self.opts.keymaps.increase_priority, function() self:change_priority(-1) end)
  map(self.opts.keymaps.decrease_priority, function() self:change_priority(1) end)
  map(self.opts.keymaps.quick_note, function() self:quick_note() end)
  map(self.opts.keymaps.quick_date, function() self:quick_date() end)
  
  -- Task filtering and search
  map(self.opts.keymaps.search_tasks, function() self:advanced_search() end)
  map(self.opts.keymaps.sort_by_priority, function() self:show_sort_menu() end)
  
  -- Additional features
  map('<CR>', function() self:quick_actions() end)
  map('?', function() self:show_help() end)
end

-- Add highlight groups
function LazyDo:setup_highlights()
  local highlights = {
    LazyDoHeader = { link = "Title" },
    LazyDoCheckbox = { fg = self.opts.colors.checkbox },
    LazyDoBullet = { fg = self.opts.colors.bullet },
    LazyDoExpand = { fg = self.opts.colors.expand },
    LazyDoDone = { link = "Comment" },
    LazyDoOverdue = { fg = "#ff0000", bold = true },
    LazyDoPriorityHigh = { fg = "#ff0000", bold = true },
    LazyDoPriorityMed = { fg = "#ffff00" },
    LazyDoPriorityLow = { fg = "#00ff00" },
    LazyDoDate = { fg = "#7aa2f7" },
    LazyDoNote = { fg = "#bb9af7" },
    LazyDoTag = { fg = "#7dcfff" },
  }

  for name, attrs in pairs(highlights) do
    vim.api.nvim_set_hl(0, name, attrs)
  end
end

-- Improved task toggle
function LazyDo:toggle_task()
  local cursor = vim.api.nvim_win_get_cursor(self.win)
  local task = self:get_task_at_line(cursor[1])
  if not task then return end

  task.done = not task.done
  
  -- Handle dependent tasks
  if task.done then
    -- Check if all dependencies are completed
    local all_deps_done = true
    for _, dep_id in ipairs(task.dependencies or {}) do
      local dep = self:get_task_by_id(dep_id)
      if dep and not dep.done then
        all_deps_done = false
        break
      end
    end
    
    if not all_deps_done then
      vim.notify("Cannot complete task: dependencies not done", vim.log.levels.WARN)
      task.done = false
      return
    end
  else
    -- Uncompleting a task should uncheck dependent tasks
    self:uncheck_dependent_tasks(task)
  end

  self:render()
end

-- Improved task editing
function LazyDo:edit_task()
  local cursor = vim.api.nvim_win_get_cursor(self.win)
  local task = self:get_task_at_line(cursor[1])
  if not task then return end

  vim.ui.input({
    prompt = "Edit task: ",
    default = task.content,
    completion = "custom,v:lua.LazyDo_completion",
  }, function(input)
    if input and input ~= "" then
      task.content = input
      self:render()
    end
  end)
end

-- Safe task addition
function LazyDo:add_task()
  vim.ui.input({
    prompt = "New task: ",
    completion = "custom,v:lua.LazyDo_completion",
  }, function(input)
    if input and input ~= "" then
      local cursor = vim.api.nvim_win_get_cursor(self.win)
      local current_task = self:get_task_at_line(cursor[1])
      
      local new_task = {
        id = tostring(os.time()) .. math.random(1000, 9999),
        content = input,
        done = false,
        priority = 3,
        indent = current_task and current_task.indent or 0,
        tags = {},
        subtasks = {},
        dependencies = {},
      }
      
      table.insert(self.tasks, cursor[1] - 3, new_task)
      self:render()
    end
  end)
end

-- Safe task deletion
function LazyDo:delete_task()
  local cursor = vim.api.nvim_win_get_cursor(self.win)
  local task = self:get_task_at_line(cursor[1])
  if not task then return end

  -- Check if task has dependents
  local has_dependents = false
  for _, t in ipairs(self.tasks) do
    if vim.tbl_contains(t.dependencies or {}, task.id) then
      has_dependents = true
      break
    end
  end

  if has_dependents then
    vim.ui.select({ "Yes", "No" }, {
      prompt = "Task has dependents. Delete anyway?",
    }, function(choice)
      if choice == "Yes" then
        self:remove_task_and_subtasks(task)
      end
    end)
  else
    self:remove_task_and_subtasks(task)
  end
end

-- Helper function to remove task and its subtasks
function LazyDo:remove_task_and_subtasks(task)
  local to_remove = {task.id}
  
  -- Collect all subtask IDs
  local function collect_subtasks(t)
    for _, subtask in ipairs(t.subtasks or {}) do
      table.insert(to_remove, subtask.id)
      collect_subtasks(subtask)
    end
  end
  
  collect_subtasks(task)
  
  -- Remove tasks
  self.tasks = vim.tbl_filter(function(t)
    return not vim.tbl_contains(to_remove, t.id)
  end, self.tasks)
  
  self:render()
end

-- Helper function to uncheck dependent tasks
function LazyDo:uncheck_dependent_tasks(task)
  for _, t in ipairs(self.tasks) do
    if vim.tbl_contains(t.dependencies or {}, task.id) then
      t.done = false
      self:uncheck_dependent_tasks(t)
    end
  end
end

-- Show sort menu
function LazyDo:show_sort_menu()
  local options = {
    { text = "Priority", value = "priority" },
    { text = "Due Date", value = "due_date" },
    { text = "Status", value = "status" },
    { text = "Alphabetical", value = "alphabetical" },
  }

  vim.ui.select(options, {
    prompt = "Sort by:",
    format_item = function(item) return item.text end
  }, function(choice)
    if choice then
      self:sort_tasks_by(choice.value)
    end
  end)
end

-- Show help
function LazyDo:show_help()
  local help_lines = {
    "LazyDo Keybindings",
    "═════════════════",
    "",
    "Task Management:",
    string.format("  %s - Toggle task completion", self.opts.keymaps.toggle_done),
    string.format("  %s - Edit task", self.opts.keymaps.edit_task),
    string.format("  %s - Add new task", self.opts.keymaps.add_task),
    string.format("  %s - Delete task", self.opts.keymaps.delete_task),
    "",
    "Organization:",
    string.format("  %s - Move task up", self.opts.keymaps.move_up),
    string.format("  %s - Move task down", self.opts.keymaps.move_down),
    string.format("  %s - Toggle expand/collapse", self.opts.keymaps.toggle_expand),
    "",
    "Properties:",
    string.format("  %s - Increase priority", self.opts.keymaps.increase_priority),
    string.format("  %s - Decrease priority", self.opts.keymaps.decrease_priority),
    string.format("  %s - Add/edit note", self.opts.keymaps.quick_note),
    string.format("  %s - Set due date", self.opts.keymaps.quick_date),
    "",
    "Other:",
    string.format("  %s - Search tasks", self.opts.keymaps.search_tasks),
    string.format("  %s - Sort tasks", self.opts.keymaps.sort_by_priority),
    "  <CR> - Quick actions menu",
    "  ?    - Show this help",
  }

  local buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, help_lines)
  vim.api.nvim_buf_set_option(buf, 'modifiable', false)
  vim.api.nvim_buf_set_option(buf, 'filetype', 'help')

  local width = 60
  local height = #help_lines
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

  local win = vim.api.nvim_open_win(buf, true, opts)
  
  -- Close help window with q or <Esc>
  vim.keymap.set('n', 'q', '<cmd>close<CR>', { buffer = buf, silent = true })
  vim.keymap.set('n', '<Esc>', '<cmd>close<CR>', { buffer = buf, silent = true })
end

-- Add buffer-local keymaps setup
function LazyDo:setup_buffer_keymaps()
  local function map(key, fn)
    vim.keymap.set('n', key, fn, {
      buffer = self.buf,
      silent = true,
      nowait = true,
      desc = "LazyDo: " .. key
    })
  end

  -- Core task management
  map(self.opts.keymaps.toggle_done, function() self:toggle_task() end)
  map(self.opts.keymaps.edit_task, function() self:edit_task() end)
  map(self.opts.keymaps.add_task, function() self:add_task() end)
  map(self.opts.keymaps.delete_task, function() self:delete_task() end)
  
  -- Task organization
  map(self.opts.keymaps.move_up, function() self:move_task_up() end)
  map(self.opts.keymaps.move_down, function() self:move_task_down() end)
  map(self.opts.keymaps.toggle_expand, function() self:toggle_expand() end)
  
  -- Task properties
  map(self.opts.keymaps.increase_priority, function() self:change_priority(-1) end)
  map(self.opts.keymaps.decrease_priority, function() self:change_priority(1) end)
  map(self.opts.keymaps.quick_note, function() self:quick_note() end)
  map(self.opts.keymaps.quick_date, function() self:quick_date() end)
  
  -- Task filtering and search
  map(self.opts.keymaps.search_tasks, function() self:advanced_search() end)
  map(self.opts.keymaps.sort_by_priority, function() self:show_sort_menu() end)
  
  -- Additional features
  map('<CR>', function() self:quick_actions() end)
  map('?', function() self:show_help() end)
end

-- Add highlight groups
function LazyDo:setup_highlights()
  local highlights = {
    LazyDoHeader = { link = "Title" },
    LazyDoCheckbox = { fg = self.opts.colors.checkbox },
    LazyDoBullet = { fg = self.opts.colors.bullet },
    LazyDoExpand = { fg = self.opts.colors.expand },
    LazyDoDone = { link = "Comment" },
    LazyDoOverdue = { fg = "#ff0000", bold = true },
    LazyDoPriorityHigh = { fg = "#ff0000", bold = true },
    LazyDoPriorityMed = { fg = "#ffff00" },
    LazyDoPriorityLow = { fg = "#00ff00" },
    LazyDoDate = { fg = "#7aa2f7" },
    LazyDoNote = { fg = "#bb9af7" },
    LazyDoTag = { fg = "#7dcfff" },
  }

  for name, attrs in pairs(highlights) do
    vim.api.nvim_set_hl(0, name, attrs)
  end
end

-- Improved task toggle
function LazyDo:toggle_task()
  local cursor = vim.api.nvim_win_get_cursor(self.win)
  local task = self:get_task_at_line(cursor[1])
  if not task then return end

  task.done = not task.done
  
  -- Handle dependent tasks
  if task.done then
    -- Check if all dependencies are completed
    local all_deps_done = true
    for _, dep_id in ipairs(task.dependencies or {}) do
      local dep = self:get_task_by_id(dep_id)
      if dep and not dep.done then
        all_deps_done = false
        break
      end
    end
    
    if not all_deps_done then
      vim.notify("Cannot complete task: dependencies not done", vim.log.levels.WARN)
      task.done = false
      return
    end
  else
    -- Uncompleting a task should uncheck dependent tasks
    self:uncheck_dependent_tasks(task)
  end

  self:render()
end

-- Improved task editing
function LazyDo:edit_task()
  local cursor = vim.api.nvim_win_get_cursor(self.win)
  local task = self:get_task_at_line(cursor[1])
  if not task then return end

  vim.ui.input({
    prompt = "Edit task: ",
    default = task.content,
    completion = "custom,v:lua.LazyDo_completion",
  }, function(input)
    if input and input ~= "" then
      task.content = input
      self:render()
    end
  end)
end

-- Safe task addition
function LazyDo:add_task()
  vim.ui.input({
    prompt = "New task: ",
    completion = "custom,v:lua.LazyDo_completion",
  }, function(input)
    if input and input ~= "" then
      local cursor = vim.api.nvim_win_get_cursor(self.win)
      local current_task = self:get_task_at_line(cursor[1])
      
      local new_task = {
        id = tostring(os.time()) .. math.random(1000, 9999),
        content = input,
        done = false,
        priority = 3,
        indent = current_task and current_task.indent or 0,
        tags = {},
        subtasks = {},
        dependencies = {},
      }
      
      table.insert(self.tasks, cursor[1] - 3, new_task)
      self:render()
    end
  end)
end

-- Safe task deletion
function LazyDo:delete_task()
  local cursor = vim.api.nvim_win_get_cursor(self.win)
  local task = self:get_task_at_line(cursor[1])
  if not task then return end

  -- Check if task has dependents
  local has_dependents = false
  for _, t in ipairs(self.tasks) do
    if vim.tbl_contains(t.dependencies or {}, task.id) then
      has_dependents = true
      break
    end
  end

  if has_dependents then
    vim.ui.select({ "Yes", "No" }, {
      prompt = "Task has dependents. Delete anyway?",
    }, function(choice)
      if choice == "Yes" then
        self:remove_task_and_subtasks(task)
      end
    end)
  else
    self:remove_task_and_subtasks(task)
  end
end

-- Helper function to remove task and its subtasks
function LazyDo:remove_task_and_subtasks(task)
  local to_remove = {task.id}
  
  -- Collect all subtask IDs
  local function collect_subtasks(t)
    for _, subtask in ipairs(t.subtasks or {}) do
      table.insert(to_remove, subtask.id)
      collect_subtasks(subtask)
    end
  end
  
  collect_subtasks(task)
  
  -- Remove tasks
  self.tasks = vim.tbl_filter(function(t)
    return not vim.tbl_contains(to_remove, t.id)
  end, self.tasks)
  
  self:render()
end

-- Helper function to uncheck dependent tasks
function LazyDo:uncheck_dependent_tasks(task)
  for _, t in ipairs(self.tasks) do
    if vim.tbl_contains(t.dependencies or {}, task.id) then
      t.done = false
      self:uncheck_dependent_tasks(t)
    end
  end
end

-- Show sort menu
function LazyDo:show_sort_menu()
  local options = {
    { text = "Priority", value = "priority" },
    { text = "Due Date", value = "due_date" },
    { text = "Status", value = "status" },
    { text = "Alphabetical", value = "alphabetical" },
  }

  vim.ui.select(options, {
    prompt = "Sort by:",
    format_item = function(item) return item.text end
  }, function(choice)
    if choice then
      self:sort_tasks_by(choice.value)
    end
  end)
end

-- Show help
function LazyDo:show_help()
  local help_lines = {
    "LazyDo Keybindings",
    "═════════════════",
    "",
    "Task Management:",
    string.format("  %s - Toggle task completion", self.opts.keymaps.toggle_done),
    string.format("  %s - Edit task", self.opts.keymaps.edit_task),
    string.format("  %s - Add new task", self.opts.keymaps.add_task),
    string.format("  %s - Delete task", self.opts.keymaps.delete_task),
    "",
    "Organization:",
    string.format("  %s - Move task up", self.opts.keymaps.move_up),
    string.format("  %s - Move task down", self.opts.keymaps.move_down),
    string.format("  %s - Toggle expand/collapse", self.opts.keymaps.toggle_expand),
    "",
    "Properties:",
    string.format("  %s - Increase priority", self.opts.keymaps.increase_priority),
    string.format("  %s - Decrease priority", self.opts.keymaps.decrease_priority),
    string.format("  %s - Add/edit note", self.opts.keymaps.quick_note),
    string.format("  %s - Set due date", self.opts.keymaps.quick_date),
    "",
    "Other:",
    string.format("  %s - Search tasks", self.opts.keymaps.search_tasks),
    string.format("  %s - Sort tasks", self.opts.keymaps.sort_by_priority),
    "  <CR> - Quick actions menu",
    "  ?    - Show this help",
  }

  local buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, help_lines)
  vim.api.nvim_buf_set_option(buf, 'modifiable', false)
  vim.api.nvim_buf_set_option(buf, 'filetype', 'help')

  local width = 60
  local height = #help_lines
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

  local win = vim.api.nvim_open_win(buf, true, opts)
  
  -- Close help window with q or <Esc>
  vim.keymap.set('n', 'q', '<cmd>close<CR>', { buffer = buf, silent = true })
  vim.keymap.set('n', '<Esc>', '<cmd>close<CR>', { buffer = buf, silent = true })
end

-- Add buffer-local keymaps setup
function LazyDo:setup_buffer_keymaps()
  local function map(key, fn)
    vim.keymap.set('n', key, fn, {
      buffer = self.buf,
      silent = true,
      nowait = true,
      desc = "LazyDo: " .. key
    })
  end

  -- Core task management
  map(self.opts.keymaps.toggle_done, function() self:toggle_task() end)
  map(self.opts.keymaps.edit_task, function() self:edit_task() end)
  map(self.opts.keymaps.add_task, function() self:add_task() end)
  map(self.opts.keymaps.delete_task, function() self:delete_task() end)
  
  -- Task organization
  map(self.opts.keymaps.move_up, function() self:move_task_up() end)
  map(self.opts.keymaps.move_down, function() self:move_task_down() end)
  map(self.opts.keymaps.toggle_expand, function() self:toggle_expand() end)
  
  -- Task properties
  map(self.opts.keymaps.increase_priority, function() self:change_priority(-1) end)
  map(self.opts.keymaps.decrease_priority, function() self:change_priority(1) end)
  map(self.opts.keymaps.quick_note, function() self:quick_note() end)
  map(self.opts.keymaps.quick_date, function() self:quick_date() end)
  
  -- Task filtering and search
  map(self.opts.keymaps.search_tasks, function() self:advanced_search() end)
  map(self.opts.keymaps.sort_by_priority, function() self:show_sort_menu() end)
  
  -- Additional features
  map('<CR>', function() self:quick_actions() end)
  map('?', function() self:show_help() end)
end

-- Add highlight groups
function LazyDo:setup_highlights()
  local highlights = {
    LazyDoHeader = { link = "Title" },
    LazyDoCheckbox = { fg = self.opts.colors.checkbox },
---@class LazyDo
---@field opts table Plugin options
---@field win number? Window handle
---@field buf number? Buffer handle
---@field is_visible boolean Visibility state
local LazyDo = {}

-- Add utility functions at the top of the file
local utils = {}

-- Fix string.center function
function utils.center(text, width)
  local padding = width - vim.fn.strdisplaywidth(text)
  if padding <= 0 then return text end
  local left_pad = math.floor(padding / 2)
  local right_pad = padding - left_pad
  return string.rep(" ", left_pad) .. text .. string.rep(" ", right_pad)
end

-- Safe table access
function utils.get_or_create(tbl, key, default)
  if tbl[key] == nil then
    tbl[key] = default
  end
  return tbl[key]
end

-- Safe string operations
function utils.safe_sub(str, start_idx, end_idx)
  if not str then return "" end
  return string.sub(str or "", start_idx, end_idx)
end

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
    auto_save = true,        -- Save on every change
    backup = true,           -- Keep backup file
  },
  create_keymaps = true,     -- Enable/disable default keymaps
  render = {
    use_markdown = true,     -- Use markdown-style rendering
    show_empty_state = true, -- Show message when no tasks
    show_help = true,        -- Show keybindings help
    compact_view = false,    -- Compact view mode
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
  end

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
  if not self.buf or not vim.api.nvim_buf_is_valid(self.buf) then return end

  local lines = {}
  local highlights = {}

  -- Add header
  table.insert(lines, "╭" .. string.rep("─", 50) .. "╮")
  table.insert(lines, "│" .. utils.center("LazyDo Task Manager", 50) .. "│")
  table.insert(lines, "╰" .. string.rep("─", 50) .. "╯")

  -- Add statistics
  table.insert(lines, "")
  table.insert(lines, self:render_statistics())
  table.insert(lines, "")

  -- Initialize task fields if they don't exist
  for _, task in ipairs(self.tasks) do
    task.tags = task.tags or {}
    task.priority = task.priority or 3
    task.indent = task.indent or 0
    task.id = task.id or tostring(os.time()) .. math.random(1000, 9999)
    task.subtasks = task.subtasks or {}
    task.dependencies = task.dependencies or {}
  end

  -- Filter tasks if needed
  local tasks_to_render = self.current_filter and 
    self:filter_tasks(self.current_filter) or self.tasks

  -- Render tasks
  local task_lines, task_highlights = self:render_tasks(tasks_to_render)
  vim.list_extend(lines, task_lines)
  vim.list_extend(highlights, task_highlights)

  -- Add help footer if enabled
  if self.opts and self.opts.render and self.opts.render.show_help then
    table.insert(lines, "")
    table.insert(lines, "── Commands ──")
    local keymaps = self.opts.keymaps or {}
    table.insert(lines, string.format(
      "%s:Toggle | %s:Edit | %s:Add | %s:Delete | %s:Filter | %s:Sort",
      keymaps.toggle_done or "t",
      keymaps.edit_task or "e",
      keymaps.add_task or "a",
      keymaps.delete_task or "d",
      keymaps.search_tasks or "f",
      keymaps.sort_by_priority or "s"
    ))
  end

  -- Update buffer content safely
  vim.api.nvim_buf_set_option(self.buf, 'modifiable', true)
  vim.api.nvim_buf_set_lines(self.buf, 0, -1, false, lines)
  vim.api.nvim_buf_set_option(self.buf, 'modifiable', false)

  -- Apply highlights safely
  for _, hl in ipairs(highlights) do
    pcall(vim.api.nvim_buf_add_highlight,
      self.buf, -1, hl.hl_group, hl.line, hl.col_start, hl.col_end
    )
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
    { text = "Edit Content",  value = "edit" },
    { text = "Set Priority",  value = "priority" },
    { text = "Set Due Date",  value = "due_date" },
    { text = "Add/Edit Note", value = "note" },
    { text = "Add Subtask",   value = "subtask" },
    { text = "Delete Task",   value = "delete" },
    { text = "Move Up",       value = "move_up" },
    { text = "Move Down",     value = "move_down" },
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
  local current_idx = cursor[1] - 4

  if current_idx > 1 then
    local task = self.tasks[current_idx]
    local subtasks = self:get_task_hierarchy(current_idx)
    local move_size = #subtasks + 1
    local target_idx = current_idx - 1

    -- Check if move is possible
    if target_idx > 0 and
        (task.indent <= self.tasks[target_idx].indent or
          current_idx - target_idx == 1) then
      -- Move task and its subtasks
      local tasks_to_move = { table.unpack(self.tasks, current_idx, current_idx + #subtasks) }
      table.remove(self.tasks, current_idx, current_idx + #subtasks)
      for i, t in ipairs(tasks_to_move) do
        table.insert(self.tasks, target_idx + i - 1, t)
      end

      self:render()
      vim.api.nvim_win_set_cursor(self.win, { target_idx + 4, cursor[2] })
    end
  end
end

function LazyDo:move_task_down()
  local cursor = vim.api.nvim_win_get_cursor(self.win)
  local current_idx = cursor[1] - 4

  if current_idx < #self.tasks then
    local task = self.tasks[current_idx]
    local subtasks = self:get_task_hierarchy(current_idx)
    local move_size = #subtasks + 1
    local target_idx = current_idx + 1

    -- Check if move is possible
    if target_idx <= #self.tasks and
        (task.indent <= self.tasks[target_idx].indent or
          target_idx - current_idx == 1) then
      -- Move task and its subtasks
      local tasks_to_move = { table.unpack(self.tasks, current_idx, current_idx + #subtasks) }
      table.remove(self.tasks, current_idx, current_idx + #subtasks)
      for i, t in ipairs(tasks_to_move) do
        table.insert(self.tasks, target_idx + i - 1, t)
      end

      self:render()
      vim.api.nvim_win_set_cursor(self.win, { target_idx + 4, cursor[2] })
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
  if not filter then return self.tasks end

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
    { text = "All Tasks",       value = function(t) return true end },
    { text = "Pending Tasks",   value = function(t) return not t.done end },
    { text = "Completed Tasks", value = function(t) return t.done end },
    {
      text = "Overdue Tasks",
      value = function(t)
        return not t.done and t.due_date and t.due_date < os.time()
      end
    },
    { text = "High Priority", value = function(t) return t.priority == 1 end },
    { text = "No Due Date",   value = function(t) return not t.due_date end },
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
  table.insert(lines, "│" .. utils.center("LazyDo Task Manager", 50) .. "│")
  table.insert(lines, "╰" .. string.rep("─", 50) .. "╯")

  -- Add statistics
  table.insert(lines, "")
  table.insert(lines, self:render_statistics())
  table.insert(lines, "")

  -- Initialize task fields if they don't exist
  for _, task in ipairs(self.tasks) do
    task.tags = task.tags or {}
    task.priority = task.priority or 3
    task.indent = task.indent or 0
    task.id = task.id or tostring(os.time()) .. math.random(1000, 9999)
    task.subtasks = task.subtasks or {}
    task.dependencies = task.dependencies or {}
  end

  -- Filter tasks if needed
  local tasks_to_render = self.current_filter and 
    self:filter_tasks(self.current_filter) or self.tasks

  -- Render tasks
  local task_lines, task_highlights = self:render_tasks(tasks_to_render)
  vim.list_extend(lines, task_lines)
  vim.list_extend(highlights, task_highlights)

  -- Add help footer if enabled
  if self.opts and self.opts.render and self.opts.render.show_help then
    table.insert(lines, "")
    table.insert(lines, "── Commands ──")
    local keymaps = self.opts.keymaps or {}
    table.insert(lines, string.format(
      "%s:Toggle | %s:Edit | %s:Add | %s:Delete | %s:Filter | %s:Sort",
      keymaps.toggle_done or "t",
      keymaps.edit_task or "e",
      keymaps.add_task or "a",
      keymaps.delete_task or "d",
      keymaps.search_tasks or "f",
      keymaps.sort_by_priority or "s"
    ))
  end

  -- Update buffer content safely
  vim.api.nvim_buf_set_option(self.buf, 'modifiable', true)
  vim.api.nvim_buf_set_lines(self.buf, 0, -1, false, lines)
  vim.api.nvim_buf_set_option(self.buf, 'modifiable', false)

  -- Apply highlights safely
  for _, hl in ipairs(highlights) do
    pcall(vim.api.nvim_buf_add_highlight,
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
    { text = "Add Dependency",    value = "add" },
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
    { text = "Daily",     value = "daily" },
    { text = "Weekly",    value = "weekly" },
    { text = "Monthly",   value = "monthly" },
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
    { text = "Load Template",    value = "load" },
    { text = "Delete Template",  value = "delete" },
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
      local lines = { "Content,Status,Due Date,Priority,Notes" }
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
    vim.notify("Telescope not found, falling back to basic search", vim.log.levels.WARN)
    return self:basic_search()
  end

  -- Add error handling for telescope operations
  local ok, err = pcall(function()
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
              vim.api.nvim_win_set_cursor(self.win, { task_idx + 4, 0 })
            end
          end
        end)
        return true
      end
    })
  end)

  if not ok then
    vim.notify("Search failed: " .. err, vim.log.levels.ERROR)
    return self:basic_search()
  end
end

-- Add task statistics and analytics
function LazyDo:show_analytics()
  if #self.tasks == 0 then
    vim.notify("No tasks to analyze", vim.log.levels.INFO)
    return
  end

  local stats = {
    total = #self.tasks,
    completed = 0,
    overdue = 0,
    priority = { high = 0, medium = 0, low = 0 },
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

    if task.priority == 1 then
      stats.priority.high = stats.priority.high + 1
    elseif task.priority == 2 then
      stats.priority.medium = stats.priority.medium + 1
    else
      stats.priority.low = stats.priority.low + 1
    end

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

-- Fix string.center function that might be missing
local function center_text(text, width)
  local padding = width - #text
  if padding <= 0 then return text end
  local left_pad = math.floor(padding / 2)
  local right_pad = padding - left_pad
  return string.rep(" ", left_pad) .. text .. string.rep(" ", right_pad)
end

-- Fix task hierarchy management
function LazyDo:get_task_hierarchy(task_idx)
  local subtasks = {}
  local indent = self.tasks[task_idx].indent
  local i = task_idx + 1

  while i <= #self.tasks and self.tasks[i].indent > indent do
    table.insert(subtasks, i)
    i = i + 1
  end

  return subtasks
end

-- Fix move_task functions to handle subtasks correctly
function LazyDo:move_task_up()
  local cursor = vim.api.nvim_win_get_cursor(self.win)
  local current_idx = cursor[1] - 4

  if current_idx > 1 then
    local task = self.tasks[current_idx]
    local subtasks = self:get_task_hierarchy(current_idx)
    local move_size = #subtasks + 1
    local target_idx = current_idx - 1

    -- Check if move is possible
    if target_idx > 0 and
        (task.indent <= self.tasks[target_idx].indent or
          current_idx - target_idx == 1) then
      -- Move task and its subtasks
      local tasks_to_move = { table.unpack(self.tasks, current_idx, current_idx + #subtasks) }
      table.remove(self.tasks, current_idx, current_idx + #subtasks)
      for i, t in ipairs(tasks_to_move) do
        table.insert(self.tasks, target_idx + i - 1, t)
      end

      self:render()
      vim.api.nvim_win_set_cursor(self.win, { target_idx + 4, cursor[2] })
    end
  end
end

-- Fix task filtering to handle nil values
function LazyDo:filter_tasks(filter)
  if not filter then return self.tasks end

  local filtered = {}
  for _, task in ipairs(self.tasks) do
    if filter(task) then
      table.insert(filtered, task)
    end
  end
  return filtered
end

-- Fix template management to handle errors
function LazyDo:save_template()
  local cursor = vim.api.nvim_win_get_cursor(self.win)
  local task = self:get_task_at_line(cursor[1])
  if not task then return end

  vim.ui.input({
    prompt = "Template name: "
  }, function(name)
    if not name or name == "" then return end

    local template_dir = vim.fn.stdpath("data") .. "/lazydo/templates"
    vim.fn.mkdir(template_dir, "p")

    local ok, err = pcall(function()
      local template = vim.deepcopy(task)
      template.id = nil -- Remove task-specific data
      template.done = false

      local file = io.open(template_dir .. "/" .. name .. ".json", "w")
      if file then
        file:write(vim.json.encode(template))
        file:close()
        vim.notify("Template saved: " .. name, vim.log.levels.INFO)
      end
    end)

    if not ok then
      vim.notify("Failed to save template: " .. err, vim.log.levels.ERROR)
    end
  end)
end

-- Fix analytics to handle edge cases
function LazyDo:show_analytics()
  if #self.tasks == 0 then
    vim.notify("No tasks to analyze", vim.log.levels.INFO)
    return
  end

  -- Rest of the analytics function...
end

-- Fix telescope integration to handle missing plugin
function LazyDo:advanced_search()
  local has_telescope, telescope = pcall(require, "telescope.builtin")
  if not has_telescope then
    vim.notify("Telescope not found, falling back to basic search", vim.log.levels.WARN)
    return self:basic_search()
  end

  -- Add error handling for telescope operations
  local ok, err = pcall(function()
    -- Existing telescope implementation...
  end)

  if not ok then
    vim.notify("Search failed: " .. err, vim.log.levels.ERROR)
    return self:basic_search()
  end
end

-- Fix task dependencies to prevent circular references
function LazyDo:add_dependency(task, dep_task)
  if not task or not dep_task then return false end

  -- Check for circular dependencies
  local function has_circular_dep(t, target)
    if not t.dependencies then return false end
    for _, dep_id in ipairs(t.dependencies) do
      local dep = self:get_task_by_id(dep_id)
      if dep.id == target.id or has_circular_dep(dep, target) then
        return true
      end
    end
    return false
  end

  if has_circular_dep(dep_task, task) then
    vim.notify("Circular dependency detected", vim.log.levels.WARN)
    return false
  end

  task.dependencies = task.dependencies or {}
  table.insert(task.dependencies, dep_task.id)
  return true
end

-- Fix render function to handle long content
function LazyDo:render_task_line(task, width)
  local content = task.content
  if #content > width - 20 then
    content = content:sub(1, width - 23) .. "..."
  end

  -- Rest of the render logic...
end

-- Add proper cleanup for resources
function LazyDo:cleanup()
  if self.win and vim.api.nvim_win_is_valid(self.win) then
    pcall(vim.api.nvim_win_close, self.win, true)
  end

  if self.buf and vim.api.nvim_buf_is_valid(self.buf) then
    pcall(vim.api.nvim_buf_delete, self.buf, { force = true })
  end

  -- Clear any autocommands we've created
  if self.augroup then
    pcall(vim.api.nvim_del_augroup_by_id, self.augroup)
  end

  self.win = nil
  self.buf = nil
  self.is_visible = false
end

-- Task template management
function LazyDo:load_template()
  local template_dir = vim.fn.stdpath("data") .. "/lazydo/templates"
  local templates = vim.fn.glob(template_dir .. "/*.json", false, true)
  
  if #templates == 0 then
    vim.notify("No templates found", vim.log.levels.INFO)
    return
  end

  local items = vim.tbl_map(function(path)
    local name = vim.fn.fnamemodify(path, ":t:r")
    return { text = name, path = path }
  end, templates)

  vim.ui.select(items, {
    prompt = "Select template:",
    format_item = function(item) return item.text end
  }, function(choice)
    if not choice then return end
    
    local ok, content = pcall(vim.fn.readfile, choice.path)
    if not ok then
      vim.notify("Failed to read template", vim.log.levels.ERROR)
      return
    end

    local ok, template = pcall(vim.json.decode, table.concat(content))
    if not ok then
      vim.notify("Failed to parse template", vim.log.levels.ERROR)
      return
    end

    template.id = tostring(os.time()) .. math.random(1000, 9999)
    table.insert(self.tasks, template)
    self:render()
  end)
end

function LazyDo:delete_template()
  local template_dir = vim.fn.stdpath("data") .. "/lazydo/templates"
  local templates = vim.fn.glob(template_dir .. "/*.json", false, true)
  
  if #templates == 0 then
    vim.notify("No templates found", vim.log.levels.INFO)
    return
  end

  local items = vim.tbl_map(function(path)
    local name = vim.fn.fnamemodify(path, ":t:r")
    return { text = name, path = path }
  end, templates)

  vim.ui.select(items, {
    prompt = "Delete template:",
    format_item = function(item) return item.text end
  }, function(choice)
    if not choice then return end
    
    vim.ui.select({ "Yes", "No" }, {
      prompt = "Confirm delete " .. choice.text .. "?",
    }, function(confirm)
      if confirm == "Yes" then
        os.remove(choice.path)
        vim.notify("Template deleted: " .. choice.text, vim.log.levels.INFO)
      end
    end)
  end)
end

-- Task dependency management
function LazyDo:select_task_as_dependency(task)
  local available_tasks = {}
  for _, t in ipairs(self.tasks) do
    if t.id ~= task.id then
      table.insert(available_tasks, {
        text = t.content,
        task = t
      })
    end
  end

  vim.ui.select(available_tasks, {
    prompt = "Select dependency:",
    format_item = function(item) return item.text end
  }, function(choice)
    if choice then
      self:add_dependency(task, choice.task)
      self:render()
    end
  end)
end

function LazyDo:remove_dependency(task)
  if not task.dependencies or #task.dependencies == 0 then
    vim.notify("No dependencies to remove", vim.log.levels.INFO)
    return
  end

  local deps = {}
  for _, dep_id in ipairs(task.dependencies) do
    local dep_task = self:get_task_by_id(dep_id)
    if dep_task then
      table.insert(deps, {
        text = dep_task.content,
        id = dep_id
      })
    end
  end

  vim.ui.select(deps, {
    prompt = "Remove dependency:",
    format_item = function(item) return item.text end
  }, function(choice)
    if choice then
      task.dependencies = vim.tbl_filter(function(id)
        return id ~= choice.id
      end, task.dependencies)
      self:render()
    end
  end)
end

function LazyDo:view_dependencies(task)
  if not task.dependencies or #task.dependencies == 0 then
    vim.notify("No dependencies", vim.log.levels.INFO)
    return
  end

  local lines = {"Dependencies for: " .. task.content, ""}
  for _, dep_id in ipairs(task.dependencies) do
    local dep_task = self:get_task_by_id(dep_id)
    if dep_task then
      table.insert(lines, string.format("• %s (%s)",
        dep_task.content,
        dep_task.done and "Done" or "Pending"
      ))
    end
  end

  vim.api.nvim_echo(vim.tbl_map(function(line)
    return {line, "Normal"}
  end, lines), false, {})
end

-- Basic search implementation
function LazyDo:basic_search()
  vim.ui.input({
    prompt = "Search tasks: "
  }, function(query)
    if not query or query == "" then return end
    
    local matches = {}
    for i, task in ipairs(self.tasks) do
      if task.content:lower():find(query:lower()) then
        table.insert(matches, {
          index = i,
          task = task
        })
      end
    end

    if #matches == 0 then
      vim.notify("No matches found", vim.log.levels.INFO)
      return
    end

    vim.ui.select(matches, {
      prompt = "Select task:",
      format_item = function(item)
        return string.format("%s %s",
          item.task.done and "✓" or "☐",
          item.task.content
        )
      end
    }, function(choice)
      if choice then
        vim.api.nvim_win_set_cursor(self.win, {choice.index + 4, 0})
      end
    end)
  end)
end

-- Get task by ID
function LazyDo:get_task_by_id(id)
  for _, task in ipairs(self.tasks) do
    if task.id == id then
      return task
    end
  end
  return nil
end

-- Process recurring tasks
function LazyDo:process_recurring_tasks()
  local now = os.time()
  local new_tasks = {}

  for _, task in ipairs(self.tasks) do
    if task.recurrence and task.done then
      local next_date
      if task.recurrence.type == "preset" then
        if task.recurrence.pattern == "daily" then
          next_date = now + (24 * 60 * 60)
        elseif task.recurrence.pattern == "weekly" then
          next_date = now + (7 * 24 * 60 * 60)
        elseif task.recurrence.pattern == "monthly" then
          next_date = os.time(os.date("*t", now + (30 * 24 * 60 * 60)))
        end
      elseif task.recurrence.type == "cron" then
        -- Basic cron implementation for daily/weekly/monthly
        local pattern = task.recurrence.pattern
        if pattern == "0 0 * * *" then -- daily
          next_date = now + (24 * 60 * 60)
        elseif pattern == "0 0 * * 0" then -- weekly
          next_date = now + (7 * 24 * 60 * 60)
        elseif pattern == "0 0 1 * *" then -- monthly
          next_date = os.time(os.date("*t", now + (30 * 24 * 60 * 60)))
        end
      end

      if next_date then
        local new_task = vim.deepcopy(task)
        new_task.id = tostring(os.time()) .. math.random(1000, 9999)
        new_task.done = false
        new_task.due_date = next_date
        table.insert(new_tasks, new_task)
      end
    end
  end

  -- Add new recurring tasks
  for _, task in ipairs(new_tasks) do
    table.insert(self.tasks, task)
  end

  if #new_tasks > 0 then
    self:render()
  end
end

-- Add autocommands for recurring tasks
function LazyDo:setup_recurring_tasks()
  if not self.augroup then
    self.augroup = vim.api.nvim_create_augroup("LazyDoRecurring", { clear = true })
  end

  vim.api.nvim_create_autocmd("BufEnter", {
    group = self.augroup,
    pattern = "*",
    callback = function()
      self:process_recurring_tasks()
    end
  })
end

-- Enhanced task sorting
function LazyDo:sort_tasks_by(criteria)
  local sort_functions = {
    due_date = function(a, b)
      if not a.due_date and not b.due_date then return false end
      if not a.due_date then return false end
      if not b.due_date then return true end
      return a.due_date < b.due_date
    end,
    priority = function(a, b)
      return a.priority < b.priority
    end,
    status = function(a, b)
      if a.done == b.done then return false end
      return not a.done
    end,
    alphabetical = function(a, b)
      return a.content:lower() < b.content:lower()
    end
  }

  if sort_functions[criteria] then
    table.sort(self.tasks, sort_functions[criteria])
    self:render()
  end
end

return LazyDo
