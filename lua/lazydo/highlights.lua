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
    TaskNotes = { link = "Special" },          -- Orange from Special
    TaskDate = { link = "Constant" },          -- Purple from Constant
    TaskSubtask = { link = "Type" },           -- Cyan from Type
    TaskPriorityHigh = { link = "Error" },     -- Red from Error
    TaskPriorityMed = { link = "WarningMsg" }, -- Yellow from WarningMsg
    TaskPriorityLow = { link = "Comment" },    -- Gray from Comment
    TaskProgress = { link = "Function" },      -- For progress bar
    TaskBorder = { link = "FloatBorder" },     -- For window border
    TaskTitle = { link = "Title" },            -- For section titles
    SubtaskConnector = { link = "Connector" },
    ProgressBarBorder = { link = "ProgressBorder" },
    HeaderSeparator = { fg = colors.header.fg },

    TaskRelation = { link = "Special" },
    TaskRelationTarget = { link = "String" },
    TaskRelationType = { link = "Type" },

    -- Header and title components
    Header = {
      fg = colors.header.fg,
      bold = colors.header.bold,
    },
    Title = {
      fg = colors.title.fg,
      bold = colors.title.bold,
    },
    HeaderBorder = {
      fg = colors.header.fg,
    },
    HeaderText = {
      fg = colors.header.fg or "#ffaaff",
    },

    -- Task status highlights with all states
    TaskPending = {
      fg = colors.task.pending.fg,
      italic = colors.task.pending.italic,
    },
    TaskDone = {
      fg = colors.task.done.fg,
      italic = colors.task.done.italic,
      strikethrough = true,
    },
    TaskOverdue = {
      fg = colors.task.overdue.fg,
      bold = colors.task.overdue.bold,
    },
    TaskBlocked = {
      fg = colors.task.blocked.fg or colors.task.overdue.fg,
      italic = true,
    },
    TaskInProgress = {
      fg = colors.task.in_progress.fg or colors.task.pending.fg,
      bold = true,
    },

    -- Priority highlights with enhanced states
    PriorityHigh = {
      fg = colors.priority.high.fg,
      bold = true,
    },
    PriorityMedium = {
      fg = colors.priority.medium.fg,
    },
    PriorityLow = {
      fg = colors.priority.low.fg,
    },
    PriorityUrgent = {
      fg = colors.priority.urgent.fg or colors.priority.high.fg,
      bold = true,
    },

    -- Note highlights with improved visual hierarchy
    NotesIcon = {
      fg = colors.notes.header.fg or "#7dcfff",
      bold = true,
    },
    NotesTitle = {
      fg = colors.notes.header.fg or "#7aa2f7",
      bold = true,
    },
    NotesBorder = {
      fg = colors.notes.border.fg or "#3b4261",
    },
    NotesBody = {
      fg = colors.notes.body.fg or "#c0caf5",
      italic = true,
    },

    -- Due date with different states
    DueDate = {
      fg = colors.due_date.fg,
    },
    DueDateNear = {
      fg = colors.due_date.near.fg or colors.due_date.fg,
      bold = true,
    },
    DueDateOverdue = {
      fg = colors.due_date.overdue.fg or colors.task.overdue.fg,
    },

    ProgressComplete = {
      fg = colors.progress.complete.fg,
    },
    ProgressPartial = {
      fg = colors.progress.partial.fg,
    },
    ProgressNone = {
      fg = colors.progress.none.fg,
    },

    -- Tags with enhanced styling
    Tags = {
      fg = config.features.tags.colors.fg,
    },

    -- Metadata with enhanced components
    MetadataKey = {
      fg = config.features.metadata.colors.key.fg,
      bold = true,
    },
    MetadataValue = {
      fg = config.features.metadata.colors.value.fg,
    },
    MetadataSection = {
      fg = config.features.metadata.colors.section.fg or config.features.metadata.colors.key.fg,
      bold = true,
      italic = true,
    },

    -- Folding and structure indicators
    FoldIcon = {
      fg = colors.title.fg,
    },
    FoldIconExpanded = {
      fg = colors.fold.expanded.fg or colors.title.fg,
      bold = true,
    },
    FoldIconCollapsed = {
      fg = colors.fold.collapsed.fg or colors.title.fg,
    },

    -- Separators and structural elements
    Separator = {
      fg = colors.separator.fg,
    },
    SeparatorVertical = {
      fg = colors.separator.vertical.fg or colors.separator.fg,
    },
    SeparatorHorizontal = {
      fg = colors.separator.horizontal.fg or colors.separator.fg,
    },
    TaskInfo = {
      fg = colors.task.info.fg or colors.task.pending.fg,
      italic = true,
    },

    SearchMatch = {
      fg = colors.search.match.fg,
      bold = true,
    },

    SubtaskIndicator = {
      fg = colors.indent.indicator.fg or colors.separator.fg,
      bold = true,
    },

    -- Help and UI elements
    Help = {
      fg = colors.help.fg,
    },
    HelpKey = {
      fg = colors.help.key.fg or colors.help.fg,
      bold = true,
    },
    HelpText = {
      fg = colors.help.text.fg or colors.help.fg,
      italic = true,
    },

    -- Task structure and indentation
    Connector = {
      fg = colors.indent.connector.fg,
    },
    IndentGuide = {
      fg = colors.indent.line.fg or "#3b4261",
      nocombine = true,
    },
    IndentLine = {
      fg = colors.indent.line.fg or "#3b4261",
      nocombine = true,
    },
    IndentConnector = {
      fg = colors.indent.connector.fg or "#3bf2f1",
      nocombine = true,
    },

    -- Selection and cursor
    Selection = {
      fg = colors.selection.fg or colors.task.pending.fg,
      bold = true,
    },
    PinWindowBorder = {
      fg = config.pin_window.colors.border.fg,
    },
    PinWindowTitle = {
      fg = config.pin_window.colors.title.fg,
      bold = config.pin_window.colors.title.bold,
    },
    StorageMode = { fg = colors.storage.fg, bold = colors.storage.bold },

    -- Status line and UI elements
    Status = {
      fg = "#c0caf5",
      bold = true,
    },

    -- Improved kanban highlights
    KanbanColumnHeaderIcon = {
      fg = "#7dcfff",
      bold = true,
    },
    KanbanColumnBorderVertical = {
      fg = "#3b4261",
    },
    KanbanTaskUrgent = {
      fg = "#ff0000",
      bold = true,
    },
    KanbanTaskHigh = {
      fg = "#ff7700",
      bold = true,
    },
    KanbanTaskMedium = {
      fg = "#ffff00",
    },
    KanbanTaskLow = {
      fg = "#00ff00",
    },
    KanbanStatusPending = {
      fg = "#c0caf5",
    },
    KanbanStatusInProgress = {
      fg = "#7aa2f7",
      bold = true,
    },
    KanbanStatusBlocked = {
      fg = "#f7768e",
      italic = true,
    },
    KanbanStatusDone = {
      fg = "#9ece6a",
      strikethrough = true,
    },
    KanbanDragIndicator = {
      fg = "#7aa2f7",
      bold = true,
    },
    KanbanInfoText = {
      fg = "#565f89",
      italic = true,
    },
  }

  -- Create all highlight groups
  for name, opts in pairs(highlights) do
    create_highlight(name, opts)
  end

  -- Kanban view highlights
  if config.views and config.views.kanban and config.views.kanban.enabled then
    vim.api.nvim_set_hl(0, "LazyDoKanbanColumnHeader", config.views.kanban.colors.column_header)
    vim.api.nvim_set_hl(0, "LazyDoKanbanCardBorder", config.views.kanban.colors.card_border)
    vim.api.nvim_set_hl(0, "LazyDoKanbanCardTitle", config.views.kanban.colors.card_title)
    vim.api.nvim_set_hl(0, "LazyDoKanbanDragActive", { fg = "#ffffff", bg = "#7aa2f7", bold = true })
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
