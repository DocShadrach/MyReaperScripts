-- Step 1: Ask the user for the track name, FX name, FX position, and desired oversampling
local retval, userInput = reaper.GetUserInputs("Track, FX, Position, and Oversampling", 4, "Track Name:,FX Name:,FX Position (Relative):,Oversampling (2,4,8,16):", "")
if not retval then return end  -- Exit if the user cancels

local trackName, fxName, fxPosition, oversampling = userInput:match("([^,]+),([^,]+),([^,]+),([^,]+)")
fxPosition = tonumber(fxPosition)  -- Ensure fxPosition is a number
oversampling = tonumber(oversampling)  -- Ensure oversampling is a number

-- Validate that the input values are correct
if not trackName or not fxName or not fxPosition or not oversampling or (oversampling ~= 2 and oversampling ~= 4 and oversampling ~= 8 and oversampling ~= 16) then
    reaper.ShowMessageBox("Invalid input. Please enter a track name, FX name, position, and valid oversampling (2, 4, 8, or 16).", "Error", 0)
    return
end

-- Step 2: Define the script content to enable oversampling
local script_enable = [[
-- Automatically generated script to enable oversampling

-- Track, FX, and position information
local trackNameToFind = "]] .. trackName .. [["
local fxNameToFind = "]] .. fxName .. [["  -- The name of the FX to search for
local fxPositionToFind = ]] .. tostring(fxPosition) .. [[  -- Relative position of the FX (1 for first, 2 for second, etc.)
local oversamplingValue = ]] .. tostring(oversampling) .. [[  -- Ensure the value is a number

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

-- Variable to store the index of the FX
local fxIndex = -1
local fxMatchCount = 0  -- Variable to count how many FX match the given name

-- Search for the FX that matches the name and appearance order
for i = 0, fxCount - 1 do
    local _, currentFxName = reaper.TrackFX_GetFXName(trackFound, i, "")
    if currentFxName:find(fxNameToFind) then  -- If the FX name contains the user-provided FX name
        fxMatchCount = fxMatchCount + 1  -- Increment the match count
        if fxMatchCount == fxPositionToFind then  -- If this is the n-th appearance of the FX
            fxIndex = i
            break
        end
    end
end

-- Check if the FX was found
if fxIndex == -1 then
    reaper.ShowMessageBox("FX '" .. fxNameToFind .. "' not found at the specified position.", "Error", 0)
    return
end

-- Set the oversampling based on the input value
local oversampling_shift = math.log(oversamplingValue, 2)  -- Calculate the shift for the oversampling
reaper.TrackFX_SetNamedConfigParm(trackFound, fxIndex, 'instance_oversample_shift', oversampling_shift)  -- Set oversampling value
]]

-- Step 3: Define the script content to disable oversampling (set it to 1x)
local script_disable = [[
-- Automatically generated script to disable oversampling

-- Track, FX, and position information
local trackNameToFind = "]] .. trackName .. [["  -- The name of the track to search for
local fxNameToFind = "]] .. fxName .. [["  -- The name of the FX to search for
local fxPositionToFind = ]] .. tostring(fxPosition) .. [[  -- Relative position of the FX (1 for first, 2 for second, etc.)

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

-- Variable to store the index of the FX
local fxIndex = -1
local fxMatchCount = 0  -- Variable to count how many FX match the given name

-- Search for the FX that matches the name and appearance order
for i = 0, fxCount - 1 do
    local _, currentFxName = reaper.TrackFX_GetFXName(trackFound, i, "")
    if currentFxName:find(fxNameToFind) then  -- If the FX name contains the user-provided FX name
        fxMatchCount = fxMatchCount + 1  -- Increment the match count
        if fxMatchCount == fxPositionToFind then  -- If this is the n-th appearance of the FX
            fxIndex = i
            break
        end
    end
end

-- Check if the FX was found
if fxIndex == -1 then
    reaper.ShowMessageBox("FX '" .. fxNameToFind .. "' not found at the specified position.", "Error", 0)
    return
end

-- Disable the oversampling (set to 1x)
reaper.TrackFX_SetNamedConfigParm(trackFound, fxIndex, 'instance_oversample_shift', 0)  -- Set to 1x
]]


-- Step 4: Create names for the new script files
local script_name_enable = "Enable_Oversampling_" .. oversampling .. "x_" .. fxName .. "_" .. trackName
local script_name_disable = "Disable_Oversampling_" .. fxName .. "_" .. trackName

-- Add the position to the names if it's not 0
if fxPosition ~= 0 then
    script_name_enable = script_name_enable .. "_" .. fxPosition .. "_position"
    script_name_disable = script_name_disable .. "_" .. fxPosition .. "_position"
end

-- Complete the script names
script_name_enable = script_name_enable .. ".lua"
script_name_disable = script_name_disable .. ".lua"

-- Define the paths where the scripts will be saved (in REAPER's script path)
local script_path_enable = reaper.GetResourcePath() .. "/Scripts/" .. script_name_enable
local script_path_disable = reaper.GetResourcePath() .. "/Scripts/" .. script_name_disable

-- Step 5: Write the "Enable Oversampling" script to the file
local file_enable = io.open(script_path_enable, "w")
if not file_enable then
    reaper.ShowMessageBox("Failed to write the script file: " .. script_path_enable, "Error", 0)
    return
end
file_enable:write(script_enable)
file_enable:close()

-- Step 6: Write the "Disable Oversampling" script to the file
local file_disable = io.open(script_path_disable, "w")
if not file_disable then
    reaper.ShowMessageBox("Failed to write the script file: " .. script_path_disable, "Error", 0)
    return
end
file_disable:write(script_disable)
file_disable:close()

-- Step 7: Register the new scripts as actions in the Action List
local ret_enable = reaper.AddRemoveReaScript(true, 0, script_path_enable, true)
local ret_disable = reaper.AddRemoveReaScript(true, 0, script_path_disable, true)

if ret_enable == 0 or ret_disable == 0 then
    reaper.ShowMessageBox("Error registering the new scripts as actions.", "Whoops!", 0)
    return
end

-- Step 8: Confirm success to the user
reaper.ShowMessageBox("Scripts successfully created and added to the Action List:\n" .. script_name_enable .. "\n" .. script_name_disable, "Done!", 0)
