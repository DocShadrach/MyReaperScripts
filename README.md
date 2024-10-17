# DocShadrach's Reaper Scripts

### Cycle_Select-Bypass_Plugins_Creator.lua

This script allows the user to create a custom script that cycles through FX plugins on a specified track or within a container. Based on user input, it generates a new script that either applies the action to all plugins or to a specified range, cycling through them by enabling the next FX and disabling the current active one.

Key Features:

- User input for track name, FX container, and whether to apply the action to all plugins or just a specified range.
- Generates a new script based on these inputs that cycles forward through the plugins, enabling one and disabling the rest.
- The generated script is automatically added to REAPER's Action List for future use.

### Cycle_Select-Bypass_Plugins_Creator_F&B.lua

This script allows the user to create two custom scripts: one for cycling forward and another for cycling backward through FX plugins on a specified track or within a container. Similar to the first script, it generates two separate scripts based on user input. These scripts can apply the action to all plugins or to a specific range, enabling one plugin at a time while disabling the rest.

Key Features:

- User input for track name, FX container, and whether to apply the action to all plugins or just a specified range.
- Generates two new scripts: one that cycles forward and another that cycles backward through the plugins, enabling one and disabling the rest.
- Both generated scripts are automatically added to REAPER's Action List for future use.

### Enable-Disable_Oversampling_FX_Creator.lua

This script allows the user to generate two custom scripts to control the oversampling of an FX plugin on a specified track. Based on user input, it creates one script to enable oversampling and another to disable it. These scripts are tailored to the track, FX, and oversampling value provided, and are automatically added to REAPER's Action List for easy future use.

Key Features:

- User input for track name, FX name, FX position (relative), and oversampling value (2x, 4x, 8x, or 16x).
- The FX position is relative, targeting the nth instance of an FX with the same name, rather than its slot position.
- The FX name used is the one displayed in the track's FX list, which allows for custom naming for easier identification of the target FX.
- Generates two scripts: one to enable the specified oversampling and another to disable it (set to 1x).
- Both scripts are automatically added to REAPER's Action List for future use.

### Enable-Disable_Oversampling_FX_MasterTrack_Creator.lua

This script generates two custom actions to control the oversampling of an FX on the Master Track based on user input. One script enables oversampling to a specified value, while the other disables it (setting it to 1x). It simplifies the management of oversampling for plugins on the Master Track, with a user-friendly approach to handle plugins that appear multiple times in the chain. It is similar to the previous script but acts on the Master Track.

### Toggle_Bypass_Container_Creator.lua

This script allows the user to create a custom Lua script that toggles the bypass state of an FX container on a specified track. Based on user input, it generates a new script to enable or disable the selected container.

Key Features:

- Prompts the user to specify the track name and the position of the container within the FX chain.
- The generated script searches for the specified container on the selected track, ensuring it finds the correct one before toggling its bypass state.
- The generated script is automatically saved in REAPER’s script directory and added to the Action List for future use.

### Toggle_Bypass_FX_Creator.lua

This script allows the user to create a custom Lua script that toggles the bypass state of a specific FX plugin on a chosen track. It uses user input to specify the track name, FX name, and FX position within the chain, then generates a new script that can enable or disable the selected FX.

Key Features:

- Prompts the user to input the track name, FX name, and FX position within the FX chain. If the FX is unique, the position can be set to 0.
- The generated script searches for the specified FX on the selected track, ensuring it finds the correct instance. Once located, it toggles the bypass state of the FX.
- The generated script is automatically saved in REAPER's script directory and added to the Action List for future use.

