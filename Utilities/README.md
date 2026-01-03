# Detailed description:

### DocShadrach_Detect BPM from a kick or snare using an SWS action.lua
This script detects the BPM (Beats Per Minute) from a selected audio item containing kick or snare drums using Xenakios' "Split at Transients" SWS action. It analyzes the transient positions to calculate the tempo and provides options to apply the detected BPM to the project.

Key Features:

- Uses Xenakios' "Split at Transients" SWS action to detect transients in the selected audio item.
- Automatically reverts the split operation after analysis to preserve the original project state.
- Implements adaptive filtering and grouping algorithms to identify consistent beat intervals.
- Applies musical corrections to ensure the detected BPM falls within typical musical ranges (60-180 BPM).
- Includes smart rounding to common musical values (whole numbers or .5 increments).
- Provides a confirmation dialog to apply the detected BPM to the project or keep the current tempo.
- Preserves the original project view, cursor position, and item selection after analysis.

### DocShadrach_FX scene manager and switcher using ReaImGui.lua

This script provides a professional interface to define, manage, and switch between different sets of FX (Scenes) across the project. It allows users to create custom groups of plugins based on name patterns and toggle them instantly, functioning as a powerful A/B testing tool for mixing chains or distinct production stages.

Key Features:

- Custom FX Scenes: Define multiple FX groups (rows) using flexible name patterns, supporting comma-separated values (e.g., "ReaEQ, Pro-Q 3, SSL Channel").
- Smart Exclusive Mode: Acts as an intelligent A/B switcher that automatically disables other scenes when activating a specific one, ideal for comparing different processing chains.
- Scope Control: Includes a "Selected Tracks Only" option to limit the script's action to specific tracks (e.g., toggling vocal chains without affecting drums).
- Drag-and-Drop Organization: Easily reorder scenes using a dedicated drag handle to maintain a logical workflow.
- Real-Time Feedback: Buttons display live status (ON, OFF, or MIXED) based on the actual state of the plugins in the project.
- Container Support: Scans root FX and first-level FX Containers to manage complex routing structures.
- Project Persistence: Automatically saves all scene configurations and settings directly into the .rpp project file via ExtState.

### DocShadrach_Global FX bypass synchronizer using ReaImGui.lua

This script provides a reactive interface to globally synchronize the bypass state of specific FX plugins across the entire project. It monitors FX states in real-time, allowing users to enable or disable plugins by name with immediate visual feedback, supporting complex routing including FX containers.

Key Features:

- Reactive Real-Time Monitoring: Continuously scans the project to reflect the current state of plugins (Enabled, Disabled, or Mixed) via color-coded buttons.
- Flexible Name Search: Targets plugins based on text search, with an optional Case Sensitive mode for precision.
- Visual State Feedback: Buttons light up bright Green (All On) or Red (All Off) and dim when inactive; Mixed states are highlighted in Amber.
- Container Support: Optional scanning of first-level FX Containers to manage complex chains.
- Smart Mixed-State Handling: Detects when some instances are on and others off, allowing the user to force a uniform state with a single click.
- CPU Optimization: Implements intelligent throttling to scan tracks efficiently without affecting playback performance.
- Safety & Undo: Requires a minimum of 3 characters to activate controls (preventing accidental matches), ignores offline FX, and creates named Undo points.

### DocShadrach_Global oversampling manager using ReaImGui.lua

This script provides a central control panel to manage REAPER's native oversampling for specific plugins across the entire project. It is designed to switch oversampling processing on or off globally, allowing for a high-fidelity mixing stage while maintaining a responsive workflow during production.

Key Features:

- Infinite Container Depth: Implements an advanced polynomial addressing engine (Recursive DIFF logic) to detect and process plugins regardless of how many FX Containers they are nested within.
- Smart Status Filtering: Automatically ignores plugin instances that are currently Bypassed or Offline, focusing only on active processing to save CPU resources.
- Per-Plugin Skip Logic: Includes individual checkboxes for each plugin pattern, allowing users to define a master list but selectively exclude specific plugins from the global oversampling toggle.
- Precise State Restoration: Uses a GUID-based mapping system to store each plugin's unique oversampling value before activation, ensuring the "Restore" function returns every instance to its exact prior state.
- Real-Time Instance Counting: Provides live feedback on the number of active plugins found for each filter pattern..
- Global Quality Selector: Features a quick-access menu to switch between 2x, 4x, and 8x oversampling levels project-wide with a single click.
- Project Persistence: Automatically saves all filter lists, enabled states, and configurations directly into the .rpp project file via ExtState for seamless multi-session use.

### DocShadrach_Project Startup Loader.lua

This script acts as the execution engine for the Project Startup Manager. It is designed to be set as the SWS Project Startup Action. Upon loading a project, it intelligently locates and executes the list of actions defined by the Manager, handling both saved projects and new projects derived from templates.

Key Features:

- Hybrid Loading Logic: Prioritizes reading from the local project_startup_actions.lua file; if missing, falls back to reading Project ExtState metadata.
- Auto-Regeneration: Automatically recreates the local configuration file from metadata if it's missing (e.g., when first saving a new project created from a Template), ensuring the list becomes editable.
- Secure Parsing: Uses strict text parsing instead of direct execution (dofile), ensuring that only valid Reaper Command IDs are triggered and preventing arbitrary code execution for security.
- Bypass Recognition: Respects the bypass state set in the Manager, ignoring actions commented out in the configuration.
- Relative Pathing: Dynamically locates the configuration file relative to the current project's .rpp location.
- Silent Operation: Runs invisibly in the background during project load without interrupting the user workflow.

### DocShadrach_Project Startup Manager.lua

This script provides a comprehensive graphical interface to manage project-specific startup actions. Unlike global startup actions, this tool allows you to define a unique list of commands (actions/scripts) that execute only when a specific project is opened. It works in tandem with the "Project Startup Loader" script and supports Project Templates via metadata embedding.

Key Features:

- Project-Specific Context: Creates and manages a local Lua file alongside your .rpp project file to store action lists.
- Template Support (Hybrid Architecture): Saves action lists to both the local file and Project ExtState metadata, ensuring startup actions persist even when creating new projects from Templates.
- Smart SWS Linking: Includes a "Link Loader" button that automatically finds the Loader script ID, copies it to the clipboard, and opens the SWS Startup Action dialog for easy setup.
- Action Bypass: Allows toggling actions on/off via checkboxes without deleting them from the list.
- Clipboard Workflow: Features a "Paste Action from Clipboard" button to quickly add Command IDs copied from the Reaper Action List.
- Safety & Sync: Automatically detects unsaved projects (warning the user) and auto-regenerates local files from metadata if they are missing (e.g., after loading a template).
- Integrated Help: Built-in instructions guide the user through the initial setup process.

### DocShadrach_Quick file importer using ReaImGui.lua
This script provides an advanced file import interface with drag-and-drop functionality, track filtering, and hierarchical organization. It allows users to import audio files to specific tracks with comprehensive filtering and assignment management.

Key Features:

- Drag-and-drop file assignment from the file browser to tracks.
- Shift-click multi-selection for selecting ranges of files quickly.
- Track isolation via double-click to focus on specific track groups and their children.
- Color-based track filtering with visual color squares and "Show Only" dropdown.
- Name-based track filtering using comma-separated keywords.
- Folder level filtering to hide tracks up to certain hierarchy depths.
- Undo/Redo functionality for file selections and assignments.
- Automatic peak building for imported audio files.
- Smart import options for tracks with existing files (add as new takes, replace, or skip).
- State management with "Copy State" to clipboard for saving filter configurations.
- Keyboard shortcuts: Enter for assignment, Ctrl+Enter for import, Esc for deselect, Ctrl+Z for undo.

### DocShadrach_Rename selected tracks using ReaImGui with selection auto-update.lua
This script opens a ReaImGui window to rename all selected tracks simultaneously with automatic selection tracking and colored track numbers. It provides a convenient interface for batch track renaming while maintaining visual context.

Key Features:

- Automatically updates the interface when track selection changes.
- Displays track numbers colored according to each track's color for easy identification.
- Real-time input fields for each selected track with immediate visual feedback.
- Apply changes with the Enter key or the "Apply Changes" button.
- Close the window with the Escape key or the "Close" button.
- Maintains track order based on their position in the REAPER track list.
- Uses track GUIDs for reliable selection tracking even when tracks are reordered.

### DocShadrach_Show notes duration in milliseconds based on bpm using ReaImGui.lua
This script displays musical note durations in milliseconds based on the current project tempo. It provides a real-time calculator for various note divisions with color-coded display and clipboard functionality.

Key Features:

- Automatically updates when the project tempo changes.
- Calculates durations for note divisions from whole notes (1/1) to 128th notes (1/128).
- Supports normal notes, triplets, and dotted notes with toggleable visibility.
- Color-coded display: white for normal notes, yellow for triplets, purple for dotted notes.
- Click any note duration to copy the value to clipboard (formatted to 2 decimal places).
- Toggle buttons to show/hide triplet and dotted notes.
- Real-time calculation ensures accuracy when tempo changes.
- Auto-resizing window that adapts to the number of visible note types.

### DocShadrach_Simple track notepad using ReaImGui.lua
This script provides a simple notepad system for tracks that saves notes in a project-specific text file. It allows users to attach notes to individual tracks and quickly access them across sessions.

Key Features:

- Automatically loads and saves notes for the currently selected track.
- Stores all track notes in a single "project_notes.txt" file in the project directory.
- Large, readable font for comfortable note-taking.
- Track name displayed in the track's color for visual identification.
- "Show Tracks with Notes" button to display a sidebar with all tracks that have notes.
- Click any track in the sidebar to select it and load its associated notes.
- "Clear Note" button to delete the current track's notes.
- Automatic cleanup of empty notes when the script closes.
- Real-time saving when pressing Enter in the text field.
- Works with any project and persists notes across REAPER sessions.






