local M = {}

M.defaults = {
	version = "1.0.0",
	storage = {
		-- Allow custom directory or default to data directory
		directory = nil, -- Will be set to vim.fn.stdpath("data") .. "/lazydo" if nil
		filename = "tasks.json",
		auto_save = true,
		save_interval = 30, -- Auto-save interval in seconds
	},
	performance = {
		debounce_refresh = 100, -- Debounce UI refresh in ms
		cache_enabled = true, -- Enable task caching
		lazy_loading = true, -- Load tasks only when needed
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
		search = true,
		task_statistics = true,
		task_history = true,
		task_templates = true,
	},
	icons = {
		task_pending = "",
		task_done = "",
		task_overdue = "󰨱",
		due_date = "󰃰",
		note = "󱞁",
		priority = {
			high = "", -- Changed to match UI constants
			medium = "", -- Changed to match UI constants
			low = "󰻂", -- Changed to match UI constants
		},
		checkbox = {
			unchecked = "[ ]",
			checked = "[x]",
			overdue = "[!]",
		},
		bullet = "",
		expand = "▼", -- Changed to match UI constants
		collapse = "▶", -- Changed to match UI constants
		search = "",
		filter = "",
		sort = "󰒿",
		template = "󰗀",
		progress = { -- Added new progress icons
			full = "●",
			empty = "○",
		},
		subtask = { -- Added new subtask icons
			branch = "├─",
			last = "└─",
		},
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
		activetask = "#2D3343",
		activeborder = "#7aa2f7", -- Added new color for active task border
		tag = "#89ddff",
		metadata = "#565f89",
		progress = {
			full = "#50fa7b", -- Green color for filled progress
			empty = "#ffffff", -- White color for empty progress
		},
		subtask_bullet = "#7dcfff",
		search_highlight = "#bb9af7",
		filter_active = "#7aa2f7",
	},
	keymaps = {
		-- Task management
		toggle_done = "<CR>",
		toggle_subtask = "<C-CR>", -- Added new keymap for subtask toggle
		edit_task = "e",
		delete_task = "dd",
		add_task = "a",
		add_subtask = "A",
		edit_subtask = "E",
		quick_add = "o",
		add_below = "O",

		-- Movement
		move_up = "K",
		move_down = "J",

		-- Priority management
		increase_priority = ">",
		decrease_priority = "<",

		-- Quick actions
		quick_note = "n",
		quick_date = "D",

		search = "s",
		filter = "f",
		clear_filter = "F",
		sort_menu = "S",
		templates = "t",
		quick_stats = "I",

		-- Window control
		close_window = "q", -- Added explicit close window keymap
		refresh_view = "R", -- Added explicit refresh view keymap
		toggle_help = "<C-s>", -- Added explicit help toggle keymap
	},
	ui = {
		width = 0.8,
		height = 0.8,
		border = "rounded",
		winblend = 5,
		title = " LazyDo Task manager ",
		highlight = {
			blend = 5,
			cursorline = true,
		},
		animations = true, -- Enable/disable animations
		show_progress = true, -- Show progress bars
		show_stats = true, -- Show statistics
	},
}

return M
