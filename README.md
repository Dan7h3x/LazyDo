<div align="center">
  <h1> LazyDo</h1>
  <p>A smart, feature-rich task manager for Neovim</p>

  <p>
    <a href="#-screenshots">Screenshots</a> •
    <a href="#-features">Features</a> •
    <a href="#-installation">Installation</a> •
    <a href="#usage">Usage</a> •
    <a href="#-configuration">Configuration</a>
  </p>

  <p>  ... made with  ...</p>
</div>

##  Screenshots

![Main Panel](https://github.com/user-attachments/assets/da5255fa-90c9-4ddd-adc0-5ab4da2cbff0)
![StatusLine](https://github.com/user-attachments/assets/e81bc6dd-815d-4a5d-8086-d815ba7cff1d)

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
{
    "Dan7h3x/LazyDo",
    branch = "main",
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
          return require("lazydo").get_lualine_stats()
        end,
        cond = function()
          return require("lazydo")._initialized
        end,
      })
    end,
  }
```

## Usage

- :LazyDoToggle - Toggle the task manager window
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
	metadata_position = "bottom", -- "bottom" or "right"
  },
  theme = {
    border = "rounded",󰁦
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
			marker = "│",
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
		due_date = "",
		recurring = {
			daily = "",
			monthly = "",
		},
		metadata = "󰂵",
		important = "",
	},
  date_format = "%Y-%m-%d",
  storage_path = nil, -- Uses default if not specified
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
		metadata = {
			enabled = true,
			display = true,
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
