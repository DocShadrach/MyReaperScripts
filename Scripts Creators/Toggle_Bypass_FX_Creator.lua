-- Step 1: Ask the user for the track name, FX name, and container position
local retval, userInput = reaper.GetUserInputs("Track, FX, and Position Info", 3, "Track Name:,FX Name:,FX Position (0 if unique):", "")
if not retval then return end  -- Exit if the user cancels

local trackName, fxName, fxPosition = userInput:match("([^,]+),([^,]+),([^,]+)")
fxPosition = tonumber(fxPosition)

if not trackName or not fxName or not fxPosition then
    reaper.ShowMessageBox("Invalid input. Please enter a track name, FX name, and position.", "Error", 0)
    return
end

-- Step 2: Define the script content
local script_content = [[
-- Automatically generated script

-- Track, FX, and position information
local trackNameToFind = "]] .. trackName .. [["
local fxNameToFind = "]] .. fxName .. [["
local fxPositionToFind = ]] .. fxPosition .. [[

-- Get the total number of tracks
local trackCount = reaper.CountTracks(0)

-- Variable to store the found track
local trackFound = nil

-- Search for the track by its name
for i = 0, trackCount - 1 do
    local track = reaper.GetTrack(0, i)
    local _, trackName = reaper.GetTrackName(track, "")
    if trackName == trackNameToFind then
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

-- Variable to count the found FX
local fxCountInTrack = 0

-- Variable to store the index of the n-th FX
local fxIndex = -1

-- Search for the FX corresponding to the value of fxPositionToFind
for i = 0, fxCount - 1 do
    local _, currentFxName = reaper.TrackFX_GetFXName(trackFound, i, "")
    if currentFxName:find(fxNameToFind) then  -- If the FX name contains the user-provided FX name
        fxCountInTrack = fxCountInTrack + 1
        if fxPositionToFind == 0 or fxCountInTrack == fxPositionToFind then  -- Found the n-th FX or it's the only one
            fxIndex = i
            break
        end
    end
end

-- Check if the FX was found
if fxIndex == -1 then
    reaper.ShowMessageBox("FX '" .. fxNameToFind .. "' not found in the track at the specified position.", "Error", 0)
    return
end

-- Toggle the bypass of the FX
local currentBypassState = reaper.TrackFX_GetEnabled(trackFound, fxIndex)
reaper.TrackFX_SetEnabled(trackFound, fxIndex, not currentBypassState)
]]

-- Step 3: Create a name for the new script file
local script_name = "Toggle_Bypass_" .. fxName .. "_" .. trackName

-- Add the position to the name if it's not 0
if fxPosition ~= 0 then
    script_name = script_name .. "_" .. fxPosition .. "_position"
end

-- Complete the script name
script_name = script_name .. ".lua"

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

