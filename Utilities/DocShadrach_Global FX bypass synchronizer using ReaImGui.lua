-- @description Global FX Bypass Synchronizer
-- @version 1.1
-- @author DocShadrach
-- @about
--   A ReaImGui tool to globally synchronize the bypass state of specific FX plugins by name.
--   Features:
--   - Real-time monitoring of FX states across the project.
--   - Reactive GUI: Buttons light up based on current state.
--   - Supports FX inside Containers (First level).
--   - Handles mixed states (some enabled, some disabled).
--   - Option for Case Sensitive search.
--   - Safety: Requires min. 3 characters to activate.

local r = reaper
local ctx -- Context for ReaImGui

-- Check if ReaImGui is installed
if not r.APIExists('ImGui_GetVersion') then
    r.ShowMessageBox("ReaImGui extension is required.", "Error", 0)
    return
end

-- GUI State & Config
local fx_name_input = "" -- Starts empty
local include_containers = true
local case_sensitive = false 

-- Monitoring State (Updated via timer)
local state = {
    total_found = 0,
    enabled_count = 0,
    disabled_count = 0,
    offline_count = 0,
    is_mixed = false,
    current_status = "Waiting for input...",
    status_color = 0x888888FF,
    last_scan_time = 0
}

local SCAN_INTERVAL = 0.2 -- Seconds between state checks (saves CPU)

-------------------------------------------------------------------------
-- HELPERS
-------------------------------------------------------------------------

local function nameMatches(sourceName, searchPattern, isSensitive)
    if isSensitive then
        return sourceName:find(searchPattern)
    else
        return sourceName:lower():find(searchPattern:lower(), 1, true)
    end
end

-------------------------------------------------------------------------
-- CORE: SCANNING & LOGIC
-------------------------------------------------------------------------

local function scanTrack(track, nameToFind, checkContainers, isSensitive)
    local found = 0
    local en = 0
    local dis = 0
    local off = 0
    
    local fxCount = r.TrackFX_GetCount(track)
    
    for fxIndex = 0, fxCount - 1 do
        local _, currentFxName = r.TrackFX_GetFXName(track, fxIndex, "")
        
        if nameMatches(currentFxName, nameToFind, isSensitive) then
            if r.TrackFX_GetOffline(track, fxIndex) then
                off = off + 1
            else
                found = found + 1
                if r.TrackFX_GetEnabled(track, fxIndex) then en = en + 1 else dis = dis + 1 end
            end
        end
        
        if checkContainers then
            local retval, containerCount = r.TrackFX_GetNamedConfigParm(track, fxIndex, "container_count")
            if retval and tonumber(containerCount) and tonumber(containerCount) > 0 then
                local numFXInContainer = tonumber(containerCount)
                for containerFXIndex = 0, numFXInContainer - 1 do
                    local globalIdx = 0x2000000 + (containerFXIndex + 1) * (fxCount + 1) + fxIndex + 1
                    local _, cName = r.TrackFX_GetFXName(track, globalIdx, "")
                    
                    if nameMatches(cName, nameToFind, isSensitive) then
                        if r.TrackFX_GetOffline(track, globalIdx) then
                            off = off + 1
                        else
                            found = found + 1
                            if r.TrackFX_GetEnabled(track, globalIdx) then en = en + 1 else dis = dis + 1 end
                        end
                    end
                end
            end
        end
    end
    return found, en, dis, off
end

local function updateState()
    if #fx_name_input < 3 then
        state.total_found = 0
        state.current_status = "Enter at least 3 characters..."
        state.status_color = 0x888888FF
        state.is_mixed = false
        return
    end

    local t_found, t_en, t_dis, t_off = 0, 0, 0, 0
    local trackCount = r.CountTracks(0)
    
    -- Check Master Track
    local f, e, d, o = scanTrack(r.GetMasterTrack(0), fx_name_input, include_containers, case_sensitive)
    t_found, t_en, t_dis, t_off = t_found+f, t_en+e, t_dis+d, t_off+o
    
    -- Check Regular Tracks
    for i = 0, trackCount - 1 do
        f, e, d, o = scanTrack(r.GetTrack(0, i), fx_name_input, include_containers, case_sensitive)
        t_found, t_en, t_dis, t_off = t_found+f, t_en+e, t_dis+d, t_off+o
    end
    
    state.total_found = t_found
    state.enabled_count = t_en
    state.disabled_count = t_dis
    state.offline_count = t_off
    
    if t_found == 0 then
        state.current_status = "No active FX found matching name."
        state.status_color = 0xEF5350FF
        state.is_mixed = false
    elseif t_en == t_found then
        state.current_status = "Status: ALL ENABLED (" .. t_found .. ")"
        state.status_color = 0x66BB6AFF
        state.is_mixed = false
    elseif t_dis == t_found then
        state.current_status = "Status: ALL DISABLED (" .. t_found .. ")"
        state.status_color = 0xEF5350FF
        state.is_mixed = false
    else
        state.current_status = "WARNING: MIXED STATES\n" .. t_en .. " Enabled / " .. t_dis .. " Disabled"
        state.status_color = 0xFFCA28FF
        state.is_mixed = true
    end
end

local function applyState(targetState)
    if #fx_name_input < 3 then return end

    r.Undo_BeginBlock()
    r.PreventUIRefresh(1)
    
    local trackCount = r.CountTracks(0)
    
    local function applyToTrack(track)
        local fxCount = r.TrackFX_GetCount(track)
        for i = 0, fxCount - 1 do
            local _, name = r.TrackFX_GetFXName(track, i, "")
            if nameMatches(name, fx_name_input, case_sensitive) and not r.TrackFX_GetOffline(track, i) then
                r.TrackFX_SetEnabled(track, i, targetState)
            end
            
            if include_containers then
                local retval, cCount = r.TrackFX_GetNamedConfigParm(track, i, "container_count")
                if retval and tonumber(cCount) and tonumber(cCount) > 0 then
                    for cIdx = 0, tonumber(cCount) - 1 do
                        local gIdx = 0x2000000 + (cIdx + 1) * (fxCount + 1) + i + 1
                        local _, cName = r.TrackFX_GetFXName(track, gIdx, "")
                        if nameMatches(cName, fx_name_input, case_sensitive) and not r.TrackFX_GetOffline(track, gIdx) then
                            r.TrackFX_SetEnabled(track, gIdx, targetState)
                        end
                    end
                end
            end
        end
    end
    
    applyToTrack(r.GetMasterTrack(0))
    for i = 0, trackCount - 1 do applyToTrack(r.GetTrack(0, i)) end
    
    r.TrackList_AdjustWindows(false)
    r.UpdateArrange()
    r.PreventUIRefresh(-1)
    
    local actionName = targetState and "Enable All " or "Disable All "
    r.Undo_EndBlock(actionName .. fx_name_input, -1)
    
    updateState()
end

-------------------------------------------------------------------------
-- REAIMGUI INTERFACE
-------------------------------------------------------------------------

local function loop()
    local now = r.time_precise()
    if now - state.last_scan_time > SCAN_INTERVAL then
        updateState()
        state.last_scan_time = now
    end

    local window_flags = r.ImGui_WindowFlags_NoCollapse()
    -- Increased width slightly to fit the longer text comfortably
    r.ImGui_SetNextWindowSize(ctx, 380, 260, r.ImGui_Cond_FirstUseEver()) 
    
    local visible, open = r.ImGui_Begin(ctx, 'Global FX Sync', true, window_flags)
    
    if visible then
        -- 1. Input Section
        r.ImGui_Text(ctx, "FX Name Search:")
        r.ImGui_SetNextItemWidth(ctx, -1)
        local changed, new_text = r.ImGui_InputText(ctx, '##fxname', fx_name_input)
        if changed then fx_name_input = new_text end
        
        -- Checkboxes
        local chk_changed, new_chk = r.ImGui_Checkbox(ctx, "Include First-Level Containers", include_containers)
        if chk_changed then include_containers = new_chk end
        
        r.ImGui_SameLine(ctx)
        
        local case_changed, new_case = r.ImGui_Checkbox(ctx, "Case Sensitive", case_sensitive)
        if case_changed then case_sensitive = new_case end
        
        r.ImGui_Separator(ctx)
        r.ImGui_Spacing(ctx)
        
        -- 2. Dynamic Status Text
        local win_w = r.ImGui_GetWindowSize(ctx)
        local text_w = r.ImGui_CalcTextSize(ctx, state.current_status)
        r.ImGui_SetCursorPosX(ctx, (win_w - text_w) * 0.5)
        r.ImGui_TextColored(ctx, state.status_color, state.current_status)
        
        if state.is_mixed then
             local subtext = "(Select action to synchronize)"
             local sub_w = r.ImGui_CalcTextSize(ctx, subtext)
             r.ImGui_SetCursorPosX(ctx, (win_w - sub_w) * 0.5)
             r.ImGui_TextColored(ctx, 0xAAAAAAFF, subtext)
        end
        
        r.ImGui_Spacing(ctx)
        
        -- 3. Reactive Buttons
        local avail_w, avail_h = r.ImGui_GetContentRegionAvail(ctx)
        local btn_w = (avail_w - 10) / 2
        local btn_h = 45 
        
        local col_green = 0x2E7D32FF
        local col_red   = 0xC62828FF
        local col_dim   = 0x424242FF 
        
        local on_btn_col = col_green
        local off_btn_col = col_red
        
        local input_valid = (#fx_name_input >= 3)
        
        if input_valid and state.total_found > 0 then
            if state.enabled_count == state.total_found then
                on_btn_col = 0x4CAF50FF -- Bright Green
                off_btn_col = col_dim
            elseif state.disabled_count == state.total_found then
                on_btn_col = col_dim
                off_btn_col = 0xF44336FF -- Bright Red
            else
                on_btn_col = 0x1B5E20FF -- Darker Green
                off_btn_col = 0xB71C1CFF -- Darker Red
            end
        else
            on_btn_col = col_dim
            off_btn_col = col_dim
        end

        if not input_valid then r.ImGui_BeginDisabled(ctx) end
        
        r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Button(), on_btn_col)
        r.ImGui_PushStyleColor(ctx, r.ImGui_Col_ButtonHovered(), 0x66BB6AFF)
        r.ImGui_PushStyleColor(ctx, r.ImGui_Col_ButtonActive(), 0x1B5E20FF)
        if r.ImGui_Button(ctx, "ENABLE ALL", btn_w, btn_h) then
            if state.total_found > 0 then applyState(true) end
        end
        r.ImGui_PopStyleColor(ctx, 3)

        r.ImGui_SameLine(ctx)

        r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Button(), off_btn_col)
        r.ImGui_PushStyleColor(ctx, r.ImGui_Col_ButtonHovered(), 0xEF5350FF)
        r.ImGui_PushStyleColor(ctx, r.ImGui_Col_ButtonActive(), 0xB71C1CFF)
        if r.ImGui_Button(ctx, "DISABLE ALL", btn_w, btn_h) then
            if state.total_found > 0 then applyState(false) end
        end
        r.ImGui_PopStyleColor(ctx, 3)
        
        if not input_valid then r.ImGui_EndDisabled(ctx) end
        
        r.ImGui_End(ctx)
    end
    
    if open then
        r.defer(loop)
    end
end

ctx = r.ImGui_CreateContext('FX_Synchronizer')
r.defer(loop)
