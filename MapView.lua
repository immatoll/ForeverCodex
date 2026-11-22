local ADDON, ns = ...
local L = ns.L
local W = ns.W
local C = W.C
local Ease = W.Ease

-- A zoomable zone map: the map picture (tiles from the client), dots on it, and
-- the player. Mouse wheel zooms around the cursor, dragging pans. Used by the
-- journal's map page and by the session panel's map tab.
--
--   local view = W.NewMapView(parent)
--   view.sf:SetPoint(...)        -- where it sits; the view fits its map's aspect
--   view:SetArea(w, h)           -- the space it may use
--   view:SetMap(mapID)           -- picture (falls back to a plain field)
--   view:SetDots({ {x=, y=, color=, title=, n=, spot=, zone=}, ... })

local DOT = 9
local ICON_D = 13 -- the picture inside a marker's ring
local MAX_ZOOM = 10
local BLOB = "Interface\\CharacterFrame\\TempPortraitAlphaMask" -- a round shape, stacked into a soft glow
local MAX_HEAT = 320
local HEAT_GRID = 56 -- cells per map width: places close together melt into one area
local atan2 = math.atan2 or function(y, x) return math.atan(y, x) end

-- how far a saved spot is from you in yards; nil when you are not in its zone
function ns.SpotDistance(spot)
    if not spot or not spot.m then return nil end
    local mapID, px, py = ns.PlayerPos()
    if mapID ~= spot.m then return nil end
    local w, h = ns.WorldSize(mapID)
    local dx, dy = (spot.x - px) * w, (spot.y - py) * h
    return math.floor(math.sqrt(dx * dx + dy * dy))
end

-- "5 min ago", "3 h ago" ...
function ns.Ago(t)
    if not t then return L["unknown"] end
    local d = math.max(0, time() - t)
    if d < 60 then return L["just now"] end
    if d < 3600 then return L["%d min ago"]:format(math.floor(d / 60)) end
    if d < 86400 then return L["%d h ago"]:format(math.floor(d / 3600)) end
    return L["%d d ago"]:format(math.floor(d / 86400))
end

local function Clamp(v, lo, hi) return math.max(lo, math.min(hi, v)) end

-- The hidden parts of a zone's picture ---------------------------------------------------------
-- Data/MapOverlays.lua: per art id a string of overlays "width,height,x,y,file:file:...;..."
-- (positions in the picture's pixels, tiles row by row, as many columns as the width needs).

local overlayCache = {}
local function Overlays(artID)
    local list = overlayCache[artID]
    if list then return list end
    list = {}
    for part in ((ns.MAP_OVERLAYS or {})[artID] or ""):gmatch("[^;]+") do
        local w, h, x, y, files = part:match("^(%d+),(%d+),(%-?%d+),(%-?%d+),([%d:]+)$")
        if w then
            local ids = {}
            for id in files:gmatch("%d+") do ids[#ids + 1] = tonumber(id) end
            list[#list + 1] = { w = tonumber(w), h = tonumber(h), x = tonumber(x), y = tonumber(y), ids = ids }
        end
    end
    overlayCache[artID] = list
    return list
end

-- picture files have power-of-two sizes
local function FileSize(px)
    local s = 16
    while s < px do s = s * 2 end
    return s
end

-- A marker: the picture of a plant or vein in a gold ring (a slim bevel with a soft shadow),
-- or a small flat dot. Everything is drawn around the marker's centre, so a number or a
-- picture sits exactly in the middle. Shared by the maps and the minimap.

-- gold shading from dark below to light above; flat gold when the client has no gradients
local function GoldDisc(tex)
    tex:SetTexture(BLOB)
    local ok = pcall(function()
        tex:SetGradient("VERTICAL", CreateColor(0.50, 0.36, 0.13, 1), CreateColor(1, 0.87, 0.48, 1))
    end)
    if not ok then tex:SetVertexColor(C.gold[1], C.gold[2], C.gold[3], 1) end
end

local function AddRing(frame)
    frame.shadow = frame:CreateTexture(nil, "BACKGROUND", nil, -1)
    frame.shadow:SetTexture(BLOB)
    frame.shadow:SetVertexColor(0, 0, 0, 0.55)
    frame.shadow:SetPoint("CENTER")
    frame.rim = frame:CreateTexture(nil, "BACKGROUND", nil, 0)
    GoldDisc(frame.rim)
    frame.rim:SetPoint("CENTER")
    frame.rimIn = frame:CreateTexture(nil, "BACKGROUND", nil, 1)
    frame.rimIn:SetTexture(BLOB)
    frame.rimIn:SetVertexColor(0.13, 0.095, 0.05, 1)
    frame.rimIn:SetPoint("CENTER")
end

local function SizeRing(frame, D)
    frame.shadow:SetSize(D + 3, D + 3)
    frame.rim:SetSize(D, D)
    frame.rimIn:SetSize(D - 4, D - 4)
end

local function ShowRing(frame, on)
    frame.shadow:SetShown(on)
    frame.rim:SetShown(on)
    frame.rimIn:SetShown(on)
end

function W.NewMapMarker(parent)
    local b = CreateFrame("Button", nil, parent)
    AddRing(b)
    b.fill = b:CreateTexture(nil, "ARTWORK")
    b.fill:SetPoint("CENTER")
    b.pic = b:CreateTexture(nil, "ARTWORK", nil, 1)
    b.pic:SetPoint("CENTER")
    b.pic:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    b.num = b:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    b.num:SetPoint("CENTER", 0, 0)
    -- the picture and the fill are square: round them with masks
    if b.CreateMaskTexture then
        b.maskIn = b:CreateMaskTexture()
        b.maskIn:SetTexture(BLOB, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
        b.maskIn:SetPoint("CENTER")
        b.maskFill = b:CreateMaskTexture()
        b.maskFill:SetTexture(BLOB, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
        b.maskFill:SetPoint("CENTER")
        b.fill:AddMaskTexture(b.maskFill)
        b.pic:AddMaskTexture(b.maskIn)
    end
    b.grow = 0

    -- Combined places show the pictures of their members: one picture when they are all the same, two
    -- halves for two kinds, a half and two quarters for three, four quarters beyond. The parts sit on the
    -- main picture's area and take the same round mask.
    b.parts = {}
    local PART_AT = {
        -- { first anchor on the picture, second anchor on the picture, texcoords l r t b }
        half = {
            { "TOPLEFT", "BOTTOM", { 0.08, 0.50, 0.08, 0.92 } },
            { "TOP", "BOTTOMRIGHT", { 0.50, 0.92, 0.08, 0.92 } },
        },
        three = {
            { "TOPLEFT", "BOTTOM", { 0.08, 0.50, 0.08, 0.92 } },
            { "TOP", "RIGHT", { 0.50, 0.92, 0.08, 0.50 } },
            { "CENTER", "BOTTOMRIGHT", { 0.50, 0.92, 0.50, 0.92 } },
        },
        quarter = {
            { "TOPLEFT", "CENTER", { 0.08, 0.50, 0.08, 0.50 } },
            { "TOP", "RIGHT", { 0.50, 0.92, 0.08, 0.50 } },
            { "LEFT", "BOTTOM", { 0.08, 0.50, 0.50, 0.92 } },
            { "CENTER", "BOTTOMRIGHT", { 0.50, 0.92, 0.50, 0.92 } },
        },
    }
    -- list: { { icon = texture or nil, color = { r, g, b } }, ... } (nil: no parts)
    function b:SetParts(list)
        local n = list and #list or 0
        local layout = n == 2 and PART_AT.half or (n == 3 and PART_AT.three or (n >= 4 and PART_AT.quarter or nil))
        for i = 1, 4 do
            local t = self.parts[i]
            if layout and layout[i] then
                if not t then
                    t = self:CreateTexture(nil, "ARTWORK", nil, 1)
                    if self.maskIn then t:AddMaskTexture(self.maskIn) end
                    self.parts[i] = t
                end
                local spec, def = list[i], layout[i]
                t:ClearAllPoints()
                t:SetPoint("TOPLEFT", self.pic, def[1])
                t:SetPoint("BOTTOMRIGHT", self.pic, def[2])
                if spec.icon then
                    t:SetTexture(spec.icon)
                    t:SetTexCoord(def[3][1], def[3][2], def[3][3], def[3][4])
                else
                    t:SetColorTexture(spec.color[1], spec.color[2], spec.color[3], 1)
                end
                t:Show()
            elseif t then
                t:Hide()
            end
        end
    end

    -- a small round badge with a number, at the top right like a notification
    b.badgeRing = b:CreateTexture(nil, "OVERLAY", nil, 2)
    b.badgeRing:SetTexture(BLOB)
    b.badgeBg = b:CreateTexture(nil, "OVERLAY", nil, 3)
    b.badgeBg:SetTexture(BLOB)
    b.badgeNum = b:CreateFontString(nil, "OVERLAY", "NumberFontNormalSmall")
    b.badgeNum:SetTextColor(1, 0.93, 0.7)
    function b:SetBadge(n)
        if not n then
            self.badgeRing:Hide(); self.badgeBg:Hide(); self.badgeNum:Hide()
            return
        end
        local text = n > 99 and "99+" or tostring(n)
        local size = #text >= 3 and 21 or (#text == 2 and 17 or 14)
        self.badgeRing:SetSize(size + 2, size + 2)
        self.badgeBg:SetSize(size, size)
        self.badgeRing:SetVertexColor(C.gold[1], C.gold[2], C.gold[3], 1)
        self.badgeBg:SetVertexColor(0.10, 0.07, 0.04, 1)
        for _, t in ipairs({ self.badgeRing, self.badgeBg }) do
            t:ClearAllPoints()
            t:SetPoint("CENTER", self, "TOPRIGHT", -4, -4)
        end
        self.badgeNum:ClearAllPoints()
        self.badgeNum:SetPoint("CENTER", self.badgeBg, "CENTER", 0, 0)
        self.badgeNum:SetText(text)
        self.badgeRing:Show(); self.badgeBg:Show(); self.badgeNum:Show()
    end
    b:SetBadge(nil)

    -- kind "ring": d is the picture's size, the marker is twice that; "plain": a flat dot of size d
    function b:SetLook(kind, d)
        self.kind, self.d = kind, d
        if kind == "ring" then
            self:SetSize(d * 2, d * 2)
        else
            self:SetSize(d, d)
        end
        ShowRing(self, kind == "ring")
        self:Scale(self.scaleNow or 1)
    end

    -- size factor (breathing) and hover growth, around the centre; the hit area stays
    function b:Scale(k)
        self.scaleNow = k
        local d = self.d
        if not d then return end
        local f = k * (1 + 0.22 * (self.grow or 0))
        local pic, fill
        if self.kind == "ring" then
            local D = d * 2 * f
            SizeRing(self, D)
            fill, pic = D - 6, D * 0.62
        else
            fill, pic = d * f, d * f
        end
        self.pic:SetSize(pic, pic)
        self.fill:SetSize(fill, fill)
        if self.maskIn then self.maskIn:SetSize(pic, pic) end
        if self.maskFill then self.maskFill:SetSize(fill, fill) end
    end

    function b:SetGrow(v)
        self.grow = v
        self:Scale(self.scaleNow or 1)
    end

    function b:SetPulse(on)
        on = on and true or false
        if self.pulse and not on then self:Scale(1) end
        self.pulse = on
    end
    return b
end

-- A dial for the guide: the arrow in the same gold ring. d is half the dial's size.
function W.NewDial(parent, d)
    local f = CreateFrame("Frame", nil, parent)
    f:SetSize(d * 2, d * 2)
    AddRing(f)
    SizeRing(f, d * 2)
    f.arrow = f:CreateTexture(nil, "ARTWORK")
    f.arrow:SetTexture("Interface\\Minimap\\ROTATING-MINIMAPARROW")
    f.arrow:SetSize(d * 2.3, d * 2.3) -- the texture has wide empty margins: the visible arrow fills the dial
    f.arrow:SetPoint("CENTER")
    f.arrow:SetVertexColor(C.gold[1], C.gold[2], C.gold[3])
    function f:SetAngle(rad) self.arrow:SetRotation(rad) end
    function f:SetActive(on) self.arrow:SetAlpha(on and 1 or 0.3) end
    return f
end

-- marked markers (a search matches them) breathe: a little larger, a little smaller
function W.PulseMarkers(list)
    local k = 1 + 0.13 * math.sin(GetTime() * 3.2)
    for _, b in ipairs(list) do
        if b.pulse and b:IsShown() then b:Scale(k) end
    end
end

-- what is typed in the session window's map search: matches pulse on the maps and the minimap
function ns.SetMapQuery(text)
    ns.mapQuery = (text and text ~= "") and text:lower() or nil
    ns.mapVersion = ns.mapVersion + 1
end

-- What the map shows (kept between sessions and shared by both maps) ----------------
local MAP_CATS = { "mob", "herb", "ore", "object" }
ns.MAP_CATS = MAP_CATS

-- What the filter lists and the map shows as one switch. Rare and boss creatures are groups
-- of their own, next to the ordinary ones (normal and elite).
local GROUPS = { "herb", "ore", "object", "mob", "mob_rare", "mob_boss" }
local ALWAYS = { herb = true, ore = true, mob = true, mob_rare = true, mob_boss = true }
local function GroupOf(cat, kind)
    if cat ~= "mob" then return cat end
    if kind == "boss" then return "mob_boss" end
    if kind == "rare" then return "mob_rare" end
    return "mob"
end
ns.MapGroupOf = GroupOf
local function GroupInfo(id)
    if id == "mob_rare" then
        return { label = L["Creatures (rare)"], color = ns.KINDS.rare.color, icon = ns.CAT.mob.icon }
    elseif id == "mob_boss" then
        return { label = L["Creatures (boss)"], color = ns.KINDS.boss.color, icon = ns.CAT.mob.icon }
    end
    return ns.CAT[id]
end

ns.MAP_GROUPS, ns.MAP_ALWAYS, ns.MapGroupInfo = GROUPS, ALWAYS, GroupInfo

local function Filter()
    local db = ns.db
    local f = db.mapFilter
    if not f then f = { cats = {} }; db.mapFilter = f end
    f.sel = f.sel or {} -- source key -> true / false: an explicit choice for one source
    f.hidden = nil      -- the older way of hiding single sources
    return f
end
-- every change bumps the version, so the minimap knows to rebuild its pins
ns.mapVersion = 0
local function Touch() ns.mapVersion = ns.mapVersion + 1 end
-- plants and veins matter most: creatures stay off the map until they are switched on
function ns.MapCatShown(cat)
    local v = Filter().cats[cat]
    if v == nil then return not cat:find("^mob") end
    return v
end
function ns.MapSetCat(cat, on) Filter().cats[cat] = on and true or false; Touch() end
-- Is this source on the map? Its own choice counts; without one it follows its group.
function ns.MapSourceVisible(key, group)
    local sel = Filter().sel[key]
    if sel ~= nil then return sel end
    return ns.MapCatShown(group)
end
-- choose one source: shown even when its group is off, hidden even when it is on
function ns.MapSetSourceSel(key, on, group)
    local f = Filter()
    if on == ns.MapCatShown(group) then f.sel[key] = nil else f.sel[key] = on and true or false end
    Touch()
end
-- the explicit choice of one source (nil = it follows its group), and putting it back
function ns.MapSelOf(key) return Filter().sel[key] end
function ns.MapRestoreSel(key, value)
    Filter().sel[key] = value
    Touch()
end
-- switch a whole group: all its sources follow
function ns.MapSetGroup(group, on)
    local f = Filter()
    f.cats[group] = on and true or false
    for key, gm in pairs(ns.db.mobs) do
        if GroupOf(gm.cat, gm.kind) == group then f.sel[key] = nil end
    end
    Touch()
end
function ns.MapHeatOn() return Filter().heat ~= false end
function ns.MapSetHeat(on) Filter().heat = on and true or false; Touch() end
function ns.MapFollowOn() return ns.db.settings.mapFollow ~= false end
function ns.MapSetFollow(on) ns.db.settings.mapFollow = on and true or false end
-- a dark veil over the map picture, so the dots stand out and the picture is not so bright
-- 0 = as the game draws it; above 0 darkens; below 0 brightens (the dark, unexplored parts of the picture)
local DIM_LEVELS = { 0, 0.25, 0.5, 0.7, -0.4 }
function ns.MapDim()
    -- the veil starts at 0 now: an earlier default (50 %) is dropped once
    if not ns.db.settings.mapDimReset then
        ns.db.settings.mapDim = nil
        ns.db.settings.mapDimReset = true
    end
    local d = ns.db.settings.mapDim
    return type(d) == "number" and d or 0
end
function ns.MapNextDim()
    local cur, idx = ns.MapDim(), 1
    for i, v in ipairs(DIM_LEVELS) do
        if math.abs(v - cur) < math.abs(DIM_LEVELS[idx] - cur) then idx = i end
    end
    ns.db.settings.mapDim = DIM_LEVELS[idx % #DIM_LEVELS + 1]
end
-- the tooltip of a veil button
function ns.MapDimTip(button)
    local d = ns.MapDim()
    local text = d < 0 and L["Brightened by %d%%"]:format(-d * 100 + 0.5) or L["Dimmed by %d%%"]:format(d * 100 + 0.5)
    button:SetTip(L["Map brightness"], text .. " - " .. L["Click to change"])
end
-- how opaque the markers (and the heat) are, on the maps and the minimap
local OPACITY_LEVELS = { 1, 0.75, 0.5, 0.3 }
function ns.MapOpacity()
    local o = ns.db.settings.markerOpacity
    return type(o) == "number" and o or 1
end
function ns.MapNextOpacity()
    local cur, idx = ns.MapOpacity(), 1
    for i, v in ipairs(OPACITY_LEVELS) do
        if math.abs(v - cur) < math.abs(OPACITY_LEVELS[idx] - cur) then idx = i end
    end
    ns.db.settings.markerOpacity = OPACITY_LEVELS[idx % #OPACITY_LEVELS + 1]
    ns.mapVersion = ns.mapVersion + 1
end
-- which kinds of creatures the map shows
function ns.MapKindShown(kind)
    local k = Filter().kinds
    return not (k and k[kind] == false)
end
function ns.MapSetKind(kind, on)
    local f = Filter()
    f.kinds = f.kinds or {}
    f.kinds[kind] = on and true or false
    ns.mapVersion = ns.mapVersion + 1
end
function ns.MapOpacityTip(button)
    button:SetTip(L["Marker opacity"], L["Opacity: %d%%"]:format(ns.MapOpacity() * 100 + 0.5) .. " - " .. L["Click to change"])
end
function ns.MapMinimapOn() return Filter().minimap ~= false end
function ns.MapSetMinimap(on) Filter().minimap = on and true or false; Touch() end

-- Plants and veins show what they give; everything else its category.
local function SourceMapIcon(gm)
    if gm.cat == "herb" or gm.cat == "ore" then
        local best, bestN
        for id, c in pairs(gm.items or {}) do
            if not bestN or c > bestN then best, bestN = id, c end
        end
        if best then return W.ItemTexture(best) end
    end
    if gm.cat == "object" then return ns.CAT.object.icon end
    if gm.cat == "mob" and (gm.kind == "rare" or gm.kind == "boss") then return ns.CAT.mob.icon end
    return nil
end
ns.SourceMapIcon = SourceMapIcon

-- the subzone a creature was met in most often (nil when it was never recorded)
function ns.PrimarySub(gm)
    local best, bestN
    for name, n in pairs(gm.subs or {}) do
        if not bestN or n > bestN then best, bestN = name, n end
    end
    return best
end

-- Everything for one zone: dots (nodes, or creatures when the heatmap is off),
-- heat cells (creatures), and the list of sources for the filter.
-- scope "session": this session's points; "all": everything saved.
function ns.MapData(mapID, scope, query, noHeat)
    local dots, bins, dimBins, sources, byKey = {}, {}, {}, {}, {}

    local function Add(key, gm, x, y, n, spot, last)
        local cat = gm.cat
        local s = byKey[key]
        if not s then
            s = { key = key, cat = cat, name = gm.name or key, n = 0, icon = SourceMapIcon(gm), group = GroupOf(cat, gm.kind),
                level = cat == "mob" and ns.LevelTag(gm) or nil, sub = cat == "mob" and ns.PrimarySub(gm) or nil }
            byKey[key] = s
            sources[#sources + 1] = s
        end
        s.n = s.n + n
        -- A search filters: it shows what it finds, whatever the groups say, and nothing else.
        -- Without one, the choices of the filter panel decide.
        if query then
            if not s.name:lower():find(query, 1, true) then return end
        elseif not ns.MapSourceVisible(key, s.group) then
            return
        end
        -- creatures are a heatmap; found by a search they are also swords that group together
        local asHeat = s.group == "mob" and not noHeat
        if asHeat then
            local set = bins
            local cx, cy = math.floor(x * HEAT_GRID), math.floor(y * HEAT_GRID)
            local id = cx * 1000 + cy
            local bin = set[id]
            if not bin then bin = { x = 0, y = 0, w = 0 }; set[id] = bin end
            bin.x, bin.y, bin.w = bin.x + x * n, bin.y + y * n, bin.w + n
        end
        if not asHeat or query then
            local sword = asHeat and query ~= nil
            dots[#dots + 1] = { x = x, y = y, color = ns.CAT[cat].color, icon = sword and ns.CAT.mob.icon or s.icon, title = s.name,
                sub = ns.CAT[cat].label, n = n, spot = spot, zone = gm.zone, last = last,
                lastLabel = cat == "mob" and L["Last kill here"] or L["Last used"], dim = false, node = cat ~= "mob",
                hot = query ~= nil, solo = cat == "mob" and not s.icon and not sword, noCount = sword or nil }
        end
    end

    if scope == "session" then
        for _, p in ipairs(ns.session.points or {}) do
            local gm = ns.db.mobs[p.key]
            if p.m == mapID and gm and ns.CatOn(p.cat) then
                Add(p.key, gm, p.x, p.y, p.n or 1, { m = p.m, x = p.x, y = p.y }, p.t)
            end
        end
    else
        for key, gm in pairs(ns.db.mobs) do
            if gm.spots and ns.CatOn(gm.cat) and (gm.cat == "mob" or gm.cat == "herb" or gm.cat == "ore" or gm.cat == "object") then
                for _, sp in pairs(gm.spots) do
                    if sp.m == mapID then Add(key, gm, sp.x, sp.y, sp.n, sp, sp.t) end
                end
            end
        end
    end

    local heat = {}
    for _, b in pairs(bins) do heat[#heat + 1] = { x = b.x / b.w, y = b.y / b.w, w = b.w } end
    for _, b in pairs(dimBins) do heat[#heat + 1] = { x = b.x / b.w, y = b.y / b.w, w = b.w, dim = true } end
    if #heat > MAX_HEAT then
        table.sort(heat, function(a, b) return a.w > b.w end)
        for i = #heat, MAX_HEAT + 1, -1 do heat[i] = nil end
    end

    local order = {}
    for i, c in ipairs(MAP_CATS) do order[c] = i end
    table.sort(sources, function(a, b)
        if a.cat ~= b.cat then return order[a.cat] < order[b.cat] end
        if a.n ~= b.n then return a.n > b.n end
        return a.name < b.name
    end)
    return { dots = dots, heat = heat, sources = sources, shown = query and #dots or (#dots + #heat) }
end

function W.NewMapView(parent)
    local v = { zoom = 1, aspect = 1002 / 668, tiles = {}, dots = {}, data = {}, availW = 300, availH = 200 }

    local sf = CreateFrame("ScrollFrame", nil, parent)
    v.sf = sf
    sf:SetSize(300, 200)
    sf:EnableMouse(true)
    sf:EnableMouseWheel(true)
    local canvas = CreateFrame("Frame", nil, sf)
    canvas:SetSize(300, 200)
    sf:SetScrollChild(canvas)
    v.canvas = canvas

    local shade = canvas:CreateTexture(nil, "ARTWORK", nil, 7)
    shade:SetAllPoints()
    shade:SetColorTexture(0.03, 0.025, 0.02, 0)
    v.shade = shade

    local field = canvas:CreateTexture(nil, "BACKGROUND")
    field:SetAllPoints()
    field:SetColorTexture(0.02, 0.016, 0.012, 1)

    local border = W.NewPlate(parent, { 0, 0, 0, 0 })
    border:SetPoint("TOPLEFT", sf, -3, 3)
    border:SetPoint("BOTTOMRIGHT", sf, 3, -3)
    border:SetFrameLevel(sf:GetFrameLevel() + 30)
    border:EnableMouse(false)
    v.border = border

    -- an obvious button in the map's top right corner: the map as a small window of its own
    local pop = W.NewButton(border, L["Mini map"], 98, 24)
    pop:SetPoint("TOPRIGHT", sf, "TOPRIGHT", -8, -8)
    pop.icon = pop:CreateTexture(nil, "OVERLAY")
    pop.icon:SetSize(14, 14)
    pop.icon:SetPoint("LEFT", 7, 0)
    pop.icon:SetTexture("Interface\\Icons\\INV_Misc_Spyglass_02")
    pop.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    pop.text:ClearAllPoints()
    pop.text:SetPoint("CENTER", 7, 0)
    pop:SetScript("OnClick", function() if ns.MapWindow then ns.MapWindow.Toggle() end end)
    pop:HookScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
        GameTooltip:AddLine(L["Open in a small window"], 1, 0.85, 0.4)
        GameTooltip:AddLine(L["The map as a window of its own, following you, with the current filter."], 0.8, 0.8, 0.8, true)
        GameTooltip:Show()
    end)
    pop:HookScript("OnLeave", function() GameTooltip:Hide() end)
    v.popBtn = pop

    v.note = border:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    v.note:SetPoint("CENTER", sf, "CENTER")
    v.note:SetTextColor(unpack(C.muted))
    v.note:SetWidth(260)

    v.zoomText = border:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    v.zoomText:SetPoint("BOTTOMLEFT", sf, "BOTTOMLEFT", 6, 6)
    v.zoomText:SetTextColor(0.9, 0.84, 0.68)

    -- you on the map: a small light arrow, with a faint breath around it
    local me = CreateFrame("Button", nil, canvas)
    me:SetFrameLevel(canvas:GetFrameLevel() + 12)
    me:SetSize(22, 22)
    me.pulse = me:CreateTexture(nil, "BACKGROUND")
    me.pulse:SetTexture(BLOB)
    me.pulse:SetBlendMode("ADD")
    me.pulse:SetPoint("CENTER")
    me.pulse:SetVertexColor(0.95, 0.9, 0.78, 1)
    me.tex = me:CreateTexture(nil, "OVERLAY")
    me.tex:SetSize(26, 26)
    me.tex:SetPoint("CENTER")
    me.tex:SetTexture("Interface\\Minimap\\ROTATING-MINIMAPARROW")
    -- exactly the picture the minimap uses for you (it may be a custom one)
    do
        local ok, tex = pcall(function() return Minimap:GetPlayerTexture() end)
        if ok and tex then me.tex:SetTexture(tex) end
    end
    me.pulse:Hide() -- the game's own arrow needs no halo
    me:Hide()
    v.me = me
    me:SetScript("OnClick", function()
        if not ns.MapFollowOn() then
            ns.MapSetFollow(true)
            v:ZoomAtLeast(3)
            ns.Refresh()
        end
    end)
    me:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:AddLine(L["You"], 1, 0.85, 0.4)
        if not ns.MapFollowOn() then GameTooltip:AddLine(L["Click: follow me."], 0.4, 0.86, 0.66) end
        GameTooltip:Show()
    end)
    me:SetScript("OnLeave", function() GameTooltip:Hide() end)

    -- the way to the target while the arrow guides you: a line from you to it
    local pathLine, pathShadow
    if canvas.CreateLine then
        pathShadow = canvas:CreateLine(nil, "ARTWORK", nil, 2)
        pathShadow:SetThickness(7)
        pathShadow:SetColorTexture(0, 0, 0, 0.5)
        pathShadow:Hide()
        pathLine = canvas:CreateLine(nil, "ARTWORK", nil, 3)
        pathLine:SetThickness(3.5)
        pathLine:SetColorTexture(1, 0.86, 0.4, 0.95)
        pathLine:Hide()
    end
    local goal = CreateFrame("Frame", nil, canvas)
    goal:SetFrameLevel(canvas:GetFrameLevel() + 11)
    goal:SetSize(8, 8)
    goal.edge = goal:CreateTexture(nil, "ARTWORK")
    goal.edge:SetTexture(BLOB)
    goal.edge:SetAllPoints()
    goal.edge:SetVertexColor(0, 0, 0, 0.8)
    goal.core = goal:CreateTexture(nil, "OVERLAY")
    goal.core:SetTexture(BLOB)
    goal.core:SetSize(6, 6)
    goal.core:SetPoint("CENTER")
    goal.core:SetVertexColor(C.gold[1], C.gold[2], C.gold[3], 1)
    goal:Hide()

    -- while a route is on: a button to end it
    local cancel = W.NewButton(border, L["Cancel route"], 124, 24)
    cancel:SetPoint("BOTTOM", sf, "BOTTOM", 0, 10)
    cancel:SetScript("OnClick", function() if ns.Routes then ns.Routes.StopNav() end end)
    cancel:Hide()
    v.cancelBtn = cancel

    -- heat under the dots: every place is a soft glow, overlaps add up
    local heatFrame = CreateFrame("Frame", nil, canvas)
    heatFrame:SetAllPoints(canvas)
    heatFrame:SetFrameLevel(canvas:GetFrameLevel() + 2)
    v.heat, v.heatTex = {}, {}

    -- layout ----------------------------------------------------------------
    function v:CanvasSize()
        return self.baseW * self.zoom, self.baseH * self.zoom
    end

    v.ov, v.ovPool = {}, {}

    -- the pieces of the hidden overlays for this map: a texture each, with its place in the picture
    function v:BuildOverlays(mapID)
        self.ov = {}
        local li = self.layerInfo
        local artID = C_Map and C_Map.GetMapArtID and C_Map.GetMapArtID(mapID)
        local list = (li and artID) and Overlays(artID) or {}
        local n = 0
        for _, o in ipairs(list) do
            local wide, tall = math.ceil(o.w / li.tw), math.ceil(o.h / li.th)
            for j = 1, tall do
                local ph, fh = li.th, li.th
                if j == tall then
                    ph = o.h % li.th
                    if ph == 0 then ph = li.th end
                    fh = FileSize(ph)
                end
                for k = 1, wide do
                    local pw, fw = li.tw, li.tw
                    if k == wide then
                        pw = o.w % li.tw
                        if pw == 0 then pw = li.tw end
                        fw = FileSize(pw)
                    end
                    local id = o.ids[(j - 1) * wide + k]
                    if id then
                        n = n + 1
                        local tex = self.ovPool[n]
                        if not tex then
                            tex = canvas:CreateTexture(nil, "ARTWORK", nil, 1)
                            self.ovPool[n] = tex
                        end
                        tex:SetTexture(id)
                        tex:SetTexCoord(0, pw / fw, 0, ph / fh)
                        self.ov[n] = { tex = tex, x = o.x + li.tw * (k - 1), y = o.y + li.th * (j - 1), w = pw, h = ph }
                    end
                end
            end
        end
        for i = n + 1, #self.ovPool do self.ovPool[i]:Hide() end
    end

    function v:LayoutOverlays()
        local on = ns.db.settings.mapReveal ~= false
        self.revealShown = on
        local li = self.layerInfo
        local cw, ch = self:CanvasSize()
        for _, o in ipairs(self.ov) do
            if on and li then
                o.tex:ClearAllPoints()
                o.tex:SetPoint("TOPLEFT", canvas, "TOPLEFT", o.x / li.lw * cw, -o.y / li.lh * ch)
                o.tex:SetSize(o.w / li.lw * cw, o.h / li.lh * ch)
                o.tex:Show()
            else
                o.tex:Hide()
            end
        end
    end

    function v:LayoutTiles()
        local t = self.tileInfo
        if not t then return end
        local cw, ch = self:CanvasSize()
        for i, tex in ipairs(self.tiles) do
            if t.files[i] then
                local col, row = (i - 1) % t.cols, math.floor((i - 1) / t.cols)
                local w = math.min(t.tw, t.lw - col * t.tw)
                local h = math.min(t.th, t.lh - row * t.th)
                tex:ClearAllPoints()
                tex:SetPoint("TOPLEFT", canvas, "TOPLEFT", (col * t.tw / t.lw) * cw, -(row * t.th / t.lh) * ch)
                tex:SetSize(w / t.lw * cw, h / t.lh * ch)
            end
        end
    end

    local function NewDot()
        local b = W.NewMapMarker(canvas)
        b:SetFrameLevel(canvas:GetFrameLevel() + 5)
        b:SetScript("OnEnter", function(self)
            Ease(self, "hv", 1, 14, function(o, val) o:SetGrow(val) end)
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            if self.members then
                GameTooltip:AddLine(L["%d places here"]:format(#self.members), 1, 0.85, 0.4)
                local counts, order, latest = {}, {}, nil
                for _, d in ipairs(self.members) do
                    local k = d.title or "?"
                    if not counts[k] then counts[k] = 0; order[#order + 1] = k end
                    counts[k] = counts[k] + 1
                    if d.last and (not latest or d.last > latest) then latest = d.last end
                end
                table.sort(order, function(x, y)
                    if counts[x] ~= counts[y] then return counts[x] > counts[y] end
                    return x < y
                end)
                for i = 1, math.min(8, #order) do
                    GameTooltip:AddDoubleLine(order[i], counts[order[i]] > 1 and ("x" .. counts[order[i]]) or "", 0.9, 0.9, 0.9, 0.7, 0.7, 0.7)
                end
                if #order > 8 then GameTooltip:AddLine(L["and %d more"]:format(#order - 8), 0.6, 0.6, 0.6) end
                if latest then GameTooltip:AddDoubleLine(L["Latest"], ns.Ago(latest), 0.8, 0.8, 0.8, 1, 1, 1) end
                GameTooltip:AddLine(L["Click to zoom in."], 0.4, 0.86, 0.66)
            else
                GameTooltip:AddLine(self.title or "", 1, 0.85, 0.4)
                if self.sub then GameTooltip:AddLine(self.sub, 0.6, 0.6, 0.6) end
                if self.n and self.n > 1 then
                    GameTooltip:AddLine((self.node and L["Looted %d times"] or L["Seen %d times"]):format(self.n), 0.8, 0.8, 0.8)
                end
                GameTooltip:AddDoubleLine(self.lastLabel or L["Last used"], ns.Ago(self.last), 0.8, 0.8, 0.8, 1, 1, 1)
                local away = ns.SpotDistance(self.spot)
                if away then GameTooltip:AddDoubleLine(L["Distance"], away .. " " .. L["yd"], 0.8, 0.8, 0.8, 1, 1, 1) end
                if self.spot then
                    local guiding = ns.Routes and ns.Routes.IsTarget(self.spot)
                    GameTooltip:AddLine(guiding and L["Click: stop guiding."] or L["Click: the arrow leads you there."], 0.4, 0.86, 0.66)
                    local idx = ns.Routes and ns.Routes.IndexOf(self.spot)
                    if idx then GameTooltip:AddLine(L["In the route (point %d)"]:format(idx), 0.85, 0.85, 0.85) end
                    GameTooltip:AddLine(idx and L["Shift+click: take it out of the route."] or L["Shift+click: add it to the route."], 0.4, 0.86, 0.66)
                end
            end
            GameTooltip:Show()
        end)
        b:SetScript("OnLeave", function(self)
            Ease(self, "hv", 0, 14, function(o, val) o:SetGrow(val) end)
            GameTooltip:Hide()
        end)
        b:SetScript("OnClick", function(self)
            if self.members then
                v:ZoomToPoint(self.cu, self.cv, 2.4)
            elseif self.spot and ns.Routes and IsShiftKeyDown() then
                -- build the route by hand: add the place, or take it out again
                local idx = ns.Routes.IndexOf(self.spot)
                if idx then ns.Routes.RemoveFromActive(idx) else ns.Routes.AddToActive(self.title, self.spot, self.zone) end
            elseif self.spot and ns.Routes then
                if ns.Routes.IsTarget(self.spot) then
                    ns.Routes.StopNav()
                else
                    ns.Routes.GoTo(self.title, self.spot, self.zone)
                end
            end
        end)
        return b
    end

    -- Places that sit close together on screen merge into one numbered marker; zooming
    -- in pulls them apart again.
    local CLUSTER_R = 28

    local function Cluster(data, cw, ch)
        local clusters, grid = {}, {}
        for _, d in ipairs(data) do
            local px, py = d.x * cw, d.y * ch
            local gx, gy = math.floor(px / CLUSTER_R), math.floor(py / CLUSTER_R)
            local hit
            for ox = -1, d.solo and -2 or 1 do
                for oy = -1, 1 do
                    local list = grid[(gx + ox) * 100003 + (gy + oy)]
                    if list then
                        for _, c in ipairs(list) do
                            local dx, dy = c.px / c.n - px, c.py / c.n - py
                            if dx * dx + dy * dy < CLUSTER_R * CLUSTER_R then hit = c break end
                        end
                    end
                    if hit then break end
                end
                if hit then break end
            end
            if hit then
                hit.items[#hit.items + 1] = d
                hit.px, hit.py, hit.n = hit.px + px, hit.py + py, hit.n + 1
            else
                local c = { px = px, py = py, n = 1, items = { d } }
                clusters[#clusters + 1] = c
                if not d.solo then
                    local key = gx * 100003 + gy
                    grid[key] = grid[key] or {}
                    table.insert(grid[key], c)
                end
            end
        end
        return clusters
    end

    function v:LayoutDots()
        local cw, ch = self:CanvasSize()
        local clusters = Cluster(self.data, cw, ch)
        self.targetHasDot = false
        for i, c in ipairs(clusters) do
            local b = self.dots[i]
            if not b then b = NewDot(); self.dots[i] = b end
            local x, y = c.px / c.n, c.py / c.n
            local allDim, anyHot = true, false
            for _, d in ipairs(c.items) do
                if not d.dim then allDim = false end
                if d.hot then anyHot = true end
            end
            local swords = c.n > 1
            for _, d in ipairs(c.items) do if not d.noCount then swords = false end end
            if swords then
                -- found creatures: the grouped swords show no number
                b:SetLook("ring", ICON_D)
                b.pic:SetTexture(c.items[1].icon)
                b.pic:Show()
                b.fill:Hide()
                b.num:SetText("")
                b:SetParts(nil)
                b:SetBadge(nil)
                b.members, b.cu, b.cv = c.items, x / cw, y / ch
                b.title, b.spot = nil, nil
            elseif c.n > 1 then
                -- a combined place: the pictures of what is in it (the most frequent first), and how many
                local order, count = {}, {}
                for _, d in ipairs(c.items) do
                    local key = d.icon or (d.color[1] .. ":" .. d.color[2] .. ":" .. d.color[3])
                    if not count[key] then
                        count[key] = 0
                        order[#order + 1] = { key = key, icon = d.icon, color = d.color }
                    end
                    count[key] = count[key] + 1
                end
                table.sort(order, function(p, q)
                    if count[p.key] ~= count[q.key] then return count[p.key] > count[q.key] end
                    return p.key < q.key
                end)
                b:SetLook("ring", ICON_D)
                b.num:SetText("")
                if #order == 1 then
                    b:SetParts(nil)
                    if order[1].icon then
                        b.pic:SetTexture(order[1].icon)
                        b.pic:Show()
                        b.fill:Hide()
                    else
                        b.pic:Hide()
                        b.fill:Show()
                        b.fill:SetColorTexture(order[1].color[1], order[1].color[2], order[1].color[3], 1)
                    end
                else
                    b.pic:Hide()
                    b.fill:Hide()
                    b:SetParts(order)
                end
                b:SetBadge(c.n)
                b.members, b.cu, b.cv = c.items, x / cw, y / ch
                b.title, b.spot = nil, nil
            else
                local d = c.items[1]
                b.members = nil
                b.num:SetText("")
                b:SetParts(nil)
                b:SetBadge(nil)
                if d.icon then
                    b:SetLook("ring", ICON_D)
                    b.pic:SetTexture(d.icon)
                    b.pic:Show()
                    b.fill:Hide()
                else
                    b:SetLook("plain", DOT)
                    b.pic:Hide()
                    b.fill:Show()
                    b.fill:SetColorTexture(d.color[1], d.color[2], d.color[3], 1)
                end
                b.title, b.sub, b.n, b.spot, b.zone = d.title, d.sub, d.n, d.spot, d.zone
                b.node = d.node
                b.last, b.lastLabel = d.last, d.lastLabel
            end
            local guiding = c.n == 1 and c.items[1].spot and ns.Routes and ns.Routes.IsTarget(c.items[1].spot)
            if guiding then self.targetHasDot = true end
            b:SetPulse(anyHot or guiding)
            b:SetAlpha((allDim and 0.28 or 1) * ns.MapOpacity())
            b:ClearAllPoints()
            b:SetPoint("CENTER", canvas, "TOPLEFT", x, -y)
            b:Show()
        end
        for i = #clusters + 1, #self.dots do self.dots[i]:Hide() end
    end

    -- zoom in on a spot of the map (0..1 coordinates) and centre it
    function v:ZoomToPoint(u, w, factor)
        if not self.baseW then return end
        self.zoom = Clamp(self.zoom * factor, 1, MAX_ZOOM)
        self:Apply()
        local cw, ch = self:CanvasSize()
        sf:SetHorizontalScroll(Clamp(u * cw - self.viewW / 2, 0, math.max(0, cw - self.viewW)))
        sf:SetVerticalScroll(Clamp(w * ch - self.viewH / 2, 0, math.max(0, ch - self.viewH)))
    end

    -- faint round layers from wide to narrow, added up: a soft cloud with no hard edge
    local HEAT_LAYERS = 6
    local HEAT_SIZE = { 1, 0.84, 0.68, 0.52, 0.38, 0.25 }
    local HEAT_COLOR = {
        { 0.80, 0.22, 0.10 }, { 0.88, 0.30, 0.10 }, { 0.95, 0.42, 0.12 },
        { 1.00, 0.55, 0.16 }, { 1.00, 0.68, 0.24 }, { 1.00, 0.82, 0.40 },
    }
    function v:LayoutHeat()
        local cw, ch = self:CanvasSize()
        -- an area, not a place: wide, and still wide when you zoom in
        local base = cw * 0.11 / math.max(1, self.zoom) ^ 0.3
        local max = 0
        for _, h in ipairs(self.heat) do max = math.max(max, h.w) end
        for i, h in ipairs(self.heat) do
            local set = self.heatTex[i]
            if not set then
                set = {}
                for k = 1, HEAT_LAYERS do
                    local t = heatFrame:CreateTexture(nil, "ARTWORK")
                    t:SetTexture(BLOB)
                    t:SetBlendMode("ADD")
                    set[k] = t
                end
                self.heatTex[i] = set
            end
            local t = math.sqrt(h.w / math.max(1, max))
            local fade = (h.dim and 0.3 or 1) * ns.MapOpacity()
            for k = 1, HEAT_LAYERS do
                local tex = set[k]
                local c = HEAT_COLOR[k]
                tex:SetVertexColor(c[1], c[2], c[3], (0.012 + 0.03 * t) * fade)
                tex:ClearAllPoints()
                tex:SetPoint("CENTER", canvas, "TOPLEFT", h.x * cw, -h.y * ch)
                local size = base * HEAT_SIZE[k] * (0.8 + 0.4 * t)
                tex:SetSize(size, size)
                tex:Show()
            end
        end
        for i = #self.heat + 1, #self.heatTex do
            for k = 1, HEAT_LAYERS do self.heatTex[i][k]:Hide() end
        end
    end

    function v:SetHeat(list)
        self.heat = list or {}
        if self.baseW then self:LayoutHeat() end
    end

    function v:ClampScroll()
        local cw, ch = self:CanvasSize()
        sf:SetHorizontalScroll(Clamp(sf:GetHorizontalScroll(), 0, math.max(0, cw - self.viewW)))
        sf:SetVerticalScroll(Clamp(sf:GetVerticalScroll(), 0, math.max(0, ch - self.viewH)))
    end

    function v:Apply()
        local cw, ch = self:CanvasSize()
        canvas:SetSize(cw, ch)
        self:LayoutTiles()
        self:LayoutOverlays()
        self:LayoutHeat()
        self:LayoutDots()
        self:ClampScroll()
        if self.UpdateOverlay then self:UpdateOverlay() end
        self.zoomText:SetText(self.zoom > 1.01 and string.format("×%.1f", self.zoom) or "")
    end

    -- The view fills the whole area it may use. The picture (baseW x baseH at zoom 1) keeps
    -- its aspect ratio and covers the view; what sticks out is reached by moving it.
    function v:Fit()
        local vw, vh = math.max(40, math.floor(self.availW)), math.max(30, math.floor(self.availH))
        local bw = math.max(vw, vh * self.aspect)
        local bh = bw / self.aspect
        if vw ~= self.viewW or vh ~= self.viewH or bw ~= self.baseW or bh ~= self.baseH then
            self.viewW, self.viewH = vw, vh
            self.baseW, self.baseH = bw, bh
            sf:SetSize(vw, vh)
            self:Apply()
        end
    end

    -- centre the picture in the view (at zoom 1 one side usually sticks out)
    function v:CenterView()
        local cw, ch = self:CanvasSize()
        sf:SetHorizontalScroll(math.max(0, (cw - self.viewW) / 2))
        sf:SetVerticalScroll(math.max(0, (ch - self.viewH) / 2))
    end

    function v:SetArea(w, h)
        if w == self.availW and h == self.availH and self.baseW then return end
        self.availW, self.availH = w, h
        self:Fit()
    end

    function v:SetMap(mapID)
        for _, t in ipairs(self.tiles) do t:Hide() end
        self.tileInfo = nil
        local keep = self.mapID == mapID
        local keepH, keepV = sf:GetHorizontalScroll(), sf:GetVerticalScroll()
        if keep then
            -- same map: nothing changes
        else
            local here, px, py = ns.PlayerPos()
            if here == mapID then
                local w = ns.WorldSize(mapID)
                self.zoom = Clamp(w / 700, 2, 8)
                self.startAt = { px, py }
            else
                self.zoom = 1
                self.startAt = nil
            end
            keepH, keepV = 0, 0
        end
        sf:SetHorizontalScroll(0)
        sf:SetVerticalScroll(0)
        local ok, layers = pcall(C_Map.GetMapArtLayers, mapID)
        local info = ok and layers and layers[1]
        local ok2, files = pcall(C_Map.GetMapArtLayerTextures, mapID, 1)
        if info and ok2 and type(files) == "table" and #files > 0 then
            self.aspect = info.layerWidth / info.layerHeight
            self.layerInfo = { lw = info.layerWidth, lh = info.layerHeight, tw = info.tileWidth, th = info.tileHeight }
            self.tileInfo = { files = files, lw = info.layerWidth, lh = info.layerHeight,
                tw = info.tileWidth, th = info.tileHeight, cols = math.ceil(info.layerWidth / info.tileWidth) }
            for i, file in ipairs(files) do
                local tex = self.tiles[i]
                if not tex then
                    tex = canvas:CreateTexture(nil, "ARTWORK")
                    self.tiles[i] = tex
                end
                tex:SetTexture(file)
                local col, row = (i - 1) % self.tileInfo.cols, math.floor((i - 1) / self.tileInfo.cols)
                local w = math.min(info.tileWidth, info.layerWidth - col * info.tileWidth)
                local h = math.min(info.tileHeight, info.layerHeight - row * info.tileHeight)
                tex:SetTexCoord(0, w / info.tileWidth, 0, h / info.tileHeight)
                tex:Show()
            end
            self.note:SetText("")
        else
            self.note:SetText(L["The map picture is not available; spots are shown on a plain field."])
        end
        self.mapID = mapID
        if not self.tileInfo then self.layerInfo = nil end
        self:BuildOverlays(mapID)
        self.baseW = nil -- refit: the aspect may have changed
        self:Fit()
        self:Apply()
        if keep then
            sf:SetHorizontalScroll(keepH)
            sf:SetVerticalScroll(keepV)
            self:ClampScroll()
        elseif self.startAt and self.zoom > 1 then
            -- open centred on you
            local cw, ch = self:CanvasSize()
            sf:SetHorizontalScroll(Clamp(self.startAt[1] * cw - self.viewW / 2, 0, math.max(0, cw - self.viewW)))
            sf:SetVerticalScroll(Clamp(self.startAt[2] * ch - self.viewH / 2, 0, math.max(0, ch - self.viewH)))
        else
            self:CenterView()
        end
    end

    function v:SetDots(list)
        if self.revealShown ~= (ns.db.settings.mapReveal ~= false) then self:LayoutOverlays() end
        local d = ns.MapDim()
        if d < 0 then
            self.shade:SetBlendMode("ADD")
            self.shade:SetColorTexture(1, 0.96, 0.9, -d)
        else
            self.shade:SetBlendMode("BLEND")
            self.shade:SetColorTexture(0.03, 0.025, 0.02, d)
        end
        self.data = list
        self:LayoutDots()
    end

    function v:ResetZoom()
        self.zoom = 1
        self:Apply()
        self:CenterView()
    end

    -- zoom around the cursor, so the point under it stays put ---------------------
    local function Cursor()
        local x, y = GetCursorPosition()
        local s = sf:GetEffectiveScale()
        return x / s - sf:GetLeft(), sf:GetTop() - y / s
    end

    function v:ZoomAt(factor)
        if not self.baseW then return end
        local cx, cy = Cursor()
        local cw, ch = self:CanvasSize()
        local u = (sf:GetHorizontalScroll() + cx) / cw
        local w = (sf:GetVerticalScroll() + cy) / ch
        self.zoom = Clamp(self.zoom * factor, 1, MAX_ZOOM)
        self:Apply()
        local ncw, nch = self:CanvasSize()
        sf:SetHorizontalScroll(Clamp(u * ncw - cx, 0, math.max(0, ncw - self.viewW)))
        sf:SetVerticalScroll(Clamp(w * nch - cy, 0, math.max(0, nch - self.viewH)))
    end

    sf:SetScript("OnMouseWheel", function(_, delta)
    -- the wheel also reaches windows that are covered by another one: only the one on top scrolls
        if not W.TopFrameIs(sf) then return end
        v:ZoomAt(delta > 0 and 1.3 or 1 / 1.3)
    end)

    -- drag to pan
    local drag
    sf:SetScript("OnMouseDown", function(_, button)
        if button == "LeftButton" and not v.noPan then
            local x, y = GetCursorPosition()
            drag = { x = x, y = y, h = sf:GetHorizontalScroll(), v = sf:GetVerticalScroll() }
        end
    end)
    sf:SetScript("OnMouseUp", function() drag = nil end)
    sf:SetScript("OnHide", function() drag = nil end)

    -- the player marker and the drag, throttled
    local acc = 0
    local function Facing()
        if not GetPlayerFacing then return nil end
        local ok, f = pcall(GetPlayerFacing)
        return ok and ns.ReadableNumber(f) or nil
    end
    -- you, and the line to the place the arrow leads to
    function v:UpdateOverlay()
        if not self.baseW then return end
        local open = ns.MapWindow and ns.MapWindow.IsShown()
        self.popBtn:SetBackdropBorderColor(unpack(open and C.gold or C.goldDim))
        local mapID, px, py = ns.PlayerPos()
        local cw, ch = self:CanvasSize()
        local here = mapID and mapID == self.mapID
        self.meX, self.meY = nil, nil
        if here then
            self.meX, self.meY = px * cw, py * ch
            me:ClearAllPoints()
            me:SetPoint("CENTER", canvas, "TOPLEFT", px * cw, -py * ch)
            local f = Facing()
            if f then me.tex:SetRotation(f) end
            me:Show()
        else
            me:Hide()
        end

        local target = ns.Routes and ns.Routes.Target and ns.Routes.Target()
        if target and target.map == self.mapID then
            -- where a marker stands, the marker itself breathes; elsewhere a small dot marks the goal
            goal:ClearAllPoints()
            goal:SetPoint("CENTER", canvas, "TOPLEFT", target.x * cw, -target.y * ch)
            goal:SetShown(not self.targetHasDot)
            if pathLine and here then
                for _, ln in ipairs({ pathShadow, pathLine }) do
                    ln:SetStartPoint("TOPLEFT", canvas, px * cw, -py * ch)
                    ln:SetEndPoint("TOPLEFT", canvas, target.x * cw, -target.y * ch)
                    ln:Show()
                end
            elseif pathLine then
                pathLine:Hide()
                pathShadow:Hide()
            end
        else
            goal:Hide()
            if pathLine then pathLine:Hide(); pathShadow:Hide() end
        end

        -- the way ahead: the points after the current one, joined by faint lines
        self.routeLines, self.routeShadows = self.routeLines or {}, self.routeShadows or {}
        local ahead = (ns.Routes and ns.Routes.Upcoming and ns.Routes.Upcoming()) or {}
        local drawn = 0
        if canvas.CreateLine then
            for i = 1, #ahead - 1 do
                local a, b = ahead[i], ahead[i + 1]
                if a.map == self.mapID and b.map == self.mapID then
                    drawn = drawn + 1
                    local ln, sh = self.routeLines[drawn], self.routeShadows[drawn]
                    if not ln then
                        sh = canvas:CreateLine(nil, "ARTWORK", nil, 1)
                        sh:SetThickness(6)
                        sh:SetColorTexture(0, 0, 0, 0.4)
                        ln = canvas:CreateLine(nil, "ARTWORK", nil, 2)
                        ln:SetThickness(3)
                        ln:SetColorTexture(1, 0.84, 0.38, 0.8)
                        self.routeLines[drawn], self.routeShadows[drawn] = ln, sh
                    end
                    for _, line in ipairs({ sh, ln }) do
                        line:SetStartPoint("TOPLEFT", canvas, a.x * cw, -a.y * ch)
                        line:SetEndPoint("TOPLEFT", canvas, b.x * cw, -b.y * ch)
                        line:Show()
                    end
                end
            end
        end
        for i = drawn + 1, #self.routeLines do self.routeLines[i]:Hide(); self.routeShadows[i]:Hide() end

        self.cancelBtn:SetShown((ns.Routes and ns.Routes.Target and ns.Routes.Target()) ~= nil)
    end

    sf:SetScript("OnUpdate", function(_, dt)
        if drag then
            local x, y = GetCursorPosition()
            local s = sf:GetEffectiveScale()
            sf:SetHorizontalScroll(Clamp(drag.h - (x - drag.x) / s, 0, math.max(0, canvas:GetWidth() - v.viewW)))
            sf:SetVerticalScroll(Clamp(drag.v + (y - drag.y) / s, 0, math.max(0, canvas:GetHeight() - v.viewH)))
            -- moving the map by hand ends following
            if ns.MapFollowOn() and math.abs(x - drag.x) + math.abs(y - drag.y) > 8 then
                ns.MapSetFollow(false)
                ns.Refresh()
            end
        elseif v.meX and v.baseW and ns.db and (v.alwaysFollow or ns.MapFollowOn()) then
            -- follow: ease the view so you stay in the middle (as far as the zoom allows)
            local cw, ch = v:CanvasSize()
            local tx = Clamp(v.meX - v.viewW / 2, 0, math.max(0, cw - v.viewW))
            local ty = Clamp(v.meY - v.viewH / 2, 0, math.max(0, ch - v.viewH))
            local k = math.min(1, dt * 6)
            local hx, hy = sf:GetHorizontalScroll(), sf:GetVerticalScroll()
            sf:SetHorizontalScroll(hx + (tx - hx) * k)
            sf:SetVerticalScroll(hy + (ty - hy) * k)
        end
        -- a slow pulse around you and the goal
        local k = 0.5 + 0.5 * math.sin(GetTime() * 2.4)
        if me:IsShown() then me.pulse:SetSize(18 + 10 * k, 18 + 10 * k); me.pulse:SetAlpha(0.2 - 0.14 * k) end
        W.PulseMarkers(v.dots)
        acc = acc + dt
        if acc < 0.15 then return end
        acc = 0
        v:UpdateOverlay()
    end)

    -- make sure the map is zoomed in at least this far
    function v:ZoomAtLeast(z)
        if self.zoom < z then
            self.zoom = Clamp(z, 1, MAX_ZOOM)
            self:Apply()
        end
    end

    function v:Show() sf:Show(); border:Show() end
    function v:Hide() sf:Hide(); border:Hide(); self.note:SetText("") end

    return v
end
