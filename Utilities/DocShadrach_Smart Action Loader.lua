-- @description Smart Action Loader
-- @author DocShadrach
-- @version 1.0
-- @about 
--   Background engine that monitors 'Smart Action Button' JSFX instances.
--   It executes the actions assigned via the 'Smart Action Manager' script.
--   Note: Add this script to your SWS Global/Project Startup Actions to ensure it runs automatically.

local r = reaper

-- CONFIGURATION
local EXT_SECTION = "DocShadrach_SmartActions"
local EXT_KEY     = "MapData"
local JSFX_NAME   = "Smart Action Button" -- Partial match for the JSFX name

-- LOGIC: Retrieve Action ID from Project Data
local function GetActionForButton(btn_index)
    local retval, data = r.GetProjExtState(0, EXT_SECTION, EXT_KEY)
    if retval == 1 and data ~= "" then
        -- Parse format "index:ID|"
        for idx, id in data:gmatch("(%d+):([^|]+)") do
            if tonumber(idx) == btn_index then return id end
        end
    end
    return nil
end

-- LOGIC: Trigger Event
local function handle_trigger(track, fx_idx)
    -- Get Button ID from JSFX Slider 2 (Index 1)
    local button_id = math.floor(r.TrackFX_GetParam(track, fx_idx, 1))
    
    -- Lookup Assigned Action
    local cmd_id_str = GetActionForButton(button_id)
    
    if cmd_id_str and cmd_id_str ~= "" then
        local cmd_int = r.NamedCommandLookup(cmd_id_str)
        if cmd_int ~= 0 then 
            r.Main_OnCommand(cmd_int, 0) 
        else
            r.ShowConsoleMsg("\n[Smart Loader] Error: Command ID '" .. cmd_id_str .. "' not found.\n")
        end
    else
        r.ShowConsoleMsg("\n[Smart Loader] Button " .. button_id .. " pressed but NO ACTION assigned.\n")
        r.ShowConsoleMsg("Run 'DocShadrach_Smart Action Manager' to assign actions.\n")
    end
    
    -- Reset JSFX Trigger (Slider 1 / Index 0) -> Turns off the green light
    r.TrackFX_SetParam(track, fx_idx, 0, 0)
end

-- MAIN LOOP
local function scan_loop()
    local num_tracks = r.CountTracks(0)
    for i = 0, num_tracks - 1 do
        local track = r.GetTrack(0, i)
        if track then
            local fx_count = r.TrackFX_GetCount(track)
            for j = 0, fx_count - 1 do
                -- Efficient Name Check
                local retval, buf = r.TrackFX_GetFXName(track, j, "")
                if buf:find(JSFX_NAME) then
                    -- Check Trigger Slider (Index 0)
                    if r.TrackFX_GetParam(track, j, 0) > 0.5 then
                        handle_trigger(track, j)
                    end
                end
            end
        end
    end
    r.defer(scan_loop)
end

r.defer(scan_loop)