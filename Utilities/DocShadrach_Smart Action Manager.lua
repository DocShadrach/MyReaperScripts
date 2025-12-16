-- @description Smart Action Manager
-- @author DocShadrach
-- @version 1.0
-- @about 
--   Configuration interface for Smart Action Buttons (1-32).
--   Assigns Reaper Actions to specific button IDs per project.
--   Requires 'DocShadrach_Smart Action Loader.lua' running in the background.
-- @requirement ReaImGui

local r = reaper
local ctx = r.ImGui_CreateContext('SmartActionManager')

-- CONFIG
local EXT_SECTION = "DocShadrach_SmartActions"
local EXT_KEY     = "MapData"
local GLOBAL_KEY  = "GlobalPreset"

-- DATA
local action_map = {}
for i=1, 32 do action_map[i] = "" end

-- COLORS
local COL_BG_H = 0x2D2D2DFF

-- HELPERS
function GetCommandName(id)
    if not id or id == "" then return "-" end
    local int_id = r.NamedCommandLookup(id)
    if int_id == 0 then return "(Invalid ID)" end
    local text = r.CF_GetCommandText(0, int_id)
    if not text or text == "" then return id else return text end
end

function SaveToProject()
    local str = ""
    for i=1, 32 do
        if action_map[i] ~= "" then str = str .. i .. ":" .. action_map[i] .. "|" end
    end
    r.SetProjExtState(0, EXT_SECTION, EXT_KEY, str)
    r.MarkProjectDirty(0)
end

function LoadFromProject()
    local retval, data = r.GetProjExtState(0, EXT_SECTION, EXT_KEY)
    if retval == 1 and data ~= "" then
        for i=1, 32 do action_map[i] = "" end
        for pair in data:gmatch("([^|]+)") do
            local idx, id = pair:match("(%d+):(.*)")
            if idx then action_map[tonumber(idx)] = id end
        end
    end
end

function SaveGlobal()
    local str = ""
    for i=1, 32 do
        if action_map[i] ~= "" then str = str .. i .. ":" .. action_map[i] .. "|" end
    end
    r.SetExtState(EXT_SECTION, GLOBAL_KEY, str, true)
end

function LoadGlobal()
    local data = r.GetExtState(EXT_SECTION, GLOBAL_KEY)
    if data and data ~= "" then
        for i=1, 32 do action_map[i] = "" end
        for pair in data:gmatch("([^|]+)") do
            local idx, id = pair:match("(%d+):(.*)")
            if idx then action_map[tonumber(idx)] = id end
        end
        SaveToProject()
    else
        r.ShowMessageBox("No global preset found.", "Info", 0)
    end
end

LoadFromProject()

-- GUI LOOP
function Loop()
    -- Safe Flags
    local w_flags = r.ImGui_WindowFlags_None and r.ImGui_WindowFlags_None() or 0
    r.ImGui_SetNextWindowSize(ctx, 550, 650, r.ImGui_Cond_FirstUseEver())
    
    local visible, open = r.ImGui_Begin(ctx, 'Smart Action Manager', true, w_flags)
    
    if visible then
        
        -- 1. HEADER
        r.ImGui_Text(ctx, "SMART BUTTONS MANAGER")
        r.ImGui_SameLine(ctx)
        
        -- Just a simple link to Action List
        if r.ImGui_Button(ctx, "Open Action List") then r.ShowActionList(0, 0) end

        r.ImGui_Separator(ctx)
        
        -- 2. GLOBAL PRESETS
        if r.ImGui_Button(ctx, "Save Global Preset") then SaveGlobal() end
        if r.ImGui_IsItemHovered(ctx) then r.ImGui_SetTooltip(ctx, "Save current list as default for new projects") end
        
        r.ImGui_SameLine(ctx)
        if r.ImGui_Button(ctx, "Load Global Preset") then LoadGlobal() end

        r.ImGui_Separator(ctx)

        -- 3. ASSIGNMENT TABLE
        local t_flags = r.ImGui_TableFlags_RowBg and (r.ImGui_TableFlags_RowBg() | r.ImGui_TableFlags_BordersInnerH() | r.ImGui_TableFlags_ScrollY()) or 0
        
        if r.ImGui_BeginTable(ctx, "MapTable", 4, t_flags) then
            
            -- Safe Column Flags
            local f_fixed = r.ImGui_TableColumnFlags_WidthFixed and r.ImGui_TableColumnFlags_WidthFixed() or 0
            local f_stretch = r.ImGui_TableColumnFlags_WidthStretch and r.ImGui_TableColumnFlags_WidthStretch() or 0
            
            r.ImGui_TableSetupScrollFreeze(ctx, 0, 1)
            r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Header(), COL_BG_H)
            
            r.ImGui_TableSetupColumn(ctx, "#", f_fixed, 30)
            r.ImGui_TableSetupColumn(ctx, "Action Name", f_stretch)
            r.ImGui_TableSetupColumn(ctx, "Command ID", f_fixed, 110)
            r.ImGui_TableSetupColumn(ctx, "Edit", f_fixed, 70)
            r.ImGui_TableHeadersRow(ctx)
            r.ImGui_PopStyleColor(ctx)

            for i = 1, 32 do
                r.ImGui_TableNextRow(ctx)
                
                -- COL 1
                r.ImGui_TableSetColumnIndex(ctx, 0)
                r.ImGui_TextDisabled(ctx, tostring(i))
                
                -- COL 2
                r.ImGui_TableSetColumnIndex(ctx, 1)
                local has_action = (action_map[i] ~= "")
                local name = GetCommandName(action_map[i])
                
                if has_action then
                    r.ImGui_TextColored(ctx, 0x88FF88FF, name)
                else
                    r.ImGui_TextDisabled(ctx, "---")
                end
                
                -- COL 3
                r.ImGui_TableSetColumnIndex(ctx, 2)
                if has_action then r.ImGui_TextDisabled(ctx, action_map[i]) end

                -- COL 4
                r.ImGui_TableSetColumnIndex(ctx, 3)
                r.ImGui_PushID(ctx, i)
                
                if r.ImGui_Button(ctx, "Paste") then
                    if r.CF_GetClipboard then
                        local clip = r.CF_GetClipboard(""):match("^%s*(.-)%s*$")
                        if clip and r.NamedCommandLookup(clip) ~= 0 then
                            action_map[i] = clip; SaveToProject()
                        else
                            r.ShowMessageBox("Clipboard invalid or empty.", "Error", 0)
                        end
                    else
                        r.ShowMessageBox("SWS Extension required.", "Error", 0)
                    end
                end
                if r.ImGui_IsItemHovered(ctx) then r.ImGui_SetTooltip(ctx, "Paste Command ID") end
                
                r.ImGui_SameLine(ctx)
                if r.ImGui_Button(ctx, "X") then
                    action_map[i] = ""; SaveToProject()
                end
                
                r.ImGui_PopID(ctx)
            end
            r.ImGui_EndTable(ctx)
        end
        r.ImGui_End(ctx)
    end

    if open then r.defer(Loop) end
end

Loop()