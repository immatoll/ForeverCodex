local ADDON, ns = ...
local L = ns.L
local W = ns.W
local UI = ns.UI
local C = W.C
local Ease = W.Ease

-- Search: type a name, get items and sources from everything ever recorded.
-- For an item the right page ranks where it drops best (items per kill); for a
-- source it lists what it drops and how often.

local LIST_W, GAP = 300, 8
local REL_ROWS = 8

local function Label(parent, template, color, ...)
    local fs = parent:CreateFontString(nil, "OVERLAY", template)
    fs:SetJustifyH("LEFT")
    if color then fs:SetTextColor(unpack(color)) end
    if ... then fs:SetPoint(...) end
    return fs
end

local function ItemName(link) return link and link:match("%[(.-)%]") or "?" end

local function Colored(link)
    local color, name = link:match("|c(%x%x%x%x%x%x%x%x)|Hitem:.-|h%[(.-)%]|h")
    return color and ("|c" .. color .. name .. "|r") or link
end

UI.AddPage({ id = "search", label = L["Search"], icon = "Interface\\Icons\\INV_Misc_Spyglass_02",
    hint = L["Find an item or a source and see where it drops best."],
    Build = function(area)
        local obj = {}
        local frame = CreateFrame("Frame", nil, area)
        obj.frame = frame
        local H = UI.AREA_H
        local RW = UI.AREA_W - LIST_W - GAP
        local sel
        local query = ""
        local kind = "all" -- all | items | sources

        local left = W.NewPlate(frame, C.page)
        left:SetSize(LIST_W, H)
        left:SetPoint("TOPLEFT")

        -- search box: a gilded plate with an edit box inside
        local box = W.NewPlate(left, C.inset)
        box:SetSize(LIST_W - 16, 28)
        box:SetPoint("TOPLEFT", 8, -8)
        local edit = CreateFrame("EditBox", nil, box)
        edit:SetPoint("TOPLEFT", 10, -4)
        edit:SetPoint("BOTTOMRIGHT", -10, 4)
        edit:SetFontObject("GameFontHighlight")
        edit:SetAutoFocus(false)
        edit:SetMaxLetters(40)
        local hint = Label(box, "GameFontHighlight", C.muted, "LEFT", 10, 0)
        hint:SetText(L["Type to search…"])
        edit:SetScript("OnTextChanged", function(self)
            query = self:GetText():lower()
            hint:SetShown(query == "")
            obj.lv:ScrollToTop()
            UI.Dirty()
        end)
        edit:SetScript("OnEscapePressed", function(self) self:SetText(""); self:ClearFocus() end)
        edit:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)
        edit:SetScript("OnEditFocusGained", function() box:SetBackdropBorderColor(unpack(C.gold)) end)
        edit:SetScript("OnEditFocusLost", function() box:SetBackdropBorderColor(unpack(C.goldDim)) end)
        obj.edit = edit

        -- kind filter
        local kinds = {}
        local function Kind(id, icon, label, x)
            local b = W.NewIconButton(left, icon, 24)
            b:SetPoint("TOPLEFT", x, -42)
            b:SetTip(label)
            b:SetScript("OnClick", function() kind = id; obj.lv:ScrollToTop(); UI.Dirty() end)
            b.id = id
            kinds[#kinds + 1] = b
        end
        Kind("all", W.ICON.search, L["All"], 8)
        Kind("items", W.ICON.loot, L["Items"], 36)
        Kind("sources", W.ICON.sword, L["Sources"], 64)
        local info = Label(left, "GameFontHighlightSmall", C.muted, "TOPRIGHT", -10, -47)
        info:SetJustifyH("RIGHT")

        obj.lv = UI.NewListView(left, LIST_W - 14, H - 76, 44)
        obj.lv.frame:SetPoint("TOPLEFT", left, "TOPLEFT", 7, -70)

        -- right page ------------------------------------------------------------
        local right = W.NewPlate(frame, C.page)
        right:SetSize(RW, H)
        right:SetPoint("TOPRIGHT")

        local d = {}
        d.icon = W.NewIcon(right)
        d.icon:SetPoint("TOPLEFT", 16, -16)
        d.srcIconEdge = right:CreateTexture(nil, "ARTWORK")
        d.srcIconEdge:SetSize(52, 52)
        d.srcIconEdge:SetPoint("TOPLEFT", 16, -16)
        d.srcIcon = right:CreateTexture(nil, "OVERLAY")
        d.srcIcon:SetPoint("TOPLEFT", d.srcIconEdge, 2, -2)
        d.srcIcon:SetPoint("BOTTOMRIGHT", d.srcIconEdge, -2, 2)
        d.srcIcon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
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

        d.relTitle = Label(right, "GameFontHighlightSmall", C.muted, "TOPLEFT", 16, -152)
        d.relHead = Label(right, "GameFontHighlightSmall", C.muted, "TOPRIGHT", -16, -152)
        d.relHead:SetJustifyH("RIGHT")
        d.rel = {}
        for i = 1, REL_ROWS do
            local r = CreateFrame("Button", nil, right)
            r:SetSize(RW - 32, 30)
            r:SetPoint("TOPLEFT", 16, -170 - (i - 1) * 32)
            r.bg = r:CreateTexture(nil, "BACKGROUND")
            r.bg:SetAllPoints()
            r.bg:SetColorTexture(1, 1, 1, 0.03)
            r.fill = r:CreateTexture(nil, "ARTWORK")
            r.fill:SetPoint("TOPLEFT")
            r.fill:SetPoint("BOTTOMLEFT")
            r.hl = r:CreateTexture(nil, "OVERLAY")
            r.hl:SetAllPoints()
            r.hl:SetTexture(W.HILITE_TEX)
            r.hl:SetBlendMode("ADD")
            r.hl:SetVertexColor(C.gold[1], C.gold[2], C.gold[3])
            r.hl:SetAlpha(0)
            r.edge = r:CreateTexture(nil, "ARTWORK")
            r.edge:SetSize(22, 22)
            r.edge:SetPoint("LEFT", 6, 0)
            r.icon = r:CreateTexture(nil, "OVERLAY")
            r.icon:SetPoint("TOPLEFT", r.edge, 1, -1)
            r.icon:SetPoint("BOTTOMRIGHT", r.edge, -1, 1)
            r.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
            r.name = Label(r, "GameFontHighlight", C.text, "LEFT", 36, 0)
            r.name:SetWidth(RW - 200)
            r.name:SetWordWrap(false)
            r.count = Label(r, "GameFontHighlightSmall", C.muted, "RIGHT", -92, 0)
            r.count:SetJustifyH("RIGHT")
            r.rate = Label(r, "GameFontHighlight", C.text, "RIGHT", -8, 0)
            r.rate:SetJustifyH("RIGHT")
            r:SetScript("OnEnter", function(self)
                Ease(self, "hl", 1, 16, function(o, v) o.hl:SetAlpha(v * 0.5) end)
                if self.link then
                    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
                    GameTooltip:SetHyperlink(self.link)
                    GameTooltip:Show()
                end
            end)
            r:SetScript("OnLeave", function(self)
                Ease(self, "hl", 0, 16, function(o, v) o.hl:SetAlpha(v * 0.5) end)
                if GameTooltip:GetOwner() == self then GameTooltip:Hide() end
            end)
            r:SetScript("OnClick", function(self)
                -- jump to that source / item in the search results
                if self.jump then
                    sel, kind = self.jump, "all"
                    edit:SetText("")
                    UI.Dirty()
                end
            end)
            d.rel[i] = r
        end
        d.more = Label(right, "GameFontHighlightSmall", C.muted, "BOTTOMRIGHT", -16, 10)
        d.empty = Label(right, "GameFontHighlight", C.muted, "CENTER", 0, 0)
        d.empty:SetJustifyH("CENTER")
        d.empty:SetWidth(RW - 60)

        -- entries -------------------------------------------------------------------
        local function Entries()
            local list = {}
            local q = query
            if kind ~= "sources" then
                for id, gi in pairs(ns.db.items) do
                    local name = ItemName(gi.link)
                    if gi.link and (q == "" or name:lower():find(q, 1, true)) then
                        local best, bestRate, nsrc = nil, 0, 0
                        for key, c in pairs(gi.sources) do
                            local gm = ns.db.mobs[key]
                            if gm and ns.CatOn(gm.cat) then
                                nsrc = nsrc + 1
                                local rate = c / math.max(1, gm.kills)
                                if rate > bestRate then best, bestRate = gm, rate end
                            end
                        end
                        if nsrc > 0 then
                            list[#list + 1] = {
                                key = "i" .. id, itemID = id, quality = gi.quality or 1, name = Colored(gi.link),
                                sub = best and (L["Best"] .. ": " .. (best.name or "?")) or "",
                                right = tostring(gi.count), right2 = ns.Value.Format(ns.Value.Get(id)),
                                sort = gi.count, link = gi.link, kindIsItem = true,
                                tip = function() GameTooltip:SetHyperlink(gi.link) end,
                            }
                        end
                    end
                end
            end
            if kind ~= "items" then
                for key, gm in pairs(ns.db.mobs) do
                    if ns.CatOn(gm.cat) and gm.cat ~= "skin" and (q == "" or (gm.name or key):lower():find(q, 1, true)) then
                        local cat = ns.CAT[gm.cat]
                        list[#list + 1] = {
                            key = "s" .. key, texture = ns.SourceIcon(gm), noIcon = gm.cat == "mob", quality = 1, name = gm.name or key,
                            sub = cat.label .. (gm.zone and (" · " .. gm.zone) or ""),
                            right = tostring(gm.kills), right2 = cat.verb,
                            sort = gm.kills, srcKey = key,
                        }
                    end
                end
            end
            table.sort(list, function(a, b)
                if a.sort ~= b.sort then return a.sort > b.sort end
                return a.name < b.name
            end)
            -- an empty query would list everything: cap it
            if q == "" then for i = #list, 61, -1 do list[i] = nil end end
            return list
        end

        local function SetRel(i, data)
            local r = d.rel[i]
            if not data then r:Hide() return end
            r.link, r.jump = data.link, data.jump
            r.icon:SetTexture(data.icon)
            local c = data.edge or W.QUALITY_COLOR[1]
            r.edge:SetColorTexture(c[1], c[2], c[3], 1)
            r.name:SetText(data.name)
            r.count:SetText(data.count)
            r.rate:SetText(data.rate)
            r.rate:SetTextColor(unpack(data.rateColor or C.text))
            r.fill:SetColorTexture(data.fillColor[1], data.fillColor[2], data.fillColor[3], 0.22)
            r.fill:SetWidth(math.max(2, (RW - 32) * data.frac))
            r:Show()
        end

        local function Show(e)
            local has = e ~= nil
            d.empty:SetText(has and "" or L["Nothing found."])
            for _, w in ipairs({ rule, d.relTitle, d.relHead, d.name, d.sub }) do w:SetShown(has) end
            for _, s in ipairs(d.stats) do s:SetShown(has) end
            d.icon:SetShown(has and e.kindIsItem or false)
            d.srcIconEdge:SetShown(has and not e.kindIsItem)
            d.srcIcon:SetShown(has and not e.kindIsItem)
            d.more:SetText("")
            if not has then for i = 1, REL_ROWS do SetRel(i, nil) end return end
            local fmt = ns.Value.Format

            if e.kindIsItem then
                local id = e.itemID
                local gi = ns.db.items[id]
                W.SetIcon(d.icon, id, gi.link, gi.quality, nil, 52)
                d.name:ClearAllPoints(); d.name:SetPoint("TOPLEFT", 80, -18)
                d.sub:ClearAllPoints(); d.sub:SetPoint("TOPLEFT", 80, -46)
                d.name:SetText(Colored(gi.link))
                local rel = {}
                for key, c in pairs(gi.sources) do
                    local gm = ns.db.mobs[key]
                    if gm and ns.CatOn(gm.cat) then
                        rel[#rel + 1] = { gm = gm, key = key, c = c, rate = c / math.max(1, gm.kills) }
                    end
                end
                table.sort(rel, function(a, b)
                    if a.rate ~= b.rate then return a.rate > b.rate end
                    return a.c > b.c
                end)
                d.sub:SetText(L["%d sources"]:format(#rel))
                local unit = ns.Value.Get(id)
                local labels = { L["Total"], L["Sources"], L["Best rate"], L["Each"] }
                local values = { tostring(gi.count), tostring(#rel),
                    rel[1] and string.format("%.2f", rel[1].rate) or "-", fmt(unit) ~= "" and fmt(unit) or "-" }
                for i, s in ipairs(d.stats) do s.label:SetText(labels[i]); s.value:SetText(values[i]) end
                d.relTitle:SetText(L["Where it drops best"])
                d.relHead:SetText(L["per kill"])
                local top = rel[1] and rel[1].rate or 1
                for i = 1, REL_ROWS do
                    local x = rel[i]
                    if x then
                        local cat = ns.CAT[x.gm.cat]
                        SetRel(i, { icon = cat.icon, edge = cat.color, name = (i == 1 and x.gm.kills >= 5 and "* " or "") .. (x.gm.name or x.key) .. (x.gm.cat == "skin" and (" (" .. cat.label .. ")") or ""),
                            count = x.c .. "× / " .. x.gm.kills, rate = string.format("%.2f", x.rate),
                            rateColor = i == 1 and C.jade or C.text, fillColor = cat.color, frac = x.rate / top,
                            jump = "s" .. x.key })
                    else
                        SetRel(i, nil)
                    end
                end
                if #rel > REL_ROWS then d.more:SetText(L["and %d more"]:format(#rel - REL_ROWS)) end
            else
                local gm = ns.db.mobs[e.srcKey]
                local cat = ns.CAT[gm.cat]
                local hasIcon = gm.cat ~= "mob"
                d.srcIconEdge:SetShown(hasIcon)
                d.srcIcon:SetShown(hasIcon)
                d.srcIcon:SetTexture(cat.icon)
                d.name:ClearAllPoints(); d.name:SetPoint("TOPLEFT", hasIcon and 80 or 16, -18)
                d.sub:ClearAllPoints(); d.sub:SetPoint("TOPLEFT", hasIcon and 80 or 16, -46)
                d.srcIconEdge:SetColorTexture(cat.color[1], cat.color[2], cat.color[3], 1)
                d.name:SetText(gm.name or e.srcKey)
                d.sub:SetText(cat.label .. (gm.zone and (" · " .. gm.zone) or ""))
                local rel, kinds, value = {}, 0, 0
                for id, c in pairs(ns.MergedItems(gm)) do
                    local gi = ns.db.items[id]
                    if gi and gi.link then
                        kinds = kinds + 1
                        value = value + ns.Value.Get(id) * c
                        rel[#rel + 1] = { id = id, gi = gi, c = c, rate = c / math.max(1, gm.kills) }
                    end
                end
                table.sort(rel, function(a, b)
                    if a.rate ~= b.rate then return a.rate > b.rate end
                    return a.id < b.id
                end)
                local avg = gm.kills > 0 and value / gm.kills or 0
                local labels = { cat.verb, L["Items"], L["Value"], L["Avg per"] }
                local values = { tostring(gm.kills), tostring(kinds), fmt(value) ~= "" and fmt(value) or "-",
                    fmt(avg) ~= "" and fmt(avg) or "-" }
                for i, s in ipairs(d.stats) do s.label:SetText(labels[i]); s.value:SetText(values[i]) end
                d.relTitle:SetText(L["What it drops"])
                d.relHead:SetText(L["per kill"])
                local top = rel[1] and rel[1].rate or 1
                for i = 1, REL_ROWS do
                    local x = rel[i]
                    if x then
                        SetRel(i, { icon = W.ItemTexture(x.id), edge = W.QUALITY_COLOR[x.gi.quality or 1], link = x.gi.link,
                            name = Colored(x.gi.link), count = "×" .. x.c, rate = string.format("%.2f", x.rate),
                            fillColor = W.QUALITY_COLOR[x.gi.quality or 1], frac = x.rate / top, jump = "i" .. x.id })
                    else
                        SetRel(i, nil)
                    end
                end
                if #rel > REL_ROWS then d.more:SetText(L["and %d more"]:format(#rel - REL_ROWS)) end
            end
        end

        function obj.Refresh()
            local entries = Entries()
            local found, current
            for _, x in ipairs(entries) do if x.key == sel then found, current = true, x break end end
            if not found then current = entries[1]; sel = current and current.key end
            for _, b in ipairs(kinds) do b:SetActive(b.id == kind) end
            info:SetText(L["%d entries"]:format(#entries))
            obj.lv:SetData(entries, sel, function(e) sel = e.key; UI.Dirty() end, L["Nothing found."])
            Show(current)
        end

        function obj.SetSel(k) sel = k end

        return obj
    end,
})
