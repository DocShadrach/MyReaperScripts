-- Prompt the user for the track name and FX name
local userInputs = {}
local userInputCount, userInputs = reaper.GetUserInputs("Input Required", 2, "Track Name:,FX Name:", "")
if userInputCount then
    local trackNameToFind, fxNameToFind = userInputs:match("([^,]+),([^,]+)")

    -- Verify that both names are not empty
    if not trackNameToFind or not fxNameToFind then
        reaper.ShowMessageBox("Please enter a valid track name and FX name.", "Error", 0)
        return
    end

    -- Create the script that moves to the next preset
    local forwardScript = [[
-- Track and FX to search for
local trackNameToFind = "]] .. trackNameToFind .. [["  -- Track name
local fxNameToFind = "]] .. fxNameToFind .. [["   -- FX name

-- Get the total number of tracks
local trackCount = reaper.CountTracks(0)

-- Variable to store the found track
local trackFound = nil

-- Search for the track by name
for i = 0, trackCount - 1 do
    local track = reaper.GetTrack(0, i)
    local _, trackName = reaper.GetTrackName(track, "")
    if trackName == trackNameToFind then
        trackFound = track
        break
    end
end

-- Verify if the track was found
if not trackFound then
    reaper.ShowMessageBox("Track with the specified name not found.", "Error", 0)
    return
end

-- Get the total number of FX in the found track
local fxCount = reaper.TrackFX_GetCount(trackFound)

-- Variable to store the index of the found FX
local fxIndex = -1

-- Search for the FX by name
for i = 0, fxCount - 1 do
    local _, currentFxName = reaper.TrackFX_GetFXName(trackFound, i, "")
    if currentFxName:find(fxNameToFind) then
        fxIndex = i
        break
    end
end

-- Verify if the FX was found
if fxIndex == -1 then
    reaper.ShowMessageBox("FX '" .. fxNameToFind .. "' not found on the track.", "Error", 0)
    return
end

-- Get the current preset
local retval, currentPresetIndex = reaper.TrackFX_GetPresetIndex(trackFound, fxIndex)

-- If there's an error
if retval == -1 then
    reaper.ShowMessageBox("Could not retrieve preset information.", "Error", 0)
    return
end

-- Move to the next preset
local success = reaper.TrackFX_NavigatePresets(trackFound, fxIndex, 1)  -- Change to the next preset
if not success then
    reaper.TrackFX_SetPresetByIndex(trackFound, fxIndex, 0) -- Go back to the first preset if it's the last
end

-- Get the new preset to display
local _, newPresetName = reaper.TrackFX_GetPreset(trackFound, fxIndex, "")
]]

    -- Create the script that moves to the previous preset
    local backwardScript = [[
-- Track and FX to search for
local trackNameToFind = "]] .. trackNameToFind .. [["  -- Track name
local fxNameToFind = "]] .. fxNameToFind .. [["   -- FX name

-- Get the total number of tracks
local trackCount = reaper.CountTracks(0)

-- Variable to store the found track
local trackFound = nil

-- Search for the track by name
for i = 0, trackCount - 1 do
    local track = reaper.GetTrack(0, i)
    local _, trackName = reaper.GetTrackName(track, "")
    if trackName == trackNameToFind then
        trackFound = track
        break
    end
end

-- Verify if the track was found
if not trackFound then
    reaper.ShowMessageBox("Track with the specified name not found.", "Error", 0)
    return
end

-- Get the total number of FX in the found track
local fxCount = reaper.TrackFX_GetCount(trackFound)

-- Variable to store the index of the found FX
local fxIndex = -1

-- Search for the FX by name
for i = 0, fxCount - 1 do
    local _, currentFxName = reaper.TrackFX_GetFXName(trackFound, i, "")
    if currentFxName:find(fxNameToFind) then
        fxIndex = i
        break
    end
end

-- Verify if the FX was found
if fxIndex == -1 then
    reaper.ShowMessageBox("FX '" .. fxNameToFind .. "' not found on the track.", "Error", 0)
    return
end

-- Get the current preset
local retval, currentPresetIndex = reaper.TrackFX_GetPresetIndex(trackFound, fxIndex)

-- If there's an error
if retval == -1 then
    reaper.ShowMessageBox("Could not retrieve preset information.", "Error", 0)
    return
end

-- Move to the previous preset
local success = reaper.TrackFX_NavigatePresets(trackFound, fxIndex, -1)  -- Change to the previous preset
if not success then
    reaper.TrackFX_SetPresetByIndex(trackFound, fxIndex, reaper.TrackFX_GetPresetCount(trackFound, fxIndex) - 1) -- Go back to the last preset if it's the first
end

-- Get the new preset to display
local _, newPresetName = reaper.TrackFX_GetPreset(trackFound, fxIndex, "")
]]

    -- Format the names of the scripts
    local forwardScriptName = "[Generated]_Selecting presets in loop " .. fxNameToFind:gsub("[^%w]", " ") .. " " .. trackNameToFind:gsub("[^%w]", " ") .. " (Forward).lua"
    local backwardScriptName = "[Generated]_Selecting presets in loop " .. fxNameToFind:gsub("[^%w]", " ") .. " " .. trackNameToFind:gsub("[^%w]", " ") .. " (Backward).lua"

    -- Save the forward script to a file
    local forwardFilePath = reaper.GetResourcePath() .. "/Scripts/" .. forwardScriptName
    local forwardFile = io.open(forwardFilePath, "w")
    if forwardFile then
        forwardFile:write(forwardScript)
        forwardFile:close()

        -- Register the new script as an action
        local ret = reaper.AddRemoveReaScript(true, 0, forwardFilePath, true)
        if ret == 0 then
            reaper.ShowMessageBox("Error registering the forward script as an action.", "Whoops!", 0)
            return
        else
            reaper.ShowMessageBox("New script saved and registered as action: " .. forwardScriptName, "Success", 0)
        end
    else
        reaper.ShowMessageBox("Error saving the forward script.", "Error", 0)
    end

    -- Save the backward script to a file
    local backwardFilePath = reaper.GetResourcePath() .. "/Scripts/" .. backwardScriptName
    local backwardFile = io.open(backwardFilePath, "w")
    if backwardFile then
        backwardFile:write(backwardScript)
        backwardFile:close()

        -- Register the new script as an action
        local ret = reaper.AddRemoveReaScript(true, 0, backwardFilePath, true)
        if ret == 0 then
            reaper.ShowMessageBox("Error registering the backward script as an action.", "Whoops!", 0)
            return
        else
            reaper.ShowMessageBox("New script saved and registered as action: " .. backwardScriptName, "Success", 0)
        end
    else
        reaper.ShowMessageBox("Error saving the backward script.", "Error", 0)
    end
else
    reaper.ShowMessageBox("No inputs were provided.", "Error", 0)
end
