local ADDON, ns = ...
local L = ns.L
local W = ns.W
local C = W.C

-- The page of your own auctions in the auction house tab: what is on offer now (of all your characters, as far as each was read at the auction
-- house) and the history: auctions that have ended (sold, run out, cancelled), kept in the saved variables (ns.db.ahHistory, written by
-- Account.lua when an auction is gone from the list). A view of the tab like the shopping list.

local O = {}
ns.AuctionOwn = O

local ROW_H = 26
local MAX_ROWS = 24

local function Money(copper, tint) return ns.Value.Format(copper, tint) end

local function ClassName(rec)
    local col = RAID_CLASS_COLORS and rec and rec.class and RAID_CLASS_COLORS[rec.class]
    local name = rec and rec.name or "?"
    if col then return ("|cff%02x%02x%02x%s|r"):format(col.r * 255 + 0.5, col.g * 255 + 0.5, col.b * 255 + 0.5, name) end
    return name
end

-- how long an auction still runs
local function TimeLeft(at)
    local left = at - time()
    if left <= 0 then return "|cffff7a6b" .. L["ended"] .. "|r" end
    local text
    if left >= 86400 then
        text = ("%d %s %d %s"):format(math.floor(left / 86400), L["d"], math.floor((left % 86400) / 3600), L["h"])
    elseif left >= 3600 then
        text = ("%d %s"):format(math.floor(left / 3600), L["h"]) .. (left < 7200 and "" or "")
    else
        text = L["< 1 h"]
    end
    return (left < 7200 and "|cffffa63d" or "|cffffffff") .. text .. "|r"
end

local STATES = {
    sold = { "|cff66dbb0", "Sold" },
    expired = { "|cffff7a6b", "Expired" },
    cancelled = { "|cff8a806e", "Cancelled" },
}

-- a purchase that was made with the buy panel is noted (for the sums of the first page)
function O.Spent(id, qty, total)
    if not (ns.db and total and total > 0) then return end
    local h = ns.db.ahSpent
    if not h then h = {}; ns.db.ahSpent = h end
    h[#h + 1] = { id = id, count = qty or 1, total = total, at = time() }
    while #h > 500 do table.remove(h, 1) end
end

function O.Build(parent)
    local f = CreateFrame("Frame", nil, parent)
    f:Hide()
    f.offset = 0
    f.mode = "active" -- "active" | "history"

    f.title = f:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    f.title:SetPoint("TOPLEFT", 10, -8)
    f.title:SetText(L["Auctions"])
    f.title:SetTextColor(C.gold[1], C.gold[2], C.gold[3])

    -- the two lists: what is on offer, and what has ended
    f.buttons = {}
    local x = 0
    for _, def in ipairs({ { "active", L["On offer"] }, { "history", L["History"] } }) do
        local b = W.NewButton(f, def[2], 110, 22)
        b:SetPoint("TOPRIGHT", f, "TOPRIGHT", -4 - x, -6)
        b.mode = def[1]
        b:SetScript("OnClick", function()
            W.Click()
            f.mode, f.offset = def[1], 0
            f:Update()
        end)
        f.buttons[#f.buttons + 1] = b
        x = x + 116
    end

    -- the heads: the columns from the right edge of a row
    local RIGHT = { status = 6, total = 134, each = 238, char = 340 }
    local WIDTH = { status = 120, total = 100, each = 96, char = 110 }
    f.heads = {}
    local function Head(key, text, justify)
        local fs = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        fs:SetPoint("TOPRIGHT", f, "TOPRIGHT", -(RIGHT[key] + 6), -44)
        fs:SetWidth(WIDTH[key])
        fs:SetJustifyH(justify or "RIGHT")
        fs:SetTextColor(unpack(C.muted))
        fs:SetText(text)
        f.heads[key] = fs
        return fs
    end
    Head("status", "")
    Head("total", L["Total"])
    Head("each", L["Each"])
    Head("char", L["Character"], "LEFT")
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
        r.name:SetPoint("RIGHT", r, "RIGHT", -(RIGHT.char + WIDTH.char + 12), 0)
        r.name:SetJustifyH("LEFT")
        r.name:SetWordWrap(false)
        r.cell = {}
        for _, key in ipairs({ "char", "each", "total", "status" }) do
            local fs = r:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
            fs:SetPoint("RIGHT", r, "RIGHT", -RIGHT[key], 0)
            fs:SetWidth(WIDTH[key])
            fs:SetJustifyH(key == "char" and "LEFT" or "RIGHT")
            fs:SetWordWrap(false)
            r.cell[key] = fs
        end
        r:EnableMouse(true)
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
    f.empty:SetWidth(460)
    f.empty:SetTextColor(unpack(C.muted))
    f.sum = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    f.sum:SetPoint("BOTTOMRIGHT", -12, 8)
    f.sum:SetJustifyH("RIGHT")
    f.sum:SetTextColor(unpack(C.muted))

    -- what is on offer now (all characters), by the time they run out; and what has ended, the latest first
    local function Entries(mode)
        local out = {}
        if mode == "active" then
            for _, rec in ipairs(ns.Acc and ns.Acc.Chars and ns.Acc.Chars() or {}) do
                for _, a in ipairs(rec.auctions and rec.auctions.list or {}) do
                    out[#out + 1] = { id = a.id, count = a.count or 1, buyout = a.buyout or 0, rec = rec, left = a.left }
                end
            end
            table.sort(out, function(a, b) return (a.left or math.huge) < (b.left or math.huge) end)
        else
            local keyed = {}
            for _, rec in ipairs(ns.Acc and ns.Acc.Chars and ns.Acc.Chars() or {}) do keyed[rec.key] = rec end
            local h = ns.db and ns.db.ahHistory or {}
            for i = #h, 1, -1 do
                local e = h[i]
                out[#out + 1] = { id = e.id, count = e.count or 1, buyout = e.buyout or 0, rec = keyed[e.char], char = e.char, state = e.state, at = e.at }
            end
        end
        return out
    end

    function f:Update()
        for _, b in ipairs(self.buttons) do b:SetSelected(b.mode == self.mode) end
        local list = Entries(self.mode)
        local fit = math.max(1, math.min(MAX_ROWS, math.floor((self:GetHeight() - 96) / ROW_H)))
        local maxOff = math.max(0, #list - fit)
        self.offset = math.min(self.offset, maxOff)
        self.heads.status:SetText(self.mode == "active" and L["Time left"] or L["Result"])
        local total, sold = 0, 0
        for _, e in ipairs(list) do
            total = total + e.buyout
            if e.state == "sold" then sold = sold + e.buyout end
        end
        for i, r in ipairs(self.rows) do
            local e = list[self.offset + i]
            if e and i <= fit then
                local name, quality, icon = W.ItemData(e.id)
                local col = ITEM_QUALITY_COLORS and ITEM_QUALITY_COLORS[quality or 1]
                r.id = e.id
                r.pic:SetTexture(icon or "Interface\\Icons\\INV_Misc_QuestionMark")
                r.name:SetText((col and col.hex or "|cffffffff") .. (name or ("item:" .. e.id)) .. "|r" .. (e.count > 1 and (" |cff8a806e×" .. e.count .. "|r") or ""))
                r.cell.char:SetText(e.rec and ClassName(e.rec) or (e.char or ""))
                r.cell.total:SetText(e.buyout > 0 and Money(e.buyout) or "|cff8a806e–|r")
                r.cell.each:SetText(e.buyout > 0 and Money(math.floor(e.buyout / math.max(1, e.count))) or "|cff8a806e–|r")
                if self.mode == "active" then
                    r.cell.status:SetText(e.left and TimeLeft(e.left) or "|cff8a806e–|r")
                else
                    local st = STATES[e.state] or STATES.cancelled
                    r.cell.status:SetText(st[1] .. L[st[2]] .. "|r  |cff8a806e" .. date("%d.%m. %H:%M", e.at or 0) .. "|r")
                end
                r:Show()
            else
                r.id = nil
                r:Hide()
            end
        end
        if self.mode == "active" then
            self.empty:SetText(L["Nothing on offer. Auctions are read when you open the auction house with a character."])
            self.sum:SetText(#list > 0 and ((L["%d auctions, worth %s"]):format(#list, Money(total))) or "")
        else
            self.empty:SetText(L["No finished auctions yet. They are noted when they have gone from your list."])
            self.sum:SetText(#list > 0 and ((L["%d finished, %s sold"]):format(#list, Money(sold))) or "")
        end
        self.empty:SetShown(#list == 0)
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
    -- the list of your auctions is asked for when the page is opened (the game answers with an update that Account.lua reads)
    f:SetScript("OnShow", function(self)
        if C_AuctionHouse and C_AuctionHouse.QueryOwnedAuctions and ns.AH and ns.AH.IsOpen() then
            pcall(C_AuctionHouse.QueryOwnedAuctions, {})
        end
        self:Update()
    end)
    f:SetScript("OnSizeChanged", function(self) if self:IsShown() then self:Update() end end)
    return f
end
