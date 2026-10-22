-- Free Mode uses the game's own rank buttons and loadout selection events.
-- Unlock their UI in memory without changing Gauntlet progression or saves.
local FreeMode={}
local helpers=require('UEHelpers')
local next_check=0
local function valid(object)return object~=nil and object:IsValid()end
function FreeMode.update()
    if os.clock()<next_check then return end
    next_check=os.clock()+.25
    local mode=helpers.GetGameModeBase()
    if not valid(mode)or mode['Gauntlet Mode Enabled']~=false then return end
    for _,menu in ipairs(FindAllOf('UI_MainMenuSNF_C')or{})do
        if valid(menu)and menu:IsInViewport()and menu['Can Start']then
            for rank=1,9 do
                local button=menu['Button_Rank_'..rank]
                if valid(button)then
                    if not button:GetIsEnabled()then button:SetIsEnabled(true)end
                    if button:GetVisibility()~=0 then button:SetVisibility(0)end
                end
            end
        end
    end
end
return FreeMode
