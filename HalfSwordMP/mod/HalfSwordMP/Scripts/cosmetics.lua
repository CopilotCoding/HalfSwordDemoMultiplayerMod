-- Snapshot actual native cosmetic parameters. Zero saved dyes can mean random.
-- Textures, injury masks and camera-dependent hiding remain native state.
local Cosmetics={}
local function valid(o)return o~=nil and o:IsValid()end
local function cosmetic(name)
 name=name:lower()
 for _,word in ipairs({'blood','wound','damage','opacity','hide','hidden','camera','dither','fade','alpha'})do
  if name:find(word,1,true)then return false end
 end
 return true
end
local function meshes(pawn,weapons)
 local result={}
 for _,r in ipairs(pawn:K2_GetComponentsByClass(StaticFindObject(weapons and '/Script/Engine.MeshComponent'or'/Script/Engine.SkinnedMeshComponent')))do
  local c=r:get();local a
  if valid(c)then
   if weapons and c:IsA('/Script/Engine.StaticMeshComponent')then a=c.StaticMesh else a=c:GetSkinnedAsset()end
  end
  if valid(a)then result[#result+1]={component=c,asset=a:GetFullName()..(weapons and'|'..c:GetFName():ToString()or'')}end
 end
 return result
end
function Cosmetics.capture(pawn,weapons)
 local saved={}
 for _,entry in ipairs(meshes(pawn,weapons))do
  local slots={};saved[entry.asset]=slots
  for i=0,math.min(entry.component:GetNumMaterials(),16)-1 do
   local values,seen={},{};slots[i]=values
   local material=entry.component:GetMaterial(i)
   for depth=1,8 do
    if not valid(material)then break end
    if weapons and not material:IsA('/Script/Engine.MaterialInstanceDynamic')and not values.base then
     values.base=material:GetFullName():gsub('^%S+ ','')
    end
    if not material:IsA('/Script/Engine.MaterialInstance')then break end
    for _,kind in ipairs({'ScalarParameterValues','VectorParameterValues'})do
     material[kind]:ForEach(function(_,r)
      local p=r:get();local info=p.ParameterInfo;local name=info.Name:ToString()
      local key=name..':'..info.Association..':'..info.Index
      if cosmetic(name)and not seen[key]then
       seen[key]=true
       local value=p.ParameterValue
       if kind=='VectorParameterValues'then value={value.R,value.G,value.B,value.A}end
       values[#values+1]={name=name,association=info.Association,index=info.Index,value=value}
      end
     end)
    end
    material=material.Parent
   end
  end
 end
 return saved
end
function Cosmetics.restore(pawn,saved,weapons)
 for _,entry in ipairs(meshes(pawn,weapons))do
  for slot,values in pairs(saved and saved[entry.asset]or{})do
   if slot<entry.component:GetNumMaterials()then
    local material=entry.component:GetMaterial(slot)
    if valid(material)then
     if weapons and values.base then
      local base=StaticFindObject(values.base)
      if not valid(base)then LoadAsset(values.base:match('^(.+)%.[^%.]+$'));base=StaticFindObject(values.base)end
      local old=material
      for _=1,8 do if not valid(old)or not old:IsA('/Script/Engine.MaterialInstanceDynamic')then break end;old=old.Parent end
      if valid(base)and base:IsA('/Script/Engine.MaterialInterface')and(not valid(old)or old:GetFullName()~=base:GetFullName())then
       material=entry.component:CreateDynamicMaterialInstance(slot,base,FName('None'))
      end
     end
     if not material:IsA('/Script/Engine.MaterialInstanceDynamic')then
      material=entry.component:CreateDynamicMaterialInstance(slot,material,FName('None'))
     end
     if valid(material)then for _,p in ipairs(values)do
      local info={Name=FName(p.name),Association=p.association,Index=p.index}
      if type(p.value)=='table'then local v=p.value
       material:SetVectorParameterValueByInfo(info,{R=v[1],G=v[2],B=v[3],A=v[4]})
      else material:SetScalarParameterValueByInfo(info,p.value)end
     end end
    end
   end
  end
 end
end
return Cosmetics
