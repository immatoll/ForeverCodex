local ADDON, ns = ...
local W = ns.W
local UI = ns.UI
local C = W.C

-- Debug aid: /fcbg opens a gallery of every background picture of the game it can find (textures that frames keep under a name like Bg or
-- Background, and the atlases with "bg" or "background" in their name) and a test window in the Blizzard style with a few sample parts.
-- A click on the list (or the buttons) shows that picture as the background of the Blizzard window style, so that one can be picked by
-- eye. The one shown last stays (setting "blizzBgTex").

local lists, tab = {}, "bg"          -- the pictures of the two tabs: backgrounds, icons
local list, filtered, idx = nil, {}, 0
local idxOf = { bg = 0, icon = 0 }
local bar, test
local target = "all"                -- which window the choices are for: "all", or one of the windows (see TARGETS)
local TARGETS = { { "all", "All windows", 96 }, { "hud", "Kills & Loot", 96 }, { "account", "Account", 66 }, { "map", "Map", 50 },
    { "settings", "Settings", 66 }, { "journal", "Journal", 64 }, { "ah", "Auction house", 96 }, { "bags", "Bags", 50 } }
local ALPHAS = { { "100%", 1 }, { "85%", 0.85 }, { "70%", 0.7 }, { "55%", 0.55 } }

-- what is set for the chosen window (a layer of W.SkinOf, in ns.db.settings.skins)
local function Layer()
    local st = ns.db.settings
    st.skins = st.skins or {}
    st.skins[target] = st.skins[target] or {}
    return st.skins[target]
end
local function Key() return target ~= "all" and target or nil end
local query, kindFilter = "", "all"
local Use

local function Match(name)
    local n = tostring(name):lower()
    return n:find("bg", 1, true) or n:find("background", 1, true) or n:find("backdrop", 1, true)
end

-- names of the addons that are not the game's own: what they keep in globals starts with their name
local function OtherAddons()
    local out = {}
    local get = C_AddOns and C_AddOns.GetAddOnInfo or GetAddOnInfo
    local count = C_AddOns and C_AddOns.GetNumAddOns or GetNumAddOns
    if not (get and count) then return out end
    for i = 1, count() do
        local name = get(i)
        if type(name) == "table" then name = name.name end
        if type(name) == "string" and #name >= 4 and not name:find("^Blizzard_") then out[#out + 1] = name:lower() end
    end
    return out
end

local PARTS = { "nineslice", "edge", "corner", "border", "button", "icon", "glow", "highlight", "slot", "bar", "arrow", "shadow" }
local function Partial(name)
    local n = tostring(name):lower()
    for _, p in ipairs(PARTS) do if n:find(p, 1, true) then return true end end
    return false
end

local function Candidates()
    local seen, files, atlases = {}, {}, {}
    local others = OtherAddons()
    local function Foreign(gname)
        local n = gname:lower()
        if n:find("^lib") or n:find("^ace") or n:find("^forevercompanion") or n:find("^bugsack") or n:find("^_") then return true end
        for _, o in ipairs(others) do if n:sub(1, #o) == o then return true end end
        return false
    end
    local function Add(kind, value, label)
        if value == nil or value == "" then return end
        local key = kind .. ":" .. tostring(value)
        if seen[key] then return end
        seen[key] = true
        local e = { kind = kind, value = value, label = label or tostring(value) }
        if kind == "atlas" then atlases[#atlases + 1] = e else files[#files + 1] = e end
    end
    local function AddTexture(tex, label)
        local atlas = tex.GetAtlas and tex:GetAtlas()
        if atlas then Add("atlas", atlas, label) return end
        local file = tex.GetTexture and tex:GetTexture()
        if type(file) == "number" or type(file) == "string" then Add("file", file, label) end
    end
    for gname, obj in pairs(_G) do
        if type(gname) == "string" and type(obj) == "table" and not Foreign(gname) then
            pcall(function()
                if not obj.GetObjectType then return end
                if obj:GetObjectType() == "Texture" then
                    if Match(gname) then AddTexture(obj, gname) end
                else
                    for k, v in pairs(obj) do
                        if type(k) == "string" and Match(k) and type(v) == "table" and v.GetObjectType and v:GetObjectType() == "Texture" then
                            AddTexture(v, gname .. "." .. k)
                        end
                    end
                end
            end)
        end
    end
    if C_Texture and C_Texture.GetAtlasElements then
        local ok, names = pcall(C_Texture.GetAtlasElements)
        if ok and type(names) == "table" then
            for _, n in ipairs(names) do if Match(n) and not Partial(n) then Add("atlas", n, n) end end
        end
    end
    table.sort(files, function(a, b) return a.label < b.label end)
    table.sort(atlases, function(a, b) return a.value < b.value end)
    for _, e in ipairs(atlases) do files[#files + 1] = e end
    return files
end

-- Pictures for the ring: the atlases with a name like an icon, a portrait, a crest, and the game's own icons (the ones of the macro
-- window, by number).
local ICON_WORDS = { "icon", "portrait", "emblem", "crest", "micromenu", "classicon", "poi", "ability", "spellicon" }
local ICON_NOT = { "nineslice", "edge", "corner", "shadow", "glow", "highlight", "arrow", "bar-" }
local function IconCandidates()
    local out, seen = {}, {}
    if C_Texture and C_Texture.GetAtlasElements then
        local ok, names = pcall(C_Texture.GetAtlasElements)
        if ok and type(names) == "table" then
            table.sort(names)
            for _, n in ipairs(names) do
                local low = tostring(n):lower()
                local want, bad = false, false
                for _, w in ipairs(ICON_WORDS) do if low:find(w, 1, true) then want = true break end end
                for _, w in ipairs(ICON_NOT) do if low:find(w, 1, true) then bad = true break end end
                if want and not bad and not seen[n] then
                    seen[n] = true
                    out[#out + 1] = { kind = "atlas", value = n, label = n }
                end
            end
        end
    end
    local ids = {}
    for _, fn in ipairs({ "GetMacroIcons", "GetMacroItemIcons", "GetLooseMacroIcons", "GetLooseMacroItemIcons" }) do
        if _G[fn] then pcall(_G[fn], ids) end
    end
    for _, id in ipairs(ids) do
        if not seen[id] then
            seen[id] = true
            out[#out + 1] = { kind = "file", value = id, label = "Icon " .. tostring(id) }
        end
    end
    return out
end

-- Every atlas of the game, to look for a picture by its name (a search for "beam", "ray", "light", "pillar" ...). A click only shows the name:
-- nothing is set for a window.
local function AllAtlasCandidates()
    local out = {}
    if C_Texture and C_Texture.GetAtlasElements then
        local ok, names = pcall(C_Texture.GetAtlasElements)
        if ok and type(names) == "table" then
            table.sort(names)
            for _, n in ipairs(names) do out[#out + 1] = { kind = "atlas", value = n, label = tostring(n) } end
        end
    end
    return out
end

local function ApplyTest()
    if not test then return end
    test.skinKey = Key() -- the test window shows what the chosen window gets
    if W.BlizzSkin(test, true, W.ICON.journal, "Test window") then test:SetBackdrop(nil) end
    -- the picture as it is, for comparison with what the window shows
    local spec = ns.db.settings.blizzBgTex
    if test.swatch and spec then
        if spec.atlas then test.swatch:SetAtlas(spec.atlas, false) else test.swatch:SetTexture(spec.file); test.swatch:SetTexCoord(0, 1, 0, 1) end
    end
end

local function ApplyStyles()
    for _, fn in ipairs({ UI and UI.ApplyFrameStyle, ns.HUD and ns.HUD.ApplyFrameStyle, ns.MapMain and ns.MapMain.ApplyFrameStyle,
        ns.AccountWindow and ns.AccountWindow.ApplyFrameStyle, ns.ItemInfo and ns.ItemInfo.ApplyFrameStyle,
        ns.AuctionWindow and ns.AuctionWindow.ApplyFrameStyle, ApplyTest }) do
        pcall(fn)
    end
    if ns.Settings and ns.Settings.ApplyFrameStyle then pcall(ns.Settings.ApplyFrameStyle) end
end

-- the gallery -----------------------------------------------------------------------------------------------------------------
local COLS, TILE_W, TILE_H, GAP = 5, 112, 80, 6
local GRID_TOP, VISIBLE = 104, 6 -- (the tiles fill the frame to its end: whole rows only)
local GRID_H = VISIBLE * (TILE_H + GAP) - GAP
local tiles, top, thumb, track = {}, 0, nil, nil
local MODES = { { "Stretch", "stretch" }, { "Zoom", "zoom" }, { "Fit", "fit" }, { "Center", "center" },
    { "Tile 128", "tile128" }, { "Tile 256", "tile256" }, { "Tile 512", "tile512" } }

local function Filter()
    filtered = {}
    local words = {}
    for w in query:lower():gmatch("%S+") do words[#words + 1] = w end
    for k, e in ipairs(list) do
        if kindFilter == "all" or (kindFilter == "atlas") == (e.kind == "atlas") then
            local hay = (e.label .. " " .. tostring(e.value)):lower()
            local ok = true
            for _, w in ipairs(words) do
                if not hay:find(w, 1, true) then ok = false break end
            end
            if ok then filtered[#filtered + 1] = k end
        end
    end
end

local function Render()
    local rows = math.ceil(#filtered / COLS)
    local maxTop = math.max(0, rows - VISIBLE)
    top = math.max(0, math.min(maxTop, top))
    for n, t in ipairs(tiles) do
        local k = filtered[top * COLS + n]
        local e = k and list[k]
        t.k = k
        if e then
            if e.kind == "atlas" then
                t.tex:SetAtlas(e.value, false)
            else
                t.tex:SetTexture(e.value)
                t.tex:SetTexCoord(0, 1, 0, 1)
            end
            t.label:SetText(e.label)
            t.sel:SetAlpha(k == idx and 1 or 0)
            t:Show()
        else
            t:Hide()
        end
    end
    track:SetShown(rows > VISIBLE)
    if rows > VISIBLE then
        local h = math.max(24, GRID_H * VISIBLE / rows)
        thumb:ClearAllPoints()
        thumb:SetPoint("TOP", track, "TOP", 0, -(GRID_H - h) * top / maxTop)
        thumb:SetHeight(h)
    end
    bar.count:SetText(("%d of %d"):format(#filtered, #list))
end

function Use(k)
    if not list or #list == 0 then return end
    idx = ((k - 1) % #list) + 1
    local e = list[idx]
    ns.db.settings.frameStyle = "blizzard"
    if tab == "all" then
        -- (only to look at: the name is shown, nothing is set)
        bar.text:SetText(("%d   atlas   %s"):format(idx, e.label))
        Render()
        return
    end
    if tab == "bg" then
        Layer().bgTex = { [e.kind] = e.value }
    else
        Layer().icon = e.kind == "atlas" and { atlas = e.value } or e.value
    end
    ApplyStyles()
    bar.text:SetText(("%d   %s   %s"):format(idx, e.kind, e.label))
    Render()
end

-- the next / previous picture of what the filter lets through
local function Step(d)
    if #filtered == 0 then return end
    local pos = 0
    for n, k in ipairs(filtered) do if k == idx then pos = n break end end
    pos = ((pos - 1 + d) % #filtered) + 1
    Use(filtered[pos])
    local row = math.floor((pos - 1) / COLS)
    if row < top or row >= top + VISIBLE then top = math.max(0, row - 1); Render() end
end

-- what the chosen window has now (background / icon of the tab shown) is marked in the list, and the list is scrolled to it
local function Sync()
    if not list then return end
    local sk = W.SkinOf(Key())
    local kind, value
    if tab == "bg" then
        local spec = sk.spec
        if type(spec) == "table" then
            if spec.atlas then kind, value = "atlas", spec.atlas elseif spec.file then kind, value = "file", spec.file end
        end
    else
        local icon = sk.icon
        if type(icon) == "table" then
            if icon.atlas then kind, value = "atlas", icon.atlas end
        elseif icon ~= nil then
            kind, value = "file", icon
        end
    end
    idx = 0
    if kind then
        for k, e in ipairs(list) do
            if e.kind == kind and tostring(e.value) == tostring(value) then idx = k break end
        end
    end
    local e = idx > 0 and list[idx]
    if e then
        bar.text:SetText(("%d   %s   %s"):format(idx, e.kind, e.label))
        for pos, k in ipairs(filtered) do
            if k == idx then top = math.max(0, math.floor((pos - 1) / COLS) - 1) break end
        end
    else
        bar.text:SetText(kind and ("%s   %s   (not in this list)"):format(kind, tostring(value)) or "(the standard of the window)")
    end
    Render()
end

-- an empty window in the Blizzard style with a few parts to judge a background by
local function BuildTest()
    local f = W.NewPlate(UIParent, C.page)
    f:SetSize(520, 380)
    _G.ForeverCompanionBgTest = f -- (for /fcdump ForeverCompanionBgTest.blizzFrame)
    f:SetPoint("CENTER", 260, 0)
    f:SetFrameStrata("DIALOG")
    f:SetToplevel(true)
    f:SetMovable(true)
    f:SetClampedToScreen(true)
    f:EnableMouse(true)
    local close = W.NewButton(f, "×", 20, 20, "GameFontNormal")
    close:SetPoint("TOPRIGHT", -8, -8)
    close:SetScript("OnClick", function() f:Hide() end)
    f.closeBtn = close
    for k, label in ipairs({ "Button", "Another", "Third one" }) do
        local b = W.NewButton(f, label, 110, 24)
        b:SetPoint("TOPLEFT", 16 + (k - 1) * 118, -16)
    end
    -- (little in it, so that the background shows)
    local plate = W.NewPlate(f, C.inset)
    plate:SetSize(220, 64)
    plate:SetPoint("BOTTOMLEFT", 16, 16)
    local text = plate:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    text:SetPoint("TOPLEFT", 12, -12)
    text:SetText("Text on a plate")
    local muted = plate:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    muted:SetPoint("TOPLEFT", text, "BOTTOMLEFT", 0, -6)
    muted:SetTextColor(unpack(C.muted))
    muted:SetText("2g 14s 36c   x7")
    local head = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    head:SetPoint("TOPLEFT", 16, -52)
    head:SetText("Text straight on the background")
    local swatchBox = f:CreateTexture(nil, "ARTWORK")
    swatchBox:SetPoint("TOPRIGHT", -16, -52)
    swatchBox:SetSize(204, 154)
    swatchBox:SetColorTexture(C.gold[1], C.gold[2], C.gold[3], 1)
    f.swatch = f:CreateTexture(nil, "OVERLAY")
    f.swatch:SetPoint("TOPLEFT", swatchBox, "TOPLEFT", 2, -2)
    f.swatch:SetPoint("BOTTOMRIGHT", swatchBox, "BOTTOMRIGHT", -2, 2)
    local bottom = W.NewButton(f, "Confirm", 120, 26)
    bottom:SetPoint("BOTTOMRIGHT", -16, 18)
    f:Hide()
    return f
end

local function Tile(i, parent)
    local t = CreateFrame("Button", nil, parent)
    t:SetSize(TILE_W, TILE_H)
    local col, row = (i - 1) % COLS, math.floor((i - 1) / COLS)
    t:SetPoint("TOPLEFT", parent, "TOPLEFT", 12 + col * (TILE_W + GAP), -GRID_TOP - row * (TILE_H + GAP))
    t.sel = t:CreateTexture(nil, "BACKGROUND")
    t.sel:SetAllPoints()
    t.sel:SetColorTexture(C.gold[1], C.gold[2], C.gold[3], 1)
    t.sel:SetAlpha(0)
    t.tex = t:CreateTexture(nil, "ARTWORK")
    t.tex:SetPoint("TOPLEFT", 2, -2)
    t.tex:SetPoint("BOTTOMRIGHT", -2, 2)
    local strip = t:CreateTexture(nil, "OVERLAY")
    strip:SetPoint("BOTTOMLEFT", 2, 2)
    strip:SetPoint("BOTTOMRIGHT", -2, 2)
    strip:SetHeight(16)
    strip:SetColorTexture(0, 0, 0, 0.65)
    t.label = t:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    t.label:SetPoint("BOTTOMLEFT", 5, 4)
    t.label:SetPoint("BOTTOMRIGHT", -5, 4)
    t.label:SetJustifyH("LEFT")
    t.label:SetWordWrap(false)
    t.hl = t:CreateTexture(nil, "HIGHLIGHT")
    t.hl:SetAllPoints()
    t.hl:SetColorTexture(1, 1, 1, 0.12)
    t:SetScript("OnClick", function(self) if self.k then Use(self.k) end end)
    t:SetScript("OnEnter", function(self)
        local e = self.k and list[self.k]
        if not e then return end
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:AddLine(e.label, 1, 0.85, 0.4, true)
        GameTooltip:AddLine(e.kind .. "  " .. tostring(e.value), 0.8, 0.8, 0.8, true)
        GameTooltip:Show()
    end)
    t:SetScript("OnLeave", function() GameTooltip:Hide() end)
    return t
end

local function Percent(v) return ("%d%%"):format(math.floor(v * 100 + 0.5)) end
local function TargetName(key)
    for _, d in ipairs(TARGETS) do if d[1] == key then return d[2] end end
    return key
end
local function ModeName(key)
    for _, d in ipairs(MODES) do if d[2] == key then return d[1] end end
    return key
end
local KIND_NAMES = { all = "All", file = "Frames", atlas = "Atlas" }

-- the menus of the header, and what they show now
local function Refresh()
    local sk = W.SkinOf(Key())
    bar.menuWindow:SetContent("Window: " .. TargetName(target), nil, bar.rowsWindow)
    bar.menuShow:SetContent("Show: " .. KIND_NAMES[kindFilter], nil, bar.rowsShow)
    bar.menuLayout:SetContent("Layout: " .. ModeName(sk.bgMode), nil, bar.rowsLayout)
    bar.menuBg:SetContent("Background: " .. Percent(sk.bgAlpha), nil, bar.rowsBg)
    bar.menuFrame:SetContent("Frame: " .. Percent(sk.frameAlpha), nil, bar.rowsFrame)
    bar.menuLayout:SetShown(tab == "bg")
    bar.menuBg:SetShown(tab == "bg")
    for _, o in ipairs(bar.tabs) do o:SetSelected(o.tab == tab) end
    if bar.layoutMenus then bar.layoutMenus() end
    ApplyTest()
end

local function SetTab(which)
    idxOf[tab] = idx
    tab = which
    if not lists[tab] then lists[tab] = tab == "bg" and Candidates() or (tab == "all" and AllAtlasCandidates() or IconCandidates()) end
    list = lists[tab]
    kindFilter = "all"
    Filter()
    top = 0
    Refresh()
    Sync()
end

local function Build()
    local f = W.NewPlate(UIParent, C.page)
    f:SetSize(12 + COLS * (TILE_W + GAP) - GAP + 32, GRID_TOP + GRID_H + 12)
    f:SetPoint("CENTER", -330, 0)
    f:SetFrameStrata("FULLSCREEN_DIALOG")
    f:SetMovable(true)
    f:SetClampedToScreen(true)
    f:EnableMouse(true)
    f:EnableMouseWheel(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", f.StartMoving)
    f:SetScript("OnDragStop", f.StopMovingOrSizing)
    bar = f
    f.tabs = {}

    -- row 1: what is shown now, and how many pictures there are
    f.count = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    f.count:SetPoint("TOPRIGHT", -16, -14)
    f.count:SetTextColor(unpack(C.muted))
    -- (an edit box that only shows: a click marks the whole line, Ctrl+C copies it, e.g. the name of a picture to tell somebody)
    f.text = CreateFrame("EditBox", nil, f)
    f.text:SetFontObject("GameFontHighlightSmall")
    f.text:SetPoint("TOPLEFT", 12, -14)
    f.text:SetPoint("RIGHT", f.count, "LEFT", -10, 0)
    f.text:SetHeight(14)
    f.text:SetAutoFocus(false)
    f.text:SetJustifyH("LEFT")
    local shownText = ""
    local rawSet = f.text.SetText
    function f.text:SetText(t) shownText = t or ""; rawSet(self, shownText); self:SetCursorPosition(0) end
    f.text:SetScript("OnTextChanged", function(self, user) if user and self:GetText() ~= shownText then rawSet(self, shownText) end end)
    f.text:SetScript("OnEditFocusGained", function(self) self:HighlightText() end)
    f.text:SetScript("OnEditFocusLost", function(self) self:HighlightText(0, 0) end)
    f.text:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    f.text:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)
    f.text:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
        GameTooltip:AddLine("Click to mark, Ctrl+C to copy", 1, 0.85, 0.4)
        GameTooltip:Show()
    end)
    f.text:SetScript("OnLeave", function() GameTooltip:Hide() end)

    -- row 2: step, the two kinds of picture, the search, and the window buttons
    local x = 12
    local function Btn(label, w, fn, anchorRight)
        local btn = W.NewButton(f, label, w, 24)
        if anchorRight then
            btn:SetPoint("TOPRIGHT", anchorRight, -36)
        else
            btn:SetPoint("TOPLEFT", x, -36)
            x = x + w + 6
        end
        btn:SetScript("OnClick", fn)
        return btn
    end
    Btn("<", 30, function() Step(-1) end)
    Btn(">", 30, function() Step(1) end)
    for _, def in ipairs({ { "Backgrounds", "bg", 100 }, { "Icons", "icon", 60 }, { "All atlases", "all", 96 } }) do
        local btn = Btn(def[1], def[3], function() SetTab(def[2]) end)
        btn.tab = def[2]
        f.tabs[#f.tabs + 1] = btn
    end
    local right = -12
    for _, def in ipairs({ { "Close", 54, function() f:Hide(); test:Hide() end },
        { "Info", 44, function() f.info() end },
        { "Test", 44, function() if test:IsShown() then test:Hide() else test:Show() end end } }) do
        local btn = Btn(def[1], def[2], def[3], right)
        right = right - def[2] - 6
    end
    local box = W.NewPlate(f, C.inset)
    box:SetPoint("TOPLEFT", x + 4, -36)
    box:SetPoint("BOTTOMRIGHT", f, "TOPRIGHT", right - 4, -60)
    local edit = CreateFrame("EditBox", nil, box)
    edit:SetPoint("TOPLEFT", 8, -4)
    edit:SetPoint("BOTTOMRIGHT", -8, 4)
    edit:SetAutoFocus(false)
    edit:SetFontObject("GameFontHighlight")
    local hint = box:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    hint:SetPoint("LEFT", 10, 0)
    hint:SetTextColor(unpack(C.muted))
    hint:SetText("Search (all words must match)")
    edit:SetScript("OnTextChanged", function(self)
        query = self:GetText() or ""
        hint:SetShown(query == "")
        Filter(); top = 0; Render()
    end)
    edit:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    edit:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)

    -- row 3: menus (a click opens one)
    local dd = W.NewDropdown(f, { level = f:GetFrameLevel() + 60, width = 190, strata = "FULLSCREEN_DIALOG" })
    local mx = 12
    local function Menu(field)
        local m = W.NewMenuButton(f, dd, "", nil)
        m.clickOnly = true
        m:SetPoint("TOPLEFT", mx, -68)
        f[field] = m
        return m
    end
    local function Radio(label, on, fn) return { kind = "radio", state = on and "all" or "none", label = label, onClick = fn, close = true } end
    local menus = { "menuWindow", "menuShow", "menuLayout", "menuBg", "menuFrame" }
    for _, field in ipairs(menus) do Menu(field) end
    function f.rowsWindow()
        local out = {}
        for _, d in ipairs(TARGETS) do
            out[#out + 1] = Radio(d[2], target == d[1], function() target = d[1]; Refresh(); ApplyStyles(); Sync() end)
        end
        out[#out + 1] = { kind = "separator" }
        out[#out + 1] = { kind = "action", label = "Reset this window", close = true, onClick = function()
            ns.db.settings.skins = ns.db.settings.skins or {}
            ns.db.settings.skins[target] = nil
            Refresh(); ApplyStyles(); Sync()
        end }
        return out
    end
    function f.rowsShow()
        local out = {}
        for _, key in ipairs({ "all", "file", "atlas" }) do
            out[#out + 1] = Radio(KIND_NAMES[key], kindFilter == key, function() kindFilter = key; Filter(); top = 0; Render(); Refresh() end)
        end
        return out
    end
    function f.rowsLayout()
        local out, now = {}, W.SkinOf(Key()).bgMode
        for _, d in ipairs(MODES) do
            out[#out + 1] = Radio(d[1], now == d[2], function() Layer().bgMode = d[2]; Refresh(); ApplyStyles() end)
        end
        return out
    end
    local function Alphas(field)
        return function()
            local out, now = {}, W.SkinOf(Key())[field]
            for _, d in ipairs(ALPHAS) do
                out[#out + 1] = Radio(d[1], now == d[2], function() Layer()[field] = d[2]; Refresh(); ApplyStyles() end)
            end
            return out
        end
    end
    f.rowsBg, f.rowsFrame = Alphas("bgAlpha"), Alphas("frameAlpha")
    -- (the buttons are laid one after the other, each as wide as its text: put them in a row once they have their text)
    function f.layoutMenus()
        local lx = 12
        for _, field in ipairs(menus) do
            local m = f[field]
            m:ClearAllPoints()
            if m:IsShown() then
                m:SetPoint("TOPLEFT", lx, -68)
                lx = lx + m:GetWidth() + 6
            end
        end
    end

    function f.info()
        local e = list and list[idx]
        local blizz = test.blizzFrame
        local out = {
            "selected: " .. (e and (e.kind .. " " .. tostring(e.value) .. "  " .. e.label) or "none") .. "  (tab " .. tab .. ", window " .. target .. ")",
            "layout: " .. tostring(W.SkinOf(Key()).bgMode),
            ("test window: %dx%d   frame: %s"):format(test:GetWidth(), test:GetHeight(), blizz and ("%dx%d"):format(blizz:GetWidth(), blizz:GetHeight()) or "none"),
            "", "--- the picture of the background:", W.Dump(blizz and blizz.talentBg),
            "", "--- the frame:", W.Dump(blizz),
        }
        W.Console(table.concat(out, "\n"), "Background info")
    end

    -- the tiles, and a scroll bar at the side that can be dragged (or clicked)
    for n = 1, COLS * VISIBLE do tiles[n] = Tile(n, f) end
    track = CreateFrame("Frame", nil, f)
    track:SetSize(10, GRID_H)
    track:SetPoint("TOPRIGHT", -8, -GRID_TOP)
    track:EnableMouse(true)
    local trackBg = track:CreateTexture(nil, "BACKGROUND")
    trackBg:SetAllPoints()
    trackBg:SetColorTexture(1, 1, 1, 0.06)
    thumb = CreateFrame("Button", nil, track)
    thumb:SetWidth(10)
    local thumbTex = thumb:CreateTexture(nil, "OVERLAY")
    thumbTex:SetAllPoints()
    thumbTex:SetColorTexture(C.gold[1], C.gold[2], C.gold[3], 0.75)
    local grab -- how far under the thumb's top the mouse was taken hold
    local function CursorY()
        local _, cy = GetCursorPosition()
        return cy / track:GetEffectiveScale()
    end
    local function Drag()
        local rows = math.ceil(#filtered / COLS)
        local maxTop = math.max(0, rows - VISIBLE)
        local frac = (track:GetTop() - CursorY() - grab) / math.max(1, GRID_H - thumb:GetHeight())
        top = math.floor(math.max(0, math.min(1, frac)) * maxTop + 0.5)
        Render()
    end
    thumb:SetScript("OnMouseDown", function(self) grab = self:GetTop() - CursorY() end)
    thumb:SetScript("OnMouseUp", function() grab = nil end)
    track:SetScript("OnMouseDown", function() grab = thumb:GetHeight() / 2; Drag() end)
    track:SetScript("OnMouseUp", function() grab = nil end)
    f:SetScript("OnUpdate", function()
        if not grab then return end
        if IsMouseButtonDown("LeftButton") then Drag() else grab = nil end
    end)
    f:SetScript("OnMouseWheel", function(_, delta)
        top = top - delta * 2
        Render()
    end)
    return f
end

SLASH_FOREVERCOMPANIONBG1 = "/fcbg"
SlashCmdList.FOREVERCOMPANIONBG = function(msg)
    if not bar then Build(); test = BuildTest(); bar:Hide() end -- (a new frame is shown: it must not count as open, or the first call would close it again)
    if bar:IsShown() and msg == "" then bar:Hide() test:Hide() return end
    if not list then
        lists.bg = Candidates()
        list = lists.bg
        Filter()
    end
    bar:Show()
    test:Show()
    Refresh()
    bar.layoutMenus()
    if tonumber(msg) then Use(tonumber(msg)) else Sync() end
end
