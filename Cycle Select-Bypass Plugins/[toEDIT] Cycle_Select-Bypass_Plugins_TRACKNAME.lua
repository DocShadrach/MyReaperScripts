-- Define the name of the track you want to find
track_name_to_find = "Track Name"  -- CHANGE this to the actual track name

-- Get the number of tracks in the project
num_tracks = reaper.CountTracks(0)

-- Search for the track with the specific name
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

-- Get the number of plugins in the track
num_fx = reaper.TrackFX_GetCount(track)

-- Find which plugin is currently active
active_fx = -1
for i = 0, num_fx - 1 do
    if reaper.TrackFX_GetEnabled(track, i) then
        active_fx = i
        break
    end
end

-- If no plugin is active, activate the first one
if active_fx == -1 then
    reaper.TrackFX_SetEnabled(track, 0, true)
else
    -- Deactivate the current plugin
    reaper.TrackFX_SetEnabled(track, active_fx, false)
    
    -- Calculate the next plugin to activate
    next_fx = (active_fx + 1) % num_fx
    
    -- Activate the next plugin
    reaper.TrackFX_SetEnabled(track, next_fx, true)
end

-- Refresh the FX window
reaper.TrackList_AdjustWindows(false)
