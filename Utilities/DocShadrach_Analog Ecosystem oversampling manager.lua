-- @description DocShadrach's Analog Ecosystem Oversampling Manager
-- @version 1.0
-- @author DocShadrach
-- @about
--   Dedicated oversampling manager for "The Analog Molecule" and "The Hot Summer".
--   Features independent rate selection, current status detection, and global toggle/restore.

local r = reaper
local ctx

-------------------------------------------------------------------------
-- CONSTANTS & CONFIGURATION
-------------------------------------------------------------------------
local EXT_SECTION = "OVERSAMPLE_MGR_ANALOG"
local EXT_KEY_STATE = "GLOBAL_STATE"
local EXT_KEY_ORIG = "ORIGINAL_VALUES"
local EXT_KEY_CONFIG = "PLUGIN_CONFIGS"

-- Fixed targets definition
-- shift: User target (0=Off/- , 1=2x, 2=4x, 3=8x)
-- current_detect: Actual state read from plugin (-1 = not found)
local targets = {
    { name = "The Analog Molecule", label = "The Analog Molecule", shift = 0, count = 0, current_detect = -1 },
    { name = "The Hot Summer",      label = "The Hot Summer",      shift = 0, count = 0, current_detect = -1 }
}

local global_on = false
local last_scan_time = 0
local initial_sync_done = false -- To sync UI with reality only once on load

-- UI Colors
local COL_GREEN = 0x2E7D32FF
local COL_RED   = 0xC62828FF
local COL_TEXT_DIM = 0x999999FF
local COL_HIGHLIGHT = 0x4FC3F7FF

-------------------------------------------------------------------------
-- HELPER FUNCTIONS
-------------------------------------------------------------------------

---Converts shift integer to string label
local function GetShiftLabel(val)
    if val == 0 then return "-" end
    if val == 1 then return "2x" end
    if val == 2 then return "4x" end
    if val == 3 then return "8x" end
    return "?"
end

-------------------------------------------------------------------------
-- FX SCANNING ENGINE (Recursive)
-------------------------------------------------------------------------

---Recursively scans FX Containers
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

---Iterates through all tracks (Root + Recursive Containers)
local function ForEachFX(callback)
    local tracks = { r.GetMasterTrack(0) }
    for i = 0, r.CountTracks(0) - 1 do tracks[#tracks+1] = r.GetTrack(0, i) end

    for _, tr in ipairs(tracks) do
        local root_count = r.TrackFX_GetCount(tr)
        for i = 1, root_count do
            local addr = i - 1
            local guid = r.TrackFX_GetFXGUID(tr, addr)
            if guid then
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
-- LOGIC & STATE DETECTION
-------------------------------------------------------------------------

---Matches plugin name against defined targets
local function GetTargetMatch(fx_name)
    if not fx_name then return nil end
    local n_low = fx_name:lower()
    for _, t in ipairs(targets) do
        if n_low:find(t.name:lower(), 1, true) then
            return t
        end
    end
    return nil
end

---Updates instance counts and detects current oversampling state
local function UpdateStats()
    -- Reset temporary counters
    for _, t in ipairs(targets) do 
        t.count = 0 
        t.current_detect = -1 
    end
    
    ForEachFX(function(tr, addr)
        local _, name = r.TrackFX_GetFXName(tr, addr, "")
        local t = GetTargetMatch(name)
        if t then
            t.count = t.count + 1
            
            -- Detect current oversampling of this instance
            local ok, val = r.TrackFX_GetNamedConfigParm(tr, addr, "instance_oversample_shift")
            if ok then
                local current_val = tonumber(val) or 0
                -- Use the first instance found to populate the "Actual" display
                if t.current_detect == -1 then
                    t.current_detect = current_val
                end
            end
        end
    end)

    -- Initial Sync: If script loads and system is OFF, set Target UI to match Reality
    if not initial_sync_done and not global_on then
        for _, t in ipairs(targets) do
            if t.current_detect >= 0 then
                t.shift = t.current_detect
            end
        end
        initial_sync_done = true
    end
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
        local target = GetTargetMatch(name)
        
        if target then
            -- 1. Store original value
            local ok, val = r.TrackFX_GetNamedConfigParm(tr, addr, "instance_oversample_shift")
            if ok then
                original_values[#original_values+1] = guid .. "=" .. (tonumber(val) or 0)
                -- 2. Apply target value (0-3)
                r.TrackFX_SetNamedConfigParm(tr, addr, "instance_oversample_shift", tostring(target.shift))
            end
        end
    end)
    
    -- Save restore map to Project ExtState
    r.SetProjExtState(0, EXT_SECTION, EXT_KEY_ORIG, table.concat(original_values, "|"))
    
    global_on = true
    r.SetProjExtState(0, EXT_SECTION, EXT_KEY_STATE, "1")
    
    r.PreventUIRefresh(-1)
    r.Undo_EndBlock("Enable Fixed Oversampling", -1)
    
    -- Force stats update immediately to reflect changes in UI
    UpdateStats()
end

local function RestoreOversampling()
    r.Undo_BeginBlock()
    r.PreventUIRefresh(1)
    
    local _, data = r.GetProjExtState(0, EXT_SECTION, EXT_KEY_ORIG)
    local restore_map = {}
    
    -- Parse saved string
    for entry in data:gmatch("[^|]+") do
        local g, v = entry:match("(%b{})=(%d+)")
        if g then restore_map[g] = v end
    end
    
    ForEachFX(function(tr, addr, guid)
        if restore_map[guid] then
            -- Restore specific value
            r.TrackFX_SetNamedConfigParm(tr, addr, "instance_oversample_shift", restore_map[guid])
        else
            -- Safety fallback: if target but no saved data, turn off OS
            local _, name = r.TrackFX_GetFXName(tr, addr, "")
            if GetTargetMatch(name) then
                r.TrackFX_SetNamedConfigParm(tr, addr, "instance_oversample_shift", "0")
            end
        end
    end)
    
    r.SetProjExtState(0, EXT_SECTION, EXT_KEY_ORIG, "")
    global_on = false
    r.SetProjExtState(0, EXT_SECTION, EXT_KEY_STATE, "0")
    
    r.PreventUIRefresh(-1)
    r.Undo_EndBlock("Restore Oversampling State", -1)
    
    UpdateStats()
end

-------------------------------------------------------------------------
-- PERSISTENCE
-------------------------------------------------------------------------

local function SaveConfig()
    -- Save target shifts to project
    local save_str = string.format("%d|%d", targets[1].shift, targets[2].shift)
    r.SetProjExtState(0, EXT_SECTION, EXT_KEY_CONFIG, save_str)
    r.MarkProjectDirty(0)
end

local function LoadConfig()
    local _, st = r.GetProjExtState(0, EXT_SECTION, EXT_KEY_STATE)
    global_on = (st == "1")
    
    -- If Global Mode is ON, we must respect the saved configuration.
    -- If Global Mode is OFF, we let UpdateStats sync the initial values from reality.
    if global_on then
        local _, cfg = r.GetProjExtState(0, EXT_SECTION, EXT_KEY_CONFIG)
        if cfg ~= "" then
            local s1, s2 = cfg:match("^(%d+)|(%d+)$")
            if s1 then targets[1].shift = tonumber(s1) end
            if s2 then targets[2].shift = tonumber(s2) end
        end
        initial_sync_done = true -- Prevent overwrite
    end
end

-------------------------------------------------------------------------
-- IMGUI LOOP
-------------------------------------------------------------------------

local function loop()
    -- 1. Periodic background scan (every 500ms)
    local now = r.time_precise()
    if now - last_scan_time > 0.5 then
        UpdateStats()
        last_scan_time = now
    end

    -- 2. Window Setup
    r.ImGui_SetNextWindowSize(ctx, 480, 240, r.ImGui_Cond_FirstUseEver())
    local visible, open = r.ImGui_Begin(ctx, "DocShadrach's Analog Ecosystem oversampling manager", true)
    
    if visible then
        -- MAIN TOGGLE BUTTON
        -- "APPLY TARGETS" is more neutral than "ACTIVATE"
        local btn_label = global_on and "RESTORE ORIGINALS" or "APPLY TARGETS"
        local btn_col = global_on and COL_RED or COL_GREEN
        
        r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Button(), btn_col)
        if r.ImGui_Button(ctx, btn_label, -1, 50) then
            if global_on then 
                RestoreOversampling() 
            else 
                ApplyOversampling() 
                SaveConfig() 
            end
        end
        r.ImGui_PopStyleColor(ctx, 1)
        
        r.ImGui_Spacing(ctx)
        r.ImGui_Separator(ctx)
        
        -- STATUS TABLE
        -- Columns: Name | Actual State | Target State (Editable) | Count
        if r.ImGui_BeginTable(ctx, 'target_table', 4, r.ImGui_TableFlags_Borders() | r.ImGui_TableFlags_RowBg()) then
            r.ImGui_TableSetupColumn(ctx, 'Plugin', r.ImGui_TableColumnFlags_WidthStretch())
            r.ImGui_TableSetupColumn(ctx, 'Actual', r.ImGui_TableColumnFlags_WidthFixed(), 60)
            r.ImGui_TableSetupColumn(ctx, 'Target', r.ImGui_TableColumnFlags_WidthFixed(), 90)
            r.ImGui_TableSetupColumn(ctx, '#', r.ImGui_TableColumnFlags_WidthFixed(), 40)
            r.ImGui_TableHeadersRow(ctx)
            
            for i, t in ipairs(targets) do
                r.ImGui_PushID(ctx, i)
                r.ImGui_TableNextRow(ctx)
                
                -- Column 1: Name
                r.ImGui_TableSetColumnIndex(ctx, 0)
                r.ImGui_AlignTextToFramePadding(ctx)
                r.ImGui_Text(ctx, t.label)
                
                -- Column 2: Actual Status (Read Only)
                r.ImGui_TableSetColumnIndex(ctx, 1)
                local cur_str = (t.current_detect >= 0) and GetShiftLabel(t.current_detect) or "?"
                -- Highlight if Actual != Target
                local cur_col = (t.current_detect ~= t.shift) and COL_HIGHLIGHT or 0xAAAAAAFF
                r.ImGui_TextColored(ctx, cur_col, cur_str)

                -- Column 3: Target Selection (Combo)
                r.ImGui_TableSetColumnIndex(ctx, 2)
                r.ImGui_SetNextItemWidth(ctx, -1)
                
                -- Disable input if global mode is active to prevent sync issues
                if global_on then r.ImGui_BeginDisabled(ctx) end
                
                -- shift: 0=-, 1=2x, 2=4x, 3=8x.
                local current_idx = t.shift
                local ok, new_idx = r.ImGui_Combo(ctx, "##rate", current_idx, "-\0 2x\0 4x\0 8x\0")
                if ok then t.shift = new_idx end
                
                if global_on then r.ImGui_EndDisabled(ctx) end
                
                -- Column 4: Instance Count
                r.ImGui_TableSetColumnIndex(ctx, 3)
                local count_col = (t.count > 0) and 0x55FF55FF or 0xAAAAAAFF
                r.ImGui_TextColored(ctx, count_col, tostring(t.count))
                
                r.ImGui_PopID(ctx)
            end
            r.ImGui_EndTable(ctx)
        end
        
        -- Footer text
        if global_on then
           r.ImGui_Spacing(ctx)
           r.ImGui_TextColored(ctx, COL_TEXT_DIM, "Status: TARGETS APPLIED!")
        end
        
        r.ImGui_End(ctx)
    end
    
    if open then r.defer(loop) end
end

-------------------------------------------------------------------------
-- ENTRY POINT
-------------------------------------------------------------------------
ctx = r.ImGui_CreateContext('OversamplingManagerAnalog')
LoadConfig()
r.defer(loop)
