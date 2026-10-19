-- Each peer keeps its own fighter and drives a native opponent with remote input.
local Session={}
local helpers,paths=require("UEHelpers"),require("paths")
local Waiting=dofile(paths.scripts.."/waiting.lua")
local Round=dofile(paths.scripts.."/round.lua")
local Fighter=dofile(paths.scripts.."/fighter.lua")
local Damage=dofile(paths.scripts.."/damage.lua")
local Injury=dofile(paths.scripts..'/injury.lua')
local Clothing=dofile(paths.scripts..'/clothing.lua')
local Pause=dofile(paths.scripts..'/pause.lua')or{}
_G.HSMPPause=Pause

local Match=dofile(paths.scripts.."/match.lua")
_G.HSMPMatch=Match
local role,connected,nonce="off",false,""
local local_pawn,local_world
local retiring_pawn
local input_pawn
local previous_remote_owner
local frame
local tick=0
local last_role_record
local injury_state,injury_attacker
local function valid(o) return o~=nil and o:IsValid() end
local function same(a,b) return valid(a) and valid(b) and a:GetFullName()==b:GetFullName() end
function Session.stop()
    if _G.HSMPDropped and _G.HSMPDropped.reset then _G.HSMPDropped.reset()end
    if Pause.reset then Pause.reset()end
    Clothing.reset()
    Fighter.destroy();Waiting.release();Round.release();Damage.stop();
    Injury.reset()
    Match.leave()
    local_pawn,local_world,retiring_pawn=nil,nil,nil
    input_pawn=nil
    previous_remote_owner=nil
    frame=nil
    injury_state,injury_attacker=nil,nil
    local f=io.open(paths.runtime.."/frame.cfg","w");if f then f:write("OFF\n");f:close() end
    role,connected,nonce="off",false,""
end
function Session.is_host() return false end
function Session.in_match() return Match.playable() end
function Session.owns_arena()return role~='off'and Match.active()end
local function guest_spawning()
    return role=='join'and Match.active()and not Match.playable()and not _G.HSMPNativeProxySpawn
end
function Session.adjust_guest_spawn(class,world,transform)
    if not guest_spawning()or not valid(class)or class:GetFName():ToString()~='Willie_BP_C'then return end
    for _,a in ipairs(FindAllOf('LevelScriptActor')or{})do
        if valid(a)and a:GetWorld():GetFullName()==world:GetFullName()
            and a:GetClass():GetFName():ToString()=='Arena_Cutting_Map_C'then
            local first,second=a['Spawn Point 1'],a['Spawn Point 2']
            local v=transform.Translation
            v.X,v.Y=first.X+second.X-v.X,first.Y+second.Y-v.Y
            local q=transform.Rotation;local x,y,z,w=q.X,q.Y,q.Z,q.W
            q.X,q.Y,q.Z,q.W=-y,x,w,-z
            return
        end
    end
end
local function install_spawn_hook()
    if _G.HSMPNativeSpawnHook then return end
    local begin='/Script/Engine.GameplayStatics:BeginDeferredActorSpawnFromClass'
    local finish='/Script/Engine.GameplayStatics:FinishSpawningActor'
    if valid(StaticFindObject(begin))and valid(StaticFindObject(finish))then
        _G.HSMPNativeSpawnHook={}
        _G.HSMPNativeSpawnHook.begin={RegisterHook(begin,function(ctx,world,class,transform)
            if _G.HSMPSession then _G.HSMPSession.adjust_guest_spawn(class:get(),world:get():GetWorld(),transform:get())end
        end)}
        _G.HSMPNativeSpawnHook.finish={RegisterHook(finish,function(ctx,actor,transform)
            local p=actor:get()
            if guest_spawning()and valid(p)and p:GetClass():GetFName():ToString()=='Willie_BP_C'then
                -- FinishSpawning receives the original Blueprint transform.
                -- Keep the position established before deferred construction.
                local source=p:GetTransform();local t=transform:get()
                t.Translation=source.Translation;t.Rotation=source.Rotation
            end
        end)}
    end
end
function Session.capture_pawn() return local_pawn end
function Session.round_outcome(pawn)return Round.defeated(pawn)end
function Session.give_up()
    return Match.playable()and Round.surrender(local_pawn)
end
function Session.injury_source()return Damage.injury_source()end
function Session.sync_injury(pawn)
    if connected and Match.playable()and valid(local_pawn)and (not pawn or same(pawn,local_pawn))and _G.HSMPAvatar then
        -- Native injury events own wounds and health together. A scalar write
        -- before the event would subtract the same injury twice.
        Round.guard_pawn(local_pawn)
    end
end
function Session.respawning() return retiring_pawn~=nil end
function Session.hide_waiting()
    if role~="off" and Match.playable() then Waiting.hide() end
end
function Session.tick(pawn)
    tick=tick+1
    local f=io.open(paths.runtime.."/role.cfg","r")
    local p={}
    if f then local line=f:read(256) or "";f:close();for v in line:gmatch("[^|\r\n]+") do p[#p+1]=v end end
    local fresh=p[1]=="HSROLE1" and tonumber(p[5]) and math.abs(os.time()-tonumber(p[5]))<3
    if fresh then last_role_record=p
    elseif p[1]~="OFF" and last_role_record and math.abs(os.time()-tonumber(last_role_record[5]))<3 then
        -- A busy Windows reader can briefly fail to open an atomically replaced
        -- file. Keep the last fresh record instead of leaving the match.
        p=last_role_record;fresh=true
    end
    local next_role=fresh and p[2] or "off"
    if next_role~=role then
        if role~="off" then print("[HalfSwordMP] Connection role changed: "..role.." -> "..next_role.."\n") end
        Session.stop()
    elseif fresh and nonce~="" and nonce~=p[4] then
        -- The transport rotates its nonce when the guest connects. That is a
        -- peer boundary, not a request to leave the selected multiplayer mode.
        local old=Fighter.pawn();Fighter.destroy();Waiting.refreeze(old);Damage.stop();
        Injury.reset();injury_state,injury_attacker=nil,nil
    end
    role,connected,nonce=next_role,fresh and p[3]=="1",fresh and p[4] or ""
    local world=helpers.GetWorld()
    if not valid(world) then return role end
    Match.menu(world)
    if role=="off" then return "off" end
    if Pause.tick then Pause.tick(world)end
    if role=='join'then install_spawn_hook()end
    Round.install_hooks()
    if not Match.poll(world,pawn) then
        if local_pawn or local_world then
            Fighter.destroy();Waiting.release();Round.release();Damage.stop()
            local_pawn,local_world,retiring_pawn,frame=nil,nil,nil,nil
            injury_state,injury_attacker=nil,nil
        end
        return role
    end
    Match.prepare(world)
    if local_world and local_world~=world:GetFullName() then
        Fighter.destroy();Waiting.release();Round.release();Damage.stop();local_pawn=nil;retiring_pawn=nil;frame=nil
    end
    local_world=world:GetFullName()
    if Round.poll(world,function()
        if _G.HSMPDropped and _G.HSMPDropped.reset then _G.HSMPDropped.reset()end
        previous_remote_owner=Fighter.owner()
        Clothing.reset()
        retiring_pawn=valid(local_pawn) and local_pawn:GetFullName() or ""
        Fighter.destroy();Waiting.release();Damage.stop();local_pawn=nil;frame=nil
        injury_state,injury_attacker=nil,nil
        Match.restart()
    end) then return role end
    if retiring_pawn then
        if not valid(pawn) or pawn:GetClass():GetFName():ToString()~="Willie_BP_C"
            or pawn:GetFullName()==retiring_pawn then return role end
        retiring_pawn=nil
    end
    if valid(pawn) and pawn:GetClass():GetFName():ToString()=="Willie_BP_C" and not same(pawn,local_pawn) then
        Fighter.destroy();Waiting.release();Damage.stop();
        injury_state,injury_attacker=nil,nil
        local_pawn=pawn
        if role=="join" then
            for _,a in ipairs(FindAllOf("LevelScriptActor") or {}) do
                if valid(a) and a:GetWorld():GetFullName()==world:GetFullName()
                    and a:GetClass():GetFName():ToString()=="Arena_Cutting_Map_C" then
                    local first=a["Spawn Point 1"];local ax,ay=first.X,first.Y
                    local second=a["Spawn Point 2"];frame={ax,ay,second.X,second.Y};break
                end
            end
            local other=not frame and Waiting.candidate(pawn) or nil
            if valid(other) then
                local a=pawn:K2_GetActorLocation();local ax,ay=a.X,a.Y
                local b=other:K2_GetActorLocation();frame={ax,ay,b.X,b.Y}
            end
        end
    end
    if not valid(local_pawn) then return role end
    if not Match.ready(world,local_pawn) then return role end
    if input_pawn~=local_pawn:GetFullName()then
        local pc=helpers.GetPlayerController()
        if valid(pc)and same(pc.Pawn,local_pawn)then
            if role=='join'and frame then
                local r=pc:GetControlRotation()
                local a=local_pawn:K2_GetActorLocation()
                pc:SetControlRotation({Pitch=r.Pitch,Yaw=math.deg(math.atan(frame[2]+frame[4]-2*a.Y,frame[1]+frame[3]-2*a.X)),Roll=r.Roll})
            end
            local_pawn:EnableInput(pc)
            pc:ResetIgnoreMoveInput();pc:ResetIgnoreLookInput()
            if _G.HSMPUI then _G.HSMPUI.set_open(false)end
            input_pawn=local_pawn:GetFullName()
        end
    end
    if frame and _G.HSMPAvatar then
        local f=io.open(paths.runtime.."/frame.cfg","w")
        if f then f:write(string.format("HSFRAME2|%d|%.4f|%.4f|%.4f|%.4f|0|%d\n",
            _G.HSMPAvatar.owner(local_pawn),frame[1],frame[2],frame[3],frame[4],os.time()));f:close() end
    end
    Round.hold(world)
    Waiting.hold(local_pawn)
    return role
end
function Session.after_render(renderer)
    if role=="off" or not Match.playable() or not valid(local_pawn) then return end
    local _,mesh=renderer.rendered()
    if connected and valid(mesh) then
        if previous_remote_owner and renderer.owner()==previous_remote_owner then return end
        previous_remote_owner=nil
        Fighter.update(local_pawn,renderer,Waiting)
        Fighter.appearance(renderer)
        local avatar=_G.HSMPAvatar
        if avatar then
            Damage.configure(local_pawn,Fighter.pawn(),avatar.owner(local_pawn),renderer.owner(),avatar.contact_id,Fighter.component,Fighter.contact_frame)
            Damage.tick()
        end
    else Fighter.destroy();Damage.stop() end
end
function Session.animate(renderer)
    if role~="off" and Match.playable() and valid(local_pawn) then
        if _G.HSMPDropped then _G.HSMPDropped.tick(local_pawn,renderer)end
        Clothing.update(local_pawn);Clothing.update(Fighter.pawn())
        Fighter.controls(local_pawn)
        Fighter.render(renderer)
        if connected and renderer.vitals and _G.HSMPAvatar then
            injury_state,injury_attacker=renderer.vitals(),renderer.owner()
            Session.sync_injury()
        end
        Round.guard_pawn(local_pawn);Round.guard_pawn(Fighter.pawn())
    end
end
function Session.inspect(f)
    f:write("custom_match_active=",tostring(Match.active()),"\n")
    Match.inspect(f)
    f:write("session_role=",role,"\nconnected=",tostring(connected),"\nauthority=native_input\nclient_suspended=false\nguest_assigned=false\n")
    f:write("waiting_opponents=",Waiting.count(),"\n")
    Waiting.inspect(f)
    if valid(local_pawn) then
        f:write("local_health=",tostring(local_pawn.Health),"\nlocal_visible=",tostring(not local_pawn.bHidden),
            "\nlocal_tick=",tostring(local_pawn:IsActorTickEnabled()),"\nlocal_physics=",tostring(local_pawn.Mesh:IsSimulatingPhysics(FName("None"))),"\n")
    end
    Round.inspect(f);Fighter.inspect(f);Damage.inspect(f)
end
return Session
