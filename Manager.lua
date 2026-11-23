local ADDON, ns = ...
local L = ns.L
local W = ns.W
local C = W.C

-- The bags manager: what to do with every item in the bags (and the reagent bag): sell it to a vendor, keep it, send it to a character by
-- mail, or store it in the bank. A window with four tabs (Vendor, Mail, Bank, Rules) that opens by itself with the merchant, the mailbox and
-- the bank. The list is ordered by what an item is worth at a vendor against the auction house. A rule can be set for one item (the rules
-- are kept in ns.db.itemRules, account wide) or for a kind of item (cloth, leather, green gear ... in ns.db.catRules). The Rules tab and the
-- settings list and change them all, and suggest a character for a kind of item (the one who has the profession that uses it).
-- Junk (gray) is sold at once when a merchant opens, if that is switched on. Nothing else is sold, mailed or stored without a click.
-- Ideas from watching how Blackthornes Butler sorts bags (a verdict per item with a mark and a colour); the code is our own.

local M = {}
ns.Manager = M

local ROW_H, MAX_ROWS = 28, 19
local WIN_W, WIN_H = 780, 620
local state = { tab = "vendor", offset = 0, query = "", kindFilter = "all", scope = "char" }
local heads, actHead, qtyHead, searchBox, filterBtn, clearBtn
local win, rows, tabs, menu, status, junkBtn, sellBtn, actionBtn, track
local dirty, scanned = true, {}
local autoOpened -- the window was opened by itself (with a merchant, the mailbox or the bank)

local function Say(text) print("|cffffd100ForeverCompanion:|r " .. text) end
local function Money(copper, tint) return ns.Value.Format(copper or 0, tint) end

-- the settings ------------------------------------------------------------------------------------------------------------------------
local function St() return ns.db.settings end
function M.JunkAuto() return St().mgrSellJunk ~= false end
function M.AutoOpen() return St().mgrAutoOpen ~= false end
function M.AhGain() return tonumber(St().mgrAhGain) or 25 end        -- percent more at the auction house (after the fee) that makes it worth a look
function M.SellLimit() return tonumber(St().mgrSellLimit) or 1 end   -- "sell without AH" takes items up to this quality (0 gray, 1 white, 2 green)

-- the rules ----------------------------------------------------------------------------------------------------------------------------
-- rule: { kind = "keep" | "mail" | "bank", target = character name (mail) }
local function Rules()
    ns.db.itemRules = ns.db.itemRules or {}
    return ns.db.itemRules
end
local function CatRules()
    ns.db.catRules = ns.db.catRules or {}
    return ns.db.catRules
end
-- rules that hold for this character only (ns.db.charRules[character].items / .cats); they go before those for all characters.
-- A new rule holds for this character first; in the menu of a rule it can be changed to all characters.
local function MeKey() return (ns.Acc and ns.Acc.MyKey and ns.Acc.MyKey()) or "?" end
local function CharTable(field)
    ns.db.charRules = ns.db.charRules or {}
    local t = ns.db.charRules[MeKey()]
    if not t then t = { items = {}, cats = {} }; ns.db.charRules[MeKey()] = t end
    t[field] = t[field] or {}
    return t[field]
end
local function CharRules() return CharTable("items") end
local function CharCatRules() return CharTable("cats") end
-- the rule that counts for an item / a kind: that of this character, or else the one for all
local function RuleOf(id) return CharRules()[id] or Rules()[id] end
local function CatRuleOf(id) return CharCatRules()[id] or CatRules()[id] end
-- the rule as it is kept in one of the two places
local function RuleIn(scope, id) return (scope == "char" and CharRules() or Rules())[id] end
local function CatRuleIn(scope, id) return (scope == "char" and CharCatRules() or CatRules())[id] end

local KIND = {
    keep = { label = L["Keep"], color = { 0.4, 0.85, 0.5 }, icon = "Interface\\Icons\\INV_Misc_Key_03" },
    mail = { label = L["Mail"], color = { 0.45, 0.68, 1 }, icon = "Interface\\Icons\\INV_Letter_15" },
    bank = { label = L["Bank"], color = { 0.7, 0.7, 0.72 }, icon = "Interface\\Icons\\INV_Misc_Bag_09" },
    vendor = { label = L["Vendor"], color = { 1, 0.82, 0.25 }, icon = "Interface\\Icons\\INV_Misc_Coin_01" },
    auction = { label = L["Auction"], color = { 1, 0.68, 0.25 }, icon = "Interface\\Icons\\INV_Misc_Coin_02" },
}
M.KIND = KIND

-- the kinds of items that a rule can be made for, and the profession that uses them
local GetInstant = (C_Item and C_Item.GetItemInfoInstant) or GetItemInfoInstant
local CATS = {
    { id = "cloth", label = L["Cloth"], icon = "Interface\\Icons\\INV_Fabric_Wool_01", prof = "tailoring", match = function(it) return it.class == 7 and it.sub == 5 end },
    { id = "leather", label = L["Leather"], icon = "Interface\\Icons\\INV_Misc_LeatherScrap_02", prof = "leatherworking", match = function(it) return it.class == 7 and it.sub == 6 end },
    { id = "herb", label = L["Herbs"], icon = "Interface\\Icons\\INV_Misc_Herb_02", prof = "alchemy", match = function(it) return it.class == 7 and it.sub == 9 end },
    { id = "ore", label = L["Ore and stone"], icon = "Interface\\Icons\\INV_Ore_Copper_01", prof = "blacksmithing", match = function(it) return it.class == 7 and it.sub == 7 end },
    { id = "gem", label = L["Gems"], icon = "Interface\\Icons\\INV_Misc_Gem_Variety_01", prof = "jewelcrafting", match = function(it) return it.class == 3 end },
    { id = "elemental", label = L["Elementals"], icon = "Interface\\Icons\\INV_Elemental_Primal_Fire", prof = "alchemy", match = function(it) return it.class == 7 and it.sub == 10 end },
    { id = "enchant", label = L["Enchanting materials"], icon = "Interface\\Icons\\INV_Enchant_DustStrange", prof = "enchanting", match = function(it) return it.class == 7 and it.sub == 12 end },
    { id = "parts", label = L["Parts"], icon = "Interface\\Icons\\INV_Misc_Gear_01", prof = "engineering", match = function(it) return it.class == 7 and it.sub == 1 end },
    { id = "green", label = L["Green gear"], icon = "Interface\\Icons\\INV_Chest_Cloth_03", prof = "enchanting", match = function(it) return (it.class == 2 or it.class == 4) and it.quality == 2 end },
    { id = "blue", label = L["Blue gear or better"], icon = "Interface\\Icons\\INV_Chest_Plate06", prof = "enchanting", match = function(it) return (it.class == 2 or it.class == 4) and it.quality >= 3 end },
}
M.CATS = CATS
local PROF_NAMES = {
    tailoring = { "tailoring", "schneiderei" }, leatherworking = { "leatherworking", "lederverarbeitung" }, alchemy = { "alchemy", "alchemie" },
    blacksmithing = { "blacksmithing", "schmiedekunst" }, jewelcrafting = { "jewelcrafting", "juwelenschleifen" },
    enchanting = { "enchanting", "verzauberkunst" }, engineering = { "engineering", "ingenieurskunst" },
}

-- A letter needs the first name and the surname (the surname is part of the name here); the name is shown in the colour of the class.
local function FullName(rec)
    return (rec.name or "?") .. ((rec.surname and rec.surname ~= "") and (" " .. rec.surname) or "")
end
local function Colored(rec, text)
    local col = RAID_CLASS_COLORS and rec.class and RAID_CLASS_COLORS[rec.class]
    text = text or FullName(rec)
    if not col then return text end
    return ("|cff%02x%02x%02x%s|r"):format(col.r * 255 + 0.5, col.g * 255 + 0.5, col.b * 255 + 0.5, text)
end
-- a name that is kept in a rule, in the colour of its character (a name that no known character has stays as it is)
local function ColoredName(name)
    for _, rec in ipairs(ns.Acc and ns.Acc.Chars and ns.Acc.Chars() or {}) do
        if FullName(rec) == name or rec.name == name then return Colored(rec, name) end
    end
    return name
end

function M.CatRule(id) return CatRuleOf(id) end
function M.SetCatRule(id, kind, target, scope)
    local store = scope == "all" and CatRules() or CharCatRules()
    if kind then store[id] = { kind = kind, target = target, char = scope ~= "all" or nil } else store[id] = nil end
    dirty = true
    if ns.Settings and ns.Settings.Refresh then ns.Settings.Refresh() end
end
function M.Rule(id) return RuleOf(id) end
function M.SetRule(id, kind, target, scope)
    if not id then return end
    local store = scope == "all" and Rules() or CharRules()
    if kind then store[id] = { kind = kind, target = target, char = scope ~= "all" or nil } else store[id] = nil end
    dirty = true
    if ns.Settings and ns.Settings.Refresh then ns.Settings.Refresh() end
end
-- all rules for single items, ordered: kind, then name (for the settings and the Rules tab; also items that are not in the bags)
function M.RuleList()
    local list = {}
    for _, store in ipairs({ Rules(), CharRules() }) do
        for id, r in pairs(store) do
            local name, _, icon = W.ItemData(id)
            list[#list + 1] = { id = id, kind = r.kind, target = r.target, char = r.char, name = name or ("item:" .. id), icon = icon }
        end
    end
    table.sort(list, function(a, b)
        if a.kind ~= b.kind then return a.kind < b.kind end
        return tostring(a.name):lower() < tostring(b.name):lower()
    end)
    return list
end
-- takes every rule away (the kinds of items stay, they just have no rule any more), after a warning
function M.ClearRules()
    ns.db.itemRules, ns.db.catRules, ns.db.charRules = {}, {}, {}
    dirty = true
    if ns.Settings and ns.Settings.Refresh then ns.Settings.Refresh() end
end
function M.AskClearRules()
    StaticPopupDialogs["FOREVERCOMPANION_CLEAR_RULES"] = StaticPopupDialogs["FOREVERCOMPANION_CLEAR_RULES"] or {
        text = L["Delete ALL rules of ALL characters? This cannot be undone."],
        button1 = L["Delete"], button2 = CANCEL or "Cancel",
        OnAccept = function() M.ClearRules() end,
        timeout = 0, whileDead = true, hideOnEscape = true, preferredIndex = 3,
    }
    StaticPopup_Show("FOREVERCOMPANION_CLEAR_RULES")
end

-- the character a kind of item is best sent to: the one with the profession that uses it (the highest skill), not the one playing now
function M.Suggest(cat)
    local names = PROF_NAMES[cat.prof]
    if not (names and ns.Acc and ns.Acc.Chars) then return nil end
    local me = ns.Acc.MyKey and ns.Acc.MyKey()
    local best, bestRank
    for _, rec in ipairs(ns.Acc.Chars()) do
        if rec.key ~= me and rec.name then
            for _, sk in ipairs(rec.skills or {}) do
                local n = tostring(sk.name or ""):lower()
                if (n == names[1] or n == names[2]) and (not bestRank or (sk.rank or 0) > bestRank) then best, bestRank = FullName(rec), sk.rank or 0 end
            end
        end
    end
    return best
end
function M.ApplySuggestions()
    local n = 0
    for _, cat in ipairs(CATS) do
        if not CatRuleOf(cat.id) then
            local who = M.Suggest(cat)
            if who then CharCatRules()[cat.id] = { kind = "mail", target = who, char = true }; n = n + 1 end
        end
    end
    dirty = true
    if ns.Settings and ns.Settings.Refresh then ns.Settings.Refresh() end
    Say((L["%d suggestions taken over."]):format(n))
end

-- the bags --------------------------------------------------------------------------------------------------------------------------
local function BagList()
    local list = {}
    for bag = 0, (NUM_BAG_SLOTS or 4) do list[#list + 1] = bag end
    local reagent = Enum and Enum.BagIndex and Enum.BagIndex.ReagentBag
    if not reagent and (NUM_REAGENTBAG_SLOTS or 0) > 0 then reagent = (NUM_BAG_SLOTS or 4) + 1 end
    if reagent then list[#list + 1] = reagent end
    return list
end

-- the rule of an item: its own, or that of its kind (cloth ...); soulbound items cannot be mailed
local function RuleFor(it)
    local own = RuleOf(it.id)
    if own then return own end
    for _, cat in ipairs(CATS) do
        if cat.match(it) then
            local r = CatRuleOf(cat.id)
            if r and not (r.kind == "mail" and it.bound) then return r, cat end
        end
    end
end

-- every item of the bags, once, with its stacks, what a vendor pays and the auction price
local function Scan()
    local items, order = {}, {}
    if not (C_Container and C_Container.GetContainerNumSlots and C_Container.GetContainerItemInfo) then return order end
    for _, bag in ipairs(BagList()) do
        for slot = 1, (C_Container.GetContainerNumSlots(bag) or 0) do
            local info = C_Container.GetContainerItemInfo(bag, slot)
            if info and info.itemID then
                local id = info.itemID
                local it = items[id]
                if not it then
                    it = { id = id, count = 0, slots = {}, link = info.hyperlink, quality = info.quality or 1 }
                    items[id] = it
                    order[#order + 1] = it
                end
                local n = info.stackCount or 1
                it.count = it.count + n
                it.slots[#it.slots + 1] = { bag = bag, slot = slot, count = n }
                if info.isBound then it.bound = true end
            end
        end
    end
    local gain = M.AhGain()
    for _, it in ipairs(order) do
        local name, quality, icon = W.ItemData(it.id)
        it.name, it.icon = name or ("item:" .. it.id), icon
        if quality then it.quality = quality end
        if GetInstant then
            local _, _, _, _, _, class, sub = GetInstant(it.id)
            it.class, it.sub = class, sub
        end
        it.vendor = ns.Value.Vendor(it.id) or 0
        local ah = (not it.bound) and ns.Value.AuctionPrice(it.id) or nil
        it.ah = ah
        it.ahNet = ah and math.floor(ah * 0.95) or nil   -- (the auction house keeps 5 %)
        local rule, cat = RuleFor(it)
        it.rule, it.ruleCat = rule, cat
        -- what the list proposes
        if rule then it.verdict = rule.kind
        elseif it.quality == 0 then it.verdict = "junk"
        elseif it.ahNet and it.vendor > 0 and it.ahNet >= it.vendor * (1 + gain / 100) then it.verdict = "ah"
        elseif it.vendor > 0 then it.verdict = "vendor"
        else it.verdict = "none" end
    end
    return order
end

local function RuleText(rule)
    local k = rule and KIND[rule.kind]
    if not k then return "–", { 0.5, 0.5, 0.5 } end
    return k.label .. ((rule.kind == "mail" and rule.target) and (": " .. ColoredName(rule.target)) or "")
        .. ((not rule.char) and ("  |cff8a806e(" .. L["all characters"] .. ")|r") or ""), k.color
end
M.RuleText = RuleText
M.ColoredName = ColoredName

-- the entries of a tab: items, with headers between the groups
local function Entries(tab)
    local items = scanned
    local out = {}
    if tab == "vendor" then
        local main, ruled = {}, {}
        for _, it in ipairs(items) do
            if it.rule then ruled[#ruled + 1] = it
            elseif it.class == (Enum and Enum.ItemClass and Enum.ItemClass.Questitem or 12) then -- (quest items: nothing to do with them here)
            elseif it.vendor > 0 or not it.bound then main[#main + 1] = it end -- (without a vendor price they are still there, to be mailed: if they are not bound)
        end
        local rank = { junk = 0, vendor = 1, ah = 2, none = 3 }
        table.sort(main, function(a, b)
            if rank[a.verdict] ~= rank[b.verdict] then return rank[a.verdict] < rank[b.verdict] end
            return a.vendor * a.count > b.vendor * b.count
        end)
        for _, it in ipairs(main) do out[#out + 1] = { it = it } end
        if #ruled > 0 then
            out[#out + 1] = { header = L["With a rule"] }
            table.sort(ruled, function(a, b)
                if a.rule.kind ~= b.rule.kind then return a.rule.kind < b.rule.kind end
                return a.name:lower() < b.name:lower()
            end)
            for _, it in ipairs(ruled) do out[#out + 1] = { it = it } end
        end
    elseif tab == "mail" then
        local groups, order = {}, {}
        for _, it in ipairs(items) do
            if it.rule and it.rule.kind == "mail" and it.rule.target then
                local g = groups[it.rule.target]
                if not g then g = {}; groups[it.rule.target] = g; order[#order + 1] = it.rule.target end
                g[#g + 1] = it
            end
        end
        table.sort(order)
        for _, target in ipairs(order) do
            out[#out + 1] = { header = L["To"] .. " " .. ColoredName(target), mailTo = target }
            table.sort(groups[target], function(a, b) return a.name:lower() < b.name:lower() end)
            for _, it in ipairs(groups[target]) do out[#out + 1] = { it = it } end
        end
    elseif tab == "bank" then
        local list = {}
        for _, it in ipairs(items) do if it.rule and it.rule.kind == "bank" then list[#list + 1] = it end end
        table.sort(list, function(a, b) return a.name:lower() < b.name:lower() end)
        for _, it in ipairs(list) do out[#out + 1] = { it = it } end
    else -- rules: all of them, the kinds of items and the single items (also those that are not in the bags), with the filter
        local q = (state.query or ""):lower()
        local kf = state.kindFilter or "all"
        local function Passes(name, rule)
            if q ~= "" and not tostring(name):lower():find(q, 1, true) then return false end
            if kf == "all" then return true end
            if kf == "none" then return rule == nil end
            return rule ~= nil and rule.kind == kf
        end
        local kinds = {}
        for _, cat in ipairs(CATS) do if Passes(cat.label, CatRuleOf(cat.id)) then kinds[#kinds + 1] = { cat = cat } end end
        if #kinds > 0 then
            out[#out + 1] = { header = L["Kinds of items"] }
            for _, e in ipairs(kinds) do out[#out + 1] = e end
        end
        local single = {}
        for _, e in ipairs(M.RuleList()) do if Passes(e.name, { kind = e.kind, char = e.char }) then single[#single + 1] = e end end
        if #single > 0 then
            out[#out + 1] = { header = L["Single items"] }
            for _, e in ipairs(single) do out[#out + 1] = { single = e } end
        end
    end
    return out
end

-- doing things ----------------------------------------------------------------------------------------------------------------------
local function MerchantOpen() return MerchantFrame and MerchantFrame:IsShown() end
local function MailOpen() return MailFrame and MailFrame:IsShown() end
local function BankOpen() return BankFrame and BankFrame:IsShown() end

-- a run of clicks on bag slots, a little apart (the game does one move at a time)
local function Run(slots, step, check)
    for i, sl in ipairs(slots) do
        C_Timer.After((i - 1) * step, function()
            if check() then pcall(C_Container.UseContainerItem, sl.bag, sl.slot) end
        end)
    end
    C_Timer.After(#slots * step + 0.3, function() dirty = true end)
end

function M.Sell(items)
    if not MerchantOpen() then Say(L["Open a merchant first."]); return end
    local slots, total = {}, 0
    for _, it in ipairs(items) do
        if not (it.rule and it.rule.kind == "keep") and it.vendor > 0 then
            for _, sl in ipairs(it.slots) do slots[#slots + 1] = sl end
            total = total + it.vendor * it.count
        end
    end
    if #slots == 0 then return end
    Run(slots, 0.1, MerchantOpen)
    Say((L["Selling %d stacks for %s."]):format(#slots, Money(total)))
end

-- the items of the bags that are meant for the auction house: those with the rule "auction", and those that the list proposes for it
function M.AuctionSet()
    local set = {}
    for _, it in ipairs(Scan()) do
        if (it.verdict == "auction" or it.verdict == "ah") and not it.bound then set[it.id] = true end
    end
    return set
end

function M.SellJunk()
    scanned = Scan()
    local junk = {}
    for _, it in ipairs(scanned) do
        if (it.verdict == "junk" or (it.rule and it.rule.kind == "vendor")) and it.vendor > 0 then junk[#junk + 1] = it end
    end
    if #junk > 0 then M.Sell(junk) end
end

-- the items for sale that the auction house would not pay more for (up to the quality that is set)
local function NotWorthAuctioning()
    local list = {}
    for _, it in ipairs(scanned) do
        if not it.rule and it.vendor > 0 and it.quality <= M.SellLimit() and it.verdict ~= "ah" then list[#list + 1] = it end
    end
    return list
end

function M.Attach(target, items)
    if not MailOpen() then Say(L["Open the mailbox first."]); return end
    if MailFrameTab_OnClick then pcall(MailFrameTab_OnClick, nil, 2) end -- (the tab for sending)
    if SendMailNameEditBox then SendMailNameEditBox:SetText(target) end
    local slots = {}
    local most = ATTACHMENTS_MAX_SEND or 12
    for _, it in ipairs(items) do
        for _, sl in ipairs(it.slots) do
            if #slots < most then slots[#slots + 1] = sl end
        end
    end
    Run(slots, 0.25, MailOpen)
    -- (the game fills the subject with the name of the first thing attached: ours replaces it once they are all in)
    C_Timer.After(#slots * 0.25 + 0.5, function()
        if MailOpen() and SendMailSubjectEditBox then SendMailSubjectEditBox:SetText(L["Mail from Forever Companion"]) end
    end)
    Say((L["%d stacks put in the letter to %s. Check it and send it."]):format(#slots, target))
end

function M.Deposit(items)
    if not BankOpen() then Say(L["Open the bank first."]); return end
    local slots = {}
    for _, it in ipairs(items) do for _, sl in ipairs(it.slots) do slots[#slots + 1] = sl end end
    if #slots == 0 then return end
    Run(slots, 0.2, BankOpen)
    Say((L["%d stacks stored in the bank."]):format(#slots))
end

-- the menus: the verdicts, for an item and for a kind of item ---------------------------------------------------------------------------
local function Menu()
    if not menu then menu = W.NewDropdown(UIParent, { level = 200, width = 250, strata = "FULLSCREEN_DIALOG" }) end
    return menu
end

-- the lines that choose a rule: keep, bank, mail to each character, and taking the rule away
-- a name that is typed (a character that is not in the list, or one of another account): first name and surname, as the game needs them
local askDone
function M.AskName(done)
    askDone = done
    StaticPopupDialogs["FOREVERCOMPANION_MAIL_NAME"] = StaticPopupDialogs["FOREVERCOMPANION_MAIL_NAME"] or {
        text = L["Name of the character the mail goes to (first name and surname):"],
        button1 = ACCEPT or "OK", button2 = CANCEL or "Cancel", hasEditBox = 1, maxLetters = 64,
        OnAccept = function(self)
            local box = self.editBox or self.EditBox
            local name = box and strtrim(box:GetText() or "") or ""
            if name ~= "" and askDone then askDone(name) end
        end,
        EditBoxOnEnterPressed = function(box)
            local parent = box:GetParent()
            local name = strtrim(box:GetText() or "")
            if name ~= "" and askDone then askDone(name) end
            parent:Hide()
        end,
        EditBoxOnEscapePressed = function(box) box:GetParent():Hide() end,
        timeout = 0, whileDead = true, hideOnEscape = true, preferredIndex = 3,
    }
    StaticPopup_Show("FOREVERCOMPANION_MAIL_NAME")
end

local function RuleRows(set, current)
    local out = {}
    local me
    for _, rec in ipairs(ns.Acc and ns.Acc.Chars and ns.Acc.Chars() or {}) do if rec.key == MeKey() then me = rec end end
    out[#out + 1] = { kind = "header", label = L["Applies to"] }
    out[#out + 1] = { kind = "radio", state = state.scope == "char" and "all" or "none", label = L["Only"] .. " " .. (me and Colored(me) or UnitName("player")),
        onClick = function() state.scope = "char" end }
    out[#out + 1] = { kind = "radio", state = state.scope == "all" and "all" or "none", label = L["All characters"],
        onClick = function() state.scope = "all" end }
    out[#out + 1] = { kind = "separator" }
    out[#out + 1] = { kind = "action", label = L["Keep it"], icon = KIND.keep.icon, close = true, onClick = function() set("keep") end }
    out[#out + 1] = { kind = "action", label = L["Store it in the bank"], icon = KIND.bank.icon, close = true, onClick = function() set("bank") end }
    out[#out + 1] = { kind = "action", label = L["Always sell to vendor"], icon = KIND.vendor.icon, close = true, onClick = function() set("vendor") end }
    out[#out + 1] = { kind = "action", label = L["Always sell at auction"], icon = KIND.auction.icon, close = true, onClick = function() set("auction") end }
    out[#out + 1] = { kind = "separator" }
    local me = ns.Acc and ns.Acc.MyKey and ns.Acc.MyKey()
    for _, rec in ipairs(ns.Acc and ns.Acc.Chars and ns.Acc.Chars() or {}) do
        if rec.name and rec.key ~= me then
            out[#out + 1] = { kind = "action", label = L["Always mail to"] .. " " .. Colored(rec), icon = KIND.mail.icon, close = true,
                onClick = function() set("mail", FullName(rec)) end }
        end
    end
    out[#out + 1] = { kind = "action", label = L["Mail to another name ..."], icon = KIND.mail.icon, close = true, onClick = function() M.AskName(function(name) set("mail", name) end) end }
    if current then
        out[#out + 1] = { kind = "separator" }
        out[#out + 1] = { kind = "action", label = L["Remove the rule"], close = true, onClick = function() set(nil) end }
    end
    return out
end

-- (the menu starts with the place where the rule is kept now; a kind or an item without a rule starts with this character)
local function ScopeOfRule(rule) state.scope = (rule and not rule.char) and "all" or "char" end

local function OpenItemMenu(anchor, it, scope)
    if scope then state.scope = scope else ScopeOfRule(RuleOf(it.id)) end
    Menu():Open(anchor, function()
        local out = { { kind = "header", label = it.name } }
        for _, row in ipairs(RuleRows(function(kind, target) M.SetRule(it.id, kind, target, state.scope) end, RuleIn(state.scope, it.id))) do out[#out + 1] = row end
        if MerchantOpen() and (it.vendor or 0) > 0 and it.slots and not (it.rule and it.rule.kind == "keep") then
            out[#out + 1] = { kind = "separator" }
            out[#out + 1] = { kind = "action", label = L["Sell it now"], icon = "Interface\\Icons\\INV_Misc_Coin_01", close = true, onClick = function() M.Sell({ it }) end }
        end
        return out
    end, true)
end


function M.OpenCatMenu(anchor, cat)
    ScopeOfRule(CatRuleOf(cat.id))
    Menu():Open(anchor, function()
        local out = { { kind = "header", label = cat.label } }
        local who = M.Suggest(cat)
        if who and not CatRuleOf(cat.id) then
            out[#out + 1] = { kind = "action", label = L["Set rule: Send to"] .. " " .. ColoredName(who), icon = KIND.mail.icon, close = true, onClick = function() M.SetCatRule(cat.id, "mail", who, state.scope) end }
            out[#out + 1] = { kind = "separator" }
        end
        for _, row in ipairs(RuleRows(function(kind, target) M.SetCatRule(cat.id, kind, target, state.scope) end, CatRuleIn(state.scope, cat.id))) do out[#out + 1] = row end
        return out
    end, true)
end

-- the window ------------------------------------------------------------------------------------------------------------------------
local COLS = { qty = 342, vendor = 452, ah = 550, gain = 620, mark = 636 }

local VERDICT_TEXT = {
    junk = { L["Junk"], { 0.62, 0.62, 0.62 } }, vendor = { L["Vendor"], { 1, 0.82, 0.25 } }, ah = { L["Auction"], { 1, 0.68, 0.25 } },
    none = { "–", { 0.5, 0.5, 0.5 } },
}

local function MakeRow(i)
    local r = CreateFrame("Button", nil, win)
    r:SetHeight(ROW_H)
    r:SetPoint("TOPLEFT", win, "TOPLEFT", 12, -(34 + (i - 1) * ROW_H))
    r:SetPoint("TOPRIGHT", win, "TOPRIGHT", -24, -(34 + (i - 1) * ROW_H))
    r.bg = r:CreateTexture(nil, "BACKGROUND")
    r.bg:SetAllPoints()
    r.hl = r:CreateTexture(nil, "BACKGROUND", nil, 1)
    r.hl:SetAllPoints()
    r.hl:SetColorTexture(1, 0.85, 0.4, 0.09)
    r.hl:SetAlpha(0)
    r.icon = r:CreateTexture(nil, "ARTWORK")
    r.icon:SetSize(22, 22)
    r.icon:SetPoint("LEFT", 6, 0)
    r.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
    r.name = r:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    r.name:SetPoint("LEFT", r.icon, "RIGHT", 8, 0)
    r.name:SetWidth(COLS.qty - 70)
    r.name:SetJustifyH("LEFT")
    r.name:SetWordWrap(false)
    local function Cell(key, justify, w)
        local fs = r:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        fs:SetPoint("RIGHT", r, "LEFT", COLS[key], 0)
        fs:SetWidth(w)
        fs:SetJustifyH(justify or "RIGHT")
        fs:SetWordWrap(false)
        return fs
    end
    r.qty = Cell("qty", "RIGHT", 40)
    r.vendor = Cell("vendor", "RIGHT", 100)
    r.ah = Cell("ah", "RIGHT", 96)
    r.gain = Cell("gain", "RIGHT", 64)
    r.mark = r:CreateTexture(nil, "ARTWORK")
    r.mark:SetSize(16, 16)
    r.mark:SetPoint("LEFT", r, "LEFT", COLS.mark, 0)
    r.verdict = r:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    r.verdict:SetPoint("LEFT", r.mark, "RIGHT", 6, 0)
    r.verdict:SetWidth(112)
    r.verdict:SetJustifyH("LEFT")
    r.verdict:SetWordWrap(false)
    r.sell = W.NewIconButton(r, "Interface\\Icons\\INV_Misc_Coin_01", 22)
    r.sell:SetPoint("RIGHT", -4, 0)
    r.sell:SetTip(L["Sell it now"])
    r.sell:SetScript("OnClick", function() if r.it then M.Sell({ r.it }) end end)
    r.act = W.NewButton(r, "", 120, 22)
    r.act:SetPoint("RIGHT", -4, 0)
    r.act:Hide()
    r:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    r:SetScript("OnClick", function(self)
        if self.it then OpenItemMenu(self, self.it)
        elseif self.cat then M.OpenCatMenu(self, self.cat)
        elseif self.single then
            local scope = self.single.char and "char" or "all" -- (the line that was clicked: its own rule)
            OpenItemMenu(self, { id = self.single.id, name = self.single.name, rule = RuleIn(scope, self.single.id), vendor = 0 }, scope)
        end
    end)
    r:SetScript("OnEnter", function(self)
        if not (self.it or self.cat or self.single) then return end
        self.hl:SetAlpha(1)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        if self.it and self.it.link then
            pcall(GameTooltip.SetHyperlink, GameTooltip, self.it.link)
            if self.it.rule then
                GameTooltip:AddLine(" ")
                local text = RuleText(self.it.rule)
                GameTooltip:AddLine(L["Rule"] .. ": " .. text, 0.9, 0.9, 0.9)
                if self.it.ruleCat then GameTooltip:AddLine(L["Rule of the kind"] .. ": " .. self.it.ruleCat.label, 0.6, 0.8, 1) end
            end
        elseif self.it then GameTooltip:AddLine(self.it.name)
        elseif self.cat then GameTooltip:AddLine(self.cat.label, 1, 0.85, 0.4)
        else GameTooltip:AddLine(self.single.name, 1, 0.85, 0.4) end
        GameTooltip:AddLine(" ")
        GameTooltip:AddLine(L["Click: set what to do with it."], 0.7, 0.7, 0.7, true)
        GameTooltip:Show()
    end)
    r:SetScript("OnLeave", function(self) self.hl:SetAlpha(0); GameTooltip:Hide() end)
    r:Hide()
    return r
end

local function ClearRow(r)
    r.it, r.cat, r.single = nil, nil, nil
    r.icon:Hide(); r.qty:SetText(""); r.vendor:SetText(""); r.ah:SetText(""); r.gain:SetText(""); r.mark:Hide(); r.verdict:SetText("")
    r.sell:Hide(); r.act:Hide()
end

local function Render()
    if not (win and win:IsShown()) then return end
    scanned = Scan()
    local entries = Entries(state.tab)
    local maxOff = math.max(0, #entries - MAX_ROWS)
    state.offset = math.min(state.offset, maxOff)
    for _, t in ipairs(tabs) do t:SetSelected(t.tab == state.tab) end
    local mailN, bankN = 0, 0
    for _, it in ipairs(scanned) do
        if it.rule and it.rule.kind == "mail" then mailN = mailN + 1 elseif it.rule and it.rule.kind == "bank" then bankN = bankN + 1 end
    end
    for _, t in ipairs(tabs) do
        local n = (t.tab == "mail" and mailN) or (t.tab == "bank" and bankN) or nil
        t.text:SetText(t.baseLabel .. ((n and n > 0) and ("  |cffffd100" .. n .. "|r") or ""))
    end
    -- the scroll bar
    if #entries > MAX_ROWS then
        local trackH = MAX_ROWS * ROW_H
        local h = math.max(24, trackH * MAX_ROWS / #entries)
        track.thumb:SetHeight(h)
        track.thumb:ClearAllPoints()
        track.thumb:SetPoint("TOP", track, "TOP", 0, -(state.offset / math.max(1, #entries - MAX_ROWS)) * (trackH - h))
        track:Show()
        track.total = #entries
    else
        track:Hide()
    end
    -- the rules tab has no prices: the rule stands right after the amount
    local rulesTab = state.tab == "rules"
    local mx = rulesTab and (COLS.qty - 24) or COLS.mark
    for _, k in ipairs({ "qty", "vendor", "ah", "gain" }) do heads[k]:SetShown(not rulesTab) end
    searchBox:SetShown(rulesTab)
    filterBtn:SetShown(rulesTab)
    clearBtn:SetShown(rulesTab)
    actHead:ClearAllPoints()
    actHead:SetPoint("LEFT", win, "TOPLEFT", mx + 8, -18)
    for i = 1, MAX_ROWS do
        local r = rows[i]
        r.mark:ClearAllPoints()
        r.mark:SetPoint("LEFT", r, "LEFT", mx, 0)
        r.verdict:SetWidth(rulesTab and 230 or 112)
        r.act:ClearAllPoints()
        if rulesTab then r.act:SetPoint("LEFT", r, "LEFT", mx, 0) else r.act:SetPoint("RIGHT", -4, 0) end
        r.act:SetWidth(rulesTab and 270 or 120)
    end
    local inBags = {}
    for _, it in ipairs(scanned) do inBags[it.id] = it end
    for i = 1, MAX_ROWS do
        local r = rows[i]
        local e = entries[state.offset + i]
        if not e then
            ClearRow(r)
            r:Hide()
        else
            r:Show()
            ClearRow(r)
            r.bg:SetColorTexture(1, 1, 1, i % 2 == 0 and 0.03 or 0)
            if e.header then
                r.name:SetText("|cffffd100" .. e.header .. "|r")
                r.bg:SetColorTexture(C.gold[1], C.gold[2], C.gold[3], 0.12)
                if e.mailTo then
                    r.act.text:SetText(L["In a letter"])
                    r.act:SetScript("OnClick", function()
                        local list = {}
                        for _, it in ipairs(scanned) do if it.rule and it.rule.kind == "mail" and it.rule.target == e.mailTo then list[#list + 1] = it end end
                        M.Attach(e.mailTo, list)
                    end)
                    r.act:Show()
                end
            elseif e.cat then
                -- a kind of item: its rule, or a suggestion
                r.cat = e.cat
                r.icon:Show(); r.icon:SetTexture(e.cat.icon)
                r.name:SetText(e.cat.label)
                local n = 0
                for _, it in ipairs(scanned) do if e.cat.match(it) then n = n + 1 end end
                r.qty:SetText("")
                local rule = CatRuleOf(e.cat.id)
                local text, col = RuleText(rule)
                r.verdict:SetText(text); r.verdict:SetTextColor(col[1], col[2], col[3])
                if rule then r.mark:SetTexture(KIND[rule.kind].icon); r.mark:Show() end
                local who = (not rule) and M.Suggest(e.cat)
                if who then
                    r.act.text:SetText(L["Set rule: Send to"] .. " " .. ColoredName(who))
                    r.act:SetScript("OnClick", function() M.SetCatRule(e.cat.id, "mail", who, "char") end)
                    r.act:Show()
                end
            elseif e.single then
                r.single = e.single
                r.icon:Show(); r.icon:SetTexture(e.single.icon or "Interface\\Icons\\INV_Misc_QuestionMark")
                r.name:SetText(e.single.name)
                local here = inBags[e.single.id]
                r.qty:SetText("")
                local text, col = RuleText({ kind = e.single.kind, target = e.single.target, char = e.single.char })
                r.mark:SetTexture(KIND[e.single.kind].icon); r.mark:Show()
                r.verdict:SetText(text); r.verdict:SetTextColor(col[1], col[2], col[3])
            else
                local it = e.it
                r.it = it
                r.icon:Show()
                r.icon:SetTexture(it.icon or "Interface\\Icons\\INV_Misc_QuestionMark")
                local col = ITEM_QUALITY_COLORS and ITEM_QUALITY_COLORS[it.quality or 1]
                r.name:SetText((col and col.hex or "|cffffffff") .. it.name .. "|r")
                r.qty:SetText(it.count > 1 and ("×" .. it.count) or "")
                r.vendor:SetText(it.vendor > 0 and Money(it.vendor * it.count) or "|cff8a806e–|r")
                if it.ah then
                    r.ah:SetText(Money(it.ah * it.count)) -- (the sum for the stack, as the vendor price)
                    if it.vendor > 0 then
                        local pct = (it.ahNet - it.vendor) / it.vendor * 100
                        -- a gain is green (stronger from the set threshold on), a loss red
                        local c = pct >= M.AhGain() and "|cff66dbb0" or (pct > 0 and "|cff8fc9b0" or (pct < 0 and "|cffe86a5a" or "|cff8a806e"))
                        r.gain:SetText(c .. ("%+d %%"):format(pct + (pct >= 0 and 0.5 or -0.5)) .. "|r")
                    end
                else
                    r.ah:SetText(it.bound and "|cff8a806e" .. L["bound"] .. "|r" or "|cff8a806e–|r")
                end
                local k = it.rule and KIND[it.rule.kind]
                if k then
                    -- (short: the column is narrow; the mail tab has the name over the group, and the tooltip has the whole rule)
                    local text, c = RuleText(it.rule)
                    if it.rule.kind == "mail" then
                        text = k.label
                        if state.tab ~= "mail" and it.rule.target then
                            local who = it.rule.target
                            for _, rec in ipairs(ns.Acc and ns.Acc.Chars and ns.Acc.Chars() or {}) do
                                if FullName(rec) == it.rule.target then who = Colored(rec, rec.name) break end
                            end
                            text = text .. ": " .. who
                        end
                    end
                    r.mark:SetTexture(k.icon); r.mark:Show()
                    r.verdict:SetText(text); r.verdict:SetTextColor(c[1], c[2], c[3])
                else
                    local v = VERDICT_TEXT[it.verdict] or VERDICT_TEXT.none
                    r.verdict:SetText(v[1]); r.verdict:SetTextColor(v[2][1], v[2][2], v[2][3])
                end
                r.sell:SetShown(state.tab == "vendor" and it.vendor > 0 and MerchantOpen() and not (it.rule and it.rule.kind == "keep") and true or false)
            end
        end
    end
    -- the line at the bottom: where one is, and the buttons for the tab
    local open = (state.tab == "vendor" and MerchantOpen()) or (state.tab == "mail" and MailOpen()) or (state.tab == "bank" and BankOpen())
    local junkN, junkSum = 0, 0
    for _, it in ipairs(scanned) do
        if (it.verdict == "junk" or (it.rule and it.rule.kind == "vendor")) and it.vendor > 0 then junkN = junkN + 1; junkSum = junkSum + it.vendor * it.count end
    end
    junkBtn:Hide(); sellBtn:Hide(); actionBtn:Hide()
    if state.tab == "vendor" then
        status:SetText((open and ("|cff66dbb0" .. L["Merchant open"] .. "|r  ·  ") or ("|cff8a806e" .. L["No merchant"] .. "|r  ·  "))
            .. (junkN > 0 and ((L["%d junk, %s"]):format(junkN, Money(junkSum))) or L["No junk"]))
        junkBtn:Show(); sellBtn:Show()
        junkBtn:SetAlpha((open and junkN > 0) and 1 or 0.5)
        sellBtn:SetAlpha(open and 1 or 0.5)
    elseif state.tab == "mail" then
        status:SetText(open and ("|cff66dbb0" .. L["Mailbox open"] .. "|r") or ("|cff8a806e" .. L["No mailbox"] .. "|r"))
    elseif state.tab == "bank" then
        status:SetText(open and ("|cff66dbb0" .. L["Bank open"] .. "|r") or ("|cff8a806e" .. L["No bank"] .. "|r"))
        actionBtn.text:SetText(L["Store"])
        actionBtn:SetScript("OnClick", function()
            local list = {}
            for _, it in ipairs(scanned) do if it.rule and it.rule.kind == "bank" then list[#list + 1] = it end end
            M.Deposit(list)
        end)
        actionBtn:Show()
        actionBtn:SetAlpha(open and 1 or 0.5)
    else
        status:SetText("")
        filterBtn.text:SetText(state.kindFilter == "all" and L["All rules"] or (state.kindFilter == "none" and L["No rule"] or KIND[state.kindFilter].label))
        actionBtn.text:SetText(L["All suggestions"])
        actionBtn:SetScript("OnClick", function() M.ApplySuggestions() end)
        actionBtn:Show()
        actionBtn:SetAlpha(1)
    end
    if #entries == 0 then
        win.empty:SetText(state.tab == "rules" and L["No rule matches."] or state.tab == "vendor" and L["Nothing to sell."]
            or (state.tab == "mail" and L["Nothing to mail. Set a rule in the Vendor tab."] or L["Nothing for the bank. Set a rule in the Vendor tab."]))
        win.empty:Show()
    else
        win.empty:Hide()
    end
end

local function Build()
    win = W.NewPlate(UIParent, C.page)
    win:SetSize(WIN_W, WIN_H)
    win:SetPoint("CENTER", UIParent, "CENTER", 80, 0)
    win:SetFrameStrata("MEDIUM")
    win:SetToplevel(true)
    win:SetMovable(true)
    win:SetClampedToScreen(true)
    win:EnableMouse(true)
    win:EnableMouseWheel(true)
    win:Hide()
    _G.ForeverCompanionManager = win
    tinsert(UISpecialFrames, "ForeverCompanionManager")
    win.skinKey = "bags"
    win.skinRowAll = {}
    local function Save()
        if not ns.db then return end
        local point, _, rel, x, y = win:GetPoint()
        ns.db.managerWin = { pos = { point, rel, x, y }, scale = win:GetScale() }
    end
    win:RegisterForDrag("LeftButton")
    win:SetScript("OnDragStart", win.StartMoving)
    win:SetScript("OnDragStop", function(self) self:StopMovingOrSizing(); Save() end)
    local saved = ns.db and ns.db.managerWin
    if saved and saved.pos then
        win:ClearAllPoints()
        win:SetPoint(saved.pos[1], UIParent, saved.pos[2], saved.pos[3], saved.pos[4])
    end
    local close = W.NewButton(win, "×", 20, 20, "GameFontNormal")
    close:SetPoint("TOPRIGHT", -8, -8)
    close:SetScript("OnClick", function() win:Hide() end)
    win.closeBtn = close
    win.titleText = win:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    win.titleText:SetPoint("TOP", 0, -12)
    win.titleText:SetText(L["Bags"])
    win.titleText:SetTextColor(C.gold[1], C.gold[2], C.gold[3])

    -- the plates (as in the auction house): the table with a head band, and the foot with the line of the state and the buttons
    local tbl = W.NewPlate(win, C.page)
    tbl:SetPoint("TOPLEFT", win, "TOPLEFT", 6, -4)
    tbl:SetPoint("BOTTOMRIGHT", win, "BOTTOMRIGHT", -6, 52)
    local band = tbl:CreateTexture(nil, "BACKGROUND")
    band:SetPoint("TOPLEFT", 1, -1)
    band:SetPoint("TOPRIGHT", -1, -1)
    band:SetHeight(26)
    band:SetColorTexture(0.13, 0.095, 0.06, 1)
    local rule = tbl:CreateTexture(nil, "ARTWORK")
    rule:SetPoint("TOPLEFT", 4, -27)
    rule:SetPoint("TOPRIGHT", -4, -27)
    rule:SetHeight(1)
    rule:SetColorTexture(C.goldDim[1], C.goldDim[2], C.goldDim[3], 0.8)
    local foot = W.NewPlate(win, C.page)
    foot:SetPoint("BOTTOMLEFT", win, "BOTTOMLEFT", 6, 6)
    foot:SetPoint("BOTTOMRIGHT", win, "BOTTOMRIGHT", -6, 6)
    foot:SetHeight(42)
    -- (the texts of the window are on a frame of their own, above the plates)
    local top = CreateFrame("Frame", nil, win)
    top:SetAllPoints()
    top:SetFrameLevel(win:GetFrameLevel() + 6)
    win.top = top

    -- the tabs, in the strip under the title bar
    tabs = {}
    local x = 56
    for _, def in ipairs({ { "vendor", L["Vendor"] }, { "mail", L["Mail"] }, { "bank", L["Bank"] }, { "rules", L["Rules"] } }) do
        local b = W.NewButton(win, def[2], 104, 22)
        b:SetPoint("TOPLEFT", win, "TOPLEFT", x, 22)
        b.tab, b.baseLabel = def[1], def[2]
        b:SetScript("OnClick", function() state.tab, state.offset = def[1], 0; dirty = true end)
        tabs[#tabs + 1] = b
        x = x + 110
    end
    -- the column heads
    local function Head(text, key, w)
        local fs = top:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        fs:SetPoint("RIGHT", win, "TOPLEFT", COLS[key] + 8, -18) -- (the middle of the head band)
        fs:SetWidth(w)
        fs:SetJustifyH("RIGHT")
        fs:SetTextColor(unpack(C.muted))
        fs:SetText(text)
        heads[key] = fs
    end
    heads = {}
    local iHead = top:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    iHead:SetPoint("LEFT", win, "TOPLEFT", 44, -18)
    iHead:SetTextColor(unpack(C.muted))
    iHead:SetText(L["Item"])
    Head(L["Qty"], "qty", 40)
    qtyHead = heads.qty
    Head(L["Vendor"], "vendor", 100)
    Head(L["AH"], "ah", 96)
    Head(L["Gain"], "gain", 64)
    local vHead = top:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    vHead:SetPoint("LEFT", win, "TOPLEFT", COLS.mark + 8, -18)
    vHead:SetTextColor(unpack(C.muted))
    vHead:SetText(L["Action"])
    actHead = vHead

    rows = {}
    for i = 1, MAX_ROWS do rows[i] = MakeRow(i) end
    win.empty = top:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    win.empty:SetPoint("CENTER", 0, 20)
    win.empty:SetWidth(520)
    win.empty:SetTextColor(unpack(C.muted))

    status = top:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    status:SetPoint("BOTTOMLEFT", 18, 20)
    status:SetWidth(380)
    status:SetJustifyH("LEFT")
    status:SetWordWrap(false)
    status:SetTextColor(unpack(C.muted))
    junkBtn = W.NewButton(win, L["Sell junk"], 150, 26)
    junkBtn:SetPoint("BOTTOMRIGHT", -184, 14)
    junkBtn:SetScript("OnClick", function() M.SellJunk() end)
    local armed
    sellBtn = W.NewButton(win, L["Sell without AH"], 160, 26)
    sellBtn:SetPoint("BOTTOMRIGHT", -16, 14)
    sellBtn:SetScript("OnClick", function(self)
        if not armed then
            armed = true
            self.text:SetText(L["Sure? Click again"])
            self.text:SetTextColor(unpack(C.red))
            C_Timer.After(3, function()
                if armed then armed = nil; self.text:SetText(L["Sell without AH"]); self.text:SetTextColor(unpack(C.text)) end
            end)
            return
        end
        armed = nil
        self.text:SetText(L["Sell without AH"])
        self.text:SetTextColor(unpack(C.text))
        M.Sell(NotWorthAuctioning())
    end)
    sellBtn:HookScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:AddLine(L["Sell without AH"], 1, 0.85, 0.4)
        GameTooltip:AddLine(L["Sells everything up to the chosen quality that the auction house would not pay more for."], 0.8, 0.8, 0.8, true)
        GameTooltip:Show()
    end)
    sellBtn:HookScript("OnLeave", function() GameTooltip:Hide() end)
    actionBtn = W.NewButton(win, "", 170, 26)
    actionBtn:SetPoint("BOTTOMRIGHT", -16, 14)
    actionBtn:Hide()

    -- (the tab of the rules: a search for names, and a filter for the kind of rule)
    searchBox = W.NewPlate(top, C.inset)
    searchBox:SetSize(210, 26)
    searchBox:SetPoint("BOTTOMLEFT", win, "BOTTOMLEFT", 16, 14)
    local edit = CreateFrame("EditBox", nil, searchBox)
    edit:SetPoint("TOPLEFT", 8, -4)
    edit:SetPoint("BOTTOMRIGHT", -8, 4)
    edit:SetAutoFocus(false)
    edit:SetFontObject("GameFontHighlight")
    local hint = searchBox:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    hint:SetPoint("LEFT", 10, 0)
    hint:SetTextColor(unpack(C.muted))
    hint:SetText(L["Search"])
    edit:SetScript("OnTextChanged", function(self)
        state.query = self:GetText() or ""
        hint:SetShown(state.query == "")
        state.offset = 0
        dirty = true
    end)
    edit:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    edit:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)
    searchBox:Hide()
    filterBtn = W.NewButton(win, L["All rules"], 130, 26)
    filterBtn:SetPoint("BOTTOMLEFT", win, "BOTTOMLEFT", 234, 14)
    filterBtn:SetScript("OnClick", function(self)
        Menu():Open(self, function()
            local out = {}
            local function Pick(label, key, icon)
                out[#out + 1] = { kind = "radio", state = state.kindFilter == key and "all" or "none", label = label, icon = icon, close = true,
                    onClick = function() state.kindFilter = key; state.offset = 0; dirty = true end }
            end
            Pick(L["All rules"], "all")
            for _, key in ipairs({ "keep", "mail", "bank", "vendor", "auction" }) do Pick(KIND[key].label, key, KIND[key].icon) end
            out[#out + 1] = { kind = "separator" }
            Pick(L["No rule"], "none")
            return out
        end)
    end)
    filterBtn:Hide()
    clearBtn = W.NewButton(win, L["Delete all rules"], 150, 26)
    clearBtn:SetPoint("BOTTOMRIGHT", win, "BOTTOMRIGHT", -194, 14)
    clearBtn:SetScript("OnClick", function() M.AskClearRules() end)
    clearBtn:Hide()

    -- the scroll bar: a track at the right edge of the table, with a thumb that can be dragged
    track = CreateFrame("Frame", nil, win)
    track:SetPoint("TOPRIGHT", win, "TOPRIGHT", -12, -34)
    track:SetSize(8, MAX_ROWS * ROW_H)
    track:EnableMouse(true)
    track.bg = track:CreateTexture(nil, "BACKGROUND")
    track.bg:SetAllPoints()
    track.bg:SetColorTexture(1, 1, 1, 0.06)
    track.thumb = CreateFrame("Button", nil, track)
    track.thumb:SetWidth(8)
    track.thumb.tex = track.thumb:CreateTexture(nil, "OVERLAY")
    track.thumb.tex:SetAllPoints()
    track.thumb.tex:SetColorTexture(C.gold[1], C.gold[2], C.gold[3], 0.75)
    track:Hide()
    local grab
    local function Drag()
        local _, cy = GetCursorPosition()
        cy = cy / track:GetEffectiveScale()
        local trackH = MAX_ROWS * ROW_H
        local h = track.thumb:GetHeight()
        local frac = (track:GetTop() - cy - (grab or h / 2)) / math.max(1, trackH - h)
        local total = track.total or MAX_ROWS
        state.offset = math.floor(math.max(0, math.min(1, frac)) * math.max(0, total - MAX_ROWS) + 0.5)
        dirty = true
    end
    track.thumb:SetScript("OnMouseDown", function(self)
        local _, cy = GetCursorPosition()
        grab = self:GetTop() - cy / track:GetEffectiveScale()
    end)
    track.thumb:SetScript("OnMouseUp", function() grab = nil end)
    track:SetScript("OnMouseDown", function() grab = track.thumb:GetHeight() / 2; Drag() end)
    track:SetScript("OnMouseUp", function() grab = nil end)
    track:SetScript("OnUpdate", function()
        if not grab then return end
        if IsMouseButtonDown("LeftButton") then Drag() else grab = nil end
    end)

    win:SetScript("OnMouseWheel", function(_, delta)
        state.offset = math.max(0, state.offset - delta * 3)
        dirty = true
    end)
    local acc = 0
    win:SetScript("OnUpdate", function(self, dt)
        if self.fcMoving then return end
        acc = acc + dt
        if (dirty and acc > 0.1) or acc > 2 then acc, dirty = 0, false; Render() end
    end)
    win:SetScript("OnShow", function() dirty = true end)
    M.ApplyFrameStyle()
end

function M.ApplyFrameStyle()
    if not win then return end
    local blizz = W.BlizzSkin(win, true, W.ICON.loot, L["Bags"], "bags")
    if blizz then win:SetBackdrop(nil) end
    win.titleText:SetShown(not blizz)
end

function M.Show(tab, byItself)
    if not win then Build() end
    if not byItself then autoOpened = nil end -- (opened by hand: it stays when the merchant goes)
    if tab then state.tab, state.offset = tab, 0 end
    M.ApplyFrameStyle()
    win:Show()
    win:Raise()
    dirty = true
end
function M.Hide() if win then win:Hide() end end
function M.IsShown() return win and win:IsShown() end
function M.Toggle()
    if win and win:IsShown() then M.Hide() else M.Show() end
end
function M.ResetWindow()
    if ns.db then ns.db.managerWin = nil end
    if win then win:ClearAllPoints(); win:SetPoint("CENTER", UIParent, "CENTER", 80, 0); win:SetScale(1) end
end

-- The events: the window opens by itself with a merchant, the mailbox and the bank (if that is on), and goes again when the last of them is
-- closed, if it was opened by itself (one that was open before, or that was opened by hand since, stays). Which of the three are open is
-- kept here: while the event of closing comes, the game's frame may still count as shown. Junk is sold when a merchant opens.
local open = { merchant = false, mail = false, bank = false }
local ev = CreateFrame("Frame")
for _, e in ipairs({ "MERCHANT_SHOW", "MERCHANT_CLOSED", "MAIL_SHOW", "MAIL_CLOSED", "BANKFRAME_OPENED", "BANKFRAME_CLOSED", "PLAYER_INTERACTION_MANAGER_FRAME_HIDE", "BAG_UPDATE_DELAYED" }) do
    pcall(ev.RegisterEvent, ev, e)
end
local function OpenFor(tab, which)
    open[which] = true
    if not M.AutoOpen() then return end
    local was = win and win:IsShown()
    M.Show(tab, true)
    if not was then autoOpened = true end
    if autoOpened and M.Watch then M.Watch() end
end
local function Closed(which)
    open[which] = false
    C_Timer.After(0.3, function() M.Reconcile() end)
    if autoOpened and win and win:IsShown() and not (open.merchant or open.mail or open.bank) then
        win:Hide()
        autoOpened = nil
    end
    dirty = true
end
-- (some versions of the game send other events for leaving the mailbox or the bank, or none that arrive: so what is open is also looked up
-- on the frames of the game, a little after each closing and every half second while the window stands there by itself)
local watch
local function Reconcile()
    if MerchantFrame then open.merchant = MerchantFrame:IsShown() and true or false end
    if MailFrame then open.mail = MailFrame:IsShown() and true or false end
    if BankFrame then open.bank = BankFrame:IsShown() and true or false end
    if autoOpened and win and win:IsShown() and not (open.merchant or open.mail or open.bank) then
        win:Hide()
        autoOpened = nil
    end
    if not (autoOpened and win and win:IsShown()) and watch then watch:Cancel(); watch = nil end
end
M.Reconcile = Reconcile
function M.Watch()
    if not watch then watch = C_Timer.NewTicker(0.5, Reconcile) end
end
ev:SetScript("OnEvent", function(_, event)
    if not ns.db then return end
    if event == "PLAYER_INTERACTION_MANAGER_FRAME_HIDE" then C_Timer.After(0.3, Reconcile); return end
    if event == "BAG_UPDATE_DELAYED" then dirty = true
    elseif event == "MERCHANT_SHOW" then
        OpenFor("vendor", "merchant")
        if M.JunkAuto() then C_Timer.After(0.4, function() if MerchantOpen() then M.SellJunk() end end) end
    elseif event == "MAIL_SHOW" then OpenFor("mail", "mail")
    elseif event == "BANKFRAME_OPENED" then OpenFor("bank", "bank")
    elseif event == "MERCHANT_CLOSED" then Closed("merchant")
    elseif event == "MAIL_CLOSED" then Closed("mail")
    else Closed("bank") end
end)

SLASH_FOREVERCOMPANIONBAGS1 = "/fcbags"
SlashCmdList.FOREVERCOMPANIONBAGS = function() M.Toggle() end
