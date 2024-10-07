-- Define the name of the track you want to find
track_name_to_find = "Track Name"  -- CHANGE this to the actual track name

-- Define the range of plugins you want to affect (plugin indices start from 0)
min_fx = 1  -- The second plugin (since Lua indices start at 0, 1 = second plugin)
max_fx = 4  -- The fifth plugin

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

-- Find which plugin within the range is currently active
active_fx = -1
for i = min_fx, max_fx do
    if reaper.TrackFX_GetEnabled(track, i) then
        active_fx = i
        break
    end
end

-- If no plugin is active within the range, activate the first one in the range
if active_fx == -1 then
    reaper.TrackFX_SetEnabled(track, min_fx, true)
else
    -- Deactivate the current plugin
    reaper.TrackFX_SetEnabled(track, active_fx, false)
    
    -- Calculate the next plugin within the range
    next_fx = active_fx + 1
    if next_fx > max_fx then
        next_fx = min_fx  -- Go back to the first plugin in the range if we reach the last one
    end
    
    -- Activate the next plugin
    reaper.TrackFX_SetEnabled(track, next_fx, true)
end

-- Refresh the FX window
reaper.TrackList_AdjustWindows(false)
