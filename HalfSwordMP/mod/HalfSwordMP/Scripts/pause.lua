-- Native pause UI stays usable while multiplayer keeps the arena simulating.
local Pause={}
local widgets,active,closing={},nil,false
local next_scan=0
local classes={'UI_Pause','UI_Pause_Eng'}
local function valid(o)return o~=nil and o:IsValid()end
local function owned()return _G.HSMPSession and _G.HSMPSession.owns_arena()end
local function retire(w)
 if not valid(w)then return end
 w:CancelLatentActions();w:StopAllAnimations();w.TickFrequency=1
 w:SetIsEnabled(false);w:SetRenderOpacity(0);w:RemoveFromParent()
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
  else
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
 -- A second Escape creates another native widget because the shared arena
 -- cannot stay globally paused. Treat that second request as Resume.
 if valid(active)and active:IsInViewport()then closing=true end
 widgets[widget:GetFullName()]=widget;active=widget
end
function Pause.resume()if owned()then closing=true end end
function Pause.tick(world)
 if not owned()then return end
 _G.HSMPPauseHooks=_G.HSMPPauseHooks or{}
 if os.clock()>=next_scan then
  next_scan=os.clock()+.25;discover(world)
  for _,class in ipairs(classes)do
   for event,callback in pairs({Construct=Pause.construct,
    BndEvt__Pause_UI_Button_0_K2Node_ComponentBoundEvent_0_OnButtonClickedEvent__DelegateSignature=Pause.resume})do
    local fn='/Game/UI/'..class..'.'..class..'_C:'..event
    if not _G.HSMPPauseHooks[fn]and valid(StaticFindObject(fn))then
     _G.HSMPPauseHooks[fn]={RegisterHook(fn,function(ctx)
      if _G.HSMPPause then callback(ctx:get())end
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
end
function Pause.reset()widgets,active,closing={},nil,false;next_scan=0 end
return Pause
