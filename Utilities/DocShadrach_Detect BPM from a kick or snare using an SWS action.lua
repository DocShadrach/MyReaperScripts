-- Detect BPM from kick track using Xenakios Split at Transients
-- Safe version: avoids nested undo blocks, reverts split cleanly, preserves project state

function detect_bpm_with_xenakios()
    -- Save current project state
    local transport_pos = reaper.GetCursorPosition()
    local view_start, view_end = reaper.BR_GetArrangeView(0)

    local original_selection = {}
    local original_count = reaper.CountSelectedMediaItems(0)
    for i = 0, original_count - 1 do
        local sel_item = reaper.GetSelectedMediaItem(0, i)
        if sel_item then table.insert(original_selection, sel_item) end
    end

    local item = reaper.GetSelectedMediaItem(0, 0)
    if not item then
        reaper.MB("Select an audio item with kick drum.", "Error", 0)
        return
    end

    local item_pos = reaper.GetMediaItemInfo_Value(item, "D_POSITION")
    local item_len = reaper.GetMediaItemInfo_Value(item, "D_LENGTH")
    local track = reaper.GetMediaItemTrack(item)
    if not track then
        reaper.MB("Could not find track for selected item.", "Error", 0)
        return
    end

    reaper.PreventUIRefresh(1)

    -- Execute Xenakios split
    local split_cmd = reaper.NamedCommandLookup("_XENAKIOS_SPLIT_ITEMSATRANSIENTS")
    reaper.Main_OnCommand(split_cmd, 0)

    -- Get transient positions
    local positions = {}
    local item_count = reaper.CountTrackMediaItems(track)
    for i = 0, item_count - 1 do
        local it = reaper.GetTrackMediaItem(track, i)
        local pos = reaper.GetMediaItemInfo_Value(it, "D_POSITION")
        if pos >= item_pos and pos <= item_pos + item_len then
            table.insert(positions, pos)
        end
    end

    if #positions < 3 then
        reaper.Undo_DoUndo2(0) -- revert split
        reaper.PreventUIRefresh(-1)
        reaper.MB("Not enough transients detected.", "Error", 0)
        return
    end

    table.sort(positions)

    -- Calculate intervals between transients
    local intervals = {}
    for i = 2, #positions do
        local diff = positions[i] - positions[i - 1]
        if diff > 0.1 and diff < 2.0 then
            table.insert(intervals, diff)
        end
    end

    if #intervals < 2 then
        reaper.Undo_DoUndo2(0)
        reaper.PreventUIRefresh(-1)
        reaper.MB("Insufficient or invalid intervals.", "Error", 0)
        return
    end

    -- Helper functions
    local function mean(t)
        local s = 0 for _,v in ipairs(t) do s = s + v end
        return s / #t
    end

    local function std(t, m)
        local s = 0 for _,v in ipairs(t) do s = s + (v - m)^2 end
        return math.sqrt(s / #t)
    end

    -- Adaptive filtering
    local avg = mean(intervals)
    local deviation = std(intervals, avg)
    local clean = {}
    for _, v in ipairs(intervals) do
        if math.abs(v - avg) <= deviation * 1.2 then
            table.insert(clean, v)
        end
    end
    if #clean < 2 then clean = intervals end

    -- Group similar intervals
    table.sort(clean)
    local groups = {{sum = clean[1], count = 1, mean = clean[1]}}
    for i = 2, #clean do
        local diff = math.abs(clean[i] - groups[#groups].mean)
        if diff < 0.015 then
            local g = groups[#groups]
            g.sum = g.sum + clean[i]
            g.count = g.count + 1
            g.mean = g.sum / g.count
        else
            table.insert(groups, {sum = clean[i], count = 1, mean = clean[i]})
        end
    end

    table.sort(groups, function(a,b) return a.count > b.count end)
    local beat_interval = groups[1].mean
    local bpm = 60 / beat_interval

    -- Adaptive musical correction
    local function best_bpm(base)
        local candidates = {base/2, base, base*2}
        local valid = {}
        for _, b in ipairs(candidates) do
            if b >= 60 and b <= 180 then table.insert(valid, b) end
        end
        if #valid == 0 then valid = {base} end

        local function weight(b)
            if b >= 80 and b <= 140 then return 1.5
            elseif b >= 60 and b <= 180 then return 1.0
            else return 0.6 end
        end

        local best, best_w = valid[1], 0
        for _, b in ipairs(valid) do
            local w = weight(b)
            if w > best_w then best, best_w = b, w end
        end
        return best
    end

    bpm = best_bpm(bpm)

    -- Duration-based correction
    if (item_len / 60 > 3 and bpm > 140) then bpm = bpm / 2 end
    if bpm > 180 then bpm = bpm / 2 end
    if bpm < 60 then bpm = bpm * 2 end

    -- Smart musical rounding
    local function smart_round_bpm(b)
        local dec = b - math.floor(b)
        if dec >= 0.4 and dec <= 0.6 then
            return math.floor(b) + 0.5
        else
            return math.floor(b + 0.5)
        end
    end

    local original_bpm = bpm
    bpm = smart_round_bpm(bpm)

    -- Revert Xenakios split (restore everything as it was)
    reaper.Undo_DoUndo2(0)

    -- Restore original view and selection
    reaper.SetEditCurPos(transport_pos, false, false)
    reaper.SelectAllMediaItems(0, false)
    for _, it in ipairs(original_selection) do
        if reaper.ValidatePtr(it, "MediaItem*") then
            reaper.SetMediaItemSelected(it, true)
        end
    end
    if view_start and view_end then
        reaper.BR_SetArrangeView(0, view_start, view_end)
    end

    reaper.PreventUIRefresh(-1)
    reaper.UpdateArrange()

    -- Show result
    local bpm_display = (bpm == math.floor(bpm))
        and string.format("%d", bpm)
        or string.format("%.1f", bpm)

    local msg = string.format("Detected BPM: %s\nTransients detected: %d", bpm_display, #positions)
    local choice = reaper.MB(msg .. "\n\nApply this BPM to the project?", "BPM Detection", 4)

    if choice == 6 then
        reaper.Main_OnCommand(reaper.NamedCommandLookup("_SWS_AWTBASETIME"), 0)
        reaper.SetCurrentBPM(0, bpm, false)
    end
end

-- Execute function directly
detect_bpm_with_xenakios()

