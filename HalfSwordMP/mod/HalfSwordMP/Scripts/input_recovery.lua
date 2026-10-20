-- Retire stale UI focus without flushing keys or overriding native ragdolls.
local Recovery={}
local next_check=0
local function valid(o)return o and o:IsValid()end
function Recovery.reset()next_check=0 end
function Recovery.tick(pawn,clock,ready)
 if not valid(pawn)or clock<next_check then return end
 next_check=clock+.5
 local h=require('UEHelpers');local pc=h.GetPlayerController()
 if not valid(pc)or not valid(pc.Pawn)or pc.Pawn:GetFullName()~=pawn:GetFullName()then return end
 local world=pawn:GetWorld();local gs=h.GetGameplayStatics()
 if math.abs(gs:GetGlobalTimeDilation(world)-1)>.0001 then gs:SetGlobalTimeDilation(world,1)end
 if ready and gs:IsGamePaused(world)then gs:SetGamePaused(world,false)end
 if not ready or(_G.HSMPUI and _G.HSMPUI.is_open())then return end
 if _G.HSMPPause and valid(_G.HSMPPause.modal(world))then return end
 local outcome=_G.HSMPSession and _G.HSMPSession.round_outcome and _G.HSMPSession.round_outcome(pawn)
 if pawn.DED or pawn.Headless or pawn.Health<=0 or outcome=='dead'then return end
 if pawn.Player==false then pawn.Player=true end
 -- GameOnly(false) preserves held keys. Native latent UI can leave input in
 -- UI-only mode without setting ignore-input flags or showing a cursor.
 StaticFindObject('/Script/UMG.Default__WidgetBlueprintLibrary'):SetInputMode_GameOnly(pc,false)
 pc.bShowMouseCursor=false;pc:ResetIgnoreMoveInput();pc:ResetIgnoreLookInput()
 if pawn.bBlockInput then pawn.bBlockInput=false end
 if not pawn:IsActorTickEnabled()then pawn:SetActorTickEnabled(true)end
 pawn:EnableInput(pc)
end
return Recovery
