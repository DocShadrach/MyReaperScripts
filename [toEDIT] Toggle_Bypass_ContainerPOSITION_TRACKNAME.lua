-- Replace with the name of the track you want to find
local trackNameToFind = "Track Name"

-- Change this number to search for the n-th container
local containerToFind = 3  -- For example, 3 for the third container

-- Get the total number of tracks
local trackCount = reaper.CountTracks(0)

-- Variable to store the found track
local trackFound = nil

-- Search for the track by its name
for i = 0, trackCount - 1 do
    local track = reaper.GetTrack(0, i)
    local _, trackName = reaper.GetTrackName(track, "")
    if trackName == trackNameToFind then
        trackFound = track
        break
    end
end

-- Check if the track was found
if not trackFound then
    reaper.ShowMessageBox("Track with the specified name not found.", "Error", 0)
    return
end

-- Get the total number of FX on the found track
local fxCount = reaper.TrackFX_GetCount(trackFound)

-- Variable to count the found containers
local containerCount = 0

-- Variable to store the index of the n-th container
local containerIndex = -1

-- Search for the container corresponding to the value of containerToFind
for i = 0, fxCount - 1 do
    local _, fxName = reaper.TrackFX_GetFXName(trackFound, i, "")
    if fxName:find("Container") then  -- If the FX name contains "Container"
        containerCount = containerCount + 1
        if containerCount == containerToFind then  -- Found the n-th container
            containerIndex = i
            break
        end
    end
end

-- Check if the container was found
if containerIndex == -1 then
    reaper.ShowMessageBox("Container number " .. containerToFind .. " not found in the track.", "Error", 0)
    return
end

-- Toggle the bypass of the container
local currentBypassState = reaper.TrackFX_GetEnabled(trackFound, containerIndex)
reaper.TrackFX_SetEnabled(trackFound, containerIndex, not currentBypassState)
