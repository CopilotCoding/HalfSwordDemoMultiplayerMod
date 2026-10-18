-- Keep native worn garments in the same visibility bounds as their fighter.
-- Copy-pose garments can retain standing bounds while ragdoll bones move away.
local Clothing={}
local scans={}
local function valid(o)return o~=nil and o:IsValid()end
function Clothing.reset()scans={}end
function Clothing.update(pawn)
 if not valid(pawn)or not valid(pawn.Mesh)then return end
 local key=pawn:GetFullName();local now=os.clock()
 if now<(scans[key]or 0)then return end;scans[key]=now+.25
 local body=pawn.Mesh:GetFullName()
 for _,r in ipairs(pawn:K2_GetComponentsByClass(StaticFindObject('/Script/Engine.SkinnedMeshComponent')))do
  local c=r:get();local asset=valid(c)and c:GetSkinnedAsset()or nil
  if valid(asset)then
   local path=asset:GetFullName():gsub('^%S+ ','')
   local worn=path:sub(1,22)=='/Game/Assets/Clothing/'or path:sub(1,19)=='/Game/Assets/Armor/'
   local parent=worn and c:GetAttachParent()or nil
   if valid(parent)and parent:GetFullName()==body and not c.bUseAttachParentBound then
    c.bUseAttachParentBound=true
    -- Ask the native renderer to refresh bounds; preserve the garment's pose,
    -- materials, wound masks, hidden bones and native visibility decisions.
    c:SetBoundsScale(c.BoundsScale)
   end
  end
 end
end
return Clothing
