-- @description Vox Leveler
-- @version 1.0
-- @author DocShadrach
-- @about
--   Professional offline Vocal Rider that analyzes source audio and writes precise Take Volume automation.
--   Non-destructive workflow: always reads the original source file, allowing infinite re-adjustments.
--   Forces visual waveform updates immediately to show the resulting dynamic control.
--   Includes Smart Noise Gate to prevent boosting background noise or breaths during silent parts.
--   Features Lookahead detection, Target RMS, and configurable Max Boost/Cut limits.
--   Output stage controls: Amount (Wet/Dry) intensity and Output Make-Up Gain.
--   Bypass toggle (Before/After) for instant A/B comparison against the raw signal.
--   Robust "Hide Envelope" mode using direct Chunk manipulation for a clean view.
--   Modern ReaImGui interface with double-click reset and detailed tooltips.

local r = reaper

-- Check dependencies
if not r.APIExists('ImGui_GetVersion') then
  r.ShowMessageBox("This script requires ReaImGui.\nPlease install it via ReaPack.", "Error", 0)
  return
end

-- =========================================================
-- CONFIG & STATE
-- =========================================================
local ctx = r.ImGui_CreateContext('Vox Leveler')

local DEFAULTS = {
  target_db    = -18.0,
  window_ms    = 40,
  lookahead_ms = 5,
  gate_db      = -50.0,
  max_boost    = 6.0,
  max_cut      = -12.0,
  amount       = 100, -- 100% Wet
  out_gain     = 0.0,
  show_tooltips = true,
  hide_env      = false, -- Default: Visible
  bypass        = false  -- Default: Processed
}

local params = {
  target_db    = DEFAULTS.target_db,
  window_ms    = DEFAULTS.window_ms,
  lookahead_ms = DEFAULTS.lookahead_ms,
  gate_db      = DEFAULTS.gate_db,
  max_boost    = DEFAULTS.max_boost,
  max_cut      = DEFAULTS.max_cut,
  amount       = DEFAULTS.amount,
  out_gain     = DEFAULTS.out_gain,
  show_tooltips = DEFAULTS.show_tooltips,
  hide_env     = DEFAULTS.hide_env,
  bypass       = DEFAULTS.bypass
}

local TOOLTIPS = {
  target    = "Target RMS level.\nThe script calculates gain to bring the audio closer to this volume.",
  gate      = "Noise Gate Threshold.\nAudio below this level is IGNORED (Gain = 0dB).\nPrevents boosting background noise.",
  window    = "Analysis Resolution.\n- Lower (10-20ms): Fast, aggressive.\n- Higher (100ms+): Smooth, averaging.",
  lookahead = "Pre-Attack Time.\nWrites the volume change slightly BEFORE the peak happens.\nCrucial for catching transients.",
  boost     = "Max allowed Boost (Clamp Upper).",
  cut       = "Max allowed Cut (Clamp Lower).",
  amount    = "Intensity (Wet/Dry).\n- 100%: Full correction.\n- 50%: Half correction.\n- 0%: No correction.",
  out       = "Output Make-Up Gain.\nStatic boost/cut applied AFTER leveling.\nOnly applied when the Gate is Open (signal present).",
  btn       = "CALCULATE NEW CURVE.\n(Also automatically turns OFF Bypass so you can hear the result).",
  hide      = "FORCE HIDE ENVELOPE.\nUnchecks the 'Visible' box via internal Chunk data.\nAutomation stays ACTIVE, but the line disappears for a clean view.",
  bypass    = "BEFORE / AFTER COMPARE.\n- Checked: Envelope DISABLED (Hear Original).\n- Unchecked: Envelope ACTIVE (Hear Vox Leveler)."
}

-- Math Helpers
local function ValFromdB(dB_val) return 10 ^ (dB_val / 20) end
local function dBFromVal(val) 
  if val <= 0.00000002 then return -150.0 end
  return 20 * math.log(val, 10) 
end

-- =========================================================
-- GUI HELPERS (Sliders with Double-Click Reset)
-- =========================================================
local function DrawSliderDouble(ctx, label, val, v_min, v_max, format, default_val, tooltip)
  local changed, new_val = r.ImGui_SliderDouble(ctx, label, val, v_min, v_max, format)
  if r.ImGui_IsItemHovered(ctx) then
    if r.ImGui_IsMouseDoubleClicked(ctx, 0) then
      new_val = default_val
      changed = true
    end
    if params.show_tooltips and tooltip then r.ImGui_SetTooltip(ctx, tooltip .. "\n\n(Double-click to reset)") end
  end
  return changed, new_val
end

local function DrawSliderInt(ctx, label, val, v_min, v_max, default_val, tooltip)
  local changed, new_val = r.ImGui_SliderInt(ctx, label, val, v_min, v_max)
  if r.ImGui_IsItemHovered(ctx) then
    if r.ImGui_IsMouseDoubleClicked(ctx, 0) then
      new_val = default_val
      changed = true
    end
    if params.show_tooltips and tooltip then r.ImGui_SetTooltip(ctx, tooltip .. "\n\n(Double-click to reset)") end
  end
  return changed, new_val
end

-- =========================================================
-- CORE LOGIC
-- =========================================================

-- Ensures the option "Show media item peaks adjusted by take volume envelope" is ON
function EnsureVisualPeaksOn()
  local cmd_id = 40698 
  if r.GetToggleCommandState(cmd_id) == 0 then
    r.Main_OnCommand(cmd_id, 0)
  end
end

-- Directly modifies the Item Chunk to set Envelope Active state and Visibility
-- This bypasses API limitations regarding the "Visible" checkbox.
function SetEnvelopeState(env, visible, bypassed)
  local retval, chunk = r.GetEnvelopeStateChunk(env, "", false)
  if not retval then return end
  
  -- 1. Set Active State (ACT)
  -- Bypassed = ACT 0, Active = ACT 1
  local target_act = bypassed and "0" or "1"
  chunk = string.gsub(chunk, "ACT %d", "ACT " .. target_act)
  
  -- 2. Set Visibility (VIS)
  -- Hidden = VIS 0, Visible = VIS 1
  local target_vis = visible and "1" or "0"
  chunk = string.gsub(chunk, "VIS %d", "VIS " .. target_vis)
  
  r.SetEnvelopeStateChunk(env, chunk, false)
end

-- Exclusive function for the Bypass/Hide checkboxes (updates state without re-calculating audio)
function ToggleBypassState()
  local item = r.GetSelectedMediaItem(0, 0)
  if not item then return end
  local take = r.GetActiveTake(item)
  if not take then return end
  
  local env = r.GetTakeEnvelopeByName(take, "Volume")
  if env then
    SetEnvelopeState(env, not params.hide_env, params.bypass)
    r.UpdateArrange()
  end
end

-- Main Processing Function
function ProcessItem()
  local item = r.GetSelectedMediaItem(0, 0)
  if not item then r.ShowMessageBox("Select an audio item.", "Vox Leveler", 0) return end
  local take = r.GetActiveTake(item)
  if not take or r.TakeIsMIDI(take) then return end

  -- AUTO-DISABLE BYPASS ON APPLY (So user hears the result immediately)
  params.bypass = false

  r.Undo_BeginBlock()
  r.PreventUIRefresh(1)
  
  EnsureVisualPeaksOn()
  
  -- Ensure Envelope exists (Try SWS first)
  r.Main_OnCommand(r.NamedCommandLookup("_S&M_TAKEENV1"), 0) 
  
  local env = r.GetTakeEnvelopeByName(take, "Volume")
  if not env then
    -- Fallback to native toggle
    r.Main_OnCommand(40693, 0)
    env = r.GetTakeEnvelopeByName(take, "Volume")
  end
  
  if not env then
    r.PreventUIRefresh(-1)
    r.Undo_EndBlock("Vox Leveler Error", -1)
    return 
  end

  -- Clear previous automation points
  local item_len = r.GetMediaItemInfo_Value(item, "D_LENGTH")
  r.DeleteEnvelopePointRange(env, 0, item_len + 10)
  
  -- Insert anchor points (Start/End)
  r.InsertEnvelopePoint(env, 0, ValFromdB(0), 0, 0, false, true)
  r.InsertEnvelopePoint(env, item_len, ValFromdB(0), 0, 0, false, true)

  -- Setup Audio Accessor (Reads Source Audio)
  local accessor = r.CreateTakeAudioAccessor(take)
  local src = r.GetMediaItemTake_Source(take)
  local num_channels = r.GetMediaSourceNumChannels(src)
  local sample_rate = 44100
  
  local window_sec = params.window_ms / 1000
  local lookahead_sec = params.lookahead_ms / 1000
  if window_sec < 0.001 then window_sec = 0.001 end

  local samples_per_window = math.floor(sample_rate * window_sec)
  local buffer = r.new_array(samples_per_window * num_channels)
  local pos = 0
  
  local intensity_factor = params.amount / 100.0

  -- ANALYSIS LOOP
  while pos < item_len do
    local retval = r.GetAudioAccessorSamples(accessor, sample_rate, num_channels, pos, samples_per_window, buffer)
    if retval > 0 then
      local sum_sq = 0
      local cnt = 0
      local t = buffer.table()
      for i = 1, #t do sum_sq = sum_sq + (t[i] * t[i]); cnt = cnt + 1 end
      
      if cnt > 0 then
        local rms = math.sqrt(sum_sq / cnt)
        local rms_db = dBFromVal(rms)
        local gain_db = 0
        
        -- Logic: Gate -> Target -> Limits -> Amount -> Output Gain
        if rms_db >= params.gate_db then
           local raw_gain = params.target_db - rms_db
           
           -- Clamping
           if raw_gain > params.max_boost then raw_gain = params.max_boost end
           if raw_gain < params.max_cut then raw_gain = params.max_cut end
           
           -- Intensity & Output
           gain_db = (raw_gain * intensity_factor) + params.out_gain
        else
           -- Silence
           gain_db = 0 
        end

        local write_pos = pos - lookahead_sec
        if write_pos < 0 then write_pos = 0 end
        if write_pos <= item_len then
          r.InsertEnvelopePoint(env, write_pos, ValFromdB(gain_db), 0, 0, false, true)
        end
      end
    end
    pos = pos + window_sec
  end

  r.DestroyAudioAccessor(accessor)
  r.Envelope_SortPoints(env)

  -- Apply Visibility and Activation State (Always Active on Apply)
  SetEnvelopeState(env, not params.hide_env, false) 

  r.PreventUIRefresh(-1)
  r.UpdateArrange()
  r.Undo_EndBlock("Apply Vox Leveler", -1)
end

-- =========================================================
-- GUI MAIN LOOP
-- =========================================================
local function Loop()
  local visible, open = r.ImGui_Begin(ctx, 'Vox Leveler', true, r.ImGui_WindowFlags_AlwaysAutoResize())
  if visible then
    -- Style Adjustment (Larger Padding)
    r.ImGui_PushStyleVar(ctx, r.ImGui_StyleVar_FramePadding(), 6, 6) 
    r.ImGui_PushStyleVar(ctx, r.ImGui_StyleVar_ItemSpacing(), 8, 10)

    -- HEADER: OPTIONS
    local _
    _, params.show_tooltips = r.ImGui_Checkbox(ctx, "Tooltips", params.show_tooltips)
    r.ImGui_SameLine(ctx)
    
    local prev_hide = params.hide_env
    _, params.hide_env = r.ImGui_Checkbox(ctx, "Hide Envelope Line", params.hide_env)
    if params.hide_env ~= prev_hide then ToggleBypassState() end -- Refresh visibility immediately
    
    if params.show_tooltips and r.ImGui_IsItemHovered(ctx) then r.ImGui_SetTooltip(ctx, TOOLTIPS.hide) end
    
    -- SECTION 1: ANALYSIS
    r.ImGui_SeparatorText(ctx, "Analysis")
    local rv 
    rv, params.target_db = DrawSliderDouble(ctx, 'Target (dB)', params.target_db, -60.0, 0.0, '%.1f dB', DEFAULTS.target_db, TOOLTIPS.target)
    rv, params.gate_db = DrawSliderDouble(ctx, 'Gate Thresh', params.gate_db, -80.0, -10.0, '%.1f dB', DEFAULTS.gate_db, TOOLTIPS.gate)
    rv, params.window_ms = DrawSliderInt(ctx, 'Window (ms)', params.window_ms, 1, 500, DEFAULTS.window_ms, TOOLTIPS.window)
    rv, params.lookahead_ms = DrawSliderInt(ctx, 'Lookahead (ms)', params.lookahead_ms, 0, 200, DEFAULTS.lookahead_ms, TOOLTIPS.lookahead)

    -- SECTION 2: LIMITS
    r.ImGui_SeparatorText(ctx, "Limits")
    rv, params.max_boost = DrawSliderDouble(ctx, 'Max Boost', params.max_boost, 0.0, 24.0, '+%.1f dB', DEFAULTS.max_boost, TOOLTIPS.boost)
    rv, params.max_cut = DrawSliderDouble(ctx, 'Max Cut', params.max_cut, -60.0, 0.0, '%.1f dB', DEFAULTS.max_cut, TOOLTIPS.cut)

    -- SECTION 3: OUTPUT
    r.ImGui_SeparatorText(ctx, "Output")
    rv, params.amount = DrawSliderInt(ctx, 'Amount (%)', params.amount, 0, 100, DEFAULTS.amount, TOOLTIPS.amount)
    rv, params.out_gain = DrawSliderDouble(ctx, 'Output Gain', params.out_gain, -12.0, 12.0, '%+.1f dB', DEFAULTS.out_gain, TOOLTIPS.out)

    r.ImGui_Spacing(ctx)
    r.ImGui_Separator(ctx)
    r.ImGui_Spacing(ctx)

    -- BYPASS CHECKBOX
    local prev_bypass = params.bypass
    _, params.bypass = r.ImGui_Checkbox(ctx, "BYPASS (Hear Original)", params.bypass)
    if params.bypass ~= prev_bypass then ToggleBypassState() end -- Refresh active state immediately
    if params.show_tooltips and r.ImGui_IsItemHovered(ctx) then r.ImGui_SetTooltip(ctx, TOOLTIPS.bypass) end

    -- APPLY BUTTON
    local w = r.ImGui_GetContentRegionAvail(ctx)
    if r.ImGui_Button(ctx, 'APPLY / UPDATE', w, 50) then ProcessItem() end
    if params.show_tooltips and r.ImGui_IsItemHovered(ctx) then r.ImGui_SetTooltip(ctx, TOOLTIPS.btn) end

    r.ImGui_PopStyleVar(ctx, 2)
    r.ImGui_End(ctx)
  end
  if open then r.defer(Loop) end
end

r.defer(Loop)
