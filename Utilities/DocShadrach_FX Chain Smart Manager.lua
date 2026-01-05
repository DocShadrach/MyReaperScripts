-- @description FX Chain Smart Manager
-- @version 1.0
-- @author DocShadrach
-- @about
--   Smart FX Chain browser that filters files based on Track Names within a 2-level hierarchy.
--   Supports dynamic categorization using any tag inside brackets (e.g., [EQ], [SAT], [CLEAN]).
--   Features [GEN] tag inheritance: chains in parent folders appear in all sub-category tracks.
--   Global RECURRENT chains: files in the root Importer folder are available for every track.
--   Toggle switches to show/hide RECURRENT and GENERAL [GEN] chains independently.
--   Interactive Drag & Drop with precise multi-plugin insertion between existing FX.
--   Includes per-FX deletion, content preview tooltips, and track-color matched interface.

local ctx = reaper.ImGui_CreateContext('FX_Chain_Smart_Manager')
local FONT = reaper.ImGui_CreateFont('sans-serif', 16)
reaper.ImGui_Attach(ctx, FONT)

local OS_SEP = package.config:sub(1,1)
local FX_CHAINS_PATH = reaper.GetResourcePath() .. OS_SEP .. "FXChains"
local IMPORTER_PATH = FX_CHAINS_PATH .. OS_SEP .. "Importer" .. OS_SEP

local available_chains = {}
local current_track_fx = {}
local last_track_guid = ""
local last_track_name = ""
local current_track_color = 0x4DA6FFFF 
local show_gen_chains = true 
local show_recurrent_chains = true

-- --- HELPER: CONVERT NATIVE COLOR TO IMGUI ---
local function get_imgui_track_color(track)
  local native_color = reaper.GetTrackColor(track)
  if native_color == 0 then return 0x4DA6FFFF end
  local r, g, b = reaper.ColorFromNative(native_color)
  return (r << 24) | (g << 16) | (b << 8) | 0xFF
end

-- --- HELPER: PARSE RFXCHAIN CONTENT ---
local function get_plugins_in_chain(path)
  local file = io.open(path, "r")
  if not file then return "Error: Could not read file" end
  local plugins = {}
  for line in file:lines() do
    local name = line:match('<%w+%s+"([^"]+)"')
    if name then
      name = name:match(":.+: (.+)") or name:match(": (.+)") or name
      table.insert(plugins, "- " .. name)
    end
  end
  file:close()
  return #plugins == 0 and "Empty Chain" or table.concat(plugins, "\n")
end

-- --- CORE: MULTI-PLUGIN INSERTION ---
local function smart_insert(track, full_path, target_idx)
  local relative_path = full_path:sub(#FX_CHAINS_PATH + 2)
  
  reaper.Undo_BeginBlock()
  reaper.PreventUIRefresh(1)
  
  local count_before = reaper.TrackFX_GetCount(track)
  -- Always add to the end first to ensure all plugins in the .RfxChain are loaded
  reaper.TrackFX_AddByName(track, relative_path, false, -1)
  
  local count_after = reaper.TrackFX_GetCount(track)
  local num_added = count_after - count_before
  
  -- Move the block of new plugins only if they were added and a specific target index was provided
  if num_added > 0 and target_idx ~= -1 and target_idx < count_before then
    for i = 0, num_added - 1 do
      -- Sources are at the end, destination is the target gap
      reaper.TrackFX_CopyToTrack(track, count_before + i, track, target_idx + i, true)
    end
  end
  
  reaper.PreventUIRefresh(-1)
  reaper.Undo_EndBlock("Insert FX Chain", -1)
end

-- --- DISK SCAN ---
local function get_chains_from_path(path, flag_type)
  local chains = {}
  local i = 0
  while true do
    local file = reaper.EnumerateFiles(path, i)
    if not file then break end
    if file:lower():match("%.rfxchain$") then
      local full_path = path .. OS_SEP .. file
      table.insert(chains, {
        name = file:gsub("%.[Rr]fx[Cc]hain$", ""), 
        path = full_path,
        content = get_plugins_in_chain(full_path),
        type = flag_type
      })
    end
    i = i + 1
  end
  return chains
end

local function scan_importer(track_name)
  if track_name == "" then return {} end
  local search = track_name:upper():gsub("[%s%-_]+", "")
  local results = {}
  
  -- 1. Root Scan
  local root_files = get_chains_from_path(IMPORTER_PATH, "RECURRENT")
  for _, c in ipairs(root_files) do table.insert(results, c) end

  -- 2. Hierarchy Scan
  local i = 0
  while true do
    local dir = reaper.EnumerateSubdirectories(IMPORTER_PATH, i)
    if not dir then break end
    local p1 = IMPORTER_PATH .. dir
    
    if dir:upper():gsub("[%s%-_]+", "") == search then
      local list = get_chains_from_path(p1, "NORMAL")
      for _, c in ipairs(list) do table.insert(results, c) end
    end
    
    local j = 0
    while true do
      local subdir = reaper.EnumerateSubdirectories(p1, j)
      if not subdir then break end
      if subdir:upper():gsub("[%s%-_]+", "") == search then
        local list = get_chains_from_path(p1 .. OS_SEP .. subdir, "NORMAL")
        for _, c in ipairs(list) do table.insert(results, c) end
        local gen_list = get_chains_from_path(p1, "NORMAL")
        for _, c in ipairs(gen_list) do 
            if c.name:upper():find("[GEN]", 1, true) then table.insert(results, c) end
        end
      end
      j = j + 1
    end
    i = i + 1
  end
  return results
end

local function refresh_data()
  local track = reaper.GetSelectedTrack(0, 0)
  if not track then 
    available_chains, current_track_fx, last_track_guid = {}, {}, ""
    return 
  end
  local guid = reaper.GetTrackGUID(track)
  local _, name = reaper.GetTrackName(track)
  current_track_color = get_imgui_track_color(track)
  if guid ~= last_track_guid or name ~= last_track_name then
    available_chains = scan_importer(name)
    last_track_guid, last_track_name = guid, name
  end
  current_track_fx = {}
  for i = 0, reaper.TrackFX_GetCount(track) - 1 do
    local _, fx_name = reaper.TrackFX_GetFXName(track, i, "")
    fx_name = fx_name:match(":.+: (.+)") or fx_name:match(": (.+)") or fx_name
    table.insert(current_track_fx, { name = fx_name, index = i })
  end
end

-- --- UI ---
local function render_chain_item(track, chain, display_name)
  reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_Text(), 0x4DA6FFFF)
  reaper.ImGui_Selectable(ctx, display_name, false)
  reaper.ImGui_PopStyleColor(ctx)
  if reaper.ImGui_IsItemHovered(ctx) then
    reaper.ImGui_BeginTooltip(ctx)
    reaper.ImGui_Text(ctx, "Contents:")
    reaper.ImGui_TextColored(ctx, 0xAAAAAAFF, chain.content)
    reaper.ImGui_EndTooltip(ctx)
  end
  if reaper.ImGui_BeginDragDropSource(ctx) then
    reaper.ImGui_SetDragDropPayload(ctx, "FX_PATH", chain.path)
    reaper.ImGui_Text(ctx, "Insert: " .. display_name)
    reaper.ImGui_EndDragDropSource(ctx)
  end
  if reaper.ImGui_IsItemHovered(ctx) and reaper.ImGui_IsMouseDoubleClicked(ctx, 0) then
    smart_insert(track, chain.path, -1)
  end
end

local function draw_drop_gap(track, reaper_idx)
  reaper.ImGui_PushID(ctx, "gap_" .. reaper_idx)
  reaper.ImGui_InvisibleButton(ctx, "##gap", -1, 8)
  if reaper.ImGui_BeginDragDropTarget(ctx) then
    local dl = reaper.ImGui_GetWindowDrawList(ctx)
    local x, y = reaper.ImGui_GetItemRectMin(ctx)
    local w, h = reaper.ImGui_GetItemRectSize(ctx)
    reaper.ImGui_DrawList_AddRectFilled(dl, x, y + h/2 - 1, x + w, y + h/2 + 1, 0xFF00FFFF)
    local rv, payload = reaper.ImGui_AcceptDragDropPayload(ctx, "FX_PATH")
    if rv then smart_insert(track, tostring(payload), reaper_idx) end
    reaper.ImGui_EndDragDropTarget(ctx)
  end
  reaper.ImGui_PopID(ctx)
end

function loop()
  refresh_data()
  reaper.ImGui_PushFont(ctx, FONT, 16)
  reaper.ImGui_SetNextWindowSize(ctx, 900, 500, reaper.ImGui_Cond_FirstUseEver())
  local visible, open = reaper.ImGui_Begin(ctx, 'FX Chain Smart Manager', true, reaper.ImGui_WindowFlags_NoScrollbar())

  if visible then
    local track = reaper.GetSelectedTrack(0, 0)
    reaper.ImGui_TextColored(ctx, current_track_color, "SELECTED TRACK: " .. (last_track_name ~= "" and last_track_name or "NONE"))
    
    reaper.ImGui_SameLine(ctx)
    reaper.ImGui_SetCursorPosX(ctx, reaper.ImGui_GetWindowWidth(ctx) - 340)
    local c1, v1 = reaper.ImGui_Checkbox(ctx, "Show GEN", show_gen_chains)
    if c1 then show_gen_chains = v1 end
    reaper.ImGui_SameLine(ctx)
    local c2, v2 = reaper.ImGui_Checkbox(ctx, "Show RECURRENT", show_recurrent_chains)
    if c2 then show_recurrent_chains = v2 end

    reaper.ImGui_Separator(ctx)

    if track then
      local table_flags = reaper.ImGui_TableFlags_Resizable() | reaper.ImGui_TableFlags_BordersInnerV() | reaper.ImGui_TableFlags_ScrollY()
      local avail_h = reaper.ImGui_GetContentRegionAvail(ctx)

      if reaper.ImGui_BeginTable(ctx, "main_ui", 2, table_flags, 0, avail_h) then
        reaper.ImGui_TableSetupColumn(ctx, "Track FX Chain")
        reaper.ImGui_TableSetupColumn(ctx, "Available (Importer)")
        reaper.ImGui_TableHeadersRow(ctx)
        reaper.ImGui_TableNextRow(ctx)

        -- LEFT COLUMN: CORRECTED GAP INDEXING
        reaper.ImGui_TableSetColumnIndex(ctx, 0)
        if reaper.ImGui_BeginChild(ctx, "left_pane", 0, 0, 1) then
          -- Gap 0: Before the first FX
          draw_drop_gap(track, 0)
          
          for i, fx in ipairs(current_track_fx) do
            reaper.ImGui_PushID(ctx, "fx_row_" .. i)
            local avail_w = reaper.ImGui_GetContentRegionAvail(ctx)
            reaper.ImGui_Selectable(ctx, (fx.index + 1) .. ": " .. fx.name, false, 0, avail_w - 30)
            reaper.ImGui_SameLine(ctx, avail_w - 25)
            reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_Text(), 0xFF5555FF)
            if reaper.ImGui_SmallButton(ctx, "X") then reaper.TrackFX_Delete(track, fx.index) end
            reaper.ImGui_PopStyleColor(ctx)
            reaper.ImGui_PopID(ctx)
            
            -- GAP FIX: Slot index should be the CURRENT FX index + 1
            draw_drop_gap(track, fx.index + 1)
          end
          reaper.ImGui_EndChild(ctx)
        end

        -- RIGHT COLUMN
        reaper.ImGui_TableSetColumnIndex(ctx, 1)
        if reaper.ImGui_BeginChild(ctx, "right_pane", 0, 0, 1) then
          local cats = {}
          local sorted_tags = {}
          local has_visible_tags = false
          
          for _, chain in ipairs(available_chains) do
            local tag = chain.name:match("%[(.-)%]")
            local clean_name = chain.name
            local group_name = "MISC"
            if chain.type == "RECURRENT" then
                if show_recurrent_chains then group_name = "RECURRENT" has_visible_tags = true end
            elseif tag then
                local tag_upper = tag:upper()
                if tag_upper == "GEN" then
                    if show_gen_chains then group_name = "GENERAL" has_visible_tags = true else group_name = nil end
                else group_name = tag_upper has_visible_tags = true end
            end
            if group_name then
                if tag then clean_name = chain.name:gsub("%[.-%]", ""):gsub("^%s*(.-)%s*$", "%1") end
                if not cats[group_name] then cats[group_name] = {} end
                table.insert(cats[group_name], {orig = chain, clean = clean_name})
            end
          end

          if not has_visible_tags then
            for k, items in pairs(cats) do for _, item in ipairs(items) do render_chain_item(track, item.orig, item.clean) end end
          else
            if cats["RECURRENT"] then table.insert(sorted_tags, "RECURRENT") end
            local alpha_tags = {}
            for k, _ in pairs(cats) do if k ~= "MISC" and k ~= "GENERAL" and k ~= "RECURRENT" then table.insert(alpha_tags, k) end end
            table.sort(alpha_tags)
            for _, v in ipairs(alpha_tags) do table.insert(sorted_tags, v) end
            if cats["MISC"] then table.insert(sorted_tags, "MISC") end
            if cats["GENERAL"] then table.insert(sorted_tags, "GENERAL") end
            
            for _, t in ipairs(sorted_tags) do
              reaper.ImGui_SetNextItemOpen(ctx, true, 1)
              reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_Text(), 0xFFCC00FF)
              local is_open = reaper.ImGui_TreeNode(ctx, t .. " (" .. #cats[t] .. ")")
              reaper.ImGui_PopStyleColor(ctx)
              if is_open then
                for _, item in ipairs(cats[t]) do render_chain_item(track, item.orig, item.clean) end
                reaper.ImGui_TreePop(ctx)
              end
            end
          end
          reaper.ImGui_EndChild(ctx)
        end
        reaper.ImGui_EndTable(ctx)
      end
    else
      reaper.ImGui_TextDisabled(ctx, "Please select a track in REAPER...")
    end
    reaper.ImGui_End(ctx)
  end
  reaper.ImGui_PopFont(ctx)
  if open then reaper.defer(loop) end
end

loop()
