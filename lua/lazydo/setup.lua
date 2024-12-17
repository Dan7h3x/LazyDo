local LazyDo = require('lazydo.core')
local config = require('lazydo.config')

return function(opts)
  if not LazyDo.instance then
    local instance = LazyDo:new()
    instance.opts = vim.tbl_deep_extend("force", config.defaults, opts or {})

    -- Initialize storage and wrap functions
    instance:wrap_with_auto_save()
    instance:load_tasks()
    instance:create_commands()
    instance:setup_highlights()

    -- Setup auto-save
    if instance.opts.storage.auto_save then
      vim.api.nvim_create_autocmd("BufLeave", {
        pattern = "*",
        callback = function()
          if instance.is_visible then
            instance:save_tasks()
          end
        end
      })
    end

    LazyDo.instance = instance
  end

  return LazyDo.instance
end
