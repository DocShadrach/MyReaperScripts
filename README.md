# DocShadrach's Reaper Scripts


### Cycle_Select-Bypass_Plugins_Creator.lua

This script allows you to cycle through FX plugins on a specified track or within a container, enabling the next FX and disabling the current active one. The user can choose whether to apply the action to all plugins or to a specific range of plugins.

Key Features:
- User input for track name, FX container, and whether to apply the action to all or specific plugins.
- Cycles forward through the plugins, enabling one and disabling the rest.
- Only generates one script for forward cycling.

### Cycle_Select-Bypass_Plugins_Creator_F&B.lua

This script is very similar to the first, with the key difference being that it creates two scripts: one for cycling forward through the FX plugins and another for cycling backward. This gives users the flexibility to move both forward and backward through the plugin list.

Key Features:
- Same user input process and functionality as the first script.
- Generates two scripts: one for forward cycling and one for backward cycling.
- Both scripts are automatically added to REAPER’s action list.
- So yes, the main distinction is that the second script creates both forward and backward cycling scripts, while the first script only creates one for forward cycling.
