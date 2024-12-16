# LazyDo

a lazy way to manage Todos in `neovim`. Early development.

```lua
{
    "Dan7h3x/LazyDo",
    branch = "devel",
    event = "VeryLazy",
    cmd = "LazyDo",
    keys = {
      { "<leader>td", "<cmd>LazyDo<cr>", desc = "Open LazyDo" },
    },
    opts = {
      window = {
        width_ratio = 0.6,
        height_ratio = 0.8,
        min_width = 60,
        min_height = 10,
        border = "solid"
      },
      appearance = {
        style = "box",         -- "box" or "md"
        box_style = "modern", -- "modern", "minimal", "double"
        padding = 1,
        indent = "    ",
        highlight_current = false,
        show_icons = true
      },
      -- colors = DEFAULT_COLORS, -- User can override colors
      icons = {
        task_pending = "◆",
        task_done = "✓",
        priority = {
          HIGH = "1",
          MEDIUM = "2",
          LOW = "3",
          NONE = "0"
        },
        note = "📝",
        due_date = "📅",
        fold = {
          expanded = "▾",
          collapsed = "▸"
        }
      },
      -- storage = {
      --   data_path = string.format("s/lazydo_tasks.json", fn.stdpath("data"))
      -- }
    },
    config = function(_, opts)
      require("lazydo").setup(opts)
    end,
    dependencies = {
      "nvim-lua/plenary.nvim", -- For utility functions
    },
  }
```

