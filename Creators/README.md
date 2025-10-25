# Detailed description:

### DocShadrach_Enable-Disable Oversampling FX [Creator].lua
This script allows the user to generate two custom scripts to control the oversampling of an FX plugin on a specified track. Based on user input, it creates one script to enable oversampling and another to disable it. These scripts are tailored to the track, FX, and oversampling value provided, and are automatically added to REAPER's Action List for easy future use.

Key Features:

- User input for track name, FX name, FX position (relative), and oversampling value (2x, 4x, 8x, or 16x).
- The FX position is relative, meaning it targets the nth instance of an FX with the same name, rather than its slot position in the FX chain.
- The FX name used is the one displayed in the track's FX list, which may differ from the plugin’s original name. If the user has renamed the plugin in the FX list, the script will target that new name. This allows the user to rename plugins for easier identification and precise targeting.
- The name doesn’t need to be complete; a partial match is sufficient (e.g., one word from a multi-word name), but the input is case sensitive, so capitalization must match exactly as displayed.
- Generates two scripts: one to enable the specified oversampling and another to disable it (set to 1x).
- Both scripts are automatically added to REAPER's Action List for future use.

### DocShadrach_Enable-Disable Oversampling FX in MasterTrack [Creator].lua
This script generates two custom actions to control the oversampling of an FX on the Master Track based on user input. One script enables oversampling to a specified value, while the other disables it (setting it to 1x). It simplifies the management of oversampling for plugins on the Master Track, with a user-friendly approach to handle plugins that appear multiple times in the chain. It is similar to the previous script but acts on the Master Track.

Key Features:

- User input for FX name and its relative position within the FX chain on the Master Track.
- The FX name does not need to be complete; a partial match is enough, but it is case sensitive, meaning the capitalization must match as displayed.
- The name used is the one displayed in the Master Track's FX list, and if the user renames the plugin, the script will target that new name, making it easier to identify and target specific plugins.
- Generates two scripts: one to enable oversampling and another to disable it (set to 1x).
- Both scripts are automatically added to REAPER's Action List for future use.

### DocShadrach_Project-wide sync ON-OFF FX [Creator].lua
This script allows the user to generate a custom script that synchronizes the bypass state of a specific FX plugin across ALL tracks in the project. Based on user input for the FX name, it creates a script that intelligently manages the bypass state to ensure all instances of the same FX have the same ON/OFF status throughout the entire project.

Key Features:

- User input for the FX name only - no track specification needed as it operates project-wide.
- The FX name does not need to be complete; a partial match is sufficient, but the input is case sensitive, meaning the capitalization must match exactly as displayed in the FX list.
- The script searches for FX instances using the name provided by the user. If the user has renamed a plugin in the FX list, the script will only find it if the user input matches part of the new name. This behavior can be used strategically: users can rename specific plugin instances to include or exclude them from the script's action by choosing names that do or don't match the search criteria.
- Only shows user notifications when mixed states are detected, asking for confirmation before proceeding.
- The generated script searches for ALL instances of the specified FX across every track in the project, ensuring comprehensive synchronization.
- The generated script is automatically saved in REAPER's script directory and added to the Action List for future use.

Implements intelligent synchronization logic:
- If all FX instances are enabled: Disables all (sets to bypass)
- If all FX instances are disabled: Enables all (removes bypass)
- If mixed states are detected: Disables all first (next run will enable all)

### DocShadrach_Selecting plugins one by one in loop [Creator].lua
This script allows the user to create a custom script that cycles through FX plugins on a specified track or within a container. Based on user input, it generates a new script that applies the action to all plugins or just a specified range, cycling through them by enabling the next FX and disabling the currently active one.

Key Features:

- User input for track name, FX container, and whether to apply the action to all plugins or just a specified range.
- Generates a new script based on these inputs that cycles forward through the plugins, enabling one and disabling the rest.
- The generated script is automatically added to REAPER's Action List for future use.

### DocShadrach_Selecting plugins one by one in loop [Creator] (F&B).lua
This script allows the user to create two custom scripts: one for cycling forward and another for cycling backward through FX plugins on a specified track or within a container. Similar to the first script, it generates two separate scripts based on user input. These scripts can apply the action to all plugins or a specific range, enabling one plugin at a time while disabling the rest.

Key Features:

- User input for track name, FX container, and whether to apply the action to all plugins or just a specified range.
- Generates two new scripts: one that cycles forward and another that cycles backward through the plugins, enabling one and disabling the rest.
- Both generated scripts are automatically added to REAPER's Action List for future use.

### DocShadrach_Selecting presets in loop [Creator] (F&B).lua
This script allows the user to create two custom scripts for cycling through FX presets on a specified track in REAPER. Based on user input for the track and FX names, it generates scripts that allow the user to navigate through the presets, moving forward or backward through the available options.

Key Features:

- User input for the track name and FX name, ensuring that the correct track and effect are targeted for preset navigation.
- Generates two distinct scripts: one for advancing to the next preset and another for reverting to the previous preset, each accommodating the specified track and FX.
- The generated scripts are automatically saved and registered in REAPER's Action List, allowing easy access for future use.

### DocShadrach_Toggle bypass Container [Creator].lua
This script allows the user to create a custom Lua script that toggles the bypass state of an FX container on a specified track. Based on user input, it generates a new script to enable or disable the selected container.

Key Features:

- Prompts the user to specify the track name and the position of the container within the FX chain.
- The generated script searches for the specified container on the selected track, ensuring it finds the correct one before toggling its bypass state.
- The generated script is automatically saved in REAPER’s script directory and added to the Action List for future use.

### DocShadrach_Toggle bypass FX [Creator].lua
This script allows the user to create a custom Lua script that toggles the bypass state of a specific FX plugin on a chosen track. It uses user input to specify the track name, FX name, and FX position within the chain, then generates a new script that can enable or disable the selected FX.

Key Features:

- Prompts the user to input the track name, FX name, and FX position within the FX chain. If the FX is unique, the position can be set to 0.
- The FX position is relative, meaning it targets the nth instance of an FX with the same name, not the slot position.
- The FX name does not need to be complete; a partial match is sufficient, but the input is case sensitive, so the capitalization must match exactly as shown in the FX list.
- The name used is the one displayed in the track's FX list. If the user has renamed the plugin, the script will target that new name, allowing the user to give specific names to plugins to make identification easier.
- The generated script searches for the specified FX on the selected track, ensuring it finds the correct instance. Once located, it toggles the bypass state of the FX.
- The generated script is automatically saved in REAPER's script directory and added to the Action List for future use.

### DocShadrach_Toggle mute Sends by index [Creator].lua

This script allows the user to create a custom Lua script that toggles the mute status of the sends on a specified track in REAPER. Based on user input, the generated script can mute or unmute either all sends or a specific set of sends by their index on a given track.

Key Features:

- User input for specifying the track name and whether to mute all sends or only specific ones.
- If the track name is left blank, the script will operate on the currently selected track.
- Allows specifying which send indices to mute/unmute if not applying to all sends.
- The generated script is automatically saved and added to REAPER's Action List for future access.

### DocShadrach_Toggle mute Sends with Specific-Receive-Names [Creator].lua

This script allows the user to create a custom Lua script that toggles the mute status of sends based on the names of the receiving tracks. It provides control over which sends to mute or unmute depending on the target receiving track names.

Key Features:

- User input for specifying the track name, the number of sends, and the names of the receiving tracks.
- If the track name is left blank, the script will operate on the currently selected track.
- Mutes or unmutes only the sends directed to specified receiving track names.
- The generated script is automatically saved and added to REAPER's Action List for future access.


