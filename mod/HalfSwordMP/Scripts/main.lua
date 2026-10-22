local UEHelpers = require("UEHelpers")
local paths = require("paths")
local Pose = require("pose")
local FreeMode = dofile(paths.scripts..'/free_mode.lua')
local pending = false
local last_pawn = ""
local renderer_failed = false
local renderer_retry_at,renderer_failures=0,0

local function log(message)
    print("[HalfSwordMP] " .. message .. "\n")
end
local function render_failed(err)
    renderer_failed=true;renderer_failures=renderer_failures+1
    renderer_retry_at=os.clock()+math.min(4,.25*2^math.min(renderer_failures-1,4))
    pcall(Pose.destroy)
    log('Pose renderer will retry: '..tostring(err))
end

local function valid(object)
    return object ~= nil and object:IsValid()
end

local function describe(object, file, inherited)
    if not valid(object) then return end
    file:write("\nOBJECT ", object:GetFullName(), "\n")
    local class = object:GetClass()
    while valid(class) do
        file:write("CLASS ", class:GetFullName(), "\n")
        class:ForEachProperty(function(property)
            file:write("  PROPERTY ", property:GetFName():ToString(), "\n")
        end)
        class:ForEachFunction(function(fn)
            file:write("  FUNCTION ", fn:GetFullName(), "\n")
        end)
        if inherited == false then break end
        class = class:GetSuperStruct()
    end
end

local function diagnose()
    local file = assert(io.open(paths.runtime .. "/discovery.txt", "w"))
    local ok, err = pcall(function()
        local controller = UEHelpers.GetPlayerController()
        describe(controller, file)
        describe(UEHelpers.GetPlayer(), file)
        describe(UEHelpers.GetWorld(), file)
        describe(UEHelpers.GetGameModeBase(), file)
        -- Menu widgets and level scripts help identify the game's spawn/input flow.
        for _, widget in ipairs(FindAllOf("UserWidget") or {}) do
            describe(widget, file, false)
        end
        for _, script in ipairs(FindAllOf("LevelScriptActor") or {}) do
            describe(script, file, false)
        end
        local pawn = UEHelpers.GetPlayer()
        if valid(pawn) then
            if pawn:GetClass():GetFName():ToString() == "Willie_BP_C" and valid(pawn.Mesh) then
                describe(pawn.Mesh, file)
                file:write("\nSKELETON\n")
                for i = 0, pawn.Mesh:GetNumBones() - 1 do
                    file:write(pawn.Mesh:GetBoneName(i):ToString(), "\n")
                end
            end
            file:write("\nPAWN LOCATION\n")
            local loc = pawn:K2_GetActorLocation()
            file:write(string.format("%.3f %.3f %.3f\n", loc.X, loc.Y, loc.Z))
        end
    end)
    file:close()
    if not ok then error(err) end
    log("Discovery saved to " .. paths.runtime .. "/discovery.txt")
end

-- Register keys on the startup Lua stack, never from the timer's hook stack.
-- The loader invokes input callbacks asynchronously while its timer executes
-- without that input mutex. Sharing the hook stack can corrupt a native call.
_G.HSMPUIToggleRequests=0
RegisterKeyBind(Key.F5, function()
    _G.HSMPUIToggleRequests=_G.HSMPUIToggleRequests+1
end)

RegisterKeyBind(Key.F8, function()
    _G.HSMPDiagnosticRequests=(_G.HSMPDiagnosticRequests or 0)+1
end)

local function toggle_preview()
    renderer_failed = false
    log("Local pose preview: " .. tostring(Pose.toggle_preview()))
end

RegisterKeyBind(Key.F9, function()
    _G.HSMPPreviewRequests=(_G.HSMPPreviewRequests or 0)+1
end)

local last_error = ""
local tick = 0
local profile_total,profile_max,profile_count=0,0,0
local draw_tick=0
local draw_total,draw_max,draw_count=0,0,0
local next_full_update=0
local rate_start,rate_count=os.clock(),0
-- Register one persistent game-thread timer. Repeated cross-thread
-- ExecuteInGameThread registry references can invalidate callbacks and stop
-- replication with UE4SS's "Ref was not function" error.
local function update()
    if pending then return end
    pending = true
        local started=os.clock()
        if _G.HSMPDevFrame then
            local dev_ok,dev_error=pcall(_G.HSMPDevFrame)
            if not dev_ok then _G.HSMPDevFrame=nil;log('Development frame: '..tostring(dev_error))end
        end
        if _G.HSMPSession and _G.HSMPSession.update_ui then
            local ui_ok,ui_error=pcall(_G.HSMPSession.update_ui)
            if not ui_ok and tostring(ui_error)~=last_error then last_error=tostring(ui_error);log('Native UI: '..last_error)end
        end
        local unlock_ok,unlock_error=pcall(FreeMode.update)
        if not unlock_ok and tostring(unlock_error)~=last_error then last_error=tostring(unlock_error);log('Free Mode unlock: '..last_error)end
        if renderer_failed and started>=renderer_retry_at then renderer_failed=false end
        if (_G.HSMPDiagnosticRequests or 0)>0 then
            _G.HSMPDiagnosticRequests=0
            local ok,err=pcall(diagnose);if not ok then log('Discovery error: '..tostring(err))end
        end
        if (_G.HSMPPreviewRequests or 0)%2==1 then toggle_preview()end
        _G.HSMPPreviewRequests=0
        draw_tick=draw_tick+1
        if started<next_full_update then
            local ok,err=xpcall(function()if not renderer_failed then Pose.animate() end end,debug.traceback)
            local elapsed=(os.clock()-started)*1000
            draw_total,draw_max,draw_count=draw_total+elapsed,math.max(draw_max,elapsed),draw_count+1
            if draw_count%120==0 then
                local f=io.open(paths.runtime.."/render-performance.txt","w")
                if f then f:write(string.format("draw_average_ms=%.3f\ndraw_max_ms=%.3f\ndraw_count=%d\n",draw_total/draw_count,draw_max,draw_count));f:close() end
            end
            if not ok then render_failed(err)end
            pending=false
            return
        end
        -- Advance a deadline rather than adding a whole interval after each
        -- late frame. This avoids turning a 30 Hz target into ~20-25 Hz.
        next_full_update=math.max(next_full_update+1/30,started+.001)
        rate_count=rate_count+1
        local ok, err = pcall(function()
            tick = tick + 1
            -- Local development commands; network payloads never write this file.
            if tick % 5 == 0 then
                local file = io.open(paths.runtime .. "/command.txt", "r")
                if file then
                    local command = file:read("*l")
                    file:close()
                    os.remove(paths.runtime .. "/command.txt")
                    if command == "preview" then toggle_preview()
                    elseif command == "discover" then diagnose()
                    elseif command == "reload_pose" then
                        Pose.destroy()
                        package.loaded["pose"] = nil
                        Pose = dofile(paths.scripts .. "/pose.lua")
                        renderer_failed = false
                        log("Pose adapter reloaded")
                    elseif command == "test_step" then
                        package.loaded["dev"] = nil
                        dofile(paths.scripts .. "/dev.lua").step(UEHelpers, paths, Pose)
                    end
                end
            end
            local pawn = UEHelpers.GetPlayer()
            if valid(pawn) and pawn:GetFullName() ~= last_pawn then
                last_pawn = pawn:GetFullName()
                renderer_failed = false
                log("Local pawn: " .. last_pawn)
            end
            local text = Pose.capture(pawn)
            Pose.write_local(paths.runtime, text)
            local source=_G.HSMPSession and _G.HSMPSession.capture_pawn() or pawn
            if not valid(source) then source=pawn end
            if not renderer_failed then
                local render_ok, render_error = xpcall(Pose.update,debug.traceback,paths.runtime,source,text)
                if not render_ok then
                    render_failed(render_error)
                else renderer_failures=0 end
            end
        end)
        pending = false
        local elapsed=(os.clock()-started)*1000
        profile_total,profile_max,profile_count=profile_total+elapsed,math.max(profile_max,elapsed),profile_count+1
        if profile_count%30==0 then
            local f=io.open(paths.runtime.."/performance.txt","w")
            local hz=(rate_count-1)/math.max(.001,started-rate_start)
            if f then f:write(string.format("adapter_average_ms=%.3f\nadapter_max_ms=%.3f\nnetwork_target_hz=30\nnetwork_capture_hz=%.2f\n",profile_total/profile_count,profile_max,hz));f:close() end
            rate_start,rate_count=started,1
        end
        if not ok and tostring(err) ~= last_error then
            last_error = tostring(err)
            log("Adapter error: " .. last_error)
        end
end
assert(type(LoopInGameThreadAfterFrames)=='function','HalfSwordMP requires its pinned UE4SS loader with game-thread timers')
_G.HSMPUpdate=update
_G.HSMPUpdateHandle=LoopInGameThreadAfterFrames(1,update)

log("0.12.0: Free Mode character unlock; configurable free-for-all over Steam or Direct IP. F8: discovery. F9: local pose preview.")
