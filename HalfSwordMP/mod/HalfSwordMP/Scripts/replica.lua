-- Native collision bodies follow their owner's snapshots; no second AI fight.
local Replica={}
local Math=dofile(require('paths').scripts..'/rig_math.lua')
local function valid(o)return o~=nil and o:IsValid()end
function Replica.create(pawn,equipment)
 local transform=pawn.Mesh:GetSocketTransform(FName('Root'),0)
 local c=pawn:AddComponentByClass(StaticFindObject('/Script/PhysicsControl.PhysicsControlComponent'),true,transform,true)
 pawn:FinishAddComponent(c,true,transform);c:SetComponentTickEnabled(true);c:Activate(true)
 local state={pawn=pawn,control=c,bones={},weapons={},equipment=equipment,tick=pawn:IsActorTickEnabled(),
  movement_tick=pawn.CharacterMovement:IsComponentTickEnabled(),transform=transform}
 if valid(pawn.CapsuleComponent)then
  state.capsule=pawn.CapsuleComponent;state.capsule_mode=state.capsule:GetCollisionEnabled()
  state.capsule:SetCollisionEnabled(0)
 end
 local data={MovementType=1,CollisionType=3,GravityMultiplier=0,PhysicsBlendWeight=1,
  bUseSkeletalAnimation=false,bUpdateKinematicFromSimulation=false}
 local asset=pawn.Mesh:GetSkeletalMeshAsset():GetPhysicsAsset()
 local bones={}
 local setups=asset.SkeletalBodySetups
 for i=1,#setups do bones[#bones+1]=setups[i].BoneName:ToString()end
 -- Finish the native array callback before entering another Unreal function.
 -- Reentrant UFunction calls inside UE4SS ForEach use its callback Lua stack.
 for _,text in ipairs(bones)do
  local bone=FName(text);local name=FName('HSMPReplica_'..text)
  c:CreateNamedBodyModifier(name,pawn.Mesh,bone,FName('HSMPReplicaBody'),data)
  c:SetBodyModifierUpdateKinematicFromSimulation(name,true)
  state.bones[#state.bones+1]={bone=text,name=name}
 end
 pawn:SetActorTickEnabled(false)
 pawn.CharacterMovement:StopMovementImmediately();pawn.CharacterMovement:SetComponentTickEnabled(false)
 return state
end
local function target(control,entry,t)
 local old=entry.target
 if old then local same=true;for i=1,10 do if old[i]~=t[i]then same=false;break end end;if same then return end end
 local rotation=Math.rotator(t)
 control:SetBodyModifierKinematicTarget(entry.name,{X=t[1],Y=t[2],Z=t[3]},rotation,true)
 entry.target=t
end
function Replica.clear_weapons(state)
 if not state or not valid(state.control)then return end
 for _,e in pairs(state.weapons)do state.control:DestroyBodyModifier(e.name)end
 state.weapons={}
end
function Replica.equipment(state,equipment)state.equipment=equipment end
function Replica.update(state,frame)
 if not state or not frame or not valid(state.pawn)then return end
 local p,c,r=state.pawn,state.control,frame.root
 for _,w in ipairs(state.equipment.weapons)do if valid(w)and w:IsActorTickEnabled()then w:SetActorTickEnabled(false)end end
 p:K2_SetActorLocationAndRotation({X=r[1],Y=r[2],Z=r[3]},{Pitch=r[4],Yaw=r[5],Roll=r[6]},false,{},true)
 for _,entry in ipairs(state.bones)do
  local t=frame.bones['body|'..entry.bone]
  if t then target(c,entry,t)end
 end
 for id,t in pairs(frame.colliders)do
  local component=state.equipment.by_geometry[id]
  if valid(component)then
   if component:IsA('/Script/Engine.MeshComponent')then
   local entry=state.weapons[id]
   if not entry or not valid(entry.component)or entry.component:GetFullName()~=component:GetFullName()then
    if entry then c:DestroyBodyModifier(entry.name)end
    local name=FName('HSMPReplicaWeapon_'..id)
    c:CreateNamedBodyModifier(name,component,FName('None'),FName('HSMPReplicaWeapons'),
     {MovementType=1,CollisionType=component:GetCollisionEnabled(),GravityMultiplier=0,PhysicsBlendWeight=1,bUseSkeletalAnimation=false})
    c:SetBodyModifierUpdateKinematicFromSimulation(name,true)
    entry={name=name,component=component};state.weapons[id]=entry
   end
   target(c,entry,t)
   local mode=frame.collision_modes and frame.collision_modes[id]or 3
   if entry.mode~=mode then c:SetBodyModifierCollisionType(entry.name,mode);entry.mode=mode end
   else
    -- Physics Control accepts mesh components. Native query boxes/spheres
    -- retain their collision bodies and follow the captured helper transform.
    local transform=state.transform
    transform.Translation.X,transform.Translation.Y,transform.Translation.Z=t[1],t[2],t[3]
    transform.Rotation.X,transform.Rotation.Y,transform.Rotation.Z,transform.Rotation.W=t[4],t[5],t[6],t[7]
    transform.Scale3D.X,transform.Scale3D.Y,transform.Scale3D.Z=t[8],t[9],t[10]
    component:K2_SetWorldTransform(transform,false,{},true)
    local mode=frame.collision_modes and frame.collision_modes[id]or 3
    if component:GetCollisionEnabled()~=mode then component:SetCollisionEnabled(mode)end
   end
  end
 end
 for id,component in pairs(state.equipment.by_geometry)do
  if valid(component)and not frame.colliders[id]then
   local entry=state.weapons[id]
   if entry then
    if entry.mode~=0 then c:SetBodyModifierCollisionType(entry.name,0);entry.mode=0 end
   elseif component:GetCollisionEnabled()~=0 then component:SetCollisionEnabled(0)end
  end
 end
end
function Replica.destroy(state)
 if not state or not valid(state.control)then return end
 for _,e in ipairs(state.bones)do state.control:DestroyBodyModifier(e.name)end
 for _,e in pairs(state.weapons)do state.control:DestroyBodyModifier(e.name)end
 state.control:K2_DestroyComponent(state.pawn)
 if valid(state.capsule)then state.capsule:SetCollisionEnabled(state.capsule_mode)end
 if valid(state.pawn)then state.pawn:SetActorTickEnabled(state.tick);state.pawn.CharacterMovement:SetComponentTickEnabled(state.movement_tick)end
end
return Replica
