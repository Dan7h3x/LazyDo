local M = {}
local Task = require("lazydo.task").Task

-- Add validation function
local function validate_data(data)
	if type(data) ~= "table" then
		return false, "Data must be a table"
	end

	if not data.version then
		return false, "Missing version information"
	end

	if not data.tasks or type(data.tasks) ~= "table" then
		-- If no tasks found, return empty but valid data
		data.tasks = {}
		return true, data
	end

	return true, data
end

function M.ensure_storage_path(path)
	local dir = vim.fn.fnamemodify(path, ":h")
	if vim.fn.isdirectory(dir) == 0 then
		vim.fn.mkdir(dir, "p")
	end
end

function M.save_tasks(lazydo)
	local ok, err = pcall(function()
		M.ensure_storage_path(lazydo.opts.storage.path)

		-- Prepare backup if enabled
		if lazydo.opts.storage.backup then
			local backup_path = lazydo.opts.storage.path .. ".bak"
			if vim.fn.filereadable(lazydo.opts.storage.path) == 1 then
				if vim.fn.filereadable(backup_path) == 1 then
					vim.fn.delete(backup_path)
				end
				vim.fn.rename(lazydo.opts.storage.path, backup_path)
			end
		end

		-- Prepare data for saving
		local save_data = {
			version = lazydo.opts.version or "1.0.0",
			last_modified = os.time(),
			tasks = vim.tbl_map(function(task)
				return task:serialize()
			end, lazydo.tasks or {}),
		}

		-- Write atomically using temporary file
		local temp_path = lazydo.opts.storage.path .. ".tmp"
		local file = io.open(temp_path, "w")
		if not file then
			error("Could not open temporary file for writing: " .. temp_path)
		end

		local json_str = vim.json.encode(save_data)
		file:write(json_str)
		file:close()

		-- Atomic rename
		if vim.fn.rename(temp_path, lazydo.opts.storage.path) ~= 0 then
			error("Failed to rename temporary file")
		end
	end)

	if not ok then
		vim.notify("Failed to save tasks: " .. err, vim.log.levels.ERROR)
		return false
	end
	return true
end

function M.load_tasks(lazydo)
	local ok, result = pcall(function()
		local path = lazydo.opts.storage.path
		local backup_path = path .. ".bak"

		-- Initialize empty tasks if no storage exists
		if vim.fn.filereadable(path) == 0 and vim.fn.filereadable(backup_path) == 0 then
			lazydo.tasks = {}
			-- Create initial storage
			M.save_tasks(lazydo)
			return true
		end

		-- Try loading main file first
		local file = io.open(path, "r")
		if not file and vim.fn.filereadable(backup_path) == 1 then
			-- Try backup if main file fails
			file = io.open(backup_path, "r")
			if file then
				vim.notify("Loading from backup file", vim.log.levels.WARN)
			end
		end

		if not file then
			lazydo.tasks = {}
			return true
		end

		local content = file:read("*all")
		file:close()

		-- Safely decode JSON
		local ok_decode, data = pcall(vim.json.decode, content)
		if not ok_decode then
			error("Invalid JSON format: " .. data)
		end

		-- Validate data structure
		local valid, result = validate_data(data)
		if not valid then
			error(result)
		end

		-- Version check and migration if needed
		if data.version ~= (lazydo.opts.version or "1.0.0") then
			data = M.migrate_data(data, lazydo.opts.version or "1.0.0")
		end

		-- Deserialize tasks with error handling
		lazydo.tasks = vim.tbl_map(function(task_data)
			local ok_task, task = pcall(Task.deserialize, task_data)
			if not ok_task then
				vim.notify("Failed to deserialize task: " .. vim.inspect(task_data), vim.log.levels.WARN)
				return nil
			end
			return task
		end, data.tasks)

		-- Filter out any failed tasks
		lazydo.tasks = vim.tbl_filter(function(task)
			return task ~= nil
		end, lazydo.tasks)

		return true
	end)

	if not ok then
		vim.notify("Failed to load tasks: " .. result, vim.log.levels.ERROR)
		lazydo.tasks = {}
		-- Create new storage with empty tasks
		M.save_tasks(lazydo)
		return false
	end

	return true
end

function M.migrate_data(data, target_version)
	-- Add migration logic here when needed
	-- For now, just ensure the basic structure
	return {
		version = target_version,
		last_modified = data.last_modified or os.time(),
		tasks = data.tasks or {},
	}
end

return M

