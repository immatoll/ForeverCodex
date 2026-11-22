local _, ns = ...
local L = ns.L

-- Minimap button through LibDBIcon so minimap managers (FlareUI's drawer,
-- button collectors) pick it up like any other addon button.
local loader = CreateFrame("Frame")
loader:RegisterEvent("PLAYER_LOGIN")
loader:SetScript("OnEvent", function()
    local broker = LibStub("LibDataBroker-1.1", true)
    local icon = LibStub("LibDBIcon-1.0", true)
    if not (broker and icon) then return end

    ns.db.minimap = ns.db.minimap or { hide = false }

    local object = broker:NewDataObject("ForeverCompanion", {
        type = "launcher",
        text = L["Forever Companion"],
        icon = "Interface\\AddOns\\ForeverCompanion\\Media\\logo64",
        OnClick = function(_, button)
            -- left: the quick bar, shift + left: the session window, right: the settings
            if button == "RightButton" then ns.Settings.Toggle()
            elseif IsShiftKeyDown() then ns.HUD.Toggle()
            else ns.QuickBar.Toggle() end
        end,
        OnTooltipShow = function(tooltip)
            tooltip:AddLine(L["Forever Companion"], 1, 0.85, 0.4)
            tooltip:AddLine(" ")
            -- the quick openers: the click on the left (gold), what it opens on the right
            for _, e in ipairs({ { L["Click"], L["Quick bar"] }, { L["Shift + click"], L["Kills & Loot"] }, { L["Right-click"], L["Settings"] } }) do
                tooltip:AddDoubleLine(e[1], e[2], 1, 0.82, 0.2, 1, 1, 1)
            end
        end,
    })
    icon:Register("ForeverCompanion", object, ns.db.minimap)
end)
