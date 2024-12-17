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

return LazyDo 