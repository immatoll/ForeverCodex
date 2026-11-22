local ADDON, ns = ...
local L = ns.L
local W = ns.W
local C = W.C

-- The shopping list of the auction house tab: items with the amount that is wanted, kept in the saved variables (ns.db.ahShop). They are put on
-- the list from the buy panel, from a recipe (the missing materials, one or all) and from the context menu of a row; the page shows them with
-- the price and what they cost together, and a button for each opens the buy panel with the amount. S.Build makes the page (a view of the tab).

local S = {}
ns.AuctionShop = S

local ROW_H = 28
local MAX_ROWS = 24

local function Store()
    local db = ns.db
    db.ahShop = db.ahShop or { order = {}, qty = {} }
    return db.ahShop
end

local function Changed() if S.OnChange then S.OnChange() end end

function S.Count() return #Store().order end
function S.Qty(id) return Store().qty[id] or 0 end

-- puts an item on the list (or more of it)
function S.Add(id, n)
    if not id then return end
    local st = Store()
    if not st.qty[id] then
        st.order[#st.order + 1] = id
        st.qty[id] = 0
    end
    st.qty[id] = st.qty[id] + math.max(1, math.floor(n or 1))
    Changed()
end

function S.Remove(id)
    local st = Store()
    if not st.qty[id] then return end
    st.qty[id] = nil
    for i, v in ipairs(st.order) do
        if v == id then table.remove(st.order, i) break end
    end
    Changed()
end

function S.Set(id, n)
    n = math.floor(tonumber(n) or 0)
    if n <= 0 then S.Remove(id) return end
    Store().qty[id] = n
end

function S.Clear()
    local st = Store()
    st.order, st.qty = {}, {}
    Changed()
end

local function Money(copper, tint) return ns.Value.Format(copper, tint) end

function S.Build(parent)
    local f = CreateFrame("Frame", nil, parent)
    f:Hide()
    f.offset = 0

    f.title = f:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    f.title:SetPoint("TOPLEFT", 10, -8)
    f.title:SetText(L["Shopping list"])
    f.title:SetTextColor(C.gold[1], C.gold[2], C.gold[3])
    local clear = W.NewButton(f, L["Remove all"], 110, 22)
    clear:SetPoint("TOPRIGHT", -4, -6)
    clear:SetScript("OnClick", function() W.Click(); S.Clear() end)

    -- the columns, from the right edge of a row
    local RIGHT = { remove = 6, buy = 34, total = 106, each = 208, qty = 300 }
    local WIDTH = { remove = 22, buy = 66, total = 96, each = 86, qty = 60 }
    local heads = { { "qty", L["Amount"] }, { "each", L["Each"] }, { "total", L["Total"] } }
    for _, h in ipairs(heads) do
        local fs = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        fs:SetPoint("TOPRIGHT", f, "TOPRIGHT", -(RIGHT[h[1]] + 6), -44)
        fs:SetWidth(WIDTH[h[1]])
        fs:SetJustifyH("RIGHT")
        fs:SetTextColor(unpack(C.muted))
        fs:SetText(h[2])
    end
    local itemHead = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    itemHead:SetPoint("TOPLEFT", f, "TOPLEFT", 36, -44)
    itemHead:SetTextColor(unpack(C.muted))
    itemHead:SetText(L["Item"])
    local rule = f:CreateTexture(nil, "ARTWORK")
    rule:SetPoint("TOPLEFT", 6, -60)
    rule:SetPoint("TOPRIGHT", -6, -60)
    rule:SetHeight(1)
    rule:SetColorTexture(C.goldDim[1], C.goldDim[2], C.goldDim[3], 0.5)

    f.rows = {}
    for i = 1, MAX_ROWS do
        local r = CreateFrame("Frame", nil, f)
        r:SetHeight(ROW_H)
        r:SetPoint("TOPLEFT", f, "TOPLEFT", 6, -(64 + (i - 1) * ROW_H))
        r:SetPoint("TOPRIGHT", f, "TOPRIGHT", -6, -(64 + (i - 1) * ROW_H))
        r.bg = r:CreateTexture(nil, "BACKGROUND")
        r.bg:SetAllPoints()
        r.bg:SetColorTexture(1, 1, 1, i % 2 == 0 and 0.035 or 0)
        r.pic = r:CreateTexture(nil, "ARTWORK")
        r.pic:SetSize(20, 20)
        r.pic:SetPoint("LEFT", 6, 0)
        r.pic:SetTexCoord(0.07, 0.93, 0.07, 0.93)
        r.name = r:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        r.name:SetPoint("LEFT", r.pic, "RIGHT", 8, 0)
        r.name:SetPoint("RIGHT", r, "RIGHT", -(RIGHT.qty + WIDTH.qty + 12), 0)
        r.name:SetJustifyH("LEFT")
        r.name:SetWordWrap(false)
        r.qty = CreateFrame("EditBox", nil, r, W.TEMPLATE)
        r.qty:SetSize(WIDTH.qty, 20)
        r.qty:SetPoint("RIGHT", r, "RIGHT", -RIGHT.qty, 0)
        r.qty:SetBackdrop(W.PLATE_BACKDROP)
        r.qty:SetBackdropColor(unpack(C.inset))
        r.qty:SetBackdropBorderColor(unpack(C.goldDim))
        r.qty:SetFontObject("GameFontHighlightSmall")
        r.qty:SetAutoFocus(false)
        r.qty:SetNumeric(true)
        r.qty:SetMaxLetters(5)
        r.qty:SetJustifyH("RIGHT")
        r.qty:SetTextInsets(6, 6, 0, 0)
        r.qty:SetScript("OnTextChanged", function(self, user)
            if not user or not r.id then return end
            local n = tonumber(self:GetText()) or 0
            if n > 0 then S.Set(r.id, n); f:Sums() end
        end)
        r.qty:SetScript("OnEnterPressed", function(self) self:ClearFocus(); f:Update() end)
        r.qty:SetScript("OnEscapePressed", function(self) self:ClearFocus(); f:Update() end)
        r.each = r:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        r.each:SetPoint("RIGHT", r, "RIGHT", -RIGHT.each, 0)
        r.each:SetWidth(WIDTH.each)
        r.each:SetJustifyH("RIGHT")
        r.total = r:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        r.total:SetPoint("RIGHT", r, "RIGHT", -RIGHT.total, 0)
        r.total:SetWidth(WIDTH.total)
        r.total:SetJustifyH("RIGHT")
        r.buy = W.NewButton(r, L["Buy"], WIDTH.buy, 20)
        r.buy:SetPoint("RIGHT", r, "RIGHT", -RIGHT.buy, 0)
        r.buy:SetScript("OnClick", function()
            local panel = ns.AuctionBuyPanel
            if panel and r.id then
                W.Click()
                panel:Open(r.id, f, nil, S.Qty(r.id))
            end
        end)
        r.remove = W.NewButton(r, "×", WIDTH.remove, 20, "GameFontNormal")
        r.remove:SetPoint("RIGHT", r, "RIGHT", -RIGHT.remove, 0)
        r.remove:SetScript("OnClick", function() W.Click(); S.Remove(r.id) end)
        r:SetScript("OnEnter", function(self)
            if self.id then
                GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
                GameTooltip:SetHyperlink("item:" .. self.id)
                GameTooltip:Show()
            end
        end)
        r:SetScript("OnLeave", function() GameTooltip:Hide() end)
        r:Hide()
        f.rows[i] = r
    end

    f.empty = f:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    f.empty:SetPoint("TOP", f, "TOP", 0, -110)
    f.empty:SetWidth(420)
    f.empty:SetTextColor(unpack(C.muted))
    f.empty:SetText(L["The list is empty. Put items on it from the buy panel, from a recipe or from the menu of a row."])
    f.sum = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    f.sum:SetPoint("BOTTOMRIGHT", -12, 8)
    f.sum:SetJustifyH("RIGHT")

    -- the total of what has a price
    function f:Sums()
        local st = Store()
        local total, unknown = 0, 0
        for _, id in ipairs(st.order) do
            local price = ns.AH and ns.AH.Price(id)
            if price then total = total + price * (st.qty[id] or 0) else unknown = unknown + 1 end
        end
        local text = L["Total"] .. "  " .. Money(total)
        if unknown > 0 then text = text .. "  |cff8a806e(" .. (L["%d without price"]):format(unknown) .. ")|r" end
        self.sum:SetText(#st.order > 0 and text or "")
    end

    function f:Update()
        local st = Store()
        local fit = math.max(1, math.min(MAX_ROWS, math.floor((self:GetHeight() - 96) / ROW_H)))
        local maxOff = math.max(0, #st.order - fit)
        self.offset = math.min(self.offset, maxOff)
        for i, r in ipairs(self.rows) do
            local id = st.order[self.offset + i]
            if id and i <= fit then
                local name, quality, icon = W.ItemData(id)
                local col = ITEM_QUALITY_COLORS and ITEM_QUALITY_COLORS[quality or 1]
                r.id = id
                r.pic:SetTexture(icon or "Interface\\Icons\\INV_Misc_QuestionMark")
                r.name:SetText((col and col.hex or "|cffffffff") .. (name or ("item:" .. id)) .. "|r")
                local n = st.qty[id] or 0
                if not r.qty:HasFocus() then r.qty:SetText(tostring(n)) end
                local price = ns.AH and ns.AH.Price(id)
                r.each:SetText(price and Money(price) or "|cff8a806e–|r")
                r.total:SetText(price and Money(price * n) or "|cff8a806e–|r")
                r.buy:SetAlpha((price and 1) or 0.5)
                r:Show()
            else
                r.id = nil
                r:Hide()
            end
        end
        self.empty:SetShown(#st.order == 0)
        self:Sums()
    end

    f:EnableMouseWheel(true)
    f:SetScript("OnMouseWheel", function(self, delta)
        self.offset = math.max(0, self.offset - delta * 2)
        self:Update()
    end)
    local acc = 0
    f:SetScript("OnUpdate", function(self, dt)
        acc = acc + dt
        if acc < 2 then return end
        acc = 0
        self:Update()
    end)
    f:SetScript("OnShow", function(self) self:Update() end)
    f:SetScript("OnSizeChanged", function(self) if self:IsShown() then self:Update() end end)
    S.OnChange = function() if f:IsShown() then f:Update() end end
    return f
end
