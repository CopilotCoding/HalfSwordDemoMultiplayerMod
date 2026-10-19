-- Replay a confirmed native sever, using only this life’s native components.
local S={}
local pending={}
function S.reset()pending={}end
local Math=dofile(require('paths').scripts..'/rig_math.lua')
local function valid(o)return o~=nil and o:IsValid()end
local function packed(t)local a,q,s=t.Translation,t.Rotation,t.Scale3D
 return {a.X,a.Y,a.Z,q.X,q.Y,q.Z,q.W,s.X,s.Y,s.Z}end
local function transform(t)
 if #t~=10 then return false end
 for _,n in ipairs(t)do if type(n)~='number'or n~=n or math.abs(n)>1e7 then return false end end
 local q=t[4]^2+t[5]^2+t[6]^2+t[7]^2
 return q>=.95 and q<=1.05 and t[8]>0 and t[8]<=100 and t[9]>0 and t[9]<=100 and t[10]>0 and t[10]<=100
end
local function component_name(s)return type(s)=='string'and #s<=64 and s:match('^[%w_ %-]+$')end
function S.capture(context,a,source,frame_getter,victim)
 if not valid(a[1]:get())or a[1]:get():GetFullName()~=context.Mesh:GetFullName()then return end
 local part,marker,weapon=a[2]:get(),a[3]:get(),a[7]:get()
 local id=valid(weapon)and source(weapon)
 if type(part)~='number'or part<0 or part>14 or part%1~=0 or not valid(marker)or not id then return end
 -- UE4SS cannot safely dereference this Blueprint's by-reference UObject
 -- array in a script hook. Read owned native markers on the normal tick instead.
 return {part=part,marker=marker,source=id,box1=a[5]:get(),box2=a[6]:get(),context=context,victim=victim,frame_getter=frame_getter}
end
function S.encode(e,seq)
 if not valid(e.context)or not valid(e.marker)or not valid(e.box1)or not valid(e.box2)then return end
 local confirmed=false;e.context['Dismembered Parts Map']:ForEach(function(k,v)if k:get()==e.part and v:get()then confirmed=true end end)
 if not confirmed then return end
 local bone=e.marker:GetAttachSocketName():ToString();local frame=e.frame_getter(bone)
 if not frame then return end
 local marker=e.marker:GetFName():ToString();if not component_name(marker)then return end
 local names={marker}
 for _,r in ipairs(e.context:K2_GetComponentsByClass(StaticFindObject('/Script/Engine.SphereComponent')))do
  local c=r:get()
  if valid(c)and c:GetFName():ToString()~=marker and #names<32 then
   local name=c:GetFName():ToString();local socket=c:GetAttachSocketName()
   if name:sub(1,10)=='DM Sphere 'and (socket:ToString()==bone or e.context.Mesh:BoneIsChildOf(socket,FName(bone)))then
    names[#names+1]=name
   end
  end
 end
 local row={'S',seq,e.victim,e.part,marker,e.source,bone}
 for _,v in ipairs(frame)do row[#row+1]=v end
 for _,box in ipairs({e.box1,e.box2})do
  for _,v in ipairs(packed(box:K2_GetComponentToWorld()))do row[#row+1]=v end
  local s=box:GetUnscaledBoxExtent();row[#row+1]=s.X;row[#row+1]=s.Y;row[#row+1]=s.Z
 end
 row[#row+1]=#names
 for _,n in ipairs(names)do if not component_name(n)then return end;row[#row+1]=n end
 return row
end
function S.replay(row,own,owner,resolve,make_box)
 if row[1]~='S'or #row<44 or tonumber(row[3])~=owner then return end
 local seq,part,count=tonumber(row[2]),tonumber(row[4]),tonumber(row[44])
 if not seq or seq<1 or seq%1~=0 or not part or part<0 or part>14 or part%1~=0
  or not count or count<0 or count>32 or count%1~=0 or #row~=44+count or not component_name(row[5])then return end
 if #row[6]>64 or not row[6]:match('^[%w_./:%-]+$')or #row[7]>64 or not row[7]:match('^[%w_./:%-]+$')then return end
 local already=false;own['Dismembered Parts Map']:ForEach(function(k,v)if k:get()==part and v:get()then already=true end end)
 if already then return true end
 for _,e in ipairs(pending)do
  if e.part==part and valid(e.own)and e.own:GetFullName()==own:GetFullName()then return true end
 end
 local source=resolve(row[6]);if not valid(source)then return end
 local from={};for i=8,17 do from[#from+1]=tonumber(row[i])end;if not transform(from)then return end
 local descriptions={}
 for _,start in ipairs({18,31})do
  local t={};for i=start,start+9 do t[#t+1]=tonumber(row[i])end;if not transform(t)then return end
  local size={};for i=start+10,start+12 do local n=tonumber(row[i]);if not n or n~=n or n<0 or n>10000 then return end;size[#size+1]=n end
  descriptions[#descriptions+1]={t=t,size=size}
 end
 local by_name={}
 for _,r in ipairs(own:K2_GetComponentsByClass(StaticFindObject('/Script/Engine.PrimitiveComponent')))do
  local c=r:get();if valid(c)then by_name[c:GetFName():ToString()]=c end
 end
 local marker=by_name[row[5]];if not valid(marker)or marker:GetAttachSocketName():ToString()~=row[7]then return end
 local overlaps={}
 for i=45,#row do if not component_name(row[i])or not valid(by_name[row[i]])then return end;overlaps[#overlaps+1]=by_name[row[i]]end
 local bone=FName(row[7]);if own.Mesh:GetBoneIndex(bone)<0 then return end
 local to=packed(own.Mesh:GetSocketTransform(bone,0));local boxes={}
 for _,d in ipairs(descriptions)do boxes[#boxes+1]=make_box(Math.transform(d.t,from,to),d.size,bone)end
 pending[#pending+1]={own=own,part=part,marker=marker,overlaps=overlaps,boxes=boxes,source=source}
 return true
end
function S.update(own)
 local e=pending[1];if not e then return 0,0 end
 if not valid(e.own)or e.own:GetFullName()~=own:GetFullName()then table.remove(pending,1);return 0,0 end
 if not valid(e.marker)or not valid(e.source)or not valid(e.boxes[1])or not valid(e.boxes[2])then
  table.remove(pending,1);return 0,1
 end
 local done=false;own['Dismembered Parts Map']:ForEach(function(k,v)if k:get()==e.part and v:get()then done=true end end)
 if done then table.remove(pending,1);return 1,0 end
 if not e.started then
  e.started=os.clock()
  -- Native Initiate collects the owner's current vertex paint asynchronously.
  -- Delayed alone sets the limb flag but has no parent-mesh cut mask to use.
  own['Currently VP Painted Dismembered Mesh']:Empty()
  local invulnerable=own.Invulnerable;own.Invulnerable=false
  local ok,err=pcall(own['Dismember Function Initiate'],own,own.Mesh,e.part,e.marker,e.overlaps,e.boxes[1],e.boxes[2],e.source)
  own.Invulnerable=invulnerable
  if not ok then table.remove(pending,1);print('[HalfSwordMP] Sever preparation: '..tostring(err)..'\n');return 0,1 end
  return 0,0
 end
 local ready=false;local painted=own['Currently VP Painted Dismembered Mesh']
 for i=1,#painted do if painted[i].AmountOfVerticesAtLOD>0 then ready=true;break end end
 if ready then
  local ok,err=pcall(own['Dismember Function Delayed'],own,own.Mesh,e.part,e.marker,e.overlaps,e.boxes[1],e.boxes[2],e.source,{})
  table.remove(pending,1)
  if not ok then print('[HalfSwordMP] Native sever: '..tostring(err)..'\n');return 0,1 end
  return 1,0
 end
 if os.clock()-e.started>3 then table.remove(pending,1);print('[HalfSwordMP] Native sever paint preparation timed out\n');return 0,1 end
 return 0,0
end
return S
