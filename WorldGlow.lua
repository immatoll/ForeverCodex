local ADDON, ns = ...
local L = ns.L

-- Sparkles over the plant or vein you are standing near.
--
-- The game tells addons nothing about the objects around you, except the one that the interact key would use: the "softinteract" unit,
-- the object nearest in front of you (up to about 15 yards: the limit of the game). Given a few game settings, the game makes a nameplate
-- for that object, a frame that follows it in the world; the effect is a frame of ours on that nameplate. Which kind of object it is
-- comes from the picture its mouse cursor would have (a herb: the gathering hand, a vein: the pick), so it works for every plant and
-- vein, also for those that were never gathered before.
--
-- The settings of the game that are changed (the interact key "for both", the interaction icons on objects, how far and wide it
-- looks) are kept in ns.db.cvarBackup first and put back when the option is switched off. The nameplate of the object is only switched
-- on while a plant or a vein is the interact target, so that no other creature gets one. Not with a controller (the game uses the
-- interact target itself then). Another addon that does the same (the node glow of OneForAll, Lueur, Blackthornes Farmer) should not be
-- on at the same time.

local G = {}
ns.WorldGlow = G

local SOFT = "softinteract"
local MANAGED = { "SoftTargetInteract", "SoftTargetNameplateInteract", "SoftTargetInteractRange", "SoftTargetInteractArc",
    "SoftTargetInteractOnlyInRange", "SoftTargetIconGameObject" }
local FINDER = { herb = { 2383, 8387 }, ore = { 2580, 8388 }, skin = { 8613, 8617, 8618, 10768, 32678 } } -- (Find Herbs, Find Minerals, Skinning)
local COLORS = { herb = { 0.6, 1, 0.5 }, ore = { 0.65, 0.85, 1 }, skin = { 1, 0.8, 0.5 } }
local STAR = "Interface\\Cooldown\\star4"

local function Enabled() return ns.db and ns.db.settings.worldGlow == true end
local function InCombat() return InCombatLockdown and InCombatLockdown() end
local function GetCV(name)
    local ok, v = pcall(GetCVar, name)
    if ok then return v end
end
-- only when it differs: every change goes through the handlers of the game's own frames
local function SetCV(name, value)
    local now = GetCV(name)
    if now ~= nil and now ~= tostring(value) then pcall(SetCVar, name, tostring(value)) end
end

local pending, gate
local Restore

local function UsingGamepad()
    if GetCV("GamePadEnable") ~= "1" then return false end
    local ids = C_GamePad and C_GamePad.GetAllDeviceIDs and select(2, pcall(C_GamePad.GetAllDeviceIDs))
    return type(ids) == "table" and #ids > 0
end

-- force: the option has just been switched on (the player's own two settings, the interact key and the icons, are then set)
local function Apply(force)
    if InCombat() then pending = force and "force" or (pending or "apply") return end
    if UsingGamepad() then Restore() return end
    if not ns.db then return end
    if not ns.db.cvarBackup then
        force = true
        ns.db.cvarBackup = {}
        for _, name in ipairs(MANAGED) do ns.db.cvarBackup[name] = GetCV(name) or false end
    end
    if force then
        SetCV("SoftTargetInteract", 3) -- 0 off, 1 controller, 2 mouse and keyboard, 3 both
        SetCV("SoftTargetIconGameObject", 1) -- without the icons the game makes no nameplate for objects
    end
    SetCV("SoftTargetInteractRange", 15)
    SetCV("SoftTargetInteractArc", 2) -- all round
    SetCV("SoftTargetInteractOnlyInRange", 0)
    gate = nil
end

Restore = function()
    if InCombat() then pending = "restore" return end
    local backup = ns.db and ns.db.cvarBackup
    if not backup then return end
    for name, old in pairs(backup) do
        if old ~= false then SetCV(name, old) end
    end
    ns.db.cvarBackup = nil
    gate = nil
end

local function SetGate(open)
    if open == gate or InCombat() then return end
    gate = open
    SetCV("SoftTargetNameplateInteract", open and 1 or 0)
end

-- what is it ---------------------------------------------------------------------------------------------------------------------------
-- A dead creature that can be skinned: the tooltip of what the interact key would use says "Skinnable" (the game's own word for it).
local function SkinnableCorpse(unit)
    if ns.db.settings.worldGlowSkin == false then return nil end
    local okD, dead = pcall(UnitIsDead, unit)
    if not (okD and dead == true) then return nil end
    local okP, player = pcall(UnitIsPlayer, unit)
    if okP and player == true then return nil end
    if not (C_TooltipInfo and C_TooltipInfo.GetUnit) then return nil end
    local okT, data = pcall(C_TooltipInfo.GetUnit, unit)
    if not (okT and type(data) == "table" and type(data.lines) == "table") then return nil end
    local word = ns.Readable(_G.UNIT_SKINNABLE_LEATHER) or "Skinnable"
    for _, line in ipairs(data.lines) do
        local text = ns.Readable(line.leftText)
        if text and text:find(word, 1, true) then return "skin" end
    end
end

local probe, cursorIds
local function KindOf(unit)
    local ok, isObject = pcall(UnitIsGameObject, unit)
    if not (ok and isObject == true) then return SkinnableCorpse(unit) end
    if not probe then
        probe = UIParent:CreateTexture(nil, "BACKGROUND")
        probe:Hide()
        cursorIds = {}
        for file, kind in pairs({ GatherHerbs = "herb", Mine = "ore" }) do
            for _, prefix in ipairs({ "", "Unable" }) do
                local okId, id = pcall(GetFileIDFromPath, "Interface\\Cursor\\" .. prefix .. file)
                if okId and id then cursorIds[id] = kind end
            end
        end
    end
    if not SetUnitCursorTexture or not pcall(SetUnitCursorTexture, probe, unit, nil, true) then return nil end
    local tex = probe:GetTexture()
    if type(tex) == "number" and cursorIds[tex] then return cursorIds[tex] end
    local name = type(tex) == "string" and tex:lower() or ""
    if name:find("gather", 1, true) then return "herb" end
    if name:find("mine", 1, true) then return "ore" end
end

-- Only for a profession you have. Three ways to tell, any one is enough: the finding spell is known (Find Herbs / Find Minerals), the
-- skill list of the game has the profession, or the account data of this character has it.
local PROF_NAMES = { herb = { herbalism = true, ["kräuterkunde"] = true }, ore = { mining = true, bergbau = true },
    skin = { skinning = true, ["kürschnerei"] = true } }
local function Known(kind)
    local known = (C_SpellBook and C_SpellBook.IsSpellKnown) or IsPlayerSpell or IsSpellKnown
    if known then
        for _, id in ipairs(FINDER[kind]) do
            local ok, yes = pcall(known, id)
            if ok and yes then return "spell" end
        end
    end
    if GetNumSkillLines and GetSkillLineInfo then
        for i = 1, (GetNumSkillLines() or 0) do
            local ok, name = pcall(GetSkillLineInfo, i)
            if ok and type(name) == "string" and PROF_NAMES[kind][name:lower()] then return "skill list" end
        end
    end
    local rec = ns.Acc and ns.Acc.Me and ns.Acc.Me()
    for _, sk in ipairs(rec and rec.skills or {}) do
        if sk.name and PROF_NAMES[kind][tostring(sk.name):lower()] then return "account data" end
    end
end
function G.Knows(kind) return Known(kind) ~= nil end
local function Trained(kind)
    if ns.db.settings.worldGlowOnlyMine == false then return true end
    return Known(kind) ~= nil
end

-- the effect ---------------------------------------------------------------------------------------------------------------------------
local SPARKS = {
    { x = -26, y = 10, size = 18, phase = 0.0 }, { x = 24, y = 22, size = 14, phase = 0.9 }, { x = 18, y = -8, size = 12, phase = 1.8 },
    { x = -12, y = -14, size = 10, phase = 2.7 }, { x = 2, y = 34, size = 13, phase = 3.6 }, { x = -30, y = 30, size = 9, phase = 4.5 },
}
local fx, anchor

local function Build()
    fx = CreateFrame("Frame")
    fx:SetSize(2, 2)
    fx:EnableMouse(false)
    fx.sparks = {}
    for i, def in ipairs(SPARKS) do
        local t = fx:CreateTexture(nil, "OVERLAY", nil, 3)
        t:SetTexture(STAR)
        t:SetBlendMode("ADD")
        t:SetSize(def.size * 2, def.size * 2)
        t:SetPoint("CENTER", fx, "CENTER", def.x, def.y)
        fx.sparks[i] = t
    end
    fx:Hide()
end

-- The game's nameplate of the object (name, health bar) is made see-through while the effect is on it, and shown again when it is not (the
-- effect itself ignores the alpha of its nameplate). The game may set the alpha again as it fades the plate, so it is kept at 0.
local veiled
local function Veil(plate, on)
    local frame = plate and plate.UnitFrame
    if not frame then return end
    if on then
        if frame:GetAlpha() > 0 then pcall(frame.SetAlpha, frame, 0) end
        veiled = plate
    else
        pcall(frame.SetAlpha, frame, 1)
        if veiled == plate then veiled = nil end
    end
end

local function Animate(self)
    local t = GetTime()
    if anchor and ns.db.settings.worldGlowHidePlate ~= false then Veil(anchor, true) end
    for i, tex in ipairs(self.sparks) do
        local a = math.sin(t * 2.4 + SPARKS[i].phase)
        tex:SetAlpha(a > 0 and a or 0)
        tex:SetRotation(t * 0.6 + i)
    end
end

local function Release()
    if veiled then Veil(veiled, false) end
    if not fx then return end
    fx:SetScript("OnUpdate", nil)
    fx:Hide()
    fx:ClearAllPoints()
    fx:SetParent(nil)
    anchor = nil
end

local function Attach(plate, kind)
    if not fx then Build() end
    local st = ns.db.settings
    local col = COLORS[kind] or COLORS.herb
    for _, tex in ipairs(fx.sparks) do
        tex:SetVertexColor(col[1], col[2], col[3])
        tex:Show()
    end
    if anchor ~= plate then
        Release()
        fx:SetParent(plate)
        local ok, level = pcall(plate.GetFrameLevel, plate)
        if ok and type(level) == "number" then fx:SetFrameLevel(math.max(level - 1, 0)) end
        if fx.SetIgnoreParentAlpha then fx:SetIgnoreParentAlpha(true) end
        anchor = plate
    end
    fx:ClearAllPoints()
    fx:SetPoint("CENTER", plate, "CENTER", 0, -(tonumber(st.worldGlowDrop) or 45))
    fx:SetScript("OnUpdate", Animate)
    fx:Show()
end

local function Evaluate()
    if not Enabled() then Release() return end
    local kind = KindOf(SOFT)
    if not (kind and Trained(kind)) then SetGate(false); Release() return end
    SetGate(true)
    local plate = C_NamePlate and C_NamePlate.GetNamePlateForUnit and select(2, pcall(C_NamePlate.GetNamePlateForUnit, SOFT))
    if plate then
        Attach(plate, kind)
    else
        Release() -- (the nameplate comes with NAME_PLATE_UNIT_ADDED)
        -- no nameplate for it at all: the game's nameplates are probably off, and the effect has nothing to hang on
        if not G.hintedPlates and C_Timer and C_Timer.After then
            G.hintedPlates = true
            C_Timer.After(1.5, function()
                local again = select(2, pcall(C_NamePlate.GetNamePlateForUnit, SOFT))
                if not again and Enabled() and KindOf(SOFT) then
                    print("|cffffd100ForeverCompanion:|r " .. L["The sparkle needs the nameplates of the game (switch them on in the game's options, or with the key for nameplates)."])
                end
            end)
        end
    end
end

local EVENTS = { "LOOT_CLOSED", "PLAYER_SOFT_INTERACT_CHANGED", "NAME_PLATE_UNIT_ADDED", "NAME_PLATE_UNIT_REMOVED", "PLAYER_ENTERING_WORLD",
    "PLAYER_REGEN_ENABLED", "PLAYER_REGEN_DISABLED" }
local ev = CreateFrame("Frame")
ev:SetScript("OnEvent", function(_, event, unit)
    if event == "PLAYER_REGEN_DISABLED" then
        SetGate(false) -- (settings cannot change in combat: the nameplate is closed just before)
        Release()
        return
    end
    if event == "PLAYER_ENTERING_WORLD" then
        Apply()
    elseif event == "PLAYER_REGEN_ENABLED" then
        if pending == "restore" then Restore() elseif pending then Apply(pending == "force") end
        pending = nil
    elseif event == "NAME_PLATE_UNIT_REMOVED" then
        local plate = C_NamePlate and C_NamePlate.GetNamePlateForUnit and select(2, pcall(C_NamePlate.GetNamePlateForUnit, unit))
        if plate and plate == anchor then Release() end
        return
    end
    if event == "LOOT_CLOSED" and C_Timer and C_Timer.After then
        -- (a corpse is skinned or looted: the tooltip changes a moment later)
        C_Timer.After(0.4, Evaluate)
    end
    Evaluate()
end)

-- the option: events only while it is on; the settings of the game back when it goes off
function G.Refresh(switched)
    if not ns.db then return end
    if Enabled() then
        for _, e in ipairs(EVENTS) do pcall(ev.RegisterEvent, ev, e) end
        Apply(switched == true)
        Evaluate()
    else
        ev:UnregisterAllEvents()
        Release()
        Restore()
    end
end

-- /fc glow: what the effect sees right now (face a plant or a vein, then type it)
function G.Report()
    local out = {}
    local function P(...)
        local t = {}
        for i = 1, select("#", ...) do t[i] = tostring((select(i, ...))) end
        out[#out + 1] = table.concat(t, " ")
    end
    P("option on:", Enabled(), " only my professions:", ns.db.settings.worldGlowOnlyMine ~= false,
        " height:", ns.db.settings.worldGlowDrop or 45)
    P("combat:", InCombat() and true or false, " gamepad:", UsingGamepad(), " events registered: use /reload after switching it on if 0")
    for _, name in ipairs(MANAGED) do P("  cvar", name, "=", tostring(GetCV(name))) end
    P("backup kept:", ns.db.cvarBackup and "yes" or "no")
    local okE, exists = pcall(UnitExists, SOFT)
    P("softinteract exists:", okE and tostring(exists) or "ERROR")
    if okE and exists then
        local okN, uname = pcall(UnitName, SOFT)
        P("  name:", okN and ns.Readable(uname) or "(secret)")
        local okG, isObj = pcall(UnitIsGameObject, SOFT)
        P("  is object:", okG and tostring(isObj) or "ERROR (UnitIsGameObject: " .. type(UnitIsGameObject) .. ")")
        local tex
        if not probe then KindOf(SOFT) end
        if probe and SetUnitCursorTexture then
            local okC = pcall(SetUnitCursorTexture, probe, SOFT, nil, true)
            tex = probe:GetTexture()
            P("  cursor texture:", okC and tostring(tex) or "ERROR", " SetUnitCursorTexture:", type(SetUnitCursorTexture))
        else
            P("  cursor texture: no probe; SetUnitCursorTexture:", type(SetUnitCursorTexture))
        end
        local kind = KindOf(SOFT)
        P("  skinnable corpse:", tostring(SkinnableCorpse(SOFT)))
        P("  kind:", tostring(kind), " profession known by:", kind and tostring(Known(kind)) or "-")
        local okP, plate = pcall(C_NamePlate.GetNamePlateForUnit, SOFT)
        P("  nameplate:", okP and tostring(plate) or "ERROR", " effect shown:", fx and fx:IsShown() or false)
    end
    return table.concat(out, "\n")
end

local boot = CreateFrame("Frame")
boot:RegisterEvent("PLAYER_LOGIN")
boot:SetScript("OnEvent", function(self)
    self:UnregisterAllEvents()
    G.Refresh()
end)
