---@mod lazydo Task Manager for Neovim
---@brief [[
--- LazyDo is a modern, functional task manager for Neovim
--- Features:
---   - Clean and intuitive UI
---   - Task management with priorities and due dates
---   - Project-specific tasks
---   - Powerful search and filter capabilities
---   - Statistics and analytics
---@brief ]]

local Config = require("lazydo.config")
local Core = require("lazydo.core")
local Highlights = require("lazydo.highlights")

---@class LazyDo
---@field private _instance LazyDoCore?
---@field private _config LazyDoConfig
---@field private _initialized boolean
local LazyDo = {
	_instance = nil,
	_config = nil,
	_initialized = false,
}

-- Utility function for safe command execution
local function safe_execute(callback, error_msg)
	return function(...)
		if not LazyDo._initialized then
			vim.notify("LazyDo is not initialized. Call setup() first.", vim.log.levels.ERROR)
			return
		end
		local success, result = pcall(callback, ...)
		if not success then
			vim.notify(error_msg .. ": " .. tostring(result), vim.log.levels.ERROR)
		end
		return result
	end
end

-- Create commands with improved error handling and feedback
local function create_commands()
	-- Command definitions with validation and feedback
	local commands = {
		{
			name = "LazyDoToggle",
			callback = function()
				LazyDo.toggle()
			end,
			opts = {},
			error_msg = "Failed to toggle LazyDo window",
		},
	}

	-- Register commands with error handling
	for _, cmd in ipairs(commands) do
		local wrapped_callback = safe_execute(cmd.callback, cmd.error_msg)
		vim.api.nvim_create_user_command(cmd.name, wrapped_callback, cmd.opts)
	end
end

---Initialize LazyDo with user configuration
---@param opts? table User configuration
---@return LazyDo
---@throws string when configuration is invalid
function LazyDo.setup(opts)
	-- Prevent multiple initialization with proper cleanup
	if LazyDo._initialized then
		vim.notify("LazyDo is already initialized", vim.log.levels.WARN)
		return LazyDo
	end

	-- Setup with error handling
	local success, result = pcall(function()
		LazyDo._config = Config.setup(opts)

		-- Setup highlights with error handling
		local hl_success, hl_err = pcall(Highlights.setup, LazyDo._config)
		if not hl_success then
			error(string.format("Failed to setup highlights: %s", hl_err))
		end

		-- Initialize core with error handling
		LazyDo._instance = Core.new(LazyDo._config)
		if not LazyDo._instance then
			error("Failed to initialize core instance")
		end

		-- Setup autocommands with proper cleanup
		local augroup = vim.api.nvim_create_augroup("LazyDo", { clear = true })
		local function setup_signs()
			vim.fn.sign_define("LazyDoSearchSign", {
				text = "",
				texthl = "LazyDoSearchMatch",
				numhl = "LazyDoSearchMatch",
			})
		end
		setup_signs()

		-- Cleanup on exit
		vim.api.nvim_create_autocmd("VimLeave", {
			group = augroup,
			callback = function()
				if LazyDo._instance then
					LazyDo._instance:cleanup()
				end
			end,
		})

		-- Refresh highlights on colorscheme change
		vim.api.nvim_create_autocmd("ColorScheme", {
			group = augroup,
			callback = function()
				Highlights.setup(LazyDo._config)
				if LazyDo._instance then
					LazyDo._instance:refresh_ui()
				end
			end,
		})

		-- Create commands
		create_commands()

		LazyDo._initialized = true
	end)

	if not success then
		vim.notify("Failed to initialize LazyDo: " .. tostring(result), vim.log.levels.ERROR)
		return nil
	end

	return LazyDo
end

-- Public API Methods with improved error handling and validation

---Toggle task manager window
---@throws string when toggle operation fails
function LazyDo.toggle()
	if not LazyDo._initialized then
		vim.notify("LazyDo is not initialized", vim.log.levels.ERROR)
		return
	end

	local success, err = pcall(function()
		LazyDo._instance:toggle()
		Highlights.setup(LazyDo._config)
	end)

	if not success then
		vim.notify("Failed to toggle window: " .. tostring(err), vim.log.levels.ERROR)
	end
end

---Add a new task with validation
---@param content string Task content
---@param opts? table Additional task options
---@throws string when task creation fails
function LazyDo.add_task(content, opts)
	if not LazyDo._initialized then
		vim.notify("LazyDo is not initialized", vim.log.levels.ERROR)
		return
	end

	if not content or content == "" then
		vim.notify("Task content cannot be empty", vim.log.levels.WARN)
		return
	end

	local success, err = pcall(function()
		LazyDo._instance:add_task(content, opts)
	end)

	if not success then
		vim.notify("Failed to add task: " .. tostring(err), vim.log.levels.ERROR)
	end
end

---Get all tasks with error handling
---@return Task[] List of tasks
---@throws string when task retrieval fails
function LazyDo.get_tasks()
	if not LazyDo._initialized then
		vim.notify("LazyDo is not initialized", vim.log.levels.ERROR)
		return {}
	end

	local success, result = pcall(function()
		return LazyDo._instance:get_tasks()
	end)

	if not success then
		vim.notify("Failed to get tasks: " .. tostring(result), vim.log.levels.ERROR)
		return {}
	end

	return result or {}
end
function LazyDo.get_lualine_stats()
	if not LazyDo._initialized then
		return "LazyDo not initialized"
	end

	local success, result = pcall(function()
		return LazyDo._instance:get_statistics()
	end)

	if not success then
		return "Error retrieving stats"
	end

	local icons = {
		total = "",
		done = "",
		pending = "󱛢",
		overdue = "󰨱",
	}
	return string.format(
		"%%#Title#%s %%#Function#%d|%%#Constant#%s %%#Function#%d|%%#Error#%s %%#Function#%d|%%#String#%s %%#Function#%d",
		icons.total,
		result.total,
		icons.pending,
		result.pending,
		icons.overdue,
		result.overdue,
		icons.done,
		result.completed
	)
end
---Search tasks with improved validation
---@param query string Search query
---@return Task[] Matching tasks
---@throws string when search operation fails
function LazyDo.search(query)
	if not LazyDo._initialized then
		vim.notify("LazyDo is not initialized", vim.log.levels.ERROR)
		return {}
	end

	if not query or query == "" then
		vim.notify("Search query cannot be empty", vim.log.levels.WARN)
		return {}
	end

	local success, result = pcall(function()
		return LazyDo._instance:search(query)
	end)

	if not success then
		vim.notify("Failed to search tasks: " .. tostring(result), vim.log.levels.ERROR)
		return {}
	end

	return result or {}
end

---Filter tasks with validation
---@param filter string Filter criteria
---@throws string when filter operation fails
function LazyDo.filter_tasks(filter)
	if not LazyDo._initialized then
		vim.notify("LazyDo is not initialized", vim.log.levels.ERROR)
		return
	end

	if not filter or filter == "" then
		vim.notify("Filter criteria cannot be empty", vim.log.levels.WARN)
		return
	end

	local success, err = pcall(function()
		LazyDo._instance:filter_tasks(filter)
	end)

	if not success then
		vim.notify("Failed to filter tasks: " .. tostring(err), vim.log.levels.ERROR)
	end
end

---Sort tasks with validation
---@param criteria string Sort criteria
---@throws string when sort operation fails
function LazyDo.sort_tasks(criteria)
	if not LazyDo._initialized then
		vim.notify("LazyDo is not initialized", vim.log.levels.ERROR)
		return
	end

	if not criteria or criteria == "" then
		vim.notify("Sort criteria cannot be empty", vim.log.levels.WARN)
		return
	end

	local success, err = pcall(function()
		LazyDo._instance:sort_tasks(criteria)
	end)

	if not success then
		vim.notify("Failed to sort tasks: " .. tostring(err), vim.log.levels.ERROR)
	end
end

return LazyDo
