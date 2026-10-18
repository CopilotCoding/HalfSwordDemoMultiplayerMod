-- Blood Niagara state only. Never copy UObject parameters or collision callbacks.
local Effects={}
local cache={}
local rendered={}
local inventory
local attempted={}
local function valid(o) return o~=nil and o:IsValid() end
local function path(o) return o:GetFullName():gsub("^%S+ ","") end
local function parameters(c)
    local store=c.OverrideParameters
    local entries,types,bytes={},{},{}
    store.SortedParameterOffsets:ForEach(function(_,r)
        local p=r:get()
        local n,t=p.Name:ToString(),p.TypeDefHandle.RegisteredTypeIndex
        entries[#entries+1]={name=n,type=t,offset=p.Offset}
        if n=="User.Spawn Rate" then types[t]="F"
        elseif n=="User.LoopCount" then types[t]="I"
        elseif n=="User.Hit Direction" then types[t]="V"
        elseif n=="User.Color" then types[t]="C" end
    end)
    store.ParameterData:ForEach(function(_,r) if #bytes<4096 then bytes[#bytes+1]=string.char(r:get()) end end)
    local data=table.concat(bytes)
    local result={}
    for _,p in ipairs(entries) do
        local kind=types[p.type]
        local count=kind=="C" and 4 or kind=="V" and 3 or 1
        if kind and #result<64 and #p.name<=64 and p.name:match("^[%w_ ./:%-]+$")
            and p.offset>=0 and p.offset+count*4<=#data then
            local values,okay={},true
            for i=1,count do
                local value=string.unpack(kind=="I" and "<i4" or "<f",data,p.offset+(i-1)*4+1)
                if value~=value or math.abs(value)>10000000 then okay=false end
                values[#values+1]=value
            end
            if okay then result[#result+1]={kind=kind,name=p.name,values=values} end
        end
    end
    return result
end

function Effects.capture(pawn,lines,packed)
    local now=require("UEHelpers").GetGameplayStatics():GetRealTimeSeconds(pawn:GetWorld())
    local seen,count={},0
    local key=path(pawn)
    if not inventory or inventory.pawn~=key or now-inventory.time>.2 then
        local actors={}
        -- The Blueprint's Spawned Blood array can contain cleared entries while
        -- live emitters remain. Parent ownership is the reliable association.
        for _,a in ipairs(FindAllOf("Blood_BP_PT_C") or {}) do
            if valid(a) and valid(a.Parent) and valid(a.Parent:GetOwner())
                and path(a.Parent:GetOwner())==key then actors[#actors+1]=a end
        end
        inventory={pawn=key,time=now,actors=actors}
    end
    for _,a in ipairs(inventory.actors) do
    local function capture()
        if count>=16 or not valid(a) then return end
        local c=a.Blood_Fountain_System
        if not valid(c) or not c:IsActive() then return end
        local asset=c:GetAsset()
        if not valid(asset) or not path(asset):match("^/Game/Effects/Blood/[%w_./:%-]+$") then return end
        local id=a:GetFName():ToString()
        if seen[id] then return end
        seen[id],count=true,count+1
        local t=c:K2_GetComponentToWorld()
        lines[#lines+1]="N|"..id.."|"..path(asset).."|"..packed(t)
        local entry=cache[id]
        if not entry or now-entry.time>.2 then entry={time=now,parameters=parameters(c)};cache[id]=entry end
        for _,p in ipairs(entry.parameters) do
            local values={"Q",id,p.kind,p.name}
            for _,v in ipairs(p.values) do values[#values+1]=p.kind=="I" and tostring(v) or string.format("%.6g",v) end
            lines[#lines+1]=table.concat(values,"|")
        end
    end
    capture()
    end
    for id in pairs(cache) do if not seen[id] then cache[id]=nil end end
end
function Effects.destroy() rendered={} end
function Effects.update(actor,pawn,lines,offset,identity,set_transform)
    local present={}
    for _,v in ipairs(lines) do
        if v[1]=="N" and #v==13 then
            local id,asset=v[2],StaticFindObject(v[3])
            -- A fresh guest may not have spawned blood locally yet. Load only
            -- blood assets from the demo's own content, once per missing path.
            if not valid(asset) and not attempted[v[3]] and v[3]:match("^/Game/Effects/Blood/[%w_./%-]+$")
                    and not v[3]:find("..",1,true) then
                attempted[v[3]]=true
                LoadAsset(v[3]:gsub("%.[^.]+$",""))
                asset=StaticFindObject(v[3])
            end
            if valid(asset) and asset:IsA("/Script/Niagara.NiagaraSystem") and v[3]:match("^/Game/Effects/Blood/") then
                present[id]=true
                local e=rendered[id]
                if e and (not valid(e.component) or e.asset~=v[3]) then
                    if valid(e.component) then e.component:K2_DestroyComponent(actor) end
                    rendered[id]=nil;e=nil
                end
                if not e then
                    local c=actor:AddComponentByClass(StaticFindObject("/Script/Niagara.NiagaraComponent"),false,identity(pawn.Mesh),true)
                    c:SetAutoActivate(false)
                    c:SetAutoDestroy(false)
                    c:SetAsset(asset,true)
                    actor:FinishAddComponent(c,false,identity(pawn.Mesh))
                    e={component=c,asset=v[3],expected={},fresh=true};rendered[id]=e
                end
                e.component:K2_SetWorldTransform(set_transform(identity(pawn.Mesh),v,4,offset),false,{},true)
            end
        elseif v[1]=="Q" then
            local e=rendered[v[2]]
            if e and present[v[2]] then
                local c,kind,name=e.component,v[3],FName(v[4])
                local values={};for i=5,#v do values[#values+1]=tonumber(v[i]) end
                local signature=table.concat(v,"|")
                if not e.expected[v[4]] or e.expected[v[4]].signature~=signature then
                    if kind=="F" then c:SetVariableFloat(name,values[1])
                    elseif kind=="I" then c:SetVariableInt(name,values[1])
                    elseif kind=="V" then c:SetVariableVec3(name,{X=values[1],Y=values[2],Z=values[3]})
                    elseif kind=="C" then c:SetVariableLinearColor(name,{R=values[1],G=values[2],B=values[3],A=values[4]}) end
                    e.expected[v[4]]={signature=signature,values=values}
                end
            end
        end
    end
    for id,e in pairs(rendered) do
        if not present[id] then
            if valid(e.component) then e.component:K2_DestroyComponent(actor) end
            rendered[id]=nil
        elseif e.fresh then e.component:Activate(true);e.fresh=false end
    end
end
function Effects.inspect(file)
    local count,values,error=0,0,0
    for _,e in pairs(rendered) do
        if valid(e.component) then
            count=count+1
            for _,p in ipairs(parameters(e.component)) do
                local expected=e.expected[p.name]
                if expected then
                    values=values+1
                    for i,v in ipairs(p.values) do error=math.max(error,math.abs(v-expected.values[i])) end
                end
            end
        end
    end
    file:write("blood_effects=",count,"\nblood_parameters=",values,"\nblood_parameter_error=",error,"\n")
end
return Effects
