-- @description Toggle oversampling for The Analog Molecule (2x)
-- @version 1.00
-- @author MPL (modified by DocShadrach)
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
function main_body_parseextstate(extstatekey)
  local ret, str = GetProjExtState(0, extstatekey, 'FXGUIDS')
  local extstatein = {}
  if ret then
    for line in str:gmatch('[^\r\n]+') do
      local GUID, pluginOS, chainOS = line:match('({.*}) (%d) (%d)')
      if not GUID then
        GUID, pluginOS = line:match('({.*}) (%d)')
        chainOS = 0
      end
      extstatein[GUID] = {
        pluginOS = tonumber(pluginOS),
        chainOS  = tonumber(chainOS) or 0
      }
    end
  end
  return extstatein
end

---------------------------------------------------
function collect_fx_ids(track, plugin)
  local fxids = {}
  if plugin then plugin = plugin:lower():gsub('[%p%s]+','') end

  for fx_id = 0, TrackFX_GetCount(track)-1 do
    local retval, fxname = TrackFX_GetNamedConfigParm(track, fx_id, 'fx_name')
    if retval then
      fxname = fxname:lower():gsub('[%p%s]+','')
      if not plugin or fxname:match(plugin) then
        fxids[#fxids+1] = fx_id
      end
    end
  end
  return fxids
end

---------------------------------------------------
function process_track(track, instanceOS, state, extstateout, extstatein, plugin)
  if not track then return end
  local fxids = collect_fx_ids(track, plugin)

  for i = 1, #fxids do
    local fx_id = fxids[i]

    local _, pluginOS = TrackFX_GetNamedConfigParm(track, fx_id, 'instance_oversample_shift')
    local _, chainOS  = TrackFX_GetNamedConfigParm(track, fx_id, 'chain_oversample_shift')

    pluginOS = tonumber(pluginOS) or 0
    chainOS  = tonumber(chainOS) or 0

    if state == 0 then
      extstateout[#extstateout+1] =
        TrackFX_GetFXGUID(track, fx_id)..' '..pluginOS..' '..chainOS
      TrackFX_SetNamedConfigParm(track, fx_id, 'instance_oversample_shift', instanceOS)
      TrackFX_SetNamedConfigParm(track, fx_id, 'chain_oversample_shift', 0)
    else
      local GUID = TrackFX_GetFXGUID(track, fx_id)
      if extstatein[GUID] then
        TrackFX_SetNamedConfigParm(track, fx_id, 'instance_oversample_shift', extstatein[GUID].pluginOS)
        TrackFX_SetNamedConfigParm(track, fx_id, 'chain_oversample_shift',  extstatein[GUID].chainOS)
      end
    end
  end
end

---------------------------------------------------
function main(sec, cmd, filename)

  local extstatekey = 'ANALOG_MOLECULE_OS_TOGGLE'
  local plugin = 'theanalogmolecule'
  local instanceOS = 1 -- 2x oversampling

  local state = tonumber(GetExtState(extstatekey, 'STATE')) or 0
  local extstatein = main_body_parseextstate(extstatekey)
  local extstateout = {}

  for i = 0, CountTracks(0) do
    local tr = (i == 0) and GetMasterTrack(0) or GetTrack(0, i-1)
    process_track(tr, instanceOS, state, extstateout, extstatein, plugin)
  end

  if state == 0 then
    SetExtState(extstatekey, 'STATE', 1, true)
    SetProjExtState(0, extstatekey, 'FXGUIDS', table.concat(extstateout, '\n'))
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
  Undo_EndBlock2(0, 'Toggle 2x oversampling for The Analog Molecule', 0xFFFFFFFF)
end

