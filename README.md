# REAPER Scripts Collection by DocShadrach

A comprehensive collection of REAPER scripts designed to enhance workflow efficiency and provide advanced functionality for audio production and mixing.

## Repository Structure

This repository contains two main categories of REAPER scripts:

### 📁 Creators
Scripts that generate custom actions and scripts based on user input. These are "script generators" that create tailored solutions for specific workflow needs.

**Key Scripts:**
- **FX Control Scripts**: Enable/disable oversampling, toggle bypass states, manage FX containers
- **Selection Scripts**: Cycle through plugins and presets in loops
- **Project-wide Scripts**: Synchronize FX states across entire projects
- **Send Management**: Toggle mute states for sends by index or receiving track names

### 📁 Utilities
Standalone utility scripts that provide immediate functionality for common tasks and workflow enhancements.

**Key Scripts:**
- **BPM Detection**: Analyze audio items to detect tempo from kick/snare transients
- **File Import**: Advanced drag-and-drop file importer with track filtering
- **Track Management**: Batch rename tracks with automatic selection tracking
- **Note Duration Calculator**: Real-time musical note duration calculator based on project tempo
- **Track Notepad**: Persistent note-taking system for individual tracks

## Features

### 🎛️ Advanced FX Management
- Project-wide FX synchronization
- Oversampling control for specific plugins
- Container and individual FX bypass toggling
- Plugin selection cycling for A/B testing

### 📊 Smart Analysis Tools
- BPM detection from audio transients
- Real-time note duration calculations
- Musical tempo corrections and rounding

### 🗂️ File and Track Organization
- Hierarchical file import with drag-and-drop
- Color-based and name-based track filtering
- Batch track renaming with visual feedback
- Persistent track notes system

### 🎨 User-Friendly Interfaces
- ReaImGui-based graphical interfaces
- Color-coded track identification
- Keyboard shortcuts and hotkeys
- Undo/Redo functionality
- Real-time selection tracking

## Requirements

- **REAPER DAW** (version 6.0 or later recommended)
- **ReaImGui Extension** (for scripts with graphical interfaces)
- **SWS Extension** (for certain advanced functionality)

## Installation via ReaPack

This repository is available as a ReaPack package for easy installation and updates:

1. **Install ReaPack** (if not already installed):
   - Download from: https://reapack.com/
   - Follow the installation instructions for your operating system

2. **Add the repository**:
   - In REAPER, go to **Extensions menu > ReaPack > Import repositories...**
   - Paste the following URL:
     ```
     https://raw.githubusercontent.com/DocShadrach/MyReaperScripts/master/index.xml
     ```
   - Click **OK** to add the repository

3. **Install scripts**:
   - Go to **Extensions > ReaPack > Browse packages...**
   - Search for "DocShadrach" or browse the available scripts
   - Right-click on the scripts you want and select **Install**
   - Click **Apply** to install the selected scripts

4. **Access scripts**:
   - The scripts will be available in REAPER's Action List
   - Go to **Actions > Show Action List**
   - Search for the script names to find and use them
   - Assign keyboard shortcuts or toolbar buttons for quick access

### Manual Installation (Alternative)

If you prefer manual installation:

1. Download the desired script files from this repository
2. Place them in your REAPER Scripts directory:
   - Windows: `C:\Users\[Username]\AppData\Roaming\REAPER\Scripts\`
   - macOS: `~/Library/Application Support/REAPER/Scripts/`
   - Linux: `~/.config/REAPER/Scripts/`

3. In REAPER, go to **Actions > Show Action List**
4. Click **New Action** and select **Load ReaScript**
5. Navigate to the script file and load it
6. Assign a keyboard shortcut or toolbar button for quick access

## Usage Notes

- **Creator Scripts**: These generate new scripts that will appear in your Action List for repeated use
- **Utility Scripts**: These provide immediate functionality when run
- Most scripts with graphical interfaces will automatically update when project parameters change
- Track color coding and filtering helps organize large projects efficiently

## Contributing

These scripts are designed to improve your REAPER workflow. Feel free to modify, customize, and adapt them to your personal or professional needs.

## License

These scripts are open source under the MIT License. See the `LICENSE` file for full terms.

---

*Created by DocShadrach - Enhancing REAPER workflows one script at a time*
