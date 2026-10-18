-- Stop AI movement and hide native opponents without destroying their physics.
local Waiting={}
local saved={}
local spawned
local native_equipment={}
local last_scan=-1
local function valid(o) return o~=nil and o:IsValid() end
local function equipment(a)
    if not valid(a) then return false end
    local c=a:GetClass()
    while valid(c) do
        local name=c:GetFName():ToString()
        if name=="ModularWeaponBP_C" or name=="BP_Armor_Master_C" or name=="Modular_Weapon_Part_Master_C" then return true end
        c=c:GetSuperStruct()
    end
    return false
end
local function environment_only(s)
    for _,p in ipairs(s.primitives) do
        if valid(p.component) then
            p.component:SetCollisionResponseToAllChannels(0)
            p.component:SetCollisionResponseToChannel(0,2) -- WorldStatic: preserve floor contact.
            -- Native weapons also use object traces. A hidden arena opponent
            -- must not remain a query target that absorbs the real attack.
            p.component:SetCollisionEnabled(p.mode==0 and 0 or 2)
        end
    end
    s.actor:SetActorEnableCollision(true)
end
local function restore_responses(s)
    for _,p in ipairs(s.primitives) do
        if valid(p.component) then
            for channel,value in pairs(p.responses) do p.component:SetCollisionResponseToChannel(channel,value) end
            p.component:SetCollisionEnabled(p.mode)
        end
    end
end
local function hide(s)
    if not valid(s.actor) then return end
    if not s.actor.bHidden then s.actor:SetActorHiddenInGame(true) end
    for _,p in ipairs(s.primitives) do
        local c=p.component
        if valid(c) then
            if c:IsVisible() then c:SetVisibility(false,false) end
            if not c.bHiddenInGame then c:SetHiddenInGame(true,false) end
        end
    end
end
local function hold(a)
    if not valid(a) then return end
    local key=a:GetFullName()
    local now=require("UEHelpers").GetGameplayStatics():GetRealTimeSeconds(a:GetWorld())
    if saved[key] then
        local s=saved[key]
        if s.dynamic then return end
        if s.ready_at and now>=s.ready_at then s.actor:SetActorTickEnabled(false);s.ready_at=nil end
        if s.active then return end
        if s.actor.bHidden then return end
        -- Native death/reset callbacks can unhide actors after the first hold.
        -- Keep only the replicated avatar visible throughout multiplayer.
        hide(s)
        if s.fighter then a.Invulnerable=true;a["Give Up"]=false end
        return
    end
    local s={actor=a,tick=a:IsActorTickEnabled(),collision=a:GetActorEnableCollision(),hidden=a.bHidden,primitives={}}
    saved[key]=s
    if a:GetClass():GetFName():ToString()=="Willie_BP_C" then
        s.fighter=true;s.invulnerable=a.Invulnerable;s.give_up=a["Give Up"]
        s.usable=a.Health>=99 and not a.DED and not a.Headless and not s.give_up
        a.Invulnerable=true;a["Give Up"]=false
    end
    for _,r in ipairs(a:K2_GetComponentsByClass(StaticFindObject("/Script/Engine.PrimitiveComponent"))) do
        local c=r:get()
        if valid(c) then
            local responses={};for channel=0,31 do responses[channel]=c:GetCollisionResponseToChannel(channel) end
            s.primitives[#s.primitives+1]={component=c,responses=responses,mode=c:GetCollisionEnabled(),visible=c:IsVisible(),hidden=c.bHiddenInGame}
        end
    end
    if a:IsA("/Script/Engine.Character") and valid(a.CharacterMovement) then
        s.movement=a.CharacterMovement;s.mode,s.custom=s.movement.MovementMode,s.movement.CustomMovementMode
        s.movement:StopMovementImmediately();s.movement:SetMovementMode(0,0)
    end
    if a:IsA("/Script/Engine.Pawn") and valid(a.Controller) and a.Controller:IsA("/Script/AIModule.AIController") then
        s.ai=a.Controller;s.ai:StopMovement()
        s.ai_tick=s.ai:IsActorTickEnabled();s.ai:SetActorTickEnabled(false)
        if valid(s.ai.BrainComponent) then s.ai.BrainComponent:StopLogic("Multiplayer opponent") end
    end
    -- Native handles, constraints and post-physics ticks keep their native
    -- bodies for their entire lifetime. Never toggle their simulation/ticks.
    environment_only(s)
    if s.tick and a:IsA("/Script/Engine.Pawn") then
        -- Let native body/handle setup finish while AI and player collisions are
        -- disabled. Do not create a replacement body controller.
        s.ready_at=now+2
    else a:SetActorTickEnabled(false) end
    hide(s)
end
function Waiting.hide()for _,s in pairs(saved) do if not s.active then hide(s) end end end
function Waiting.hold(pawn)
    local clock=require('UEHelpers').GetGameplayStatics():GetRealTimeSeconds(pawn:GetWorld())
    if clock-last_scan<.24 then return end
    last_scan=clock
    local world=pawn:GetWorld():GetFullName()
    for _,p in ipairs(FindAllOf("Willie_BP_C") or {}) do
        if valid(p) and not p.Player and p:GetFullName()~=pawn:GetFullName() and p:GetWorld():GetFullName()==world then
            hold(p)
            local driven=saved[p:GetFullName()] and saved[p:GetFullName()].dynamic
            local current={}
            for _,name in ipairs({"Weapon R","Weapon L"}) do
                local o=p[name]
                if valid(o) then
                    local a=o:IsA("/Script/Engine.Actor") and o or o:GetOwner()
                    if driven then current[#current+1]=a
                    elseif equipment(a) and not native_equipment[a:GetFullName()] then hold(a) end
                end
            end
            if driven then Waiting.equipment(p,current)
            else
                local attached={};p:GetAttachedActors(attached,true,true)
                for _,r in ipairs(attached) do local o=r:get();if equipment(o) and not native_equipment[o:GetFullName()] then hold(o) end end
            end
        end
    end
    -- Native delayed startup can finish equipping an AI after its actor tick
    -- was stopped. Hide those old weapons even if its hand field was replaced.
    for _,w in ipairs(FindAllOf("ModularWeaponBP_C") or {}) do
        if valid(w) and not native_equipment[w:GetFullName()] then
            local parent=w["Parent Actor"]
            local s=valid(parent) and saved[parent:GetFullName()]
            if s and not s.dynamic then hold(w) end
        end
    end
    for _,a in ipairs(FindAllOf("BP_Prop_Training_Dummy_001_C") or {}) do
        if valid(a) and a:GetWorld():GetFullName()==world then hold(a) end
    end
end
function Waiting.equipment(pawn,actors)
    local owner=pawn:GetFullName()
    for name,p in pairs(native_equipment) do if p==owner then native_equipment[name]=nil end end
    for _,a in ipairs(actors) do if valid(a) then
        native_equipment[a:GetFullName()]=owner
        local s=saved[a:GetFullName()]
        if s then
            s.active=true;s.dynamic=true;restore_responses(s)
            a:SetActorHiddenInGame(s.hidden)
            for _,p in ipairs(s.primitives) do if valid(p.component) then
                p.component:SetVisibility(p.visible,false);p.component:SetHiddenInGame(p.hidden,false)
            end end
        end
        if not a:IsActorTickEnabled() then a:SetActorTickEnabled(true) end
    end end
end
function Waiting.ensure(pawn)
    if Waiting.candidate(pawn) or valid(spawned) then return end
    -- Training mode can contain a prop and no Willie at all. Spawn the game's
    -- native fighter class once; its own construction creates its physics.
    local position
    for _,a in ipairs(FindAllOf("LevelScriptActor") or {}) do
        if valid(a) and a:GetWorld():GetFullName()==pawn:GetWorld():GetFullName()
            and a:GetClass():GetFName():ToString()=="Arena_Cutting_Map_C" then
                local p=a["Spawn Point 2"];position={X=p.X,Y=p.Y,Z=p.Z};break
            end
    end
    if not position then return end
    spawned=pawn:GetWorld():SpawnActor(pawn:GetClass(),position,{Pitch=0,Yaw=180,Roll=0})
    if valid(spawned) then
        spawned["Team Int"]=pawn["Team Int"]==0 and 1 or 0
        spawned:SpawnDefaultController()
    end
end
function Waiting.spawn_at(pawn,root)
    _G.HSMPNativeProxySpawn=true
    local ok,a=pcall(function()return pawn:GetWorld():SpawnActor(pawn:GetClass(),{X=root[1],Y=root[2],Z=root[3]},
        {Pitch=root[4],Yaw=root[5],Roll=root[6]})end)
    _G.HSMPNativeProxySpawn=nil
    if not ok then error(a)end
    if valid(a) then a['Team Int']=pawn['Team Int']==0 and 1 or 0;a:SpawnDefaultController();hold(a) end
    return a
end
function Waiting.ready(a)
    local s=valid(a) and saved[a:GetFullName()]
    return s and not s.ready_at and valid(a.Controller)
end
function Waiting.refreeze(a)
    if valid(a) and saved[a:GetFullName()] then
        local s=saved[a:GetFullName()];s.active=false;s.dynamic=false
        a:SetActorTickEnabled(false)
        if valid(s.movement) then s.movement:SetMovementMode(0,0) end
        environment_only(s);a.Invulnerable=true;hide(s)
    end
end
function Waiting.activate(a)
    if valid(a) and saved[a:GetFullName()] then
        local s=saved[a:GetFullName()];s.active=true;restore_responses(s)
    end
end
function Waiting.drive(a)
    local s=valid(a) and saved[a:GetFullName()]
    if not s then return false end
    s.active=true;s.dynamic=true;s.ready_at=nil
    restore_responses(s)
    if valid(s.movement) then s.movement:SetMovementMode(s.mode,s.custom) end
    a.Invulnerable=s.invulnerable==true
    a:SetActorHiddenInGame(false);a:SetActorEnableCollision(true);a:SetActorTickEnabled(true)
    for _,p in ipairs(s.primitives) do
        if valid(p.component) then p.component:SetVisibility(p.visible,false);p.component:SetHiddenInGame(p.hidden,false) end
    end
    return true
end
function Waiting.candidate(pawn,ready_only)
    for _,p in ipairs(FindAllOf("Willie_BP_C") or {}) do
        if valid(p) and p:GetClass():GetFName():ToString()=="Willie_BP_C" and p:GetFullName()~=pawn:GetFullName()
            and p:GetWorld():GetFullName()==pawn:GetWorld():GetFullName() and p.Health>=99 and not p.DED and not p.Headless and not p["Give Up"]
            and (not saved[p:GetFullName()] or saved[p:GetFullName()].usable)
            and valid(p.Controller) and p.Controller:IsA("/Script/AIModule.AIController")
            and (not ready_only or saved[p:GetFullName()] and not saved[p:GetFullName()].ready_at) then return p end
    end
end
function Waiting.release()
    last_scan=-1
    for _,s in pairs(saved) do
        if valid(s.actor) then
            restore_responses(s)
            for _,p in ipairs(s.primitives) do
                if valid(p.component) then
                    p.component:SetVisibility(p.visible,false);p.component:SetHiddenInGame(p.hidden,false)
                end
            end
            s.actor:SetActorEnableCollision(s.collision);s.actor:SetActorHiddenInGame(s.hidden)
            if s.fighter then
                if s.invulnerable~=nil then s.actor.Invulnerable=s.invulnerable end
                if s.give_up~=nil then s.actor["Give Up"]=s.give_up end
            end
            if valid(s.movement) then s.movement:SetMovementMode(s.mode,s.custom) end
            if valid(s.ai) and valid(s.ai.BrainComponent) then s.ai.BrainComponent:RestartLogic() end
            if valid(s.ai) and s.ai_tick~=nil then s.ai:SetActorTickEnabled(s.ai_tick) end
            s.actor:SetActorTickEnabled(s.tick)
        end
    end
    saved={}
    native_equipment={}
    if valid(spawned) then spawned:K2_DestroyActor() end
    spawned=nil
end
function Waiting.count() local n=0;for _ in pairs(saved) do n=n+1 end;return n end
function Waiting.inspect(file)
    for key,s in pairs(saved) do
        if valid(s.actor) then
            local visible=0
            for _,p in ipairs(s.primitives) do
                if valid(p.component) and p.component:IsVisible() and not p.component.bHiddenInGame then visible=visible+1 end
            end
            file:write("waiting_actor=",key,"|tick=",tostring(s.actor:IsActorTickEnabled()),"|hidden=",tostring(s.actor.bHidden),"|visible_primitives=",visible,"\n")
        end
    end
end
return Waiting
