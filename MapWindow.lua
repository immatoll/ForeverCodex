local ADDON, ns = ...
local L = ns.L
local W = ns.W
local C = W.C

-- The map as a small window of its own: only the map, following you, showing what the
-- filter of the maps shows (groups, choices, search). Dragging the map moves the window,
-- the corner resizes it.

local MapWindow = {}
ns.MapWindow = MapWindow

local DEFAULT_W, DEFAULT_H = 280, 230
local PAD = 6

local win = CreateFrame("Frame", "ForeverCodexMapWindow", UIParent, W.TEMPLATE)
win:SetSize(DEFAULT_W, DEFAULT_H)
win:SetPoint("CENTER", UIParent, "CENTER", 300, 0)
win:SetFrameStrata("MEDIUM")
win:SetToplevel(true)
win:SetMovable(true)
win:SetResizable(true)
if win.SetResizeBounds then win:SetResizeBounds(170, 140, 700, 600)
else win:SetMinResize(170, 140); win:SetMaxResize(700, 600) end
win:SetClampedToScreen(true)
win:EnableMouse(true)
win:SetBackdrop(W.PLATE_BACKDROP)
win:SetBackdropColor(0.055, 0.045, 0.038, 1)
win:SetBackdropBorderColor(C.goldDim[1], C.goldDim[2], C.goldDim[3], 1)
win:Hide()

local view = W.NewMapView(win)
view.alwaysFollow = true -- the window is for following you
view.noPan = true        -- dragging the map moves the window instead
view.popBtn:Hide()          -- it is the small window itself
view.sf:SetPoint("TOPLEFT", win, "TOPLEFT", PAD + 3, -(PAD + 3))

local zone = win:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
zone:SetPoint("TOPLEFT", view.sf, "TOPLEFT", 8, -7)
zone:SetTextColor(1, 0.9, 0.62)

local close = W.NewButton(win, "×", 18, 18, "GameFontNormal")
close:SetPoint("TOPRIGHT", view.sf, "TOPRIGHT", -5, -5)
close:SetFrameLevel(view.border:GetFrameLevel() + 6)
close:SetScript("OnClick", function() MapWindow.Hide() end)
local opacityBtn = W.NewOpacityButton(win, "map", win, 18)
opacityBtn:SetPoint("RIGHT", close, "LEFT", -3, 0)
opacityBtn:SetFrameLevel(view.border:GetFrameLevel() + 6)

local function SavePosition()
    local point, _, rel, x, y = win:GetPoint()
    ns.db.mapWin = ns.db.mapWin or {}
    ns.db.mapWin.pos = { point, rel, x, y }
    ns.db.mapWin.size = { win:GetWidth(), win:GetHeight() }
    ns.db.mapWin.scale = win:GetScale()
end

-- dragging the map or the frame moves the window
view.sf:HookScript("OnMouseDown", function(_, button)
    if button == "LeftButton" then win:StartMoving() end
end)
view.sf:HookScript("OnMouseUp", function()
    win:StopMovingOrSizing()
    SavePosition()
end)
win:SetScript("OnMouseDown", function(self, button)
    if button == "LeftButton" then self:StartMoving() end
end)
win:SetScript("OnMouseUp", function(self)
    self:StopMovingOrSizing()
    SavePosition()
end)

local grip = CreateFrame("Button", nil, win)
grip:SetSize(14, 14)
grip:SetPoint("BOTTOMRIGHT", -2, 2)
grip:SetFrameLevel(view.border:GetFrameLevel() + 6)
grip:SetNormalTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Up")
grip:SetHighlightTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Highlight")
grip:SetPushedTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Down")
W.AttachScaleGrip(win, grip, {
    defaultSize = { DEFAULT_W, DEFAULT_H }, minSize = { 170, 140 }, maxSize = { 700, 600 },
    gridSize = { 20, 20 }, gridScale = 0.05,
    saveSize = SavePosition, saveScale = SavePosition, savePos = SavePosition,
})

local function Fit()
    view:SetArea(win:GetWidth() - 2 * (PAD + 3), win:GetHeight() - 2 * (PAD + 3))
end
win:SetScript("OnSizeChanged", Fit)

-- what is shown follows the zone you are in; the dots every second
local acc, lastVersion, lastQuery = 0, -1, nil
local function Refresh(force)
    local mapID = ns.PlayerPos()
    if not mapID then
        zone:SetText("")
        view:SetDots({})
        view:SetHeat({})
        view.note:SetText(L["No position available here."])
        return
    end
    if view.mapID ~= mapID then
        view:SetMap(mapID)
        force = true
    end
    if C_Map and C_Map.GetMapInfo then
        local ok, info = pcall(C_Map.GetMapInfo, mapID)
        zone:SetText(ok and info and info.name or "")
    end
    if force or lastVersion ~= ns.mapVersion or lastQuery ~= ns.mapQuery then
        lastVersion, lastQuery = ns.mapVersion, ns.mapQuery
    end
    local data = ns.MapData(mapID, "all", ns.mapQuery)
    view:SetHeat(data.heat)
    view:SetDots(data.dots)
end

win:SetScript("OnUpdate", function(_, dt)
    W.Step(dt)
    acc = acc + dt
    if acc < 1 then return end
    acc = 0
    Refresh(false)
end)

function MapWindow.Show()
    win:Show()
    if ns.db then ns.db.mapWinShown = true end
    Fit()
    view.mapID = nil -- start at the zone and the zoom for the player
    Refresh(true)
end

function MapWindow.Hide()
    win:Hide()
    if ns.db then ns.db.mapWinShown = false end
end

function MapWindow.IsShown() return win:IsShown() end

function MapWindow.Toggle()
    if win:IsShown() then MapWindow.Hide() else MapWindow.Show() end
end

local loader = CreateFrame("Frame")
loader:RegisterEvent("PLAYER_LOGIN")
loader:SetScript("OnEvent", function()
    local saved = ns.db and ns.db.mapWin
    if saved and saved.scale then win:SetScale(math.max(0.6, math.min(1.6, saved.scale))) end
    if saved and saved.size then
        win:SetSize(math.max(170, saved.size[1]), math.max(140, saved.size[2]))
    end
    if saved and saved.pos then
        win:ClearAllPoints()
        win:SetPoint(saved.pos[1], UIParent, saved.pos[2], saved.pos[3], saved.pos[4])
    end
    W.SetWindowAlpha(win, W.WindowAlpha("map"))
    if ns.db and ns.db.mapWinShown then MapWindow.Show() end
end)

SLASH_FOREVERCODEXMINI1 = "/fcmini"
SLASH_FOREVERCODEXMINI2 = "/fklmini"
SlashCmdList.FOREVERCODEXMINI = function() MapWindow.Toggle() end
