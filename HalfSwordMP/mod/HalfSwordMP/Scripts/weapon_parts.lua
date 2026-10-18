-- Portable fields from the demo's own Str_WeaponParts save structure.
local Parts={}
local assets={
 grip_mesh='GripMesh_39_EDA3307B485303C5BF981B82D8462D0A',
 grip='GripModule_38_15B14C3F4E9701389A9B35A3B0909867',
 head='HeadModule_19_B043442745EED9AD1BE7929F0A06DB8F',
 guard='GuardModule_21_774015784EB0300D2671C894D57ED144',
 pommel='PommelModule_22_4F6D0ABC4AA88CF780EE1C9649F96984',
 sub1='HeadSubModule1_28_EA08538346D6DADCE01E8B8B7B50A9A0',
 sub2='HeadSubModule2_29_491313E24CE70DD60B5A6D88ED4B5980'}
local sizes={head='HeadSize_23_5DF30AE0493E534BD92D5B95E31E13CA',
 guard='GuardSize_24_7EB9BB3F4B7B54DD51CE529FEEA9A98D',
 pommel='PommelPommelSize_26_5B37388746A83FCB7A7833891C1C5524'}
local layers='MemberVar_40_43_0B501E224AC2292FC03A999C237C2C81'
local colors='MemberVar_44_45_FF627FBE4FE882E7D295BFA0BB6716C0'
local coat='COAInt_63_593665BE4EF020F95F7D1A92564C1239'
local function valid(o)return o~=nil and o:IsValid()end
function Parts.capture(w,slot,lines)
 local s=w['Str Weapon Parts'];local captured={}
 -- Preset weapons such as fists may not use a modular saved construction.
 if not valid(s[assets.grip])then return end
 for key,field in pairs(assets)do
  local a=s[field];local path=valid(a)and a:GetFullName():gsub('^%S+ ','')or'-'
  captured[#captured+1]=table.concat({'K',slot,key,path},'|')
 end
 for key,field in pairs(sizes)do
  local v=s[field]
  for _,n in ipairs({v.X,v.Y,v.Z})do if n~=n or n<=0 or n>100 then return end end
  captured[#captured+1]=table.concat({'Z',slot,key,v.X,v.Y,v.Z},'|')
 end
 s[layers]:ForEach(function(k,v)captured[#captured+1]=table.concat({'L',slot,k:get(),v:get()},'|')end)
 s[colors]:ForEach(function(k,v)local c=v:get();captured[#captured+1]=table.concat({'Y',slot,k:get(),c.R,c.G,c.B,c.A},'|')end)
 captured[#captured+1]=table.concat({'O',slot,s[coat]},'|')
 table.sort(captured);for _,line in ipairs(captured)do lines[#lines+1]=line end
end
function Parts.read(w,row)
 local tag=row[1]
 if not ({K=true,Z=true,L=true,Y=true,O=true})[tag]then return false end
 w.construction=w.construction or {assets={},sizes={},layers={},colors={}}
 local p=w.construction
 if tag=='K'and #row==4 and assets[row[3]]then p.assets[row[3]]=row[4]
 elseif tag=='Z'and #row==6 and sizes[row[3]]then p.sizes[row[3]]={tonumber(row[4]),tonumber(row[5]),tonumber(row[6])}
 elseif tag=='L'and #row==4 then p.layers[#p.layers+1]={tonumber(row[3]),tonumber(row[4])}
 elseif tag=='Y'and #row==7 then p.colors[#p.colors+1]={tonumber(row[3]),tonumber(row[4]),tonumber(row[5]),tonumber(row[6]),tonumber(row[7])}
 elseif tag=='O'and #row==3 then p.coat=tonumber(row[3])
 else return false end
 return true
end
function Parts.apply(template,value)
 local s=template['Str Weapon Parts'];if not value then return s end
 for key,field in pairs(assets)do
  local path=value.assets[key];local a
  if path and path~='-'then
   a=StaticFindObject(path)
   if not valid(a)then LoadAsset(path:match('^(.+)%.[^%.]+$'));a=StaticFindObject(path)end
   assert(valid(a),'Native weapon module unavailable: '..path)
   if key=='grip_mesh'then assert(a:IsA('/Script/Engine.StaticMesh'),'Weapon grip must be a static mesh')
   else
    assert(a:IsA('/Script/CoreUObject.Class'),'Weapon module must be a class')
    local parent=a;local accepted=false
    local expected=key=='grip'and'Modular_Weapon_Grip_C'
      or((key=='sub1'or key=='sub2')and'Modular_Weapon_SubModule_C'or'Modular_Weapon_Module_C')
    while valid(parent)do
     local n=parent:GetFName():ToString()
     if n==expected then accepted=true;break end
     parent=parent:GetSuperStruct()
    end
    assert(accepted,'Weapon module must derive from the native part class')
   end
  end
  s[field]=a
 end
 for key,field in pairs(sizes)do local v=value.sizes[key];s[field]={X=v[1],Y=v[2],Z=v[3]}end
 s[layers]:Empty();for _,v in ipairs(value.layers)do s[layers]:Add(v[1],v[2])end
 s[colors]:Empty();for _,v in ipairs(value.colors)do s[colors]:Add(v[1],{R=v[2],G=v[3],B=v[4],A=v[5]})end
 s[coat]=value.coat
 return s
end
return Parts
