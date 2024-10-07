-- Define the range of plugins you want to affect (plugin indices start from 0)
min_fx = 1  -- The second plugin (since Lua indices start at 0, 1 = second plugin)
max_fx = 4  -- The fifth plugin

-- Get the currently focused track and plugin
retval, track_index, item_index, focused_fx = reaper.GetFocusedFX()

-- If no FX is focused, exit the script
if retval == 0 or focused_fx == 0 then
    reaper.ShowMessageBox("No FX chain is currently focused", "Error", 0)
    return
end

-- Get the track with focus
track = reaper.GetTrack(0, track_index - 1)  -- Track indices in REAPER start at 1, so we subtract 1

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
