local ADDON, ns = ...
local L = ns.L
local W = ns.W
local C = W.C

-- A tab of our own in the game's auction house window ("Companion", next to Buy / Sell / Auctions): the data scan
-- with its progress, the price trends of what the scan follows, and a comparison of vendor against auction
-- house for what you carry. It is made the first time the auction house opens (the window does not exist
-- before), the way Auctionator's tab library does it for the modern auction house.

local T = {}
ns.AuctionTab = T

local ROW, HEAD = 24, 22
local DAYS = 7
local BAR_W, BAR_GAP, BAR_H = 6, 2, 16
local FEE = 0.05          -- the auction house keeps this much of a sale
local SIDE_W = 176               -- the filters stand in a column on the left (it can be folded away)
local LEFT0 = SIDE_W + 18        -- where the list begins (when the column stays open)
local HANDLE_W, SIDE_TOP, SIDE_BOTTOM = 20, 48, 12   -- the strip at the left edge; where the column begins and ends (the footer is under the panel)
local HIDDEN = HANDLE_W + 4       -- the column's width when it has slid away (only the strip is left)
local headY, listTop = 48, 74
local NAME_MIN = 200             -- the item name always keeps this much room; columns give way first
local left0 = LEFT0              -- where the list begins now (the column may be folded away)
local LIST_RIGHT = 24     -- from the panel's right edge to the list's (the scroll bar sits between)
-- constants that the page builder needs, in one table: a function may reach only 60 outer variables, and Build was at the limit
local K = { ROW = ROW, HEAD = HEAD, SIDE_W = SIDE_W, LEFT0 = LEFT0, HANDLE_W = HANDLE_W, SIDE_TOP = SIDE_TOP, SIDE_BOTTOM = SIDE_BOTTOM,
    HIDDEN = HIDDEN, OPEN = SIDE_W + 6, LIST_RIGHT = LIST_RIGHT }

-- some clients only have the item functions in C_Item
local GetInfo = GetItemInfo or (C_Item and C_Item.GetItemInfo)
local GetInstant = GetItemInfoInstant or (C_Item and C_Item.GetItemInfoInstant)

-- Every view has its own filters and sort (kept in the settings); `state` reads and writes those of the view that is
-- shown, so that the code can say state.class whatever the view is. state.view is the view itself.
local viewData, currentView = {}, "dash"
local state = setmetatable({}, {
    __index = function(_, k)
        if k == "view" then return currentView end
        local d = viewData[currentView]
        return d and d[k]
    end,
    __newindex = function(_, k, v)
        if k == "view" then currentView = v; return end
        local d = viewData[currentView]
        if d then d[k] = v end
    end,
})
local panel, tab, rows, content, scroll, count, status, scanBtn, scanNote, empty, heads, thumb, track, indexNote
local data, pool, histSet = {}, {}, {}
local results = {}                    -- per view: the last finished list (shown at once when the view is chosen again)
local SLICE_MS = 5                   -- how long the list may work per frame
local recCache = { all = {}, trend = {}, profit = {}, recipes = {} } -- the rows are kept and filled again, not made anew
local poolCache = {}                  -- the pool and the id list of the view of everything, while the scan is the same
local collectHave = {}                -- what the chosen characters carry (for the recipes)
local collectLoc                      -- where the items of "Sell" are: in the bags of this character, in its bank, with another character
local poolExtra = {}                  -- items whose data is needed too (products and materials of recipes)
local job, driver, collectStamp           -- the list being worked out, the frame that works on it, the scan it is for
local poolVersion, indexedVersion = 0, -1 -- (when the items change, their names are looked at again)
local statCache, statStamp = {}, nil
local dirty, created = true, false
local failed, tries = {}, {}   -- items the game does not give (not loaded after several tries, or reported as unknown)
local meta, idx, asked = {}, {}, {}   -- per item: class; name and vendor price once the game has them; when asked

-- the views and their columns, from the right edge: { id, width, title, tip, gives way (low numbers go first) }
local VIEWS = {
    dash = {
        label = L["Dashboard"], icon = W.ICON.loot,
        cols = {},
        sort = "name", asc = true,
    },
    own = {
        label = L["Auctions"], icon = "Interface\\Icons\\INV_Misc_Coin_03",
        cols = {},
        sort = "name", asc = true,
    },
    shop = {
        label = L["Shopping list"], icon = "Interface\\Icons\\INV_Misc_Bag_09",
        cols = {},
        sort = "name", asc = true,
    },
    all = {
        label = L["Market"], icon = "Interface\\Icons\\INV_Misc_Bag_08",
        cols = {
            { "price", 92, L["Price"] },
            { "avg", 92, L["Avg. 7d"], L["The average price of the last 7 days (from your scans)."], 2 },
            { "demand", 70, L["Demand"], L["Estimated sales per day: pieces that left the offers between your scans. Expired and cancelled auctions count too, and new listings hide some, so take it as a guide."], 1 },
            { "supply", 70, L["Supply"], L["How many pieces were on offer at the last scan."], 3 },
        },
        sort = "name", asc = true,
    },
    trend = {
        label = L["Trends"], icon = W.ICON.rate,
        cols = {
            { "price", 92, L["Price"] },
            { "avg", 88, L["Avg. 7d"], nil, 2 },
            { "diff", 66, L["vs. avg."], L["The price now against the average of the last 7 days."] },
            { "supply", 60, L["Supply"], L["How many pieces were on offer at the last scan."], 4 },
            { "demand", 66, L["Demand"], L["Estimated sales per day: pieces that left the offers between your scans. Expired and cancelled auctions count too, and new listings hide some, so take it as a guide."], 1 },
            { "trend", DAYS * (BAR_W + BAR_GAP) + 14, L["Trend"], L["Price of the last 7 days; the last bar is the latest scan."], 3 },
        },
        sort = "diff", asc = true,
    },
    recipes = {
        label = L["Craft"], icon = "Interface\\Icons\\INV_Scroll_03",
        cols = {
            { "profit", 98, L["Profit"], L["What it sells for on the auction house (after the fee) minus what its materials cost."] },
            { "cost", 88, L["Materials"], L["What the materials cost: the auction price, or the vendor price where there is none."], 3 },
            { "value", 88, L["Sells for"], L["The auction price of the item after the fee (or its disenchant value, when that is chosen at the left). Without a price there is no profit."], 4 },
            { "demand", 66, L["Demand"], L["Estimated sales per day of the product: pieces that left the offers between your scans. Expired and cancelled auctions count too, and new listings hide some, so take it as a guide."], 2 },
            { "can", 46, L["Now"], L["How many you can make now with what the chosen characters carry."] },
            { "known", 124, L["Known by"], nil, 1 },
        },
        sort = "profit", asc = false,
    },
    profit = {
        label = L["Sell"], icon = W.ICON.coin,
        cols = {
            { "total", 98, L["Gain total"], L["Gain of selling all pieces on the auction house instead of to a vendor."] },
            { "gain", 92, L["Gain each"], L["The auction price after the fee, minus what it is compared with (a vendor's price, or the disenchant value)."], 3 },
            { "vendor", 84, L["Vendor"], L["What it is compared with: what a vendor pays, or the estimated disenchant value (switch at the left)."], 1 },
            { "price", 88, L["AH"], nil, 2 },
            { "count", 46, L["Qty"] },
        },
        sort = "total", asc = false,
    },
}
local VIEW_ORDER = { "dash", "all", "profit", "own", "recipes", "trend", "shop" }
-- pages have no table of their own (the dashboard, the shopping list)
function T.IsPage(v) return v == "dash" or v == "shop" or v == "own" end

local CLASSES = { 0, 7, 2, 4, 9, 1, 3, 15 } -- consumable, trade goods, weapon, armor, recipe, container, gem, misc
local SLOTS = {
    { "head", { "INVTYPE_HEAD" } }, { "neck", { "INVTYPE_NECK" } }, { "shoulder", { "INVTYPE_SHOULDER" } },
    { "cloak", { "INVTYPE_CLOAK" } }, { "chest", { "INVTYPE_CHEST", "INVTYPE_ROBE" } }, { "wrist", { "INVTYPE_WRIST" } },
    { "hands", { "INVTYPE_HAND" } }, { "waist", { "INVTYPE_WAIST" } }, { "legs", { "INVTYPE_LEGS" } },
    { "feet", { "INVTYPE_FEET" } }, { "finger", { "INVTYPE_FINGER" } }, { "trinket", { "INVTYPE_TRINKET" } },
    { "shield", { "INVTYPE_SHIELD" } }, { "offhand", { "INVTYPE_HOLDABLE" } },
}
local SLOT_BY_KEY = {}
for _, sl in ipairs(SLOTS) do SLOT_BY_KEY[sl[1]] = sl[2] end
local GetSubName = GetItemSubClassInfo or (C_Item and C_Item.GetItemSubClassInfo)
local counts, classCount = {}, {}   -- what the list holds, per class and subclass (for the category menu)

local CLASS_FALLBACK = { [0] = L["Consumable"], [1] = L["Container"], [2] = L["Weapon"], [3] = L["Gem"], [4] = L["Armor"],
    [7] = L["Trade goods"], [9] = L["Recipe"], [15] = L["Miscellaneous"] }

local active, activeKey = {}, {}   -- per view: the columns that fit now
local function Cols(view) return active[view] or VIEWS[view].cols end
local function ColRight(view, i)
    local x, cols = 0, Cols(view)
    for k = 1, i - 1 do x = x + cols[k][2] end
    return x
end
local function ColsWidth(view) return ColRight(view, #Cols(view) + 1) end
local function HasCol(view, id)
    for _, col in ipairs(Cols(view)) do if col[1] == id then return true end end
end

-- What fits: when the window is too narrow, the columns of the lowest "gives way" number go first, so that the name
-- keeps its room. Returns true when the set of columns has changed.
local function Compute(listWidth)
    local avail = listWidth - 54 - NAME_MIN
    local changed = false
    for view, def in pairs(VIEWS) do
        local list, sum = {}, 0
        for _, col in ipairs(def.cols) do
            -- (the demand stays with a filter set too: the supply is shown beside it, and a narrow list gives way to it last)
            list[#list + 1] = col; sum = sum + col[2]
        end
        while sum > avail do
            local best, at
            for i, col in ipairs(list) do
                if col[5] and (not best or col[5] < best) then best, at = col[5], i end
            end
            if not at then break end
            sum = sum - list[at][2]
            table.remove(list, at)
        end
        local key = ""
        for _, col in ipairs(list) do key = key .. col[1] .. "," end
        if activeKey[view] ~= key then changed = true end
        activeKey[view], active[view] = key, list
    end
    return changed
end

-- item data: the name and the vendor price are not there until the game has loaded the item (it is asked for
-- in small portions and kept in an index, so that searching does not have to ask again); class and picture are
local function Meta(id)
    local m = meta[id]
    if not m then
        local icon, class, sub, equip
        if GetInstant then
            local _, _, _, eq, ic, cl, sc = GetInstant(id)
            icon, class, sub, equip = ic, cl, sc, eq
        end
        if not icon and C_Item and C_Item.GetItemIconByID then icon = C_Item.GetItemIconByID(id) end
        m = { icon = icon, class = class, sub = sub, equip = equip }
        meta[id] = m
    end
    return m
end

-- Names, rarity and vendor prices are kept in the saved variables ("sell|rarity|level|name", per game language), so that they are
-- not asked for again after every reload.
local function Cache()
    local db = ns.db
    db.itemCache = db.itemCache or {}
    if db.itemCache.lang ~= GetLocale() or db.itemCache.fmt ~= 3 then
        wipe(db.itemCache)
        db.itemCache.lang, db.itemCache.fmt = GetLocale(), 3
    end
    return db.itemCache
end

local function Fill(id)
    if idx[id] then return true end
    local cache = Cache()
    local hit = cache[id]
    if hit and hit:sub(1, 1) == "x" then
        -- an item the game did not know: left alone for two weeks, then tried again
        if time() / 86400 - (tonumber(hit:sub(2)) or 0) < 14 then failed[id] = true; return false end
        cache[id] = nil
        hit = nil
    end
    if hit then
        local sell, quality, level, name = hit:match("^(%d+)|(%d+)|(%d+)|(.*)$")
        if name then
            idx[id] = { name = name, lower = name:lower(), sell = tonumber(sell), quality = tonumber(quality), level = tonumber(level) }
            return true
        end
    end
    local name, _, quality, _, level, _, _, _, _, _, sell = GetInfo(id)
    if name then
        quality, level = quality or 1, level or 0
        idx[id] = { name = name, lower = name:lower(), sell = sell or 0, quality = quality, level = level }
        cache[id] = (sell or 0) .. "|" .. quality .. "|" .. level .. "|" .. name
        return true
    end
end

local function Fail(id)
    failed[id] = true
    Cache()[id] = "x" .. math.floor(time() / 86400)
end

local function Ask(id)
    if failed[id] or Fill(id) then return end
    local now = GetTime()
    if asked[id] and now - asked[id] < 15 then return end
    tries[id] = (tries[id] or 0) + 1
    if tries[id] > 3 then Fail(id); return end
    asked[id] = now
    if C_Item and C_Item.RequestLoadItemDataByID then pcall(C_Item.RequestLoadItemDataByID, id) end
end

-- Lists of items (favourites and as many others as you like): { id, name, items = { [itemId] = true } }
local function Lists()
    local db = ns.db
    if not db.ahLists then
        db.ahLists = { { id = 1, name = L["Favourites"], items = {} } }
        for id in pairs(db.ahFavs or {}) do db.ahLists[1].items[id] = true end -- the single list of the first version
        db.ahFavs = nil
        db.ahNextList = 2
    end
    return db.ahLists
end
local function ListById(id)
    for _, l in ipairs(Lists()) do if l.id == id then return l end end
end
local function InAnyList(id)
    for _, l in ipairs(Lists()) do if l.items[id] then return true end end
end
local function ListSize(l)
    local n = 0
    for _ in pairs(l.items) do n = n + 1 end
    return n
end

-- the recipe data (Data/Recipes.lua): the items that are materials of a profession, and those it makes
local sets
local function Sets()
    if sets then return sets end
    sets = { mat = {}, make = {}, names = {} }
    for prof, list in pairs(ns.RecipeDB and ns.RecipeDB.professions or {}) do
        local mat, make = {}, {}
        for _, r in ipairs(list) do
            if r[2] > 0 then make[r[2]] = true end
            local re = r[6]
            for i = 1, #re, 2 do mat[re[i]] = true end
        end
        sets.mat[prof], sets.make[prof] = mat, make
        sets.names[#sets.names + 1] = prof
    end
    table.sort(sets.names)
    return sets
end

-- a small dialog that asks for a name
StaticPopupDialogs["FOREVERCOMPANION_NAME"] = {
    text = "%s", button1 = ACCEPT, button2 = CANCEL, hasEditBox = 1, maxLetters = 24, timeout = 0, whileDead = 1, hideOnEscape = 1,
    OnShow = function(self)
        local eb = self.editBox or self.EditBox
        eb:SetText(T.popupText or "")
        eb:HighlightText()
    end,
    OnAccept = function(self)
        local eb = self.editBox or self.EditBox
        if T.popupDone then T.popupDone(eb:GetText()) end
    end,
    EditBoxOnEnterPressed = function(self)
        if T.popupDone then T.popupDone(self:GetText()) end
        self:GetParent():Hide()
    end,
    EditBoxOnEscapePressed = function(self) self:GetParent():Hide() end,
}
StaticPopupDialogs["FOREVERCOMPANION_CONFIRM"] = {
    text = "%s", button1 = YES, button2 = NO, timeout = 0, whileDead = 1, hideOnEscape = 1,
    OnAccept = function() if T.popupDone then T.popupDone() end end,
}
local function AskName(title, text, done)
    T.popupText, T.popupDone = text, done
    StaticPopup_Show("FOREVERCOMPANION_NAME", title)
end
local function Confirm(title, done)
    T.popupDone = done
    StaticPopup_Show("FOREVERCOMPANION_CONFIRM", title)
end

-- a text in the colour of a rarity, and in the colour of a character's class
local function QualityColour(q, text)
    local col = ITEM_QUALITY_COLORS and ITEM_QUALITY_COLORS[q or 1]
    if not col then return text end
    return ("|cff%02x%02x%02x%s|r"):format(col.r * 255 + 0.5, col.g * 255 + 0.5, col.b * 255 + 0.5, text)
end
local function ClassColour(rec, text)
    local col = RAID_CLASS_COLORS and rec.class and RAID_CLASS_COLORS[rec.class]
    if not col then return text end
    return ("|cff%02x%02x%02x%s|r"):format(col.r * 255 + 0.5, col.g * 255 + 0.5, col.b * 255 + 0.5, text)
end

-- the name in the colour of its rarity
local function Coloured(entry, fallback)
    if not entry then return fallback end
    local c = ITEM_QUALITY_COLORS and ITEM_QUALITY_COLORS[entry.quality or 1]
    if not c then return entry.name end
    return ("|cff%02x%02x%02x%s|r"):format(c.r * 255 + 0.5, c.g * 255 + 0.5, c.b * 255 + 0.5, entry.name)
end

-- the list ---------------------------------------------------------------------------------------------
-- the rarities that are shown (grey items are hidden by default); kept in the settings
local function SetDefaultRarity(t)
    for q = 0, 7 do t[q] = (q ~= 0) end
    return t
end
local function RarityIsDefault()
    for q = 0, 7 do
        if (state.rarity[q] and true or false) ~= (q ~= 0) then return false end
    end
    return true
end

-- the filters of a view when it has none yet: your items start with this character, your recipes with all of them
-- The places of the items are shown (a picture beside the star) when the list is not only what this character carries in its bags.
local function LocActive()
    if state.view ~= "profit" or not (ns.Acc and ns.Acc.MyKey) then return false end
    local me, n = ns.Acc.MyKey(), 0
    for _ in pairs(state.chars or {}) do n = n + 1 end
    local onlyMe = n == 1 and state.chars and state.chars[me]
    local bagsOnly = state.places and state.places.bags and not state.places.bank
    return not (onlyMe and bagsOnly)
end
local LOCS = {
    { "locBag", "Bags", { 0.25, 0.78, 0.48, 0.17 } },
    { "locBank", "Bank", { 0.30, 0.55, 0.95, 0.16 } },
    { "locOther", "Other characters", { 0.68, 0.46, 0.92, 0.16 } },
}
function T.LocW() return 0 end

local function ViewDefaults(v)
    local d = { sort = VIEWS[v].sort, asc = VIEWS[v].asc, query = "", deals = false, rarity = SetDefaultRarity({}) }
    if v == "profit" or v == "recipes" then
        d.chars = {}
        if v == "recipes" then
            for _, rec in ipairs(ns.Acc.Chars()) do d.chars[rec.key] = true end
        else
            d.chars[ns.Acc.MyKey()] = true
        end
        d.places = { bags = true, bank = v ~= "profit" } -- (what is to be sold is in the bags: the bank is for the other views)
    end
    return d
end

-- where an item stands at the auction house: "offer" (it has a price at the last scan), "out" (seen before, not
-- on offer now) or "never" (no price and no history)
local function Offer(id)
    if ns.AH.Price(id) then return "offer" end
    return histSet[id] and "out" or "never"
end

local function Pool()
    pool = {}
    wipe(poolExtra)
    wipe(histSet)
    for _, id in ipairs(ns.AH.HistIds()) do histSet[id] = true end
    local view = state.view
    if view == "profit" then
        local own = ns.Acc and ns.Acc.Holdings and ns.Acc.Holdings(state.chars, state.places.bags, state.places.bank, true) or {}
        for id, n in pairs(own) do pool[id] = n end
    elseif view == "recipes" then
        -- the recipes that the chosen characters know (by recipe, not by item)
        for _, e in ipairs(ns.Acc.Recipes()) do
            local known = {}
            for _, rec in ipairs(e.knownBy) do if state.chars[rec.key] then known[#known + 1] = rec end end
            if #known > 0 then
                pool[e.key] = { e = e, known = known }
                if e.id then poolExtra[e.id] = true end
                for _, rg in ipairs(e.reagents) do if rg.id then poolExtra[rg.id] = true end end
            end
        end
    elseif view == "trend" then
        for _, id in ipairs(ns.AH.HistIds()) do pool[id] = true end
    else -- every item of the last scan, and what has a history
        for id in pairs(ns.AH.Prices()) do pool[id] = true end
        for _, id in ipairs(ns.AH.HistIds()) do pool[id] = true end
        local list = state.list and ListById(state.list)
        if list then for id in pairs(list.items) do pool[id] = true end end -- even if it is not on the auction house
        if state.prof then
            for id in pairs(Sets()[state.prof.mode][state.prof.name] or {}) do pool[id] = true end
        end
    end
    if state.prof and view ~= "recipes" then
        local set = Sets()[state.prof.mode][state.prof.name] or {}
        for id in pairs(pool) do if not set[id] then pool[id] = nil end end
    end
end

-- What the scan knows about an item, worked out once per scan (not on every keystroke or filter change)
local function Stats(id)
    local stamp = ns.AH.Time()
    if statStamp ~= stamp then wipe(statCache); statStamp = stamp end
    local st = statCache[id]
    if not st then
        local price, qty, avg = ns.AH.Trend(id, DAYS)
        st = { price = price, avg = avg, demand = ns.AH.Demand(id, DAYS), supply = ns.AH.Supply(id) or 0, last = 0 }
        if qty then
            for i = #qty, 1, -1 do
                if qty[i] > 0 then st.last = qty[i]; break end
            end
        end
        statCache[id] = st
    end
    return st
end

-- A row of the list. They are kept per view and filled again each time: making some thousand new tables for every
-- change of a filter or a view would leave so much garbage that the game stalls while it is collected.
local function RecordOf(key)
    local cache = recCache[state.view]
    local d = cache[key]
    if not d then d = {}; cache[key] = d end
    return d
end

-- what an item costs when it is a material: the auction price, else what a vendor pays
local function ReagentPrice(id)
    local ah = ns.AH.Price(id)
    if ah then return ah end
    local e = idx[id]
    if e and e.sell and e.sell > 0 then return e.sell end
    return ns.Value.Vendor(id) or 0
end

local function Tie(a, b)
    local x, y = a.id or a.key, b.id or b.key
    if type(x) ~= type(y) then return tostring(x) < tostring(y) end
    return x < y
end

-- One recipe: filtered like an item (by what it makes), then worked out: materials, value, profit, how many can be
-- made now, who knows it.
local function ConsiderRecipe(key, entry, out)
    local e, known = entry.e, entry.known
    local id = e.id
    local m = id and Meta(id) or nil
    if state.class then
        if not (m and m.class) then return end
        if state.class == 15 then
            for _, cl in ipairs(CLASSES) do if cl ~= 15 and cl == m.class then return end end
        elseif m.class ~= state.class then
            return
        end
    end
    if state.sub and not (m and m.sub == state.sub) then return end
    if state.slot and m and m.class == 4 then -- (only armour has a slot to be worn at: other things pass)
        local hit = false
        for _, loc in ipairs(SLOT_BY_KEY[state.slot] or {}) do if m.equip == loc then hit = true end end
        if not hit then return end
    end
    if state.stock and not (id and Offer(id) == state.stock) then return end
    local ix = id and idx[id] or nil
    if ix and not state.rarity[ix.quality or 1] then return end
    if state.level and not (ix and ix.level >= state.level[1] and ix.level <= state.level[2]) then return end
    if state.list then
        local list = ListById(state.list)
        if not (id and list and list.items[id]) then return end
    end
    if state.prof and e.prof ~= L[state.prof.name] and e.prof ~= state.prof.name then return end
    local lname = e.name:lower()
    if state.query ~= "" and not lname:find(state.query, 1, true) then return end

    local cost, can = 0, nil
    for _, rg in ipairs(e.reagents) do
        local n = rg.count or 1
        cost = cost + ReagentPrice(rg.id) * n
        local have = math.floor((collectHave[rg.id] or 0) / n)
        can = can and math.min(can, have) or have
    end
    -- what the product is worth: what it sells for (the auction price after the fee: the point is materials against sale), or,
    -- when that is chosen, what disenchanting it would bring
    local value
    if state.vsDE then
        value = id and ns.DisenchantValue and ns.DisenchantValue(id) or nil
    else
        local ah = id and ns.AH.Price(id) or nil
        value = ah and math.floor(ah * (1 - FEE)) or nil
    end
    local profit = (value and value > 0 and #e.reagents > 0) and (value - cost) or nil
    if state.deals and not (profit and profit > 0) then return end
    local names = {}
    for _, rec in ipairs(known) do names[#names + 1] = ClassColour(rec, rec.name or "?") end
    local d = RecordOf(key)
    d.key, d.id, d.name, d.lname, d.link, d.quality = key, id, e.name, lname, e.link, ix and ix.quality
    d.icon = (m and m.icon) or ns.Acc.ProfIcon(e.prof)
    d.cost, d.value, d.profit, d.can = (#e.reagents > 0) and cost or nil, value, profit, can
    d.demand = (id and ns.AH.Demand and ns.AH.Demand(id, 7)) or 0
    d.reagents, d.prof = e.reagents, e.prof -- (for the craft panel)
    d.known, d.knownSort = table.concat(names, ", "), #known
    out[#out + 1] = d
end

-- what the craft panel asks of the tab: what the chosen characters have of an item, and the price of a material
if ns.AuctionCraft then
    ns.AuctionCraft.Hooks = {
        have = function(id) return collectHave[id] or 0 end,
        price = function(id) return ReagentPrice(id) end,
    }
end

-- One item: counted for the category menu, then filtered and, if it passes, added to `out`.
local function Consider(id, own, out, cnt, ccount)
    if state.view == "recipes" then return ConsiderRecipe(id, own, out) end
    if plannedSet and not plannedSet[id] then return end -- ("Planned" is on: only what is meant for the auction house)
    local m = Meta(id)
    local ok = true
    if m.class then
        local known = false
        for _, cl in ipairs(CLASSES) do if cl ~= 15 and cl == m.class then known = true end end
        local group = known and m.class or 15
        ccount[group] = (ccount[group] or 0) + 1
        if group ~= 15 and m.sub then
            cnt[group] = cnt[group] or {}
            cnt[group][m.sub] = (cnt[group][m.sub] or 0) + 1
        end
    end
    if state.class then
        if state.class == 15 then
            local known = false
            for _, c in ipairs(CLASSES) do if c ~= 15 and c == m.class then known = true end end
            ok = not known
        else
            ok = m.class == state.class
        end
    end
    if ok and state.sub and m.sub ~= state.sub then ok = false end
    if ok and state.slot and m.class == 4 then -- (armour only)
        ok = false
        for _, loc in ipairs(SLOT_BY_KEY[state.slot] or {}) do if m.equip == loc then ok = true end end
    end
    if ok and state.stock and Offer(id) ~= state.stock then ok = false end
    local e = idx[id]
    if ok and e and not state.rarity[e.quality or 1] then ok = false end
    if ok and state.level then
        -- the level an item needs (gear, and whatever else has such a requirement); unknown until the item is loaded
        ok = e ~= nil and e.level >= state.level[1] and e.level <= state.level[2]
    end
    if ok and state.list then
        local list = ListById(state.list)
        if not (list and list.items[id]) then ok = false end
    end
    if ok and state.query ~= "" and not (e and e.lower:find(state.query, 1, true)) then ok = false end
    if not ok then return end

    local name = e and e.name or ("item:" .. id)
    local d = RecordOf(id)
    d.id, d.name, d.lname, d.icon = id, name, (e and e.lower) or name:lower(), m.icon
    d.gain, d.total = nil, nil
    d.locBag, d.locBank, d.locOther = nil, nil, nil
    if collectLoc then d.locBag, d.locBank, d.locOther = collectLoc.bag[id], collectLoc.bank[id], collectLoc.other[id] end
    if state.view == "trend" then
        local st = Stats(id)
        if not st.price then return end
        local now = ns.AH.Price(id)
        if not now then
            for i = #st.price, 1, -1 do
                if st.price[i] > 0 then now = st.price[i]; break end
            end
        end
        d.price, d.avg, d.supply, d.series, d.demand = now or 0, st.avg or 0, st.last, st.price, st.demand
        d.diff = (now and st.avg and st.avg > 0) and ((now - st.avg) / st.avg * 100) or 0
        if state.deals and d.diff > -10 then return end
    elseif state.view == "all" then
        local st = Stats(id)
        local ah = ns.AH.Price(id)
        d.price, d.avg, d.supply, d.demand = ah or 0, st.avg, st.supply, st.demand
        -- a market overview: the vendor plays no part; "deals" are what costs at least 10 % less than its average
        if state.deals and not (ah and st.avg and st.avg > 0 and (ah - st.avg) / st.avg * 100 <= -10) then return end
    else
        local ah = ns.AH.Price(id)
        -- what the auction price is measured against: what a vendor pays, or the estimated disenchant value (then an item
        -- that cannot be disenchanted has nothing to compare with)
        local base = e and e.sell or 0
        if state.vsDE then base = ns.DisenchantValue and ns.DisenchantValue(id) or nil end
        d.count, d.price, d.vendor = own, ah or 0, base or 0
        if ah and base then
            d.gain = math.floor(ah * (1 - FEE)) - base
            d.total = d.gain * own
        end
        if state.deals and not (d.gain and d.gain > 0) then return end
    end
    out[#out + 1] = d
end

-- The list is worked out in small slices (a few milliseconds per frame, by the driver below), so that opening the tab or
-- changing a filter never stalls the game; the old list stays on screen until the new one is ready. A new request
-- replaces a job that is still running.
-- Everything that decides what a view's list contains (its filters and sort, and for the views of what you own, whose things).
local function Signature()
    local p = { state.view, tostring(state.sort), tostring(state.asc), state.query or "", tostring(state.class), tostring(state.sub),
        tostring(state.slot), state.level and (state.level[1] .. "-" .. state.level[2]) or "", tostring(state.stock),
        tostring(state.list), state.prof and (state.prof.mode .. ":" .. state.prof.name) or "", tostring(state.deals), tostring(state.vsDE), tostring(state.view == "profit" and PlannedOn()) }
    for q = 0, 7 do p[#p + 1] = state.rarity[q] and "1" or "0" end
    if state.chars then
        local keys = {}
        for k in pairs(state.chars) do keys[#keys + 1] = k end
        table.sort(keys)
        p[#p + 1] = table.concat(keys, ",")
    end
    if state.places then p[#p + 1] = (state.places.bags and "b" or "-") .. (state.places.bank and "k" or "-") end
    return table.concat(p, "|")
end

-- The list that a view had is good for use again when its filters are the same, the scan is the same, all item names were
-- known when it was made, and it is not old (what you carry changes). Then switching to it needs no new list.
local function ResultsValid(view)
    local r = results[view]
    return r and r.view == view and r.sig == Signature() and r.stamp == ns.AH.Time() and r.full and GetTime() - r.at < 30 or false
end

-- "Planned": in the sell view only what the bags manager has set aside for the auction house (rule "auction", or proposed by its list).
-- Kept in the settings; it only counts while your own character is chosen (the manager looks at the bags of the character you play).
local plannedSet
local function PlannedOn()
    if not (ns.db and ns.db.settings.ahPlanned ~= false and ns.Manager and ns.Manager.AuctionSet) then return false end
    return state.chars and state.chars[ns.Acc.MyKey()] and true or false
end
T.PlannedOn = PlannedOn

local function StartCollect()
    if T.IsPage(state.view) then job = nil; return end -- (a page has no list)
    -- the view of everything is the same until the next scan: its pool and id list are kept
    local ckey = (state.view == "all" and not state.list and not state.prof) and ("all:" .. tostring(ns.AH.Time())) or nil
    local ids
    if ckey and poolCache.key == ckey then
        pool, ids = poolCache.pool, poolCache.ids
    else
        Pool()
        ids = {}
        local n = 0
        for id in pairs(pool) do n = n + 1; ids[n] = id end
        if ckey then poolCache = { key = ckey, pool = pool, ids = ids } end
    end
    poolVersion = poolVersion + 1
    collectStamp = ns.AH.Time()
    collectHave = (state.view == "recipes") and ns.Acc.Holdings(state.chars, state.places.bags, state.places.bank, false) or {}
    plannedSet = (state.view == "profit" and PlannedOn()) and ns.Manager.AuctionSet() or nil
    collectLoc = nil
    if LocActive() then
        local me, others = ns.Acc.MyKey(), {}
        for key in pairs(state.chars or {}) do if key ~= me then others[key] = true end end
        local mine = state.chars and state.chars[me] and { [me] = true } or {}
        collectLoc = {
            bag = state.places.bags and ns.Acc.Holdings(mine, true, false, true) or {},
            bank = state.places.bank and ns.Acc.Holdings(mine, false, true, true) or {},
            other = ns.Acc.Holdings(others, state.places.bags, state.places.bank, true),
        }
    end
    job = { ids = ids, n = #ids, i = 1, out = {}, cnt = {}, ccount = {}, stage = "filter", view = state.view, sig = Signature() }
    if driver then driver:Show() end
end

-- sorting, in slices too (a bottom-up merge sort: runs of 1, 2, 4 ... are merged, a few at a time per frame)
local function BeginSort()
    local key, asc = state.sort, state.asc
    if key == "name" then key = "lname" elseif key == "known" then key = "knownSort" end
    job.stage = "sort"
    job.src, job.dst, job.width, job.pos, job.m = job.out, {}, 1, 1, #job.out
    job.less = function(a, b) -- a before b?
        local x, y = a[key], b[key]
        if x == nil and y == nil then return Tie(a, b) end
        if x == nil then return false end -- nothing to compare goes last
        if y == nil then return true end
        if x == y then return Tie(a, b) end
        if asc then return x < y end
        return x > y
    end
end

-- returns true when the list is sorted (it is in job.src then)
local function SortSlice(t0)
    local src, dst, n, w, less = job.src, job.dst, job.m, job.width, job.less
    if n <= 1 or w >= n then return true end
    local pos = job.pos
    while pos <= n do
        local mid = math.min(pos + w, n + 1)       -- where the second run begins
        local hi = math.min(pos + 2 * w, n + 1)    -- where it ends
        local i, j, k = pos, mid, pos
        while i < mid and j < hi do
            if less(src[j], src[i]) then dst[k] = src[j]; j = j + 1 else dst[k] = src[i]; i = i + 1 end
            k = k + 1
        end
        while i < mid do dst[k] = src[i]; i = i + 1; k = k + 1 end
        while j < hi do dst[k] = src[j]; j = j + 1; k = k + 1 end
        pos = hi
        if debugprofilestop() - t0 > SLICE_MS then break end
    end
    job.pos = pos
    if pos > n then -- a pass is done: the runs are twice as long now
        job.src, job.dst = dst, src
        job.width = w * 2
        job.pos = 1
        if job.width >= n then return true end
    end
    return false
end

local function FinishCollect()
    local out, view = job.src, job.view
    local full = true -- were all names known? (a list made before they were is made again when they are)
    for id in pairs(pool) do
        if type(id) == "number" and not (idx[id] or failed[id]) then full = false; break end
    end
    if full and view == "recipes" then -- (the products of the recipes are in the extra pool: their names and rarity matter too)
        for id in pairs(poolExtra) do
            if type(id) == "number" and not (idx[id] or failed[id]) then full = false; break end
        end
    end
    results[view] = { view = view, data = out, counts = job.cnt, classCount = job.ccount, sig = job.sig, stamp = collectStamp,
        at = GetTime(), full = full }
    if view == state.view then -- (and not another one that was chosen meanwhile)
        data, counts, classCount = out, job.cnt, job.ccount
    end
    job = nil
    if panel and panel:IsShown() then T.Redraw() end
end

local function Pct(v)
    local text = ("%+d %%"):format(math.floor(math.abs(v) + 0.5) * (v < 0 and -1 or 1))
    local col = v <= -10 and "|cff66dbb0" or (v >= 10 and "|cffffa63d" or "|cffb8a88a")
    return col .. text .. "|r"
end

-- "12/d": a rough number of sales per day
local function Demand(v)
    if v == nil then return "|cff8a806e–|r" end
    if v < 0.5 then return "|cff8a806e<1/d|r" end
    return (v < 10 and "%.1f/d" or "%d/d"):format(v)
end

local function Gain(v)
    if v == nil then return "|cff8a806e–|r" end
    if v > 0 then return ns.Value.Format(v, "|cff66dbb0") end
    if v < 0 then return "-" .. ns.Value.Format(-v, "|cffff7a6b") end
    return "|cffb8a88a0|r"
end

local function Star(btn, on)
    btn.tex:SetDesaturated(not on)
    btn.tex:SetAlpha(on and 1 or 0.35)
end

local function ApplyLayout(r)
    if r.view == state.view then return end
    r.view = state.view
    local cols = Cols(state.view)
    for _, fs in pairs(r.cell) do fs:Hide() end
    for ci, col in ipairs(cols) do
        local fs = r.cell[col[1]]
        if fs then
            fs:ClearAllPoints()
            fs:SetPoint("RIGHT", r, "RIGHT", -ColRight(state.view, ci), 0)
            fs:SetWidth(col[2] - 8)
            fs:Show()
        end
    end
    r.name:ClearAllPoints()
    r.name:SetPoint("LEFT", r.icon, "RIGHT", 6, 0)
    r.name:SetPoint("RIGHT", r, "RIGHT", -(ColsWidth(state.view) + 8), 0)
    for k = 1, DAYS do r.bars[k]:SetShown(state.view == "trend" and HasCol("trend", "trend")) end
end

-- The comparison with the worn equipment (the extra tooltips beside the item) is switched off in this tab unless Shift is
-- held: hovering a long list would otherwise cover it with them.
local function HideCompare()
    for _, name in ipairs({ "ShoppingTooltip1", "ShoppingTooltip2" }) do
        local t = _G[name]
        if t and t.Hide then t:Hide() end
    end
    pcall(function() if TooltipComparisonManager and TooltipComparisonManager.Clear then TooltipComparisonManager:Clear() end end)
end
if GameTooltip_ShowCompareItem then
    hooksecurefunc("GameTooltip_ShowCompareItem", function()
        local owner = GameTooltip:GetOwner()
        if owner and owner.codexRow and not IsShiftKeyDown() then HideCompare() end
    end)
end

-- The context menu of an item (right-click on a row): recipes, link, shopping list, lists. The overview page uses it too.
local function ItemMenu(owner, id)
    local _, link = GetInfo(id)
    T.dd:Open(owner, function()
        local rows = {
            { kind = "header", label = Coloured(idx[id], "item:" .. id) },
            { kind = "action", label = L["Recipes and professions…"], close = true,
                onClick = function() if ns.ItemInfo then ns.ItemInfo.Show(id) end end },
            { kind = "action", label = L["Link in chat"], close = true,
                onClick = function() if link and ChatEdit_InsertLink then ChatEdit_InsertLink(link) end end },
            { kind = "action", label = L["Add to shopping list"], close = true,
                onClick = function() if ns.AuctionShop then ns.AuctionShop.Add(id, 1) end end },
            { kind = "separator" },
            { kind = "header", label = L["Lists"] },
        }
        for _, l in ipairs(Lists()) do
            rows[#rows + 1] = { kind = "check", state = l.items[id] and "all" or "none", label = l.name,
                onClick = function() l.items[id] = (not l.items[id]) or nil; T.Draw() end }
        end
        return rows
    end, true) -- (at the mouse)
end
ns.AuctionItemMenu = function(owner, id) if T.dd and id then ItemMenu(owner, id) end end

local function NewRow(i)
    local r = CreateFrame("Button", nil, content)
    r:SetHeight(ROW)
    r.stripe = r:CreateTexture(nil, "BACKGROUND")
    r.stripe:SetAllPoints()
    r.hl = r:CreateTexture(nil, "BACKGROUND", nil, 1)
    r.hl:SetAllPoints()
    r.hl:SetColorTexture(1, 0.85, 0.4, 0.10)
    r.hl:Hide()
    r.fav = CreateFrame("Button", nil, r)
    r.fav:SetSize(16, 16)
    r.fav:SetPoint("LEFT", 6, 0)
    r.fav.tex = r.fav:CreateTexture(nil, "ARTWORK")
    r.fav.tex:SetAllPoints()
    if not pcall(r.fav.tex.SetAtlas, r.fav.tex, "auctionhouse-icon-favorite") then
        r.fav.tex:SetColorTexture(C.gold[1], C.gold[2], C.gold[3], 1)
    end
    r.fav:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    r.fav:SetScript("OnClick", function(self, button)
        local id = self:GetParent().id
        if not id then return end
        W.Click()
        if button == "RightButton" then
            T.dd:Open(self, function()
                local rows = {}
                for _, l in ipairs(Lists()) do
                    rows[#rows + 1] = { kind = "check", state = l.items[id] and "all" or "none", label = l.name,
                        onClick = function() l.items[id] = (not l.items[id]) or nil; Star(self, InAnyList(id)); if state.list then StartCollect() end end }
                end
                rows[#rows + 1] = { kind = "separator" }
                rows[#rows + 1] = { kind = "action", label = L["New list…"], close = true,
                    onClick = function() AskName(L["Name of the new list:"], "", T.NewList(id)) end }
                return rows
            end)
            return
        end
        local list = (state.list and ListById(state.list)) or Lists()[1]
        list.items[id] = (not list.items[id]) or nil
        Star(self, InAnyList(id))
        if state.list then StartCollect() end
    end)
    r.fav:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText(L["Lists"], 1, 0.85, 0.4)
        local list = (state.list and ListById(state.list)) or Lists()[1]
        GameTooltip:AddLine((L["Click: add to or remove from \"%s\"."]):format(list.name), 0.85, 0.85, 0.85, true)
        GameTooltip:AddLine(L["Right-click: choose the lists."], 0.85, 0.85, 0.85, true)
        GameTooltip:Show()
        self:GetParent().hl:Show()
    end)
    r.fav:SetScript("OnLeave", function(self) GameTooltip:Hide(); self:GetParent().hl:Hide() end)
    r.icon = r:CreateTexture(nil, "ARTWORK")
    r.icon:SetSize(18, 18)
    r.icon:SetPoint("LEFT", 28, 0)
    r.name = r:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    r.name:SetJustifyH("LEFT")
    r.name:SetWordWrap(false)
    r.cell = {}
    for _, id in ipairs({ "price", "avg", "diff", "supply", "demand", "count", "vendor", "gain", "total",
        "profit", "cost", "value", "can", "known" }) do
        local fs = r:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        fs:SetJustifyH("RIGHT")
        fs:SetWordWrap(false)
        r.cell[id] = fs
    end
    r.bars = {}
    for k = 1, DAYS do
        local b = r:CreateTexture(nil, "ARTWORK")
        b:SetWidth(BAR_W)
        r.bars[k] = b
    end
    r.codexRow = true
    r:SetScript("OnEnter", function(self)
        self.hl:Show()
        if state.view == "recipes" and self.recipe then
            -- a recipe (of any profession): what it makes (the item, or the enchantment as the game words it) and, below, its materials
            local d = self.recipe
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip.fcDone = nil
            local shown = false
            if d.id then
                shown = pcall(GameTooltip.SetHyperlink, GameTooltip, d.link or ("item:" .. d.id))
                if shown and ns.TipItem then ns.TipItem(GameTooltip, d.id) end
            else
                local sid = d.link and tonumber(d.link:match("enchant:(%d+)"))
                if sid then shown = pcall(GameTooltip.SetSpellByID, GameTooltip, sid) end
            end
            if not shown then
                GameTooltip:ClearLines()
                GameTooltip:AddLine(d.name or "", 1, 0.85, 0.4)
                GameTooltip:AddLine(d.prof or "", 0.7, 0.7, 0.7)
            end
            if d.reagents and #d.reagents > 0 then
                GameTooltip:AddLine(" ")
                GameTooltip:AddLine(L["Materials"] .. ":", 1, 0.85, 0.4)
                for _, rg in ipairs(d.reagents) do
                    local need = rg.count or 1
                    local have = collectHave[rg.id] or 0
                    local name, q, icon = W.ItemData(rg.id)
                    local pic = icon and (("|T%s:14:14:0:0:64:64:5:59:5:59|t "):format(icon)) or ""
                    local ok = have >= need
                    GameTooltip:AddDoubleLine(pic .. QualityColour(q, name or ("item:" .. rg.id)), have .. " / " .. need,
                        1, 1, 1, ok and 0.4 or 0.92, ok and 0.86 or 0.35, ok and 0.66 or 0.30)
                end
            end
            GameTooltip:Show()
            HideCompare()
            return
        end
        if self.link or self.id then
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip.fcDone = nil -- a fresh tooltip (the flag is reset by the game's "cleared" event, which may not have come)
            GameTooltip:SetHyperlink(self.link or ("item:" .. self.id))
            -- our lines are asked for directly, so that they do not depend on the game's hook having fired for this tooltip
            if self.id and ns.TipItem then ns.TipItem(GameTooltip, self.id) end
            GameTooltip:Show()
            -- (the game may show the comparison a moment later, so look again next frame)
            if not IsShiftKeyDown() then
                HideCompare()
                C_Timer.After(0, function()
                    if GameTooltip:GetOwner() == self and not IsShiftKeyDown() then HideCompare() end
                end)
            end
        end
    end)
    r:SetScript("OnLeave", function(self) self.hl:Hide(); GameTooltip:Hide() end)
    -- right-click: a context menu for the item; shift + left click: its link into the chat
    r:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    r:SetScript("OnClick", function(self, button)
        local id = self.id
        if state.view == "recipes" and self.recipe and button == "LeftButton" and not IsShiftKeyDown() and T.craft then
            -- a click on a recipe: the materials for the crafts, what is there and what is missing, with a button to buy each
            W.Click()
            T.craft:Open(self.recipe, self)
            return
        end
        if not id then return end
        local _, link = GetInfo(id)
        if button == "RightButton" then
            W.Click()
            ItemMenu(self, id)
        elseif IsShiftKeyDown() then
            if link and ChatEdit_InsertLink then ChatEdit_InsertLink(link) end
        elseif state.view == "profit" and T.sell then
            -- a click on a row of "Sell" opens the sell panel in the middle (the cheapest listings, the price, the button)
            W.Click()
            T.sell:Open(id, self, scroll)
        elseif (state.view == "all" or state.view == "trend") and T.buy then
            -- a click on a row of "Market" or "Trends" opens the buy panel (the cheapest listings, the amount, the cost, the button)
            W.Click()
            T.buy:Open(id, self, scroll)
        end
    end)
    rows[i] = r
    return r
end

local function UpdateThumb()
    local total, shown = #data * ROW, scroll:GetHeight()
    if total <= shown or shown <= 0 then thumb:Hide(); return end
    local trackH = track:GetHeight()
    local th = math.max(24, trackH * shown / total)
    thumb:SetHeight(th)
    thumb:ClearAllPoints()
    thumb:SetPoint("TOP", track, "TOP", 0, -(scroll:GetVerticalScroll() / (total - shown)) * (trackH - th))
    thumb:Show()
end

function T.Draw()
    T.locOn = LocActive()
    local n = #data
    content:SetHeight(math.max(1, n * ROW))
    local maxScroll = math.max(0, n * ROW - scroll:GetHeight())
    if scroll:GetVerticalScroll() > maxScroll then scroll:SetVerticalScroll(maxScroll) end
    local first = math.floor(scroll:GetVerticalScroll() / ROW)
    local visible = math.ceil(scroll:GetHeight() / ROW) + 1
    for i = 1, visible do
        local r = rows[i] or NewRow(i)
        local at = first + i
        local d = data[at]
        if d then
            ApplyLayout(r)
            r:ClearAllPoints()
            r:SetPoint("TOPLEFT", content, "TOPLEFT", 0, -(at - 1) * ROW)
            r:SetPoint("TOPRIGHT", content, "TOPRIGHT", 0, -(at - 1) * ROW)
            r.id, r.link = d.id, d.link
            r.recipe = state.view == "recipes" and d or nil
            r.stripe:SetColorTexture(1, 1, 1, at % 2 == 0 and 0.035 or 0)
            r.fav:SetShown(d.id ~= nil)
            Star(r.fav, d.id and InAnyList(d.id))
            r.icon:SetTexture(d.icon or "Interface\\Icons\\INV_Misc_QuestionMark")
            -- the places of the item: the colour of the row
            r.locD = T.locOn and d or nil
            if T.locOn then
                for _, spec in ipairs(LOCS) do
                    local n = d[spec[1]]
                    if n and n > 0 then
                        local col = spec[3]
                        r.stripe:SetColorTexture(col[1], col[2], col[3], col[4])
                        break
                    end
                end
            end
            if d.id then Ask(d.id) end
            r.name:SetText(state.view == "recipes" and QualityColour(d.quality or (d.id and idx[d.id] and idx[d.id].quality), d.name) or Coloured(idx[d.id], d.name))
            if state.view == "trend" then
                r.cell.price:SetText(ns.Value.Format(d.price))
                r.cell.avg:SetText(ns.Value.Format(d.avg))
                r.cell.diff:SetText(Pct(d.diff))
                r.cell.supply:SetText(d.supply > 0 and tostring(d.supply) or "–")
                r.cell.demand:SetText(Demand(d.demand))
                local ti = 1 -- (the column of the bars: not the first one any more, the price is at the right)
                for i, col in ipairs(Cols("trend")) do if col[1] == "trend" then ti = i end end
                local x0 = ColRight("trend", ti) + 8
                local top = 0
                for _, v in ipairs(d.series) do if v > top then top = v end end
                for k = 1, DAYS do
                    local v, b = d.series[k] or 0, r.bars[k]
                    b:ClearAllPoints()
                    b:SetPoint("BOTTOMRIGHT", r, "BOTTOMRIGHT", -(x0 + (DAYS - k) * (BAR_W + BAR_GAP)), 4)
                    b:SetHeight((v > 0 and top > 0) and math.max(2, math.floor(v / top * BAR_H + 0.5)) or 1)
                    if v == 0 then b:SetColorTexture(0.32, 0.28, 0.22, 1)
                    elseif k == DAYS then b:SetColorTexture(0.40, 0.86, 0.69, 1)
                    else b:SetColorTexture(0.80, 0.67, 0.35, 1) end
                end
            elseif state.view == "recipes" then
                r.cell.profit:SetText(Gain(d.profit))
                r.cell.cost:SetText(d.cost and ns.Value.Format(d.cost) or "|cff8a806e–|r")
                r.cell.value:SetText((d.value and d.value > 0) and ns.Value.Format(d.value) or "|cff8a806e–|r")
                r.cell.can:SetText((d.can and d.can > 0) and tostring(d.can) or "|cff8a806e–|r")
                r.cell.demand:SetText(Demand(d.demand))
                r.cell.known:SetText(d.known)
            elseif state.view == "all" then
                r.cell.price:SetText(d.price > 0 and ns.Value.Format(d.price) or "|cff8a806e–|r")
                r.cell.avg:SetText((d.avg and d.avg > 0) and ns.Value.Format(d.avg) or "|cff8a806e–|r")
                r.cell.supply:SetText(d.supply > 0 and tostring(d.supply) or "–")
                r.cell.demand:SetText(Demand(d.demand))
            else
                r.cell.count:SetText(d.count)
                r.cell.price:SetText(d.price > 0 and ns.Value.Format(d.price) or "|cff8a806e–|r")
                local v = (state.vsDE or idx[d.id]) and d.vendor or nil
                r.cell.vendor:SetText(v and (v > 0 and ns.Value.Format(v) or "|cff8a806e–|r") or "|cff8a806e…|r")
                r.cell.gain:SetText(Gain(d.gain))
                r.cell.total:SetText(Gain(d.total))
            end
            r:Show()
        else
            r.id = nil
            r:Hide()
        end
    end
    for i = visible + 1, #rows do rows[i]:Hide() end
    empty:SetShown(n == 0 and not T.IsPage(state.view))
    empty:SetText(job and L["Loading…"] or state.view == "recipes" and L["No recipes to show: open a profession window with each of your characters to have its recipes read."]
        or state.view == "profit" and L["Nothing to compare: nothing tradable in your bags or bank matches, or the auction house has not been scanned yet."]
        or (state.view == "all" and L["Nothing matches. Scan the auction house to fill this list."])
        or L["No price history yet. Scan the auction house here, and again on other days: from the second day on the trends appear."])
    count:SetText(T.IsPage(state.view) and "" or (L["%d items"]):format(n))
    UpdateThumb()
end

function T.Redraw()
    for _, h in pairs(heads) do
        local mark = (state.sort == h.key and h:IsShown()) and (state.asc and "  ^" or "  v") or ""
        local title = h.title
        if state.vsDE and (h.hk == "profit:vendor" or h.hk == "recipes:value") then title = L["Disenchant"] end
        h.text:SetText(title .. mark)
    end
    T.Draw()
end

local function Refresh()
    if not (panel and panel:IsShown()) then return end
    if state.view == "dash" then
        if T.DashUpdate then T.DashUpdate() end
        return
    elseif state.view == "shop" then
        if T.ShopUpdate then T.ShopUpdate() end
        return
    elseif state.view == "own" then
        if T.OwnUpdate then T.OwnUpdate() end
        return
    end
    if dirty or collectStamp ~= ns.AH.Time() then dirty = false; StartCollect() end
    T.Redraw()
end

-- the list is prepared when the auction house opens, so that it is there when the tab is clicked
function T.Prewarm()
    if T.IsPage(state.view) then return end
    if dirty or collectStamp ~= ns.AH.Time() then dirty = false; StartCollect() end
end

-- Something changed: the list is made anew. When the user did it (a filter, a view, a sort) the table also dips a little and
-- comes back when the new list is there, so that the change is soft; changes that come by themselves (names that arrive, a
-- scan that ends, typing) do not make it blink.
local function Dirty()
    dirty = true
    if T.Transition and panel and panel:IsShown() then T.Transition(nil, true) end -- the table fades out, and in when the list is there
    Refresh()
end
local function DirtyQuiet() dirty = true; Refresh() end
-- what the characters carry changed: the views of what you own (sell, craft) are worked out again
function T.HoldingsChanged()
    if state.view == "profit" or state.view == "recipes" then DirtyQuiet() end
end
-- a price was looked at on the auction house and is another one than the scan's: the lists are worked out again
function T.PriceChanged()
    for k in pairs(results) do results[k] = nil end
    DirtyQuiet()
end

-- The index of names is filled in the background, a few items at a time (what is saved is taken at once, a limited
-- number per round; only the rest is asked for from the game).
local function IndexStep()
    if indexedVersion == poolVersion then return false end
    local todo, done, budget, work = 0, 0, 60, 0
    local function Visit(id)
        todo = todo + 1
        if idx[id] or failed[id] then
            done = done + 1
        elseif work < 500 then
            work = work + 1
            if Fill(id) then
                done = done + 1
            elseif budget > 0 then
                Ask(id)
                budget = budget - 1
            end
        end
    end
    for id in pairs(pool) do if type(id) == "number" then Visit(id) end end
    for id in pairs(poolExtra) do Visit(id) end
    if done < todo then
        indexNote:SetText((L["Reading item names… %d %%"]):format(math.floor(done / todo * 100)))
        return true
    end
    indexedVersion = poolVersion
    indexNote:SetText("")
    return false
end

-- the one that does the work: the list in slices, then the names; it rests when there is nothing to do
driver = CreateFrame("Frame")
driver:Hide()
driver:SetScript("OnUpdate", function(self, dt)
    if job then
        local t0 = debugprofilestop()
        if job.stage == "filter" then
            while job.i <= job.n do
                local id = job.ids[job.i]
                job.i = job.i + 1
                Consider(id, pool[id], job.out, job.cnt, job.ccount)
                if debugprofilestop() - t0 > SLICE_MS then break end
            end
            if job.i > job.n then BeginSort() end
        elseif SortSlice(t0) then
            FinishCollect()
        end
        return
    end
    self.acc = (self.acc or 0) + dt
    if self.acc < 0.3 then return end
    self.acc = 0
    if not (panel and indexNote) then self:Hide(); return end
    if IndexStep() then
        self.indexing = true
    else
        if self.indexing then
            self.indexing = nil
            DirtyQuiet() -- everything is known now: names for search and sorting, vendor prices, rarity
        end
        self:Hide()
    end
end)

-- the page ---------------------------------------------------------------------------------------------
-- The page (panel) lives in the auction house frame or in a window of the addon (when the auction house is closed). T.PlacePanel docks it
-- in a host: its parent, its places, and the frame levels of all it holds (the level of a frame does not follow its parent's).
local function ShiftLevels(frame, delta)
    frame:SetFrameLevel(math.max(0, frame:GetFrameLevel() + delta))
    for _, ch in ipairs({ frame:GetChildren() }) do ShiftLevels(ch, delta) end
end
function T.PlacePanel(host)
    local isAH = AuctionHouseFrame ~= nil and host == AuctionHouseFrame
    local delta = host:GetFrameLevel() + 6 - panel:GetFrameLevel()
    panel:SetParent(host)
    panel:ClearAllPoints()
    if isAH then
        panel:SetPoint("TOPLEFT", host, "TOPLEFT", 14, -58)
        panel:SetPoint("BOTTOMRIGHT", host, "BOTTOMRIGHT", -14, 30)
    else
        -- (in the Blizzard style the strip for the views is above the window's edge, in the other styles it is inside)
        local top = 0
        panel:SetPoint("TOPLEFT", host, "TOPLEFT", 12, top)
        panel:SetPoint("BOTTOMRIGHT", host, "BOTTOMRIGHT", -12, 32)
    end
    if delta ~= 0 then ShiftLevels(panel, delta) end
    -- the state line: beside the gold of the auction house, or at the left of the window
    local st = T.status
    if st then
        st:ClearAllPoints()
        local gold = isAH and (AuctionHouseFrame.MoneyFrameBorder or AuctionHouseFrame.MoneyFrameInset)
        if gold then
            st:SetPoint("LEFT", gold, "RIGHT", 14, 0)
        elseif isAH then
            st:SetPoint("LEFT", host, "BOTTOMLEFT", 260, 15)
        else
            st:SetPoint("LEFT", host, "BOTTOMLEFT", 16, 16)
        end
        if T.scanBtn then st:SetPoint("RIGHT", T.optionsBtn or T.scanBtn, "LEFT", -12, 0) end
    end
end

local function Build(host)
    ns.db.settings.ahViews = ns.db.settings.ahViews or {}
    viewData = ns.db.settings.ahViews
    for v in pairs(VIEWS) do
        local d = viewData[v] or ViewDefaults(v)
        viewData[v] = d
        d.rarity = d.rarity or SetDefaultRarity({})
        if v == "profit" or v == "recipes" then
            d.chars = d.chars or ViewDefaults(v).chars
            d.places = d.places or { bags = true, bank = true }
        end
        d.query = "" -- (the search text is not kept)
        if d.sort == nil then d.sort, d.asc = VIEWS[v].sort, VIEWS[v].asc end
    end
    panel = W.NewPlate(host, C.page)
    T.PlacePanel(host)
    panel:Hide()

    -- The column of filters grows out of a strip at the left edge and shrinks back into it: a frame that clips what lies
    -- outside it changes its width, and the column (of fixed width, without a frame of its own) is uncovered from the left.
    -- Unless it is pinned it shrinks when the mouse has left it for a moment (the table then has the room), and grows
    -- when the mouse touches the strip (the table makes room).
    local clip = CreateFrame("Frame", nil, panel)
    clip:SetPoint("TOPLEFT", panel, "TOPLEFT", 3, -K.SIDE_TOP)
    clip:SetPoint("BOTTOMLEFT", panel, "BOTTOMLEFT", 3, K.SIDE_BOTTOM)
    clip:SetWidth(K.HIDDEN)
    if clip.SetClipsChildren then clip:SetClipsChildren(true) end
    clip:SetFrameLevel(panel:GetFrameLevel() + 20)
    -- the dashboard (the first page): a frame over the whole area of the table and the column
    T.sell = ns.AuctionSell and ns.AuctionSell.Build(panel)
    T.buy = ns.AuctionBuy and ns.AuctionBuy.Build(panel)
    T.craft = ns.AuctionCraft and ns.AuctionCraft.Build(panel)
    ns.AuctionBuyPanel = T.buy
    if ns.AuctionSell then ns.AuctionSell.OnPrice = T.PriceChanged end
    ns.AuctionSellPanel = T.sell -- (for /fcdeposit)
    local dash = ns.AuctionDash.Build(panel)
    dash:SetPoint("TOPLEFT", panel, "TOPLEFT", 8, -8) -- (it has no first row of its own: no search, no filter)
    dash:SetPoint("BOTTOMRIGHT", panel, "BOTTOMRIGHT", -8, K.SIDE_BOTTOM)
    dash:SetFrameLevel(panel:GetFrameLevel() + 12)
    function T.DashUpdate() dash:Update() end
    local shop = ns.AuctionShop.Build(panel)
    shop:SetPoint("TOPLEFT", panel, "TOPLEFT", 8, -8)
    shop:SetPoint("BOTTOMRIGHT", panel, "BOTTOMRIGHT", -8, K.SIDE_BOTTOM)
    shop:SetFrameLevel(panel:GetFrameLevel() + 12)
    function T.ShopUpdate() shop:Update() end
    local ownPage = ns.AuctionOwn.Build(panel) -- (not "own": T.Layout has a variable of that name)
    ownPage:SetPoint("TOPLEFT", panel, "TOPLEFT", 8, -8)
    ownPage:SetPoint("BOTTOMRIGHT", panel, "BOTTOMRIGHT", -8, K.SIDE_BOTTOM)
    ownPage:SetFrameLevel(panel:GetFrameLevel() + 12)
    function T.OwnUpdate() ownPage:Update() end
    local side = CreateFrame("Frame", nil, clip)
    side:SetPoint("TOPLEFT", clip, "TOPLEFT", 0, 0)
    side:SetPoint("BOTTOMLEFT", clip, "BOTTOMLEFT", 0, 0)
    side:SetWidth(K.OPEN)
    local handle = CreateFrame("Button", nil, panel)
    handle:SetWidth(K.HANDLE_W)
    handle:SetPoint("TOPLEFT", panel, "TOPLEFT", 6, -K.SIDE_TOP)
    handle:SetPoint("BOTTOMLEFT", panel, "BOTTOMLEFT", 6, K.SIDE_BOTTOM)
    -- (the strip has no background of its own: only the arrow, so that nothing covers the frame behind it)
    handle.arrow = handle:CreateTexture(nil, "ARTWORK")
    handle.arrow:SetSize(14, 14)
    handle.arrow:SetPoint("CENTER")
    handle.arrow:SetTexture("Interface\\ChatFrame\\ChatFrameExpandArrow")
    handle:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText(L["Filters"], 1, 0.85, 0.4)
        GameTooltip:AddLine(L["Move the mouse here to open the filters."], 0.85, 0.85, 0.85, true)
        GameTooltip:Show()
    end)
    handle:SetScript("OnLeave", function() GameTooltip:Hide() end)
    -- sideX: the width of the column now; it grows from the strip and shrinks back into it, and the table's left edge follows
    -- it frame by frame (T.ListEdge): the two move as one, at one speed
    local sideX, sideTarget, sideAway = K.HIDDEN, K.HIDDEN, 0
    -- sizes that move are kept to whole screen pixels: text that sits at part of a pixel shimmers while its frame moves
    local function Snap(v)
        local _, ph = GetPhysicalScreenSize()
        local up = UIParent:GetHeight()
        local ratio = panel:GetEffectiveScale() / UIParent:GetEffectiveScale()
        local px = (ph and ph > 0 and up and up > 0 and ratio > 0) and (up / ph / ratio) or 1
        return math.floor(v / px + 0.5) * px
    end
    local function SetSideX(w)
        sideX = w
        clip:SetWidth(Snap(w))
        side:SetShown(w > K.HIDDEN + 6)
        handle:SetShown(ns.db.settings.ahPin ~= true and w <= K.HIDDEN + 1)
    end

    -- a button with a small picture in front of its text
    local function Pictured(text, picture, atlas, extra)
        local b = W.NewButton(panel, text, 60, 24)
        b.pic = b:CreateTexture(nil, "OVERLAY")
        b.pic:SetSize(14, 14)
        b.pic:SetPoint("LEFT", 7, 0)
        if atlas and pcall(b.pic.SetAtlas, b.pic, atlas) then
            -- the game's own picture
        else
            b.pic:SetTexture(picture)
            b.pic:SetTexCoord(0.07, 0.93, 0.07, 0.93)
        end
        b.text:ClearAllPoints()
        b.text:SetPoint("LEFT", 26, 0)
        b:SetWidth(26 + b.text:GetStringWidth() + 12 + (extra or 0))
        return b
    end

    local dd = W.NewDropdown(panel, { level = panel:GetFrameLevel() + 60, width = 300, strata = "FULLSCREEN_DIALOG" })

    -- first row: the two views on the left; on the right the scan (state and progress, then the button) and options
    local viewButtons, vx = {}, 58 -- (above the panel, beside the round icon of the window)
    for _, v in ipairs(VIEW_ORDER) do
        local b = Pictured(VIEWS[v].label, VIEWS[v].icon)
        b:SetPoint("BOTTOMLEFT", panel, "TOPLEFT", vx, 2)
        b:SetScript("OnClick", function()
            if state.view == v then return end
            -- the old table fades out; then, under the cover, the view changes (what it showed last is there at once, a new list is
            -- only made when that one is out of date), and the table fades in when it is ready
            T.Transition(function()
                state.view = v
                T.ApplyView()
                if not ResultsValid(v) then dirty = true; Refresh() end
            end, true)
        end)
        viewButtons[v] = b
        vx = vx + b:GetWidth() + 6
    end

    local options = W.NewMenuButton(panel, dd, L["Options"], W.ICON.settings)
    -- (the options sit in the footer, left of the scan button: placed below, when that exists)
    local sideBtn = W.NewButton(panel, L["Filters"], 84, 24)
    sideBtn:SetPoint("TOPRIGHT", panel, "TOPRIGHT", -8, -8)
    -- "Check prices": looks at the items of the list one by one at the auction house (the full scan can only be asked for now and then)
    local checkBtn = W.NewButton(panel, L["Check prices"], 120, 24)
    checkBtn:SetPoint("RIGHT", sideBtn, "LEFT", -6, 0)
    checkBtn:SetScript("OnClick", function()
        local ids = {}
        for _, d in ipairs(data) do
            if d.id and #ids < 40 then ids[#ids + 1] = d.id end
        end
        local ok, why = ns.AuctionSell.Check(ids)
        if not ok and why then print("|cffffd100ForeverCompanion:|r " .. why) end
    end)
    checkBtn:HookScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
        GameTooltip:SetText(L["Check prices"], 1, 0.85, 0.4)
        GameTooltip:AddLine(L["Asks the auction house for each of the first 40 items of the list, one after the other, and takes the cheapest price as its price. Nothing waits for the full scan."], 0.85, 0.85, 0.85, true)
        GameTooltip:Show()
    end)
    checkBtn:HookScript("OnLeave", function() GameTooltip:Hide() end)
    T.checkBtn = checkBtn
    -- "Planned": only what the bags manager meant for the auction house (a quick switch next to "Check prices")
    local plannedBtn = W.NewButton(panel, L["Planned"], 84, 24)
    plannedBtn:SetPoint("RIGHT", checkBtn, "LEFT", -6, 0)
    plannedBtn:SetScript("OnClick", function()
        if not (state.chars and state.chars[ns.Acc.MyKey()]) then return end
        ns.db.settings.ahPlanned = not (ns.db.settings.ahPlanned ~= false)
        T.SyncPlanned()
        Dirty()
    end)
    plannedBtn:HookScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
        GameTooltip:SetText(L["Planned"], 1, 0.85, 0.4)
        GameTooltip:AddLine(L["Only the items that the bags manager has set aside for the auction house: those with the rule \"auction\", and those that its list proposes for it."], 0.85, 0.85, 0.85, true)
        if not (state.chars and state.chars[ns.Acc.MyKey()]) then
            GameTooltip:AddLine(" ")
            GameTooltip:AddLine(L["Only with your own character chosen."], 0.93, 0.74, 0.30, true)
        end
        GameTooltip:Show()
    end)
    plannedBtn:HookScript("OnLeave", function() GameTooltip:Hide() end)
    T.plannedBtn = plannedBtn
    function T.SyncPlanned()
        local mine = state.chars and state.chars[ns.Acc.MyKey()] and true or false
        plannedBtn:SetSelected(PlannedOn())
        plannedBtn:SetAlpha(mine and 1 or 0.45)
    end
    sideBtn:SetScript("OnClick", function()
        T.Transition(function()
            ns.db.settings.ahPin = not (ns.db.settings.ahPin == true)
            T.Layout()
            dirty = true
            Refresh()
        end)
    end)
    sideBtn:HookScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
        GameTooltip:SetText(L["Filters"], 1, 0.85, 0.4)
        GameTooltip:AddLine(L["Pinned: the filters stay open. Otherwise they slide away when the mouse leaves them and the table uses the room; they come back when it touches the left edge."], 0.85, 0.85, 0.85, true)
        GameTooltip:Show()
    end)
    sideBtn:HookScript("OnLeave", function() GameTooltip:Hide() end)
    local function Check(on) return on and "all" or "none" end
    local function OptionRows()
        return {
            { kind = "header", label = L["Scanning"] },
            { kind = "check", state = Check(ns.AH.Enabled()), label = L["Scan when the auction house opens"],
                onClick = function() ns.db.settings.ownAuction = not ns.AH.Enabled(); ns.Value.Reset(); ns.Refresh() end },
            { kind = "header", label = L["Trends"] },
            { kind = "check", state = Check(ns.db.settings.ahTrackAll == true), label = L["Follow every item (larger save file)"],
                onClick = function() ns.db.settings.ahTrackAll = not ns.db.settings.ahTrackAll end },
        }
    end
    options:SetContent(L["Options"], W.ICON.settings, OptionRows)

    scanBtn = Pictured(L["Scan"], W.ICON.search)
    -- (the footer: in the strip of the window under the panel, to the right of the gold)
    -- (placed by the panel's edge: the strip under it is 30 high; the button is 20 high, 8 above the lower edge of the window, and flush right)
    scanBtn:SetHeight(20)
    scanBtn:SetPoint("BOTTOMRIGHT", panel, "BOTTOMRIGHT", 2, -22)
    options:SetHeight(20)
    options:ClearAllPoints()
    options:SetPoint("RIGHT", scanBtn, "LEFT", -6, 0)
    T.optionsBtn = options
    scanBtn:SetScript("OnClick", function()
        local ok, why = ns.AH.Scan()
        if not ok and why then print("|cffffd100ForeverCompanion:|r " .. why) end
    end)

    -- The progress of a scan is shown in the scan button itself: a stripe sweeps while the server is asked, then the
    -- button fills while the list is read. Beside it: the state of the data (last scan, when the next one is possible).
    status = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    T.status, T.scanBtn = status, scanBtn
    status:SetJustifyH("LEFT")
    status:SetWordWrap(false)
    T.PlacePanel(host) -- (the place of the state line)
    status:SetTextColor(unpack(C.muted))

    -- the column of filters: search first, then the menus (they are placed by T.Layout)
    local search = CreateFrame("EditBox", nil, panel, W.TEMPLATE)
    search:SetSize(260, 24)
    search:SetPoint("TOPLEFT", 8, -8)
    search:SetBackdrop(W.PLATE_BACKDROP)
    search:SetBackdropColor(unpack(C.inset))
    search:SetBackdropBorderColor(unpack(C.goldDim))
    search:SetFontObject("GameFontHighlightSmall")
    search:SetAutoFocus(false)
    search:SetMaxLetters(40)
    search:SetTextInsets(26, 8, 0, 0)
    local mag = search:CreateTexture(nil, "OVERLAY")
    mag:SetSize(14, 14)
    mag:SetPoint("LEFT", 7, 0)
    mag:SetTexture(W.ICON.search)
    mag:SetTexCoord(0.07, 0.93, 0.07, 0.93)
    local hint = search:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    hint:SetPoint("LEFT", 26, 0)
    hint:SetTextColor(unpack(C.muted))
    hint:SetText(L["Find an item…"])
    local syncing = false
    search:SetScript("OnTextChanged", function(self)
        if syncing then return end
        state.query = self:GetText():lower()
        hint:SetShown(self:GetText() == "")
        DirtyQuiet()
    end)
    function T.SyncSearch()
        syncing = true
        search:SetText(state.query or "")
        syncing = false
        hint:SetShown((state.query or "") == "")
    end
    search:SetScript("OnEscapePressed", function(self) self:SetText(""); self:ClearFocus() end)
    search:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)

    -- a star beside the search: only the favourites (the first list), in every view
    local favBtn = W.NewIconButton(panel, W.ICON.search, 24)
    favBtn:SetPoint("LEFT", search, "RIGHT", 6, 0)
    if not pcall(favBtn.icon.SetAtlas, favBtn.icon, "auctionhouse-icon-favorite") then
        favBtn.icon:SetTexture("Interface\Icons\Achievement_General")
    end
    favBtn:SetTip(L["Favourites"], L["Show only your favourites."])
    favBtn:SetScript("OnClick", function()
        local first = Lists()[1]
        local id = first and first.id or 1
        if state.list == id then state.list = nil else state.list = id end
        T.Filters()
        Dirty()
    end)
    T.favBtn = favBtn

    local category = W.NewMenuButton(panel, dd, L["Category"], W.ICON.loot)
    category:SetPoint("LEFT", search, "RIGHT", 8, 0)
    local function ClassName(cl)
        return (GetItemClassInfo and GetItemClassInfo(cl)) or CLASS_FALLBACK[cl] or tostring(cl)
    end
    local function SubName(cl, sub)
        return (GetSubName and GetSubName(cl, sub)) or tostring(sub)
    end
    local function Pick(cl, sub, slot)
        state.class, state.sub, state.slot = cl, sub, slot
        T.Filters()
        Dirty()
    end
    local function CategoryRows()
        local rows = { { kind = "radio", state = Check(state.class == nil), label = L["All categories"],
            onClick = function() Pick(nil) end } }
        for _, cl in ipairs(CLASSES) do
            local here = state.class == cl
            rows[#rows + 1] = { kind = "radio", state = Check(here and not state.sub and not state.slot), label = ClassName(cl),
                right = tostring(classCount[cl] or 0),
                onClick = function()
                    if here and not state.sub and not state.slot then Pick(nil) else Pick(cl) end -- (the chosen one again: off)
                end }
            if here and counts[cl] then
                local subs = {}
                for sub in pairs(counts[cl]) do subs[#subs + 1] = sub end
                table.sort(subs)
                for _, sub in ipairs(subs) do
                    rows[#rows + 1] = { kind = "radio", state = Check(state.sub == sub), label = SubName(cl, sub), indent = 14,
                        right = tostring(counts[cl][sub]), onClick = function() Pick(cl, state.sub ~= sub and sub or nil, state.slot) end }
                end
            end
        end
        return rows
    end
    -- the button's text: class > subclass
    local function CategoryLabel()
        if not state.class then return L["Category"] end
        local text = ClassName(state.class)
        if state.sub then text = text .. " › " .. SubName(state.class, state.sub) end
        return text
    end

    -- where armour is worn: a filter of its own under the category, there while armour is the category. It only holds for armour.
    T.slotBtn = W.NewMenuButton(panel, dd, L["Worn at"], "Interface\\Icons\\INV_Chest_Cloth_17")
    function T.SlotRows()
        local rows = { { kind = "radio", state = Check(state.slot == nil), label = L["All slots"],
            onClick = function() state.slot = nil; T.Filters(); Dirty() end } }
        for _, sl in ipairs(SLOTS) do
            rows[#rows + 1] = { kind = "radio", state = Check(state.slot == sl[1]), label = _G[sl[2][1]] or sl[1],
                onClick = function() state.slot = state.slot ~= sl[1] and sl[1] or nil; T.Filters(); Dirty() end }
        end
        return rows
    end
    function T.SlotLabel()
        local loc = state.slot and SLOT_BY_KEY[state.slot]
        return state.slot and (loc and _G[loc[1]] or state.slot) or L["Worn at"]
    end

    -- the rarity: which kinds are shown
    -- whose things count (your items, your recipes), and where they are
    local charsBtn = W.NewMenuButton(panel, dd, L["Characters"], W.ICON.account)
    local function CharRows()
        local rows = {}
        for _, rec in ipairs(ns.Acc.Chars()) do
            rows[#rows + 1] = { kind = "check", state = Check(state.chars[rec.key]), label = ClassColour(rec, rec.name or "?"),
                onClick = function() state.chars[rec.key] = (not state.chars[rec.key]) or nil; T.Filters(); Dirty() end }
        end
        rows[#rows + 1] = { kind = "separator" }
        rows[#rows + 1] = { kind = "action", label = L["All characters"],
            onClick = function()
                for _, rec in ipairs(ns.Acc.Chars()) do state.chars[rec.key] = true end
                T.Filters(); Dirty()
            end }
        rows[#rows + 1] = { kind = "action", label = L["Only this character"],
            onClick = function() wipe(state.chars); state.chars[ns.Acc.MyKey()] = true; T.Filters(); Dirty() end }
        return rows
    end
    local placeBtn = W.NewMenuButton(panel, dd, L["Bags & bank"], "Interface\\Icons\\INV_Misc_Bag_08")
    local function PlaceRows()
        return {
            { kind = "check", state = Check(state.places.bags), label = L["Bags"],
                onClick = function() state.places.bags = not state.places.bags; T.Filters(); Dirty() end },
            { kind = "check", state = Check(state.places.bank), label = L["Bank"],
                onClick = function() state.places.bank = not state.places.bank; T.Filters(); Dirty() end },
        }
    end

    local rarityBtn = W.NewMenuButton(panel, dd, L["Rarity"], "Interface\\Icons\\INV_Misc_Gem_Variety_02")
    local function RarityName(q)
        local col = ITEM_QUALITY_COLORS and ITEM_QUALITY_COLORS[q]
        local name = _G["ITEM_QUALITY" .. q .. "_DESC"] or tostring(q)
        if not col then return name end
        return ("|cff%02x%02x%02x%s|r"):format(col.r * 255 + 0.5, col.g * 255 + 0.5, col.b * 255 + 0.5, name)
    end
    local function RarityRows()
        local rows = {}
        for q = 0, 5 do
            rows[#rows + 1] = { kind = "check", state = Check(state.rarity[q]), label = RarityName(q),
                onClick = function() state.rarity[q] = not state.rarity[q] or nil; T.Filters(); Dirty() end }
        end
        rows[#rows + 1] = { kind = "separator" }
        rows[#rows + 1] = { kind = "action", label = L["Hide grey items (default)"],
            onClick = function() SetDefaultRarity(state.rarity); T.Filters(); Dirty() end }
        rows[#rows + 1] = { kind = "action", label = L["Show all rarities"],
            onClick = function() for q = 0, 7 do state.rarity[q] = true end; T.Filters(); Dirty() end }
        return rows
    end

    -- the level an item needs
    local levelBtn = W.NewMenuButton(panel, dd, L["Level"], W.ICON.rate)
    levelBtn:SetPoint("LEFT", category, "RIGHT", 6, 0)
    local function LevelRows()
        local me = UnitLevel("player") or 1
        local function Row(label, lo, hi)
            local on = (lo == nil and state.level == nil) or (state.level and state.level[1] == lo and state.level[2] == hi)
            return { kind = "radio", state = Check(on), label = label,
                onClick = function() state.level = lo and { lo, hi } or nil; T.Filters(); Dirty() end }
        end
        local rows = {
            Row(L["Any level"]),
            Row((L["Usable at level %d"]):format(me), 0, me),
            Row((L["Level %d–%d"]):format(math.max(1, me - 5), me + 5), math.max(1, me - 5), me + 5),
            { kind = "separator" },
        }
        for lo = 1, 61, 10 do rows[#rows + 1] = Row((L["Level %d–%d"]):format(lo, lo + 9), lo, lo + 9) end
        rows[#rows + 1] = { kind = "separator" }
        rows[#rows + 1] = { kind = "action", label = L["Own range…"], close = true,
            onClick = function()
                AskName(L["Level range, e.g. 20-30:"], "", function(text)
                    text = tostring(text or ""):gsub("–", "-")
                    local lo, hi = text:match("^%s*(%d+)%s*%-%s*(%d+)%s*$")
                    if not lo then lo = text:match("^%s*(%d+)%s*$"); hi = lo end
                    if lo then
                        lo, hi = tonumber(lo), tonumber(hi)
                        state.level = { math.min(lo, hi), math.max(lo, hi) }
                        T.Filters()
                        Dirty()
                    end
                end)
            end }
        return rows
    end

    -- the profession: its materials, or what it makes
    local profession = W.NewMenuButton(panel, dd, L["Profession"], "Interface\\Icons\\Trade_BlackSmithing")
    profession:SetPoint("LEFT", levelBtn, "RIGHT", 6, 0)
    local function ProfRows()
        local rows = { { kind = "radio", state = Check(state.prof == nil), label = L["All professions"],
            onClick = function() state.prof = nil; T.Filters(); Dirty() end } }
        if state.view == "recipes" then
            -- only what the chosen characters can make
            local names, seen = {}, {}
            for _, e in ipairs(ns.Acc.Recipes()) do
                for _, rec in ipairs(e.knownBy) do
                    if state.chars[rec.key] then
                        if not seen[e.prof] then seen[e.prof] = true; names[#names + 1] = e.prof end
                        break
                    end
                end
            end
            table.sort(names)
            for _, name in ipairs(names) do
                rows[#rows + 1] = { kind = "radio", state = Check(state.prof and state.prof.name == name), label = name,
                    onClick = function() state.prof = { mode = "recipe", name = name }; T.Filters(); Dirty() end }
            end
            return rows
        end
        for _, mode in ipairs({ "mat", "make" }) do
            rows[#rows + 1] = { kind = "header", label = mode == "mat" and L["Materials of"] or L["Made by"] }
            for _, name in ipairs(Sets().names) do
                rows[#rows + 1] = { kind = "radio", state = Check(state.prof and state.prof.mode == mode and state.prof.name == name),
                    label = L[name], indent = 6,
                    onClick = function() state.prof = { mode = mode, name = name }; T.Filters(); Dirty() end }
            end
        end
        return rows
    end

    -- the lists of items
    local lists = W.NewMenuButton(panel, dd, L["Lists"], "Interface\\Icons\\INV_Misc_Note_01")
    lists:SetPoint("LEFT", profession, "RIGHT", 6, 0)
    function T.NewList(item)
        return function(name)
            name = (name or ""):gsub("^%s+", ""):gsub("%s+$", "")
            if name == "" then return end
            local db = ns.db
            local l = { id = db.ahNextList or 2, name = name, items = {} }
            db.ahNextList = l.id + 1
            if item then l.items[item] = true end
            table.insert(Lists(), l)
            state.list = l.id
            T.Filters()
            Dirty()
        end
    end
    local function ListRows()
        local rows = { { kind = "radio", state = Check(state.list == nil), label = L["All items"],
            onClick = function() state.list = nil; T.Filters(); Dirty() end } }
        for _, l in ipairs(Lists()) do
            rows[#rows + 1] = { kind = "radio", state = Check(state.list == l.id), label = l.name, right = tostring(ListSize(l)),
                onClick = function() state.list = l.id; T.Filters(); Dirty() end }
        end
        rows[#rows + 1] = { kind = "separator" }
        rows[#rows + 1] = { kind = "action", label = L["New list…"], close = true,
            onClick = function() AskName(L["Name of the new list:"], "", T.NewList()) end }
        local cur = state.list and ListById(state.list)
        if cur then
            rows[#rows + 1] = { kind = "action", label = (L["Rename \"%s\"…"]):format(cur.name), close = true,
                onClick = function()
                    AskName(L["New name:"], cur.name, function(name)
                        name = (name or ""):gsub("^%s+", ""):gsub("%s+$", "")
                        if name ~= "" then cur.name = name; T.Filters() end
                    end)
                end }
            rows[#rows + 1] = { kind = "action", label = (L["Delete \"%s\""]):format(cur.name), close = true, color = C.red,
                onClick = function()
                    Confirm((L["Delete the list \"%s\"?"]):format(cur.name), function()
                        local all = Lists()
                        for i, l in ipairs(all) do if l == cur then table.remove(all, i) break end end
                        if #all == 0 then all[1] = { id = ns.db.ahNextList or 2, name = L["Favourites"], items = {} }; ns.db.ahNextList = all[1].id + 1 end
                        state.list = nil
                        T.Filters()
                        Dirty()
                    end)
                end }
        end
        return rows
    end

    -- availability at the auction house, and deals
    local offerBtn = W.NewMenuButton(panel, dd, L["Availability"], "Interface\\Icons\\INV_Misc_Coin_02")
    offerBtn:SetPoint("LEFT", lists, "RIGHT", 6, 0)
    local STOCK_LABEL = { offer = L["On offer"], out = L["Out of stock"], never = L["Never seen on the auction house"] }
    local function OfferRows()
        local function Row(label, key)
            return { kind = "radio", state = Check(state.stock == key), label = label,
                onClick = function() state.stock = key; T.Filters(); Dirty() end }
        end
        return {
            { kind = "header", label = L["Availability"] },
            Row(L["Any"], nil), Row(STOCK_LABEL.offer, "offer"), Row(STOCK_LABEL.out, "out"), Row(STOCK_LABEL.never, "never"),
        }
    end

    -- deals, and a way back to no filters at all
    local dealsT = W.NewToggle(panel, L["Deals only"], nil,
        function() return state.deals end,
        function(on) state.deals = on; T.Filters(); Dirty() end, K.SIDE_W - 16)
    dealsT:HookScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText(L["Deals only"], 1, 0.85, 0.4)
        local text
        if state.view == "trend" or state.view == "all" then
            text = L["Only items that cost at least 10 % less than their average."]
        elseif state.view == "recipes" then
            text = L["Only recipes that make a profit: the product is worth more than its materials cost."]
        elseif state.vsDE then
            text = L["Only items that sell for more on the auction house than disenchanting them is worth."]
        else
            text = L["Only items that sell for more on the auction house than to a vendor."]
        end
        GameTooltip:AddLine(text, 0.85, 0.85, 0.85, true)
        GameTooltip:Show()
    end)
    dealsT:HookScript("OnLeave", function() GameTooltip:Hide() end)
    -- (your items, your recipes) only what disenchanting would bring more than selling it
    local deT = W.NewToggle(panel, L["Compare: disenchanting"], nil,
        function() return state.vsDE end,
        function(on) state.vsDE = on or nil; T.Filters(); Dirty() end, K.SIDE_W - 16)
    deT:HookScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText(L["Compare: disenchanting"], 1, 0.85, 0.4)
        GameTooltip:AddLine(state.view == "recipes" and L["Measure the profit of a recipe against what disenchanting the product would bring, instead of what it sells for."]
            or L["Measure the auction price against the estimated disenchant value instead of what a vendor pays: the gain is the auction price (after the fee) minus that value."], 0.85, 0.85, 0.85, true)
        GameTooltip:Show()
    end)
    deT:HookScript("OnLeave", function() GameTooltip:Hide() end)
    local clearBtn = W.NewButton(panel, L["Clear filters"], K.SIDE_W - 16, 24)
    clearBtn:SetScript("OnClick", function()
        state.class, state.sub, state.slot, state.level, state.stock = nil, nil, nil, nil, nil
        state.list, state.prof, state.deals = nil, nil, false
        SetDefaultRarity(state.rarity)
        search:SetText("")
        T.Filters()
        Dirty()
    end)

    for _, b in ipairs({ category, T.slotBtn, levelBtn, profession, rarityBtn, lists, offerBtn, options, charsBtn, placeBtn }) do b.clickOnly = true end
    for _, w in ipairs({ category, T.slotBtn, levelBtn, profession, rarityBtn, lists, offerBtn, charsBtn, placeBtn, dealsT, deT, clearBtn }) do
        w:SetParent(side)
    end

    T.dd = dd
    function T.Filters()
        local first = Lists()[1]
        favBtn:SetActive(state.list ~= nil and first ~= nil and state.list == first.id)
        category:SetContent(CategoryLabel(), W.ICON.loot, CategoryRows, state.class ~= nil)
        if state.class ~= 4 then state.slot = nil end -- (the slot belongs to armour only)
        T.slotBtn:SetContent(T.SlotLabel(), "Interface\\Icons\\INV_Chest_Cloth_17", T.SlotRows, state.slot ~= nil)
        local lv = state.level
        levelBtn:SetContent(lv and ((lv[1] == 0 and (L["Usable at level %d"]):format(lv[2])) or (L["Level %d–%d"]):format(lv[1], lv[2])) or L["Level"],
            W.ICON.rate, LevelRows, lv ~= nil)
        local chars, places = state.chars or {}, state.places or { bags = true, bank = true } -- (only the views of what you own have them)
        local nChars, total, only = 0, 0, nil
        for _, rec in ipairs(ns.Acc.Chars()) do
            total = total + 1
            if chars[rec.key] then nChars = nChars + 1; only = rec end
        end
        charsBtn:SetContent(nChars == total and total > 1 and L["All characters"] or (nChars == 1 and only and ClassColour(only, only.name or "?"))
            or (L["%d characters"]):format(nChars), W.ICON.account, CharRows, false)
        placeBtn:SetContent(places.bags and places.bank and L["Bags & bank"] or (places.bags and L["Bags"])
            or (places.bank and L["Bank"]) or L["No place"], "Interface\\Icons\\INV_Misc_Bag_08", PlaceRows,
            not (places.bags and places.bank))
        local kinds = 0
        for q = 0, 7 do if state.rarity[q] then kinds = kinds + 1 end end
        rarityBtn:SetContent(RarityIsDefault() and L["Rarity"] or (L["Rarity (%d of 8)"]):format(kinds),
            "Interface\\Icons\\INV_Misc_Gem_Variety_02", RarityRows, not RarityIsDefault())
        local p = state.prof
        profession:SetContent(p and (p.mode == "recipe" and p.name or (p.mode == "mat" and L["Materials: %s"] or L["Made: %s"]):format(L[p.name]))
            or L["Profession"],
            "Interface\\Icons\\Trade_BlackSmithing", ProfRows, p ~= nil)
        local cur = state.list and ListById(state.list)
        lists:SetContent(cur and cur.name or L["Lists"], "Interface\\Icons\\INV_Misc_Note_01", ListRows, cur ~= nil)
        offerBtn:SetContent(state.stock and STOCK_LABEL[state.stock] or L["Availability"], "Interface\\Icons\\INV_Misc_Coin_02",
            OfferRows, state.stock ~= nil)
        dealsT:Refresh()
        deT:Refresh()
        T.anyFilter = (state.class or state.level or state.stock or state.list or state.prof or state.deals or state.query ~= ""
            or not RarityIsDefault()) and true or false
        if T.anyFilter then handle.arrow:SetVertexColor(C.gold[1], C.gold[2], C.gold[3]) else handle.arrow:SetVertexColor(0.6, 0.55, 0.45) end
        if T.Layout then T.Layout() end
    end
    T.Filters()

    count = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    count:SetPoint("RIGHT", options, "LEFT", -14, 0)
    count:SetTextColor(unpack(C.muted))
    indexNote = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    indexNote:SetPoint("RIGHT", count, "LEFT", -14, 0)
    scanNote = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    scanNote:SetPoint("RIGHT", indexNote, "LEFT", -14, 0)
    scanNote:SetTextColor(0.78, 0.62, 0.28)
    indexNote:SetTextColor(C.goldDim[1], C.goldDim[2], C.goldDim[3])
    count:Hide()      -- (these three only hold their texts: the one line of the footer, "status", shows them all)
    indexNote:Hide()
    scanNote:Hide()

    -- column heads (click to sort); one set per view, as the same column can be called differently
    heads = {}
    local function Head(hk, sortKey, title, tip, left)
        local h = CreateFrame("Button", nil, panel)
        h:SetHeight(K.HEAD)
        h.key, h.title, h.hk = sortKey, title, hk
        h.text = h:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        h.text:SetAllPoints()
        h.text:SetTextColor(C.gold[1], C.gold[2], C.gold[3])
        h.text:SetJustifyH(left and "LEFT" or "RIGHT")
        h:SetScript("OnClick", function()
            W.Click()
            if state.sort == sortKey then state.asc = not state.asc else state.sort, state.asc = sortKey, left or false end
            Dirty()
        end)
        h:SetScript("OnEnter", function(self)
            self.text:SetTextColor(1, 0.95, 0.7)
            if tip then
                GameTooltip:SetOwner(self, "ANCHOR_TOP")
                GameTooltip:SetText(title, 1, 0.85, 0.4)
                GameTooltip:AddLine(tip, 0.85, 0.85, 0.85, true)
                GameTooltip:Show()
            end
        end)
        h:SetScript("OnLeave", function(self) self.text:SetTextColor(C.gold[1], C.gold[2], C.gold[3]); GameTooltip:Hide() end)
        h:Hide()
        heads[hk] = h
        return h
    end
    Head("name", "name", L["Item"], nil, true)
    for _, v in ipairs(VIEW_ORDER) do
        for _, col in ipairs(VIEWS[v].cols) do
            local h = Head(v .. ":" .. col[1], col[1] == "trend" and "diff" or col[1], col[3], col[4])
            if col[1] == "trend" then h.text:SetJustifyH("CENTER") end
        end
    end

    function T.AnchorHeads()
        for _, h in pairs(heads) do h:Hide() end
        if T.IsPage(state.view) then return end
        for ci, col in ipairs(Cols(state.view)) do
            local h = heads[state.view .. ":" .. col[1]]
            h:ClearAllPoints()
            h:SetWidth(col[2] - 8)
            h:SetPoint("TOPRIGHT", panel, "TOPRIGHT", -(K.LIST_RIGHT + ColRight(state.view, ci)), -headY)
            h:Show()
        end
        heads.name:ClearAllPoints()
        heads.name:SetPoint("TOPLEFT", left0 + 44 + T.LocW(), -headY)
        heads.name:SetPoint("TOPRIGHT", panel, "TOPRIGHT", -(K.LIST_RIGHT + ColsWidth(state.view) + 8), -headY)
        heads.name:Show()
    end

    function T.ApplyView()
        if T.sell then T.sell:Close() end
        if T.buy then T.buy:Close() end
        if T.craft then T.craft:Close() end
        T.SyncSearch()
        for v, b in pairs(viewButtons) do b:SetSelected(state.view == v) end
        for _, h in pairs(heads) do h:Hide() end
        T.Filters()
        T.Layout()
        for _, r in ipairs(rows) do r.view = nil end
        -- What this view showed last is there at once, with its own columns; a fresh list follows. Without one the
        -- table is empty ("Loading…") rather than showing the rows of the other view in the wrong columns.
        local last = results[state.view]
        data = last and last.data or {}
        counts, classCount = last and last.counts or {}, last and last.classCount or {}
        scroll:SetVerticalScroll(0)
        if panel:IsShown() then T.Redraw() end
    end

    local line = panel:CreateTexture(nil, "ARTWORK")
    line:SetColorTexture(C.goldDim[1], C.goldDim[2], C.goldDim[3], 0.8)
    line:SetPoint("TOPLEFT", K.LEFT0, -(listTop - 2))
    line:SetPoint("TOPRIGHT", -8, -(listTop - 2))
    line:SetHeight(1)
    -- thin dividers: under the views, between the column and the list, above the scan strip
    local function Rule()
        local t = panel:CreateTexture(nil, "ARTWORK")
        t:SetColorTexture(C.goldDim[1], C.goldDim[2], C.goldDim[3], 0.55)
        return t
    end
    local rule = Rule() -- under the first row (search and filter)
    rule:SetPoint("TOPLEFT", 8, -40)
    rule:SetPoint("TOPRIGHT", -8, -40)
    rule:SetHeight(1)
    T.topRule = rule
    rule = Rule() -- between the column and the list
    rule:SetPoint("TOPLEFT", clip, "TOPRIGHT", 3, 0)
    rule:SetPoint("BOTTOMLEFT", clip, "BOTTOMRIGHT", 3, 0)
    rule:SetWidth(1)
    local sideRule = rule

    -- the list and its scroll bar
    scroll = CreateFrame("ScrollFrame", nil, panel)
    scroll:SetPoint("TOPLEFT", K.LEFT0, -listTop)
    scroll:SetPoint("BOTTOMRIGHT", -K.LIST_RIGHT, K.SIDE_BOTTOM)
    scroll:EnableMouseWheel(true)
    content = CreateFrame("Frame", nil, scroll)
    content:SetSize(10, 10)
    scroll:SetScrollChild(content)
    rows = {}
    scroll:SetScript("OnSizeChanged", function(_, w) content:SetWidth(w); Refresh() end)
    local function ScrollTo(v)
        local maxScroll = math.max(0, #data * K.ROW - scroll:GetHeight())
        scroll:SetVerticalScroll(math.max(0, math.min(maxScroll, v)))
    end
    scroll:SetScript("OnMouseWheel", function(_, delta) ScrollTo(scroll:GetVerticalScroll() - delta * K.ROW * 3) end)
    scroll:SetScript("OnVerticalScroll", function() T.Draw() end)

    track = CreateFrame("Frame", nil, panel)
    track:SetWidth(10)
    track:SetPoint("TOPRIGHT", panel, "TOPRIGHT", -8, -listTop)
    track:SetPoint("BOTTOMRIGHT", panel, "BOTTOMRIGHT", -8, K.SIDE_BOTTOM)
    track:EnableMouse(true)
    -- (the scroll bar as everywhere in this addon: a slim gilded thumb, no dark track behind it)
    track:SetScript("OnMouseDown", function(self)
        local _, y = GetCursorPosition()
        y = y / self:GetEffectiveScale()
        local page = scroll:GetHeight() - K.ROW
        local top = thumb:GetTop()
        ScrollTo(scroll:GetVerticalScroll() + ((top and y > top) and -page or page))
    end)
    thumb = CreateFrame("Button", nil, track)
    thumb:SetWidth(4)
    thumb.tex = thumb:CreateTexture(nil, "ARTWORK")
    thumb.tex:SetAllPoints()
    local function ThumbColor(on)
        local c = on and C.gold or C.goldDim
        thumb.tex:SetColorTexture(c[1], c[2], c[3], 0.8)
    end
    ThumbColor(false)
    thumb:SetScript("OnEnter", function() ThumbColor(true) end)
    thumb:SetScript("OnLeave", function(self) if not self.drag then ThumbColor(false) end end)
    thumb:SetScript("OnMouseDown", function(self)
        local _, y = GetCursorPosition()
        self.drag = { y = y / self:GetEffectiveScale(), scroll = scroll:GetVerticalScroll() }
    end)
    thumb:SetScript("OnMouseUp", function(self) self.drag = nil; ThumbColor(false) end)
    thumb:SetScript("OnUpdate", function(self)
        if not self.drag then return end
        local _, y = GetCursorPosition()
        y = y / self:GetEffectiveScale()
        local total, shown = #data * K.ROW, scroll:GetHeight()
        local room = track:GetHeight() - self:GetHeight()
        if room > 0 then ScrollTo(self.drag.scroll + (self.drag.y - y) / room * (total - shown)) end
    end)
    thumb:Hide()

    -- the same for the table: a cover over heads, list and scroll bar, as opaque as the table is invisible
    local listCoverF = CreateFrame("Frame", nil, panel)
    listCoverF:SetPoint("TOPLEFT", line, "TOPLEFT", 0, 24)
    listCoverF:SetPoint("BOTTOMRIGHT", track, "BOTTOMRIGHT", 0, 0)
    listCoverF:SetFrameLevel(scroll:GetFrameLevel() + 40)
    -- (no cover with a colour of its own: the table is emptied by fading its parts out, and "Loading…" is written on the bare panel)
    local loadingText = listCoverF:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    loadingText:SetPoint("TOP", scroll, "TOP", 0, -50)
    loadingText:SetTextColor(unpack(C.muted))
    loadingText:SetText(L["Loading…"])
    loadingText:Hide()

    -- A change of the table (another view, a filter, the column coming or going) is a transition in three parts: the table fades
    -- out under a cover (a tenth of a second); then the change is made, out of sight, and the list worked out if that takes time
    -- (it is waited for, "Loading…" on the cover); then the table fades in (a sixth of a second). Nothing is seen half-changed.
    local trans, listC = nil, 0
    function T.Transition(swap, hold)
        if not trans then trans = { swaps = {}, phase = "out", wait = 0 } end
        if trans.phase == "in" then trans.phase = "out" end
        if swap then trans.swaps[#trans.swaps + 1] = swap end
        if hold then trans.hold = true end
    end
    local function TransStep(dt)
        if not trans then return end
        if trans.phase == "out" then
            listC = math.min(1, listC + dt * 10)
            if listC >= 1 then
                local swaps = trans.swaps
                trans.swaps = {}
                for _, fn in ipairs(swaps) do fn() end
                trans.phase, trans.wait = "hold", 0
            end
        elseif trans.phase == "hold" then
            trans.wait = trans.wait + dt
            if not (trans.hold and job) or trans.wait > 4 then -- nothing to wait for any more (or it takes too long)
                trans.hold = nil
                if panel:IsShown() then T.Redraw() end
                trans.phase = "in"
            end
        else
            listC = math.max(0, listC - dt * 6)
            if listC <= 0 then trans = nil end
        end
        local a = 1 - listC
        scroll:SetAlpha(a); track:SetAlpha(a); thumb:SetAlpha(a); line:SetAlpha(a); dash:SetAlpha(a); shop:SetAlpha(a); ownPage:SetAlpha(a)
        for _, h in pairs(heads) do h:SetAlpha(a) end
        loadingText:SetShown(trans ~= nil and trans.phase == "hold" and job ~= nil and listC >= 1)
    end

    -- the filters stand one below the other in the column; the column can be folded away to give the list the room
    -- The table begins where the column ends (and is laid out again for the width it has: columns that do not fit give way).
    -- Called every frame while the column grows or shrinks.
    function T.ListEdge()
        -- (when the column is away the table is close to the arrow; the gap to the column's line comes with its width)
        local open = math.min(1, math.max(0, (sideX - K.HIDDEN) / (K.OPEN - K.HIDDEN)))
        left0 = Snap(sideX + 6 + 9 * open)
        sideRule:SetShown(sideX > K.HIDDEN + 6 and not T.IsPage(state.view))
        line:ClearAllPoints()
        line:SetPoint("TOPLEFT", left0, -(listTop - 2))
        line:SetPoint("TOPRIGHT", -8, -(listTop - 2))
        scroll:ClearAllPoints()
        scroll:SetPoint("TOPLEFT", left0, -listTop)
        scroll:SetPoint("BOTTOMRIGHT", -K.LIST_RIGHT, K.SIDE_BOTTOM)
        if Compute(panel:GetWidth() - left0 - K.LIST_RIGHT) then
            for _, r in ipairs(rows) do r.view = nil end
        end
        T.AnchorHeads()
    end

    function T.Layout()
        local pinned = ns.db.settings.ahPin == true
        if T.pinned ~= pinned then -- pinned: the column stays; otherwise it starts folded away
            T.pinned = pinned
            sideTarget = pinned and K.OPEN or K.HIDDEN
            SetSideX(sideTarget)
        end
        local own = state.view == "profit" or state.view == "recipes" -- views of what you own: characters and places first
        local order = { category, profession, levelBtn, rarityBtn, lists, offerBtn }
        T.slotBtn:SetShown(state.class == 4)
        if state.class == 4 then table.insert(order, 2, T.slotBtn) end
        if own then
            table.insert(order, 1, placeBtn)
            table.insert(order, 1, charsBtn)
        end
        charsBtn:SetShown(own)
        placeBtn:SetShown(own)
        -- The rhythm of the column: every control 24 high, 6 between them, a little more before the switches; they stand 5 from
        -- the column's edge (8 from the window's), as the lines do, and as wide as the column less the same room on the right.
        local GAP, H, CW = 6, 24, K.OPEN - 10
        local y = 0
        for _, b in ipairs(order) do
            b:SetSize(CW, H)
            b.text:ClearAllPoints()
            b.text:SetPoint("LEFT", b.pic:IsShown() and 26 or 9, 0)
            b.text:SetPoint("RIGHT", b, "RIGHT", -20, 0)
            b.text:SetJustifyH("LEFT")
            b.text:SetWordWrap(false)
            b:ClearAllPoints()
            b:SetPoint("TOPLEFT", side, "TOPLEFT", 5, -y)
            y = y + H + GAP
        end
        y = y + GAP
        dealsT:SetSize(CW, H)
        dealsT:ClearAllPoints()
        dealsT:SetPoint("TOPLEFT", side, "TOPLEFT", 5, -y)
        y = y + H + GAP
        deT:SetSize(CW, H)
        deT:ClearAllPoints()
        deT:SetPoint("TOPLEFT", side, "TOPLEFT", 5, -y)
        deT:SetShown(own)
        if own then y = y + H + GAP end
        y = y + GAP
        clearBtn:SetSize(CW, H)
        clearBtn:ClearAllPoints()
        clearBtn:SetPoint("TOPLEFT", side, "TOPLEFT", 5, -y)
        clearBtn:SetShown(T.anyFilter and true or false)
        sideBtn:SetSelected(pinned)
        -- the dashboard has no filters and no table: the column, its strip and the table's parts are not there
        local isDash = T.IsPage(state.view)
        clip:SetShown(not isDash)
        search:SetShown(not isDash)
        T.favBtn:SetShown(not isDash)
        T.checkBtn:SetShown(state.view == "profit")
        T.plannedBtn:SetShown(state.view == "profit")
        T.SyncPlanned()
        if T.topRule then T.topRule:SetShown(not isDash) end
        sideBtn:SetShown(not isDash)
        scroll:SetShown(not isDash)
        track:SetShown(not isDash)
        line:SetShown(not isDash)
        dash:SetShown(state.view == "dash")
        shop:SetShown(state.view == "shop")
        ownPage:SetShown(state.view == "own")
        if isDash then handle:Hide() else SetSideX(sideX) end
        sideBtn.text:SetText(L["Filters"] .. ((not pinned and T.anyFilter) and " •" or ""))
        T.ListEdge()
    end

    -- Every frame. The column grows out of the strip while the mouse is on it (or on the strip), while a menu of it is open or the
    -- search is typed in, and shrinks back after a moment without any of that; the table's left edge moves with it.
    local function SideStep(dt)
        TransStep(dt)
        if ns.db.settings.ahPin == true or T.IsPage(state.view) then return end
        local over = handle:IsMouseOver() or clip:IsMouseOver()
        local menuOpen = dd:IsShown() and dd.owner and dd.owner:GetParent() == side
        if over or menuOpen or search:HasFocus() then
            sideAway, sideTarget = 0, K.OPEN
        else
            sideAway = sideAway + dt
            if sideAway > 0.35 then sideTarget = K.HIDDEN end
        end
        if sideX ~= sideTarget then
            local nx = sideX + (sideTarget - sideX) * math.min(1, dt * 12)
            if math.abs(sideTarget - nx) < 0.6 then nx = sideTarget end
            SetSideX(nx)
            T.ListEdge()
        end
    end
    panel:SetScript("OnSizeChanged", function() T.Layout() end)

    empty = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    empty:SetPoint("TOP", scroll, "TOP", 0, -50)
    empty:SetWidth(560)
    empty:SetTextColor(unpack(C.muted))

    local acc = 0
    panel:SetScript("OnUpdate", function(_, dt)
        W.Step(dt) -- the buttons' hover and selected glow is eased by whoever owns the window
        SideStep(dt)
        local phase, frac = ns.AH.Progress()
        if phase == "wait" then
            scanNote:SetText(L["Waiting for the auction house…"])
        elseif phase then
            scanNote:SetText((L["Scanning… %d %%"]):format(math.floor(frac * 100)))
        else
            scanNote:SetText("")
        end
        -- one line: the scan (or the state of the data), what is being read, the count of the list
        local parts = {}
        local checked, checkTotal = ns.AuctionSell.Progress()
        if checked then
            parts[1] = (L["Checking prices… %d of %d"]):format(checked, checkTotal)
            status:SetTextColor(0.78, 0.62, 0.28)
        elseif phase then
            parts[1] = scanNote:GetText()
            status:SetTextColor(0.78, 0.62, 0.28)
        else
            parts[1] = panel.stateText
            status:SetTextColor(unpack(C.muted))
        end
        for _, fs in ipairs({ indexNote, count }) do
            local t = fs:GetText()
            if t and t ~= "" then parts[#parts + 1] = t end
        end
        status:SetText(table.concat(parts, "   ·   "))
        acc = acc + dt
        if acc < 0.4 then return end
        acc = 0
        panel.stateText = ns.AH.Status()
        local was = panel.scanning
        panel.scanning = ns.AH.Scanning()
        scanBtn:SetAlpha((not panel.scanning and (not ns.AH.IsOpen() or ns.AH.CooldownLeft() > 0)) and 0.5 or 1)
        if was and not panel.scanning then DirtyQuiet() end
    end)
    panel:SetScript("OnShow", function() Refresh() end)

    local loader = CreateFrame("Frame", nil, panel)
    loader:RegisterEvent("GET_ITEM_INFO_RECEIVED")
    local pending
    loader:SetScript("OnEvent", function(_, _, itemID, success)
        if itemID then
            if success == false then Fail(itemID) else Fill(itemID) end
        end
        if pending then return end
        pending = true
        C_Timer.After(0.6, function() pending = nil; if panel:IsShown() then Refresh() end end)
    end)

    T.ApplyView()
end

local OFFSET_X = (WOW_PROJECT_ID == WOW_PROJECT_MAINLINE or WOW_PROJECT_ID == WOW_PROJECT_CAMELOT) and 3 or -14

local function Select()
    W.TabClick()
    AuctionHouseFrame:SetDisplayMode({})
    AuctionHouseFrame.displayMode = nil
    for _, t in ipairs(AuctionHouseFrame.Tabs) do PanelTemplates_DeselectTab(t) end
    PanelTemplates_SelectTab(tab)
    if AuctionHouseFrame.SetTitle then AuctionHouseFrame:SetTitle(L["Forever Companion"]) end
    T.PlacePanel(AuctionHouseFrame) -- (the page may have been in the window)
    if ns.AuctionWindow then ns.AuctionWindow.Hide() end
    panel:Show()
end

local function Create()
    if created or not (AuctionHouseFrame and AuctionHouseFrame.Tabs and #AuctionHouseFrame.Tabs > 0) then return end
    created = true
    if panel then T.PlacePanel(AuctionHouseFrame) else Build(AuctionHouseFrame) end -- (it may be built already, for the window)
    local last = AuctionHouseFrame.Tabs[#AuctionHouseFrame.Tabs]
    tab = CreateFrame("Button", "ForeverCompanionAuctionTabButton", AuctionHouseFrame, "AuctionHouseFrameDisplayModeTabTemplate")
    tab:SetText(L["Companion"])
    PanelTemplates_TabResize(tab, 20, nil, 70)
    tab:SetPoint("TOPLEFT", last, "TOPRIGHT", OFFSET_X, 0)
    tab:SetHitRectInsets((math.abs(OFFSET_X) - 3) / 2, (math.abs(OFFSET_X) - 3) / 2, 0, 0)
    PanelTemplates_DeselectTab(tab)
    tab:SetScript("OnClick", Select)
    T.Prewarm()
    -- the game's own tabs take over again: hide our page
    hooksecurefunc(AuctionHouseFrame, "SetDisplayMode", function(_, mode)
        if mode ~= nil and #mode > 0 and panel:IsShown() and panel:GetParent() == AuctionHouseFrame then
            panel:Hide()
            PanelTemplates_DeselectTab(tab)
        end
    end)
    AuctionHouseFrame:HookScript("OnHide", function()
        if panel:GetParent() == AuctionHouseFrame then panel:Hide() end
        PanelTemplates_DeselectTab(tab)
    end)
end

local events = CreateFrame("Frame")
events:RegisterEvent("AUCTION_HOUSE_SHOW")
events:SetScript("OnEvent", function()
    C_Timer.After(0, function()
        local ok, err = pcall(Create)
        if not ok then
            created = true -- do not try again every time
            -- say so (once): a tab that silently does not appear is worse than a message
            print("|cffffd100ForeverCompanion:|r auction tab could not be built: " .. tostring(err))
        end
        -- the Companion tab is the first one that is shown (a setting, on unless switched off): after a moment, when the game has set its own
        if tab and panel and ns.db.settings.ahOpenCodex ~= false then
            C_Timer.After(0.15, function()
                if AuctionHouseFrame and AuctionHouseFrame:IsShown() then pcall(Select) end
            end)
        end
    end)
end)

-- The window of the addon with the same page (when the auction house is closed): the prices of the last scan, the lists, the trends, the
-- shopping list and the history. Buying and selling need the auction house: the panels say so. With the auction house open the tab is used.
local win
local AW = {}
ns.AuctionWindow = AW

local function BuildWindow()
    win = W.NewPlate(UIParent, C.page)
    win:SetSize(1010, 700)
    win:SetPoint("CENTER")
    win:SetFrameStrata("MEDIUM")
    win:SetToplevel(true)
    win:SetMovable(true)
    win:SetClampedToScreen(true)
    win:EnableMouse(true)
    win:RegisterForDrag("LeftButton")
    win:SetScript("OnDragStart", win.StartMoving)
    -- place and scale are kept
    local function SaveWin()
        if not ns.db then return end
        local point, _, rel, x, y = win:GetPoint()
        ns.db.ahWin = { pos = { point, rel, x, y }, scale = win:GetScale() }
    end
    win:SetScript("OnDragStop", function(self) self:StopMovingOrSizing(); SaveWin() end)
    local saved = ns.db and ns.db.ahWin
    if saved then
        if saved.scale then win:SetScale(math.max(0.6, math.min(1.6, saved.scale))) end
        if saved.pos then
            win:ClearAllPoints()
            win:SetPoint(saved.pos[1], UIParent, saved.pos[2], saved.pos[3], saved.pos[4])
        end
    end
    -- the corner grip scales the whole window (its layout is fixed)
    local grip = CreateFrame("Button", nil, win)
    grip:SetSize(16, 16)
    grip:SetPoint("BOTTOMRIGHT", -3, 3)
    grip:SetFrameLevel(win:GetFrameLevel() + 50)
    grip:SetNormalTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Up")
    grip:SetHighlightTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Highlight")
    grip:SetPushedTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Down")
    W.AttachScaleGrip(win, grip, { scaleOnly = true, minScale = 0.6, maxScale = 1.6, gridScale = 0.05, saveScale = SaveWin, savePos = SaveWin })
    win:Hide()
    _G.ForeverCompanionAuctionWindow = win
    tinsert(UISpecialFrames, "ForeverCompanionAuctionWindow")
    local close = W.NewButton(win, "×", 20, 20, "GameFontNormal")
    close:SetPoint("TOPRIGHT", -8, -8)
    close:SetScript("OnClick", function() win:Hide() end)
    win.closeBtn = close
    win.skinRowAll = {} -- (the round icon opens the menu of the other windows)
    win.skinKey = "ah"
    win.titleText = win:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    win.titleText:SetPoint("TOP", 0, -12)
    win.titleText:SetText(L["Auction house"])
    win.titleText:SetTextColor(C.gold[1], C.gold[2], C.gold[3])
    win:SetScript("OnHide", function(self)
        if panel and panel:GetParent() == self then panel:Hide() end
    end)
end

function AW.ApplyFrameStyle()
    if not win then return end
    local blizz = W.BlizzSkin(win, true, W.ICON.coin, L["Auction house"], "ah")
    if blizz then
        win:SetBackdrop(nil)
    else
        win:SetBackdrop(W.PLATE_BACKDROP)
        win:SetBackdropColor(unpack(C.page))
        win:SetBackdropBorderColor(C.goldDim[1], C.goldDim[2], C.goldDim[3], 1)
    end
    win.titleText:SetShown(not blizz)
    if panel and panel:GetParent() == win then T.PlacePanel(win) end -- (the place of the page depends on the style)
end

function AW.Hide() if win and win:IsShown() then win:Hide() end end
function AW.ResetWindow()
    if ns.db then ns.db.ahWin = nil end
    if win then
        win:SetScale(1)
        win:ClearAllPoints()
        win:SetPoint("CENTER")
    end
end
function AW.IsShown() return win and win:IsShown() end

function AW.Show()
    -- with the auction house open the page is in its tab
    if created and tab and AuctionHouseFrame and AuctionHouseFrame:IsShown() then Select() return end
    if not win then BuildWindow() end
    if not panel then Build(win) end
    T.PlacePanel(win)
    AW.ApplyFrameStyle()
    win:Show()
    panel:Show()
    win:Raise()
end

function AW.Toggle()
    if win and win:IsShown() then win:Hide() else AW.Show() end
end

SLASH_FOREVERCOMPANIONAH1 = "/fcah"
SlashCmdList.FOREVERCOMPANIONAH = function() AW.Toggle() end
