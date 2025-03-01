-- storage.lua
local Utils = require("lazydo.utils")

---@class Storage
local Storage = {}

-- Private config variable
local config = nil

---Setup storage with configuration
---@param user_config LazyDoConfig
---@return nil
function Storage.setup(user_config)
	if not user_config then
		error("Storage configuration is required")
	end
	config = user_config
end

---@return string
local function get_git_root()
	if not config then
		error("Storage not initialized. Call setup() first")
	end

	-- Only try git root if configured
	if not (config.storage.project.enabled and config.storage.project.use_git_root) then
		return "Global"
	end

	local git_cmd = "git rev-parse --show-toplevel"
	local ok, result = pcall(vim.fn.systemlist, git_cmd)
	if ok and result[1]:match("^fatal:") then
		-- Not a git directory or git command failed
		return "Global"
	end
	return result[1]
end

---@return string
local function get_project_root()
	local cwd = vim.fn.getcwd()
	if not config then
		error("Storage not initialized. Call setup() first")
	end

	if not config.storage.project.enabled then
		return "Global"
	end

	-- Try git root first if configured
	local git_root = get_git_root()
	if git_root and git_root ~= "Global" then
		return git_root
	end

	-- Fallback to current working directory if not "Global"
	if git_root == "Global" then
		return cwd
	end

	return vim.fn.getcwd()
end

---@return string
local function get_storage_path()
    if not config then
        error("Storage not initialized. Call setup() first")
    end

    -- Check for global storage path first
    if not config.storage.project.enabled and config.storage.global_path then
        Utils.ensure_dir(vim.fn.fnamemodify(config.storage.global_path, ":h"))
        return vim.fn.expand(config.storage.global_path)
    end

    if config.storage.project.enabled then
        local project_root = get_project_root()
        if project_root and project_root ~= "Global" then
            local project_path = string.format(config.storage.project.path_pattern, project_root)
            return project_path
        end
    end

    -- Fallback to default path in data directory
    local data_dir = Utils.get_data_dir()
    return data_dir .. "/tasks.json"
end


---@param timestamp? string
---@return string
local function get_backup_path(timestamp)
	local storage_path = get_storage_path()
	local dir = vim.fn.fnamemodify(storage_path, ":h")
	local base = vim.fn.fnamemodify(storage_path, ":t:r")
	return string.format("%s/%s.backup.%s.json", dir, base, timestamp or os.date("%Y%m%d%H%M%S"))
end

---Create backup of current storage
---@return nil
local function create_backup()
	if not config or not config.storage.auto_backup then
		return
	end

	local current_file = get_storage_path()
	if not Utils.path_exists(current_file) then
		return
	end

	local backup_file = get_backup_path()
	vim.fn.writefile(vim.fn.readfile(current_file), backup_file)

	-- Cleanup old backups
	local dir = vim.fn.fnamemodify(current_file, ":h")
	local pattern = vim.fn.fnamemodify(current_file, ":t:r") .. ".backup.*.json"
	local backups = vim.fn.glob(dir .. "/" .. pattern, true, true)
	table.sort(backups)

	-- Keep only the configured number of backups
	while #backups > config.storage.backup_count do
		vim.fn.delete(backups[1])
		table.remove(backups, 1)
	end
end

---Compress data using improved compression
---@param data string
---@return string
local function compress_data(data)
	-- More robust compression that preserves repeated patterns
	local compressed = data:gsub("(.)%1+", function(s)
		local count = #s
		if count > 3 then
			return string.format("##%d##%s", count, s:sub(1, 1))
		end
		return s
	end)

	-- Preserve JSON structure markers
	compressed = compressed:gsub('([{}%[%]":])', function(marker)
		return string.format("##JSON##%s", marker)
	end)

	return compressed
end

---Decompress data with improved safety
---@param data string
---@return string
local function decompress_data(data)
	-- First restore JSON structure markers
	local decompressed = data:gsub("##JSON##(.)", "%1")

	-- Then decompress repeated patterns
	decompressed = decompressed:gsub("##(%d+)##(.)", function(count, char)
		return string.rep(char, tonumber(count))
	end)

	return decompressed
end

---Basic encryption
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

---Load tasks from storage
---@return Task[]
function Storage.load()
	if not config then
		error("Storage not initialized. Call setup() first")
	end

	local file_path = get_storage_path()
	if not Utils.path_exists(file_path) then
		return {}
	end

	local content = vim.fn.readfile(file_path)
	if #content == 0 then
		return {}
	end

	local data = table.concat(content, "\n")

	-- Handle encryption and compression based on config
	if config.storage.encryption then
		data = decrypt_data(data)
	end
	if config.storage.compression then
		data = decompress_data(data)
	end

	local ok, decoded = pcall(vim.json.decode, data)
	if not ok then
		vim.notify("Failed to decode tasks: " .. decoded, vim.log.levels.ERROR)
		return {}
	end

	-- Add project information to loaded tasks
	if config.storage.project.enabled then
		local project_root = get_project_root()
		for _, task in ipairs(decoded) do
			task.project_root = project_root
			task.project_path = file_path
		end
	end

	return decoded
end

---Save tasks to storage
---@param tasks Task[]
function Storage.save(tasks)
	if not config then
		error("Storage not initialized. Call setup() first")
	end

	if config.storage.auto_backup then
		create_backup()
	end

	local ok, encoded = pcall(vim.json.encode, tasks)
	if not ok then
		vim.notify("Failed to encode tasks: " .. encoded, vim.log.levels.ERROR)
		return
	end

	-- Handle compression and encryption based on config
	local data = encoded
	if config.storage.compression then
		data = compress_data(data)
	end
	if config.storage.encryption then
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
---Toggle between project and global storage
---@param mode? "project"|"global" Optional mode to set directly
---@return boolean is_project_mode
function Storage.toggle_mode(mode)
    if not config then
        error("Storage not initialized. Call setup() first")
    end

    -- Get current storage path before changing mode
    local old_storage_path = get_storage_path()
    
    -- Load tasks from current location before switching modes
    local old_tasks = Storage.load()
    
    -- If mode is specified, set it directly
    if mode then
        config.storage.project.enabled = (mode == "project")
    else
        -- Toggle current mode
        config.storage.project.enabled = not config.storage.project.enabled
    end

    -- Create backup before switching modes
    if config.storage.auto_backup and Utils.path_exists(old_storage_path) then
        create_backup()
    end
    
    -- Get new storage path after mode change
    local new_storage_path = get_storage_path()
    
    -- Notify user of mode change
    local mode_str = config.storage.project.enabled and "Project" or "Global"
    vim.notify(string.format("Switched to %s storage mode: %s", mode_str, new_storage_path), vim.log.levels.INFO)

    -- Save tasks to new location
    Storage.save(old_tasks)

    return config.storage.project.enabled
end
---Restore from backup
---@param backup_date? string Optional backup date in format YYYYMMDDHHMMSS
---@return boolean success
function Storage.restore_backup(backup_date)
	if not config then
		error("Storage not initialized. Call setup() first")
	end

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

---Get project information
---@return table
function Storage.get_project_info()
	if not config then
		error("Storage not initialized. Call setup() first")
	end

	local root = get_project_root()
	local is_global = root == "Global"

	return {
		enabled = config.storage.project.enabled,
		root = is_global and nil or root,
		storage_path = get_storage_path(),
		is_project_based = not is_global and config.storage.project.enabled,
	}
end


---@return table
function Storage.get_status()
    if not config then
        error("Storage not initialized. Call setup() first")
    end
	local root = get_project_root()
	local is_global = root == "Global"
    return {
        mode = config.storage.project.enabled and "project" or "global",
        current_path = get_storage_path(),
        global_path = config.storage.global_path,
		root = is_global and nil or root,
        project_enabled = config.storage.project.enabled,
        use_git_root = config.storage.project.use_git_root,
        compression = config.storage.compression,
        encryption = config.storage.encryption,
        auto_backup = config.storage.auto_backup,
        backup_count = config.storage.backup_count
    }
end
-- Create debounced save function
Storage.save_debounced = Utils.debounce(Storage.save, 1000)

return Storage