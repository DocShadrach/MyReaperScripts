-- Step 1: Ask for user inputs
retval, user_inputs = reaper.GetUserInputs("Script Setup", 2, "Track Name:,All Sends (Y/N):", "")
if retval == false then return end  -- If the user cancels, stop the script

-- Step 2: Parse user inputs
track_name, all_sends = user_inputs:match("([^,]*),([^,]+)")

-- Validate inputs
if (not track_name) or (all_sends ~= "Y" and all_sends ~= "y" and all_sends ~= "N" and all_sends ~= "n") then
    reaper.ShowMessageBox("Invalid inputs. Please check the values.", "Error", 0)
    return
end

local mute_all_sends = all_sends:upper() == "Y"

-- Step 3: If not applying to all sends, ask for specific send numbers
local sends = {}
local user_sends = {}  -- To store user input sends for filename
if not mute_all_sends then
    retval, send_numbers = reaper.GetUserInputs("Select Sends", 1, "Send Numbers (e.g. 2,4,5):", "")
    if retval == false then return end  -- If the user cancels, stop the script
    
    -- Parse the send numbers, split by comma
    for num in string.gmatch(send_numbers, "%d+") do
        table.insert(sends, tonumber(num) - 1) -- Convert to 0-based indexing for REAPER
        table.insert(user_sends, tonumber(num)) -- Store the exact input for the filename
    end
    
    if #sends == 0 then
        reaper.ShowMessageBox("No valid send numbers provided.", "Error", 0)
        return
    end
end

-- Step 4: Generate the Lua script content based on the input
local script_content = [[
-- Automatically generated script for REAPER
]]

if track_name == "" then
    -- If no track name is provided, use selected track
    script_content = script_content .. [[
-- Get the currently selected track
track = reaper.GetSelectedTrack(0, 0)
if not track then
    reaper.ShowMessageBox("No track selected.", "Error", 0)
    return
end
]]
else
    -- Search for the track by name
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
]]

if mute_all_sends then
    -- Handle muting all sends
    script_content = script_content .. [[
-- Get the number of sends on the track
local num_sends = reaper.GetTrackNumSends(track, 0)

-- Mute/unmute all sends
for send_idx = 0, num_sends - 1 do
    toggle_mute_send(track, send_idx)
end
]]
else
    -- Handle muting specific sends
    script_content = script_content .. [[
-- Mute/unmute specific sends
local sends_to_toggle = { ]] .. table.concat(sends, ", ") .. [[ }

for _, send_idx in ipairs(sends_to_toggle) do
    toggle_mute_send(track, send_idx)
end
]]
end

script_content = script_content .. [[

-- Refresh the UI
reaper.TrackList_AdjustWindows(false)
reaper.UpdateArrange()
]]

-- Step 5: Create the script filename based on user input
local script_name
if track_name == "" then
    if mute_all_sends then
        script_name = "[Generated]_Toggle mute all Sends SelectedTrack.lua"
    else
        script_name = "[Generated]_Toggle mute Sends " .. table.concat(user_sends, "-") .. " SelectedTrack.lua"
    end
else
    if mute_all_sends then
        script_name = "[Generated]_Toggle mute all Sends " .. track_name .. ".lua"
    else
        script_name = "[Generated]_Toggle mute Sends " .. table.concat(user_sends, "-") .. " " .. track_name .. ".lua"
    end
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

