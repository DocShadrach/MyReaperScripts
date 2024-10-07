-- Define the name of the track you want to find
track_name_to_find = "Track Name"  -- CHANGE to the name of the track you're looking for

-- Define the index of the container you want to use (1 for the first container, 2 for the second, etc.)
container_number = 1  -- CHANGE to the desired container number

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

-- Search for the container according to the specified number
container_index = -1
container_count = 0

for i = 0, reaper.TrackFX_GetCount(track) - 1 do
    local retval, is_container = reaper.TrackFX_GetNamedConfigParm(track, i, "container_count")
    
    -- Check if the current plugin is a container
    if retval and tonumber(is_container) and tonumber(is_container) > 0 then
        container_count = container_count + 1
        if container_count == container_number then  -- If it's the desired container
            container_index = i
            break
        end
    end
end

-- If the container is not found, display an error message
if container_index == -1 then
    reaper.ShowMessageBox("Container number " .. container_number .. " not found in the track", "Error", 0)
    return
end

-- Activate the container (it should always be active)
reaper.TrackFX_SetEnabled(track, container_index, true)

-- Define the range of plugins you want to affect (plugin indices within the container, starting from 0)
min_fx = 1  -- Second plugin inside the container (index 1)
max_fx = 4  -- Fifth plugin inside the container (index 4)

-- Get the number of FX inside the container
local retval, container_fx_count = reaper.TrackFX_GetNamedConfigParm(track, container_index, "container_count")
num_fx_in_container = tonumber(container_fx_count)

-- If unable to retrieve the number of FX in the container, display an error message
if not num_fx_in_container or num_fx_in_container == 0 then
    reaper.ShowMessageBox("Could not get the number of FX in container number " .. container_number, "Error", 0)
    return
end

-- Find which FX within the range is active
active_fx = -1
for j = min_fx, max_fx do
    local fx_index = 0x2000000 + (j + 1) * (reaper.TrackFX_GetCount(track) + 1) + container_index + 1  -- Calculate the FX index inside the container
    if reaper.TrackFX_GetEnabled(track, fx_index) then
        active_fx = j
        break
    end
end

-- If no FX is active within the range, activate the first one in the range
if active_fx == -1 then
    local fx_index = 0x2000000 + (min_fx + 1) * (reaper.TrackFX_GetCount(track) + 1) + container_index + 1  -- First FX in the range
    reaper.TrackFX_SetEnabled(track, fx_index, true)
else
    -- Deactivate the current FX
    local fx_index = 0x2000000 + (active_fx + 1) * (reaper.TrackFX_GetCount(track) + 1) + container_index + 1
    reaper.TrackFX_SetEnabled(track, fx_index, false)
    
    -- Calculate the next FX within the range
    local next_fx = active_fx + 1
    if next_fx > max_fx then
        next_fx = min_fx  -- Return to the first in the range if we reach the last one
    end
    
    -- Activate the next FX in the range
    local next_fx_index = 0x2000000 + (next_fx + 1) * (reaper.TrackFX_GetCount(track) + 1) + container_index + 1
    reaper.TrackFX_SetEnabled(track, next_fx_index, true)
end

-- Refresh the FX window
reaper.TrackList_AdjustWindows(false)
