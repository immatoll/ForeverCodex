local ADDON, ns = ...
local L = ns.L
local W = ns.W
local C = W.C

-- The craft panel of the auction house tab: a click on a recipe of "Craft" opens it in the middle of the table. It lists the materials of the recipe
-- for the number of crafts that is asked for, what the chosen characters already have, what is missing and what that costs on the auction house,
-- and has a button for each material that opens the buy panel with the missing amount. A first version: one material at a time.

local K = {}
ns.AuctionCraft = K

local FEE = 0.05
local ROW_H = 24
local MAX_ROWS = 9
local PANEL_W = 680
local HEAD_H = 78
local FOOT_H = 112
local PANEL_H = HEAD_H + 22 + MAX_ROWS * ROW_H + FOOT_H

-- (given by the tab: what the chosen characters have of an item, and the price of a material)
K.Hooks = { have = function() return 0 end, price = function() return 0 end }

local GetInfo = GetItemInfo or (C_Item and C_Item.GetItemInfo)

local function Money(copper, tint) return ns.Value.Format(copper, tint) end

function K.Build(parent)
    local f = W.NewPlate(parent, { 0.045, 0.036, 0.03, 1 })
    f:SetFrameStrata("FULLSCREEN")
    f:SetFrameLevel(parent:GetFrameLevel() + 70)
    f:SetSize(PANEL_W, PANEL_H)
    f:EnableMouse(true)
    f:Hide()
    f.crafts = 1
    local solid = f:CreateTexture(nil, "BACKGROUND", nil, -8)
    solid:SetPoint("TOPLEFT", 1, -1)
    solid:SetPoint("BOTTOMRIGHT", -1, 1)
    solid:SetColorTexture(0.05, 0.04, 0.034, 1)

    local close = W.NewButton(f, "×", 20, 20, "GameFontNormal")
    close:SetPoint("TOPRIGHT", -8, -8)
    close:SetScript("OnClick", function() f:Close() end)

    -- the recipe
    f.icon = f:CreateTexture(nil, "ARTWORK")
    f.icon:SetSize(30, 30)
    f.icon:SetPoint("TOPLEFT", 14, -12)
    f.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
    f.name = f:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    f.name:SetPoint("TOPLEFT", f.icon, "TOPRIGHT", 10, -1)
    f.name:SetPoint("RIGHT", close, "LEFT", -10, 0)
    f.name:SetJustifyH("LEFT")
    f.name:SetWordWrap(false)
    f.prof = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    f.prof:SetPoint("TOPLEFT", f.name, "BOTTOMLEFT", 0, -3)
    f.prof:SetTextColor(unpack(C.muted))

    -- how many crafts
    local lbl = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    lbl:SetPoint("TOPLEFT", 14, -56)
    lbl:SetText(L["Crafts"])
    lbl:SetTextColor(C.gold[1], C.gold[2], C.gold[3])
    local qty = CreateFrame("EditBox", nil, f, W.TEMPLATE)
    qty:SetSize(60, 22)
    qty:SetPoint("LEFT", lbl, "RIGHT", 10, 0)
    qty:SetBackdrop(W.PLATE_BACKDROP)
    qty:SetBackdropColor(unpack(C.inset))
    qty:SetBackdropBorderColor(unpack(C.goldDim))
    qty:SetFontObject("GameFontHighlight")
    qty:SetAutoFocus(false)
    qty:SetNumeric(true)
    qty:SetMaxLetters(4)
    qty:SetTextInsets(6, 6, 0, 0)
    qty:SetText("1")
    qty:SetScript("OnTextChanged", function(self) f.crafts = math.max(1, tonumber(self:GetText()) or 1); f:Fill() end)
    qty:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)
    qty:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    f.qty = qty
    local x = 0
    for _, n in ipairs({ 1, 5, 10, 20 }) do
        local b = W.NewButton(f, tostring(n), 40, 22)
        b:SetPoint("LEFT", qty, "RIGHT", 8 + x, 0)
        b:SetScript("OnClick", function() qty:SetText(tostring(n)) end)
        x = x + 46
    end

    -- the heads and the rows of the materials
    local COLS = { -- from the left edge of the row: { key, x, width, justify }
        { "name", 30, 160, "LEFT" }, { "need", 196, 40, "RIGHT" }, { "have", 242, 40, "RIGHT" }, { "missing", 288, 50, "RIGHT" },
        { "each", 344, 84, "RIGHT" }, { "cost", 434, 92, "RIGHT" },
    }
    local heads = { name = L["Material"], need = L["Need"], have = L["Have"], missing = L["Missing"], each = L["Each"], cost = L["Cost"] }
    for _, col in ipairs(COLS) do
        local h = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        h:SetPoint("TOPLEFT", f, "TOPLEFT", 14 + col[2], -(HEAD_H + 2))
        h:SetWidth(col[3])
        h:SetJustifyH(col[4])
        h:SetTextColor(unpack(C.muted))
        h:SetText(heads[col[1]])
    end
    f.rows = {}
    for i = 1, MAX_ROWS do
        local r = CreateFrame("Frame", nil, f)
        r:SetHeight(ROW_H)
        r:SetPoint("TOPLEFT", f, "TOPLEFT", 10, -(HEAD_H + 20 + (i - 1) * ROW_H))
        r:SetWidth(PANEL_W - 20)
        r.bg = r:CreateTexture(nil, "BACKGROUND")
        r.bg:SetAllPoints()
        r.bg:SetColorTexture(1, 1, 1, i % 2 == 0 and 0.035 or 0)
        r.pic = r:CreateTexture(nil, "ARTWORK")
        r.pic:SetSize(18, 18)
        r.pic:SetPoint("LEFT", 6, 0)
        r.pic:SetTexCoord(0.07, 0.93, 0.07, 0.93)
        r.cell = {}
        for _, col in ipairs(COLS) do
            local fs = r:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
            fs:SetPoint("LEFT", r, "LEFT", col[2] + (col[1] == "name" and 0 or 4), 0)
            fs:SetWidth(col[3])
            fs:SetJustifyH(col[4])
            fs:SetWordWrap(false)
            r.cell[col[1]] = fs
        end
        r.buy = W.NewButton(r, L["Buy"], 60, 20)
        r.buy:SetPoint("RIGHT", r, "RIGHT", -6, 0)
        r.buy:SetScript("OnClick", function(self)
            local e = self:GetParent().e
            local buyPanel = ns.AuctionBuyPanel
            if e and buyPanel then
                W.Click()
                buyPanel:Open(e.id, f, nil, e.missing > 0 and e.missing or e.need) -- (what is missing; if nothing is, the whole need)
            end
        end)
        r.buy:HookScript("OnEnter", function(self)
            local e = self:GetParent().e
            if e and e.missing == 0 then
                GameTooltip:SetOwner(self, "ANCHOR_TOP")
                GameTooltip:SetText(L["Buy more"], 0.55, 0.75, 1)
                GameTooltip:AddLine(L["You have enough of it: this buys the whole amount for the crafts anyway."], 0.85, 0.85, 0.85, true)
                GameTooltip:Show()
            end
        end)
        r.buy:HookScript("OnLeave", function() GameTooltip:Hide() end)
        r.add = W.NewButton(r, "+", 22, 20, "GameFontNormal")
        r.add:SetPoint("RIGHT", r.buy, "LEFT", -4, 0)
        r.add:SetScript("OnClick", function(self)
            local e = self:GetParent().e
            if e and ns.AuctionShop then
                W.Click()
                ns.AuctionShop.Add(e.id, e.missing > 0 and e.missing or e.need)
                self.text:SetText("OK")
                C_Timer.After(1.0, function() self.text:SetText("+") end)
            end
        end)
        r.add:HookScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_TOP")
            GameTooltip:SetText(L["Add to shopping list"], 1, 0.85, 0.4)
            GameTooltip:Show()
        end)
        r.add:HookScript("OnLeave", function() GameTooltip:Hide() end)
        r:SetScript("OnEnter", function(self)
            if self.e and self.e.id then
                GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
                GameTooltip:SetHyperlink("item:" .. self.e.id)
                GameTooltip:Show()
            end
        end)
        r:SetScript("OnLeave", function() GameTooltip:Hide() end)
        r:Hide()
        f.rows[i] = r
    end

    -- the sums
    local RIGHT = PANEL_W - 14
    f.sum = {}
    local function Sum(key, text, y, big)
        local lbl2 = f:CreateFontString(nil, "OVERLAY", big and "GameFontNormal" or "GameFontHighlightSmall")
        lbl2:SetPoint("TOPLEFT", f, "TOPLEFT", RIGHT - 300, -(HEAD_H + 28 + MAX_ROWS * ROW_H + y))
        lbl2:SetText(text)
        lbl2:SetTextColor(unpack(big and C.gold or C.muted))
        local val = f:CreateFontString(nil, "OVERLAY", big and "GameFontNormal" or "GameFontHighlightSmall")
        val:SetPoint("TOPRIGHT", f, "TOPLEFT", RIGHT, -(HEAD_H + 28 + MAX_ROWS * ROW_H + y))
        val:SetJustifyH("RIGHT")
        f.sum[key] = val
    end
    Sum("buy", L["To buy"], 0)
    Sum("all", L["All materials"], 16)
    Sum("sells", L["Sells for"], 32)
    Sum("profit", L["Profit (-5 %)"], 52, true)
    f.addAll = W.NewButton(f, L["All missing to the shopping list"], 250, 24)
    f.addAll:SetPoint("BOTTOMLEFT", 14, 12)
    f.addAll:SetScript("OnClick", function(self)
        local rec = f.recipe
        if not (rec and ns.AuctionShop) then return end
        local n = 0
        for _, rg in ipairs(rec.reagents or {}) do
            local missing = math.max(0, (rg.count or 1) * f.crafts - (K.Hooks.have(rg.id) or 0))
            if missing > 0 then ns.AuctionShop.Add(rg.id, missing); n = n + 1 end
        end
        W.Click()
        self.text:SetText(n > 0 and (L["Added: %d"]):format(n) or L["Nothing is missing."])
        C_Timer.After(1.4, function() self.text:SetText(L["All missing to the shopping list"]) end)
    end)
    f.note = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    f.note:SetPoint("BOTTOMLEFT", 14, 44)
    f.note:SetWidth(PANEL_W - 340)
    f.note:SetJustifyH("LEFT")
    f.note:SetTextColor(unpack(C.muted))

    -- opens for a recipe (its record from the list: name, product, materials)
    function f:Open(recipe, row)
        if self:IsShown() and self.recipe == recipe then self:Close() return end
        self.recipe = recipe
        local name = recipe.name or "?"
        self.name:SetText(name)
        self.icon:SetTexture(recipe.icon or "Interface\\Icons\\INV_Misc_QuestionMark")
        self.prof:SetText(recipe.prof or "")
        self.qty:SetText("1")
        self:ClearAllPoints()
        self:SetPoint("CENTER", parent, "CENTER", 0, 0) -- (the middle of the whole page, whether the filters are open or not: the panel is wide)
        self:Show()
        self:Fill()
    end

    function f:Close()
        self:Hide()
        self.recipe = nil
    end

    -- the materials for the crafts, what is there, what is missing
    function f:Fill()
        local rec = self.recipe
        if not rec then return end
        local crafts = self.crafts or 1
        local toBuy, all, unknown = 0, 0, false
        local shown = 0
        for _, rg in ipairs(rec.reagents or {}) do
            shown = shown + 1
            local r = self.rows[shown]
            if not r then break end
            local need = (rg.count or 1) * crafts
            local have = K.Hooks.have(rg.id) or 0
            local missing = math.max(0, need - have)
            local price = K.Hooks.price(rg.id) or 0
            local name, quality, icon = W.ItemData(rg.id)
            local col = ITEM_QUALITY_COLORS and ITEM_QUALITY_COLORS[quality or 1]
            r.e = { id = rg.id, missing = missing, need = need }
            r.pic:SetTexture(icon or (C_Item and C_Item.GetItemIconByID and C_Item.GetItemIconByID(rg.id)) or "Interface\\Icons\\INV_Misc_QuestionMark")
            r.cell.name:SetText((col and col.hex or "|cffffffff") .. (name or ("item:" .. rg.id)) .. "|r")
            r.cell.need:SetText(need)
            r.cell.have:SetText(have >= need and ("|cff66dbb0" .. have .. "|r") or ("|cffffffff" .. have .. "|r"))
            r.cell.missing:SetText(missing > 0 and ("|cffffa63d" .. missing .. "|r") or "|cff66dbb00|r") -- (a check mark is not in the game's font: a box)
            r.cell.each:SetText(price > 0 and Money(price) or "|cff8a806e–|r")
            r.cell.cost:SetText((missing > 0 and price > 0) and Money(missing * price) or "|cff8a806e–|r")
            local ahPrice = ns.AH and ns.AH.Price(rg.id)
            -- to buy: the button as usual; when it is all there, the button is blue (buying more is possible, not needed)
            r.buy:SetShown(ahPrice ~= nil)
            r.buy.baseColor = missing > 0 and nil or { 0.55, 0.75, 1 }
            r.buy:Restyle()
            r.add:SetShown(true)
            toBuy = toBuy + missing * price
            all = all + need * price
            if price <= 0 then unknown = true end
            r:Show()
        end
        for i = shown + 1, MAX_ROWS do self.rows[i]:Hide() end
        self.sum.buy:SetText(Money(toBuy))
        self.sum.all:SetText(Money(all))
        -- what the crafts sell for (the auction price, as a sum), and what is left of it after the fee and the materials
        local gross = rec.id and ns.AH and ns.AH.Price(rec.id)
        if not gross and rec.value and rec.value > 0 then gross = math.floor(rec.value / (1 - FEE)) end
        if gross and gross > 0 then
            local sum = gross * crafts
            self.sum.sells:SetText(Money(sum))
            local profit = math.floor(sum * (1 - FEE)) - all
            self.sum.profit:SetText(profit >= 0 and Money(profit, "|cff66dbb0") or ("-" .. Money(-profit, "|cffff7a6b")))
        else
            self.sum.sells:SetText("|cff8a806e–|r")
            self.sum.profit:SetText("|cff8a806e–|r")
        end
        local notes = {}
        if unknown then notes[#notes + 1] = L["A material has no price."] end
        if #(rec.reagents or {}) > MAX_ROWS then notes[#notes + 1] = L["Only the first materials are listed."] end
        self.note:SetText(table.concat(notes, "  "))
    end

    -- what the characters have changes while buying: the panel looks again from time to time
    local acc = 0
    f:SetScript("OnUpdate", function(self, dt)
        acc = acc + dt
        if acc < 1.5 or not self.recipe then return end
        acc = 0
        self:Fill()
    end)
    f:SetScript("OnHide", function(self) self.recipe = nil end)
    return f
end
