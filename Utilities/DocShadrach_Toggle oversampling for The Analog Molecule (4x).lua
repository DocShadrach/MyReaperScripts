-- @description Toggle oversampling for The Analog Molecule (4x)
-- @version 1.00
-- @author MPL (modified by Doc Shadrach)
-- @metapackage

for key in pairs(reaper) do _G[key]=reaper[key] end

---------------------------------------------------
function VF_CheckReaperVrs(rvrs, showmsg)
  local vrs_num = tonumber(GetAppVersion():match('[%d%.]+'))
  if rvrs > vrs_num then
    if showmsg then MB('Update REAPER to newer version ('..rvrs..' or newer)', '', 0) end
    return
  end
  return true
end

---------------------------------------------------
function parse_extstate(extstatekey)
  local ret, str = GetProjExtState(0, extstatekey, 'FXGUIDS')
  local t = {}
  if ret then
    for line in str:gmatch('[^\r\n]+') do
      local GUID, pluginOS, chainOS = line:match('({.*}) (%d) (%d)')
      if not GUID then
        GUID, pluginOS = line:match('({.*}) (%d)')
        chainOS = 0
      end
      t[GUID] = {
        pluginOS = tonumber(pluginOS),
        chainOS  = tonumber(chainOS) or 0
      }
    end
  end
  return t
end

---------------------------------------------------
function collect_fx(track, plugin)
  local fxids = {}
  plugin = plugin:lower():gsub('[%p%s]+','')

  for fx_id = 0, TrackFX_GetCount(track)-1 do
    local retval, fxname = TrackFX_GetNamedConfigParm(track, fx_id, 'fx_name')
    if retval then
      fxname = fxname:lower():gsub('[%p%s]+','')
      if fxname:match(plugin) then
        fxids[#fxids+1] = fx_id
      end
    end
  end
  return fxids
end

---------------------------------------------------
function process_track(track, instanceOS, state, extout, extin, plugin)
  if not track then return end
  local fxids = collect_fx(track, plugin)

  for i = 1, #fxids do
    local fx_id = fxids[i]

    local _, instOS = TrackFX_GetNamedConfigParm(track, fx_id, 'instance_oversample_shift')
    local _, chOS   = TrackFX_GetNamedConfigParm(track, fx_id, 'chain_oversample_shift')

    instOS = tonumber(instOS) or 0
    chOS   = tonumber(chOS) or 0

    if state == 0 then
      extout[#extout+1] =
        TrackFX_GetFXGUID(track, fx_id)..' '..instOS..' '..chOS
      TrackFX_SetNamedConfigParm(track, fx_id, 'instance_oversample_shift', instanceOS)
      TrackFX_SetNamedConfigParm(track, fx_id, 'chain_oversample_shift', 0)
    else
      local GUID = TrackFX_GetFXGUID(track, fx_id)
      if extin[GUID] then
        TrackFX_SetNamedConfigParm(track, fx_id, 'instance_oversample_shift', extin[GUID].pluginOS)
        TrackFX_SetNamedConfigParm(track, fx_id, 'chain_oversample_shift',  extin[GUID].chainOS)
      end
    end
  end
end

---------------------------------------------------
function main(sec, cmd)

  local extstatekey = 'ANALOG_MOLECULE_OS_TOGGLE_4X'
  local plugin = 'theanalogmolecule'
  local instanceOS = 2 -- 4x oversampling

  local state = tonumber(GetExtState(extstatekey, 'STATE')) or 0
  local extin = parse_extstate(extstatekey)
  local extout = {}

  for i = 0, CountTracks(0) do
    local tr = (i == 0) and GetMasterTrack(0) or GetTrack(0, i-1)
    process_track(tr, instanceOS, state, extout, extin, plugin)
  end

  if state == 0 then
    SetExtState(extstatekey, 'STATE', 1, true)
    SetProjExtState(0, extstatekey, 'FXGUIDS', table.concat(extout, '\n'))
    SetToggleCommandState(sec, cmd, 1)
  else
    SetExtState(extstatekey, 'STATE', 0, true)
    SetToggleCommandState(sec, cmd, 0)
  end

  RefreshToolbar2(sec, cmd)
end

---------------------------------------------------
if VF_CheckReaperVrs(6.72, true) then
  local _, _, sec, cmd = get_action_context()
  Undo_BeginBlock2(0)
  main(sec, cmd)
  Undo_EndBlock2(0, 'Toggle 4x oversampling for The Analog Molecule', 0xFFFFFFFF)
end

