-- Relay native injury once to its owner, without replaying collision forces.
local Damage={}
local paths=require('paths')
local Math=dofile(paths.scripts..'/rig_math.lua')
local Sever=dofile(paths.scripts..'/native_sever.lua')
local own,remote,owner,target,identify,resolve,bone_frame,original_invulnerable,epoch
local events,sequence,received,boxes={},0,{},{}
local captured,applied,errors,severs=0,0,0,0
local next_publish,published_sequence=0,-1
local replay_queue,last_read_text,last_published_text={},nil,nil
local queue_peak,replay_max_ms=0,0
local arm_after=0
local function valid(o)return o~=nil and o:IsValid()end
local function same(a,b)return valid(a)and valid(b)and a:GetFullName()==b:GetFullName()end
local function finite(n,b)return type(n)=='number'and n==n and math.abs(n)<=b end
local function vector(v)return {v.X,v.Y,v.Z}end
local function vec(v)return {X=v[1],Y=v[2],Z=v[3]}end
local function packed(t)local a,q,s=t.Translation,t.Rotation,t.Scale3D
 return {a.X,a.Y,a.Z,q.X,q.Y,q.Z,q.W,s.X,s.Y,s.Z}end
local function clear_file()local f=io.open(paths.runtime..'/local.damage','w');if f then f:write('OFF\n');f:close()end end
function Damage.stop()
 Sever.reset()
 if valid(own)and original_invulnerable~=nil then own.Invulnerable=original_invulnerable end
 for _,b in ipairs(boxes)do if valid(b.component)then b.component:K2_DestroyComponent(own)end end
 own,remote,owner,target,identify,resolve,bone_frame,original_invulnerable,epoch=nil,nil,nil,nil,nil,nil,nil,nil,nil
 events,sequence,received,boxes={},0,{},{}
 replay_queue,last_read_text,last_published_text={},nil,nil
 next_publish,published_sequence=0,-1
 arm_after=0
 _G.HSMPComplexDispatch=nil;_G.HSMPDamageDispatch=nil;_G.HSMPSeverDispatch=nil;clear_file()
end
function Damage.protect(pawn)
 if not valid(pawn)then return end
 if not same(pawn,own)then Damage.stop();own=pawn;original_invulnerable=pawn.Invulnerable end
 -- Protection starts as soon as this life is possessed, before loadout,
 -- native AI cleanup or the remote replica has finished initializing.
 pawn.Invulnerable=true
end
function Damage.configure(pawn,other,owner_id,target_id,identifier,resolver,frame_getter)
 if not same(pawn,own)then Damage.stop();original_invulnerable=pawn.Invulnerable end
 if not same(other,remote)or target~=target_id then
  events={};replay_queue={};received={};last_read_text=nil;Sever.reset()
  epoch=string.format('%08x%08x%08x%08x',os.time(),math.random(1,0x7fffffff),math.random(1,0x7fffffff),math.random(1,0x7fffffff))
  arm_after=os.clock()+.5
 end
 own,remote,owner,target,identify,resolve,bone_frame=pawn,other,owner_id,target_id,identifier,resolver,frame_getter
 -- Native local contacts must not damage the owner a second time. Its exact
 -- deduplicated injury event alone bypasses this flag.
 own.Invulnerable=true
 if valid(remote)then remote.Invulnerable=os.clock()<arm_after end
 _G.HSMPDamageDispatch=function(context,...)
  if os.clock()<arm_after or not same(context,remote)or not identify then return end
  local a={...};if #a<16 then return end
  local source=a[13]:get();local source_id=valid(source)and identify(source)
  if not source_id then return end
  local raw,cut,blunt=a[6]:get(),a[7]:get(),a[10]:get()
  if not finite(raw,1e6)or raw<0 or not finite(cut,1e6)or cut<0 or not finite(blunt,16)or blunt<0 then return end
  local bone=a[5]:get():ToString();local frame=bone_frame and bone_frame(bone)
  if not frame then return end
  sequence=sequence+1
  local row={'N',sequence,'body',bone}
  for _,i in ipairs({3,4,2,1})do for _,v in ipairs(vector(a[i]:get()))do row[#row+1]=v end end
  for _,v in ipairs({raw,cut,blunt,a[8]:get()and 1 or 0,a[11]:get()and 1 or 0,0,a[14]:get()and 1 or 0,target,source_id})do row[#row+1]=v end
  for _,v in ipairs(frame)do row[#row+1]=v end
  local b=a[15]:get();events[#events+1]={row=row,box=valid(b)and b or nil,time=os.clock()}
  if #events>32 then table.remove(events,1)end
  captured=captured+1
 end
 _G.HSMPDamageHooks=_G.HSMPDamageHooks or{}
 local name='/Game/Character/Blueprints/Willie_BP.Willie_BP_C:Get Damage'
 if not _G.HSMPDamageHooks[name]and valid(StaticFindObject(name))then
  _G.HSMPDamageHooks[name]={RegisterHook(name,function(context,...)
   if _G.HSMPDamageDispatch then local ok,err=pcall(_G.HSMPDamageDispatch,context:get(),...)
    if not ok then print('[HalfSwordMP] Injury capture: '..tostring(err)..'\n')end
   end
  end)}
 end
 _G.HSMPSeverDispatch=function(context,...)
  if os.clock()<arm_after or not same(context,remote)or not identify or not bone_frame then return end
  local e=Sever.capture(context,{...},identify,bone_frame,target)
  if e then sequence=sequence+1;events[#events+1]={sever=e,seq=sequence,time=os.clock()};if #events>32 then table.remove(events,1)end end
 end
 local sever_name='Function /Game/Character/Blueprints/Willie_BP.Willie_BP_C:Dismember Function Delayed'
 if not _G.HSMPDamageHooks[sever_name]and valid(StaticFindObject(sever_name))then
  _G.HSMPDamageHooks[sever_name]={RegisterHook(sever_name,function(context,...)
   if _G.HSMPSeverDispatch then local ok,err=pcall(_G.HSMPSeverDispatch,context:get(),...)
    if not ok then print('[HalfSwordMP] Sever capture: '..tostring(err)..'\n')end end
  end)}
 end
end
local function publish()
 if not epoch or not valid(own)then return end
 if sequence==published_sequence and os.clock()<next_publish then return end
 published_sequence=sequence;next_publish=os.clock()+.25
 local lines={'HSDM1|'..epoch..'|'..own:GetWorld():GetFullName():gsub('^%S+ ','')}
 for _,e in ipairs(events)do if os.clock()-e.time<1.5 then
  if not e.text then
   local row=e.row
   if e.sever then row=Sever.encode(e.sever,e.seq)end
   if row and not e.sever then
   local has_box=valid(e.box);row[#row+1]=has_box and 1 or 0
   if has_box then
    for _,v in ipairs(packed(e.box:K2_GetComponentToWorld()))do row[#row+1]=v end
    local s=e.box:GetUnscaledBoxExtent();for _,v in ipairs({s.X,s.Y,s.Z})do row[#row+1]=v end
   end
   end
   if row then
   for i,v in ipairs(row)do if type(v)=='number'then row[i]=string.format('%.9g',v)end end
   e.text=table.concat(row,'|');e.box=nil
   end
  end
  if e.text then lines[#lines+1]=e.text end
 end end
 lines[#lines+1]='END|'..#lines
 local text=table.concat(lines,'\n')..'\n'
 if text==last_published_text then return end
 local f=io.open(paths.runtime..'/local.damage','wb');if f then f:write(text);f:close();last_published_text=text end
end
local function read()
 local f=io.open(paths.runtime..'/remote.damage','rb');if not f then return end
 local text=f:read(32769)or'';f:close()
 if text==last_read_text or #text>32768 or text:sub(-1)~='\n' then return end
 local rows={};for line in text:gmatch('[^\r\n]+')do local row={};for v in line:gmatch('[^|]+')do row[#row+1]=v end;rows[#rows+1]=row end
 local h,last=rows[1],rows[#rows]
 if #rows>34 or not h or #h~=3 or h[1]~='HSDM1'or #h[2]~=32 or not h[2]:match('^[a-f0-9]+$')
  or not last or last[1]~='END'or tonumber(last[2])~=#rows-1
  or h[3]~=own:GetWorld():GetFullName():gsub('^%S+ ','')then return end
 last_read_text=text;return rows,h[2]
end
local function make_box(t,size,bone)
 local tr=own.Mesh:GetSocketTransform(bone,0)
 tr.Translation.X,tr.Translation.Y,tr.Translation.Z=t[1],t[2],t[3]
 tr.Rotation.X,tr.Rotation.Y,tr.Rotation.Z,tr.Rotation.W=t[4],t[5],t[6],t[7]
 tr.Scale3D.X,tr.Scale3D.Y,tr.Scale3D.Z=t[8],t[9],t[10]
 local box=own:AddComponentByClass(StaticFindObject('/Script/Engine.BoxComponent'),true,tr,true)
 box:SetBoxExtent({X=size[1],Y=size[2],Z=size[3]},false)
 box:SetCollisionEnabled(1);box:SetCollisionResponseToAllChannels(1)
 own:FinishAddComponent(box,true,tr);box:SetHiddenInGame(true,false)
 boxes[#boxes+1]={component=box,expires=os.clock()+6}
 return box
end
local function replay(row)
 if row[1]=='S'then
  return Sever.replay(row,own,owner,resolve,make_box)
 end
 if row[1]~='N'or not((#row==36 and row[36]=='0')or(#row==49 and row[36]=='1'))then return end
 local n={};for i=2,#row do if i~=3 and i~=4 and i~=25 then n[i]=tonumber(row[i]);if not finite(n[i],1e7)then return end end end
 if n[24]~=owner or n[2]<1 or n[2]%1~=0 or n[17]<0 or n[17]>1e6 or n[18]<0 or n[18]>1e6
  or n[19]<0 or n[19]>16 or n[19]%1~=0 then return end
 if #row[4]>64 or not row[4]:match('^[%w_./:%-]+$')or #row[25]>64 or not row[25]:match('^[%w_./:%-]+$')then return end
 for i=20,23 do if row[i]~='0'and row[i]~='1'then return end end
 local source=resolve and resolve(row[25]);if not valid(source)then return end
 local bone=FName(row[4]);if own.Mesh:GetBoneIndex(bone)<0 then return end
 local from={};for i=26,35 do from[#from+1]=n[i]end
 local norm=from[4]^2+from[5]^2+from[6]^2+from[7]^2;if norm<.95 or norm>1.05 then return end
 local to=packed(own.Mesh:GetSocketTransform(bone,0))
 local point=Math.point({n[5],n[6],n[7]},from,to)
 local normal=Math.rotate(to,Math.rotate(from,{n[8],n[9],n[10]},true))
 local box
 if row[36]=='1'then
  local t={};for i=37,46 do t[#t+1]=n[i]end;t=Math.transform(t,from,to)
  local tr=own.Mesh:GetSocketTransform(bone,0)
  tr.Translation.X,tr.Translation.Y,tr.Translation.Z=t[1],t[2],t[3]
  tr.Rotation.X,tr.Rotation.Y,tr.Rotation.Z,tr.Rotation.W=t[4],t[5],t[6],t[7]
  tr.Scale3D.X,tr.Scale3D.Y,tr.Scale3D.Z=t[8],t[9],t[10]
  box=own:AddComponentByClass(StaticFindObject('/Script/Engine.BoxComponent'),true,tr,true)
  box:SetBoxExtent({X=n[47],Y=n[48],Z=n[49]},false)
  box:SetCollisionEnabled(1);box:SetCollisionResponseToAllChannels(1)
  own:FinishAddComponent(box,true,tr);box:SetHiddenInGame(true,false)
  boxes[#boxes+1]={component=box,expires=os.clock()+3}
 end
 -- Preserve the native wound/bleed/dismemberment path. Physics already ran:
 -- replay no impulse, velocity or shockwave and move no fighters or weapons.
 local zero={X=0,Y=0,Z=0}
 own['Get Damage'](own,zero,zero,vec(point),vec(normal),bone,n[17],n[18],row[20]=='1',own.Mesh,n[19],
  row[21]=='1',false,source,row[23]=='1',box,true,{})
 applied=applied+1;return true
end
function Damage.tick()
 publish();if not valid(own)then return end
 local added,failed=Sever.update(own);severs=severs+added;errors=errors+failed
 for i=#boxes,1,-1 do local b=boxes[i];if os.clock()>b.expires then
  if valid(b.component)then b.component:K2_DestroyComponent(own)end;table.remove(boxes,i)
 end end
 local rows,id=read()
 if rows then
  received[id]=received[id]or{}
  for i=2,#rows-1 do local row=rows[i];local seq=row[2]
   local victim=tonumber(row[row[1]=='S'and 3 or 24])
   if (row[1]=='N'or row[1]=='S')and not received[id][seq]and victim==owner then
    if #replay_queue>=128 then last_read_text=nil;break end
    received[id][seq]=true;replay_queue[#replay_queue+1]={row=row,expires=os.clock()+1.5}
    queue_peak=math.max(queue_peak,#replay_queue)
   end
  end
 end
 -- Native wound painting can be expensive. Retain every accepted event, but
 -- do not replay an entire packet's injuries in one game-thread update.
 local started=os.clock();local count=0
 while #replay_queue>0 and count<4 do
  local e=replay_queue[1];local ok,result=pcall(replay,e.row)
  count=count+1
  if ok and result then table.remove(replay_queue,1)
  elseif not ok or os.clock()>e.expires then
   table.remove(replay_queue,1);errors=errors+1
   if not ok then print('[HalfSwordMP] Injury replay: '..tostring(result)..'\n')end
  else break end -- Wait briefly for this life's native weapon construction.
  if os.clock()-started>=.002 then break end
 end
 replay_max_ms=math.max(replay_max_ms,(os.clock()-started)*1000)
end
function Damage.injury_source()return nil end
function Damage.inspect(f)f:write('native_contacts_observed=',captured,'\nnative_injuries_applied=',applied,
 '\nnative_severs_applied=',severs,'\nnative_injury_errors=',errors,
 '\nnative_injury_queue=',#replay_queue,'\nnative_injury_queue_peak=',queue_peak,
 '\nnative_injury_replay_max_ms=',replay_max_ms,'\nnative_impacts_applied=0\nnetwork_hitbox_moves=0\n')end
return Damage
