local ADDON, ns = ...
local L = ns.L

-- The account: everything the addon learns about each of your characters, kept in the saved
-- variables so that the account window can show all of them, whoever is logged in. What is
-- known depends on what each character has done: the character itself is read on login, the
-- bank when its window is opened, the mail at a mailbox, recipes when a profession window is
-- opened, auctions at the auction house. Every part has the time it was last read.

local Acc = {}
ns.Acc = Acc

local PART_TIMES = { "info", "equip", "bags", "bank", "mail", "skills", "recipes", "auctions" }
Acc.PARTS = PART_TIMES

function Acc.Enabled() return ns.db and ns.db.settings and ns.db.settings.accTrack ~= false end

local function Root()
    local db = ns.db
    if not db then return nil end
    db.account = db.account or { chars = {}, links = {} }
    db.account.links = db.account.links or {}
    return db.account
end

-- Character names are unique on WoW Forever, and a character can move between realms, so the name alone is
-- the key; the realm is only a property that is kept up to date.
function Acc.MyKey()
    return UnitName("player") or "?"
end

local function RealmNow()
    local realm = GetRealmName and GetRealmName()
    return (realm and realm ~= "") and realm or nil
end

-- Records of older versions were keyed "Name-Realm" (with an empty realm if it was not known yet at login), so
-- one character could exist twice. They are merged: the data of the more recently seen record wins, and each
-- part (equipment, bags, ...) comes from whichever record scanned it last.
local PARTS = { "equip", "bags", "bank", "mail", "skills", "recipes", "auctions" }
local merged
local function MergeLegacy()
    local root = Root()
    if merged or not root then return end
    merged = true
    local keys = {}
    for key in pairs(root.chars) do keys[#keys + 1] = key end
    for _, key in ipairs(keys) do
        local rec = root.chars[key]
        local name = rec and (rec.name or key:match("^(.-)%-")) or nil
        if rec and name and name ~= "" and key ~= name then
            root.chars[key] = nil
            local other = root.chars[name]
            if not other then
                rec.key, rec.name = name, name
                root.chars[name] = rec
            else
                local win, lose = other, rec
                if (rec.lastSeen or 0) > (other.lastSeen or 0) then win, lose = rec, other end
                for k, v in pairs(lose) do
                    if win[k] == nil then win[k] = v end
                end
                win.at = win.at or {}
                for _, part in ipairs(PARTS) do
                    local tw, tl = win.at[part] or 0, (lose.at and lose.at[part]) or 0
                    if tl > tw then win[part], win.at[part] = lose[part], tl end
                end
                if not win.realm or win.realm == "" then win.realm = lose.realm end
                win.key, win.name = name, name
                root.chars[name] = win
            end
        end
    end
end

-- the record of the character that is logged in (made on first use)
function Acc.Me()
    local root = Root()
    if not root or not Acc.Enabled() then return nil end
    MergeLegacy()
    local key = Acc.MyKey()
    local rec = root.chars[key]
    if not rec then
        rec = { key = key, name = UnitName("player"), realm = RealmNow(),
            equip = {}, bags = {}, bank = {}, mail = {}, skills = {}, recipes = {}, auctions = {}, at = {} }
        root.chars[key] = rec
    end
    rec.at = rec.at or {}
    rec.realm = RealmNow() or rec.realm -- a character may have moved to another realm
    return rec
end

local function Stamp(rec, part) rec.at[part] = time() end

local function Link(id, link)
    local root = Root()
    if root and id and link and link ~= "" then root.links[id] = link end
end

function Acc.LinkOf(id)
    local root = Root()
    return root and root.links[id] or ("item:" .. id)
end

local function IdOf(link)
    return link and tonumber(link:match("item:(%d+)")) or nil
end

-- a skill line that is a profession or a secondary skill (not a weapon skill or a language)
local PROF_HEADERS = { "professions", "secondary skills", "trade skills", "berufe", "nebenberufe" }
for _, g in ipairs({ "TRADE_SKILLS", "SECONDARY_SKILLS", "PROFESSIONS_BUTTON" }) do
    if _G[g] then PROF_HEADERS[#PROF_HEADERS + 1] = tostring(_G[g]):lower() end
end
function Acc.IsProfession(skill)
    local h = (skill.header or ""):lower()
    for _, name in ipairs(PROF_HEADERS) do
        if h == name then return true end
    end
    return false
end

-- cooking, fishing and first aid: the secondary skills
local SECONDARY_HEADERS = { "secondary skills", "nebenberufe" }
if _G.SECONDARY_SKILLS then SECONDARY_HEADERS[#SECONDARY_HEADERS + 1] = tostring(_G.SECONDARY_SKILLS):lower() end
function Acc.IsSecondary(skill)
    local h = (skill.header or ""):lower()
    for _, name in ipairs(SECONDARY_HEADERS) do
        if h == name then return true end
    end
    return false
end

-- a picture for a profession (by its English or German name)
local PROF_ICONS = {
    alchemy = "Trade_Alchemy", alchemie = "Trade_Alchemy",
    blacksmithing = "Trade_BlackSmithing", schmiedekunst = "Trade_BlackSmithing",
    enchanting = "Trade_Engraving", verzauberkunst = "Trade_Engraving",
    engineering = "Trade_Engineering", ingenieurskunst = "Trade_Engineering",
    herbalism = "Trade_Herbalism", ["kräuterkunde"] = "Trade_Herbalism",
    leatherworking = "Trade_LeatherWorking", lederverarbeitung = "Trade_LeatherWorking",
    mining = "Trade_Mining", bergbau = "Trade_Mining",
    skinning = "INV_Misc_Pelt_Wolf_01", ["kürschnerei"] = "INV_Misc_Pelt_Wolf_01",
    tailoring = "Trade_Tailoring", schneiderei = "Trade_Tailoring",
    cooking = "INV_Misc_Food_15", kochkunst = "INV_Misc_Food_15",
    fishing = "Trade_Fishing", angeln = "Trade_Fishing",
    ["first aid"] = "Spell_Holy_SealOfSacrifice", ["erste hilfe"] = "Spell_Holy_SealOfSacrifice",
    jewelcrafting = "INV_Misc_Gem_01", juwelenschleifen = "INV_Misc_Gem_01",
    inscription = "INV_Inscription_Tradeskill01", inschriftenkunde = "INV_Inscription_Tradeskill01",
    lockpicking = "Spell_Nature_MoonKey", ["schlossknacken"] = "Spell_Nature_MoonKey",
    poisons = "Ability_Poisons", gifte = "Ability_Poisons",
}
function Acc.ProfIcon(name)
    local file = PROF_ICONS[(name or ""):lower()]
    return file and ("Interface\\Icons\\" .. file) or nil
end

-- What a skill line is: a profession ("primary"), cooking, fishing or first aid ("secondary"), or
-- something else (riding, weapon skills, languages: nil). The name decides first, because clients
-- differ in which heading they list the skills under.
local SECONDARY_NAMES = { cooking = true, kochkunst = true, fishing = true, angeln = true, ["first aid"] = true,
    ["erste hilfe"] = true, archaeology = true, ["archäologie"] = true }
local OTHER_NAMES = { riding = true, reiten = true, lockpicking = true, schlossknacken = true, poisons = true, gifte = true }
function Acc.SkillKind(skill)
    local n = (skill.name or ""):lower()
    if SECONDARY_NAMES[n] then return "secondary" end
    if OTHER_NAMES[n] then return nil end
    if PROF_ICONS[n] then return "primary" end
    if Acc.IsProfession(skill) then return Acc.IsSecondary(skill) and "secondary" or "primary" end
    return nil
end

-- the character -------------------------------------------------------------------------
-- The client reports empty values (0, nothing) while it loads or shuts down, and some facts only
-- exist at times (a guild, rested experience). A value that looks empty never replaces one that is
-- known; a fact that is really gone (no guild, no rested bonus) is cleared on purpose.
local function Keep(rec, key, value, valid)
    if valid == nil then valid = value ~= nil and value ~= "" end
    if valid then rec[key] = value end
end

-- A surname (or title) is whatever the client's full name adds to the plain name: "Aldric the Bold" gives "the Bold".
-- The raw values are shown by /fc accdebug, in case this client puts it elsewhere.
local function SurnameOf()
    local name, full = UnitName("player"), UnitPVPName and UnitPVPName("player")
    if not (name and full) or full == name then return nil end
    local s, e = full:find(name, 1, true)
    if not s then return nil end
    local after = full:sub(e + 1):gsub("^[%s,]+", ""):gsub("%s+$", "")
    return after ~= "" and after or nil
end

-- the name as shown in the account window: with the surname if the setting is on
function Acc.NameOf(rec)
    local name = rec and rec.name or "?"
    if rec and rec.surname and ns.db and ns.db.settings and ns.db.settings.accSurname ~= false then
        return name .. " " .. rec.surname
    end
    return name
end

local function ScanInfo()
    local rec = Acc.Me()
    if not rec then return end
    rec.surname = SurnameOf()
    local className, classFile = UnitClass("player")
    local raceName, raceFile = UnitRace("player")
    local level = UnitLevel("player")
    Keep(rec, "level", level, level and level > 0)
    Keep(rec, "class", classFile)
    Keep(rec, "className", className)
    Keep(rec, "race", raceName)
    Keep(rec, "raceFile", raceFile)
    Keep(rec, "sex", UnitSex("player"))
    Keep(rec, "faction", UnitFactionGroup("player"))
    local money = GetMoney()
    Keep(rec, "money", money, money and (money > 0 or not rec.money))
    -- experience: the maximum must be real, then the current value belongs to it
    local xp, xpMax = UnitXP("player"), UnitXPMax("player")
    if xpMax and xpMax > 0 then
        rec.xp, rec.xpMax = xp or 0, xpMax
        rec.rested = GetXPExhaustion and GetXPExhaustion() or nil -- none: no bonus
    elseif level and level > 0 and not rec.xpMax then
        rec.xpMax = 0 -- the highest level: no experience bar
    end
    if IsInGuild and not IsInGuild() then
        rec.guild = nil
    else
        Keep(rec, "guild", GetGuildInfo and (GetGuildInfo("player")) or nil)
    end
    Keep(rec, "zone", (GetRealZoneText and GetRealZoneText()) or GetZoneText())
    rec.sub = GetSubZoneText()
    Keep(rec, "hearth", GetBindLocation and GetBindLocation() or nil)
    if GetAverageItemLevel then
        local _, equipped = GetAverageItemLevel()
        Keep(rec, "ilvl", equipped, equipped and equipped > 0)
    end
    rec.resting = IsResting and IsResting() and true or false
    rec.lastSeen = time()
    Stamp(rec, "info")
end

-- time played: asked for once per login; the chat line it would print is held back meanwhile
local playedFrames
local function RequestPlayed()
    if not RequestTimePlayed then return end
    playedFrames = {}
    for i = 1, (NUM_CHAT_WINDOWS or 10) do
        local cf = _G["ChatFrame" .. i]
        if cf and cf.IsEventRegistered and cf:IsEventRegistered("TIME_PLAYED_MSG") then
            cf:UnregisterEvent("TIME_PLAYED_MSG")
            playedFrames[#playedFrames + 1] = cf
        end
    end
    RequestTimePlayed()
    C_Timer.After(4, function()
        for _, cf in ipairs(playedFrames or {}) do cf:RegisterEvent("TIME_PLAYED_MSG") end
        playedFrames = nil
    end)
end

-- equipment -------------------------------------------------------------------------------
Acc.SLOTS = {
    { 1, L["Head"] }, { 2, L["Neck"] }, { 3, L["Shoulders"] }, { 15, L["Back"] }, { 5, L["Chest"] },
    { 9, L["Wrists"] }, { 10, L["Hands"] }, { 6, L["Waist"] }, { 7, L["Legs"] }, { 8, L["Feet"] },
    { 11, L["Finger 1"] }, { 12, L["Finger 2"] }, { 13, L["Trinket 1"] }, { 14, L["Trinket 2"] },
    { 16, L["Main hand"] }, { 17, L["Off hand"] }, { 18, L["Ranged"] }, { 4, L["Shirt"] }, { 19, L["Tabard"] },
}

local function ScanEquipment()
    local rec = Acc.Me()
    if not rec then return end
    local eq = {}
    for slot = 1, 19 do
        local link = GetInventoryItemLink("player", slot)
        if link then
            eq[slot] = link
            Link(IdOf(link), link)
        end
    end
    rec.equip = eq
    Stamp(rec, "equip")
end

-- bags and bank ---------------------------------------------------------------------------
local function NumSlots(bag)
    if C_Container and C_Container.GetContainerNumSlots then return C_Container.GetContainerNumSlots(bag) or 0 end
    if GetContainerNumSlots then return GetContainerNumSlots(bag) or 0 end
    return 0
end
local function SlotItem(bag, slot)
    if C_Container and C_Container.GetContainerItemInfo then
        local info = C_Container.GetContainerItemInfo(bag, slot)
        if info then return info.itemID, info.stackCount or 1, info.hyperlink, info.isBound end
    elseif GetContainerItemInfo then
        local _, count, _, _, _, _, link, _, _, id, bound = GetContainerItemInfo(bag, slot)
        if id or link then return id or IdOf(link), count or 1, link, bound end
    end
end

local function ScanContainers(bags, sizeFrom, sizeTo)
    local items, bound, total, free = {}, {}, 0, 0
    local sizes = {} -- how many slots each bag has, in the order of the list (from sizeFrom on: the first ones are not bags that can be changed)
    for i, bag in ipairs(bags) do
        local n = NumSlots(bag)
        if i >= (sizeFrom or 1) and i <= (sizeTo or #bags) then sizes[#sizes + 1] = n end
        total = total + n
        for slot = 1, n do
            local id, count, link, isBound = SlotItem(bag, slot)
            if id then
                items[id] = (items[id] or 0) + (count or 1)
                if isBound then bound[id] = (bound[id] or 0) + (count or 1) end
                Link(id, link)
            else
                free = free + 1
            end
        end
    end
    return { items = items, bound = bound, slots = total, free = free, sizes = sizes }
end

-- The reagent bag (its own slot beside the four bags, where the client has one) counts as a bag: its number is the one after the bags, and the
-- bank bags come after it.
local function ReagentBagId()
    local id = Enum and Enum.BagIndex and Enum.BagIndex.ReagentBag
    if id then return id end
    if (NUM_REAGENTBAG_SLOTS or 0) > 0 then return (NUM_BAG_SLOTS or 4) + 1 end
end

local function ScanBags()
    local rec = Acc.Me()
    if not rec then return end
    local list = {}
    for bag = 0, (NUM_BAG_SLOTS or 4) do list[#list + 1] = bag end
    local reagent = ReagentBagId()
    if reagent then list[#list + 1] = reagent end
    rec.bags = ScanContainers(list, 2)
    Stamp(rec, "bags")
end

local bankOpen = false
local function ScanBank()
    local rec = Acc.Me()
    if not rec or not bankOpen then return end
    local list = { BANK_CONTAINER or -1 }
    local first = (ReagentBagId() or (NUM_BAG_SLOTS or 4)) + 1 -- (after the bags, and the reagent bag if there is one)
    for bag = first, first + (NUM_BANKBAGSLOTS or 7) - 1 do list[#list + 1] = bag end
    if REAGENTBANK_CONTAINER then list[#list + 1] = REAGENTBANK_CONTAINER end
    rec.bank = ScanContainers(list, 2, #list - ((REAGENTBANK_CONTAINER and 1) or 0)) -- (not the bank itself, nor the reagent bank: their size is fixed)
    Stamp(rec, "bank")
end

-- mail ------------------------------------------------------------------------------------
local function ScanMail()
    local rec = Acc.Me()
    if not rec or not GetInboxNumItems then return end
    local list = {}
    local n = GetInboxNumItems() or 0
    for i = 1, n do
        local _, _, sender, subject, money, cod, daysLeft, itemCount = GetInboxHeaderInfo(i)
        local atts = {}
        for j = 1, (ATTACHMENTS_MAX_RECEIVE or 16) do
            local link = GetInboxItemLink and GetInboxItemLink(i, j)
            if link then
                local _, _, _, count = GetInboxItem(i, j)
                local id = IdOf(link)
                atts[#atts + 1] = { id = id, count = count or 1 }
                Link(id, link)
            end
        end
        list[#list + 1] = { sender = sender, subject = subject, money = money or 0, cod = cod or 0,
            expires = time() + math.floor((daysLeft or 0) * 86400), items = atts }
    end
    rec.mail = { list = list }
    Stamp(rec, "mail")
end

-- professions and the recipes of the open profession window -----------------------------------
local function ScanSkills()
    local rec = Acc.Me()
    if not rec then return end
    local list = {}
    if GetNumSkillLines and GetSkillLineInfo then
        local header
        for i = 1, GetNumSkillLines() do
            local name, isHeader, _, rank, _, _, maxRank = GetSkillLineInfo(i)
            if isHeader then
                header = name
            elseif name then
                list[#list + 1] = { name = name, rank = rank or 0, max = maxRank or 0, header = header }
            end
        end
    elseif GetProfessions and GetProfessionInfo then
        for _, idx in pairs({ GetProfessions() }) do
            local name, icon, rank, maxRank = GetProfessionInfo(idx)
            if name then list[#list + 1] = { name = name, rank = rank or 0, max = maxRank or 0, icon = icon, header = "Professions" } end
        end
    end
    rec.skills = list
    -- recipes of a profession that the character does not have (any more: it was dropped, or the data came from a wrong window) are taken away.
    -- Only when the list of skills is plausible: at least one profession with recipes is in it (a collapsed header would show none).
    if rec.recipes and #list > 0 then
        local have = {}
        for _, sk in ipairs(list) do have[tostring(sk.name):lower()] = true end
        local known, stale = false, {}
        for pname in pairs(rec.recipes) do
            if have[tostring(pname):lower()] then known = true else stale[#stale + 1] = pname end
        end
        if known then for _, pname in ipairs(stale) do rec.recipes[pname] = nil end end
    end
    Stamp(rec, "skills")
end

-- what the last recipe scans did (for /fc accdebug)
Acc.dbg = { events = {}, last = {} }

-- one recipe: its name, how hard it is, the item it makes and what it needs
local function ReagentsClassic(count, info, link, i)
    local list = {}
    for j = 1, (count(i) or 0) do
        local _, _, need = info(i, j)
        local id = IdOf(link(i, j))
        if id then
            Link(id, link(i, j))
            list[#list + 1] = { id = id, count = need or 1 }
        end
    end
    return list
end

local function ScanRecipes(kind)
    local rec = Acc.Me()
    if not rec then return end
    local name, list = nil, {}
    local api
    if kind == "trade" and GetTradeSkillLine and GetNumTradeSkills then
        api = "classic trade"
        name = GetTradeSkillLine()
        for i = 1, GetNumTradeSkills() do
            local rname, rtype = GetTradeSkillInfo(i)
            if rname and rtype ~= "header" then
                local link = GetTradeSkillItemLink and GetTradeSkillItemLink(i) or nil
                local reagents = GetTradeSkillNumReagents and ReagentsClassic(GetTradeSkillNumReagents,
                    GetTradeSkillReagentInfo, GetTradeSkillReagentItemLink, i) or {}
                list[#list + 1] = { name = rname, difficulty = rtype, link = link, id = IdOf(link), reagents = reagents }
                Link(IdOf(link), link)
            end
        end
    elseif kind == "craft" and GetCraftDisplaySkillLine and GetNumCrafts then
        api = "classic craft"
        name = GetCraftDisplaySkillLine()
        for i = 1, GetNumCrafts() do
            local rname, _, rtype = GetCraftInfo(i)
            if rname and rtype ~= "header" then
                local link = GetCraftItemLink and GetCraftItemLink(i) or nil
                local reagents = GetCraftNumReagents and ReagentsClassic(GetCraftNumReagents,
                    GetCraftReagentInfo, GetCraftReagentItemLink, i) or {}
                list[#list + 1] = { name = rname, difficulty = rtype, link = link, id = IdOf(link), reagents = reagents }
            end
        end
    elseif kind == "trade" and C_TradeSkillUI and C_TradeSkillUI.GetAllRecipeIDs then
        api = "modern"
        local base = C_TradeSkillUI.GetBaseProfessionInfo and C_TradeSkillUI.GetBaseProfessionInfo()
        name = base and base.professionName
        if not name and C_TradeSkillUI.GetTradeSkillLine then name = select(2, C_TradeSkillUI.GetTradeSkillLine()) end
        for _, rid in ipairs(C_TradeSkillUI.GetAllRecipeIDs() or {}) do
            local info = C_TradeSkillUI.GetRecipeInfo(rid)
            if info and info.learned then
                local reagents, product = {}, nil
                local ok, schematic = pcall(C_TradeSkillUI.GetRecipeSchematic, rid, false)
                if ok and schematic then
                    product = schematic.outputItemID
                    for _, slot in ipairs(schematic.reagentSlotSchematics or {}) do
                        local first = slot.reagents and slot.reagents[1]
                        if first and first.itemID then
                            reagents[#reagents + 1] = { id = first.itemID, count = slot.quantityRequired or 1 }
                        end
                    end
                end
                list[#list + 1] = { name = info.name, difficulty = "optimal", link = info.hyperlink, id = product, reagents = reagents }
            end
        end
    else
        Acc.dbg.last[kind] = "no recipe API for " .. kind
        return
    end
    Acc.dbg.last[kind] = ("%s: profession %s, %d recipes"):format(api, tostring(name), #list)
    if not name or name == "UNKNOWN" or #list == 0 then return end
    rec.recipes[name] = { list = list, time = time() }
    Stamp(rec, "recipes")
end

-- auctions --------------------------------------------------------------------------------
-- The history of the auctions: an auction that was in the list of a character and is not in it any more is noted (ns.db.ahHistory, the latest
-- last) as sold, run out or cancelled. Cancelled is known from the game's message; run out when its time was up; otherwise it was sold.
local cancelledIds = {}
local HISTORY_MAX = 500
local function PushHistory(entry)
    if not ns.db then return end
    local h = ns.db.ahHistory
    if not h then h = {}; ns.db.ahHistory = h end
    h[#h + 1] = entry
    while #h > HISTORY_MAX do table.remove(h, 1) end
end

local function NoteEnded(rec, old, list)
    local now = time()
    local present, used = {}, {}
    for _, a in ipairs(list) do if a.auctionID then present[a.auctionID] = true end end
    for _, o in ipairs(old) do
        local still = false
        if o.auctionID then
            still = present[o.auctionID] and true or false
        else
            for j, a in ipairs(list) do
                if not used[j] and not a.auctionID and a.id == o.id and a.count == o.count and a.buyout == o.buyout then used[j] = true; still = true break end
            end
        end
        if not still then
            local state = "sold"
            if o.auctionID and cancelledIds[o.auctionID] then state = "cancelled"
            elseif o.left and o.left <= now + 90 then state = "expired" end
            PushHistory({ id = o.id, count = o.count, buyout = o.buyout, char = rec.key, state = state, at = now })
        end
    end
end

local function ScanAuctions()
    local rec = Acc.Me()
    if not rec then return end
    local list = {}
    local complete = true
    if C_AuctionHouse and C_AuctionHouse.GetNumOwnedAuctions and C_AuctionHouse.GetOwnedAuctionInfo then
        local soldStatus = Enum and Enum.AuctionStatus and Enum.AuctionStatus.Sold
        if C_AuctionHouse.HasFullOwnedAuctionResults then complete = C_AuctionHouse.HasFullOwnedAuctionResults() and true or false end
        for i = 1, C_AuctionHouse.GetNumOwnedAuctions() do
            local info = C_AuctionHouse.GetOwnedAuctionInfo(i)
            local id = info and info.itemKey and info.itemKey.itemID
            -- (a sold auction is not on offer any more: it falls out of the list and is noted as sold)
            if id and not (soldStatus and info.status == soldStatus) then
                list[#list + 1] = { id = id, count = info.quantity or 1, buyout = info.buyoutAmount or 0, auctionID = info.auctionID,
                    left = info.timeLeftSeconds and (time() + info.timeLeftSeconds) or nil }
            end
        end
    elseif GetNumAuctionItems then
        local n = GetNumAuctionItems("owner") or 0
        for i = 1, n do
            local _, _, count, _, _, _, _, _, _, buyout, _, _, _, _, _, _, id = GetAuctionItemInfo("owner", i)
            local link = GetAuctionItemLink and GetAuctionItemLink("owner", i)
            id = id or IdOf(link)
            if id then
                Link(id, link)
                local left = GetAuctionItemTimeLeft and GetAuctionItemTimeLeft("owner", i)
                list[#list + 1] = { id = id, count = count or 1, buyout = buyout or 0, left4 = left, seen = time() }
            end
        end
    else
        return
    end
    -- what was in the list and is not any more (only when the game has sent all of it, and the auction house is open)
    local old = rec.auctions and rec.auctions.list
    if old and complete and ns.AH and ns.AH.IsOpen and ns.AH.IsOpen() then pcall(NoteEnded, rec, old, list) end
    rec.auctions = { list = list }
    Stamp(rec, "auctions")
end

-- queries for the window and the tooltips -------------------------------------------------------
function Acc.Chars(skip)
    local root = Root()
    MergeLegacy()
    local list = {}
    if root then
        for _, rec in pairs(root.chars) do
            if not (skip and skip[rec.key]) then list[#list + 1] = rec end
        end
    end
    table.sort(list, function(a, b)
        if (a.level or 0) ~= (b.level or 0) then return (a.level or 0) > (b.level or 0) end
        return (a.name or "") < (b.name or "")
    end)
    return list
end

-- Realm and faction are not shown on a character; only when the account has more than one of them
-- the characters are grouped by it. Returns a function rec -> group name, or nil for no grouping.
function Acc.GroupFn()
    local realms, factions, nr, nf = {}, {}, 0, 0
    for _, rec in ipairs(Acc.Chars()) do
        if rec.realm and not realms[rec.realm] then realms[rec.realm] = true; nr = nr + 1 end
        if rec.faction and not factions[rec.faction] then factions[rec.faction] = true; nf = nf + 1 end
    end
    if nr <= 1 and nf <= 1 then return nil end
    return function(rec)
        local parts = {}
        if nr > 1 then parts[#parts + 1] = rec.realm or "?" end
        if nf > 1 then
            local f = rec.faction or "?"
            parts[#parts + 1] = _G["FACTION_" .. f:upper()] or f
        end
        return table.concat(parts, " – ")
    end
end

function Acc.Forget(key)
    local root = Root()
    if root and key ~= Acc.MyKey() then root.chars[key] = nil end
end

-- everything a character is worth: coins, mail, auctions, and what bags and bank hold
function Acc.WorthOf(rec)
    local sum = rec.money or 0
    for _, m in ipairs(rec.mail and rec.mail.list or {}) do sum = sum + (m.money or 0) end
    for _, a in ipairs(rec.auctions and rec.auctions.list or {}) do sum = sum + (a.buyout or 0) end
    for _, set in ipairs({ rec.bags or {}, rec.bank or {} }) do
        for id, n in pairs(set.items or {}) do sum = sum + ns.Value.Get(id) * n end
    end
    return sum
end

function Acc.Totals()
    local gold, worth, n = 0, 0, 0
    for _, rec in ipairs(Acc.Chars()) do
        gold = gold + (rec.money or 0)
        worth = worth + Acc.WorthOf(rec)
        n = n + 1
    end
    return { money = gold, worth = worth, chars = n }
end

local function ItemName(id)
    local link = Acc.LinkOf(id)
    local name = link:match("%[(.-)%]")
    if name then return name end
    local get = GetItemInfo or (C_Item and C_Item.GetItemInfo)
    return get and (get(id)) or nil
end
Acc.ItemName = ItemName

-- where an item is, per character: { rec, bags, bank, mail, equip, auction }
function Acc.Owners(id)
    local owners, total, tradable = {}, 0, 0
    for _, rec in ipairs(Acc.Chars()) do
        local o = { rec = rec, bags = rec.bags and rec.bags.items and rec.bags.items[id] or 0,
            bank = rec.bank and rec.bank.items and rec.bank.items[id] or 0, mail = 0, equip = 0, auction = 0 }
        for _, m in ipairs(rec.mail and rec.mail.list or {}) do
            for _, a in ipairs(m.items or {}) do if a.id == id then o.mail = o.mail + (a.count or 1) end end
        end
        for _, link in pairs(rec.equip or {}) do if IdOf(link) == id then o.equip = o.equip + 1 end end
        for _, a in ipairs(rec.auctions and rec.auctions.list or {}) do
            if a.id == id then o.auction = o.auction + (a.count or 1) end
        end
        local sum = o.bags + o.bank + o.mail + o.equip + o.auction
        if sum > 0 then
            o.sum = sum
            -- soulbound: the bound stacks of bags and bank, and what is worn
            o.bound = (rec.bags and rec.bags.bound and rec.bags.bound[id] or 0)
                + (rec.bank and rec.bank.bound and rec.bank.bound[id] or 0) + o.equip
            o.tradable = math.max(0, sum - o.bound)
            owners[#owners + 1] = o
            total = total + sum
            tradable = tradable + o.tradable
        end
    end
    table.sort(owners, function(a, b) return a.sum > b.sum end)
    return owners, total, tradable
end

-- what could be sold: id -> number of tradable pieces (not soulbound) in bags and bank, of the character that is
-- logged in, or of all characters
function Acc.Sellable(all)
    local out, me = {}, Acc.MyKey()
    for _, rec in ipairs(Acc.Chars()) do
        if all or rec.key == me then
            for _, set in ipairs({ rec.bags or {}, rec.bank or {} }) do
                for id, n in pairs(set.items or {}) do
                    local free = n - (set.bound and set.bound[id] or 0)
                    if free > 0 then out[id] = (out[id] or 0) + free end
                end
            end
        end
    end
    return out
end

-- what the chosen characters carry: id -> pieces, in the bags and/or the bank. keys: a set of character keys (nil:
-- all). tradable: leave out what is soulbound.
function Acc.Holdings(keys, bags, bank, tradable)
    local out = {}
    for _, rec in ipairs(Acc.Chars()) do
        if keys == nil or keys[rec.key] then
            for _, part in ipairs({ { bags, rec.bags }, { bank, rec.bank } }) do
                local on, set = part[1], part[2]
                if on and set then
                    for id, n in pairs(set.items or {}) do
                        local free = n - ((tradable and set.bound and set.bound[id]) or 0)
                        if free > 0 then out[id] = (out[id] or 0) + free end
                    end
                end
            end
        end
    end
    return out
end

-- how many of each item all characters have in bags, bank and mail: what can be crafted from
function Acc.MaterialIndex(skip)
    local idx = {}
    for _, rec in ipairs(Acc.Chars(skip)) do
        for id, n in pairs(rec.bags and rec.bags.items or {}) do idx[id] = (idx[id] or 0) + n end
        for id, n in pairs(rec.bank and rec.bank.items or {}) do idx[id] = (idx[id] or 0) + n end
        for _, m in ipairs(rec.mail and rec.mail.list or {}) do
            for _, att in ipairs(m.items or {}) do
                if att.id then idx[att.id] = (idx[att.id] or 0) + (att.count or 1) end
            end
        end
    end
    return idx
end

-- every recipe any character knows, with who knows it
function Acc.Recipes()
    local map, list = {}, {}
    for _, rec in ipairs(Acc.Chars()) do
        for prof, r in pairs(rec.recipes or {}) do
            for _, rc in ipairs(r.list or {}) do
                local key = prof .. ":" .. rc.name
                local e = map[key]
                if not e then
                    e = { key = key, name = rc.name, prof = prof, link = rc.link, id = rc.id, reagents = rc.reagents or {}, knownBy = {} }
                    map[key] = e
                    list[#list + 1] = e
                end
                e.knownBy[#e.knownBy + 1] = rec
                if #e.reagents == 0 and rc.reagents and #rc.reagents > 0 then e.reagents = rc.reagents end
            end
        end
    end
    return list
end

-- every item (by id) that any character has anywhere, for the search
function Acc.AllItemIds()
    local ids = {}
    for _, rec in ipairs(Acc.Chars()) do
        for id in pairs(rec.bags and rec.bags.items or {}) do ids[id] = true end
        for id in pairs(rec.bank and rec.bank.items or {}) do ids[id] = true end
        for _, link in pairs(rec.equip or {}) do
            local eid = IdOf(link)
            if eid then ids[eid] = true end
        end
        for _, m in ipairs(rec.mail and rec.mail.list or {}) do
            for _, a in ipairs(m.items or {}) do if a.id then ids[a.id] = true end end
        end
        for _, a in ipairs(rec.auctions and rec.auctions.list or {}) do if a.id then ids[a.id] = true end end
    end
    return ids
end

-- when a part of a character was last read, and a line saying what to do when it never was
Acc.HINT = {
    bank = L["Visit the bank with this character to read it."],
    mail = L["Open a mailbox with this character to read its mail."],
    recipes = L["Open a profession window with this character to read its recipes."],
    auctions = L["Visit the auction house with this character to read its auctions."],
    equip = L["Log in with this character to read its equipment."],
    bags = L["Log in with this character to read its bags."],
    skills = L["Log in with this character to read its professions."],
    info = L["Log in with this character to read it."],
}

-- events ---------------------------------------------------------------------------------------
local pending = {}
local function Queue(kind) pending[kind] = true end

-- talents -----------------------------------------------------------------------------------
-- This client has no classic talent functions; its talents are a trait tree (C_Traits). Every node of the tree is kept: where it sits
-- (the game's own coordinates), its rank, its spell and picture, and which nodes it leads to. That is enough to draw the tree as the game
-- does, also for a character that is not logged in.
-- The game does not say when a character last reset its talents (respec). What can be seen is the points spent: when they fall, the
-- talents were reset, and that moment is kept (rec.respecAt). Resets from before the addon watched the character are not known. Not noted
-- in the first moments after login (the data may still be arriving).
local loginAt = GetTime()

local function SpellPicture(spell)
    if not spell then return nil end
    local tex
    if C_Spell and C_Spell.GetSpellTexture then local ok, v = pcall(C_Spell.GetSpellTexture, spell) if ok then tex = v end end
    if not tex and GetSpellTexture then local ok, v = pcall(GetSpellTexture, spell) if ok then tex = v end end
    return tex
end

local function ScanTalents(fromEvent)
    local rec = Acc.Me()
    if not rec then return end
    if not (C_ClassTalents and C_ClassTalents.GetActiveConfigID and C_Traits and C_Traits.GetConfigInfo and C_Traits.GetTreeNodes) then return end
    local okC, cfg = pcall(C_ClassTalents.GetActiveConfigID)
    if not (okC and cfg) then return end
    local okI, info = pcall(C_Traits.GetConfigInfo, cfg)
    local treeID = okI and type(info) == "table" and info.treeIDs and info.treeIDs[1]
    if not treeID then return end
    local okN, ids = pcall(C_Traits.GetTreeNodes, treeID)
    if not (okN and type(ids) == "table" and #ids > 0) then return end
    local nodes, spent = {}, 0
    for _, id in ipairs(ids) do
        local ok, nd = pcall(C_Traits.GetNodeInfo, cfg, id)
        if ok and type(nd) == "table" and nd.ID and nd.posX and nd.isVisible ~= false then
            local rank = tonumber(nd.currentRank) or 0
            local entryID = (type(nd.activeEntry) == "table" and nd.activeEntry.entryID) or (nd.entryIDs and nd.entryIDs[1])
            local spell
            if entryID and C_Traits.GetEntryInfo then
                local okE, entry = pcall(C_Traits.GetEntryInfo, cfg, entryID)
                local defID = okE and type(entry) == "table" and entry.definitionID
                if defID and C_Traits.GetDefinitionInfo then
                    local okD, def = pcall(C_Traits.GetDefinitionInfo, defID)
                    spell = okD and type(def) == "table" and def.spellID or nil
                end
            end
            local edges = {}
            for _, e in ipairs(nd.visibleEdges or {}) do
                if type(e) == "table" and e.targetNode then edges[#edges + 1] = e.targetNode end
            end
            nodes[#nodes + 1] = { id = nd.ID, x = nd.posX, y = nd.posY, rank = rank, max = tonumber(nd.maxRanks) or 1, spell = spell,
                tex = SpellPicture(spell), edges = edges }
            spent = spent + rank
        end
    end
    if #nodes == 0 then return end
    local old = rec.talents
    if old and old.spent and spent < old.spent then
        if not (fromEvent and GetTime() - loginAt > 15) then return end -- (a short reading while loading: the old value stays)
        rec.respecAt = time()
    end
    local unspent = 0
    if C_Traits.GetTreeCurrencyInfo then
        local okU, cur = pcall(C_Traits.GetTreeCurrencyInfo, cfg, treeID, false)
        if okU and type(cur) == "table" and type(cur[1]) == "table" then unspent = tonumber(cur[1].quantity) or 0 end
    end
    -- the names and pictures of the three trees (the specializations): the game tells them for the character that is logged in
    local specs = old and old.specs
    if C_SpecializationInfo and C_SpecializationInfo.GetSpecializationInfo then
        local found = {}
        for i = 1, 3 do
            local okS, _, name, _, icon = pcall(C_SpecializationInfo.GetSpecializationInfo, i)
            if okS and type(name) == "string" then found[i] = { name = name, icon = icon } end
        end
        if #found > 0 then specs = found end
    end
    rec.talents = { spent = spent, unspent = unspent, nodes = nodes, tree = treeID, specs = specs }
    Stamp(rec, "talents")
end

local RUN = {
    info = ScanInfo, equip = ScanEquipment, bags = ScanBags, bank = ScanBank, mail = ScanMail,
    skills = ScanSkills, auctions = ScanAuctions,
    talents = function() ScanTalents(false) end, talentsChanged = function() ScanTalents(true) end,
    trade = function() ScanRecipes("trade") end, craft = function() ScanRecipes("craft") end,
}

local worker = CreateFrame("Frame")
local acc = 0
local sinceInfo, sincePlayed = 0, 0
worker:SetScript("OnUpdate", function(_, dt)
    acc = acc + dt
    if acc < 0.6 then return end
    sinceInfo, sincePlayed = sinceInfo + acc, sincePlayed + acc
    acc = 0
    -- the character is looked at again every minute, the time played every twenty
    if sinceInfo > 60 then sinceInfo = 0; pending.info = true end
    if sincePlayed > 1200 then sincePlayed = 0; RequestPlayed() end
    if not next(pending) then return end
    if not (ns.db and Acc.Enabled()) then wipe(pending) return end
    local work = pending
    pending = {}
    for kind in pairs(work) do
        local ok, err = pcall(RUN[kind])
        if not ok and ns.db and ns.db.debug then print("ForeverCompanion account:", kind, err) end
    end
    if ns.AccountWindow and ns.AccountWindow.Dirty then ns.AccountWindow.Dirty() end
    -- the bags changed (something was put up for sale, bought, moved): the list of what can be sold is worked out again
    if (work.bags or work.bank) and ns.AuctionTab and ns.AuctionTab.HoldingsChanged then ns.AuctionTab.HoldingsChanged() end
end)

local events = CreateFrame("Frame")
local HANDLE = {
    PLAYER_LOGIN = function() Queue("info"); Queue("equip"); Queue("bags"); Queue("skills"); C_Timer.After(6, RequestPlayed); C_Timer.After(8, function() Queue("info") end) end,
    PLAYER_ENTERING_WORLD = function() Queue("info"); Queue("skills"); C_Timer.After(5, function() Queue("talents") end) end,
    PLAYER_TALENT_UPDATE = function() Queue("talentsChanged") end,
    CHARACTER_POINTS_CHANGED = function() Queue("talentsChanged") end,
    PLAYER_LEVEL_UP = function() Queue("info"); C_Timer.After(3, function() Queue("info") end) end,
    UPDATE_EXHAUSTION = function() Queue("info") end,
    PLAYER_UPDATE_RESTING = function() Queue("info") end,
    PLAYER_ALIVE = function() Queue("info") end,
    PLAYER_XP_UPDATE = function() Queue("info") end,
    PLAYER_MONEY = function()
        local rec = Acc.Me()
        local money = GetMoney()
        if rec and money then rec.money = money end -- during play a change is real, 0 included
    end,
    ZONE_CHANGED_NEW_AREA = function() Queue("info") end,
    PLAYER_GUILD_UPDATE = function() Queue("info") end,
    PLAYER_EQUIPMENT_CHANGED = function() Queue("equip"); Queue("info") end,
    BAG_UPDATE_DELAYED = function() Queue("bags"); if bankOpen then Queue("bank") end end,
    PLAYERBANKSLOTS_CHANGED = function() if bankOpen then Queue("bank") end end,
    BANKFRAME_OPENED = function() bankOpen = true; Queue("bank") end,
    BANKFRAME_CLOSED = function() ScanBank(); bankOpen = false end,
    MAIL_INBOX_UPDATE = function() Queue("mail") end,
    MAIL_SHOW = function() Queue("mail") end,
    SKILL_LINES_CHANGED = function() Queue("skills") end,
    TRADE_SKILL_SHOW = function() Queue("trade") end,
    TRADE_SKILL_UPDATE = function() Queue("trade") end,
    CRAFT_SHOW = function() Queue("craft") end,
    CRAFT_UPDATE = function() Queue("craft") end,
    AUCTION_OWNED_LIST_UPDATE = function() Queue("auctions") end,
    OWNED_AUCTIONS_UPDATED = function() Queue("auctions") end,
    AUCTION_CANCELED = function(id) if id then cancelledIds[id] = true end end,
    TIME_PLAYED_MSG = function(total, level)
        local rec = Acc.Me()
        if rec then
            rec.played, rec.playedLevel = total, level
            Stamp(rec, "info")
        end
        for _, cf in ipairs(playedFrames or {}) do cf:RegisterEvent("TIME_PLAYED_MSG") end
        playedFrames = nil
    end,
    PLAYER_LOGOUT = function()
        -- the client may already have emptied its data here: only what is certain is kept
        local rec = Acc.Me()
        if rec then
            rec.lastSeen = time()
            rec.resting = IsResting and IsResting() and true or false
            local money = GetMoney()
            if money and money > 0 then rec.money = money end
        end
    end,
}
HANDLE.TRADE_SKILL_LIST_UPDATE = function() Queue("trade") end
HANDLE.TRADE_SKILL_DATA_SOURCE_CHANGED = function() Queue("trade") end
for event in pairs(HANDLE) do
    Acc.dbg.events[event] = pcall(events.RegisterEvent, events, event) and 0 or false
end
events:SetScript("OnEvent", function(_, event, ...)
    if not ns.db then return end
    Acc.dbg.events[event] = (Acc.dbg.events[event] or 0) + 1
    HANDLE[event](...)
end)

-- /fc accdebug: what this client offers and what the scans did
function Acc.Debug()
    local function Say(t) print("|cffffd100ForeverCompanion account:|r " .. t) end
    local function Raw(...) local t = {} for i = 1, select("#", ...) do t[#t + 1] = tostring((select(i, ...))) end return table.concat(t, " | ") end
    Say("names: UnitName=" .. Raw(UnitName("player")) .. "; UnitFullName=" .. Raw(UnitFullName and UnitFullName("player"))
        .. "; UnitPVPName=" .. Raw(UnitPVPName and UnitPVPName("player")) .. "; surname=" .. tostring(SurnameOf()))
    local have = {}
    for _, n in ipairs({ "GetNumTradeSkills", "GetTradeSkillLine", "GetNumCrafts", "GetNumSkillLines", "GetProfessions",
        "GetInboxNumItems", "GetNumAuctionItems", "GetAverageItemLevel", "RequestTimePlayed" }) do
        have[#have + 1] = n .. "=" .. (_G[n] and "yes" or "no")
    end
    have[#have + 1] = "C_TradeSkillUI=" .. (C_TradeSkillUI and "yes" or "no")
    have[#have + 1] = "C_Container=" .. (C_Container and "yes" or "no")
    have[#have + 1] = "C_AuctionHouse=" .. (C_AuctionHouse and "yes" or "no")
    Say(table.concat(have, ", "))
    local seen = {}
    for event, n in pairs(Acc.dbg.events) do
        seen[#seen + 1] = event .. "=" .. (n == false and "not available" or tostring(n))
    end
    table.sort(seen)
    Say(L["Events"] .. ": " .. table.concat(seen, ", "))
    for kind, text in pairs(Acc.dbg.last) do Say(kind .. " -> " .. text) end
    local rec = Acc.Me()
    local n = 0
    if rec then for prof, r in pairs(rec.recipes) do n = n + 1; Say(prof .. ": " .. #r.list .. " recipes") end end
    if n == 0 then Say("no recipes stored for this character") end
end
