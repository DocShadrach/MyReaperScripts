-- @description FX Scene Manager and Switcher
-- @version 1.2
-- @author DocShadrach
-- @about
--   A ReaImGui tool to define and switch between different sets of FX.
--   Features:
--   - Multi-Scene Support: Switch between 8 different pages/scenes of FX configurations.
--   - Define multiple FX groups (Rows).
--   - Supports Multiple Patterns per row (comma separated: "ReaEQ, Pro-Q").
--   - "Selected Tracks Only" scope mode.
--   - Drag & Drop reordering of rows.
--   - Smart Exclusive Mode (A/B Testing logic).
--   - Persistence: Saves settings in the .rpp file.
--   - Containers support.

local r = reaper
local ctx

if not r.APIExists('ImGui_GetVersion') then
    r.ShowMessageBox("ReaImGui is required.", "Error", 0)
    return
end

-- CONFIGURATION CONSTANTS
local EXT_SECTION = "DocShadrach_FXManager"
local EXT_KEY_PREFIX = "SceneData_"
local EXT_OPT_KEY = "GlobalOptions"
local SCAN_INTERVAL = 0.3
local MAX_SCENES = 8

-- COLORS
local COL_GREEN = 0x2E7D32FF
local COL_RED   = 0xC62828FF
local COL_AMBER = 0xFF8F00FF
local COL_GREY  = 0x444444FF
local COL_TEXT_YELLOW = 0xFFFF00FF 

-- STATE
local all_scenes = {} 
local current_scene_idx = 1
local global_exclusive = true
local include_containers = true
local scope_selected = false 
local last_scan_time = 0

for i = 1, MAX_SCENES do all_scenes[i] = {} end

-------------------------------------------------------------------------
-- RECURSIVE POLYNOMIAL ENGINE
-------------------------------------------------------------------------

---Recursive function to scan FX using polynomial scale multipliers
---@param track MediaTrack
---@param container_id integer - The base ID of the container
---@param parent_count integer - FX count of the level above
---@param multiplier integer - The accumulated multiplier (Diff)
---@param callback function - Action(track, address)
local function ScanRecursive(track, container_id, parent_count, multiplier, callback)
    -- Calculate the scale step for this level
    local current_diff = (parent_count + 1) * multiplier
    
    -- Query the number of children in this container
    local ok, c_fx_count = r.TrackFX_GetNamedConfigParm(track, 0x2000000 + container_id, "container_count")
    if not ok then return end
    
    local count = tonumber(c_fx_count) or 0

    for i = 1, count do
        -- Formula: 0x2000000 + Parent_ID + (Index_1based * Multiplier)
        local fx_addr = 0x2000000 + container_id + (i * current_diff)
        
        callback(track, fx_addr)

        -- If the child is also a container, recurse deeper
        local ok_type, fx_type = r.TrackFX_GetNamedConfigParm(track, fx_addr, "fx_type")
        if ok_type and fx_type == "Container" then
            ScanRecursive(track, container_id + (i * current_diff), count, current_diff, callback)
        end
    end
end

---Iterates project tracks and scans Root + Deep Containers
local function ForEachFX(callback)
    local tracks = {}
    if scope_selected then
        for i = 0, r.CountSelectedTracks(0) - 1 do table.insert(tracks, r.GetSelectedTrack(0, i)) end
    else
        table.insert(tracks, r.GetMasterTrack(0))
        for i = 0, r.CountTracks(0) - 1 do table.insert(tracks, r.GetTrack(0, i)) end
    end

    for _, tr in ipairs(tracks) do
        local root_count = r.TrackFX_GetCount(tr)
        for i = 1, root_count do
            local addr = i - 1
            callback(tr, addr)
            
            -- If root FX is a container, enter the recursive polynomial engine
            if include_containers then
                local ok_type, fx_type = r.TrackFX_GetNamedConfigParm(tr, addr, "fx_type")
                if ok_type and fx_type == "Container" then
                    -- container_id: 1-based root index
                    -- parent_count: root count
                    -- multiplier: base scale 1
                    ScanRecursive(tr, i, root_count, 1, callback)
                end
            end
        end
    end
end

-------------------------------------------------------------------------
-- PERSISTENCE
-------------------------------------------------------------------------

local function serialize_rows(rows)
    local str = ""
    for _, item in ipairs(rows) do
        local n = item.name:gsub("|", ""):gsub("::", "")
        local p = item.pattern:gsub("|", ""):gsub("::", "")
        str = str .. n .. "|" .. p .. "::"
    end
    return str
end

local function saveState()
    local opt_str = "OPT_EXCL=" .. tostring(global_exclusive) .. "::" ..
                    "OPT_CONT=" .. tostring(include_containers) .. "::" ..
                    "OPT_SCOPE=" .. tostring(scope_selected) .. "::" ..
                    "CUR_SCENE=" .. tostring(current_scene_idx)
    r.SetProjExtState(0, EXT_SECTION, EXT_OPT_KEY, opt_str)
    for i = 1, MAX_SCENES do
        r.SetProjExtState(0, EXT_SECTION, EXT_KEY_PREFIX .. i, serialize_rows(all_scenes[i]))
    end
    r.MarkProjectDirty(0)
end

local function loadState()
    local retval, opt_data = r.GetProjExtState(0, EXT_SECTION, EXT_OPT_KEY)
    if retval == 1 and opt_data ~= "" then
        global_exclusive = (opt_data:match("OPT_EXCL=(.-)::") == "true")
        include_containers = (opt_data:match("OPT_CONT=(.-)::") == "true")
        scope_selected = (opt_data:match("OPT_SCOPE=(.-)::") == "true")
        local cs = tonumber(opt_data:match("CUR_SCENE=(%d+)"))
        if cs then current_scene_idx = cs end
    end
    for i = 1, MAX_SCENES do
        local rv, s_data = r.GetProjExtState(0, EXT_SECTION, EXT_KEY_PREFIX .. i)
        if rv == 1 and s_data ~= "" then
            all_scenes[i] = {}
            for entry in s_data:gmatch("([^::]+)") do
                local name, pattern = entry:match("^(.*)|(.*)$")
                if name then 
                    table.insert(all_scenes[i], {name=name, pattern=pattern, status_color=COL_GREY, match_stats="...", is_fully_active=false})
                end
            end
        end
    end
end

-------------------------------------------------------------------------
-- CORE LOGIC
-------------------------------------------------------------------------

local function nameMatches(source, pattern_str)
    if not pattern_str or pattern_str == "" then return false end
    local s_lower = source:lower()
    for part in pattern_str:gmatch("[^,]+") do
        part = part:match("^%s*(.-)%s*$"):lower() 
        if #part >= 2 and s_lower:find(part, 1, true) then return true end
    end
    return false
end

local function getPatternStats(pattern)
    if not pattern or pattern == "" then return 0, 0, 0 end
    local found, en, dis = 0, 0, 0
    ForEachFX(function(track, addr)
        local _, name = r.TrackFX_GetFXName(track, addr, "")
        if nameMatches(name, pattern) and not r.TrackFX_GetOffline(track, addr) then
            found = found + 1
            if r.TrackFX_GetEnabled(track, addr) then en = en + 1 else dis = dis + 1 end
        end
    end)
    return found, en, dis
end

local function updateMonitor()
    local current_rows = all_scenes[current_scene_idx]
    for _, scene in ipairs(current_rows) do
        local f, en, dis = getPatternStats(scene.pattern)
        scene.match_stats = f .. " Found"
        if f == 0 then
            scene.status_color, scene.is_fully_active = COL_GREY, false
        elseif en == f then
            scene.status_color, scene.is_fully_active = COL_GREEN, true
        elseif dis == f then
            scene.status_color, scene.is_fully_active = COL_RED, false
        else
            scene.status_color, scene.is_fully_active = COL_AMBER, false
        end
    end
end

local function toggleScene(targetIndex, targetState)
    r.Undo_BeginBlock()
    r.PreventUIRefresh(1)
    
    local rows = all_scenes[current_scene_idx]
    local targetPattern = rows[targetIndex].pattern
    local patternsToDisable = {}
    
    if global_exclusive and targetState == true then
        for i, scene in ipairs(rows) do
            if i ~= targetIndex and scene.pattern ~= "" then
                table.insert(patternsToDisable, scene.pattern)
            end
        end
    end
    
    ForEachFX(function(track, addr)
        if r.TrackFX_GetOffline(track, addr) then return end
        local _, name = r.TrackFX_GetFXName(track, addr, "")
        
        if nameMatches(name, targetPattern) then
            r.TrackFX_SetEnabled(track, addr, targetState)
        end
        
        if global_exclusive and targetState == true then
            for _, otherP in ipairs(patternsToDisable) do
                if nameMatches(name, otherP) and not nameMatches(name, targetPattern) then
                    r.TrackFX_SetEnabled(track, addr, false)
                end
            end
        end
    end)
    
    r.TrackList_AdjustWindows(false)
    r.UpdateArrange()
    r.PreventUIRefresh(-1)
    r.Undo_EndBlock((targetState and "Turn ON " or "Turn OFF ") .. rows[targetIndex].name, -1)
    updateMonitor()
end

-------------------------------------------------------------------------
-- GUI
-------------------------------------------------------------------------

local function loop()
    local now = r.time_precise()
    if now - last_scan_time > SCAN_INTERVAL then
        updateMonitor()
        last_scan_time = now
    end

    r.ImGui_SetNextWindowSize(ctx, 600, 400, r.ImGui_Cond_FirstUseEver())
    local visible, open = r.ImGui_Begin(ctx, 'FX Scene Manager', true, r.ImGui_WindowFlags_NoCollapse())
    
    if visible then
        local avail_w = r.ImGui_GetContentRegionAvail(ctx)
        
        if r.ImGui_Checkbox(ctx, "Exclusive", global_exclusive) then global_exclusive = not global_exclusive; saveState() end
        r.ImGui_SameLine(ctx)
        if r.ImGui_Checkbox(ctx, "Containers", include_containers) then include_containers = not include_containers; saveState() end
        r.ImGui_SameLine(ctx)
        if r.ImGui_Checkbox(ctx, "Selected Only", scope_selected) then scope_selected = not scope_selected; saveState() end
        
        r.ImGui_SameLine(ctx)
        local right_align = avail_w - 125
        if right_align > r.ImGui_GetCursorPosX(ctx) then r.ImGui_SetCursorPosX(ctx, right_align) end
        
        if r.ImGui_ArrowButton(ctx, "##prev", r.ImGui_Dir_Left()) then
            current_scene_idx = (current_scene_idx - 2) % MAX_SCENES + 1
            saveState(); updateMonitor()
        end
        r.ImGui_SameLine(ctx)
        r.ImGui_TextColored(ctx, COL_TEXT_YELLOW, "Scene < " .. current_scene_idx .. " >")
        r.ImGui_SameLine(ctx)
        if r.ImGui_ArrowButton(ctx, "##next", r.ImGui_Dir_Right()) then
            current_scene_idx = (current_scene_idx % MAX_SCENES) + 1
            saveState(); updateMonitor()
        end

        r.ImGui_Separator(ctx)
        
        if r.ImGui_BeginTable(ctx, 'SceneTable_v4', 5, r.ImGui_TableFlags_Resizable() | r.ImGui_TableFlags_RowBg()) then
            r.ImGui_TableSetupColumn(ctx, '::', r.ImGui_TableColumnFlags_WidthFixed(), 20)
            r.ImGui_TableSetupColumn(ctx, 'Status', r.ImGui_TableColumnFlags_WidthFixed(), 70)
            r.ImGui_TableSetupColumn(ctx, 'Set Name', r.ImGui_TableColumnFlags_WidthStretch())
            r.ImGui_TableSetupColumn(ctx, 'Pattern(s)', r.ImGui_TableColumnFlags_WidthStretch())
            r.ImGui_TableSetupColumn(ctx, 'X', r.ImGui_TableColumnFlags_WidthFixed(), 30)
            r.ImGui_TableHeadersRow(ctx)
            
            local current_rows = all_scenes[current_scene_idx]
            local to_remove = nil
            
            for i, scene in ipairs(current_rows) do
                r.ImGui_PushID(ctx, i)
                r.ImGui_TableNextRow(ctx)
                
                r.ImGui_TableSetColumnIndex(ctx, 0)
                r.ImGui_Selectable(ctx, "::", false, r.ImGui_SelectableFlags_AllowOverlap())
                if r.ImGui_BeginDragDropSource(ctx) then
                    r.ImGui_SetDragDropPayload(ctx, 'DND_SCENE', tostring(i))
                    r.ImGui_Text(ctx, "Move " .. scene.name); r.ImGui_EndDragDropSource(ctx)
                end
                if r.ImGui_BeginDragDropTarget(ctx) then
                    local rv, pay = r.ImGui_AcceptDragDropPayload(ctx, 'DND_SCENE')
                    if rv then 
                        local src = tonumber(pay)
                        local item = table.remove(current_rows, src)
                        table.insert(current_rows, i, item)
                        saveState()
                    end
                    r.ImGui_EndDragDropTarget(ctx)
                end
                
                r.ImGui_TableSetColumnIndex(ctx, 1)
                local btn_txt = scene.is_fully_active and "ON" or (scene.status_color == COL_AMBER and "MIXED" or "OFF")
                r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Button(), scene.status_color)
                if r.ImGui_Button(ctx, btn_txt, -1, 0) then
                    toggleScene(i, not scene.is_fully_active)
                end
                r.ImGui_PopStyleColor(ctx, 1)
                
                r.ImGui_TableSetColumnIndex(ctx, 2); r.ImGui_SetNextItemWidth(ctx, -1)
                local ch_n, new_n = r.ImGui_InputText(ctx, "##name", scene.name)
                if ch_n then scene.name = new_n; saveState() end
                
                r.ImGui_TableSetColumnIndex(ctx, 3); r.ImGui_SetNextItemWidth(ctx, -1)
                local ch_p, new_p = r.ImGui_InputText(ctx, "##pat", scene.pattern)
                if ch_p then scene.pattern = new_p; saveState() end
                if r.ImGui_IsItemHovered(ctx) then r.ImGui_SetTooltip(ctx, scene.match_stats) end
                
                r.ImGui_TableSetColumnIndex(ctx, 4)
                if r.ImGui_Button(ctx, "X", -1) then to_remove = i end
                r.ImGui_PopID(ctx)
            end
            r.ImGui_EndTable(ctx)
            if to_remove then table.remove(current_rows, to_remove); saveState() end
        end
        if r.ImGui_Button(ctx, "+ ADD NEW SET", -1, 30) then
            table.insert(all_scenes[current_scene_idx], {name="New Set", pattern="", status_color=COL_GREY, match_stats="...", is_fully_active=false})
            saveState()
        end
        r.ImGui_End(ctx)
    end
    if open then r.defer(loop) end
end

ctx = r.ImGui_CreateContext('FX_Scene_Manager')
loadState()
r.defer(loop)
