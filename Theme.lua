local ADDON, ns = ...
local W = ns.W
local C = W.C

-- The measures a window's layout is made of, in one place (kept per window group, e.g. "hud" for Kills & Loot), so that they can be
-- looked at and changed together instead of being numbers in the code of each window. A value changed here is kept in the saved
-- variables (ForeverCodexDB.theme.<group>.<key>) and is used when the windows are built, that is after a reload.
-- A window reads its measures with ns.Theme.Get(group, key). /fctheme opens the developer window to change them.

local T = {}
ns.Theme = T

-- group -> key -> default
T.defaults = {
    hud = {
        tabTop = 92,     -- where the tabs / list heads begin, from the window's top
        rowH = 32,       -- the height of a row of the list
        valW = 72,       -- the column "value" (from the right edge)
        totW = 56,       -- the column "total value"
        avgW = 72,       -- the column "average value"
        icoSize = 20,    -- a loot icon in a row
        icoStep = 23,    -- the distance from one loot icon to the next
        levelW = 30,     -- the column of a creature's level before its name
        nameX = 10,      -- how far from the left edge the names begin
        cardH = 46,      -- the height of the stat cards (value, per hour, session)
        tileH = 36,      -- the height of the small figures
        tileGap = 5,     -- the space between them
    },
}

-- What was set in the window designer (/fcbg) and exported (the button "Export" of /fctheme) is pasted here and is then the default of the
-- code: T.skins per window (background, how it lies, icon, transparency), T.design for the window style settings. What a user sets
-- himself on top of it (ns.db.settings) wins.
T.skins = {}
T.design = {}

-- how the developer window shows them: key, label, step, smallest, largest
T.meta = {
    hud = {
        { "tabTop", "Top of the list heads", 2, 60, 160 },
        { "rowH", "Row height", 1, 20, 60 },
        { "valW", "Column: value", 2, 40, 140 },
        { "totW", "Column: total", 2, 30, 140 },
        { "avgW", "Column: average", 2, 40, 140 },
        { "icoSize", "Loot icon size", 1, 12, 32 },
        { "icoStep", "Loot icon distance", 1, 14, 40 },
        { "levelW", "Level column", 1, 16, 60 },
        { "nameX", "Names from the left", 1, 0, 40 },
        { "cardH", "Stat card height", 2, 30, 80 },
        { "tileH", "Small figure height", 2, 24, 60 },
        { "tileGap", "Space between figures", 1, 0, 16 },
    },
}
T.groupLabel = { hud = "Kills & Loot" }

local function Saved(group, key)
    local db = ns.db or _G.ForeverCodexDB -- (the saved variables are there from ADDON_LOADED on: a window reads its measures through ns.AfterLoad)
    local g = db and db.theme and db.theme[group]
    return g and g[key]
end

function T.Get(group, key)
    local v = Saved(group, key)
    if type(v) ~= "number" then v = T.defaults[group][key] end
    return v
end

local function Set(group, key, value)
    local db = ns.db or _G.ForeverCodexDB
    if not db then return end
    db.theme = db.theme or {}
    db.theme[group] = db.theme[group] or {}
    if value == T.defaults[group][key] then value = nil end
    db.theme[group][key] = value
end

-- the developer window ------------------------------------------------------------------------------------------------------------

local win, rows = nil, {}
local group = "hud"
local ROW_H, LABEL_W = 26, 190

local function Refresh()
    for i, def in ipairs(T.meta[group]) do
        local row = rows[i]
        local v, d = T.Get(group, def[1]), T.defaults[group][def[1]]
        row.value:SetText(tostring(v))
        row.value:SetTextColor(unpack(v == d and C.text or C.gold))
        row.default:SetText(v == d and "" or ("(" .. d .. ")"))
    end
end

local function Build()
    local f = W.NewPlate(UIParent, C.page)
    local n = #T.meta[group]
    f:SetSize(440, 96 + n * ROW_H + 40)
    f:SetPoint("CENTER", 300, 0)
    f:SetFrameStrata("FULLSCREEN_DIALOG")
    f:SetMovable(true)
    f:SetClampedToScreen(true)
    f:EnableMouse(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", f.StartMoving)
    f:SetScript("OnDragStop", f.StopMovingOrSizing)
    local title = f:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    title:SetPoint("TOPLEFT", 14, -12)
    title:SetText("Theme - " .. (T.groupLabel[group] or group))
    local note = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    note:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -6)
    note:SetPoint("RIGHT", -14, 0)
    note:SetJustifyH("LEFT")
    note:SetTextColor(unpack(C.muted))
    note:SetText("The measures of the window's layout. A change is kept and takes effect after a reload.")
    local close = W.NewButton(f, "×", 20, 20, "GameFontNormal")
    close:SetPoint("TOPRIGHT", -8, -8)
    close:SetScript("OnClick", function() f:Hide() end)
    for i, def in ipairs(T.meta[group]) do
        local key, label, step, lo, hi = def[1], def[2], def[3], def[4], def[5]
        local y = -72 - (i - 1) * ROW_H
        local row = {}
        local fs = f:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        fs:SetPoint("TOPLEFT", 14, y - 4)
        fs:SetWidth(LABEL_W)
        fs:SetJustifyH("LEFT")
        fs:SetText(label)
        local minus = W.NewButton(f, "-", 24, 22, "GameFontNormal")
        minus:SetPoint("TOPLEFT", 14 + LABEL_W + 10, y)
        row.value = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        row.value:SetPoint("LEFT", minus, "RIGHT", 4, 0)
        row.value:SetWidth(40)
        row.value:SetJustifyH("CENTER")
        local plus = W.NewButton(f, "+", 24, 22, "GameFontNormal")
        plus:SetPoint("LEFT", row.value, "RIGHT", 4, 0)
        row.default = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        row.default:SetPoint("LEFT", plus, "RIGHT", 10, 0)
        row.default:SetTextColor(unpack(C.muted))
        local function Change(delta)
            local v = math.max(lo, math.min(hi, T.Get(group, key) + delta))
            Set(group, key, v)
            Refresh()
        end
        minus:SetScript("OnClick", function() Change(-step) end)
        plus:SetScript("OnClick", function() Change(step) end)
        rows[i] = row
    end
    local reset = W.NewButton(f, "Reset all", 90, 24)
    reset:SetPoint("BOTTOMLEFT", 14, 14)
    reset:SetScript("OnClick", function()
        for _, def in ipairs(T.meta[group]) do Set(group, def[1], nil) end
        Refresh()
    end)
    local export = W.NewButton(f, "Export", 80, 24)
    export:SetPoint("LEFT", reset, "RIGHT", 8, 0)
    export:SetScript("OnClick", function() W.Console(T.Export(), "Theme export (copy into Theme.lua)") end)
    local reload = W.NewButton(f, "Reload UI", 100, 24)
    reload:SetPoint("BOTTOMRIGHT", -14, 14)
    reload:SetScript("OnClick", function() ReloadUI() end)
    return f
end

-- The current values as Lua text to copy into this file (T.defaults and T.design), so that what was tried here becomes the default of the
-- code. The design is what the window style settings hold now: style, background and how it lies, plate transparency.
function T.Export()
    local out = { "-- exported from /fctheme", "T.defaults = {" }
    local groups = {}
    for g in pairs(T.defaults) do groups[#groups + 1] = g end
    table.sort(groups)
    for _, g in ipairs(groups) do
        out[#out + 1] = "    " .. g .. " = {"
        for _, def in ipairs(T.meta[g] or {}) do
            out[#out + 1] = ("        %s = %s,"):format(def[1], tostring(T.Get(g, def[1])))
        end
        out[#out + 1] = "    },"
    end
    out[#out + 1] = "}"
    local st = ns.db and ns.db.settings or {}
    local tex = "nil"
    if type(st.blizzBgTex) == "table" then
        if st.blizzBgTex.atlas then
            tex = ("{ atlas = %q }"):format(st.blizzBgTex.atlas)
        elseif st.blizzBgTex.file then
            tex = type(st.blizzBgTex.file) == "number" and ("{ file = %d }"):format(st.blizzBgTex.file) or ("{ file = %q }"):format(st.blizzBgTex.file)
        end
    end
    -- what is set per window (background, how it lies, icon, transparency)
    local function Ser(v, indent)
        if type(v) == "string" then return ("%q"):format(v) end
        if type(v) ~= "table" then return tostring(v) end
        local keys = {}
        for k in pairs(v) do keys[#keys + 1] = k end
        table.sort(keys, function(x, y) return tostring(x) < tostring(y) end)
        local parts = {}
        for _, k in ipairs(keys) do parts[#parts + 1] = indent .. "    " .. tostring(k) .. " = " .. Ser(v[k], indent .. "    ") .. "," end
        if #parts == 0 then return "{}" end
        return "{\n" .. table.concat(parts, "\n") .. "\n" .. indent .. "}"
    end
    out[#out + 1] = "T.skins = " .. Ser((ns.db and ns.db.settings and ns.db.settings.skins) or {}, "")
    out[#out + 1] = "T.design = {"
    out[#out + 1] = ("    frameStyle = %q,"):format(tostring(st.frameStyle or "ornate"))
    out[#out + 1] = ("    blizzBg = %q,"):format(tostring(st.blizzBg or "standard"))
    out[#out + 1] = ("    blizzBgMode = %q,"):format(tostring(st.blizzBgMode or "stretch"))
    out[#out + 1] = "    blizzBgTex = " .. tex .. ","
    out[#out + 1] = ("    panelAlpha = %s,"):format(tostring(st.panelAlpha or 1))
    out[#out + 1] = "}"
    return table.concat(out, "\n")
end

SLASH_FOREVERCODEXTHEME1 = "/fctheme"
SlashCmdList.FOREVERCODEXTHEME = function()
    if not win then win = Build() end
    if win:IsShown() then win:Hide() return end
    Refresh()
    win:Show()
end
