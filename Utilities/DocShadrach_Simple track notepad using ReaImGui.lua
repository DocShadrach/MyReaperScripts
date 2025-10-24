--@description Simple Track Notepad
--@version 1.1
--@author DocShadrach
--@noindex

local r = reaper

-- Check for ReaImGui
if not r.ImGui_CreateContext then
    r.ShowMessageBox("This script requires ReaImGui.", "Error", 0)
    return
end

-- Create ImGui context
local ctx = r.ImGui_CreateContext('Simple Track Notepad')

-- í ½í´¤ Load a larger global font (OPTION 2)
local font = r.ImGui_CreateFont('sans-serif', 18)
r.ImGui_Attach(ctx, font)

local text_content = ""
local window_open = true
local last_text = ""
local selected_track_name = "No Track Selected"
local tracks_with_notes = {}
local track_list_window_open = false

-- Get project path
local function getCurrentProjectPath()
    local _, project_path = reaper.EnumProjects(-1, "")
    if not project_path or project_path == "" then return nil end
    local proj_dir = project_path:match("(.*)[/\\]")
    return proj_dir
end

-- Get selected track name
local function getSelectedTrackName()
    local track = r.GetSelectedTrack(0, 0)
    if track then
        local _, track_name = r.GetTrackName(track)
        return track_name
    end
    return "No Track Selected"
end

-- Convert REAPER color to RGB
local function nativeColorToRGB(native_color)
    if native_color == 0 then return 0.5, 0.5, 0.5 end
    local r_ = (native_color & 0xFF) / 255
    local g_ = ((native_color >> 8) & 0xFF) / 255
    local b_ = ((native_color >> 16) & 0xFF) / 255
    return r_, g_, b_
end

-- Load notes for the selected track
local function loadNoteContent(track_name)
    local proj_path = getCurrentProjectPath()
    if not proj_path or not track_name then return "" end

    local file_path = proj_path .. "/project_notes.txt"
    local file = io.open(file_path, "r")
    if not file then return "" end

    local content = file:read("*all")
    file:close()

    -- Escape special characters in track_name for pattern matching
    local escaped_track_name = track_name:gsub("([%(%)%.%%%+%-%*%?%[%]%^%$])", "%%%1")
    local start_idx, end_idx = content:find("##" .. escaped_track_name)
    if not start_idx then return "" end

    local track_notes = content:sub(end_idx + 1)
    local end_track_idx = track_notes:find("##")
    if end_track_idx then
        track_notes = track_notes:sub(1, end_track_idx - 1)
    end

    -- Remove only trailing whitespace, preserve leading whitespace
    track_notes = track_notes:match("^(.-)%s*$")
    return track_notes
end

-- Retrieve all tracks with notes, filtering empty notes
local function getTracksWithNotes()
    local proj_path = getCurrentProjectPath()
    if not proj_path then return end

    local file_path = proj_path .. "/project_notes.txt"
    local file = io.open(file_path, "r")
    if not file then return end

    local content = file:read("*all")
    file:close()

    tracks_with_notes = {}
    for track_name in content:gmatch("##(.-)\n") do
        local note = loadNoteContent(track_name)
        if note and note ~= "" then
            table.insert(tracks_with_notes, track_name)
        end
    end
end

-- Save notes for the selected track
local function saveNoteContent(track_name, content)
    local proj_path = getCurrentProjectPath()
    if not proj_path or not track_name then
        r.ShowMessageBox("No project open or track selected.", "Error", 0)
        return
    end

    local file_path = proj_path .. "/project_notes.txt"
    local file = io.open(file_path, "r")
    local file_content = ""
    if file then
        file_content = file:read("*all")
        file:close()
    end

    -- Escape special characters in track_name for pattern matching
    local escaped_track_name = track_name:gsub("([%(%)%.%%%+%-%*%?%[%]%^%$])", "%%%1")
    local start_idx, end_idx = file_content:find("##" .. escaped_track_name)
    if start_idx then
        local new_content = file_content:sub(1, start_idx + #track_name + 2) .. content
        local next_track_idx = file_content:find("##", end_idx + 1)
        if next_track_idx then
            new_content = new_content .. file_content:sub(next_track_idx)
        end
        file = io.open(file_path, "w")
        file:write(new_content)
        file:close()
    else
        local new_content = file_content .. "\n##" .. track_name .. "\n" .. content
        file = io.open(file_path, "w")
        file:write(new_content)
        file:close()
    end

    getTracksWithNotes()
end

-- Delete notes for the selected track
local function deleteNoteContent(track_name)
    local proj_path = getCurrentProjectPath()
    if not proj_path or not track_name then
        r.ShowMessageBox("No project open or track selected.", "Error", 0)
        return
    end

    local file_path = proj_path .. "/project_notes.txt"
    local file = io.open(file_path, "r")
    local file_content = ""
    if file then
        file_content = file:read("*all")
        file:close()
    end

    -- Escape special characters in track_name for pattern matching
    local escaped_track_name = track_name:gsub("([%(%)%.%%%+%-%*%?%[%]%^%$])", "%%%1")
    local start_idx, end_idx = file_content:find("##" .. escaped_track_name)
    if start_idx then
        local next_track_idx = file_content:find("##", end_idx + 1)
        local new_content = ""
        if next_track_idx then
            new_content = file_content:sub(1, start_idx - 1) .. file_content:sub(next_track_idx)
        else
            new_content = file_content:sub(1, start_idx - 1)
        end
        file = io.open(file_path, "w")
        file:write(new_content)
        file:close()
    end

    getTracksWithNotes()
end

-- Select a specific track by name
local function selectTrackByName(track_name)
    r.Main_OnCommand(40297, 0) -- Unselect all tracks
    for i = 0, r.CountTracks(0) - 1 do
        local track = r.GetTrack(0, i)
        local _, name = r.GetTrackName(track)
        if name == track_name then
            r.SetTrackSelected(track, true)
            break
        end
    end
end

-- Clean up empty notes
local function cleanupEmptyNotes()
    local proj_path = getCurrentProjectPath()
    if not proj_path then return end

    local file_path = proj_path .. "/project_notes.txt"
    local file = io.open(file_path, "r")
    if not file then return end

    local content = file:read("*all")
    file:close()

    local new_content = ""
    for track_name in content:gmatch("##(.-)\n") do
        local note = loadNoteContent(track_name)
        if note and note ~= "" then
            new_content = new_content .. "##" .. track_name .. "\n" .. note .. "\n"
        end
    end

    file = io.open(file_path, "w")
    file:write(new_content)
    file:close()
end

-- Load initial content
selected_track_name = getSelectedTrackName()
text_content = loadNoteContent(selected_track_name)
last_text = text_content
getTracksWithNotes()

-- Main loop
local function loop()
    if not window_open then
        cleanupEmptyNotes()
        return
    end

    local main_window_x, main_window_y
    local main_window_w, main_window_h
    local new_selected_track_name = getSelectedTrackName()

    if selected_track_name ~= new_selected_track_name then
        selected_track_name = new_selected_track_name
        text_content = loadNoteContent(selected_track_name)
        last_text = text_content
    end

    local track = r.GetSelectedTrack(0, 0)
    local track_color = 0
    if track then
        track_color = r.GetTrackColor(track)
    end
    local r_col, g_col, b_col = nativeColorToRGB(track_color)

    r.ImGui_PushFont(ctx, font, 14) -- Apply larger font globally

    r.ImGui_SetNextWindowSize(ctx, 600, 400, r.ImGui_Cond_FirstUseEver())
    local visible, open = r.ImGui_Begin(ctx, 'Track Notepad', true)
    window_open = open

    if visible then
        main_window_x, main_window_y = r.ImGui_GetWindowPos(ctx)
        main_window_w, main_window_h = r.ImGui_GetWindowSize(ctx)

        if main_window_x and main_window_y and main_window_w and main_window_h then
            r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Text(), r.ImGui_ColorConvertDouble4ToU32(r_col, g_col, b_col, 1.0))
            r.ImGui_Text(ctx, "Track: " .. selected_track_name)
            r.ImGui_PopStyleColor(ctx)

            local windowWidth, windowHeight = r.ImGui_GetContentRegionAvail(ctx)
            local flags = r.ImGui_InputTextFlags_AllowTabInput()

            -- Calculate dynamic bottom space for buttons and reminder text
            local button_height = 22
            local spacing = 3
            local reminder_height = 20
            local bottom_space = 10 + button_height + spacing + button_height + spacing + reminder_height

            local rv, new_text = r.ImGui_InputTextMultiline(ctx, '##content', text_content, windowWidth, windowHeight - bottom_space, flags)

            if rv then
                text_content = new_text
                if #new_text > #last_text and new_text:sub(-1) == "\n" then
                    saveNoteContent(selected_track_name, new_text)
                end
                last_text = new_text
            end

            if r.ImGui_Button(ctx, "Clear Note") then
                deleteNoteContent(selected_track_name)
                text_content = ""
                last_text = ""
            end

            r.ImGui_TextWrapped(ctx, "REMEMBER: Always press Enter to save the note")

            if r.ImGui_Button(ctx, track_list_window_open and "Hide Tracks with Notes" or "Show Tracks with Notes") then
                track_list_window_open = not track_list_window_open
            end
        end
    end

    if visible then r.ImGui_End(ctx) end

    if track_list_window_open then
        if main_window_w and main_window_h then
            r.ImGui_SetNextWindowPos(ctx, main_window_x + main_window_w + 2, main_window_y, 1)
            
            -- Calculate dynamic height based on number of tracks
            local track_count = #tracks_with_notes
            local track_height = 30  -- Increased height for larger font
            local header_height = 40  -- Space for window title and padding
            local dynamic_height = math.min(track_count * track_height + header_height, main_window_h)
            
            -- Set window size with dynamic height and let auto-resize handle the rest
            r.ImGui_SetNextWindowSize(ctx, 180, dynamic_height, r.ImGui_Cond_FirstUseEver())

            local visible, open = r.ImGui_Begin(ctx, 'Tracks w/ Notes', true, r.ImGui_WindowFlags_AlwaysAutoResize())
            track_list_window_open = open

            if visible then
                for _, track_name in ipairs(tracks_with_notes) do
                    if r.ImGui_Button(ctx, track_name) then
                        selectTrackByName(track_name)
                        text_content = loadNoteContent(track_name)
                        last_text = text_content
                    end
                end
            end

            if visible then r.ImGui_End(ctx) end
        end
    end

    r.ImGui_PopFont(ctx)
    r.defer(loop)
end

-- Start the loop
r.defer(loop)
