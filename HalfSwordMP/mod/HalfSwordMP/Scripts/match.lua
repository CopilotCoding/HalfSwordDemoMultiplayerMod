-- Enter the multiplayer rules through the game's existing Start delegate.
-- Character creation, equipment selection and save data stay owned by the game.
local Match={}
local helpers,paths=require("UEHelpers"),require("paths")
local active,last_request,ready=false,"",false
local started=false
local awaiting_card=false
local reset_card_needed=false
local pending_entry=false
local duel_type
local cards_bypassed=0
local tutorial_instance,tutorial_original
local selection
local instance_selection
local selected_loadout,loadout_pawn,loadout_after,loadout_done
local Equipment
local retired_cards={}
local next_menu_scan=0
local next_card_scan=0
local function valid(o) return o~=nil and o:IsValid() end
function Match.retire_card(card)
    if not valid(card)then return end
    local name=card:GetFullName()
    if not retired_cards[name]then
        -- RemoveFromParent alone leaves the native card's repeating latent
        -- UI-only input callbacks alive. They flush held keys every half second.
        -- Retire only after its real Duel/start animation and loadout finish.
        card.Destroyed=true
        card:CancelLatentActions()
        card:StopAllAnimations()
        card.TickFrequency=1 -- EWidgetTickFrequency::Never
        retired_cards[name]=true
    end
    if card:IsInViewport()then card:RemoveFromParent()end
end
local function remember_selection()
    if selection then return end
    local mode=helpers.GetGameModeBase and helpers.GetGameModeBase()
    if not valid(mode)then return end
    selection={}
    for _,key in ipairs({'Player Rank','Player Team','Free Armor','Faction Chosen','Body Chosen','Abyss'})do
        local value=mode[key]
        if type(value)=='number'or type(value)=='boolean'then selection[key]=value end
    end
    local instance=helpers.GetGameInstance and helpers.GetGameInstance()
    if valid(instance)then
        instance_selection={}
        for _,key in ipairs({'Player Head','Player Garment','Player Cuirass','Player R Arm','Player L Arm','Player Team'})do
            local value=instance[key];if type(value)=='number'then instance_selection[key]=value end
        end
    end
end
local function restore_selection()
    local mode=helpers.GetGameModeBase and helpers.GetGameModeBase()
    if not valid(mode)then return end
    for key,value in pairs(selection or{})do mode[key]=value end
    mode['Player DED']=false
    local instance=helpers.GetGameInstance and helpers.GetGameInstance()
    if valid(instance)then for key,value in pairs(instance_selection or{})do instance[key]=value end end
end
function Match.loadout_ready(pawn)
    if not valid(pawn)then return false end
    local name=pawn:GetFullName()
    local clock=helpers.GetGameplayStatics():GetRealTimeSeconds(pawn:GetWorld())
    if name~=loadout_pawn then loadout_pawn,loadout_after,loadout_done=name,clock+2,false end
    if loadout_done==true then return true end
    if clock<loadout_after then return false end
    Equipment=Equipment or dofile(paths.scripts..'/equipment.lua')
    if loadout_done=='settling'then
        Equipment.restore_cosmetics(pawn,selected_loadout)
        loadout_done=true;return true
    end
    if not selected_loadout then selected_loadout=Equipment.save_loadout(pawn)
    else
        Equipment.restore_loadout(pawn,selected_loadout)
        loadout_after=clock+.5;loadout_done='settling';return false
    end
    loadout_done=true
    return true
end
local function launcher_alive()
    local f=io.open(paths.runtime.."/ui.state","r")
    if not f then return false end
    local line=f:read(2048) or "";f:close()
    local stamp=tonumber(line:match("|([%d%.]+)\n$"))
    return stamp~=nil and math.abs(os.time()-stamp)<4
end
local function report(phase,message)
    local f=io.open(paths.runtime.."/match.state","w")
    if f then f:write("HSMPMATCHSTATE1|",phase,"|",message,"|",os.time(),"\n");f:close() end
end
function Match.active() return active end
function Match.playable() return ready end
function Match.restart()
    -- LevelReset creates opening cards again. Their native Duel handler owns
    -- equipment/possession setup on every round, not only the first entry.
    ready=false;started=false;pending_entry=false;awaiting_card=true;reset_card_needed=true
    restore_selection()
end
function Match.leave()
    if valid(tutorial_instance) then tutorial_instance.Tutorial=tutorial_original end
    tutorial_instance,tutorial_original=nil,nil
    selection=nil
    instance_selection=nil
    selected_loadout,loadout_pawn,loadout_after,loadout_done=nil,nil,nil,nil
    active=false;ready=false;started=false;pending_entry=false;awaiting_card=false;reset_card_needed=false;report("off","Choose Host or Join, then Enter multiplayer match")
end
local function bypass_tutorial()
    local instance=helpers.GetGameInstance and helpers.GetGameInstance()
    if valid(instance) then
        if not tutorial_instance then tutorial_instance=instance;tutorial_original=instance.Tutorial end
        instance.Tutorial=false -- Runtime only; do not save the player's settings.
    end
end
local function native_duel_type()
    if duel_type then return duel_type end
    local enum=StaticFindObject('/Game/Blueprints/Enumerator/Enum_PlayCards.Enum_PlayCards')
    local library=StaticFindObject('/Script/Engine.Default__KismetNodeHelperLibrary')
    if valid(enum) and valid(library) then
        for i=0,10 do
            if library:GetEnumeratorUserFriendlyName(enum,i):ToString():lower()=='duel' then duel_type=i;return i end
        end
    end
end
function Match.block_cards(widget)
    if (active or launcher_alive()) and valid(widget) then
        widget:SetRenderOpacity(0)
        widget:SetIsEnabled(false)
    end
end
function Match.menu(world)
    Match.install_hooks()
    if not active and launcher_alive() then
        for _,card in ipairs(FindAllOf("UI_Cards_C") or {}) do
            if valid(card) and card:GetWorld():GetFullName()==world:GetFullName() and card:IsInViewport() then Match.block_cards(card) end
        end
    end
end
function Match.install_hooks()
    if _G.HSMPMatchCardHook then return end
    local name="/Game/UI/UI_Cards.UI_Cards_C:Construct"
    if not valid(StaticFindObject(name)) then LoadAsset("/Game/UI/UI_Cards") end
    if valid(StaticFindObject(name)) then
        _G.HSMPMatchCardHook={RegisterHook(name,function(context)
            if _G.HSMPMatch then _G.HSMPMatch.block_cards(context:get()) end
        end)}
    end
end
function Match.prepare(world)
    if not active then return end
    if ready then
        if os.clock()<next_card_scan then return end
        next_card_scan=os.clock()+.25
    end
    local found=false
    for _,card in ipairs(FindAllOf("UI_Cards_C") or {}) do
        if valid(card) and card:GetWorld():GetFullName()==world:GetFullName() and card:IsInViewport() then
            found=true;reset_card_needed=false
            Match.block_cards(card)
            if not ready and not started then
                native_duel_type()
                if not duel_type or not valid(card.Card_1) then
                    report("error","Could not find the demo's native duel start action")
                    return
                end
                -- Run the complete native card handler, including equipment,
                -- pause and invulnerability handoff. Calling GM Duel alone
                -- skips that setup and leaves a paused, unequipped fighter.
                card["Card 1 Type"]=duel_type
                restore_selection()
                if selection and selection['Player Rank']then card['Player Rank']=selection['Player Rank']end
                started=true;awaiting_card=false;cards_bypassed=cards_bypassed+1
                card.Card_1.OnClicked:Broadcast()
            elseif ready then
                Match.retire_card(card);cards_bypassed=cards_bypassed+1
            end
            -- Keep the invisible widget ticking until its native selection
            -- animation finishes. Removing it early strands the game paused.
        end
    end
    if reset_card_needed and not found then
        -- LevelReset can skip creating cards when the level's victory poll is
        -- disabled. Construct the same native widget so its complete bound
        -- Duel handler still owns equipment/startup on the next update.
        local class=StaticFindObject('/Game/UI/UI_Cards.UI_Cards_C')
        local library=StaticFindObject('/Script/UMG.Default__WidgetBlueprintLibrary')
        local pc=helpers.GetPlayerController()
        if valid(class)and valid(library)and valid(pc)then
            local card=library:Create(world,class,pc)
            if valid(card)then card:AddToViewport(0);Match.block_cards(card);reset_card_needed=false end
        end
    end
end
function Match.ready(world,pawn)
    if awaiting_card then return false end
    if not active or (not ready and helpers.GetGameplayStatics():IsGamePaused(world)) then return false end
    if not started then
        local mode=helpers.GetGameModeBase and helpers.GetGameModeBase()
        local duel=native_duel_type()
        if not valid(mode) or not duel or mode['Current PlayCard']~=duel then
            report('loading','Waiting for the native duel to start')
            return false
        end
        started=true
    end
    if active and not ready then
        remember_selection()
        for _,card in ipairs(FindAllOf('UI_Cards_C')or{})do
            if valid(card)and card:GetWorld():GetFullName()==world:GetFullName()and card:IsInViewport()
                and valid(card.Select_Card_1)and card:IsAnimationPlaying(card.Select_Card_1)then return false end
        end
        -- Native startup initially possesses an unequipped pawn. Wait for its
        -- own setup before saving/restoring the selected loadout once per life.
        if pawn and not Match.loadout_ready(pawn)then return false end
        for _,name in ipairs({"UI_MainMenuSNF_C","UI_Cards_C","UI_Lose_C"}) do
            for _,widget in ipairs(FindAllOf(name) or {}) do
                if valid(widget) and widget:GetWorld():GetFullName()==world:GetFullName() then
                    if name=='UI_Cards_C'then Match.retire_card(widget)
                    elseif widget:IsInViewport()then widget:RemoveFromParent()end
                end
            end
        end
        -- Re-evaluate input after the real fighter is possessed. Closing the
        -- panel while the free camera still owns input leaves the vanilla UI.
        if _G.HSMPUI then _G.HSMPUI.set_open(false) end
        ready=true;report("active","Multiplayer match ready - waiting for the other fighter")
    end
    return ready
end
function Match.enter(world,pawn)
    if active then return true end
    -- Broadcast the actual bound Start event; do not reproduce its equipment,
    -- selected-body or save-slot logic in the mod.
    for _,menu in ipairs(FindAllOf("UI_MainMenuSNF_C") or {}) do
        if valid(menu) and menu:GetWorld():GetFullName()==world:GetFullName() and menu:IsInViewport() then
            local start=menu.Button_Start
            if not valid(start) or not start:GetIsEnabled() then
                report("error","Finish selecting your fighter before entering multiplayer")
                return false
            end
            if menu["Can Start"]==false then
                pending_entry=true
                report("loading","Waiting for the native fighter selection to finish loading")
                return false
            end
            local mode=helpers.GetGameModeBase and helpers.GetGameModeBase()
            if valid(mode) and mode["Gauntlet Mode Enabled"]==true and valid(menu.ButtonFreeMode) then
                -- The demo's Gauntlet start replaces the preview loadout with
                -- progression gear. Use its native free-combat start instead.
                pending_entry=true
                menu.ButtonFreeMode.OnClicked:Broadcast()
                report("loading","Preparing native combat with your selected fighter")
                return false
            end
            pending_entry=false
            active=true
            remember_selection()
            local preview=menu.MyDressUpDarling
            if valid(preview)and not selected_loadout then
                Equipment=Equipment or dofile(paths.scripts..'/equipment.lua')
                selected_loadout=Equipment.save_loadout(preview)
            end
            awaiting_card=true
            bypass_tutorial()
            Match.install_hooks()
            start.OnClicked:Broadcast()
            report("loading","Entering multiplayer with your selected fighter")
            return true
        end
    end
    -- A game already sitting at its opening cards can enter directly too.
    for _,card in ipairs(FindAllOf("UI_Cards_C") or {}) do
        if valid(card) and card:GetWorld():GetFullName()==world:GetFullName() and card:IsInViewport() then
            active=true;remember_selection();awaiting_card=true;Match.install_hooks();Match.prepare(world)
            report("loading","Entering multiplayer with your selected fighter")
            return true
        end
    end
    if valid(pawn) and pawn:GetClass():GetFName():ToString()=="Willie_BP_C"
        and world:GetFullName():find("/Game/Maps/Arena_Cutting_Map.",1,true) then
        -- An existing fighter can enter the rules without being respawned.
        active=true;remember_selection();bypass_tutorial();Match.ready(world)
        return true
    end
    report("error","Open the game's fighter selection, select your fighter, then enter multiplayer")
    return false
end
function Match.poll(world,pawn)
    if ready and os.clock()>=next_menu_scan then
        next_menu_scan=os.clock()+.25
        for _,menu in ipairs(FindAllOf('UI_MainMenuSNF_C')or{})do
            if valid(menu)and menu:GetWorld():GetFullName()==world:GetFullName()and menu:IsInViewport()then
                -- Returning to fighter selection ends this entry. Starting
                -- again requires a fresh Enter request and a fresh loadout.
                -- Never treat a visible main menu as permission to auto-start.
                Match.leave()
                return false
            end
        end
    end
    if pending_entry then Match.enter(world,pawn) end
    local f=io.open(paths.runtime.."/match.request","r")
    if not f then return active end
    local text=f:read(257) or "";f:close()
    if #text>256 or text:sub(-1)~="\n" then return active end
    local nonce,stamp=text:match("^HSMPMATCH1|([%w_%-]+)|([%d%.]+)\n$")
    if not nonce or nonce==last_request or not tonumber(stamp) or math.abs(os.time()-tonumber(stamp))>=5 then return active end
    last_request=nonce
    Match.enter(world,pawn)
    return active
end
function Match.inspect(f) f:write("opening_card_choices_bypassed=",cards_bypassed,"\nnative_duel_started=",tostring(started),"\n") end
return Match
