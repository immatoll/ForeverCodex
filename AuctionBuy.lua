local ADDON, ns = ...
local L = ns.L
local W = ns.W
local C = W.C

-- The buy panel of the auction house tab: a click on a row of "Market" (or of a list of the first page) opens it in the middle of the table. It shows
-- the cheapest listings of the item (pieces at a price, the price each), asks for the amount and tells what that costs over the cheapest listings.
-- Buying is in two steps: the first click asks the auction house for the price (the game's own way: StartCommoditiesPurchase), the button then
-- shows what it costs, and only the second click buys. Nothing is bought without both.

local B = {}
ns.AuctionBuy = B

local ROWS = 10
local ROW_H = 20
local PANEL_W, PANEL_H = 480, 270
local RX = 232

local GetInfo = GetItemInfo or (C_Item and C_Item.GetItemInfo)

local function Money(copper, tint) return ns.Value.Format(copper, tint) end

function B.Build(parent)
    local f = W.NewPlate(parent, { 0.045, 0.036, 0.03, 1 })
    f:SetFrameStrata("FULLSCREEN")
    f:SetFrameLevel(parent:GetFrameLevel() + 80)
    f:SetSize(PANEL_W, PANEL_H)
    f:EnableMouse(true)
    f:Hide()
    f.listing, f.all = {}, {}
    local solid = f:CreateTexture(nil, "BACKGROUND", nil, -8)
    solid:SetPoint("TOPLEFT", 1, -1)
    solid:SetPoint("BOTTOMRIGHT", -1, 1)
    solid:SetColorTexture(0.05, 0.04, 0.034, 1)

    local close = W.NewButton(f, "×", 20, 20, "GameFontNormal")
    close:SetPoint("TOPRIGHT", -8, -8)
    close:SetScript("OnClick", function() f:Close() end)

    -- the cheapest listings (left)
    f.listHead = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    f.listHead:SetPoint("TOPLEFT", 14, -14)
    f.listHead:SetText(L["Cheapest listings"])
    f.listHead:SetTextColor(C.gold[1], C.gold[2], C.gold[3])
    f.rows = {}
    for i = 1, ROWS do
        local r = CreateFrame("Frame", nil, f)
        r:SetHeight(ROW_H)
        r:SetPoint("TOPLEFT", f, "TOPLEFT", 10, -(36 + (i - 1) * ROW_H))
        r:SetWidth(RX - 24)
        r.bg = r:CreateTexture(nil, "BACKGROUND")
        r.bg:SetAllPoints()
        r.bg:SetColorTexture(1, 1, 1, i % 2 == 0 and 0.035 or 0)
        r.mark = r:CreateTexture(nil, "ARTWORK")
        r.mark:SetColorTexture(C.gold[1], C.gold[2], C.gold[3], 0.2)
        r.mark:SetAllPoints()
        r.mark:Hide()
        r.rank = r:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        r.rank:SetPoint("LEFT", 8, 0)
        r.rank:SetTextColor(unpack(C.muted))
        r.rank:SetText(i)
        r.qty = r:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        r.qty:SetPoint("LEFT", 30, 0)
        r.qty:SetWidth(62)
        r.qty:SetJustifyH("RIGHT")
        r.qty:SetTextColor(unpack(C.muted))
        r.price = r:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        r.price:SetPoint("LEFT", 104, 0)
        r.price:SetWidth(94)
        r.price:SetJustifyH("RIGHT")
        r:Hide()
        f.rows[i] = r
    end
    f.note = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    f.note:SetPoint("TOPLEFT", 16, -40)
    f.note:SetWidth(RX - 40)
    f.note:SetJustifyH("LEFT")
    f.note:SetTextColor(unpack(C.muted))
    local refresh = W.NewButton(f, L["Refresh"], 100, 22)
    refresh:SetPoint("BOTTOMLEFT", 10, 12)
    refresh:SetScript("OnClick", function() f:Ask() end)

    -- the amount and the cost (right)
    local RW = PANEL_W - RX - 14
    local function Label(text, y)
        local fs = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        fs:SetPoint("TOPLEFT", f, "TOPLEFT", RX, y)
        fs:SetText(text)
        fs:SetTextColor(C.gold[1], C.gold[2], C.gold[3])
        return fs
    end
    Label(L["Amount"], -14)
    local qty = CreateFrame("EditBox", nil, f, W.TEMPLATE)
    qty:SetSize(70, 24)
    qty:SetPoint("TOPLEFT", f, "TOPLEFT", RX, -32)
    qty:SetBackdrop(W.PLATE_BACKDROP)
    qty:SetBackdropColor(unpack(C.inset))
    qty:SetBackdropBorderColor(unpack(C.goldDim))
    qty:SetFontObject("GameFontHighlight")
    qty:SetAutoFocus(false)
    qty:SetNumeric(true)
    qty:SetMaxLetters(5)
    qty:SetTextInsets(6, 6, 0, 0)
    qty:SetText("1")
    qty:SetScript("OnTextChanged", function() f:Reset(); f:Sums() end)
    qty:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)
    qty:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    f.qty = qty
    local x = 80
    for _, n in ipairs({ 1, 5, 20 }) do
        local b = W.NewButton(f, tostring(n), 44, 24)
        b:SetPoint("TOPLEFT", f, "TOPLEFT", RX + x, -32)
        b:SetScript("OnClick", function() qty:SetText(tostring(n)) end)
        x = x + 50
    end

    -- the accounts: what it costs, each, and what you have
    f.acc = {}
    local function AccRow(key, text, y, big)
        local lbl = f:CreateFontString(nil, "OVERLAY", big and "GameFontNormal" or "GameFontHighlightSmall")
        lbl:SetPoint("TOPLEFT", f, "TOPLEFT", RX, y)
        lbl:SetText(text)
        lbl:SetTextColor(unpack(big and C.gold or C.muted))
        local val = f:CreateFontString(nil, "OVERLAY", big and "GameFontNormal" or "GameFontHighlightSmall")
        val:SetPoint("TOPRIGHT", f, "TOPLEFT", RX + RW, y)
        val:SetJustifyH("RIGHT")
        f.acc[key] = val
    end
    AccRow("each", L["Each (average)"], -78)
    AccRow("have", L["You have"], -96)
    local line = f:CreateTexture(nil, "ARTWORK")
    line:SetPoint("TOPLEFT", f, "TOPLEFT", RX, -118)
    line:SetSize(RW, 1)
    line:SetColorTexture(C.goldDim[1], C.goldDim[2], C.goldDim[3], 0.6)
    AccRow("total", L["Total"], -124, true)
    f.warn = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    f.warn:SetPoint("TOPLEFT", f, "TOPLEFT", RX, -154)
    f.warn:SetWidth(RW)
    f.warn:SetJustifyH("LEFT")
    f.warn:SetTextColor(0.93, 0.65, 0.37)

    f.buy = W.NewButton(f, L["Buy"], RW, 30, "GameFontNormal")
    f.buy:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", RX, 12)
    f.buy:SetScript("OnClick", function() f:Buy() end)
    -- not now: onto the shopping list with the amount
    f.listBtn = W.NewButton(f, L["Add to shopping list"], RW, 22)
    f.listBtn:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", RX, 48)
    f.listBtn:SetScript("OnClick", function(self)
        if not (f.id and ns.AuctionShop) then return end
        W.Click()
        ns.AuctionShop.Add(f.id, math.max(1, tonumber(f.qty:GetText()) or 1))
        self.text:SetText(L["Added to the list."])
        C_Timer.After(1.2, function() self.text:SetText(L["Add to shopping list"]) end)
    end)

    -- opens in the middle of the table
    function f:Open(id, row, scrollFrame, amount)
        if self:IsShown() and self.id == id then self:Close() return end
        if ns.AuctionSellPanel and ns.AuctionSellPanel:IsShown() then ns.AuctionSellPanel:Close() end
        self:Cancel()
        self.id, self.scrollFrame = id, scrollFrame
        self.scrollAt = scrollFrame and scrollFrame.GetVerticalScroll and scrollFrame:GetVerticalScroll()
        self.qty:SetText(tostring(math.max(1, math.floor(amount or 1)))) -- (the craft panel asks for the missing amount)
        self.listing, self.all = {}, {}
        self.state = nil
        self:ClearAllPoints()
        self:SetPoint("CENTER", scrollFrame or row, "CENTER", 0, 0)
        self:Show()
        self:Render()
        self:Ask()
    end

    function f:Close()
        self:Cancel()
        self:Hide()
        self.id = nil
        self.asking = nil
    end

    -- a purchase that was begun (the price asked for) is given up when the amount changes or the panel closes
    function f:Cancel()
        if self.state == "confirm" and self.commodity and C_AuctionHouse and C_AuctionHouse.CancelCommoditiesPurchase then
            pcall(C_AuctionHouse.CancelCommoditiesPurchase)
        end
        self.state, self.quote = nil, nil
        if self.buy then self.buy.text:SetText(L["Buy"]) end
    end
    function f:Reset() if self.state == "confirm" then self:Cancel() end end

    function f:Ask()
        if not self.id then return end
        self:Cancel()
        self.listing, self.all = {}, {}
        self:Render()
        if not (ns.AH and ns.AH.IsOpen()) then
            self.note:SetText(L["The auction house is not open."])
            return
        end
        if not (C_AuctionHouse and C_AuctionHouse.SendSearchQuery and C_AuctionHouse.MakeItemKey) then
            self.note:SetText(L["This client cannot look at single items."])
            return
        end
        if C_AuctionHouse.IsThrottledMessageSystemReady and not C_AuctionHouse.IsThrottledMessageSystemReady() then
            self.note:SetText(L["Waiting for the auction house…"])
            self.retry = 1.0
            return
        end
        self.retry = nil
        self.itemKey = C_AuctionHouse.MakeItemKey(self.id)
        local sorts = Enum and Enum.AuctionHouseSortOrder and { { sortOrder = Enum.AuctionHouseSortOrder.Price, reverseSort = false } } or {}
        local ok = pcall(C_AuctionHouse.SendSearchQuery, self.itemKey, sorts, true)
        self.asking = ok and GetTime() or nil
        self.note:SetText(ok and L["Reading the auction house…"] or L["The auction house did not take the question."])
    end

    -- reads what the auction house sent: all the listings it has sent (for the cost), the first ones are shown
    function f:Read()
        local all = {}
        local me = UnitName("player")
        local AHc = C_AuctionHouse
        local n = AHc.GetNumCommoditySearchResults and AHc.GetNumCommoditySearchResults(self.id) or 0
        self.commodity = n > 0
        if n > 0 then
            for i = 1, n do
                local info = AHc.GetCommoditySearchResultInfo(self.id, i)
                if info then all[#all + 1] = { price = info.unitPrice, qty = info.quantity, mine = info.containsOwnerItem or info.containsAccountItem } end
            end
        else
            local m = AHc.GetNumItemSearchResults and AHc.GetNumItemSearchResults(self.itemKey) or 0
            for i = 1, math.min(m, 40) do
                local info = AHc.GetItemSearchResultInfo(self.itemKey, i)
                if info and info.buyoutAmount and info.buyoutAmount > 0 and info.quantity and info.quantity > 0 then
                    all[#all + 1] = { price = math.floor(info.buyoutAmount / info.quantity), qty = info.quantity, total = info.buyoutAmount,
                        auction = info.auctionID, mine = info.owner == me or info.containsOwnerItem }
                end
            end
        end
        table.sort(all, function(a, b) return a.price < b.price end)
        self.all = all
        -- the first ten are shown, listings of the same price together
        local shown = {}
        for _, e in ipairs(all) do
            local last = shown[#shown]
            if last and last.price == e.price and self.commodity then
                last.qty = last.qty + e.qty
            elseif #shown < ROWS then
                shown[#shown + 1] = { price = e.price, qty = e.qty, mine = e.mine }
            end
        end
        self.listing = shown
        self.asking = nil
        -- the cheapest price is the price of the item now: the lists show it
        if all[1] and ns.AH and ns.AH.Observe and ns.AH.Observe(self.id, all[1].price) and ns.AuctionSell and ns.AuctionSell.OnPrice then
            ns.AuctionSell.OnPrice(self.id)
        end
        self:Render()
    end

    function f:Render()
        for i, r in ipairs(self.rows) do
            local e = self.listing[i]
            if e then
                r.qty:SetText(e.qty and ("×" .. e.qty) or "")
                r.price:SetText(Money(e.price))
                r.mark:SetShown(e.mine and true or false)
                r:Show()
            else
                r:Hide()
            end
        end
        if #self.listing > 0 then self.note:SetText("") elseif not self.asking and self.note:GetText() == "" then self.note:SetText(L["Nobody sells it right now."]) end
        self:Sums()
    end

    -- what the amount costs over the cheapest listings
    function f:Cost(amount)
        local left, total = amount, 0
        for _, e in ipairs(self.all or {}) do
            if left <= 0 then break end
            local take = math.min(left, e.qty)
            total = total + take * e.price
            left = left - take
        end
        return total, amount - left
    end

    function f:Sums()
        if not self.id then return end
        local amount = math.max(1, tonumber(self.qty:GetText()) or 1)
        local total, got = self:Cost(amount)
        local dash = "|cff8a806e–|r"
        local money = GetMoney and GetMoney() or 0
        local cost = self.quote or total
        self.acc.each:SetText(got > 0 and Money(math.floor(cost / math.max(1, got))) or dash)
        self.acc.have:SetText(Money(money, cost > money and "|cffff7a6b" or nil))
        self.acc.total:SetText(got > 0 and Money(cost) or dash)
        local warn
        if got > 0 and got < amount then
            warn = (L["Only %d for sale."]):format(got)
        elseif got > 0 and cost > money then
            warn = L["You do not have enough gold."]
        end
        if not self.commodity and #self.all > 0 then warn = L["One listing at a time: the cheapest is bought."] end
        self.warn:SetText(warn or "")
        self.buy:SetAlpha((got > 0 and cost <= money) and 1 or 0.5)
    end

    -- the purchase: the first click asks for the price, the second buys
    function f:Buy()
        if not self.id then return end
        if not (ns.AH and ns.AH.IsOpen()) then print("|cffffd100ForeverCompanion:|r " .. L["The auction house is not open."]) return end
        local amount = math.max(1, tonumber(self.qty:GetText()) or 1)
        local total, got = self:Cost(amount)
        if got == 0 or total > (GetMoney and GetMoney() or 0) then return end
        if self.state == "confirm" then
            -- the second click
            if self.commodity then
                if C_AuctionHouse.ConfirmCommoditiesPurchase then
                    local ok, err = pcall(C_AuctionHouse.ConfirmCommoditiesPurchase, self.id, self.quoteAmount or amount)
                    if not ok then print("|cffffd100ForeverCompanion:|r " .. (L["Could not buy it: %s"]):format(tostring(err))) end
                end
            else
                local first = self.all[1]
                local ok, err = pcall(C_AuctionHouse.PlaceBid, first.auction, first.total)
                if ok then
                    print("|cffffd100ForeverCompanion:|r " .. (L["Bought: %s ×%d for %s"]):format(W.ItemData(self.id) or ("item:" .. self.id), first.qty, Money(first.total)))
                    if ns.AuctionOwn then ns.AuctionOwn.Spent(self.id, first.qty, first.total) end
                    if ns.db.settings.ahCloseAfter ~= false then self:Close() return end -- (done: the panel goes)
                    C_Timer.After(1.5, function() if self.id then self:Ask() end end)
                else
                    print("|cffffd100ForeverCompanion:|r " .. (L["Could not buy it: %s"]):format(tostring(err)))
                end
            end
            self.state, self.quote = "done", nil
            self.buy.text:SetText(L["Buy"])
            return
        end
        -- the first click
        if self.commodity then
            if not C_AuctionHouse.StartCommoditiesPurchase then print("|cffffd100ForeverCompanion:|r " .. L["This client cannot buy from here."]) return end
            self.quoteAmount = got
            local ok, err = pcall(C_AuctionHouse.StartCommoditiesPurchase, self.id, got)
            if not ok then print("|cffffd100ForeverCompanion:|r " .. (L["Could not buy it: %s"]):format(tostring(err))) return end
            self.state = "asking"
            self.buy.text:SetText(L["Asking for the price…"])
        else
            local first = self.all[1]
            if not first then return end
            self.state, self.quote = "confirm", first.total
            self.buy.text:SetText((L["Confirm: %s"]):format(Money(first.total)))
            self:Sums()
        end
    end

    -- events and waiting
    for _, e in ipairs({ "COMMODITY_SEARCH_RESULTS_UPDATED", "ITEM_SEARCH_RESULTS_UPDATED", "AUCTION_HOUSE_THROTTLED_SYSTEM_READY",
        "COMMODITY_PRICE_UPDATED", "COMMODITY_PRICE_UNAVAILABLE", "COMMODITY_PURCHASE_SUCCEEDED", "COMMODITY_PURCHASE_FAILED" }) do
        pcall(f.RegisterEvent, f, e)
    end
    f:SetScript("OnEvent", function(self, event, a, b)
        if not (self:IsShown() and self.id) then return end
        if event == "AUCTION_HOUSE_THROTTLED_SYSTEM_READY" then
            if self.retry then self:Ask() end
        elseif event == "COMMODITY_PRICE_UPDATED" then
            -- the price of the purchase (each, total): the button now buys at it
            if self.state == "asking" then
                self.state, self.quote = "confirm", b or (a and a * (self.quoteAmount or 1))
                self.buy.text:SetText((L["Confirm: %s"]):format(Money(self.quote or 0)))
                self:Sums()
            end
        elseif event == "COMMODITY_PRICE_UNAVAILABLE" then
            if self.state == "asking" or self.state == "confirm" then
                self.state, self.quote = nil, nil
                self.buy.text:SetText(L["Buy"])
                self.note:SetText(L["The price is not available any more. Refresh the list."])
            end
        elseif event == "COMMODITY_PURCHASE_SUCCEEDED" then
            print("|cffffd100ForeverCompanion:|r " .. (L["Bought: %s ×%d for %s"]):format(W.ItemData(self.id) or ("item:" .. self.id), self.quoteAmount or 0,
                Money(self.quote or 0)))
            if ns.AuctionOwn then ns.AuctionOwn.Spent(self.id, self.quoteAmount or 0, self.quote or 0) end
            self.state, self.quote = nil, nil
            self.buy.text:SetText(L["Buy"])
            if ns.db.settings.ahCloseAfter ~= false then self:Close() return end -- (done: the panel goes)
            C_Timer.After(1.5, function() if self.id then self:Ask() end end)
        elseif event == "COMMODITY_PURCHASE_FAILED" then
            self.state, self.quote = nil, nil
            self.buy.text:SetText(L["Buy"])
            print("|cffffd100ForeverCompanion:|r " .. (L["Could not buy it: %s"]):format(""))
        else
            self:Read()
        end
    end)
    f:SetScript("OnUpdate", function(self, dt)
        if not self.id then return end
        if self.scrollFrame and self.scrollAt and self.scrollFrame:GetVerticalScroll() ~= self.scrollAt then self:Close() return end
        if self.retry then
            self.retry = self.retry - dt
            if self.retry <= 0 then self:Ask() end
        end
        if self.asking and GetTime() - self.asking > 8 then
            self.asking = nil
            self.note:SetText(L["No answer from the auction house."])
        end
    end)
    f:SetScript("OnHide", function(self) self:Cancel(); self.id = nil end)
    return f
end
