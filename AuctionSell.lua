local ADDON, ns = ...
local L = ns.L
local W = ns.W
local C = W.C

-- The sell panel of the auction house tab: a click on a row of "Sell" opens it in the middle of the table. It shows the cheapest listings of
-- the item on the auction house (the price each), a price (the cheapest listing of someone else less 1 copper, to change), the amount and
-- the duration, and puts the item up for sale. It asks the auction house for one item at a time (C_AuctionHouse.SendSearchQuery) and reads
-- the answer from the events; nothing is sold without the click on the button.

local S = {}
ns.AuctionSell = S

local FEE = 0.05
local ROWS = 10
local ROW_H = 20
local PANEL_W, PANEL_H = 480, 270
local RX = 232 -- where the right column (the offer) begins
local DURATIONS = { { 1, 2 }, { 2, 8 }, { 3, 24 } } -- { the game's number, hours }: this auction house has 2, 8 and 24 hours

local GetInfo = GetItemInfo or (C_Item and C_Item.GetItemInfo)
local GetNum = (C_Container and C_Container.GetContainerNumSlots) or GetContainerNumSlots
local GetBagItemID = (C_Container and C_Container.GetContainerItemID) or GetContainerItemID

local function Money(copper, tint) return ns.Value.Format(copper, tint) end

-- where the item is in the bags of this character: how many in all, and the first stack (bag and slot)
local function InBags(id)
    local total, bag0, slot0 = 0, nil, nil
    for bag = 0, 5 do
        local slots = GetNum and GetNum(bag) or 0
        for slot = 1, slots do
            if GetBagItemID(bag, slot) == id then
                local count = 1
                if C_Container and C_Container.GetContainerItemInfo then
                    local info = C_Container.GetContainerItemInfo(bag, slot)
                    count = info and info.stackCount or 1
                elseif GetContainerItemInfo then
                    count = select(2, GetContainerItemInfo(bag, slot)) or 1
                end
                total = total + count
                if not bag0 then bag0, slot0 = bag, slot end
            end
        end
    end
    return total, bag0, slot0
end

function S.Build(parent)
    local f = W.NewPlate(parent, { 0.045, 0.036, 0.03, 1 })
    f:SetFrameStrata("FULLSCREEN")
    f:SetFrameLevel(parent:GetFrameLevel() + 80)
    f:SetSize(PANEL_W, PANEL_H)
    f:EnableMouse(true)
    f:Hide()
    f.duration = (ns.db and ns.db.settings and ns.db.settings.ahSellDuration) or 2 -- (8 hours unless another one was chosen; the older setting 'ahDuration' meant other times)
    -- (fully solid whatever the setting for the plates' transparency: the table must not show through)
    local solid = f:CreateTexture(nil, "BACKGROUND", nil, -8)
    solid:SetPoint("TOPLEFT", 1, -1)
    solid:SetPoint("BOTTOMRIGHT", -1, 1)
    solid:SetColorTexture(0.05, 0.04, 0.034, 1)

    local close = W.NewButton(f, "×", 20, 20, "GameFontNormal")
    close:SetPoint("TOPRIGHT", -8, -8)
    close:SetScript("OnClick", function() f:Close() end)

    -- the cheapest listings (left): the price each, the order of the prices
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

    -- the offer (right)
    local RW = PANEL_W - RX - 14
    local function Label(text, y)
        local fs = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        fs:SetPoint("TOPLEFT", f, "TOPLEFT", RX, y)
        fs:SetText(text)
        fs:SetTextColor(C.gold[1], C.gold[2], C.gold[3])
        return fs
    end
    Label(L["Your price (each)"], -14)
    local ok, money = pcall(CreateFrame, "Frame", nil, f, "MoneyInputFrameTemplate")
    if ok and money then
        money:SetPoint("TOPLEFT", f, "TOPLEFT", RX - 2, -32)
        f.money = money
        if MoneyInputFrame_SetOnValueChangedFunc then MoneyInputFrame_SetOnValueChangedFunc(money, function() f:Sums() end) end
    end
    local auto = W.NewButton(f, L["Cheapest minus 1 copper"], RW, 22)
    auto:SetPoint("TOPLEFT", f, "TOPLEFT", RX, -64)
    auto:SetScript("OnClick", function() f:AutoPrice() end)

    Label(L["Amount"], -100)
    local qty = CreateFrame("EditBox", nil, f, W.TEMPLATE)
    qty:SetSize(60, 22)
    qty:SetPoint("TOPLEFT", f, "TOPLEFT", RX, -116)
    qty:SetBackdrop(W.PLATE_BACKDROP)
    qty:SetBackdropColor(unpack(C.inset))
    qty:SetBackdropBorderColor(unpack(C.goldDim))
    qty:SetFontObject("GameFontHighlight")
    qty:SetAutoFocus(false)
    qty:SetNumeric(true)
    qty:SetMaxLetters(5)
    qty:SetTextInsets(6, 6, 0, 0)
    qty:SetScript("OnTextChanged", function() f:Sums() end)
    qty:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)
    qty:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    f.qty = qty
    local allBtn = W.NewButton(f, L["All"], 50, 22)
    allBtn:SetPoint("LEFT", qty, "RIGHT", 6, 0)
    allBtn:SetScript("OnClick", function() qty:SetText(tostring(f.total or 1)) end)
    local dur = W.NewButton(f, "", 70, 22)
    dur:SetPoint("LEFT", allBtn, "RIGHT", 6, 0)
    local function ShowDuration()
        for _, d in ipairs(DURATIONS) do
            if d[1] == f.duration then dur.text:SetText((L["%d h"]):format(d[2])) end
        end
    end
    dur:SetScript("OnClick", function()
        f.duration = f.duration % #DURATIONS + 1
        if ns.db then ns.db.settings.ahSellDuration = f.duration end
        ShowDuration()
        f:Sums()
    end)
    dur:HookScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:SetText(L["Duration"], 1, 0.85, 0.4)
        GameTooltip:AddLine(L["Click to change how long the offer runs."], 0.85, 0.85, 0.85, true)
        GameTooltip:Show()
    end)
    dur:HookScript("OnLeave", function() GameTooltip:Hide() end)

    -- the accounts: the deposit apart; then what the sale brings, the fee (red) and what is left (green)
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
    AccRow("deposit", L["Deposit"], -148)
    AccRow("proceeds", L["Proceeds"], -172)
    AccRow("fee", L["Fee"], -188)
    local line = f:CreateTexture(nil, "ARTWORK")
    line:SetPoint("TOPLEFT", f, "TOPLEFT", RX, -204)
    line:SetSize(RW, 1)
    line:SetColorTexture(C.goldDim[1], C.goldDim[2], C.goldDim[3], 0.6)
    AccRow("profit", L["Gain"], -209, true)
    f.sell = W.NewButton(f, L["Put up for sale"], RW, 30, "GameFontNormal")
    f.sell:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", RX, 12)
    f.sell:SetScript("OnClick", function() f:Post() end)
    -- what cannot be sold from here: only what is in the bags of this character can be put up for sale
    f.blocked = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    f.blocked:SetPoint("BOTTOMLEFT", f.sell, "TOPLEFT", 0, 6)
    f.blocked:SetWidth(RW)
    f.blocked:SetJustifyH("LEFT")
    f.blocked:SetTextColor(0.93, 0.65, 0.37)
    f.blocked:SetText(L["Not in your bags: only what you carry can be put up for sale from here."])
    f.blocked:Hide()

    -- opens in the middle of the table (whether the filters are open or not); the list scrolling closes it
    function f:Open(id, row, scrollFrame)
        if self:IsShown() and self.id == id then self:Close() return end
        if ns.AuctionBuyPanel and ns.AuctionBuyPanel:IsShown() then ns.AuctionBuyPanel:Close() end
        self.id, self.scrollFrame, self.priced = id, scrollFrame, nil
        self.scrollAt = scrollFrame and scrollFrame.GetVerticalScroll and scrollFrame:GetVerticalScroll()
        self.total, self.bag, self.slot = InBags(id)
        self.qty:SetText(tostring(math.max(1, self.total)))
        ShowDuration()
        self.listing = {}
        self:ClearAllPoints()
        self:SetPoint("CENTER", scrollFrame or row, "CENTER", 0, 0)
        self:Show()
        self:Render()
        self:Ask()
    end

    function f:Close()
        self:Hide()
        self.id = nil
        self.asking = nil
    end

    -- the answer of the auction house is only waited for a while
    function f:Ask()
        if not self.id then return end
        self.listing = {}
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
        local okQuery = pcall(C_AuctionHouse.SendSearchQuery, self.itemKey, sorts, true)
        self.asking = okQuery and GetTime() or nil
        self.note:SetText(okQuery and L["Reading the auction house…"] or L["The auction house did not take the question."])
    end

    -- reads what the auction house sent: the price each of the cheapest listings
    function f:Read()
        local out = {}
        local me = UnitName("player")
        local AHc = C_AuctionHouse
        local n = AHc.GetNumCommoditySearchResults and AHc.GetNumCommoditySearchResults(self.id) or 0
        if n > 0 then
            for i = 1, math.min(n, ROWS) do
                local info = AHc.GetCommoditySearchResultInfo(self.id, i)
                if info then
                    out[#out + 1] = { price = info.unitPrice, qty = info.quantity, mine = info.containsOwnerItem or info.containsAccountItem }
                end
            end
        else
            local m = AHc.GetNumItemSearchResults and AHc.GetNumItemSearchResults(self.itemKey) or 0
            for i = 1, math.min(m, ROWS) do
                local info = AHc.GetItemSearchResultInfo(self.itemKey, i)
                if info then
                    local each = info.buyoutAmount and info.quantity and info.quantity > 0 and math.floor(info.buyoutAmount / info.quantity) or nil
                    if each then
                        local same
                        for _, e in ipairs(out) do if e.price == each then same = e break end end
                        if same then
                            same.qty = (same.qty or 0) + info.quantity
                            same.mine = same.mine or info.owner == me or info.containsOwnerItem
                        else
                            out[#out + 1] = { price = each, qty = info.quantity, mine = info.owner == me or info.containsOwnerItem }
                        end
                    end
                end
            end
        end
        table.sort(out, function(a, b) return a.price < b.price end)
        self.listing = out
        self.asking = nil
        -- the cheapest price is the price of the item now: the list shows it (it may have changed since the last scan)
        if out[1] and ns.AH and ns.AH.Observe and ns.AH.Observe(self.id, out[1].price) and S.OnPrice then S.OnPrice(self.id) end
        self:Render()
        -- the first price: the cheapest listing of someone else, less 1 copper
        if not self.priced then self:AutoPrice() end
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

    function f:Price(copper)
        if self.money then MoneyInputFrame_SetCopper(self.money, math.max(1, copper or 1)) end
        self.priced = true
        self:Sums()
    end

    function f:AutoPrice()
        local base
        for _, e in ipairs(self.listing) do
            if not e.mine then base = e.price break end
        end
        base = base or (ns.AH and ns.AH.Price(self.id)) or (ns.Value.Vendor(self.id) or 0) * 2
        self:Price(math.max(1, (base or 1) - 1))
    end

    -- what the offer brings
    function f:Sums()
        if not self.id then return end
        local RED, GREEN = "|cffff7a6b", "|cff66dbb0"
        local price = self.money and MoneyInputFrame_GetCopper(self.money) or 0
        local qty = math.max(1, math.min(tonumber(self.qty:GetText()) or 1, math.max(1, self.total or 1)))
        local total = price * qty
        local fee = total - math.floor(total * (1 - FEE))
        local dep
        if C_AuctionHouse and C_AuctionHouse.CalculateCommodityDeposit then
            local ok, v = pcall(C_AuctionHouse.CalculateCommodityDeposit, self.id, self.duration, qty)
            if ok and type(v) == "number" then dep = v end
        end
        local dash = "|cff8a806e–|r"
        self.acc.deposit:SetText(dep and Money(dep) or dash)
        self.acc.proceeds:SetText(total > 0 and Money(total) or dash)
        self.acc.fee:SetText(fee > 0 and ("-" .. Money(fee, RED)) or dash)
        self.acc.profit:SetText(total > 0 and Money(total - fee, GREEN) or dash)
        local canSell = (self.total or 0) > 0
        self.sell:SetAlpha(canSell and price > 0 and 1 or 0.5)
        self.sell:SetEnabled(canSell)
        self.blocked:SetShown(not canSell)
    end

    -- For finding out what the deposit is on this auction house: every way of asking the game for it, for the item and the amount that are in the
    -- panel now (/fcdeposit), to be compared with what the game's own sell tab says.
    function f:DepositDebug()
        if not self.id then return "Open the sell panel for an item first (a click on a row of Sell), then /fcdeposit." end
        local qty = math.max(1, math.min(tonumber(self.qty:GetText()) or 1, math.max(1, self.total or 1)))
        local lines = { ("item %d, amount %d, in the panel: duration %s"):format(self.id, qty, tostring(self.duration)) }
        local loc = self.bag and ItemLocation and ItemLocation:CreateFromBagAndSlot(self.bag, self.slot)
        for _, d in ipairs({ 1, 2, 3, 2, 8, 24 }) do
            local a1, a2 = "-", "-"
            if C_AuctionHouse and C_AuctionHouse.CalculateCommodityDeposit then
                local ok, v = pcall(C_AuctionHouse.CalculateCommodityDeposit, self.id, d, qty)
                a1 = ok and tostring(v) or ("error: " .. tostring(v))
            end
            if loc and C_AuctionHouse and C_AuctionHouse.CalculateItemDeposit then
                local ok, v = pcall(C_AuctionHouse.CalculateItemDeposit, loc, d, qty)
                a2 = ok and tostring(v) or ("error: " .. tostring(v))
            end
            lines[#lines + 1] = ("duration value %2d:  commodity %s   item %s"):format(d, a1, a2)
        end
        local vendor = ns.Value.Vendor and ns.Value.Vendor(self.id)
        lines[#lines + 1] = "vendor price (each): " .. tostring(vendor)
        return table.concat(lines, "\n")
    end

    -- puts the item up for sale
    function f:Post()
        if not self.id then return end
        if not (ns.AH and ns.AH.IsOpen()) then print("|cffffd100ForeverCompanion:|r " .. L["The auction house is not open."]) return end
        local total, bag, slot = InBags(self.id)
        if total <= 0 or not bag then print("|cffffd100ForeverCompanion:|r " .. L["It is not in your bags."]) return end
        local price = self.money and MoneyInputFrame_GetCopper(self.money) or 0
        if price < 1 then return end
        local qty = math.max(1, math.min(tonumber(self.qty:GetText()) or 1, total))
        local loc = ItemLocation and ItemLocation:CreateFromBagAndSlot(bag, slot)
        if not loc then print("|cffffd100ForeverCompanion:|r " .. L["This client cannot put items up for sale from here."]) return end
        local commodity = true
        if C_AuctionHouse.GetItemCommodityStatus and Enum and Enum.ItemCommodityStatus then
            commodity = C_AuctionHouse.GetItemCommodityStatus(loc) == Enum.ItemCommodityStatus.Commodity
        end
        local ok, err
        if commodity then
            ok, err = pcall(C_AuctionHouse.PostCommodity, loc, self.duration, qty, price)
        else
            ok, err = pcall(C_AuctionHouse.PostItem, loc, self.duration, qty, nil, price * qty)
        end
        if ok then
            local name = W.ItemData(self.id) or ("item:" .. self.id)
            print("|cffffd100ForeverCompanion:|r " .. (L["Put up for sale: %s ×%d at %s each"]):format(name, qty, Money(price)))
            C_Timer.After(1.5, function()
                if self.id then
                    self.total = InBags(self.id)
                    self:Ask()
                end
            end)
        else
            print("|cffffd100ForeverCompanion:|r " .. (L["Could not put it up for sale: %s"]):format(tostring(err)))
        end
    end

    -- events and waiting
    for _, e in ipairs({ "COMMODITY_SEARCH_RESULTS_UPDATED", "ITEM_SEARCH_RESULTS_UPDATED", "AUCTION_HOUSE_THROTTLED_SYSTEM_READY" }) do
        pcall(f.RegisterEvent, f, e)
    end
    f:SetScript("OnEvent", function(self, event)
        if not (self:IsShown() and self.id) then return end
        if event == "AUCTION_HOUSE_THROTTLED_SYSTEM_READY" then
            if self.retry then self:Ask() end
        else
            self:Read()
        end
    end)
    f:SetScript("OnUpdate", function(self, dt)
        if not self.id then return end
        -- the list scrolled: the row it was opened for is another one now
        if self.scrollFrame and self.scrollAt and self.scrollFrame:GetVerticalScroll() ~= self.scrollAt then self:Close() return end -- (not for the page)
        if self.retry then
            self.retry = self.retry - dt
            if self.retry <= 0 then self:Ask() end
        end
        if self.asking and GetTime() - self.asking > 8 then
            self.asking = nil
            self.note:SetText(L["No answer from the auction house."])
        end
    end)
    f:SetScript("OnHide", function(self) self.id = nil end)
    return f
end

SLASH_FOREVERCOMPANIONDEPOSIT1 = "/fcdeposit"
SlashCmdList.FOREVERCOMPANIONDEPOSIT = function()
    local panel = ns.AuctionSellPanel
    W.Console(panel and panel:DepositDebug() or "The sell panel is not built yet.", "Deposit")
end

-- Looking at the items one by one ------------------------------------------------------------------------------------------------------
-- The full scan can only be asked for now and then; the auction house answers a question about one item at any time (only paced by the game).
-- S.Check(ids) asks for the items one after the other, takes the cheapest price of each as its price, and lists are worked out again at
-- the end. S.Progress() gives { done, total } while it runs. A second call while it runs stops it.
local check = { queue = {}, total = 0, done = 0, changed = 0 }
local driver = CreateFrame("Frame")
driver:Hide()

local function Cheapest(id, key)
    local AHc = C_AuctionHouse
    local best
    local n = AHc.GetNumCommoditySearchResults and AHc.GetNumCommoditySearchResults(id) or 0
    if n > 0 then
        local info = AHc.GetCommoditySearchResultInfo(id, 1)
        best = info and info.unitPrice
    elseif key and AHc.GetNumItemSearchResults then
        for i = 1, math.min(AHc.GetNumItemSearchResults(key), 5) do
            local info = AHc.GetItemSearchResultInfo(key, i)
            if info and info.buyoutAmount and info.buyoutAmount > 0 and info.quantity and info.quantity > 0 then
                local each = math.floor(info.buyoutAmount / info.quantity)
                if not best or each < best then best = each end
            end
        end
    end
    return best
end

local function Finish()
    driver:Hide()
    check.queue, check.current = {}, nil
    if check.changed > 0 and S.OnPrice then S.OnPrice() end
    check.total, check.done, check.changed = 0, 0, 0
end

local function Next()
    local id = table.remove(check.queue, 1)
    if not id then Finish() return end
    check.current = { id = id, since = GetTime() }
end

local function Send()
    local cur = check.current
    if not cur or cur.sent then return end
    if C_AuctionHouse.IsThrottledMessageSystemReady and not C_AuctionHouse.IsThrottledMessageSystemReady() then return end
    cur.key = C_AuctionHouse.MakeItemKey(cur.id)
    local sorts = Enum and Enum.AuctionHouseSortOrder and { { sortOrder = Enum.AuctionHouseSortOrder.Price, reverseSort = false } } or {}
    cur.sent = GetTime()
    if not pcall(C_AuctionHouse.SendSearchQuery, cur.key, sorts, true) then cur.failed = true end
end

local function Answered(cur)
    local price = not cur.failed and Cheapest(cur.id, cur.key)
    if price and ns.AH.Observe(cur.id, price) then check.changed = check.changed + 1 end
    check.done = check.done + 1
    Next()
end

for _, e in ipairs({ "COMMODITY_SEARCH_RESULTS_UPDATED", "ITEM_SEARCH_RESULTS_UPDATED" }) do pcall(driver.RegisterEvent, driver, e) end
driver:SetScript("OnEvent", function(_, _, arg)
    local cur = check.current
    if not (cur and cur.sent) then return end
    if arg == cur.id or (type(arg) == "table" and arg.itemID == cur.id) then Answered(cur) end
end)
driver:SetScript("OnUpdate", function()
    local cur = check.current
    if not cur then return end
    if not (ns.AH and ns.AH.IsOpen()) then Finish() return end
    if not cur.sent then
        Send()
    elseif GetTime() - cur.sent > 4 then
        Answered(cur) -- (no answer: the next one)
    end
end)

function S.Check(ids)
    if driver:IsShown() then Finish() return false end -- (a click while it runs: stop)
    if not (ns.AH and ns.AH.IsOpen()) then return false, L["The auction house is not open."] end
    if not (C_AuctionHouse and C_AuctionHouse.SendSearchQuery and C_AuctionHouse.MakeItemKey) then
        return false, L["This client cannot look at single items."]
    end
    check.queue = {}
    for _, id in ipairs(ids) do check.queue[#check.queue + 1] = id end
    check.total, check.done, check.changed = #check.queue, 0, 0
    if check.total == 0 then return false end
    Next()
    driver:Show()
    return true
end

function S.Progress()
    if not driver:IsShown() then return nil end
    return check.done, check.total
end
