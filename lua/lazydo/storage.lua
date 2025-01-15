-- storage.lua
local Utils = require("lazydo.utils")

---@class Storage
local Storage = {}

---@class StorageOptions
---@field auto_backup boolean Enable automatic backups
---@field backup_count number Number of backups to keep
---@field compression boolean Enable data compression
---@field encryption boolean Enable basic encryption
local DEFAULT_OPTIONS = {
	auto_backup = true,
	backup_count = 5,
	compression = true,
	encryption = false,
}

-- Private functions
local function get_storage_path()
	local data_dir = Utils.get_data_dir()
	return data_dir .. "/tasks.json"
end

local function get_backup_path(timestamp)
	local data_dir = Utils.get_data_dir()
	return string.format("%s/tasks.backup.%s.json", data_dir, timestamp or os.date("%Y%m%d%H%M%S"))
end

local function create_backup()
	local current_file = get_storage_path()
	if not Utils.path_exists(current_file) then
		return
	end

	local backup_file = get_backup_path()
	vim.fn.writefile(vim.fn.readfile(current_file), backup_file)

	-- Cleanup old backups
	local data_dir = Utils.get_data_dir()
	local backups = vim.fn.glob(data_dir .. "/tasks.backup.*.json", true, true)
	table.sort(backups)

	-- Keep only the most recent backups
	while #backups > DEFAULT_OPTIONS.backup_count do
		vim.fn.delete(backups[1])
		table.remove(backups, 1)
	end
end

---Validate task data structure
---@param task table
---@return boolean
---@return string? error
local function validate_task(task)
	if type(task) ~= "table" then
		return false, "Task must be a table"
	end

	-- Check required fields
	local required_fields = { "id", "content", "status", "priority", "created_at", "updated_at" }
	for _, field in ipairs(required_fields) do
		if task[field] == nil then
			return false, string.format("Missing required field: %s", field)
		end
	end

	-- Validate status
	if not vim.tbl_contains({ "pending", "done" }, task.status) then
		return false, "Invalid status value"
	end

	-- Validate priority
	if not vim.tbl_contains({ "low", "medium", "high" }, task.priority) then
		return false, "Invalid priority value"
	end

	-- Validate dates
	if task.due_date and type(task.due_date) ~= "number" then
		return false, "Invalid due_date format"
	end

	-- Validate subtasks recursively
	if task.subtasks then
		if type(task.subtasks) ~= "table" then
			return false, "Subtasks must be a table"
		end
		for _, subtask in ipairs(task.subtasks) do
			local valid, err = validate_task(subtask)
			if not valid then
				return false, "Invalid subtask: " .. err
			end
		end
	end

	return true
end

---Compress data using basic compression
---@diagnostic disable-next-line: undefined-doc-param
---@param data string
---@return string

local function compress_data(data)
	local compressed = data:gsub("(.)%1+", function(s)
		local char = s:sub(1, 1)
		local count = #s
		if count > 8 then
			return string.format("##%d##%s", count, char)
		end
		return s
	end)
	return compressed
end

---Decompress data
---@param data string
---@return string
local function decompress_data(data)
	local decompressed = data:gsub("##(%d+)##(.)", function(count, char)
		return string.rep(char, tonumber(count))
	end)
	return decompressed
end
---@param data string
---@return string
local function encrypt_data(data)
	local result = {}
	for i = 1, #data do
		local byte = data:byte(i)
		table.insert(result, string.char((byte + 7) % 256))
	end
	return table.concat(result)
end

---Basic decryption
---@param data string
---@return string
local function decrypt_data(data)
	local result = {}
	for i = 1, #data do
		local byte = data:byte(i)
		table.insert(result, string.char((byte - 7) % 256))
	end
	return table.concat(result)
end

-- Public API

---Load tasks from storage
---@return Task[]
function Storage.load()
	local file_path = get_storage_path()
	if not Utils.path_exists(file_path) then
		return {}
	end

	local content = vim.fn.readfile(file_path)
	if #content == 0 then
		return {}
	end

	local data = table.concat(content, "\n")

	-- Handle compression and encryption
	if DEFAULT_OPTIONS.encryption then
		data = decrypt_data(data)
	end
	if DEFAULT_OPTIONS.compression then
		data = decompress_data(data)
	end

	local ok, decoded = pcall(vim.json.decode, data)
	if not ok then
		vim.notify("Failed to decode tasks: " .. decoded, vim.log.levels.ERROR)
		return {}
	end

	-- Validate loaded data
	local tasks = {}
	for _, task_data in ipairs(decoded) do
		local valid, err = validate_task(task_data)
		if valid then
			table.insert(tasks, task_data)
		else
			vim.notify("Invalid task data: " .. err, vim.log.levels.WARN)
		end
	end

	return tasks
end

---Save tasks to storage
---@param tasks Task[]
function Storage.save(tasks)
	if DEFAULT_OPTIONS.auto_backup then
		create_backup()
	end

	local ok, encoded = pcall(vim.json.encode, tasks)
	if not ok then
		vim.notify("Failed to encode tasks: " .. encoded, vim.log.levels.ERROR)
		return
	end

	-- Handle compression and encryption
	local data = encoded
	if DEFAULT_OPTIONS.compression then
		data = compress_data(data)
	end
	if DEFAULT_OPTIONS.encryption then
		data = encrypt_data(data)
	end

	local lines = vim.split(data, "\n")
	local file_path = get_storage_path()

	-- Ensure storage directory exists
	Utils.ensure_dir(vim.fn.fnamemodify(file_path, ":h"))

	-- Write file atomically
	local temp_file = file_path .. ".tmp"
	local success = pcall(vim.fn.writefile, lines, temp_file)
	if success then
		vim.uv.fs_rename(temp_file, file_path)
	else
		vim.notify("Failed to save tasks", vim.log.levels.ERROR)
		pcall(vim.fn.delete, temp_file)
	end
end

---Restore from backup
---@param backup_date? string Optional backup date in format YYYYMMDDHHMMSS
---@return boolean success
function Storage.restore_backup(backup_date)
	local backup_file
	if backup_date then
		backup_file = get_backup_path(backup_date)
		if not Utils.path_exists(backup_file) then
			vim.notify("Backup not found: " .. backup_file, vim.log.levels.ERROR)
			return false
		end
	else
		-- Find most recent backup
		local data_dir = Utils.get_data_dir()
		local backups = vim.fn.glob(data_dir .. "/tasks.backup.*.json", true, true)
		table.sort(backups)
		backup_file = backups[#backups]
		if not backup_file then
			vim.notify("No backups found", vim.log.levels.ERROR)
			return false
		end
	end

	local current_file = get_storage_path()
	local success = pcall(vim.fn.writefile, vim.fn.readfile(backup_file), current_file)
	if success then
		vim.notify("Successfully restored from backup", vim.log.levels.INFO)
		return true
	else
		vim.notify("Failed to restore from backup", vim.log.levels.ERROR)
		return false
	end
end

-- Create debounced save function
Storage.save_debounced = Utils.debounce(Storage.save, 1000)

return Storage
