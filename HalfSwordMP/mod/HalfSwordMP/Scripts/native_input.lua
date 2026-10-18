-- Capture native input on either peer; replay only on its remote controller.
local Input = {}
local helpers = require("UEHelpers")
local paths = require("paths")
local prefix = "/Game/Character/Blueprints/Willie_BP.Willie_BP_C:"
Input.axes = {
    "InpAxisEvt_Left Guard Axis_K2Node_InputAxisEvent_7",
    "InpAxisEvt_Right Guard Axis_K2Node_InputAxisEvent_6",
    "InpAxisEvt_Key Right_K2Node_InputAxisEvent_5",
    "InpAxisEvt_Key Forward_K2Node_InputAxisEvent_4",
    "InpAxisEvt_Left Arm Axis_K2Node_InputAxisEvent_3",
    "InpAxisEvt_Right Arm Axis_K2Node_InputAxisEvent_2",
    "InpAxisEvt_Look Up / Down Gamepad_K2Node_InputAxisEvent_1",
    "InpAxisEvt_Turn Right / Left Gamepad_K2Node_InputAxisEvent_0",
    "InpAxisEvt_Move Right / Left_K2Node_InputAxisEvent_19",
    "InpAxisEvt_Move Forward / Backward_K2Node_InputAxisEvent_14",
    "InpAxisEvt_Look Up / Down Mouse_K2Node_InputAxisEvent_17",
    "InpAxisEvt_Turn Right / Left Mouse_K2Node_InputAxisEvent_16",
}
Input.events = {
    {"InpActEvt_Grab Right_K2Node_InputActionEvent_19","E"},
    {"InpActEvt_Grab Right_K2Node_InputActionEvent_18","E"},
    {"InpActEvt_Grab Left_K2Node_InputActionEvent_17","Q"},
    {"InpActEvt_Grab Left_K2Node_InputActionEvent_16","Q"},
    {"InpActEvt_Swap Hands_K2Node_InputActionEvent_15","X"},
    {"InpActEvt_Jump_K2Node_InputActionEvent_14","SpaceBar"},
    {"InpActEvt_RightMouseButton_K2Node_InputKeyEvent_1","RightMouseButton"},
    {"InpActEvt_RightMouseButton_K2Node_InputKeyEvent_0","RightMouseButton"},
    {"InpActEvt_Crouch Hold_K2Node_InputActionEvent_10","LeftControl"},
    {"InpActEvt_Crouch Hold_K2Node_InputActionEvent_9","LeftControl"},
    {"InpActEvt_Thrust_K2Node_InputActionEvent_8","LeftAlt"},
    {"InpActEvt_Thrust_K2Node_InputActionEvent_7","LeftAlt"},
    {"InpActEvt_Crouch Key_K2Node_InputActionEvent_5","Gamepad_LeftThumbstick"},
    {"InpActEvt_Crouch Key_K2Node_InputActionEvent_4","Gamepad_LeftThumbstick"},
    {"InpActEvt_Run_K2Node_InputActionEvent_3","LeftShift"},
    {"InpActEvt_Run_K2Node_InputActionEvent_2","LeftShift"},
}
Input.keys = {"LeftMouseButton","RightMouseButton","MiddleMouseButton","LeftShift","LeftControl",
    "LeftAlt","SpaceBar","W","A","S","D","Q","E","R","F","G","X"}
local function valid(o) return o ~= nil and o:IsValid() end
local function same(a,b) return valid(a) and valid(b) and a:GetFullName()==b:GetFullName() end
local axes,events,sequence,event_sequence = {},{},0,0
for i=1,12 do axes[i]=0 end
local epoch = string.format("%08x%08x%08x%08x",os.time(),math.random(1,0x7fffffff),math.random(1,0x7fffffff),math.random(1,0x7fffffff))
local role,capture_pawn,guest_controller,buttons = "off",nil,nil,0
local menu_was_open=false
local installed=false
local function menu_open() return _G.HSMPUI and _G.HSMPUI.is_open() end

function Input.configure(new_role,pawn,controller,mask)
    if new_role=="active" and (role~="active" or not same(capture_pawn,pawn)) then
        epoch=string.format("%08x%08x%08x%08x",os.time(),math.random(1,0x7fffffff),math.random(1,0x7fffffff),math.random(1,0x7fffffff))
        sequence,event_sequence,events=0,0,{}
        for i=1,12 do axes[i]=0 end
    end
    role,capture_pawn,guest_controller,buttons = new_role,pawn,controller,mask or 0
end
function Input.on_tick(callback) Input.tick=callback end

function Input.install_hooks()
    if installed then return end
    -- Hooks survive development reloads; dispatch through a replaceable table.
    if not _G.HSMPInputHooks then _G.HSMPInputHooks={registered={},axis=nil,event=nil,key=nil} end
    local hooks = _G.HSMPInputHooks
    hooks.axis = function(context,index,value)
        if role ~= "active" or not same(context,capture_pawn) or menu_open() then return end
        if index >= 11 then axes[index] = math.max(-10000,math.min(10000,axes[index]+value))
        else axes[index] = math.max(-1,math.min(1,value)) end
    end
    hooks.event = function(context,index)
        if role ~= "active" or not same(context,capture_pawn) or menu_open() then return end
        event_sequence = event_sequence+1
        events[#events+1] = {event_sequence,index-1}
        if #events>64 then table.remove(events,1) end
    end
    hooks.tick = function(context,delta)
        if role=="active" and Input.tick then Input.tick(context,delta) end
    end
    local function register(name,callback)
        if hooks.registered[name] then return end
        if not valid(StaticFindObject(name)) then return end
        RegisterHook(name,callback)
        hooks.registered[name]=true
    end
    for i,name in ipairs(Input.axes) do
        register(prefix..name,function(context,value) if hooks.axis then hooks.axis(context:get(),i,value:get()) end end)
    end
    for i,event in ipairs(Input.events) do
        register(prefix..event[1],function(context) if hooks.event then hooks.event(context:get(),i) end end)
    end
    register(prefix.."ReceiveTick",function(context,delta) if hooks.tick then hooks.tick(context:get(),delta:get()) end end)
    -- Remote fighters retain AI controllers. Their axes/actions are replayed
    -- directly; intercepting every local PlayerController key query adds work
    -- and cannot provide input to an AI controller.
    hooks.key=nil
    installed=true
end

function Input.write()
    if role ~= "active" or not valid(capture_pawn) then return end
    local pc = helpers.GetPlayerController()
    if not valid(pc) then return end
    local mask,down = 0,{}
    for i,key in ipairs(Input.keys) do
        down[key]=pc:IsInputKeyDown({KeyName=FName(key)})
        if down[key] then mask=mask | (1 << (i-1)) end
    end
    -- Axis hooks already contain the game's resolved keyboard/gamepad values.
    -- Keep those channels separate, including analog guards. Held-key polling
    -- supplies action buttons only; it must not replace native axis samples.
    local blocked=menu_open()
    if blocked then
        mask=0
        for i=1,12 do axes[i]=0 end
        if not menu_was_open then
            for _,id in ipairs({0,2,6,8,10,12,14}) do
                event_sequence=event_sequence+1;events[#events+1]={event_sequence,id}
            end
        end
    end
    menu_was_open=blocked
    sequence=sequence+1
    local map=capture_pawn:GetWorld():GetFullName():gsub("^%S+ ","")
    local lines={"HSIN1|"..epoch.."|"..sequence.."|"..mask.."|"..map}
    local values={"A"}
    for i=1,12 do values[#values+1]=string.format("%.5f",axes[i]) end
    lines[#lines+1]=table.concat(values,"|")
    for _,event in ipairs(events) do lines[#lines+1]="E|"..event[1].."|"..event[2] end
    local r=pc:GetControlRotation()
    lines[#lines+1]=string.format("R|%.5f|%.5f|%.5f",r.Pitch,r.Yaw,r.Roll)
    lines[#lines+1]="END|"..sequence.."|"..#lines
    local file=io.open(paths.runtime.."/local.input","w")
    if file then file:write(table.concat(lines,"\n"),"\n"); file:close() end
    axes[11],axes[12]=0,0
end

function Input.read()
    local f=io.open(paths.runtime.."/remote.input","r");if not f then return end
    local text=f:read(8193);f:close()
    if #text>8192 or text:sub(-1)~="\n" then return end
    local rows={};for line in text:gmatch("[^\r\n]+") do
        local row={};for v in line:gmatch("[^|]+") do row[#row+1]=v end;rows[#rows+1]=row
    end
    local h,ending=rows[1],rows[#rows]
    if not h or #h~=5 or h[1]~="HSIN1" or not ending or ending[1]~="END" or ending[2]~=h[3]
        or tonumber(ending[3])~=#rows-1 or not valid(capture_pawn)
        or h[5]~=capture_pawn:GetWorld():GetFullName():gsub("^%S+ ","") then return end
    local value={epoch=h[2],seq=tonumber(h[3]),buttons=tonumber(h[4]),axes={},events={}}
    if #h[2]~=32 or not h[2]:match("^[a-f0-9]+$") or not value.seq or not value.buttons then return end
    for i=2,#rows-1 do
        local r=rows[i]
        if r[1]=="A" and #r==13 then
            for j=2,13 do local v=tonumber(r[j]);if not v or v~=v or math.abs(v)>(j>=12 and 10000 or 1) then return end;value.axes[j-1]=v end
        elseif r[1]=="E" and #r==3 then
            local seq,id=tonumber(r[2]),tonumber(r[3]);if not seq or not id or id%1~=0 or id<0 or id>=16 then return end
            value.events[#value.events+1]={seq,id}
        elseif r[1]=="R" and #r==4 then
            value.view={};for j=2,4 do local v=tonumber(r[j]);if not v or v~=v or math.abs(v)>3600 then return end;value.view[j-1]=v end
        else return end
    end
    if #value.axes~=12 then return end
    return value
end

function Input.apply_axis(pawn,index,value)
    assert(index>=1 and index<=#Input.axes,"Invalid input axis")
    pawn[Input.axes[index]](pawn,value)
end
function Input.apply_event(pawn,index)
    local entry=Input.events[index+1]
    assert(entry,"Invalid input action")
    pawn[entry[1]](pawn,{KeyName=FName(entry[2])})
end
return Input
