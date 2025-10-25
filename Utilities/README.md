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
