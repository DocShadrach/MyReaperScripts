--[[
ReaScript Name: Rename selected tracks using ReaImGui with selection auto-update and Colored Track Numbers
Description: Opens an ReaImGui window to rename all selected tracks at once with automatic selection update.
Instructions: Select the tracks you want to rename, run the script, and rename each track in the ImGui window.
Author: DocShadrach
--]]

-- Load the ReaImGui library and create a context
local ctx = reaper.ImGui_CreateContext('Rename Selected Tracks')

-- Create variables to store track data and previous state
local track_data = {}
local track_order = {}

-- Function to convert REAPER native color to RGB
local function nativeColorToRGB(native_color)
    if native_color == 0 then return 0.5, 0.5, 0.5 end  -- Default gray for no color
    
    local r = (native_color & 0xFF) / 255
    local g = ((native_color >> 8) & 0xFF) / 255
    local b = ((native_color >> 16) & 0xFF) / 255
    
    return r, g, b
end

-- Function to gather track data and track order
local function gatherTrackData()
    track_data = {}
    track_order = {}
    local num_tracks = reaper.CountSelectedTracks(0)
    
    for i = 0, num_tracks - 1 do
        local track = reaper.GetSelectedTrack(0, i)
        if track then
            local _, current_name = reaper.GetTrackName(track, "")
            local track_number = math.floor(reaper.GetMediaTrackInfo_Value(track, "IP_TRACKNUMBER"))
            local track_color = reaper.GetTrackColor(track)
            local track_guid = reaper.GetTrackGUID(track)
            
            track_data[track_guid] = {
                name = current_name,
                track_number = track_number,
                color = track_color,
                track = track
            }
            
            -- Add the GUID to the ordered list
            table.insert(track_order, track_guid)
        end
    end
end

-- Function to check if selection has changed by comparing track GUIDs
local function hasSelectionChanged()
    local current_track_guids = {}
    local num_tracks = reaper.CountSelectedTracks(0)

    -- Collect GUIDs of currently selected tracks
    for i = 0, num_tracks - 1 do
        local track = reaper.GetSelectedTrack(0, i)
        local track_guid = reaper.GetTrackGUID(track)
        current_track_guids[track_guid] = true
    end

    -- Check if the current set of GUIDs differs from the previous set
    local changed = false
    if #track_order ~= num_tracks then
        changed = true
    else
        for i = 0, num_tracks - 1 do
            local track = reaper.GetSelectedTrack(0, i)
            local track_guid = reaper.GetTrackGUID(track)
            if track_order[i + 1] ~= track_guid then
                changed = true
                break
            end
        end
    end

    return changed
end

-- Function to apply changes to the track names
local function applyChanges()
    reaper.Undo_BeginBlock()
    for _, guid in ipairs(track_order) do
        local data = track_data[guid]
        local track = data.track
        if track then
            reaper.GetSetMediaTrackInfo_String(track, 'P_NAME', data.name, true)
        end
    end
    reaper.Undo_EndBlock("Rename Selected Tracks", -1)
    reaper.UpdateArrange()
    gatherTrackData() -- Refresh data after applying changes
end

-- Create an ImGui frame function
function frame()
    -- Check for selection changes automatically
    if hasSelectionChanged() then
        gatherTrackData()
    end
    
    local changed = false
    -- Loop through selected tracks in the correct order and draw input fields for names
    for _, guid in ipairs(track_order) do
        local data = track_data[guid]
        local track = data.track
        if track then
            -- Convert track color to RGB
            local r, g, b = nativeColorToRGB(data.color)
            
            -- Set the text color for "Track X"
            reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_Text(), reaper.ImGui_ColorConvertDouble4ToU32(r, g, b, 1.0))
            reaper.ImGui_Text(ctx, string.format("Track %d", data.track_number))
            reaper.ImGui_PopStyleColor(ctx)
            
            reaper.ImGui_SameLine(ctx)
            
            -- Input field for the track name
            local _, new_name = reaper.ImGui_InputText(ctx, "##" .. guid, data.name)
            if new_name ~= data.name then
                track_data[guid].name = new_name
                changed = true
            end
        end
    end
    
    -- Detect if the Enter key is pressed
    if reaper.ImGui_IsKeyPressed(ctx, reaper.ImGui_Key_Enter()) then
        applyChanges()
    end

    -- Draw a button to apply changes
    if reaper.ImGui_Button(ctx, 'Apply Changes (Enter)') then
        applyChanges()
    end
    
    -- Detect if the Escape key is pressed
    if reaper.ImGui_IsKeyPressed(ctx, reaper.ImGui_Key_Escape()) then
        return false
    end

    -- Draw a button to close the window
    if reaper.ImGui_Button(ctx, 'Close (Esc)') then
        return false
    end
    
    return true
end

-- Main loop to keep ImGui window open
function main()
    local visible, open = reaper.ImGui_Begin(ctx, 'Rename Selected Tracks', true)
    
    if visible then
        if not frame() then
            open = false
        end
        reaper.ImGui_End(ctx)
    end
    
    if not open then
        return
    else
        reaper.defer(main)
    end
end

-- Initialize track data before starting
gatherTrackData()

-- Start the main loop
main()
