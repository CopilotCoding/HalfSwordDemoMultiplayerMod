local UI={}
_G.HSMPUICallbacks={} -- Disable the retired Deactivate route after a hot reload.
local helpers,paths=require("UEHelpers"),require("paths")
local widget,canvas,panel,status,address,port,automatic,router,world_name,restart
local open,sequence,ticks=true,0,0
local last_auto,settings_loaded=false,false
local previous_cursor
local companion_time=0
_G.HSMPUIActionQueue=_G.HSMPUIActionQueue or {}
_G.HSMPUIToggleRequests=_G.HSMPUIToggleRequests or 0
local function valid(o) return o~=nil and o:IsValid() end
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
local function request(action,value)
    if os.time()-companion_time>4 then
        if valid(status) then status:SetText(text("Launcher offline. Start the game with Start Multiplayer.cmd.")) end
        return false
    end
    sequence=sequence+1
    local host=string_value(address:GetText()):gsub("[|\r\n]","")
    local number=tonumber(string_value(port:GetText())) or 7777
    local f=io.open(paths.runtime.."/ui.command","w")
    if f then f:write("HSUI1|",os.time(),"-",sequence,"|",action,"|",number,"|",host=="" and "-" or host,"|",value and "1" or "0","\n");f:close() end
    return f~=nil
end
function UI.is_open() return open and valid(widget) end
function UI.set_open(value)
    local pc=helpers.GetPlayerController()
    local library=StaticFindObject("/Script/UMG.Default__WidgetBlueprintLibrary")
    if not valid(pc) or not valid(library) or not valid(widget) or not valid(panel) or not valid(address) then return end
    open=value
    if open and _G.HSMPPause then _G.HSMPPause.close(false)end
    panel:SetVisibility(open and 0 or 1)
    if open then
        previous_cursor=pc.bShowMouseCursor;pc.bShowMouseCursor=true
        library:SetInputMode_UIOnlyEx(pc,address,0,true)
    else
        local p=helpers.GetPlayer()
        local in_fight=valid(p) and p:GetClass():GetFName():ToString()=="Willie_BP_C"
        pc.bShowMouseCursor=not in_fight
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
    _G.HSMPUIClickCallbacks[receiver:GetFullName()]=action
    b.OnClicked:Add(receiver,FName("ToggleActive"))
    return b
end
function UI.destroy()
    -- Deactivation also happens during teardown; it must not act like a click.
    _G.HSMPUICallbacks={}
    _G.HSMPUIClickCallbacks={}
    _G.HSMPUIActionQueue={};_G.HSMPUIToggleRequests=0
    if valid(widget) then widget:RemoveFromParent() end
    if valid(router) then router:K2_DestroyActor() end
    widget,canvas,panel,status,address,port,automatic,router=nil,nil,nil,nil,nil,nil,nil,nil
    restart=nil
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
    place(canvas,border,22,70,640,600)
    panel=border
    local content=make("CanvasPanel");border:AddChild(content)
    place(content,label("HALF SWORD  /  MULTIPLAYER",24),24,20,590,36)
    status=place(content,label("Offline — choose Host or Join",17),24,66,590,48)
    status:SetAutoWrapText(true)
    place(content,label("Host IP (Join only)",16),24,125,380,28)
    place(content,label("UDP port",16),440,125,160,28)
    address=place(content,make("EditableTextBox"),24,156,390,42)
    address:SetForegroundColor({R=0,G=0,B=0,A=1})
    address:SetHintText(text("Only needed when joining"))
    port=place(content,make("EditableTextBox"),440,156,170,42);port:SetText(text("7777"))
    port:SetForegroundColor({R=0,G=0,B=0,A=1})
    button(content,"Host",24,222,180,function()
        if request("host") then status:SetText(text("Starting host...")) end
    end)
    button(content,"Join",226,222,180,function()
        if request("join") then status:SetText(text("Connecting...")) end
    end)
    button(content,"Disconnect",428,222,180,function() request("disconnect") end)
    button(content,"Enter multiplayer match",24,280,282,function()
        if request("enter_match") then status:SetText(text("Entering multiplayer with your selected fighter...")) end
    end)
    restart=button(content,"Restart round",326,280,282,function()
        if request("restart_round")then status:SetText(text("Starting the next multiplayer round..."))end
    end)
    restart:SetVisibility(1);restart:SetIsEnabled(false)
    place(content,label('Hold G to fill the native give-up meter. Release to cancel.',15),24,335,590,36)
    automatic=place(content,make("CheckBox"),24,394,28,30)
    automatic:SetIsChecked(last_auto)
    place(content,label("Automatic updates from the host",16),66,394,500,30)
    button(content,"Check for update",24,442,282,function() request("check_updates") end)
    button(content,"Apply update & restart",326,442,282,function() request("apply_update") end)
    place(content,label("Selected gear returns each round. E / Q: pick up enemy drops.\nHold G to give up, including while downed. F5: menu.",15),24,510,590,62)
    widget:AddToViewport(10000)
    UI.set_open(open)
end
function UI.tick()
    ticks=ticks+1
    local world=helpers.GetWorld()
    if not valid(world) then return end
    if world_name~=world:GetFullName() then UI.destroy();world_name=world:GetFullName() end
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
                restart:SetVisibility(values[9]=='host'and 0 or 1)
                restart:SetIsEnabled(values[10]=='1')
                status:SetText(text(values[2] or "Offline"))
                local enabled=values[3]=="1"
                if enabled~=last_auto then automatic:SetIsChecked(enabled);last_auto=enabled end
                if not settings_loaded then
                    if string_value(address:GetText())=="" then address:SetText(text(values[4]=="-" and "" or values[4])) end
                    port:SetText(text(values[5] or "7777"));settings_loaded=true
                end
            else
                restart:SetVisibility(1);restart:SetIsEnabled(false)
                status:SetText(text("Start the game using Start Multiplayer.cmd"))
            end
        end
    end
    local checked=automatic:IsChecked()
    if checked~=last_auto then last_auto=checked;request("auto_updates",checked) end
end
if not _G.HSMPUIKey then
    _G.HSMPUIKey=true
    RegisterKeyBind(Key.F5,function()
        _G.HSMPUIToggleRequests=(_G.HSMPUIToggleRequests or 0)+1
    end)
end
function UI.toggle() UI.set_open(not open) end
return UI
