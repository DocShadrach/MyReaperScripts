-- Step 1: Ask the user for the track name, FX name, and container position
local retval, userInput = reaper.GetUserInputs("Track, FX, and Position Info", 3, "Track Name (empty = selected):,FX Name:,FX Position (empty = unique):", "")
if not retval then return end  -- Exit if the user cancels

local trackName, fxName, fxPosition = userInput:match("([^,]*),([^,]+),([^,]*)")

-- If FX position is empty, treat it as "unique" (0)
if fxPosition == "" then
    fxPosition = 0
else
    fxPosition = tonumber(fxPosition)
end

if not trackName or not fxName or not fxPosition then
    reaper.ShowMessageBox("Invalid input. Please enter FX name. Track name and FX position may be empty.", "Error", 0)
    return
end

-- Step 2: Define the script content
local script_content = [[
-- Automatically generated script

local trackNameToFind = "]] .. trackName .. [["
local fxNameToFind = "]] .. fxName .. [["
local fxPositionToFind = ]] .. fxPosition .. [[

local trackFound = nil

-- If no track name was given → use selected track
if trackNameToFind == "" then
    trackFound = reaper.GetSelectedTrack(0, 0)
    if not trackFound then
        reaper.ShowMessageBox("No track selected.", "Error", 0)
        return
    end
else
    -- Search for track by name
    local trackCount = reaper.CountTracks(0)
    for i = 0, trackCount - 1 do
        local track = reaper.GetTrack(0, i)
        local _, tName = reaper.GetTrackName(track, "")
        if tName == trackNameToFind then
            trackFound = track
            break
        end
    end

    if not trackFound then
        reaper.ShowMessageBox("Track '" .. trackNameToFind .. "' not found.", "Error", 0)
        return
    end
end

-- Now search for the FX
local fxCount = reaper.TrackFX_GetCount(trackFound)
local fxCountInTrack = 0
local fxIndex = -1

for i = 0, fxCount - 1 do
    local _, currentFxName = reaper.TrackFX_GetFXName(trackFound, i, "")
    if currentFxName:find(fxNameToFind) then
        fxCountInTrack = fxCountInTrack + 1
        if fxPositionToFind == 0 or fxCountInTrack == fxPositionToFind then
            fxIndex = i
            break
        end
    end
end

if fxIndex == -1 then
    reaper.ShowMessageBox("FX '" .. fxNameToFind .. "' not found in the selected/named track.", "Error", 0)
    return
end

local currentBypassState = reaper.TrackFX_GetEnabled(trackFound, fxIndex)
reaper.TrackFX_SetEnabled(trackFound, fxIndex, not currentBypassState)
]]

-- Step 3: Create a name for the new script file
local script_name = "[Generated]_Toggle bypass " .. fxName

if trackName ~= "" then
    script_name = script_name .. " on " .. trackName
else
    script_name = script_name .. " on SelectedTrack"
end

if fxPosition ~= 0 then
    script_name = script_name .. " (" .. fxPosition .. ")"
end

script_name = script_name .. ".lua"

-- Step 4: Write file
local script_path = reaper.GetResourcePath() .. "/Scripts/" .. script_name
local file = io.open(script_path, "w")
if not file then
    reaper.ShowMessageBox("Failed to write script file: " .. script_path, "Error", 0)
    return
end

file:write(script_content)
file:close()

-- Step 5: Register script
local ret = reaper.AddRemoveReaScript(true, 0, script_path, true)
if ret == 0 then
    reaper.ShowMessageBox("Error registering the new script as an action.", "Whoops!", 0)
    return
end

-- Step 6: Done
reaper.ShowMessageBox("Script successfully created:\n" .. script_name, "Done!", 0)
