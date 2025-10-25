-- DocShadrach_Project-wide sync ON-OFF FX [Creator]
-- Creates a script that synchronizes bypass state for a specific FX across all tracks in the project

-- Step 1: Ask the user for the FX name
local retval, fxName = reaper.GetUserInputs("Project-wide sync ON-OFF FX", 1, "FX Name:", "")
if not retval then return end  -- Exit if the user cancels

if not fxName or fxName == "" then
    reaper.ShowMessageBox("Invalid input. Please enter an FX name.", "Error", 0)
    return
end

-- Step 2: Define the script content for project-wide FX sync bypass
local script_content = [[
-- Project-wide FX Sync Bypass Script
-- Automatically generated script
-- Synchronizes bypass state for a specific FX across all tracks

-- FX information
local fxNameToFind = "]] .. fxName .. [["

-- Variables to track results and analyze current state
local totalTracksProcessed = 0
local totalFXFound = 0
local tracksWithFX = 0
local enabledFXCount = 0
local disabledFXCount = 0

-- Get the total number of tracks in the project
local trackCount = reaper.CountTracks(0)

-- First pass: Analyze current state (regular tracks + Master Track)
for trackIndex = -1, trackCount - 1 do
    local track
    if trackIndex == -1 then
        -- Master Track
        track = reaper.GetMasterTrack(0)
        totalTracksProcessed = totalTracksProcessed + 1
    else
        -- Regular tracks
        track = reaper.GetTrack(0, trackIndex)
        totalTracksProcessed = totalTracksProcessed + 1
    end
    
    -- Get the total number of FX on this track
    local fxCount = reaper.TrackFX_GetCount(track)
    
    -- Search for ALL FX matching the name
    for fxIndex = 0, fxCount - 1 do
        local _, currentFxName = reaper.TrackFX_GetFXName(track, fxIndex, "")
        if currentFxName:find(fxNameToFind) then  -- If the FX name contains the user-provided FX name
            totalFXFound = totalFXFound + 1
            tracksWithFX = tracksWithFX + 1
            
            -- Count enabled vs disabled FX
            local currentBypassState = reaper.TrackFX_GetEnabled(track, fxIndex)
            if currentBypassState then
                enabledFXCount = enabledFXCount + 1
            else
                disabledFXCount = disabledFXCount + 1
            end
        end
    end
end

-- Determine the action based on current state
local actionToTake = ""
local newState = false
local showMessage = false

if totalFXFound == 0 then
    reaper.ShowMessageBox(
        "No FX instances found matching:\n" ..
        "FX Name: " .. fxNameToFind .. "\n" ..
        "Searched " .. totalTracksProcessed .. " tracks",
        "No FX Found", 0
    )
    return
end

-- Logic for synchronization:
-- If all FX are enabled, disable all (no message)
-- If all FX are disabled, enable all (no message)
-- If mixed states, ask for confirmation to disable all
if enabledFXCount == totalFXFound then
    -- All FX are enabled, so disable all (silent)
    actionToTake = "Disabling all FX instances"
    newState = false
    showMessage = false
elseif disabledFXCount == totalFXFound then
    -- All FX are disabled, so enable all (silent)
    actionToTake = "Enabling all FX instances"
    newState = true
    showMessage = false
else
    -- Mixed states, ask for confirmation to disable all
    local confirmResult = reaper.ShowMessageBox(
        "Mixed states detected for FX: " .. fxNameToFind .. "\n\n" ..
        "Found: " .. enabledFXCount .. " enabled, " .. disabledFXCount .. " disabled\n" ..
        "Total FX instances: " .. totalFXFound .. "\n\n" ..
        "The script will disable all FX instances to synchronize them.\n" ..
        "Are you sure you want to continue?",
        "Mixed States Detected", 4  -- 4 = Yes/No buttons
    )
    
    if confirmResult == 6 then  -- 6 = Yes button
        actionToTake = "Mixed states detected - disabling all FX instances"
        newState = false
        showMessage = false  -- No need to show message after confirmation
    else
        -- User cancelled
        return
    end
end

-- Second pass: Apply the determined action (regular tracks + Master Track)
for trackIndex = -1, trackCount - 1 do
    local track
    if trackIndex == -1 then
        -- Master Track
        track = reaper.GetMasterTrack(0)
    else
        -- Regular tracks
        track = reaper.GetTrack(0, trackIndex)
    end
    
    -- Get the total number of FX on this track
    local fxCount = reaper.TrackFX_GetCount(track)
    
    -- Apply the new state to all matching FX
    for fxIndex = 0, fxCount - 1 do
        local _, currentFxName = reaper.TrackFX_GetFXName(track, fxIndex, "")
        if currentFxName:find(fxNameToFind) then
            reaper.TrackFX_SetEnabled(track, fxIndex, newState)
        end
    end
end

-- Only show message for mixed states (after confirmation)
if showMessage then
    local stateDescription = newState and "ENABLED" or "DISABLED"
    reaper.ShowMessageBox(
        actionToTake .. "\n\n" ..
        "FX: " .. fxNameToFind .. "\n" ..
        "New state: All FX " .. stateDescription .. "\n" ..
        "Total FX instances: " .. totalFXFound .. "\n" ..
        "Tracks with FX: " .. tracksWithFX,
        "FX Sync Complete", 0
    )
end

-- Update the arrange view
reaper.TrackList_AdjustWindows(false)
reaper.UpdateArrange()
]]

-- Step 3: Create a name for the new script file
local script_name = "[Generated]_Project-wide sync ON-OFF " .. fxName .. " plugin.lua"

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
reaper.ShowMessageBox(
    "Project-wide FX sync bypass script successfully created and added to the Action List:\n" .. 
    script_name .. "\n\n" ..
    "This script will synchronize bypass state for '" .. fxName .. "' FX across ALL tracks in the project.\n\n" ..
    "Logic:\n" ..
    "- If all FX are enabled: Disable all\n" ..
    "- If all FX are disabled: Enable all\n" ..
    "- If mixed states: Disable all (next run will enable all)",
    "Script Created Successfully", 0
)
