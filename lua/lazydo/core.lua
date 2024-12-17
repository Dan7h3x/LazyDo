local LazyDo = {}
local utils = require('lazydo.utils')
local ui = require('lazydo.ui')
local storage = require('lazydo.storage')
local task = require('lazydo.task')

-- Core functionality and state management
LazyDo.instance = nil
LazyDo.is_visible = false
LazyDo.is_processing = false
LazyDo.is_ui_busy = false

function LazyDo:new()
  local instance = setmetatable({}, { __index = LazyDo })
  instance.tasks = {}
  instance.buf = nil
  instance.win = nil
  instance.help_win = nil
  instance.help_buf = nil
  instance.ns = {
    render = vim.api.nvim_create_namespace('lazydo_render'),
    highlight = vim.api.nvim_create_namespace('lazydo_highlight'),
    virtual = vim.api.nvim_create_namespace('lazydo_virtual')
  }
  return instance
end

function LazyDo:toggle()
  if self.is_visible then
    self:close_window()
  else
    self:show()
  end
end

function LazyDo:show()
  if not self.buf or not vim.api.nvim_buf_is_valid(self.buf) then
    self.buf = ui.create_buffer(self)
  end

  if not self.win or not vim.api.nvim_win_is_valid(self.win) then
    self.win = ui.create_window(self)
  end

  self.is_visible = true
  self:setup_live_refresh()
  self:refresh_display()
end

function LazyDo:close_window()
  if self.is_ui_busy then return end
  
  if self.refresh_timer then
    self.refresh_timer:stop()
    self.refresh_timer:close()
    self.refresh_timer = nil
  end

  if self.win and vim.api.nvim_win_is_valid(self.win) then
    vim.api.nvim_win_close(self.win, true)
  end

  self.win = nil
  self.is_visible = false
end

function LazyDo:set_ui_busy(busy)
  self.is_ui_busy = busy
  if self.buf and vim.api.nvim_buf_is_valid(self.buf) then
    vim.api.nvim_buf_set_option(self.buf, 'modifiable', not busy)
  end
end

function LazyDo:setup_live_refresh()
  if not self.refresh_timer then
    self.refresh_timer = vim.loop.new_timer()
  end
  
  self.refresh_timer:start(0, 100, vim.schedule_wrap(function()
    if self.is_visible and not self.is_processing then
      self:refresh_display()
    end
  end))
end

function LazyDo:refresh_display()
  if not self.buf or not vim.api.nvim_buf_is_valid(self.buf) then return end
  
  self.is_processing = true
  local ok = pcall(function()
    local cursor = vim.api.nvim_win_get_cursor(self.win)
    self:render_content()
    
    if cursor[1] <= vim.api.nvim_buf_line_count(self.buf) then
      vim.api.nvim_win_set_cursor(self.win, cursor)
    end
    
    ui.setup_task_highlights(self)
  end)
  self.is_processing = false
end

function LazyDo:render_content()
  if not self.buf or not vim.api.nvim_buf_is_valid(self.buf) then return end
  
  vim.api.nvim_buf_set_option(self.buf, 'modifiable', true)
  
  local width = vim.api.nvim_win_get_width(self.win)
  local lines = {}
  
  -- Add header
  table.insert(lines, utils.center(" LazyDo ", width))
  table.insert(lines, string.rep("═", width))
  
  -- Add statistics
  local stats = self:get_task_statistics()
  local stats_line = string.format(" Total: %d | Done: %d | Pending: %d | Overdue: %d ",
    stats.total, stats.done, stats.pending, stats.overdue)
  table.insert(lines, utils.center(stats_line, width))
  table.insert(lines, "")
  
  -- Render tasks
  for _, task in ipairs(self.tasks) do
    local task_lines = ui.render_task_block(task, width, "", self.opts.icons)
    vim.list_extend(lines, task_lines)
  end
  
  vim.api.nvim_buf_set_lines(self.buf, 0, -1, false, lines)
  vim.api.nvim_buf_set_option(self.buf, 'modifiable', false)
end

function LazyDo:get_task_statistics()
  local stats = {
    total = #self.tasks,
    done = 0,
    pending = 0,
    overdue = 0
  }
  
  local now = os.time()
  for _, task in ipairs(self.tasks) do
    if task.done then
      stats.done = stats.done + 1
    else
      stats.pending = stats.pending + 1
      if task.due_date and task.due_date < now then
        stats.overdue = stats.overdue + 1
      end
    end
  end
  
  return stats
end

function LazyDo:get_current_task()
  if not self.win or not vim.api.nvim_win_is_valid(self.win) then return nil end
  
  local cursor = vim.api.nvim_win_get_cursor(self.win)
  local line_nr = cursor[1]
  
  -- Skip header (title + separator + stats + empty line)
  if line_nr <= 4 then return nil end
  
  local current_task = nil
  local current_line = line_nr
  local task_start = 5 -- First task starts after header
  
  for _, task in ipairs(self.tasks) do
    local task_height = self:get_task_block_height(task)
    if current_line >= task_start and current_line < task_start + task_height then
      current_task = task
      break
    end
    task_start = task_start + task_height + 1 -- +1 for spacing
  end
  
  return current_task
end

function LazyDo:get_task_block_height(task)
  local height = 3 -- Minimum height (top border + content + bottom border)
  
  if task.due_date then height = height + 1 end
  if task.notes then
    local wrapped_notes = utils.word_wrap(task.notes, vim.api.nvim_win_get_width(self.win) - 6)
    height = height + #wrapped_notes
  end
  if #task.subtasks > 0 then
    height = height + 1 + #task.subtasks -- Header + subtasks
  end
  
  return height
end

function LazyDo:add_task(content, opts)
  local task = require('lazydo.task').Task.new(content, opts)
  table.insert(self.tasks, task)
  if self.opts.storage.auto_save then
    storage.save_tasks(self)
  end
  self:refresh_display()
  return task
end

function LazyDo:delete_task()
  local task = self:get_current_task()
  if not task then return end
  
  for i, t in ipairs(self.tasks) do
    if t.id == task.id then
      table.remove(self.tasks, i)
      if self.opts.storage.auto_save then
        storage.save_tasks(self)
      end
      self:refresh_display()
      return true
    end
  end
  return false
end

function LazyDo:move_task(task, direction)
  for i, t in ipairs(self.tasks) do
    if t.id == task.id then
      local new_pos = i + direction
      if new_pos >= 1 and new_pos <= #self.tasks then
        self.tasks[i], self.tasks[new_pos] = self.tasks[new_pos], self.tasks[i]
        if self.opts.storage.auto_save then
          storage.save_tasks(self)
        end
        self:refresh_display()
        return true
      end
      break
    end
  end
  return false
end

function LazyDo:setup_highlights()
  local colors = self.opts.colors
  
  -- Define highlight groups
  local highlights = {
    LazyDoBorder = { fg = colors.border },
    LazyDoHeader = { fg = colors.header, bold = true },
    LazyDoPending = { fg = colors.pending },
    LazyDoDone = { fg = colors.done },
    LazyDoOverdue = { fg = colors.overdue },
    LazyDoNote = { fg = colors.note },
    LazyDoDueDate = { fg = colors.due_date },
    LazyDoPriorityHigh = { fg = colors.priority.high },
    LazyDoPriorityMedium = { fg = colors.priority.medium },
    LazyDoPriorityLow = { fg = colors.priority.low },
    LazyDoSubtask = { fg = colors.subtask },
  }
  
  for group, settings in pairs(highlights) do
    vim.api.nvim_set_hl(0, group, settings)
  end
end

function LazyDo:create_commands()
  vim.api.nvim_create_user_command('LazyDoToggle', function()
    self:toggle()
  end, {})
  
  vim.api.nvim_create_user_command('LazyDoAdd', function(opts)
    self:add_task(opts.args)
  end, { nargs = '?' })
end

return LazyDo 