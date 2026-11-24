local ADDON, ns = ...
local L = ns.L
local W = ns.W
local C = W.C

-- The game's own world map: the markers of the loot map (plants, veins, objects, creatures) with the same
-- filter, opacity and size as the loot map and the minimap, and a column of buttons at the map's edge:
-- a menu (what is shown), the marker opacity and the marker size. Everything is read from ns.MapData, so
-- a change of the filter here shows on the minimap too (and the other way round).

local M = {}
ns.WorldMapMarkers = M

local MAX_DOTS = 400
local MAX_HEAT = 120
local HEAT_SIZE = { 1, 0.62, 0.3 }
local HEAT_COLOR = { { 0.85, 0.16, 0.1 }, { 1, 0.5, 0.14 }, { 1, 0.86, 0.45 } }
local BLOB = "Interface\\CharacterFrame\\TempPortraitAlphaMask"

local overlay, heatFrame
local dots, heat = {}, {}
local lastKey, lastAt = nil, 0
local open = {} -- which groups list their single sources

local function Canvas()
    if not WorldMapFrame then return nil end
    if WorldMapFrame.GetCanvas then return WorldMapFrame:GetCanvas() end
    return WorldMapFrame.ScrollContainer and WorldMapFrame.ScrollContainer.Child
end

local function Ensure()
    if overlay then return overlay end
    local canvas = Canvas()
    if not canvas then return nil end
    overlay = CreateFrame("Frame", nil, canvas)
    overlay:SetAllPoints(canvas)
    overlay:SetFrameLevel(canvas:GetFrameLevel() + 55)
    heatFrame = CreateFrame("Frame", nil, canvas)
    heatFrame:SetAllPoints(canvas)
    heatFrame:SetFrameLevel(canvas:GetFrameLevel() + 54)
    return overlay
end

local function CanvasScale()
    local sc = WorldMapFrame and WorldMapFrame.ScrollContainer
    if sc and sc.GetCanvasScale then
        local ok, s = pcall(sc.GetCanvasScale, sc)
        if ok and type(s) == "number" and s > 0 then return s end
    end
    return 1
end

local function NewDot(parent)
    local b = W.NewMapMarker(parent)
    b:SetScript("OnEnter", function(self)
        W.Ease(self, "hv", 1, 14, function(o, val) o:SetGrow(val) end)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        local named = self.key and self.node and ns.TipNodeFor and ns.TipNodeFor(GameTooltip, self.key, self.spot)
        if not named then
            GameTooltip:AddLine(self.title or "", 1, 0.85, 0.4)
            if self.sub then GameTooltip:AddLine(self.sub, 0.6, 0.6, 0.6) end
            if self.count and self.count > 1 then
                GameTooltip:AddLine((self.node and L["Looted %d times"] or L["Seen %d times"]):format(self.count), 0.8, 0.8, 0.8)
            end
            GameTooltip:AddDoubleLine(self.lastLabel or L["Last used"], ns.Ago(self.last), 0.8, 0.8, 0.8, 1, 1, 1)
        end
        GameTooltip:Show()
    end)
    b:SetScript("OnLeave", function(self)
        W.Ease(self, "hv", 0, 14, function(o, val) o:SetGrow(val) end)
        GameTooltip:Hide()
    end)
    return b
end

local function HideAll()
    for i = 1, #dots do dots[i]:Hide() end
    for i = 1, #heat do for k = 1, 3 do heat[i][k]:Hide() end end
end

function M.Refresh(force)
    if not (ns.db and WorldMapFrame and WorldMapFrame:IsShown()) then return end
    local o = Ensure()
    if not o then return end
    if not ns.MapWorldOn() then HideAll(); lastKey = nil; return end
    local mapID = WorldMapFrame.GetMapID and WorldMapFrame:GetMapID()
    if not mapID then HideAll() return end
    local w, h = o:GetWidth(), o:GetHeight()
    local scale = CanvasScale()
    local now = GetTime()
    local key = table.concat({ mapID, ns.mapVersion, math.floor(scale * 20), math.floor(w), ns.MapSize(), tostring(ns.mapQuery) }, ":")
    if not force and key == lastKey and now - lastAt < 4 then return end
    lastKey, lastAt = key, now

    local data = ns.MapData(mapID, "all", ns.mapQuery)
    local size, opacity = ns.MapSize(), ns.MapOpacity()

    local n = 0
    for _, d in ipairs(data.dots) do
        if n >= MAX_DOTS then break end
        n = n + 1
        local b = dots[n]
        if not b then b = NewDot(overlay); dots[n] = b end
        if d.icon then
            b:SetLook("ring", 13 * size / scale)
            b.pic:SetTexture(d.icon)
            b.pic:Show()
            b.fill:Hide()
        else
            b:SetLook("plain", 9 * size / scale)
            b.pic:Hide()
            b.fill:Show()
            b.fill:SetColorTexture(d.color[1], d.color[2], d.color[3], 1)
        end
        b:SetParts(nil)
        b:SetBadge(nil)
        b.num:SetText("")
        b:SetPulse(d.hot)
        b:SetAlpha((d.dim and 0.28 or 1) * opacity)
        b.title, b.sub, b.count, b.last, b.lastLabel = d.title, d.sub, d.n, d.last, d.lastLabel
        b.node, b.spot, b.key = d.node, d.spot, d.key
        b:ClearAllPoints()
        b:SetPoint("CENTER", o, "TOPLEFT", d.x * w, -d.y * h)
        b:Show()
    end
    for i = n + 1, #dots do dots[i]:Hide() end

    -- creatures: a heat cloud, as on the loot map
    local maxW = 0
    for _, hc in ipairs(data.heat) do maxW = math.max(maxW, hc.w) end
    local base = w * 0.07
    local nh = 0
    for _, hc in ipairs(data.heat) do
        if nh >= MAX_HEAT then break end
        nh = nh + 1
        local set = heat[nh]
        if not set then
            set = {}
            for k = 1, 3 do
                local t = heatFrame:CreateTexture(nil, "ARTWORK")
                t:SetTexture(BLOB)
                t:SetBlendMode("ADD")
                set[k] = t
            end
            heat[nh] = set
        end
        local t = math.sqrt(hc.w / math.max(1, maxW))
        local fade = (hc.dim and 0.3 or 1) * opacity
        local alpha = { (0.08 + 0.08 * t) * fade, (0.11 + 0.17 * t) * fade, (0.13 + 0.30 * t) * fade }
        for k = 1, 3 do
            local tex = set[k]
            local c = HEAT_COLOR[k]
            tex:SetVertexColor(c[1], c[2], c[3], alpha[k])
            tex:ClearAllPoints()
            tex:SetPoint("CENTER", o, "TOPLEFT", hc.x * w, -hc.y * h)
            local s = base * HEAT_SIZE[k] * (0.75 + 0.5 * t)
            tex:SetSize(s, s)
            tex:Show()
        end
    end
    for i = nh + 1, #heat do for k = 1, 3 do heat[i][k]:Hide() end end
end

-- the menu -----------------------------------------------------------------------------------

local dd, menuBtn, opBtn, sizeBtn

local function CurrentSources()
    local mapID = WorldMapFrame and WorldMapFrame.GetMapID and WorldMapFrame:GetMapID()
    if not mapID then return {} end
    local data = ns.MapData(mapID, "all", nil, true)
    return data.sources or {}
end

local function GroupState(id, list)
    local visible = 0
    for _, src in ipairs(list) do
        if ns.MapSourceVisible(src.key, id) then visible = visible + 1 end
    end
    if #list == 0 then return ns.MapCatShown(id) and "all" or "none" end
    return visible == 0 and "none" or (visible == #list and "all" or "some")
end

local function MenuRows()
    local rows = {}
    local function Add(e) rows[#rows + 1] = e end
    Add({ kind = "header", label = L["Loot map markers"] })
    Add({ kind = "check", state = ns.MapWorldOn() and "all" or "none", label = L["Show on the world map"],
        onClick = function() ns.MapSetWorld(not ns.MapWorldOn()) end })
    Add({ kind = "check", state = ns.MapMinimapOn() and "all" or "none", label = L["Show on the minimap"],
        onClick = function() ns.MapSetMinimap(not ns.MapMinimapOn()) end })
    Add({ kind = "separator" })
    local sources = CurrentSources()
    for _, id in ipairs(ns.MAP_GROUPS) do
        local list = {}
        for _, src in ipairs(sources) do if src.group == id then list[#list + 1] = src end end
        local info = ns.MapGroupInfo(id)
        local total = 0
        for _, src in ipairs(list) do total = total + src.n end
        Add({ kind = "check", state = GroupState(id, list), label = info.label, icon = info.icon,
            right = #list > 0 and tostring(#list) or nil,
            onClick = function()
                ns.MapSetGroup(id, GroupState(id, list) ~= "all")
            end })
        if #list > 0 then
            Add({ kind = "action", indent = 18, label = (open[id] and "- " or "+ ") .. L["Choose single ones"],
                color = C.muted, onClick = function() open[id] = not open[id] end })
            if open[id] then
                table.sort(list, function(a, b)
                    if a.n ~= b.n then return a.n > b.n end
                    return a.name < b.name
                end)
                for _, src in ipairs(list) do
                    Add({ kind = "check", indent = 18, label = src.name, right = tostring(src.n),
                        state = ns.MapSourceVisible(src.key, id) and "all" or "none",
                        onClick = function() ns.MapSetSourceSel(src.key, not ns.MapSourceVisible(src.key, id), id) end })
                end
            end
        end
    end
    Add({ kind = "separator" })
    Add({ kind = "action", label = L["Show everything"], onClick = function()
        for _, g in ipairs(ns.MAP_GROUPS) do ns.MapSetGroup(g, true) end
    end })
    Add({ kind = "action", label = L["Hide everything"], onClick = function()
        for _, g in ipairs(ns.MAP_GROUPS) do ns.MapSetGroup(g, false) end
    end })
    return rows
end

local function Build()
    if menuBtn or not (WorldMapFrame and WorldMapFrame.ScrollContainer) then return end
    local host = WorldMapFrame.ScrollContainer
    dd = W.NewDropdown(UIParent, { width = 260, maxHeight = 460 })
    local level = host:GetFrameLevel() + 120
    local SZ = 28

    menuBtn = W.NewIconButton(WorldMapFrame, "Interface\\AddOns\\ForeverCompanion\\Media\\logo64.tga", SZ)
    menuBtn:SetFrameLevel(level)
    menuBtn:SetPoint("TOPRIGHT", host, "TOPRIGHT", -8, -44)
    menuBtn:SetTip(L["Loot map markers"], L["Click for the menu: what the map and the minimap show."])
    menuBtn:SetScript("OnClick", function(self)
        if dd.owner == self and dd:IsShown() then dd:Close() else dd:Open(self, MenuRows) end
    end)

    opBtn = W.NewIconButton(WorldMapFrame, "Interface\\Icons\\Spell_Nature_Invisibilty", SZ)
    opBtn:SetFrameLevel(level)
    opBtn:SetPoint("TOP", menuBtn, "BOTTOM", 0, -4)
    opBtn:SetScript("OnClick", function() ns.MapNextOpacity(); ns.MapOpacityTip(opBtn) end)
    ns.MapOpacityTip(opBtn)

    sizeBtn = W.NewIconButton(WorldMapFrame, "Interface\\Icons\\INV_Misc_Gem_Variety_01", SZ)
    sizeBtn:SetFrameLevel(level)
    sizeBtn:SetPoint("TOP", opBtn, "BOTTOM", 0, -4)
    sizeBtn:SetScript("OnClick", function() ns.MapNextSize(); ns.MapSizeTip(sizeBtn) end)
    ns.MapSizeTip(sizeBtn)
end

local watcher = CreateFrame("Frame")
watcher:RegisterEvent("PLAYER_LOGIN")
watcher:SetScript("OnEvent", function()
    local ok, err = pcall(Build)
    if not ok then print("|cffffd100ForeverCompanion:|r world map buttons could not be built: " .. tostring(err)) end
    if WorldMapFrame then
        if WorldMapFrame.OnMapChanged then hooksecurefunc(WorldMapFrame, "OnMapChanged", function() M.Refresh(true) end) end
        WorldMapFrame:HookScript("OnShow", function() M.Refresh(true) end)
    end
end)
local acc = 0
watcher:SetScript("OnUpdate", function(_, dt)
    if not (WorldMapFrame and WorldMapFrame:IsShown() and ns.db) then return end
    W.PulseMarkers(dots)
    acc = acc + dt
    if acc < 0.4 then return end
    acc = 0
    M.Refresh()
end)
