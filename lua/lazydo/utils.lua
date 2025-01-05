---@class Utils
local Utils = {}

Utils.Str = {}
Utils.Date = {}

---Split string into lines
---@param str string
---@param width number
---@return string[]
function Utils.Str.wrap(str, width)
	if not str or type(str) ~= "string" then
		return {}
	end

	local lines = {}
	local line = ""
	local words = {}

	-- Split string into words safely
	for word in str:gsub("(%s+)", " "):gmatch("%S+") do
		table.insert(words, word)
	end

	for _, word in ipairs(words) do
		if #line + #word + 1 <= width then
			line = line == "" and word or line .. " " .. word
		else
			table.insert(lines, line)
			line = word
		end
	end

	if line ~= "" then
		table.insert(lines, line)
	end

	return lines
end

---Parse date string into timestamp
---@param date_str string
---@return number?
function Utils.Date.parse(date_str)
	if not date_str or date_str == "" then
		return nil
	end

	-- Handle special keywords
	if date_str == "today" then
		return os.time({
			year = os.date("%Y"),
			month = os.date("%m"),
			day = os.date("%d"),
		})
	elseif date_str == "tomorrow" then
		return os.time({
			year = os.date("%Y"),
			month = os.date("%m"),
			day = os.date("%d"),
		}) + 86400
	end

	-- Handle "Nd" format (N days from now)
	local days = date_str:match("^(%d+)d$")
	if days then
		return os.time() + (tonumber(days) * 86400)
	end

	-- Handle YYYY-MM-DD format
	local year, month, day = date_str:match("^(%d%d%d%d)-(%d%d?)-(%d%d?)$")
	if year and month and day then
		return os.time({
			year = tonumber(year),
			month = tonumber(month),
			day = tonumber(day),
		})
	end

	return nil
end

---Format timestamp to date string
---@param timestamp number
---@return string
function Utils.Date.format(timestamp)
	if not timestamp then
		return ""
	end
	return os.date("%Y-%m-%d", timestamp)
end

---Format timestamp to relative date string
---@param timestamp number
---@return string
function Utils.Date.relative(timestamp)
	if not timestamp then
		return ""
	end

	local now = os.time()
	local diff = os.difftime(timestamp, now)
	local days = math.floor(diff / 86400)

	if days < 0 then
		return math.abs(days) .. " days ago"
	elseif days == 0 then
		return "today"
	elseif days == 1 then
		return "tomorrow"
	else
		return days .. " days"
	end
end

---Deep copy a table
---@param tbl table
---@return table
function Utils.deep_copy(tbl)
	if type(tbl) ~= "table" then
		return tbl
	end

	local copy = {}
	for k, v in pairs(tbl) do
		if type(v) == "table" then
			copy[k] = Utils.deep_copy(v)
		else
			copy[k] = v
		end
	end

	return copy
end

---Generate unique ID
---@return string
function Utils.generate_id()
	return string.format("%x%x", os.time(), math.random(0, 0xffff))
end

---Debounce a function
---@param fn function
---@param ms number
---@return function
function Utils.debounce(fn, ms)
	local timer = vim.loop.new_timer()
	return function(...)
		local args = { ... }
		timer:stop()
		timer:start(
			ms,
			0,
			vim.schedule_wrap(function()
				fn(unpack(args))
			end)
		)
	end
end

---Safe JSON encode
---@param data any
---@return string?
function Utils.json_encode(data)
	local success, result = pcall(vim.fn.json_encode, data)
	if success then
		return result
	end
	return nil
end

---Safe JSON decode
---@param str string
---@return table?
function Utils.json_decode(str)
	local success, result = pcall(vim.fn.json_decode, str)
	if success then
		return result
	end
	return nil
end

-- Add new utility functions for improved functionality

---Check if a path exists
---@param path string
---@return boolean
function Utils.path_exists(path)
	local stat = vim.loop.fs_stat(path)
	return stat ~= nil
end

---Ensure directory exists
---@param path string
---@return boolean
function Utils.ensure_dir(path)
	if not Utils.path_exists(path) then
		return vim.fn.mkdir(path, "p") == 1
	end
	return true
end

---Get plugin data directory
---@return string
function Utils.get_data_dir()
	local data_dir = vim.fn.stdpath("data") .. "/lazydo"
	Utils.ensure_dir(data_dir)
	return data_dir
end

---Format duration
---@param seconds number
---@return string
function Utils.format_duration(seconds)
	local days = math.floor(seconds / 86400)
	local hours = math.floor((seconds % 86400) / 3600)
	local minutes = math.floor((seconds % 3600) / 60)

	if days > 0 then
		return string.format("%dd %dh", days, hours)
	elseif hours > 0 then
		return string.format("%dh %dm", hours, minutes)
	else
		return string.format("%dm", minutes)
	end
end

---Safe table merge
---@param t1 table
---@param t2 table
---@return table
function Utils.merge_tables(t1, t2)
	local result = Utils.deep_copy(t1)
	for k, v in pairs(t2) do
		if type(v) == "table" and type(result[k]) == "table" then
			result[k] = Utils.merge_tables(result[k], v)
		else
			result[k] = v
		end
	end
	return result
end

---Validate date string format
---@param date_str string
---@return boolean
function Utils.Date.validate(date_str)
	if not date_str or date_str == "" then
		return false
	end

	-- Check special formats
	if date_str == "today" or date_str == "tomorrow" then
		return true
	end

	-- Check "Nd" format
	if date_str:match("^%d+d$") then
		return true
	end

	-- Check YYYY-MM-DD format
	local year, month, day = date_str:match("^(%d%d%d%d)-(%d%d?)-(%d%d?)$")
	if year and month and day then
		year, month, day = tonumber(year), tonumber(month), tonumber(day)
		if month >= 1 and month <= 12 and day >= 1 and day <= 31 then
			return true
		end
	end

	return false
end

---Center align text
---@param text string Text to center
---@param width number Total width
---@return string Centered text
function Utils.Str.center(text, width)
	local padding = width - vim.fn.strdisplaywidth(text)
	if padding <= 0 then
		return text
	end
	local left = math.floor(padding / 2)
	local right = padding - left
	return string.rep(" ", left) .. text .. string.rep(" ", right)
end

function Utils.Str.truncate(str, width)
    if not str or width <= 0 then
        return ""
    end
    
    if vim.fn.strdisplaywidth(str) <= width then
        return str
    end
    
    local truncated = ""
    local current_width = 0
    
    for char in vim.gsplit(str, "") do
        local char_width = vim.fn.strdisplaywidth(char)
        if current_width + char_width > width - 1 then
            break
        end
        truncated = truncated .. char
        current_width = current_width + char_width
    end
    
    return truncated .. "…"
end

function Utils.is_floating_window(win_id)
	local config = vim.api.nvim_win_get_config(win_id)
	return config.relative ~= ""
end

function Utils.get_window_size()
	local width = math.floor(vim.o.columns * 0.8)
	local height = math.floor(vim.o.lines * 0.8)
	return {
		width = width,
		height = height,
		row = math.floor((vim.o.lines - height) / 2),
		col = math.floor((vim.o.columns - width) / 2),
	}
end

function Utils.create_restore_cursor()
	local win = vim.api.nvim_get_current_win()
	local pos = vim.api.nvim_win_get_cursor(win)
	return function()
		if vim.api.nvim_win_is_valid(win) then
			vim.api.nvim_win_set_cursor(win, pos)
		end
	end
end

Utils.Window = {
	save_state = function()
		return {
			win = vim.api.nvim_get_current_win(),
			pos = vim.api.nvim_win_get_cursor(0),
			view = vim.fn.winsaveview(),
		}
	end,

	restore_state = function(state)
		if state and vim.api.nvim_win_is_valid(state.win) then
			vim.api.nvim_set_current_win(state.win)
			vim.api.nvim_win_set_cursor(state.win, state.pos)
			vim.fn.winrestview(state.view)
		end
	end,
}

---@param path string
---@return table?
function Utils.read_json_file(path)
	local success, result = pcall(vim.fn.json_decode, vim.fn.readfile(path))
	if success then
		return result
	end
	return nil
end

---Write data to JSON file
---@param path string
---@param data any
---@return boolean
function Utils.write_json_file(path, data)
	local success, json_data = pcall(vim.fn.json_encode, data)
	if success then
		vim.fn.writefile({ json_data }, path)
		return true
	end
	return false
end
return Utils
