-- Game-thread-only adapter. The remote object is a non-colliding visual proxy.
local Pose = {}
local options=...
if type(options)~='table'then options={}end
local function session()return options.session or _G.HSMPSession end
function Pose.new(callbacks)
    return assert(loadfile(require('paths').scripts..'/pose.lua'))({secondary=true,session=callbacks})
end
local preview = false
local actor, component, actor_world, mesh_name
local last_counter = ""
local unchanged = 0
local serial = 0
local last_pelvis
local last_bones = {}
local body_transforms={}
local interpolation,draw_pawn
local parts = {}
local hidden = {}
local materials = {}
local expected_parameters = {}
local heartbeat,last_heartbeat_check,last_heartbeat_change = "",0,0
local local_off = false
local remote_owner,remote_root
local remote_vitals={}
local remote_velocity={0,0,0}
local remote_frame
local remote_equipment,remote_rows,remote_colliders
local remote_drops,remote_pickups={},{}
local Dropped=dofile(require('paths').scripts..'/dropped_weapons.lua')
local native_visible=false
local Voice=dofile(require('paths').scripts..'/voice.lua')
local remote_voice,voice_updated={},-100
function Pose.voice()return remote_voice,voice_updated end
local appearance_signature
local cosmetic_signature
local appearance_version=0
local appearance_updated=-100
local last_remote_valid=-100
local bone_names={}
local last_capture_time,last_capture_pawn,last_capture_text=-100,"",nil
local Effects=dofile(require("paths").scripts.."/effects.lua")
local Assets=dofile(require("paths").scripts.."/assets.lua")
local Geometry=dofile(require("paths").scripts.."/geometry.lua")
local Interpolation=dofile(require("paths").scripts.."/interpolation.lua")
local Held=dofile(require('paths').scripts..'/held_pose.lua')
local Equipment=dofile(require("paths").scripts.."/equipment.lua")
local Cosmetics=dofile(require('paths').scripts..'/cosmetics.lua')

local function valid(obj) return obj ~= nil and obj:IsValid() end
local function path(obj) return obj:GetFullName():gsub("^%S+ ", "") end
local function fields(line)
    local values = {}
    for value in line:gmatch("[^|]+") do values[#values + 1] = value end
    return values
end
local function identity(source)
    -- FTransform has native fields in this build. Use an Unreal-owned value:
    -- marshaling a plain Lua table can silently leave its scale at zero.
    local result = source:GetSocketTransform(FName("Root"), 0)
    result.Translation.X,result.Translation.Y,result.Translation.Z = 0,0,0
    result.Rotation.X,result.Rotation.Y,result.Rotation.Z,result.Rotation.W = 0,0,0,1
    result.Scale3D.X,result.Scale3D.Y,result.Scale3D.Z = 1,1,1
    return result
end

function Pose.destroy()
    Geometry.destroy(draw_pawn)
    if valid(actor) then actor:K2_DestroyActor() end
    actor, component, actor_world, mesh_name = nil, nil, nil, nil
    last_pelvis = nil
    last_bones = {}
    body_transforms={};interpolation,draw_pawn=nil,nil
    parts,hidden,materials,expected_parameters = {},{},{},{}
    Effects.destroy()
    remote_owner,remote_root=nil,nil
    remote_vitals={}
    remote_velocity={0,0,0}
    remote_frame=nil
    remote_equipment,remote_rows,remote_colliders=nil,nil,nil;native_visible=false
    remote_drops,remote_pickups={},{}
    remote_voice,voice_updated={},-100
    appearance_signature=nil
    cosmetic_signature=nil
end

function Pose.toggle_preview()
    preview = not preview
    Pose.destroy()
    return preview
end
function Pose.rendered() return actor,component end
function Pose.owner() return remote_owner end
function Pose.root() return remote_root end
function Pose.vitals()return remote_vitals end
function Pose.velocity()return remote_velocity end
function Pose.received_at()return last_remote_valid end
function Pose.frame()return remote_frame end
function Pose.transforms() return body_transforms end
function Pose.hidden() return hidden.body end
function Pose.equipment() return remote_equipment,remote_rows end
function Pose.drops()return remote_drops,remote_pickups end
function Pose.colliders() return remote_colliders end
function Pose.appearance()return component,parts end
function Pose.appearance_version()return appearance_version end
function Pose.use_native(value)
    if value==native_visible then return end
    native_visible=value
    if valid(component) then component:SetVisibility(not value,false);component:SetHiddenInGame(value,false) end
    for _,p in pairs(parts) do
        local show=not value or p.kind=='D'or p.kind=='T'
        if valid(p.component) then p.component:SetVisibility(show,false);p.component:SetHiddenInGame(not show,false) end
    end
end
function Pose.part(id) return id=="body" and component or parts[id] and parts[id].component end

local Avatar = options.secondary and _G.HSMPAvatar or dofile(require("paths").scripts .. "/avatar.lua")
if not options.secondary then _G.HSMPAvatar=Avatar end
function Pose.capture(pawn)
    serial = serial + 1
    if not _G.HSMPUI then _G.HSMPUI=dofile(require("paths").scripts.."/ui.lua") end
    local ui_ok,ui_error=pcall(_G.HSMPUI.tick)
    if not ui_ok and _G.HSMPUIError~=tostring(ui_error) then
        _G.HSMPUIError=tostring(ui_error);print("[HalfSwordMP] Multiplayer menu: "..tostring(ui_error).."\n")
    end
    if not _G.HSMPSession then _G.HSMPSession=dofile(require("paths").scripts.."/session.lua") end
    local mode=_G.HSMPSession.tick(pawn)
    if not preview and not _G.HSMPSession.in_match() then return nil end
    if _G.HSMPSession.respawning() then return nil end
    local owned=_G.HSMPSession.capture_pawn()
    if owned and owned:IsValid() then pawn=owned end
    if not preview then
        local now = os.time()
        if now ~= last_heartbeat_check then
            last_heartbeat_check = now
            local file = io.open(require("paths").runtime .. "/bridge.heartbeat","r")
            if file then
                local value = file:read("*l")
                file:close()
                local timestamp = tonumber(value)
                if timestamp and math.abs(now-timestamp) < 3 and value ~= heartbeat then
                    heartbeat,last_heartbeat_change = value,now
                end
            end
        end
        if now-last_heartbeat_change > 2 then return nil end
    end
    if not valid(pawn) then return nil end
    local now=require("UEHelpers").GetGameplayStatics():GetRealTimeSeconds(pawn:GetWorld())
    local name=pawn:GetFullName()
    -- The single update queue owns the 30 Hz deadline. A second minimum-
    -- interval throttle here would discard early frames and halve the rate.
    last_capture_time,last_capture_pawn=now,name
    if _G.HSMPSession then _G.HSMPSession.sync_injury()end
    last_capture_text=Avatar.capture(pawn,serial,not preview)
    return last_capture_text
end

function Pose.write_local(runtime, text)
    if not text and local_off then return end
    local file = io.open(runtime .. "/local.pose", "wb")
    if not file then return end
    file:write(text or "OFF|0\n")
    file:close()
    local_off = text == nil
end

local function read_remote(runtime)
    local file = io.open(runtime .. "/remote.pose", "rb")
    if not file then return nil end
    local text = file:read(262145)
    file:close()
    if #text > 262144 then return nil end
    return text
end

local function create_proxy(pawn, asset)
    local source = pawn.Mesh
    actor = pawn:GetWorld():SpawnActor(StaticFindObject("/Script/Engine.Actor"),
        {X=0,Y=0,Z=0}, {Pitch=0,Yaw=0,Roll=0})
    assert(valid(actor), "Cannot spawn pose proxy actor")
    local pose_class = StaticFindObject("/Script/Engine.PoseableMeshComponent")
    -- Assign the mesh BEFORE registration allocates the pose's bone storage.
    component = actor:AddComponentByClass(pose_class, false, identity(source), true)
    assert(valid(component), "Cannot create pose component")
    component:SetSkinnedAssetAndUpdate(asset,true)
    actor:FinishAddComponent(component, false, identity(source))
    component:SetMobility(2) -- Movable
    actor.RootComponent = component
    actor:SetActorScale3D({X=1,Y=1,Z=1})
    component.VisibilityBasedAnimTickOption = 0 -- AlwaysTickPoseAndRefreshBones
    component:SetComponentTickEnabled(true)
    component:Activate(true)
    component:CopyPoseFromSkeletalComponent(source)
    component:SetCollisionEnabled(0)
    actor:SetActorEnableCollision(true) -- Only the separate equipment shapes collide.
    for index = 0, source:GetNumMaterials() - 1 do
        component:SetMaterial(index, source:GetMaterial(index))
    end
    actor_world = path(pawn:GetWorld())
    mesh_name = path(asset)
    print("[HalfSwordMP] Remote avatar created; native hit bodies are driven separately.\n")
end

local function set_transform(t, values, start, offset)
    t.Translation.X,t.Translation.Y,t.Translation.Z = tonumber(values[start])+offset,tonumber(values[start+1]),tonumber(values[start+2])
    t.Rotation.X,t.Rotation.Y,t.Rotation.Z,t.Rotation.W = tonumber(values[start+3]),tonumber(values[start+4]),tonumber(values[start+5]),tonumber(values[start+6])
    t.Scale3D.X,t.Scale3D.Y,t.Scale3D.Z = tonumber(values[start+7]),tonumber(values[start+8]),tonumber(values[start+9])
    return t
end

local function render_parts(lines, pawn, offset)
    local present = {}
    local signatures = {}
    for i = 2, #lines do
        local v = fields(lines[i])
        if v[1] == "P" then
            local key = v[2]..":"..v[3]
            signatures[key] = (signatures[key] or "")..v[4]..":"..v[5]..":"..v[6]..":"..#v.."|"
        end
    end
    for i = 2, #lines do
        local v = fields(lines[i])
        if v[1] == "C" and #v == 14 then
            local id,kind,asset_name = v[2],v[3],v[4]
            local static=kind=='S'or kind=='D'or kind=='T'
            local asset = Assets.mesh(asset_name,not static)
            local class_name = not static and "/Script/Engine.PoseableMeshComponent" or "/Script/Engine.StaticMeshComponent"
            local correct = valid(asset) and (((kind == "K" or kind == "L") and asset:IsA("/Script/Engine.SkeletalMesh"))
                or (static and asset:IsA("/Script/Engine.StaticMesh")))
            if correct then
                local p = parts[id]
                if p and (p.asset ~= asset_name or p.kind ~= kind) then
                    if valid(p.component) then p.component:K2_DestroyComponent(actor) end
                    parts[id] = nil
                    p = nil
                end
                if not p then
                    local c = actor:AddComponentByClass(StaticFindObject(class_name),true,identity(pawn.Mesh),true)
                    assert(valid(c),"Cannot create avatar part")
                    c:SetMobility(2)
                    if not static then c:SetSkinnedAssetAndUpdate(asset,true) else c:SetStaticMesh(asset) end
                    actor:FinishAddComponent(c,true,identity(pawn.Mesh))
                    c:SetCollisionEnabled(0)
                    if not static then c.VisibilityBasedAnimTickOption = 0 end
                    if kind == "L" then c:SetLeaderPoseComponent(component,true,false) end
                    p = {component=c,asset=asset_name,kind=kind}
                    parts[id] = p
                end
                local show=not native_visible or kind=='D'or kind=='T'
                p.component:SetHiddenInGame(not show,false)
                p.component:SetVisibility(show,false)
                if kind == "L" then
                    p.component:K2_SetWorldTransform(component:K2_GetComponentToWorld(),false,{},true)
                else p.component:K2_SetWorldTransform(set_transform(identity(pawn.Mesh),v,5,offset),false,{},true) end
                present[id] = true
            end
        end
    end
    for id,p in pairs(parts) do
        if not present[id] then
            if valid(p.component) then p.component:K2_DestroyComponent(actor) end
            parts[id] = nil
            hidden[id] = nil
        end
    end
    local next_hidden = {}
    expected_parameters = {}
    for i = 2, #lines do
        local v = fields(lines[i])
        local c = v[2] == "body" and component or (parts[v[2]] and parts[v[2]].component)
        if valid(c) then
            if v[1] == "M" and #v == 4 then
                local slot = tonumber(v[3])
                local material = v[4] ~= "-" and StaticFindObject(v[4]) or nil
                if slot and slot >= 0 and slot < 16 and valid(material) and material:IsA("/Script/Engine.MaterialInterface") then
                    local key = v[2]..":"..slot
                    local old = materials[key]
                    if not old or old.base ~= v[4] or old.owner ~= path(c) or old.signature ~= signatures[key] or not valid(old.dynamic) then
                        old = {base=v[4],owner=path(c),signature=signatures[key],dynamic=c:CreateDynamicMaterialInstance(slot,material,FName("None"))}
                        materials[key] = old
                    end
                    -- The component retains its dynamic material between snapshots.
                end
            elseif v[1] == "P" and (#v == 7 or #v == 10)and not Cosmetics.view_dependent(v[4])then
                local m = materials[v[2]..":"..v[3]]
                if m and valid(m.dynamic) then
                    expected_parameters[#expected_parameters+1] = {material=m.dynamic,values=v}
                    local parameter_key = v[4]..":"..v[5]..":"..v[6]
                    local encoded = table.concat(v,"|")
                    m.values = m.values or {}
                    if m.values[parameter_key] ~= encoded then
                        m.values[parameter_key] = encoded
                        local info = {Name=FName(v[4]),Association=tonumber(v[5]),Index=tonumber(v[6])}
                        if #v == 7 then m.dynamic:SetScalarParameterValueByInfo(info,tonumber(v[7]))
                        else
                            local color = m.dynamic:K2_GetVectorParameterValueByInfo(info)
                            color.R,color.G,color.B,color.A = tonumber(v[7]),tonumber(v[8]),tonumber(v[9]),tonumber(v[10])
                            m.dynamic:SetVectorParameterValueByInfo(info,color)
                        end
                    end
                end
            elseif v[1] == "B" and #v == 13 and v[2] ~= "body" then
                if c:IsA("/Script/Engine.PoseableMeshComponent") then
                    c:SetBoneTransformByName(FName(v[3]),set_transform(identity(pawn.Mesh),v,4,offset),0)
                end
            elseif v[1] == "H" and #v == 3 then
                next_hidden[v[2]] = next_hidden[v[2]] or {}
                next_hidden[v[2]][v[3]] = true
            end
        end
    end
    for id,old in pairs(hidden) do
        local c = id == "body" and component or (parts[id] and parts[id].component)
        if valid(c) then
            for bone in pairs(old) do
                if not (next_hidden[id] and next_hidden[id][bone]) then c:UnHideBoneByName(FName(bone)) end
            end
        end
    end
    for id,current in pairs(next_hidden) do
        local c = id == "body" and component or (parts[id] and parts[id].component)
        if valid(c) then
            for bone in pairs(current) do
                if not (hidden[id] and hidden[id][bone]) then c:HideBoneByName(FName(bone),0) end
            end
        end
    end
    hidden = next_hidden
end

local function update(runtime, pawn, local_text, remote_text)
    if not valid(pawn) or pawn:GetClass():GetFName():ToString()~="Willie_BP_C" then Pose.destroy();return end
    local clock=require('UEHelpers').GetGameplayStatics():GetRealTimeSeconds(pawn:GetWorld())
    local function missing()
        if valid(component) and actor_world==path(pawn:GetWorld()) and clock-last_remote_valid<1 then return end
        Pose.destroy()
    end
    if not local_text then missing(); return end
    local text = preview and local_text or remote_text or read_remote(runtime)
    if not text then missing(); return end
    local lines = {}
    for line in text:gmatch("[^\r\n]+") do lines[#lines + 1] = line end
    local header = fields(lines[1] or "")
    if #header ~= 10 or header[1] ~= "HSMP2" then missing(); return end
    local ending = fields(lines[#lines] or "")
    if ending[1] ~= "E" or ending[2] ~= header[2] or tonumber(ending[3]) ~= #lines-1 then return end
    if header[2] == last_counter and not preview then unchanged = unchanged + 1 else unchanged = 0 end
    last_counter = header[2]
    -- Hide a stale peer if the launcher was killed (40 x 50 ms).
    if unchanged > 20 then Pose.destroy(); return end
    if unchanged>0 and not preview then return end
    local current_world = path(pawn:GetWorld())
    if header[3] ~= current_world then Pose.destroy(); return end
    last_remote_valid=clock
    -- Different selections can require mesh assets not used by this PC's loadout.
    local asset=valid(component) and component:GetSkinnedAsset() or nil
    if not valid(component) or mesh_name~=header[4] then
        asset=Assets.mesh(header[4],true)
        if not valid(asset) or not asset:IsA("/Script/Engine.SkeletalMesh") then Pose.destroy(); return end
    end
    local incoming_owner=text:match('\nV|owner_id|([%d]+)')
    if actor_world ~= current_world or mesh_name ~= header[4]
        or (remote_owner and tonumber(incoming_owner)~=remote_owner)then Pose.destroy() end
    if not valid(actor) or not valid(component) then create_proxy(pawn, asset) end
    local offset = preview and 125 or 0
    local root = {}
    for i = 5, 10 do root[i] = tonumber(header[i]) end
    if not root[5] or not root[6] or not root[7] or not root[8] or not root[9] or not root[10] then
        Pose.destroy(); return
    end
    local frame={root={root[5]+offset,root[6],root[7],root[8],root[9],root[10]},bones={},parts={},colliders={},collision_modes={}}
    remote_owner=nil;remote_vitals={};remote_velocity={0,0,0}
    for _,line in ipairs(lines) do
        local x,y,z=line:match('^S|([%d%.%-]+)|([%d%.%-]+)|([%d%.%-]+)$')
        if x then remote_velocity={tonumber(x),tonumber(y),tonumber(z)}end
        local key,value=line:match('^V|([%w_]+)|([%d%.%-]+)$')
        if key then remote_vitals[key]=tonumber(value) end
    end
    remote_owner=remote_vitals.owner_id
    local appearance_rows,cosmetic_rows={},{}
    for _,line in ipairs(lines) do
        local kind=line:sub(1,2)
        if kind=='C|' then
            local v=fields(line);local entry=table.concat({v[1],v[2],v[3],v[4]},'|')
            appearance_rows[#appearance_rows+1]=entry;cosmetic_rows[#cosmetic_rows+1]=entry
        elseif kind=='M|' or kind=='P|' or kind=='H|' then
            appearance_rows[#appearance_rows+1]=line
            if kind=='M|'then cosmetic_rows[#cosmetic_rows+1]=line
            elseif kind=='P|'then
                local v=fields(line);local name=v[4]:lower();local transient=false
                for _,word in ipairs({'blood','wound','damage','opacity','hide','hidden','camera','dither','fade','alpha'})do
                    if name:find(word,1,true)then transient=true;break end
                end
                if not transient then cosmetic_rows[#cosmetic_rows+1]=line end
            end
        end
    end
    local next_appearance=table.concat(appearance_rows,'\n')
    if not native_visible or (next_appearance~=appearance_signature and clock-appearance_updated>=.25) then
        render_parts(lines,pawn,offset);appearance_signature=next_appearance
        local signature=table.concat(cosmetic_rows,'\n')
        if signature~=cosmetic_signature then cosmetic_signature=signature;appearance_version=appearance_version+1 end
        appearance_updated=clock
    end
    local rows={}
    local appearance={}
    for _,line in ipairs(lines) do
        local v=fields(line);rows[#rows+1]=v
        local kind,start,key
        if v[1]=="B" and #v==13 then kind,start,key="bones",4,v[2].."|"..v[3]
        elseif v[1]=="C" and #v==14 then
            kind,start,key="parts",5,v[2];appearance[#appearance+1]=v[2]..":"..v[3]..":"..v[4]
        elseif v[1]=="G" and #v==21 then
            kind,start,key="colliders",5,v[2];frame.collision_modes[v[2]]=tonumber(v[21])
        end
        if kind then
            local t={};for i=0,9 do t[i+1]=tonumber(v[start+i]) end;t[1]=t[1]+offset
            frame[kind][key]=t
        end
    end
    remote_equipment,remote_rows=Equipment.read(rows),rows
    remote_voice,voice_updated=Voice.read(rows),clock
    Held.prepare(frame,remote_equipment)
    remote_drops,remote_pickups=Dropped.read(rows)
    -- Native weapon Blueprints provide the collision shapes for this protocol.
    -- The former generic shapes are retained only for old local preview data.
    Geometry.prepare(actor,pawn,remote_equipment.present and {} or rows,identity)
    local effect_lines={}
    if not native_visible then for _,line in ipairs(lines) do
        if line:sub(1,2)=="N|" or line:sub(1,2)=="Q|" then effect_lines[#effect_lines+1]=fields(line) end
    end end
    Effects.update(actor,pawn,effect_lines,offset,identity,set_transform)
    draw_pawn=pawn
    local now=require("UEHelpers").GetGameplayStatics():GetRealTimeSeconds(pawn:GetWorld())
    table.sort(appearance)
    interpolation=Interpolation.push(interpolation,frame,now,current_world..header[4]..tostring(remote_owner)..table.concat(appearance,"|"))
end

function Pose.animate()
    if not interpolation or not valid(component) or not valid(draw_pawn) then
        if session()then session().animate(Pose)end
        return
    end
    local now=require("UEHelpers").GetGameplayStatics():GetRealTimeSeconds(draw_pawn:GetWorld())
    local frame=Interpolation.sample(interpolation,now)
    remote_frame=frame
    remote_colliders=frame.colliders
    -- Native prediction consumes the newest root immediately. The visual-only
    -- preview may interpolate; do not stack that delay onto native correction.
    remote_root=native_visible and interpolation.to.root or frame.root
    if native_visible then
        -- Dropped weapons belong to the world, not the native stand-in's hands.
        -- Keep their visual meshes moving even while its pose proxy is hidden.
        local t
        for id,p in pairs(parts)do
            local n=frame.parts[id]
            if (p.kind=='D'or p.kind=='T')and n and valid(p.component)then
                t=t or identity(draw_pawn.Mesh)
                t.Translation.X,t.Translation.Y,t.Translation.Z=n[1],n[2],n[3]
                t.Rotation.X,t.Rotation.Y,t.Rotation.Z,t.Rotation.W=n[4],n[5],n[6],n[7]
                t.Scale3D.X,t.Scale3D.Y,t.Scale3D.Z=n[8],n[9],n[10]
                p.component:K2_SetWorldTransform(t,false,{},true)
            end
        end
        if session()then session().animate(Pose)end
        return
    end
    local r=frame.root
    actor:K2_SetActorLocationAndRotation({X=r[1],Y=r[2],Z=r[3]},
        {Pitch=r[4],Yaw=r[5],Roll=r[6]},false,{},true)
    local t=identity(draw_pawn.Mesh)
    body_transforms={};last_bones={}
    for key,n in pairs(frame.bones) do
        local id,bone=key:match("^([^|]+)|(.+)$")
        local c=id=="body" and component or parts[id] and parts[id].component
        if valid(c) then
            local name=bone_names[bone] or FName(bone);bone_names[bone]=name
            t.Translation.X,t.Translation.Y,t.Translation.Z=n[1],n[2],n[3]
            t.Rotation.X,t.Rotation.Y,t.Rotation.Z,t.Rotation.W=n[4],n[5],n[6],n[7]
            t.Scale3D.X,t.Scale3D.Y,t.Scale3D.Z=n[8],n[9],n[10]
            if not native_visible then c:SetBoneTransformByName(name,t,0) end
            if id=="body" then
                body_transforms[bone]=n;last_bones[bone]={X=n[1],Y=n[2],Z=n[3]}
                if bone:lower()=="pelvis" then last_pelvis=last_bones[bone] end
            end
        end
    end
    for id,n in pairs(frame.parts) do
        local p=parts[id]
        if not native_visible and p and valid(p.component) then
            if p.kind=="L" then p.component:K2_SetWorldTransform(component:K2_GetComponentToWorld(),false,{},true)
            else
                t.Translation.X,t.Translation.Y,t.Translation.Z=n[1],n[2],n[3]
                t.Rotation.X,t.Rotation.Y,t.Rotation.Z,t.Rotation.W=n[4],n[5],n[6],n[7]
                t.Scale3D.X,t.Scale3D.Y,t.Scale3D.Z=n[8],n[9],n[10]
                p.component:K2_SetWorldTransform(t,false,{},true)
            end
        end
    end
    Geometry.draw(frame.colliders,t)
    if session()then session().animate(Pose)end
end

function Pose.update(runtime,pawn,local_text,remote_text)
    Pose.local_text=local_text
    local owned=_G.HSMPSession and _G.HSMPSession.capture_pawn()
    if valid(owned) then pawn=owned end
    update(runtime,pawn,local_text,remote_text)
    Pose.animate()
    if session()then session().after_render(Pose)end
end

function Pose.inspect(runtime, pawn, filename)
    local file = assert(io.open(runtime .. "/"..(filename or "render-check.txt"), "w"))
    file:write("proxy_valid=", tostring(valid(component)), "\npreview=", tostring(preview), "\n")
    Effects.inspect(file)
    file:write("equipment_collision_shapes=",Geometry.count(),"\ninterpolated_render=",tostring(interpolation~=nil),"\n")
    local part_count,bone_count = 0,0
    for _ in pairs(parts) do part_count = part_count + 1 end
    for _ in pairs(last_bones) do bone_count = bone_count + 1 end
    file:write("rendered_parts=",part_count,"\nbody_bones=",bone_count,"\n")
    local parameter_error = 0
    for _,entry in ipairs(expected_parameters) do
        local v,m = entry.values,entry.material
        local info = {Name=FName(v[4]),Association=tonumber(v[5]),Index=tonumber(v[6])}
        if #v == 7 then
            parameter_error = math.max(parameter_error,math.abs(m:K2_GetScalarParameterValueByInfo(info)-tonumber(v[7])))
        else
            local c = m:K2_GetVectorParameterValueByInfo(info)
            parameter_error = math.max(parameter_error,math.abs(c.R-tonumber(v[7])),math.abs(c.G-tonumber(v[8])),math.abs(c.B-tonumber(v[9])),math.abs(c.A-tonumber(v[10])))
        end
    end
    file:write("material_parameters=",#expected_parameters,"\nmax_parameter_error=",parameter_error,"\n")
    if valid(component) and last_pelvis then
        local actual = component:GetBoneTransformByName(FName("pelvis"), 0)
        local error = math.sqrt((actual.Translation.X-last_pelvis.X)^2
            +(actual.Translation.Y-last_pelvis.Y)^2+(actual.Translation.Z-last_pelvis.Z)^2)
        file:write(string.format("pelvis_error_cm=%.5f\nvisible=%s\n", error, tostring(component:IsVisible())))
        file:write(string.format("expected_xyz=%.3f,%.3f,%.3f\n",last_pelvis.X,last_pelvis.Y,last_pelvis.Z))
        file:write("proxy_world=", actor_world, "\nmesh=", mesh_name, "\n")
        file:write(string.format("pelvis_xyz=%.3f,%.3f,%.3f\n",actual.Translation.X,actual.Translation.Y,actual.Translation.Z))
        local location = actor:K2_GetActorLocation()
        file:write(string.format("actor_xyz=%.3f,%.3f,%.3f\n",location.X,location.Y,location.Z))
        file:write("component_ticks=",tostring(component:IsComponentTickEnabled()),"\n")
        file:write("component_bones=",tostring(component:GetNumBones()),"\n")
        local assigned = component.SkeletalMesh
        file:write("assigned_mesh=",valid(assigned) and assigned:GetFullName() or "null","\n")
        local skinned = component:GetSkinnedAsset()
        file:write("skinned_asset=",valid(skinned) and skinned:GetFullName() or "null","\n")
        file:write("root_valid=",tostring(valid(actor.RootComponent)),"\n")
        local scale = actor:GetActorScale3D()
        file:write(string.format("actor_scale=%.3f,%.3f,%.3f\n",scale.X,scale.Y,scale.Z))
        file:write("active=",tostring(component:IsActive()),"\n")
        file:write("bone_index=",tostring(component:GetBoneIndex(FName("pelvis"))),"\n")
        file:write("render_static=",tostring(component.bRenderStatic),"\n")
        local max_error, max_name = 0, ""
        for name, expected in pairs(last_bones) do
            local got = component:GetBoneLocationByName(FName(name), 0)
            local d = math.sqrt((got.X-expected.X)^2+(got.Y-expected.Y)^2+(got.Z-expected.Z)^2)
            if d > max_error then max_error,max_name = d,name end
        end
        file:write(string.format("max_bone_error_cm=%.5f\nworst_bone=%s\n",max_error,max_name))
    end
    file:close()
end

return Pose
