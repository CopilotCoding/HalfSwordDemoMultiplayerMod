-- Describe and construct the demo's native equipment. No replacement combat math.
local Equipment={}
local Assets=dofile(require("paths").scripts.."/assets.lua")
local Parts=dofile(require("paths").scripts.."/weapon_parts.lua")
local Cosmetics=dofile(require('paths').scripts..'/cosmetics.lua')
local function valid(o)return o~=nil and o:IsValid()end
local function path(o)return o:GetFullName():gsub("^%S+ ","")end
local boolean={['Double Edged']=true,NoStab=true,Shield=true}
local properties={'Rigidity','Edge Sharpness','Tip Sharpness','Stab Rate','Mat Density','Weapon Length',
    'Wound Shape','Brush Scale','Draw Cut Rate','Dismemberment Level Sharp','Dismemberment Level Blunt','Double Edged','NoStab','Shield'}
local function allowed(s,kind)
    local prefix=kind=="weapon" and "/Game/Assets/Weapons/" or "/Game/Assets/Armor/Blueprints/"
    return type(s)=="string" and #s<=240 and s:sub(1,#prefix)==prefix and s:sub(-2)=="_C"
        and s:match("^[%w_./%-]+$") and not s:find("..",1,true)
end
local function native_class(s,kind)
    if not allowed(s,kind) then return nil end
    local c=StaticFindObject(s)
    if not valid(c) then LoadAsset(s:match("^(.+)%.[^%.]+$"));c=StaticFindObject(s) end
    if not valid(c) or not c:IsA("/Script/CoreUObject.Class") then return nil end
    local base=kind=="weapon" and "ModularWeaponBP_C" or "BP_Armor_Master_C"
    local parent=c
    while valid(parent) do
        if parent:GetFName():ToString()==base then return c end
        parent=parent:GetSuperStruct()
    end
end
local captured
local armor_config
function Equipment.capture(pawn,lines,geometry,part_id)
    local key,stamp=pawn:GetFullName(),os.time()
    local held={}
    for _,field in ipairs({'Weapon R','Weapon L'})do
        local w=pawn[field];held[#held+1]=valid(w)and w:GetFullName()or'-'
    end
    local hand_signature=table.concat(held,'|')
    if captured and captured.pawn==key and captured.time==stamp and captured.hands==hand_signature then
        for _,line in ipairs(captured.lines) do lines[#lines+1]=line end;return
    end
    local first=#lines+1
    lines[#lines+1]="GEAR|1"
    local seen_weapons={}
    for _,slot in ipairs({{"right","Weapon R"},{"left","Weapon L"}}) do
        local w=pawn[slot[2]]
        if valid(w) and not seen_weapons[w:GetFullName()]and allowed(path(w:GetClass()),"weapon") then
            seen_weapons[w:GetFullName()]=true
            lines[#lines+1]="W|"..slot[1].."|"..path(w:GetClass())
            Parts.capture(w,slot[1],lines)
            for _,key in ipairs(properties) do
                local value=w[key]
                if type(value)=='boolean' then value=value and 1 or 0 end
                if type(value)=='number' and value==value and math.abs(value)<=10000000 then
                    lines[#lines+1]=table.concat({'J',slot[1],key,tostring(value)},'|')
                end
            end
            for _,r in ipairs(w:K2_GetComponentsByClass(StaticFindObject("/Script/Engine.PrimitiveComponent"))) do
                local c=r:get();local id=valid(c) and geometry.id(c)
                local n=valid(c) and c:GetFName():ToString()
                if id and #n<=64 and n:match("^[%w_ %-]+$") then
                    lines[#lines+1]=table.concat({"I",slot[1],n,part_id(c) or "-",id},"|")
                end
            end
        end
    end
    local colors={};local ok,config=pcall(armor_config,pawn)
    if ok then for _,a in ipairs(config)do colors[a.slot]=a.colors end end
    pawn.ArmorSlots_1:ForEach(function(k,v)
        local class=v:get();local slot=k:get()
        if valid(class) and allowed(path(class),"armor") and slot>=0 and slot<32 then
            lines[#lines+1]="A|"..slot.."|"..path(class)
            if colors[slot]then
                local row={'DYE',slot};for _,c in ipairs(colors[slot])do for _,n in ipairs(c)do row[#row+1]=n end end
                lines[#lines+1]=table.concat(row,'|')
            end
        end
    end)
    captured={pawn=key,time=stamp,hands=hand_signature,lines={}}
    for i=first,#lines do captured.lines[#captured.lines+1]=lines[i] end
end
function Equipment.read(rows)
    local value={weapons={},armor={},colors={},signature=""};local weapons={};local signature,mapping,armor_signature={},{},{}
    for _,v in ipairs(rows) do
        if v[1]=="GEAR" and v[2]=="1" then value.present=true
        elseif v[1]=="W" and #v==3 then
            local w={slot=v[2],class=v[3],components={},state={}};weapons[v[2]]=w;value.weapons[#value.weapons+1]=w
            signature[#signature+1]=table.concat(v,"|")
        elseif v[1]=="I" and #v==5 and weapons[v[2]] then
            weapons[v[2]].components[#weapons[v[2]].components+1]={v[3],v[4],v[5]}
            mapping[#mapping+1]=table.concat(v,"|")
        elseif v[1]=='J' and #v==4 and weapons[v[2]] then weapons[v[2]].state[v[3]]=tonumber(v[4])
        elseif weapons[v[2]] and Parts.read(weapons[v[2]],v) then
            -- Native material tint/coat values can change during play. The
            -- appearance path copies them without rebuilding hand constraints.
            if v[1]~='Y'and v[1]~='O'then signature[#signature+1]=table.concat(v,'|')end
        elseif v[1]=="A" and #v==3 then
            value.armor[#value.armor+1]={tonumber(v[2]),v[3]};signature[#signature+1]=table.concat(v,"|")
            armor_signature[#armor_signature+1]=table.concat(v,"|")
        elseif v[1]=='DYE'and #v==14 then
            local colors={};for i=3,14,4 do colors[#colors+1]={tonumber(v[i]),tonumber(v[i+1]),tonumber(v[i+2]),tonumber(v[i+3])}end
            value.colors[tonumber(v[2])]=colors
        end
    end
    table.sort(signature);value.signature=table.concat(signature,"\n")
    table.sort(mapping);value.mapping_signature=table.concat(mapping,"\n")
    table.sort(armor_signature);value.armor_signature=table.concat(armor_signature,"\n")
    return value
end
local armor_field="Armor_84_A1BA4DD44FD262BCA53B9DACF03CDF04"
local slots_field="ArmorinSlots_31_702A9C5C40C7F4335C6B4687EC09936A"
local class_field="ArmorBPClass_2_0A22459840BF9E6989DFA4BA6CFED1D3"
local color_fields={"Color1_5_5527FC7C442DCF594A4DA5BA8D94351F","Color2_7_1FF790D94C8CD95FF2D76183E7102E1B","Color3_9_D8B5A08742A87F5492F8138A4F686141"}
local weapons_field='Weapons_83_06F076E247B54D0D9942B383323C1968'
local loadout_slots={'WeaponHandR_2_64D3388F445655CA2E9E60B639016D17','WeaponHandL_4_4BF5616F480598D39F54058D5181EB86',
 'WeaponSlotR1_6_140F311C4B659EE501761B8D99781B20','WeaponSlotR2_8_8B0CA70A4477398EB3B1E58EBB1AD2DC',
 'WeaponSlotL1_10_908E8A984A1C041B0CC6238D804CEB60','WeaponSlotL2_12_EF7AA9044E150C11545E349E5AD7C2E0',
 'WeaponBack_14_2CBE21CA47095EF150DD5791D72AC8C9'}
local live_slots={'Weapon R','Weapon L','Weapon Slot R 1','Weapon Slot R 2','Weapon Slot L 1','Weapon Slot L 2','Weapon Slot Back'}
armor_config=function(pawn)
    local result={}
    pawn["Load Equipment"][armor_field][slots_field]:ForEach(function(k,v)
        local a=v:get();local entry={[class_field]=a[class_field]}
        for _,field in ipairs(color_fields) do local c=a[field];entry[field]={R=c.R,G=c.G,B=c.B,A=c.A} end
        local colors={};for _,field in ipairs(color_fields)do local c=entry[field];colors[#colors+1]={c.R,c.G,c.B,c.A}end
        result[#result+1]={slot=k:get(),value=entry,colors=colors}
    end)
    return result
end
local function set_armor(pawn,entries,load)
    local config=pawn["Load Equipment"]
    local map=config[armor_field][slots_field];map:Empty()
    for _,a in ipairs(entries) do map:Add(a.slot,a.value) end
    pawn["Set Up Armor"](pawn,true,load==true,false,config)
end
function Equipment.save_loadout(pawn)
    local rows={}
    captured=nil -- A selected loadout snapshot must include current dyes immediately.
    Equipment.capture(pawn,rows,{id=function()return nil end},function()return nil end)
    local full={}
    local weapon_cosmetics={}
    for i,field in ipairs(loadout_slots)do
        local actor=pawn[live_slots[i]]
        if valid(actor)then
            full[field]=Parts.snapshot(actor['Str Weapon Parts']);full[field].class=path(actor:GetClass())
            weapon_cosmetics[live_slots[i]]=Cosmetics.capture(actor,true)
        else full[field]=Parts.snapshot(pawn['Load Equipment'][weapons_field][field])end
    end
    local signature={};for _,line in ipairs(rows)do signature[#signature+1]=line end;table.sort(signature)
    return {value=Equipment.read((function()
        local result={}
        for _,line in ipairs(rows)do
            local row={};for v in line:gmatch('[^|]+')do row[#row+1]=v end
            result[#result+1]=row
        end
        return result
    end)()),armor=armor_config(pawn),full=full,signature=table.concat(signature,'\n'),cosmetics=Cosmetics.capture(pawn),weapon_cosmetics=weapon_cosmetics}
end
function Equipment.restore_loadout(pawn,snapshot)
    local current=Equipment.save_loadout(pawn)
    -- Classes alone do not describe clothing colours, modular dyes or sidearms.
    -- Apply the saved native weapon structure before rebuilding the sheath slots.
    if snapshot.full then
        pawn['Event Clear Sheathed Weapon Slots'](pawn)
        local config=pawn['Load Equipment']
        for _,field in ipairs(loadout_slots)do Parts.restore_struct(config[weapons_field][field],snapshot.full[field])end
        pawn['Load Equipment']=config
        pawn['Event Add Sheathed Weapon'](pawn)
    end
    if current.signature~=snapshot.signature then Equipment.create_fighter(pawn,snapshot.value,{})end
    -- Preserve the selected native armor colors as well as its classes.
    local colors={};for _,a in ipairs(snapshot.armor)do colors[a.slot]=a.value end
    local armor={}
    for _,a in ipairs(snapshot.value.armor)do
        local value=colors[a[1]]
        if not value or not valid(value[class_field])or path(value[class_field])~=a[2]then
            value={[class_field]=native_class(a[2],'armor')}
            for _,field in ipairs(color_fields)do value[field]={R=1,G=1,B=1,A=1}end
        end
        armor[#armor+1]={slot=a[1],value=value}
    end
    set_armor(pawn,armor,true)
    Equipment.restore_cosmetics(pawn,snapshot)
end
function Equipment.restore_cosmetics(pawn,snapshot)
    Cosmetics.restore(pawn,snapshot.cosmetics)
    -- Native hand/sheath setup can randomize a construction dye while spawning.
    -- Keep the saved description aligned with the materials restored below,
    -- without rerunning setup or changing an existing hand constraint.
    for i,field in ipairs(loadout_slots)do
        local actor=pawn[live_slots[i]]
        if valid(actor)and snapshot.full and snapshot.full[field]then
            Parts.restore_struct(actor['Str Weapon Parts'],snapshot.full[field])
        end
    end
    for field,appearance in pairs(snapshot.weapon_cosmetics or{})do
        local actor=pawn[field];if valid(actor)then Cosmetics.restore(actor,appearance,true)end
    end
end
function Equipment.loadout_present(pawn,snapshot)
    local actual={}
    pawn.ArmorSlots_1:ForEach(function(k,v)local class=v:get();if valid(class)then actual[k:get()]=path(class)end end)
    for _,entry in ipairs(snapshot.value.armor)do if actual[entry[1]]~=entry[2]then return false end end
    local meshes=Cosmetics.capture(pawn)
    for asset in pairs(snapshot.cosmetics or{})do if not meshes[asset]then return false end end
    return true
end
function Equipment.selection_ready(pawn)
    -- A preview can permit Start before its asynchronous armour meshes exist.
    -- Compare the native selection to the worn slots before taking our snapshot.
    local worn={}
    pawn.ArmorSlots_1:ForEach(function(k,v)local c=v:get();if valid(c)then worn[k:get()]=path(c)end end)
    for _,entry in ipairs(armor_config(pawn))do
        local class=entry.value[class_field]
        if valid(class)and worn[entry.slot]~=path(class)then return false end
    end
    return true
end
function Equipment.restore_armor(pawn,snapshot)
    set_armor(pawn,snapshot.armor,true)
    Equipment.restore_cosmetics(pawn,snapshot)
end
-- Native hand setup owns construction, collision, grip and weapon damage.
function Equipment.pickup(pawn,description,hand)
    assert(hand=='right'or hand=='left','Invalid pickup hand')
    local class=native_class(description.class,'weapon');assert(valid(class),'Unavailable pickup weapon')
    local p=pawn.Mesh:GetSocketLocation(FName(hand=='right'and'hand_r'or'hand_l'))
    local template=pawn:GetWorld():SpawnActor(class,{X=p.X,Y=p.Y,Z=p.Z},{Pitch=0,Yaw=0,Roll=0})
    assert(valid(template),'Native pickup spawn failed')
    local ok,actor=pcall(function()
        local construction=Parts.apply(template,description.construction)
        local method=hand=='right'and'Set Up Right Hand Weapon'or'Set Up Left Hand Weapon'
        pawn[method](pawn,class,description.construction and nil or template,false,true,construction)
        local item=pawn[hand=='right'and'Weapon R'or'Weapon L']
        assert(valid(item),'Native pickup hand setup failed');return item
    end)
    if not ok or template:GetFullName()~=actor:GetFullName()then template:K2_DestroyActor()end
    if not ok then error(actor)end
    return actor
end
local function modifier_component(pawn)
    local t=pawn.Mesh:GetSocketTransform(FName("Root"),0)
    local c=pawn:AddComponentByClass(StaticFindObject("/Script/PhysicsControl.PhysicsControlComponent"),true,t,true)
    pawn:FinishAddComponent(c,true,t);c:SetComponentTickEnabled(true);c:Activate(true)
    return c
end
function Equipment.clear_hand(pawn,field,kept)
    local old=pawn[field]
    if not valid(old)then return end
    -- Native two-handed setup can alias the opposite hand to the same actor.
    -- Clearing an absent off-hand slot must not destroy the new main weapon.
    for _,actor in pairs(kept or{})do
        if valid(actor)and actor:GetFullName()==old:GetFullName()then return end
    end
    old:K2_DestroyActor();pawn[field]=nil
end
function Equipment.create_fighter(pawn,value,rows,keep_armor)
    assert(value and value.present,"Native fighter equipment description missing")
    local state={pawn=pawn,signature=value.signature,armor_signature=value.armor_signature,weapons={},weapon_by_slot={},properties={},components={},by_part={},by_geometry={},bodies={}}
    local armor={}
    for _,a in ipairs(value.armor) do
        local c=native_class(a[2],"armor");assert(valid(c),"Unavailable native armor class: "..a[2])
        local entry={[class_field]=c}
        for i,field in ipairs(color_fields)do
            local color=value.colors and value.colors[a[1]]and value.colors[a[1]][i]or{1,1,1,1}
            entry[field]={R=color[1],G=color[2],B=color[3],A=color[4]}
        end
        armor[#armor+1]={slot=a[1],value=entry}
    end
    if not keep_armor then
        pawn['Use External Armor Slots']=false
        print('[HalfSwordMP] Native equipment: armor\n')
        set_armor(pawn,armor,true)
    end
    local wanted={};for _,w in ipairs(value.weapons) do wanted[w.slot]=w end
    for _,slot in ipairs({{'right','Weapon R','Set Up Right Hand Weapon','hand_r'},
                             {'left','Weapon L','Set Up Left Hand Weapon','hand_l'}}) do
        local w=wanted[slot[1]]
        if w then
            print('[HalfSwordMP] Native equipment: '..slot[1]..' weapon template\n')
            local class=native_class(w.class,'weapon');assert(valid(class),'Unavailable native weapon class: '..w.class)
            local p=pawn.Mesh:GetSocketLocation(FName(slot[4]))
            local template=pawn:GetWorld():SpawnActor(class,{X=p.X,Y=p.Y,Z=p.Z},{Pitch=0,Yaw=0,Roll=0})
            assert(valid(template),'Native weapon template failed')
            -- The native save-load path builds modules, materials and hand
            -- constraints from the owner's saved weapon construction.
            local ok,err=pcall(function()
                local parts=Parts.apply(template,w.construction)
                local existing;if not w.construction then existing=template end
                pawn[slot[3]](pawn,class,existing,false,true,parts)
            end)
            print('[HalfSwordMP] Native equipment: hand setup returned\n')
            if not ok then template:K2_DestroyActor();error(err) end
            local actor=pawn[slot[2]]
            if not valid(actor) or actor:GetFullName()~=template:GetFullName() then template:K2_DestroyActor() end
            assert(valid(actor),'Native hand setup did not produce a weapon')
            state.weapons[#state.weapons+1]=actor;state.weapon_by_slot[w.slot]=actor
            actor['Parent Actor']=pawn;actor.Team=pawn['Team Int']
            for _,r in ipairs(actor:K2_GetComponentsByClass(StaticFindObject('/Script/Engine.PrimitiveComponent'))) do
                local c=r:get()
                state.bodies[#state.bodies+1]=c
            end
        else
            Equipment.clear_hand(pawn,slot[2],state.weapon_by_slot)
        end
    end
    Equipment.bind(state,value,rows)
    return state
end
function Equipment.bind(state,value,rows)
    if not state or state.mapping_signature==value.mapping_signature then return end
    -- Capture IDs describe packet layout, not a change of native equipment.
    -- Refresh lookups without destroying weapons, constraints or worn armor.
    state.components,state.by_part,state.by_geometry={},{},{}
    local geometry={};for _,r in ipairs(rows or{})do if r[1]=='G'then geometry[r[2]]=r end end
    for _,w in ipairs(value.weapons)do
        local actor=state.weapon_by_slot[w.slot]
        if valid(actor)then
            local components={}
            for _,r in ipairs(actor:K2_GetComponentsByClass(StaticFindObject('/Script/Engine.PrimitiveComponent')))do
                local c=r:get();components[c:GetFName():ToString()]=c
            end
            for _,d in ipairs(w.components)do
                local c=components[d[1]];local g=geometry[d[3]]
                if valid(c)then
                    state.components[#state.components+1]={component=c,part=d[2]}
                    state.by_part[d[2]]=c;state.by_geometry[d[3]]=c
                    if g and c:IsA('/Script/Engine.StaticMeshComponent')and g[3]=='mesh'then
                        local mesh=Assets.mesh(g[4],false)
                        if valid(mesh)and(not valid(c.StaticMesh)or path(c.StaticMesh)~=path(mesh))then c:SetStaticMesh(mesh)end
                        c:SetWorldScale3D({X=tonumber(g[12]),Y=tonumber(g[13]),Z=tonumber(g[14])})
                    end
                    if g and g[20]~='-'then
                        local material=StaticFindObject(g[20])
                        if valid(material)and material:IsA('/Script/PhysicsCore.PhysicalMaterial')then c:SetPhysMaterialOverride(material)end
                    end
                end
            end
        end
    end
    state.mapping_signature=value.mapping_signature
end
function Equipment.show_fighter(state,rows)
    if not state then return end
    local visual={}
    for _,r in ipairs(rows or{})do if r[1]=='C'then visual[r[2]]=r[4]end end
    for _,w in ipairs(state.weapons)do if valid(w)and w.bHidden then w:SetActorHiddenInGame(false)end end
    for _,e in ipairs(state.components)do
        local c=e.component
        if valid(c)and c:IsA('/Script/Engine.StaticMeshComponent')then
            local mesh=c.StaticMesh
            -- An owner fallback ID can also name an invisible collision helper.
            -- Show only components actually present in the owner's appearance.
            local show=valid(mesh)and visual[e.part]==path(mesh)
            if c.bOnlyOwnerSee then c:SetOnlyOwnerSee(false)end
            if c.bOwnerNoSee then c:SetOwnerNoSee(false)end
            if c:IsVisible()~=show then c:SetVisibility(show,false)end
            if c.bHiddenInGame==show then c:SetHiddenInGame(not show,false)end
        end
    end
end
function Equipment.attached(state,pawn,value)
    for _,w in ipairs(value.weapons)do
        local actor=state.weapon_by_slot[w.slot]
        local held=pawn[w.slot=='right'and'Weapon R'or'Weapon L']
        if not valid(actor)or not valid(held)or actor:GetFullName()~=held:GetFullName()then return false end
    end
    return true
end
function Equipment.create(pawn,value)
    assert(value and value.present,"Native equipment description missing")
    local state={pawn=pawn,signature=value.signature,weapons={},weapon_by_slot={},properties={},components={},by_part={},geometry={},modifiers={},original_armor=armor_config(pawn),
        original_right=pawn['Weapon R'],original_left=pawn['Weapon L']}
    local ok,err=pcall(function()
    local armor={}
    for _,a in ipairs(value.armor) do
        local c=native_class(a[2],"armor");assert(valid(c),"Unavailable native armor class: "..a[2])
        local entry={[class_field]=c}
        for _,field in ipairs(color_fields) do entry[field]={R=1,G=1,B=1,A=1} end
        armor[#armor+1]={slot=a[1],value=entry}
    end
    -- Run native armor setup before creating any physics body modifiers.
    set_armor(pawn,armor)
    for _,w in ipairs(value.weapons) do
        local class=native_class(w.class,"weapon");assert(valid(class),"Unavailable native weapon class: "..w.class)
        local actor=pawn:GetWorld():SpawnActor(class,{X=-10000,Y=-10000,Z=300},{Pitch=0,Yaw=0,Roll=0})
        assert(valid(actor),"Native weapon spawn failed")
        state.weapons[#state.weapons+1]=actor
        state.weapon_by_slot[w.slot]=actor
        actor["Parent Actor"]=pawn;actor.Team=pawn["Team Int"]
        actor:SetActorTickEnabled(false);actor:SetActorHiddenInGame(true)
        local components={}
        for _,r in ipairs(actor:K2_GetComponentsByClass(StaticFindObject("/Script/Engine.PrimitiveComponent"))) do
            local c=r:get();local n=c:GetFName():ToString()
            components[n]=c;c:SetCollisionEnabled(0)
        end
        for _,description in ipairs(w.components) do
            local c=components[description[1]]
            if valid(c) then
                local e={component=c,id=description[3],part=description[2],name=FName("HSMPWeapon_"..(#state.components+1)),actor=actor}
                state.components[#state.components+1]=e;state.geometry[e.id]=true;state.by_part[e.part]=c
                -- Only the real attacker's PC detects body hits. These native
                -- weapon bodies still collide with local weapons for parries.
                c:SetCollisionResponseToChannel(16,0)
            end
        end
    end
    state.control=modifier_component(pawn)
    pawn['Weapon R']=state.weapon_by_slot.right
    pawn['Weapon L']=state.weapon_by_slot.left
    end)
    if not ok then pcall(Equipment.destroy,state);error(err) end
    return state
end
function Equipment.sync(state,value)
    if not state or not value then return end
    for _,description in ipairs(value.weapons) do
        local actor=state.weapon_by_slot[description.slot]
        if valid(actor) then
            for _,key in ipairs(properties) do
                local value=description.state[key];local id=description.slot..key
                if value~=nil and state.properties[id]~=value then
                    if key=='Dismemberment Level Sharp' or key=='Dismemberment Level Blunt' then value=math.floor(value) end
                    actor[key]=boolean[key] and value==1 or (not boolean[key] and value)
                    state.properties[id]=value
                end
            end
        end
    end
end
function Equipment.draw(state,transforms,rows,template)
    if not state then return end
    local modes,geometry={},{}
    for _,v in ipairs(rows or {}) do if v[1]=="G" then modes[v[2]]=tonumber(v[21]);geometry[v[2]]=v end end
    local mathlib=StaticFindObject("/Script/Engine.Default__KismetMathLibrary")
    for _,e in ipairs(state.components) do
        local c=e.component;local t=transforms[e.id]
        if valid(c) then
            if t and modes[e.id] then
                e.actor:SetActorHiddenInGame(false)
                c:SetVisibility(e.part~="-",false);c:SetHiddenInGame(e.part=="-",false)
                if not e.started then
                    local g=geometry[e.id]
                    if c:IsA("/Script/Engine.StaticMeshComponent") and g[3]=="mesh" then
                        local mesh=Assets.mesh(g[4],false)
                        if valid(mesh) then c:SetStaticMesh(mesh) end
                    elseif c:IsA("/Script/Engine.BoxComponent") and g[3]=="box" then
                        c:SetBoxExtent({X=tonumber(g[15]),Y=tonumber(g[16]),Z=tonumber(g[17])},false)
                    elseif c:IsA("/Script/Engine.SphereComponent") and g[3]=="sphere" then c:SetSphereRadius(tonumber(g[15]),false)
                    elseif c:IsA("/Script/Engine.CapsuleComponent") and g[3]=="capsule" then c:SetCapsuleSize(tonumber(g[15]),tonumber(g[16]),false) end
                    local material=g[20]~='-' and StaticFindObject(g[20]) or nil
                    if valid(material) and material:IsA('/Script/PhysicsCore.PhysicalMaterial') then c:SetPhysMaterialOverride(material) end
                    template.Translation.X,template.Translation.Y,template.Translation.Z=t[1],t[2],t[3]
                    template.Rotation.X,template.Rotation.Y,template.Rotation.Z,template.Rotation.W=t[4],t[5],t[6],t[7]
                    template.Scale3D.X,template.Scale3D.Y,template.Scale3D.Z=t[8],t[9],t[10]
                    c:K2_SetWorldTransform(template,false,{},true)
                    e.modifier=c:IsA("/Script/Engine.MeshComponent")
                    if e.modifier then
                        state.control:CreateNamedBodyModifier(e.name,c,FName("None"),FName("HSMPWeapons"),
                            {MovementType=1,CollisionType=modes[e.id],GravityMultiplier=0,PhysicsBlendWeight=1,bUseSkeletalAnimation=false})
                        state.control:SetBodyModifierUpdateKinematicFromSimulation(e.name,true)
                    end
                    e.started=true
                end
                if e.modifier then
                    local rotation=mathlib:Quat_Rotator({X=t[4],Y=t[5],Z=t[6],W=t[7]})
                    state.control:SetBodyModifierKinematicTarget(e.name,{X=t[1],Y=t[2],Z=t[3]},rotation,true)
                    state.control:SetBodyModifierCollisionType(e.name,modes[e.id])
                else
                    template.Translation.X,template.Translation.Y,template.Translation.Z=t[1],t[2],t[3]
                    template.Rotation.X,template.Rotation.Y,template.Rotation.Z,template.Rotation.W=t[4],t[5],t[6],t[7]
                    template.Scale3D.X,template.Scale3D.Y,template.Scale3D.Z=t[8],t[9],t[10]
                    c:K2_SetWorldTransform(template,false,{},false);c:SetCollisionEnabled(modes[e.id])
                end
            elseif e.started then
                if e.modifier then state.control:SetBodyModifierCollisionType(e.name,0) else c:SetCollisionEnabled(0) end
            end
        end
    end
end
function Equipment.destroy(state)
    if not state then return end
    if valid(state.pawn) then
        state.pawn['Weapon R']=valid(state.original_right) and state.original_right or nil
        state.pawn['Weapon L']=valid(state.original_left) and state.original_left or nil
    end
    if valid(state.control) then
        for _,e in ipairs(state.components) do if e.modifier then state.control:DestroyBodyModifier(e.name) end end
        state.control:K2_DestroyComponent(state.pawn)
    end
    for _,w in ipairs(state.weapons) do if valid(w) then w:K2_DestroyActor() end end
    if valid(state.pawn) then set_armor(state.pawn,state.original_armor) end
end
return Equipment
