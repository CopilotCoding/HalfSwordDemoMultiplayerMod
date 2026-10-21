-- Relay the owner's native exterior voice components, including loop volume.
-- Heartbeat, tinnitus, music and contact loops remain local to their native PC.
local Voice={}
local fields={voice='Voice Audio',throat='Throat Audio',exertion='heavy_exertion_Cue'}
local captured,remote={},{}
local own_name,remote_name
local function valid(o)return o~=nil and o:IsValid()end
local function allowed(s)return type(s)=='string'and #s<=240 and s:match('^/Game/Sounds/Voice/[%w_/%-]+%.[%w_%-]+$')and not s:find('..',1,true)end
local function clock(p)return require('UEHelpers').GetGameplayStatics():GetRealTimeSeconds(p:GetWorld())end
local function bounded(n,lo,hi)return type(n)=='number'and n==n and math.max(lo,math.min(hi,n))or lo end
function Voice.capture(pawn,lines)
 local name=pawn:GetFullName();local time=clock(pawn)
 if own_name~=name then captured={};own_name=name;_G.HSMPVoiceStarts={}end
 _G.HSMPVoiceSource={}
 for channel,field in pairs(fields)do
  local c=pawn[field]
  if valid(c)then
   local key=c:GetFullName();_G.HSMPVoiceSource[key]=true
   local sound=c.Sound;local path=valid(sound)and sound:GetFullName():gsub('^%S+ ','')or''
   if allowed(path)then
    local playing=c:IsPlaying();local previous=captured[channel]
    local serial=(_G.HSMPVoiceStarts or{})[key]or 0
    if not previous or previous.path~=path or previous.playing~=playing or previous.serial~=serial then
     previous={path=path,playing=playing,serial=serial,revision=(previous and previous.revision or 0)+1,time=time}
     captured[channel]=previous
    end
    lines[#lines+1]=table.concat({'AU',channel,path,previous.revision,playing and 1 or 0,
     string.format('%.4f',bounded(c.VolumeMultiplier,0,2)),string.format('%.4f',bounded(c.PitchMultiplier,.25,4)),
     string.format('%.3f',bounded(time-previous.time,0,3600))},'|')
   end
  end
 end
end
function Voice.install()
 if _G.HSMPVoicePlayHook then return end
 _G.HSMPVoiceStarts={}
 _G.HSMPVoicePlayHook={RegisterHook('/Script/Engine.AudioComponent:Play',function(ctx)
  local c=ctx:get()
  if valid(c)and(_G.HSMPVoiceSource or{})[c:GetFullName()]then
   local starts=_G.HSMPVoiceStarts;local name=c:GetFullName();starts[name]=(starts[name]or 0)+1
  end
 end)}
end
function Voice.read(rows)
 local sounds={}
 for _,r in ipairs(rows or{})do
  if r[1]=='AU'and #r==8 and fields[r[2]]and allowed(r[3])then
   local seq,playing,volume,pitch,age=tonumber(r[4]),tonumber(r[5]),tonumber(r[6]),tonumber(r[7]),tonumber(r[8])
   if seq and seq>=1 and seq<=1e7 and seq%1==0 and(playing==0 or playing==1)
    and volume and volume>=0 and volume<=2 and pitch and pitch>=.25 and pitch<=4 and age and age>=0 and age<=3600 then
    sounds[r[2]]={path=r[3],seq=seq,playing=playing==1,volume=volume,pitch=pitch,age=age}
   end
  end
 end
 return sounds
end
function Voice.update(pawn,sounds,fresh)
 if not valid(pawn)then return end
 if remote_name~=pawn:GetFullName()then remote={};remote_name=pawn:GetFullName();_G.HSMPVoiceManaged={}end
 local managed=_G.HSMPVoiceManaged
 for channel,field in pairs(fields)do
  local c=pawn[field];local row=fresh and sounds and sounds[channel]
  if valid(c)then
   if row then
    managed[c:GetFullName()]=true
    local old=remote[channel]
    if not old or old.seq~=row.seq or old.path~=row.path then
     local sound=StaticFindObject(row.path)
     if not valid(sound)then LoadAsset(row.path:match('^(.+)%.[^%.]+$'));sound=StaticFindObject(row.path)end
     if valid(sound)and sound:IsA('/Script/Engine.SoundBase')then
      c:Stop();c:SetSound(sound)
      c:SetVolumeMultiplier(row.volume);c:SetPitchMultiplier(row.pitch)
      if row.playing then c:Play(row.age)end
      remote[channel]={seq=row.seq,path=row.path,volume=row.volume,pitch=row.pitch}
     end
    end
    local active=remote[channel]
    if active and active.volume~=row.volume then c:SetVolumeMultiplier(row.volume);active.volume=row.volume end
    if active and active.pitch~=row.pitch then c:SetPitchMultiplier(row.pitch);active.pitch=row.pitch end
    if not row.playing and c:IsPlaying()then c:Stop()end
   else
    -- Stop on silence, stale packets, leaving the arena, or a new life.
    if c:IsPlaying()then c:Stop()end
    c:SetVolumeMultiplier(0);remote[channel]=nil;managed[c:GetFullName()]=nil
   end
  end
 end
end
return Voice
