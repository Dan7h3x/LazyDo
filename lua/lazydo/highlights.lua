local M = {}

local function create_highlight(name, opts)
	vim.api.nvim_set_hl(0, "LazyDo" .. name, opts)
end

function M.setup(config)
	if not config or not config.theme or not config.theme.colors then
		error("Invalid theme configuration")
		return
	end

	local colors = config.theme.colors

	-- Base highlights linking to common Neovim groups
	local highlights = {
		TaskNotes = { link = "Special" }, -- Orange from Special
		TaskDate = { link = "Constant" }, -- Purple from Constant
		TaskSubtask = { link = "Type" }, -- Cyan from Type
		TaskPriorityHigh = { link = "Error" }, -- Red from Error
		TaskPriorityMed = { link = "WarningMsg" }, -- Yellow from WarningMsg
		TaskPriorityLow = { link = "Comment" }, -- Gray from Comment
		TaskProgress = { link = "Function" }, -- For progress bar
		TaskBorder = { link = "FloatBorder" }, -- For window border
		TaskTitle = { link = "Title" }, -- For section titles
		SubtaskConnector = { link = "Connector" },
		ProgressBarBorder = { link = "ProgressBorder" },
		HeaderSeparator = { fg = colors.header.fg },

		TaskRelation = { link = "Special" },
		TaskRelationTarget = { link = "String" },
		TaskRelationType = { link = "Type" },

		-- Header and title components
		Header = {
			fg = colors.header.fg,
			-- bg = colors.header.bg,
			bold = colors.header.bold,
		},
		Title = {
			fg = colors.title.fg,
			-- bg = colors.title.bg,
			bold = colors.title.bold,
		},
		HeaderBorder = {
			fg = colors.header.fg,
			-- bg = colors.header.bg,
		},
		HeaderText = {
			fg = colors.header.fg or "#ffaaff",
		},

		-- Task status highlights with all states
		TaskPending = {
			fg = colors.task.pending.fg,
			-- bg = colors.task.pending.bg,
			italic = colors.task.pending.italic,
		},
		TaskDone = {
			fg = colors.task.done.fg,
			-- bg = colors.task.done.bg,
			italic = colors.task.done.italic,
			strikethrough = true,
		},
		TaskOverdue = {
			fg = colors.task.overdue.fg,
			-- bg = colors.task.overdue.bg,
			bold = colors.task.overdue.bold,
		},
		TaskBlocked = {
			fg = colors.task.blocked.fg or colors.task.overdue.fg,
			-- bg = colors.task.blocked.bg or colors.task.overdue.bg,
			italic = true,
		},
		TaskInProgress = {
			fg = colors.task.in_progress.fg or colors.task.pending.fg,
			-- bg = colors.task.in_progress.bg or colors.task.pending.bg,
			bold = true,
		},

		-- Priority highlights with enhanced states
		PriorityHigh = {
			fg = colors.priority.high.fg,
			-- bg = colors.priority.high.bg,
			bold = true,
		},
		PriorityMedium = {
			fg = colors.priority.medium.fg,
			-- bg = colors.priority.medium.bg,
		},
		PriorityLow = {
			fg = colors.priority.low.fg,
			-- bg = colors.priority.low.bg,
		},
		PriorityUrgent = {
			fg = colors.priority.urgent.fg or colors.priority.high.fg,
			-- bg = colors.priority.urgent.bg or colors.priority.high.bg,
			bold = true,
		},

		-- In highlights.lua, add these highlight definitions:
		NotesIcon = {
			fg = colors.notes.header.fg or "#7dcfff",
			-- bg = colors.notes.header.bg,
			bold = true,
		},
		NotesTitle = {
			fg = colors.notes.header.fg or "#7aa2f7",
			-- bg = colors.notes.header.bg,
			bold = true,
		},
		NotesBorder = {
			fg = colors.notes.border.fg or "#3b4261",
			-- bg = colors.notes.border.bg,
		},
		NotesBody = {
			fg = colors.notes.body.fg or "#c0caf5",
			-- bg = colors.notes.body.bg,
			italic = true,
		},

		-- Due date with different states
		DueDate = {
			fg = colors.due_date.fg,
			-- bg = colors.due_date.bg,
		},
		DueDateNear = {
			fg = colors.due_date.near.fg or colors.due_date.fg,
			-- bg = colors.due_date.near.bg or colors.due_date.bg,
			bold = true,
		},
		DueDateOverdue = {
			fg = colors.due_date.overdue.fg or colors.task.overdue.fg,
			-- bg = colors.due_date.overdue.bg or colors.task.overdue.bg,
		},

		ProgressComplete = {
			fg = colors.progress.complete.fg,
			-- bg = colors.progress.complete.bg,
		},
		ProgressPartial = {
			fg = colors.progress.partial.fg,
			-- bg = colors.progress.partial.bg,
		},
		ProgressNone = {
			fg = colors.progress.none.fg,
			-- bg = colors.progress.none.bg,
		},

		-- Tags with enhanced styling
		Tags = {
			fg = config.features.tags.colors.fg,
			-- bg = config.features.tags.colors.bg,
		},

		-- Metadata with enhanced components
		MetadataKey = {
			fg = config.features.metadata.colors.key.fg,
			-- bg = config.features.metadata.colors.key.bg,
			bold = true,
		},
		MetadataValue = {
			fg = config.features.metadata.colors.value.fg,
			-- bg = config.features.metadata.colors.value.bg,
		},
		MetadataSection = {
			fg = config.features.metadata.colors.section.fg or config.features.metadata.colors.key.fg,
			-- bg = config.features.metadata.colors.section.bg or config.features.metadata.colors.key.bg,
			bold = true,
			italic = true,
		},

		-- Folding and structure indicators
		FoldIcon = {
			fg = colors.title.fg,
			-- bg = colors.title.bg,
		},
		FoldIconExpanded = {
			fg = colors.fold.expanded.fg or colors.title.fg,
			-- bg = colors.fold.expanded.bg or colors.title.bg,
			bold = true,
		},
		FoldIconCollapsed = {
			fg = colors.fold.collapsed.fg or colors.title.fg,
			-- bg = colors.fold.collapsed.bg or colors.title.bg,
		},

		-- Separators and structural elements
		Separator = {
			fg = colors.separator.fg,
			-- bg = colors.separator.bg,
		},
		SeparatorVertical = {
			fg = colors.separator.vertical.fg or colors.separator.fg,
			-- bg = colors.separator.vertical.bg or colors.separator.bg,
		},
		SeparatorHorizontal = {
			fg = colors.separator.horizontal.fg or colors.separator.fg,
			-- bg = colors.separator.horizontal.bg or colors.separator.bg,
		},
		TaskInfo = {
			fg = colors.task.info.fg or colors.task.pending.fg,
			-- bg = colors.task.info.bg or colors.task.pending.bg,
			italic = true,
		},

		SearchMatch = {
			fg = colors.search.match.fg or colors.task.pending.fg,
			-- bg = colors.search.match.bg or "#445588",
			bold = true,
		},

		SubtaskIndicator = {
			fg = colors.indent.indicator.fg or colors.separator.fg,
			-- bg = colors.indent.indicator.bg or colors.separator.bg,
			bold = true,
		},

		-- Help and UI elements
		Help = {
			fg = colors.help.fg,
			-- bg = colors.help.bg,
		},
		HelpKey = {
			fg = colors.help.key.fg or colors.help.fg,
			-- bg = colors.help.key.bg or colors.help.bg,
			bold = true,
		},
		HelpText = {
			fg = colors.help.text.fg or colors.help.fg,
			-- bg = colors.help.text.bg or colors.help.bg,
			italic = true,
		},

		-- Task structure and indentation
		Connector = {
			fg = colors.indent.connector.fg,
			-- bg = colors.separator.bg,
		},
		IndentGuide = {
			fg = colors.separator.fg,
			-- bg = colors.separator.bg,
		},
		IndentLine = {
			fg = colors.indent.line.fg,
			-- bg = colors.indent.line.bg or colors.separator.bg,
		},
		IndentConnector = {
			fg = colors.indent.connector.fg,
			-- bg = colors.indent.connector.bg or colors.separator.bg,
		},

		-- Selection and cursor
		Selection = {
			fg = colors.selection.fg or colors.task.pending.fg,
			-- bg = colors.selection.bg or colors.task.pending.bg,
			bold = true,
		},
		PinWindowBorder = {
			fg = config.pin_window.colors.border.fg,
		},
		PinWindowTitle = {
			fg = config.pin_window.colors.title.fg,
			bold = config.pin_window.colors.title.bold,
		},
	}

	-- Create all highlight groups
	for name, opts in pairs(highlights) do
		create_highlight(name, opts)
	end
end

function M.groups()
	return {
		done = "TaskDone",
		pending = "TaskPending",
		notes = "TaskNotes",
		date = "TaskDate",
		subtask = "TaskSubtask",
		priority = {
			high = "TaskPriorityHigh",
			medium = "TaskPriorityMed",
			low = "TaskPriorityLow",
		},
		progress = "TaskProgress",
		border = "TaskBorder",
		title = "TaskTitle",
		feedback = {
			info = "FeedbackInfo",
			warn = "FeedbackWarn",
			error = "FeedbackError",
		},
		selected = "TaskSelected",
		header = "TaskHeader",
		progress_bar = {
			fill = "ProgressBarFill",
			empty = "ProgressBarEmpty",
		},
	}
end

return M
