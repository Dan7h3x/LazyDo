local M = {}

function M.center(text, width)
	local padding = width - vim.fn.strdisplaywidth(text)
	if padding <= 0 then
		return text
	end
	local left_pad = math.floor(padding / 2)
	local right_pad = padding - left_pad
	return string.rep(" ", left_pad) .. text .. string.rep(" ", right_pad)
end

function M.word_wrap(str, width)
	if not str then
		return {}
	end
	local lines = {}
	local line = ""
	for word in str:gmatch("%S+") do
		if #line + #word + 1 > width then
			table.insert(lines, line)
			line = word
		else
			line = #line == 0 and word or line .. " " .. word
		end
	end
	if #line > 0 then
		table.insert(lines, line)
	end
	return lines
end

function M.pad_right(str, width)
	return str .. string.rep(" ", width - vim.fn.strdisplaywidth(str))
end

function M.parse_date(date_str)
	-- Support various date formats
	local patterns = {
		"^(%d%d%d%d)%-(%d%d)%-(%d%d)$", -- YYYY-MM-DD
		"^(%d%d)%-(%d%d)%-(%d%d%d%d)$", -- DD-MM-YYYY
		"^(%d%d)/(%d%d)/(%d%d%d%d)$", -- DD/MM/YYYY
		"^today$",
		"^tomorrow$",
		"^(%d+)d$", -- Xd (X days from now)
		"^(%d+)w$", -- Xw (X weeks from now)
		"^(%d+)m$", -- Xm (X months from now)
	}

	-- Handle special keywords
	if date_str == "today" then
		return os.time({ year = os.date("*t").year, month = os.date("*t").month, day = os.date("*t").day })
	elseif date_str == "tomorrow" then
		return os.time({ year = os.date("*t").year, month = os.date("*t").month, day = os.date("*t").day }) + 86400
	end

	-- Handle relative dates
	local num, unit = date_str:match("^(%d+)([dwm])$")
	if num and unit then
		local days = num
		if unit == "w" then
			days = days * 7
		elseif unit == "m" then
			days = days * 30
		end
		return os.time() + (days * 86400)
	end

	-- Handle standard date formats
	for _, pattern in ipairs(patterns) do
		local y, m, d = date_str:match(pattern)
		if y and m and d then
			return os.time({ year = tonumber(y), month = tonumber(m), day = tonumber(d) })
		end
	end

	return nil
end

function M.format_date(timestamp)
	if not timestamp then
		return ""
	end
	return os.date("%Y-%m-%d", timestamp)
end

function M.debounce(fn, ms)
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

function M.deep_copy(orig)
	local copy
	if type(orig) == "table" then
		copy = {}
		for orig_key, orig_value in next, orig, nil do
			copy[M.deep_copy(orig_key)] = M.deep_copy(orig_value)
		end
		setmetatable(copy, M.deep_copy(getmetatable(orig)))
	else
		copy = orig
	end
	return copy
end

return M

