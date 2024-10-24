-- Step 1: Ask the user for the track name and container position
local retval, trackNameToFind = reaper.GetUserInputs("Track and Container Info", 2, "Track Name:,Container Position:", "")
if not retval then return end  -- Exit if the user cancels

local trackName, containerToFind = trackNameToFind:match("([^,]+),([^,]+)")
containerToFind = tonumber(containerToFind)

if not trackName or not containerToFind then
    reaper.ShowMessageBox("Invalid input. Please enter a track name and container position.", "Error", 0)
    return
end

-- Step 2: Define the script content
local script_content = [[
-- Automatically generated script

-- Track and container information
local trackNameToFind = "]] .. trackName .. [["
local containerToFind = ]] .. containerToFind .. [[

-- Get the total number of tracks
local trackCount = reaper.CountTracks(0)

-- Variable to store the found track
local trackFound = nil

-- Search for the track by its name
for i = 0, trackCount - 1 do
    local track = reaper.GetTrack(0, i)
    local _, trackNameCurrent = reaper.GetTrackName(track, "")
    if trackNameCurrent == trackNameToFind then
        trackFound = track
        break
    end
end

-- Check if the track was found
if not trackFound then
    reaper.ShowMessageBox("Track with the specified name not found.", "Error", 0)
    return
end

-- Get the total number of FX on the found track
local fxCount = reaper.TrackFX_GetCount(trackFound)

-- Variable to count the found containers
local containerCount = 0
local containerIndex = -1

-- Search for the container corresponding to the value of containerToFind
for i = 0, fxCount - 1 do
    local fx_is_container = reaper.TrackFX_GetNamedConfigParm(trackFound, i, "container_count")
    if fx_is_container then  -- If the FX is a container
        containerCount = containerCount + 1
        if containerCount == containerToFind then  -- Found the n-th container
            containerIndex = i
            break
        end
    end
end

-- Check if the container was found
if containerIndex == -1 then
    reaper.ShowMessageBox("Container number " .. containerToFind .. " not found in the track.", "Error", 0)
    return
end

-- Toggle the bypass of the container
local currentBypassState = reaper.TrackFX_GetEnabled(trackFound, containerIndex)
reaper.TrackFX_SetEnabled(trackFound, containerIndex, not currentBypassState)

-- reaper.ShowMessageBox("Toggled bypass state of container #" .. containerToFind, "Success", 0)
]]

-- Step 3: Create a name for the new script file
local script_name = "[Generated]_Toggle bypass " .. containerToFind .. " Container " .. trackName .. ".lua"

-- Define the path where the script will be saved (in REAPER's script path)
local script_path = reaper.GetResourcePath() .. "/Scripts/" .. script_name

-- Step 4: Write the script content to the file
local file = io.open(script_path, "w")
if not file then
    reaper.ShowMessageBox("Failed to write the script file: " .. script_path, "Error", 0)
    return
end

file:write(script_content)
file:close()

-- Step 5: Register the new script as an action in the Action List
local ret = reaper.AddRemoveReaScript(true, 0, script_path, true)
if ret == 0 then
    reaper.ShowMessageBox("Error registering the new script as an action.", "Whoops!", 0)
    return
end

-- Step 6: Confirm success to the user
reaper.ShowMessageBox("Script successfully created and added to the Action List:\n" .. script_name, "Done!", 0)

