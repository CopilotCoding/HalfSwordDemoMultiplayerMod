-- Keep tracking this life’s native weapons after the hands release them.
-- The owning game supplies physics; the peer displays the measured mesh poses.
local Dropped={}
local life,tracked,serial=nil,{},0
local pending,consumed,queued={}, {}, {}
local Parts,Equipment
local hand_fields={'Weapon R','Weapon L','Grab Component R','Grab Component L',
 'Weapon Slot R 1','Weapon Slot R 2','Weapon Slot L 1','Weapon Slot L 2','Weapon Slot Back'}
local tick_after=0
local function valid(o)return o~=nil and o:IsValid()end
local function path(o)return o:GetFullName():gsub('^%S+ ','')end
local function live(entry)return valid(entry.actor)and entry.actor:GetFullName()==entry.identity end
local function weapon(o)
 if not valid(o)then return false end
 local c=o:GetClass()
 while valid(c)do
  local name=c:GetFName():ToString()
  if name=='Weapon_Fists_C'then return false end
  if name=='ModularWeaponBP_C'then return true end
  c=c:GetSuperStruct()
 end
 return false
end
function Dropped.reset()
 _G.HSMPDropInput=nil
 for _,entry in pairs(tracked)do
  if entry.granted and live(entry)then entry.actor:K2_DestroyActor()end
 end
 life,tracked,serial=nil,{},0;pending,consumed,queued={},{},{};tick_after=0
end
function Dropped.update(pawn)
 local key=pawn:GetFullName()
 if life~=key then Dropped.reset();life=key end
 local held,signature={},{}
 local count=0
 for name,entry in pairs(tracked)do
  if not live(entry)and not entry.granted then tracked[name]=nil else count=count+1 end
 end
 for _,field in ipairs(hand_fields)do
  local o=pawn[field]
  if valid(o)then
   local a=(field=='Grab Component R'or field=='Grab Component L')and o:GetOwner()or o
   local name=valid(a)and a:GetFullName()
   if name and(tracked[name]or weapon(a))then
    held[name]=true
    signature[#signature+1]=field..'='..name
    -- A bounded life inventory, without a world-wide object scan on each tick.
    if not tracked[name]and count<16 and serial<9999999 then
     serial=serial+1;count=count+1;tracked[name]={actor=a,identity=name,id='drop'..serial}
    end
   end
  end
 end
 local state={signature=table.concat(signature,'|'),actors={},names={}}
 for name,entry in pairs(tracked)do
  if not live(entry)and not entry.granted then tracked[name]=nil
  elseif not held[name]then
   state.actors[#state.actors+1]=entry;state.names[name]=true
  end
 end
 table.sort(state.actors,function(a,b)return a.id<b.id end)
 return state
end
function Dropped.capture(state,lines,packed,capture_mesh,budget)
 Parts=Parts or dofile(require('paths').scripts..'/weapon_parts.lua')
 for _,request in pairs(pending)do
  lines[#lines+1]=table.concat({'DR',request.owner,request.id,request.hand},'|')
 end
 local count=0
 for _,entry in ipairs(state.actors)do
  local actor=entry.actor
  if not entry.description and live(entry)then
   local rows={};Parts.capture(actor,entry.id,rows)
   entry.description={class=path(actor:GetClass()),rows=rows}
  end
  if live(entry)then entry.transform=packed(actor:GetTransform())end
  if entry.description and entry.transform then
   lines[#lines+1]=table.concat({'DW',entry.id,entry.description.class,entry.transform,entry.granted or 0},'|')
   for _,row in ipairs(entry.description.rows)do lines[#lines+1]='D'..row end
  end
  if live(entry)and not entry.granted and not actor.bHidden then
   -- Native hand/module setup can replace mesh components on the same actor.
   -- A lifetime cache of the old components makes subsequent drops invisible.
   if not entry.components or os.clock()>=(entry.component_scan or 0)then
    entry.component_scan=os.clock()+.5
    entry.components={};entry.component_names={}
    for _,r in ipairs(actor:K2_GetComponentsByClass(StaticFindObject('/Script/Engine.StaticMeshComponent')))do
     local c=r:get()
     if valid(c)then entry.components[#entry.components+1]=c;entry.component_names[c]=c:GetFullName()end
    end
   end
   for index,c in ipairs(entry.components)do
    local current=valid(c)and c:GetFullName()==entry.component_names[c]
    if not current then entry.component_scan=0 end
    local asset=current and c.StaticMesh
    if count<budget and valid(asset)and c:IsVisible()and not c.bHiddenInGame then
     local name=path(asset)
     if name:match('^/Game/Assets/Weapons/')and not name:find('/Collisions/',1,true)then
      local t=c:K2_GetComponentToWorld();local transform=packed(t)
      if transform then
       local id=entry.id..'_'..index
       lines[#lines+1]='C|'..id..'|D|'..name..'|'..transform
       capture_mesh(lines,c,id,false,false,true);count=count+1
      end
     end
    end
   end
  end
 end
 return count
end
function Dropped.read(rows)
 local items,requests,by_id={},{},{}
 Parts=Parts or dofile(require('paths').scripts..'/weapon_parts.lua')
 for _,row in ipairs(rows or{})do
  if row[1]=='DW'and #row==14 then
   local entry={id=row[2],class=row[3],transform={},grant=tonumber(row[14])}
   for i=4,13 do entry.transform[#entry.transform+1]=tonumber(row[i])end
   items[#items+1]=entry;by_id[entry.id]=entry
  elseif row[1]=='DR'and #row==4 then
   requests[#requests+1]={owner=tonumber(row[2]),id=row[3],hand=row[4]}
  elseif row[1]:match('^D[KZLYO]$')and by_id[row[2]]then
   local copy={row[1]:sub(2)};for i=2,#row do copy[#copy+1]=row[i]end
   Parts.read(by_id[row[2]],copy)
  end
 end
 return items,requests
end
local function free_hand(pawn,hand)
 local w=pawn[hand=='right'and'Weapon R'or'Weapon L']
 return not valid(w)or w:GetClass():GetFName():ToString():lower():find('fist',1,true)~=nil
end
local function distance(a,b)return(a.X-b[1])^2+(a.Y-b[2])^2+(a.Z-b[3])^2 end
function Dropped.request(pawn,renderer,hand)
 if not free_hand(pawn,hand)then return false end
 for _,request in pairs(pending)do if request.hand==hand then return false end end
 local items=renderer.drops();local root=pawn:K2_GetActorLocation()
 local best,range=nil,220^2
 for _,item in ipairs(items or{})do
  local token=renderer.owner()..':'..item.id
  local d=distance(root,item.transform)
  local requested=false;for _,request in pairs(pending)do if request.id==item.id then requested=true end end
  if item.grant==0 and d<range and not requested and not consumed[token]then best,range=item,d end
 end
 if not best then return false end
 local token=renderer.owner()..':'..best.id
 pending[token]={owner=renderer.owner(),id=best.id,hand=hand}
 return true
end
function Dropped.tick(pawn,renderer)return Dropped.tick_many(pawn,{renderer})end
function Dropped.tick_many(pawn,renderers)
 if not _G.HSMPAvatar then return end
 local ready={}
 for _,renderer in ipairs(renderers)do if renderer.drops and renderer.owner()then ready[#ready+1]=renderer end end
 if #ready==0 then return end
 local clock=os.clock();if clock<tick_after then return end;tick_after=clock+.05
 local own=_G.HSMPAvatar.owner(pawn);local state=Dropped.update(pawn)
 _G.HSMPDropInput=function(context,hand)
  if valid(pawn)and valid(context)and context:GetFullName()==pawn:GetFullName()
   and _G.HSMPSession and _G.HSMPSession.in_match()
   and (not _G.HSMPUI or not _G.HSMPUI.is_open())then queued[hand]=true end
 end
 _G.HSMPDropHooks=_G.HSMPDropHooks or{}
 for _,event in ipairs({{'Grab Right',19,'right'},{'Grab Right',18,'right'},{'Grab Left',17,'left'},{'Grab Left',16,'left'}})do
  local fn='/Game/Character/Blueprints/Willie_BP.Willie_BP_C:InpActEvt_'..event[1]..'_K2Node_InputActionEvent_'..event[2]
  if not _G.HSMPDropHooks[fn]then
   _G.HSMPDropHooks[fn]={RegisterHook(fn,function(ctx)
    local p=ctx:get()
    if valid(p)and p[event[3]=='right'and'R Grab Pressed'or'L Grab Pressed']and _G.HSMPDropInput then
     _G.HSMPDropInput(p,event[3])
    end
   end)}
  end
 end
 if pawn.Health<=0 or pawn.DED then queued={};return end
 for hand in pairs(queued)do
  table.sort(ready,function(a,b)
   local root=pawn:K2_GetActorLocation()
   local function nearest(renderer)local n=math.huge;for _,item in ipairs(renderer.drops()or{})do if item.grant==0 then n=math.min(n,distance(root,item.transform))end end;return n end
   return nearest(a)<nearest(b)
  end)
  for _,renderer in ipairs(ready)do if Dropped.request(pawn,renderer,hand)then break end end
 end
 queued={}
 for _,renderer in ipairs(ready)do
 local items,requests=renderer.drops()
 local present={};for _,item in ipairs(items or{})do present[item.id]=true end
 for token,request in pairs(pending)do
  if request.owner==renderer.owner()and not present[request.id]then pending[token]=nil end
 end
 local root=renderer.root()
 for _,request in ipairs(requests or{})do
  if request.owner==own and root then
   for _,entry in ipairs(state.actors)do
    if entry.id==request.id and not entry.granted and live(entry)and not entry.actor.bHidden
      and distance(entry.actor:K2_GetActorLocation(),root)<=240^2 then
     entry.granted=renderer.owner()
     entry.granted_at=clock
     entry.actor:SetActorHiddenInGame(true);entry.actor:SetActorEnableCollision(false);entry.actor:SetActorTickEnabled(false)
    end
   end
  end
 end
 -- A cleared request acknowledges native pickup on the receiver. Retire its
 -- old hidden source copy after a grace period, keeping the item ID unique
 -- for this life so delayed packets cannot claim a later dropped weapon.
 for name,entry in pairs(tracked)do
  if entry.granted and entry.granted==renderer.owner()and clock-(entry.granted_at or clock)>=1 then
   local requested=false
   for _,request in ipairs(requests or{})do if request.owner==own and request.id==entry.id then requested=true;break end end
   if not requested then
    if live(entry)then entry.actor:K2_DestroyActor()end
    tracked[name]=nil
   end
  end
 end
 for _,item in ipairs(items or{})do
  local token=renderer.owner()..':'..item.id;local request=pending[token]
  if item.grant==own and request and not consumed[token]and free_hand(pawn,request.hand)then
   Equipment=Equipment or dofile(require('paths').scripts..'/equipment.lua')
   local ok,err=pcall(Equipment.pickup,pawn,item,request.hand)
   if ok then consumed[token]=true;pending[token]=nil
   elseif request.error~=tostring(err)then request.error=tostring(err);print('[HalfSwordMP] Pickup: '..tostring(err)..'\n')end
  end
 end
 end -- each remote owner
end
return Dropped
