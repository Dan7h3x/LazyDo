-- Main entry point
local LazyDo = require('lazydo.core')
local setup = require('lazydo.setup')

-- Re-export the module
return setmetatable({}, {
  __index = LazyDo,
  __call = function(_, opts)
    return setup(opts)
  end
})
