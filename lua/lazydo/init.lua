-- Main entry point
local LazyDo = require('lazydo.core')
local setup = require('lazydo.setup')

-- Create the setup function that lazy.nvim will call
local M = {
  _instance = nil
}

function M.setup(opts)
  if not M._instance then
    M._instance = setup(opts)
  end
  return M._instance
end

-- Add convenience methods
function M.toggle()
  if M._instance then
    M._instance:toggle()
  end
end

function M.show()
  if M._instance then
    M._instance:show()
  end
end

function M.close()
  if M._instance then
    M._instance:close_window()
  end
end

-- Re-export the module
return M
