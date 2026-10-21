-- Copy the native equipment's active collision shapes, including hidden helpers.
local Geometry={}
local cache,serial
local rendered={}
local paths=require("paths")
local Assets=dofile(paths.scripts.."/assets.lua")
local function valid(o)return o~=nil and o:IsValid()end
local function path(o)return o:GetFullName():gsub("^%S+ ","")end
local function safe(s)return #s<=240 and s:match("^[%w_./:%-]+$") and not s:find("..",1,true)end
local function equipment(a)
    if not valid(a) then return false end
    local c=a:GetClass()
    while valid(c) do
        local n=c:GetFName():ToString()
        if n=="ModularWeaponBP_C" or n=="BP_Armor_Master_C" or n=="Modular_Weapon_Part_Master_C" then return true end
        c=c:GetSuperStruct()
    end
    return false
end
function Geometry.capture(pawn,lines,packed,native,held_signature)
    local now,key=os.time(),path(pawn)
    if cache and cache.pawn==key then
        for _,g in ipairs(cache.entries)do
            if not valid(g.c)or path(g.c)~=g.identity then cache.time=-1;break end
        end
    end
    if not cache or cache.pawn~=key or cache.time~=now or cache.held_signature~=held_signature then
        local old=cache and cache.pawn==key and cache.ids or {}
        serial=cache and cache.pawn==key and serial or 0
        cache={pawn=key,time=now,held_signature=held_signature,entries={},ids={}}
        local seen={}
        local function add(a)
            if not equipment(a) or seen[path(a)] then return end
            seen[path(a)]=true
            for _,ref in ipairs(a:K2_GetComponentsByClass(StaticFindObject("/Script/Engine.PrimitiveComponent"))) do
                local c=ref:get()
                if valid(c) and #cache.entries<96 then
                    local shape,asset,size
                    if c:IsA("/Script/Engine.CapsuleComponent") then
                        shape,asset,size="capsule","-",{c:GetUnscaledCapsuleRadius(),c:GetUnscaledCapsuleHalfHeight(),0}
                    elseif c:IsA("/Script/Engine.BoxComponent") then
                        local e=c:GetUnscaledBoxExtent();shape,asset,size="box","-",{e.X,e.Y,e.Z}
                    elseif c:IsA("/Script/Engine.SphereComponent") then
                        shape,asset,size="sphere","-",{c:GetUnscaledSphereRadius(),0,0}
                    elseif c:IsA("/Script/Engine.StaticMeshComponent") and valid(c.StaticMesh) then
                        asset=path(c.StaticMesh)
                        if safe(asset) and (asset:match("^/Game/Assets/Weapons/") or asset:match("^/Game/Assets/Armor/")) then
                            shape,size="mesh",{0,0,0}
                        end
                    end
                    if shape then
                        local id=old[path(c)]
                        if not id then serial=serial+1;id="geom"..serial end
                        cache.ids[path(c)]=id
                        cache.entries[#cache.entries+1]={c=c,identity=path(c),id=id,shape=shape,asset=asset,size=size}
                    end
                end
            end
        end
        for _,property in ipairs({"Weapon R","Weapon L","Grab Component R","Grab Component L"}) do
            local o=pawn[property]
            if valid(o) then add(o:IsA("/Script/Engine.Actor") and o or o:GetOwner()) end
        end
        local attached={};pawn:GetAttachedActors(attached,true,true)
        for _,ref in ipairs(attached) do add(ref:get()) end
    end
    local first=#lines+1
    local p=pawn:K2_GetActorLocation()
    for _,g in ipairs(cache.entries) do
        local c=g.c
        if valid(c) then
            local mode=c:GetCollisionEnabled()
            local t=c:K2_GetComponentToWorld();local v=t.Translation
            local transform=packed(t)
            -- Native disabled helpers may be parked below the map. Do not copy them.
            if transform and mode>=1 and mode<=3 and (v.X-p.X)^2+(v.Y-p.Y)^2+(v.Z-p.Z)^2<25000000 then
                if not g.responses then
                    local responses={};for channel=0,31 do responses[#responses+1]=tostring(c:GetCollisionResponseToChannel(channel))end
                    g.responses=table.concat(responses);g.material='-'
                    pcall(function()
                    local m=c.BodyInstance.PhysMaterialOverride
                    if valid(m) and safe(path(m)) and path(m):match("^/Game/") then g.material=path(m) end
                    end)
                end
                lines[#lines+1]=table.concat({"G",g.id,g.shape,g.asset,transform,
                    g.size[1],g.size[2],g.size[3],c:GetCollisionObjectType(),g.responses,g.material,mode},"|")
            end
        end
    end
    if native then cache.lines={};for i=first,#lines do cache.lines[#cache.lines+1]=lines[i] end end
end
local function release(c,own)
    if not valid(c) or not valid(own) then return end
    -- A native hand can hold a remote shape. Release only that constraint before
    -- destroying its body; leave every unrelated native handle untouched.
    for _,ref in ipairs(own:K2_GetComponentsByClass(StaticFindObject("/Script/Engine.PhysicsHandleComponent"))) do
        local h=ref:get();local held=valid(h) and h:GetGrabbedComponent() or nil
        if valid(held) and path(held)==path(c) then h:ReleaseComponent() end
    end
end
function Geometry.destroy(own)
    for _,g in pairs(rendered) do
        if valid(g.c) then release(g.c,own);g.c:K2_DestroyComponent(g.actor) end
    end
    rendered={}
end
function Geometry.prepare(actor,pawn,rows,identity)
    local present={}
    for _,v in ipairs(rows) do
        if v[1]=="G" and #v==21 then
            local id,shape=v[2],v[3]
            local signature=table.concat({shape,v[4],v[15],v[16],v[17],v[18],v[19],v[20],v[21]},"|")
            local g=rendered[id]
            if g and (g.signature~=signature or not valid(g.c)) then
                if valid(g.c) then release(g.c,pawn);g.c:K2_DestroyComponent(g.actor) end
                rendered[id]=nil;g=nil
            end
            if not g then
                local classes={box="BoxComponent",sphere="SphereComponent",capsule="CapsuleComponent",mesh="StaticMeshComponent"}
                local class=classes[shape] and StaticFindObject("/Script/Engine."..classes[shape])
                local asset=shape=="mesh" and Assets.mesh(v[4],false) or nil
                if valid(class) and (shape~="mesh" or valid(asset)) then
                    local t=identity(pawn.Mesh)
                    local c=actor:AddComponentByClass(class,true,t,true)
                    c:SetMobility(2)
                    if shape=="box" then c:SetBoxExtent({X=tonumber(v[15]),Y=tonumber(v[16]),Z=tonumber(v[17])},false)
                    elseif shape=="sphere" then c:SetSphereRadius(tonumber(v[15]),false)
                    elseif shape=="capsule" then c:SetCapsuleSize(tonumber(v[15]),tonumber(v[16]),false)
                    else c:SetStaticMesh(asset) end
                    c:SetCollisionEnabled(0)
                    actor:FinishAddComponent(c,true,t)
                    c:SetHiddenInGame(true,false);c:SetVisibility(false,false)
                    c:SetCollisionObjectType(tonumber(v[18]))
                    for channel=0,31 do c:SetCollisionResponseToChannel(channel,tonumber(v[19]:sub(channel+1,channel+1))) end
                    local material=v[20]~="-" and StaticFindObject(v[20]) or nil
                    if valid(material) and material:IsA("/Script/PhysicsCore.PhysicalMaterial") then c:SetPhysMaterialOverride(material) end
                    g={c=c,actor=actor,signature=signature,mode=tonumber(v[21]),started=false};rendered[id]=g
                end
            end
            if g then present[id]=true end
        end
    end
    for id,g in pairs(rendered) do
        if not present[id] then
            if valid(g.c) then release(g.c,pawn);g.c:K2_DestroyComponent(g.actor) end
            rendered[id]=nil
        end
    end
end
function Geometry.draw(transforms,template)
    for id,t in pairs(transforms) do
        local g=rendered[id]
        if g and valid(g.c) then
            template.Translation.X,template.Translation.Y,template.Translation.Z=t[1],t[2],t[3]
            template.Rotation.X,template.Rotation.Y,template.Rotation.Z,template.Rotation.W=t[4],t[5],t[6],t[7]
            template.Scale3D.X,template.Scale3D.Y,template.Scale3D.Z=t[8],t[9],t[10]
            g.c:K2_SetWorldTransform(template,false,{},not g.started)
            if not g.started then g.c:SetCollisionEnabled(g.mode);g.started=true end
        end
    end
end
function Geometry.count()local n=0;for _ in pairs(rendered) do n=n+1 end;return n end
function Geometry.id(c)return cache and cache.ids[path(c)] end
return Geometry
