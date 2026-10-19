-- Bounded interpolation of cached numbers. No UObject or filesystem work here.
local Interpolation={}
function Interpolation.transform(a,b,t,out)
    out=out or {}
    for i=1,10 do out[i]=a[i]+(b[i]-a[i])*t end
    local dot=0;for i=4,7 do dot=dot+a[i]*b[i] end
    local sign=dot<0 and -1 or 1
    local length=0
    for i=4,7 do out[i]=a[i]+(sign*b[i]-a[i])*t;length=length+out[i]^2 end
    length=math.sqrt(length)
    if length>0 then for i=4,7 do out[i]=out[i]/length end end
    return out
end
function Interpolation.root(a,b,t,out)
    out=out or {}
    for i=1,3 do out[i]=a[i]+(b[i]-a[i])*t end
    for i=4,6 do out[i]=a[i]+((b[i]-a[i]+180)%360-180)*t end
    return out
end
function Interpolation.push(state,frame,now,key)
    if not state or state.key~=key then return {key=key,from=frame,to=frame,time=now,duration=1/30} end
    -- Start at the current displayed pose when packet timing is uneven.
    local current=Interpolation.sample(state,now)
    -- Cover the complete packet interval. Finishing halfway through it made
    -- a moving fighter alternate between a fast step and a stationary frame.
    local duration=math.max(.008,math.min(.05,now-state.time))
    state.from,state.to,state.time,state.duration=current,frame,now,duration
    state.sample_time,state.sample_result=nil,nil
    return state
end
function Interpolation.sample(state,now)
    if state.sample_time==now then return state.sample_result end
    local t=math.max(0,math.min(1,(now-state.time)/state.duration))
    if t>=1 then return state.to end
    local result={bones={},parts={},colliders={},collision_modes=state.to.collision_modes,
        root=Interpolation.root(state.from.root,state.to.root,t)}
    for _,kind in ipairs({"bones","parts","colliders"}) do
        for id,b in pairs(state.to[kind]) do
            local a=state.from[kind][id]
            result[kind][id]=a and Interpolation.transform(a,b,t) or b
        end
    end
    state.sample_time,state.sample_result=now,result
    return result
end
return Interpolation
