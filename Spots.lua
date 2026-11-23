local ADDON, ns = ...
local L = ns.L
local W = ns.W

-- Spots: where creatures were killed and where herbs, veins and chests were
-- looted. Every source remembers its places (clustered, see Core's RecordSpot).
-- From those we draw pins on the world map, lead you to the nearest place and
-- build routes through all of them.

local Spots = {}
ns.Spots = Spots

local sqrt = math.sqrt

function Spots.Count(gm)
    local n = 0
    if gm and gm.spots then for _ in pairs(gm.spots) do n = n + 1 end end
    return n
end

-- the spots of a source on one map (nil = all maps)
function Spots.List(gm, mapID)
    local list = {}
    if gm and gm.spots then
        for _, sp in pairs(gm.spots) do
            if not mapID or sp.m == mapID then list[#list + 1] = sp end
        end
    end
    return list
end

local function Dist(a, b, w, h)
    local dx, dy = (a.x - b.x) * w, (a.y - b.y) * h
    return sqrt(dx * dx + dy * dy)
end

-- The spot of a source closest to the player (same map first, else any).
function Spots.Nearest(gm)
    local mapID, x, y = ns.PlayerPos()
    local here = mapID and Spots.List(gm, mapID) or {}
    local pool = #here > 0 and here or Spots.List(gm)
    if #pool == 0 then return nil end
    if not mapID or #here == 0 then return pool[1], nil end
    local w, h = ns.WorldSize(mapID)
    local me = { x = x, y = y }
    local best, bestD
    for _, sp in ipairs(pool) do
        local d = Dist(sp, me, w, h)
        if not bestD or d < bestD then best, bestD = sp, d end
    end
    return best, bestD
end

-- Nearest-neighbour order from the player, then 2-opt to remove crossings.
local function Order(points, start, w, h)
    local remaining = {}
    for i, p in ipairs(points) do remaining[i] = p end
    local path = { start }
    while #remaining > 0 do
        local cur = path[#path]
        local bi, bd
        for i, p in ipairs(remaining) do
            local d = Dist(cur, p, w, h)
            if not bd or d < bd then bi, bd = i, d end
        end
        path[#path + 1] = table.remove(remaining, bi)
    end
    for _ = 1, 4 do
        local improved = false
        for i = 1, #path - 2 do
            for j = i + 1, #path do
                local a, b, c, nxt = path[i], path[i + 1], path[j], path[j + 1]
                local before = Dist(a, b, w, h) + (nxt and Dist(c, nxt, w, h) or 0)
                local after = Dist(a, c, w, h) + (nxt and Dist(b, nxt, w, h) or 0)
                if after + 0.001 < before then
                    local lo, hi = i + 1, j
                    while lo < hi do
                        path[lo], path[hi] = path[hi], path[lo]
                        lo, hi = lo + 1, hi - 1
                    end
                    improved = true
                end
            end
        end
        if not improved then break end
    end
    table.remove(path, 1)
    return path
end

-- A route through every saved spot of the given sources on the current map.
-- Returns the route, or nil and a reason.
function Spots.MakeRoute(keys, name)
    local mapID, x, y = ns.PlayerPos()
    if not mapID then return nil, L["No position available here."] end
    local points = {}
    for _, key in ipairs(keys) do
        local gm = ns.db.mobs[key]
        for _, sp in ipairs(Spots.List(gm, mapID)) do
            points[#points + 1] = { x = sp.x, y = sp.y, zone = gm.zone, key = key, name = gm.name }
        end
    end
    if #points == 0 then return nil, L["No saved spots yet."] end
    local w, h = ns.WorldSize(mapID)
    local ordered = Order(points, { x = x, y = y }, w, h)
    local out = {}
    for _, p in ipairs(ordered) do
        out[#out + 1] = { map = mapID, x = p.x, y = p.y, zone = p.zone or GetZoneText(), key = p.key, name = p.name }
    end
    return ns.Routes.Create(name, out), #out
end

-- Respawn and planning ------------------------------------------------------------
-- How long a plant or vein takes to come back, from the times the same place was looted:
-- every gap between two loots is an upper bound, so the lower quarter of them is used.
-- Without such gaps a typical time stands in.

local DEFAULT_RESPAWN = { herb = 600, ore = 600, object = 900 }
local RUN_SPEED = 11 -- yards per second, a typical mount

function Spots.Respawn(gm)
    local gaps = {}
    for _, sp in pairs(gm.spots or {}) do
        local ts = sp.ts
        if ts then
            for i = 2, #ts do
                local gap = ts[i] - ts[i - 1]
                if gap >= 120 and gap <= 7200 then gaps[#gaps + 1] = gap end
            end
        end
    end
    if #gaps >= 2 then
        table.sort(gaps)
        return gaps[math.max(1, math.ceil(#gaps * 0.25))], #gaps
    end
    return DEFAULT_RESPAWN[gm.cat] or 600, 0
end

-- A lap through the spots of these sources on the map the player is on, nearest first with
-- crossings removed. opts.onlyReady leaves out spots that were looted too recently to be back.
-- Returns the plan, or nil and the reason.
function Spots.Plan(keys, opts)
    opts = opts or {}
    local mapID, x, y = ns.PlayerPos()
    if not mapID then return nil, L["No position available here."] end
    local w, h = ns.WorldSize(mapID)
    local points, minRespawn, basis = {}, nil, 0
    local now = time()
    for _, key in ipairs(keys) do
        local gm = ns.db.mobs[key]
        if gm then
            local respawn, n = Spots.Respawn(gm)
            if not minRespawn or respawn < minRespawn then minRespawn, basis = respawn, n end
            for _, sp in ipairs(Spots.List(gm, mapID)) do
                local since = sp.t and (now - sp.t) or nil
                local ready = (not since) or since >= respawn * 0.9
                if ready or not opts.onlyReady then
                    points[#points + 1] = { x = sp.x, y = sp.y, gm = gm, sp = sp, ready = ready, zone = gm.zone, key = key, name = gm.name,
                        wait = (not ready) and (respawn - since) or 0 }
                end
            end
        end
    end
    if #points == 0 then return nil, L["No saved spots yet."] end
    local ordered = Order(points, { x = x, y = y }, w, h)
    local dist, prev, ready = 0, { x = x, y = y }, 0
    for _, p in ipairs(ordered) do
        p.leg = Dist(prev, p, w, h)
        dist = dist + p.leg
        prev = p
        if p.ready then ready = ready + 1 end
    end
    local back = Dist(prev, ordered[1], w, h)
    local loop = dist + back
    return { points = ordered, mapID = mapID, dist = dist, loop = loop, ready = ready,
        lapTime = loop / RUN_SPEED + #ordered * 4, minRespawn = minRespawn or 600, basis = basis }
end

function Spots.CreateRoute(plan, name)
    local out = {}
    for _, p in ipairs(plan.points) do
        out[#out + 1] = { map = plan.mapID, x = p.x, y = p.y, zone = p.zone or GetZoneText(), key = p.key, name = p.name }
    end
    return ns.Routes.Create(name, out)
end

-- World map pins ---------------------------------------------------------------

function Spots.IsPinned(key) return ns.db.pins and ns.db.pins[key] or false end
function Spots.TogglePin(key)
    ns.db.pins = ns.db.pins or {}
    if ns.db.pins[key] then ns.db.pins[key] = nil else ns.db.pins[key] = true end
    Spots.RefreshMap()
end

local overlay
local pins = {}

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
    overlay:SetFrameLevel(canvas:GetFrameLevel() + 60)
    overlay:SetScript("OnSizeChanged", function() Spots.RefreshMap() end)
    return overlay
end

local function NewPin(parent)
    local b = CreateFrame("Button", nil, parent)
    b.edge = b:CreateTexture(nil, "BACKGROUND")
    b.edge:SetAllPoints()
    b.tex = b:CreateTexture(nil, "ARTWORK")
    b.tex:SetPoint("TOPLEFT", 1, -1)
    b.tex:SetPoint("BOTTOMRIGHT", -1, 1)
    b.tex:SetTexCoord(0.07, 0.93, 0.07, 0.93)
    b:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:AddLine(self.title or "", 1, 0.85, 0.4)
        GameTooltip:AddLine(L["Seen %d times"]:format(self.count or 1), 0.8, 0.8, 0.8)
        GameTooltip:Show()
    end)
    b:SetScript("OnLeave", function() GameTooltip:Hide() end)
    return b
end

function Spots.RefreshMap()
    if not (ns.db and WorldMapFrame and WorldMapFrame:IsShown()) then return end
    local o = Ensure()
    if not o then return end
    local mapID = WorldMapFrame.GetMapID and WorldMapFrame:GetMapID()
    local w, h = o:GetWidth(), o:GetHeight()
    local scale = 1
    local sc = WorldMapFrame.ScrollContainer
    if sc and sc.GetCanvasScale then
        local ok, s = pcall(sc.GetCanvasScale, sc)
        if ok and type(s) == "number" and s > 0 then scale = s end
    end
    local n = 0
    for key in pairs(ns.db.pins or {}) do
        local gm = ns.db.mobs[key]
        if gm and gm.spots and ns.CatOn(gm.cat) then
            local cat = ns.CAT[gm.cat]
            for _, sp in pairs(gm.spots) do
                if sp.m == mapID then
                    n = n + 1
                    local pin = pins[n]
                    if not pin then pin = NewPin(o); pins[n] = pin end
                    pin:SetSize(16 / scale, 16 / scale)
                    pin.tex:SetTexture(cat.icon)
                    pin.edge:SetColorTexture(cat.color[1], cat.color[2], cat.color[3], 1)
                    pin.title, pin.count = gm.name or key, sp.n
                    pin:ClearAllPoints()
                    pin:SetPoint("CENTER", o, "TOPLEFT", sp.x * w, -sp.y * h)
                    pin:Show()
                end
            end
        end
    end
    for i = n + 1, #pins do pins[i]:Hide() end
end

local watcher = CreateFrame("Frame")
watcher:RegisterEvent("PLAYER_LOGIN")
watcher:SetScript("OnEvent", function()
    if WorldMapFrame then
        if WorldMapFrame.OnMapChanged then hooksecurefunc(WorldMapFrame, "OnMapChanged", Spots.RefreshMap) end
        WorldMapFrame:HookScript("OnShow", Spots.RefreshMap)
    end
end)
-- zooming changes the canvas scale without a map change: check twice a second while open
local acc = 0
watcher:SetScript("OnUpdate", function(_, dt)
    acc = acc + dt
    if acc < 0.5 then return end
    acc = 0
    if WorldMapFrame and WorldMapFrame:IsShown() and ns.db and next(ns.db.pins or {}) then Spots.RefreshMap() end
end)

-- Minimap pins -------------------------------------------------------------------
-- The same picture as the map pages, with the same filter: round icons for plants
-- and veins, a heat glow for creatures, and a line to the place the arrow leads to.
-- Everything is placed from the player's offset in yards. The minimap shows a fixed
-- number of yards per zoom level (indoors and outdoors differ) and may be rotated
-- with the player; both are accounted for.

local MM_OUTDOOR = { [0] = 466.67, 400, 333.33, 266.67, 200, 133.33 }
local MM_INDOOR = { [0] = 300, 240, 180, 120, 80, 50 }
local MM_MAX_PINS = 120
local MM_MAX_HEAT = 50
local BLOB = "Interface\\CharacterFrame\\TempPortraitAlphaMask"
local HEAT_SIZE = { 1, 0.62, 0.3 }
local HEAT_COLOR = { { 0.85, 0.16, 0.1 }, { 1, 0.5, 0.14 }, { 1, 0.86, 0.45 } }

local mmPins, mmHeat = {}, {}
local holder, pathLine, goal

local function Holder()
    if holder then return holder end
    holder = CreateFrame("Frame", nil, Minimap)
    holder:SetAllPoints(Minimap)
    holder:SetFrameLevel(Minimap:GetFrameLevel() + 10)
    if holder.CreateLine then
        pathLine = holder:CreateLine(nil, "ARTWORK", nil, 3)
        pathLine:SetThickness(2)
        pathLine:SetColorTexture(W.C.gold[1], W.C.gold[2], W.C.gold[3], 0.85)
        pathLine:Hide()
    end
    goal = CreateFrame("Frame", nil, Minimap)
    goal:SetFrameLevel(Minimap:GetFrameLevel() + 13)
    goal:SetSize(7, 7)
    goal.edge = goal:CreateTexture(nil, "ARTWORK")
    goal.edge:SetTexture(BLOB)
    goal.edge:SetAllPoints()
    goal.edge:SetVertexColor(0, 0, 0, 0.8)
    goal.core = goal:CreateTexture(nil, "OVERLAY")
    goal.core:SetTexture(BLOB)
    goal.core:SetSize(5, 5)
    goal.core:SetPoint("CENTER")
    goal.core:SetVertexColor(W.C.gold[1], W.C.gold[2], W.C.gold[3], 1)
    goal:Hide()
    return holder
end

local function NewMinimapPin()
    local b = W.NewMapMarker(Minimap)
    b:SetFrameLevel(Minimap:GetFrameLevel() + 12)
    -- a pin: the marker floats just above the spot, so the game's own blip at the spot
    -- (herb or mineral search) stays visible, joined to it by a short stem
    b.tail = b:CreateTexture(nil, "ARTWORK")
    b.tail:SetSize(2, 10)
    b.tail:SetPoint("TOP", b, "BOTTOM", 0, 1)
    b.tail:SetColorTexture(0.9, 0.9, 0.9, 0.35) -- a quiet neutral line, not gold
    b:SetScript("OnEnter", function(self)
        W.Ease(self, "hv", 1, 14, function(o, val) o:SetGrow(val) end)
        GameTooltip:SetOwner(self, "ANCHOR_LEFT")
        -- a plant or a vein: its tooltip as in the world (name, then the lines of the settings); the rest as before
        local named = self.key and self.node and ns.TipNodeFor and ns.TipNodeFor(GameTooltip, self.key, self.spot)
        if not named then
            GameTooltip:AddLine(self.title or "", 1, 0.85, 0.4)
            if self.sub then GameTooltip:AddLine(self.sub, 0.6, 0.6, 0.6) end
            if self.count and self.count > 1 then
                GameTooltip:AddLine((self.node and L["Looted %d times"] or L["Seen %d times"]):format(self.count), 0.8, 0.8, 0.8)
            end
            GameTooltip:AddDoubleLine(self.lastLabel or L["Last used"], ns.Ago(self.last), 0.8, 0.8, 0.8, 1, 1, 1)
        end
        local away = ns.SpotDistance(self.spot)
        if away then GameTooltip:AddDoubleLine(L["Distance"], away .. " " .. L["yd"], 0.8, 0.8, 0.8, 1, 1, 1) end
        GameTooltip:Show()
    end)
    b:SetScript("OnLeave", function(self)
        W.Ease(self, "hv", 0, 14, function(o, val) o:SetGrow(val) end)
        GameTooltip:Hide()
    end)
    return b
end

-- The glow of the pins: resources close to the player sparkle (a turning star, rings that go out, a halo), the closer the stronger. How
-- far, how strong and whether all of them sparkle a little is set in the settings (map page). Drawn by the watcher below, every frame.
local STAR = "Interface\\Cooldown\\star4"
local RING = "Interface\\Cooldown\\ping4"
local HALO = "Interface\\Buttons\\UI-ActionButton-Border"
local FX_STYLES = {
    -- star size, star alpha, rings, halo size (0: none), speed
    subtle = { star = 24, alpha = 0.6, rings = 0, halo = 0, speed = 0.6 },
    strong = { star = 38, alpha = 0.95, rings = 1, halo = 40, speed = 1 },
    maximum = { star = 58, alpha = 1, rings = 2, halo = 64, speed = 1.6 },
}

local function FxOf(pin)
    local fx = pin.fx
    if fx then return fx end
    fx = {}
    fx.halo = pin:CreateTexture(nil, "OVERLAY", nil, 5)
    fx.halo:SetTexture(HALO)
    fx.halo:SetBlendMode("ADD")
    fx.halo:SetVertexColor(1, 0.8, 0.35)
    fx.star = pin:CreateTexture(nil, "OVERLAY", nil, 6)
    fx.star:SetTexture(STAR)
    fx.star:SetBlendMode("ADD")
    fx.star:SetVertexColor(1, 0.93, 0.6)
    fx.star2 = pin:CreateTexture(nil, "OVERLAY", nil, 6)
    fx.star2:SetTexture(STAR)
    fx.star2:SetBlendMode("ADD")
    fx.star2:SetVertexColor(1, 1, 0.9)
    fx.rings = {}
    for i = 1, 2 do
        local r = pin:CreateTexture(nil, "OVERLAY", nil, 4)
        r:SetTexture(RING)
        r:SetBlendMode("ADD")
        r:SetVertexColor(1, 0.85, 0.4)
        fx.rings[i] = r
    end
    pin.fx = fx
    return fx
end

local function HideFx(pin)
    local fx = pin.fx
    if not fx then return end
    fx.halo:Hide(); fx.star:Hide(); fx.star2:Hide()
    for _, r in ipairs(fx.rings) do r:Hide() end
end

local function DrawFx(pin, t)
    local level = pin.fxLevel or 0
    if level <= 0 or not pin:IsShown() then HideFx(pin) return end
    local st = FX_STYLES[pin.fxStyle or "strong"] or FX_STYLES.strong
    local fx = FxOf(pin)
    local near = math.min(level, 2) -- 0.5 (quiet, far) to 2 (right here)
    local k = near * ((level < 1) and 1 or 0.75)
    local pulse = 0.65 + 0.35 * math.sin(t * 3.2 * st.speed + (pin.fxPhase or 0))
    -- the star: turns, and a second one turns the other way
    local size = st.star * k
    fx.star:SetSize(size, size)
    fx.star:SetRotation(t * 0.9 * st.speed)
    fx.star:SetAlpha(math.min(1, st.alpha * pulse))
    fx.star:ClearAllPoints(); fx.star:SetPoint("CENTER", pin, "CENTER", 0, 0)
    fx.star:Show()
    fx.star2:SetSize(size * 0.7, size * 0.7)
    fx.star2:SetRotation(-t * 1.4 * st.speed + 0.8)
    fx.star2:SetAlpha(math.min(1, st.alpha * (1.3 - pulse)))
    fx.star2:ClearAllPoints(); fx.star2:SetPoint("CENTER", pin, "CENTER", 0, 0)
    fx.star2:SetShown(st.rings > 0)
    if st.halo > 0 then
        local hs = st.halo * k * (0.85 + 0.3 * pulse)
        fx.halo:SetSize(hs, hs)
        fx.halo:SetAlpha(math.min(1, 0.55 * near))
        fx.halo:ClearAllPoints(); fx.halo:SetPoint("CENTER", pin, "CENTER", 0, 0)
        fx.halo:Show()
    else
        fx.halo:Hide()
    end
    for i, r in ipairs(fx.rings) do
        if i <= st.rings then
            local phase = (t * 0.7 * st.speed + (i - 1) * 0.5) % 1
            local rs = (10 + phase * 46) * k
            r:SetSize(rs, rs)
            r:SetAlpha((1 - phase) * 0.9)
            r:ClearAllPoints(); r:SetPoint("CENTER", pin, "CENTER", 0, 0)
            r:Show()
        else
            r:Hide()
        end
    end
end

local function NewHeatSet()
    local set = {}
    for k = 1, 3 do
        local t = holder:CreateTexture(nil, "ARTWORK")
        t:SetTexture(BLOB)
        t:SetBlendMode("ADD")
        set[k] = t
    end
    return set
end

local function HideMinimapStuff()
    for i = 1, #mmPins do mmPins[i]:Hide() end
    for i = 1, #mmHeat do for k = 1, 3 do mmHeat[i][k]:Hide() end end
    if pathLine then pathLine:Hide() end
    if goal then goal:Hide() end
end

local function Facing()
    if not GetPlayerFacing then return nil end
    local ok, f = pcall(GetPlayerFacing)
    return ok and ns.ReadableNumber(f) or nil
end

-- the zone's data is rebuilt when the filter changes, the zone changes, or every 2 s
local cache = {}
local function ZoneData(mapID)
    local now = GetTime()
    if cache.data and cache.map == mapID and cache.version == ns.mapVersion and now - cache.at < 2 then return cache.data end
    local data = ns.MapData(mapID, "all", ns.mapQuery, true) -- creatures as dots here: heat would spill over the minimap's edge
    local max = 0
    for _, hc in ipairs(data.heat) do max = math.max(max, hc.w) end
    data.maxHeat = max
    cache.data, cache.map, cache.version, cache.at = data, mapID, ns.mapVersion, now
    return data
end

function Spots.RefreshMinimap()
    if not (ns.db and Minimap and Minimap:IsVisible() and ns.MapMinimapOn()) then
        if holder then HideMinimapStuff() end
        return
    end
    Holder()
    local mapID, px, py = ns.PlayerPos()
    if not mapID then HideMinimapStuff() return end
    local data = ZoneData(mapID)
    local w, h = ns.WorldSize(mapID)
    local zoom = Minimap:GetZoom() or 0
    local indoors = IsIndoors and IsIndoors()
    local diameter = (indoors and MM_INDOOR or MM_OUTDOOR)[zoom] or 300
    local perYard = Minimap:GetWidth() / diameter
    local radius = diameter / 2 * 0.94

    local rotate = GetCVar and GetCVar("rotateMinimap") == "1"
    local f = rotate and Facing() or 0
    local cosf, sinf = math.cos(f), math.sin(f)
    -- offset from the player in yards, turned the way the minimap is turned
    local function Offset(x, y)
        local east, north = (x - px) * w, -(y - py) * h
        return east * cosf + north * sinf, -east * sinf + north * cosf
    end

    -- creatures: heat
    local nh = 0
    local base = w * 0.07 * perYard
    for _, hc in ipairs(data.heat) do
        if nh >= MM_MAX_HEAT then break end
        local sx, sy = Offset(hc.x, hc.y)
        local d = math.sqrt(sx * sx + sy * sy)
        if d <= radius - base / perYard * 0.25 then
            nh = nh + 1
            local set = mmHeat[nh]
            if not set then set = NewHeatSet(); mmHeat[nh] = set end
            local t = math.sqrt(hc.w / math.max(1, data.maxHeat))
            local fade = (hc.dim and 0.3 or 1) * ns.MapOpacity()
            local alpha = { (0.08 + 0.08 * t) * fade, (0.11 + 0.17 * t) * fade, (0.13 + 0.30 * t) * fade }
            for k = 1, 3 do
                local tex = set[k]
                local c = HEAT_COLOR[k]
                tex:SetVertexColor(c[1], c[2], c[3], alpha[k])
                tex:ClearAllPoints()
                tex:SetPoint("CENTER", Minimap, "CENTER", sx * perYard, sy * perYard)
                local size = base * HEAT_SIZE[k] * (0.75 + 0.5 * t)
                tex:SetSize(size, size)
                tex:Show()
            end
        end
    end
    for i = nh + 1, #mmHeat do for k = 1, 3 do mmHeat[i][k]:Hide() end end

    -- plants, veins and the rest
    local st = ns.db.settings
    local glowOn, glowRange, glowStyle, glowAll = st.mmGlow == true, tonumber(st.mmGlowRange) or 80, st.mmGlowStyle or "strong", st.mmSparkleAll == true
    local n = 0
    for _, d in ipairs(data.dots) do
        if n >= MM_MAX_PINS then break end
        local sx, sy = Offset(d.x, d.y)
        if sx * sx + sy * sy <= radius * radius then
            n = n + 1
            local pin = mmPins[n]
            if not pin then pin = NewMinimapPin(); mmPins[n] = pin end
            if d.icon then
                pin:SetLook("ring", 10)
                pin.pic:SetTexture(d.icon)
                pin.pic:Show()
                pin.fill:Hide()
            else
                pin:SetLook("plain", 8)
                pin.pic:Hide()
                pin.fill:Show()
                pin.fill:SetColorTexture(d.color[1], d.color[2], d.color[3], 1)
            end
            pin:SetPulse(d.hot or (d.spot and ns.Routes and ns.Routes.IsTarget(d.spot)))
            pin:SetAlpha((d.dim and 0.3 or 1) * ns.MapOpacity())
            pin.tail:SetShown(d.icon ~= nil)
            pin.title, pin.sub, pin.count, pin.last, pin.lastLabel = d.title, d.sub, d.n, d.last, d.lastLabel
            pin.node, pin.spot, pin.key = d.node, d.spot, d.key
            -- close resources sparkle (the closer, the stronger); a quiet sparkle for all of them, if set
            local dist = math.sqrt(sx * sx + sy * sy)
            pin.fxLevel = 0
            if d.node and not d.dim then
                if glowOn and dist <= glowRange then
                    pin.fxLevel = 1 + (glowRange - dist) / glowRange
                elseif glowAll then
                    pin.fxLevel = 0.5
                end
            end
            pin.fxStyle = glowStyle
            pin.fxPhase = (d.x * 977 + d.y * 331) % 6.28
            pin.spx, pin.spy = sx * perYard, sy * perYard -- (where the spot is, from the middle of the minimap: for the tooltip of the game's blip)
            pin:ClearAllPoints()
            if d.icon then
                -- plants and veins float above the spot (the game's own blip stays visible)
                pin:SetPoint("BOTTOM", Minimap, "CENTER", sx * perYard, sy * perYard + 10)
            else
                pin:SetPoint("CENTER", Minimap, "CENTER", sx * perYard, sy * perYard)
            end
            pin:Show()
        end
    end
    for i = n + 1, #mmPins do mmPins[i]:Hide(); HideFx(mmPins[i]) end

    -- the line to the place the arrow leads to; beyond the edge it points the way
    local target = ns.Routes and ns.Routes.Target and ns.Routes.Target()
    if target and target.map == mapID then
        local sx, sy = Offset(target.x, target.y)
        local d = math.sqrt(sx * sx + sy * sy)
        if d > radius then sx, sy = sx * radius / d, sy * radius / d end
        if pathLine then
            pathLine:SetStartPoint("CENTER", Minimap, 0, 0)
            pathLine:SetEndPoint("CENTER", Minimap, sx * perYard, sy * perYard)
            pathLine:Show()
        end
        goal:ClearAllPoints()
        goal:SetPoint("CENTER", Minimap, "CENTER", sx * perYard, sy * perYard)
        goal:Show()
    else
        if pathLine then pathLine:Hide() end
        if goal then goal:Hide() end
    end
end

-- The tooltip the game shows for the blip of a plant or a vein on the minimap (the herb or mineral search of the game) is its text only,
-- and the name in it cannot be read. So the known spot nearest to the mouse is looked for: if one is under it, its lines are added.
local function NearestPinToMouse()
    if not (Minimap and Minimap:IsMouseOver()) then return nil end
    local mx, my = Minimap:GetCenter()
    if not mx then return nil end
    local scale = Minimap:GetEffectiveScale()
    local cx, cy = GetCursorPosition()
    local dx, dy = cx / scale - mx, cy / scale - my
    local best, bestD
    for _, pin in ipairs(mmPins) do
        if pin:IsShown() and pin.node and pin.key and pin.spx then
            local ddx, ddy = pin.spx - dx, pin.spy - dy
            local d = ddx * ddx + ddy * ddy
            if d <= 100 and (not bestD or d < bestD) then best, bestD = pin, d end
        end
    end
    return best
end

if GameTooltip and GameTooltip.HookScript then
    GameTooltip:HookScript("OnTooltipCleared", function(tt) tt.fcMinimap = nil end)
    GameTooltip:HookScript("OnShow", function(tt)
        if tt.fcMinimap or not (ns.db and ns.TipNodeFor) then return end
        local owner = tt.GetOwner and tt:GetOwner()
        if not owner or owner.key or not (owner == Minimap or (owner.GetParent and owner:GetParent() == Minimap)) then return end
        local pin = NearestPinToMouse()
        if not pin then return end
        tt.fcMinimap = true
        pcall(ns.TipNodeFor, tt, pin.key, pin.spot, true)
        tt:Show()
    end)
end

local mmWatcher = CreateFrame("Frame")
local mmAcc = 0
mmWatcher:SetScript("OnUpdate", function(_, dt)
    W.PulseMarkers(mmPins)
    local now = GetTime()
    for i = 1, #mmPins do
        local pin = mmPins[i]
        if pin.fxLevel and pin.fxLevel > 0 and pin:IsShown() then DrawFx(pin, now) elseif pin.fx then HideFx(pin) end
    end
    mmAcc = mmAcc + dt
    if mmAcc < 0.15 then return end
    mmAcc = 0
    Spots.RefreshMinimap()
end)
