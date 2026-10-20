-- Actor ticks normally maintain continuous voice/contact cues. A frozen native
-- stand-in cannot maintain them, so stop its loops while keeping finite hits.
local Audio={}
local muted={}
local scans={}
local function valid(o)return o~=nil and o:IsValid()end
function Audio.quiet(actor,hidden)
 if not valid(actor)then return end
 local key=actor:GetFullName();local clock=os.clock();local scan=scans[key]
 if scan and scan.hidden==hidden and clock<scan.after then return end
 scans[key]={hidden=hidden,after=clock+.1}
 for _,r in ipairs(actor:K2_GetComponentsByClass(StaticFindObject('/Script/Engine.AudioComponent')))do
  local c=r:get()
  if valid(c)then
   local name=c:GetFullName();local sound=c.Sound
   local loop=valid(sound)and type(sound.Duration)=='number'and sound.Duration>=10000
   local old=muted[name]
   local managed=(_G.HSMPVoiceManaged or{})[name]
   if hidden or(loop and not managed)then
    if not old then old={component=c,volume=c.VolumeMultiplier};muted[name]=old end
    if c.VolumeMultiplier~=0 then c:SetVolumeMultiplier(0)end
    if c:IsPlaying()then c:Stop()end
   elseif old then
    if not managed then c:SetVolumeMultiplier(old.volume)end;muted[name]=nil
   end
  end
 end
end
function Audio.release()
 for name,s in pairs(muted)do
  if valid(s.component)and s.component:GetFullName()==name then s.component:SetVolumeMultiplier(s.volume)end
 end
 muted={};scans={}
end
return Audio
