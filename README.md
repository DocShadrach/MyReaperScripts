# DocShadrach's Reaper Scripts


### Cycle_Select-Bypass_Plugins_Creator.lua

This script allows the user to create a custom script that cycles through FX plugins on a specified track or within a container. Based on user input, it generates a new script that can either apply the action to all plugins or to a specific range of plugins, cycling through them by enabling the next FX and disabling the current active one.

Key Features:
- User input for track name, FX container, and whether to apply the action to all plugins or just a specified range.
- Generates a new script based on these inputs that cycles forward through the plugins, enabling one and disabling the rest.
- The generated script is automatically added to REAPER's action list for future use.

### Cycle_Select-Bypass_Plugins_Creator_F&B.lua

This script allows the user to create two custom scripts, one for cycling forward and another for cycling backward through FX plugins on a specified track or within a container. It is very similar to the first script, but instead of generating just one, it creates two separate scripts based on user input. These scripts can apply the action to all plugins or to a specific range, enabling one plugin at a time while disabling the rest.

Key Features:
- User input for track name, FX container, and whether to apply the action to all plugins or just a specified range.
- Generates two new scripts: one that cycles forward and another that cycles backward through the plugins, enabling one and disabling the rest.
- Both generated scripts are automatically added to REAPER's action list for future use.

### Enable-Disable_Oversampling_FX_Creator.lua

This script allows the user to generate two custom scripts to control the oversampling of an FX plugin on a specified track. Based on user input, it creates one script to enable oversampling and another to disable it. These scripts are tailored to the track, FX, and oversampling value provided, and are automatically added to REAPER's action list for easy future use.

Key Features:
- User input for track name, FX name, FX position (relative), and oversampling value (2x, 4x, 8x, or 16x).
- FX position is relative, meaning it is based on how many times the FX appears in the chain, not its slot position. This allows you to target the nth instance of an FX with the same name.
- The FX name used is the one displayed in the track's FX list, which could differ from the plugin’s original or real name. This enables the user to rename an FX in the list for easier identification, allowing specific targeting of the desired FX for oversampling.
- Generates two new scripts: one that enables the specified level of oversampling for the selected FX, and another that disables it (sets it to 1x).
- Both generated scripts are automatically added to REAPER's action list for future use.

### Enable-Disable_Oversampling_FX_MasterTrack_Creator.lua

This script generates two custom actions to control the oversampling of an FX on the Master Track based on user input. One script enables oversampling to a specified value, while the other disables it (setting it to 1x). It simplifies the management of oversampling for plugins on the Master Track, with a user-friendly approach to handle plugins that appear multiple times in the chain. It's similar to the previous one but acts on the Master Track instead of acting on a specific track.

### Toggle_Bypass_Container_Creator.lua

This script allows the user to create a custom Lua script that toggles the bypass state of an FX container on a specified track. Based on user input, it generates a new script that can be used to enable or disable the selected container.

Key Features:

- The script prompts the user to specify the name of the track and the position of the container within the FX chain.
- The generated script searches for the specified container on the selected track, ensuring it finds the correct one before toggling its bypass state. Once the container is located, the script will toggle the bypass state, enabling or disabling the FX container.
- The generated script is automatically saved in REAPER’s script directory and registered in the Action List for easy future access.

### Toggle_Bypass_FX_Creator.lua

This script allows the user to create a custom Lua script that toggles the bypass state of a specific FX plugin on a chosen track. It uses user input to specify the track name, FX name, and FX position within the chain, then generates a new script that can enable or disable the selected FX.

Key Features:

- The script prompts the user to input the track name, the FX name, and the FX position in the FX chain. If the FX is unique on the track, the position can be set to 0.
- The generated script searches for the specified FX on the selected track, ensuring it finds the correct instance. Once located, the script toggles the bypass state of the FX.
- The generated script is automatically saved in REAPER's script directory and added to the Action List for future use.

