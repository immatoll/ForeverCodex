local ADDON, ns = ...
local L = ns.L
local W = ns.W
local UI = ns.UI
local C = W.C
local Ease = W.Ease

-- History: every finished session is kept as a summary. Left the list, right
-- the numbers of the selected one, how its value was made up, and the best loot.

local LIST_W, GAP = 300, 8
local MAX_CATS = 7

local function Label(parent, template, color, ...)
    local fs = parent:CreateFontString(nil, "OVERLAY", template)
    fs:SetJustifyH("LEFT")
    if color then fs:SetTextColor(unpack(color)) end
    if ... then fs:SetPoint(...) end
    return fs
end

local function Stamp(t) return date("%d.%m.%Y  %H:%M", t) end

UI.AddPage({ id = "history", label = L["History"], icon = "Interface\\Icons\\INV_Misc_Book_09",
    hint = L["Every finished session, with its numbers and best loot."],
    Build = function(area)
        local obj = {}
        local frame = CreateFrame("Frame", nil, area)
        obj.frame = frame
        local H = UI.AREA_H
        local RW = UI.AREA_W - LIST_W - GAP
        local sel
        local sortIndex = 1
        local SORTS = { "recent", "perHour", "value" }
        local SORT_LABEL = { recent = L["Recent"], perHour = L["Per hour"], value = L["Value"] }

        local left = W.NewPlate(frame, C.page)
        left:SetSize(LIST_W, H)
        left:SetPoint("TOPLEFT")
        local sortBtn = W.NewIconButton(left, W.ICON.recent, 24)
        sortBtn:SetPoint("TOPRIGHT", -8, -8)
        local SORT_ICON = { recent = W.ICON.recent, perHour = W.ICON.rate, value = W.ICON.coin }
        sortBtn:SetScript("OnClick", function()
            sortIndex = sortIndex % #SORTS + 1
            obj.lv:ScrollToTop()
            UI.Dirty()
        end)
        local info = Label(left, "GameFontHighlightSmall", C.muted, "TOPLEFT", 12, -13)
        obj.lv = UI.NewListView(left, LIST_W - 14, H - 44, 44)
        obj.lv.frame:SetPoint("TOPLEFT", left, "TOPLEFT", 7, -38)

        local right = W.NewPlate(frame, C.page)
        right:SetSize(RW, H)
        right:SetPoint("TOPRIGHT")

        local d = {}
        d.title = right:CreateFontString(nil, "OVERLAY")
        d.title:SetFontObject(UI.titleFontObject)
        d.title:SetPoint("TOPLEFT", 16, -16)
        d.title:SetTextColor(1, 0.88, 0.5)
        d.badge = Label(right, "GameFontNormal", C.jade, "TOPRIGHT", -16, -20)
        d.badge:SetJustifyH("RIGHT")
        d.sub = Label(right, "GameFontHighlightSmall", C.muted, "TOPLEFT", 16, -42)
        d.sub:SetWidth(RW - 32)
        local rule = right:CreateTexture(nil, "ARTWORK")
        rule:SetPoint("TOPLEFT", 16, -62)
        rule:SetPoint("TOPRIGHT", -16, -62)
        rule:SetHeight(1)
        rule:SetColorTexture(C.goldDim[1], C.goldDim[2], C.goldDim[3], 0.5)

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

        d.bestTitle = Label(right, "GameFontHighlightSmall", C.muted, "TOPLEFT", 16, -134)
        d.grid = W.NewIconGrid(right, 34, 5, math.floor((RW - 32) / 39), 1)
        d.grid.frame:SetPoint("TOPLEFT", 16, -152)

        d.catTitle = Label(right, "GameFontHighlightSmall", C.muted, "TOPLEFT", 16, -204)
        d.bar = CreateFrame("Frame", nil, right)
        d.bar:SetSize(RW - 32, 16)
        d.bar:SetPoint("TOPLEFT", 16, -222)
        d.bar.bg = d.bar:CreateTexture(nil, "BACKGROUND")
        d.bar.bg:SetAllPoints()
        d.bar.bg:SetColorTexture(1, 1, 1, 0.04)
        d.segs, d.legend = {}, {}
        for i, cat in ipairs(ns.CATS) do
            local seg = d.bar:CreateTexture(nil, "ARTWORK")
            seg:SetHeight(16)
            seg:SetColorTexture(ns.CAT[cat].color[1], ns.CAT[cat].color[2], ns.CAT[cat].color[3], 1)
            d.segs[cat] = seg
            local r = CreateFrame("Frame", nil, right)
            r:SetSize((RW - 40) / 2, 18)
            r:SetPoint("TOPLEFT", 16 + ((i - 1) % 2) * ((RW - 32) / 2), -246 - math.floor((i - 1) / 2) * 20)
            r.swatch = r:CreateTexture(nil, "ARTWORK")
            r.swatch:SetSize(10, 10)
            r.swatch:SetPoint("LEFT")
            r.swatch:SetColorTexture(ns.CAT[cat].color[1], ns.CAT[cat].color[2], ns.CAT[cat].color[3], 1)
            r.text = Label(r, "GameFontHighlightSmall", C.text, "LEFT", 16, 0)
            d.legend[cat] = r
        end

        d.zoneTitle = Label(right, "GameFontHighlightSmall", C.muted, "TOPLEFT", 16, -336)
        d.zones = Label(right, "GameFontHighlight", C.text, "TOPLEFT", 16, -354)
        d.zones:SetWidth(RW - 32)
        d.zones:SetSpacing(4)

        -- delete (two clicks)
        d.del = W.NewIconButton(right, W.ICON.clear, 28)
        d.del:SetPoint("BOTTOMRIGHT", -14, 12)
        d.del:SetTip(L["Delete session"])
        local armed
        d.del:SetScript("OnClick", function(self)
            if not obj.current then return end
            if armed then
                armed = nil
                for i, h in ipairs(ns.db.history) do
                    if h == obj.current then table.remove(ns.db.history, i) break end
                end
                sel = nil
                self.icon:SetVertexColor(1, 1, 1)
                self:SetTip(L["Delete session"])
                UI.Dirty()
            else
                armed = true
                self.icon:SetVertexColor(1, 0.4, 0.35)
                self:SetTip(L["Sure? Click again"])
                C_Timer.After(3, function()
                    if armed then
                        armed = nil
                        self.icon:SetVertexColor(1, 1, 1)
                        self:SetTip(L["Delete session"])
                    end
                end)
            end
        end)

        d.empty = Label(right, "GameFontHighlight", C.muted, "CENTER", 0, 0)
        d.empty:SetJustifyH("CENTER")
        d.empty:SetWidth(RW - 60)

        local function Entries()
            local list = {}
            local bestRate = 0
            for _, h in ipairs(ns.db.history) do bestRate = math.max(bestRate, h.perHour or 0) end
            local mode = SORTS[sortIndex]
            for i, h in ipairs(ns.db.history) do
                local record = bestRate > 0 and h.perHour == bestRate
                list[#list + 1] = {
                    key = tostring(h.t) .. "-" .. math.floor((h.dur or 0)), h = h, order = i,
                    name = Stamp(h.t),
                    sub = W.Duration(h.dur) .. " · " .. L["%d kills"]:format(h.kills or 0),
                    texture = "Interface\\Icons\\INV_Misc_Book_09", quality = record and 4 or 1,
                    right = ns.Value.Format(h.value) ~= "" and ns.Value.Format(h.value) or "-",
                    right2 = ns.Value.Format(h.perHour or 0) ~= "" and (ns.Value.Format(h.perHour) .. "/h") or "",
                    record = record,
                    value = h.value, perHour = h.perHour or 0, recent = -i,
                }
            end
            table.sort(list, function(a, b)
                if a[mode] ~= b[mode] then return a[mode] > b[mode] end
                return a.order < b.order
            end)
            return list
        end

        local function Show(e)
            local has = e ~= nil
            d.empty:SetText(has and "" or L["Finished sessions appear here."])
            for _, w in ipairs({ d.title, d.sub, rule, d.bestTitle, d.grid.frame, d.catTitle, d.bar,
                d.zoneTitle, d.zones, d.del }) do w:SetShown(has) end
            for _, s in ipairs(d.stats) do s:SetShown(has) end
            for _, r in pairs(d.legend) do r:Hide() end
            d.badge:SetText("")
            if not has then obj.current = nil return end

            local h = e.h
            obj.current = h
            d.title:SetText(Stamp(h.t))
            d.badge:SetText(e.record and ("* " .. L["Record"]) or "")
            d.sub:SetText(L["%d items looted"]:format(h.looted or 0))
            local fmt = ns.Value.Format
            local labels = { L["Duration"], L["Per hour"], L["Total value"], L["Kills"] }
            local values = { W.Duration(h.dur), fmt(h.perHour or 0) ~= "" and fmt(h.perHour) or "-",
                fmt(h.value) ~= "" and fmt(h.value) or "-", tostring(h.kills or 0) }
            for i, s in ipairs(d.stats) do
                s.label:SetText(labels[i])
                s.value:SetText(values[i])
            end

            d.bestTitle:SetText(L["Best loot"])
            local items = {}
            for _, t in ipairs(h.top or {}) do
                local gi = ns.db.items[t.id]
                items[#items + 1] = { id = t.id, link = gi and gi.link, quality = gi and gi.quality or 1, count = t.count }
            end
            d.grid:Set(items)

            d.catTitle:SetText(L["Where it comes from"])
            local total = 0
            for _, cat in ipairs(ns.CATS) do total = total + ((h.cats or {})[cat] or 0) end
            local x, legendIndex = 0, 0
            local BARW = RW - 32
            for _, cat in ipairs(ns.CATS) do
                local v = (h.cats or {})[cat] or 0
                local seg = d.segs[cat]
                if v > 0 and total > 0 then
                    local w = math.max(2, BARW * v / total)
                    seg:ClearAllPoints()
                    seg:SetPoint("LEFT", d.bar, "LEFT", x, 0)
                    seg:SetWidth(w)
                    seg:Show()
                    x = x + w
                    legendIndex = legendIndex + 1
                    local r = d.legend[cat]
                    r.text:SetText(ns.CAT[cat].label .. "  " .. string.format("%d%%", v / total * 100 + 0.5))
                    r:Show()
                else
                    seg:Hide()
                end
            end

            d.zoneTitle:SetText(L["Areas"])
            local zones = {}
            for _, z in ipairs(h.zones or {}) do zones[#zones + 1] = z.zone end
            d.zones:SetText(#zones > 0 and table.concat(zones, "\n") or "-")
        end

        function obj.Refresh()
            local entries = Entries()
            local found, current
            for _, x in ipairs(entries) do if x.key == sel then found, current = true, x break end end
            if not found then current = entries[1]; sel = current and current.key end
            info:SetText(L["%d sessions"]:format(#entries))
            sortBtn:SetIcon(SORT_ICON[SORTS[sortIndex]])
            sortBtn:SetTip(L["Sort: %s"]:format(SORT_LABEL[SORTS[sortIndex]]), L["Click to change"])
            obj.lv:SetData(entries, sel, function(e) sel = e.key; UI.Dirty() end, L["Finished sessions appear here."])
            Show(current)
        end

        return obj
    end,
})
