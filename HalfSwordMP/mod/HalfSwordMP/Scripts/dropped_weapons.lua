-- Keep tracking this life’s native weapons after the hands release them.
-- The owning game supplies physics; the peer displays the measured mesh poses.
local Dropped={}
local life,tracked,serial=nil,{},0
local function valid(o)return o~=nil and o:IsValid()end
local function path(o)return o:GetFullName():gsub('^%S+ ','')end
local function weapon(o)
 if not valid(o)then return false end
 local c=o:GetClass()
 while valid(c)do
  if c:GetFName():ToString()=='ModularWeaponBP_C'then return true end
  c=c:GetSuperStruct()
 end
 return false
end
function Dropped.update(pawn)
 local key=pawn:GetFullName()
 if life~=key then life,tracked,serial=key,{},0 end
 local held,signature={},{}
 for _,field in ipairs({'Weapon R','Weapon L','Grab Component R','Grab Component L'})do
  local o=pawn[field]
  if valid(o)then
   local a=o:IsA('/Script/Engine.Actor')and o or o:GetOwner()
   if weapon(a)then
    local name=a:GetFullName();held[name]=true
    signature[#signature+1]=field..'='..name
    -- A bounded life inventory, without a world-wide object scan on each tick.
    if not tracked[name]and serial<16 then
     serial=serial+1;tracked[name]={actor=a,id='drop'..serial}
    end
   end
  end
 end
 local state={signature=table.concat(signature,'|'),actors={},names={}}
 for name,entry in pairs(tracked)do
  if not valid(entry.actor)then tracked[name]=nil
  elseif not held[name]then
   state.actors[#state.actors+1]=entry;state.names[name]=true
  end
 end
 table.sort(state.actors,function(a,b)return a.id<b.id end)
 return state
end
function Dropped.capture(state,lines,packed,capture_mesh,budget)
 local count=0
 for _,entry in ipairs(state.actors)do
  local actor=entry.actor
  if not actor.bHidden then
   if not entry.components then
    entry.components={}
    for _,r in ipairs(actor:K2_GetComponentsByClass(StaticFindObject('/Script/Engine.StaticMeshComponent')))do
     local c=r:get()
     if valid(c)then entry.components[#entry.components+1]=c end
    end
   end
   for index,c in ipairs(entry.components)do
    local asset=valid(c)and c.StaticMesh
    if count<budget and valid(asset)and c:IsVisible()and not c.bHiddenInGame then
     local name=path(asset)
     if name:match('^/Game/Assets/Weapons/')and not name:find('/Collisions/',1,true)then
      local t=c:K2_GetComponentToWorld();local p=t.Translation
      if math.abs(p.X)<=10000000 and math.abs(p.Y)<=10000000 and math.abs(p.Z)<=10000000 then
       local id=entry.id..'_'..index
       lines[#lines+1]='C|'..id..'|D|'..name..'|'..packed(t)
       capture_mesh(lines,c,id,false,false,true);count=count+1
      end
     end
    end
   end
  end
 end
 return count
end
return Dropped
