local ADDON, ns = ...
local L = ns.L
local W = ns.W
local UI = ns.UI
local C = W.C
local Ease = W.Ease

-- Routes: record waypoints while you farm, give the route a name, and let a
-- small arrow lead you around it. While a route is active its gold per hour is
-- measured, so you can compare routes with each other.

local Routes = {}
ns.Routes = Routes

local atan2 = math.atan2 or function(y, x) return math.atan(y, x) end
local ARRIVE_YARDS = 18

-- position helpers -----------------------------------------------------------

local PlayerPos, WorldSize = ns.PlayerPos, ns.WorldSize

local function Facing()
    if not GetPlayerFacing then return nil end
    local ok, f = pcall(GetPlayerFacing)
    return ok and ns.ReadableNumber(f) or nil
end

local function Active()
    local nav = ns.db and ns.db.nav
    if not (nav and nav.route) then return nil end
    for _, r in ipairs(ns.db.routes) do
        if r.id == nav.route then return r, nav end
    end
end

-- hooks from the recorder
function Routes.OnLoot(copper)
    local r = Active()
    if r then r.value = (r.value or 0) + copper end
end
function Routes.OnKill()
    local r = Active()
    if r then r.kills = (r.kills or 0) + 1 end
end

-- navigation arrow -----------------------------------------------------------

local NAV_W, NAV_H, ROW_H, MAX_ROWS = 206, 64, 20, 8

local nav = W.NewPlate(UIParent, { 0.045, 0.036, 0.03, 0.94 })
nav:SetSize(NAV_W, NAV_H)
nav:SetPoint("TOP", UIParent, "TOP", 0, -170)
-- same layer as the journal and the session window: the one you used last is in front
nav:SetFrameStrata("MEDIUM")
nav:SetToplevel(true)
nav:SetMovable(true)
nav:SetClampedToScreen(true)
nav:EnableMouse(true)
nav:RegisterForDrag("LeftButton")
nav:Hide()
nav:SetScript("OnDragStart", nav.StartMoving)
nav:SetScript("OnDragStop", function(self)
    self:StopMovingOrSizing()
    local point, _, rel, x, y = self:GetPoint()
    ns.db.navPos = { point, rel, x, y }
end)

-- the head: the dial with the way, the route and how far
nav.dial = W.NewDial(nav, 15)
nav.dial:SetPoint("TOPLEFT", 9, -17)
nav.name = nav:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
nav.name:SetPoint("TOPLEFT", 50, -9)
nav.name:SetWidth(108)
nav.name:SetJustifyH("LEFT")
nav.name:SetWordWrap(false)
nav.name:SetTextColor(unpack(C.muted))
nav.dist = nav:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
nav.dist:SetPoint("TOPLEFT", 50, -22)
nav.dist:SetTextColor(unpack(C.text))
nav.step = nav:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
nav.step:SetPoint("TOPLEFT", 50, -43)
nav.step:SetTextColor(unpack(C.muted))

local stop = W.NewButton(nav, "×", 16, 16, "GameFontNormal")
stop:SetPoint("TOPRIGHT", -5, -5)
stop:SetScript("OnClick", function() Routes.StopNav() end)
-- unfolds the list of every point of the route
local expand = W.NewButton(nav, "", 16, 16)
expand:SetPoint("RIGHT", stop, "LEFT", -3, 0)
expand.arrow = expand:CreateTexture(nil, "OVERLAY")
expand.arrow:SetSize(10, 10)
expand.arrow:SetPoint("CENTER")
expand.arrow:SetTexture("Interface\\ChatFrame\\ChatFrameExpandArrow")
expand.arrow:SetVertexColor(0.85, 0.78, 0.55)
expand:SetScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
    GameTooltip:AddLine(ns.db.navExpanded and L["Hide the route"] or L["Show the whole route"], 1, 0.85, 0.4)
    GameTooltip:Show()
end)
expand:HookScript("OnLeave", function() GameTooltip:Hide() end)
expand:SetScript("OnClick", function()
    ns.db.navExpanded = not ns.db.navExpanded
end)

-- the list of points
nav.rule = nav:CreateTexture(nil, "ARTWORK")
nav.rule:SetPoint("TOPLEFT", 8, -NAV_H)
nav.rule:SetPoint("TOPRIGHT", -8, -NAV_H)
nav.rule:SetHeight(1)
nav.rule:SetColorTexture(C.goldDim[1], C.goldDim[2], C.goldDim[3], 0.5)
nav.rows = {}

local function NewNavRow(i)
    local row = CreateFrame("Button", nil, nav)
    row:SetSize(NAV_W - 12, ROW_H)
    row:SetPoint("TOPLEFT", 6, -(NAV_H + 4 + (i - 1) * ROW_H))
    row.bg = row:CreateTexture(nil, "BACKGROUND")
    row.bg:SetAllPoints()
    row.bg:SetColorTexture(C.gold[1], C.gold[2], C.gold[3], 0)
    row.hl = row:CreateTexture(nil, "BACKGROUND", nil, 1)
    row.hl:SetAllPoints()
    row.hl:SetColorTexture(1, 1, 1, 0.06)
    row.hl:Hide()
    row.idx = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    row.idx:SetPoint("LEFT", 6, 0)
    row.idx:SetWidth(16)
    row.idx:SetJustifyH("RIGHT")
    -- what the point is: the picture of the plant or vein, round
    local ROUND = "Interface\\CharacterFrame\\TempPortraitAlphaMask"
    row.picEdge = row:CreateTexture(nil, "BACKGROUND", nil, 2)
    row.picEdge:SetTexture(ROUND)
    row.picEdge:SetVertexColor(C.gold[1], C.gold[2], C.gold[3], 0.85)
    row.picEdge:SetSize(14, 14)
    row.picEdge:SetPoint("LEFT", 26, 0)
    row.pic = row:CreateTexture(nil, "ARTWORK")
    row.pic:SetSize(11.5, 11.5)
    row.pic:SetPoint("CENTER", row.picEdge, "CENTER")
    row.pic:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    if row.CreateMaskTexture then
        local mask = row:CreateMaskTexture()
        mask:SetTexture(ROUND, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
        mask:SetPoint("CENTER", row.picEdge, "CENTER")
        mask:SetSize(11.5, 11.5)
        row.pic:AddMaskTexture(mask)
    end
    row.label = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    row.label:SetPoint("LEFT", 48, 0)
    row.label:SetWidth(84)
    row.label:SetJustifyH("LEFT")
    row.label:SetWordWrap(false)
    row.dist = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    row.dist:SetPoint("RIGHT", -6, 0)
    row.dist:SetJustifyH("RIGHT")
    row:SetScript("OnEnter", function(self)
        self.hl:Show()
        if self.point then
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:AddLine(self.point.zone or "?", 1, 0.85, 0.4)
            GameTooltip:AddLine(L["Click: lead me here."], 0.4, 0.86, 0.66)
            GameTooltip:Show()
        end
    end)
    row:SetScript("OnLeave", function(self) self.hl:Hide(); GameTooltip:Hide() end)
    row:SetScript("OnClick", function(self)
        if self.index and ns.db.nav.route then ns.db.nav.point = self.index end
    end)
    return row
end

local function NextPoint(route, state)
    state.point = state.point + 1
    if state.point > #route.points then
        state.point = 1
        route.laps = (route.laps or 0) + 1
        ns.Notify("lap", "Interface\\Icons\\INV_Misc_Map_01", L["Lap %d finished"]:format(route.laps) .. ": " .. (route.name or ""))
    end
end

local acc = 0
nav:SetScript("OnUpdate", function(self, dt)
    W.Step(dt)
    acc = acc + dt
    local route, state = Active()
    if route then route.time = (route.time or 0) + math.min(dt, 1) end
    if acc < 0.1 then return end
    acc = 0
    if not route or #route.points == 0 then
        self:Hide()
        return
    end
    state.point = math.max(1, math.min(state.point or 1, #route.points))
    local p = route.points[state.point]
    self.name:SetText(((route.name or ""):gsub("^>%s*", ""))) -- older saved names carry a "> "
    self.step:SetText(L["Point %d of %d"]:format(state.point, #route.points))

    local mapID, x, y = PlayerPos()
    local w, h = 1100, 733
    if mapID then w, h = WorldSize(mapID) end

    -- the list: every point, the current one marked; long routes scroll along
    local expanded = ns.db.navExpanded and #route.points > 0
    local n = #route.points
    local shown = expanded and math.min(n, MAX_ROWS) or 0
    local first = math.max(1, math.min(state.point - 3, n - shown + 1))
    for k = 1, MAX_ROWS do
        local row = self.rows[k]
        if k <= shown then
            if not row then row = NewNavRow(k); self.rows[k] = row end
            local index = first + k - 1
            local pt = route.points[index]
            local current = index == state.point
            row.index, row.point = index, pt
            row.idx:SetText(index)
            -- the source of the point: found by key, or by its name for older points
            local src = pt.key and ns.db.mobs[pt.key]
            if not src and pt.name then
                for _, gm in pairs(ns.db.mobs) do
                    if gm.name == pt.name and gm.cat ~= "skin" then src = gm break end
                end
            end
            local icon = src and (ns.SourceMapIcon and ns.SourceMapIcon(src) or ns.CAT[src.cat].icon)
            row.pic:SetTexture(icon or nil)
            row.pic:SetShown(icon ~= nil)
            row.picEdge:SetShown(icon ~= nil)
            row.label:ClearAllPoints()
            row.label:SetPoint("LEFT", icon and 45 or 28, 0)
            row.label:SetWidth(icon and 88 or 104)
            row.label:SetText(pt.name or string.format("%.1f / %.1f", pt.x * 100, pt.y * 100))
            row.bg:SetColorTexture(C.gold[1], C.gold[2], C.gold[3], current and 0.14 or 0)
            local c = current and C.gold or (index < state.point and C.muted or C.text)
            row.idx:SetTextColor(unpack(c))
            row.label:SetTextColor(unpack(c))
            row.dist:SetTextColor(unpack(c))
            if mapID and mapID == pt.map then
                local dx, dy = (pt.x - x) * w, (pt.y - y) * h
                row.dist:SetText(math.floor(math.sqrt(dx * dx + dy * dy)) .. " " .. L["yd"])
            else
                row.dist:SetText("")
            end
            row:Show()
        elseif row then
            row:Hide()
        end
    end
    self:SetHeight(NAV_H + (shown > 0 and (shown * ROW_H + 8) or 0))
    self.rule:SetShown(shown > 0)
    expand.arrow:SetRotation(expanded and math.pi / 2 or -math.pi / 2)

    if not mapID then
        self.dist:SetText("?")
        return
    end
    if mapID ~= p.map then
        self.dist:SetText(L["Elsewhere"])
        self.dial:SetActive(false)
        return
    end
    self.dial:SetActive(true)
    local dx, dy = (p.x - x) * w, (p.y - y) * h
    local dist = math.sqrt(dx * dx + dy * dy)
    self.dist:SetText(math.floor(dist) .. " " .. L["yd"])
    local theta = atan2(dx, -dy)
    local facing = Facing()
    if facing then self.dial:SetAngle(-(theta + facing)) end
    if dist < ARRIVE_YARDS then
        if route.temp then Routes.StopNav() else NextPoint(route, state) end
        UI.Dirty()
    end
end)

-- the point the arrow currently leads to, and its route
function Routes.Target()
    local route, state = Active()
    if not (route and state) or #route.points == 0 then return nil end
    local p = route.points[math.max(1, math.min(state.point or 1, #route.points))]
    return p, route
end

function Routes.ResetNav()
    if ns.db then ns.db.navPos = nil end
    nav:ClearAllPoints()
    nav:SetPoint("TOP", UIParent, "TOP", 0, -170)
end

-- is the arrow currently leading to this saved spot?
function Routes.IsTarget(spot)
    local t = Routes.Target()
    return t and spot and t.map == spot.m and math.abs(t.x - spot.x) < 1e-6 and math.abs(t.y - spot.y) < 1e-6 or false
end

function Routes.StartNav(route, point)
    ns.db.nav.route = route.id
    ns.db.nav.point = point or 1
    nav:Show()
    ns.Refresh()
end
function Routes.StopNav()
    ns.db.nav.route = nil
    nav:Hide()
    ns.Refresh()
end
function Routes.ToggleNav()
    if ns.db.nav.route then Routes.StopNav()
    elseif ns.db.routes[1] then Routes.StartNav(ns.db.routes[1]) end
end

function Routes.Create(name, points)
    ns.db.routeSeq = (ns.db.routeSeq or 0) + 1
    local route = { id = ns.db.routeSeq, name = name, points = points, laps = 0, value = 0, time = 0, kills = 0 }
    table.insert(ns.db.routes, route)
    return route
end

-- Lead the player to one saved spot. One throw-away route is reused for this.
function Routes.GoTo(label, spot, zone)
    local pt = { map = spot.m, x = spot.x, y = spot.y, zone = zone or GetZoneText(), name = label }
    local route
    for _, existing in ipairs(ns.db.routes) do
        if existing.temp then route = existing break end
    end
    if not route then
        route = Routes.Create(label, { pt })
        route.temp = true
    else
        route.name, route.points = label, { pt }
    end
    Routes.StartNav(route, 1)
end

-- Building the active route by hand: shift-click a place on the map to add it, shift-click
-- it again to take it out.

-- which point of the active route is this saved spot (nil when it is not part of it)
function Routes.IndexOf(spot)
    local route = Active()
    if not (route and spot) then return nil end
    for i, p in ipairs(route.points) do
        if p.map == spot.m and math.abs(p.x - spot.x) < 1e-6 and math.abs(p.y - spot.y) < 1e-6 then return i end
    end
    return nil
end

function Routes.AddToActive(label, spot, zone)
    local route = Active()
    if not route then
        Routes.GoTo(label, spot, zone)
        return
    end
    if Routes.IndexOf(spot) then return end
    route.points[#route.points + 1] = { map = spot.m, x = spot.x, y = spot.y, zone = zone or GetZoneText(), name = label }
    if route.temp then
        -- more than one place: it is a route now, and it stays
        route.temp = nil
        route.name = L["Quick route"]
    end
    ns.Refresh()
end

function Routes.RemoveFromActive(index)
    local route, state = Active()
    if not (route and route.points[index]) then return end
    table.remove(route.points, index)
    if #route.points == 0 then
        Routes.StopNav()
        return
    end
    if index < (state.point or 1) then state.point = state.point - 1 end
    state.point = math.max(1, math.min(state.point or 1, #route.points))
    ns.Refresh()
end

-- the point the arrow leads to and the ones after it (at most 40), for drawing the way ahead
function Routes.Upcoming()
    local route, state = Active()
    local list = {}
    if not route then return list end
    for i = math.max(1, state.point or 1), math.min(#route.points, (state.point or 1) + 39) do
        list[#list + 1] = route.points[i]
    end
    return list
end

local loader = CreateFrame("Frame")
loader:RegisterEvent("PLAYER_LOGIN")
loader:SetScript("OnEvent", function()
    local pos = ns.db and ns.db.navPos
    if pos then
        nav:ClearAllPoints()
        nav:SetPoint(pos[1], UIParent, pos[2], pos[3], pos[4])
    end
    if Active() then nav:Show() end
end)

-- page -----------------------------------------------------------------------

local LIST_W, GAP = 300, 8

local function Label(parent, template, color, ...)
    local fs = parent:CreateFontString(nil, "OVERLAY", template)
    fs:SetJustifyH("LEFT")
    if color then fs:SetTextColor(unpack(color)) end
    if ... then fs:SetPoint(...) end
    return fs
end

UI.AddPage({ id = "routes", label = L["Routes"], icon = "Interface\\Icons\\INV_Misc_Map_01",
    hint = L["Record waypoints, follow them with an arrow, compare gold per hour."],
    Build = function(area)
        local obj = {}
        local frame = CreateFrame("Frame", nil, area)
        obj.frame = frame
        local H = UI.AREA_H
        local RW = UI.AREA_W - LIST_W - GAP
        local sel, wsel

        local left = W.NewPlate(frame, C.page)
        left:SetSize(LIST_W, H)
        left:SetPoint("TOPLEFT")
        local info = Label(left, "GameFontHighlightSmall", C.muted, "TOPLEFT", 12, -13)
        local newBtn = W.NewIconButton(left, "Interface\\Icons\\Spell_ChargePositive", 24)
        newBtn:SetPoint("TOPRIGHT", -8, -8)
        newBtn:SetTip(L["New route"])
        obj.lv = UI.NewListView(left, LIST_W - 14, H - 48, 44)
        obj.lv.frame:SetPoint("TOPLEFT", left, "TOPLEFT", 7, -42)

        local right = W.NewPlate(frame, C.page)
        right:SetSize(RW, H)
        right:SetPoint("TOPRIGHT")

        local d = {}
        -- the name is an edit box styled as the page title
        d.nameBox = CreateFrame("EditBox", nil, right)
        d.nameBox:SetPoint("TOPLEFT", 16, -14)
        d.nameBox:SetSize(RW - 32, 28)
        d.nameBox:SetFontObject(UI.titleFontObject)
        d.nameBox:SetTextColor(1, 0.88, 0.5)
        d.nameBox:SetAutoFocus(false)
        d.nameBox:SetMaxLetters(40)
        d.nameLine = right:CreateTexture(nil, "ARTWORK")
        d.nameLine:SetPoint("TOPLEFT", d.nameBox, "BOTTOMLEFT", 0, -1)
        d.nameLine:SetPoint("TOPRIGHT", d.nameBox, "BOTTOMRIGHT", 0, -1)
        d.nameLine:SetHeight(1)
        d.nameLine:SetColorTexture(C.goldDim[1], C.goldDim[2], C.goldDim[3], 0.5)
        local function Commit(box)
            local route = obj.current
            local text = box:GetText():gsub("^%s+", ""):gsub("%s+$", "")
            if route and text ~= "" then route.name = text end
            UI.Dirty()
        end
        d.nameBox:SetScript("OnEnterPressed", function(self) Commit(self); self:ClearFocus() end)
        d.nameBox:SetScript("OnEscapePressed", function(self) self:ClearFocus(); UI.Dirty() end)
        d.nameBox:SetScript("OnEditFocusGained", function() d.nameLine:SetColorTexture(C.gold[1], C.gold[2], C.gold[3], 1) end)
        d.nameBox:SetScript("OnEditFocusLost", function(self)
            d.nameLine:SetColorTexture(C.goldDim[1], C.goldDim[2], C.goldDim[3], 0.5)
            Commit(self)
        end)
        d.sub = Label(right, "GameFontHighlightSmall", C.muted, "TOPLEFT", 16, -52)
        d.sub:SetWidth(RW - 32)

        local BW = (RW - 32 - 3 * 8) / 4
        d.stats = {}
        for i = 1, 4 do
            local s = W.NewPlate(right, C.inset)
            s:SetSize(BW, 46)
            s:SetPoint("TOPLEFT", 16 + (i - 1) * (BW + 8), -74)
            s.label = Label(s, "GameFontHighlightSmall", C.muted, "TOPLEFT", 8, -7)
            s.value = Label(s, "GameFontNormal", C.text, "BOTTOMLEFT", 8, 7)
            d.stats[i] = s
        end

        d.wpTitle = Label(right, "GameFontHighlightSmall", C.muted, "TOPLEFT", 16, -132)
        d.wpBox = W.NewPlate(right, C.inset)
        d.wpBox:SetPoint("TOPLEFT", 16, -150)
        d.wpBox:SetSize(RW - 32, H - 150 - 56)
        d.wp = UI.NewListView(d.wpBox, RW - 32 - 8, H - 150 - 56 - 8, 34)
        d.wp.frame:SetPoint("TOPLEFT", d.wpBox, "TOPLEFT", 4, -4)

        -- action row: icons only, tooltips say what they do
        d.add = W.NewIconButton(right, "Interface\\Icons\\Spell_ChargePositive", 30)
        d.add:SetPoint("BOTTOMLEFT", 16, 14)
        d.add:SetTip(L["Add point here"])
        d.remove = W.NewIconButton(right, "Interface\\Icons\\Spell_ChargeNegative", 30)
        d.remove:SetPoint("LEFT", d.add, "RIGHT", 6, 0)
        d.remove:SetTip(L["Remove point"])
        d.del = W.NewIconButton(right, W.ICON.clear, 30)
        d.del:SetPoint("BOTTOMRIGHT", -16, 14)
        d.del:SetTip(L["Delete route"])
        d.go = W.NewIconButton(right, "Interface\\Icons\\Ability_Tracking", 30)
        d.go:SetPoint("RIGHT", d.del, "LEFT", -6, 0)
        d.go:SetTip(L["Start navigation"])

        d.empty = Label(right, "GameFontHighlight", C.muted, "CENTER", 0, 0)
        d.empty:SetJustifyH("CENTER")
        d.empty:SetWidth(RW - 60)

        -- actions -------------------------------------------------------------------
        local function Current()
            for _, r in ipairs(ns.db.routes) do if r.id == sel then return r end end
        end

        newBtn:SetScript("OnClick", function()
            ns.db.routeSeq = (ns.db.routeSeq or 0) + 1
            local route = { id = ns.db.routeSeq, name = L["Route"] .. " " .. ns.db.routeSeq, points = {},
                laps = 0, value = 0, time = 0, kills = 0 }
            table.insert(ns.db.routes, route)
            sel, wsel = route.id, nil
            UI.Dirty()
        end)

        d.add:SetScript("OnClick", function()
            local route = Current()
            if not route then return end
            local mapID, x, y = PlayerPos()
            if not mapID then
                print("|cffffd100ForeverCodex:|r " .. L["No position available here."])
                return
            end
            local zone = GetZoneText()
            local sub = GetSubZoneText and GetSubZoneText() or ""
            table.insert(route.points, { map = mapID, x = x, y = y, zone = (sub ~= "" and sub ~= zone) and (zone .. " – " .. sub) or zone })
            wsel = #route.points
            UI.Dirty()
        end)
        d.remove:SetScript("OnClick", function()
            local route = Current()
            if route and wsel and route.points[wsel] then
                table.remove(route.points, wsel)
                wsel = math.min(wsel, #route.points)
                if wsel == 0 then wsel = nil end
                UI.Dirty()
            end
        end)
        d.go:SetScript("OnClick", function()
            local route = Current()
            if not route or #route.points == 0 then return end
            local active = Active()
            if active and active.id == route.id then Routes.StopNav() else Routes.StartNav(route, wsel or 1) end
        end)

        local armed
        d.del:SetScript("OnClick", function(self)
            local route = Current()
            if not route then return end
            if armed then
                armed = nil
                self.icon:SetVertexColor(1, 1, 1)
                self:SetTip(L["Delete route"])
                local active = Active()
                if active and active.id == route.id then Routes.StopNav() end
                for i, r in ipairs(ns.db.routes) do if r == route then table.remove(ns.db.routes, i) break end end
                sel, wsel = nil, nil
                UI.Dirty()
            else
                armed = true
                self.icon:SetVertexColor(1, 0.4, 0.35)
                self:SetTip(L["Sure? Click again"])
                C_Timer.After(3, function()
                    if armed then
                        armed = nil
                        self.icon:SetVertexColor(1, 1, 1)
                        self:SetTip(L["Delete route"])
                    end
                end)
            end
        end)

        -- refresh -----------------------------------------------------------------
        function obj.Refresh()
            local routes = ns.db.routes
            local active = Active()
            local entries = {}
            for i, r in ipairs(routes) do
                local rate = (r.time or 0) >= 60 and (r.value or 0) / (r.time / 3600) or 0
                entries[#entries + 1] = {
                    key = r.id, name = r.name, texture = "Interface\\Icons\\INV_Misc_Map_01", quality = 1,
                    sub = L["%d points"]:format(#r.points) .. " · " .. L["%d laps"]:format(r.laps or 0),
                    right = rate > 0 and (ns.Value.Format(rate) .. "/h") or "-",
                    right2 = active and active.id == r.id and ("> " .. L["active"]) or "",
                    right2Color = C.jade,
                }
            end
            local route
            for _, r in ipairs(routes) do if r.id == sel then route = r break end end
            if not route then route = routes[1]; sel = route and route.id; wsel = nil end
            obj.current = route
            info:SetText(L["%d routes"]:format(#routes))
            obj.lv:SetData(entries, sel, function(e) sel = e.key; wsel = nil; UI.Dirty() end, L["No routes yet."])

            local has = route ~= nil
            d.empty:SetText(has and "" or L["Create a route and add waypoints while you farm."])
            for _, w in ipairs({ d.nameBox, d.nameLine, d.sub, d.wpTitle, d.wpBox, d.add, d.remove, d.go, d.del }) do
                w:SetShown(has)
            end
            for _, s in ipairs(d.stats) do s:SetShown(has) end
            if not has then return end

            if not d.nameBox:HasFocus() then d.nameBox:SetText(route.name) end
            d.sub:SetText(L["Drag the arrow to move it. Select a point to start from there."])
            local rate = (route.time or 0) >= 60 and (route.value or 0) / (route.time / 3600) or 0
            local fmt = ns.Value.Format
            local labels = { L["Points"], L["Laps"], L["Per hour"], L["Yield"] }
            local values = { tostring(#route.points), tostring(route.laps or 0),
                rate > 0 and fmt(rate) or "-", (route.value or 0) > 0 and fmt(route.value) or "-" }
            for i, s in ipairs(d.stats) do s.label:SetText(labels[i]); s.value:SetText(values[i]) end

            d.wpTitle:SetText(L["Waypoints"])
            local wps = {}
            for i, p in ipairs(route.points) do
                local isNext = active and active.id == route.id and ns.db.nav.point == i
                wps[#wps + 1] = {
                    key = i, name = L["Point %d"]:format(i), texture = "Interface\\Icons\\INV_Misc_Map_01", quality = 1,
                    sub = (p.zone or "?") .. string.format(" · %.1f / %.1f", p.x * 100, p.y * 100),
                    right = isNext and (">") or "", rightColor = C.jade,
                }
            end
            if wsel and not route.points[wsel] then wsel = nil end
            d.wp:SetData(wps, wsel, function(e) wsel = e.key; UI.Dirty() end, L["No waypoints yet."])
            local navigating = active and active.id == route.id
            d.go:SetTip(navigating and L["Stop navigation"] or L["Start navigation"])
            d.go:SetActive(navigating)
        end

        function obj.SetSel(k) sel = k end

        return obj
    end,
})
