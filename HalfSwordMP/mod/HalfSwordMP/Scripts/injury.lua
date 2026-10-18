-- The attacking peer's native opponent computes combat injury. Its owner
-- receives those native results instead of independently guessing the outcome.
local Injury={}
Injury.fields={health='Health',consciousness='Consciousness',head='Head Health',
 chest='Body Upper Health',abdomen='Body Lower Health',arm_r='Arm_R Health',arm_l='Arm_L Health',
 leg_r='Leg_R Health',leg_l='Leg_L Health',neck='Neck Health'}
local applied
local function valid(o)return o~=nil and o:IsValid()end
function Injury.reset()applied=nil end
function Injury.capture(pawn,lines,owner,attacker,revision,outcome)
 if not valid(pawn)or not owner or not attacker then return end
 lines[#lines+1]='V|hit_owner_id|'..owner
 lines[#lines+1]='V|hit_attacker_id|'..attacker
 lines[#lines+1]='V|hit_revision|'..revision
 for key,field in pairs(Injury.fields)do
  local value=pawn[field];if type(value)=='boolean'then value=value and 1 or 0 end
  if outcome=='dead'and key=='health'then value=0
  elseif outcome=='unconscious'and key=='consciousness'then value=0 end
  if type(value)=='number'and value==value and math.abs(value)<=10000000 then
   lines[#lines+1]=string.format('V|hit_%s|%.5f',key,value)
  end
 end
end
function Injury.apply(pawn,state,owner,attacker)
 if not valid(pawn)or not state or state.hit_owner_id~=owner or state.hit_attacker_id~=attacker then return false end
 if not state.hit_revision or not state.hit_health or not state.hit_consciousness then return false end
 local name=pawn:GetFullName()
 if applied and applied.name==name and applied.owner==owner and applied.attacker==attacker then
  if state.hit_revision<=applied.revision then return false end
 end
 applied={name=name,owner=owner,attacker=attacker,revision=state.hit_revision}
 -- Transfer scalar injury once per fresh record. Native physics owns posture,
 -- muscle strength, pain and recovery; stamping those every tick locks limbs.
 -- An older remote result must never heal a newer local injury.
 for key,field in pairs(Injury.fields)do
  local value=state['hit_'..key]
  if type(value)=='number'and value==value and math.abs(value)<=10000000 and type(pawn[field])=='number' then
   if value<pawn[field]then pawn[field]=value end
  end
 end
 return true
end
return Injury
