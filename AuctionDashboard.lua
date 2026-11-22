local ADDON, ns = ...
local L = ns.L
local W = ns.W
local C = W.C

-- The first page of the auction house tab: a dashboard. What you are worth, what in your bags is worth a look (and what
-- to do with it), where the market moves (cheap now / rising) and which of your recipes pay. It is made by
-- AuctionTab.lua (D.Build) and only reads: prices from the scans, items from the account data.

local D = {}
ns.AuctionDash = D

local FEE = 0.05          -- the auction house keeps this much of a sale
local ROW_H = 20
local MIN_PRICE = 100     -- copper: cheaper things do not make a market worth showing
local GetInfo = GetItemInfo or (C_Item and C_Item.GetItemInfo)
local GREY, GREEN, AMBER, RED, JADE = "|cff8a806e", "|cff66dbb0", "|cffffa63d", "|cffff7a6b", "|cff66dbb0"

local function Money(copper, tint)
    if not copper or copper <= 0 then return GREY .. "–|r" end
    return ns.Value.Format(copper, tint)
end

local function Coloured(q, text)
    local c = ITEM_QUALITY_COLORS and ITEM_QUALITY_COLORS[q or 1]
    if not c then return text end
    return ("|cff%02x%02x%02x%s|r"):format(c.r * 255 + 0.5, c.g * 255 + 0.5, c.b * 255 + 0.5, text)
end

local function Pct(v)
    local text = ("%+d %%"):format(math.floor(math.abs(v) + 0.5) * (v < 0 and -1 or 1))
    return (v <= -10 and GREEN or (v >= 10 and AMBER or GREY)) .. text .. "|r"
end

-- Name, rarity and picture of an item. Once known they are kept (a name that the game cannot give for a moment must not turn
-- back into an id): in memory, and the saved list of the auction house tab ("sell|rarity|level|name") is read first.
local memo = {}
local function Item(id)
    local m = memo[id]
    if m then return m[1], m[2], m[3] end
    local name, q, icon
    local cache = ns.db and ns.db.itemCache
    local hit = cache and cache[id]
    if hit then
        local _, quality, _, nm = hit:match("^(%d+)|(%d+)|(%d+)|(.*)$")
        if nm then name, q = nm, tonumber(quality) end
    end
    if not name then
        local n, _, qq, _, _, _, _, _, _, ic = GetInfo(id)
        if n then name, q, icon = n, qq, ic end
    end
    if not name then
        if C_Item and C_Item.RequestLoadItemDataByID then pcall(C_Item.RequestLoadItemDataByID, id) end
        return nil, nil, (C_Item and C_Item.GetItemIconByID and C_Item.GetItemIconByID(id)) or nil
    end
    icon = icon or (C_Item and C_Item.GetItemIconByID and C_Item.GetItemIconByID(id)) or nil
    memo[id] = { name, q, icon }
    return name, q, icon
end

-- a card: a plate with a title and rows (a picture, a name, up to three figures on the right)
local function NewCard(parent, title, widths)
    local card = W.NewPlate(parent, C.plate)
    card.title = card:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    card.title:SetPoint("TOPLEFT", 10, -8)
    card.title:SetText(title)
    card.title:SetTextColor(C.gold[1], C.gold[2], C.gold[3])
    card.note = card:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    card.note:SetPoint("TOPRIGHT", -10, -10)
    card.note:SetTextColor(unpack(C.muted))
    card.empty = card:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    card.empty:SetPoint("TOPLEFT", 12, -34)
    card.empty:SetPoint("RIGHT", -12, 0)
    card.empty:SetJustifyH("LEFT")
    card.empty:SetWordWrap(true)
    card.empty:SetTextColor(unpack(C.muted))
    card.rows = {}
    for i = 1, 14 do
        local r = CreateFrame("Button", nil, card)
        r:SetHeight(ROW_H)
        r:SetPoint("TOPLEFT", 6, -(30 + (i - 1) * ROW_H))
        r:SetPoint("TOPRIGHT", -6, -(30 + (i - 1) * ROW_H))
        r.hl = r:CreateTexture(nil, "BACKGROUND")
        r.hl:SetAllPoints()
        r.hl:SetColorTexture(1, 0.85, 0.4, 0.10)
        r.hl:Hide()
        r.icon = r:CreateTexture(nil, "ARTWORK")
        r.icon:SetSize(16, 16)
        r.icon:SetPoint("LEFT", 4, 0)
        r.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
        r.cell = {}
        local x = 4
        for k = #widths, 1, -1 do -- the figures from the right edge: the last one first
            local fs = r:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
            local wd = math.max(1, widths[k] or 1)
            fs:SetPoint("RIGHT", r, "RIGHT", -x, 0)
            fs:SetWidth(wd)
            fs:SetJustifyH("RIGHT")
            fs:SetWordWrap(false)
            r.cell[k] = fs
            x = x + wd + 6
        end
        card.nameInset = x
        r.name = r:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        r.name:SetPoint("LEFT", r.icon, "RIGHT", 6, 0)
        r.name:SetPoint("RIGHT", r, "RIGHT", -x, 0)
        r.name:SetJustifyH("LEFT")
        r.name:SetWordWrap(false)
        r:SetScript("OnEnter", function(self)
            self.hl:Show()
            if self.id then
                GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
                GameTooltip:SetHyperlink("item:" .. self.id)
                if ns.TipItem then ns.TipItem(GameTooltip, self.id) end
                GameTooltip:Show()
            elseif self.tip then
                GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
                GameTooltip:SetText(self.tip, 1, 0.85, 0.4, true)
                GameTooltip:Show()
            end
        end)
        r:SetScript("OnLeave", function(self) self.hl:Hide(); GameTooltip:Hide() end)
        card.rows[i] = r
    end
    card.shown = 0
    -- fills the rows from a list of { id, icon, name, a, b, c, tip }; as many as fit
    function card:Fill(list, note, emptyText)
        local fit = math.min(self.fit or 6, 6)
        self.note:SetText(note or "")
        for i, r in ipairs(self.rows) do
            local e = list[i]
            if e and i <= fit then
                r.id, r.tip = e.id, e.tip
                r.icon:SetShown(e.icon ~= nil)
                if e.icon then r.icon:SetTexture(e.icon) end
                r.name:ClearAllPoints()
                r.name:SetPoint("LEFT", e.icon and r.icon or r, e.icon and "RIGHT" or "LEFT", e.icon and 6 or 8, 0)
                r.name:SetPoint("RIGHT", r, "RIGHT", -self.nameInset, 0)
                r.name:SetText(e.name or "")
                r.cell[1]:SetText(e.a or "")
                r.cell[2]:SetText(e.b or "")
                r.cell[3]:SetText(e.c or "")
                if r.cell[4] then r.cell[4]:SetText(e.d or "") end
                r:Show()
            else
                r.id, r.tip = nil, nil
                r:Hide()
            end
        end
        self.empty:SetText((#list == 0) and (emptyText or "") or "")
    end
    return card
end

-- data ------------------------------------------------------------------------------------------------------------------

local function WealthList()
    local acc = ns.Acc
    if not (acc and acc.Enabled and acc.Enabled()) then return {}, L["Account tracking is off: switch it on in the settings to see your wealth."] end
    local t = acc.Totals()
    local chars = acc.Chars()
    local ahValue, ahCount, mail = 0, 0, 0
    for _, rec in ipairs(chars) do
        for _, a in ipairs(rec.auctions and rec.auctions.list or {}) do ahValue = ahValue + (a.buyout or 0); ahCount = ahCount + 1 end
        for _, m in ipairs(rec.mail and rec.mail.list or {}) do mail = mail + (m.money or 0) end
    end
    local list = {
        { name = L["Total worth"], c = Money(t.worth) },
        { name = L["Cash"], c = Money(t.money) },
        { name = L["Items"], c = Money((t.worth or 0) - (t.money or 0)) },
    }
    if ahValue + mail > 0 then list[#list + 1] = { name = L["In auctions and mail"], c = Money(ahValue + mail) } end
    return list, nil
end

-- What in the bags is worth a look: the item, how many, what it fetches on the auction house (each) and what that is over a vendor's
-- price, for all of them. Sorted by that gain; only what has an auction price.
local function Gain(v)
    if v == nil then return GREY .. "–|r" end
    if v > 0 then return Money(v, GREEN) end
    if v < 0 then return "-" .. Money(-v, RED) end
    return GREY .. "0|r"
end

local function BagList()
    local acc = ns.Acc
    if not (acc and acc.Enabled and acc.Enabled()) then return {}, L["Account tracking is off."] end
    local have = acc.Holdings({ [acc.MyKey()] = true }, true, false, true)
    local list = {}
    for id, n in pairs(have) do
        local ah = ns.AH.Price(id)
        if ah then
            local net = math.floor(ah * (1 - FEE))
            local vendor = ns.Value.Vendor(id) or 0
            list[#list + 1] = { id = id, n = n, ah = ah, gain = (net - vendor) * n }
        end
    end
    table.sort(list, function(a, b) return a.gain > b.gain end)
    local out = {}
    for i = 1, math.min(14, #list) do
        local e = list[i]
        local name, q, icon = Item(e.id)
        out[i] = { id = e.id, icon = icon, name = Coloured(q, name or "…"), a = "×" .. e.n, b = Money(e.ah), c = Gain(e.gain) }
    end
    return out, L["Nothing of value in your bags (or no auction scan yet)."]
end

-- crafting materials: every item that a recipe uses (from the game's recipe data), as a set
local reagents
local function Reagents()
    if reagents then return reagents end
    reagents = {}
    local Instant = GetItemInfoInstant or (C_Item and C_Item.GetItemInfoInstant)
    for _, list in pairs(ns.RecipeDB and ns.RecipeDB.professions or {}) do
        for _, r in ipairs(list) do
            local re = r[6]
            for i = 1, #re, 2 do
                local id = re[i]
                if reagents[id] == nil then
                    -- only trade goods and reagents: some recipes use a finished piece of armour as a material
                    local class = Instant and select(6, Instant(id))
                    reagents[id] = (class == 7 or class == 5) and true or false
                end
            end
        end
    end
    return reagents
end

-- The market of the materials: how much each sells (demand) and how its price moved against its average of the last week.
-- Worked out a few hundred items per frame, once per scan.
local movers = { stamp = false }
local function MoversStart()
    local stamp = ns.AH.Time()
    if movers.stamp == stamp and movers.ids then return end
    local ids, prices = {}, ns.AH.Prices()
    for id, is in pairs(Reagents()) do
        if is and prices[id] then ids[#ids + 1] = id end
    end
    movers = { stamp = stamp, ids = ids, i = 1, demand = {}, trend = {} }
end
local function MoversStep()
    local m = movers
    if not m.ids or m.done then return end
    local stop = math.min(#m.ids, m.i + 250)
    for i = m.i, stop do
        local id = m.ids[i]
        local now = ns.AH.Price(id)
        if now and now >= MIN_PRICE then
            local sales = ns.AH.Demand and ns.AH.Demand(id, 7)
            if sales and sales >= 0.5 then
                m.demand[#m.demand + 1] = { id = id, sales = sales, now = now }
                -- what is rising counts only when it also sells
                local price, _, avg = ns.AH.Trend(id, 7)
                if price and avg and avg >= MIN_PRICE then
                    local diff = (now - avg) / avg * 100
                    if diff >= 10 then m.trend[#m.trend + 1] = { id = id, diff = diff, now = now, gain = now - avg, sales = sales } end
                end
            end
        end
    end
    m.i = stop + 1
    if m.i > #m.ids then
        table.sort(m.demand, function(a, b) return a.sales > b.sales end)
        table.sort(m.trend, function(a, b) return a.gain > b.gain end) -- the most per piece first
        m.done = true
    end
end

local function SalesText(v)
    if v < 0.5 then return "<1/d" end
    if v >= 1000 then return ("%.1fk/d"):format(v / 1000) end
    return v < 10 and ("%.1f/d"):format(v) or ("%d/d"):format(math.floor(v + 0.5))
end

local function MaterialList(which)
    local m = movers
    if not m.done then return {}, L["Working it out…"] end
    local list, out = m[which], {}
    for i = 1, math.min(14, #list) do
        local e = list[i]
        local name, q, icon = Item(e.id)
        if which == "demand" then
            out[i] = { id = e.id, icon = icon, name = Coloured(q, name or "…"), b = Money(e.now), c = SalesText(e.sales) }
        else
            out[i] = { id = e.id, icon = icon, name = Coloured(q, name or "…"), a = SalesText(e.sales), b = Pct(e.diff), c = Money(e.gain, GREEN) }
        end
    end
    local none = which == "demand" and L["No material has a demand yet: it needs scans on different days (or follow every item in the options)."]
        or L["No material is rising and in demand."]
    return out, none
end

-- the page -------------------------------------------------------------------------------------------------------------

function D.Build(parent)
    local f = CreateFrame("Frame", nil, parent)
    f:Hide()

    local wealth = NewCard(f, L["Your wealth"], { 0, 0, 110 })
    local bags = NewCard(f, L["Worth a look in your bags"], { 44, 92, 110 })
    local demand = NewCard(f, L["Crafting materials in demand"], { 1, 92, 70 })
    local trend = NewCard(f, L["Trending crafting materials"], { 62, 58, 96 })

    -- two rows: your wealth and your bags above, the two lists of materials below, side by side
    local GAP, LEFT_W = 8, 300
    local function Place()
        local w, h = f:GetWidth(), f:GetHeight()
        if not w or w <= 0 or not h or h <= 0 then return end
        local top = math.floor((h - GAP) * 0.42)
        local bottom = h - GAP - top
        local half = math.floor((w - GAP) / 2)
        local function At(card, point, x, y, cw, ch)
            card:ClearAllPoints()
            card:SetPoint(point, f, point, x, y)
            card:SetSize(cw, ch)
            card.fit = math.max(1, math.floor((ch - 36) / ROW_H))
        end
        At(wealth, "TOPLEFT", 0, 0, LEFT_W, top)
        At(bags, "TOPRIGHT", 0, 0, w - LEFT_W - GAP, top)
        At(demand, "BOTTOMLEFT", 0, 0, half, bottom)
        At(trend, "BOTTOMRIGHT", 0, 0, half, bottom)
    end
    f:SetScript("OnSizeChanged", function() Place(); if f:IsShown() then f:Update() end end)

    function f:Update()
        Place()
        MoversStart()
        local list, note = WealthList()
        wealth:Fill(list, note, note)
        local b, bEmpty = BagList()
        bags:Fill(b, nil, bEmpty)
        local d, dEmpty = MaterialList("demand")
        demand:Fill(d, nil, dEmpty)
        local t, tEmpty = MaterialList("trend")
        trend:Fill(t, nil, tEmpty)
    end

    local acc = 0
    f:SetScript("OnUpdate", function(_, dt)
        if movers.ids and not movers.done then MoversStep() end
        acc = acc + dt
        if acc < 2 then return end
        acc = 0
        f:Update()
    end)
    f:SetScript("OnShow", function() f:Update() end)
    return f
end
