-- ui.lua
local Utils = require("lazydo.utils")
local Task = require("lazydo.task")
local Actions = require("lazydo.actions")

---@class UI
local UI = {}

-- Add config as a module-level variable
local config = nil

local ns_id = vim.api.nvim_create_namespace("LazyDo")
local buf_name = "LazyDo"

---@class UIState
---@field buf number Buffer handle
---@field win number Window handle
---@field tasks Task[] Current tasks
---@field cursor_task? Task Task under cursor
---@field line_to_task table<number, {task: Task, mapping: table}>
---@field task_to_line table<string, number>
---@field on_task_update function?
local state = {
  buf = nil,
  win = nil,
  tasks = {},
  cursor_task = nil,
  line_to_task = {}, -- Map line numbers to tasks
  task_to_line = {}, -- Map task IDs to line numbers
  on_task_update = nil,
  search_results = {},
  current_search = nil,
  show_task_info = false,
}

local function ensure_number(value, default)
  if type(value) == "number" then
    return value
  end
  return default or 0
end

local function get_safe_window_width()
  if not state.win then
    return 80 -- Default width
  end
  local ok, width = pcall(vim.api.nvim_win_get_width, state.win)
  return ok and width or 80
end

---@return string
function UI:get_storage_mode_info()
  local storage_info = require("lazydo.storage").get_status()
  local mode_icon = "" -- Default storage icon

  if storage_info.selected_storage == "custom" and storage_info.custom_project_name then
    -- Custom project storage
    return string.format(" %s Custom Project: %s ", mode_icon, storage_info.custom_project_name)
  elseif storage_info.mode == "project" then
    -- Project storage
    local root = vim.fn.fnamemodify(storage_info.project_root, ":t")
    return string.format(" %s Project: %s ", mode_icon, root)
  else
    -- Global storage
    return string.format(" %s Global ", mode_icon)
  end
end

local function create_task_separator(level, width)
  level = level or 0
  width = width or get_safe_window_width()

  local left_separator_char = config and config.theme.task_separator.left or "❮"
  local right_separator_char = config and config.theme.task_separator.right or "❯"
  local center_separator_char = config and config.theme.task_separator.center or "─"
  local indent = string.rep(" ", level)
  local separator_char = level == 0 and center_separator_char or "─"
  local separator_width = math.max(0, width - #indent - 2) -- Ensure non-negative
  local separator = indent



  -- Use different separator styles for top-level vs nested tasks
  if level == 0 then
    -- Add fancy ends for top-level tasks with improved visual appearance
    separator = indent .. left_separator_char .. string.rep(separator_char, separator_width - 2) .. right_separator_char
  else
    -- For nested tasks, use a simpler but still visually distinctive separator
    separator = separator .. string.rep(separator_char, separator_width - 2)
  end

  return separator
end

local function highlight_search_results()
  if not state.search_results or #state.search_results == 0 then
    return
  end

  for _, result in ipairs(state.search_results) do
    local line = state.task_to_line[result.id]
    if line then
      -- Highlight the matched text
      vim.api.nvim_buf_add_highlight(
        state.buf,
        ns_id,
        "LazyDoSearchMatch",
        line - 1,
        result.match_start,
        result.match_end
      )

      -- Add a sign to make it easier to spot
      vim.fn.sign_place(0, "LazyDoSearch", "LazyDoSearchSign", state.buf, { lnum = line, priority = 10 })
    end
  end
end

local function is_valid_window()
  return state.win and vim.api.nvim_win_is_valid(state.win)
end

local function is_valid_buffer()
  return state.buf and vim.api.nvim_buf_is_valid(state.buf)
end
function UI.is_valid()
  return is_valid_window() and is_valid_buffer()
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
  local required_fields = {
    "id",
    "content",
    "status",
    "priority",
    "created_at",
    "updated_at",
  }

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

  -- Validate tags
  if task.tags and type(task.tags) ~= "table" then
    return false, "Tags must be an array"
  end

  -- Validate metadata
  if task.metadata and type(task.metadata) ~= "table" then
    return false, "Metadata must be a table"
  end

  return true
end

local function clear_state()
  state.buf = nil
  state.win = nil
  state.tasks = {}
  state.cursor_task = nil
  state.line_to_task = {}
  state.task_to_line = {}
end

local function validate_config()
  if not config then
    return false, "Configuration is missing"
  end

  local required_sections = {
    "theme",
    "icons",
    "features",
    "layout",
  }

  for _, section in ipairs(required_sections) do
    if not config[section] then
      return false, string.format("Missing required configuration section: %s", section)
    end
  end

  -- Validate theme colors
  if not config.theme.colors then
    return false, "Missing theme colors configuration"
  end

  -- Validate icons
  if not config.icons.task_pending or not config.icons.task_done then
    return false, "Missing required task status icons"
  end

  return true
end

-- Improve window creation with proper validation
local function create_window()
  -- Validate configuration first
  local valid, err = validate_config()
  if not valid then
    error("Invalid configuration: " .. err)
    return nil
  end

  -- Create buffer
  local buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_name(buf, buf_name)

  local buf_opts = {
    modifiable = false,
    buftype = "nofile",
    swapfile = false,
    bufhidden = "wipe",
    filetype = "lazydo",
  }

  for opt, val in pairs(buf_opts) do
    vim.api.nvim_buf_set_option(buf, opt, val)
  end

  local size = Utils.get_window_size(config)

  -- Enhanced window options
  local win_opts = {
    relative = "editor",
    width = size.width,
    height = size.height,
    row = size.row,
    col = size.col,
    style = "minimal",
    border = config.theme.border or "rounded",
    footer =
    " [a/A]dd task/subtask, [d]elete, [D]ate, [e]dit task, [K/J]move, [i]nfo, [m/M]etadata, [n]ote, [t/T]ag, [z]fold, [p]riority, [?]help ",
    footer_pos = "center",
    zindex = 50, -- Ensure window stays on top
  }
  local win = vim.api.nvim_open_win(buf, true, win_opts)

  -- Set window options
  local win_local_opts = {
    wrap = false,
    number = false,
    relativenumber = false,
    cursorline = false,
    signcolumn = "no",
    foldcolumn = "0",
    spell = false,
    list = false,
  }

  for opt, val in pairs(win_local_opts) do
    vim.api.nvim_win_set_option(win, opt, val)
  end

  return buf, win
end

function UI.restore_window_state(state)
  if not state then
    return
  end

  -- Restore cursor position
  if state.cursor then
    pcall(vim.api.nvim_win_set_cursor, state.win, state.cursor)
  end

  -- Restore scroll position
  if state.scroll then
    vim.fn.winrestview(state.scroll)
  end
end

local function render_progress_bar(progress, width)
  local style = config.theme.progress_bar.style
  local bar_width = config.theme.progress_bar.width or width
  local filled = math.floor(bar_width * progress / 100)
  local empty = bar_width - filled
  progress = progress or 0
  width = width or 10 -- Default reasonable width

  -- 󰪞󰪟󰪠󰪡󰪢󰪣󰪤󰪥
  -- Enhanced progress icons based on percentage
  local progress_icon = progress == 100 and config.icons.task_done
      or progress >= 75 and "󰪣 "
      or progress >= 50 and "󰪡 "
      or progress >= 25 and "󰪟 "
      or progress > 0 and "󰪞 "
      or "󰪥 "

  if style == "modern" then
    return string.format(
      "%s[%s%s]%d%%",
      progress_icon,
      string.rep(config.theme.progress_bar.filled, filled),
      string.rep(config.theme.progress_bar.empty, empty),
      progress
    )
  elseif style == "minimal" then
    return string.format("%s %d%%", progress_icon, progress)
  else -- classic
    return string.format(
      "%s%s %d%%",
      string.rep(config.theme.progress_bar.filled, filled),
      string.rep(config.theme.progress_bar.empty, empty),
      progress
    )
  end
end

local function render_note_section(note, indent_level, is_subtask)
  if not note or note == "" then
    return {}, {}
  end

  local indent = string.rep("  ", indent_level)
  local width = get_safe_window_width() - #indent - 4
  local lines = {}
  local regions = {}
  local current_line = 0

  local note_icon = config.icons.note or "󰎞"
  local box = {
    top_left = is_subtask and "├" or "╭",
    top_right = "╮",
    vertical = "│",
    horizontal = "─",
    bottom_left = is_subtask and "└" or "╰",
    bottom_right = "╯",
    separator = "┄",
  }

  -- Create header with improved styling
  local header = string.format("%s%s%s %s Notes ", indent, box.top_left, box.horizontal, note_icon)
  local header_padding = string.rep(box.horizontal, width - vim.fn.strwidth(header) + #indent)
  header = header .. header_padding .. box.top_right
  table.insert(lines, header)

  -- Add virtual text for indentation guide
  -- vim.api.nvim_buf_set_extmark(state.buf, ns_id, current_line, 0, {
  --   virt_text = { { string.rep("│ ", indent_level), "LazyDoIndentGuide" } },
  --   virt_text_pos = "overlay",
  --   hl_mode = "combine",
  -- })

  -- Header highlights with improved visual hierarchy
  table.insert(regions, {
    line = current_line,
    col = #indent + 1,
    length = #box.top_left + 3,
    hl_group = "LazyDoNotesBorder",
  })
  table.insert(regions, {
    line = current_line,
    col = #indent + #box.top_left + 3,
    length = #note_icon + 4,
    hl_group = "LazyDoNotesIcon",
  })
  table.insert(regions, {
    line = current_line,
    col = #indent + 20,
    length = #header_padding + #box.top_right + 1,
    hl_group = "LazyDoNotesBorder",
  })

  current_line = current_line + 1

  -- Process note content with improved paragraph handling
  local paragraphs = vim.split(note, "\n", { plain = true })

  for i, paragraph in ipairs(paragraphs) do
    if paragraph == "" then
      -- Empty line handling with virtual text
      local empty_line = string.format("%s%s%s%s", indent, box.vertical, string.rep(" ", width - 2), box.vertical)
      table.insert(lines, empty_line)

      -- Add virtual text for indentation guide
      -- vim.api.nvim_buf_set_extmark(state.buf, ns_id, current_line, 0, {
      --   virt_text = { { string.rep("│ ", indent_level), "LazyDoIndentGuide" } },
      --   virt_text_pos = "overlay",
      --   hl_mode = "combine",
      -- })

      -- Border highlights
      table.insert(regions, {
        line = current_line,
        col = #indent,
        length = 1,
        hl_group = "LazyDoNotesBorder",
      })
      table.insert(regions, {
        line = current_line,
        col = #empty_line - 1,
        length = 1,
        hl_group = "LazyDoNotesBorder",
      })

      current_line = current_line + 1
    else
      -- Word wrap the paragraph content
      local wrapped_lines = Utils.Str.wrap(paragraph, width - 4)
      for _, line_content in ipairs(wrapped_lines) do
        local padding = width - vim.fn.strwidth(line_content) - 2
        local content_line = string.format(
          "%s%s %s%s%s",
          indent,
          box.vertical,
          line_content,
          string.rep(" ", padding),
          box.vertical
        )

        table.insert(lines, content_line)

        -- Add virtual text for indentation guide
        -- vim.api.nvim_buf_set_extmark(state.buf, ns_id, current_line, 0, {
        --   virt_text = { { string.rep("│ ", indent_level), "LazyDoIndentGuide" } },
        --   virt_text_pos = "overlay",
        --   hl_mode = "combine",
        -- })

        -- Content line highlights with improved visual hierarchy
        table.insert(regions, {
          line = current_line,
          col = #indent,
          length = 1,
          hl_group = "LazyDoNotesBorder",
        })
        table.insert(regions, {
          line = current_line,
          col = #indent + 2,
          length = 1,
          hl_group = "LazyDoNotesBorder",
        })
        table.insert(regions, {
          line = current_line,
          col = #indent + 3,
          length = #line_content + 4,
          hl_group = "LazyDoNotesBody",
        })
        table.insert(regions, {
          line = current_line,
          col = #content_line - 1,
          length = 1,
          hl_group = "LazyDoNotesBorder",
        })

        current_line = current_line + 1
      end
    end
  end

  -- Add footer with virtual text
  local footer = string.format("%s%s%s%s", indent, box.bottom_left, string.rep(box.horizontal, width - 1),
    box.bottom_right)
  table.insert(lines, footer)

  -- Add virtual text for indentation guide
  -- vim.api.nvim_buf_set_extmark(state.buf, ns_id, current_line, 0, {
  --   virt_text = { { string.rep("│ ", indent_level), "LazyDoIndentGuide" } },
  --   virt_text_pos = "overlay",
  --   hl_mode = "combine",
  -- })

  table.insert(regions, {
    line = current_line,
    col = #indent,
    length = #footer - #indent,
    hl_group = "LazyDoNotesBorder",
  })

  return lines, regions
end

local function render_task_info(task, indent_level)
  if not state.show_task_info then
    return "", {}
  end
  local indent = string.rep("  ", indent_level + 1)
  local lines = {}
  local regions = {}

  -- Format timestamps with icons
  local created_icon = config.icons.created or "󰃰"
  local updated_icon = config.icons.updated or "󰦒"
  local recurring_icon = "󰑖"

  local created_at = os.date("%Y-%m-%d/%H:%M", task.created_at)
  local updated_at = task.updated_at > task.created_at and os.date("%Y-%m-%d/%H:%M", task.updated_at) or nil

  -- Add creation time with proper highlighting
  local created_line = string.format("%s%s Created: %s", indent, created_icon, created_at)
  table.insert(lines, created_line)
  table.insert(regions, {
    line = #lines - 1,
    col = #indent,
    length = #created_line - #indent,
    hl_group = "LazyDoTaskInfo",
  })

  -- Add update time if different
  if updated_at then
    local updated_line = string.format("%s Updated: %s", updated_icon, updated_at)
    table.insert(lines, updated_line)
    table.insert(regions, {
      line = #lines - 1,
      col = #indent,
      length = #updated_line - #indent,
      hl_group = "LazyDoTaskInfo",
    })
  end

  -- Add recurring info if present
  if task.recurring then
    local recurring_line = string.format("%s %s", recurring_icon, task.recurring)
    table.insert(lines, recurring_line)
    table.insert(regions, {
      line = #lines - 1,
      col = #indent,
      length = #recurring_line - #indent,
      hl_group = "LazyDoTaskInfo",
    })
  end
  local single_lines = table.concat(lines, "|")
  return single_lines, regions
end

local function render_tags(task)
  if not config.features.tags.enabled or not task.tags or #task.tags == 0 then
    return "", {}
  end

  local tags = {}
  local regions = {}
  local start_col = 0

  for _, tag in ipairs(task.tags) do
    local formatted_tag = config.features.tags.prefix .. tag
    table.insert(tags, formatted_tag)

    -- Add highlight for each tag
    table.insert(regions, {
      col = start_col + 1,
      length = #formatted_tag,
      hl_group = "LazyDoTags",
    })
    start_col = start_col + #formatted_tag + 1
  end

  return " " .. table.concat(tags, " "), regions
end

local function render_task_header(task, level, is_last)
  if not task then
    return "", {}
  end



  -- local base_indent = string.rep(" ", ensure_number(level, 0) * ensure_number(config.theme.indent.size, 2))
  local base_indent = string.rep(" ", ensure_number(level, 0) * 2)
  local regions = {}
  local current_col = #base_indent

  -- Helper function to add region
  local function add_region(length, hl_group, offset)
    table.insert(regions, {
      col = current_col + (offset or 0),
      length = ensure_number(length, 0) + 1,
      hl_group = hl_group or "Normal",
    })
    current_col = current_col + ensure_number(length, 0) + (offset or 0)
  end

  -- Build header components
  local components = {
    indent = base_indent,
    connector = "",
    status = "",
    priority = "",
    fold = "",
    content = task.content or "",
    tags = "",
    due = "",
    overdue = "",
    recurring = "",
    progress = "",
    info = "",
  }

  -- Add connector for subtasks
  if level > 0 then
    components.connector = is_last and (config and config.theme.indent.last_connector) or
        (config and config.theme.indent.connector)
    add_region(#components.connector, "LazyDoConnector")
  end

  -- Add status icon
  local status_icon = task.status == "done" and (config and config.icons.task_done) or
      (config and config.icons.task_pending)
  local status_hl = task.status == "done" and "LazyDoTaskDone"
      or (
        Task.is_overdue(task) and "LazyDoTaskOverdue"
        or (
          task.status == "blocked" and "LazyDoTaskBlocked"
          or (task.status == "in_progress" and "LazyDoTaskInProgress" or "LazyDoTaskPending")
        )
      )

  components.status = " " .. status_icon .. " "
  add_region(#status_icon, status_hl, 1)

  -- Add priority icon
  if (config and config.icons.priority) and config.icons.priority[task.priority] then
    local priority_icon = config.icons.priority[task.priority]
    components.priority = priority_icon .. " "
    add_region(#priority_icon, "LazyDoPriority" .. task.priority:sub(1, 1):upper() .. task.priority:sub(2))
  end

  -- Add folding indicator
  if (config and config.features.folding.enabled) and task.subtasks and #task.subtasks > 0 then
    components.fold = (
      task.collapsed and config.features.folding.icons.folded or config.features.folding.icons.unfolded
    ) .. " "
    add_region(#components.fold - 1, "LazyDoFoldIcon", 1)
  end

  -- Add task content
  add_region(#components.content, status_hl, 1)

  -- Add tags
  if (config and config.features.tags.enabled) and task.tags and #task.tags > 0 then
    local tags_str, tag_regions = render_tags(task)
    if tags_str then
      components.tags = tags_str
      for _, region in ipairs(tag_regions) do
        add_region(region.length, region.hl_group, 1)
      end
    end
  end

  -- Add due date
  if task.due_date then
    local relative_date = Utils.Date.relative(task.due_date)
    local is_overdue = Utils.Date.is_overdue(task.due_date)
    local is_today = Utils.Date.is_today(task.due_date)

    local due_text = string.format(" %s %s", (config and config.icons.due_date) or "", relative_date)
    components.due = due_text

    -- Determine highlight based on due status
    local due_hl = is_overdue and "LazyDoDueDateOverdue" or is_today and "LazyDoDueDateToday" or "LazyDoDueDate"

    add_region(#due_text, due_hl, 1)
  end

  -- Add progress bar
  if (config and config.theme.progress_bar) and (config and config.theme.progress_bar.enabled) then
    local progress = Task.calculate_progress(task)
    local progress_bar = render_progress_bar(progress, config.theme.progress_bar.width)
    if progress_bar then
      local spacer = " | "
      components.progress = spacer .. progress_bar

      local progress_hl = progress == 100 and "LazyDoProgressComplete"
          or progress > 0 and "LazyDoProgressPartial"
          or "LazyDoProgressNone"

      add_region(#progress_bar, progress_hl, #spacer)
    end
  end
  if (config and config.features.task_info) and (config and config.features.task_info.enabled) then
    local info_lines = render_task_info(task, 0)
    if info_lines then
      components.info = info_lines
      add_region(#info_lines, "LazyDoTaskInfo", 4)
    end
  end

  -- Construct final header line
  local header_line = table.concat({
    components.indent,
    components.connector,
    components.status,
    components.priority,
    components.fold,
    components.content,
    components.tags,
    components.due,
    components.recurring,
    components.overdue,
    components.progress,
    components.info,
  })

  return header_line, regions
end

local function render_task(task, level, current_line, is_last)
  if not task then
    return {}, {}, {}
  end

  -- Get priority and status for styling
  local priority = task.priority or "medium"
  local status = task.status or "pending"
  level = ensure_number(level, 0)
  current_line = ensure_number(current_line, 0)

  local lines = {}
  local regions = {}
  local mappings = {}

  -- Calculate indentation
  local base_indent = string.rep("ab", level)
  local connector_indent = string.rep("xy", math.max(0, level - 2))

  -- Define connector characters based on task position
  local connector = level > 0 and (is_last and "└─" or "├─") or ""
  local vertical_line = level > 0 and "│ " or ""

  -- Render task header with improved connectors
  local header_line, header_regions = render_task_header(task, level, is_last)
  table.insert(lines, header_line)

  -- Add header highlights
  for _, region in ipairs(header_regions) do
    table.insert(regions, {
      line = current_line,
      start = ensure_number(region.col, 0),
      length = ensure_number(region.length, 0),
      hl_group = region.hl_group or "Normal",
    })
  end

  -- Store task mapping
  if task.content then
    mappings[current_line + 1] = {
      task = task,
      mapping = {
        start_line = current_line,
        content_start = #header_line - #task.content,
        content_end = #header_line,
      },
    }
  end

  current_line = current_line + 1

  -- Add notes with proper indentation and connectors
  if task.notes then
    local note_lines, note_regions = render_note_section(task.notes, level + 1, level > 0)
    if note_lines and #note_lines > 0 then
      -- Add vertical connector before notes if task has subtasks
      if task.subtasks and #task.subtasks > 0 then
        for i, line in ipairs(note_lines) do
          local note_line = connector_indent .. vertical_line .. "  " .. line
          table.insert(lines, note_line)
        end
        for _, region in ipairs(note_regions) do
          table.insert(regions, {
            line = current_line + region.line,
            start = ensure_number(region.col, 0) + #connector_indent,
            length = ensure_number(region.length, 0) + #connector_indent,
            hl_group = region.hl_group,
          })
        end
      else
        -- Just add notes with proper indentation
        for _, line in ipairs(note_lines) do
          table.insert(lines, connector_indent .. "  " .. line)
        end
        for _, region in ipairs(note_regions) do
          table.insert(regions, {
            line = current_line + region.line,
            start = ensure_number(region.col, 0),
            length = ensure_number(region.length, 0),
            hl_group = region.hl_group,
          })
        end
      end
      current_line = current_line + #note_lines
    end
  end

  -- Render subtasks with improved connectors
  if task.subtasks and #task.subtasks > 0 and not task.collapsed then
    for i, subtask in ipairs(task.subtasks) do
      local sub_lines, sub_regions, sub_mappings = render_task(
        subtask,
        level + 1,
        current_line,
        i == #task.subtasks
      )

      vim.list_extend(lines, sub_lines)
      vim.list_extend(regions, sub_regions)

      for line_nr, mapping in pairs(sub_mappings) do
        mappings[line_nr] = mapping
      end

      current_line = current_line + #sub_lines
    end
  end

  if
      (config and config.features.metadata)
      and config.features.metadata.enabled
      and task.metadata
      and not vim.tbl_isempty(task.metadata)
  then
    local metadata_lines, metadata_regions = UI.render_metadata(task, level + 1)
    if metadata_lines and #metadata_lines > 0 then
      -- Add metadata lines
      for _, line in ipairs(metadata_lines) do
        table.insert(lines, line)
      end

      -- Add metadata highlights with proper line offsets
      for _, region in ipairs(metadata_regions) do
        table.insert(regions, {
          line = current_line + region.line,
          start = ensure_number(region.start, 0),
          length = ensure_number(region.length, 0),
          hl_group = region.hl_group,
        })
      end

      current_line = current_line + #metadata_lines
    end
  end
  if (config and config.features.relations.enabled) and task.relations and #task.relations > 0 then
    local relation_lines, relation_regions = UI.render_relations_section(task, level + 1)
    if relation_lines and #relation_lines > 0 then
      -- Add relation lines
      for _, line in ipairs(relation_lines) do
        table.insert(lines, line)
      end

      -- Add relation highlights with proper line offsets
      for _, region in ipairs(relation_regions) do
        table.insert(regions, {
          line = current_line + region.line,
          start = region.start,
          length = region.length,
          hl_group = region.hl_group,
        })
      end

      current_line = current_line + #relation_lines
    end
  end

  -- Add separator for top-level tasks
  if level == 0 then
    local separator = create_task_separator(level, get_safe_window_width())
    table.insert(lines, separator)
    table.insert(regions, {
      line = current_line,
      start = 0,
      length = #separator,
      hl_group = "LazyDoTaskBorder",
    })
    current_line = current_line + 1
  end

  return lines, regions, mappings
end

local function ensure_valid_window()
  if not state.win then
    error("Window handle is nil")
    return false
  end
  if not vim.api.nvim_win_is_valid(state.win) then
    error("Invalid window handle")
    return false
  end
  return true
end

function UI.render()
  if not state.buf or not state.win then
    return
  end
  if not ensure_valid_window() then
    return
  end

  -- Save the current window to restore focus after rendering if needed
  local current_win = vim.api.nvim_get_current_win()
  local was_focused = current_win == state.win

  vim.api.nvim_buf_clear_namespace(state.buf, ns_id, 0, -1)

  local lines = {}
  local all_regions = {}
  local current_line = 0

  -- Get window width for proper centering and layout
  local width = get_safe_window_width()

  -- Render header section
  local storage_mode = UI:get_storage_mode_info()

  local title = (config.title or " LazyDo Tasks ") .. storage_mode
  local centered_title = Utils.Str.center(title, width)
  local header_separator = "╭" .. string.rep("━", width - 2) .. "╮"

  -- Add header components
  table.insert(lines, centered_title)
  local base_title_start = math.floor((width - #title) / 2)
  table.insert(all_regions, {
    line = current_line,
    start = base_title_start,
    length = #config.title,
    hl_group = "LazyDoTitle",
  })

  -- Add storage mode highlight
  table.insert(all_regions, {
    line = current_line,
    start = base_title_start + #config.title,
    length = #storage_mode,
    hl_group = "LazyDoStorageMode",
  })
  current_line = current_line + 1

  -- Add separator after title
  table.insert(lines, header_separator)
  table.insert(all_regions, {
    line = current_line,
    start = 0,
    length = #header_separator,
    hl_group = "LazyDoHeaderSeparator",
  })
  current_line = current_line + 1

  -- Add empty line after header
  table.insert(lines, "")
  current_line = current_line + 1

  -- Reset task mappings
  state.line_to_task = {}
  state.task_to_line = {}

  -- Render tasks
  local tasks_to_render = state.filtered_tasks or state.tasks
  for i, task in ipairs(tasks_to_render) do
    -- Add spacing between tasks based on config
    if i > 1 and config.layout.spacing > 1 then
      for _ = 1, config.layout.spacing do
        table.insert(lines, "")
        current_line = current_line + 1
      end
    end

    -- Render task and its components
    local task_lines, task_regions, task_mappings = render_task(
      task,
      0,    -- start at root level
      current_line,
      false -- not last by default
    )

    -- Add task content
    vim.list_extend(lines, task_lines)
    vim.list_extend(all_regions, task_regions)

    -- Update task mappings
    for line_nr, mapping in pairs(task_mappings) do
      state.line_to_task[line_nr] = mapping
      state.task_to_line[mapping.task.id] = line_nr
    end

    current_line = current_line + #task_lines
  end

  -- Add footer if no tasks
  if #tasks_to_render == 0 then
    local empty_msg = "No tasks found. Press 'a' to add a new task."
    local centered_msg = Utils.Str.center(empty_msg, width)
    table.insert(lines, "")
    table.insert(lines, centered_msg)
    table.insert(all_regions, {
      line = current_line + 1,
      start = math.floor((width - #empty_msg) / 2),
      length = #empty_msg,
      hl_group = "LazyDoEmptyMessage",
    })
  end

  -- Add final separator
  local footer_separator = "╰" .. string.rep("━", width - 2) .. "╯"
  table.insert(lines, footer_separator)
  table.insert(all_regions, {
    line = #lines - 1,
    start = 0,
    length = #footer_separator,
    hl_group = "LazyDoHeaderSeparator",
  })

  -- Update buffer content
  vim.api.nvim_buf_set_option(state.buf, "modifiable", true)
  vim.api.nvim_buf_set_lines(state.buf, 0, -1, false, lines)

  -- Group regions by line for more efficient highlighting
  local grouped_regions = {}
  for _, region in ipairs(all_regions) do
    if region.line and region.start and region.length and region.hl_group then
      grouped_regions[region.line] = grouped_regions[region.line] or {}
      table.insert(grouped_regions[region.line], {
        start = region.start,
        length = region.length,
        hl_group = region.hl_group,
      })
    end
  end

  -- Apply highlights efficiently by line
  for line, regions in pairs(grouped_regions) do
    -- Sort regions by start position to ensure proper layering
    table.sort(regions, function(a, b)
      return a.start < b.start
    end)

    for _, region in ipairs(regions) do
      pcall(
        vim.api.nvim_buf_add_highlight,
        state.buf,
        ns_id,
        region.hl_group,
        line,
        region.start,
        region.start + region.length
      )
    end
  end

  -- Apply search highlights if any
  if #(state.search_results or {}) > 0 then
    highlight_search_results()
  end

  -- Lock buffer after rendering
  vim.api.nvim_buf_set_option(state.buf, "modifiable", false)

  -- Update status line if configured
  if config.features.statusline and config.features.statusline.enabled then
    vim.api.nvim_command("redrawstatus!")
  end

  if state.tasks and config and config.pin_window and config.pin_window.enabled then
    UI.sync_pin_window(state.tasks, config)
  end

  -- Restore focus to the LazyDo window if it was focused before
  if was_focused and state.win and vim.api.nvim_win_is_valid(state.win) then
    pcall(vim.api.nvim_set_current_win, state.win)
  end
end

local function show_help()
  local help_text = {
    "LazyDo Keybindings:",
    "",
    "Task Management:",
    " <CR>      Toggle task status",
    " a         Add new task",
    " A         Add subtask",
    "<leader>a      Quick task",
    "<leader>A      Quick subtask",
    " d         Delete task",
    " e         Edit task",
    "Task Properties:",
    " p         Cycle priority",
    " n         Add/edit notes",
    " N         Delete note",
    " D         Set due date",
    " t         Add tags",
    " T         Edit tags",
    "<leader>t   Remove tags",
    " m         Add metadata",
    " M         Edit metadata",
    "<leader>md   Remove metadata",
    " i         Toggle info",
    "Task Organization:",
    " K         Move task up",
    " J         Move task down",
    " z         Toggle fold",
    " x  Convert to subtask",
    " X  Convert to Task",
    "Links and Relations",
    " l  Show relations",
    " L  Add relation",
    "Filtering and Sorting:",
    " <leader>sp Sort by priority",
    " <leader>sd Sort by due date",
    " <leader>ss Sort by status",
    "Export/Import:",
    " <leader>m  Save to markdown file",
    "Other:",
    " ?         Show this help",
  }

  local buf = vim.api.nvim_create_buf(false, true)
  local width = math.min(60, vim.o.columns - 4)
  local height = #help_text
  local row = math.floor((vim.o.lines - height) / 2)
  local col = math.floor((vim.o.columns - width) / 2)

  vim.api.nvim_buf_set_lines(buf, 0, -1, false, help_text)
  vim.api.nvim_buf_set_option(buf, "modifiable", false)
  vim.api.nvim_buf_set_option(buf, "buftype", "nofile")

  local win = vim.api.nvim_open_win(buf, true, {
    relative = "editor",
    width = width,
    height = height,
    row = row,
    col = col,
    style = "minimal",
    border = "rounded",
    title = " Help ",
    title_pos = "center",
  })

  -- Close help window on any key press
  vim.api.nvim_buf_set_keymap(buf, "n", "q", "", {
    callback = function()
      vim.api.nvim_win_close(win, true)
      vim.api.nvim_buf_delete(buf, { force = true })
    end,
    noremap = true,
    silent = true,
  })
end

---Refresh the UI display
function UI.refresh()
  if is_valid_window() and is_valid_buffer() then
    -- Save cursor position and window ID before rendering
    local current_win = vim.api.nvim_get_current_win()
    local is_lazypanel_focused = current_win == state.win
    local pos = vim.api.nvim_win_get_cursor(state.win)
    local scroll_info = vim.api.nvim_win_call(state.win, vim.fn.winsaveview)

    -- Render content
    UI.render()

    -- Ensure cursor position is valid
    local line_count = vim.api.nvim_buf_line_count(state.buf)
    if pos[1] > line_count then
      pos[1] = line_count
    end

    -- Restore cursor position safely
    pcall(vim.api.nvim_win_set_cursor, state.win, pos)
    pcall(function() vim.api.nvim_win_call(state.win, function() vim.fn.winrestview(scroll_info) end) end)

    -- Ensure focus returns to LazyDo window if it was focused before
    if is_lazypanel_focused then
      vim.api.nvim_set_current_win(state.win)
    end
  end
end

-- Wrap action callback to ensure UI refresh
local function wrap_action_callback(fn)
  return function(...)
    -- Save current window and cursor state
    local current_win = vim.api.nvim_get_current_win()
    local is_on_lazypanel = current_win == state.win
    local cursor_pos = is_on_lazypanel and vim.api.nvim_win_get_cursor(state.win) or nil
    local scroll_info = is_on_lazypanel and vim.api.nvim_win_call(state.win, vim.fn.winsaveview) or nil

    -- Track which task is under cursor before action
    local current_task_id = nil
    if is_on_lazypanel then
      local task_under_cursor = UI.get_task_under_cursor()
      if task_under_cursor then
        current_task_id = task_under_cursor.id
      end
    end

    -- Run the action function
    local result = fn(...)

    -- Refresh UI
    UI.refresh()

    -- If we were on the LazyDo panel, try to restore focus and position
    if is_on_lazypanel and state.win and vim.api.nvim_win_is_valid(state.win) then
      -- First ensure window is focused - use pcall to avoid errors
      pcall(vim.api.nvim_set_current_win, state.win)

      -- Try to find the same task if it still exists
      if current_task_id then
        local new_line = state.task_to_line[current_task_id]
        if new_line then
          pcall(vim.api.nvim_win_set_cursor, state.win, { new_line, cursor_pos and cursor_pos[2] or 0 })
        else
          -- Fall back to original position if task not found
          if cursor_pos then
            -- Ensure cursor position is valid
            local line_count = vim.api.nvim_buf_line_count(state.buf)
            cursor_pos[1] = math.min(cursor_pos[1], line_count)
            pcall(vim.api.nvim_win_set_cursor, state.win, cursor_pos)
          end
        end
      elseif cursor_pos then
        -- Restore original cursor position if we didn't track a task
        local line_count = vim.api.nvim_buf_line_count(state.buf)
        cursor_pos[1] = math.min(cursor_pos[1], line_count)
        pcall(vim.api.nvim_win_set_cursor, state.win, cursor_pos)
      end

      -- Restore scroll position
      if scroll_info then
        pcall(function() vim.api.nvim_win_call(state.win, function() vim.fn.winrestview(scroll_info) end) end)
      end
    end

    return result
  end
end

-- ui.lua

function UI.setup_keymaps()
  local function map(key, fn, desc)
    vim.api.nvim_buf_set_keymap(state.buf, "n", key, "", {
      callback = wrap_action_callback(fn),
      noremap = true,
      silent = true,
      desc = desc,
    })
  end

  -- Add 'q' to close list view
  map("q", function()
    UI.close()
  end, "Close list view")

  -- Task Movement
  map("K", function()
    local task = UI.get_task_under_cursor()
    if task then
      Actions.move_task_up(state.tasks, task.id, state.on_task_update)
    end
  end, "Move Task Up")

  map("J", function()
    local task = UI.get_task_under_cursor()
    if task then
      Actions.move_task_down(state.tasks, task.id, state.on_task_update)
    end
  end, "Move Task Down")

  -- Task Status
  map("<CR>", function()
    local task = UI.get_task_under_cursor()
    if task then
      Actions.toggle_status(state.tasks, task.id, state.on_task_update)
      UI.refresh()
    end
  end, "Toggle Task")

  -- Task Management
  map("d", function()
    UI.delete_task()
  end, "Delete Task")
  map("i", function()
    UI.toggle_task_info()
  end, "Toggle Task Info")
  map("e", function()
    local task = UI.get_task_under_cursor()
    if task then
      vim.ui.input({
        prompt = "Edit task:",
        default = task.content,
      }, function(new_content)
        if new_content and new_content ~= "" then
          Actions.update_task(state.tasks, task.id, { content = new_content }, state.on_task_update)
          UI.refresh()
        end
      end)
    end
  end, "Edit Task")

  -- Task Properties
  map("p", function()
    UI.cycle_priority()
  end, "Toggle Priority")

  map("n", function()
    UI.add_multi_note()
  end, "add multi note")

  map("N", function()
    UI.delete_note()
  end, "delete note")

  map("D", function()
    UI.set_due_date()
  end, "Set Date")

  -- Task Hierarchy
  map("x", function()
    local task = UI.get_task_under_cursor()
    if task then
      vim.ui.select(state.tasks, {
        prompt = "Select parent task:",
        format_item = function(t)
          return t.content
        end,
      }, function(parent)
        if parent and parent.id ~= task.id then
          Actions.convert_to_subtask(state.tasks, task.id, parent.id, state.on_task_update)
          UI.refresh()
        end
      end)
    end
  end, "Convert To SubTask")
  map("X", function()
    local task = UI.get_task_under_cursor()
    if not task then
      UI.show_feedback("No task selected", "warn")
      return
    end

    -- Find the parent task by traversing all tasks
    local function find_parent_and_remove(tasks, target_id)
      for _, t in ipairs(tasks) do
        if t.subtasks then
          for i, subtask in ipairs(t.subtasks) do
            if subtask.id == target_id then
              -- Found the subtask, remove it from parent
              table.remove(t.subtasks, i)
              return true
            end
          end
          -- Recursively check nested subtasks
          if find_parent_and_remove(t.subtasks, target_id) then
            return true
          end
        end
      end
      return false
    end

    -- Try to find and remove the task from its parent
    if find_parent_and_remove(state.tasks, task.id) then
      -- Add the task to main tasks list
      table.insert(state.tasks, task)

      if state.on_task_update then
        state.on_task_update(state.tasks)
      end
      UI.show_feedback("Converted subtask to main task")
      UI.refresh()
    else
      UI.show_feedback("Task is not a subtask", "warn")
    end
  end, "Convert SubTask to Task")
  map("<leader>m", function()
    local task = UI.get_task_under_cursor()
    if task then
      vim.ui.input({
        prompt = "Set filename to save tasks in .md:",
        default = vim.fn.expand("%") or "",
      }, function(name)
        if name then
          Actions.export_to_markdown(state.tasks, name)
          UI.show_feedback("The tasks saved in " .. name, "info")
          UI.refresh()
        end
      end)
    end
  end, "Export to markdown")

  map("?", function()
    show_help()
  end, "Help Window")

  -- Add task creation keymap
  map("a", function()
    UI.add_task()
  end, "Add Task")
  map("A", function()
    UI.add_subtask()
  end, "Add SubTask")
  map("<leader>a", function()
    vim.ui.input({
      prompt = "Quick task:",
    }, function(content)
      if content and content ~= "" then
        local task

        -- Use core method with immediate saving if available
        if state.core and state.core.add_task then
          task = state.core:add_task(content, {
            priority = "medium",
            due_date = nil,
          })
        else
          -- Fallback to old method
          task = Actions.add_task(state.tasks, content, {
            priority = "medium",
            due_date = nil,
          }, state.on_task_update)
        end

        if task then
          UI.refresh()
          UI.show_feedback("Quick task added")
        end
      end
    end)
  end, "Quick Add Task")

  map("<leader>A", function()
    local parent_task = UI.get_task_under_cursor()
    if not parent_task then
      UI.show_feedback("No task selected", "warn")
      return
    end

    vim.ui.input({
      prompt = "Subtask content:",
    }, function(content)
      if content and content ~= "" then
        local subtask = Task.new(content, {
          priority = "medium",
          parent_id = parent_task.id,
          due_date = nil,
        })

        parent_task.subtasks = parent_task.subtasks or {}
        table.insert(parent_task.subtasks, subtask)

        if state.on_task_update then
          state.on_task_update(state.tasks)
        end

        UI.show_feedback(string.format("Added subtask to '%s'", parent_task.content))
        UI.refresh()

        if parent_task.collapsed then
          parent_task.collapsed = false
          UI.refresh()
        end
      end
    end)
  end, "Quick Add Subtask")

  map("z", function()
    UI.toggle_fold()
  end, "Toggle Fold")

  map("t", function()
    UI.add_tag()
  end, "Add Tag")
  map("T", function()
    UI.edit_tag()
  end, "Edit Tag")
  map("<leader>t", function()
    UI.remove_tag()
  end, "Remove Tag")
  map("m", function()
    UI.set_metadata()
  end, "Set MetaData")
  map("M", function()
    UI.edit_metadata()
  end, "Edit Metadata")
  map("<leader>md", function()
    local task = UI.get_task_under_cursor()
    if not task then
      UI.show_feedback("No task selected", "warn")
      return
    end

    if not task.metadata or vim.tbl_isempty(task.metadata) then
      UI.show_feedback("No metadata to delete", "warn")
      return
    end

    local metadata_keys = vim.tbl_keys(task.metadata)
    table.sort(metadata_keys)

    vim.ui.select(metadata_keys, {
      prompt = "Select metadata to delete:",
      format_item = function(key)
        return string.format("%s: %s", key, tostring(task.metadata[key]))
      end,
    }, function(choice)
      if choice then
        task.metadata[choice] = nil
        if vim.tbl_isempty(task.metadata) then
          task.metadata = nil
        end
        if state.on_task_update then
          state.on_task_update(state.tasks)
        end
        UI.show_feedback("Metadata deleted")
        UI.refresh()
      end
    end)
  end, "Delete Metadata")
  map("l", function()
    UI.show_relations()
  end, "Show Relations")
  map("L", function()
    local task = UI.get_task_under_cursor()
    if task then
      vim.ui.select(state.tasks, {
        prompt = "Select target task:",
        format_item = function(t)
          return t.content
        end,
      }, function(target)
        if target then
          vim.ui.select({ "blocks", "depends_on", "related_to", "duplicates" }, {
            prompt = "Relation type:",
          }, function(rel_type)
            if rel_type then
              Task.add_relation(task, target.id, rel_type)
              UI.refresh()
            end
          end)
        end
      end)
    end
  end, "Add Relation")

  -- Add sort keymaps
  map("<leader>sp", function()
    if #state.tasks == 0 then
      UI.show_feedback("No tasks to sort", "warn")
      return
    end
    Task.sort_by_priority(state.tasks)
    if state.on_task_update then
      state.on_task_update(state.tasks)
    end
    UI.show_feedback("Tasks sorted by priority")
    UI.refresh()
  end, "Sort by Priority")

  map("<leader>sd", function()
    if #state.tasks == 0 then
      UI.show_feedback("No tasks to sort", "warn")
      return
    end
    Task.sort_by_due_date(state.tasks)
    if state.on_task_update then
      state.on_task_update(state.tasks)
    end
    UI.show_feedback("Tasks sorted by due date")
    UI.refresh()
  end, "Sort by Due")

  -- Add new sort by status keymap
  map("<leader>ss", function()
    if #state.tasks == 0 then
      UI.show_feedback("No tasks to sort", "warn")
      return
    end
    Task.sort_by_status(state.tasks)
    if state.on_task_update then
      state.on_task_update(state.tasks)
    end
    UI.show_feedback("Tasks sorted by status")
    UI.refresh()
  end, "Sort by Status")
end

function UI.delete_task()
  local task = UI.get_task_under_cursor()
  if not task then
    UI.show_feedback("No task selected", "warn")
    return nil
  end

  -- Configure confirmation dialog with improved options
  local confirm_opts = {
    prompt = string.format("Delete Task: %s", task.content:sub(1, 30) .. (task.content:len() > 30 and "..." or "")),
    kind = "warning",
    default = false,
    format_item = function(item)
      return item == "y" and "Yes, delete this task" or "No, keep it"
    end,
  }

  -- Show task details in the confirmation
  local details = {
    "• Status: " .. task.status,
    "• Priority: " .. task.priority,
    task.due_date and ("• Due: " .. Utils.Date.format(task.due_date)) or nil,
    #(task.subtasks or {}) > 0 and ("• Subtasks: " .. #task.subtasks) or nil,
    task.notes and "• Has notes" or nil,
  }

  -- Filter out nil entries and join with newlines
  confirm_opts.prompt = confirm_opts.prompt
      .. "\n"
      .. table.concat(
        vim.tbl_filter(function(item)
          return item ~= nil
        end, details),
        "\n"
      )

  -- Show confirmation dialog
  vim.ui.select({ "y", "n" }, confirm_opts, function(choice)
    if choice == "y" then
      -- Attempt to delete the task
      local success, err = pcall(function()
        Actions.delete_task(state.tasks, task.id, state.on_task_update)
      end)

      if success then
        UI.show_feedback("Task deleted successfully")
        UI.refresh()
        return true
      else
        UI.show_feedback("Failed to delete task: " .. tostring(err), "error")
        return nil
      end
    else
      UI.show_feedback("Task deletion cancelled")
      return nil
    end
  end)
end

---Show feedback to user
---@param message string Message to show
---@param level? "info"|"warn"|"error" Feedback level
function UI.show_feedback(message, level)
  level = level or "info"
  local levels = {
    info = vim.log.levels.INFO,
    warn = vim.log.levels.WARN,
    error = vim.log.levels.ERROR,
  }

  vim.notify(message, levels[level], {
    title = "LazyDo",
    icon = "󱃔 ",
    timeout = 2000,
  })
end

function UI.toggle_task_info()
  state.show_task_info = not state.show_task_info
  UI.refresh()
  UI.show_feedback(state.show_task_info and "Task info shown" or "Task info hidden")
end

function UI.filter_tasks(filter_fn)
  if not state.tasks then
    return
  end
  local filtered = vim.tbl_filter(filter_fn, state.tasks)
  state.filtered_tasks = filtered
  UI.refresh()
end

-- Quick filters
UI.filters = {
  today = function()
    UI.filter_tasks(function(task)
      return Task.is_due_today(task)
    end)
    UI.refresh()
  end,
  overdue = function()
    UI.filter_tasks(function(task)
      return Task.is_overdue(task)
    end)
    UI.refresh()
  end,
  high_priority = function()
    UI.filter_tasks(function(task)
      return task.priority == "high"
    end)
    UI.refresh()
  end,
}

-- Task sorting capabilities
function UI.sort_tasks(sort_fn)
  if not state.tasks then
    return
  end
  table.sort(state.tasks, sort_fn)
  UI.refresh()
end

-- Quick sorts
UI.sorts = {
  by_priority = function()
    local priority_order = { low = 1, medium = 2, high = 3 }
    UI.sort_tasks(function(a, b)
      return priority_order[a.priority] > priority_order[b.priority]
    end)
    UI.refresh()
  end,
  by_due_date = function()
    UI.sort_tasks(function(a, b)
      -- If both tasks have no due date, maintain current order
      if not a.due_date and not b.due_date then
        return false
      end
      -- Tasks without due dates go to the end
      if not a.due_date then
        return false
      end
      if not b.due_date then
        return true
      end
      -- Compare actual dates
      return a.due_date < b.due_date
    end)
    UI.refresh()
  end,
}
-- Task grouping
function UI.group_tasks(group_fn)
  if not state.tasks then
    return
  end
  local groups = {}
  for _, task in ipairs(state.tasks) do
    local group = group_fn(task)
    groups[group] = groups[group] or {}
    table.insert(groups[group], task)
  end
  return groups
end

-- Quick groups
UI.groups = {
  by_status = function()
    return UI.group_tasks(function(task)
      return task.status
    end)
  end,
  by_priority = function()
    return UI.group_tasks(function(task)
      return task.priority
    end)
  end,
}

-- Task export capabilities
function UI.export_tasks(format)
  local exporters = {
    markdown = function(tasks)
      local lines = {}
      local function add_task(task, level)
        local indent = string.rep("  ", level)
        local status = task.status == "done" and "[x]" or "[ ]"
        local line = string.format("%s%s %s", indent, status, task.content)
        table.insert(lines, line)
        if task.subtasks then
          for _, subtask in ipairs(task.subtasks) do
            add_task(subtask, level + 1)
          end
        end
      end
      for _, task in ipairs(tasks) do
        add_task(task, 0)
      end
      return table.concat(lines, "\n")
    end,
    json = function(tasks)
      return vim.fn.json_encode(tasks)
    end,
  }

  local exporter = exporters[format]
  if exporter then
    return exporter(state.tasks)
  end
end

function UI.add_task()
  vim.ui.input({
    prompt = "Task content:",
  }, function(content)
    if not content or content == "" then
      UI.show_feedback("Task content cannot be empty", "warn")
      return
    end

    vim.ui.select({ "low", "medium", "high" }, {
      prompt = "Select priority:",
      format_item = function(item)
        return string.format("%s Priority", item:sub(1, 1):upper() .. item:sub(2))
      end,
    }, function(priority)
      if not priority then
        return
      end

      vim.ui.input({
        prompt = "Due (Y-M-D/today/tomorrow/nd/nw, optional):",
      }, function(due_date)
        local timestamp = due_date and due_date ~= "" and Utils.Date.parse(due_date)

        vim.ui.input({
          prompt = "Notes (optional):",
          completion = "file",
        }, function(notes)
          -- Check if we have a core reference for immediate saving
          if state.core and state.core.add_task then
            local task = state.core:add_task(content, {
              priority = priority,
              due_date = timestamp,
              notes = notes ~= "" and notes or nil,
            })

            if task then
              UI.refresh()
              UI.show_feedback("Task added successfully")
            end
          else
            -- Fallback to old method if core reference not available
            local task = Actions.add_task(state.tasks, content, {
              priority = priority,
              due_date = timestamp,
              notes = notes ~= "" and notes or nil,
            }, state.on_task_update)

            if task then
              UI.refresh()
              UI.show_feedback("Task added successfully")
            end
          end
        end)
      end)
    end)
  end)
end

function UI.toggle_task()
  local task = UI.get_task_under_cursor()
  if not task then
    return
  end

  Actions.toggle_status(state.tasks, task.id, function(tasks)
    if state.on_task_update then
      state.on_task_update(tasks)
    end
    -- Recalculate progress after status change
    local progress = Task.calculate_progress(task)
    UI.show_feedback(string.format("Task marked as %s (%d%% complete)", task.status, progress))
  end)
  UI.refresh()
end

function UI.edit_task()
  local task = UI.get_task_under_cursor()
  if not task then
    return
  end

  vim.ui.input({
    prompt = "Edit task:",
    default = task.content,
  }, function(new_content)
    if new_content and new_content ~= "" then
      Actions.update_task(state.tasks, task.id, { content = new_content }, state.on_task_update)
    end
  end)
  UI.refresh()
end

function UI.delete_note()
  local task = UI.get_task_under_cursor()
  if not task then
    UI.show_feedback("No task selected", "warn")
    return
  end

  if task.notes == nil then
    UI.show_feedback("No task note", "warn")
    return
  end

  local confirm_opts = {
    prompt = string.format("Delete Note: \n%s", task.notes:sub(1, 60) .. (task.notes:len() > 60 and "..." or "")),
    kind = "warning",
    default = false,
    format_item = function(item)
      return item == "y" and "Yes, delete this Note" or "No, keep it"
    end,
  }

  vim.ui.select({ "y", "n" }, confirm_opts, function(choice)
    if choice == "y" then
      Actions.delete_note(state.tasks, task.id, state.on_task_update())
      UI.show_feedback("Note deleted successfully")
      UI.refresh()
    else
      UI.show_feedback("Note deletion cancelled")
    end
  end)
end

function UI.add_note()
  local task = UI.get_task_under_cursor()
  if not task then
    return
  end

  vim.ui.input({
    prompt = "Add note:",
    default = task.notes or "",
  }, function(notes)
    if notes then
      Actions.set_notes(state.tasks, task.id, notes, state.on_task_update)
      UI.refresh()
    end
  end)
end

function UI.add_multi_note()
  local task = UI.get_task_under_cursor()
  if not task then
    return
  end

  Utils.multiline_input({
    prompt = "Add multiline note:",
    default = task.notes or "",
    width = 60,
    height = 10,
  }, function(notes)
    if notes then
      Actions.set_notes(state.tasks, task.id, notes, state.on_task_update)
      UI.refresh()
    end
  end)
end

function UI.cycle_priority()
  local task = UI.get_task_under_cursor()
  if not task then
    return
  end

  Actions.cycle_priority(state.tasks, task.id, state.on_task_update)
  UI.refresh()
end

function UI.set_due_date()
  local task = UI.get_task_under_cursor()
  if not task then
    return
  end

  local current_date = task.due_date and Utils.Date.format(task.due_date) or ""
  local prompt_text = string.format(
    [[
Due date: (For valid dates, check docs)]],
    current_date
  )

  vim.ui.input({
    prompt = prompt_text,
    default = current_date,
  }, function(date_str)
    if date_str == nil then
      return
    end
    Actions.set_due_date(state.tasks, task.id, date_str, state.on_task_update)
    UI.refresh()
  end)
end

function UI.get_task_under_cursor()
  if not state.win or not state.buf then
    return nil
  end

  -- Get current cursor position
  local cursor = vim.api.nvim_win_get_cursor(state.win)
  local line_nr = cursor[1]

  -- Find the task for current line by checking line range
  for task_line, line_info in pairs(state.line_to_task) do
    local task_end_line = task_line
    -- Find end of task section (next task start or end of buffer)
    for i = task_line + 1, vim.api.nvim_buf_line_count(state.buf) do
      local next_line_info = state.line_to_task[i]
      if next_line_info then
        task_end_line = i - 1
        break
      end
      task_end_line = i
    end

    -- Check if cursor is within task range
    if line_nr >= task_line and line_nr <= task_end_line then
      state.cursor_task = line_info.task
      return line_info.task
    end
  end

  return nil
end

function UI.update_task(task)
  if not validate_task(task) then
    UI.show_feedback("Cannot update invalid task", "error")
    return
  end

  if state.on_task_update then
    local success, err = pcall(state.on_task_update, task)
    if not success then
      UI.show_feedback("Failed to update task: " .. tostring(err), "error")
      return
    end
  end

  UI.refresh()
end

function UI.update_task_status(task_id, new_status)
  local task = UI.find_task_by_id(task_id)
  if not task then
    UI.show_feedback("Task not found", "error")
    return
  end

  local old_status = task.status
  task.status = new_status
  task.updated_at = os.time()

  -- Calculate progress
  local progress = Task.calculate_progress(task)

  -- Update parent task progress if exists
  if task.parent_id then
    local parent = UI.find_task_by_id(task.parent_id)
    if parent then
      parent.progress = Task.calculate_progress(parent)
    end
  end

  -- Show feedback with progress
  UI.show_feedback(
    string.format("Task status changed from %s to %s (%d%% complete)", old_status, new_status, progress)
  )

  UI.refresh()
end

---Find a task by ID in the current task list
---@param task_id string
---@return Task|nil
function UI.find_task_by_id(task_id)
  if not task_id or not state.tasks then
    return nil
  end

  -- Check if we have the task in our line mapping
  if state.task_to_line[task_id] then
    local line = state.task_to_line[task_id]
    if state.line_to_task[line] then
      return state.line_to_task[line].task
    end
  end

  -- Helper function to recursively search the task tree
  local function search_in_tasks(tasks)
    for _, task in ipairs(tasks) do
      if task.id == task_id then
        return task
      end
      if task.subtasks and #task.subtasks > 0 then
        local found = search_in_tasks(task.subtasks)
        if found then
          return found
        end
      end
    end
    return nil
  end

  return search_in_tasks(state.tasks)
end

-- Add task folding support
function UI.toggle_fold()
  local task = UI.get_task_under_cursor()
  if task and task.subtasks and #task.subtasks > 0 then
    local cursor_pos = vim.api.nvim_win_get_cursor(state.win)
    task.collapsed = not task.collapsed
    UI.refresh()
    vim.api.nvim_win_set_cursor(state.win, cursor_pos)
  end
end

-- Add task tags support
function UI.add_tag()
  local task = UI.get_task_under_cursor()
  if task then
    vim.ui.input({
      prompt = "Add tag:",
    }, function(tag)
      if tag and tag ~= "" then
        Task.add_tag(task, tag)
        if state.on_task_update then
          state.on_task_update(state.tasks)
        end
        UI.refresh()
      end
    end)
  end
end

function UI.edit_tag()
  local task = UI.get_task_under_cursor()
  if not task or not task.tags or #task.tags == 0 then
    UI.show_feedback("No tags to edit", "warn")
    return
  end

  vim.ui.select(task.tags, {
    prompt = "Select tag to edit:",
  }, function(selected_tag)
    if selected_tag then
      vim.ui.input({
        prompt = "Edit tag:",
        default = selected_tag,
      }, function(new_tag)
        if new_tag and new_tag ~= "" then
          Task.remove_tag(task, selected_tag)
          Task.add_tag(task, new_tag)
          if state.on_task_update then
            state.on_task_update(state.tasks)
          end
          UI.refresh()
        end
      end)
    end
  end)
end

function UI.remove_tag()
  local task = UI.get_task_under_cursor()

  if not task or not task.tags or #task.tags == 0 then
    UI.show_feedback("No tags to remove", "warn")
    return
  end

  vim.ui.select(task.tags, {
    prompt = "Select tag to remove:",
    format_item = function(tag)
      return tag
    end,
  }, function(selected_tag)
    if selected_tag then
      Task.remove_tag(task, selected_tag)
    end
    if state.on_task_update then
      state.on_task_update(state.tasks)
    end
    UI.refresh()
  end)
end

function UI.add_subtask()
  local parent_task = UI.get_task_under_cursor()
  if not parent_task then
    UI.show_feedback("No task selected", "warn")
    return
  end

  -- Get content first
  vim.ui.input({
    prompt = "Subtask content:",
    default = "",
  }, function(content)
    if not content or content == "" then
      UI.show_feedback("Subtask content cannot be empty", "warn")
      return
    end

    -- Then get priority
    vim.ui.select({ "low", "medium", "high" }, {
      prompt = "Select priority:",
      format_item = function(item)
        return string.format("%s Priority", item:sub(1, 1):upper() .. item:sub(2))
      end,
      default = "medium",
    }, function(priority)
      if not priority then
        return
      end

      -- Get due date
      vim.ui.input({
        prompt = "Due date (YYYY-MM-DD/today/tomorrow/Nd, optional):",
      }, function(due_date)
        local timestamp = due_date and due_date ~= "" and Utils.Date.parse(due_date)

        -- Finally get notes
        vim.ui.input({
          prompt = "Notes (optional):",
          completion = "file",
        }, function(notes)
          -- Create and add the subtask
          local subtask = Task.new(content, {
            priority = priority,
            parent_id = parent_task.id,
            due_date = timestamp,
            notes = notes ~= "" and notes or nil,
          })

          -- Initialize subtasks array if needed
          parent_task.subtasks = parent_task.subtasks or {}
          table.insert(parent_task.subtasks, subtask)

          -- Update state and UI
          if state.on_task_update then
            state.on_task_update(state.tasks)
          end

          -- Show success message and refresh
          UI.show_feedback(string.format("Added subtask to '%s'", parent_task.content))
          UI.refresh()

          -- Ensure parent task is unfolded to show new subtask
          if parent_task.collapsed then
            parent_task.collapsed = false
            UI.refresh()
          end
        end)
      end)
    end)
  end)
end

-- Add task metadata support
function UI.set_metadata()
  local task = UI.get_task_under_cursor()
  if task then
    vim.ui.input({
      prompt = "Metadata key:",
    }, function(key)
      if key and key ~= "" then
        vim.ui.input({
          prompt = "Metadata value:",
        }, function(value)
          if value then
            Task.set_metadata(task, key, value)
            if state.on_task_update then
              state.on_task_update(state.tasks)
            end
            UI.refresh()
          end
        end)
      end
    end)
  end
end

function UI.edit_metadata()
  local task = UI.get_task_under_cursor()
  if not task or not task.metadata or vim.tbl_isempty(task.metadata) then
    UI.show_feedback("No metadata to edit", "warn")
    return
  end

  local metadata_keys = vim.tbl_keys(task.metadata)
  vim.ui.select(metadata_keys, {
    prompt = "Select metadata to edit:",
  }, function(selected_key)
    if selected_key then
      vim.ui.input({
        prompt = "Edit metadata value:",
        default = tostring(task.metadata[selected_key]),
      }, function(new_value)
        if new_value then
          Task.set_metadata(task, selected_key, new_value)
          if state.on_task_update then
            state.on_task_update(state.tasks)
          end
          UI.refresh()
        end
      end)
    end
  end)
end

function UI.render_metadata(task, indent)
  if not task.metadata or vim.tbl_isempty(task.metadata) then
    return {}, {}
  end

  local lines = {}
  local regions = {}
  local indent_str = string.rep("  ", indent + 2)

  -- Sort metadata keys for consistent display
  local sorted_keys = vim.tbl_keys(task.metadata)
  table.sort(sorted_keys)

  for _, key in ipairs(sorted_keys) do
    local value = task.metadata[key]
    local line = string.format("%s%s: %s", indent_str, key, tostring(value))
    table.insert(lines, line)

    -- Add highlights for key and value
    table.insert(regions, {
      line = #lines,
      start = #indent_str,
      length = #key,
      hl_group = "LazyDoMetadataKey",
    })
    table.insert(regions, {
      line = #lines,
      start = #indent_str + #key + 2,
      length = #tostring(value),
      hl_group = "LazyDoMetadataValue",
    })
  end

  -- Add separator lines
  if #lines > 0 then
    table.insert(lines, 1, string.rep("  ", indent) .. "┌" .. string.rep("─", 40) .. "┐")
    table.insert(lines, string.rep("  ", indent) .. "└" .. string.rep("─", 40) .. "┘")
  end

  return lines, regions
end

---Close UI window
function UI.close()
  -- Save current state for potential restoration later
  if is_valid_window() then
    -- Try to save position, but don't error if it fails
    pcall(function()
      state.last_position = {
        cursor = vim.api.nvim_win_get_cursor(state.win),
        scroll = vim.fn.winsaveview(),
      }
    end)

    -- Before closing, check if we need to switch focus to another window
    local current_win = vim.api.nvim_get_current_win()
    local is_focused = current_win == state.win

    -- Get all windows except our LazyDo window
    local windows = vim.tbl_filter(function(win)
      return win ~= state.win and vim.api.nvim_win_is_valid(win)
    end, vim.api.nvim_list_wins())

    -- Close the window with pcall to prevent errors
    pcall(vim.api.nvim_win_close, state.win, true)

    -- If we were focused on the LazyDo window, switch to another window if available
    if is_focused and #windows > 0 then
      pcall(function()
        vim.api.nvim_set_current_win(windows[1])
      end)
    end
  end

  -- Clean up buffer with pcall to prevent errors
  if is_valid_buffer() then
    pcall(vim.api.nvim_buf_delete, state.buf, { force = true })
  end

  -- Always reset state after close attempt
  clear_state()
end

---Toggle UI visibility
---@param tasks Task[] Current tasks
---@param on_task_update? function Callback for task updates
---@param lazy_config? table Configuration to use if not initialized
---@param last_state? table Previous UI state for restoration
---@param core_instance? LazyDoCore Core instance for direct method calls
function UI.toggle(tasks, on_task_update, lazy_config, last_state, core_instance)
  -- Check if window already exists and is valid
  if UI.is_valid() then
    UI.close()
    return
  end

  if lazy_config then
    config = lazy_config
  end

  if not config then
    error("UI not properly initialized: config is missing")
    return
  end

  if is_valid_window() then
    UI.close()
    return
  end

  clear_state()
  state.tasks = type(tasks) == "table" and tasks or {}
  state.on_task_update = on_task_update
  state.core = core_instance -- Store reference to core instance for direct method calls

  local success, buf_or_err, win_or_err = pcall(create_window)
  if not success then
    error("Failed to create UI: " .. tostring(buf_or_err))
    return
  end

  if not buf_or_err or not win_or_err then
    error("Failed to create window or buffer")
    return
  end

  state.buf = buf_or_err
  state.win = win_or_err

  -- Make sure window is focused
  pcall(function()
    if state.win and vim.api.nvim_win_is_valid(state.win) then
      vim.api.nvim_set_current_win(state.win)
    end
  end)

  UI.setup_keymaps()
  UI.refresh()

  if last_state then
    UI.restore_window_state(last_state)
  end

  -- Set up essential autocommands
  if state.buf then
    -- Save state when leaving window
    vim.api.nvim_create_autocmd("WinLeave", {
      buffer = state.buf,
      callback = function()
        pcall(function()
          if state.win and vim.api.nvim_win_is_valid(state.win) then
            state.last_position = {
              cursor = vim.api.nvim_win_get_cursor(state.win),
              scroll = vim.fn.winsaveview(),
            }
          end
        end)
      end,
    })

    -- Handle window resizing
    vim.api.nvim_create_autocmd("VimResized", {
      buffer = state.buf,
      callback = function()
        pcall(function()
          if is_valid_window() then
            local size = Utils.get_window_size(config)
            vim.api.nvim_win_set_config(state.win, {
              width = size.width,
              height = size.height,
              row = size.row,
              col = size.col,
            })
            UI.refresh()
          end
        end)
      end,
    })

    -- Prevent cursor from leaving the window
    vim.api.nvim_create_autocmd("BufEnter", {
      buffer = state.buf,
      callback = function()
        pcall(function()
          if state.win and vim.api.nvim_win_is_valid(state.win) then
            -- Ensure we're in the LazyDo window
            vim.api.nvim_set_current_win(state.win)
          end
        end)
      end,
    })
  end

  -- Ensure focus is on the LazyDo window
  pcall(function()
    if state.win and vim.api.nvim_win_is_valid(state.win) then
      vim.api.nvim_set_current_win(state.win)
    end
  end)
end

-- Add new UI components for relations
function UI.show_relations()
  local task = UI.get_task_under_cursor()
  if not task then
    UI.show_feedback("No task selected", "warn")
    return
  end

  if not task.relations or #task.relations == 0 then
    UI.show_feedback("No relations found", "warn")
    return
  end

  local relation_items = {}
  for _, rel in ipairs(task.relations) do
    local target = UI.find_task_by_id(rel.target_id)
    if target then
      local status_icon = target.status == "done" and config.icons.task_done or config.icons.task_pending
      table.insert(relation_items, {
        relation = rel,
        target = target,
        display = string.format(
          "%s %s → [%s] %s",
          (config.icons.relations or "󱒖"),
          rel.type:gsub("_", " "):upper(),
          status_icon,
          target.content
        ),
      })
    end
  end

  vim.ui.select(relation_items, {
    prompt = "Task Relations:",
    format_item = function(item)
      return item.display
    end,
  }, function(choice)
    if choice then
      vim.ui.select({
        "View Target Task",
        "Remove Relation",
        "Edit Relation Type",
      }, {
        prompt = "Relation Action:",
      }, function(action)
        if action == "Remove Relation" then
          for i, rel in ipairs(task.relations) do
            if rel.target_id == choice.relation.target_id and rel.type == choice.relation.type then
              table.remove(task.relations, i)
              if state.on_task_update then
                state.on_task_update(state.tasks)
              end
              UI.show_feedback("Relation removed")
              UI.refresh()
              break
            end
          end
        elseif action == "Edit Relation Type" then
          vim.ui.select(Task.get_relation_types(), {
            prompt = "Select new relation type:",
            format_item = function(item)
              return item:gsub("_", " "):upper()
            end,
          }, function(new_type)
            if new_type then
              for _, rel in ipairs(task.relations) do
                if rel.target_id == choice.relation.target_id then
                  rel.type = new_type
                  if state.on_task_update then
                    state.on_task_update(state.tasks)
                  end
                  UI.show_feedback("Relation type updated")
                  UI.refresh()
                  break
                end
              end
            end
          end)
        elseif action == "View Target Task" then
          -- TODO: Implement jump to target task
          UI.show_feedback("Viewing target task (not implemented)")
        end
      end)
    end
  end)
end

function UI.render_relations_section(task, indent_level)
  if not task.relations or #task.relations == 0 then
    return {}, {}
  end

  local lines = {}
  local regions = {}
  local indent = string.rep("  ", indent_level)
  local base_indent = indent .. "    " -- 4 spaces after base indent
  local box_width = 50                 -- Increased width for better visual appeal

  -- Add section header with icon
  local title = " Relations "
  local header = indent .. "┌─" .. title .. string.rep("─", box_width - #title - 1) .. "┐"
  table.insert(lines, header)

  -- Add title highlight
  table.insert(regions, {
    line = #lines - 1,
    start = #indent + 4,
    length = #title + 1,
    hl_group = "LazyDoTitle",
  })

  -- Group relations by type
  local relations_by_type = {}
  for _, rel in ipairs(task.relations) do
    relations_by_type[rel.type] = relations_by_type[rel.type] or {}
    local target = UI.find_task_by_id(rel.target_id)
    if target then
      table.insert(relations_by_type[rel.type], {
        relation = rel,
        target = target,
      })
    end
  end

  -- Render relations grouped by type
  local types = vim.tbl_keys(relations_by_type)
  table.sort(types)

  for type_idx, type in ipairs(types) do
    -- Add relation type header with icon (safely handle missing icon)
    local type_header = type:gsub("_", " "):upper()
    local relation_icon = (config.icons and config.icons.relations) or "→"
    local type_line = indent .. "│ " .. relation_icon .. " " .. type_header .. ":"
    table.insert(lines, type_line)

    -- Add type highlight
    table.insert(regions, {
      line = #lines - 1,
      start = #base_indent + 1, -- After border and icon
      length = #type_header + 6,
      hl_group = "LazyDoTaskRelationType",
    })

    -- Add relation targets
    for _, rel_info in ipairs(relations_by_type[type]) do
      local status_icon = rel_info.target.status == "done" and (config.icons and config.icons.task_done or "✓")
          or (config.icons and config.icons.task_pending or "·")
      local target_line = indent .. "│   • " .. status_icon .. " " .. rel_info.target.content

      table.insert(lines, target_line)

      -- Add target task highlight
      table.insert(regions, {
        line = #lines - 1,
        start = #base_indent + 6, -- After border, bullet, and status
        length = #rel_info.target.content + 6,
        hl_group = "LazyDoTaskRelationTarget",
      })
    end

    -- Add separator between types unless it's the last one
    if type_idx < #types then
      table.insert(lines, indent .. "│" .. string.rep("─", box_width - 4))
    end
  end

  -- Add section footer
  table.insert(lines, indent .. "└" .. string.rep("─", box_width) .. "┘")

  return lines, regions
end

-- Add new UI components for reminders
function UI.add_reminder()
  local task = UI.get_task_under_cursor()
  if not task then
    return
  end

  vim.ui.input({
    prompt = "Reminder time (YYYY-MM-DD HH:MM):",
  }, function(time_str)
    if time_str then
      local timestamp = Utils.Date.parse(time_str)
      if timestamp then
        vim.ui.select({ "low", "normal", "high", "critical" }, {
          prompt = "Select urgency level:",
        }, function(urgency)
          if urgency then
            Task.add_reminder(task, timestamp, {
              days = 0,
              hours = 1,
              minutes = 0,
            }, urgency)
            UI.show_feedback("Reminder added")
            UI.refresh()
          end
        end)
      end
    end
  end)
end

local pin_window_state = {
  buf = nil,
  win = nil,
  last_update = 0,
}

function UI.create_pin_window(tasks, position)
  if not config then
    UI.show_feedback("First open LazyDo")
    return
  end

  -- If window exists, close it (toggle behavior)
  if pin_window_state.win and vim.api.nvim_win_is_valid(pin_window_state.win) then
    UI.close_pin_window()
    return
  end

  -- Filter for pending tasks
  local pending_tasks = vim.tbl_filter(function(task)
    return task.status ~= "done"
  end, tasks or {})

  -- Window setup
  local width = config.pin_window.width or 40
  local height = pending_tasks and #pending_tasks > 0 and math.min(#pending_tasks, config.pin_window.max_height or 10)
      or 1 -- Height for empty message

  -- Calculate window position based on config
  local editor_width = vim.o.columns
  local editor_height = vim.o.lines
  local row = 1
  local col = editor_width - width - 2
  local position = position or config.pin_window.position

  -- Position the window according to configuration
  if position == "topleft" then
    row = 1
    col = 1
  elseif position == "bottomright" then
    row = editor_height - height - 4
    col = editor_width - width - 2
  elseif position == "bottomleft" then
    row = editor_height - height - 4
    col = 1
  end

  -- Create buffer and window
  local buf = vim.api.nvim_create_buf(false, true)
  local win = vim.api.nvim_open_win(buf, false, {
    relative = "editor",
    width = width,
    height = height,
    row = row,
    col = col,
    style = "minimal",
    border = "rounded",
    title = (config.pin_window.title .. UI:get_storage_mode_info()) or " LazyDo Tasks ",
    title_pos = "center",
    zindex = 45,
  })

  -- Apply window highlights using config colors
  local win_hl = string.format("Normal:LazyDoFloat,FloatBorder:LazyDoPinWindowBorder,FloatTitle:LazyDoPinWindowTitle")
  vim.api.nvim_win_set_option(win, "winhl", win_hl)

  -- Render content
  local lines = {}
  local highlights = {}

  if #pending_tasks == 0 then
    -- Show empty state message
    local empty_msg = "󰱱 Yay! No pending tasks"
    local centered_msg = Utils.Str.center(empty_msg, width - 2)
    table.insert(lines, centered_msg)
    -- Add highlight for empty message
    table.insert(highlights, {
      line = 0,
      segments = {
        {
          start = math.floor((width - #empty_msg) / 2),
          length = #empty_msg,
          hl = "LazyDoNotesBody",
        },
      },
    })
  else
    -- Render tasks
    for _, task in ipairs(pending_tasks) do
      local status_icon = config.icons[task.status] or config.icons.task_pending
      local priority_icon = config.icons.priority[task.priority] or ""
      local due_text = task.due_date and Utils.Date.relative(task.due_date) or ""

      local content = Utils.Str.truncate(task.content, width - #due_text - 8)
      local line = string.format("%s %s %s %s", status_icon, priority_icon, content, due_text)
      table.insert(lines, line)

      -- Add highlights using config colors
      table.insert(highlights, {
        line = #lines - 1,
        segments = {
          { start = 0, length = 2, hl = "LazyDoTaskStatus" },
          {
            start = 3,
            length = 2,
            hl = "LazyDoPriority" .. task.priority:sub(1, 1):upper() .. task.priority:sub(2),
          },
          {
            start = 6,
            length = #content + 4,
            hl = Task.is_overdue(task) and "LazyDoTaskOverdue" or "Normal",
          },
          {
            start = #line - #due_text,
            length = #due_text,
            hl = Task.is_overdue(task) and "LazyDoDueDateOverdue" or "LazyDoDueDate",
          },
        },
      })
    end
  end

  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)

  -- Apply highlights
  for _, hl in ipairs(highlights) do
    for _, segment in ipairs(hl.segments) do
      vim.api.nvim_buf_add_highlight(buf, -1, segment.hl, hl.line, segment.start, segment.start + segment.length)
    end
  end

  -- Add basic keymaps
  local function map(key, fn, desc)
    vim.api.nvim_buf_set_keymap(buf, "n", key, "", {
      callback = fn,
      noremap = true,
      silent = true,
      desc = desc,
    })
  end

  map("q", function()
    UI.close_pin_window()
  end, "Close window")

  map("<ESC>", function()
    UI.close_pin_window()
  end, "Close window")

  -- Store state
  pin_window_state.buf = buf
  pin_window_state.win = win

  return win, buf
end

function UI.close_pin_window()
  if pin_window_state.win and vim.api.nvim_win_is_valid(pin_window_state.win) then
    vim.api.nvim_win_close(pin_window_state.win, true)
  end

  if pin_window_state.buf and vim.api.nvim_buf_is_valid(pin_window_state.buf) then
    vim.api.nvim_buf_delete(pin_window_state.buf, { force = true })
  end

  pin_window_state.win = nil
  pin_window_state.buf = nil
end

function UI.refresh_pin_window(tasks, position)
  if pin_window_state.win and vim.api.nvim_win_is_valid(pin_window_state.win) then
    UI.close_pin_window()
    UI.create_pin_window(tasks, position)
  end
end

function UI.sync_pin_window(tasks, position)
  if not config.pin_window or not config.pin_window.enabled then
    return
  end

  if pin_window_state.win and vim.api.nvim_win_is_valid(pin_window_state.win) then
    UI.refresh_pin_window(tasks, position)
  end
end

return UI
