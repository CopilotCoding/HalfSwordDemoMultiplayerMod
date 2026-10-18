-- Follow measured owner travel through native CharacterMovement. No body edits.
local Movement={}
function Movement.capture(previous,key,position,clock)
    local velocity={0,0,0}
    if previous and previous.key==key then
        local dt=clock-previous.time
        if dt>=.001 and dt<=.25 then
            local speed=0
            for i=1,3 do velocity[i]=(position[i]-previous.position[i])/dt;speed=speed+velocity[i]^2 end
            -- A respawn/teleport is a new position, not extreme travel speed.
            if speed>25000000 then velocity={0,0,0}end
        end
    end
    return velocity,{key=key,position=position,time=clock}
end
function Movement.command(position,motion,clock,max_speed,current_velocity)
    if not motion or clock-motion.time<0 or clock-motion.time>.25 then return end
    local age=math.min(.05,clock-motion.time)
    local velocity=motion.velocity or{0,0,0}
    local dx=motion.root[1]+velocity[1]*age-position.X
    local dy=motion.root[2]+velocity[2]*age-position.Y
    local error=math.sqrt(dx*dx+dy*dy)
    if error<1.5 then dx,dy=0,0 end
    local current=current_velocity or{X=velocity[1],Y=velocity[2]}
    local vx=velocity[1]+dx*6+(velocity[1]-current.X)*1.5
    local vy=velocity[2]+dy*6+(velocity[2]-current.Y)*1.5
    local speed=math.sqrt(vx*vx+vy*vy)
    if speed<.5 then return nil,nil,error end
    return {X=vx/speed,Y=vy/speed,Z=0},math.min(1,speed/(math.max(1,max_speed)*1.5)),error
end
function Movement.drive(pawn,motion,clock)
    local direction,scale,error=Movement.command(pawn:K2_GetActorLocation(),motion,clock,pawn.CharacterMovement.MaxWalkSpeed)
    if direction then pawn:AddMovementInput(direction,scale,false)end
    return error
end
return Movement
