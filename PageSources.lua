local ADDON, ns = ...
local L = ns.L
local W = ns.W
local UI = ns.UI
local C = W.C
local Ease = W.Ease

-- Bestiary (creatures) and Gathering (nodes, skinning, fishing, ...): the same
-- two-page spread with a list of sources on the left and the selected entry on
-- the right.

local LIST_W, GAP = 300, 8
local ICON = 34
local STAT_LABELS

local function Items(map)
    local list = {}
    local hideGray = ns.db.settings.hideGray
    for id, count in pairs(map) do
        local gi = ns.db.items[id]
        local quality = gi and gi.quality or 1
        if not (hideGray and quality == 0) then
            list[#list + 1] = { id = id, link = gi and gi.link, quality = quality, count = count }
        end
    end
    table.sort(list, function(a, b)
        if a.quality ~= b.quality then return a.quality > b.quality end
        if a.count ~= b.count then return a.count > b.count end
        return a.id < b.id
    end)
    return list
end

local function TopItem(map)
    local best
    for id, count in pairs(map) do
        local gi = ns.db.items[id]
        local q = gi and gi.quality or 1
        if not best or q > best.q or (q == best.q and count > best.count) then
            best = { id = id, q = q, count = count }
        end
    end
    return best
end

local function ItemsValue(map)
    local v = 0
    for id, c in pairs(map) do v = v + ns.Value.Get(id) * c end
    return v
end

local function Label(parent, template, color, ...)
    local fs = parent:CreateFontString(nil, "OVERLAY", template)
    fs:SetJustifyH("LEFT")
    if color then fs:SetTextColor(unpack(color)) end
    if ... then fs:SetPoint(...) end
    return fs
end

local function MakePage(cfg)
    UI.AddPage({ id = cfg.id, label = cfg.label, icon = cfg.icon, hint = cfg.hint, Build = function(area)
        local obj = {}
        local frame = CreateFrame("Frame", nil, area)
        obj.frame = frame
        local H = UI.AREA_H
        local RW = UI.AREA_W - LIST_W - GAP
        local sel
        local sortIndex = 1
        local filter -- gathering: a single category, nil = all
        local SORTS = { "recent", "kills", "value" }
        local SORT_LABEL = { recent = L["Recent"], kills = L["Count"], value = L["Value"] }

        -- left page: list --------------------------------------------------
        local left = W.NewPlate(frame, C.page)
        left:SetSize(LIST_W, H)
        left:SetPoint("TOPLEFT")

        local sortBtn = W.NewIconButton(left, W.ICON.recent, 24)
        sortBtn:SetPoint("TOPRIGHT", -8, -8)
        local SORT_ICON = { recent = W.ICON.recent, kills = W.ICON.skull, value = W.ICON.coin }
        sortBtn:SetScript("OnClick", function()
            sortIndex = sortIndex % #SORTS + 1
            obj.lv:ScrollToTop()
            UI.Dirty()
        end)

        local info = Label(left, "GameFontHighlightSmall", C.muted, "TOPLEFT", 12, -13)

        if cfg.chips then
            info:Hide()
            local x = 8
            local function Chip(cat)
                local b = W.NewIconButton(left, cat and ns.CAT[cat].icon or W.ICON.search, 24)
                b:SetPoint("TOPLEFT", x, -8)
                x = x + 26
                b.cat = cat
                b:SetTip(cat and ns.CAT[cat].label or L["All"])
                b:SetScript("OnClick", function()
                    filter = cat
                    obj.lv:ScrollToTop()
                    UI.Dirty()
                end)
                return b
            end
            obj.chips = { Chip(nil) }
            for _, cat in ipairs(ns.CATS) do
                if cfg.cats[cat] then obj.chips[#obj.chips + 1] = Chip(cat) end
            end

            -- a route through every listed source in the current area
            local allBtn = W.NewIconButton(left, "Interface\\Icons\\INV_Misc_Map_01", 24)
            allBtn:SetPoint("TOPLEFT", x + 6, -8)
            allBtn:SetTip(L["Route through all spots here"], L["Of everything listed, in the current area."])
            allBtn:SetScript("OnClick", function()
                local keys = {}
                for _, e in ipairs(obj.entries or {}) do keys[#keys + 1] = e.key end
                local route, info = ns.Spots.MakeRoute(keys, (filter and ns.CAT[filter].label or cfg.label) .. " · " .. GetZoneText())
                if route then
                    print("|cffffd100ForeverCodex:|r " .. L["Route created: %s"]:format(route.name))
                    ns.UI.OpenEntry("routes", route.id)
                else
                    print("|cffffd100ForeverCodex:|r " .. info)
                end
            end)
        end

        obj.lv = UI.NewListView(left, LIST_W - 14, H - 44, 44)
        obj.lv.frame:SetPoint("TOPLEFT", left, "TOPLEFT", 7, -38)

        -- right page: the selected entry ------------------------------------
        local right = W.NewPlate(frame, C.page)
        right:SetSize(RW, H)
        right:SetPoint("TOPRIGHT")

        local d = {}
        d.iconEdge = right:CreateTexture(nil, "ARTWORK")
        d.iconEdge:SetSize(52, 52)
        d.iconEdge:SetPoint("TOPLEFT", 16, -16)
        d.icon = right:CreateTexture(nil, "OVERLAY")
        d.icon:SetPoint("TOPLEFT", d.iconEdge, 2, -2)
        d.icon:SetPoint("BOTTOMRIGHT", d.iconEdge, -2, 2)
        d.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)

        d.name = right:CreateFontString(nil, "OVERLAY")
        d.name:SetFontObject(UI.titleFontObject)
        d.name:SetJustifyH("LEFT")
        d.name:SetPoint("TOPLEFT", d.iconEdge, "TOPRIGHT", 12, -2)
        d.name:SetWidth(RW - 200)
        d.name:SetWordWrap(false)
        d.name:SetTextColor(1, 0.88, 0.5)
        d.sub = Label(right, "GameFontHighlightSmall", C.muted, "TOPLEFT", d.iconEdge, "BOTTOMRIGHT", 12, 18)
        d.sub:ClearAllPoints()
        d.sub:SetPoint("BOTTOMLEFT", d.iconEdge, "BOTTOMRIGHT", 12, 2)
        d.sub:SetWidth(RW - 200)

        -- where to find it: pins on the world map, the nearest spot, a route through all
        local function MapButton(icon, offset)
            local b = W.NewIconButton(right, icon, 28)
            b:SetPoint("TOPRIGHT", -16 - offset, -18)
            return b
        end
        d.routeBtn = MapButton("Interface\\Icons\\INV_Misc_Map_01", 0)
        d.nearBtn = MapButton("Interface\\Icons\\Ability_Tracking", 34)
        d.pinBtn = MapButton(W.ICON.search, 68)
        d.pinBtn:SetScript("OnClick", function()
            if sel then ns.Spots.TogglePin(sel); UI.Dirty() end
        end)
        d.nearBtn:SetScript("OnClick", function()
            local gm = sel and ns.db.mobs[sel]
            if not gm then return end
            local spot = ns.Spots.Nearest(gm)
            if not spot then
                print("|cffffd100ForeverCodex:|r " .. L["No saved spots yet."])
                return
            end
            ns.Routes.GoTo(gm.name or sel, spot, gm.zone)
        end)
        d.routeBtn:SetScript("OnClick", function()
            local gm = sel and ns.db.mobs[sel]
            if not gm then return end
            local route, info = ns.Spots.MakeRoute({ sel }, (gm.name or sel) .. " · " .. GetZoneText())
            if route then
                print("|cffffd100ForeverCodex:|r " .. L["Route created: %s"]:format(route.name))
                ns.UI.OpenEntry("routes", route.id)
            else
                print("|cffffd100ForeverCodex:|r " .. info)
            end
        end)

        local rule = right:CreateTexture(nil, "ARTWORK")
        rule:SetPoint("TOPLEFT", 16, -78)
        rule:SetPoint("TOPRIGHT", -16, -78)
        rule:SetHeight(1)
        rule:SetColorTexture(C.goldDim[1], C.goldDim[2], C.goldDim[3], 0.5)

        -- four stat blocks
        local BW = (RW - 32 - 3 * 8) / 4
        d.stats = {}
        for i = 1, 4 do
            local s = W.NewPlate(right, C.inset)
            s:SetSize(BW, 46)
            s:SetPoint("TOPLEFT", 16 + (i - 1) * (BW + 8), -90)
            s.label = Label(s, "GameFontHighlightSmall", C.muted, "TOPLEFT", 8, -7)
            s.value = Label(s, "GameFontNormal", C.text, "BOTTOMLEFT", 8, 7)
            d.stats[i] = s
        end

        -- kills until the drop chances: a bar that leads to a "chance" token
        d.pipTitle = Label(right, "GameFontHighlightSmall", C.muted, "TOPLEFT", 16, -152)
        d.goal = W.NewGoalBar(right, RW - 32)
        d.goal:SetPoint("TOPLEFT", 16, -168)
        d.pipStatus = Label(right, "GameFontHighlight", C.text, "TOPLEFT", 16, -198)
        d.pipStatus:SetWidth(RW - 32)

        -- drop-chance lines
        d.chance = Label(right, "GameFontHighlight", C.text, "TOPLEFT", 16, -216)
        d.chanceVal = Label(right, "GameFontHighlight", C.text, "TOPRIGHT", -16, -216)
        d.chanceVal:SetJustifyH("RIGHT")
        d.sofar = Label(right, "GameFontHighlight", C.text, "TOPLEFT", 16, -238)
        d.sofarVal = Label(right, "GameFontHighlight", C.text, "TOPRIGHT", -16, -238)
        d.sofarVal:SetJustifyH("RIGHT")

        d.lootTitle = Label(right, "GameFontHighlightSmall", C.muted, "TOPLEFT", 16, -268)
        d.grid = W.NewIconGrid(right, ICON, 5, math.floor((RW - 32) / (ICON + 5)), 4)
        d.grid.frame:SetPoint("TOPLEFT", 16, -286)

        d.empty = Label(right, "GameFontHighlight", C.muted, "CENTER", 0, 0)
        d.empty:SetJustifyH("CENTER")
        d.empty:SetWidth(RW - 60)

        -- entries ------------------------------------------------------------
        local function BuildEntries(snap)
            local list = {}
            local T = ns.Threshold()
            for key, gm in pairs(ns.db.mobs) do
                if cfg.cats[gm.cat] and ns.CatOn(gm.cat) and (not filter or gm.cat == filter) then
                    local sm = ns.session.mobs[key]
                    local skinSm = gm.cat == "mob" and ns.session.mobs["skin:" .. (gm.name or "")]
                    local top = TopItem(gm.items)
                    local value = ItemsValue(ns.MergedItems(gm))
                    local sub
                    if gm.cat == "mob" then
                        sub = gm.zone or ""
                        local lt = ns.LevelText(gm)
                        if lt then sub = sub .. (sub ~= "" and " · " or "") .. lt end
                    else
                        sub = ns.CAT[gm.cat].label .. (gm.zone and (" · " .. gm.zone) or "")
                    end
                    local itemSum = 0
                    if sm then for _, c in pairs(sm.items) do itemSum = itemSum + c end end
                    local icon = ns.SourceIcon(gm)
                    list[#list + 1] = {
                        key = key, name = gm.name or key, sub = sub,
                        texture = icon, noIcon = icon == nil, quality = 1,
                        right = tostring(gm.kills),
                        right2 = (sm and sm.kills > 0) and ("+" .. sm.kills) or ns.Value.Format(value),
                        right2Color = (sm and sm.kills > 0) and C.jade or C.muted,
                        activity = sm and (sm.kills + itemSum) or nil,
                        recent = math.max(sm and sm.last or 0, skinSm and skinSm.last or 0), kills = gm.kills, value = value,
                    }
                end
            end
            local mode = SORTS[sortIndex]
            table.sort(list, function(a, b)
                if mode == "recent" then
                    if a.recent ~= b.recent then return a.recent > b.recent end
                    return a.kills > b.kills
                end
                if a[mode] ~= b[mode] then return a[mode] > b[mode] end
                return a.name < b.name
            end)
            return list
        end

        local function ShowDetail(entries)
            local e
            for _, x in ipairs(entries) do if x.key == sel then e = x break end end
            if not e then
                e = entries[1]
                sel = e and e.key
            end
            local hasEntry = e ~= nil
            d.empty:SetText(hasEntry and "" or cfg.emptyText)
            for _, w in ipairs({ d.iconEdge, d.icon, d.name, d.sub, rule, d.pipTitle, d.goal, d.pipStatus,
                d.chance, d.chanceVal, d.sofar, d.sofarVal, d.lootTitle, d.grid.frame, d.pinBtn, d.nearBtn, d.routeBtn }) do
                w:SetShown(hasEntry)
            end
            for _, s in ipairs(d.stats) do s:SetShown(hasEntry) end
            if not hasEntry then return end

            local gm = ns.db.mobs[sel]
            local sm = ns.session.mobs[sel]
            local cat = ns.CAT[gm.cat]
            local T = ns.Threshold()
            local top = TopItem(gm.items)
            local merged = ns.MergedItems(gm)
            local skin = ns.SkinRecord(gm)
            local value = ItemsValue(merged)

            -- creatures have no icon; gathering sources show their category's
            local srcIcon = ns.SourceIcon(gm)
            local hasIcon = srcIcon ~= nil
            d.iconEdge:SetShown(hasIcon)
            d.icon:SetShown(hasIcon)
            d.name:ClearAllPoints()
            d.sub:ClearAllPoints()
            if hasIcon then
                d.icon:SetTexture(srcIcon)
                d.iconEdge:SetColorTexture(cat.color[1], cat.color[2], cat.color[3], 1)
                d.name:SetPoint("TOPLEFT", d.iconEdge, "TOPRIGHT", 12, -2)
                d.sub:SetPoint("BOTTOMLEFT", d.iconEdge, "BOTTOMRIGHT", 12, 2)
            else
                d.name:SetPoint("TOPLEFT", right, "TOPLEFT", 16, -20)
                d.sub:SetPoint("TOPLEFT", right, "TOPLEFT", 16, -50)
            end
            d.name:SetText(gm.name or sel)
            local sub = cat.label
            if gm.zone then sub = sub .. " · " .. gm.zone end
            local lt = ns.LevelText(gm)
            if lt then sub = sub .. " · " .. lt end
            local nSpots = ns.Spots.Count(gm)
            if nSpots > 0 then sub = sub .. " · " .. L["%d spots"]:format(nSpots) end
            d.sub:SetText(sub)
            local pinned = ns.Spots.IsPinned(sel)
            for _, b in ipairs({ d.pinBtn, d.nearBtn, d.routeBtn }) do b.icon:SetDesaturated(nSpots == 0) end
            d.pinBtn:SetActive(pinned)
            d.pinBtn:SetTip(pinned and L["Hide from world map"] or L["Show on world map"], L["%d spots"]:format(nSpots))
            d.nearBtn:SetTip(L["Go to nearest spot"], L["The arrow leads you there."])
            d.routeBtn:SetTip(L["Route through all spots here"], L["Creates a route in the current area, ordered to walk."])

            local avg = gm.kills > 0 and value / gm.kills or 0
            local labels = { cat.verb, L["This session"], L["Avg per"], L["Value"] }
            local values = {
                tostring(gm.kills),
                (sm and sm.kills or 0) > 0 and ("+" .. sm.kills) or "0",
                ns.Value.Format(avg) ~= "" and ns.Value.Format(avg) or "-",
                ns.Value.Format(value) ~= "" and ns.Value.Format(value) or "-",
            }
            for i, s in ipairs(d.stats) do
                s.label:SetText(labels[i])
                s.value:SetText(values[i])
            end

            local isMob = gm.cat == "mob"
            d.chance:SetShown(isMob); d.chanceVal:SetShown(isMob)
            d.sofar:SetShown(isMob); d.sofarVal:SetShown(isMob)
            d.goal:SetShown(isMob)
            if isMob then
                d.pipTitle:SetText(L["Progress to drop chances"])
                d.goal:Set(gm.kills, T, sel)
                if gm.kills >= T then
                    d.pipStatus:SetText(L["Drop chances unlocked"])
                    d.pipStatus:SetTextColor(unpack(C.jade))
                else
                    d.pipStatus:SetText(L["%d kills until unlocked"]:format(T - gm.kills))
                    d.pipStatus:SetTextColor(unpack(C.text))
                end
                local good = gm.greens + gm.blues
                d.chance:SetText(L["Green+ drops"])
                d.sofar:SetText(L["So far from it"])
                if gm.kills >= T then
                    d.chanceVal:SetText(good > 0 and L["1 in %d kills"]:format(math.floor(gm.kills / good + 0.5)) or L["no drop yet"])
                    d.chanceVal:SetTextColor(unpack(good > 0 and C.jade or C.muted))
                else
                    d.chanceVal:SetText("-")
                    d.chanceVal:SetTextColor(unpack(C.muted))
                end
                local parts = L["%d green"]:format(gm.greens)
                if gm.blues > 0 then parts = parts .. ", " .. L["%d blue+"]:format(gm.blues) end
                d.sofarVal:SetText(parts)
                d.sofarVal:SetTextColor(unpack(good > 0 and C.jade or C.red))
            else
                d.pipTitle:SetText(L["Yield"])
                local items = 0
                for _, c in pairs(gm.items) do items = items + c end
                d.pipStatus:SetText(L["%.1f items per %s"]:format(gm.kills > 0 and items / gm.kills or 0, cat.verb))
                d.pipStatus:SetTextColor(unpack(C.text))
            end
            d.lastSel = sel

            d.lootTitle:SetText(L["Loot"] .. ((skin and skin.kills > 0) and ("  ·  " .. L["%d skinned"]:format(skin.kills)) or ""))
            d.grid:Set(Items(merged))
        end

        local function Select(e)
            sel = e.key
            UI.Dirty()
        end

        function obj.Refresh(snap)
            local entries = BuildEntries(snap)
            obj.entries = entries
            if cfg.chips then
                for _, b in ipairs(obj.chips) do
                    b:SetActive(b.cat == filter)
                    b:SetShown(not b.cat or ns.CatOn(b.cat))
                end
            end
            info:SetText(L["%d entries"]:format(#entries))
            sortBtn:SetIcon(SORT_ICON[SORTS[sortIndex]])
            sortBtn:SetTip(L["Sort: %s"]:format(SORT_LABEL[SORTS[sortIndex]]), L["Click to change"])
            local found
            for _, x in ipairs(entries) do if x.key == sel then found = true break end end
            if not found then sel = entries[1] and entries[1].key end
            obj.lv:SetData(entries, sel, Select, cfg.emptyText)
            ShowDetail(entries)
        end

        function obj.SetSel(k) sel = k; filter = nil end

        return obj
    end })
end

MakePage({
    id = "bestiary", label = L["Bestiary"], hint = L["Every creature you looted, with kills and drop chances."],
    icon = "Interface\\Icons\\INV_Misc_Bone_HumanSkull_01",
    cats = { mob = true }, emptyText = L["Nothing recorded yet. Go hunt!"],
})

MakePage({
    id = "gathering", label = L["Gathering"], hint = L["Herbs, ore, skinning, fishing and more."],
    icon = "Interface\\Icons\\Trade_Herbalism", chips = true,
    cats = { herb = true, ore = true, fish = true, disenchant = true, object = true },
    emptyText = L["Gather something to see it here."],
})
