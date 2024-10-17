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
- #Generates two new scripts#: one that cycles forward and another that cycles backward through the plugins, enabling one and disabling the rest.
- Both generated scripts are automatically added to REAPER's action list for future use.
