-- Native pause UI stays usable while multiplayer keeps the arena simulating.
local Pause={}
local widgets,active,closing={},nil,false
local next_scan=0
local classes={'UI_Pause','UI_Pause_Eng'}
local settings_classes={'UI_AdvGraphics','UI_GoreSettings','UI_Controls','UI_AudioSettings','UI_DisplaySettings','UI_GameSettings'}
local settings,focused
local events={}
local modal_scan,modal_world=-100,nil
local function valid(o)return o~=nil and o:IsValid()end
local function owned()return _G.HSMPSession and _G.HSMPSession.owns_arena()end
local function retire(w)
 if not valid(w)then return end
 w:CancelLatentActions();w:StopAllAnimations();w.TickFrequency=1
 w:SetIsEnabled(false);w:SetRenderOpacity(0);w:RemoveFromParent()
end
function Pause.modal(world,force)
 world=world or require('UEHelpers').GetWorld()
 if not valid(world)then return end
 if not force and modal_world==world:GetFullName()and os.clock()<modal_scan then
  return valid(settings)and settings:IsInViewport()and settings or(valid(active)and active:IsInViewport()and active or nil)
 end
 modal_world=world:GetFullName();modal_scan=os.clock()+.1;settings=nil
 for _,class in ipairs(settings_classes)do
  for _,w in ipairs(FindAllOf(class..'_C')or{})do
   if valid(w)and w:GetWorld():GetFullName()==world:GetFullName()and w:IsInViewport()then settings=w;return w end
  end
 end
 return valid(active)and active:IsInViewport()and active or nil
end
function Pause.restore_focus()
 local h=require('UEHelpers');local target=Pause.modal(h.GetWorld(),true);local pc=h.GetPlayerController()
 if valid(target)and valid(pc)then
  pc.bShowMouseCursor=true
  StaticFindObject('/Script/UMG.Default__WidgetBlueprintLibrary'):SetInputMode_UIOnlyEx(pc,target,0,true)
  focused=target:GetFullName();return true
 end
 focused=nil;return false
end
function Pause.queue(event,widget)
 if #events<16 then events[#events+1]={event,widget}end
end
local function discover(world)
 for _,class in ipairs(classes)do
  for _,w in ipairs(FindAllOf(class..'_C')or{})do
   if valid(w)and w:GetWorld():GetFullName()==world:GetFullName()and w:IsInViewport()then
    widgets[w:GetFullName()]=w
   end
  end
 end
end
function Pause.close(restore)
 local h=require('UEHelpers');local world=h.GetWorld()
 if valid(world)then discover(world)end
 for _,w in pairs(widgets)do retire(w)end
 widgets,active,closing={},nil,false
 if restore~=false then
  if _G.HSMPUI and _G.HSMPUI.is_open()then _G.HSMPUI.set_open(true)
  elseif not Pause.restore_focus()then
   local pc=h.GetPlayerController();local p=_G.HSMPSession.capture_pawn()
   if valid(pc)then
    StaticFindObject('/Script/UMG.Default__WidgetBlueprintLibrary'):SetInputMode_GameOnly(pc,true)
    pc.bShowMouseCursor=false;pc:ResetIgnoreMoveInput();pc:ResetIgnoreLookInput()
    if valid(p)then p:EnableInput(pc)end
   end
  end
 end
end
function Pause.construct(widget)
 if not owned()then return end
 local front=Pause.modal(widget:GetWorld(),true)
 if valid(settings)then
  -- Escape belongs to the settings panel. Discard the pause layer that the
  -- unpaused arena created and use the native panel's Back action.
  retire(widget)
  local back=settings.BackButton
  if not valid(back)then back=settings.BackButton_1 end
  if valid(back)then back.OnClicked:Broadcast()end
  Pause.restore_focus();return
 end
 if _G.HSMPUI and _G.HSMPUI.is_open()then retire(widget);_G.HSMPUI.set_open(true);return end
 -- A second Escape creates another native widget because the shared arena
 -- cannot stay globally paused. Treat that second request as Resume.
 if valid(active)and active:IsInViewport()then closing=true end
 widgets[widget:GetFullName()]=widget;active=widget
end
function Pause.resume()if owned()then closing=true end end
function Pause.tick(world)
 if not owned()then return end
 local queued=events;events={}
 for _,event in ipairs(queued)do
  if valid(event[2])then if event[1]=='construct'then Pause.construct(event[2])else Pause.resume()end end
 end
 _G.HSMPPauseHooks=_G.HSMPPauseHooks or{}
 if os.clock()>=next_scan then
  next_scan=os.clock()+.25;discover(world)
  for _,class in ipairs(classes)do
   for event,callback in pairs({Construct=Pause.construct,
    BndEvt__Pause_UI_Button_0_K2Node_ComponentBoundEvent_0_OnButtonClickedEvent__DelegateSignature=Pause.resume})do
    local fn='/Game/UI/'..class..'.'..class..'_C:'..event
    if not _G.HSMPPauseHooks[fn]and valid(StaticFindObject(fn))then
     _G.HSMPPauseHooks[fn]={RegisterHook(fn,function(ctx)
      if _G.HSMPPause then _G.HSMPPause.queue(event=='Construct'and'construct'or'resume',ctx:get())end
     end)}
    end
   end
  end
 end
 if closing then Pause.close(true);return end
 local keep=valid(active)and active:IsInViewport()and active or nil
 for name,w in pairs(widgets)do
  if not valid(w)or not w:IsInViewport()then widgets[name]=nil
  elseif keep and name~=keep:GetFullName()then retire(w);widgets[name]=nil
  else keep=w end
 end
 active=keep
 local target=Pause.modal(world)
 if valid(target)and(not _G.HSMPUI or not _G.HSMPUI.is_open())then
  local pc=require('UEHelpers').GetPlayerController()
  if target:GetFullName()~=focused or(valid(pc)and not pc.bShowMouseCursor)then Pause.restore_focus()end
 end
end
function Pause.reset()widgets,active,closing={},nil,false;settings,focused=nil,nil;events={};next_scan=0;modal_scan=-100;modal_world=nil end
return Pause
