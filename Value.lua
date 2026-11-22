local _, ns = ...

-- Price provider. Everything that needs an item value goes through
-- ns.Value.Get, so an auction source only has to be added here.
local V = {}
ns.Value = V

local GetInfo = GetItemInfo or (C_Item and C_Item.GetItemInfo)
local vendorCache = {}

local function Vendor(id)
    local cached = vendorCache[id]
    if cached then return cached end
    local sell = select(11, GetInfo(id))
    if sell then
        vendorCache[id] = sell
        return sell
    end
    -- not cached by the client yet; GET_ITEM_INFO_RECEIVED triggers a refresh
    if C_Item and C_Item.RequestLoadItemDataByID then C_Item.RequestLoadItemDataByID(id) end
    return 0
end

local function Auction(id)
    local api = Auctionator and Auctionator.API and Auctionator.API.v1
    if api and api.GetAuctionPriceByItemID then
        local ok, price = pcall(api.GetAuctionPriceByItemID, "ForeverCodex", id)
        if ok and price and price > 0 then return price end
    end
    return nil
end

-- Copper per single item.
function V.Get(id)
    if ns.db and ns.db.valueSource == "auction" then
        -- our own scans first when they are switched on; Auctionator is what is left
        local own = ns.AH and ns.AH.Enabled() and ns.AH.Price(id)
        if own then return own end
        local p = Auction(id)
        if p then return p end
    end
    return Vendor(id)
end

function V.Reset() wipe(vendorCache) end

-- for tooltips: the vendor price, and the auction price with where it comes from
-- ("own" = our scan, with its time; "Auctionator")
V.Vendor = Vendor
function V.AuctionPrice(id)
    local own = ns.AH and ns.AH.Price(id)
    if own then return own, "own", ns.AH.Time() end
    local p = Auction(id)
    if p then return p, "Auctionator" end
end

-- "2g 9s 0c" / "38s 72c" / "45c": the numbers in the text's own colour, only the coin letters coloured.
-- tint (a "|cffrrggbb" prefix) colours the numbers, for a profit (green) or a loss (red).
-- Empty string for zero.
function V.Format(copper, tint)
    copper = math.floor(copper or 0)
    if copper <= 0 then return "" end
    local g = math.floor(copper / 10000)
    local s = math.floor(copper / 100) % 100
    local c = copper % 100
    -- silver and copper after a larger coin are always two digits ("1g 05s 08c"): the figures keep their width and line up
    local num, num2 = tint and (tint .. "%d|r") or "%d", tint and (tint .. "%02d|r") or "%02d"
    local G, S, C = num .. "|cffffd700g|r", num .. "|cffc7c7cfs|r", num .. "|cffeda55fc|r"
    local S2, C2 = num2 .. "|cffc7c7cfs|r", num2 .. "|cffeda55fc|r"
    -- the first coin that is there and every one after it, also at 0: "1g 00s 08c", "38s 00c", "45c"
    if g > 0 then
        return string.format(G, g) .. " " .. string.format(S2, s) .. " " .. string.format(C2, c)
    elseif s > 0 then
        return string.format(S, s) .. " " .. string.format(C2, c)
    end
    return string.format(C, c)
end
