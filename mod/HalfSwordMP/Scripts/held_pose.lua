-- Preserve the measured hand-to-weapon relation between snapshot endpoints.
local Held={}
local Math=dofile(require('paths').scripts..'/rig_math.lua')
local origin={0,0,0,0,0,0,1,1,1,1}
function Held.prepare(frame,equipment)
 frame.grips={};frame.grip_interpolate=Held.interpolate
 for _,weapon in ipairs(equipment.weapons or{})do
  local anchor=weapon.slot=='right'and'body|hand_r'or weapon.slot=='left'and'body|hand_l'
  local hand=anchor and frame.bones[anchor]
  if hand then for _,entry in ipairs(weapon.components or{})do
   local id=entry[3];local world=frame.colliders[id]
   if world then frame.grips[id]={anchor=anchor,transform=Math.transform(world,hand,origin)}end
  end end
 end
end
function Held.interpolate(result,from,to,t,lerp)
 result.grips={};result.grip_interpolate=Held.interpolate
 for id,b in pairs(to.grips or{})do
  local a=from.grips and from.grips[id];local hand=result.bones[b.anchor]
  if a and a.anchor==b.anchor and hand then
   local relative=lerp(a.transform,b.transform,t)
   result.grips[id]={anchor=b.anchor,transform=relative}
   result.colliders[id]=Math.transform(relative,origin,hand)
  end
 end
end
return Held
