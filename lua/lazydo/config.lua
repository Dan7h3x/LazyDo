local M = {}

M.defaults = {
	version = "1.0.0",
	storage = {
		path = vim.fn.stdpath("data") .. "/lazydo/tasks.json",
		backup = true,
		auto_save = true,
	},
	icons = {
		task_pending = "󰄱",
		task_done = "󰄵",
		task_overdue = "󰄮",
		due_date = "󰃰",
		note = "󰏫",
		priority = {
			high = "󰀦",
			medium = "󰀧",
			low = "󰀨",
		},
		checkbox = {
			unchecked = "[ ]",
			checked = "[x]",
			overdue = "[!]",
		},
		bullet = "•",
		expand = "▸",
		collapse = "▾",
	},
	colors = {
		header = "#7aa2f7",
		border = "#3b4261",
		pending = "#7aa2f7",
		done = "#9ece6a",
		overdue = "#f7768e",
		note = "#e0af68",
		due_date = "#bb9af7",
		priority = {
			high = "#f7768e",
			medium = "#e0af68",
			low = "#9ece6a",
		},
		subtask = "#7dcfff",
	},
	keymaps = {
		toggle_done = "<Space>",
		edit_task = "e",
		delete_task = "d",
		add_task = "a",
		add_subtask = "A",
		move_up = "K",
		move_down = "J",
		increase_priority = ">",
		decrease_priority = "<",
		quick_note = "n",
		quick_date = "D",
		toggle_expand = "za",
		search_tasks = "/",
		sort_by_date = "sd",
		sort_by_priority = "sp",
	},
	ui = {
		width = 0.8, -- 80% of screen width
		height = 0.8, -- 80% of screen height
		border = "rounded",
		winblend = 5,
		title = " A Lazy Todo Manager  ",
	},
	features = {
		recurring_tasks = true,
		task_notes = true,
		subtasks = true,
		priorities = true,
		due_dates = true,
		tags = true,
		sorting = true,
		filtering = true,
	},
}

return M
