# LazyDo - Task Management for Neovim

recreate the Core:toggle to match my needs, everytime i use "LazyDotoggle" its clears the created tasks and starts from empty, also make the saving process of created tasks very fast, save after task created and delete after task deleted, edit after task edited, i want simple and smart mechanism

LazyDo is a powerful task management plugin for Neovim with task organization in both list and Kanban views.

## Architecture and Workflow

```
┌────────────────────────────────────────────────────────────────────┐
│                          LazyDo Architecture                        │
└────────────────────────────────────────────────────────────────────┘

┌────────────────────┐     ┌─────────────────┐     ┌─────────────────┐
│     init.lua       │────▶│     Core        │────▶│  Storage        │
│ (Plugin Entry)     │     │ (Main Engine)   │     │ (Data Layer)    │
└────────────────────┘     └─────────────────┘     └─────────────────┘
        │                        │   ▲                    │   ▲
        │                        │   │                    │   │
        │                        ▼   │                    ▼   │
        │                  ┌─────────────────┐     ┌─────────────────┐
        │                  │     Task        │     │ JSON             │
        │                  │ (Data Objects)  │     │ (Persistence)    │
        │                  └─────────────────┘     └─────────────────┘
        │                        │   ▲
        │                        │   │
        ▼                        ▼   │
┌────────────────────┐     ┌─────────────────┐     ┌─────────────────┐
│    Commands        │────▶│    Views        │────▶│    Actions      │
│ (User Interface)   │     │ (UI Components) │     │ (Task Ops)      │
└────────────────────┘     └─────────────────┘     └─────────────────┘
                                 │   │
                                 │   │
                                 ▼   ▼
                           ┌─────────────────┐
                           │ List / Kanban   │
                           │ (Visualization) │
                           └─────────────────┘

```

## Data Flow

1. **Initialization**:

   - User calls `LazyDoToggle` command or `require('lazydo').setup()`
   - The plugin initializes with default or user configuration
   - Storage module is initialized and attempts to load tasks

2. **Storage Detection**:

   - Storage module automatically detects if in a project directory
   - If in project mode, looks for project markers or git root
   - Tasks are loaded from the appropriate storage (global or project)

3. **View Rendering**:

   - Based on config, either List or Kanban view is displayed
   - Tasks are filtered and displayed according to view rules
   - UI components handle user interactions

4. **Task Manipulation**:
   - Actions on tasks (create, update, delete) are handled by Actions module
   - Changes are passed to Storage module for persistence
   - UI is refreshed to reflect changes

## Identified Issues and Improvements

1. **Storage Module**:

   - The auto-detection logic can be error-prone in complex directory structures
   - Encryption implementation is very basic and not secure for sensitive data
   - Consider using a more reliable storage format beyond JSON (e.g., SQLite)

2. **UI Responsiveness**:

   - Large task lists may cause performance issues in the Kanban view
   - Scrolling and navigation in Kanban view needs optimization for large boards

3. **Error Handling**:

   - Some error conditions are not fully recovered from, particularly in Storage module
   - Edge cases like corrupted files could be handled more gracefully

4. **Potential Improvements**:
   - Add a task search feature with fuzzy finding
   - Implement better task filtering and sorting capabilities
   - Add statistics and productivity tracking
   - Improve drag-and-drop functionality in Kanban view

## Code Efficiency Notes

- The drag-and-drop implementation in Kanban view is complex and could be simplified
- Some functions in UI modules have redundant code and could be refactored for better reuse
- The debouncing mechanism in Storage could be improved to avoid potential task loss
- Project detection could use a more robust approach with a clearer hierarchy of detection methods

