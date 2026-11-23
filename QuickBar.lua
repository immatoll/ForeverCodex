local ADDON, ns = ...
local L = ns.L
local W = ns.W
local C = W.C

-- The quick bar: a small bar of buttons, one for each window of the addon, that the player can put wherever they like. A click on the
-- minimap button shows or hides it. The round logo at its start (it can hide itself while the mouse is away) moves it (drag) and turns it between a row and a column (right-click).

local Q = {}
ns.QuickBar = Q

local BTN, PAD, GAP = 34, 5, 5
local HANDLE = 58 -- the round logo: bigger than the bar, it stands over its corner; drag it to move the bar, right-click it to turn it
local HANDLE_ROOM = 38 -- how much of the bar's length it takes

local function Windows()
    return {
        { "hud", L["Kills & Loot"], function() if ns.HUD then ns.HUD.Toggle() end end },
        { "map", L["Loot map"], function() if ns.MapMain then ns.MapMain.Toggle() end end },
        { "journal", L["Journal"], function() if ns.UI then ns.UI.Toggle() end end },
        { "ah", L["Auction house"], function() if ns.AuctionWindow then ns.AuctionWindow.Toggle() end end },
        { "bags", L["Bags"], function() if ns.Manager then ns.Manager.Toggle() end end },
        { "recipes", L["Recipes"], function() if ns.ItemInfo then ns.ItemInfo.Toggle() end end },
        { "account", L["Account"], function() if ns.AccountWindow then ns.AccountWindow.Toggle() end end },
        { "settings", L["Settings"], function() if ns.Settings then ns.Settings.Toggle() end end },
    }
end
local FALLBACK = { journal = W.ICON.journal, hud = W.ICON.session, map = W.ICON.map, account = W.ICON.account, ah = W.ICON.coin,
    settings = W.ICON.settings, bags = "Interface\\Icons\\INV_Misc_Bag_10", recipes = "Interface\\Icons\\INV_Misc_Book_09" }

local bar, buttons, handle
local DELTA = HANDLE_ROOM + GAP - PAD -- how much longer the bar is with the logo
local ext = 0 -- how far the logo is out: 0 (not there) to DELTA (there); it follows the mouse smoothly
local base -- the place of the bar without the logo: its upper left corner (the bar grows at its start, to the left or upwards, so that the
           -- buttons stay where they are)

local function Saved()
    ns.db.quickBar = ns.db.quickBar or {}
    return ns.db.quickBar
end

-- the place of the bar without the logo, from where it is now
local function Capture()
    local left, top = bar:GetLeft(), bar:GetTop()
    if not (left and top) then return end
    if Saved().vertical then top = top - ext else left = left + ext end
    base = { left = left, top = top }
end

local function SavePosition()
    if not (ns.db and bar) then return end
    Capture()
    if base then Saved().pos = { "TOPLEFT", "BOTTOMLEFT", base.left, base.top } end
end

-- the width of the bar across its length (one row / column of buttons, or two)
local function Short()
    local lanes = Saved().two and 2 or 1
    return PAD * 2 + lanes * BTN + (lanes - 1) * GAP
end

local function Layout()
    local vertical, two = Saved().vertical, Saved().two
    local n = #buttons
    local lanes = two and 2 or 1 -- one row / column of buttons, or two
    local per = math.ceil(n / lanes)
    local start = PAD + ext
    local long = start + per * BTN + (per - 1) * GAP + PAD
    local short = PAD * 2 + lanes * BTN + (lanes - 1) * GAP
    bar:SetSize(vertical and short or long, vertical and long or short)
    for i, b in ipairs(buttons) do
        b:ClearAllPoints()
        local along = start + ((i - 1) % per) * (BTN + GAP)
        local across = PAD + math.floor((i - 1) / per) * (BTN + GAP)
        if vertical then b:SetPoint("TOPLEFT", bar, "TOPLEFT", across, -along) else b:SetPoint("TOPLEFT", bar, "TOPLEFT", along, -across) end
    end
    handle:SetShown(ext > 0.5)
    handle:SetAlpha(ext / DELTA)
    handle:ClearAllPoints()
    -- Centred on the bar's short side, standing out at the start. While the bar grows or shrinks the logo stays where it is (it only fades):
    -- it is then held at the place it has with the bar full grown; with the bar full (or being moved) it is simply the bar's.
    if base and not bar.moving and ext < DELTA - 0.01 then
        if vertical then
            handle:SetPoint("TOP", UIParent, "BOTTOMLEFT", base.left + short / 2, base.top + DELTA + 14)
        else
            handle:SetPoint("LEFT", UIParent, "BOTTOMLEFT", base.left - DELTA - 14, base.top - short / 2)
        end
    elseif vertical then
        handle:SetPoint("TOP", bar, "TOP", 0, 14)
    else
        handle:SetPoint("LEFT", bar, "LEFT", -14, 0)
    end
end

local function SetExt(v)
    ext = v
    Layout()
    if base and not bar.moving then
        bar:ClearAllPoints()
        if Saved().vertical then
            bar:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", base.left, base.top + ext)
        else
            bar:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", base.left - ext, base.top)
        end
    end
end

-- A change of the shape (turned between a row and a column, one or two rows) is made around the logo: its centre stays where it is and the
-- bar changes round it. (The bar's own place is kept as that of its upper left corner without the logo, so the centre of the logo is
-- worked out from it, and back.)
local function Reshape(change)
    if not bar.moving then Capture() end
    if not base then change(); Layout(); return end
    local cx, cy
    local short = Short()
    if Saved().vertical then
        cx, cy = base.left + short / 2, base.top + DELTA + 14 - HANDLE / 2
    else
        cx, cy = base.left - DELTA - 14 + HANDLE / 2, base.top - short / 2
    end
    change()
    short = Short()
    if Saved().vertical then
        base = { left = cx - short / 2, top = cy + HANDLE / 2 - 14 - DELTA }
    else
        base = { left = cx + 14 - HANDLE / 2 + DELTA, top = cy + short / 2 }
    end
    SetExt(ext)
    Saved().pos = { "TOPLEFT", "BOTTOMLEFT", base.left, base.top }
end
local function Rotate() Reshape(function() Saved().vertical = not Saved().vertical end) end
local function TwoRows() Reshape(function() Saved().two = not Saved().two end) end

-- the pictures of the windows follow what is set for them in the window designer (the round icon of their frame)
local function Pictures()
    for _, b in ipairs(buttons) do
        local sk = W.SkinOf(b.key)
        if type(sk.icon) == "table" and sk.icon.atlas then
            b.icon:SetAtlas(sk.icon.atlas, false)
        else
            b.icon:SetTexture(sk.icon or FALLBACK[b.key])
            b.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
        end
    end
end

local function Build()
    bar = W.NewPlate(UIParent, { 0.125, 0.1, 0.08, 0.96 })
    bar:SetFrameStrata("MEDIUM")
    bar:SetToplevel(true)
    bar:SetMovable(true)
    bar:SetClampedToScreen(true)
    bar:EnableMouse(true)
    bar:SetScript("OnMouseUp", function(_, button)
        if button == "RightButton" and not IsShiftKeyDown() then Rotate() end
    end)
    -- the logo (it has its own ring): the place to take hold of the bar
    handle = CreateFrame("Button", nil, bar)
    handle:SetSize(HANDLE, HANDLE)
    handle:SetFrameLevel(bar:GetFrameLevel() + 5)
    handle.logo = handle:CreateTexture(nil, "ARTWORK")
    handle.logo:SetAllPoints()
    handle.logo:SetVertexColor(0.82, 0.8, 0.78) -- (a little darker: the buttons are the bright part)
    handle.logo:SetTexture("Interface\\AddOns\\ForeverCompanion\\Media\\logo")
    handle:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    -- (the bar follows the mouse from the first pixel; Shift + click is for the rows, so no move then)
    handle:SetScript("OnMouseDown", function(_, button)
        if button ~= "LeftButton" or IsShiftKeyDown() then return end
        bar.moving = true
        W.StartDrag(bar, function() bar.moving = nil; SavePosition() end)
    end)
    handle:SetScript("OnClick", function(_, button)
        if button == "RightButton" then
            if IsShiftKeyDown() then Saved().autoHide = not Saved().autoHide else Rotate() end
            return
        elseif IsShiftKeyDown() then
            TwoRows()
        end
    end)
    handle:SetScript("OnEnter", function(self)
        self.logo:SetVertexColor(1, 1, 1)
        GameTooltip:SetOwner(self, "ANCHOR_NONE") -- (at the left of the logo, in the middle of its height, turned or not)
        GameTooltip:ClearAllPoints()
        GameTooltip:SetPoint("RIGHT", self, "LEFT", -4, 0)
        GameTooltip:AddLine(L["Forever Companion"], 1, 0.85, 0.4)
        GameTooltip:AddDoubleLine(L["Drag"], L["Move"], 1, 0.82, 0.2, 1, 1, 1)
        GameTooltip:AddDoubleLine(L["Right-click"], L["Turn"], 1, 0.82, 0.2, 1, 1, 1)
        GameTooltip:AddDoubleLine(L["Shift + click"], L["1 or 2 rows"], 1, 0.82, 0.2, 1, 1, 1)
        GameTooltip:AddDoubleLine(L["Shift + right-click"], Saved().autoHide and L["Show logo always"] or L["Auto-hide logo"], 1, 0.82, 0.2, 1, 1, 1)
        GameTooltip:Show()
    end)
    handle:SetScript("OnLeave", function(self) self.logo:SetVertexColor(0.82, 0.8, 0.78); GameTooltip:Hide() end)
    buttons = {}
    for _, d in ipairs(Windows()) do
        local b = W.NewIconButton(bar, FALLBACK[d[1]], BTN)
        b.key = d[1]
        b.iconBase = 1 -- (bright, not dimmed)
        b.icon:SetAlpha(1)
        b:SetBackdropColor(0.2, 0.165, 0.125, 0.96)
        b:SetTip(d[2])
        -- the tooltip a little further below the button
        function b:ShowTip()
            GameTooltip:SetOwner(self, "ANCHOR_BOTTOM", 0, -10)
            GameTooltip:ClearLines()
            GameTooltip:AddLine(self.tipTitle or "", 1, 0.85, 0.4)
            GameTooltip:Show()
        end
        b:SetScript("OnClick", d[3])
        buttons[#buttons + 1] = b
    end
    local pos = Saved().pos
    bar:ClearAllPoints()
    if pos then bar:SetPoint(pos[1], UIParent, pos[2], pos[3], pos[4]) else bar:SetPoint("CENTER", UIParent, "CENTER", 0, -200) end
    Layout()
    Pictures()
    -- the logo fades in and the bar grows with the mouse over it; a moment after the mouse has left it goes the same way back
    local away = 0
    bar:SetScript("OnUpdate", function(self, dt)
        if not base and ext == 0 then Capture() end
        local goal = DELTA
        if Saved().autoHide and not (self:IsMouseOver() or handle:IsMouseOver() or self.moving) then
            away = away + dt
            if away > 0.5 then goal = 0 else goal = ext end
        else
            away = 0
        end
        if ext ~= goal then
            local step = (goal - ext) * math.min(1, dt * 14)
            if math.abs(goal - ext) < 0.4 then step = goal - ext end
            if ext == 0 and not self.moving then Capture() end
            SetExt(ext + step)
        end
    end)
    bar:Hide()
end

function Q.Show()
    if not bar then Build() end
    Pictures()
    bar:Show()
    Saved().shown = true
end
function Q.Hide()
    if bar then bar:Hide() end
    if ns.db then Saved().shown = false end
end
function Q.Toggle()
    if bar and bar:IsShown() then Q.Hide() else Q.Show() end
end
function Q.IsShown() return bar and bar:IsShown() or false end

-- The bar is there at the first start (so that a new player sees it and finds out how to use it), and after that as it was left: shown
-- until the player closes it (Hide writes shown = false).
local loader = CreateFrame("Frame")
loader:RegisterEvent("PLAYER_LOGIN")
loader:SetScript("OnEvent", function()
    if ns.db and Saved().shown ~= false then Q.Show() end
end)

SLASH_FOREVERCOMPANIONBAR1 = "/fcbar"
SlashCmdList.FOREVERCOMPANIONBAR = function() Q.Toggle() end
