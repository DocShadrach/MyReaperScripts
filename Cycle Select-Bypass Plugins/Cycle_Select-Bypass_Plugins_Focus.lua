-- Get the track and the plugin that currently has focus
retval, track_index, item_index, focused_fx = reaper.GetFocusedFX()

-- If no FX has focus, exit the script
if retval == 0 or focused_fx == 0 then
    reaper.ShowMessageBox("No FX chain is focused", "Error", 0)
    return
end

-- Get the track that has focus
track = reaper.GetTrack(0, track_index - 1)  -- Track indices in REAPER start at 1, so we subtract 1

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
