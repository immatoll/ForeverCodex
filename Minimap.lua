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

    local object = broker:NewDataObject("ForeverCodex", {
        type = "launcher",
        text = L["Kills & Loot"],
        icon = "Interface\\AddOns\\ForeverCodex\\Media\\logo64",
        OnClick = function(_, button)
            if button == "RightButton" or IsShiftKeyDown() then ns.UI.Toggle() else ns.HUD.Toggle() end
        end,
        OnTooltipShow = function(tooltip)
            tooltip:AddLine(L["Kills & Loot"], 1, 0.85, 0.4)
            tooltip:AddLine(L["Click: session overlay, right-click: journal"], 0.8, 0.8, 0.8)
        end,
    })
    icon:Register("ForeverCodex", object, ns.db.minimap)
end)
