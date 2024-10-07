-- Define the range of plugins you want to affect (plugin indices, starting from 0)
min_fx = 1  -- The second plugin (index in Lua starts from 0, so 1 = second plugin)
max_fx = 4  -- The fifth plugin

-- Get the selected track
track = reaper.GetSelectedTrack(0, 0)

-- If no track is selected, exit the script
if track == nil then
    reaper.ShowMessageBox("No track is selected", "Error", 0)
    return
end

-- Find which plugin in the range is currently active
active_fx = -1
for i = min_fx, max_fx do
    if reaper.TrackFX_GetEnabled(track, i) then
        active_fx = i
        break
    end
end

-- If no plugin is active in the range, activate the first one in the range
if active_fx == -1 then
    reaper.TrackFX_SetEnabled(track, min_fx, true)
else
    -- Deactivate the current plugin
    reaper.TrackFX_SetEnabled(track, active_fx, false)
    
    -- Calculate the next plugin in the range
    next_fx = active_fx + 1
    if next_fx > max_fx then
        next_fx = min_fx  -- Return to the first plugin in the range if we reach the last one
    end
    
    -- Activate the next plugin
    reaper.TrackFX_SetEnabled(track, next_fx, true)
end

-- Refresh the FX window
reaper.TrackList_AdjustWindows(false)
