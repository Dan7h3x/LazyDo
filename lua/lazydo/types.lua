---@meta

---@class Task
---@field id string Unique identifier
---@field content string Task content
---@field status "pending" | "done" Task status
---@field priority "low" | "medium" | "high" Task priority
---@field due_date? number Due date timestamp
---@field notes? string Additional notes
---@field subtasks Task[] List of subtasks
---@field created_at number Creation timestamp
---@field updated_at number Last update timestamp

---@class LazyDoConfig
---@field theme LazyDoTheme
---@field keymaps LazyDoKeymaps
---@field icons LazyDoIcons
---@field date_format string
---@field storage_path? string

---@class LazyDoTheme
---@field border "none"|"single"|"double"|"rounded"|"solid"|"shadow"
---@field priority_colors { low: string, medium: string, high: string }
---@field progress_bar { filled: string, empty: string }

---@class LazyDoKeymaps
---@field toggle_status string
---@field delete_task string
---@field edit_task string
---@field add_note string
---@field cycle_priority string
---@field set_due_date string
---@field add_subtask string
---@field close string

---@class LazyDoIcons
---@field task_pending string
---@field task_done string
---@field priority { low: string, medium: string, high: string }
---@field note string
---@field due_date string