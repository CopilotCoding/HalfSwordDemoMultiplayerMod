-- Suppress the single-player victory poll while a multiplayer session owns the arena.
local Round={}
local saved={}
local paths=require("paths")
local session,round_id="",0
local phase="waiting"
local suppressed=0
local hidden_results=0
local time_world,time_original
local guarded={}
local retired_fades={}
local next_scan=0
local surrender_widgets={}
local result_classes={'UI_KO','UI_DED','UI_Lose','UI_WIN','UI_WinScreen','UI_WinScreen_Versus'}
local function valid(o) return o~=nil and o:IsValid() end
local function now(pawn)
    local ok,helpers=pcall(require,'UEHelpers')
    if ok and helpers.GetGameplayStatics then
        local gs=helpers.GetGameplayStatics()
        if gs.GetRealTimeSeconds then return gs:GetRealTimeSeconds(pawn:GetWorld())end
    end
    return os.clock()
end
function Round.surrender(pawn)
    if not Round.can_surrender(pawn)then return false end
    Round.guard_pawn(pawn)
    local s=guarded[pawn:GetFullName()]
    s.defeat=s.defeat or 'gave_up';pawn['Give Up']=true
    return true
end
local function block_result(widget,class)
    widget:SetRenderOpacity(0);widget:SetIsEnabled(false)
    if class=='UI_KO'or class=='UI_DED'then
        widget['Can Restart']=false
        if valid(widget.Button_Restart)then widget.Button_Restart:SetIsEnabled(false)end
        widget:StopAllAnimations()
    end
end
local function retire_surrender(widget)
    if not valid(widget)then return end
    widget:CancelLatentActions();widget:StopAllAnimations();widget.TickFrequency=1
    widget:SetRenderOpacity(0);widget:SetIsEnabled(false);widget:RemoveFromParent()
end
function Round.keep_surrender_meter(widget)
    local session=_G.HSMPSession
    if not session or not session.owns_arena()then return end
    local own=session.capture_pawn and session.capture_pawn()
    local master=widget['My Master (Willie)']
    if not valid(own)or not valid(master)or master:GetFullName()~=own:GetFullName()then return end
    surrender_widgets[widget:GetFullName()]=widget
    if not Round.can_surrender(own)then
        own['Give Up']=false;own['Give Up 2 (Temp)']=false
        retire_surrender(widget);return
    end
    local state=guarded[own:GetFullName()]
    if (state and state.defeat=='gave_up')or widget['Hold Meter']>=1 then
        Round.surrender(own)
        -- Keep the native meter running until it fills. Only its completed
        -- single-player fade/menu path is retired before the shared restart.
        retire_surrender(widget)
    end
end
local injury_fields={'Health','Head Health','Body Upper Health','Body Lower Health',
    'Arm_R Health','Arm_L Health','Leg_R Health','Leg_L Health','Neck Health'}
local function badly_hurt(pawn)
    for _,field in ipairs(injury_fields)do
        local value=pawn[field]
        if type(value)=='number'and value<50 then return true end
    end
    return false
end
function Round.can_surrender(pawn)
    if not valid(pawn)or pawn.DED or pawn.Health<=0 then return false end
    return true
end
function Round.keep_surrender_prompt(widget)
    local session=_G.HSMPSession
    if not session or not session.owns_arena()or(session.in_match and not session.in_match())then return end
    local own=session.capture_pawn and session.capture_pawn()
    local master=widget['My Player']
    if not valid(own)or not valid(master)or master:GetFullName()~=own:GetFullName()then return end
    local state=guarded[own:GetFullName()]
    local prompt=widget.TextHurt
    if not state or state.defeat or not valid(prompt)then return end
    if not state.prompt_hurt and not prompt:IsVisible()then return end
    if not badly_hurt(own)then state.prompt_hurt=nil;return end
    -- Native HUD visibility can switch off when one regenerating value crosses
    -- its threshold although other limbs are still badly injured. Preserve the
    -- native prompt after it has appeared, until recovery or the next life.
    state.prompt_hurt=true
    if not prompt:IsVisible()then prompt:SetVisibility(4)end
    if prompt:GetRenderOpacity()<1 then prompt:SetRenderOpacity(1)end
end
function Round.guard_pawn(pawn)
    if not valid(pawn)then return end
    local key=pawn:GetFullName()
    local s=guarded[key]
    if not s then s={pawn=pawn,player=pawn.Player,timelines={}};guarded[key]=s
        for _,field in ipairs({'Death Timeline','Fallen Give Up TL','Slomo Timeline'})do
            local t=pawn[field];if valid(t)then s.timelines[#s.timelines+1]=t end
        end
    end
    local clock=now(pawn)
    if pawn.DED or pawn.Health<=0 then s.defeat='dead'
    elseif not s.defeat and pawn['Give Up']and pawn['Give Up 2 (Temp)']==true and Round.can_surrender(pawn)then s.defeat='gave_up'
    elseif not s.defeat then
        -- Native Force Fall briefly sets consciousness to zero, then immediately
        -- recovers. Confirm a sustained KO instead of latching that single frame.
        if pawn.Consciousness<=0 then
            s.ko_since=s.ko_since or clock
            if clock-s.ko_since>=.25 then s.defeat='unconscious'end
        else s.ko_since=nil end
        local function zero(field)local n=pawn[field];return type(n)=='number'and n<=0 end
        local function critical(field)local n=pawn[field];return type(n)=='number'and n<=1 end
        -- Native regeneration raises a destroyed leg above zero before the
        -- two-second confirmation finishes. Remember that critical injury for
        -- this fall, while still requiring native inability to get up.
        if not pawn.Fallen then s.critical_leg=nil
        elseif critical('Leg_R Health')or critical('Leg_L Health')then s.critical_leg=true end
        local no_support=pawn['Get Up Any Limb Found']==false
        local trying=pawn['Player Getting Up Pressed']==true
        if pawn.Fallen then s.fallen_since=s.fallen_since or clock else s.fallen_since=nil end
        local rate=pawn['Get Up Rate Interp']
        local stalled=pawn.Fallen and trying and s.fallen_since and clock-s.fallen_since>=12
            and type(rate)=='number'and rate<=.1
        local incapable=pawn.Fallen and (pawn['Neck Snapped']==true or zero('Consciousness 2 (Legs)')
            or(no_support and(s.critical_leg or trying)))
        if incapable then
            s.incapable_since=s.incapable_since or clock
            local delay=(s.critical_leg or pawn['Neck Snapped']==true or zero('Consciousness 2 (Legs)'))and 2 or 6
            if clock-s.incapable_since>=delay then s.defeat=s.defeat or 'incapacitated'end
        else s.incapable_since=nil end
        if stalled then s.defeat=s.defeat or 'incapacitated'end
    end
    -- Some downed states stop routing G. Forward missing press/release edges
    -- to the same native handlers; the native widget still owns its hold meter.
    local session=_G.HSMPSession
    local own=session and session.capture_pawn and session.capture_pawn()
    if Round.can_surrender(pawn)and not s.defeat and valid(own)and own:GetFullName()==key
        and (not _G.HSMPUI or not _G.HSMPUI.is_open())then
        local ok,helpers=pcall(require,'UEHelpers')
        local pc
        if ok and helpers.GetPlayerController then pc=helpers.GetPlayerController()end
        if valid(pc)and not s.routing_g then
            local held=pc:IsInputKeyDown({KeyName=FName('G')})
            if held and not s.g_held and not pawn['Give Up']then
                s.routing_g=true;s.routed_g=true
                pawn:InpActEvt_G_K2Node_InputKeyEvent_5({KeyName=FName('G')})
                s.routing_g=false
            elseif not held and s.routed_g then
                s.routing_g=true;s.routed_g=false
                pawn:InpActEvt_G_K2Node_InputKeyEvent_6({KeyName=FName('G')})
                s.routing_g=false
            end
            s.g_held=held
        end
    else s.g_held=false end
    -- Player is a native control-mode switch, not just a death-UI flag. A KO
    -- must never permanently convert the local controlled fighter into an AI.
    -- Stop exit timelines only for a latched defeat, leaving recovery alone.
    if s.defeat then
        for _,t in ipairs(s.timelines)do if valid(t)and t:IsPlaying()then t:Stop()end end
    end
    if s.defeat=='dead'then pawn.Player=false end
end
function Round.defeated(pawn)
    local s=valid(pawn)and guarded[pawn:GetFullName()]
    return s and s.defeat
end
function Round.confirm_ko(pawn)
    if not valid(pawn)then return end
    Round.guard_pawn(pawn)
    local s=guarded[pawn:GetFullName()]
    if not s.defeat then s.defeat='unconscious'end
    Round.guard_pawn(pawn)
end
function Round.install_hooks()
    _G.HSMPRoundWidgetHooks=_G.HSMPRoundWidgetHooks or{}
    _G.HSMPRoundWidgetDispatch=function(widget,class)
        if _G.HSMPSession and _G.HSMPSession.owns_arena()then
            if class=='UI_KO'then
                local pawn=widget['My Master (Willie)']
                local own=_G.HSMPSession.capture_pawn and _G.HSMPSession.capture_pawn()
                if valid(pawn)and valid(own)and pawn:GetFullName()==own:GetFullName()then
                    Round.confirm_ko(pawn)
                end
            end
            block_result(widget,class)
            hidden_results=hidden_results+1
        end
    end
    for _,class in ipairs(result_classes)do
        local fn='/Game/UI/'..class..'.'..class..'_C:Construct'
        if not _G.HSMPRoundWidgetHooks[fn]and valid(StaticFindObject(fn))then
            _G.HSMPRoundWidgetHooks[fn]={RegisterHook(fn,function(ctx)
                if _G.HSMPRoundWidgetDispatch then _G.HSMPRoundWidgetDispatch(ctx:get(),class)end
            end)}
        end
    end
    _G.HSMPSurrenderPromptDispatch=Round.keep_surrender_prompt
    -- The cooked HUD uses Unreal's fast event-graph path, bypassing its Tick
    -- wrapper. Run after the graph so native visibility has finished updating.
    local hud='/Game/UI/UI_HUD.UI_HUD_C:ExecuteUbergraph_UI_HUD'
    if not _G.HSMPRoundWidgetHooks[hud]and valid(StaticFindObject(hud))then
        _G.HSMPRoundWidgetHooks[hud]={RegisterHook(hud,function(ctx)
            if _G.HSMPSurrenderPromptDispatch then _G.HSMPSurrenderPromptDispatch(ctx:get())end
        end)}
    end
    _G.HSMPSurrenderMeterDispatch=Round.keep_surrender_meter
    local meter='/Game/UI/UI_GiveUp.UI_GiveUp_C:ExecuteUbergraph_UI_GiveUp'
    if not _G.HSMPRoundWidgetHooks[meter]and valid(StaticFindObject(meter))then
        _G.HSMPRoundWidgetHooks[meter]={RegisterHook(meter,function(ctx)
            if _G.HSMPSurrenderMeterDispatch then _G.HSMPSurrenderMeterDispatch(ctx:get())end
        end)}
    end
end
function Round.hold(world)
    local gameplay=require("UEHelpers").GetGameplayStatics()
    if not time_world then time_world=world;time_original=gameplay:GetGlobalTimeDilation(world) end
    -- Native KO/result-card callbacks can leave the arena at half speed. Online
    -- rounds share wall-clock timing and keep normal simulation speed.
    if math.abs(gameplay:GetGlobalTimeDilation(world)-1)>.0001 then gameplay:SetGlobalTimeDilation(world,1) end
    -- Result-card callbacks can pause after their widget was removed. A ready
    -- multiplayer round keeps simulating while either PC has a menu open.
    if gameplay:IsGamePaused(world) then gameplay:SetGamePaused(world,false) end
    -- Result constructors are guarded immediately. Discovery of retired UI
    -- and rule actors need not scan the entire object store every snapshot.
    if os.clock()<next_scan then return end
    next_scan=os.clock()+.1
    local function stop(a)
        if not valid(a) or a:GetWorld():GetFullName()~=world:GetFullName() then return end
        local key=a:GetFullName()
        if not saved[key] then
            local s={actor=a,tick=a:IsActorTickEnabled()};saved[key]=s
            if a:GetClass():GetFName():ToString()=="BP_HalfSwordGameMode_C" then
                s.count=a["Enemy Count"];s.won=a["Match Won"];s.all=a["All Enemies Dead"]
                s.gauntlet=a["Gauntlet Mode Enabled"]
            end
        end
        if saved[key].count then
            a["Enemy Count"]=math.max(1,a["Enemy Count"]);a["Match Won"]=false;a["All Enemies Dead"]=false
            a["Gauntlet Mode Enabled"]=false
        end
        a:SetActorTickEnabled(false)
    end
    for _,a in ipairs(FindAllOf("LevelScriptActor") or {}) do stop(a) end
    for _,a in ipairs(FindAllOf("BP_HalfSwordGameMode_C") or {}) do stop(a) end
    local removed=false
    -- LevelReset's fade widget can survive invisibly with a repeating latent
    -- UI-only/FlushInput callback. Removing its viewport parent is insufficient.
    -- Let the native reset finish, then retire the fade when the life is ready.
    for _,w in ipairs(FindAllOf('UI_FadeOut_C')or{})do
        if valid(w)and w:GetWorld():GetFullName()==world:GetFullName()
            and not retired_fades[w:GetFullName()]then
            w['Is Opened']=false
            w:CancelLatentActions();w:StopAllAnimations();w.TickFrequency=1
            w:SetRenderOpacity(0);w:SetIsEnabled(false);w:RemoveFromParent()
            retired_fades[w:GetFullName()]=true;removed=true
        end
    end
    local widgets={'UI_Cards_C'}
    for _,class in ipairs(result_classes)do widgets[#widgets+1]=class..'_C'end
    for _,name in ipairs(widgets) do
        local setup_pending=name=='UI_Cards_C'and _G.HSMPMatch and not _G.HSMPMatch.playable()
        for _,w in ipairs(FindAllOf(name) or {}) do
            if not setup_pending and valid(w) and w:GetWorld():GetFullName()==world:GetFullName() and w:IsInViewport() then
                block_result(w,name:gsub('_C$',''))
                if name=='UI_Cards_C'and _G.HSMPMatch and _G.HSMPMatch.retire_card then
                    _G.HSMPMatch.retire_card(w)
                else w:RemoveFromParent()end
                suppressed=suppressed+1;removed=true
            end
        end
    end
    if removed and (not _G.HSMPUI or not _G.HSMPUI.is_open()) then
        local pc=require("UEHelpers").GetPlayerController()
        if valid(pc) then
            StaticFindObject("/Script/UMG.Default__WidgetBlueprintLibrary"):SetInputMode_GameOnly(pc,true)
            pc.bShowMouseCursor=false
        end
    end
end
-- Only a new host-issued round number requests a native reset. Repeated UDP
-- snapshots and a repeated countdown never reset the arena a second time.
function Round.poll(world,before_reset)
    local f=io.open(paths.runtime.."/round.cfg","rb")
    if not f then return false end
    local text=f:read(257) or "";f:close()
    if #text>256 or text:sub(-1)~="\n" then return false end
    local p={};for v in text:gmatch("[^|\r\n]+") do p[#p+1]=v end
    local id,stamp=tonumber(p[3]),tonumber(p[7])
    if #p~=7 or p[1]~="HSROUND1" or #p[2]~=32 or not p[2]:match("^[a-f0-9]+$")
        or not id or id<0 or id%1~=0 or not stamp or math.abs(os.time()-stamp)>=3 then return false end
    if p[4]~="waiting" and p[4]~="playing" and p[4]~="restart" and p[4]~="respawning" then return false end
    phase=p[4]
    if session~=p[2] then
        session,round_id=p[2],phase=="respawning" and id-1 or id
        if phase~="respawning" then return false end
    elseif id<=round_id then return false end
    if id<2 then round_id=id;return false end
    for _,a in ipairs(FindAllOf("LevelScriptActor") or {}) do
        if valid(a) and a:GetWorld():GetFullName()==world:GetFullName()
            and a:GetClass():GetFName():ToString()=="Arena_Cutting_Map_C" then
            for _,widget in pairs(surrender_widgets)do retire_surrender(widget)end
            surrender_widgets={}
            before_reset()
            guarded={}
            a:LevelReset()
            round_id=id
            if not _G.HSMPMatch or _G.HSMPMatch.playable()then Round.hold(world)end
            print("[HalfSwordMP] Native multiplayer round reset: "..id.."\n")
            return true
        end
    end
    return false
end
function Round.release()
    for _,widget in pairs(surrender_widgets)do retire_surrender(widget)end
    surrender_widgets={}
    guarded={}
    retired_fades={}
    next_scan=0
    if valid(time_world) then require("UEHelpers").GetGameplayStatics():SetGlobalTimeDilation(time_world,time_original) end
    time_world,time_original=nil,nil
    for _,s in pairs(saved) do
        if valid(s.actor) then
            s.actor:SetActorTickEnabled(s.tick)
            if s.count then
                s.actor["Enemy Count"]=s.count;s.actor["Match Won"]=s.won;s.actor["All Enemies Dead"]=s.all
                s.actor["Gauntlet Mode Enabled"]=s.gauntlet
            end
        end
    end
    saved={}
    session,round_id,phase="",0,"waiting"
end
function Round.inspect(f)
    f:write("multiplayer_round=",round_id,"\nround_phase=",phase,"\n")
    f:write("single_player_result_screens_suppressed=",suppressed,"\n")
    f:write('native_result_widgets_hidden_at_construct=',hidden_results,'\n')
    for _,s in pairs(saved) do
        if valid(s.actor) then
            f:write("round_poll_disabled=",tostring(not s.actor:IsActorTickEnabled()),"\n")
            if s.count then f:write("native_match_won=",tostring(s.actor["Match Won"]),
                "\nnative_gauntlet_enabled=",tostring(s.actor["Gauntlet Mode Enabled"]),"\n") end
        end
    end
end
return Round
