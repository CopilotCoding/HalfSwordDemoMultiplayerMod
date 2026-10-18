-- Load only mesh content from the installed demo for a different remote loadout.
local Assets={}
local attempted={}
local second,count,total=0,0,0
local function valid(o)return o~=nil and o:IsValid()end
function Assets.mesh(name,skinned)
    local expected=skinned and "/Script/Engine.SkeletalMesh" or "/Script/Engine.StaticMesh"
    local asset=StaticFindObject(name)
    if valid(asset) then return asset:IsA(expected) and asset or nil end
    local allowed=name:match("^/Game/Character/Skeleton/[%w_./%-]+$")
        or name:match("^/Game/Assets/Character/[%w_./%-]+$")
        or name:match("^/Game/Assets/Armor/[%w_./%-]+$")
        or name:match("^/Game/Assets/Clothing/[%w_./%-]+$")
        or name:match("^/Game/Assets/Weapons/[%w_./%-]+$")
    if not allowed or name:find("..",1,true) or #name>240 or attempted[name] or total>=64 then return nil end
    local now=os.time();if second~=now then second,count=now,0 end
    if count>=2 then return nil end
    count,total=count+1,total+1;attempted[name]=true
    LoadAsset(name:gsub("%.[^.]+$",""))
    asset=StaticFindObject(name)
    return valid(asset) and asset:IsA(expected) and asset or nil
end
return Assets
