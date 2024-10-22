-- Step 1: Ask for user inputs (track name and number of sends)
retval, user_inputs = reaper.GetUserInputs("Script Setup", 2, "Track Name:,Number of Sends:", "")
if retval == false then return end  -- If the user cancels, stop the script

-- Step 2: Parse user inputs (handling potential nil for track_name)
track_name, num_sends = user_inputs:match("([^,]*),([^,]+)")

-- Convert num_sends to number and validate
num_sends = tonumber(num_sends)
if not num_sends or num_sends < 1 then
    reaper.ShowMessageBox("Invalid number of sends. Please enter a valid number.", "Error", 0)
    return
end

-- Step 3: Ask for the names of the target tracks for each send
local send_names = {}  -- Nombres de los tracks que reciben los sends
for i = 1, num_sends do
    retval, send_name = reaper.GetUserInputs("Send " .. i, 1, "Target Track Name:", "")
    if retval == false then return end  -- If the user cancels, stop the script
    
    send_name = send_name:match("^%s*(.-)%s*$")  -- Elimina espacios antes y después
    if send_name == "" then
        reaper.ShowMessageBox("Invalid track name for send " .. i, "Error", 0)
        return
    end
    table.insert(send_names, send_name)
end

-- Step 4: Generate the Lua script content based on the input
local script_content = [[
-- Automatically generated script for REAPER
]]

if track_name == "" then
    -- Use selected track if no track name was provided
    script_content = script_content .. [[
-- Get the currently selected track
track = reaper.GetSelectedTrack(0, 0)
if not track then
    reaper.ShowMessageBox("No track selected.", "Error", 0)
    return
end
]]
else
    -- Search for the track by name if provided
    script_content = script_content .. [[
track_name_to_find = "]] .. track_name .. [["

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
]]
end

-- Function to toggle mute for a given send
script_content = script_content .. [[

-- Function to toggle mute for a given send
function toggle_mute_send(track, send_idx)
    local send_mute = reaper.GetTrackSendInfo_Value(track, 0, send_idx, "B_MUTE")
    reaper.SetTrackSendInfo_Value(track, 0, send_idx, "B_MUTE", send_mute == 0 and 1 or 0)
end

-- Mute/unmute specific sends based on the names of the receiving tracks
local num_sends = reaper.GetTrackNumSends(track, 0)
local target_send_names = { ]] .. '"' .. table.concat(send_names, '", "') .. '"' .. [[ }

for send_idx = 0, num_sends - 1 do
    local dest_track = reaper.BR_GetMediaTrackSendInfo_Track(track, 0, send_idx, 1) -- Get destination track
    _, dest_track_name = reaper.GetSetMediaTrackInfo_String(dest_track, "P_NAME", "", false)

    for _, target_name in ipairs(target_send_names) do
        if dest_track_name == target_name then
            toggle_mute_send(track, send_idx)
        end
    end
end

-- Refresh the UI
reaper.TrackList_AdjustWindows(false)
reaper.UpdateArrange()
]]

-- Step 5: Create the script filename based on user input
local script_name
if track_name == "" then
    script_name = "Toggle_Mute_Sends_" .. table.concat(send_names, "-") .. "_SelectedTrack.lua"
else
    script_name = "Toggle_Mute_Sends_" .. table.concat(send_names, "-") .. "_" .. track_name .. ".lua"
end

-- Step 6: Write the script to a file
local script_path = reaper.GetResourcePath() .. "/Scripts/" .. script_name
local file = io.open(script_path, "w")
if not file then
    reaper.ShowMessageBox("Failed to write the script file: " .. script_path, "Error", 0)
    return
end

file:write(script_content)
file:close()

-- Step 7: Register the new script as an action
local ret = reaper.AddRemoveReaScript(true, 0, script_path, true)
if ret == 0 then
    reaper.ShowMessageBox("Error registering the new script as an action.", "Whoops!", 0)
    return
end

-- Step 8: Confirm success to the user
reaper.ShowMessageBox("Script successfully created and added to the Action List:\n" .. script_name, "Done!", 0)

