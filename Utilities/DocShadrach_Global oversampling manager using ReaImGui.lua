-- @description Global Oversampling Manager
-- @version 1.0
-- @author DocShadrach
-- @about
--   Toggles oversampling project-wide for specific plugins.
--   Only detects and processes plugins that are currently ACTIVE and ONLINE.
--   Supports infinite nesting depth.
--   Features per-plugin bypass checkboxes and project-persistent state.

local r = reaper
local ctx

-------------------------------------------------------------------------
-- CONSTANTS & PERSISTENCE KEYS
-------------------------------------------------------------------------
local EXT_SECTION = "OVERSAMPLE_MGR"
local EXT_KEY_LIST = "PLUGIN_LIST_V2" 
local EXT_KEY_STATE = "GLOBAL_STATE"
local EXT_KEY_SHIFT = "TARGET_SHIFT"
local EXT_KEY_ORIG = "ORIGINAL_VALUES"

local COL_GREEN = 0x2E7D32FF
local COL_RED   = 0xC62828FF
local COL_AMBER = 0xFF8F00FF

local plugin_patterns = {} 
local global_on = false
local target_shift = 1 
local last_scan_time = 0

-------------------------------------------------------------------------
-- RECURSIVE ENGINE (DIFF LOGIC)
-------------------------------------------------------------------------

---Recursive function to scan FX using the "Diff" scaling method
local function ScanContainers(track, container_id, parent_fx_count, previous_diff, callback)
    local diff = (parent_fx_count + 1) * previous_diff
    local ok, c_fx_count = r.TrackFX_GetNamedConfigParm(track, 0x2000000 + container_id, "container_count")
    if not ok then return end
    
    local count = tonumber(c_fx_count) or 0
    for i = 1, count do
        local fx_id = container_id + (diff * i)
        local full_addr = 0x2000000 + fx_id
        local guid = r.TrackFX_GetFXGUID(track, full_addr)
        if guid then
            -- CHECK STATUS: Skip if Bypassed or Offline
            local is_enabled = r.TrackFX_GetEnabled(track, full_addr)
            local is_offline = r.TrackFX_GetOffline(track, full_addr)
            
            if is_enabled and not is_offline then
                callback(track, full_addr, guid)
            end
            
            local ok_type, fx_type = r.TrackFX_GetNamedConfigParm(track, full_addr, "fx_type")
            if ok_type and fx_type == "Container" then
                ScanContainers(track, fx_id, count, diff, callback)
            end
        end
    end
end

---Iterates through all tracks and scans Root + Recursive Containers
local function ForEachFX(callback)
    local tracks = { r.GetMasterTrack(0) }
    for i = 0, r.CountTracks(0) - 1 do tracks[#tracks+1] = r.GetTrack(0, i) end

    for _, tr in ipairs(tracks) do
        local root_count = r.TrackFX_GetCount(tr)
        for i = 1, root_count do
            local addr = i - 1
            local guid = r.TrackFX_GetFXGUID(tr, addr)
            if guid then
                -- CHECK STATUS: Skip if Bypassed or Offline
                local is_enabled = r.TrackFX_GetEnabled(tr, addr)
                local is_offline = r.TrackFX_GetOffline(tr, addr)
                
                if is_enabled and not is_offline then
                    callback(tr, addr, guid)
                end
                
                local ok_type, fx_type = r.TrackFX_GetNamedConfigParm(tr, addr, "fx_type")
                if ok_type and fx_type == "Container" then
                    ScanContainers(tr, i, root_count, 1, callback)
                end
            end
        end
    end
end

-------------------------------------------------------------------------
-- LOGIC & FILTERING
-------------------------------------------------------------------------

---Checks if a name matches any pattern AND if that pattern is enabled in UI
local function GetMatchStatus(name)
    if not name or name == "" then return false, false end
    local n = name:lower()
    for _, p in ipairs(plugin_patterns) do
        if p.pattern ~= "" and n:find(p.pattern:lower(), 1, true) then
            return true, p.enabled
        end
    end
    return false, false
end

local function UpdateStats()
    for _, p in ipairs(plugin_patterns) do p.count = 0 end
    ForEachFX(function(tr, addr)
        local _, name = r.TrackFX_GetFXName(tr, addr, "")
        local n_low = name:lower()
        for _, p in ipairs(plugin_patterns) do
            -- Pattern must be non-empty to count
            if p.pattern ~= "" and n_low:find(p.pattern:lower(), 1, true) then
                p.count = p.count + 1
            end
        end
    end)
end

-------------------------------------------------------------------------
-- CORE ACTIONS
-------------------------------------------------------------------------

local function ApplyOversampling()
    r.Undo_BeginBlock()
    r.PreventUIRefresh(1)
    local original_values = {}
    
    ForEachFX(function(tr, addr, guid)
        local _, name = r.TrackFX_GetFXName(tr, addr, "")
        local is_match, is_enabled_in_list = GetMatchStatus(name)
        
        if is_match and is_enabled_in_list then
            local ok, val = r.TrackFX_GetNamedConfigParm(tr, addr, "instance_oversample_shift")
            if ok then
                original_values[#original_values+1] = guid .. "=" .. (tonumber(val) or 0)
                r.TrackFX_SetNamedConfigParm(tr, addr, "instance_oversample_shift", tostring(target_shift))
            end
        end
    end)
    
    r.SetProjExtState(0, EXT_SECTION, EXT_KEY_ORIG, table.concat(original_values, "|"))
    global_on = true
    r.SetProjExtState(0, EXT_SECTION, EXT_KEY_STATE, "1")
    r.PreventUIRefresh(-1)
    r.Undo_EndBlock("Enable Project Oversampling", -1)
end

local function RestoreOversampling()
    r.Undo_BeginBlock()
    r.PreventUIRefresh(1)
    local _, data = r.GetProjExtState(0, EXT_SECTION, EXT_KEY_ORIG)
    local restore_map = {}
    for entry in data:gmatch("[^|]+") do
        local g, v = entry:match("(%b{})=(%d+)")
        if g then restore_map[g] = v end
    end
    
    ForEachFX(function(tr, addr, guid)
        if restore_map[guid] then
            r.TrackFX_SetNamedConfigParm(tr, addr, "instance_oversample_shift", restore_map[guid])
        else
            local _, name = r.TrackFX_GetFXName(tr, addr, "")
            local is_match, is_enabled_in_list = GetMatchStatus(name)
            if is_match and is_enabled_in_list then
                r.TrackFX_SetNamedConfigParm(tr, addr, "instance_oversample_shift", "0")
            end
        end
    end)
    
    r.SetProjExtState(0, EXT_SECTION, EXT_KEY_ORIG, "")
    global_on = false
    r.SetProjExtState(0, EXT_SECTION, EXT_KEY_STATE, "0")
    r.PreventUIRefresh(-1)
    r.Undo_EndBlock("Restore Oversampling State", -1)
end

-------------------------------------------------------------------------
-- UI & PERSISTENCE
-------------------------------------------------------------------------

local function SaveData()
    local t = {}
    for _, p in ipairs(plugin_patterns) do 
        table.insert(t, p.pattern .. ":" .. (p.enabled and "1" or "0")) 
    end
    r.SetProjExtState(0, EXT_SECTION, EXT_KEY_LIST, table.concat(t, "|"))
    r.MarkProjectDirty(0)
end

local function LoadData()
    local _, list = r.GetProjExtState(0, EXT_SECTION, EXT_KEY_LIST)
    plugin_patterns = {}
    if list ~= "" then
        for entry in list:gmatch("[^|]+") do
            local pat, en = entry:match("^(.*):(%d)$")
            if pat then
                table.insert(plugin_patterns, {pattern = pat, enabled = (en == "1"), count = 0})
            end
        end
    end
    local _, st = r.GetProjExtState(0, EXT_SECTION, EXT_KEY_STATE)
    global_on = (st == "1")
    local _, sh = r.GetProjExtState(0, EXT_SECTION, EXT_KEY_SHIFT)
    target_shift = tonumber(sh) or 1
end

local function loop()
    local now = r.time_precise()
    if now - last_scan_time > 0.5 then
        UpdateStats()
        last_scan_time = now
    end

    r.ImGui_SetNextWindowSize(ctx, 480, 400, r.ImGui_Cond_FirstUseEver())
    local visible, open = r.ImGui_Begin(ctx, 'Global Oversampling Manager', true)
    
    if visible then
        local btn_label = global_on and "RESTORE PROJECT ORIGINALS" or "ACTIVATE OVERSAMPLING"
        r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Button(), global_on and COL_RED or COL_GREEN)
        if r.ImGui_Button(ctx, btn_label, -1, 55) then
            if global_on then RestoreOversampling() else ApplyOversampling() end
        end
        r.ImGui_PopStyleColor(ctx, 1)
        r.ImGui_Spacing(ctx)
        
        r.ImGui_AlignTextToFramePadding(ctx)
        r.ImGui_Text(ctx, "Target Rate:")
        r.ImGui_SameLine(ctx)
        r.ImGui_SetNextItemWidth(ctx, 100)
        local ok, new_val = r.ImGui_Combo(ctx, "##lvl", target_shift - 1, "2x\0 4x\0 8x\0")
        if ok then 
            target_shift = new_val + 1 
            r.SetProjExtState(0, EXT_SECTION, EXT_KEY_SHIFT, tostring(target_shift))
        end
        
        r.ImGui_Separator(ctx)
        r.ImGui_TextColored(ctx, 0x999999FF, "Active Plugins Filter (Bypassed/Offline ignored):")
        
        if r.ImGui_BeginTable(ctx, 'p_table', 4, r.ImGui_TableFlags_Borders() | r.ImGui_TableFlags_RowBg()) then
            r.ImGui_TableSetupColumn(ctx, '##en', r.ImGui_TableColumnFlags_WidthFixed(), 25)
            r.ImGui_TableSetupColumn(ctx, 'Pattern', r.ImGui_TableColumnFlags_WidthStretch())
            r.ImGui_TableSetupColumn(ctx, 'Active', r.ImGui_TableColumnFlags_WidthFixed(), 45)
            r.ImGui_TableSetupColumn(ctx, '##del', r.ImGui_TableColumnFlags_WidthFixed(), 30)
            r.ImGui_TableHeadersRow(ctx)
            
            local to_remove = nil
            for i, p in ipairs(plugin_patterns) do
                r.ImGui_PushID(ctx, i)
                r.ImGui_TableNextRow(ctx)
                
                -- Column 1: Enable Checkbox
                r.ImGui_TableSetColumnIndex(ctx, 0)
                local c_ok, c_new = r.ImGui_Checkbox(ctx, "##chk", p.enabled)
                if c_ok then p.enabled = c_new; SaveData() end
                
                -- Column 2: Pattern Text
                r.ImGui_TableSetColumnIndex(ctx, 1)
                if not p.enabled then r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Text(), 0x888888FF) end
                r.ImGui_SetNextItemWidth(ctx, -1)
                local ch, new_p = r.ImGui_InputText(ctx, "##in", p.pattern)
                if not p.enabled then r.ImGui_PopStyleColor(ctx, 1) end
                if ch then p.pattern = new_p; SaveData() end
                
                -- Column 3: Active Count
                r.ImGui_TableSetColumnIndex(ctx, 2)
                local col = (p.count > 0 and p.enabled) and 0x55FF55FF or 0xAAAAAAFF
                r.ImGui_TextColored(ctx, col, tostring(p.count))
                if r.ImGui_IsItemHovered(ctx) then
                    r.ImGui_SetTooltip(ctx, "Online & Enabled instances found in project.")
                end
                
                -- Column 4: Delete
                r.ImGui_TableSetColumnIndex(ctx, 3)
                if r.ImGui_Button(ctx, "X", -1) then to_remove = i end
                
                r.ImGui_PopID(ctx)
            end
            if to_remove then table.remove(plugin_patterns, to_remove); SaveData() end
            r.ImGui_EndTable(ctx)
        end
        
        r.ImGui_Spacing(ctx)
        if r.ImGui_Button(ctx, "+ Add Filter", -1, 30) then
            table.insert(plugin_patterns, {pattern = "Plugin Name", enabled = true, count = 0})
            SaveData()
        end
        r.ImGui_End(ctx)
    end
    if open then r.defer(loop) end
end

-------------------------------------------------------------------------
-- START
-------------------------------------------------------------------------
ctx = r.ImGui_CreateContext('OversamplingMgr')
LoadData()
r.defer(loop)
