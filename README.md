<div align="center">
  <h1> LazyDo</h1>
  <p>A smart, feature-rich task/todo manager for neovim lovers</p>

  <p>
    <a href="#-screenshots">Screenshots</a> •
    <a href="#-features">Features</a> •
    <a href="#-installation">Installation</a> •
    <a href="#usage">Usage</a> •
    <a href="#-configuration">Configuration</a>
  </p>

  <p>  ... made with love ...</p>
</div>

##  Screenshots

A demo video for `LazyDo`:
![LazyDo](https://github.com/user-attachments/assets/9fd079c8-52c3-45eb-81ef-e6cb315002fd)

Screenshots for `LazyDo`:

<p align="center">
  <img src="https://github.com/user-attachments/assets/09d1c4c8-481a-4ef9-964c-1622ca3f4fb5" alt="main panel" width="100%">
main panel
</p>

<p align="center">
  <img src="https://github.com/user-attachments/assets/e81bc6dd-815d-4a5d-8086-d815ba7cff1d" alt="`lualine` integration" width="100%">
`lualine` integration
</p>
<p align="center">
  <img src="https://github.com/user-attachments/assets/bbd88de8-e947-4fd8-ae87-57187ba7d024" alt="pin window" width="100%">
pin window for having pending task everywhere
</p>
<p align="center">
  <img src="https://github.com/user-attachments/assets/2b6da737-8fd3-4e97-90ed-e64a0e603273" alt="multiline note editor" width="100%">
multi-line note editor
</p>

## ✨ Features

-  Intuitive task management with subtasks support
-  Customizable themes and icons
-  Due dates and reminders
- 🏷️ Task tagging and categorization
- 🔍 Advanced sorting
- 󱒖 Task relationships and dependencies
- 📊 Progress tracking and filtering (WIP)
- 󰁦 File attachments (WIP)

## 📦 Installation

Using [lazy.nvim](https://github.com/folke/lazy.nvim):

```lua
return {
  {
    "Dan7h3x/LazyDo",
    branch = "main",
    cmd = {"LazyDoToggle","LazyDoPin"},
    keys = { -- recommended keymap for easy toggle LazyDo in normal and insert modes (arbitrary)
	    {
        "<F2>","<ESC><CMD>LazyDoToggle<CR>",
        mode = {"n","i"},
	    },
    },
    event = "VeryLazy",
    opts = {
      -- your config here
    },
  },
}
```

and integration with `lualine.nvim`:

```lua
{
    "nvim-lualine/lualine.nvim",
    event = "VeryLazy",
    opts = function(_, opts)
      table.insert(opts.sections.lualine_x, {
        function()
          return require("lazydo").get_lualine_stats() -- status
        end,
        cond = function()
          return require("lazydo")._initialized  -- condition for lualine
        end,
      })
    end,
  }
```

## Usage

> [!WARNING]
> For having `pin window` first spawn `LazyDoToggle` to load plugin up just
> once, when ever you enter `neovim`

- :`LazyDoToggle` - Toggle the task manager window

  - `a` - Add new task
  - `A` - Add subtask
  - `<leader>a` - Quick Task
  - `d` - Delete task
  - `e` - Edit task
  - `D` - Set due date
  - `K` - Move task up
  - `J` - Move task down
  - `i` - Toggle info
  - `m` - Add metadata
  - `M` - Edit metadata
  - `n` - Add/edit note
  - `p` - Toggle priority
  - `t` - Add tags
  - `T` - Edit tags
  - `z` - Toggle fold
    and more in help window using `?`.

- :`LazyDoPin position`
  - available positions are {default:`topright`,`topleft`,`bottomright`,`bottomleft`}.

### Valid dates

Example Dates:

- YYYY-MM-DD (like 2025-01-15)
- MM/DD (03/15)
- Nd (3d = 3 days)
- Nw (2w = 2 weeks)
- Nm (1m = 1 month)
- Ny (1y = 1 year)
- today
- tomorrow
- next week
- next month
- leave empty to clear

## 🔧 Configuration

All available options:

```lua
{
  title = " LazyDo Tasks ",
  layout = {
    width = 0.7, -- Percentage of screen width
    height = 0.8, -- Percentage of screen height
    spacing = 1, -- Lines between tasks
    task_padding = 1, -- Padding around task content
  },
  pin_window = {
    enabled = true,
    width = 50,
    max_height = 10,
    position = "topright", -- "topright", "topleft", "bottomright", "bottomleft"
    title = " LazyDo Tasks ",
    auto_sync = true, -- Enable automatic synchronization with main window
    colors = {
      border = { fg = "#3b4261" },
      title = { fg = "#7dcfff", bold = true },
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
        match = { fg = "#c0caf5", bg = "#445588", bold = true },
      },
      selection = { fg = "#c0caf5", bg = "#283457", bold = true },
      cursor = { fg = "#c0caf5", bg = "#364a82", bold = true },
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
  },
  icons = {
    task_pending = "",
    task_done = "",
    priority = {
      low = "󰘄",
      medium = "󰁭",
      high = "󰘃",
      urgent = "󰀦",
    },
    created = "󰃰",
    updated = "",
    note = "",
    relations = "󱒖 ",
    due_date = "",
    recurring = {
      daily = "",
      weekly = "",
      monthly = "",
    },
    metadata = "󰂵",
    important = "",
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
```

## 🤝 Contributing

Contributors are welcome here and thank you btw.
