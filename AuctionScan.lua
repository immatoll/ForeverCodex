local ADDON, ns = ...
local L = ns.L

-- Our own auction prices, for those who do not run Auctionator (or do not want to rely on it).
-- Opening the auction house scans it once (the whole list in one go, in small steps so the game
-- does not stall); per item the price of a single piece is kept, per realm and faction. The
-- price source "auction" uses these prices first when the setting is on.

local AH = {}
ns.AH = AH

local OPEN_DELAY = 10    -- seconds after opening before the automatic scan starts, so that the game can load its data first
local PER_FRAME = 400    -- rows read per frame while a scan is processed
local COOLDOWN = 900     -- the full list may be asked for once in 15 minutes (older interface)
local KEEP = 3           -- the cheapest listings per item that are looked at
local HOUR, DAY = 3600, 86400
local MAX_TRACK = 3000   -- items followed at most
local HIST_STALE = 60    -- an item not seen for this many days drops out of the history
local HIST_KEEP = 365    -- the oldest history kept, in days

local isOpen, waiting, job = false, nil, nil
local scanToken
local ours = false         -- true while this addon itself asks for the list (to tell it from other addons' requests)
local startAt = nil     -- when the automatic scan is due (GetTime)

-- the first version kept one entry per day: { d = first day, p = {...}, q = {...} }
local function Upgrade(e)
    if not e.d then return end
    local t, p, q = {}, {}, {}
    for i = 1, #e.p do
        if e.p[i] > 0 then
            t[#t + 1], p[#p + 1], q[#q + 1] = (e.d + i - 1) * DAY + DAY / 2, e.p[i], e.q[i] or 0
        end
    end
    e.d, e.t, e.p, e.q = nil, t, p, q
end

-- The realm name can be empty early after login; then the last known one stands in (and a store made under an
-- empty name by an older version is merged into the real one).
local lastRealm
local function RealmName()
    local realm = GetRealmName and GetRealmName()
    if realm and realm ~= "" then
        lastRealm = realm
        if ns.db then ns.db.lastRealm = realm end
        return realm
    end
    if lastRealm then return lastRealm end
    local db = ns.db
    if db and db.lastRealm then return db.lastRealm end
    for _, rec in pairs(db and db.account and db.account.chars or {}) do
        if rec.realm and rec.realm ~= "" then return rec.realm end
    end
    return "?"
end

local function Key()
    return RealmName() .. "-" .. (UnitFactionGroup("player") or "?")
end

local mended
local function Mend(db)
    if mended then return end
    mended = true
    local stores = db.ahData
    for key, src in pairs(stores) do
        local faction = key:match("^%-(.+)$")
        if faction then
            local target = stores[RealmName() .. "-" .. faction]
            if target and target ~= src then
                if (src.time or 0) > (target.time or 0) then
                    -- the older scan becomes the first point of the newer one's history
                    for id, e in pairs(src.hist or {}) do
                        Upgrade(e)
                        local old = target.prices and target.prices[id]
                        if old and e.t and e.t[1] and e.t[1] > (target.time or 0) then
                            table.insert(e.t, 1, target.time); table.insert(e.p, 1, old); table.insert(e.q, 1, 0)
                        end
                    end
                    stores[RealmName() .. "-" .. faction] = src
                end
                stores[key] = nil
            end
        end
    end
end

local function Store()
    local db = ns.db
    if not db then return nil end
    db.ahData = db.ahData or {}
    Mend(db)
    return db.ahData[Key()]
end

function AH.Enabled() return ns.db and ns.db.settings and ns.db.settings.ownAuction == true end
function AH.Price(id)
    local s = Store()
    return s and s.prices and s.prices[id] or nil
end
function AH.Time()
    local s = Store()
    return s and s.time or nil
end
function AH.IsOpen() return isOpen end

-- The server only answers a full scan now and then; when it is asked too early it stays silent, and the wait
-- ends without a result. So the last request is remembered (also across a reload), and no new one is made
-- before COOLDOWN has passed.
function AH.CooldownLeft()
    local last = ns.db and ns.db.ahLastRequest or 0
    return math.max(0, last + COOLDOWN - time())
end
-- the supply seen at the last scan that listed the item
function AH.Supply(id)
    local st = Store()
    local e = st and st.hist and st.hist[id]
    if not e then return nil end
    Upgrade(e)
    return e.q[#e.q]
end

-- A rough demand: how many pieces left the offers between two scans, per day, over the last `days` days. That is
-- sales, but also auctions that expired or were cancelled, while new listings hide some; so it is a guide, not a
-- count. nil when there are no two scans at least three hours apart.
function AH.Demand(id, days)
    local st = Store()
    local e = st and st.hist and st.hist[id]
    if not e then return nil end
    Upgrade(e)
    local from = time() - days * DAY
    local first, last, gone = nil, nil, 0
    for i = 1, #e.t do
        if e.t[i] >= from then
            if first == nil then
                first = i
            else
                local d = (e.q[i - 1] or 0) - (e.q[i] or 0)
                if d > 0 then gone = gone + d end
            end
            last = i
        end
    end
    if not first or last == first then return nil end
    local span = e.t[last] - e.t[first]
    if span < 3 * HOUR then return nil end
    return gone / (span / DAY), span / DAY
end

-- The demand per day of the last `days` days (0: no scans that day), for small bars: the pieces that left the offers
-- between the scans of a day, as a rate per day. Also the number of days that have a value; nil when none has.
function AH.DemandSeries(id, days)
    local st = Store()
    local e = st and st.hist and st.hist[id]
    if not e then return nil end
    Upgrade(e)
    local today = math.floor(time() / DAY) -- (not Today(): that local is only defined further down)
    local gone, hours = {}, {}
    for i = 1, days do gone[i], hours[i] = 0, 0 end
    for i = 2, #e.t do
        local idx = math.floor(e.t[i] / DAY) - (today - days)
        if idx >= 1 and idx <= days then
            local dt = (e.t[i] - e.t[i - 1]) / HOUR
            if dt > 0 then
                gone[idx] = gone[idx] + math.max(0, (e.q[i - 1] or 0) - (e.q[i] or 0))
                hours[idx] = hours[idx] + dt
            end
        end
    end
    local rate, n = {}, 0
    for i = 1, days do
        if hours[i] >= 3 then rate[i] = gone[i] / hours[i] * 24; n = n + 1 else rate[i] = 0 end
    end
    if n == 0 then return nil end
    return rate, n
end

-- every price of the last scan (id -> copper per piece)
function AH.Prices()
    local s = Store()
    return s and s.prices or {}
end
-- the items that have a price history
function AH.HistIds()
    local s, ids = Store(), {}
    for id in pairs(s and s.hist or {}) do ids[#ids + 1] = id end
    return ids
end
function AH.Scanning() return job ~= nil or waiting ~= nil end

-- how far a running scan is: "wait" (asked, nothing yet) or "read" with the fraction, nil when idle
function AH.Progress()
    if job then return "read", job.i / math.max(1, job.n) end
    if waiting then return "wait", 0 end
    return nil
end

-- a line for the settings: what there is and how old it is
function AH.Status()
    if startAt and not job and not waiting then
        return (L["Scan starts in %d s…"]):format(math.max(0, math.ceil(startAt - GetTime())))
    end
    if job then return L["Scanning… %d %%"]:format(math.floor(job.i / math.max(1, job.n) * 100)) end
    if waiting then return L["Waiting for the auction house…"] end
    local s = Store()
    if not s then return L["No auction scan yet."] end
    local text = L["Last scan: %s · %d items"]:format(ns.Ago(s.time), s.count or 0)
    local left = AH.CooldownLeft()
    if left > 0 then text = text .. " · " .. (L["next in %d min"]):format(math.ceil(left / 60)) end
    return text
end

-- one row of the list, whichever interface the client has: itemID, count, buyout
local function ModernRow(i)
    local r = { pcall(C_AuctionHouse.GetReplicateItemInfo, i) }
    if not r[1] then return end
    return r[18], r[4], r[11]
end
local function LegacyRow(i)
    local r = { pcall(GetAuctionItemInfo, "list", i) }
    if not r[1] then return end
    return r[18], r[4], r[11]
end
-- (count and buyout sit at 3 and 10 of the values; r[1] is pcall's flag, so everything is one further)

-- History: per item a list of samples (time, price of a piece, number on offer), only for the items that matter
-- to you (what you loot, carry, craft with, or looked at in a tooltip). The older a sample, the coarser the
-- raster it is kept in: the last 24 hours every two hours, then a day, then a week, then a month. That keeps the
-- file small however long you play.
local function Today() return math.floor(time() / DAY) end

local function Bucket(age, t)
    if age <= DAY then return "h" .. math.floor(t / (2 * HOUR)) end
    if age <= 14 * DAY then return "d" .. math.floor(t / DAY) end
    if age <= 84 * DAY then return "w" .. math.floor(t / (7 * DAY)) end
    return "m" .. math.floor(t / (30 * DAY))
end

local function Compact(e, now)
    local t, p, q, last = {}, {}, {}, nil
    for i = 1, #e.t do
        local age = now - e.t[i]
        if age <= HIST_KEEP * DAY then
            local key = Bucket(age, e.t[i])
            if key == last then
                t[#t], p[#p], q[#q] = e.t[i], e.p[i], e.q[i] -- a later sample of the same raster cell replaces it
            else
                t[#t + 1], p[#p + 1], q[#q + 1] = e.t[i], e.p[i], e.q[i]
                last = key
            end
        end
    end
    e.t, e.p, e.q = t, p, q
end

local function Record(hist, id, now, price, qty)
    local e = hist[id]
    if not e then e = { t = {}, p = {}, q = {} }; hist[id] = e end
    Upgrade(e)
    local n = #e.t
    if n > 0 and now < e.t[n] then return end -- the clock went back
    e.t[n + 1], e.p[n + 1], e.q[n + 1] = now, price, qty
    Compact(e, now)
end

local function TrackedIds(store, prices)
    local set = {}
    if prices and ns.db.settings and ns.db.settings.ahTrackAll then
        for id in pairs(prices) do set[id] = true end
    end
    for id in pairs(ns.db.items or {}) do set[id] = true end
    if ns.Acc and ns.Acc.AllItemIds then
        for id in pairs(ns.Acc.AllItemIds()) do set[id] = true end
        for _, r in ipairs(ns.Acc.Recipes()) do
            if r.id then set[r.id] = true end
            for _, g in ipairs(r.reagents or {}) do set[g.id] = true end
        end
    end
    local day = Today()
    local watch = ns.db.ahWatch
    if watch then
        for id, d in pairs(watch) do
            if day - d > 60 then watch[id] = nil else set[id] = true end
        end
    end
    for id in pairs(store and store.hist or {}) do set[id] = true end
    return set
end

-- an item looked at in a tooltip is followed from the next scan on
function AH.Watch(id)
    if not (ns.db and id) then return end
    ns.db.ahWatch = ns.db.ahWatch or {}
    local day = Today()
    if ns.db.ahWatch[id] ~= day then ns.db.ahWatch[id] = day end
end

-- the last `days` days of one item: price and supply per day (0: no data; the last scan of a day counts),
-- the average price over the samples of that time, and how many samples that is
function AH.Trend(id, days)
    local st = Store()
    local e = st and st.hist and st.hist[id]
    if not e then return nil end
    Upgrade(e)
    local today = Today()
    local price, qty, sum, n = {}, {}, 0, 0
    for i = 1, days do price[i], qty[i] = 0, 0 end
    for i = 1, #e.t do
        local idx = math.floor(e.t[i] / DAY) - (today - days)
        if idx >= 1 and idx <= days then
            price[idx], qty[idx] = e.p[i], e.q[i]
            if e.p[i] > 0 then sum, n = sum + e.p[i], n + 1 end
        end
    end
    if n < 2 then return nil end
    return price, qty, math.floor(sum / n), n
end

local function Finish()
    local prices, items = {}, 0
    for id, list in pairs(job.tmp) do
        -- the cheapest listing may be a mistake or bait: with enough of them take the second
        prices[id] = list[#list >= KEEP and 2 or 1]
        items = items + 1
    end
    ns.db.ahData = ns.db.ahData or {}
    local old = ns.db.ahData[Key()]
    local hist = old and old.hist or {}
    local now, n = time(), 0
    local limit = (ns.db.settings and ns.db.settings.ahTrackAll) and 15000 or MAX_TRACK
    for id in pairs(TrackedIds(old, prices)) do
        if n >= limit then break end
        if prices[id] or hist[id] then
            Record(hist, id, now, prices[id] or 0, job.qty[id] or 0)
            n = n + 1
        end
    end
    for id, e in pairs(hist) do -- what has not been seen for a long time goes
        Upgrade(e)
        if #e.t == 0 or now - e.t[#e.t] > HIST_STALE * DAY then hist[id] = nil end
    end
    ns.db.ahData[Key()] = { prices = prices, time = time(), count = items, hist = hist }
    job = nil
    print("|cffffd100ForeverCodex:|r " .. L["Auction scan done: %d items."]:format(items))
    ns.Value.Reset()
    ns.Refresh()
end

local worker = CreateFrame("Frame")
worker:Hide()
worker:SetScript("OnUpdate", function(self)
    if not job then self:Hide() return end
    local stop = math.min(job.n, job.i + PER_FRAME - 1)
    for i = job.i, stop do
        local id, count, buyout = job.row(i)
        id, count, buyout = ns.ReadableNumber(id), ns.ReadableNumber(count), ns.ReadableNumber(buyout)
        if id and count and buyout and count > 0 and buyout > 0 then
            local unit = math.floor(buyout / count)
            job.qty[id] = (job.qty[id] or 0) + count
            local list = job.tmp[id]
            if not list then
                job.tmp[id] = { unit }
            else
                list[#list + 1] = unit
                table.sort(list)
                if #list > KEEP then list[#list] = nil end
            end
        end
    end
    job.i = stop + 1
    if job.i > job.n then
        self:Hide()
        Finish()
    end
end)

local function Process(row, n)
    if not n or n <= 0 then return end -- (an update without items: keep waiting for the real one)
    waiting = nil
    job = { row = row, n = n, i = 1, tmp = {}, qty = {} }
    worker:Show()
end

-- Ask for the list. Returns true, or false and the reason.
function AH.Scan()
    if job or waiting then return false, L["A scan is running."] end
    if not isOpen then return false, L["Open the auction house first."] end
    local left = AH.CooldownLeft()
    if left > 0 then
        return false, L["The auction house allows a full scan only every 15 minutes."] .. " "
            .. (L["Next one in %d min."]):format(math.ceil(left / 60))
    end
    if C_AuctionHouse and C_AuctionHouse.ReplicateItems then
        waiting = "modern"
        ns.db.ahLastRequest = time()
        ours = true
        C_AuctionHouse.ReplicateItems()
        ours = false
    elseif QueryAuctionItems and CanSendAuctionQuery then
        local _, canAll = CanSendAuctionQuery("list")
        if not canAll then return false, L["The auction house allows a full scan only every 15 minutes."] end
        waiting = "legacy"
        ns.db.ahLastRequest = time()
        ours = true
        QueryAuctionItems("", nil, nil, 0, false, 0, true, false, nil)
        ours = false
    else
        return false, L["This client has no way to read the auction house."]
    end
    local mine = waiting .. GetTime()
    scanToken = mine
    C_Timer.After(30, function()
        if waiting and scanToken == mine then
            waiting = nil
            print("|cffffd100ForeverCodex:|r " .. L["No answer from the auction house. It limits full scans; try again in a few minutes."])
        end
    end)
    return true
end

-- Other addons (Auctionator and the like, or the game's own interface) may ask for the full list as well. The list is the
-- same for everybody and the server only gives it out now and then, so a request that is seen is read along instead
-- of asking again: the answer comes to us too. It also counts as the last request (the waiting time is shared).
local function Noticed(kind)
    if ours or job or waiting then return end
    if ns.db then ns.db.ahLastRequest = time() end
    isOpen = true -- a request can only be made at the auction house (this may come before our own "opened" event)
    if not AH.Enabled() then return end
    waiting = kind
    local mine = kind .. GetTime()
    scanToken = mine
    C_Timer.After(30, function() if waiting and scanToken == mine then waiting = nil end end)
    print("|cffffd100ForeverCodex:|r " .. L["Another addon is reading the auction house: reading along."])
end
if C_AuctionHouse and C_AuctionHouse.ReplicateItems then
    hooksecurefunc(C_AuctionHouse, "ReplicateItems", function() Noticed("modern") end)
end
if QueryAuctionItems then
    -- (text, minLevel, maxLevel, page, isUsable, quality, getAll, ...): only a request for the whole list matters
    hooksecurefunc("QueryAuctionItems", function(_, _, _, _, _, _, getAll)
        if getAll then Noticed("legacy") end
    end)
end

local events = CreateFrame("Frame")
for _, e in ipairs({ "AUCTION_HOUSE_SHOW", "AUCTION_HOUSE_CLOSED", "REPLICATE_ITEM_LIST_UPDATE", "AUCTION_ITEM_LIST_UPDATE" }) do
    pcall(events.RegisterEvent, events, e) -- an event the client does not have is skipped
end
events:SetScript("OnEvent", function(_, event)
    if event == "AUCTION_HOUSE_SHOW" then
        isOpen = true
        -- scanned on opening when the setting is on and the last scan is not fresh
        local s = Store()
        if AH.Enabled() and AH.CooldownLeft() == 0 and (not s or time() - (s.time or 0) > COOLDOWN) then
            local due = GetTime() + OPEN_DELAY
            startAt = due
            C_Timer.After(OPEN_DELAY, function()
                if startAt ~= due then return end -- closed meanwhile, or opened again
                startAt = nil
                if AH.Enabled() and isOpen then AH.Scan() end
            end)
        end
    elseif event == "AUCTION_HOUSE_CLOSED" then
        isOpen = false
        startAt = nil
    elseif event == "REPLICATE_ITEM_LIST_UPDATE" and waiting == "modern" then
        Process(ModernRow, C_AuctionHouse.GetNumReplicateItems())
    elseif event == "AUCTION_ITEM_LIST_UPDATE" and waiting == "legacy" then
        local batch = GetNumAuctionItems("list")
        Process(LegacyRow, batch)
    end
end)
