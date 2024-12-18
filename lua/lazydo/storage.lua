local M = {}
local Task = require("lazydo.task").Task

-- Cache for task data
local cache = {
	tasks = {},
	last_modified = nil,
	is_dirty = false,
}

function M.get_storage_path(opts)
	local dir = opts.storage.directory or vim.fn.stdpath("data") .. "/lazydo"
	return dir .. "/" .. (opts.storage.filename or "tasks.json")
end

function M.ensure_storage_path(path)
	local dir = vim.fn.fnamemodify(path, ":h")
	if vim.fn.isdirectory(dir) == 0 then
		vim.fn.mkdir(dir, "p")
	end
end

function M.save_tasks(lazydo)
	if not cache.is_dirty then
		return true
	end

	local ok, err = pcall(function()
		local path = M.get_storage_path(lazydo.opts)
		M.ensure_storage_path(path)

		-- Prepare data for saving
		local save_data = {
			version = lazydo.opts.version,
			last_modified = os.time(),
			tasks = vim.tbl_map(function(task)
				return task:serialize()
			end, lazydo.tasks or {}),
		}

		-- Write data atomically
		local temp_path = path .. ".tmp"
		local file = io.open(temp_path, "w")
		if not file then
			error("Could not open file for writing: " .. temp_path)
		end

		local json_str = vim.json.encode(save_data)
		file:write(json_str)
		file:close()

		-- Atomic rename
		if vim.fn.rename(temp_path, path) ~= 0 then
			error("Failed to save tasks file")
		end

		cache.is_dirty = false
		cache.last_modified = save_data.last_modified
	end)

	if not ok then
		vim.notify("Failed to save tasks: " .. err, vim.log.levels.ERROR)
		return false
	end
	return true
end

function M.load_tasks(lazydo)
	local ok, result = pcall(function()
		local path = M.get_storage_path(lazydo.opts)

		-- Check if we can use cached data
		if lazydo.opts.performance.cache_enabled and not cache.is_dirty then
			local stat = vim.loop.fs_stat(path)
			if stat and cache.last_modified and stat.mtime.sec <= cache.last_modified then
				lazydo.tasks = vim.deepcopy(cache.tasks)
				return true
			end
		end

		-- Initialize empty tasks if no storage exists
		if vim.fn.filereadable(path) == 0 then
			lazydo.tasks = {}
			cache.tasks = {}
			cache.last_modified = os.time()
			M.save_tasks(lazydo)
			return true
		end

		-- Load and parse file
		local file = io.open(path, "r")
		if not file then
			error("Could not open tasks file: " .. path)
		end

		local content = file:read("*all")
		file:close()

		local data = vim.json.decode(content)
		if not data or type(data) ~= "table" then
			error("Invalid task data format")
		end

		-- Deserialize tasks
		lazydo.tasks = vim.tbl_map(function(task_data)
			return Task.deserialize(task_data)
		end, data.tasks or {})

		-- Update cache
		cache.tasks = vim.deepcopy(lazydo.tasks)
		cache.last_modified = data.last_modified
		cache.is_dirty = false

		return true
	end)

	if not ok then
		vim.notify("Failed to load tasks: " .. result, vim.log.levels.ERROR)
		lazydo.tasks = {}
		cache.tasks = {}
		cache.is_dirty = true
		return false
	end

	return true
end

-- Mark cache as dirty when tasks are modified
function M.mark_dirty()
	cache.is_dirty = true
end

return M


