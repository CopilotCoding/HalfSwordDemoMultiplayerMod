local UI={}
_G.HSMPUICallbacks={} -- Disable the retired Deactivate route after a hot reload.
local helpers,paths=require("UEHelpers"),require("paths")
local widget,canvas,panel,status,address,port,automatic,router,world_name,restart
local open,sequence,ticks=true,0,0
local receivers={}
local last_auto,settings_loaded=false,false
local previous_cursor
local companion_time=0
local direct_panel,steam_panel,password,lobby_name,privacy_button,steam_status,page_label,max_players
local tab,privacy,list_mode,page='direct','friends','public',1
local list_buttons,list_targets={},{}
local steam_role,last_invite='',nil
local function hex(s)return(s:gsub('.',function(c)return string.format('%02x',string.byte(c))end))end
local function unhex(s)return s=='-'and''or(s:gsub('%x%x',function(c)return string.char(tonumber(c,16))end))end
local function split(s)local r={};for v in s:gmatch('[^|\r\n]+')do r[#r+1]=v end;return r end
local function clip(s,n)local at=utf8.offset(s,n+1);return at and s:sub(1,at-1)or s end
_G.HSMPUIActionQueue=_G.HSMPUIActionQueue or {}
_G.HSMPUIToggleRequests=_G.HSMPUIToggleRequests or 0
local function valid(o) return o~=nil and o:IsValid() end
local function intact_widgets()
    return valid(widget)and valid(canvas)and valid(panel)and valid(status)and valid(address)
        and valid(port)and valid(automatic)and valid(restart)and valid(password)and valid(lobby_name)
        and valid(direct_panel)and valid(steam_panel)and valid(privacy_button)and valid(steam_status)and valid(page_label)
        and valid(max_players)
end
local function text(s) return StaticFindObject("/Script/Engine.Default__KismetTextLibrary"):Conv_StringToText(s) end
local function string_value(t) return t:ToString() end
local function make(class,outer) return StaticConstructObject(StaticFindObject("/Script/UMG."..class),outer or widget.WidgetTree) end
local function place(parent,child,x,y,w,h)
    local slot=parent:AddChildToCanvas(child)
    slot:SetPosition({X=x,Y=y});slot:SetSize({X=w,Y=h});return child
end
local function label(value,size)
    local t=make("TextBlock")
    local font=t.Font
    font.FontObject=StaticFindObject("/Engine/EngineFonts/Roboto.Roboto")
    font.Size=size or 18
    t:SetFont(font);t:SetText(text(value));return t
end
local function request(action,value,target)
    if not intact_widgets()then return false end
    if os.time()-companion_time>4 then
        if valid(status) then status:SetText(text("Launcher offline. Start the game with Start Multiplayer.cmd.")) end
        return false
    end
    sequence=sequence+1
    local host=string_value(address:GetText()):gsub("[|\r\n]","")
    local number=tonumber(string_value(port:GetText())) or 7777
    local f=io.open(paths.runtime.."/ui.command","w")
    local secret=valid(password)and hex(string_value(password:GetText()))or''
    local name=valid(lobby_name)and hex(string_value(lobby_name:GetText()))or''
    local limit=tonumber(string_value(max_players:GetText()))or 4
    if f then f:write("HSUI3|",os.time(),"-",sequence,"|",action,"|",number,"|",host=="" and "-" or host,"|",value and "1" or "0",
        '|',tab,'|',privacy,'|',name==''and'-'or name,'|',secret==''and'-'or secret,'|',target or'-','|',limit,"\n");f:close() end
    return f~=nil
end
function UI.is_open() return open and valid(widget) end
function UI.set_open(value)
    local pc=helpers.GetPlayerController()
    local library=StaticFindObject("/Script/UMG.Default__WidgetBlueprintLibrary")
    if not valid(pc) or not valid(library) or not intact_widgets()then return end
    open=value
    -- Keep native settings alive underneath F5; restore their focus on close.
    -- Removing focused native widgets here can invalidate Slate's focus path.
    panel:SetVisibility(open and 0 or 1)
    if open then
        previous_cursor=pc.bShowMouseCursor;pc.bShowMouseCursor=true
        library:SetInputMode_UIOnlyEx(pc,tab=='steam'and valid(lobby_name)and lobby_name or address,0,true)
    else
        local p=helpers.GetPlayer()
        local in_fight=valid(p) and p:GetClass():GetFName():ToString()=="Willie_BP_C"
        pc.bShowMouseCursor=not in_fight
        if _G.HSMPPause and _G.HSMPPause.restore_focus()then return end
        if in_fight then
            library:SetInputMode_GameOnly(pc,true)
            p:EnableInput(pc);pc:ResetIgnoreMoveInput();pc:ResetIgnoreLookInput()
        else library:SetInputMode_GameAndUIEx(pc,widget,0,false,true) end
    end
end
local function button(parent,value,x,y,w,action)
    local b=make("Button")
    b:AddChild(label(value,18));place(parent,b,x,y,w,42)
    -- Delegate recipients must be registered, actor-owned components. A bare
    -- constructed UObject can be collected and deactivated during play.
    local receiver=router:AddComponentByClass(StaticFindObject("/Script/Engine.SceneComponent"),
        true,router:GetTransform(),false)
    receiver:SetComponentTickEnabled(false)
    receivers[#receivers+1]=receiver
    _G.HSMPUIClickCallbacks[receiver:GetFullName()]=action
    b.OnClicked:Add(receiver,FName("ToggleActive"))
    return b
end
local function switch_tab(value)
    tab=value
    direct_panel:SetVisibility(tab=='direct'and 0 or 1)
    steam_panel:SetVisibility(tab=='steam'and 0 or 1)
    if tab=='steam'then request('steam_open')end
end
local function text_box(parent,x,y,w,h,hint)
    local box=place(parent,make('EditableTextBox'),x,y,w,h)
    box:SetForegroundColor({R=0,G=0,B=0,A=1})
    if hint then box:SetHintText(text(hint))end
    return box
end
function UI.destroy()
    -- Deactivation also happens during teardown; it must not act like a click.
    _G.HSMPUICallbacks={}
    _G.HSMPUIClickCallbacks={}
    _G.HSMPUIActionQueue={};_G.HSMPUIToggleRequests=0
    -- Clear Slate's focused descendant before removing a partially retired
    -- tree. A live shell does not guarantee its native child widgets survived.
    if valid(widget)then
        local pc=helpers.GetPlayerController()
        local library=StaticFindObject('/Script/UMG.Default__WidgetBlueprintLibrary')
        if valid(pc)and valid(library)then library:SetInputMode_GameOnly(pc,false)end
    end
    if valid(widget) then widget:RemoveFromParent() end
    if valid(router) then router:K2_DestroyActor() end
    widget,canvas,panel,status,address,port,automatic,router=nil,nil,nil,nil,nil,nil,nil,nil
    restart=nil
    direct_panel,steam_panel,password,lobby_name,privacy_button,steam_status,page_label=nil,nil,nil,nil,nil,nil,nil
    list_buttons,list_targets={},{};steam_role=''
    receivers={}
    settings_loaded=false
end
local function create()
    local pc=helpers.GetPlayerController()
    if not valid(pc) then return end
    local shell=StaticFindObject("/Game/UI/PhotoMode/Widgets/UI_CommandButton.UI_CommandButton_C")
    if not valid(shell) then
        LoadAsset("/Game/UI/PhotoMode/Widgets/UI_CommandButton")
        shell=StaticFindObject("/Game/UI/PhotoMode/Widgets/UI_CommandButton.UI_CommandButton_C")
    end
    if not valid(shell) then return end
    widget=StaticFindObject("/Script/UMG.Default__WidgetBlueprintLibrary"):Create(helpers.GetWorld(),shell,pc)
    widget.TickFrequency=0
    canvas=make("CanvasPanel")
    widget.WidgetTree.RootWidget=canvas
    router=helpers.GetWorld():SpawnActor(StaticFindObject("/Script/Engine.Actor"),{X=0,Y=0,Z=0},{Pitch=0,Yaw=0,Roll=0})
    _G.HSMPUIClickCallbacks=_G.HSMPUIClickCallbacks or {}
    if not _G.HSMPUIClickHook then
        _G.HSMPUIClickHook={RegisterHook("/Script/Engine.ActorComponent:ToggleActive",function(context)
            local key=context:get():GetFullName()
            local callback=_G.HSMPUIClickCallbacks[key]
            if callback then
                local queue=_G.HSMPUIActionQueue
                if #queue<32 then queue[#queue+1]=key end
            end
        end)}
    end
    button(canvas,"Multiplayer  [F5]",22,18,250,function() UI.set_open(not open) end)
    local border=make("Border")
    border:SetBrushColor({R=.025,G=.035,B=.05,A=.98})
    place(canvas,border,22,70,640,990)
    panel=border
    local content=make("CanvasPanel");border:AddChild(content)
    place(content,label("HALF SWORD  /  MULTIPLAYER",24),24,20,590,36)
    status=place(content,label("Offline — choose Host or Join",17),24,66,590,48)
    status:SetAutoWrapText(true)
    direct_panel=place(content,make('CanvasPanel'),0,190,640,456)
    steam_panel=place(content,make('CanvasPanel'),0,190,640,456)
    place(direct_panel,label("Host IP (Join only)",16),24,0,380,28)
    place(direct_panel,label("UDP port",16),440,0,160,28)
    address=text_box(direct_panel,24,32,390,42,'Only needed when joining')
    port=text_box(direct_panel,440,32,170,42);port:SetText(text("7777"))
    button(direct_panel,"Host",24,206,282,function()
        if request("host") then status:SetText(text("Starting host...")) end
    end)
    button(direct_panel,"Join",326,206,282,function()
        if request("join") then status:SetText(text("Connecting...")) end
    end)
    button(content,"Disconnect",24,728,180,function() request("disconnect") end)
    button(content,"Enter multiplayer match",24,670,282,function()
        if request("enter_match") then status:SetText(text("Entering multiplayer with your selected fighter...")) end
    end)
    restart=button(content,"Restart round",326,670,282,function()
        if request("restart_round")then status:SetText(text("Starting the next multiplayer round..."))end
    end)
    restart:SetVisibility(1);restart:SetIsEnabled(false)
    button(content,'Steam',24,130,282,function()switch_tab('steam')end)
    button(content,'Direct IP / Port Forward',326,130,282,function()switch_tab('direct')end)
    place(content,label('Optional password',15),24,276,390,28)
    place(content,label('Host limit (2-16)',15),440,276,170,28)
    -- One password field is shared by both tabs and never saved in preferences.
    password=text_box(content,24,304,390,42,'Leave blank for no password');password:SetIsPassword(true)
    max_players=text_box(content,440,304,170,42);max_players:SetText(text('4'))
    place(direct_panel,label('Host: forward this UDP port for Internet play.\nJoin: enter the host address and password if set.\nDirect hosts are never publicly listed.',17),24,280,584,110)
    place(steam_panel,label('Lobby name',16),24,0,282,26)
    lobby_name=text_box(steam_panel,24,26,282,40,"Your match's name")
    privacy_button=button(steam_panel,'Friends only',326,26,282,function()
        privacy=privacy=='friends'and'invite'or privacy=='invite'and'public'or'friends'
        privacy_button:GetContent():SetText(text(privacy=='friends'and'Friends only'or privacy=='invite'and'Invite only'or'Public'))
    end)
    button(steam_panel,'Create lobby',326,156,282,function()request('steam_host')end)
    button(steam_panel,'Friends',24,156,282,function()list_mode='friends';page=1;request('steam_friends')end)
    button(steam_panel,'Public lobbies / Refresh',24,208,282,function()list_mode='public';page=1;request('steam_refresh')end)
    button(steam_panel,'Accept invite',326,208,282,function()request('steam_join')end)
    steam_status=place(steam_panel,label('Steam lobbies need no port forwarding.',14),24,258,584,42);steam_status:SetAutoWrapText(true)
    for i=1,3 do
        local index=i
        list_buttons[i]=button(steam_panel,'No lobbies loaded',24,302+(i-1)*44,584,function()
            local item=list_targets[index];if item then request(item.action,nil,item.id)end
        end)
        list_buttons[i]:SetIsEnabled(false)
    end
    button(steam_panel,'Previous',24,438,140,function()page=math.max(1,page-1)end)
    page_label=place(steam_panel,label('Page 1',15),190,444,190,30)
    button(steam_panel,'Next',440,438,168,function()page=page+1 end)
    place(content,label('Hold G to fill the give-up meter. Release to cancel.',15),24,780,590,30)
    automatic=place(content,make("CheckBox"),24,818,28,30)
    automatic:SetIsChecked(last_auto)
    place(content,label("Automatic updates from the host",16),66,818,500,30)
    button(content,"Check for update",24,858,282,function() request("check_updates") end)
    button(content,"Apply update & restart",326,858,282,function() request("apply_update") end)
    place(content,label("Selected gear returns each round. E / Q: pick up enemy drops.\nSteam lists Steam lobbies only. F5: menu.",15),24,916,590,62)
    widget:AddToViewport(10000)
    switch_tab(tab)
    UI.set_open(open)
end
function UI.tick()
    ticks=ticks+1
    local world=helpers.GetWorld()
    if not valid(world) then return end
    if world_name~=world:GetFullName() then UI.destroy();world_name=world:GetFullName() end
    if valid(widget)then
        local intact=intact_widgets()and valid(router)
        for _,receiver in ipairs(receivers)do if not valid(receiver)then intact=false;break end end
        -- Native LevelReset can remove actors/components without replacing
        -- viewport widgets. Rebuild their delegate recipients together.
        if not intact then UI.destroy()end
    end
    if not valid(widget) then create() end
    if not valid(widget) then return end
    if not widget:IsInViewport() then widget:AddToViewport(10000) end
    -- Input callbacks only enqueue intent. All widget, focus and connection
    -- operations run inside the adapter's single game-thread update.
    local toggles=_G.HSMPUIToggleRequests;_G.HSMPUIToggleRequests=0
    if toggles%2==1 then UI.toggle() end
    local queued=_G.HSMPUIActionQueue;_G.HSMPUIActionQueue={}
    for _,key in ipairs(queued) do
        local callback=_G.HSMPUIClickCallbacks[key]
        if callback then callback() end
    end
    if ticks%10==0 then
        local f=io.open(paths.runtime.."/ui.state","r")
        if f then
            local line=f:read(2048) or "";f:close()
            local values={};for v in line:gmatch("[^|\r\n]+") do values[#values+1]=v end
            if values[1]=="HSUISTATE1" and tonumber(values[8]) and math.abs(os.time()-tonumber(values[8]))<4 then
                companion_time=tonumber(values[8])
                restart:SetVisibility((values[9]=='host'or values[9]=='join')and 0 or 1)
                restart:SetIsEnabled(values[10]=='1')
                status:SetText(text(values[2] or "Offline"))
                local enabled=values[3]=="1"
                if enabled~=last_auto then automatic:SetIsChecked(enabled);last_auto=enabled end
                if not settings_loaded then
                    if string_value(address:GetText())=="" then address:SetText(text(values[4]=="-" and "" or values[4])) end
                    port:SetText(text(values[5] or "7777"));max_players:SetText(text(values[11]or'4'));settings_loaded=true
                end
            else
                restart:SetVisibility(1);restart:SetIsEnabled(false)
                status:SetText(text("Start the game using Start Multiplayer.cmd"))
            end
        end
        local sf=io.open(paths.runtime..'/steam.state','r')
        if sf then
            local values=split(sf:read(4096)or'');sf:close()
            if values[1]=='HSSTEAM1'and tonumber(values[7])and math.abs(os.time()-tonumber(values[7]))<4 then
                steam_role=values[4]or'-'
                steam_status:SetText(text(unhex(values[2]or'-')))
                if values[5]and values[5]~='-'and values[5]~=last_invite then
                    last_invite=values[5];switch_tab('steam');UI.set_open(true)
                end
            end
        end
        if tab=='steam'then
            local file=io.open(paths.runtime..(list_mode=='public'and'/steam.lobbies'or'/steam.friends'),'r')
            local rows={}
            if file then
                local raw=file:read(65536)or'';file:close()
                for line in raw:gmatch('[^\r\n]+')do
                    local v=split(line)
                    if list_mode=='public'and #v==7 then
                        rows[#rows+1]={id=v[1],action='steam_join',enabled=v[6]=='1',
                            label=clip(unhex(v[2]),38)..'  '..v[4]..'/'..(v[8]or'4')..(v[5]=='1'and' [password]'or'')..(v[6]~='1'and' [update needed]'or'')}
                    elseif list_mode=='friends'and #v==3 then
                        local invite=steam_role=='host'or steam_role=='join'
                        rows[#rows+1]={id=invite and v[1]or v[3],action=invite and'steam_invite'or'steam_join',
                            enabled=invite or v[3]~='-',label=(invite and'Invite: 'or v[3]~='-'and'Join: 'or'No lobby: ')..clip(unhex(v[2]),42)}
                    end
                end
            end
            local pages=math.max(1,math.ceil(#rows/3));page=math.min(page,pages)
            page_label:SetText(text('Page '..page..' / '..pages));list_targets={}
            for i,b in ipairs(list_buttons)do
                local row=rows[(page-1)*3+i]
                b:GetContent():SetText(text(row and row.label or(i==1 and'No available lobbies / friends'or'')))
                b:SetIsEnabled(row and row.enabled or false);list_targets[i]=row
            end
        end
    end
    local checked=automatic:IsChecked()
    if checked~=last_auto then last_auto=checked;request("auto_updates",checked) end
end
function UI.toggle() UI.set_open(not open) end
return UI
