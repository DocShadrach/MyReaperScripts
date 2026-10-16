-- @description Vox Leveler 2
-- @version 1.0
-- @author DocShadrach
-- @about
--   Offline vocal rider. Reads the selected take and writes a gain curve into the Take Volume
--   envelope so the vocal rides towards a target loudness.
--
--   The gain of each block comes from the loudest level in the look-ahead window ahead of it, so
--   the correction is in place before the peak arrives. Fast attack, slow release.
--
--   Reads the source, never the written envelope, so Apply can be run repeatedly.
--   One undo step per Apply.
--
--   Requires ReaImGui (ReaPack > ReaTeam Extensions).

local r = reaper

if not r.APIExists('ImGui_CreateContext') then
  r.ShowMessageBox('This script requires ReaImGui.\nInstall it with ReaPack (ReaTeam Extensions).',
                   'Vox Leveler 2', 0)
  return
end

local SCRIPT      = 'Vox Leveler 2'
local EXT_SECTION = 'VoxLeveler2'

local CMD_PEAKS   = 40698   -- peaks: adjust by take volume envelope
local CMD_TAKEVOL = 40693   -- toggle take volume envelope

local DB_FLOOR     = -150.0
local POINT_BUDGET = 6000
local MAX_BLOCKS   = 400000

local MODES = { 'Tight', 'Natural', 'Smooth' }
local MODE_RELEASE = { Tight = 4, Natural = 8, Smooth = 14 }

local DEF = {
  level     = -18.0,
  amount    = 100,
  speed     = 50,
  range_up  = 6.0,
  range_down = -12.0,
  output    = 0.0,
  mode      = 'Natural',
  gate      = -55.0,
  auto_gate = true,
  hide_env  = false,
}

local P = {}
for k, v in pairs(DEF) do P[k] = v end

local INT_KEYS = { speed = true, amount = true }

local function clamp(v, lo, hi) return math.max(lo, math.min(hi, v)) end

local function load_settings()
  for k, def in pairs(DEF) do
    local ok, value = r.GetProjExtState(0, EXT_SECTION, k)
    if ok == 1 and value ~= '' then
      if type(def) == 'boolean' then
        P[k] = (value == '1')
      elseif type(def) == 'number' then
        local num = tonumber(value)
        -- SliderInt needs an integer; a float from a hand-edited project state throws
        if num then P[k] = INT_KEYS[k] and (math.tointeger(math.floor(num + 0.5)) or def) or num end
      else
        P[k] = value
      end
    end
  end
  P.speed = clamp(P.speed, 0, 100)
  P.amount = clamp(P.amount, 0, 100)
  P.level = clamp(P.level, -40, 0)
  P.range_up = clamp(P.range_up, 0, 24)
  P.range_down = clamp(P.range_down, -40, 0)
  P.output = clamp(P.output, -12, 12)
  P.gate = clamp(P.gate, -80, -10)
  if P.mode ~= 'Tight' and P.mode ~= 'Natural' and P.mode ~= 'Smooth' then P.mode = DEF.mode end
end

local function save_settings()
  for k, v in pairs(P) do
    r.SetProjExtState(0, EXT_SECTION, k, type(v) == 'boolean' and (v and '1' or '0') or tostring(v))
  end
end

local TIP = {
  level  = 'How loud the vocal should sit.\nEvery analysed block is moved towards this level.',
  amount = 'Wet/dry. How much of the calculated correction is written.\n100% full, 50% half, 0% none.',
  speed  = 'How fast the rider reacts.\nSets the look-ahead window, the cut speed and the recovery time together.\nLow: broad, gentle moves. High: follows every word and writes more points.',
  up     = 'Maximum gain the rider may add.',
  down   = 'Maximum gain reduction the rider may apply.',
  output = 'Static trim added to every written point.',
  mode   = 'How the gain recovers.\nTight recovers quickly. Smooth holds the level across phrases.',
  gate   = 'Below this a block counts as silence.\nQuiet words under the gate are left alone rather than boosted.',
  autog  = 'Take the gate threshold from the material instead of setting it by hand.',
  hide   = 'Hide the envelope line in the arrange view.\nThe automation stays active.',
  bypass = 'Hear the take without the written automation.\nChecked: the envelope is disabled, so you can A/B against the raw take.',
  auto   = 'Re-apply one second after a control stops moving.',
}

local auto_update = true
local auto_at = 0
local run_now = false
local window_open = true
local status = 'Select an audio item and press Apply.'
local status_bad = false

local function db_to_val(db) return 10 ^ (db / 20) end

local function val_to_db(v)
  if not v or v <= 0.00000002 then return DB_FLOOR end
  return 20 * math.log(v, 10)
end

-- =========================================================
-- envelope
-- =========================================================

local function find_envelope(take)
  if not take then return nil end
  return r.GetTakeEnvelopeByName(take, 'Volume')
end

local function env_get(env, key)
  local ok, value = r.GetSetEnvelopeInfo_String(env, key, '', false)
  if not ok then return nil end
  return value == '1'
end

local function env_set(env, key, value)
  return r.GetSetEnvelopeInfo_String(env, key, value and '1' or '0', true)
end

-- 40693 acts on the focused item
local function get_or_create_envelope(take, item)
  local env = find_envelope(take)
  if env then return env end

  local restore = r.GetSelectedMediaItem(0, 0)
  r.SetCursorContext(1, nil)
  r.Main_OnCommand(CMD_TAKEVOL, 0)

  env = r.GetTakeEnvelopeByName(take, 'Volume')
  if env then return env end

  if restore and r.ValidatePtr(restore, 'MediaItem*') then r.SetMediaItemSelected(restore, true) end
  return nil, 'Could not create a Take Volume envelope for this take.'
end

local function show_peaks()
  if r.GetToggleCommandState(CMD_PEAKS) == 0 then
    r.Main_OnCommand(CMD_PEAKS, 0)
    return true
  end
  return false
end

local function restore_peaks(was_off)
  if was_off then r.Main_OnCommand(CMD_PEAKS, 0) end
end

-- =========================================================
-- rider
-- =========================================================

-- Speed 0..100. Block stays short so the look-ahead spans several of them.
local function rider_times(speed)
  local s = clamp(speed, 0, 100) / 100
  return {
    block_sec = 0.015 + s * 0.025,    -- 15 .. 40 ms
    lookahead = 0.020 + s * 0.180,    -- 20 .. 200 ms
    attack    = 0.004 + s * 0.030,    -- 4 .. 30 ms
  }
end

-- 35 dB under the loud parts, raised when that would sit on the noise floor
local function auto_gate_db(levels)
  local sorted = {}
  for i = 1, #levels do sorted[i] = levels[i] end
  table.sort(sorted)
  local n = #sorted
  if n == 0 then return DB_FLOOR end
  local loud = sorted[math.max(1, math.floor(n * 0.95))] or DB_FLOOR
  local floor = sorted[math.max(1, math.floor(n * 0.10))] or DB_FLOOR
  if loud <= DB_FLOOR + 1 then return DB_FLOOR end
  return math.min(loud - 6, math.max(loud - 35, floor + 6))
end

-- levels[i] is dBFS of block i. Returns gains[] and whether anything opened.
local function build_gains(levels, opt)
  local n = #levels
  local gains = {}
  for i = 1, n do gains[i] = 1.0 end

  local gate = opt.gate
  if opt.auto_gate then gate = auto_gate_db(levels) end

  -- levels are dB, so the loudest block in the window is the maximum
  local hold = math.max(1, math.floor(opt.lookahead / opt.block_sec + 0.5))

  -- opens just above the gate, closes hyst under it
  local hyst = math.max(0.5, opt.hyst or 3.0)
  local open = {}
  local any_open = false
  local state = false
  for i = 1, n do
    if state then
      if levels[i] < gate - hyst then state = false end
    elseif levels[i] > gate then
      state = true
    end
    open[i] = state
    if state then any_open = true end
  end
  if not any_open then return gains, false end

  local held = {}
  for i = 1, n do
    if not open[i] then
      held[i] = DB_FLOOR
    else
      local loudest = levels[i]
      local last = math.min(n, i + hold)
      for k = i + 1, last do
        if levels[k] > loudest then loudest = levels[k] end
      end
      held[i] = loudest
    end
  end

  -- one-pole; fast to cut, slow to recover. A closed block is driven to unity by the same release
  local release = opt.attack * opt.release_mul
  local out_db = {}

  local function target_for(i)
    if not open[i] then return 0.0 end
    local g = opt.level - held[i]
    if g > opt.range_up then g = opt.range_up end
    if g < opt.range_down then g = opt.range_down end
    return g
  end

  local current = target_for(1)
  out_db[1] = current
  for i = 2, n do
    local target = target_for(i)
    local tc = (target < current) and opt.attack or release
    local coeff = 1 - math.exp(-opt.block_sec / math.max(tc, 1e-6))
    current = current + (target - current) * coeff
    out_db[i] = current
  end

  for i = 1, n do
    gains[i] = db_to_val(out_db[i] * opt.amount / 100 + opt.output)
  end

  return gains, true
end

-- drops points the straight line between their neighbours already describes
local function decimate(times, values, tol)
  local n = #times
  if n <= 2 then return times, values end
  local out_t, out_v = { times[1] }, { values[1] }
  local last = 1
  for i = 2, n - 1 do
    local t0, v0 = times[last], values[last]
    local t1, v1 = times[i + 1], values[i + 1]
    local dt = t1 - t0
    if dt <= 0 then
      out_t[#out_t + 1], out_v[#out_v + 1] = times[i], values[i]
      last = i
    else
      local interp = v0 + (v1 - v0) * ((times[i] - t0) / dt)
      local scale = math.max(math.abs(v0), math.abs(v1), 1e-6)
      if math.abs(values[i] - interp) / scale > tol then
        out_t[#out_t + 1], out_v[#out_v + 1] = times[i], values[i]
        last = i
      end
    end
  end
  out_t[#out_t + 1], out_v[#out_v + 1] = times[n], values[n]
  return out_t, out_v
end

local function cap(times, values, budget)
  if #times <= budget then return times, values, false end
  -- budget-1 sampled points plus the closing point
  local step = math.max(1, math.ceil((#times - 1) / (budget - 1)))
  local out_t, out_v = {}, {}
  for i = 1, #times, step do
    out_t[#out_t + 1], out_v[#out_v + 1] = times[i], values[i]
  end
  if out_t[#out_t] ~= times[#times] then
    out_t[#out_t + 1], out_v[#out_v + 1] = times[#times], values[#values]
  end
  return out_t, out_v, true
end

-- =========================================================
-- analysis
-- =========================================================

local function selected_item()
  local item = r.GetSelectedMediaItem(0, 0)
  if not item then return nil end
  return item, r.GetActiveTake(item)
end

local function analyse(item, take)
  if not item then return nil, 'Select an audio item first.' end
  if not take then return nil, 'This item has no active take.' end
  if r.TakeIsMIDI(take) then return nil, 'This is a MIDI take; Vox Leveler 2 needs audio.' end

  local length = r.GetMediaItemInfo_Value(item, 'D_LENGTH')
  if not length or length <= 0 then return nil, 'This item has no length.' end

  local src = r.GetMediaItemTake_Source(take)
  if not src then return nil, 'The take has no media source. Is the file offline?' end
  local src_rate = r.GetMediaSourceSampleRate(src)
  if src_rate == 0 then return nil, 'The media source is not audio.' end

  local times_cfg = rider_times(P.speed)
  local rate = src_rate
  local block = math.max(1, math.floor(rate * times_cfg.block_sec))

  local accessor = r.CreateTakeAudioAccessor(take)
  if not accessor then return nil, 'REAPER could not create an audio accessor for this item.' end

  local aa_start = r.GetAudioAccessorStartTime(accessor)
  local aa_end = r.GetAudioAccessorEndTime(accessor)
  local span = aa_end - aa_start
  if span <= 0 then
    r.DestroyAudioAccessor(accessor)
    return nil, 'The audio accessor reports no audio. Is the file online?'
  end

  local buffer = r.new_array(block)
  local levels = {}
  local pos = aa_start
  while pos < aa_end do
    local got = r.GetAudioAccessorSamples(accessor, rate, 1, pos, block, buffer)
    if got == nil then
      r.DestroyAudioAccessor(accessor)
      return nil, 'REAPER could not read the audio for this item.'
    end
    if got < 0 then
      r.DestroyAudioAccessor(accessor)
      return nil, string.format('REAPER refused the audio accessor (rate %d Hz).', rate)
    end
    if got == 0 then
      levels[#levels + 1] = DB_FLOOR
    else
      -- got is 1/0/-1 (audio / none / error), not a sample count, so the window is always
      -- `block` samples. .table() copies in C; indexing the userdata per sample is far slower
      local t = buffer.table()
      local sum = 0
      for i = 1, block do
        local v = t[i]
        if v then sum = sum + v * v end
      end
      levels[#levels + 1] = val_to_db(math.sqrt(sum / block))
    end
    if #levels > MAX_BLOCKS then
      r.DestroyAudioAccessor(accessor)
      return nil, 'This item is too long to analyse. Raise Speed.'
    end
    pos = pos + times_cfg.block_sec
  end
  r.DestroyAudioAccessor(accessor)

  if #levels == 0 then return nil, 'Nothing to analyse in this item.' end

  local gains, any_open = build_gains(levels, {
    level = P.level,
    range_up = P.range_up,
    range_down = P.range_down,
    amount = P.amount,
    output = P.output,
    auto_gate = P.auto_gate,
    gate = P.gate,
    lookahead = times_cfg.lookahead,
    block_sec = times_cfg.block_sec,
    attack = times_cfg.attack,
    release_mul = MODE_RELEASE[P.mode] or 8,
  })

  if not any_open then
    return nil, 'Nothing above the gate, so no curve was written. Lower the gate or check the take.'
  end

  local times, values = {}, {}
  for i = 1, #levels do
    times[#times + 1] = (i - 1) * times_cfg.block_sec
    values[#values + 1] = gains[i]
  end
  -- close with the last value; a unity point here ramps to 0 dB inside the item
  times[#times + 1] = length
  values[#values + 1] = gains[#gains]

  local lo, hi = math.huge, -math.huge
  for i = 1, #values do
    if values[i] < lo then lo = values[i] end
    if values[i] > hi then hi = values[i] end
  end
  if (val_to_db(hi) - val_to_db(lo)) < 0.05 then
    return nil, 'The result is a flat curve, so nothing was written. Widen the Range or change the Level.'
  end

  times, values = decimate(times, values, 0.012)
  local capped
  times, values, capped = cap(times, values, POINT_BUDGET)

  return {
    times = times, values = values,
    length = length,
    point_lo = lo, point_hi = hi,
    capped = capped,
    aa_start = aa_start,
  }
end

local function write_result(item, take, res)
  r.Undo_BeginBlock()
  r.PreventUIRefresh(1)

  local env, err = get_or_create_envelope(take, item)
  if not env then
    r.PreventUIRefresh(-1)
    r.Undo_EndBlock(SCRIPT .. ': write volume automation', -1)
    return nil, err
  end

  local peaks_were_off = show_peaks()
  r.DeleteEnvelopePointRange(env, 0, res.length)

  local inserted = 0
  for i = 1, #res.times do
    if r.InsertEnvelopePoint(env, res.times[i], res.values[i], 0, 0, false, true) then
      inserted = inserted + 1
    end
  end
  r.Envelope_SortPoints(env)

  -- a take envelope needs both
  local want_visible = not P.hide_env
  if env_get(env, 'VISIBLE') ~= want_visible then env_set(env, 'VISIBLE', want_visible) end
  if env_get(env, 'SHOWLANE') ~= want_visible then env_set(env, 'SHOWLANE', want_visible) end

  r.PreventUIRefresh(-1)
  r.TrackList_AdjustWindows(true)
  r.UpdateArrange()
  r.Undo_EndBlock(SCRIPT .. ': write volume automation', -1)

  restore_peaks(peaks_were_off)

  if inserted == 0 then
    return nil, 'No point could be inserted. Ctrl+Z restores the previous automation.'
  end
  return inserted
end

local function run()
  local item, take = selected_item()
  if not item then
    status, status_bad = 'Select an audio item first.', true
    return
  end

  local res, err = analyse(item, take)
  if not res then
    status, status_bad = err, true
    return
  end

  local inserted, werr = write_result(item, take, res)
  if not inserted then
    status, status_bad = werr, true
    return
  end

  local note = ''
  if res.aa_start and math.abs(res.aa_start) > 0.001 then
    note = string.format('  [accessor starts at %.3f s]', res.aa_start)
  end

  status = string.format('%s | %d points, %.1f to %.1f dB%s%s',
                         P.mode, inserted, val_to_db(res.point_lo), val_to_db(res.point_hi),
                         res.capped and ' (point budget reached)' or '', note)
  status_bad = false
end

-- =========================================================
-- GUI
-- =========================================================

local ctx = r.ImGui_CreateContext(SCRIPT)
local FONT = r.ImGui_CreateFont('sans-serif', 15)
r.ImGui_Attach(ctx, FONT)

local function touch()
  save_settings()
  if auto_update then auto_at = r.time_precise() + 1.0 end
end

local function slider_f(label, value, lo, hi, fmt, default, tip)
  local changed, v = r.ImGui_SliderDouble(ctx, label, value, lo, hi, fmt)
  if r.ImGui_IsItemHovered(ctx) then
    if r.ImGui_IsMouseDoubleClicked(ctx, 0) then v, changed = default, true end
    if tip then r.ImGui_SetTooltip(ctx, tip .. '\n\nDouble-click to reset') end
  end
  if changed then touch() end
  return changed, v
end

local function slider_i(label, value, lo, hi, default, tip)
  local changed, v = r.ImGui_SliderInt(ctx, label, value, lo, hi)
  if r.ImGui_IsItemHovered(ctx) then
    if r.ImGui_IsMouseDoubleClicked(ctx, 0) then v, changed = default, true end
    if tip then r.ImGui_SetTooltip(ctx, tip .. '\n\nDouble-click to reset') end
  end
  if changed then touch() end
  return changed, v
end

local function draw()
  local visible, open = r.ImGui_Begin(ctx, SCRIPT, true, r.ImGui_WindowFlags_AlwaysAutoResize())
  window_open = open
  if not visible then return end

  local changed

  r.ImGui_SeparatorText(ctx, 'Rider')
  changed, P.level = slider_f('Level', P.level, -40, 0, '%.1f dB', DEF.level, TIP.level)
  changed, P.speed = slider_i('Speed', P.speed, 0, 100, DEF.speed, TIP.speed)

  changed, P.range_up = slider_f('Max up', P.range_up, 0, 24, '+%.1f dB', DEF.range_up, TIP.up)
  changed, P.range_down = slider_f('Max down', P.range_down, -40, 0, '%.1f dB', DEF.range_down, TIP.down)

  changed, P.output = slider_f('Output', P.output, -12, 12, '%+.1f dB', DEF.output, TIP.output)
  changed, P.amount = slider_i('Amount', P.amount, 0, 100, DEF.amount, TIP.amount)

  r.ImGui_SeparatorText(ctx, 'Mode')
  -- radio buttons, not a combo: no popup, and the active mode is visible
  for i = 1, #MODES do
    if i > 1 then r.ImGui_SameLine(ctx) end
    if r.ImGui_RadioButton(ctx, MODES[i], P.mode == MODES[i]) then
      P.mode = MODES[i]
      save_settings()
      run_now = true       -- analysis is blocking; do it outside the frame
    end
    if r.ImGui_IsItemHovered(ctx) then r.ImGui_SetTooltip(ctx, TIP.mode) end
  end

  r.ImGui_SeparatorText(ctx, 'Silence')
  local gate_changed
  gate_changed, P.auto_gate = r.ImGui_Checkbox(ctx, 'Automatic gate', P.auto_gate)
  if r.ImGui_IsItemHovered(ctx) then r.ImGui_SetTooltip(ctx, TIP.autog) end
  if gate_changed then touch() end
  r.ImGui_SameLine(ctx)
  r.ImGui_BeginDisabled(ctx, P.auto_gate)
  local manual_changed
  manual_changed, P.gate = slider_f('Gate', P.gate, -80, -10, '%.1f dB', DEF.gate, TIP.gate)
  r.ImGui_EndDisabled(ctx)

  local item, take = selected_item()
  local env = nil
  if item and take and not r.TakeIsMIDI(take) then env = find_envelope(take) end

  r.ImGui_SeparatorText(ctx, 'Envelope')
  local hide_changed
  hide_changed, P.hide_env = r.ImGui_Checkbox(ctx, 'Hide line', P.hide_env)
  if r.ImGui_IsItemHovered(ctx) then r.ImGui_SetTooltip(ctx, TIP.hide) end
  if hide_changed then
    if env then
      r.Undo_BeginBlock()
      env_set(env, 'VISIBLE', not P.hide_env)
      env_set(env, 'SHOWLANE', not P.hide_env)
      r.TrackList_AdjustWindows(true)
      r.UpdateArrange()
      r.Undo_EndBlock(SCRIPT .. ': envelope visibility', -1)
    end
    touch()
  end

  local bypass, bypass_changed
  if env then
    bypass = not (env_get(env, 'ACTIVE') == true)
    bypass_changed, bypass = r.ImGui_Checkbox(ctx, 'BYPASS - hear original', bypass)
    if r.ImGui_IsItemHovered(ctx) then r.ImGui_SetTooltip(ctx, TIP.bypass) end
    if bypass_changed then
      r.Undo_BeginBlock()
      env_set(env, 'ACTIVE', not bypass)
      -- re-enabling can bring the line back
      if P.hide_env then
        env_set(env, 'VISIBLE', false)
        env_set(env, 'SHOWLANE', false)
      end
      r.TrackList_AdjustWindows(true)
      r.UpdateArrange()
      r.Undo_EndBlock(SCRIPT .. ': toggle envelope active', -1)
      touch()
    end
  else
    r.ImGui_TextDisabled(ctx, 'BYPASS: no volume envelope yet')
  end

  local auto_changed
  auto_changed, auto_update = r.ImGui_Checkbox(ctx, 'Auto-update', auto_update)
  if r.ImGui_IsItemHovered(ctx) then r.ImGui_SetTooltip(ctx, TIP.auto) end
  if auto_changed and auto_update then auto_at = r.time_precise() + 1.0 end

  r.ImGui_Spacing(ctx)
  r.ImGui_Separator(ctx)

  if status_bad then
    r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Text(), r.ImGui_ColorConvertDouble4ToU32(1.0, 0.55, 0.35, 1.0))
  else
    r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Text(), r.ImGui_ColorConvertDouble4ToU32(0.60, 0.75, 0.60, 1.0))
  end
  r.ImGui_TextWrapped(ctx, status)
  r.ImGui_PopStyleColor(ctx)

  r.ImGui_Spacing(ctx)
  if r.ImGui_Button(ctx, 'Apply', 120) then run() end
  r.ImGui_SameLine(ctx)
  r.ImGui_TextDisabled(ctx, 'reads the source, one undo step')

  r.ImGui_End(ctx)
end

local function main()
  local ok, err = xpcall(draw, debug.traceback)
  if not ok then r.ShowConsoleMsg(SCRIPT .. ': ' .. tostring(err) .. '\n') end

  if not window_open then return end

  if run_now then
    run_now = false
    run()
  end

  if auto_update and auto_at > 0 and r.time_precise() >= auto_at then
    auto_at = 0
    run()
  end

  r.defer(main)
end

load_settings()
r.defer(main)
