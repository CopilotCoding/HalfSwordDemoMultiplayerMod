-- Per-opponent instances of the existing native fighter and pose adapters.
local Roster={}
local paths=require('paths')
local peers={}
local next_read=0
local state={slot=1,limit=2,primary=0,members={}}
local function valid(o)return o~=nil and o:IsValid()end
local function split(line)local row={};for value in line:gmatch('[^|\r\n]+')do row[#row+1]=value end;return row end
function Roster.read()
    if os.clock()<next_read then return state end
    next_read=os.clock()+.05
    local f=io.open(paths.runtime..'/roster.cfg','r');if not f then return state end
    local text=f:read(8193)or'';f:close();if #text>8192 then return state end
    local lines={};for line in text:gmatch('[^\r\n]+')do lines[#lines+1]=split(line)end
    local h=lines[1]
    if not h or h[1]~='HSPARTY1'or #h~=7 then
        if h and h[1]=='OFF'then state={slot=1,limit=2,primary=0,members={}}end
        return state
    end
    local slot,limit,primary,stamp=tonumber(h[2]),tonumber(h[3]),tonumber(h[4]),tonumber(h[6])
    if not slot or slot%1~=0 or not limit or limit%1~=0 or slot<1 or slot>limit or limit>16 or limit<2
        or not primary or primary%1~=0 or primary<0 or primary>limit or primary==slot
        or not stamp or math.abs(os.time()-stamp)>3 or #h[5]~=32 or not h[5]:match('^[a-f0-9]+$')then return state end
    local members={}
    for i=2,#lines do local row=lines[i];local id=tonumber(row[2])
        if #row~=3 or row[1]~='P'or not id or id%1~=0 or id<1 or id>limit or id==slot
            or members[id]or #row[3]~=32 or not row[3]:match('^[a-f0-9]+$')then return state end
        members[id]=row[3]
    end
    if primary~=0 and not members[primary]then return state end
    state={slot=slot,limit=limit,primary=primary,members=members,session=h[5],eliminated=h[7]=='1'}
    return state
end
function Roster.slot()return state.slot end
function Roster.primary()return state.primary end
function Roster.eliminated()return state.eliminated end
function Roster.spawn(native,origin)
    -- Slot two always uses the opposite native duel entrance, even when the
    -- lobby has spare slots. Extra slots subdivide the same native distance;
    -- capacity and the level's unused legacy spawn defaults cannot move it.
    local slot=state.session and state.slot or 2
    if slot==1 then return end
    local angle=math.pi
    if slot>2 then
        local count,start=2,3
        while slot>=start+count do start=start+count;count=count*2 end
        angle=(2*(slot-start)+1)*math.pi/count
    end
    local dx,dy=native.X-origin.X,native.Y-origin.Y
    local c,s=math.cos(angle),math.sin(angle)
    return origin.X+dx*c-dy*s,origin.Y+dx*s+dy*c,angle
end
function Roster.reset()
    for _,entry in pairs(peers)do entry.damage.stop();entry.fighter.destroy();entry.pose.destroy()end
    peers={}
end
function Roster.renderers(primary)
    local result={primary};for _,entry in pairs(peers)do result[#result+1]=entry.pose end;return result
end
function Roster.animate(pawn,clothing)
    for _,entry in pairs(peers)do
        entry.pose.animate()
        if clothing then clothing.update(entry.fighter.pawn(),true)end
    end
end
function Roster.update(pawn,primary,waiting,round)
    local current=Roster.read()
    for slot,entry in pairs(peers)do
        if not current.members[slot]or slot==current.primary or entry.token~=current.members[slot]then
            entry.damage.stop();entry.fighter.destroy();entry.pose.destroy();peers[slot]=nil
        end
    end
    for slot,token in pairs(current.members)do if slot~=current.primary then
        local entry=peers[slot]
        if not entry then
            entry={token=token,runtime=paths.runtime..'/opponents/'..slot}
            entry.fighter=dofile(paths.scripts..'/fighter.lua')
            entry.damage=assert(loadfile(paths.scripts..'/damage.lua'))({scripts=paths.scripts,runtime=entry.runtime})
            local callbacks={}
            callbacks.animate=function(renderer)
                entry.fighter.render(renderer)
                round.guard_pawn(entry.fighter.pawn())
            end
            callbacks.after_render=function(renderer)
                local _,mesh=renderer.rendered()
                if not valid(mesh)then entry.fighter.destroy();entry.damage.stop();return end
                entry.fighter.update(pawn,renderer,waiting,slot-1);entry.fighter.appearance(renderer)
                local avatar=_G.HSMPAvatar
                if avatar then
                    entry.damage.configure(pawn,entry.fighter.pawn(),avatar.owner(pawn),renderer.owner(),
                        avatar.contact_id,entry.fighter.component,entry.fighter.contact_frame)
                    entry.damage.tick()
                end
            end
            entry.pose=primary.new(callbacks);peers[slot]=entry
        end
        entry.pose.update(entry.runtime,pawn,primary.local_text)
    end end
end
function Roster.inspect(file)
    file:write('party_slot=',state.slot,'\nparty_limit=',state.limit,'\n')
    local count=0
    for slot,entry in pairs(peers)do
        if valid(entry.fighter.pawn())then count=count+1 end
        file:write('party_remote_slot=',slot,'\n');entry.fighter.inspect(file);entry.damage.inspect(file)
    end
    file:write('party_additional_native_fighters=',count,'\n')
end
return Roster
