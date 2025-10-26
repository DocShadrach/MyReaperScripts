-- DocShadrach_Project-wide sync ON-OFF FX [Creator]
-- Creates a script that synchronizes bypass state for a specific FX across all tracks in the project
-- v1.1
-- Ignores offline FX instances, only considers active bypass states
-- Container support limited to first-level containers only

-- Step 1: Ask the user for the FX name
local retval, fxName = reaper.GetUserInputs("Project-wide sync ON-OFF FX", 1, "FX Name:", "")
if not retval then return end  -- Exit if the user cancels

if not fxName or fxName == "" then
    reaper.ShowMessageBox("Invalid input. Please enter an FX name.", "Error", 0)
    return
end

-- Step 2: Ask if user wants to search inside containers
local containerResult = reaper.ShowMessageBox(
    "Do you want the script to search for FX instances inside containers?\n\n" ..
    "This will find FX in:\n" ..
    "- Track containers (first level only)\n" ..
    "- Does NOT search inside nested containers\n\n" ..
    "If you choose No, the script will only search in regular tracks and master track.",
    "Search Inside Containers?", 4  -- 4 = Yes/No buttons
)

local includeContainers = (containerResult == 6)  -- 6 = Yes button
local containerSuffix = includeContainers and " (incl Containers)" or " (excl Containers)"

-- Step 3: Define the script content for project-wide FX sync bypass
local script_content = [[
-- Project-wide FX Sync Bypass Script
-- Automatically generated script
-- Synchronizes bypass state for a specific FX across all tracks
-- Ignores offline FX instances, only considers active bypass states
]] .. (includeContainers and "-- Includes FX instances inside first-level containers only\n" or "-- Excludes FX instances inside containers\n") .. [[

-- FX information
local fxNameToFind = "]] .. fxName .. [["
local includeContainers = ]] .. tostring(includeContainers) .. [[

-- Function to search for FX in a track and its containers
local function searchFXInTrack(track)
    local fxFound = {}
    local enabledCount = 0
    local disabledCount = 0
    local offlineCount = 0
    
    -- Get the total number of FX on this track
    local fxCount = reaper.TrackFX_GetCount(track)
    
    -- Search for ALL FX matching the name on this track
    for fxIndex = 0, fxCount - 1 do
        local _, currentFxName = reaper.TrackFX_GetFXName(track, fxIndex, "")
        if currentFxName:find(fxNameToFind) then  -- If the FX name contains the user-provided FX name
            -- Check if FX is offline (bypass state is not available for offline FX)
            local isOffline = reaper.TrackFX_GetOffline(track, fxIndex)
            
            if isOffline then
                -- Skip offline FX instances
                offlineCount = offlineCount + 1
            else
                -- Only count online FX instances
                local currentBypassState = reaper.TrackFX_GetEnabled(track, fxIndex)
                local fxInfo = {
                    track = track,
                    fxIndex = fxIndex,
                    bypassState = currentBypassState,
                    isContainerTrack = false
                }
                table.insert(fxFound, fxInfo)
                
                if currentBypassState then
                    enabledCount = enabledCount + 1
                else
                    disabledCount = disabledCount + 1
                end
            end
        end
        
        -- If including containers, search inside first-level containers on this track
        if includeContainers then
            -- Check if this FX is a container
            local retval, containerCount = reaper.TrackFX_GetNamedConfigParm(track, fxIndex, "container_count")
            if retval and tonumber(containerCount) and tonumber(containerCount) > 0 then
                -- This is a container, search inside it (first level only)
                local numFXInContainer = tonumber(containerCount)
                
                -- Search for FX inside this container
                for containerFXIndex = 0, numFXInContainer - 1 do
                    -- Calculate the index for FX inside container
                    local containerFXGlobalIndex = 0x2000000 + (containerFXIndex + 1) * (fxCount + 1) + fxIndex + 1
                    
                    -- Get FX name inside container
                    local _, containerFXName = reaper.TrackFX_GetFXName(track, containerFXGlobalIndex, "")
                    if containerFXName:find(fxNameToFind) then
                        -- Check if container FX is offline
                        local isContainerFXOffline = reaper.TrackFX_GetOffline(track, containerFXGlobalIndex)
                        
                        if isContainerFXOffline then
                            -- Skip offline container FX instances
                            offlineCount = offlineCount + 1
                        else
                            -- Only count online container FX instances
                            local containerBypassState = reaper.TrackFX_GetEnabled(track, containerFXGlobalIndex)
                            local containerFXInfo = {
                                track = track,
                                fxIndex = containerFXGlobalIndex,
                                bypassState = containerBypassState,
                                isContainerTrack = true
                            }
                            table.insert(fxFound, containerFXInfo)
                            
                            if containerBypassState then
                                enabledCount = enabledCount + 1
                            else
                                disabledCount = disabledCount + 1
                            end
                        end
                    end
                end
            end
        end
    end
    
    return fxFound, enabledCount, disabledCount, offlineCount
end

-- Variables to track results and analyze current state
local totalTracksProcessed = 0
local totalFXFound = 0
local tracksWithFX = 0
local enabledFXCount = 0
local disabledFXCount = 0
local offlineFXCount = 0
local allFXInstances = {}

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
    
    -- Search for FX in this track (including containers if enabled)
    local fxFound, enabledCount, disabledCount, offlineCount = searchFXInTrack(track)
    
    -- Add found FX to our collection
    for _, fxInfo in ipairs(fxFound) do
        table.insert(allFXInstances, fxInfo)
        totalFXFound = totalFXFound + 1
        tracksWithFX = tracksWithFX + 1
    end
    
    enabledFXCount = enabledFXCount + enabledCount
    disabledFXCount = disabledFXCount + disabledCount
    offlineFXCount = offlineFXCount + offlineCount
end

-- Determine the action based on current state
local actionToTake = ""
local newState = false
local showMessage = false

if totalFXFound == 0 then
    local message = "No active FX instances found matching:\n" ..
                   "FX Name: " .. fxNameToFind .. "\n" ..
                   "Searched " .. totalTracksProcessed .. " tracks"
    
    if offlineFXCount > 0 then
        message = message .. "\n\nNote: " .. offlineFXCount .. " offline FX instances were ignored"
    end
    
    if includeContainers then
        message = message .. "\n\nContainer search: " .. (includeContainers and "ENABLED (first level only)" or "DISABLED")
    end
    
    reaper.ShowMessageBox(message, "No Active FX Found", 0)
    return
end

-- Logic for synchronization:
-- If all FX are enabled, disable all (no message)
-- If all FX are disabled, enable all (no message)
-- If mixed states, ask for confirmation to disable all
if enabledFXCount == totalFXFound then
    -- All FX are enabled, so disable all (silent)
    actionToTake = "Disabling all active FX instances"
    newState = false
    showMessage = false
elseif disabledFXCount == totalFXFound then
    -- All FX are disabled, so enable all (silent)
    actionToTake = "Enabling all active FX instances"
    newState = true
    showMessage = false
else
    -- Mixed states, ask for confirmation to disable all
    local message = "Mixed states detected for FX: " .. fxNameToFind .. "\n\n" ..
                   "Found: " .. enabledFXCount .. " enabled, " .. disabledFXCount .. " disabled\n" ..
                   "Total active FX instances: " .. totalFXFound
    
    if offlineFXCount > 0 then
        message = message .. "\n\nNote: " .. offlineFXCount .. " offline FX instances were ignored"
    end
    
    if includeContainers then
        message = message .. "\n\nContainer search: " .. (includeContainers and "ENABLED (first level only)" or "DISABLED")
    end
    
    message = message .. "\n\nThe script will disable all active FX instances to synchronize them.\n" ..
             "Are you sure you want to continue?"
    
    local confirmResult = reaper.ShowMessageBox(message, "Mixed States Detected", 4)  -- 4 = Yes/No buttons
    
    if confirmResult == 6 then  -- 6 = Yes button
        actionToTake = "Mixed states detected - disabling all active FX instances"
        newState = false
        showMessage = false  -- No need to show message after confirmation
    else
        -- User cancelled
        return
    end
end

-- Second pass: Apply the determined action to all found FX instances
for _, fxInfo in ipairs(allFXInstances) do
    reaper.TrackFX_SetEnabled(fxInfo.track, fxInfo.fxIndex, newState)
end

-- Only show message for mixed states (after confirmation)
if showMessage then
    local stateDescription = newState and "ENABLED" or "DISABLED"
    local message = actionToTake .. "\n\n" ..
                   "FX: " .. fxNameToFind .. "\n" ..
                   "New state: All active FX " .. stateDescription .. "\n" ..
                   "Total active FX instances: " .. totalFXFound .. "\n" ..
                   "Tracks with active FX: " .. tracksWithFX
    
    if offlineFXCount > 0 then
        message = message .. "\n\nNote: " .. offlineFXCount .. " offline FX instances were ignored"
    end
    
    if includeContainers then
        message = message .. "\n\nContainer search: " .. (includeContainers and "ENABLED (first level only)" or "DISABLED")
    end
    
    reaper.ShowMessageBox(message, "FX Sync Complete", 0)
end

-- Update the arrange view
reaper.TrackList_AdjustWindows(false)
reaper.UpdateArrange()
]]

-- Step 4: Create a name for the new script file
local script_name = "[Generated]_Project-wide sync ON-OFF " .. fxName .. " plugin" .. containerSuffix .. ".lua"

-- Define the path where the script will be saved (in REAPER's script path)
local script_path = reaper.GetResourcePath() .. "/Scripts/" .. script_name

-- Step 5: Write the script content to the file
local file = io.open(script_path, "w")
if not file then
    reaper.ShowMessageBox("Failed to write the script file: " .. script_path, "Error", 0)
    return
end

file:write(script_content)
file:close()

-- Step 6: Register the new script as an action in the Action List
local ret = reaper.AddRemoveReaScript(true, 0, script_path, true)
if ret == 0 then
    reaper.ShowMessageBox("Error registering the new script as an action.", "Whoops!", 0)
    return
end

-- Step 7: Confirm success to the user
local containerInfo = includeContainers and 
    "Container search: ENABLED (first level containers only)" or 
    "Container search: DISABLED (will only search regular tracks and master track)"

local successMessage = "Project-wide FX sync bypass script successfully created and added to the Action List:\n" .. 
    script_name .. "\n\n" ..
    "This script will synchronize bypass state for '" .. fxName .. "' FX across ALL tracks in the project.\n\n" ..
    "Logic:\n" ..
    "- If all active FX are enabled: Disable all\n" ..
    "- If all active FX are disabled: Enable all\n" ..
    "- If mixed states: Disable all (next run will enable all)\n\n" ..
    "Features:\n" ..
    "- Offline FX instances are ignored\n" ..
    "- " .. containerInfo .. 
    (includeContainers and "\n- Note: Does NOT search inside nested containers (containers inside containers)" or "")

reaper.ShowMessageBox(successMessage, "Script Created Successfully", 0)
