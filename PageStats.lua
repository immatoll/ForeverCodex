local ADDON, ns = ...
local L = ns.L
local W = ns.W
local UI = ns.UI
local C = W.C
local Ease = W.Ease

-- Statistics: four plates. Value over time (this session), where the value
-- comes from (by category), a heatmap of value by zone and hour of day (all
-- time) and the creatures that pay best per kill.

local GAP = 8
local BARS = 28
local HEAT_ROWS = 6
local BEST_ROWS = 7

local function Label(parent, template, color, ...)
    local fs = parent:CreateFontString(nil, "OVERLAY", template)
    fs:SetJustifyH("LEFT")
    if color then fs:SetTextColor(unpack(color)) end
    if ... then fs:SetPoint(...) end
    return fs
end

local function Panel(parent, title, x, y, w, h)
    local p = W.NewPlate(parent, C.page)
    p:SetSize(w, h)
    p:SetPoint("TOPLEFT", x, -y)
    p.title = p:CreateFontString(nil, "OVERLAY")
    p.title:SetFontObject(UI.titleFontObject)
    p.title:SetPoint("TOPLEFT", 14, -12)
    p.title:SetTextColor(1, 0.88, 0.5)
    p.title:SetText(title)
    local rule = p:CreateTexture(nil, "ARTWORK")
    rule:SetPoint("TOPLEFT", 12, -34)
    rule:SetPoint("TOPRIGHT", -12, -34)
    rule:SetHeight(1)
    rule:SetColorTexture(C.goldDim[1], C.goldDim[2], C.goldDim[3], 0.5)
    return p
end

local function Tip(owner, title, ...)
    GameTooltip:SetOwner(owner, "ANCHOR_TOP")
    GameTooltip:AddLine(title, 1, 0.85, 0.4)
    for i = 1, select("#", ...) do
        local line = select(i, ...)
        if line then GameTooltip:AddLine(line, 0.85, 0.85, 0.85) end
    end
    GameTooltip:Show()
end

UI.AddPage({ id = "stats", label = L["Statistics"], icon = "Interface\\Icons\\INV_Misc_Note_01",
    hint = L["Value over time, sources, heatmap and best creatures."],
    Build = function(area)
        local obj = {}
        local frame = CreateFrame("Frame", nil, area)
        obj.frame = frame
        local PW = (UI.AREA_W - GAP) / 2
        local PH = (UI.AREA_H - GAP) / 2
        local IW = PW - 28 -- inner width

        -- 1: value over time ----------------------------------------------
        local timeline = Panel(frame, L["Value over time"], 0, 0, PW, PH)
        local chartH = PH - 100
        local bw = math.floor((IW - (BARS - 1) * 2) / BARS)
        local bars = {}
        for i = 1, BARS do
            local b = CreateFrame("Button", nil, timeline)
            b:SetSize(bw, chartH)
            b:SetPoint("BOTTOMLEFT", 14 + (i - 1) * (bw + 2), 34)
            b.bg = b:CreateTexture(nil, "BACKGROUND")
            b.bg:SetAllPoints()
            b.bg:SetColorTexture(1, 1, 1, 0.04)
            b.fill = b:CreateTexture(nil, "ARTWORK")
            b.fill:SetPoint("BOTTOMLEFT")
            b.fill:SetPoint("BOTTOMRIGHT")
            b.fill:SetHeight(1)
            b.glow = b:CreateTexture(nil, "OVERLAY")
            b.glow:SetAllPoints()
            b.glow:SetColorTexture(1, 1, 1, 1)
            b.glow:SetBlendMode("ADD")
            b.glow:SetAlpha(0)
            b:SetScript("OnEnter", function(self)
                Ease(self, "hv", 1, 18, function(o, v) o.glow:SetAlpha(v * 0.18) end)
                Tip(self, self.when or "", self.what)
            end)
            b:SetScript("OnLeave", function(self)
                Ease(self, "hv", 0, 18, function(o, v) o.glow:SetAlpha(v * 0.18) end)
                GameTooltip:Hide()
            end)
            bars[i] = b
        end
        timeline.max = Label(timeline, "GameFontHighlightSmall", C.muted, "TOPRIGHT", -14, -42)
        timeline.max:SetJustifyH("RIGHT")
        timeline.from = Label(timeline, "GameFontHighlightSmall", C.muted, "BOTTOMLEFT", 14, 12)
        timeline.to = Label(timeline, "GameFontHighlightSmall", C.muted, "BOTTOMRIGHT", -14, 12)
        timeline.to:SetJustifyH("RIGHT")
        timeline.empty = Label(timeline, "GameFontHighlight", C.muted, "CENTER", 0, 0)
        timeline.empty:SetJustifyH("CENTER")
        timeline.empty:SetWidth(IW - 30)

        -- 2: sources by category ----------------------------------------------
        local sources = Panel(frame, L["Where it comes from"], PW + GAP, 0, PW, PH)
        sources.bar = CreateFrame("Frame", nil, sources)
        sources.bar:SetSize(IW, 18)
        sources.bar:SetPoint("TOPLEFT", 14, -44)
        sources.bar.bg = sources.bar:CreateTexture(nil, "BACKGROUND")
        sources.bar.bg:SetAllPoints()
        sources.bar.bg:SetColorTexture(1, 1, 1, 0.04)
        sources.segs = {}
        sources.rows = {}
        for i, cat in ipairs(ns.CATS) do
            local seg = sources.bar:CreateTexture(nil, "ARTWORK")
            seg:SetHeight(18)
            seg:SetColorTexture(ns.CAT[cat].color[1], ns.CAT[cat].color[2], ns.CAT[cat].color[3], 1)
            sources.segs[cat] = seg
            local r = CreateFrame("Frame", nil, sources)
            r:SetSize(IW, 18)
            r:SetPoint("TOPLEFT", 14, -70 - (i - 1) * 20)
            r.swatch = r:CreateTexture(nil, "ARTWORK")
            r.swatch:SetSize(12, 12)
            r.swatch:SetPoint("LEFT", 0, 0)
            r.swatch:SetColorTexture(ns.CAT[cat].color[1], ns.CAT[cat].color[2], ns.CAT[cat].color[3], 1)
            r.name = Label(r, "GameFontHighlight", C.text, "LEFT", 20, 0)
            r.value = Label(r, "GameFontHighlight", C.text, "RIGHT", -52, 0)
            r.value:SetJustifyH("RIGHT")
            r.pct = Label(r, "GameFontHighlight", C.muted, "RIGHT", 0, 0)
            r.pct:SetJustifyH("RIGHT")
            r.cat = cat
            sources.rows[i] = r
        end
        sources.empty = Label(sources, "GameFontHighlight", C.muted, "CENTER", 0, -10)
        sources.empty:SetJustifyH("CENTER")
        sources.empty:SetWidth(IW - 30)

        -- 3: heatmap -----------------------------------------------------------
        local heat = Panel(frame, L["Heatmap: value by zone and hour"], 0, PH + GAP, PW, PH)
        local LABEL_W = 78
        local cw = math.floor((IW - LABEL_W - 23) / 24)
        local ch = math.floor((PH - 100) / HEAT_ROWS) - 2
        heat.cells, heat.labels = {}, {}
        for row = 1, HEAT_ROWS do
            local lbl = Label(heat, "GameFontHighlightSmall", C.text, "TOPLEFT", 14, -58 - (row - 1) * (ch + 2) - 2)
            lbl:SetWidth(LABEL_W - 6)
            lbl:SetWordWrap(false)
            heat.labels[row] = lbl
            heat.cells[row] = {}
            for hour = 0, 23 do
                local b = CreateFrame("Button", nil, heat)
                b:SetSize(cw, ch)
                b:SetPoint("TOPLEFT", 14 + LABEL_W + hour * (cw + 1), -56 - (row - 1) * (ch + 2))
                b.bg = b:CreateTexture(nil, "BACKGROUND")
                b.bg:SetAllPoints()
                b.fill = b:CreateTexture(nil, "ARTWORK")
                b.fill:SetAllPoints()
                b.glow = b:CreateTexture(nil, "OVERLAY")
                b.glow:SetAllPoints()
                b.glow:SetColorTexture(1, 1, 1, 1)
                b.glow:SetBlendMode("ADD")
                b.glow:SetAlpha(0)
                b.hour = hour
                b:SetScript("OnEnter", function(self)
                    Ease(self, "hv", 1, 18, function(o, v) o.glow:SetAlpha(v * 0.25) end)
                    Tip(self, self.zone or "", string.format("%02d:00 – %02d:59", self.hour, self.hour),
                        self.amount and self.amount > 0 and ns.Value.Format(self.amount) or L["nothing yet"])
                end)
                b:SetScript("OnLeave", function(self)
                    Ease(self, "hv", 0, 18, function(o, v) o.glow:SetAlpha(v * 0.25) end)
                    GameTooltip:Hide()
                end)
                heat.cells[row][hour] = b
            end
        end
        heat.hours = {}
        for _, h in ipairs({ 0, 6, 12, 18 }) do
            local t = Label(heat, "GameFontHighlightSmall", C.muted, "TOPLEFT", 14 + LABEL_W + h * (cw + 1), -42)
            t:SetText(string.format("%02d", h))
        end
        heat.now = heat:CreateTexture(nil, "OVERLAY")
        heat.now:SetSize(cw, 2)
        heat.now:SetColorTexture(unpack(C.gold))
        heat.empty = Label(heat, "GameFontHighlight", C.muted, "CENTER", 0, -10)
        heat.empty:SetJustifyH("CENTER")
        heat.empty:SetWidth(IW - 30)

        -- 4: best creatures -------------------------------------------------------
        local best = Panel(frame, L["Best creatures per kill"], PW + GAP, PH + GAP, PW, PH)
        best.rows = {}
        for i = 1, BEST_ROWS do
            local r = CreateFrame("Frame", nil, best)
            r:SetSize(IW, 22)
            r:SetPoint("TOPLEFT", 14, -44 - (i - 1) * 24)
            r.bg = r:CreateTexture(nil, "BACKGROUND")
            r.bg:SetAllPoints()
            r.bg:SetColorTexture(1, 1, 1, 0.03)
            r.fill = r:CreateTexture(nil, "ARTWORK")
            r.fill:SetPoint("TOPLEFT")
            r.fill:SetPoint("BOTTOMLEFT")
            r.fill:SetColorTexture(C.gold[1], C.gold[2], C.gold[3], 0.2)
            r.rank = Label(r, "GameFontNormal", C.gold, "LEFT", 6, 0)
            r.name = Label(r, "GameFontHighlight", C.text, "LEFT", 26, 0)
            r.name:SetWidth(IW - 130)
            r.name:SetWordWrap(false)
            r.value = Label(r, "GameFontHighlight", C.text, "RIGHT", -8, 0)
            r.value:SetJustifyH("RIGHT")
            best.rows[i] = r
        end
        best.empty = Label(best, "GameFontHighlight", C.muted, "CENTER", 0, -10)
        best.empty:SetJustifyH("CENTER")
        best.empty:SetWidth(IW - 30)

        -- refresh ----------------------------------------------------------------
        local function ApplyBarHeight(b, v) b.fill:SetHeight(math.max(1, v)) end

        local function RefreshTimeline()
            local s = ns.session
            local nowBucket = s.start and (math.floor(ns.SessionElapsed() / ns.TIMELINE_BUCKET) + 1) or 1
            local first = math.max(1, nowBucket - BARS + 1)
            local max = 0
            for i = 1, BARS do max = math.max(max, s.timeline[first + i - 1] or 0) end
            for i = 1, BARS do
                local b = bars[i]
                local bucket = first + i - 1
                local v = s.timeline[bucket] or 0
                local frac = max > 0 and v / max or 0
                b.fill:SetColorTexture(unpack(v == max and max > 0 and C.jade or C.gold))
                b.fill:SetAlpha(v > 0 and 1 or 0)
                Ease(b, "h", frac * (chartH - 4), 8, ApplyBarHeight)
                local minutes = (bucket - 1) * ns.TIMELINE_BUCKET / 60
                b.when = string.format("%d–%d min", minutes, minutes + ns.TIMELINE_BUCKET / 60)
                b.what = v > 0 and ns.Value.Format(v) or L["nothing yet"]
            end
            timeline.max:SetText(max > 0 and ns.Value.Format(max) or "")
            timeline.from:SetText(string.format("%d min", (first - 1) * ns.TIMELINE_BUCKET / 60))
            timeline.to:SetText(L["now"])
            timeline.empty:SetText(max == 0 and L["Loot something to see the curve."] or "")
        end

        local function RefreshSources(snap)
            local total = 0
            for _, cat in ipairs(ns.CATS) do total = total + (snap.catValue[cat] or 0) end
            local x = 0
            local rowIndex = 0
            for _, cat in ipairs(ns.CATS) do
                local v = snap.catValue[cat] or 0
                local seg = sources.segs[cat]
                local row = sources.rows[rowIndex + 1]
                if v > 0 and total > 0 then
                    local w = math.max(2, IW * v / total)
                    seg:ClearAllPoints()
                    seg:SetPoint("LEFT", sources.bar, "LEFT", x, 0)
                    seg:SetWidth(w)
                    seg:Show()
                    x = x + w
                    rowIndex = rowIndex + 1
                    row.name:SetText(ns.CAT[cat].label)
                    row.value:SetText(ns.Value.Format(v))
                    row.pct:SetText(string.format("%d%%", v / total * 100 + 0.5))
                    row:Show()
                else
                    seg:Hide()
                end
            end
            for i = rowIndex + 1, #sources.rows do sources.rows[i]:Hide() end
            sources.empty:SetText(total == 0 and L["Loot something to see the split."] or "")
        end

        local function RefreshHeat()
            local zones = {}
            for zone, hours in pairs(ns.db.heat) do
                local sum = 0
                for _, v in pairs(hours) do sum = sum + v end
                zones[#zones + 1] = { zone = zone, hours = hours, sum = sum }
            end
            table.sort(zones, function(a, b) return a.sum > b.sum end)
            local max = 0
            for row = 1, math.min(HEAT_ROWS, #zones) do
                for _, v in pairs(zones[row].hours) do max = math.max(max, v) end
            end
            for row = 1, HEAT_ROWS do
                local z = zones[row]
                heat.labels[row]:SetText(z and z.zone or "")
                for hour = 0, 23 do
                    local b = heat.cells[row][hour]
                    local v = z and z.hours[hour] or 0
                    b.zone, b.amount = z and z.zone or "", v
                    b.bg:SetColorTexture(1, 1, 1, z and 0.04 or 0)
                    if v > 0 and max > 0 then
                        local t = math.sqrt(v / max)
                        b.fill:SetColorTexture(C.goldDim[1] + (C.gold[1] - C.goldDim[1]) * t,
                            C.goldDim[2] + (C.gold[2] - C.goldDim[2]) * t,
                            C.goldDim[3] + (C.gold[3] - C.goldDim[3]) * t, 0.25 + 0.75 * t)
                    else
                        b.fill:SetColorTexture(0, 0, 0, 0)
                    end
                    b:SetShown(z ~= nil)
                end
            end
            local hour = tonumber(date("%H")) or 0
            heat.now:ClearAllPoints()
            heat.now:SetPoint("TOPLEFT", heat, "TOPLEFT", 14 + LABEL_W + hour * (cw + 1), -52)
            heat.now:SetShown(#zones > 0)
            heat.empty:SetText(#zones == 0 and L["The map fills as you loot, hour by hour."] or "")
        end

        local function RefreshBest()
            local list = {}
            for key, gm in pairs(ns.db.mobs) do
                if gm.cat == "mob" and ns.CatOn("mob") and gm.kills >= 3 then
                    local v = 0
                    for id, c in pairs(ns.MergedItems(gm)) do v = v + ns.Value.Get(id) * c end
                    if v > 0 then list[#list + 1] = { name = gm.name or key, avg = v / gm.kills, kills = gm.kills } end
                end
            end
            table.sort(list, function(a, b) return a.avg > b.avg end)
            local top = list[1] and list[1].avg or 1
            for i = 1, BEST_ROWS do
                local r, e = best.rows[i], list[i]
                if e then
                    r.rank:SetText(i)
                    r.name:SetText(e.name)
                    r.value:SetText(ns.Value.Format(e.avg))
                    r.fill:SetWidth(math.max(2, IW * e.avg / top))
                    r:Show()
                else
                    r:Hide()
                end
            end
            best.empty:SetText(#list == 0 and L["Needs a few kills with priced loot."] or "")
        end

        function obj.Refresh(snap)
            RefreshTimeline()
            RefreshSources(snap)
            RefreshHeat()
            RefreshBest()
        end

        return obj
    end,
})
