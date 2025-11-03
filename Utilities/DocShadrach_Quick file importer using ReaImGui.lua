-- @description Track-by-track file importer with folder hierarchy, track colors, import button, folder level filter, name-based track hide, color-based track filter, and existing files confirmation
-- @version 1.10
-- @author DocShadrach

local ctx = reaper.ImGui_CreateContext('Quick File Importer')
local FONT = reaper.ImGui_CreateFont('sans-serif', 16)
reaper.ImGui_Attach(ctx, FONT)

local tracks = {}
local assignments = {}  -- track_ptr -> list of files
local selected_track = nil
local selected_files = {}
local folder_path = ""
local file_tree = {}
local hide_levels = 0  -- number of folder levels to hide

-- Variables for Shift multi-selection
local last_selected_file_index = nil  -- Index of last selected file
local file_list_flat = {}  -- Flat list of all files for range selection

-- Variables for Undo functionality
local undo_history = {}  -- Stack to store previous states
local max_history_size = 10  -- Maximum number of undo steps to keep

-- Variables for Drag & Drop functionality
local drag_anchor = {}  -- To avoid garbage collection
local drag_selected_files = {}  -- Store selected files for drag & drop

-- Save current state to history (both selections and assignments)
local function save_undo_state()
  -- Create deep copies of both selected_files and assignments
  local state_copy = {
    selected_files = {},
    assignments = {}
  }
  
  -- Copy selected_files
  for _, file in ipairs(selected_files) do
    table.insert(state_copy.selected_files, file)
  end
  
  -- Copy assignments (deep copy)
  for track_ptr, files in pairs(assignments) do
    state_copy.assignments[track_ptr] = {}
    for _, file in ipairs(files) do
      table.insert(state_copy.assignments[track_ptr], file)
    end
  end
  
  -- Add to history stack
  table.insert(undo_history, state_copy)
  
  -- Limit history size
  if #undo_history > max_history_size then
    table.remove(undo_history, 1)
  end
end

-- Undo last change (both selections and assignments)
local function undo_last_action()
  if #undo_history > 0 then
    -- Get the last saved state
    local previous_state = table.remove(undo_history)
    
    -- Restore the previous selection
    selected_files = {}
    for _, file in ipairs(previous_state.selected_files) do
      table.insert(selected_files, file)
    end
    
    -- Restore the previous assignments
    assignments = {}
    for track_ptr, files in pairs(previous_state.assignments) do
      assignments[track_ptr] = {}
      for _, file in ipairs(files) do
        table.insert(assignments[track_ptr], file)
      end
    end
  end
end

-- DEFAULT FILTERS - Replace these values with your preferred defaults
local hide_names_input = ""  -- initial default
local hidden_colors = {}  -- table to store hidden track colors

-- ============================================================
-- PASTE THE CLIPBOARD HERE!
-- ============================================================
-- When you click "Copy State", paste the clipboard content here (in the next line):

-- ============================================================

local hide_names = {}  -- table with names to hide
local pre_show_only_state = {}  -- store state before "Show Only" was applied
local show_only_selected_color = nil  -- track the currently selected "Show Only" color
local isolated_track = nil  -- track that is currently isolated (double-clicked)
local isolation_stack = {}  -- stack to track nested isolation
local original_track_names = {}  -- store original track names for restoration

-------------------------------------------------------------
-- FUNCTIONS
-------------------------------------------------------------

-- Parse hide_names_input into table
local function parse_hide_names()
  hide_names = {}
  for name in hide_names_input:gmatch("[^,]+") do
    name = name:gsub("^%s*(.-)%s*$", "%1") -- trim spaces
    if name ~= "" then table.insert(hide_names, name) end
  end
end

-- Refresh the list of tracks with hierarchy level
local function refresh_tracks()
  tracks = {}
  local count = reaper.CountTracks(0)
  local depth = 0
  for i = 0, count - 1 do
    local track = reaper.GetTrack(0, i)
    local _, name = reaper.GetTrackName(track)
    local folder_depth = reaper.GetMediaTrackInfo_Value(track, "I_FOLDERDEPTH")
    table.insert(tracks, {ptr = track, name = name, level = depth})
    depth = depth + folder_depth
    if depth < 0 then depth = 0 end
  end
end

-- Recursively scan folder and build tree
local function scan_folder(path)
  local tree = {}
  local i = 0
  while true do
    local file = reaper.EnumerateFiles(path, i)
    if not file then break end
    if file:match("%.wav$") or file:match("%.flac$") or file:match("%.mp3$") then
      table.insert(tree, {name = file, path = path .. "/" .. file, type = "file"})
    end
    i = i + 1
  end
  i = 0
  while true do
    local folder = reaper.EnumerateSubdirectories(path, i)
    if not folder then break end
    local sub_tree = scan_folder(path .. "/" .. folder)
    table.insert(tree, {name = folder, type = "folder", children = sub_tree})
    i = i + 1
  end
  return tree
end

-- Build flat list of all files for range selection
local function build_flat_file_list(node, list)
  for _, item in ipairs(node) do
    if item.type == "folder" then
      build_flat_file_list(item.children, list)
    else
      table.insert(list, item)
    end
  end
end

local function refresh_file_tree()
  if folder_path ~= "" then
    file_tree = scan_folder(folder_path)
    -- Reset flat file list when folder changes
    file_list_flat = {}
    build_flat_file_list(file_tree, file_list_flat)
  else
    file_tree = {}
    file_list_flat = {}
  end
end

local function remove_fades(item)
  reaper.SetMediaItemInfo_Value(item, "D_FADEINLEN", 0)
  reaper.SetMediaItemInfo_Value(item, "D_FADEOUTLEN", 0)
end

-- Check if a track already has media items
local function track_has_existing_items(track)
  local item_count = reaper.CountTrackMediaItems(track)
  return item_count > 0
end

-- Get existing takes from a track
local function get_existing_takes(track)
  local takes = {}
  local item_count = reaper.CountTrackMediaItems(track)
  for i = 0, item_count - 1 do
    local item = reaper.GetTrackMediaItem(track, i)
    local take_count = reaper.CountTakes(item)
    for j = 0, take_count - 1 do
      local take = reaper.GetTake(item, j)
      local source = reaper.GetMediaItemTake_Source(take)
      local filename = reaper.GetMediaSourceFileName(source, "")
      if filename and filename ~= "" then
        table.insert(takes, filename:match("[^/\\]+$") or filename)
      end
    end
  end
  return takes
end

-- Create media items and takes for a track based on assigned files
local function create_items_for_track(track, file_list, replace_existing)
  if replace_existing then
    -- Remove all existing items from track
    local item_count = reaper.CountTrackMediaItems(track)
    for i = item_count - 1, 0, -1 do
      local item = reaper.GetTrackMediaItem(track, i)
      reaper.DeleteTrackMediaItem(track, item)
    end
  end
  
  if #file_list == 1 then
    -- Verify file exists before importing
    local file = io.open(file_list[1], "r")
    if file then
      file:close()
      local item = reaper.AddMediaItemToTrack(track)
      reaper.SetMediaItemPosition(item, 0, false)
      remove_fades(item)
      local take = reaper.AddTakeToMediaItem(item)
      -- Use PCM_Source_CreateFromFile for better reliability
      local source = reaper.PCM_Source_CreateFromFile(file_list[1])
      if source then
        reaper.SetMediaItemTake_Source(take, source)
        local length = reaper.GetMediaSourceLength(source)
        reaper.SetMediaItemLength(item, length, false)
      else
        -- Fallback to BR_SetTakeSourceFromFile
        reaper.BR_SetTakeSourceFromFile(take, file_list[1], false)
        local length = reaper.GetMediaSourceLength(reaper.GetMediaItemTake_Source(take))
        reaper.SetMediaItemLength(item, length, false)
      end
    else
      reaper.ShowMessageBox("File not found: " .. file_list[1], "Import Error", 0)
    end
  else
    local item = reaper.AddMediaItemToTrack(track)
    reaper.SetMediaItemPosition(item, 0, false)
    remove_fades(item)
    local max_length = 0
    
    for _, path in ipairs(file_list) do
      -- Verify file exists before importing
      local file = io.open(path, "r")
      if file then
        file:close()
        local take = reaper.AddTakeToMediaItem(item)
        local source = reaper.PCM_Source_CreateFromFile(path)
        if source then
          reaper.SetMediaItemTake_Source(take, source)
          local length = reaper.GetMediaSourceLength(source)
          if length > max_length then max_length = length end
        else
          reaper.BR_SetTakeSourceFromFile(take, path, false)
          local length = reaper.GetMediaSourceLength(reaper.GetMediaItemTake_Source(take))
          if length > max_length then max_length = length end
        end
      else
        reaper.ShowMessageBox("File not found: " .. path, "Import Error", 0)
      end
    end
    
    if max_length > 0 then
      reaper.SetMediaItemLength(item, max_length, false)
    end
  end
end

-- Add new takes to existing items without replacing
local function add_takes_to_existing_items(track, file_list)
  local item = reaper.GetTrackMediaItem(track, 0) -- Get first item
  if not item then
    -- If no items exist, create one
    item = reaper.AddMediaItemToTrack(track)
    reaper.SetMediaItemPosition(item, 0, false)
    remove_fades(item)
  end
  
  for _, path in ipairs(file_list) do
    -- Verify file exists before importing
    local file = io.open(path, "r")
    if file then
      file:close()
      local take = reaper.AddTakeToMediaItem(item)
      -- Use InsertMedia to ensure proper file import
      local source = reaper.PCM_Source_CreateFromFile(path)
      if source then
        reaper.SetMediaItemTake_Source(take, source)
        reaper.SetMediaItemTakeInfo_Value(take, "D_VOL", 1.0) -- Set volume to 100%
      else
        -- If PCM_Source_CreateFromFile fails, try BR_SetTakeSourceFromFile
        reaper.BR_SetTakeSourceFromFile(take, path, false)
      end
    else
      reaper.ShowMessageBox("File not found: " .. path, "Import Error", 0)
    end
  end
  
  -- Update item length based on the longest take
  local take_count = reaper.CountTakes(item)
  local max_length = 0
  for i = 0, take_count - 1 do
    local take = reaper.GetTake(item, i)
    local source = reaper.GetMediaItemTake_Source(take)
    if source then
      local length = reaper.GetMediaSourceLength(source)
      if length > max_length then max_length = length end
    end
  end
  if max_length > 0 then
    reaper.SetMediaItemLength(item, max_length, false)
  end
end

-- Force peak building for all items on a track using REAPER's refresh system
local function build_peaks_for_track(track)
  local item_count = reaper.CountTrackMediaItems(track)
  for i = 0, item_count - 1 do
    local item = reaper.GetTrackMediaItem(track, i)
    
    -- Force peak building by selecting and refreshing the item
    reaper.SetMediaItemSelected(item, true)
    
    -- Force take peak building
    local take_count = reaper.CountTakes(item)
    for j = 0, take_count - 1 do
      local take = reaper.GetTake(item, j)
      local source = reaper.GetMediaItemTake_Source(take)
      if source then
        -- Force peak building by accessing properties
        reaper.GetMediaSourceLength(source)
        reaper.GetMediaSourceSampleRate(source)
      end
    end
    
    -- Deselect the item
    reaper.SetMediaItemSelected(item, false)
  end
  
  -- Force complete REAPER refresh
  reaper.UpdateArrange()
  reaper.UpdateTimeline()
  
  -- Additional refresh commands to ensure peaks are built
  reaper.Main_OnCommand(40047, 0) -- Track: Toggle show peaks for selected tracks
  reaper.Main_OnCommand(40047, 0) -- Toggle back to ensure peaks are visible
  
  -- Force another UI refresh
  reaper.UpdateArrange()
  reaper.UpdateTimeline()
end

-- Import all assigned files to their respective tracks with confirmation for existing files
local function import_assignments()
  reaper.Undo_BeginBlock()
  reaper.PreventUIRefresh(1)
  
  local processed_tracks = {}
  
  -- Create sorted list of assignments by track position in REAPER (same as display order)
  local sorted_assignments = {}
  for track, file_list in pairs(assignments) do
    -- Find the track position in the REAPER track list
    local track_position = -1
    for i, tr in ipairs(tracks) do
      if tr.ptr == track then
        track_position = i
        break
      end
    end
    local _, track_name = reaper.GetTrackName(track)
    table.insert(sorted_assignments, {
      track = track,
      track_name = track_name,
      file_list = file_list,
      position = track_position
    })
  end
  
  -- Sort assignments by track position (top to bottom in REAPER)
  table.sort(sorted_assignments, function(a, b)
    return a.position < b.position
  end)
  
  -- Process assignments in track order
  for _, assignment in ipairs(sorted_assignments) do
    local track = assignment.track
    local file_list = assignment.file_list
    local track_name = assignment.track_name
    
    if track_has_existing_items(track) then
      -- Track has existing items, ask user what to do
      local existing_takes = get_existing_takes(track)
      
      local message = "TRACK: " .. track_name .. "\n\n"
      message = message .. "EXISTING FILES (" .. #existing_takes .. "):\n"
      for i, take in ipairs(existing_takes) do
        message = message .. "• " .. take .. "\n"
      end
      message = message .. "\nNEW FILES TO IMPORT (" .. #file_list .. "):\n"
      for i, file in ipairs(file_list) do
        message = message .. "• " .. file:match("[^/\\]+$") .. "\n"
      end
      message = message .. "\nWhat do you want to do with this track?\n\n"
      message = message .. "YES = Add as new takes (keep existing files)\n"
      message = message .. "NO = Replace all existing files\n"
      message = message .. "CANCEL = Skip this track and continue with others"
      
      -- Use standard Yes/No/Cancel buttons
      local result = reaper.ShowMessageBox(message, "Existing Files Found - " .. track_name, 3)
      
      if result == 6 then -- Yes = Add as new takes
        reaper.ShowMessageBox("Adding files as new takes to track: " .. track_name, "Importing", 0)
        add_takes_to_existing_items(track, file_list)
        build_peaks_for_track(track)  -- Force peak building
        processed_tracks[track] = true
      elseif result == 7 then -- No = Replace existing files
        reaper.ShowMessageBox("Replacing existing files in track: " .. track_name, "Importing", 0)
        create_items_for_track(track, file_list, true)
        build_peaks_for_track(track)  -- Force peak building
        processed_tracks[track] = true
      else -- Cancel or close dialog = Skip this track
        reaper.ShowMessageBox("Skipping track: " .. track_name, "Importing", 0)
        -- Do nothing for this track, continue with others
      end
    else
      -- Track is empty, create items normally
      create_items_for_track(track, file_list, false)
      build_peaks_for_track(track)  -- Force peak building
      processed_tracks[track] = true
    end
  end
  
  reaper.PreventUIRefresh(-1)
  reaper.Undo_EndBlock("Import Assigned Files", -1)
  
  -- Force complete UI refresh and peak building
  reaper.UpdateArrange()
  reaper.UpdateTimeline()
  
  -- Additional peak building for all processed tracks
  for track, _ in pairs(processed_tracks) do
    build_peaks_for_track(track)
  end
  
  assignments = {}  -- Clear all after import
end

local function nativeColorToRGB(native_color)
  if native_color == 0 then return 0.5, 0.5, 0.5 end
  local r = (native_color & 0xFF) / 255
  local g = ((native_color >> 8) & 0xFF) / 255
  local b = ((native_color >> 16) & 0xFF) / 255
  return r, g, b
end

-- Get all unique track colors from currently visible tracks, ordered by track position
local function get_unique_track_colors()
  local colors = {}
  local color_order = {}  -- To maintain order
  
  for _, tr in ipairs(tracks) do
    -- Check if track still exists and is valid
    if reaper.ValidatePtr(tr.ptr, "MediaTrack*") then
      -- Check if track would be visible (not filtered by name or level)
      local skip = false
      for _, name in ipairs(hide_names) do
        local escaped_name = name:gsub("([%^%$%(%)%%%.%[%]%*%+%-%?])", "%%%1")
        if tr.name:match(escaped_name) then
          skip = true
          break
        end
      end
      
      if not skip and tr.level >= hide_levels then
        local color = reaper.GetTrackColor(tr.ptr)
        if not colors[color] then
          colors[color] = true
          table.insert(color_order, color)
        end
      end
    end
  end
  return colors, color_order
end

-- Get the top-left track name for a given color (the highest and leftmost track with that color)
local function get_track_name_for_color(color)
  local top_track_name = nil
  local top_track_level = math.huge  -- Start with a very high level
  
  for _, tr in ipairs(tracks) do
    -- Check if track still exists and is valid
    if reaper.ValidatePtr(tr.ptr, "MediaTrack*") then
      local track_color = reaper.GetTrackColor(tr.ptr)
      if track_color == color then
        -- Check if this track is higher (lower level) or at the same level but earlier in the list
        if tr.level < top_track_level then
          top_track_name = tr.name
          top_track_level = tr.level
        elseif tr.level == top_track_level then
          -- If same level, keep the first one we found (leftmost)
          if not top_track_name then
            top_track_name = tr.name
          end
        end
      end
    end
  end
  
  return top_track_name or "Unknown"
end

-- Get colors only from tracks that are currently visible (after all filters), ordered by track position
local function get_visible_track_colors()
  local colors = {}
  local color_order = {}  -- To maintain order
  
  for _, tr in ipairs(tracks) do
    -- Check if track still exists and is valid
    if reaper.ValidatePtr(tr.ptr, "MediaTrack*") then
      local skip = false
      
      -- Check name filter
      for _, name in ipairs(hide_names) do
        local escaped_name = name:gsub("([%^%$%(%)%%%.%[%]%*%+%-%?])", "%%%1")
        if tr.name:match(escaped_name) then
          skip = true
          break
        end
      end
      
      -- Check level filter
      if tr.level < hide_levels then
        skip = true
      end
      
      -- Check color filter
      local track_color = reaper.GetTrackColor(tr.ptr)
      if hidden_colors[track_color] then
        skip = true
      end
      
      if not skip then
        if not colors[track_color] then
          colors[track_color] = true
          table.insert(color_order, track_color)
        end
      end
    end
  end
  return colors, color_order
end

-- Copy current filter state to clipboard for easy code integration
local function copy_filter_state_to_clipboard()
  -- Build the clipboard content with proper Lua syntax
  local clipboard_content = ""
  
  -- Add hidden colors
  if next(hidden_colors) ~= nil then
    clipboard_content = clipboard_content .. "-- Hidden colors (paste in hidden_colors initialization)\n"
    clipboard_content = clipboard_content .. "local hidden_colors = {\n"
    for color, _ in pairs(hidden_colors) do
      clipboard_content = clipboard_content .. "  [" .. tostring(color) .. "] = true,\n"
    end
    clipboard_content = clipboard_content .. "}\n\n"
  else
    clipboard_content = clipboard_content .. "-- No hidden colors currently\n\n"
  end
  
  -- Add name filters
  if #hide_names > 0 then
    clipboard_content = clipboard_content .. "-- Name filters (paste in hide_names_input initialization)\n"
    clipboard_content = clipboard_content .. "local hide_names_input = \""
    for i, name in ipairs(hide_names) do
      if i > 1 then
        clipboard_content = clipboard_content .. ","
      end
      clipboard_content = clipboard_content .. name
    end
    clipboard_content = clipboard_content .. "\"\n\n"
  else
    clipboard_content = clipboard_content .. "-- No name filters currently\n\n"
  end
  
  -- Add track levels filter
  clipboard_content = clipboard_content .. "-- Track levels filter (paste in hide_levels initialization)\n"
  clipboard_content = clipboard_content .. "local hide_levels = " .. tostring(hide_levels) .. "\n"
  
  -- Copy to clipboard
  reaper.CF_SetClipboard(clipboard_content)
  
  -- Show confirmation message
  reaper.ShowMessageBox("Filter state copied to clipboard!\n\nEdit script code: Paste this in the marked section at the beginning of the script.", "Copy State", 0)
end

-- Reset all filters to default state (no filters)
local function reset_filter_state()
  -- Reset hidden colors
  hidden_colors = {}
  
  -- Reset name filters
  hide_names_input = ""
  parse_hide_names()
  
  -- Reset track levels filter
  hide_levels = 0
  
  -- Reset show only state
  show_only_selected_color = nil
  pre_show_only_state = {}
  
  -- Reset track isolation
  isolated_track = nil
  original_track_names = {}
  
  -- Show confirmation message
  reaper.ShowMessageBox("All filters have been reset to default state.", "Reset State", 0)
end

-- Toggle track isolation - show only the clicked track and its children
local function toggle_track_isolation(track_index)
  -- If we're already in isolation mode
  if isolated_track then
    -- If clicking the same track that's currently isolated, go back one level
    if isolated_track == track_index then
      -- Pop from the isolation stack
      if #isolation_stack > 0 then
        -- Restore previous isolation state
        isolated_track = table.remove(isolation_stack)
        -- Update the track name to show we're back to previous isolation
        for i, tr in ipairs(tracks) do
          if i == isolated_track then
            tr.name = original_track_names[tr.ptr] .. "-"
          else
            tr.name = original_track_names[tr.ptr]
          end
        end
      else
        -- No more isolation levels, restore all tracks
        isolated_track = nil
        -- Restore all original track names
        for i, tr in ipairs(tracks) do
          tr.name = original_track_names[tr.ptr]
        end
        original_track_names = {}
      end
    else
      -- We're isolating a new track within the current isolation
      -- Push current isolation to stack
      table.insert(isolation_stack, isolated_track)
      
      -- Set new isolation
      isolated_track = track_index
      
      -- Update track names for new isolation
      for i, tr in ipairs(tracks) do
        if i == isolated_track then
          tr.name = original_track_names[tr.ptr] .. "-"
        else
          tr.name = original_track_names[tr.ptr]
        end
      end
    end
  else
    -- No current isolation, start new isolation
    isolated_track = track_index
    
    -- Store original track names if not already stored
    if next(original_track_names) == nil then
      for i, tr in ipairs(tracks) do
        original_track_names[tr.ptr] = tr.name
      end
    end
    
    -- Add "-" suffix to the isolated track name
    tracks[track_index].name = tracks[track_index].name .. "-"
  end
end

-- Check if a track should be visible when isolation is active
local function should_show_track_in_isolation(track_index)
  if not isolated_track then return true end
  
  local isolated_track_ptr = tracks[isolated_track].ptr
  local isolated_level = tracks[isolated_track].level
  local current_track_ptr = tracks[track_index].ptr
  local current_level = tracks[track_index].level
  
  -- Show the isolated track itself
  if track_index == isolated_track then
    return true
  end
  
  -- Check if this track is a child, grandchild, etc. of the isolated track
  if current_level > isolated_level then
    -- Walk up the hierarchy to find if this track is a descendant of the isolated track
    local parent_level = current_level
    for i = track_index - 1, 1, -1 do
      if tracks[i].level < parent_level then
        -- Found a parent track
        if i == isolated_track then
          return true  -- Direct child of isolated track
        end
        -- Check if this parent is itself a child of the isolated track
        if tracks[i].level > isolated_level then
          parent_level = tracks[i].level
        else
          break  -- Reached a level equal to or above isolated track
        end
      end
    end
  end
  
  return false
end

local function show_tree(node)
  -- Build flat file list if not already built
  if #file_list_flat == 0 then
    build_flat_file_list(file_tree, file_list_flat)
  end
  
  -- Create a set of all assigned file paths for quick lookup
  local assigned_files = {}
  for _, file_list in pairs(assignments) do
    for _, file_path in ipairs(file_list) do
      assigned_files[file_path] = true
    end
  end
  
  for _, item in ipairs(node) do
    if item.type == "folder" then
      local tree_open = reaper.ImGui_TreeNode(ctx, item.name)
      if tree_open then
        show_tree(item.children)
        reaper.ImGui_TreePop(ctx)
      end
    else
      local is_selected = false
      for _, f in ipairs(selected_files) do
        if f == item.path then is_selected = true break end
      end
      
      -- Check if file is already assigned
      local is_assigned = assigned_files[item.path] or false
      
      -- Find the index of this file in the flat list
      local current_index = nil
      for i, flat_item in ipairs(file_list_flat) do
        if flat_item.path == item.path then
          current_index = i
          break
        end
      end
      
      reaper.ImGui_PushID(ctx, "file_" .. item.path)
      
      -- Set text color based on assignment status
      if is_assigned then
        reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_Text(), reaper.ImGui_ColorConvertDouble4ToU32(0.5, 0.5, 0.5, 1.0))  -- Gray for assigned files
      end
      
      if reaper.ImGui_Selectable(ctx, item.name, is_selected) then
        -- Save current state before making changes
        save_undo_state()
        
        local shift_pressed = reaper.ImGui_IsKeyDown(ctx, reaper.ImGui_Key_LeftShift()) or reaper.ImGui_IsKeyDown(ctx, reaper.ImGui_Key_RightShift())
        
        if shift_pressed and last_selected_file_index and current_index then
          -- Shift selection: select range between last selected and current
          local start_index = math.min(last_selected_file_index, current_index)
          local end_index = math.max(last_selected_file_index, current_index)
          
          -- Clear current selection and select the range
          selected_files = {}
          for i = start_index, end_index do
            if file_list_flat[i] then
              table.insert(selected_files, file_list_flat[i].path)
            end
          end
        else
          -- Normal click: toggle selection of single file
          local found = false
          for j, f in ipairs(selected_files) do
            if f == item.path then
              table.remove(selected_files, j)
              found = true
              break
            end
          end
          if not found then
            table.insert(selected_files, item.path)
          end
          
          -- Update last selected index for future shift selections
          last_selected_file_index = current_index
        end
      end
      
      -- Restore text color if we changed it
      if is_assigned then
        reaper.ImGui_PopStyleColor(ctx)
      end
      
      -- Drag & Drop source for individual files
      if reaper.ImGui_BeginDragDropSource(ctx) then
        drag_anchor.data = {item.path}
        reaper.ImGui_SetDragDropPayload(ctx, "FILE_DRAG", "file", 1)
        reaper.ImGui_Text(ctx, "Drag file: " .. item.name)
        reaper.ImGui_EndDragDropSource(ctx)
      end
      
      reaper.ImGui_PopID(ctx)
    end
  end
end

-- Tracks display with hierarchy, colors, level filter, name filter, and isolation
local function show_tracks_with_hierarchy()
  for i, tr in ipairs(tracks) do
    -- Check if track still exists and is valid
    if reaper.ValidatePtr(tr.ptr, "MediaTrack*") then
      local skip = false
      
      -- Check if track should be visible when isolation is active
      if isolated_track and not should_show_track_in_isolation(i) then
        skip = true
      end
      
      if not skip then
        for _, name in ipairs(hide_names) do
          -- Escape special characters in pattern matching to avoid errors
          local escaped_name = name:gsub("([%^%$%(%)%%%.%[%]%*%+%-%?])", "%%%1")
          if tr.name:match(escaped_name) then
            skip = true
            break
          end
        end
      end
      
      -- Check if track color is hidden
      local track_color = reaper.GetTrackColor(tr.ptr)
      if hidden_colors[track_color] then
        skip = true
      end
      
      if not skip and tr.level >= hide_levels then
        local indent_amount = (tr.level - hide_levels + 1) * 20
        reaper.ImGui_Indent(ctx, indent_amount)
        local color = reaper.GetTrackColor(tr.ptr)
        local r, g, b = nativeColorToRGB(color)
        reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_Text(), reaper.ImGui_ColorConvertDouble4ToU32(r, g, b, 1.0))
        -- Use unique ID for each track to avoid ImGui ID conflicts
        reaper.ImGui_PushID(ctx, tostring(tr.ptr))
        
        -- Show the track selectable
        reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_Text(), reaper.ImGui_ColorConvertDouble4ToU32(r, g, b, 1.0))
        if reaper.ImGui_Selectable(ctx, tr.name, selected_track == i) then
          selected_track = i
        end
        reaper.ImGui_PopStyleColor(ctx)
        
        -- Drag & Drop target for tracks
        if reaper.ImGui_BeginDragDropTarget(ctx) then
          local payload = reaper.ImGui_AcceptDragDropPayload(ctx, "FILE_DRAG")
          if payload then
            -- Save state before making assignments
            save_undo_state()
            
            -- Assign dragged files to this track
            local track_ptr = tr.ptr
            assignments[track_ptr] = assignments[track_ptr] or {}
            
            -- Check if we have selected files (multiple files drag)
            if #selected_files > 0 then
              -- Assign all selected files
              for _, file_path in ipairs(selected_files) do
                table.insert(assignments[track_ptr], file_path)
              end
              -- Clear file selection after successful drop
              selected_files = {}
            elseif drag_anchor.data then
              -- Assign single file from drag_anchor.data
              for _, file_path in ipairs(drag_anchor.data) do
                table.insert(assignments[track_ptr], file_path)
              end
            end
          end
          reaper.ImGui_EndDragDropTarget(ctx)
        end
        
        -- Handle double-click for track isolation
        if reaper.ImGui_IsItemHovered(ctx) and reaper.ImGui_IsMouseDoubleClicked(ctx, 0) then
          toggle_track_isolation(i)
        end
        
        reaper.ImGui_PopID(ctx)
        reaper.ImGui_PopStyleColor(ctx)
        reaper.ImGui_Unindent(ctx, indent_amount)
      end
    end
  end
end

-- Show color filter buttons
local function show_color_filter()
  local unique_colors, color_order = get_unique_track_colors()
  reaper.ImGui_Text(ctx, "Filter by track color:")
  
  -- Show all unique colors as toggle buttons in track position order
  local colors_shown = 0
  for _, color in ipairs(color_order) do
    local r, g, b = nativeColorToRGB(color)
    local is_hidden = hidden_colors[color] or false
    
    -- Always show the original color, but with reduced opacity when hidden
    if is_hidden then
      -- Show original color but with 40% opacity to indicate it's hidden
      reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_Button(), reaper.ImGui_ColorConvertDouble4ToU32(r, g, b, 0.4))
      reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_ButtonHovered(), reaper.ImGui_ColorConvertDouble4ToU32(r, g, b, 0.6))
      reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_ButtonActive(), reaper.ImGui_ColorConvertDouble4ToU32(r, g, b, 0.3))
    else
      -- Show full color when visible
      reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_Button(), reaper.ImGui_ColorConvertDouble4ToU32(r, g, b, 1.0))
      reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_ButtonHovered(), reaper.ImGui_ColorConvertDouble4ToU32(r * 1.2, g * 1.2, b * 1.2, 1.0))
      reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_ButtonActive(), reaper.ImGui_ColorConvertDouble4ToU32(r * 0.8, g * 0.8, b * 0.8, 1.0))
    end
    
    -- Create a small color square button
    reaper.ImGui_PushID(ctx, tostring(color))
    local button_label = "##color_" .. tostring(color)
    if is_hidden then
      button_label = "X##color_" .. tostring(color)  -- Add X when hidden
    end
    if reaper.ImGui_Button(ctx, button_label, 20, 20) then
      -- Toggle color visibility
      if hidden_colors[color] then
        hidden_colors[color] = nil
      else
        hidden_colors[color] = true
      end
    end
    reaper.ImGui_PopID(ctx)
    reaper.ImGui_PopStyleColor(ctx, 3)
    
    -- Add tooltip showing color status
    if reaper.ImGui_IsItemHovered(ctx) then
      reaper.ImGui_BeginTooltip(ctx)
      if is_hidden then
        reaper.ImGui_Text(ctx, "Hidden - Click to show")
      else
        reaper.ImGui_Text(ctx, "Visible - Click to hide")
      end
      reaper.ImGui_EndTooltip(ctx)
    end
    
    colors_shown = colors_shown + 1
    
    -- Arrange buttons in rows (5 per row)
    if colors_shown % 5 ~= 0 then
      reaper.ImGui_SameLine(ctx)
    end
  end
  
    -- Add "Show All" button and "Show Only" dropdown
  if colors_shown > 0 then
    reaper.ImGui_NewLine(ctx)
    if reaper.ImGui_Button(ctx, "Show All Colors") then
      hidden_colors = {}
      pre_show_only_state = {}  -- Clear pre-show-only state when showing all
    end
    
    reaper.ImGui_SameLine(ctx)
    reaper.ImGui_Text(ctx, "Show Only:")
    reaper.ImGui_SameLine(ctx)
    reaper.ImGui_SetNextItemWidth(ctx, 100)
    
    -- Get colors from currently visible tracks for the dropdown (ordered by track position)
    local visible_colors, visible_color_order = get_visible_track_colors()
    
    -- Create dropdown for "Show Only" single color selection
    local current_show_only = show_only_selected_color
    local visible_colors_count = 0
    for color, _ in pairs(visible_colors) do
      visible_colors_count = visible_colors_count + 1
    end
    
    -- If more than one color is visible, we're not in "show only" mode
    if visible_colors_count > 1 then
      current_show_only = nil
    end
    
    local combo_label = "---"
    if current_show_only then
      local track_name = get_track_name_for_color(current_show_only)
      combo_label = track_name
    end
    
    if reaper.ImGui_BeginCombo(ctx, "##show_only", combo_label) then
      -- Store pre-show-only state when dropdown opens (if not already stored)
      if next(pre_show_only_state) == nil then
        pre_show_only_state = {}
        for color, _ in pairs(hidden_colors) do
          pre_show_only_state[color] = true
        end
        -- If there were no previous filters, store an empty state to indicate no filters
        if next(pre_show_only_state) == nil then
          pre_show_only_state = {}  -- Empty table means no filters
        end
      end
      
      -- Add "---" option to restore pre-show-only state
      if reaper.ImGui_Selectable(ctx, "---", current_show_only == nil) then
        -- Clear the selected color
        show_only_selected_color = nil
        
        -- Restore the previous filter state from pre_show_only_state
        -- Check if we have the special marker for no filters
        if pre_show_only_state._no_filters then
          -- No filters were applied before, so clear all filters
          hidden_colors = {}
        else
          -- Restore the previous filter state
          hidden_colors = {}
          for color, _ in pairs(pre_show_only_state) do
            hidden_colors[color] = true
          end
        end
        
        pre_show_only_state = {}  -- Clear after restoring
        -- Force the dropdown to close and reopen to update selection
        reaper.ImGui_CloseCurrentPopup(ctx)
      end
      
      -- Add each visible color as an option in track position order
      for _, color in ipairs(visible_color_order) do
        local r, g, b = nativeColorToRGB(color)
        reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_Text(), reaper.ImGui_ColorConvertDouble4ToU32(r, g, b, 1.0))
        local track_name = get_track_name_for_color(color)
        local is_selected = (current_show_only == color)
        if reaper.ImGui_Selectable(ctx, track_name, is_selected) then
          -- Store current state as pre-show-only state BEFORE applying "Show Only"
          pre_show_only_state = {}
          for c, _ in pairs(hidden_colors) do
            pre_show_only_state[c] = true
          end
          -- If there were no previous filters, store a special marker to indicate no filters
          if next(pre_show_only_state) == nil then
            pre_show_only_state = {_no_filters = true}  -- Special marker for no filters
          end
          
          -- Set the selected color
          show_only_selected_color = color
          
          -- Hide all colors except the selected one
          hidden_colors = {}
          for c, _ in pairs(unique_colors) do
            if c ~= color then
              hidden_colors[c] = true
            end
          end
        end
        reaper.ImGui_PopStyleColor(ctx)
        
        if is_selected then
          reaper.ImGui_SetItemDefaultFocus(ctx)
        end
      end
      
      reaper.ImGui_EndCombo(ctx)
    end
  end
end

-------------------------------------------------------------
-- UI LOOP
-------------------------------------------------------------

local function main()
  -- Always refresh tracks to keep up with REAPER changes (undo, new tracks, etc.)
  refresh_tracks()
  
  reaper.ImGui_PushFont(ctx, FONT, 13)
  reaper.ImGui_SetNextWindowSize(ctx, 1000, 500, reaper.ImGui_Cond_FirstUseEver())
  local visible, open = reaper.ImGui_Begin(ctx, 'Quick File Importer', true, reaper.ImGui_WindowFlags_NoScrollbar())

  if not visible then
    -- If window is not visible, just clean up and return
    reaper.ImGui_PopFont(ctx)
    if open then
      reaper.defer(main)
    end
    return
  end

  -- Folder selection at the top
  if reaper.ImGui_Button(ctx, "Select Folder") then
    local retval, path = reaper.JS_Dialog_BrowseForFolder("Select a folder", "")
    if retval and path ~= "" then
      folder_path = path
      refresh_file_tree()
    end
  end
  reaper.ImGui_SameLine(ctx)
  reaper.ImGui_Text(ctx, folder_path)
  reaper.ImGui_Separator(ctx)

  -- Hide names input
  reaper.ImGui_Text(ctx, "Hide tracks containing (comma separated):")
  local changed, new_input = reaper.ImGui_InputText(ctx, "##hide_names", hide_names_input, 256)
  if changed then
    hide_names_input = new_input
    parse_hide_names()
  end
  reaper.ImGui_Separator(ctx)

  -- Color filter
  show_color_filter()
  reaper.ImGui_Separator(ctx)

  -- Folder level filter
  reaper.ImGui_Text(ctx, "Hide track levels up to:")
  reaper.ImGui_SameLine(ctx)
  reaper.ImGui_SetNextItemWidth(ctx, 40)  -- Make the combo box much smaller
  local combo_open = reaper.ImGui_BeginCombo(ctx, "##hidelevels", tostring(hide_levels))
  if combo_open then
    for i = 0, 3 do
      local is_selected = (hide_levels == i)
      if reaper.ImGui_Selectable(ctx, tostring(i), is_selected) then
        hide_levels = i
      end
      if is_selected then
        reaper.ImGui_SetItemDefaultFocus(ctx)
      end
    end
    reaper.ImGui_EndCombo(ctx)
  end
  reaper.ImGui_Separator(ctx)

  -- Copy State, Reset State, and Help buttons
  if reaper.ImGui_Button(ctx, "Copy State") then
    copy_filter_state_to_clipboard()
  end
  reaper.ImGui_SameLine(ctx)
  if reaper.ImGui_Button(ctx, "Reset State") then
    reset_filter_state()
  end
  reaper.ImGui_SameLine(ctx)
  
  -- Help button with question mark
  reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_Button(), reaper.ImGui_ColorConvertDouble4ToU32(0.2, 0.5, 0.8, 1.0))
  reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_ButtonHovered(), reaper.ImGui_ColorConvertDouble4ToU32(0.3, 0.6, 0.9, 1.0))
  reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_ButtonActive(), reaper.ImGui_ColorConvertDouble4ToU32(0.1, 0.4, 0.7, 1.0))
  if reaper.ImGui_Button(ctx, "?", 30, 20) then
    local help_message = [[
QUICK FILE IMPORTER - ADVANCED FEATURES

>> FILE SELECTION (SHIFT MULTI-SELECT)
• Click any file to select/deselect it
• Hold Shift + click another file to select range between them
• Perfect for selecting multiple consecutive files quickly
• Works across folder boundaries in the file tree

>> DRAG & DROP ASSIGNMENTS
• Drag individual files from Files column to any track
• Drag multiple selected files from Files column to any track
• Files are automatically assigned to the target track
• Works with Undo (Ctrl+Z) for easy mistake correction

>> TRACK ISOLATION (DOUBLE-CLICK MAGIC)
• Double-click any track to isolate it and its children
• Double-click again to go back through isolation levels
• Perfect for focusing on drum kits, vocal groups, etc.

>> COLOR FILTERING
• Click color squares to hide/show tracks by color
• Hidden colors show with reduced opacity and "X"
• "Show Only" dropdown focuses on single color groups
• Colors appear in track position order (top to bottom)

>> SMART FILTERING
• Name filter: Type comma-separated names to hide tracks
• Level filter: Hide tracks up to certain folder depths
• Combine filters to focus on specific track groups

>> ASSIGNMENT MANAGEMENT
• Red [x] buttons remove individual files from assignments
• Empty tracks are automatically cleaned up
• Assignments display in track position order

>> KEYBOARD SHORTCUTS
• Enter: Assign selected files to selected track
• Ctrl+Enter: Import all assignments immediately
• Esc: Deselect all files
• Ctrl+Z: Undo last file selection change

>> STATE MANAGEMENT
• "Copy State" saves current filters to clipboard
• Edit script code: Paste in the marked section
• "Reset State" clears all filters instantly

>> IMPORT OPTIONS
• Empty tracks: Multiple files become takes on one item
• Existing files: Choose to add, replace, or skip

Perfect for large mix templates! Use filters to focus on what matters.
]]
    reaper.ShowMessageBox(help_message, "Quick File Importer Help", 0)
  end
  reaper.ImGui_PopStyleColor(ctx, 3)
  
  reaper.ImGui_Separator(ctx)

  -- Keyboard shortcuts
  if reaper.ImGui_IsKeyPressed(ctx, reaper.ImGui_Key_Enter()) then
    if reaper.ImGui_IsKeyDown(ctx, reaper.ImGui_Key_LeftCtrl()) or reaper.ImGui_IsKeyDown(ctx, reaper.ImGui_Key_RightCtrl()) then
      -- Ctrl+Enter: Import assigned tracks immediately (shortcut for green button)
      import_assignments()
    else
      -- Enter: Assign selected files to selected track
      if selected_track and #selected_files > 0 then
        -- Save state before making assignments
        save_undo_state()
        
        local track_ptr = tracks[selected_track].ptr
        assignments[track_ptr] = assignments[track_ptr] or {}
        for _, f in ipairs(selected_files) do
          table.insert(assignments[track_ptr], f)
        end
        selected_files = {}
      end
    end
  end
  if reaper.ImGui_IsKeyPressed(ctx, reaper.ImGui_Key_Escape()) then
    selected_files = {}
  end
  if reaper.ImGui_IsKeyPressed(ctx, reaper.ImGui_Key_Z()) and 
     (reaper.ImGui_IsKeyDown(ctx, reaper.ImGui_Key_LeftCtrl()) or reaper.ImGui_IsKeyDown(ctx, reaper.ImGui_Key_RightCtrl())) then
    -- Ctrl+Z: Undo last selection change
    undo_last_action()
  end

  -- Main buttons
  if reaper.ImGui_Button(ctx, "Assign Selected Files (Enter)") then
    if selected_track and #selected_files > 0 then
      -- Save state before making assignments
      save_undo_state()
      
      local track_ptr = tracks[selected_track].ptr
      assignments[track_ptr] = assignments[track_ptr] or {}
      for _, f in ipairs(selected_files) do
        table.insert(assignments[track_ptr], f)
      end
      selected_files = {}
    end
  end
  reaper.ImGui_SameLine(ctx)
  if reaper.ImGui_Button(ctx, "Deselect Files (Esc)") then
    selected_files = {}
  end
  reaper.ImGui_SameLine(ctx)

  reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_Button(), reaper.ImGui_ColorConvertDouble4ToU32(0.1, 0.6, 0.1, 1.0))
  reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_ButtonHovered(), reaper.ImGui_ColorConvertDouble4ToU32(0.15, 0.7, 0.15, 1.0))
  reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_ButtonActive(), reaper.ImGui_ColorConvertDouble4ToU32(0.08, 0.5, 0.08, 1.0))
  if reaper.ImGui_Button(ctx, "Import Assignments (Ctrl+Enter)") then
    import_assignments()
  end
  reaper.ImGui_PopStyleColor(ctx, 3)

  reaper.ImGui_Separator(ctx)

  -- Fixed height for columns (not too tall, contained within main window)
  local column_height = 450  -- Fixed height for all columns
  
  -- Main table with three columns - each with fixed height and independent scrollbars
  local table_open = reaper.ImGui_BeginTable(ctx, "main_table", 3, reaper.ImGui_TableFlags_Resizable())
  if table_open then
    reaper.ImGui_TableSetupColumn(ctx, "Tracks", reaper.ImGui_TableColumnFlags_WidthStretch())
    reaper.ImGui_TableSetupColumn(ctx, "Files", reaper.ImGui_TableColumnFlags_WidthStretch())
    reaper.ImGui_TableSetupColumn(ctx, "Assignments", reaper.ImGui_TableColumnFlags_WidthStretch())
    reaper.ImGui_TableHeadersRow(ctx)

    reaper.ImGui_TableNextRow(ctx)
    
    -- Tracks column with fixed height and independent scrollbar
    reaper.ImGui_TableSetColumnIndex(ctx, 0)
    if reaper.ImGui_BeginChild(ctx, "tracks_child", 0, column_height) then
      show_tracks_with_hierarchy()
      reaper.ImGui_EndChild(ctx)
    end

  -- Files column with fixed height and independent scrollbar
  reaper.ImGui_TableSetColumnIndex(ctx, 1)
  if reaper.ImGui_BeginChild(ctx, "files_child", 0, column_height) then
    show_tree(file_tree)
    
    -- Drag & Drop source for selected files (multiple files)
    if #selected_files > 0 then
      reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_Button(), reaper.ImGui_ColorConvertDouble4ToU32(0.2, 0.5, 0.8, 0.3))
      reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_ButtonHovered(), reaper.ImGui_ColorConvertDouble4ToU32(0.3, 0.6, 0.9, 0.5))
      reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_ButtonActive(), reaper.ImGui_ColorConvertDouble4ToU32(0.1, 0.4, 0.7, 0.7))
      
      if reaper.ImGui_Button(ctx, "Drag selected files to tracks", -1, 0) then
        -- Button clicked (not used for drag, just for visual feedback)
      end
      
      -- Drag & Drop source for selected files
      if reaper.ImGui_BeginDragDropSource(ctx) then
        -- Store ALL selected files in global variable
        drag_selected_files = {}
        for _, file_path in ipairs(selected_files) do
          table.insert(drag_selected_files, file_path)
        end
        reaper.ImGui_SetDragDropPayload(ctx, "FILE_DRAG", "multiple_files", 1)
        if #selected_files == 1 then
          reaper.ImGui_Text(ctx, "Drag file: " .. selected_files[1]:match("[^/\\]+$"))
        else
          reaper.ImGui_Text(ctx, "Drag " .. tostring(#selected_files) .. " files")
        end
        reaper.ImGui_EndDragDropSource(ctx)
      end
      
      reaper.ImGui_PopStyleColor(ctx, 3)
    end
    
    reaper.ImGui_EndChild(ctx)
  end

    -- Assignments column with fixed height and independent scrollbar
    reaper.ImGui_TableSetColumnIndex(ctx, 2)
    if reaper.ImGui_BeginChild(ctx, "assignments_child", 0, column_height) then
      -- Create sorted list of assignments by track position in REAPER
      local sorted_assignments = {}
      for track_ptr, files in pairs(assignments) do
        -- Find the track position in the REAPER track list
        local track_position = -1
        for i, tr in ipairs(tracks) do
          if tr.ptr == track_ptr then
            track_position = i
            break
          end
        end
        local _, track_name = reaper.GetTrackName(track_ptr)
        table.insert(sorted_assignments, {
          track_ptr = track_ptr,
          track_name = track_name,
          files = files,
          position = track_position
        })
      end
      
      -- Sort assignments by track position (top to bottom in REAPER)
      table.sort(sorted_assignments, function(a, b)
        return a.position < b.position
      end)
      
      -- Display assignments in track order with delete buttons
      for _, assignment in ipairs(sorted_assignments) do
        reaper.ImGui_Text(ctx, assignment.track_name .. ":")
        for file_index, f in ipairs(assignment.files) do
          reaper.ImGui_PushID(ctx, tostring(assignment.track_ptr) .. "_" .. tostring(file_index))
          
          -- Create a small delete button
          reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_Button(), reaper.ImGui_ColorConvertDouble4ToU32(0.8, 0.2, 0.2, 1.0))
          reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_ButtonHovered(), reaper.ImGui_ColorConvertDouble4ToU32(0.9, 0.3, 0.3, 1.0))
          reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_ButtonActive(), reaper.ImGui_ColorConvertDouble4ToU32(0.7, 0.1, 0.1, 1.0))
          
          if reaper.ImGui_Button(ctx, "[x]", 30, 20) then
            -- Remove this specific file from the assignment
            table.remove(assignment.files, file_index)
            -- If no files left, remove the entire track assignment
            if #assignment.files == 0 then
              assignments[assignment.track_ptr] = nil
            end
          end
          
          reaper.ImGui_PopStyleColor(ctx, 3)
          reaper.ImGui_SameLine(ctx)
          
          -- Display the filename
          reaper.ImGui_Text(ctx, f:match("[^/\\]+$"))
          
          reaper.ImGui_PopID(ctx)
        end
      end
      reaper.ImGui_EndChild(ctx)
    end

    reaper.ImGui_EndTable(ctx)
  end

  reaper.ImGui_End(ctx)
  reaper.ImGui_PopFont(ctx)

  if open then
    reaper.defer(main)
  end
end

-------------------------------------------------------------
-- START
-------------------------------------------------------------
parse_hide_names()
refresh_tracks()
main()
