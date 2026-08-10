---@class LazyDoConfig
---@field theme table UI theme configuration
---@field keymaps table Keymap configuration
---@field icons table Icon configuration
---@field date_format string Date format string
---@field storage table storage config
---@field views table view configuration
local Config = {}

---Default configuration
local defaults = {
  title = " LazyDo Tasks ",
  layout = {
    width = 0.8,      -- Percentage of screen width
    height = 0.9,     -- Percentage of screen height
    spacing = 1,      -- Lines between tasks
    task_padding = 1, -- Padding around task content
  },
  pin_window = {
    enabled = true,
    width = 50,
    max_height = 10,
    position = "topright", -- "topright", "topleft", "bottomright", "bottomleft"
    title = " LazyDo Tasks ",
    auto_sync = true,      -- Enable automatic synchronization with main window
    colors = {
      border = { fg = "#3b4261" },
      title = { fg = "#7dcfff", bold = true },
    },
  },
  storage = {
    startup_detect = false, -- Enable auto-detection of projects on startup
    silent = false,         -- Disable notifications when switching storage mode
    global_path = nil,      -- Custom storage path (nil means use default)
    project = {
      enabled = false,
      use_git_root = true,
      auto_detect = false,                                                     -- Auto-detect project and switch storage mode
      markers = { ".git", ".lazydo", "package.json", "Cargo.toml", "go.mod" }, -- Project markers
    },
    auto_backup = true,     -- Enable automatic backups when saving
    backup_count = 1,       -- Keep this many backup files (0 = keep all backups)
    compression = true,
    encryption = false,
  },
  views = {
    default_view = "list", -- "list" or "kanban"
    kanban = {
      enabled = true,
      columns = {
        { id = "backlog",     title = "Backloggggg", filter = { status = "pending" } },
        { id = "in_progress", title = "In Progress", filter = { status = "in_progress" } },
        { id = "blocked",     title = "Blocked",     filter = { status = "blocked" } },
        { id = "done",        title = "Done",        filter = { status = "done" } },
      },
      colors = {
        column_header = { fg = "#7dcfff", bold = true },
        column_border = { fg = "#3b4261" },
        card_border = { fg = "#565f89" },
        card_title = { fg = "#c0caf5", bold = true },
        card = {
          urgent = { fg = "#f7768e", bold = true }, -- Red
          high = { fg = "#ff9e64", bold = true },   -- Orange
          medium = { fg = "#e0af68" },              -- Yellow
          low = { fg = "#9ece6a" },                 -- Green
        },
        status = {
          done = { fg = "#9ece6a", bold = true },        -- Green
          blocked = { fg = "#f7768e", bold = true },     -- Red
          in_progress = { fg = "#7aa2f7", bold = true }, -- Blue
          pending = { fg = "#bb9af7" },                  -- Purple
        },
        metadata = {
          due_date = { fg = "#bb9af7" },            -- Purple for dates
          tags = { fg = "#2ac3de", italic = true }, -- Cyan for tags
          progress = { fg = "#7aa2f7" },            -- Blue for progress
        },
        ui = {
          pagination = { fg = "#bb9af7", italic = true },
          icon = { fg = "#2ac3de" },
          drag_active = { fg = "#c0caf5", bg = "#3d59a1", bold = true },
        },
      },
      card_width = 30,
      show_task_count = true,
      drag_and_drop = true,
      max_tasks_per_column = 100, -- Limit for performance optimization with pagination
      pagination = {
        enabled = true,
        tasks_per_page = 10,
        navigation_icons = {
          prev = "«",
          next = "»",
          current = "•",
        },
      },
    },
  },
  theme = {
    border = "rounded",
    colors = {
      header = { fg = "#7aa2f7", bold = true },
      title = { fg = "#7dcfff", bold = true },
      task = {
        pending = { fg = "#a9b1d6" },
        done = { fg = "#56ff89", italic = true },
        overdue = { fg = "#f7768e", bold = true },
        blocked = { fg = "#f7768e", italic = true },
        in_progress = { fg = "#7aa2f7", bold = true },
        info = { fg = "#78ac99", italic = true },
      },
      priority = {
        high = { fg = "#f7768e", bold = true },
        medium = { fg = "#e0af68" },
        low = { fg = "#9ece6a" },
        urgent = { fg = "#db4b4b", bold = true, undercurl = true },
      },
      storage = { fg = "#a24db3", bold = true },
      notes = {
        header = {
          fg = "#7dcfff",
          bold = true,
        },
        body = {
          fg = "#d9a637",
          italic = true,
        },
        border = {
          fg = "#3b4261",
        },
        icon = {
          fg = "#fdcfff",
          bold = true,
        },
      },
      due_date = {
        fg = "#bb9af7",
        near = { fg = "#e0af68", bold = true },
        overdue = { fg = "#f7768e", undercurl = true },
      },
      progress = {
        complete = { fg = "#9ece6a" },
        partial = { fg = "#e0af68" },
        none = { fg = "#f7768e" },
      },
      separator = {
        fg = "#3b4261",
        vertical = { fg = "#3b4261" },
        horizontal = { fg = "#3b4261" },
      },
      help = {
        fg = "#c0caf5",
        key = { fg = "#7dcfff", bold = true },
        text = { fg = "#c0caf5", italic = true },
      },
      fold = {
        expanded = { fg = "#7aa2f7", bold = true },
        collapsed = { fg = "#7aa2f7" },
      },
      indent = {
        line = { fg = "#3b4261" },
        connector = { fg = "#3bf2f1" },
        indicator = { fg = "#fb42f1", bold = true },
      },
      search = {
        match = { fg = "#c0caf5", bold = true },
      },
      selection = { fg = "#c0caf5", bold = true },
      cursor = { fg = "#c0caf5", bold = true },
    },
    progress_bar = {
      width = 15,
      filled = "█",
      empty = "░",
      enabled = true,
      style = "modern", -- "classic", "modern", "minimal"
    },
    indent = {
      connector = "├─",
      last_connector = "└─",
    },
    task_separator = {
      left = "",
      right = "",
      center = "",
    },
  },
  icons = {
    task_pending = "",
    task_done = "",
    task_in_progress = "󱇻",
    task_blocked = "󰾕",
    priority = {
      low = "",
      medium = "󰻂",
      high = "",
      urgent = "󰀦",
    },
    created = "󰃰",
    updated = "󰇡",
    note = "󰎞",
    relations = "󱒖 ",
    due_date = "󰃭",
    metadata = "󰂵",
    kanban = {
      move_left = "",
      move_right = "",
      column = "",
      card = "󰆼",
      collapse = "▼",
      expand = "▶",
      task_status = {
        pending = "",
        done = "",
        in_progress = "",
        blocked = "",
      },
      card_actions = {
        edit = "",
        delete = "",
        add = "",
        move = "󰘕",
      },
      pagination = {
        prev = "«",
        next = "»",
        indicator = "•",
      },
    },
  },
  features = {
    task_info = {
      enabled = true,
    },
    folding = {
      enabled = true,
      default_folded = false,
      icons = {
        folded = "▶",
        unfolded = "▼",
      },
    },
    tags = {
      enabled = true,
      colors = {
        fg = "#7aa2f7",
      },
      prefix = "󰓹 ",
    },
    relations = {
      enabled = true,
    },
    metadata = {
      enabled = true,
      colors = {
        key = { fg = "#f0caf5", bg = "#bb9af7", bold = true },
        value = { fg = "#c0faf5", bg = "#7dcfff" },
        section = { fg = "#00caf5", bg = "#bb9af7", bold = true, italic = true },
      },
    },
  },
}
---Setup configuration
---@param opts? table User configuration
---@return LazyDoConfig
function Config.setup(opts)
  opts = opts or {}
  return vim.tbl_deep_extend("force", defaults, opts)
end

return Config
