-- Native opponent collision bodies follow the other player's measured poses.
local Fighter={}
local paths,helpers=require('paths'),require('UEHelpers')
local Input=dofile(paths.scripts..'/native_input.lua')
local Equipment=dofile(paths.scripts..'/equipment.lua')
local Replica=dofile(paths.scripts..'/replica.lua')
local lease
local pending_pawn,pending_owner
local input_clock=-1
local function valid(o)return o~=nil and o:IsValid()end
local function same(a,b)return valid(a) and valid(b) and a:GetFullName()==b:GetFullName()end
local function now(p)
    if helpers.GetGameplayStatics then return helpers.GetGameplayStatics():GetRealTimeSeconds(p:GetWorld())end
    return os.clock()
end
function Fighter.pawn()return lease and lease.pawn end
function Fighter.owner()return lease and lease.owner end
function Fighter.contact_frame(bone)
 return lease and lease.last_frame and lease.last_frame.bones['body|'..bone]
end
function Fighter.component(id)
    if not lease or not valid(lease.pawn) then return end
    if id=='body' then return lease.pawn.Mesh end
    local geometry=id:match('^geometry:(.+)$')
    if geometry then return lease.equipment and lease.equipment.by_geometry[geometry] end
    return lease.equipment and lease.equipment.by_part[id]
end
function Fighter.neutral()
    if not lease then return end
    if valid(lease.pawn) then
        for id in pairs(lease.held or {}) do Input.apply_event(lease.pawn,id-1) end
        if lease.keyboard_crouch then Input.apply_event(lease.pawn,12) end
        for i=1,12 do Input.apply_axis(lease.pawn,i,0) end
        lease.pawn['Crouch Key Holding']=false;lease.pawn['Is Crouched']=false
    end
    lease.axes=nil;lease.held={};lease.buttons=0;lease.mouse={0,0};lease.keyboard_crouch=false
    Input.configure('active',lease.local_pawn,lease.controller,0)
end
function Fighter.destroy()
    if valid(pending_pawn) then
        local ai=pending_pawn.Controller
        pending_pawn:K2_DestroyActor();if valid(ai) then ai:K2_DestroyActor() end
    end
    pending_pawn,pending_owner=nil,nil
    if not lease then Input.configure('off');return end
    Fighter.neutral();local old=lease;lease=nil
    Replica.destroy(old.replica)
    Input.configure('off')
    if valid(old.pawn) then
        if old.equipment then for _,w in ipairs(old.equipment.weapons) do if valid(w) then w:K2_DestroyActor() end end end
        old.waiting.equipment(old.pawn,{})
        old.pawn:K2_DestroyActor()
    end
    if valid(old.controller) then old.controller:K2_DestroyActor() end
end
local function step(context)
    if lease and same(context,lease.local_pawn)and _G.HSMPSession then
        _G.HSMPSession.sync_injury(context)
    end
end
local function acquire(local_pawn,waiting,root,owner)
    if pending_owner and pending_owner~=owner then Fighter.destroy() end
    if not valid(pending_pawn) then pending_pawn=waiting.spawn_at(local_pawn,root);pending_owner=owner;return end
    if not waiting.ready(pending_pawn) then return end
    local p=pending_pawn;pending_pawn,pending_owner=nil,nil
    local gs,world=helpers.GetGameplayStatics(),local_pawn:GetWorld()
    lease={pawn=p,local_pawn=local_pawn,ai=p.Controller,player=p.Player,index=p['Player Index'],world=world,
        local_controller=helpers.GetPlayerController(),split_disabled=gs:IsSplitscreenForceDisabled(world),
        owner=owner,held={},desired={},buttons=0,mouse={0,0},waiting=waiting,controller=p.Controller}
    local ok,err=pcall(function()
        assert(valid(lease.controller),'Native opponent has no AI controller')
        assert(waiting.drive(p),'Native opponent is not initialized')
        p['Team Int']=local_pawn['Team Int']==0 and 1 or 0
        -- Retain enemy identity so its defeat cannot respawn controller zero.
        p.Player=false;p.Invulnerable=false
        p:DisableInput(lease.local_controller)
        Input.configure('active',local_pawn,lease.controller,0)
    end)
    if not ok then Fighter.destroy();error(err) end
    return p
end
function Fighter.controls(local_pawn)
    if not valid(local_pawn) then return end
    -- Remote bodies and held weapons use measured poses rather than replayed input.
    -- The native player already consumes its own input. Re-hooking every axis
    -- and writing an unused 30 Hz input stream only adds work on slower PCs.
end
function Fighter.update(local_pawn,renderer,waiting)
    local root=renderer.root();local value,rows=renderer.equipment()
    if not root or not value or not value.present then return end
    if lease and (not valid(lease.pawn) or lease.owner~=renderer.owner()) then Fighter.destroy() end
    local p=lease and lease.pawn or acquire(local_pawn,waiting,root,renderer.owner())
    if not valid(p) then return end
    if not lease.equipment or lease.equipment.signature~=value.signature then
        local keep_armor=lease.equipment and lease.equipment.armor_signature==value.armor_signature
        if keep_armor and lease.replica then Replica.clear_weapons(lease.replica)
        else Replica.destroy(lease.replica);lease.replica=nil end
        if lease.equipment then
            for _,w in ipairs(lease.equipment.weapons)do
                if valid(w)and not same(w,p['Weapon R'])and not same(w,p['Weapon L'])then w:K2_DestroyActor()end
            end
        end
        print('[HalfSwordMP] Native stand-in: equip selected loadout\n')
        -- Dropping/changing a weapon must not clear injured clothing or replace
        -- its native cut meshes/materials during this fighter's current life.
        lease.equipment=Equipment.create_fighter(p,value,rows,keep_armor)
        if lease.replica then Replica.equipment(lease.replica,lease.equipment)
        else lease.replica=Replica.create(p,lease.equipment)end
        waiting.equipment(p,lease.equipment.weapons)
        lease.appearance_dirty=true
    end
    Equipment.bind(lease.equipment,value,rows)
    -- The same modular class can spawn with different blade materials. Use
    -- the owner's native sharpness, rigidity and other computed properties.
    Equipment.sync(lease.equipment,value)
    local clock=now(local_pawn)
    if lease.appearance_dirty or not lease.visibility_after or clock>=lease.visibility_after then
        Equipment.show_fighter(lease.equipment,rows);lease.visibility_after=clock+.25
    end
    lease.root=root
    renderer.use_native(true)
end
function Fighter.render(renderer)
    if lease and lease.replica then
        local frame=renderer.frame();lease.last_frame=frame;Replica.update(lease.replica,frame)
        if frame and valid(lease.pawn)then
            local a=lease.pawn:K2_GetActorLocation();local r=frame.root
            lease.position_error=math.sqrt((a.X-r[1])^2+(a.Y-r[2])^2+(a.Z-r[3])^2)
        end
    end
end
function Fighter.appearance(renderer)
    if not lease or not valid(lease.pawn) or not lease.equipment then return end
    local stamp=os.time()
    local version=renderer.appearance_version()
    if lease.appearance_version==version and not lease.appearance_dirty then return end
    if lease.appearance_time==stamp and not lease.appearance_dirty then return end
    lease.appearance_time=stamp;lease.appearance_dirty=false;lease.appearance_version=version
    local source,parts=renderer.appearance();local p=lease.pawn
    local function copy(from,to,weapon)
        if not valid(from) or not valid(to) then return end
        for i=0,from:GetNumMaterials()-1 do
            local source=from:GetMaterial(i);local target=to:GetMaterial(i)
            if valid(source) and source:IsA('/Script/Engine.MaterialInstance') and valid(target) then
                if weapon then
                    local function base(m)
                        for _=1,8 do
                            if not valid(m)or not m:IsA('/Script/Engine.MaterialInstanceDynamic')then return m end
                            m=m.Parent
                        end
                    end
                    local source_base,target_base=base(source),base(target)
                    if valid(source_base)and valid(target_base)and source_base:GetFullName()~=target_base:GetFullName()then
                        -- Preset shields can choose a different material asset,
                        -- without any tint parameter to copy. Preserve native
                        -- blood textures when changing that cosmetic base.
                        local textures={}
                        if target:IsA('/Script/Engine.MaterialInstanceDynamic')then
                            target.TextureParameterValues:ForEach(function(_,r)
                                local p=r:get();local info=p.ParameterInfo
                                textures[#textures+1]={info={Name=FName(info.Name:ToString()),Association=info.Association,Index=info.Index},value=p.ParameterValue}
                            end)
                        end
                        target=to:CreateDynamicMaterialInstance(i,source_base,FName('None'))
                        for _,p in ipairs(textures)do target:SetTextureParameterValueByInfo(p.info,p.value)end
                    end
                end
                if not target:IsA('/Script/Engine.MaterialInstanceDynamic') then
                    target=to:CreateDynamicMaterialInstance(i,target,FName('None'))
                end
                -- Keep native blood/wound render-target textures on this fighter.
                -- Only portable cosmetic scalar/vector parameters are copied.
                source.ScalarParameterValues:ForEach(function(_,r)
                    local p=r:get();local name=p.ParameterInfo.Name:ToString():lower()
                    -- Camera/body hide masks and wound state belong to this
                    -- native instance, not the other player's camera/material.
                    local transient=false
                    for _,word in ipairs({'hide','hidden','blood','wound','damage','opacity','fade','camera','dither','alpha'})do
                        if name:find(word,1,true)then transient=true;break end
                    end
                    if not transient then target:SetScalarParameterValueByInfo(p.ParameterInfo,p.ParameterValue)end
                end)
                source.VectorParameterValues:ForEach(function(_,r)
                    local p=r:get();target:SetVectorParameterValueByInfo(p.ParameterInfo,p.ParameterValue)
                end)
            end
        end
    end
    copy(source,p.Mesh)
    local matches={};for _,part in pairs(parts) do if valid(part.component) then matches[part.asset]=part.component end end
    for _,ref in ipairs(p:K2_GetComponentsByClass(StaticFindObject('/Script/Engine.SkinnedMeshComponent'))) do
        local c=ref:get();local asset=c:GetSkinnedAsset()
        if valid(asset) and not same(c,p.Mesh) then copy(matches[asset:GetFullName():gsub('^%S+ ','')],c) end
    end
    for _,e in ipairs(lease.equipment.components) do local part=parts[e.part];if part then copy(part.component,e.component,true) end end
    renderer.use_native(true)
end
function Fighter.inspect(f)
    f:write('remote_representation=native_input_fighter\nremote_ai_assigned=',tostring(lease~=nil),'\n')
    if lease and valid(lease.pawn) then
        local p=lease.pawn
        f:write('remote_fighter=',p:GetFullName(),'\nremote_health=',p.Health,'\nremote_invulnerable=',tostring(p.Invulnerable),
            '\nremote_tick=',tostring(p:IsActorTickEnabled()),'\nremote_physics=',tostring(p.Mesh:IsSimulatingPhysics(FName('None'))),
            '\nremote_input_sequence=',tostring(lease.seq),'\nremote_native_weapons=',lease.equipment and #lease.equipment.weapons or 0,'\n')
        f:write('remote_position_error_cm=',lease.position_error or 0,'\nremote_position_corrections=0\n')
    end
end
return Fighter
