local ADDON, ns = ...
local L = ns.L

local DB_VERSION = 2
local DEFAULT_THRESHOLD = 20

-- Source categories ------------------------------------------------------
-- Every loot source is a "mob", a gathering node, a skinned corpse, a catch,
-- a disenchant or some other object. The key of a source is its name for
-- mobs and "<cat>:<name>" for everything else.

ns.CATS = { "mob", "herb", "ore", "skin", "fish", "disenchant", "object" }
ns.CAT = {
    mob        = { label = L["Creatures"],  verb = L["Kills"],      icon = "Interface\\Icons\\INV_Sword_04",              color = { 0.90, 0.40, 0.32 } },
    herb       = { label = L["Herbalism"],  verb = L["Gathered"],   icon = "Interface\\Icons\\Trade_Herbalism",           color = { 0.40, 0.82, 0.40 } },
    ore        = { label = L["Mining"],     verb = L["Mined"],      icon = "Interface\\Icons\\Trade_Mining",              color = { 0.62, 0.72, 0.88 } },
    skin       = { label = L["Skinning"],   verb = L["Skinned"],    icon = "Interface\\Icons\\INV_Misc_Pelt_Wolf_01",     color = { 0.84, 0.62, 0.40 } },
    fish       = { label = L["Fishing"],    verb = L["Caught"],     icon = "Interface\\Icons\\Trade_Fishing",             color = { 0.32, 0.62, 0.92 } },
    disenchant = { label = L["Disenchanting"], verb = L["Broken down"], icon = "Interface\\Icons\\INV_Enchant_EssenceMagicLarge", color = { 0.72, 0.44, 0.92 } },
    object     = { label = L["Objects"],    verb = L["Opened"],     icon = "Interface\\Icons\\INV_Box_01",                color = { 0.84, 0.74, 0.52 } },
}

-- spell id -> category, read from UNIT_SPELLCAST_SENT
local SPELL_CAT = {}
local function Spells(cat, ...) for _, id in ipairs({ ... }) do SPELL_CAT[id] = cat end end
Spells("herb", 2366, 2368, 3570, 11993, 28695, 50300, 74519)
Spells("ore", 2575, 2576, 3564, 10248, 29354, 50310, 74517)
Spells("skin", 8613, 8617, 8618, 10768, 32678, 50305, 74522)
Spells("fish", 7620, 7731, 7732, 18248, 33095, 51294)
Spells("disenchant", 13262, 31252, 51005)
Spells("pocket", 921)

-- the same by the spell's name, for the ranks and clients whose ids are not in the lists above
local NAME_CAT = {
    mining = "ore", bergbau = "ore",
    ["herb gathering"] = "herb", herbalism = "herb", ["kräutersammeln"] = "herb", ["kräuterkunde"] = "herb",
    skinning = "skin", ["kürschnerei"] = "skin",
    fishing = "fish", angeln = "fish",
    disenchant = "disenchant", entzaubern = "disenchant",
}
local function GatherCat(spellID)
    local cat = SPELL_CAT[spellID]
    if cat then return cat end
    local name
    if C_Spell and C_Spell.GetSpellInfo then
        local info = C_Spell.GetSpellInfo(spellID)
        name = info and info.name
    elseif GetSpellInfo then
        name = GetSpellInfo(spellID)
    end
    if type(name) ~= "string" then return nil end
    name = name:lower():gsub("%s*%(.-%)", ""):gsub("%s+%d+$", ""):gsub("%s+$", "")
    return NAME_CAT[name]
end

-- /fc debug: what is seen while gathering (the cast, and how each loot slot was classified)
-- In combat the client hides some values (names, guids): they read as nothing. The debug says "hidden"
-- instead of "nil" for them, so it is clear that this is the client and not a gap in the addon.
local function Dbg(...)
    if not (ns.db and ns.db.debug) then return end
    local parts = {}
    for i = 1, select("#", ...) do
        local v = select(i, ...)
        parts[i] = (v == nil or v == "nil") and "hidden" or tostring(v)
    end
    print("|cffffd100FC debug:|r", table.concat(parts, " "))
end

local QUALITY_BY_COLOR = {
    ["9d9d9d"] = 0, ["ffffff"] = 1, ["1eff00"] = 2,
    ["0070dd"] = 3, ["a335ee"] = 4, ["ff8000"] = 5, ["e6cc80"] = 6,
}
local CLASS_WEAPON, CLASS_ARMOR = 2, 4

local GetInstant = (C_Item and C_Item.GetItemInfoInstant) or GetItemInfoInstant

local nameCache, nameCount = {}, 0
local levelCache = {}
local classCache = {} -- creature guid -> "normal" | "elite" | "rare" | "boss"
local lastGather = nil -- { cat, target, time }
local lastWindowAt = -100 -- when a loot window last opened
local lastTarget = nil -- { name, time }: the last creature targeted, while its name could be read
local lootDone = false
local lootWindow = 0
local seenOnce = {} -- identity -> true, so one corpse/node counts once
local seq = 0

local function NextSeq() seq = seq + 1; return seq end

-- Forever hands out "secret values" in places; reading one raises an error.
-- These return a plain copy or nil (same approach as Blackthornes_Farmer).
local function CopyText(v) local t = v .. ""; if t == "" then return nil end return t end
local function CopyNumber(v) local n = v + 0; if n ~= n then return nil end return n end
local function Readable(v)
    local kind = type(v)
    if kind == "number" or kind == "boolean" then return nil end
    local ok, copy = pcall(CopyText, v)
    if not ok or type(copy) ~= "string" then return nil end
    return copy
end
local function ReadableNumber(v)
    local kind = type(v)
    if kind == "string" or kind == "boolean" then return nil end
    local ok, copy = pcall(CopyNumber, v)
    if not ok or type(copy) ~= "number" then return nil end
    return copy
end

ns.Readable, ns.ReadableNumber = Readable, ReadableNumber

-- Where the player is: map id and normalised x, y (0..1), or nil.
function ns.PlayerPos()
    if not (C_Map and C_Map.GetBestMapForUnit and C_Map.GetPlayerMapPosition) then return end
    local ok, mapID = pcall(C_Map.GetBestMapForUnit, "player")
    mapID = ok and ReadableNumber(mapID)
    if not mapID then return end
    local ok2, pos = pcall(C_Map.GetPlayerMapPosition, mapID, "player")
    if not ok2 or not pos then return end
    local ok3, x, y = pcall(pos.GetXY, pos)
    x, y = ok3 and ReadableNumber(x), ok3 and ReadableNumber(y)
    if not x or not y or (x == 0 and y == 0) then return end
    return mapID, x, y
end

-- Map size in yards (width, height, exact); an estimate when the client will not say.
function ns.WorldSize(mapID)
    if C_Map and C_Map.GetMapWorldSize then
        local ok, w, h = pcall(C_Map.GetMapWorldSize, mapID)
        w, h = ok and ReadableNumber(w), ok and ReadableNumber(h)
        if w and h and w > 0 and h > 0 then return w, h, true end
    end
    return 1100, 733, false
end

local function QualityOf(link)
    local hex = link:match("|c%x%x(%x%x%x%x%x%x)")
    return QUALITY_BY_COLOR[hex and hex:lower()] or 1
end

-- What kind of creature this is. The client only tells while the unit is targeted or under
-- the mouse, so it is noted then (like the name and the level) and used when it is looted.
ns.KIND_ORDER = { normal = 1, elite = 2, rare = 3, boss = 4 }
local function KindOf(class, level)
    if level == -1 or class == "worldboss" then return "boss" end
    if class == "rare" or class == "rareelite" then return "rare" end
    if class == "elite" then return "elite" end
    return "normal"
end

local function CacheUnit(guid, name, level, class)
    if not guid or not guid:find("^Creature") then return end
    if name and not nameCache[guid] then
        if nameCount > 600 then wipe(nameCache); wipe(levelCache); wipe(classCache); nameCount = 0 end
        nameCache[guid] = name
        nameCount = nameCount + 1
    end
    if level and level > 0 then levelCache[guid] = level end
    if class then classCache[guid] = KindOf(class, level) end
end

-- the highest kind ever seen under this name
local function NoteKind(gm, guid)
    local k = guid and classCache[guid]
    if k and (not gm.kind or ns.KIND_ORDER[k] > (ns.KIND_ORDER[gm.kind] or 1)) then gm.kind = k end
end

ns.KINDS = {
    normal = { label = L["Normal"], color = { 0.8, 0.8, 0.8 } },
    elite = { label = L["Elite"], color = { 1, 0.82, 0.3 } },
    rare = { label = L["Rare"], color = { 0.5, 0.72, 1 } },
    boss = { label = L["Boss"], color = { 1, 0.42, 0.36 } },
}
-- "Elite" in the kind's colour, or nil for normal or unknown creatures
function ns.KindText(gm)
    local k = gm.kind
    if not k or k == "normal" then return nil end
    return ns.W.Hex(ns.KINDS[k].color) .. ns.KINDS[k].label .. "|r"
end

-- The creature's lowest known level as a tag, "18+", coloured by how it compares with your
-- own level (grey, green, yellow, orange, red); nil when no level was ever seen.
function ns.LevelTag(gm)
    local level = gm.minLevel or gm.level
    if not level or level <= 0 then return nil end
    local r, g, b = 1, 1, 0
    local col = GetQuestDifficultyColor and GetQuestDifficultyColor(level)
    if col then
        r, g, b = col.r or col[1] or 1, col.g or col[2] or 1, col.b or col[3] or 0
    else
        local d = level - (UnitLevel("player") or level)
        if d >= 5 then r, g, b = 1, 0.1, 0.1
        elseif d >= 3 then r, g, b = 1, 0.5, 0.25
        elseif d >= -2 then r, g, b = 1, 1, 0
        elseif d >= -6 then r, g, b = 0.25, 0.75, 0.25
        else r, g, b = 0.5, 0.5, 0.5 end
    end
    return string.format("|cff%02x%02x%02x%d+|r", math.floor(r * 255), math.floor(g * 255), math.floor(b * 255), level)
end

-- Only gathering-like sources get an icon (their category). Creatures get none:
-- a made-up icon for a wolf or a bandit says nothing about it.
function ns.SourceIcon(gm)
    if gm.cat == "mob" then return nil end
    -- plants and veins: the picture of the material they give (the category's picture until that is known)
    return (ns.SourceMapIcon and ns.SourceMapIcon(gm)) or ns.CAT[gm.cat].icon
end

-- A skinned corpse belongs to its creature. Skinning is still stored as its own
-- source ("skin:<name>") so it can be switched off in the settings, but the
-- views show it together with the creature.
function ns.SkinRecord(gm)
    if gm.cat ~= "mob" or not ns.CatOn("skin") then return nil end
    return ns.db.mobs["skin:" .. (gm.name or "")]
end

-- everything a creature ever dropped, skinning included
function ns.MergedItems(gm)
    local merged = {}
    for id, c in pairs(gm.items) do merged[id] = c end
    local skin = ns.SkinRecord(gm)
    if skin then
        for id, c in pairs(skin.items) do merged[id] = (merged[id] or 0) + c end
    end
    return merged
end

-- Chance (in percent) that a source drops an item: corpses it dropped on, out of the
-- corpses seen since that was recorded. Returns percent, exact, drops, corpses.
-- "exact" means a solid sample (at least the unlock threshold); older data only
-- has quantities, which gives a rough estimate instead.
function ns.DropChance(rec, id)
    local tracked = rec.tracked or 0
    local drops = rec.drops and rec.drops[id]
    if tracked > 0 and drops then
        return math.min(drops / tracked, 1) * 100, tracked >= ns.Threshold(), drops, tracked
    end
    local quantity = rec.items[id]
    if quantity and (rec.kills or 0) > 0 then
        return math.min(quantity / rec.kills, 1) * 100, false, quantity, rec.kills
    end
end

-- "Level 18" or "Levels 18–20"; nil when the level was never seen
function ns.LevelText(gm)
    local lo, hi = gm.minLevel or gm.level, gm.maxLevel or gm.level
    if not lo then return nil end
    if lo == hi then return L["Level %d"]:format(lo) end
    return L["Levels %d-%d"]:format(lo, hi)
end

local function CacheUnitToken(unit)
    local ok, exists = pcall(UnitExists, unit)
    if not ok or not exists or UnitIsPlayer(unit) then return end
    local class = UnitClassification and Readable(UnitClassification(unit)) or nil
    CacheUnit(Readable(UnitGUID(unit)), Readable(UnitName(unit)), ReadableNumber(UnitLevel(unit)), class)
end

-- Settings & session ------------------------------------------------------

function ns.CatOn(cat)
    return ns.db.settings.cats[cat] ~= false
end

function ns.Threshold() return ns.db.settings.threshold or DEFAULT_THRESHOLD end

function ns.NewSession()
    if ns.session and ns.db then ns.SaveSession() end
    ns.session = { start = nil, paused = false, pausedAt = 0, pausedTotal = 0, mobs = {}, items = {}, timeline = {}, points = {}, xp = 0 }
    ns.lastFind = nil
    ns.Refresh()
end

-- A session starts with the first loot, can be paused (the clock and gold per
-- hour stand still until the next loot or kill, or until it is resumed by hand)
-- and is ended on request: it goes to the history and the lists start empty.
ns.EndSession = ns.NewSession

function ns.SessionElapsed()
    local s = ns.session
    if not (s and s.start) then return 0 end
    local now = s.paused and s.pausedAt or GetTime()
    return math.max(0, now - s.start - (s.pausedTotal or 0))
end

function ns.PauseSession()
    local s = ns.session
    if not (s and s.start) or s.paused then return end
    s.paused, s.pausedAt = true, GetTime()
    ns.Refresh()
end

function ns.ResumeSession()
    local s = ns.session
    if not (s and s.paused) then return end
    s.pausedTotal = (s.pausedTotal or 0) + (GetTime() - s.pausedAt)
    s.paused = false
    ns.Refresh()
end

-- Optional (settings): the running session survives a reload or relog. It is
-- written out when the game closes and comes back paused, with the time it had;
-- the clock continues with the next loot or when you resume it by hand.
function ns.StashSession()
    local s = ns.session
    if not (s and s.start) then ns.db.savedSession = nil return end
    ns.db.savedSession = { elapsed = ns.SessionElapsed(), mobs = s.mobs, items = s.items, timeline = s.timeline, points = s.points, xp = s.xp }
end

function ns.RestoreSession()
    local saved = ns.db.savedSession
    ns.db.savedSession = nil
    if not saved then return end
    local s = ns.session
    s.mobs, s.items, s.timeline = saved.mobs or {}, saved.items or {}, saved.timeline or {}
    s.points = saved.points or {}
    s.xp = saved.xp or 0
    local now = GetTime()
    s.start, s.paused, s.pausedAt, s.pausedTotal = now - (saved.elapsed or 0), true, now, 0
    -- keep "most recent" ordering working: the counter continues after the saved ones
    for _, sm in pairs(s.mobs) do seq = math.max(seq, sm.last or 0) end
    for _, si in pairs(s.items) do seq = math.max(seq, si.last or 0) end
    if not ns.db.settings.keepSession then ns.EndSession() end -- the option was switched off meanwhile
end

function ns.TogglePause()
    if ns.session.paused then ns.ResumeSession() else ns.PauseSession() end
end

-- Finished sessions are kept as a small summary for the history page.
local MAX_HISTORY = 200
function ns.SaveSession()
    local s = ns.session
    if not (s and s.start) then return end
    local dur = ns.SessionElapsed()
    if dur < 30 then return end
    local snap = ns.BuildSnapshot()
    if snap.value <= 0 and snap.kills <= 0 and snap.looted <= 0 then return end

    local top = {}
    for id, it in pairs(snap.items) do top[#top + 1] = { id = id, count = it.count, value = it.value } end
    table.sort(top, function(a, b)
        if a.value ~= b.value then return a.value > b.value end
        return a.count > b.count
    end)
    for i = #top, 9, -1 do top[i] = nil end

    local zones = {}
    for key, sm in pairs(s.mobs) do
        local gm = ns.db.mobs[key]
        if gm and gm.zone and snap.sources[key] then
            zones[gm.zone] = (zones[gm.zone] or 0) + sm.kills + 1
        end
    end
    local zoneList = {}
    for zone, n in pairs(zones) do zoneList[#zoneList + 1] = { zone = zone, n = n } end
    table.sort(zoneList, function(a, b) return a.n > b.n end)
    for i = #zoneList, 4, -1 do zoneList[i] = nil end

    local cats = {}
    for cat, v in pairs(snap.catValue) do cats[cat] = v end

    table.insert(ns.db.history, 1, {
        t = time(), dur = dur, value = snap.value, kills = snap.kills, looted = snap.looted,
        perHour = snap.value / (dur / 3600), cats = cats, top = top, zones = zoneList,
    })
    for i = #ns.db.history, MAX_HISTORY + 1, -1 do ns.db.history[i] = nil end
end

-- Experience --------------------------------------------------------------
-- Experience counts like loot: it can start a session, and it is part of its rate.

local lastXP, lastXPMax
local pendingXP = { amount = 0, at = 0 }

local function XPNow()
    local ok1, xp = pcall(UnitXP, "player")
    local ok2, max = pcall(UnitXPMax, "player")
    return ok1 and ReadableNumber(xp) or nil, ok2 and ReadableNumber(max) or nil
end

function ns.AddXP(delta)
    local s = ns.session
    -- experience is activity like loot: it starts a session and ends a pause
    if not s.start then
        s.start = GetTime()
    elseif s.paused then
        ns.ResumeSession()
    end
    s.xp = (s.xp or 0) + delta
end

-- gained, per hour (after a minute), still missing for the level, and the time that takes
function ns.XPInfo()
    local s = ns.session
    local elapsed = ns.SessionElapsed()
    local gained = s.xp or 0
    local perHour = (elapsed >= 60 and gained > 0) and gained / (elapsed / 3600) or nil
    local cur, max = XPNow()
    local missing = (cur and max and max > 0) and (max - cur) or nil
    local eta = (perHour and missing) and missing / perHour * 3600 or nil
    return gained, perHour, missing, eta
end

-- 950, 12.4k, 1.1m
function ns.ShortNumber(n)
    if n >= 1000000 then return string.format("%.1fm", n / 1000000) end
    if n >= 10000 then return string.format("%.1fk", n / 1000) end
    if n >= 1000 then return string.format("%.2fk", n / 1000) end
    return string.format("%d", n + 0.5)
end

-- Experience per creature ------------------------------------------------------
-- The message "<creature> dies, you gain N experience." tells what a kill gave at the player's
-- level. That is kept per creature and per level. For levels without a measurement the
-- known formula gives an estimate, scaled by what was measured; it also tells when a
-- creature turns grey (no experience at all).

local function ZeroDiff(pl)
    if pl <= 7 then return 5 elseif pl <= 9 then return 6 elseif pl <= 11 then return 7
    elseif pl <= 15 then return 8 elseif pl <= 19 then return 9 elseif pl <= 29 then return 11
    elseif pl <= 39 then return 12 elseif pl <= 44 then return 13 elseif pl <= 49 then return 14
    elseif pl <= 54 then return 15 elseif pl <= 59 then return 16 end
    return 17
end

-- the experience of a normal creature of level ml for a player of level pl
function ns.XPFormula(ml, pl)
    if ml >= pl then
        return (pl * 5 + 45) * (1 + 0.05 * math.min(ml - pl, 4))
    end
    local zd = ZeroDiff(pl)
    if pl - ml >= zd then return 0 end
    return (pl * 5 + 45) * (1 - (pl - ml) / zd)
end

local function MobLevel(gm)
    local lo, hi = gm.minLevel or gm.level, gm.maxLevel or gm.level
    if not lo then return nil end
    return (lo + hi) / 2
end

local xpPending = {} -- creature name -> amounts that came before the creature was recorded

local function StoreXP(gm, amount)
    local pl = UnitLevel("player")
    if not pl or pl <= 0 then return end
    gm.xp = gm.xp or {}
    local e = gm.xp[pl]
    if not e then e = { n = 0, sum = 0 }; gm.xp[pl] = e end
    e.n, e.sum = e.n + 1, e.sum + amount
    -- how far this creature is from the plain formula (elites give double, for instance)
    local ml = MobLevel(gm)
    if ml then
        local f = ns.XPFormula(ml, pl)
        if f > 0 then
            gm.xpCalN = (gm.xpCalN or 0) + 1
            gm.xpCalSum = (gm.xpCalSum or 0) + amount / f
        end
    end
end

function ns.NoteKillXP(name, amount)
    if not name or not amount or amount <= 0 then return end
    local gm = ns.db.mobs[name]
    if gm and gm.cat == "mob" then
        StoreXP(gm, amount)
    else
        local list = xpPending[name]
        if not list then list = {}; xpPending[name] = list end
        if #list < 20 then list[#list + 1] = amount end
    end
end

-- the creature was just recorded: what its kill gave is waiting
local function ClaimXP(gm)
    local list = xpPending[gm.name or ""]
    if list and #list > 0 then StoreXP(gm, table.remove(list, 1)) end
end

-- Experience of one kill at the player's level (or the given one): the average measured at
-- that level, else the formula times how this creature compared with it. Second value:
-- "measured", "estimate" or "gray" (no experience at all).
function ns.XPEstimate(gm, pl)
    pl = pl or UnitLevel("player")
    local at = gm.xp and gm.xp[pl]
    if at and at.n > 0 then return at.sum / at.n, "measured" end
    local ml = MobLevel(gm)
    if not ml then return nil end
    local f = ns.XPFormula(ml, pl)
    if f <= 0 then return 0, "gray" end
    local cal = (gm.xpCalN and gm.xpCalN > 0) and gm.xpCalSum / gm.xpCalN or (gm.kind == "elite" and 2 or 1)
    return f * cal, "estimate"
end

-- the player level from which this creature gives nothing any more
function ns.XPGrayLevel(gm)
    local ml = MobLevel(gm)
    if not ml then return nil end
    for pl = math.max(1, UnitLevel("player") or 1), 70 do
        if ns.XPFormula(ml, pl) <= 0 then return pl end
    end
    return nil
end

local xpPattern
local function XPPattern()
    if xpPattern ~= nil then return xpPattern or nil end
    local g = COMBATLOG_XPGAIN_FIRSTPERSON
    if not g then xpPattern = false return nil end
    local p = g:gsub("%%s", "\1")
    p = p:gsub("%%d", "\2")
    p = p:gsub("%p", "%%%0")
    p = p:gsub("\1", "(.-)")
    p = p:gsub("\2", "(%%d+)")
    xpPattern = p
    return p
end

function ns.XPFromMessage(msg)
    local p = XPPattern()
    if not (p and type(msg) == "string") then return end
    local name, amount = msg:match(p)
    if name then ns.NoteKillXP(name, tonumber(amount)) end
end

local function Touch()
    local s = ns.session
    if not s.start then
        s.start = GetTime()
        if pendingXP.amount > 0 and GetTime() - pendingXP.at < 60 then s.xp = (s.xp or 0) + pendingXP.amount end
        pendingXP.amount = 0
    elseif s.paused then
        ns.ResumeSession() -- the next loot ends a pause
    end
    s.lastLoot = GetTime()
end

local function SourceKey(cat, name)
    return cat == "mob" and name or (cat .. ":" .. name)
end

local function GetSource(key, cat, name)
    local m = ns.db.mobs[key]
    if not m then
        m = { name = name, cat = cat, kills = 0, items = {}, greens = 0, blues = 0 }
        ns.db.mobs[key] = m
    end
    return m
end

local function GetSessionSource(key)
    local m = ns.session.mobs[key]
    if not m then
        m = { kills = 0, items = {}, last = 0 }
        ns.session.mobs[key] = m
    end
    return m
end

-- Recording -------------------------------------------------------------

ns.TIMELINE_BUCKET = 120 -- seconds per bar in the value chart

-- Places are clustered into grid cells (a creature roams, so a coarse grid; a
-- plant or a vein stays put, so a fine one) with a running average position.
local SPOT_GRID = { mob = 80, herb = 300, ore = 300, object = 300 }
local MAX_SPOTS = 250

-- A plant, a vein or a chest stays where it is and can be looted again and again. Loots
-- of one within this distance are the same place found once, not several places.
local NODE_MERGE_YARDS = 25

local function Dist2(a, b, w, h)
    local dx, dy = (a.x - b.x) * w, (a.y - b.y) * h
    return dx * dx + dy * dy
end

-- one-off tidy-up of spots saved before nodes were merged
function ns.MergeNodeSpots()
    local limit = NODE_MERGE_YARDS * NODE_MERGE_YARDS
    for _, gm in pairs(ns.db.mobs) do
        if gm.spots and gm.cat ~= "mob" and SPOT_GRID[gm.cat] then
            local list = {}
            for k, sp in pairs(gm.spots) do list[#list + 1] = { key = k, sp = sp } end
            table.sort(list, function(a, b) return a.sp.n > b.sp.n end)
            local kept = {}
            for _, e in ipairs(list) do
                local into
                local w, h = ns.WorldSize(e.sp.m)
                for _, k in ipairs(kept) do
                    if k.sp.m == e.sp.m and Dist2(k.sp, e.sp, w, h) <= limit then into = k break end
                end
                if into then
                    local n = into.sp.n + e.sp.n
                    into.sp.x = (into.sp.x * into.sp.n + e.sp.x * e.sp.n) / n
                    into.sp.y = (into.sp.y * into.sp.n + e.sp.y * e.sp.n) / n
                    into.sp.n = n
                    into.sp.t = math.max(into.sp.t or 0, e.sp.t or 0)
                    if into.sp.t == 0 then into.sp.t = nil end
                    gm.spots[e.key] = nil
                else
                    kept[#kept + 1] = e
                end
            end
        end
    end
end

-- Notifications --------------------------------------------------------------------------
-- One place for every notice: a kind, a picture and a line. Each kind can be switched off in
-- the settings (Notifications), and the sound as a whole.

ns.NOTIFY_KINDS = {
    { id = "spot", label = L["New spot saved"] },
    { id = "unlock", label = L["Creature unlocked"] },
    { id = "rare", label = L["Rare or boss creature killed"] },
    { id = "lap", label = L["Route lap finished"] },
}

function ns.NotifyOn(kind)
    local n = ns.db.settings.notify
    return not (n and n[kind] == false)
end

function ns.Notify(kind, icon, text)
    if not ns.NotifyOn(kind) then return end
    if ns.W and ns.W.Toast then ns.W.Toast(icon, text) end
    if ns.db.settings.notifySound ~= false then
        pcall(PlaySound, SOUNDKIT and SOUNDKIT.MAP_PING or 3175)
    end
end

-- a plant, vein or chest at a place not saved before
function ns.NewSpotAlert(gm)
    local icon = (ns.SourceMapIcon and ns.SourceMapIcon(gm)) or ns.CAT[gm.cat].icon
    ns.Notify("spot", icon, L["New spot saved"] .. ": " .. (gm.name or "?"))
end

local function RecordSpot(gm, cat, key)
    local grid = SPOT_GRID[cat]
    if not grid then return end
    local mapID, x, y = ns.PlayerPos()
    if not mapID then return end
    local node = cat ~= "mob"
    local w, h = ns.WorldSize(mapID)
    local limit = NODE_MERGE_YARDS * NODE_MERGE_YARDS
    local here = { x = x, y = y }

    -- the session's map: every kill is a point; a node looted again is the same point
    local pts = ns.session.points
    if pts then
        local merged = false
        if node then
            for i = #pts, math.max(1, #pts - 300), -1 do
                local p = pts[i]
                if p.key == key and p.m == mapID and Dist2(p, here, w, h) <= limit then
                    p.n, p.t = (p.n or 1) + 1, time()
                    merged = true
                    break
                end
            end
        end
        if not merged and #pts < 3000 then pts[#pts + 1] = { m = mapID, x = x, y = y, cat = cat, key = key, t = time(), n = 1 } end
    end

    gm.spots = gm.spots or {}
    if node then
        local nearest, nearestD
        for _, sp in pairs(gm.spots) do
            if sp.m == mapID then
                local d = Dist2(sp, here, w, h)
                if d <= limit and (not nearestD or d < nearestD) then nearest, nearestD = sp, d end
            end
        end
        if nearest then
            nearest.x = (nearest.x * nearest.n + x) / (nearest.n + 1)
            nearest.y = (nearest.y * nearest.n + y) / (nearest.n + 1)
            nearest.n = nearest.n + 1
            nearest.ts = nearest.ts or (nearest.t and { nearest.t }) or {}
            nearest.t = time()
            table.insert(nearest.ts, nearest.t)
            while #nearest.ts > 6 do table.remove(nearest.ts, 1) end
            return
        end
    end
    local cell = mapID .. ":" .. math.floor(x * grid) .. ":" .. math.floor(y * grid)
    local sp = gm.spots[cell]
    if sp then
        sp.x = (sp.x * sp.n + x) / (sp.n + 1)
        sp.y = (sp.y * sp.n + y) / (sp.n + 1)
        sp.n = sp.n + 1
        sp.t = time()
        return
    end
    gm.spots[cell] = { m = mapID, x = x, y = y, n = 1, t = time(), ts = { time() } }
    if node then ns.NewSpotAlert(gm) end
    local count, weakest, weakestN = 0, nil, nil
    for k, s in pairs(gm.spots) do
        count = count + 1
        if k ~= cell and (not weakestN or s.n < weakestN) then weakest, weakestN = k, s.n end
    end
    if count > MAX_SPOTS and weakest then gm.spots[weakest] = nil end
end

-- one corpse / node / catch counts once, however many items or coins it gave
local function CountSource(gm, sm, cat, key, guid)
    local ident = (guid and (guid .. "|" .. cat)) or ("w" .. lootWindow .. "|" .. key)
    if not seenOnce[ident] then
        seenOnce[ident] = true
        gm.kills = gm.kills + 1
        gm.tracked = (gm.tracked or 0) + 1 -- corpses since drops are recorded per corpse
        local sub = GetSubZoneText()
        if sub and sub ~= "" then
            gm.subs = gm.subs or {}
            gm.subs[sub] = (gm.subs[sub] or 0) + 1
        end
        sm.kills = sm.kills + 1
        if cat == "mob" then
            ClaimXP(gm)
            local swords = ns.CAT.mob.icon
            if gm.kills == ns.Threshold() then
                ns.Notify("unlock", swords, (gm.name or "?") .. ": " .. L["unlocked"])
            end
            local kind = guid and classCache[guid]
            if kind == "rare" or kind == "boss" then
                ns.Notify("rare", swords, (kind == "boss" and L["Boss killed"] or L["Rare creature killed"]) .. ": " .. (gm.name or "?"))
            end
        end
        RecordSpot(gm, cat, key)
        if ns.Routes then ns.Routes.OnKill() end
    end
    return ident
end

-- the value of what was looted goes into the session's curve and the all-time heat
local function AddValue(gm, copper, sm)
    if copper <= 0 then return end
    local bucket = math.floor(ns.SessionElapsed() / ns.TIMELINE_BUCKET) + 1
    ns.session.timeline[bucket] = (ns.session.timeline[bucket] or 0) + copper
    -- and the same curve for the source alone (its chart in the session window)
    if sm then
        sm.tl = sm.tl or {}
        sm.tl[bucket] = (sm.tl[bucket] or 0) + copper
    end
    local zone = gm.zone or "?"
    local hour = tonumber(date("%H")) or 0
    local heat = ns.db.heat[zone]
    if not heat then heat = {}; ns.db.heat[zone] = heat end
    heat[hour] = (heat[hour] or 0) + copper
end

function ns.MoneyOn() return ns.db.settings.countMoney ~= false end

-- Coins are loot too. They count towards the value (a setting), and a corpse that only
-- had coins is still a kill.
-- Something was looted or gathered: the session window opens by itself (a setting, on unless switched off).
function ns.OnFind()
    if ns.db.settings.autoOpenSession == true and ns.HUD then ns.HUD.Show() end
end

-- Inside dungeons and raids, and in a group, the game hides the names of creatures from addons: the loot could only be booked under
-- "Unknown". Two settings keep it from being recorded there (dungeons and raids: on unless switched off; a group: off unless switched on);
-- a note in the chat says so once.
local pausedNote
local function RecordingPaused()
    local st = ns.db.settings
    local why
    if st.pauseInstances ~= false then
        local inside, kind = IsInInstance()
        if inside and (kind == "party" or kind == "raid" or kind == "scenario") then why = L["in a dungeon or raid"] end
    end
    if not why and st.pauseGroup == true and IsInGroup and IsInGroup() then why = L["in a group"] end
    if not why then pausedNote = nil return false end
    if pausedNote ~= why then
        pausedNote = why
        print("|cffffd100ForeverCompanion:|r " .. (L["Loot is not recorded %s: the game hides the names of creatures there. You can change this in the settings (Kills & Loot)."]):format(why))
    end
    return true
end
ns.RecordingPaused = RecordingPaused

-- In a group the coins of a corpse are shared: what counts is the share the game names in the chat ("Your share of the loot is ..."),
-- not what the loot window shows. The sources of the coins wait for that line (or a line that came a moment before the window).
local moneyWaiting, moneyEarly = {}, {}
local function RecordMoney(cat, name, copper, guid, share)
    if not copper or copper <= 0 then return end
    if RecordingPaused() then return end
    if not share and IsInGroup and IsInGroup() then
        local now = GetTime()
        while moneyEarly[1] and now - moneyEarly[1].t > 3 do table.remove(moneyEarly, 1) end
        local early = table.remove(moneyEarly, 1)
        if early then
            copper = early.copper
        else
            moneyWaiting[#moneyWaiting + 1] = { cat = cat, name = name, guid = guid, t = now }
            return
        end
    end
    local key = SourceKey(cat, name)
    local gm, sm = GetSource(key, cat, name), GetSessionSource(key)
    CountSource(gm, sm, cat, key, guid)
    gm.money = (gm.money or 0) + copper
    sm.money = (sm.money or 0) + copper
    sm.last = NextSeq()
    gm.zone = GetZoneText()
    sm.zone, sm.sub = gm.zone, GetSubZoneText() -- where this session met it (the session list groups by it)
    if cat == "mob" then
        NoteKind(gm, guid)
        local lvl = guid and levelCache[guid]
        if lvl then
            gm.level = lvl
            gm.minLevel = math.min(gm.minLevel or lvl, lvl)
            gm.maxLevel = math.max(gm.maxLevel or lvl, lvl)
        end
    end
    Touch()
    if ns.MoneyOn() then
        if ns.Routes then ns.Routes.OnLoot(copper) end
        AddValue(gm, copper, sm)
        ns.lastFind = { money = true, value = copper, source = name, cat = cat }
        ns.OnFind()
    end
end

local function RecordLoot(cat, name, link, qty, guid)
    local id, _, _, _, _, classID = GetInstant(link)
    if not id then return end
    if RecordingPaused() then return end
    local quality = QualityOf(link)
    local key = SourceKey(cat, name)

    local gm, sm = GetSource(key, cat, name), GetSessionSource(key)

    local ident = CountSource(gm, sm, cat, key, guid)

    -- one drop per corpse and item, whatever the quantity: the basis of drop chances
    local dropKey = ident .. "|" .. id
    if not seenOnce[dropKey] then
        seenOnce[dropKey] = true
        gm.drops = gm.drops or {}
        gm.drops[id] = (gm.drops[id] or 0) + 1
    end

    gm.items[id] = (gm.items[id] or 0) + qty
    sm.items[id] = (sm.items[id] or 0) + qty
    sm.last = NextSeq()
    gm.zone = GetZoneText()
    sm.zone, sm.sub = gm.zone, GetSubZoneText() -- where this session met it (the session list groups by it)
    if cat == "mob" then
        -- creatures of one name can differ in level: keep the range that was met
        NoteKind(gm, guid)
        local lvl = guid and levelCache[guid]
        if lvl then
            gm.level = lvl
            gm.minLevel = math.min(gm.minLevel or lvl, lvl)
            gm.maxLevel = math.max(gm.maxLevel or lvl, lvl)
        end
        if quality >= 2 and (classID == CLASS_WEAPON or classID == CLASS_ARMOR) then
            if quality == 2 then gm.greens = gm.greens + 1 else gm.blues = gm.blues + 1 end
        end
    end

    local gi = ns.db.items[id]
    if not gi then
        gi = { count = 0, sources = {} }
        ns.db.items[id] = gi
    end
    gi.link, gi.quality = link, quality
    gi.count = gi.count + qty
    gi.sources[key] = (gi.sources[key] or 0) + qty

    local si = ns.session.items[id]
    if not si then
        si = { count = 0, sources = {}, last = 0 }
        ns.session.items[id] = si
    end
    si.count = si.count + qty
    si.sources[key] = (si.sources[key] or 0) + qty
    si.last = NextSeq()
    Touch()

    -- value timeline (session) and heatmap (all time), at the price of now
    local copper = ns.Value.Get(id) * qty
    if ns.Routes then ns.Routes.OnLoot(copper) end
    AddValue(gm, copper, sm)
    ns.lastFind = { link = link, qty = qty, value = copper, source = name, cat = cat } -- (the last thing looted or gathered: the footer of the session window shows it)
    ns.OnFind()
end

local function CreatureName(guid)
    if guid then
        if not nameCache[guid] then
            for _, unit in ipairs({ "target", "mouseover" }) do
                if Readable(UnitGUID(unit)) == guid then CacheUnitToken(unit) break end
            end
        end
        if nameCache[guid] then return nameCache[guid] end
    end
    local ok, exists = pcall(UnitExists, "target")
    if ok and exists and not UnitIsPlayer("target") then
        local name = Readable(UnitName("target"))
        if name then return name end
    end
    return L["Unknown"]
end

-- What a node gave tells what it is, even without a gathering spell: herbs come
-- from herbalism, ore and gems from mining. This catches plants that were
-- duplicated (the Tauren ability) or opened some other way; they are new objects
-- for the client but the same thing for us.
local TRADE_GOODS, SUB_METAL_STONE, SUB_HERB, CLASS_GEM = 7, 7, 9, 3

local function NodeKinds(entries)
    local kinds = {}
    for _, e in ipairs(entries) do
        local _, _, _, _, _, classID, subID = GetInstant(e.link)
        local herb = classID == TRADE_GOODS and subID == SUB_HERB
        local ore = (classID == TRADE_GOODS and subID == SUB_METAL_STONE) or classID == CLASS_GEM
        if (herb or ore) and e.srcs then
            local itemName = e.link:match("%[(.-)%]")
            for _, src in ipairs(e.srcs) do
                if src.guid and not (src.guid:find("^Creature") or src.guid:find("^Vehicle")) then
                    local k = kinds[src.guid]
                    if not k then k = { herb = 0, ore = 0 }; kinds[src.guid] = k end
                    if herb then k.herb = k.herb + 1 else k.ore = k.ore + 1 end
                    k.name = k.name or itemName
                end
            end
        end
    end
    return kinds
end

-- A node's name: the target of the gathering spell, else whatever unit token
-- points at it, else the name of what it gave.
local function NodeName(guid, g, kind)
    if g and g.target then return g.target end
    for _, unit in ipairs({ "softinteract", "mouseover", "target" }) do
        local ok, exists = pcall(UnitExists, unit)
        if ok and exists and Readable(UnitGUID(unit)) == guid then
            local name = Readable(UnitName(unit))
            if name then return name end
        end
    end
    return kind and kind.name or nil
end

-- Returns category, name for one loot source guid (a readable string or nil).
local function Classify(guid, g, fishing, kind)
    if fishing then return "fish", L["Fishing"] end
    local isCreature = guid and (guid:find("^Creature") or guid:find("^Vehicle"))
    if isCreature then
        local name = CreatureName(guid)
        -- Skinning opens a corpse: one we looted before, or a stranger's (nobody
        -- looted it here). The skinning spell's target is the creature's name, and
        -- the loot follows within a few seconds, so that identifies it.
        if g and g.cat == "skin" and GetTime() - g.time < 8
            and (seenOnce[guid .. "|mob"] or g.target == name) then
            return "skin", name
        end
        return "mob", name
    end
    if g and (g.cat == "herb" or g.cat == "ore") then
        return g.cat, g.target or ns.CAT[g.cat].label
    end
    if g and g.cat == "disenchant" then return "disenchant", g.target or L["Disenchanting"] end
    if kind then
        if kind.herb > 0 and kind.ore == 0 then return "herb", NodeName(guid, g, kind) or ns.CAT.herb.label end
        if kind.ore > 0 and kind.herb == 0 then return "ore", NodeName(guid, g, kind) or ns.CAT.ore.label end
    end
    if not guid then
        -- unreadable guid: the target is the best remaining guess
        local ok, exists = pcall(UnitExists, "target")
        if ok and exists and not UnitIsPlayer("target") then return "mob", CreatureName(nil) end
    end
    return "object", (g and g.target) or NodeName(guid, g, kind) or L["Object"]
end

-- "1 Gold 24 Silver 3 Copper" (as the client words it) in copper
local function MoneyFromText(text)
    if type(text) ~= "string" then return 0 end
    local total = 0
    for _, def in ipairs({ { GOLD_AMOUNT, 10000 }, { SILVER_AMOUNT, 100 }, { COPPER_AMOUNT, 1 } }) do
        if def[1] then
            local pattern = def[1]:gsub("%%d", "\1")
            pattern = pattern:gsub("%p", "%%%0")
            pattern = pattern:gsub("\1", "(%%d+)")
            local n = text:match(pattern)
            if n then total = total + tonumber(n) * def[2] end
        end
    end
    return total
end

-- the chat lines with money: "You loot 5 Silver", and in a group "Your share of the loot is 2 Silver"
local MONEY_LINES = {}
for _, name in ipairs({ "LOOT_MONEY_SPLIT", "YOU_LOOT_MONEY" }) do
    local fmt = _G[name]
    if type(fmt) == "string" then
        MONEY_LINES[#MONEY_LINES + 1] = "^" .. fmt:gsub("%p", "%%%0"):gsub("%%%%s", "(.+)") .. "$"
    end
end
function ns.OnChatMoney(text)
    text = Readable(text)
    if not text or not ns.db then return end
    local copper
    for _, pat in ipairs(MONEY_LINES) do
        local got = text:match(pat)
        if got then copper = MoneyFromText(got) break end
    end
    if not copper or copper <= 0 then return end
    local now = GetTime()
    while moneyWaiting[1] and now - moneyWaiting[1].t > 20 do table.remove(moneyWaiting, 1) end
    local w = table.remove(moneyWaiting, 1)
    if w then
        RecordMoney(w.cat, w.name, copper, w.guid, true)
        ns.Refresh()
    else
        moneyEarly[#moneyEarly + 1] = { copper = copper, t = now } -- (the line came before the loot window was read)
    end
end

local function SlotSources(slot)
    local okSrc, sources = pcall(function() return { GetLootSourceInfo(slot) } end)
    if not (okSrc and #sources > 0) then return nil end
    local srcs = {}
    for i = 1, #sources - 1, 2 do
        srcs[#srcs + 1] = { guid = Readable(sources[i]), qty = ReadableNumber(sources[i + 1]) or 1 }
    end
    return srcs
end

local function Quantity(slot)
    return ReadableNumber(select(3, GetLootSlotInfo(slot))) or 1
end

-- Called for LOOT_READY (the slots are known first) and LOOT_OPENED. A window with nothing in it yet (the
-- client's automatic looting may already have emptied it) is left to the next of the two events.
local function OnLootOpened(from)
    local slots = GetNumLootItems and GetNumLootItems() or 0
    Dbg(from or "LOOT_OPENED", "already read:", lootDone, "slots:", slots)
    if lootDone or slots == 0 then return end
    lastWindowAt = GetTime()
    lootDone = true
    lootWindow = lootWindow + 1

    local g = lastGather and (GetTime() - lastGather.time < 15) and lastGather or nil
    if g then g.opened = true end -- the loot window did show: no need for the chat message fallback
    if g and g.cat == "pocket" then Dbg("pickpocket: not counted") return end
    local okFish, fishing = pcall(IsFishingLoot)
    fishing = okFish and fishing == true

    -- read every slot first, so a source can be judged by all it gave
    local entries, coins = {}, {}
    for slot = 1, GetNumLootItems() do
        local slotType = GetLootSlotType and GetLootSlotType(slot)
        local link = Readable(GetLootSlotLink(slot))
        Dbg("slot", slot, "type", tostring(slotType), "link", tostring(link))
        if link and (slotType == nil or slotType == 1) then
            entries[#entries + 1] = { link = link, slot = slot, srcs = SlotSources(slot) }
        elseif slotType == 2 then
            local okInfo, _, text = pcall(GetLootSlotInfo, slot)
            local copper = okInfo and MoneyFromText(Readable(text)) or 0
            if copper > 0 then coins[#coins + 1] = { copper = copper, srcs = SlotSources(slot) } end
        end
    end
    local kinds = NodeKinds(entries)
    Dbg("loot window", #entries, "items; gather:", g and g.cat or "none", "fishing:", tostring(fishing))

    for _, e in ipairs(entries) do
        if not e.srcs then
            local cat, name = Classify(nil, g, fishing, nil)
            RecordLoot(cat, name, e.link, Quantity(e.slot), nil)
        else
            for _, src in ipairs(e.srcs) do
                local cat, name = Classify(src.guid, g, fishing, src.guid and kinds[src.guid])
                if ns.db and ns.db.debug then
                    local _, _, _, _, _, classID, subID = GetInstant(e.link)
                    Dbg("slot", e.link, "class", tostring(classID), "sub", tostring(subID), "source", tostring(src.guid), "->", cat, tostring(name))
                end
                RecordLoot(cat, name, e.link, src.qty, src.guid)
            end
        end
    end
    for _, coin in ipairs(coins) do
        if not coin.srcs then
            local cat, name = Classify(nil, g, fishing, nil)
            RecordMoney(cat, name, coin.copper, nil)
        else
            for _, src in ipairs(coin.srcs) do
                local cat, name = Classify(src.guid, g, fishing, nil)
                -- one source gets all of it; with several, the client says how much came from each
                RecordMoney(cat, name, #coin.srcs == 1 and coin.copper or src.qty, src.guid)
            end
        end
    end
    ns.Refresh()
end

-- Loot that comes without a loot window (the client puts it into the bags itself) is only known from the
-- chat line "You receive loot: [Item]". It counts when no loot window opened just before:
--  - after a gathering cast, for what the node gives (herbs for a plant, ore and gems for a vein);
--  - otherwise as the drop of the creature that was just killed (the dead target).
-- Items that arrive some other way ("You receive item": a purchase, a quest reward) are never counted.
local SELF_LOOT = {}
for _, name in ipairs({ "LOOT_ITEM_SELF_MULTIPLE", "LOOT_ITEM_SELF" }) do
    local fmt = _G[name]
    if type(fmt) == "string" then
        local pat = fmt:gsub("%p", "%%%0"):gsub("%%%%s", "(.+)"):gsub("%%%%d", "(%%d+)")
        SELF_LOOT[#SELF_LOOT + 1] = { pat = "^" .. pat .. "$", multiple = name:find("MULTIPLE") ~= nil }
    end
end

local chatWindowAt, chatWindowKey = -100, nil
function ns.OnChatLoot(msg)
    if GetTime() - lastWindowAt < 3 then return end -- a loot window did show: it is counted there
    msg = Readable(msg)
    if not msg then return end
    for _, p in ipairs(SELF_LOOT) do
        local link, qty = msg:match(p.pat)
        if link and link:find("|Hitem:") then
            qty = p.multiple and tonumber(qty) or 1
            local _, _, _, _, _, classID, subID = GetInstant(link)
            local g = lastGather
            local gathered = g and GetTime() - g.time < 20 and (g.cat == "ore" or g.cat == "herb")
            local cat, name
            if gathered then
                local herb = classID == TRADE_GOODS and subID == SUB_HERB
                local ore = (classID == TRADE_GOODS and subID == SUB_METAL_STONE) or classID == CLASS_GEM
                if (g.cat == "herb" and herb) or (g.cat == "ore" and ore) then
                    cat, name = g.cat, g.target or ns.CAT[g.cat].label
                end
            end
            if not cat then
                -- the dead creature that is targeted
                local ok, exists = pcall(UnitExists, "target")
                local okDead, dead = pcall(UnitIsDead, "target")
                if ok and exists and okDead and dead and not UnitIsPlayer("target") then
                    -- in combat the name can be hidden: then the one remembered from when it was targeted
                    name = Readable(UnitName("target"))
                        or (lastTarget and GetTime() - lastTarget.time < 120 and lastTarget.name) or nil
                    if name then cat = "mob" end
                end
            end
            if cat and name then
                -- the items of one corpse (or one node) arrive within a moment: one window for them
                local key = cat .. ":" .. name
                if GetTime() - chatWindowAt > 2 or chatWindowKey ~= key then lootWindow = lootWindow + 1 end
                chatWindowAt, chatWindowKey = GetTime(), key
                Dbg("loot from chat", link, "x", tostring(qty), "->", cat, tostring(name))
                RecordLoot(cat, name, link, qty, nil)
                ns.Refresh()
            else
                Dbg("loot from chat ignored (no node, no dead target)", link)
            end
            return
        end
    end
end

-- /fc debug: after a gathering cast every event that could have to do with its result is listed
-- (for 25 seconds), so it can be seen what the client really does
local trace = CreateFrame("Frame")
for _, e in ipairs({ "LOOT_READY", "LOOT_OPENED", "LOOT_CLOSED", "CHAT_MSG_LOOT", "CHAT_MSG_SYSTEM", "CHAT_MSG_SKILL",
    "UI_ERROR_MESSAGE", "UNIT_SPELLCAST_START", "UNIT_SPELLCAST_CHANNEL_START", "UNIT_SPELLCAST_SUCCEEDED",
    "UNIT_SPELLCAST_FAILED", "UNIT_SPELLCAST_INTERRUPTED", "UNIT_SPELLCAST_STOP", "BAG_UPDATE_DELAYED" }) do
    pcall(trace.RegisterEvent, trace, e)
end
trace:SetScript("OnEvent", function(_, event, ...)
    if not (ns.db and ns.db.debug and lastGather and GetTime() - lastGather.time < 25) then return end
    local unit = ...
    if event:find("^UNIT_SPELLCAST") and unit ~= "player" then return end
    local parts = {}
    for i = 1, math.min(select("#", ...), 5) do
        local v = select(i, ...)
        parts[#parts + 1] = tostring(Readable(v) or ReadableNumber(v) or (type(v) == "string" and "?" or v))
    end
    Dbg("event", event, table.concat(parts, " | "), string.format("(+%.1fs)", GetTime() - lastGather.time))
end)

-- Snapshot --------------------------------------------------------------
-- One pass per refresh over the session with the category filter applied;
-- every page reads ns.snap instead of recomputing.

function ns.BuildSnapshot()
    -- the journal and the session overlay both ask once per frame
    if ns.snap and ns.snapStamp == GetTime() then return ns.snap end
    local snap = { value = 0, unpriced = 0, kills = 0, gathered = 0, looted = 0, money = 0, items = {}, sources = {}, catValue = {} }
    local session = ns.session

    for key, sm in pairs(session.mobs) do
        local gm = ns.db.mobs[key]
        if gm and ns.CatOn(gm.cat) then
            local value = 0
            for id, c in pairs(sm.items) do value = value + ns.Value.Get(id) * c end
            local coins = sm.money or 0
            snap.money = snap.money + coins
            if ns.MoneyOn() then value = value + coins end
            snap.sources[key] = { cat = gm.cat, kills = sm.kills, value = value }
            if gm.cat == "mob" then snap.kills = snap.kills + sm.kills end
            if gm.cat == "herb" or gm.cat == "ore" or gm.cat == "object" then snap.gathered = snap.gathered + sm.kills end
            snap.catValue[gm.cat] = (snap.catValue[gm.cat] or 0) + value
            snap.value = snap.value + value
        end
    end

    for id, si in pairs(session.items) do
        local count, sources = 0, {}
        for key, c in pairs(si.sources) do
            local gm = ns.db.mobs[key]
            if not gm or ns.CatOn(gm.cat) then
                count = count + c
                sources[key] = c
            end
        end
        if count > 0 then
            local unit = ns.Value.Get(id)
            if unit <= 0 then snap.unpriced = snap.unpriced + 1 end
            snap.items[id] = { count = count, unit = unit, value = unit * count, sources = sources, last = si.last }
            snap.looted = snap.looted + count
        end
    end

    ns.snap, ns.snapStamp = snap, GetTime()
    return snap
end

-- The saved variables are there from ADDON_LOADED on, not while the files are read. Code that needs them to build (a window that reads its
-- measures from the theme, for one) is given to ns.AfterLoad(fn) and runs as soon as they are.
local afterLoad = {}
function ns.AfterLoad(fn)
    if ns.db then fn() else afterLoad[#afterLoad + 1] = fn end
end

-- Events ----------------------------------------------------------------

local f = CreateFrame("Frame")
f:RegisterEvent("ADDON_LOADED")

local function InitDB()
    -- the addon was called ForeverKillLog: take its data over once, and drop the old name so it is not saved twice
    if not ForeverCompanionDB and ForeverKillLogDB then ForeverCompanionDB = ForeverKillLogDB end
    ForeverKillLogDB = nil
    ForeverCompanionDB = ForeverCompanionDB or {}
    local db = ForeverCompanionDB
    if db.version ~= DB_VERSION then
        -- the source model changed (categories); old test data cannot be mapped
        db.mobs, db.items, db.heat = {}, {}, {}
        db.version = DB_VERSION
    end
    db.mobs = db.mobs or {}
    db.items = db.items or {}
    db.heat = db.heat or {}
    db.history = db.history or {}
    db.routes = db.routes or {}
    db.pins = db.pins or {}
    db.nav = db.nav or {}
    db.valueSource = db.valueSource or "vendor"
    db.settings = db.settings or {}
    db.settings.cats = db.settings.cats or {}
    db.settings.threshold = db.settings.threshold or DEFAULT_THRESHOLD
    ns.db = db
end

f:SetScript("OnEvent", function(_, event, ...)
    if event == "ADDON_LOADED" then
        if (...) ~= ADDON then return end
        InitDB()
        for _, fn in ipairs(afterLoad) do
            local ok, err = pcall(fn)
            if not ok then print("|cffffd100Forever Companion:|r " .. tostring(err)) end
        end
        wipe(afterLoad)
        if not ns.db.nodeMerged then ns.MergeNodeSpots(); ns.db.nodeMerged = true end
        ns.NewSession()
        ns.RestoreSession()
        f:UnregisterEvent("ADDON_LOADED")
        f:RegisterEvent("LOOT_OPENED")
        f:RegisterEvent("LOOT_CLOSED")
        pcall(f.RegisterEvent, f, "LOOT_READY")
        f:RegisterEvent("CHAT_MSG_LOOT")
        pcall(f.RegisterEvent, f, "CHAT_MSG_MONEY")
        f:RegisterEvent("PLAYER_TARGET_CHANGED")
        f:RegisterEvent("UPDATE_MOUSEOVER_UNIT")
        f:RegisterEvent("UNIT_SPELLCAST_SENT")
        f:RegisterEvent("GET_ITEM_INFO_RECEIVED")
        f:RegisterEvent("PLAYER_LOGOUT")
        f:RegisterEvent("PLAYER_XP_UPDATE")
        f:RegisterEvent("CHAT_MSG_COMBAT_XP_GAIN")
        f:RegisterEvent("PLAYER_ENTERING_WORLD")
        lastXP, lastXPMax = XPNow()
    elseif event == "CHAT_MSG_COMBAT_XP_GAIN" then
        ns.XPFromMessage(Readable((...)))
    elseif event == "PLAYER_ENTERING_WORLD" then
        lastXP, lastXPMax = XPNow()
    elseif event == "PLAYER_XP_UPDATE" then
        local xp, max = XPNow()
        if xp and lastXP then
            local delta = xp - lastXP
            if delta < 0 then delta = ((lastXPMax or xp) - lastXP) + xp end -- a level was gained
            if delta > 0 then ns.AddXP(delta); ns.Refresh() end
        end
        lastXP, lastXPMax = xp, max
    elseif event == "PLAYER_LOGOUT" then
        if ns.db.settings.keepSession then
            ns.StashSession()
        else
            ns.db.savedSession = nil
            ns.SaveSession()
        end
    elseif event == "LOOT_OPENED" then
        OnLootOpened()
    elseif event == "LOOT_READY" then
        OnLootOpened("LOOT_READY")
    elseif event == "CHAT_MSG_LOOT" then
        ns.OnChatLoot(...)
    elseif event == "CHAT_MSG_MONEY" then
        ns.OnChatMoney((...))
    elseif event == "LOOT_CLOSED" then
        Dbg("LOOT_CLOSED")
        lootDone = false
    elseif event == "PLAYER_TARGET_CHANGED" then
        CacheUnitToken("target")
        local okT, existsT = pcall(UnitExists, "target")
        if okT and existsT and not UnitIsPlayer("target") then
            local n = Readable(UnitName("target"))
            if n then lastTarget = { name = n, time = GetTime() } end
        end
    elseif event == "UPDATE_MOUSEOVER_UNIT" then
        CacheUnitToken("mouseover")
    elseif event == "UNIT_SPELLCAST_SENT" then
        local unit, target, _, spellID = ...
        if unit == "player" then
            local id = ReadableNumber(spellID) or 0
            local cat = GatherCat(id)
            Dbg("cast", id, Readable(target), "->", cat or "not a gathering spell")
            if cat then lastGather = { cat = cat, target = Readable(target), time = GetTime() } end
        end
    elseif event == "GET_ITEM_INFO_RECEIVED" then
        ns.Value.Reset()
        ns.Refresh()
    end
end)

-- Slash commands --------------------------------------------------------

function ns.ResetAll()
    wipe(ns.db.mobs); wipe(ns.db.items); wipe(ns.db.heat); wipe(ns.db.history)
    wipe(seenOnce)
    ns.NewSession()
end

-- /fc probe: what the client lets the addon read right now (in a dungeon, in a group, ...): units, the tooltip and the loot window. The
-- answer is shown in a window that can be copied. Meant for finding out why names are "unknown".
function ns.Probe()
    local out = {}
    local function P(...)
        local t = {}
        for i = 1, select("#", ...) do t[i] = tostring((select(i, ...))) end
        out[#out + 1] = table.concat(t, " ")
    end
    -- a value as text: secret, nil, or what it is
    local function S(v)
        if v == nil then return "nil" end
        if issecretvalue and issecretvalue(v) then return "SECRET" end
        local ok, t = pcall(tostring, v)
        return ok and t or "unreadable"
    end
    local function Call(fn, ...)
        local ok, a, b, c2 = pcall(fn, ...)
        if not ok then return "ERROR" end
        return S(a), S(b), S(c2)
    end
    P("issecretvalue:", type(issecretvalue), " build:", S(select(4, GetBuildInfo())))
    local inside, kind = IsInInstance()
    P("instance:", S(inside), S(kind), " zone:", S(GetZoneText()), " group:", S(IsInGroup and IsInGroup()), " raid:", S(IsInRaid and IsInRaid()))
    P("paused by the settings:", S(ns.db.settings.pauseInstances ~= false), S(ns.db.settings.pauseGroup == true))
    for _, unit in ipairs({ "target", "mouseover", "softenemy", "softinteract", "focus" }) do
        local ok, exists = pcall(UnitExists, unit)
        if ok and exists then
            P("--", unit)
            P("  name:", Call(UnitName, unit))
            P("  guid:", Call(UnitGUID, unit))
            P("  player:", Call(UnitIsPlayer, unit), " dead:", Call(UnitIsDead, unit), " level:", Call(UnitLevel, unit), " class:", Call(UnitClassification, unit))
            P("  type:", Call(UnitCreatureType, unit))
        else
            P("--", unit, "(none)")
        end
    end
    -- the data of the tooltip of the unit under the mouse, and of the target
    for _, unit in ipairs({ "mouseover", "target" }) do
        if C_TooltipInfo and C_TooltipInfo.GetUnit then
            local ok, data = pcall(C_TooltipInfo.GetUnit, unit)
            if ok and data then
                local first = data.lines and data.lines[1]
                P("tooltip data", unit, ": lines", S(data.lines and #data.lines), " first:", S(first and first.leftText), " guid:", S(data.guid))
            else
                P("tooltip data", unit, ": none")
            end
        end
    end
    local line = GameTooltip and GameTooltip:IsShown() and _G.GameTooltipTextLeft1
    P("tooltip line 1:", line and S(line:GetText()) or "(tooltip not shown)")
    local slots = GetNumLootItems and GetNumLootItems() or 0
    P("loot window slots:", slots)
    for slot = 1, slots do
        local okSrc, sources = pcall(function() return { GetLootSourceInfo(slot) } end)
        local src = {}
        if okSrc then for i = 1, #sources do src[#src + 1] = S(sources[i]) end end
        P("  slot", slot, "type:", Call(GetLootSlotType, slot), "link:", Call(GetLootSlotLink, slot))
        P("    info:", Call(GetLootSlotInfo, slot))
        P("    sources:", okSrc and table.concat(src, ", ") or "ERROR")
        -- can the creature be named from its guid alone? (a tooltip made for the guid, not for a unit)
        if okSrc then
            for i = 1, #sources, 2 do
                local guid = Readable(sources[i])
                if guid then
                    local npc = guid:match("^%a+%-%d+%-%d+%-%d+%-%d+%-(%d+)%-")
                    P("    guid", guid, "npc id:", npc or "?")
                    if C_TooltipInfo and C_TooltipInfo.GetHyperlink then
                        local ok, data = pcall(C_TooltipInfo.GetHyperlink, "unit:" .. guid)
                        if ok and data then
                            P("    hyperlink data: lines", S(data.lines and #data.lines), " first:", S(data.lines and data.lines[1] and data.lines[1].leftText))
                        else
                            P("    hyperlink data:", ok and "none" or "ERROR")
                        end
                    end
                    local tip = _G.ForeverCompanionProbeTip or CreateFrame("GameTooltip", "ForeverCompanionProbeTip", UIParent, "GameTooltipTemplate")
                    tip:SetOwner(UIParent, "ANCHOR_NONE")
                    local ok2 = pcall(tip.SetHyperlink, tip, "unit:" .. guid)
                    local l1 = _G.ForeverCompanionProbeTipTextLeft1
                    P("    tooltip by guid:", ok2 and "ok" or "ERROR", " line 1:", l1 and S(l1:GetText()) or "nil")
                    tip:Hide()
                end
            end
        end
    end
    P("names cached:", nameCount)
    -- a beacon in the world: does this client have the game's waypoint (user waypoint, super tracking)?
    P("-- waypoint")
    P("C_Map.SetUserWaypoint:", type(C_Map and C_Map.SetUserWaypoint), " CanSetUserWaypointOnMap:", type(C_Map and C_Map.CanSetUserWaypointOnMap),
        " C_SuperTrack:", type(C_SuperTrack), " SetSuperTrackedUserWaypoint:", type(C_SuperTrack and C_SuperTrack.SetSuperTrackedUserWaypoint))
    local here = ns.PlayerPos()
    if here and C_Map and C_Map.CanSetUserWaypointOnMap then
        local ok, can = pcall(C_Map.CanSetUserWaypointOnMap, here)
        P("can set a waypoint in this zone:", ok and S(can) or "ERROR")
    end
    -- talents: what this client gives for the talent trees (for drawing them as the game does)
    P("-- talents")
    P("functions:", "GetNumTalentTabs", type(GetNumTalentTabs), " GetTalentTabInfo", type(GetTalentTabInfo), " GetNumTalents", type(GetNumTalents),
        " GetTalentInfo", type(GetTalentInfo), " GetTalentPrereqs", type(GetTalentPrereqs), " GetUnspentTalentPoints", type(GetUnspentTalentPoints),
        " C_SpecializationInfo", type(C_SpecializationInfo), " C_ClassTalents", type(C_ClassTalents))
    if GetNumTalentTabs and GetTalentTabInfo then
        local okN, nTabs = pcall(GetNumTalentTabs)
        P("tabs:", okN and S(nTabs) or "ERROR")
        for tab = 1, (okN and tonumber(nTabs) or 0) do
            P("tab", tab, "info:", Call(GetTalentTabInfo, tab))
            local okI, a1, a2, a3, a4, a5, a6 = pcall(GetTalentTabInfo, tab)
            if okI then P("  all returns:", S(a1), S(a2), S(a3), S(a4), S(a5), S(a6)) end
            local okT, num = pcall(GetNumTalents, tab)
            P("  talents in the tree:", okT and S(num) or "ERROR")
            if okT and tonumber(num) and GetTalentInfo then
                for i = 1, math.min(3, tonumber(num)) do
                    local ok2, r1, r2, r3, r4, r5, r6, r7, r8, r9 = pcall(GetTalentInfo, tab, i)
                    if ok2 then
                        P("  talent", i, ":", S(r1), S(r2), S(r3), S(r4), S(r5), S(r6), S(r7), S(r8), S(r9))
                    else
                        P("  talent", i, ": ERROR")
                    end
                    if GetTalentPrereqs then
                        local okP, p1, p2, p3 = pcall(GetTalentPrereqs, tab, i)
                        P("    prereqs:", okP and (S(p1) .. " " .. S(p2) .. " " .. S(p3)) or "ERROR")
                    end
                end
            end
            if tab >= 1 then break end -- (one tree is enough to see the shape)
        end
    end
    -- this client has no classic talent functions: the newer talent system (C_Traits). What does it give?
    do
        local function Names(t)
            local n = {}
            for k, v in pairs(t or {}) do if type(v) == "function" then n[#n + 1] = k end end
            table.sort(n)
            return table.concat(n, " ")
        end
        P("C_SpecializationInfo:", Names(C_SpecializationInfo))
        P("C_ClassTalents:", Names(C_ClassTalents))
        P("C_Traits:", type(C_Traits), Names(C_Traits))
        local cfg = C_ClassTalents and C_ClassTalents.GetActiveConfigID and select(2, pcall(C_ClassTalents.GetActiveConfigID))
        P("active config id:", S(cfg))
        local function Dump(label, t)
            if type(t) ~= "table" then P("  ", label, ":", S(t)) return end
            local parts = {}
            for k, v in pairs(t) do
                local kind = type(v)
                if kind == "table" then parts[#parts + 1] = tostring(k) .. "=table(" .. #v .. ")"
                elseif kind ~= "function" then parts[#parts + 1] = tostring(k) .. "=" .. S(v) end
            end
            table.sort(parts)
            P("  ", label, ":", table.concat(parts, " "))
        end
        if cfg and C_Traits and C_Traits.GetConfigInfo then
            local okC, info = pcall(C_Traits.GetConfigInfo, cfg)
            Dump("config", okC and info or nil)
            local trees = okC and type(info) == "table" and info.treeIDs or {}
            for _, treeID in ipairs(trees) do
                local okT, nodes = pcall(C_Traits.GetTreeNodes, treeID)
                P(" tree", S(treeID), "nodes:", okT and S(type(nodes) == "table" and #nodes) or "ERROR")
                if C_Traits.GetTreeInfo then
                    local okI, tinfo = pcall(C_Traits.GetTreeInfo, cfg, treeID)
                    Dump("tree info", okI and tinfo or nil)
                end
                if okT and type(nodes) == "table" then
                    for i = 1, math.min(3, #nodes) do
                        local okN, node = pcall(C_Traits.GetNodeInfo, cfg, nodes[i])
                        Dump("node " .. S(nodes[i]), okN and node or nil)
                        local entryID = okN and type(node) == "table" and node.entryIDs and node.entryIDs[1]
                        if entryID and C_Traits.GetEntryInfo then
                            local okE, entry = pcall(C_Traits.GetEntryInfo, cfg, entryID)
                            Dump("entry " .. S(entryID), okE and entry or nil)
                            local defID = okE and type(entry) == "table" and entry.definitionID
                            if defID and C_Traits.GetDefinitionInfo then
                                local okD, def = pcall(C_Traits.GetDefinitionInfo, defID)
                                Dump("definition " .. S(defID), okD and def or nil)
                            end
                        end
                        if okN and type(node) == "table" and type(node.visibleEdges) == "table" and node.visibleEdges[1] then
                            Dump("first edge", node.visibleEdges[1])
                        end
                    end
                end
            end
        end
    end
    P("texture tests:")
    for _, path in ipairs({ "Interface\\TalentFrame\\UI-TalentArrows", "Interface\\TalentFrame\\UI-TalentBranches",
        "Interface\\TalentFrame\\TalentFrame-Parchment-TopLeft" }) do
        local fileId = GetFileIDFromPath and select(2, pcall(GetFileIDFromPath, path))
        P("  ", path, " file id:", S(fileId))
    end
    -- is the waypoint the one that is followed, and what draws it in the world?
    local function Q(fn, ...) if type(fn) ~= "function" then return "no function" end local ok, v = pcall(fn, ...) return ok and S(v) or "ERROR" end
    do
        local okU, uy, ux, uz = pcall(UnitPosition, "player")
        P("UnitPosition (y, x, z):", okU and S(uy) or "ERROR", okU and S(ux) or "", okU and S(uz) or "")
    end
    P("has user waypoint:", Q(C_Map and C_Map.HasUserWaypoint))
    P("super tracking the waypoint:", Q(C_SuperTrack and C_SuperTrack.IsSuperTrackingUserWaypoint))
    P("super tracked type:", Q(C_SuperTrack and C_SuperTrack.GetHighestPrioritySuperTrackingType))
    P("C_Navigation:", type(C_Navigation), " SuperTrackedFrame:", type(_G.SuperTrackedFrame),
        " shown:", _G.SuperTrackedFrame and S(_G.SuperTrackedFrame:IsShown()) or "-")
    if type(C_Navigation) == "table" then
        for _, fn in ipairs({ "GetDistance", "GetTargetState", "GetFrame", "WasClampedToScreen", "HasValidScreenPosition" }) do
            P("  C_Navigation." .. fn .. ":", Q(C_Navigation[fn]))
        end
    end
    -- the game's own settings about sparkles, outlines and highlights of objects
    P("-- settings of the game (sparkle, glow, outline, highlight, soft target, interact)")
    local cmds = (C_Console and C_Console.GetAllCommands and C_Console.GetAllCommands()) or (ConsoleGetAllCommands and ConsoleGetAllCommands()) or {}
    local found = 0
    for _, cmd in ipairs(cmds) do
        local name = cmd.command or cmd.name
        if type(name) == "string" and found < 60 then
            local low = name:lower()
            if low:find("beam", 1, true) or low:find("waypoint", 1, true) or low:find("supertrack", 1, true) or low:find("navigation", 1, true)
                or low:find("sparkle", 1, true) or low:find("glow", 1, true) or low:find("outline", 1, true) or low:find("highlight", 1, true)
                or low:find("softtarget", 1, true) or low:find("interact", 1, true) then
                found = found + 1
                local okv, value = pcall(GetCVar, name)
                P("  ", name, "=", okv and S(value) or "?")
            end
        end
    end
    if #cmds == 0 then P("  (the list of settings cannot be read on this client)") end
    ns.W.Console(table.concat(out, "\n"), "Companion probe (copy and send)")
end

SLASH_FOREVERCOMPANION1 = "/fc"
SLASH_FOREVERCOMPANION2 = "/companion"
SLASH_FOREVERCOMPANION5 = "/codex"
SLASH_FOREVERCOMPANION3 = "/fkl" -- the old name
SLASH_FOREVERCOMPANION4 = "/killlog"
SlashCmdList.FOREVERCOMPANION = function(msg)
    local cmd, arg = (msg or ""):lower():match("^(%S*)%s*(%S*)")
    if cmd == "reset" then
        if arg == "all" then
            ns.ResetAll()
            print("|cffffd100ForeverCompanion:|r " .. L["All data deleted."])
        else
            ns.EndSession()
            print("|cffffd100ForeverCompanion:|r " .. L["Session ended."])
        end
    elseif cmd == "pause" then
        ns.TogglePause()
        print("|cffffd100ForeverCompanion:|r " .. (ns.session.paused and L["Session paused."] or L["Session resumed."]))
    elseif cmd == "end" then
        ns.EndSession()
        print("|cffffd100ForeverCompanion:|r " .. L["Session ended."])
    elseif cmd == "value" then
        if arg == "vendor" or arg == "auction" then ns.db.valueSource = arg end
        print("|cffffd100ForeverCompanion:|r " .. L["Value source: %s"]:format(L[ns.db.valueSource]))
        ns.Refresh()
    elseif cmd == "minimap" then
        local icon = LibStub and LibStub("LibDBIcon-1.0", true)
        if icon and ns.db.minimap then
            ns.db.minimap.hide = not ns.db.minimap.hide
            if ns.db.minimap.hide then icon:Hide("ForeverCompanion") else icon:Show("ForeverCompanion") end
        end
    elseif cmd == "help" then
        print("|cffffd100ForeverCompanion:|r " .. L["Commands: /fc, /fc journal, /fc nav, /fc reset, /fc minimap"])
    elseif cmd == "debug" then
        ns.db.debug = not ns.db.debug
        print("|cffffd100ForeverCompanion:|r " .. (ns.db.debug and "debug on: gather something and read the lines" or "debug off"))
    elseif cmd == "probe" then
        ns.Probe()
    elseif cmd == "atlas" then
        -- /fc atlas word word ...: the names of the game's atlases that have all the words (to find pictures by name)
        local words = {}
        for w in (msg or ""):lower():gsub("^%s*atlas%s*", ""):gmatch("%S+") do words[#words + 1] = w end
        local out, shown = {}, 0
        if C_Texture and C_Texture.GetAtlasElements and #words > 0 then
            local ok, names = pcall(C_Texture.GetAtlasElements)
            if ok and type(names) == "table" then
                table.sort(names)
                for _, n in ipairs(names) do
                    local low = tostring(n):lower()
                    local all = true
                    for _, w in ipairs(words) do if not low:find(w, 1, true) then all = false break end end
                    if all then
                        shown = shown + 1
                        if shown <= 400 then
                            local info = C_Texture.GetAtlasInfo and C_Texture.GetAtlasInfo(n)
                            out[#out + 1] = tostring(n) .. (info and ("  " .. tostring(info.width) .. "x" .. tostring(info.height)) or "")
                        end
                    end
                end
            end
        end
        local head = ("%d atlases with: %s"):format(shown, table.concat(words, " "))
        if shown > 400 then head = head .. "   (the first 400 are shown: add a word)" end
        if #words == 0 then head = "Use: /fc atlas word word ... (all words must be in the name)" end
        ns.W.Console(head .. "\n" .. table.concat(out, "\n"), "Atlas search (copy and send)")
    elseif cmd == "glow" then
        if ns.WorldGlow then ns.W.Console(ns.WorldGlow.Report(), "Companion glow (copy and send)") end
    elseif cmd == "accdebug" then
        ns.Acc.Debug()
    elseif cmd == "account" or cmd == "alts" then
        ns.AccountWindow.Toggle()
    elseif cmd == "settings" or cmd == "options" then
        ns.Settings.Toggle()
    elseif cmd == "journal" or cmd == "j" then
        ns.UI.Toggle()
    elseif cmd == "nav" then
        if ns.Routes then ns.Routes.ToggleNav() end
    else
        ns.HUD.Toggle()
    end
end
