local LazyDo = require("lazydo.core")
local config = require("lazydo.config")

return function(opts)
	if not LazyDo.instance then
		local instance = LazyDo:new()
		instance.opts = vim.tbl_deep_extend("force", config.defaults, opts or {})

		-- Initialize storage and wrap functions
		instance:wrap_with_auto_save()
		instance:load_tasks()
		instance:create_commands()
		instance:setup_highlights()
		instance:setup_task_highlights()

		-- Enhanced auto-save setup
		if instance.opts.storage.auto_save then
			-- Save on buffer leave
			vim.api.nvim_create_autocmd("BufLeave", {
				pattern = "*",
				callback = function()
					if instance.is_visible and instance.tasks_modified then
						instance:save_tasks()
						instance.tasks_modified = false
					end
				end,
			})

			-- Save on vim leave
			vim.api.nvim_create_autocmd("VimLeavePre", {
				callback = function()
					if instance.tasks_modified then
						instance:save_tasks()
						instance.tasks_modified = false
					end
				end,
			})

			-- Periodic auto-save
			local timer = vim.loop.new_timer()
			timer:start(30000, 30000, vim.schedule_wrap(function()
				if instance.tasks_modified then
					instance:save_tasks()
					instance.tasks_modified = false
				end
			end))
		end

		LazyDo.instance = instance
	end

	return LazyDo.instance
end
