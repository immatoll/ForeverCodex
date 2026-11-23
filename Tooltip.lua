local ADDON, ns = ...
local L = ns.L

-- What the addon knows, added to the game's tooltips: prices, their age, what an item is worth
-- over its vendor price, where it drops; for creatures the kills, the progress to drop chances
-- and the best things they drop. Every line is a switch in the settings.

local TOP_N = 3

-- id, label, default; the settings page lists them by group
ns.TIP_OPTIONS = {
    { "master", L["Show information in tooltips"], true, "general" },
    { "shiftOnly", L["Only while Shift is held"], false, "general" },
    { "header", L["Heading line"], false, "general" },

    { "itemVendor", L["Vendor price"], true, "item" },
    { "itemAuction", L["Auction price"], true, "item" },
    { "itemStack", L["Stack price with Shift"], true, "item" },
    { "itemAge", L["Age of the auction price"], true, "item" },
    { "itemDiff", L["Profit over the vendor price"], true, "item" },
    { "itemTrend", L["Auction trend (7 days)"], true, "item" },
    { "itemOwned", L["How much you looted"], true, "item" },
    { "itemSources", L["Best sources of the item"], true, "item" },
    { "itemDisenchant", L["Disenchanting: results, chances and value"], true, "item" },
    { "itemCraft", L["Crafting: professions, and which of your characters need it or can make it"], true, "item" },
    { "itemAlts", L["Where your characters have it"], true, "item" },

    { "mobKills", L["Kills"], true, "mob" },
    { "mobProgress", L["Progress to the drop chances"], false, "mob" },
    { "mobTop", L["Best drops (top 3)"], true, "mob" },
    { "mobAvg", L["Average value per kill"], true, "mob" },

    { "nodeVisited", L["Visited here, and when last"], true, "node" },
    { "nodeGathered", L["Times gathered and value"], true, "node" },
    { "nodeDrops", L["What it gives (top 3)"], true, "node" },
}
local DEFAULT = {}
for _, o in ipairs(ns.TIP_OPTIONS) do DEFAULT[o[1]] = o[3] end

function ns.TipOn(id)
    local t = ns.db and ns.db.settings and ns.db.settings.tip
    local v = t and t[id]
    if v == nil then return DEFAULT[id] end
    return v
end
function ns.TipSet(id, on)
    local s = ns.db.settings
    s.tip = s.tip or {}
    s.tip[id] = on and true or false
end

local GREEN, RED, AMBER, GREY = "|cff66dbb0", "|cffe86a5a", "|cffeda65f", "|cff9a9080"

local function Money(copper, tint)
    local s = ns.Value.Format(copper, tint)
    return s ~= "" and s or "0"
end

local GOLD_HEX = "|cffffd100"

local function AddEntry(tt, left, right)
    if right then tt:AddDoubleLine(left, right, 0.82, 0.78, 0.68, 1, 1, 1)
    else tt:AddLine(left, 0.82, 0.78, 0.68, true) end
end

-- the lines are collected first: no lines, no heading. A line with .head starts a group: a gold
-- title (with a note on the right) after a little space.
local function Finish(tt, lines)
    if #lines == 0 then return end
    tt:AddLine(" ") -- (a blank line: our lines are set apart from the game's own)
    if ns.TipOn("header") then tt:AddLine(GOLD_HEX .. "Forever Companion|r") end
    for i, ln in ipairs(lines) do
        if ln.head then
            if i > 1 or ns.TipOn("header") then tt:AddLine(" ") end
            tt:AddDoubleLine(ln.head, ln.right or "", 1, 0.82, 0.2, 0.6, 0.57, 0.5)
        else
            AddEntry(tt, ln[1], ln[2])
        end
    end
    tt:Show()
end

local function Allowed()
    if not (ns.db and ns.TipOn("master")) then return false end
    if ns.TipOn("shiftOnly") and not IsShiftKeyDown() then return false end
    return true
end

-- items -------------------------------------------------------------------------------------
-- the number of items in the stack the tooltip is about (1 when it cannot be told): bag slots
-- and loot window slots say it
local function StackCount(tt)
    local owner = tt.GetOwner and tt:GetOwner()
    if not owner then return 1 end
    local n
    pcall(function()
        if owner.GetBagID and owner.GetID then
            local info = C_Container and C_Container.GetContainerItemInfo and C_Container.GetContainerItemInfo(owner:GetBagID(), owner:GetID())
            n = info and info.stackCount
        elseif owner.slot and GetLootSlotInfo then
            local _, _, qty = GetLootSlotInfo(owner.slot)
            n = qty
        end
    end)
    n = ns.ReadableNumber(n)
    return (n and n > 1) and n or 1
end

-- the last days as small bars (the last one highlighted); days without data are a thin dark line
local BAR_TEX = "Interface\\Buttons\\WHITE8X8"
local function Bars(values)
    local top = 0
    for _, v in ipairs(values) do if v > top then top = v end end
    if top <= 0 then return nil end
    local parts = {}
    for i, v in ipairs(values) do
        local h = v > 0 and math.max(2, math.floor(v / top * 12 + 0.5)) or 1
        local r, g, b = 200, 170, 90
        if v == 0 then r, g, b = 80, 70, 56 elseif i == #values then r, g, b = 102, 219, 176 end
        parts[#parts + 1] = ("|T%s:%d:5:0:%d:8:8:0:8:0:8:%d:%d:%d|t"):format(BAR_TEX, h, math.floor(h / 2 - 6), r, g, b)
        if i < #values then parts[#parts + 1] = ("|T%s:1:2:0:0:8:8:0:8:0:8:30:26:20|t"):format(BAR_TEX) end
    end
    return table.concat(parts)
end

local function ClassName(rec)
    local c = RAID_CLASS_COLORS and rec.class and RAID_CLASS_COLORS[rec.class]
    return (c and ns.W.Hex({ c.r, c.g, c.b }) or "") .. (rec.name or "?") .. "|r"
end

-- a short list of characters: coloured names, the first few, and "+n"
local function Names(list, limit)
    local parts = {}
    for i = 1, math.min(limit or 4, #list) do parts[#parts + 1] = ClassName(list[i]) end
    if #list > (limit or 4) then parts[#parts + 1] = GREY .. "+" .. (#list - (limit or 4)) .. "|r" end
    return table.concat(parts, ", ")
end

local recipeCache = { t = -10 }
local function Recipes()
    if GetTime() - recipeCache.t > 3 then
        recipeCache.list = ns.Acc.Recipes()
        recipeCache.t = GetTime()
    end
    return recipeCache.list
end

-- crafting, for the characters: who needs the item, who makes it, who could still learn it (the first list), and the
-- recipes that use it (the second, only when the detail option is on)
local function CraftLines(id)
    local recipeLines, charLines = {}, {}
    local used, made = {}, {}
    for _, r in ipairs(Recipes()) do
        for _, g in ipairs(r.reagents or {}) do
            if g.id == id then used[#used + 1] = { r = r, need = g.count or 1 } break end
        end
        if r.id == id then made[#made + 1] = r end
    end
    if #used == 0 and #made == 0 then return charLines, recipeLines end
    if #used > 0 then
        table.sort(used, function(a, b) return #a.r.knownBy > #b.r.knownBy end)
        local needers, seen = {}, {}
        for _, u in ipairs(used) do
            for _, rec in ipairs(u.r.knownBy) do
                if not seen[rec.key] then seen[rec.key] = true; needers[#needers + 1] = rec end
            end
        end
        for i = 1, math.min(TOP_N, #used) do
            local u = used[i]
            recipeLines[#recipeLines + 1] = { (i == 1 and (L["Recipes"] .. "  ") or "      ") .. u.r.name .. " " .. GREY .. "(" .. u.r.prof .. ")|r", "× " .. u.need }
        end
        if #used > TOP_N then recipeLines[#recipeLines + 1] = { " ", GREY .. L["and %d more"]:format(#used - TOP_N) .. "|r" } end
        if #needers > 0 then charLines[#charLines + 1] = { L["Needed by"], Names(needers) } end
    end
    for _, r in ipairs(made) do
        charLines[#charLines + 1] = { L["Known by"] .. " " .. GREY .. "(" .. r.prof .. ")|r", Names(r.knownBy) }
        local known, learn = {}, {}
        for _, rec in ipairs(r.knownBy) do known[rec.key] = true end
        for _, rec in ipairs(ns.Acc.Chars()) do
            if not known[rec.key] and rec.recipes and rec.recipes[r.prof] then
                for _, sk in ipairs(rec.skills or {}) do
                    if sk.name == r.prof then learn[#learn + 1] = rec end
                end
            end
        end
        if #learn > 0 then charLines[#charLines + 1] = { L["Could still learn it"], Names(learn) } end
        break
    end
    return charLines, recipeLines
end

-- crafting in short: the professions that use the item as a material, and those that make it, with the number of
-- recipes. From the recipe data of the game (Data/Recipes.lua), so it does not depend on what your characters know.
local craftIndex
local function CraftIndex()
    if craftIndex then return craftIndex end
    craftIndex = { mat = {}, make = {} }
    for prof, list in pairs(ns.RecipeDB and ns.RecipeDB.professions or {}) do
        for _, r in ipairs(list) do
            if r[2] > 0 then
                local t = craftIndex.make[r[2]] or {}
                craftIndex.make[r[2]] = t
                t[prof] = (t[prof] or 0) + 1
            end
            local re, seen = r[6], {}
            for i = 1, #re, 2 do
                local rid = re[i]
                if not seen[rid] then
                    seen[rid] = true
                    local t = craftIndex.mat[rid] or {}
                    craftIndex.mat[rid] = t
                    t[prof] = (t[prof] or 0) + 1
                end
            end
        end
    end
    return craftIndex
end

-- the professions as small pictures, each with its number of recipes ("(picture) 12  (picture) 4"); a profession
-- without a picture is written out
local function ProfList(t)
    local arr = {}
    for p, n in pairs(t) do arr[#arr + 1] = { p = p, n = n } end
    table.sort(arr, function(a, b)
        if a.n ~= b.n then return a.n > b.n end
        return a.p < b.p
    end)
    local parts = {}
    for i = 1, math.min(4, #arr) do
        local icon = ns.Acc and ns.Acc.ProfIcon and ns.Acc.ProfIcon(arr[i].p)
        local label = icon and ("|T" .. icon .. ":14:14:0:0:64:64:5:59:5:59|t") or L[arr[i].p]
        parts[#parts + 1] = label .. " " .. arr[i].n
    end
    if #arr > 4 then parts[#parts + 1] = GREY .. "+" .. (#arr - 4) .. "|r" end
    return table.concat(parts, "   ")
end

local function CraftSummary(id)
    local lines = {}
    local idx = CraftIndex()
    local mat, make = idx.mat[id], idx.make[id]
    if not (mat or make) then return lines end
    lines[#lines + 1] = { head = L["Crafting"] }
    if mat then lines[#lines + 1] = { L["Used in"], ProfList(mat) } end
    if make then lines[#lines + 1] = { L["Made by"], ProfList(make) } end
    return lines
end

-- disenchanting: the materials an item gives, with chance, amount and what that is worth (data/disenchant.lua)
-- A block of the tooltip that fails must not take the others with it: it is skipped, and said once what went wrong.
local reported = {}
local function Try(name, fn, ...)
    local ok, a, b = pcall(fn, ...)
    if ok then return a, b end
    if not reported[name] then
        reported[name] = true
        print("|cffffd100ForeverCompanion:|r tooltip (" .. name .. "): " .. tostring(a))
    end
    return {}, {}
end

-- The materials of disenchanting (dusts, essences, shards, crystals) are asked for at login, so that their names are there
-- when a tooltip needs them; the last known name, rarity and picture are also kept in the saved variables, and a tooltip
-- never waits for the game to load an item.
local function MatInfo(id)
    local GetInfo = GetItemInfo or (C_Item and C_Item.GetItemInfo)
    local keep = ns.db and ns.db.deMats
    if ns.db and (not keep or keep.lang ~= GetLocale()) then
        keep = { lang = GetLocale() }
        ns.db.deMats = keep
    end
    local name, _, q, _, _, _, _, _, _, icon = GetInfo(id)
    if name then
        if keep then keep[id] = { name, q, icon } end
        return name, q, icon
    end
    if C_Item and C_Item.RequestLoadItemDataByID then pcall(C_Item.RequestLoadItemDataByID, id) end
    local k = keep and keep[id]
    if k then return k[1], k[2], k[3] end
end

local function PreloadMaterials()
    local seen = {}
    for _, list in pairs(ns.DisenchantDB or {}) do
        for _, e in ipairs(list) do
            local res = e[3]
            for i = 1, #res, 4 do seen[res[i]] = true end
        end
    end
    for id in pairs(seen) do MatInfo(id) end
end
local preload = CreateFrame("Frame")
preload:RegisterEvent("PLAYER_LOGIN")
preload:SetScript("OnEvent", function(_, event)
    if event == "PLAYER_LOGIN" then
        -- a little after login (the game is busy then), and once more for what had not arrived by then
        C_Timer.After(6, PreloadMaterials)
        C_Timer.After(25, PreloadMaterials)
        preload:UnregisterEvent("PLAYER_LOGIN")
    end
end)

local function DisenchantLines(id)
    local lines = {}
    local db = ns.DisenchantDB
    if not db then return lines end
    local GetInfo = GetItemInfo or (C_Item and C_Item.GetItemInfo)
    local _, _, quality, ilvl, _, _, _, _, equipLoc, _, sell, class = GetInfo(id)
    if not (quality and ilvl and (class == 2 or class == 4)) then return lines end
    if quality < 2 or quality > 4 or equipLoc == "INVTYPE_BODY" or equipLoc == "INVTYPE_TABARD" then return lines end
    local group = quality == 3 and "rare" or (quality == 4 and "epic" or (class == 2 and "weapon" or "armor"))
    local res
    for _, e in ipairs(db[group] or {}) do
        if (e[1] == "<=" and ilvl <= e[2]) or (e[1] == "==" and ilvl == e[2]) then res = e[3]; break end
    end
    if not res then return lines end
    local V, total, rows = ns.Value, 0, {}
    for i = 1, #res, 4 do
        local mid, chance, lo, hi = res[i], res[i + 1], res[i + 2], res[i + 3]
        local name, q, icon = MatInfo(mid)
        local unit = V.AuctionPrice(mid) or V.Vendor(mid) or 0
        total = total + chance / 100 * (lo + hi) / 2 * unit
        local col = ITEM_QUALITY_COLORS and ITEM_QUALITY_COLORS[q or 1]
        local label = name or ("item:" .. mid)
        if col then label = ("|cff%02x%02x%02x%s|r"):format(col.r * 255 + 0.5, col.g * 255 + 0.5, col.b * 255 + 0.5, label) end
        local pic = icon and ("|T" .. icon .. ":14:14:0:0:64:64:5:59:5:59|t ") or ""
        local qty = lo == hi and tostring(lo) or (lo .. "-" .. hi)
        rows[#rows + 1] = { pic .. label .. " " .. GREY .. ("%g"):format(chance) .. " %|r",
            qty .. (unit > 0 and (" × " .. Money(unit)) or "") }
    end
    total = math.floor(total + 0.5)
    lines[#lines + 1] = { head = L["Disenchanting"], right = total > 0 and ("Ø " .. Money(total)) or nil }
    for _, r in ipairs(rows) do lines[#lines + 1] = r end
    -- against selling the item as it is
    -- (the better of the two ways: to a vendor, or on the auction house after its fee of 5 %)
    local ah = ns.Value.AuctionPrice(id)
    local direct = math.max(ah and math.floor(ah * 0.95) or 0, sell or 0)
    if total > 0 and direct > 0 then
        local pct = (total - direct) / direct * 100
        lines[#lines + 1] = { L["Against selling it"], (pct >= 0 and GREEN or RED) .. ("%+d %%"):format(pct + (pct >= 0 and 0.5 or -0.5)) .. "|r" }
    end
    return lines
end

-- the expected value of disenchanting an item, in copper (nil when it cannot be done or the item is not known yet); for the
-- lists of the auction house tab
function ns.DisenchantValue(id)
    local db = ns.DisenchantDB
    if not db then return nil end
    local GetInfo = GetItemInfo or (C_Item and C_Item.GetItemInfo)
    local _, _, quality, ilvl, _, _, _, _, equipLoc, _, _, class = GetInfo(id)
    if not (quality and ilvl and (class == 2 or class == 4)) then return nil end
    if quality < 2 or quality > 4 or equipLoc == "INVTYPE_BODY" or equipLoc == "INVTYPE_TABARD" then return nil end
    local group = quality == 3 and "rare" or (quality == 4 and "epic" or (class == 2 and "weapon" or "armor"))
    local res
    for _, e in ipairs(db[group] or {}) do
        if (e[1] == "<=" and ilvl <= e[2]) or (e[1] == "==" and ilvl == e[2]) then res = e[3]; break end
    end
    if not res then return nil end
    local V, total = ns.Value, 0
    for i = 1, #res, 4 do
        local unit = V.AuctionPrice(res[i]) or V.Vendor(res[i]) or 0
        total = total + res[i + 1] / 100 * (res[i + 2] + res[i + 3]) / 2 * unit
    end
    return total > 0 and math.floor(total + 0.5) or nil
end

local function ItemLines(id, count)
    local lines = {}
    -- the price of one piece; with Shift held, of the whole stack the tooltip is about
    local canStack = ns.TipOn("itemStack") and count > 1
    local stack = canStack and IsShiftKeyDown()
    local function Price(unit, tint)
        return Money(stack and (unit * count) or unit, tint)
    end
    local V = ns.Value
    local vendor = V.Vendor(id)
    local price, source, since = V.AuctionPrice(id)
    local showVendor = ns.TipOn("itemVendor") and vendor > 0
    local showAuction = ns.TipOn("itemAuction") and price

    -- prices: vendor and auction, then the profit (or loss) of the auction price, and in percent
    if showVendor or showAuction then
        local note
        if showAuction then
            note = source == "own" and L["own scan"] or "Auctionator"
            if ns.TipOn("itemAge") and since then note = note .. "  ·  " .. ns.Ago(since) end
        end
        -- the stack is a toggle: marked while it is on, a hint while it is off
        local mark = stack and (" " .. GREY .. "x" .. count .. "|r") or ""
        if canStack and not stack then note = (note and (note .. "  ·  ") or "") .. L["Shift: stack"] .. " x" .. count end
        lines[#lines + 1] = { head = L["Prices"] .. mark, right = note }
        if showVendor then
            lines[#lines + 1] = { L["Vendor"], Price(vendor) }
        end
        if showAuction then
            lines[#lines + 1] = { L["Auction"], Price(price) }
        end
        if ns.TipOn("itemDiff") and showAuction and vendor > 0 then
            local diff = price - vendor
            local pct = diff / vendor * 100
            local col = diff >= 0 and GREEN or RED
            -- (above a thousand percent the exact figure does not tell anything any more)
            local text = pct > 1000 and ">1000 %" or ("%+d %%"):format(pct + (pct >= 0 and 0.5 or -0.5))
            lines[#lines + 1] = { diff >= 0 and L["Profit"] or L["Loss"], col .. text .. "|r" }
        end
    end

    -- the auction trend of the last week: the price of a piece and what is on offer, as small bars
    if ns.TipOn("itemTrend") and ns.AH and ns.AH.Trend then
        if ns.AH.Enabled() then ns.AH.Watch(id) end
        local price, qty, avg, days = ns.AH.Trend(id, 7)
        local pbars = price and Bars(price)
        if pbars then
            lines[#lines + 1] = { head = L["Auction trend"], right = (L["%d days of data"]):format(days) }
            -- how the price moved over the days shown (cheaper is green, dearer amber, as in the lists)
            local pf, pl
            for i = 1, #price do if price[i] > 0 then pf = pf or price[i]; pl = price[i] end end
            local pchange = (pf and pl and pf > 0) and ((pl - pf) / pf * 100) or nil
            local pcol = pchange and (pchange > 0.5 and AMBER or (pchange < -0.5 and GREEN or GREY)) or GREY
            local ptext = pchange and (" " .. pcol .. ("%+d %%"):format(pchange + (pchange >= 0 and 0.5 or -0.5)) .. "|r") or ""
            lines[#lines + 1] = { L["Price"] .. " " .. GREY .. "(" .. L["avg"] .. " " .. "|r" .. Money(avg) .. GREY .. ")|r" .. ptext, pbars }
            local qbars = Bars(qty)
            if qbars then
                local first, last
                for i = 1, #qty do if qty[i] > 0 then first = first or qty[i]; last = qty[i] end end
                local change = (first and last and first > 0) and ((last - first) / first * 100) or nil
                local col = change and (change > 0 and AMBER or GREEN) or GREY
                lines[#lines + 1] = { L["Supply"] .. " " .. GREY .. "(" .. (last or 0) .. ")|r" .. (change and (" " .. col .. ("%+d %%"):format(change + (change >= 0 and 0.5 or -0.5)) .. "|r") or ""), qbars }
            end
            -- demand, worked out from how the offers fell between the scans (a rough guide), and how long the stock lasts
            local perDay = ns.AH.Demand and ns.AH.Demand(id, 7)
            if perDay then
                local text = perDay < 0.5 and "<1/d" or (perDay < 10 and ("%.1f/d"):format(perDay) or ("%d/d"):format(math.floor(perDay + 0.5)))
                local rate = ns.AH.DemandSeries and ns.AH.DemandSeries(id, 7)
                local dbars = rate and Bars(rate)
                local dchange
                if rate then
                    local f, l
                    for i = 1, #rate do if rate[i] > 0 then f = f or rate[i]; l = rate[i] end end
                    if f and l and f > 0 then dchange = (l - f) / f * 100 end
                end
                local dcol = dchange and (dchange > 0.5 and GREEN or (dchange < -0.5 and AMBER or GREY)) or GREY
                lines[#lines + 1] = { L["Demand"] .. " " .. GREY .. "(" .. text .. ")|r"
                    .. (dchange and (" " .. dcol .. ("%+d %%"):format(dchange + (dchange >= 0 and 0.5 or -0.5)) .. "|r") or ""), dbars or text }
            end
        end
    end

    -- what you looted of it (only while the session window is open: otherwise the tooltip is not about loot)
    local gi = ns.db.items[id]
    local sessionOpen = ns.HUD and ns.HUD.frame and ns.HUD.frame:IsShown()
    if gi and sessionOpen and ns.TipOn("itemOwned") then
        local si = ns.session and ns.session.items[id]
        local unit = V.Get(id)
        lines[#lines + 1] = { head = L["Your loot"] }
        lines[#lines + 1] = { L["This session / total"], ("%d / %d"):format(si and si.count or 0, gi.count) }
        if unit > 0 then lines[#lines + 1] = { L["Worth"], Money(unit * gi.count) } end
    end

    -- where it drops: the best three, with level and place
    if gi and ns.TipOn("itemSources") then
        local list = {}
        for key, qty in pairs(gi.sources or {}) do
            local gm = ns.db.mobs[key]
            if gm then
                local pct = ns.DropChance(gm, id)
                list[#list + 1] = { gm = gm, qty = qty, pct = pct or 0 }
            end
        end
        table.sort(list, function(a, b)
            if a.pct ~= b.pct then return a.pct > b.pct end
            return a.qty > b.qty
        end)
        -- (not for what only comes from nodes: herbs and ore have no creature to name)
        local fromCreature = false
        for _, e in ipairs(list) do
            if e.gm.cat == "mob" or e.gm.cat == "skin" then fromCreature = true break end
        end
        if #list > 0 and fromCreature then
            lines[#lines + 1] = { head = L["Drops from"], right = #list > TOP_N and (L["top %d of %d"]):format(TOP_N, #list) or nil }
            for i = 1, math.min(TOP_N, #list) do
                local e = list[i]
                local lo, hi = e.gm.minLevel or e.gm.level, e.gm.maxLevel or e.gm.level
                local where = {}
                if lo then where[#where + 1] = L["Lv"] .. " " .. (lo == hi and lo or (lo .. "-" .. hi)) end
                if e.gm.zone and e.gm.zone ~= "" then where[#where + 1] = e.gm.zone end
                lines[#lines + 1] = { (e.gm.name or "?") .. (#where > 0 and (" " .. GREY .. table.concat(where, " · ") .. "|r") or ""),
                    e.pct > 0 and ("%d %%"):format(e.pct + 0.5) or ("%dx"):format(e.qty) }
            end
        end
    end

    -- the characters: who has it, and crafting
    if ns.TipOn("itemDisenchant") then
        for _, ln in ipairs(Try("disenchant", DisenchantLines, id)) do lines[#lines + 1] = ln end
    end
    if ns.TipOn("itemCraft") then
        -- the professions as pictures; then, for the characters, who needs it, who knows how to make it, who could learn it
        local summary = Try("crafting", CraftSummary, id)
        local charLines, recipeLines = {}, {}
        if ns.Acc and ns.Acc.Enabled() then charLines, recipeLines = Try("crafting characters", CraftLines, id) end
        -- the recipes that use the item are only listed while Shift is held (the tooltip is redrawn when it is pressed)
        local shift = IsShiftKeyDown()
        if #summary == 0 and (#charLines > 0 or (shift and #recipeLines > 0)) then
            summary[1] = { head = L["Crafting"] }
        end
        if summary[1] and summary[1].head and #recipeLines > 0 and not shift then
            summary[1].right = GREY .. L["Shift: recipes"] .. "|r"
        end
        for _, ln in ipairs(summary) do lines[#lines + 1] = ln end
        if shift then
            for _, ln in ipairs(recipeLines) do lines[#lines + 1] = ln end
        end
        for _, ln in ipairs(charLines) do lines[#lines + 1] = ln end
    end
    if ns.Acc and ns.Acc.Enabled() then
        if ns.TipOn("itemAlts") then
            local owners = ns.Acc.Owners(id)
            if #owners > 0 then
                lines[#lines + 1] = { head = L["Your characters"] }
                for i = 1, math.min(5, #owners) do
                    local o = owners[i]
                    local bits = {}
                    if o.equip > 0 then bits[#bits + 1] = L["worn"] end
                    if o.bags > 0 then bits[#bits + 1] = o.bags .. " " .. L["bags"] end
                    if o.bank > 0 then bits[#bits + 1] = o.bank .. " " .. L["bank"] end
                    if o.mail > 0 then bits[#bits + 1] = o.mail .. " " .. L["mail"] end
                    if o.auction > 0 then bits[#bits + 1] = o.auction .. " " .. L["auction"] end
                    lines[#lines + 1] = { ClassName(o.rec), GREY .. table.concat(bits, ", ") .. "|r" }
                end
                if #owners > 5 then lines[#lines + 1] = { " ", GREY .. L["and %d more"]:format(#owners - 5) .. "|r" } end
            end
        end
    end
    -- until the auction house has been visited (a scan is stored): a hint, as much of this only shows when items are hovered there
    if not (ns.AH and ns.AH.Time and ns.AH.Time() and not (ns.AH.Seeded and ns.AH.Seeded())) then
        table.insert(lines, 1, { AMBER .. L["Visit the auction house: much more is shown here once you have hovered items there."] .. "|r" })
    end
    return lines
end

local function OnItem(tt, id)
    if tt.fcDone or not Allowed() then return end
    id = ns.ReadableNumber(id)
    if not id then return end
    tt.fcDone = true
    local ok, lines = pcall(ItemLines, id, StackCount(tt))
    if not ok then
        if not reported.item then reported.item = true; print("|cffffd100ForeverCompanion:|r tooltip: " .. tostring(lines)) end
        return
    end
    Finish(tt, lines)
end
-- for windows that fill a tooltip themselves (the auction house tab): add our lines for this item, once
ns.TipItem = OnItem

-- creatures ----------------------------------------------------------------------------------
-- a creature: one line with the kills and what a kill is worth, then the best drops (a title line of
-- their own when there are several, else on one line)
local function MobLines(gm, name)
    local lines = {}
    local kills = gm.kills or 0
    local list, total = {}, ns.MoneyOn() and (gm.money or 0) or 0
    for id, count in pairs(ns.MergedItems(gm)) do
        local unit = ns.Value.Get(id)
        total = total + unit * count
        local pct = ns.DropChance(gm, id)
        if pct and unit > 0 then list[#list + 1] = { id = id, unit = unit, pct = pct, expect = unit * pct / 100 } end
    end

    local left = ns.TipOn("mobKills") and (L["Killed"] .. " " .. kills) or nil
    local right = (ns.TipOn("mobAvg") and kills > 0 and total > 0) and (Money(total / kills) .. " " .. GREY .. L["per kill"] .. "|r") or nil
    if left or right then lines[#lines + 1] = { left or L["Value per kill"], right } end

    if ns.TipOn("mobProgress") then
        local thr, have = ns.Threshold(), gm.tracked or kills
        if have < thr then
            lines[#lines + 1] = { L["Drop chances"], AMBER .. ("%d / %d"):format(have, thr) .. "|r " .. GREY .. L["kills"] .. "|r" }
        else
            lines[#lines + 1] = { L["Drop chances"], GREEN .. L["known"] .. "|r " .. GREY .. ("(%d %s)"):format(have, L["kills"]) .. "|r" }
        end
    end

    if ns.TipOn("mobTop") and #list > 0 then
        table.sort(list, function(a, b) return a.expect > b.expect end)
        local n = math.min(TOP_N, #list)
        local function Entry(e)
            local gi = ns.db.items[e.id]
            return (gi and gi.link) or ("item:" .. e.id), ("%d %%"):format(e.pct + 0.5) .. "  " .. Money(e.unit)
        end
        if n == 1 then
            local item, info = Entry(list[1])
            lines[#lines + 1] = { L["Best drops"] .. ": " .. item, info }
        else
            lines[#lines + 1] = { GOLD_HEX .. L["Best drops"] .. "|r" }
            for i = 1, n do
                local item, info = Entry(list[i])
                lines[#lines + 1] = { "  " .. item, info }
            end
        end
    end
    return lines
end

local function OnUnit(tt)
    if tt.fcDone or not Allowed() then return end
    local ok, name, unit = pcall(tt.GetUnit, tt)
    if not ok or not unit then return end
    local isPlayer = pcall(UnitIsPlayer, unit) and UnitIsPlayer(unit)
    if isPlayer then return end
    name = ns.Readable(UnitName(unit))
    local gm = name and ns.db.mobs[name]
    if not gm or gm.cat ~= "mob" then return end
    tt.fcDone = true
    Finish(tt, MobLines(gm, name))
end

-- resources (herbs, veins, other nodes): has it been gathered, here and in general, when last, and what it gives -------------------
local NODE_CATS = { "herb", "ore", "object" }
local NEAR_YARDS = 60

local function NodeRecord(name)
    for _, cat in ipairs(NODE_CATS) do
        local gm = ns.db.mobs[cat .. ":" .. name]
        if gm and gm.cat == cat and (gm.kills or 0) > 0 and ns.CatOn(cat) then return gm end
    end
end

local function NodeLines(gm, spot)
    local lines = {}
    local kills = gm.kills or 0
    local spots, last, nearest, nearestD = 0, nil, nil, nil
    local mapID, px, py = ns.PlayerPos()
    local w, h
    if mapID then w, h = ns.WorldSize(mapID) end
    for _, sp in pairs(gm.spots or {}) do
        spots = spots + 1
        if sp.t and (not last or sp.t > last) then last = sp.t end
        if mapID and sp.m == mapID and w and h then
            local dx, dy = (sp.x - px) * w, (sp.y - py) * h
            local d = math.sqrt(dx * dx + dy * dy)
            if d <= NEAR_YARDS and (not nearestD or d < nearestD) then nearest, nearestD = sp, d end
        end
    end
    if spot then nearest = spot end -- (a place that is known: a pin of the minimap)
    if ns.TipOn("nodeVisited") then
        lines[#lines + 1] = { head = L["Resource"] }
        if nearest then
            lines[#lines + 1] = { L["This spot"], GREEN .. (L["visited %dx"]):format(nearest.n or 1) .. "|r" .. (nearest.t and (" " .. GREY .. "· " .. ns.Ago(nearest.t) .. "|r") or "") }
        elseif mapID then
            lines[#lines + 1] = { L["This spot"], AMBER .. L["not saved yet"] .. "|r" }
        end
        lines[#lines + 1] = { L["Known spots"], tostring(spots) .. (last and (" " .. GREY .. "· " .. L["last"] .. " " .. ns.Ago(last) .. "|r") or "") }
    end
    local list, total = {}, ns.MoneyOn() and (gm.money or 0) or 0
    for id, count in pairs(gm.items or {}) do
        local unit = ns.Value.Get(id)
        total = total + unit * count
        local pct = ns.DropChance(gm, id)
        if pct and unit > 0 then list[#list + 1] = { id = id, unit = unit, pct = pct, expect = unit * pct / 100 } end
    end
    if ns.TipOn("nodeGathered") then
        lines[#lines + 1] = { L["Gathered"], kills .. "x" .. (kills > 0 and total > 0 and (" " .. GREY .. "· " .. Money(total / kills) .. " " .. L["each"] .. "|r") or "") }
    end
    if ns.TipOn("nodeDrops") and #list > 0 then
        table.sort(list, function(a, b) return a.expect > b.expect end)
        lines[#lines + 1] = { GOLD_HEX .. L["Gives"] .. "|r" }
        for i = 1, math.min(TOP_N, #list) do
            local e = list[i]
            local gi = ns.db.items[e.id]
            lines[#lines + 1] = { "  " .. ((gi and gi.link) or ("item:" .. e.id)), ("%d %%"):format(e.pct + 0.5) .. "  " .. Money(e.unit) }
        end
    end
    return lines
end

-- The tooltip of a resource as it is in the world, for a pin of the minimap: its name, and the lines of the settings for nodes (the
-- place is the one of the pin). Returns true when it made one (the caller shows it).
function ns.TipNodeFor(tt, key, spot, noName)
    local gm = ns.db and ns.db.mobs[key]
    if not gm or gm.cat == "mob" then return false end
    local col = ns.CAT[gm.cat] and ns.CAT[gm.cat].color or { 1, 1, 1 }
    if not noName then tt:AddLine(gm.name or key, col[1], col[2], col[3]) end
    if ns.TipOn("master") then
        local ok, lines = pcall(NodeLines, gm, spot)
        if ok then Finish(tt, lines) end
    end
    return true
end

local function OnObject(tt)
    if tt.fcDone or not Allowed() or not ns.db then return end
    local line = tt.GetName and tt:GetName() and _G[tt:GetName() .. "TextLeft1"]
    local name = line and ns.Readable(line:GetText())
    if not name or name == "" then return end
    local gm = NodeRecord(name)
    if not gm then return end
    tt.fcDone = true
    local ok, lines = pcall(NodeLines, gm)
    if ok then Finish(tt, lines) end
end

-- hooks: the newer tooltip system when there is one, the older script events otherwise ---------
local tips = { GameTooltip, ItemRefTooltip }
for _, tt in ipairs(tips) do
    if tt and tt.HookScript then
        pcall(tt.HookScript, tt, "OnTooltipCleared", function(self) self.fcDone = nil end)
    end
end

if TooltipDataProcessor and TooltipDataProcessor.AddTooltipPostCall and Enum and Enum.TooltipDataType then
    TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Item, function(tt, data)
        if tt ~= GameTooltip and tt ~= ItemRefTooltip then return end
        OnItem(tt, data and data.id)
    end)
    TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Unit, function(tt)
        if tt ~= GameTooltip then return end
        OnUnit(tt)
    end)
    if Enum.TooltipDataType.Object then
        TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Object, function(tt)
            if tt ~= GameTooltip then return end
            OnObject(tt)
        end)
    end
else
    for _, tt in ipairs(tips) do
        if tt and tt.HookScript then
            pcall(tt.HookScript, tt, "OnTooltipSetItem", function(self)
                local _, link = self:GetItem()
                OnItem(self, link and tonumber(link:match("item:(%d+)")))
            end)
        end
    end
    if GameTooltip then
        pcall(GameTooltip.HookScript, GameTooltip, "OnTooltipSetUnit", OnUnit)
        -- (a node is neither a unit nor an item: its name is looked up when the tooltip is shown)
        pcall(GameTooltip.HookScript, GameTooltip, "OnShow", function(self)
            local _, unit = self:GetUnit()
            if not unit and not (self.GetItem and self:GetItem()) then OnObject(self) end
        end)
    end
end

-- pressing or letting go of Shift redraws the tooltip of an item, so that its price follows (one piece / the stack)
local shiftWatch = CreateFrame("Frame")
shiftWatch:RegisterEvent("MODIFIER_STATE_CHANGED")
shiftWatch:SetScript("OnEvent", function(_, _, key)
    if key ~= "LSHIFT" and key ~= "RSHIFT" then return end
    if not (GameTooltip and GameTooltip:IsShown() and GameTooltip.fcDone) then return end
    local owner = GameTooltip:GetOwner()
    local enter = owner and owner.GetScript and owner:GetScript("OnEnter")
    if enter then pcall(enter, owner) end
end)

-- A tooltip with made-up data, for the settings page: the same lines, switched by the same options, so that a change can be seen at once.
-- kind: "item" or "mob". (The shift options do not hide anything here: the settings say so.)
local function Change(values)
    local first, last
    for _, v in ipairs(values) do if v > 0 then first = first or v; last = v end end
    return (first and last and first > 0) and ((last - first) / first * 100) or nil
end
local function Pct(v) return ("%+d %%"):format(v + (v >= 0 and 0.5 or -0.5)) end

local function SampleItemLines()
    local lines = {}
    local count, vendor, price = 20, 12000, 31500
    local canStack = ns.TipOn("itemStack")
    local showVendor, showAuction = ns.TipOn("itemVendor"), ns.TipOn("itemAuction")
    if showVendor or showAuction then
        local note
        if showAuction then
            note = L["own scan"]
            if ns.TipOn("itemAge") then note = note .. "  ·  " .. ns.Ago(time() - 7200) end
        end
        if canStack then note = (note and (note .. "  ·  ") or "") .. L["Shift: stack"] .. " x" .. count end
        lines[#lines + 1] = { head = L["Prices"], right = note }
        if showVendor then lines[#lines + 1] = { L["Vendor"], Money(vendor) } end
        if showAuction then lines[#lines + 1] = { L["Auction"], Money(price) } end
        if ns.TipOn("itemDiff") and showAuction and showVendor then
            local pct = (price - vendor) / vendor * 100
            lines[#lines + 1] = { L["Profit"], GREEN .. Pct(pct) .. "|r" }
        end
    end
    if ns.TipOn("itemTrend") then
        local pr = { 28000, 30000, 29000, 31000, 33000, 32000, 31500 }
        local qty = { 40, 36, 38, 31, 29, 33, 27 }
        local dem = { 4, 6, 5, 7, 6, 8, 9 }
        lines[#lines + 1] = { head = L["Auction trend"], right = (L["%d days of data"]):format(7) }
        local pc = Change(pr)
        local pcol = pc > 0.5 and AMBER or (pc < -0.5 and GREEN or GREY)
        lines[#lines + 1] = { L["Price"] .. " " .. GREY .. "(" .. L["avg"] .. " " .. "|r" .. Money(30500) .. GREY .. ")|r " .. pcol .. Pct(pc) .. "|r", Bars(pr) }
        local qc = Change(qty)
        lines[#lines + 1] = { L["Supply"] .. " " .. GREY .. "(27)|r " .. (qc > 0 and AMBER or GREEN) .. Pct(qc) .. "|r", Bars(qty) }
        local dc = Change(dem)
        lines[#lines + 1] = { L["Demand"] .. " " .. GREY .. "(9/d)|r " .. (dc > 0 and GREEN or AMBER) .. Pct(dc) .. "|r", Bars(dem) }
    end
    if ns.TipOn("itemOwned") then
        lines[#lines + 1] = { head = L["Your loot"] }
        lines[#lines + 1] = { L["This session / total"], "3 / 41" }
        lines[#lines + 1] = { L["Worth"], Money(price * 41) }
    end
    if ns.TipOn("itemSources") then
        lines[#lines + 1] = { head = L["Drops from"], right = (L["top %d of %d"]):format(3, 5) }
        for _, e in ipairs({ { "Rotfang Gnoll", "12-14", "Westfall", "18 %" }, { "Defias Pillager", "13-15", "Westfall", "11 %" },
            { "Young Wolf", "9-11", "Elwynn Forest", "6 %" } }) do
            lines[#lines + 1] = { e[1] .. " " .. GREY .. L["Lv"] .. " " .. e[2] .. " · " .. e[3] .. "|r", e[4] }
        end
    end
    if ns.TipOn("itemDisenchant") then
        lines[#lines + 1] = { head = L["Disenchanting"], right = "Ø " .. Money(2400) }
        lines[#lines + 1] = { "|TInterface\\Icons\\INV_Misc_Dust_02:14:14:0:0:64:64:5:59:5:59|t " .. "|cff1eff00Strange Dust|r " .. GREY .. "75 %|r", "1-2 × " .. Money(300) }
        lines[#lines + 1] = { "|TInterface\\Icons\\INV_Enchant_EssenceMagicLarge:14:14:0:0:64:64:5:59:5:59|t " .. "|cff1eff00Greater Magic Essence|r " .. GREY .. "20 %|r", "1 × " .. Money(1800) }
        lines[#lines + 1] = { "|TInterface\\Icons\\INV_Enchant_ShardGlimmeringSmall:14:14:0:0:64:64:5:59:5:59|t " .. "|cff0070ddSmall Glimmering Shard|r " .. GREY .. "5 %|r", "1 × " .. Money(2500) }
        lines[#lines + 1] = { L["Against selling it"], GREEN .. "+12 %|r" }
    end
    if ns.TipOn("itemCraft") then
        lines[#lines + 1] = { head = L["Crafting"], right = GREY .. L["Shift: recipes"] .. "|r" }
        lines[#lines + 1] = { L["Used in"], ProfList({ Blacksmithing = 12, Engineering = 4 }) }
        lines[#lines + 1] = { L["Made by"], ProfList({ Alchemy = 1 }) }
        lines[#lines + 1] = { L["Needed by"], "|cffc79c6eThordek|r, |cff69ccf0Mirelle|r" }
        lines[#lines + 1] = { L["Known by"] .. " " .. GREY .. "(Alchemy)|r", "|cff69ccf0Mirelle|r" }
    end
    if ns.TipOn("itemAlts") then
        lines[#lines + 1] = { head = L["Your characters"] }
        lines[#lines + 1] = { "|cffc79c6eThordek|r", GREY .. "3 " .. L["bags"] .. ", 1 " .. L["bank"] .. "|r" }
        lines[#lines + 1] = { "|cff69ccf0Mirelle|r", GREY .. "2 " .. L["mail"] .. "|r" }
    end
    return lines
end

local function SampleMobLines()
    local lines = {}
    local left = ns.TipOn("mobKills") and (L["Killed"] .. " 64") or nil
    local right = ns.TipOn("mobAvg") and (Money(14200) .. " " .. GREY .. L["per kill"] .. "|r") or nil
    if left or right then lines[#lines + 1] = { left or L["Value per kill"], right } end
    if ns.TipOn("mobProgress") then
        lines[#lines + 1] = { L["Drop chances"], AMBER .. "64 / 100|r " .. GREY .. L["kills"] .. "|r" }
    end
    if ns.TipOn("mobTop") then
        lines[#lines + 1] = { GOLD_HEX .. L["Best drops"] .. "|r" }
        for _, e in ipairs({ { "|cff0070ddMithril Ore|r", "9 %", 4200 }, { "|cff1eff00Green Hills of Stranglethorn|r", "14 %", 1800 },
            { "|cffffffffLinen Cloth|r", "42 %", 150 } }) do
            lines[#lines + 1] = { "  " .. e[1], e[2] .. "  " .. Money(e[3]) }
        end
    end
    return lines
end

-- all: as if every option were on (to measure the largest the tooltip can get)
local function SampleNodeLines()
    local lines = {}
    if ns.TipOn("nodeVisited") then
        lines[#lines + 1] = { head = L["Resource"] }
        lines[#lines + 1] = { L["This spot"], GREEN .. (L["visited %dx"]):format(7) .. "|r " .. GREY .. "· " .. ns.Ago(time() - 5400) .. "|r" }
        lines[#lines + 1] = { L["Known spots"], "12 " .. GREY .. "· " .. L["last"] .. " " .. ns.Ago(time() - 600) .. "|r" }
    end
    if ns.TipOn("nodeGathered") then
        lines[#lines + 1] = { L["Gathered"], "58x " .. GREY .. "· " .. Money(2300) .. " " .. L["each"] .. "|r" }
    end
    if ns.TipOn("nodeDrops") then
        lines[#lines + 1] = { GOLD_HEX .. L["Gives"] .. "|r" }
        for _, e in ipairs({ { "|cffffffffPeacebloom|r", "100 %", 450 }, { "|cff1eff00Bruiseweed|r", "35 %", 900 },
            { "|cff1eff00Goldthorn|r", "8 %", 3200 } }) do
            lines[#lines + 1] = { "  " .. e[1], e[2] .. "  " .. Money(e[3]) }
        end
    end
    return lines
end

function ns.TipPreview(tt, kind, all)
    tt:ClearLines()
    if kind == "node" then
        tt:AddLine("Peacebloom", 1, 1, 1)
        tt:AddLine("Requires Herbalism", 1, 1, 1)
    elseif kind == "mob" then
        tt:AddLine("Rotfang Gnoll", 1, 0.82, 0)
        tt:AddLine("Level 14 Humanoid", 1, 1, 1)
    else
        tt:AddLine("Arcane Crystal", 0, 0.44, 0.87)
        tt:AddLine("Crafting Reagent", 1, 1, 1)
    end
    local real = ns.TipOn
    if all then ns.TipOn = function() return true end end
    local ok, err = pcall(function()
        if ns.TipOn("master") then
            Finish(tt, kind == "node" and SampleNodeLines() or (kind == "mob" and SampleMobLines() or SampleItemLines()))
        end
    end)
    ns.TipOn = real
    if not ok then error(err, 0) end
    tt:Show()
end
