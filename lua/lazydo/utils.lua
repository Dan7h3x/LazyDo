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
	date_str = date_str:match("^%s*(.-)%s*$")
	local date = date_str:lower()

	-- Handle special keywords
	if date == "today" then
		return os.time({
			year = os.date("%Y"),
			month = os.date("%m"),
			day = os.date("%d"),
		}) + 86400
	elseif date == "tomorrow" then
		return os.time({
			year = os.date("%Y"),
			month = os.date("%m"),
			day = os.date("%d"),
		}) + 2 * 86400
	end

	local days = date_str:match("^(%d+)d$")
	local weeks = date_str:match("^(%d+)w$")
	if days or weeks then
		days = tonumber(days)
		weeks = tonumber(weeks)
		if days and days >= 0 then
			return os.time() + (days * 86400)
		end

		if weeks and weeks >= 0 then
			return os.time() + (weeks * 7 * 86400)
		end
	else
		return nil
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
	if not timestamp or type(timestamp) ~= "number" or timestamp < 0 then
		return ""
	end
	return os.date("%Y-%m-%d", timestamp)
end

---Format timestamp to relative date string
---@param timestamp number
---@return string
function Utils.Date.relative(timestamp)
	if not timestamp or type(timestamp) ~= "number" or timestamp < 0 then
		return ""
	end

	local now = os.time()
	local diff = os.difftime(timestamp, now)

	local seconds_in_day = 86400
	local seconds_in_hour = 3600
	local seconds_in_minute = 60

	if diff < 0 then
		-- Past time
		local abs_diff = math.abs(diff)
		if abs_diff < seconds_in_minute then
			return "just now"
		elseif abs_diff < seconds_in_hour then
			local minutes = math.floor(abs_diff / seconds_in_minute)
			return minutes .. (minutes == 1 and " minute ago" or " minutes ago")
		elseif abs_diff < seconds_in_day then
			local hours = math.floor(abs_diff / seconds_in_hour)
			return hours .. (hours == 1 and " hour ago" or " hours ago")
		else
			local days = math.floor(abs_diff / seconds_in_day)
			return days .. (days == 1 and " day ago" or " days ago")
		end
	else
		-- Future time
		if diff < seconds_in_minute then
			return "in a few seconds"
		elseif diff < seconds_in_hour then
			local minutes = math.floor(diff / seconds_in_minute)
			return "in " .. minutes .. (minutes == 1 and " minute" or " minutes")
		elseif diff < seconds_in_day then
			local hours = math.floor(diff / seconds_in_hour)
			return "in " .. hours .. (hours == 1 and " hour" or " hours")
		else
			local days = math.floor(diff / seconds_in_day)
			if days == 0 then
				return "today"
			elseif days == 1 then
				return "tomorrow"
			else
				return "in " .. days .. " days"
			end
		end
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
	local is_active = false
	return function(...)
		local args = { ... }
		if timer and is_active then
			timer:stop()
		end
		timer:start(
			ms,
			0,
			vim.schedule_wrap(function()
				is_active = false
				fn(unpack(args))
			end)
		)
		is_active = true
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
	if date_str:match("^%d+d$") or date_str:match("^%d+w$") then
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
---add multiline input support
---@param opts table
---@param callback function
function Utils.multiline_input(opts, callback)
	opts = vim.tbl_extend("force", {
		prompt = "Enter text (Ctrl-D to finish):",
		default = "",
		width = 60,
		height = 10,
		border = "rounded",
		title = " Note Editor ",
		footer = "Ctrl-D: Save | Ctrl-C: Cancel",
		highlight = "Normal",
		buf_options = {
			filetype = "markdown",
			buftype = "nofile",
			modifiable = true,
			swapfile = false,
		},
		win_options = {
			wrap = true,
			linebreak = true,
			number = false,
			cursorline = true,
			signcolumn = "no",
		},
	}, opts or {})

	-- Create temporary buffer for input
	local buf = vim.api.nvim_create_buf(false, true)
	local win = vim.api.nvim_open_win(buf, true, {
		relative = "editor",
		width = opts.width,
		height = opts.height,
		row = math.floor((vim.o.lines - opts.height) / 2),
		col = math.floor((vim.o.columns - opts.width) / 2),
		style = "minimal",
		border = opts.border,
		title = opts.title,
		title_pos = "center",
		footer = opts.footer,
		footer_pos = "center",
	})

	-- Set buffer and window options
	for k, v in pairs(opts.buf_options) do
		vim.api.nvim_buf_set_option(buf, k, v)
	end
	for k, v in pairs(opts.win_options) do
		vim.api.nvim_win_set_option(win, k, v)
	end

	-- Set initial content if provided
	if opts.default and opts.default ~= "" then
		-- Split the default text into lines and set them
		local lines = vim.split(opts.default, "\n", { plain = true })
		vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
	end

	-- Handle submission
	local function submit()
		local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
		-- Filter out empty lines at the end
		while #lines > 0 and lines[#lines] == "" do
			table.remove(lines)
		end
		local text = table.concat(lines, "\n")
		vim.api.nvim_win_close(win, true)
		vim.api.nvim_buf_delete(buf, { force = true })
		if callback then
			callback(text ~= "" and text or nil)
		end
		vim.cmd("stopinsert")
	end

	-- Set up keymaps
	local keymaps = {
		["<C-c>"] = function()
			vim.api.nvim_win_close(win, true)
			vim.api.nvim_buf_delete(buf, { force = true })
			if callback then
				callback(nil)
			end
		end,
		["<C-d>"] = submit,
	}

	for k, v in pairs(keymaps) do
		vim.keymap.set("i", k, v, { buffer = buf, noremap = true })
		vim.keymap.set("n", k, v, { buffer = buf, noremap = true })
	end

	-- Enter insert mode
	vim.cmd("startinsert")
end

---Center align text
---@param str string Text to center
---@param width number Total width
---@return string Centered text
function Utils.Str.center(str, width)
	local padding = width - #str
	if padding <= 0 then
		return str
	end
	local left_pad = math.floor(padding / 2)
	local right_pad = padding - left_pad
	return string.rep(" ", left_pad) .. str .. string.rep(" ", right_pad)
end
-- function Utils.Str.center(text, width)
-- 	local padding = width - vim.fn.strdisplaywidth(text)
-- 	if padding <= 0 then
-- 		return text
-- 	end
-- 	local left = math.floor(padding / 2)
-- 	local right = padding - left
-- 	return string.rep(" ", left) .. text .. string.rep(" ", right)
-- end
function Utils.Str.ellipsis(str, max_length)
	if #str <= max_length then
		return str
	end
	return str:sub(1, max_length - 3) .. "..."
end

function Utils.Str.split_lines(str)
	local lines = {}
	for line in str:gmatch("[^\r\n]+") do
		table.insert(lines, line)
	end
	return lines
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

function Utils.get_window_size(config)
	local width = math.floor(vim.o.columns * (config.layout.width or 0.8))
	local height = math.floor(vim.o.lines * (config.layout.height or 0.8))
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
