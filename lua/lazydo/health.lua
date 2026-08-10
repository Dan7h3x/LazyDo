local M = {}

function M.check()
	vim.health.start("LazyDo")

	-- Check Neovim version
	local nvim_version = vim.version()
	if nvim_version.major >= 0 and nvim_version.minor >= 7 then
		vim.health.ok("Neovim version >= 0.7.0")
	else
		vim.health.error("Neovim version must be >= 0.7.0")
	end

	-- Check storage directory
	local data_dir = vim.fn.stdpath("data") .. "/lazydo"
	if vim.fn.isdirectory(data_dir) == 1 then
		vim.health.ok("Storage directory exists: " .. data_dir)
	else
		vim.health.warn("Storage directory will be created on first use: " .. data_dir)
	end

	-- Check required Neovim features
	local required_features = {
		"nvim_create_user_command",
		"nvim_create_autocmd",
		"nvim_create_namespace"
	}

	for _, feature in ipairs(required_features) do
		if vim.fn.exists("*" .. feature) == 1 then
			vim.health.ok(string.format("Required function '%s' is available", feature))
		else
			vim.health.error(string.format("Required function '%s' is not available", feature))
		end
	end
end

return M