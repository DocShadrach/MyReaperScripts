-- @description FX Scene Manager and Switcher
-- @version 1.0
-- @author DocShadrach
-- @about
--   A professional ReaImGui tool to define and switch between different sets of FX.
--   Features:
--   - Define multiple FX groups (Rows).
--   - Supports Multiple Patterns per row (comma separated: "ReaEQ, Pro-Q").
--   - "Selected Tracks Only" scope mode.
--   - Drag & Drop reordering of rows.
--   - Smart Exclusive Mode (A/B Testing logic).
--   - Persistence: Saves settings in the .rpp file.
--   - Container Support: Scans root FX and first-level containers.

local r = reaper
local ctx

if not r.APIExists('ImGui_GetVersion') then
    r.ShowMessageBox("ReaImGui is required.", "Error", 0)
    return
end

-- CONFIGURATION CONSTANTS
local EXT_SECTION = "DocShadrach_FXManager"
local EXT_KEY = "SceneData"
local SCAN_INTERVAL = 0.3

-- COLORS
local COL_GREEN = 0x2E7D32FF
local COL_RED   = 0xC62828FF
local COL_AMBER = 0xFF8F00FF
local COL_GREY  = 0x444444FF

-- STATE
local scenes = {} 
local global_exclusive = true
local include_containers = true
local scope_selected = false 
local last_scan_time = 0

-- INITIAL DEFAULT STATE
local function addScene(name, pattern)
    table.insert(scenes, {
        name = name or "New Set",
        pattern = pattern or "",
        status_color = COL_GREY,
        match_stats = "...",
        is_fully_active = false
    })
end

-------------------------------------------------------------------------
-- PERSISTENCE
-------------------------------------------------------------------------

local function serialize()
    local str = ""
    for _, scene in ipairs(scenes) do
        local n = scene.name:gsub("|", ""):gsub("::", "")
        local p = scene.pattern:gsub("|", ""):gsub("::", "")
        str = str .. n .. "|" .. p .. "::"
    end
    str = str .. "OPT_EXCL=" .. tostring(global_exclusive) .. "::"
    str = str .. "OPT_CONT=" .. tostring(include_containers) .. "::"
    str = str .. "OPT_SCOPE=" .. tostring(scope_selected) 
    return str
end

local function saveState()
    local data = serialize()
    r.SetProjExtState(0, EXT_SECTION, EXT_KEY, data)
end

local function loadState()
    local retval, data = r.GetProjExtState(0, EXT_SECTION, EXT_KEY)
    if retval == 1 and data ~= "" then
        scenes = {} 
        for entry in data:gmatch("([^::]+)") do
            if entry:find("OPT_EXCL=") then
                global_exclusive = (entry:match("OPT_EXCL=(.*)") == "true")
            elseif entry:find("OPT_CONT=") then
                include_containers = (entry:match("OPT_CONT=(.*)") == "true")
            elseif entry:find("OPT_SCOPE=") then
                scope_selected = (entry:match("OPT_SCOPE=(.*)") == "true")
            else
                local name, pattern = entry:match("^(.*)|(.*)$")
                if name then addScene(name, pattern) end
            end
        end
    else
        addScene("Set A (Examples)", "ReaEQ, ReaComp")
        addScene("Set B (Examples)", "ReaDelay, ReaVerb")
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
        if #part >= 2 and s_lower:find(part, 1, true) then
            return true
        end
    end
    return false
end

local function iterateTargetTracks(callback)
    if scope_selected then
        local count = r.CountSelectedTracks(0)
        for i = 0, count - 1 do
            local tr = r.GetSelectedTrack(0, i)
            callback(tr)
        end
    else
        callback(r.GetMasterTrack(0))
        local count = r.CountTracks(0)
        for i = 0, count - 1 do
            callback(r.GetTrack(0, i))
        end
    end
end

local function getPatternStats(pattern)
    if not pattern or pattern == "" then return 0, 0, 0 end
    
    local found, en, dis = 0, 0, 0
    
    local function checkTrack(tr)
        local fxCount = r.TrackFX_GetCount(tr)
        for i = 0, fxCount - 1 do
            local _, name = r.TrackFX_GetFXName(tr, i, "")
            
            -- Check Root FX
            if nameMatches(name, pattern) and not r.TrackFX_GetOffline(tr, i) then
                found = found + 1
                if r.TrackFX_GetEnabled(tr, i) then en = en + 1 else dis = dis + 1 end
            end
            
            -- Check First-Level Container
            if include_containers then
                local retval, cCount = r.TrackFX_GetNamedConfigParm(tr, i, "container_count")
                if retval and tonumber(cCount) and tonumber(cCount) > 0 then
                    for cIdx = 0, tonumber(cCount) - 1 do
                        -- Formula for 1st Level Nesting
                        local gIdx = 0x2000000 + (cIdx + 1) * (fxCount + 1) + i + 1
                        local _, cName = r.TrackFX_GetFXName(tr, gIdx, "")
                        
                        if nameMatches(cName, pattern) and not r.TrackFX_GetOffline(tr, gIdx) then
                            found = found + 1
                            if r.TrackFX_GetEnabled(tr, gIdx) then en = en + 1 else dis = dis + 1 end
                        end
                    end
                end
            end
        end
    end
    
    iterateTargetTracks(checkTrack)
    
    return found, en, dis
end

local function updateMonitor()
    for _, scene in ipairs(scenes) do
        local f, en, dis = getPatternStats(scene.pattern)
        scene.match_stats = f .. " Found"
        
        if f == 0 then
            scene.status_color = COL_GREY
            scene.is_fully_active = false
        elseif en == f then
            scene.status_color = COL_GREEN
            scene.is_fully_active = true
        elseif dis == f then
            scene.status_color = COL_RED
            scene.is_fully_active = false
        else
            scene.status_color = COL_AMBER
            scene.is_fully_active = false
        end
    end
end

local function moveScene(srcIndex, dstIndex)
    if srcIndex == dstIndex then return end
    local item = table.remove(scenes, srcIndex)
    table.insert(scenes, dstIndex, item)
    saveState()
end

local function toggleScene(targetIndex, targetState)
    r.Undo_BeginBlock()
    r.PreventUIRefresh(1)
    
    local targetPattern = scenes[targetIndex].pattern
    
    local patternsToDisable = {}
    if global_exclusive and targetState == true then
        for i, scene in ipairs(scenes) do
            if i ~= targetIndex and scene.pattern ~= "" then
                table.insert(patternsToDisable, scene.pattern)
            end
        end
    end
    
    local function processTrack(tr)
        local fxCount = r.TrackFX_GetCount(tr)
        
        -- Helper to apply logic to a specific index
        local function applyLogic(idx, name)
            if r.TrackFX_GetOffline(tr, idx) then return end
            
            -- 1. Apply Target State
            if nameMatches(name, targetPattern) then
                r.TrackFX_SetEnabled(tr, idx, targetState)
            end
            
            -- 2. Exclusive Logic
            if global_exclusive and targetState == true then
                for _, otherP in ipairs(patternsToDisable) do
                    if nameMatches(name, otherP) and not nameMatches(name, targetPattern) then
                        r.TrackFX_SetEnabled(tr, idx, false)
                    end
                end
            end
        end
        
        for i = 0, fxCount - 1 do
            local _, name = r.TrackFX_GetFXName(tr, i, "")
            
            -- Process Root
            applyLogic(i, name)
            
            -- Process First-Level Container
            if include_containers then
                local retval, cCount = r.TrackFX_GetNamedConfigParm(tr, i, "container_count")
                if retval and tonumber(cCount) and tonumber(cCount) > 0 then
                    for cIdx = 0, tonumber(cCount) - 1 do
                        local gIdx = 0x2000000 + (cIdx + 1) * (fxCount + 1) + i + 1
                        local _, cName = r.TrackFX_GetFXName(tr, gIdx, "")
                        applyLogic(gIdx, cName)
                    end
                end
            end
        end
    end
    
    iterateTargetTracks(processTrack)
    
    r.TrackList_AdjustWindows(false)
    r.UpdateArrange()
    r.PreventUIRefresh(-1)
    
    local actionText = targetState and "Turn ON " or "Turn OFF "
    r.Undo_EndBlock(actionText .. scenes[targetIndex].name, -1)
    
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

    local flags = r.ImGui_WindowFlags_NoCollapse()
    r.ImGui_SetNextWindowSize(ctx, 550, 350, r.ImGui_Cond_FirstUseEver())
    
    local visible, open = r.ImGui_Begin(ctx, 'FX Scene Manager', true, flags)
    
    if visible then
        -- Header Options
        local chk_excl, new_excl = r.ImGui_Checkbox(ctx, "Exclusive Mode", global_exclusive)
        if chk_excl then global_exclusive = new_excl; saveState() end
        if r.ImGui_IsItemHovered(ctx) then r.ImGui_SetTooltip(ctx, "Enabling one set disables the others.") end
        
        r.ImGui_SameLine(ctx)
        local chk_cont, new_cont = r.ImGui_Checkbox(ctx, "Containers", include_containers)
        if chk_cont then include_containers = new_cont; saveState() end
        if r.ImGui_IsItemHovered(ctx) then r.ImGui_SetTooltip(ctx, "Scans first-level containers.") end
        
        r.ImGui_SameLine(ctx)
        local chk_scope, new_scope = r.ImGui_Checkbox(ctx, "Selected Tracks Only", scope_selected)
        if chk_scope then scope_selected = new_scope; saveState() end
        if r.ImGui_IsItemHovered(ctx) then r.ImGui_SetTooltip(ctx, "If checked, actions only affect currently selected tracks.") end

        r.ImGui_Separator(ctx)
        
        -- Table
        if r.ImGui_BeginTable(ctx, 'SceneTable_v2', 5, r.ImGui_TableFlags_Resizable() | r.ImGui_TableFlags_RowBg()) then
            -- Column setup
            r.ImGui_TableSetupColumn(ctx, '##Mov', r.ImGui_TableColumnFlags_WidthFixed() | r.ImGui_TableColumnFlags_NoResize(), 20)
            r.ImGui_TableSetupColumn(ctx, 'Status', r.ImGui_TableColumnFlags_WidthFixed(), 80)
            r.ImGui_TableSetupColumn(ctx, 'Set Name', r.ImGui_TableColumnFlags_WidthStretch())
            r.ImGui_TableSetupColumn(ctx, 'Pattern(s)', r.ImGui_TableColumnFlags_WidthStretch())
            r.ImGui_TableSetupColumn(ctx, '##Del', r.ImGui_TableColumnFlags_WidthFixed(), 30)
            r.ImGui_TableHeadersRow(ctx)
            
            local to_remove = nil
            
            for i, scene in ipairs(scenes) do
                r.ImGui_TableNextRow(ctx)
                r.ImGui_PushID(ctx, i)

                -- COL 1: Drag Handle
                r.ImGui_TableSetColumnIndex(ctx, 0)
                r.ImGui_Selectable(ctx, "::", false, r.ImGui_SelectableFlags_AllowOverlap())
                
                if r.ImGui_BeginDragDropSource(ctx, r.ImGui_DragDropFlags_None()) then
                    r.ImGui_SetDragDropPayload(ctx, 'DND_SCENE', tostring(i))
                    r.ImGui_Text(ctx, "Move " .. scene.name)
                    r.ImGui_EndDragDropSource(ctx)
                end
                
                if r.ImGui_BeginDragDropTarget(ctx) then
                    local retval, payload = r.ImGui_AcceptDragDropPayload(ctx, 'DND_SCENE')
                    if retval then
                        local src_idx = tonumber(payload)
                        moveScene(src_idx, i)
                    end
                    r.ImGui_EndDragDropTarget(ctx)
                end
                
                -- COL 2: Status/Toggle
                r.ImGui_TableSetColumnIndex(ctx, 1)
                local btn_col = scene.status_color
                local btn_txt = "OFF"
                if scene.is_fully_active then btn_txt = "ON"
                elseif scene.status_color == COL_AMBER then btn_txt = "MIXED"
                elseif scene.status_color == COL_GREY then btn_txt = "-" end
                
                r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Button(), btn_col)
                if r.ImGui_Button(ctx, btn_txt, -1, 0) then
                    if scene.pattern ~= "" then
                        -- SMART LOGIC
                        local targetState = true
                        local othersActive = false
                        for k, otherS in ipairs(scenes) do
                            if k ~= i and (otherS.status_color == COL_GREEN or otherS.status_color == COL_AMBER) then
                                othersActive = true; break
                            end
                        end
                        if scene.is_fully_active then
                            if global_exclusive and othersActive then targetState = true
                            else targetState = false end
                        else targetState = true end
                        toggleScene(i, targetState)
                    end
                end
                r.ImGui_PopStyleColor(ctx, 1)
                
                -- COL 3: Name
                r.ImGui_TableSetColumnIndex(ctx, 2)
                r.ImGui_SetNextItemWidth(ctx, -1)
                local ch_n, new_n = r.ImGui_InputText(ctx, "##name", scene.name)
                if ch_n then scene.name = new_n; saveState() end
                
                -- COL 4: Pattern
                r.ImGui_TableSetColumnIndex(ctx, 3)
                r.ImGui_SetNextItemWidth(ctx, -1)
                local ch_p, new_p = r.ImGui_InputText(ctx, "##pat", scene.pattern)
                if ch_p then scene.pattern = new_p; saveState() end
                if r.ImGui_IsItemHovered(ctx) then
                    r.ImGui_SetTooltip(ctx, "Plugins matching any comma-separated value.\nStats: " .. scene.match_stats)
                end
                
                -- COL 5: Delete
                r.ImGui_TableSetColumnIndex(ctx, 4)
                if r.ImGui_Button(ctx, "X") then to_remove = i end
                
                r.ImGui_PopID(ctx)
            end
            
            r.ImGui_EndTable(ctx)
            
            if to_remove then
                table.remove(scenes, to_remove)
                saveState()
            end
        end
        
        r.ImGui_Spacing(ctx)
        if r.ImGui_Button(ctx, "+ ADD NEW SET", -1, 30) then
            addScene("New Set", "")
            saveState()
        end
        
        r.ImGui_End(ctx)
    end
    
    if open then r.defer(loop) end
end

ctx = r.ImGui_CreateContext('FX_Scene_Manager')
loadState()
r.defer(loop)
