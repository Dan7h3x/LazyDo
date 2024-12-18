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
        activetask = "#2D3343",  -- Subtle background for active task
        tag = "#89ddff",         -- Tag color
        metadata = "#565f89",    -- Metadata text color
		progress = {
			full = "#9ece6a",    -- Same as done color
			empty = "#3b4261",   -- Same as border color
		},
		subtask_bullet = "#7dcfff",
    },
	keymaps = {
        -- Task management
        toggle_done = "<Space>",
        edit_task = "e",
        delete_task = "dd",      -- Changed to dd for consistency
        add_task = "a",
        add_subtask = "A",
        edit_subtask = "E",      -- Added explicit subtask edit
		quick_add = "o",         -- Quick add task
		add_below = "O",
        
        -- Movement
        move_up = "K",
        move_down = "J",
        next_task = "j",         -- Added explicit task navigation
        prev_task = "k",
        
        -- Priority management
        increase_priority = ">",
        decrease_priority = "<",
        
        -- Quick actions
        quick_note = "n",
        quick_date = "D",
        toggle_expand = "za",    -- For future expandable tasks
        
        -- Search and sort
        search_tasks = "/",
        sort_by_date = "sd",
        sort_by_priority = "sp",
        
        -- UI controls
        toggle_help = "<C-s>",
        close_window = "q",
        refresh_view = "R",      -- Added refresh view
    },
	ui = {
        width = 0.8,
        height = 0.8,
        border = "rounded",
        winblend = 5,
        title = " LazyDo ",
        highlight = {
            blend = 10,          -- Background blend percentage
            cursorline = true,   -- Highlight cursor line
        }
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
