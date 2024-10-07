-- Define the name of the track you want to find
local track_name_to_find = "Track Name"  -- CHANGE to the name of the track you're looking for

-- Set this number to search for the nth container
local container_to_find = 1  -- For example, 1 for the first container, 2 for the second, etc.

-- Get the number of tracks in the project
local num_tracks = reaper.CountTracks(0)

-- Search for the track with the specific name
local track = nil
for i = 0, num_tracks - 1 do
    local track_current = reaper.GetTrack(0, i)
    local _, current_track_name = reaper.GetSetMediaTrackInfo_String(track_current, "P_NAME", "", false)
    
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

-- Search for the nth container in the track
local container_index = -1
local container_count = 0

for i = 0, reaper.TrackFX_GetCount(track) - 1 do
    local retval, is_container = reaper.TrackFX_GetNamedConfigParm(track, i, "container_count")
    
    -- Check if the current plugin is a container
    if retval and tonumber(is_container) and tonumber(is_container) > 0 then
        container_count = container_count + 1
        if container_count == container_to_find then  -- If it's the desired container
            container_index = i
            break
        end
    end
end

-- If the container is not found, show an error message
if container_index == -1 then
    reaper.ShowMessageBox("Container number " .. container_to_find .. " not found in the track", "Error", 0)
    return
end

-- Activate the container (it must always be enabled)
reaper.TrackFX_SetEnabled(track, container_index, true)

-- Get the number of FX inside the container
local retval, container_fx_count = reaper.TrackFX_GetNamedConfigParm(track, container_index, "container_count")
local num_fx_in_container = tonumber(container_fx_count)

-- If the number of FX in the container cannot be obtained, show an error message
if not num_fx_in_container or num_fx_in_container == 0 then
    reaper.ShowMessageBox("Could not retrieve the number of FX in container number " .. container_to_find, "Error", 0)
    return
end

-- Find which FX inside the container is currently active
local active_fx = -1
for j = 0, num_fx_in_container - 1 do
    local fx_index = 0x2000000 + (j + 1) * (reaper.TrackFX_GetCount(track) + 1) + container_index + 1  -- Calculate the FX index inside the container
    if reaper.TrackFX_GetEnabled(track, fx_index) then
        active_fx = j
        break
    end
end

-- If no FX is active inside the container, activate the first one
if active_fx == -1 then
    local fx_index = 0x2000000 + (0 + 1) * (reaper.TrackFX_GetCount(track) + 1) + container_index + 1  -- First FX in the container
    reaper.TrackFX_SetEnabled(track, fx_index, true)
else
    -- Deactivate the current FX
    local fx_index = 0x2000000 + (active_fx + 1) * (reaper.TrackFX_GetCount(track) + 1) + container_index + 1
    reaper.TrackFX_SetEnabled(track, fx_index, false)
    
    -- Calculate the next FX in the container
    local next_fx = (active_fx + 1) % num_fx_in_container
    
    -- Activate the next FX in the container
    local next_fx_index = 0x2000000 + (next_fx + 1) * (reaper.TrackFX_GetCount(track) + 1) + container_index + 1
    reaper.TrackFX_SetEnabled(track, next_fx_index, true)
end

-- Refresh the FX window
reaper.TrackList_AdjustWindows(false)
