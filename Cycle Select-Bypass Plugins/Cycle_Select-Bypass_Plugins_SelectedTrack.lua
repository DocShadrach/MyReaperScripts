-- Get the selected track (project index = 0, track index = 0 for the first selected one)
track = reaper.GetSelectedTrack(0, 0)

-- If no track is selected, exit the script
if track == nil then
    reaper.ShowMessageBox("No track is selected", "Error", 0)
    return
end

-- Number of plugins in the track
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
    -- Deactivate the current one
    reaper.TrackFX_SetEnabled(track, active_fx, false)
    
    -- Calculate the next plugin to activate
    next_fx = (active_fx + 1) % num_fx
    
    -- Activate the next plugin
    reaper.TrackFX_SetEnabled(track, next_fx, true)
end

-- Refresh the FX window
reaper.TrackList_AdjustWindows(false)
