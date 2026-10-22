-- Portable visual state only. No UObject pointers leave this process.
local Avatar = {}
local appearance_cache,shared_cache = {},{}
local inventory_cache
_G.HSMPAvatarOwner=_G.HSMPAvatarOwner or {}
local Effects=dofile(require("paths").scripts.."/effects.lua")
local Geometry=dofile(require("paths").scripts.."/geometry.lua")
local Equipment=dofile(require("paths").scripts.."/equipment.lua")
local Cosmetics=dofile(require('paths').scripts..'/cosmetics.lua')
local Injury=dofile(require('paths').scripts..'/injury.lua')
local Movement=dofile(require('paths').scripts..'/movement.lua')
local Dropped=dofile(require('paths').scripts..'/dropped_weapons.lua')
local Voice=dofile(require('paths').scripts..'/voice.lua')
_G.HSMPDropped=Dropped
local previous_motion
local physical_bones,physical_mesh
local function valid(o) return o ~= nil and o:IsValid() end
local function path(o) return o:GetFullName():gsub("^%S+ ", "") end
local function safe(s) return #s <= 240 and s:match("^[%w_./:%-]+$") ~= nil end
local function packed(t)
    local p,q,s=t.Translation,t.Rotation,t.Scale3D
    -- Native hand/slot setup briefly exposes uninitialized mesh transforms.
    -- One zero quaternion must not invalidate the whole moving fighter packet.
    for _,row in ipairs({{p.X,p.Y,p.Z,10000000},{q.X,q.Y,q.Z,1.01},{s.X,s.Y,s.Z,100}})do
        for i=1,3 do if row[i]~=row[i]or math.abs(row[i])>row[4]then return end end
    end
    local norm=q.X*q.X+q.Y*q.Y+q.Z*q.Z+q.W*q.W
    if q.W~=q.W or math.abs(q.W)>1.01 or norm<.95 or norm>1.05 then return end
    return string.format("%.2f|%.2f|%.2f|%.5f|%.5f|%.5f|%.5f|%.4f|%.4f|%.4f",
        p.X,p.Y,p.Z,q.X,q.Y,q.Z,q.W,s.X,s.Y,s.Z)
end
function Avatar.owner(pawn)
    local state=_G.HSMPAvatarOwner
    state.ids=state.ids or {}
    local key=path(pawn)
    if not state.ids[key] then
        local slot=_G.HSMPParty and _G.HSMPParty.slot()or 1
        state.ids[key]=(slot-1)*600000+math.random(1,599999)
    end
    return state.ids[key]
end
function Avatar.part_id(c)
    if not valid(c) or not inventory_cache then return nil end
    local name=path(c)
    if name==inventory_cache.body then return "body" end
    if inventory_cache.part_ids[name] then return inventory_cache.part_ids[name] end
    local owner=c:GetOwner()
    return valid(owner) and inventory_cache.owner_ids[path(owner)] or nil
end
function Avatar.contact_id(c)
    if not valid(c) then return end
    local id=Geometry.id(c)
    if id then return 'geometry:'..id end
    return Avatar.part_id(c)
end

local function material_path(material)
    for _ = 1, 8 do
        if not valid(material) then return "-" end
        if not material:IsA("/Script/Engine.MaterialInstanceDynamic") then
            local p = path(material)
            return safe(p) and p or "-"
        end
        material = material.Parent
    end
    return "-"
end

local function capture_parameters(lines, material, id, slot)
    local seen,depth,count = {},0,0
    while valid(material) and material:IsA("/Script/Engine.MaterialInstance") and depth < 8 do
        depth = depth + 1
        for _,kind in ipairs({"ScalarParameterValues","VectorParameterValues"}) do
            local parameters=material[kind]
            for index=1,#parameters do
                local p = parameters[index]
                local name = p.ParameterInfo.Name:ToString()
                local association,index = p.ParameterInfo.Association,p.ParameterInfo.Index
                local key = name..":"..association..":"..index
                if #name <= 64 and name:match("^[%w_ ./:%-]+$") and not seen[key] and count < 64
                    and not Cosmetics.view_dependent(name)then
                    seen[key],count = true,count+1
                    local value = p.ParameterValue
                    if kind == "ScalarParameterValues" then
                        lines[#lines+1] = string.format("P|%s|%d|%s|%d|%d|%.5f",id,slot,name,association,index,value)
                    else
                        lines[#lines+1] = string.format("P|%s|%d|%s|%d|%d|%.5f|%.5f|%.5f|%.5f",id,slot,name,association,index,value.R,value.G,value.B,value.A)
                    end
                end
            end
        end
        material = material.Parent
    end
end

local function capture_mesh(lines, c, id, skinned, shared,native)
    if native and id=='body' then
        local mesh=path(c:GetSkeletalMeshAsset())
        if mesh~=physical_mesh then
            physical_mesh,physical_bones=mesh,{}
            local bodies=c:GetSkeletalMeshAsset():GetPhysicsAsset().SkeletalBodySetups
            for i=1,#bodies do
                local text=bodies[i].BoneName:ToString();physical_bones[#physical_bones+1]={bone=FName(text),text=text}
            end
        end
        for _,entry in ipairs(physical_bones)do
            local t=packed(c:GetSocketTransform(entry.bone,0))
            if t then lines[#lines+1]='B|body|'..entry.text..'|'..t end
        end
    end
    if skinned and not shared and not native then
        for i = 0, math.min(c:GetNumBones(),128) - 1 do
            local n = c:GetBoneName(i)
            local text = n:ToString()
            if safe(text) and #text <= 64 then
                if not shared then
                    local t=packed(c:GetSocketTransform(n,0))
                    if t then lines[#lines+1] = "B|"..id.."|"..text.."|"..t end
                end
                if c:IsBoneHiddenByName(n) then lines[#lines+1] = "H|"..id.."|"..text end
            end
        end
    end
    local key,now = path(c),os.time()
    local cached = appearance_cache[key]
    if cached and cached.time == now and cached.id == id then
        for _,line in ipairs(cached.lines) do lines[#lines+1] = line end
        return
    end
    local first = #lines+1
    if shared or (native and skinned) then
        for i=0,math.min(c:GetNumBones(),128)-1 do
            local n=c:GetBoneName(i)
            if c:IsBoneHiddenByName(n) then lines[#lines+1] = "H|"..id.."|"..n:ToString() end
        end
    end
    for i = 0, math.min(c:GetNumMaterials(),16) - 1 do
        local material = c:GetMaterial(i)
        lines[#lines+1] = "M|"..id.."|"..i.."|"..material_path(material)
        capture_parameters(lines,material,id,i)
    end
    local saved = {}
    for i = first,#lines do saved[#saved+1] = lines[i] end
    appearance_cache[key] = {time=now,id=id,lines=saved}
end

function Avatar.capture(pawn, serial,native)
    if not valid(pawn) or pawn:GetClass():GetFName():ToString() ~= "Willie_BP_C" then return nil end
    local source = pawn.Mesh
    if not valid(source) or not valid(source:GetSkeletalMeshAsset()) then return nil end
    local loc,rot = pawn:K2_GetActorLocation(),pawn:K2_GetActorRotation()
    local lines = {string.format("HSMP2|%d|%s|%s|%.2f|%.2f|%.2f|%.2f|%.2f|%.2f",
        serial,path(pawn:GetWorld()),path(source:GetSkeletalMeshAsset()),
        loc.X,loc.Y,loc.Z,rot.Pitch,rot.Yaw,rot.Roll)}
    local velocity
    velocity,previous_motion=Movement.capture(previous_motion,pawn:GetFullName(),{loc.X,loc.Y,loc.Z},
        require('UEHelpers').GetGameplayStatics():GetRealTimeSeconds(pawn:GetWorld()))
    lines[#lines+1]=string.format('S|%.3f|%.3f|%.3f',velocity[1],velocity[2],velocity[3])
    capture_mesh(lines,source,"body",true,false,native)
    local dropped=Dropped.update(pawn)
    local now,pawn_key = os.time(),path(pawn)
    local entries
    if inventory_cache and inventory_cache.pawn==pawn_key then
        for _,e in ipairs(inventory_cache.entries)do
            if not valid(e.c)or path(e.c)~=e.identity then inventory_cache=nil;break end
        end
    end
    if inventory_cache and inventory_cache.pawn == pawn_key and inventory_cache.time == now
        and inventory_cache.held_signature==dropped.signature then
        entries = inventory_cache.entries
    else
    if not inventory_cache or inventory_cache.pawn ~= pawn_key then appearance_cache,shared_cache = {},{} end
    entries = {}
    local seen, count, total_bones = {[path(source)]=true},0,source:GetNumBones()
    local function add(c,kind)
        if not valid(c) or not c:IsA("/Script/Engine.MeshComponent") then return end
        local key = path(c)
        if seen[key] then return end
        seen[key] = true
        if count >= 48 or not c:IsVisible() or c.bHiddenInGame then return end
        local skinned = c:IsA("/Script/Engine.SkinnedMeshComponent")
        local asset
        if skinned then asset = c:GetSkinnedAsset()
        elseif c:IsA("/Script/Engine.StaticMeshComponent") then asset = c.StaticMesh end
        if not valid(asset) or not safe(path(asset)) then return end
        -- Damage collision helpers are flagged visible but parked far underground.
        if path(asset):find("/Collisions/",1,true) then return end
        local world_transform = c:K2_GetComponentToWorld()
        if math.abs(world_transform.Translation.X) > 10000000 or math.abs(world_transform.Translation.Y) > 10000000
            or math.abs(world_transform.Translation.Z) > 10000000 then return end
        local shared = false
        if skinned then
            local cached = shared_cache[key]
            local now = os.time()
            if not cached or cached.time ~= now then
                local n = c:GetNumBones()
                shared = n > 0 and n <= source:GetNumBones()
                -- This game's armor uses copied animation poses, rather than LeaderPoseComponent.
                -- Verify samples before sharing the body's pose, including smaller helmet rigs.
                for _,index in ipairs({0,math.floor(n/2),n-1}) do
                    if shared then
                        local bone = c:GetBoneName(index)
                        if source:GetBoneIndex(bone) < 0 then shared = false
                        else
                            local a,b = c:GetSocketTransform(bone,0),source:GetSocketTransform(bone,0)
                            shared = math.abs(a.Translation.X-b.Translation.X)<0.05
                                and math.abs(a.Translation.Y-b.Translation.Y)<0.05
                                and math.abs(a.Translation.Z-b.Translation.Z)<0.05
                                and math.abs(math.abs(a.Rotation.X*b.Rotation.X+a.Rotation.Y*b.Rotation.Y
                                    +a.Rotation.Z*b.Rotation.Z+a.Rotation.W*b.Rotation.W)-1)<0.001
                        end
                    end
                end
                shared_cache[key] = {time=now,value=shared}
            else shared = cached.value end
        end
        if skinned and not shared then
            if total_bones + c:GetNumBones() > 2048 then return end
            total_bones = total_bones + c:GetNumBones()
        end
        count = count + 1
        local id = "part"..count
        entries[#entries+1] = {c=c,identity=key,id=id,kind=kind or(shared and "L" or skinned and "K" or "S"),asset=path(asset),skinned=skinned,shared=shared}
    end
    local function owner(o,kind)
        if dropped.names[o:GetFullName()]then return end
        local array = o:K2_GetComponentsByClass(StaticFindObject("/Script/Engine.MeshComponent"))
        if type(array) == "table" then
            for _, c in ipairs(array) do add(c:get(),kind) end
        else for i=1,#array do add(array[i],kind)end end
    end
    owner(pawn)
    -- Physics-constrained held items may not appear in GetAttachedActors.
    for _, property in ipairs({"Grab Component R","Grab Component L","Weapon R","Weapon L"}) do
        pcall(function()
            local o = pawn[property]
            if valid(o) then
                if o:IsA("/Script/Engine.Actor") then owner(o) else add(o) end
            end
        end)
    end
    -- A native inventory slot can still reference an unsheathed weapon. Held
    -- meshes take precedence, or the peer shows an extra stowed visual whose
    -- world-space interpolation separates it from the swinging hand.
    for _,field in ipairs({'Weapon Slot R 1','Weapon Slot R 2','Weapon Slot L 1','Weapon Slot L 2','Weapon Slot Back'})do
        local o=pawn[field];if valid(o)then owner(o,'T')end
    end
    local attached = {}
    pawn:GetAttachedActors(attached,true,true)
    for _, ref in ipairs(attached) do local o = ref:get(); if valid(o) then owner(o) end end
    inventory_cache = {pawn=pawn_key,time=now,held_signature=dropped.signature,entries=entries,body=path(source),part_ids={},owner_ids={}}
    for _,e in ipairs(entries) do
        inventory_cache.part_ids[path(e.c)]=e.id
        local o=e.c:GetOwner();if valid(o) and not inventory_cache.owner_ids[path(o)] then inventory_cache.owner_ids[path(o)]=e.id end
    end
    end
    for _,entry in ipairs(entries) do
        local c = entry.c
        if valid(c) then
            local t = c:K2_GetComponentToWorld()
            local transform=packed(t)
            if transform then
                lines[#lines+1] = "C|"..entry.id.."|"..entry.kind.."|"..entry.asset.."|"..transform
                capture_mesh(lines,c,entry.id,entry.skinned,entry.shared,native)
            end
        end
    end
    Dropped.capture(dropped,lines,packed,capture_mesh,48-#entries)
    local outcome=_G.HSMPSession and _G.HSMPSession.round_outcome and _G.HSMPSession.round_outcome(pawn)
    for key,property in pairs({health="Health",consciousness="Consciousness",head="Head Health",
        chest="Body Upper Health",abdomen="Body Lower Health",arm_r="Arm_R Health",arm_l="Arm_L Health",
        leg_r="Leg_R Health",leg_l="Leg_L Health",neck="Neck Health",dead="DED",headless="Headless",
        blood_rate="Blood Rate",bloody_feet="BloodyFeetAlpha",give_up="Give Up"}) do
        pcall(function()
            local value = pawn[property]
            -- Keep a native KO visible to the round coordinator even if native
            -- regeneration raises consciousness before the next 30 Hz capture.
            if key=='consciousness'and _G.HSMPSession and _G.HSMPSession.in_match and _G.HSMPSession.in_match()then
                value=(outcome=='unconscious'or outcome=='incapacitated')and 0 or math.max(.001,value)
            elseif outcome=='dead'and key=='health'then value=0
            elseif key=='give_up'and _G.HSMPSession and _G.HSMPSession.in_match and _G.HSMPSession.in_match()then
                -- Native Give Up means the meter has started, not finished.
                value=outcome=='gave_up'and 1 or 0
            end
            if type(value) == "boolean" then value = value and 1 or 0 end
            if type(value) == "number" and value == value and math.abs(value) <= 10000000 then
                lines[#lines+1] = string.format("V|%s|%.4f",key,value)
            end
        end)
    end
    lines[#lines+1]="V|owner_id|"..Avatar.owner(pawn)
    if _G.HSMPSession and _G.HSMPSession.injury_source then
        local target,owner,defeat=_G.HSMPSession.injury_source()
        Injury.capture(target,lines,owner,Avatar.owner(pawn),serial,defeat)
    end
    -- Both native fighters already render blood from the relayed native injury.
    -- Sending their Niagara streams back duplicates those effects and CPU work.
    if not native then Effects.capture(pawn,lines,packed)end
    Geometry.capture(pawn,lines,packed,native,dropped.signature)
    Equipment.capture(pawn,lines,Geometry,Avatar.part_id,inventory_cache)
    Voice.install();Voice.capture(pawn,lines)
    lines[#lines+1] = "E|"..serial.."|"..#lines
    local text = table.concat(lines,"\n").."\n"
    return #text <= 262144 and text or nil
end
return Avatar

