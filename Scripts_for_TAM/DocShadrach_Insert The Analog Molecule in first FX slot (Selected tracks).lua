reaper.Undo_BeginBlock()
reaper.PreventUIRefresh(1)

-- FX name to insert
local FX_NAME = "The Analog Molecule"

local sel_count = reaper.CountSelectedTracks(0)

if sel_count == 0 then
  -- No selected tracks
  reaper.ShowMessageBox("No tracks selected.", "Warning", 0)
else
  for i = 0, sel_count - 1 do
    local track = reaper.GetSelectedTrack(0, i)

    -- Insert the plugin (REAPER inserts it at the end by default)
    local fx_index = reaper.TrackFX_AddByName(track, FX_NAME, false, 1)

    -- If successfully inserted, move it to the first FX slot (index 0)
    if fx_index >= 0 then
      if fx_index ~= 0 then
        reaper.TrackFX_CopyToTrack(track, fx_index, track, 0, true)
      end
    end
  end
end

reaper.PreventUIRefresh(-1)
reaper.Undo_EndBlock("Insert The Analog Molecule in first FX slot (Selected tracks)", -1)
reaper.UpdateArrange()
