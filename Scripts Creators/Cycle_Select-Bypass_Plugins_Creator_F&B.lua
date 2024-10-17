-- Step 1: Ask for user inputs
retval, user_inputs = reaper.GetUserInputs("Script Setup", 3, "Track Name:,FX Container (0 for none):,All Plugins (Y/N):", "")
if retval == false then return end  -- If the user cancels, stop the script

-- Step 2: Parse user inputs
track_name, fx_container, plugin_mode = user_inputs:match("([^,]+),([^,]+),([^,]+)")
fx_container = tonumber(fx_container)

-- Validate inputs
if not track_name or not fx_container or (plugin_mode ~= "Y" and plugin_mode ~= "y" and plugin_mode ~= "N" and plugin_mode ~= "n") then
    reaper.ShowMessageBox("Invalid inputs. Please check the values.", "Error", 0)
    return
end

local apply_to_all_plugins = plugin_mode:upper() == "Y"

-- Step 3: If not applying to all plugins, ask for range
local min_fx, max_fx
if not apply_to_all_plugins then
    retval, plugin_range = reaper.GetUserInputs("Plugin Range", 2, "Min Plugin Index:,Max Plugin Index:", "1,4")
    if retval == false then return end  -- If the user cancels, stop the script
    
    -- Parse the range input
    min_fx, max_fx = plugin_range:match("([^,]+),([^,]+)")
    min_fx, max_fx = tonumber(min_fx), tonumber(max_fx)
    
    -- Adjust the range to be 0-based, because plugin indexes in REAPER start from 0
    min_fx = min_fx - 1
    max_fx = max_fx - 1
    
    if min_fx == nil or max_fx == nil or min_fx < 0 or max_fx < min_fx then
        reaper.ShowMessageBox("Invalid plugin range", "Error", 0)
        return
    end
else
    min_fx, max_fx = 0, nil  -- When applying to all plugins, range is irrelevant
end

-- Function to generate the script content
local function generate_script_content(direction)
    local script_content = [[
-- Automatically generated script for REAPER
track_name_to_find = "]] .. track_name .. [["

fx_container = ]] .. fx_container .. [[  -- Container to target (0 = no container)

-- Get the number of tracks in the project
num_tracks = reaper.CountTracks(0)

-- Search for the track with the specified name
track = nil
for i = 0, num_tracks - 1 do
    local track_current = reaper.GetTrack(0, i)
    _, current_track_name = reaper.GetSetMediaTrackInfo_String(track_current, "P_NAME", "", false)
    
    if current_track_name == track_name_to_find then
        track = track_current
        break
    end
end

-- If the track is not found, exit the script
if not track then
    reaper.ShowMessageBox("Track not found: " .. track_name_to_find, "Error", 0)
    return
end

-- If fx_container is 0, work directly with the plugins on the track
if fx_container == 0 then
    -- Get the number of plugins in the track
    num_fx = reaper.TrackFX_GetCount(track)

    -- Set the range for affecting plugins
    min_fx = ]] .. (min_fx or 0) .. [[  -- Default to the first plugin in track
    max_fx = ]] .. (max_fx or "num_fx - 1") .. [[  -- Default to the last plugin in track

    -- Find which FX within the range is active
    active_fx = -1
    for j = min_fx, max_fx do
        if reaper.TrackFX_GetEnabled(track, j) then
            active_fx = j
            break
        end
    end

    -- If no FX is active within the range, activate the first one in the range
    if active_fx == -1 then
        reaper.TrackFX_SetEnabled(track, min_fx, true)
    else
        -- Deactivate the current FX
        reaper.TrackFX_SetEnabled(track, active_fx, false)
        
        -- Calculate the next FX within the range (forward or backward based on direction)
        local next_fx = active_fx + ]] .. (direction == "forward" and "1" or "-1") .. [[
        if next_fx > max_fx then
            next_fx = min_fx  -- Return to the first in the range if we reach the last one
        elseif next_fx < min_fx then
            next_fx = max_fx  -- Return to the last in the range if we reach the first one
        end
        
        -- Activate the next FX in the range
        reaper.TrackFX_SetEnabled(track, next_fx, true)
    end
else
    -- Search for the container according to the specified number
    container_index = -1
    container_count = 0

    for i = 0, reaper.TrackFX_GetCount(track) - 1 do
        local retval, is_container = reaper.TrackFX_GetNamedConfigParm(track, i, "container_count")
        
        -- Check if the current plugin is a container
        if retval and tonumber(is_container) and tonumber(is_container) > 0 then
            container_count = container_count + 1
            if container_count == fx_container then
                container_index = i
                break
            end
        end
    end

    -- If the container is not found, display an error message
    if container_index == -1 then
        reaper.ShowMessageBox("Container number " .. fx_container .. " not found in the track", "Error", 0)
        return
    end

    -- Activate the container (it should always be active)
    reaper.TrackFX_SetEnabled(track, container_index, true)

    -- Get the number of FX inside the container
    local retval, container_fx_count = reaper.TrackFX_GetNamedConfigParm(track, container_index, "container_count")
    num_fx_in_container = tonumber(container_fx_count)

    -- If unable to retrieve the number of FX in the container, display an error message
    if not num_fx_in_container or num_fx_in_container == 0 then
        reaper.ShowMessageBox("Could not get the number of FX in container number " .. fx_container, "Error", 0)
        return
    end

    -- Set the range for affecting plugins inside the container
    min_fx = ]] .. (min_fx or 0) .. [[  -- Default to the first plugin in container
    max_fx = ]] .. (max_fx or "num_fx_in_container - 1") .. [[  -- Default to the last plugin in container

    -- Find which FX within the range is active inside the container
    active_fx = -1
    for j = min_fx, max_fx do
        local fx_index = 0x2000000 + (j + 1) * (reaper.TrackFX_GetCount(track) + 1) + container_index + 1  -- Calculate the FX index inside the container
        if reaper.TrackFX_GetEnabled(track, fx_index) then
            active_fx = j
            break
        end
    end

    -- If no FX is active within the range, activate the first one in the range
    if active_fx == -1 then
        local fx_index = 0x2000000 + (min_fx + 1) * (reaper.TrackFX_GetCount(track) + 1) + container_index + 1
        reaper.TrackFX_SetEnabled(track, fx_index, true)
    else
        -- Deactivate the current FX inside the container
        local fx_index = 0x2000000 + (active_fx + 1) * (reaper.TrackFX_GetCount(track) + 1) + container_index + 1
        reaper.TrackFX_SetEnabled(track, fx_index, false)
        
        -- Calculate the next FX within the range inside the container (forward or backward based on direction)
        local next_fx = active_fx + ]] .. (direction == "forward" and "1" or "-1") .. [[
        if next_fx > max_fx then
            next_fx = min_fx  -- Return to the first in the range if we reach the last one
        elseif next_fx < min_fx then
            next_fx = max_fx  -- Return to the last in the range if we reach the first one
        end
        
        -- Activate the next FX inside the container
        local next_fx_index = 0x2000000 + (next_fx + 1) * (reaper.TrackFX_GetCount(track) + 1) + container_index + 1
        reaper.TrackFX_SetEnabled(track, next_fx_index, true)
    end
end

-- Refresh the FX window
reaper.TrackList_AdjustWindows(false)
]]
    return script_content
end

-- Step 4: Create two scripts: one for forward, one for backward
local directions = { "forward", "backward" }
for _, direction in ipairs(directions) do
    -- Step 5: Create the script filename based on user input, keeping the original name and adding _F or _B
    local suffix = direction == "forward" and "_F" or "_B"
    local script_name

    if apply_to_all_plugins then
        script_name = "Cycle_Select-Bypass_All_Plugins_" .. track_name .. (fx_container > 0 and "_" .. fx_container .. "Container" or "") .. suffix .. ".lua"
    else
        script_name = "Cycle_Select-Bypass_Plugins_range(" .. min_fx + 1 .. "-" .. (max_fx + 1) .. ")_" .. track_name .. (fx_container > 0 and "_" .. fx_container .. "Container" or "") .. suffix .. ".lua"
    end
    
    -- Step 6: Write the script content to the file
    local file = io.open(reaper.GetResourcePath() .. "/Scripts/" .. script_name, "w")
    if file then
        file:write(generate_script_content(direction))
        file:close()
    else
        reaper.ShowMessageBox("Failed to create script file: " .. script_name, "Error", 0)
    end

    -- Step 7: Register the new script as an action
    local script_path = reaper.GetResourcePath() .. "/Scripts/" .. script_name
    local ret = reaper.AddRemoveReaScript(true, 0, script_path, true)
    if ret == 0 then
        reaper.ShowMessageBox("Error registering the new script as an action.", "Whoops!", 0)
        return
    end

    -- Step 8: Confirm success to the user
    reaper.ShowMessageBox("Script successfully created and added to the Action List:\n" .. script_name, "Done!", 0)
end
