local ADDON, ns = ...
local L = ns.L
local W = ns.W
local UI = ns.UI
local C = W.C
local Ease = W.Ease

-- Loot: every item of this session (category filter applied), ranked; the
-- right page shows where it came from and how much of the haul it is.

local LIST_W, GAP = 300, 8
local MAX_SOURCES = 7

local function Label(parent, template, color, ...)
    local fs = parent:CreateFontString(nil, "OVERLAY", template)
    fs:SetJustifyH("LEFT")
    if color then fs:SetTextColor(unpack(color)) end
    if ... then fs:SetPoint(...) end
    return fs
end

local function Colored(link)
    local color, name = link:match("|c(%x%x%x%x%x%x%x%x)|Hitem:.-|h%[(.-)%]|h")
    return color and ("|c" .. color .. name .. "|r") or link
end

UI.AddPage({ id = "loot", label = L["Loot"], icon = "Interface\\Icons\\INV_Misc_Bag_10",
    hint = L["Everything you looted this session, ranked by value."],
    Build = function(area)
        local obj = {}
        local frame = CreateFrame("Frame", nil, area)
        obj.frame = frame
        local H = UI.AREA_H
        local RW = UI.AREA_W - LIST_W - GAP
        local sel
        local sortIndex = 1
        local SORTS = { "value", "count", "recent" }
        local SORT_LABEL = { value = L["Value"], count = L["Count"], recent = L["Recent"] }

        local left = W.NewPlate(frame, C.page)
        left:SetSize(LIST_W, H)
        left:SetPoint("TOPLEFT")
        local sortBtn = W.NewIconButton(left, W.ICON.coin, 24)
        sortBtn:SetPoint("TOPRIGHT", -8, -8)
        local SORT_ICON = { value = W.ICON.coin, count = W.ICON.loot, recent = W.ICON.recent }
        sortBtn:SetScript("OnClick", function()
            sortIndex = sortIndex % #SORTS + 1
            obj.lv:ScrollToTop()
            UI.Dirty()
        end)
        local info = Label(left, "GameFontHighlightSmall", C.muted, "TOPLEFT", 12, -13)

        obj.lv = UI.NewListView(left, LIST_W - 14, H - 44, 46)
        obj.lv.frame:SetPoint("TOPLEFT", left, "TOPLEFT", 7, -38)

        local right = W.NewPlate(frame, C.page)
        right:SetSize(RW, H)
        right:SetPoint("TOPRIGHT")

        local d = {}
        d.icon = W.NewIcon(right)
        d.icon:SetPoint("TOPLEFT", 16, -16)
        d.name = right:CreateFontString(nil, "OVERLAY")
        d.name:SetFontObject(UI.titleFontObject)
        d.name:SetJustifyH("LEFT")
        d.name:SetPoint("TOPLEFT", 80, -18)
        d.name:SetWidth(RW - 100)
        d.name:SetWordWrap(false)
        d.sub = Label(right, "GameFontHighlightSmall", C.muted, "TOPLEFT", 80, -46)
        d.sub:SetWidth(RW - 100)

        local rule = right:CreateTexture(nil, "ARTWORK")
        rule:SetPoint("TOPLEFT", 16, -78)
        rule:SetPoint("TOPRIGHT", -16, -78)
        rule:SetHeight(1)
        rule:SetColorTexture(C.goldDim[1], C.goldDim[2], C.goldDim[3], 0.5)

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

        -- share-of-haul bar
        d.shareTitle = Label(right, "GameFontHighlightSmall", C.muted, "TOPLEFT", 16, -152)
        d.shareVal = Label(right, "GameFontHighlightSmall", C.text, "TOPRIGHT", -16, -152)
        d.shareVal:SetJustifyH("RIGHT")
        d.bar = CreateFrame("Frame", nil, right)
        d.bar:SetPoint("TOPLEFT", 16, -170)
        d.bar:SetSize(RW - 32, 12)
        d.bar.track = d.bar:CreateTexture(nil, "BACKGROUND")
        d.bar.track:SetAllPoints()
        d.bar.track:SetColorTexture(0.02, 0.02, 0.02, 1)
        d.bar.fill = d.bar:CreateTexture(nil, "ARTWORK")
        d.bar.fill:SetPoint("TOPLEFT")
        d.bar.fill:SetPoint("BOTTOMLEFT")
        d.bar.fill:SetColorTexture(C.gold[1], C.gold[2], C.gold[3], 1)
        d.bar.shine = d.bar:CreateTexture(nil, "OVERLAY")
        d.bar.shine:SetPoint("TOPLEFT", d.bar.fill, "TOPLEFT")
        d.bar.shine:SetPoint("RIGHT", d.bar.fill, "RIGHT")
        d.bar.shine:SetHeight(3)
        d.bar.shine:SetColorTexture(1, 1, 1, 0.22)

        local function ApplyBar(bar, v) bar.fill:SetWidth(math.max(1, (RW - 32) * v)) end

        -- sources
        d.srcTitle = Label(right, "GameFontHighlightSmall", C.muted, "TOPLEFT", 16, -198)
        d.src = {}
        for i = 1, MAX_SOURCES do
            local r = CreateFrame("Frame", nil, right)
            r:SetSize(RW - 32, 26)
            r:SetPoint("TOPLEFT", 16, -216 - (i - 1) * 28)
            r.bg = r:CreateTexture(nil, "BACKGROUND")
            r.bg:SetAllPoints()
            r.bg:SetColorTexture(1, 1, 1, 0.03)
            r.fill = r:CreateTexture(nil, "ARTWORK")
            r.fill:SetPoint("TOPLEFT")
            r.fill:SetPoint("BOTTOMLEFT")
            r.icon = r:CreateTexture(nil, "OVERLAY")
            r.icon:SetSize(18, 18)
            r.icon:SetPoint("LEFT", 6, 0)
            r.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
            r.name = Label(r, "GameFontHighlight", C.text, "LEFT", 30, 0)
            r.name:SetWidth(RW - 120)
            r.name:SetWordWrap(false)
            r.count = Label(r, "GameFontHighlight", C.text, "RIGHT", -8, 0)
            r.count:SetJustifyH("RIGHT")
            d.src[i] = r
        end
        d.more = Label(right, "GameFontHighlightSmall", C.muted, "BOTTOMRIGHT", -16, 10)

        d.empty = Label(right, "GameFontHighlight", C.muted, "CENTER", 0, 0)
        d.empty:SetJustifyH("CENTER")
        d.empty:SetWidth(RW - 60)

        local function BuildEntries(snap)
            local list = {}
            local hideGray = ns.db.settings.hideGray
            local total = snap.value
            for id, it in pairs(snap.items) do
                local gi = ns.db.items[id]
                if gi and gi.link and not (hideGray and (gi.quality or 1) == 0) then
                    local src = {}
                    for key, c in pairs(it.sources) do
                        local gm = ns.db.mobs[key]
                        src[#src + 1] = { name = gm and gm.name or key, cat = gm and gm.cat or "object", c = c }
                    end
                    table.sort(src, function(a, b) if a.c ~= b.c then return a.c > b.c end return a.name < b.name end)
                    local parts = {}
                    for i = 1, math.min(2, #src) do parts[i] = src[i].name .. " " .. src[i].c end
                    if #src > 2 then parts[#parts + 1] = L["and %d more"]:format(#src - 2) end
                    local pct = total > 0 and it.value / total or 0
                    list[#list + 1] = {
                        key = id, itemID = id, quality = gi.quality or 1, name = Colored(gi.link),
                        sub = table.concat(parts, ", "),
                        right = it.value > 0 and ns.Value.Format(it.value) or "-",
                        right2 = (pct > 0 and string.format("%d%%  ", pct * 100 + 0.5) or "") .. "×" .. it.count,
                        activity = it.count,
                        count = it.count, value = it.value, recent = it.last,
                        link = gi.link, srcList = src, pct = pct, unit = it.unit,
                    }
                end
            end
            local mode = SORTS[sortIndex]
            table.sort(list, function(a, b)
                if a[mode] ~= b[mode] then return a[mode] > b[mode] end
                return a.recent > b.recent
            end)
            for i, e in ipairs(list) do e.rank = i end
            return list
        end

        local function ShowDetail(entries)
            local e
            for _, x in ipairs(entries) do if x.key == sel then e = x break end end
            if not e then e = entries[1]; sel = e and e.key end
            local has = e ~= nil
            d.empty:SetText(has and "" or L["Loot something to see it here."])
            for _, w in ipairs({ d.icon, d.name, d.sub, rule, d.shareTitle, d.shareVal, d.bar, d.srcTitle }) do
                w:SetShown(has)
            end
            for _, s in ipairs(d.stats) do s:SetShown(has) end
            if not has then
                for _, r in ipairs(d.src) do r:Hide() end
                d.more:SetText("")
                return
            end

            local gi = ns.db.items[e.key]
            W.SetIcon(d.icon, e.key, e.link, e.quality, e.count, 52)
            d.name:SetText(Colored(e.link))
            d.sub:SetText(L["Rank %d of %d"]:format(e.rank, #entries))

            local labels = { L["This session"], L["Total"], L["Each"], L["Value"] }
            local fmt = ns.Value.Format
            local values = {
                tostring(e.count), tostring(gi and gi.count or e.count),
                fmt(e.unit) ~= "" and fmt(e.unit) or "-", fmt(e.value) ~= "" and fmt(e.value) or "-",
            }
            for i, s in ipairs(d.stats) do
                s.label:SetText(labels[i])
                s.value:SetText(values[i])
            end

            d.shareTitle:SetText(L["Share of the haul"])
            d.shareVal:SetText(string.format("%d%%", e.pct * 100 + 0.5))
            local start
            if d.lastSel ~= sel then start = 0 end
            Ease(d.bar, "w", e.pct, 5, ApplyBar, start)
            d.lastSel = sel

            d.srcTitle:SetText(L["Sources"])
            local shown = math.min(#e.srcList, MAX_SOURCES)
            local top = e.srcList[1] and e.srcList[1].c or 1
            for i = 1, MAX_SOURCES do
                local r = d.src[i]
                local s = e.srcList[i]
                if i <= shown then
                    local cat = ns.CAT[s.cat] or ns.CAT.object
                    r.icon:SetTexture(cat.icon)
                    r.name:SetText(s.name)
                    r.count:SetText(s.c)
                    r.fill:SetColorTexture(cat.color[1], cat.color[2], cat.color[3], 0.22)
                    r.fill:SetWidth(math.max(2, (RW - 32) * s.c / top))
                    r:Show()
                else
                    r:Hide()
                end
            end
            d.more:SetText(#e.srcList > MAX_SOURCES and L["and %d more"]:format(#e.srcList - MAX_SOURCES) or "")
        end

        local function Select(e)
            sel = e.key
            UI.Dirty()
        end

        function obj.Refresh(snap)
            local entries = BuildEntries(snap)
            local found
            for _, x in ipairs(entries) do if x.key == sel then found = true break end end
            if not found then sel = entries[1] and entries[1].key end
            info:SetText(L["%d looted"]:format(snap.looted))
            sortBtn:SetIcon(SORT_ICON[SORTS[sortIndex]])
            sortBtn:SetTip(L["Sort: %s"]:format(SORT_LABEL[SORTS[sortIndex]]), L["Click to change"])
            obj.lv:SetData(entries, sel, Select, L["Loot something to see it here."])
            ShowDetail(entries)
        end

        function obj.SetSel(k) sel = k end

        return obj
    end,
})
