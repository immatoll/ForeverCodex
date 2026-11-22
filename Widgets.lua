local ADDON, ns = ...
local L = ns.L

-- Shared look and building blocks: palette, easing, gilded plates, buttons,
-- item icons, toggles.

local W = {}
ns.W = W

local C = {
    plate   = { 0.090, 0.072, 0.058, 1 },
    plateHi = { 0.150, 0.118, 0.080, 1 },
    inset   = { 0.045, 0.038, 0.032, 1 },
    page    = { 0.072, 0.059, 0.048, 1 },
    gold    = { 0.93, 0.74, 0.30 },
    goldDim = { 0.50, 0.40, 0.22 },
    jade    = { 0.40, 0.86, 0.66 },
    text    = { 0.95, 0.90, 0.78 },
    muted   = { 0.58, 0.54, 0.47 },
    red     = { 0.92, 0.35, 0.30 },
}
W.C = C

-- The backgrounds of plates and buttons can be a little see-through (the setting "panelAlpha", 0.5 to 1), so that the background of the
-- window shows through them. Each plate keeps its own colour here; W.SetPanelAlpha puts them all in the new strength.
local panels = setmetatable({}, { __mode = "k" })
W.panelAlpha = 1
local function PanelColor(f, col)
    panels[f] = col
    f:SetBackdropColor(col[1], col[2], col[3], (col[4] or 1) * W.panelAlpha)
end
function W.SetPanelAlpha(a)
    W.panelAlpha = math.max(0.4, math.min(1, tonumber(a) or 1))
    for f, col in pairs(panels) do f:SetBackdropColor(col[1], col[2], col[3], (col[4] or 1) * W.panelAlpha) end
end
local panelLoader = CreateFrame("Frame")
panelLoader:RegisterEvent("PLAYER_LOGIN")
panelLoader:SetScript("OnEvent", function()
    W.SetPanelAlpha(ns.db and ns.db.settings and ns.db.settings.panelAlpha or 1)
end)

W.QUALITY_COLOR = {
    [0] = { 0.30, 0.28, 0.25 }, [1] = { 0.30, 0.28, 0.25 }, [2] = { 0.12, 0.8, 0.1 },
    [3] = { 0.0, 0.44, 0.87 }, [4] = { 0.64, 0.21, 0.93 }, [5] = { 1, 0.5, 0 },
}
local QUALITY_COLOR = W.QUALITY_COLOR

W.ICON = {
    journal = "Interface\\Icons\\INV_Misc_Book_09",
    settings = "Interface\\Icons\\Trade_Engineering",
    account = "Interface\\Icons\\INV_Misc_GroupLooking",
    session = "Interface\\Icons\\INV_Misc_PocketWatch_01",
    pause   = "Interface\\TimeManager\\PauseButton",
    play    = "Interface\\ChatFrame\\ChatFrameExpandArrow",
    clear   = "Interface\\Buttons\\UI-GroupLoot-Pass-Up",
    loot    = "Interface\\Icons\\INV_Misc_Bag_10",
    coin    = "Interface\\Icons\\INV_Misc_Coin_01",
    skull   = "Interface\\Icons\\INV_Misc_Bone_HumanSkull_01",
    sword   = "Interface\\Icons\\INV_Sword_04",
    recent  = "Interface\\Icons\\INV_Misc_PocketWatch_01",
    rate    = "Interface\\Icons\\Spell_Nature_TimeStop",
    search  = "Interface\\Icons\\INV_Misc_Spyglass_02",
    stats   = "Interface\\Icons\\INV_Misc_Note_01",
    map     = "Interface\\Icons\\INV_Scroll_03",
}

W.GLOW_TEX = "Interface\\Buttons\\UI-ActionButton-Border"
W.HILITE_TEX = "Interface\\Buttons\\UI-Listbox-Highlight2"

W.TEMPLATE = BackdropTemplateMixin and "BackdropTemplate" or nil
W.PLATE_BACKDROP = {
    bgFile = "Interface\\Buttons\\WHITE8X8",
    edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
    edgeSize = 12,
    insets = { left = 3, right = 3, top = 3, bottom = 3 },
}

function W.Hex(c)
    return string.format("|cff%02x%02x%02x", math.floor(c[1] * 255), math.floor(c[2] * 255), math.floor(c[3] * 255))
end
local function Lerp(a, b, t) return a + (b - a) * t end
function W.LerpColor(a, b, t) return Lerp(a[1], b[1], t), Lerp(a[2], b[2], t), Lerp(a[3], b[3], t) end
local LerpColor = W.LerpColor

function W.Duration(sec)
    sec = math.floor(sec)
    local h, m, s = math.floor(sec / 3600), math.floor(sec / 60) % 60, sec % 60
    if h > 0 then return string.format("%d:%02d:%02d", h, m, s) end
    return string.format("%d:%02d", m, s)
end

-- Easing ----------------------------------------------------------------
-- Ease(obj, key, target, rate, apply [, startAt]): exponential approach of a
-- value towards target, stepped by the main frame's OnUpdate (W.Step).

local active = {}

function W.Ease(obj, key, target, rate, apply, startAt)
    obj._ease = obj._ease or {}
    local e = obj._ease[key]
    if not e then
        e = { obj = obj, cur = startAt or target }
        obj._ease[key] = e
    elseif startAt then
        e.cur = startAt
    end
    e.target, e.rate, e.apply = target, rate or 12, apply
    active[e] = true
    return e
end

function W.CancelEase(obj, key)
    local e = obj._ease and obj._ease[key]
    if e then active[e] = nil end
end

function W.CurrentEase(obj, key)
    local e = obj._ease and obj._ease[key]
    return e and e.cur or 0
end

local lastStep
function W.Step(dt)
    -- several frames call this per tick (journal, session overlay): step once
    local now = GetTime()
    if now == lastStep then return end
    lastStep = now
    for e in pairs(active) do
        local d = e.target - e.cur
        if math.abs(d) < 0.003 then
            e.cur = e.target
            active[e] = nil
        else
            e.cur = e.cur + d * math.min(1, dt * e.rate)
        end
        e.apply(e.obj, e.cur)
    end
end
-- A frame of its own steps the easing, too, so that windows that do not step it themselves (the debug windows, the item window) have
-- buttons that follow the mouse as well (W.Step steps once per tick, whoever calls it).
local easeDriver = CreateFrame("Frame")
easeDriver:SetScript("OnUpdate", function(_, dt) W.Step(dt) end)
local Ease = W.Ease

-- Plates and buttons ------------------------------------------------------

-- The game's own click sound for buttons (switched off by the setting "Click sounds").
function W.Click()
    if ns.db and ns.db.settings and ns.db.settings.clickSound == false then return end
    local id = SOUNDKIT and SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON
    pcall(PlaySound, id or "igMainMenuOptionCheckBoxOn")
end

-- The sound of a tab (the game's own tab click)
function W.TabClick()
    if ns.db and ns.db.settings and ns.db.settings.clickSound == false then return end
    local id = SOUNDKIT and SOUNDKIT.IG_CHARACTER_INFO_TAB
    pcall(PlaySound, id or "igCharacterInfoTab")
end

-- A button that clicks when it is clicked, whatever OnClick it gets later (HookScript is not relied upon:
-- the handler is wrapped when it is set).
local function ClickSound(b)
    local set = b.SetScript
    b.SetScript = function(self, name, fn)
        if name == "OnClick" and fn then
            return set(self, name, function(...)
                W.Click()
                return fn(...)
            end)
        end
        return set(self, name, fn)
    end
end

function W.NewPlate(parent, bg)
    local f = CreateFrame("Frame", nil, parent, W.TEMPLATE)
    f:SetBackdrop(W.PLATE_BACKDROP)
    PanelColor(f, bg or C.plate)
    f:SetBackdropBorderColor(C.goldDim[1], C.goldDim[2], C.goldDim[3], 1)
    return f
end

-- The window style "blizzard": the frame of the game's own windows (as the bags have it: bronze round icon on the corner, title bar
-- with the game's title and close button), laid behind a window's contents. It is made from one of the game's frame templates the
-- first time it is wanted; if the client has none of them the window keeps the plain style. Returns true when the frame is shown
-- (the window then draws no frame of its own). The frame reaches out over the window's edge (a title bar above it, the border
-- round it), so that the contents keep their room. icon: the round icon (none: the window has none); title: the text of the bar.
-- A background picture (spec: { atlas = name } or { file = id }) laid into an area in one of the modes: "stretch" (fills the area, as it
-- is), "zoom" (fills it, keeps the proportions, crops), "fit" (the whole picture, keeps the proportions, centred), "center" (its own
-- size, centred, cropped by the area) and "tile128", "tile256", "tile512" (repeated, files only). The proportions of a picture are known
-- for atlases only; a file is taken as square.
function W.LayoutBg(t, area, spec, mode)
    t.spec, t.mode, t.area = spec, mode, area
    local w, h = area:GetWidth() or 0, area:GetHeight() or 0
    local l, r, tp, bt, tw, th = 0, 1, 0, 1, 256, 256
    local tile = tonumber((mode or ""):match("^tile(%d+)$"))
    if spec.atlas then
        local info = C_Texture and C_Texture.GetAtlasInfo and C_Texture.GetAtlasInfo(spec.atlas)
        t:SetAtlas(spec.atlas, false)
        if info then tw, th = info.width or 256, info.height or 256 end
        -- the part of the file the atlas is, as the texture itself has it when the atlas is first set (the same as where the atlas is shown
        -- as it is). Kept: the texture's own coordinates are ours after the first time, and would be taken for the atlas's.
        if t.baseAtlas ~= spec.atlas then
            local ulx, uly, llx, lly, urx = t:GetTexCoord()
            if ulx and uly and lly and urx then t.base = { ulx, urx, uly, lly } else t.base = nil end
            t.baseAtlas = spec.atlas
        end
        if t.base then
            l, r, tp, bt = t.base[1], t.base[2], t.base[3], t.base[4]
        elseif info then
            l, r, tp, bt = info.leftTexCoord or 0, info.rightTexCoord or 1, info.topTexCoord or 0, info.bottomTexCoord or 1
        end
        tile = nil
    elseif spec.file then
        t.baseAtlas = nil
        if tile then t:SetTexture(spec.file, "REPEAT", "REPEAT") else t:SetTexture(spec.file, "CLAMP", "CLAMP") end
    else
        return
    end
    local function Co(u0, u1, v0, v1)
        t:SetTexCoord(l + (r - l) * u0, l + (r - l) * u1, tp + (bt - tp) * v0, tp + (bt - tp) * v1)
    end
    t:ClearAllPoints()
    if w < 1 or h < 1 or mode == "stretch" or (not tile and mode ~= "zoom" and mode ~= "fit" and mode ~= "center") then
        t:SetAllPoints(area)
        Co(0, 1, 0, 1)
        return
    end
    local a, A = tw / th, w / h
    if tile then
        t:SetAllPoints(area)
        t:SetTexCoord(0, w / tile, 0, h / tile)
    elseif mode == "zoom" then
        t:SetAllPoints(area)
        if A > a then
            local f = a / A
            Co(0, 1, (1 - f) / 2, (1 + f) / 2)
        else
            local f = A / a
            Co((1 - f) / 2, (1 + f) / 2, 0, 1)
        end
    elseif mode == "fit" then
        t:SetPoint("CENTER", area, "CENTER")
        if A > a then t:SetSize(h * a, h) else t:SetSize(w, w / a) end
        Co(0, 1, 0, 1)
    else -- center
        local sw, sh = math.min(tw, w), math.min(th, h)
        t:SetPoint("CENTER", area, "CENTER")
        t:SetSize(sw, sh)
        Co(0.5 - sw / tw / 2, 0.5 + sw / tw / 2, 0.5 - sh / th / 2, 0.5 + sh / th / 2)
    end
end

local BLIZZ_HIDE = { "Inset", "ButtonBar", "TopTileStreaks", "BtnCornerLeft", "BtnCornerRight", "BtnBottomBorder" }
-- What a window in the Blizzard style looks like: the settings of the window style as a base, then what is set for "all" windows, then what
-- is set for this one (ns.db.settings.skins[key], key: hud, account, map, settings, journal). Each layer can hold a background (bgTex:
-- { atlas = name } or { file = id }), how it lies (bgMode), a round icon (icon: { atlas = name } or a file), and how see-through the
-- background (bgAlpha) and the frame (frameAlpha) are, 0.3 to 1.
function W.SkinOf(key)
    local st = ns.db and ns.db.settings or {}
    local sk = st.skins or {}
    local base = ns.Theme and ns.Theme.skins or {}
    local design = ns.Theme and ns.Theme.design or {}
    local r = { mode = st.blizzBg or design.blizzBg or "standard", spec = st.blizzBgTex or design.blizzBgTex,
        bgMode = st.blizzBgMode or design.blizzBgMode or "stretch", bgAlpha = 1, frameAlpha = 1 }
    for _, layer in ipairs({ base.all or {}, key and base[key] or {}, sk.all or {}, key and sk[key] or {} }) do
        if layer.bgTex then r.spec, r.mode = layer.bgTex, "custom" end
        if layer.bgMode then r.bgMode = layer.bgMode end
        if layer.icon then r.icon = layer.icon end
        if layer.bgAlpha then r.bgAlpha = layer.bgAlpha end
        if layer.frameAlpha then r.frameAlpha = layer.frameAlpha end
    end
    return r
end

function W.BlizzSkin(f, on, icon, titleText, key)
    if key then f.skinKey = key end
    local b = f.blizzFrame
    if on and b == nil then
        for _, tpl in ipairs({ "PortraitFrameTemplate", "ButtonFrameTemplate", "BasicFrameTemplateWithInset" }) do
            local ok, fr = pcall(CreateFrame, "Frame", nil, f, tpl)
            if ok and fr then b = fr; break end
        end
        if b then
            pcall(function()
                b:SetPoint("TOPLEFT", f, "TOPLEFT", -6, 54)
                b:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", 6, -6)
                -- the frame catches the mouse (and the wheel) over all of its area, the border and the title bar too: nothing goes
                -- through it to the game world (a drag would turn the camera, the wheel zoom it)
                b:EnableMouse(true)
                b:EnableMouseWheel(true)
                b:SetScript("OnMouseWheel", function() end)
                -- the template's parts were made above the window's level: lower the whole tree so that none of it reaches above the
                -- window itself (its buttons and contents are all above that). The order of its parts stays (they are numbered one
                -- after the other, so that none of them falls together with another at the bottom), and the frame's border lies over
                -- the round icon, as the ring lies over the picture.
                local frames, was, levels = {}, {}, {}
                local function Walk(fr)
                    frames[#frames + 1] = fr
                    was[fr] = fr:GetFrameLevel()
                    levels[was[fr]] = true
                    for _, ch in ipairs({ fr:GetChildren() }) do Walk(ch) end
                end
                Walk(b)
                local sorted, rank = {}, {}
                for l in pairs(levels) do sorted[#sorted + 1] = l end
                table.sort(sorted)
                for k, l in ipairs(sorted) do rank[l] = k end
                -- (the top one of them is on the window's own level, below what is made after it: the title bar's drag area too)
                for _, fr in ipairs(frames) do fr:SetFrameLevel(math.max(0, f:GetFrameLevel() - (#sorted - rank[was[fr]]))) end
                local pc, nine = b.PortraitContainer, b.NineSlice
                if pc and nine and nine:GetFrameLevel() <= pc:GetFrameLevel() then
                    pc:SetFrameLevel(math.max(0, nine:GetFrameLevel() - 1))
                    if nine:GetFrameLevel() <= pc:GetFrameLevel() then nine:SetFrameLevel(pc:GetFrameLevel() + 1) end
                end
            end)
            -- the frame of the bags: the same border (with the small ring), if the client has them
            pcall(function()
                local bag = _G.ContainerFrameCombinedBags
                local ns9 = bag and bag.NineSlice
                if ns9 and ns9.layoutType and b.NineSlice and _G.NineSliceUtil and NineSliceUtil.ApplyLayoutByName then
                    NineSliceUtil.ApplyLayoutByName(b.NineSlice, ns9.layoutType, ns9.layoutTextureKit)
                end
            end)
            if not icon and _G.ButtonFrameTemplate_HidePortrait then pcall(_G.ButtonFrameTemplate_HidePortrait, b) end
            -- the round icon of the bags: its place and size, taken from the bags' own frame
            pcall(function()
                local bag, mine = _G.ContainerFrameCombinedBags, b.PortraitContainer
                local theirs = bag and bag.PortraitContainer
                if mine and theirs then
                    mine:SetSize(theirs:GetWidth(), theirs:GetHeight())
                    local point, rel, relPoint, x, y = theirs:GetPoint(1)
                    if point and rel == bag then
                        mine:ClearAllPoints()
                        mine:SetPoint(point, b, relPoint or point, x, y)
                    end
                end
            end)
            -- The lower left corner of the frame is as tall as the upper left one with the ring, so that in a low window (folded up) the two lie
            -- over each other, and the corner would be over the round icon. It becomes a part of the frame itself, which is below its parts (the
            -- icon and the ring), as the icon is over it and the ring over the icon.
            pcall(function()
                local corner = b.NineSlice and b.NineSlice.BottomLeftCorner
                if corner and corner.SetParent then corner:SetParent(b) end
            end)
            if b.CloseButton then b.CloseButton:Hide() end
            if _G.ButtonFrameTemplate_HideButtonBar then pcall(_G.ButtonFrameTemplate_HideButtonBar, b) end
            for _, k in ipairs(BLIZZ_HIDE) do
                local part = b[k]
                if type(part) == "table" and part.Hide then part:Hide() end
            end
        end
        f.blizzFrame = b or false
    end
    b = f.blizzFrame
    if b then b:SetShown(on) end
    on = on and b and true or false
    if not on then
        if f.blizzDrag then f.blizzDrag:Hide() end
        if f.blizzTitleFrame then f.blizzTitleFrame:Hide() end
        if f.blizzPortrait then f.blizzPortrait:Hide() end
        if f.blizzClose then f.blizzClose:Hide() end
        if f.blizzMM then f.blizzMM:Hide() end
        for _, btn in ipairs(f.skinRowAll or {}) do btn:Show() end
        if f.opacityBtn then f.opacityBtn:Show() end
        if f.blizzPortraitBtn then f.blizzPortraitBtn:Hide() end
        if f.skinMinimize and f.skinMinimize.button then f.skinMinimize.button:Show() end
        if f.closeBtn and f.closeWidth then f.closeBtn:SetWidth(f.closeWidth) end
        f:RegisterForDrag("LeftButton")
        -- back to our own button for closing, where it was
        local close = f.closeBtn
        if close and f.closeHome then
            close:ClearAllPoints()
            close:SetPoint(unpack(f.closeHome))
            close:Show()
        end
        return false
    end

    -- the background: as it is, darker, or the one of the talent window (a setting)
    local bg = b.Bg or b.Background
    local sk = W.SkinOf(f.skinKey)
    local mode = sk.mode
    if icon and sk.icon then icon = sk.icon end
    if bg and bg.SetVertexColor then
        local v = mode == "black" and 0.28 or mode == "dark" and 0.5 or 1
        bg:SetVertexColor(v, v, v, 1)
    end
    if (mode == "talents" or mode == "custom") and not b.talentBg then
        local t = b:CreateTexture(nil, "BACKGROUND", nil, 1)
        b.talentBg = t
        b:HookScript("OnSizeChanged", function() -- (laid out again for a window that changes its size)
            if t.spec and t:IsShown() then W.LayoutBg(t, t.area, t.spec, t.mode) end
        end)
    end
    if b.talentBg then
        local t = b.talentBg
        t:SetShown(mode == "talents" or mode == "custom")
        if mode == "custom" then
            W.LayoutBg(t, bg or b, sk.spec or {}, sk.bgMode)
        elseif mode == "talents" then
            W.LayoutBg(t, bg or b, { file = 374155 }, "stretch") -- the background of the game's talent window (PlayerSpellsFrameBg)
        end
    end
    if bg and bg.SetAlpha then bg:SetAlpha((mode == "talents" or mode == "custom") and 0 or sk.bgAlpha) end
    if b.talentBg then b.talentBg:SetAlpha(sk.bgAlpha) end
    if b.NineSlice then b.NineSlice:SetAlpha(sk.frameAlpha) end

    -- the round icon: the template's own (in the ring of its frame, laid as the bags lay theirs); a picture of our own when it has none
    if icon and b.PortraitContainer and b.PortraitContainer.portrait then
        b.PortraitContainer:Show()
        if type(icon) == "table" then
            b.PortraitContainer.portrait:SetAtlas(icon.atlas, false)
        elseif b.SetPortraitToAsset then
            pcall(b.SetPortraitToAsset, b, icon)
        else
            b.PortraitContainer.portrait:SetTexture(icon)
        end
        if f.blizzPortrait then f.blizzPortrait:Hide() end
    elseif icon then
        if not f.blizzPortrait then
            local p = CreateFrame("Frame", nil, f)
            p:SetFrameLevel(f:GetFrameLevel() + 2)
            p:EnableMouse(true) -- (the ring too keeps the mouse from the world)
            p.pic = p:CreateTexture(nil, "ARTWORK")
            p.pic:SetAllPoints()
            p.pic:SetTexCoord(0.07, 0.93, 0.07, 0.93)
            if p.CreateMaskTexture then
                local mask = p:CreateMaskTexture()
                mask:SetTexture("Interface\\CharacterFrame\\TempPortraitAlphaMask", "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
                mask:SetAllPoints(p.pic)
                p.pic:AddMaskTexture(mask)
            end
            p:SetSize(40, 40)
            p:SetPoint("TOPLEFT", b, "TOPLEFT", 12, -8)
            f.blizzPortrait = p
        end
        if type(icon) == "table" then f.blizzPortrait.pic:SetAtlas(icon.atlas, false) else f.blizzPortrait.pic:SetTexture(icon) end
        f.blizzPortrait:Show()
    elseif f.blizzPortrait then
        f.blizzPortrait:Hide()
    end
    -- the title: our own, in the face of the game's titles, above the frame (the template's own title is hidden)
    if b.TitleContainer then b.TitleContainer:Hide() end
    if b.TitleText and b.TitleText.Hide then b.TitleText:Hide() end
    if not f.blizzTitle then
        local tf = CreateFrame("Frame", nil, f)
        tf:SetFrameLevel(f:GetFrameLevel() + 3)
        tf:EnableMouse(false)
        tf:SetAllPoints(f)
        local fs = tf:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        fs:SetPoint("TOP", b, "TOP", 0, -8)
        f.blizzTitle = fs
        f.blizzTitleFrame = tf
    end
    f.blizzTitleFrame:Show()
    f.blizzTitle:SetText(titleText or "")

    -- the game's own close button: it closes the window the way our button does (our button stays, out of sight, where the buttons
    -- next to it are laid: left of the game's button)
    local close = f.closeBtn
    if close then
        local x = f.blizzClose
        if not x then
            local ok, made = pcall(CreateFrame, "Button", nil, f, "UIPanelCloseButton")
            if ok and made then
                made:SetSize(28, 28)
                made:SetPoint("TOPRIGHT", b, "TOPRIGHT", 1, 3)
                f.blizzClose = made
                x = made
            end
        end
        if x then
            x:Show()
            x:SetScript("OnHide", function(self) self:SetButtonState("NORMAL") end) -- (not left pressed when the click closed the window)
            x:SetScript("OnClick", function()
                local fn = close:GetScript("OnClick")
                if fn then fn(close) end
            end)
            if not f.closeHome then f.closeHome = { close:GetPoint() } end
            -- the minimize / maximize button of the game, left of it, for a window that can fold up (f.skinMinimize = { get, set, button })
            local mini, anchor = f.skinMinimize, x
            if mini then
                if not f.blizzMM then
                    local ok, mm = pcall(CreateFrame, "Frame", nil, f, "MaximizeMinimizeButtonFrameTemplate")
                    if ok and mm and mm.SetOnMinimizedCallback then
                        mm:SetPoint("RIGHT", x, "LEFT", 4, 0)
                        mm:SetOnMinimizedCallback(function() if not mm.syncing then mini.set(true) end end)
                        mm:SetOnMaximizedCallback(function() if not mm.syncing then mini.set(false) end end)
                        f.blizzMM = mm
                    elseif ok and mm then
                        mm:Hide()
                    end
                end
                if f.blizzMM then
                    f.blizzMM:Show()
                    W.SkinSyncMinimized(f, mini.get())
                    if mini.button then mini.button:Hide() end
                    anchor = f.blizzMM
                end
            end
            if not f.closeWidth then f.closeWidth = close:GetWidth() end
            close:SetWidth(1) -- (a spacer only: what is laid next to it ends up beside the game's buttons)
            close:ClearAllPoints()
            close:SetPoint("RIGHT", anchor, "LEFT", -2, 0)
            close:Hide()
        end
    end

    -- The buttons for the other windows are not in the window: a click on the round icon opens a menu of them (f.skinRowAll: the buttons
    -- that are put away). The button for the window's opacity is not there either.
    for _, btn in ipairs(f.skinRowAll or {}) do btn:Hide() end
    if f.opacityBtn then f.opacityBtn:Hide() end
    if icon and f.skinRowAll then
        if not f.blizzPortraitBtn then
            local pb = CreateFrame("Button", nil, f)
            pb:SetFrameLevel(f:GetFrameLevel() + 3)
            local region = b.PortraitContainer and b.PortraitContainer.portrait
            if region then
                pb:SetAllPoints(region)
            else
                pb:SetPoint("TOPLEFT", b, "TOPLEFT", 6, -4)
                pb:SetSize(50, 50)
            end
            local menu = W.NewDropdown(f, { level = f:GetFrameLevel() + 60, width = 240, strata = "FULLSCREEN_DIALOG", rowH = 32, iconSize = 24,
                font = "GameFontNormal", headFont = "GameFontNormal", padX = 10, padY = 10, offX = 18, offY = -2 })
            -- the menu comes with the mouse over the icon, and goes when it has left the icon and the menu
            pb:SetScript("OnEnter", function(self) menu:Open(self, function() return W.WindowMenuRows(f) end) end)
            f.blizzPortraitBtn = pb
        end
        f.blizzPortraitBtn:Show()
    elseif f.blizzPortraitBtn then
        f.blizzPortraitBtn:Hide()
    end

    -- the window is moved by its title bar only (as the game's windows are), not by its body
    if not f.blizzDrag then
        local d = CreateFrame("Frame", nil, f)
        d:SetFrameLevel(f:GetFrameLevel())
        d:SetPoint("TOPLEFT", b, "TOPLEFT", 0, 0)
        d:SetPoint("TOPRIGHT", b, "TOPRIGHT", 0, 0)
        d:SetHeight(26)
        d:EnableMouse(true)
        d:SetScript("OnMouseDown", function(_, button)
            if button ~= "LeftButton" then return end
            W.StartDrag(f, function()
                local fn = f:GetScript("OnDragStop")
                if fn then fn(f) else f:StopMovingOrSizing() end
            end)
        end)
        f.blizzDrag = d
    end
    f.blizzDrag:Show()
    f:RegisterForDrag()
    return true
end

-- Moving a window by hand: the game's own drag (RegisterForDrag) only starts once the mouse has moved a few pixels from where it was
-- pressed, which feels like a dead zone. Here the window follows the cursor from the first pixel: the press starts it (W.StartDrag from an
-- OnMouseDown), the release ends it (stop: called then; the window's own OnDragStop, which keeps the place, is a good one).
local dragDriver = CreateFrame("Frame")
dragDriver:Hide()
function W.StartDrag(f, stop)
    local scale = f:GetEffectiveScale()
    local left, top = f:GetLeft(), f:GetTop()
    if not (left and top) then return end
    local cx, cy = GetCursorPosition()
    local ox, oy = left - cx / scale, top - cy / scale
    f.fcMoving = true
    dragDriver:Show()
    dragDriver:SetScript("OnUpdate", function()
        if not IsMouseButtonDown("LeftButton") then
            dragDriver:Hide()
            dragDriver:SetScript("OnUpdate", nil)
            f.fcMoving = nil
            if stop then stop(f) end
            return
        end
        local x, y = GetCursorPosition()
        f:ClearAllPoints()
        f:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", x / scale + ox, y / scale + oy)
    end)
end

-- The rows of the menu of the windows (the round icon of a window in the Blizzard style opens it): every other window of the addon.
function W.WindowMenuRows(f)
    local L = ns.L
    local defs = {
        { "journal", L["Journal"], W.ICON.journal, function() if ns.UI then ns.UI.Toggle() end end },
        { "hud", L["Kills & Loot"], W.ICON.session, function() if ns.HUD then ns.HUD.Toggle() end end },
        { "map", L["Loot map"], W.ICON.map, function() if ns.MapMain then ns.MapMain.Toggle() end end },
        { "mini", L["Mini map"], "Interface\\Icons\\INV_Misc_Spyglass_02", function() if ns.MapWindow then ns.MapWindow.Toggle() end end },
        { "account", L["Account"], W.ICON.account, function() if ns.AccountWindow then ns.AccountWindow.Toggle() end end },
        { "ah", L["Auction house"], W.ICON.coin, function() if ns.AuctionWindow then ns.AuctionWindow.Toggle() end end },
        { "settings", L["Settings"], W.ICON.settings, function() if ns.Settings then ns.Settings.Toggle() end end },
    }
    -- the windows of the addon, then the subwindows of one (indented under it), then what is for everything (apart)
    local out = {}
    local function Add(d, indent)
        if d[1] ~= f.skinKey then
            out[#out + 1] = { kind = "action", label = d[2], icon = d[3], close = true, onClick = d[4], indent = indent }
        end
    end
    for _, d in ipairs(defs) do
        if d[1] == "mini" then Add(d, 18)
        elseif d[1] ~= "settings" then Add(d) end
    end
    out[#out + 1] = { kind = "separator" }
    for _, d in ipairs(defs) do if d[1] == "settings" then Add(d) end end
    if out[#out] and out[#out].kind == "separator" then out[#out] = nil end -- (nothing below it: the settings window is this one)
    return out
end

-- keeps the game's minimize button of a window in step with its state (when the window folds up by something other than a click on it)
function W.SkinSyncMinimized(f, minimized)
    local mm = f.blizzMM
    if not mm or not mm.Minimize then return end
    mm.syncing = true
    if minimized then pcall(mm.Minimize, mm) else pcall(mm.Maximize, mm) end
    mm.syncing = false
end

-- Name, rarity and picture of an item by its number. The names are kept in the saved variables (the list of the auction house tab fills it): the
-- game's own answer comes and goes (an item it has not got in its memory for the moment gives nothing, and the name would turn into "item:123"
-- and back), so the kept name is taken first; an item that is not kept yet is asked for and kept as soon as the game gives it.
function W.ItemData(id)
    local db = ns.db
    local cache = db and db.itemCache
    local name, quality
    local hit = cache and cache[id]
    if type(hit) == "string" and hit:sub(1, 1) ~= "x" then
        local _, q, _, nm = hit:match("^(%d+)|(%d+)|(%d+)|(.*)$")
        if nm then name, quality = nm, tonumber(q) end
    end
    local Info = GetItemInfo or (C_Item and C_Item.GetItemInfo)
    local icon
    if not name and Info then
        local n, _, q, _, lvl, _, _, _, _, ic, sell = Info(id)
        if n then
            name, quality, icon = n, q or 1, ic
            if cache and cache.lang == GetLocale() and cache.fmt == 3 then
                cache[id] = (sell or 0) .. "|" .. (q or 1) .. "|" .. (lvl or 0) .. "|" .. n
            end
        elseif C_Item and C_Item.RequestLoadItemDataByID then
            pcall(C_Item.RequestLoadItemDataByID, id)
        end
    end
    icon = icon or (C_Item and C_Item.GetItemIconByID and C_Item.GetItemIconByID(id)) or nil
    return name, quality, icon
end

function W.GlowTexture(parent)
    local g = parent:CreateTexture(nil, "OVERLAY")
    g:SetTexture(W.HILITE_TEX)
    g:SetBlendMode("ADD")
    g:SetVertexColor(C.gold[1], C.gold[2], C.gold[3])
    g:SetAlpha(0)
    return g
end

-- a selected button keeps the hovered look; leaving it eases back only as far as that
local function ApplyButtonHover(b, v)
    local k = math.max(v, b.selected and 1 or 0)
    b.glow:SetAlpha(v * 0.55 + (b.selected and 0.2 or 0))
    b:SetBackdropBorderColor(LerpColor(C.goldDim, C.gold, b.noActiveBorder and v or k)) -- (noActiveBorder: a selected one has no gilded edge)
    b.text:SetTextColor(LerpColor(b.baseColor or C.text, { 1, 0.95, 0.7 }, k))
end

function W.NewButton(parent, text, width, height, font)
    local b = CreateFrame("Button", nil, parent, W.TEMPLATE)
    b:SetSize(width, height or 24)
    b:SetBackdrop(W.PLATE_BACKDROP)
    PanelColor(b, C.plate)
    b:SetBackdropBorderColor(unpack(C.goldDim))
    b.glow = W.GlowTexture(b)
    b.glow:SetPoint("TOPLEFT", 3, -3)
    b.glow:SetPoint("BOTTOMRIGHT", -3, 3)
    b.text = b:CreateFontString(nil, "OVERLAY", font or "GameFontHighlightSmall")
    b.text:SetPoint("CENTER")
    b.text:SetText(text)
    b.text:SetTextColor(unpack(C.text))
    ClickSound(b)
    -- the look follows the state at once, and never fights the hover animation
    function b:Restyle() ApplyButtonHover(self, W.CurrentEase(self, "hv")) end
    function b:SetSelected(on)
        on = on and true or false
        if self.selected == on then return end
        self.selected = on
        self:Restyle()
    end
    b:SetScript("OnEnter", function(self) Ease(self, "hv", 1, 16, ApplyButtonHover) end)
    -- (the pressed look is also taken back when the mouse leaves or the button goes away, as a release over something else or after the
    -- window was closed by the click itself does not reach OnMouseUp)
    b:SetScript("OnLeave", function(self)
        self.text:SetPoint("CENTER", 0, 0)
        Ease(self, "hv", 0, 16, ApplyButtonHover)
    end)
    b:SetScript("OnHide", function(self) self.text:SetPoint("CENTER", 0, 0) end)
    b:SetScript("OnMouseDown", function(self) self.text:SetPoint("CENTER", 0, -1) end)
    b:SetScript("OnMouseUp", function(self) self.text:SetPoint("CENTER", 0, 0) end)
    return b
end

-- Icon button: a gilded plate with an icon and a tooltip. SetActive marks it
-- as the selected one of a group; SetTip updates the tooltip text (it can
-- describe the current state, e.g. the active sort).
local function ApplyIconButton(b, v)
    local k = math.max(v, b.active and 1 or 0)
    b.glow:SetAlpha(v * 0.55 + (b.active and 0.25 or 0))
    b:SetBackdropBorderColor(LerpColor(C.goldDim, C.gold, b.noActiveBorder and v or k))
    local base = b.iconBase or 0.6 -- (the picture at rest; a button can set a brighter one)
    b.icon:SetAlpha(base + (1 - base) * k)
end

function W.NewIconButton(parent, texture, size)
    local b = CreateFrame("Button", nil, parent, W.TEMPLATE)
    ClickSound(b)
    b:SetSize(size, size)
    b:SetBackdrop(W.PLATE_BACKDROP)
    PanelColor(b, C.plate)
    b:SetBackdropBorderColor(unpack(C.goldDim))
    b.glow = W.GlowTexture(b)
    b.glow:SetPoint("TOPLEFT", 3, -3)
    b.glow:SetPoint("BOTTOMRIGHT", -3, 3)
    local isz = math.floor(size * 0.62)
    b.icon = b:CreateTexture(nil, "ARTWORK")
    b.icon:SetSize(isz, isz)
    b.icon:SetPoint("CENTER")
    b.icon:SetTexture(texture)
    b.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
    b.active = false

    function b:SetIcon(tex) self.icon:SetTexture(tex) end
    function b:ShowTip()
        GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
        GameTooltip:ClearLines()
        GameTooltip:AddLine(self.tipTitle or "", 1, 0.85, 0.4)
        if self.tipLine then GameTooltip:AddLine(self.tipLine, 0.8, 0.8, 0.8, true) end
        GameTooltip:Show()
    end
    function b:SetTip(title, line)
        self.tipTitle, self.tipLine = title, line
        if GameTooltip:IsShown() and GameTooltip:GetOwner() == self then self:ShowTip() end
    end
    function b:SetActive(on)
        self.active = on and true or false
        ApplyIconButton(self, W.CurrentEase(self, "hv"))
    end
    b:SetScript("OnEnter", function(self)
        Ease(self, "hv", 1, 16, ApplyIconButton)
        if self.tipTitle then self:ShowTip() end
    end)
    b:SetScript("OnLeave", function(self)
        Ease(self, "hv", 0, 16, ApplyIconButton)
        GameTooltip:Hide()
    end)
    b:HookScript("OnLeave", function(self) self.icon:SetPoint("CENTER", 0, 0) end) -- (as with the text buttons: no stuck pressed look)
    b:HookScript("OnHide", function(self) self.icon:SetPoint("CENTER", 0, 0) end)
    b:SetScript("OnMouseDown", function(self) self.icon:SetPoint("CENTER", 0, -1) end)
    b:SetScript("OnMouseUp", function(self) self.icon:SetPoint("CENTER", 0, 0) end)
    ApplyIconButton(b, 0)
    return b
end

-- Is the frame under the cursor this one (or inside it)? Unlike frame:IsMouseOver() this is
-- false when another window sits on top of it, so hover effects that are polled leave it alone.
function W.TopFrameIs(frame)
    local top
    if GetMouseFoci then top = GetMouseFoci()[1]
    elseif GetMouseFocus then top = GetMouseFocus() end
    while top do
        if top == frame then return true end
        top = top.GetParent and top:GetParent() or nil
    end
    return false
end

-- The grip in a window's corner:
--   drag             resize (opts.scaleOnly: scale, for windows with a fixed layout)
--   shift + drag     resize and keep the proportions (also pressed or released while dragging)
--   ctrl + drag      scale the whole window around its top left corner
--   right-click   the window goes to the middle of the screen
--   right-click while dragging   cancel: the window goes back to how it was
--   shift + right-click   the default size (windows with a fixed layout: the default scale)
--   ctrl + right-click   the default scale
-- Holding alt while dragging moves in steps instead: 10 pixels for the size, 10 % for the scale.
-- opts: defaultSize {w, h}, minSize / maxSize {w, h}, minScale, maxScale, scaleOnly,
-- saveSize(), saveScale(), savePos().
local GRID_PX, GRID_SCALE = 10, 0.1

-- the figures next to the cursor while a window is being sized or scaled
local dragInfo
local function DragInfo(text)
    if not dragInfo then
        dragInfo = W.NewPlate(UIParent, { 0.045, 0.036, 0.03, 0.95 })
        dragInfo:SetFrameStrata("TOOLTIP")
        dragInfo:SetSize(10, 24)
        dragInfo.text = dragInfo:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        dragInfo.text:SetPoint("CENTER")
        dragInfo.text:SetTextColor(1, 0.9, 0.62)
        dragInfo:EnableMouse(false)
    end
    if not text then dragInfo:Hide() return end
    dragInfo.text:SetText(text)
    dragInfo:SetWidth(dragInfo.text:GetStringWidth() + 22)
    local x, y = GetCursorPosition()
    local k = UIParent:GetEffectiveScale()
    dragInfo:ClearAllPoints()
    dragInfo:SetPoint("BOTTOMRIGHT", UIParent, "BOTTOMLEFT", x / k - 14, y / k + 14)
    dragInfo:Show()
end

-- the tooltip of the grip: always the same table, "keys -> what happens"
local function GripTooltip(grip, scaleOnly)
    local function Keys(...)
        local t = {}
        for i = 1, select("#", ...) do t[i] = L[select(i, ...)] end
        return table.concat(t, " + ")
    end
    GameTooltip:SetOwner(grip, "ANCHOR_TOPLEFT")
    GameTooltip:AddLine(scaleOnly and L["Scale the window"] or L["Resize the window"], 1, 0.85, 0.4)
    local function Row(keys, action) GameTooltip:AddDoubleLine(keys, action, 0.4, 0.86, 0.66, 0.85, 0.85, 0.85) end
    if scaleOnly then
        Row(Keys("Drag"), L["Scale"])
        Row(Keys("Alt", "Drag"), L["In steps of 10 %"])
    else
        Row(Keys("Drag"), L["Resize"])
        Row(Keys("Shift", "Drag"), L["Keep the proportions"])
        Row(Keys("Ctrl", "Drag"), L["Scale"])
        Row(Keys("Alt", "Drag"), L["In steps (10 pixels, 10 %)"])
    end
    Row(Keys("Right-click", "Drag"), L["Cancel"])
    Row(Keys("Right-click"), L["Center the window"])
    Row(Keys("Shift", "Right-click"), scaleOnly and L["Default scale"] or L["Default size"])
    if not scaleOnly then Row(Keys("Ctrl", "Right-click"), L["Default scale"]) end
    GameTooltip:Show()
end

function W.AttachScaleGrip(frame, grip, opts)
    local minScale, maxScale = opts.minScale or 0.6, opts.maxScale or 1.6
    local active, cancelled
    local updater = CreateFrame("Frame")

    local function Snap(v, step)
        if not IsAltKeyDown() then return v end
        return math.floor(v / step + 0.5) * step
    end
    -- anchor by the top left corner, so that a new size grows to the right and downwards
    local function AnchorTopLeft()
        local left, top = frame:GetLeft(), frame:GetTop()
        if not (left and top) then return end
        frame:ClearAllPoints()
        frame:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", left, top)
    end

    local function ClampSize(wid, hei)
        if opts.minSize then wid, hei = math.max(opts.minSize[1], wid), math.max(opts.minSize[2], hei) end
        if opts.maxSize then wid, hei = math.min(opts.maxSize[1], wid), math.min(opts.maxSize[2], hei) end
        return wid, hei
    end

    local function SetScaleKeepingCorner(scale)
        local old = frame:GetScale()
        local left, top = frame:GetLeft(), frame:GetTop()
        if not (left and top) then frame:SetScale(scale) return end
        left, top = left * old, top * old
        frame:SetScale(scale)
        frame:ClearAllPoints()
        frame:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", left / scale, top / scale)
    end

    -- One drag, whatever the keys do meanwhile: every step starts from how the window was when
    -- the mouse went down and applies the mode the keys select right now (ctrl: scale, shift:
    -- keep the proportions, none: size). So shift can be pressed or let go in mid-drag, and the
    -- window takes the values of the new mode at once. The right mouse button cancels.
    local function Restore(st)
        frame:SetScale(st.scale)
        frame:ClearAllPoints()
        frame:SetPoint(st.point[1], st.point[2], st.point[3], st.point[4], st.point[5])
        frame:SetSize(st.w, st.h)
    end

    local function Step()
        local st = active
        if not st then return end
        if IsMouseButtonDown("RightButton") then
            Restore(st)
            active, cancelled = nil, true
            updater:SetScript("OnUpdate", nil)
            DragInfo(nil)
            return
        end
        local x, y = GetCursorPosition()
        local scale, wid, hei = st.scale, st.w, st.h
        st.scaled = opts.scaleOnly or IsControlKeyDown()
        if st.scaled then
            local grown = (x - st.x) + (st.y - y) -- right and down grow it
            local k = 1 + grown / ((st.w + st.h) * st.eff)
            scale = math.max(minScale, math.min(maxScale, Snap(st.scale * k, GRID_SCALE)))
        else
            local dx, dy = (x - st.x) / st.eff, (st.y - y) / st.eff
            if IsShiftKeyDown() then
                local k = math.max((st.w + dx) / st.w, (st.h + dy) / st.h)
                local lo = opts.minSize and math.max(opts.minSize[1] / st.w, opts.minSize[2] / st.h) or 0.2
                local hi = opts.maxSize and math.min(opts.maxSize[1] / st.w, opts.maxSize[2] / st.h) or 5
                k = Snap(st.w * k, GRID_PX) / st.w
                k = math.max(lo, math.min(hi, k))
                wid, hei = st.w * k, st.h * k
            else
                wid, hei = ClampSize(Snap(st.w + dx, GRID_PX), Snap(st.h + dy, GRID_PX))
            end
        end
        frame:SetScale(scale)
        frame:ClearAllPoints()
        frame:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", st.left / scale, st.top / scale)
        frame:SetSize(wid, hei)
        local info = ("%d × %d"):format(wid + 0.5, hei + 0.5)
        if st.scaled then
            info = L["Scale"] .. (" %d %%  ·  "):format(scale * 100 + 0.5) .. info
        elseif IsShiftKeyDown() then
            info = info .. "  ·  " .. L["proportions"]
        end
        DragInfo(info)
    end

    grip:SetScript("OnMouseDown", function(_, button)
        if button == "RightButton" then
            if active then -- during a drag: back to how it was
                Restore(active)
                active, cancelled = nil, true
                updater:SetScript("OnUpdate", nil)
                DragInfo(nil)
            elseif IsControlKeyDown() then -- ctrl + right-click: the default scale
                SetScaleKeepingCorner(1)
                if opts.saveScale then opts.saveScale() end
                if opts.savePos then opts.savePos() end
            elseif IsShiftKeyDown() then -- shift + right-click: the default size (windows with a fixed layout: the default scale)
                if opts.defaultSize and not opts.scaleOnly then
                    AnchorTopLeft()
                    frame:SetSize(opts.defaultSize[1], opts.defaultSize[2])
                    if opts.saveSize then opts.saveSize() end
                else
                    SetScaleKeepingCorner(1)
                    if opts.saveScale then opts.saveScale() end
                end
                if opts.savePos then opts.savePos() end
            else -- right-click: to the middle of the screen
                frame:ClearAllPoints()
                frame:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
                if opts.savePos then opts.savePos() end
            end
            return
        end
        local x, y = GetCursorPosition()
        local left, top = frame:GetLeft(), frame:GetTop()
        local point, rel, relPoint, px, py = frame:GetPoint(1)
        if not (left and top and point) then return end
        local scale = frame:GetScale()
        cancelled = false
        active = { x = x, y = y, w = frame:GetWidth(), h = frame:GetHeight(), scale = scale,
            eff = frame:GetEffectiveScale(), left = left * scale, top = top * scale,
            point = { point, rel, relPoint, px, py } }
        updater:SetScript("OnUpdate", Step)
    end)
    grip:SetScript("OnMouseUp", function()
        if active then
            local scaled = active.scaled
            active = nil
            DragInfo(nil)
            updater:SetScript("OnUpdate", nil)
            if scaled then
                if opts.saveScale then opts.saveScale() end
            elseif opts.saveSize then
                opts.saveSize()
            end
            if opts.savePos then opts.savePos() end
        elseif cancelled then
            cancelled = false
        else
            frame:StopMovingOrSizing()
            if opts.saveSize then opts.saveSize() end
        end
    end)
    grip:SetScript("OnEnter", function(self) GripTooltip(self, opts.scaleOnly) end)
    grip:SetScript("OnLeave", function() GameTooltip:Hide() end)
end

-- The frame round a list (rows and their column heads): the same gilded edge as the plates,
-- drawn over the rows' outer pixels. tl / br are the regions it is laid round; level is the
-- frame level it takes (below a scroll thumb, above the rows).
function W.NewListBorder(parent, tl, br, level)
    local b = CreateFrame("Frame", nil, parent, W.TEMPLATE)
    b:SetBackdrop({ edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border", edgeSize = 12 })
    b:SetBackdropBorderColor(C.goldDim[1], C.goldDim[2], C.goldDim[3], 1)
    b:SetPoint("TOPLEFT", tl, "TOPLEFT", -3, 3)
    b:SetPoint("BOTTOMRIGHT", br, "BOTTOMRIGHT", 3, -3)
    b:SetFrameLevel(level)
    b:EnableMouse(false)
    return b
end

-- Window opacity: a button next to the close button steps a window through 100, 75 and 50 %.
local WINDOW_ALPHAS = { 1, 0.75, 0.5 }

-- Plates inside a window (filter, buttons, cards) have backgrounds of their own. With the
-- window made see-through they would stack on its background and look darker than the
-- rest, as if highlighted. So while a window is faded their backgrounds are thinned out.
local originalBg = setmetatable({}, { __mode = "k" })
local function FadeBackgrounds(frame, factor)
    for _, child in ipairs({ frame:GetChildren() }) do
        if child.GetBackdrop and child.GetBackdropColor and child:GetBackdrop() then
            local own = panels[child]
            local o = own and { own[1], own[2], own[3], (own[4] or 1) * W.panelAlpha } or originalBg[child]
            if not o then
                local r, g, b, a = child:GetBackdropColor()
                o = { r, g, b, a }
                originalBg[child] = o
            end
            child:SetBackdropColor(o[1], o[2], o[3], (o[4] or 1) * factor)
        end
        FadeBackgrounds(child, factor)
    end
end

-- opacity of a whole window; call again after more of its parts were built
function W.SetWindowAlpha(frame, alpha)
    frame:SetAlpha(alpha)
    FadeBackgrounds(frame, alpha < 1 and 0.2 or 1)
end

function W.FadeWindowParts(frame, alpha)
    FadeBackgrounds(frame, alpha < 1 and 0.2 or 1)
end
function W.WindowAlpha(key)
    local t = ns.db and ns.db.windowAlpha
    return t and t[key] or 1
end

function W.NewOpacityButton(parent, key, frame, size)
    local b = W.NewIconButton(parent, "Interface\\Icons\\Spell_Nature_Invisibilty", size)
    local function Tip()
        b:SetTip(L["Window opacity"], string.format("%d%%", W.WindowAlpha(key) * 100 + 0.5) .. " - " .. L["Click to change"])
    end
    b:SetScript("OnClick", function()
        local cur, idx = W.WindowAlpha(key), 1
        for i, v in ipairs(WINDOW_ALPHAS) do
            if math.abs(v - cur) < math.abs(WINDOW_ALPHAS[idx] - cur) then idx = i end
        end
        ns.db.windowAlpha = ns.db.windowAlpha or {}
        ns.db.windowAlpha[key] = WINDOW_ALPHAS[idx % #WINDOW_ALPHAS + 1]
        W.SetWindowAlpha(frame, ns.db.windowAlpha[key])
        Tip()
    end)
    Tip()
    return b
end

-- Goal bar: a bordered bar that fills towards a "chance" token (dice). The token
-- lights up when the goal is reached. Used for the kills until drop chances.
local GOAL_ICON = "Interface\\Icons\\INV_Misc_Dice_01"
local GOAL_BORDER = { bgFile = "Interface\\Buttons\\WHITE8X8", edgeFile = "Interface\\Buttons\\WHITE8X8", edgeSize = 1 }

-- last displayed fraction per key: a bar only animates by what changed (7 -> 8
-- kills), never from empty, also when its frame is reused for another creature
local goalShown = {}
-- muted fills that sit in the theme instead of glowing
local GOAL_GOLD = { 0.62, 0.49, 0.22 }
local GOAL_JADE = { 0.27, 0.58, 0.47 }

function W.NewGoalBar(parent, width)
    local g = CreateFrame("Frame", nil, parent)
    g:SetSize(width, 24)
    local barW = width - 34
    g.barW = barW

    g.track = CreateFrame("Frame", nil, g, W.TEMPLATE)
    g.track:SetSize(barW, 16)
    g.track:SetPoint("LEFT", 0, 0)
    g.track:SetBackdrop(GOAL_BORDER)
    g.track:SetBackdropColor(0.015, 0.012, 0.01, 1)
    g.track:SetBackdropBorderColor(C.goldDim[1], C.goldDim[2], C.goldDim[3], 1)

    g.fill = g.track:CreateTexture(nil, "ARTWORK")
    g.fill:SetPoint("TOPLEFT", 1, -1)
    g.fill:SetPoint("BOTTOMLEFT", 1, 1)
    g.fill:SetWidth(1)
    g.shine = g.track:CreateTexture(nil, "OVERLAY")
    g.shine:SetPoint("TOPLEFT", g.fill, "TOPLEFT")
    g.shine:SetPoint("TOPRIGHT", g.fill, "TOPRIGHT")
    g.shine:SetHeight(4)
    g.shine:SetColorTexture(1, 1, 1, 0.05)
    g.text = g.track:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    g.text:SetPoint("CENTER")
    g.text:SetShadowOffset(1, -1)

    g.edge = g:CreateTexture(nil, "ARTWORK")
    g.edge:SetSize(24, 24)
    g.edge:SetPoint("RIGHT", 0, 0)
    g.icon = g:CreateTexture(nil, "OVERLAY")
    g.icon:SetPoint("TOPLEFT", g.edge, 1, -1)
    g.icon:SetPoint("BOTTOMRIGHT", g.edge, -1, 1)
    g.icon:SetTexture(GOAL_ICON)
    g.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
    g.glow = g:CreateTexture(nil, "OVERLAY")
    g.glow:SetTexture(W.GLOW_TEX)
    g.glow:SetBlendMode("ADD")
    g.glow:SetSize(46, 46)
    g.glow:SetPoint("CENTER", g.edge, "CENTER")
    g.glow:SetVertexColor(C.jade[1], C.jade[2], C.jade[3])
    g.glow:SetAlpha(0)

    g:EnableMouse(true)
    g:SetScript("OnEnter", function(self)
        if self.goal then
            GameTooltip:SetOwner(self, "ANCHOR_TOP")
            GameTooltip:AddLine(L["Drop chances unlock at %d kills"]:format(self.goal), 1, 0.85, 0.4)
            GameTooltip:Show()
        end
    end)
    g:SetScript("OnLeave", function() GameTooltip:Hide() end)

    local function ApplyFill(bar, v)
        bar.fill:SetWidth(math.max(1, (bar.barW - 2) * v))
        bar.fill:SetAlpha(v > 0.003 and 1 or 0)
        bar.shine:SetAlpha(v > 0.003 and 1 or 0)
        if bar.key then goalShown[bar.key] = v end
    end
    local function ApplyGlow(bar, v) bar.glow:SetAlpha(v * 0.8) end

    -- key identifies what the bar shows; a new key refills from empty
    function g:Set(cur, max, key)
        self.goal = max
        local frac = max > 0 and math.min(cur / max, 1) or 0
        local ready = cur >= max
        local c = ready and GOAL_JADE or GOAL_GOLD
        self.fill:SetColorTexture(c[1], c[2], c[3], 1)
        self.text:SetText(ready and tostring(cur) or (cur .. " / " .. max))
        self.icon:SetDesaturated(not ready)
        local ec = ready and C.jade or C.goldDim
        self.edge:SetColorTexture(ec[1], ec[2], ec[3], 1)
        self.key = key
        -- first time this key is seen: show it as it is, no animation
        local start = goalShown[key]
        if start == nil then start = frac end
        Ease(self, "frac", frac, 5, ApplyFill, start)
        Ease(self, "glow", ready and 1 or 0, 4, ApplyGlow)
    end
    return g
end

-- Toggle: gilded checkbox with a category icon and a label.
local function ApplyToggleHover(b, v)
    b.glow:SetAlpha(v * 0.45)
    b:SetBackdropBorderColor(LerpColor(C.goldDim, C.gold, v))
end

function W.NewToggle(parent, label, icon, get, set, width)
    local b = CreateFrame("Button", nil, parent, W.TEMPLATE)
    ClickSound(b)
    b:SetSize(width or 220, 32)
    b:SetBackdrop(W.PLATE_BACKDROP)
    PanelColor(b, C.plate)
    b:SetBackdropBorderColor(unpack(C.goldDim))
    b.glow = W.GlowTexture(b)
    b.glow:SetPoint("TOPLEFT", 3, -3)
    b.glow:SetPoint("BOTTOMRIGHT", -3, 3)

    b.boxEdge = b:CreateTexture(nil, "ARTWORK")
    b.boxEdge:SetSize(18, 18)
    b.boxEdge:SetPoint("LEFT", 9, 0)
    b.boxEdge:SetColorTexture(unpack(C.goldDim))
    b.box = b:CreateTexture(nil, "ARTWORK", nil, 1)
    b.box:SetPoint("TOPLEFT", b.boxEdge, 1, -1)
    b.box:SetPoint("BOTTOMRIGHT", b.boxEdge, -1, 1)
    b.box:SetColorTexture(unpack(C.inset))
    b.check = b:CreateTexture(nil, "OVERLAY")
    b.check:SetTexture("Interface\\Buttons\\UI-CheckBox-Check")
    b.check:SetSize(26, 26)
    b.check:SetPoint("CENTER", b.boxEdge, "CENTER", 0, 0)

    local x = 36
    if icon then
        b.icon = b:CreateTexture(nil, "ARTWORK")
        b.icon:SetSize(20, 20)
        b.icon:SetPoint("LEFT", 36, 0)
        b.icon:SetTexture(icon)
        b.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
        x = 62
    end
    b.label = b:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    b.label:SetPoint("LEFT", x, 0)
    b.label:SetText(label)

    function b:Refresh()
        local on = get()
        self.check:SetShown(on)
        self.label:SetTextColor(unpack(on and C.text or C.muted))
        if self.icon then self.icon:SetDesaturated(not on) end
    end
    b:SetScript("OnClick", function(self)
        set(not get())
        self:Refresh()
        ns.Refresh()
    end)
    b:SetScript("OnEnter", function(self) Ease(self, "hv", 1, 16, ApplyToggleHover) end)
    b:SetScript("OnLeave", function(self) Ease(self, "hv", 0, 16, ApplyToggleHover) end)
    return b
end

-- Item icons --------------------------------------------------------------

local function ApplyIconGlow(b, v) b.glow:SetAlpha(v) end

function W.NewIcon(parent)
    local b = CreateFrame("Button", nil, parent)
    b.isItemIcon = true
    b.edge = b:CreateTexture(nil, "BACKGROUND")
    b.edge:SetAllPoints()
    b.tex = b:CreateTexture(nil, "ARTWORK")
    b.tex:SetPoint("TOPLEFT", 1, -1)
    b.tex:SetPoint("BOTTOMRIGHT", -1, 1)
    b.tex:SetTexCoord(0.07, 0.93, 0.07, 0.93)
    if b.CreateMaskTexture then
        b.mask = b:CreateMaskTexture()
        b.mask:SetTexture("Interface\\CharacterFrame\\TempPortraitAlphaMask", "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
        b.mask:SetPoint("CENTER")
        b.mask:SetSize(32, 32) -- resized with the icon (SetIcon)
        b.edge:AddMaskTexture(b.mask)
        b.tex:AddMaskTexture(b.mask)
    end
    b.glow = b:CreateTexture(nil, "OVERLAY")
    b.glow:SetTexture(W.GLOW_TEX)
    b.glow:SetBlendMode("ADD")
    b.glow:SetPoint("CENTER")
    b.glow:SetAlpha(0)
    b.count = b:CreateFontString(nil, "OVERLAY", "NumberFontNormal")
    b.count:SetPoint("BOTTOMRIGHT", -2, 2)
    b:SetScript("OnEnter", function(self)
        Ease(self, "hv", 1, 18, ApplyIconGlow)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        if self.id == "money" then
            GameTooltip:AddLine(L["Money"], 1, 0.85, 0.4)
            if self.copper and self.copper > 0 and not self.tipExtra then
                GameTooltip:AddLine(ns.Value.Format(self.copper), 1, 1, 1)
            end
        else
            GameTooltip:SetHyperlink(self.link or ("item:" .. self.id))
        end
        if self.tipExtra then self.tipExtra(self) end
        GameTooltip:Show()
    end)
    b:SetScript("OnLeave", function(self)
        Ease(self, "hv", 0, 18, ApplyIconGlow)
        GameTooltip:Hide()
    end)
    return b
end

local GetInstant = (C_Item and C_Item.GetItemInfoInstant) or GetItemInfoInstant

-- Looted money is shown as an item of its own (id "money") with a coin for its icon
W.MONEY_ICON = "Interface\\Icons\\INV_Misc_Coin_01"

-- the biggest unit only: 12g, 45s, 8c
function W.MoneyShort(copper)
    copper = math.floor(copper or 0)
    if copper >= 10000 then return math.floor(copper / 10000) .. "g" end
    if copper >= 100 then return math.floor(copper / 100) .. "s" end
    return copper .. "c"
end

function W.ItemTexture(id)
    if id == "money" then return W.MONEY_ICON end
    return select(5, GetInstant(id)) or 134400
end

-- A light veil over the loot icons so their colours do not outshout the window: a little
-- desaturated and darker. Inactive icons (not looted this session) are fully grey.
W.ICON_SATURATION_LOSS = 0.3
W.ICON_SHADE = 0.82
function W.TintIcon(b, active)
    if b.tex.SetDesaturation then
        b.tex:SetDesaturation(active and W.ICON_SATURATION_LOSS or 1)
    else
        b.tex:SetDesaturated(not active)
    end
    local k = active and W.ICON_SHADE or 1
    b.tex:SetVertexColor(k, k, k)
end

function W.SetIcon(b, id, link, quality, count, size)
    b:SetSize(size, size)
    b.glow:SetSize(size * 1.75, size * 1.75)
    if b.mask then b.mask:SetSize(size * 1.3, size * 1.3) end -- a circle that only clips the corners
    local qc = QUALITY_COLOR[quality] or QUALITY_COLOR[1]
    b.glow:SetVertexColor(qc[1] + 0.2, qc[2] + 0.2, qc[3] + 0.2)
    -- uncommon and better get a 2px frame in their colour; plain items a 1px one
    local border = (quality or 1) >= 2 and 2 or 1
    b.tex:ClearAllPoints()
    b.tex:SetPoint("TOPLEFT", border, -border)
    b.tex:SetPoint("BOTTOMRIGHT", -border, border)
    b.tex:SetTexture(W.ItemTexture(id))
    W.TintIcon(b, true)
    b.id, b.link = id, link
    b.edge:SetColorTexture(qc[1], qc[2], qc[3], 1)
    if id == "money" then
        b.copper = count
        b.count:SetText("") -- the amount is in the tooltip
    else
        b.copper = nil
        b.count:SetText(count and count >= 1 and count or "") -- a single item shows its 1 as well
    end
    b:Show()
end

-- A wrapping grid of item icons. grid:Set(items) with {id, link, quality, count}.
function W.NewIconGrid(parent, size, gap, cols, maxRows)
    local grid = { icons = {}, size = size, gap = gap, cols = cols, maxRows = maxRows }
    local frame = CreateFrame("Frame", nil, parent)
    frame:SetSize(cols * (size + gap), maxRows * (size + gap))
    grid.frame = frame
    grid.more = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    grid.more:SetTextColor(unpack(C.muted))
    function grid:Set(items)
        local max = self.cols * self.maxRows
        local shown = math.min(#items, max)
        for i = 1, shown do
            local b = self.icons[i]
            if not b then b = W.NewIcon(frame); self.icons[i] = b end
            local it = items[i]
            W.SetIcon(b, it.id, it.link, it.quality, it.count, self.size)
            local col, row = (i - 1) % self.cols, math.floor((i - 1) / self.cols)
            b:ClearAllPoints()
            b:SetPoint("TOPLEFT", frame, "TOPLEFT", col * (self.size + self.gap), -row * (self.size + self.gap + (self.rowExtra or 0)))
        end
        for i = shown + 1, #self.icons do self.icons[i]:Hide() end
        if #items > max then
            self.more:ClearAllPoints()
            self.more:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", 0, -12)
            self.more:SetText(L["and %d more"]:format(#items - max))
            self.more:Show()
        else
            self.more:Hide()
        end
    end
    return grid
end

-- Pause / resume button: shows what a click would do right now.
function W.SyncPauseButton(b)
    local s = ns.session
    if not (s and s.start) then
        b:SetIcon(W.ICON.pause)
        b:SetActive(false)
        b.icon:SetDesaturated(true)
        b:SetTip(L["Pause session"], L["The session starts with your first loot."])
    elseif s.paused then
        b:SetIcon(W.ICON.play)
        b:SetActive(true)
        b.icon:SetDesaturated(false)
        b:SetTip(L["Resume session"], L["Also resumes by itself with the next loot."])
    else
        b:SetIcon(W.ICON.pause)
        b:SetActive(false)
        b.icon:SetDesaturated(false)
        b:SetTip(L["Pause session"], L["Pauses the clock until the next loot, or until you resume."])
    end
end

-- Stat cards: the plate with a framed icon, a small label and a value. The same
-- three are used in the journal header and in the session overlay.
W.STAT_ICONS = {
    "Interface\\Icons\\INV_Misc_Coin_01",
    "Interface\\Icons\\INV_Misc_PocketWatch_01",
    "Interface\\Icons\\INV_Misc_Bone_HumanSkull_01",
}

local function ApplyCardHover(card, v)
    card.glow:SetAlpha(v * 0.5)
    card:SetBackdropBorderColor(LerpColor(C.goldDim, C.gold, v))
end

function W.NewStatCard(parent, icon, tipFn)
    local card = W.NewPlate(parent)
    card.glow = W.GlowTexture(card)
    card.glow:SetPoint("TOPLEFT", 3, -3)
    card.glow:SetPoint("BOTTOMRIGHT", -3, 3)

    card.frame = card:CreateTexture(nil, "ARTWORK")
    card.frame:SetSize(32, 32)
    card.frame:SetPoint("LEFT", 10, 0)
    card.frame:SetColorTexture(unpack(C.goldDim))
    card.icon = card:CreateTexture(nil, "OVERLAY")
    card.icon:SetPoint("TOPLEFT", card.frame, 1, -1)
    card.icon:SetPoint("BOTTOMRIGHT", card.frame, -1, 1)
    card.icon:SetTexture(icon)
    card.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)

    card.label = card:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    card.label:SetWordWrap(false)
    card.label:SetPoint("TOPLEFT", card.frame, "TOPRIGHT", 9, -1)
    card.label:SetTextColor(unpack(C.muted))
    card.value = card:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    card.value:SetWordWrap(false)
    card.value:SetPoint("BOTTOMLEFT", card.frame, "BOTTOMRIGHT", 9, 0)
    card.value:SetTextColor(unpack(C.text))
    -- a small second figure at the right edge (nodes gathered)
    card.sub = card:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    card.sub:SetPoint("BOTTOMRIGHT", -10, 9)
    card.sub:SetTextColor(unpack(C.muted))

    card:EnableMouse(true)
    card:SetScript("OnEnter", function(self)
        Ease(self, "hv", 1, 14, ApplyCardHover)
        if tipFn then
            GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
            tipFn(self)
            GameTooltip:Show()
        end
    end)
    card:SetScript("OnLeave", function(self)
        Ease(self, "hv", 0, 14, ApplyCardHover)
        GameTooltip:Hide()
    end)
    return card
end

function W.StatCardTip(index)
    return function()
        if index == 1 then
            GameTooltip:AddLine(L["Total value"], 1, 0.82, 0.3)
            GameTooltip:AddLine(L["Value source: %s"]:format(L[ns.db.valueSource]), 0.8, 0.8, 0.8)
            if ns.snap and ns.snap.unpriced > 0 then
                GameTooltip:AddLine(ns.snap.unpriced == 1 and L["%d item without price not counted"]:format(1)
                    or L["%d items without price not counted"]:format(ns.snap.unpriced), 0.92, 0.6, 0.3)
            end
        elseif index == 2 then
            GameTooltip:AddLine(L["Per hour"], 1, 0.82, 0.3)
            local gained, perHour, missing, eta = ns.XPInfo()
            if gained > 0 then
                GameTooltip:AddLine(" ")
                GameTooltip:AddDoubleLine(L["XP gained"], ns.ShortNumber(gained), 0.8, 0.8, 0.8, 1, 1, 1)
                if perHour then GameTooltip:AddDoubleLine(L["XP per hour"], ns.ShortNumber(perHour), 0.8, 0.8, 0.8, 1, 1, 1) end
                if missing then GameTooltip:AddDoubleLine(L["To next level"], ns.ShortNumber(missing), 0.8, 0.8, 0.8, 1, 1, 1) end
                if eta then GameTooltip:AddDoubleLine(L["Time to level"], W.Duration(eta), 0.8, 0.8, 0.8, 1, 1, 1) end
            end
        else
            GameTooltip:AddLine(L["Session"], 1, 0.82, 0.3)
        end
    end
end

-- A card that gets too narrow gives up things step by step: the second figure, the long
-- label, the icon, and last the size of the figure, until the text fits.
local FIT_STEPS = {
    { icon = true, font = "GameFontNormalLarge" },
    { icon = true, font = "GameFontNormalLarge", short = true },
    { icon = false, font = "GameFontNormalLarge" },
    { icon = false, font = "GameFontNormalLarge", short = true },
    { icon = false, font = "GameFontNormal", short = true },
    { icon = false, font = "GameFontNormalSmall", short = true },
}

-- a smaller stat card (a smaller picture, closer to the edge): for a window that is short of room
function W.CompactStatCard(card)
    card.compact = true
    card.frame:SetSize(28, 28)
    card.frame:ClearAllPoints()
    card.frame:SetPoint("LEFT", 8, 0)
end

-- puts a card in a step and says how much room its text needs
local function MeasureStep(card, st)
    local left = st.icon and (card.compact and 43 or 51) or 10
    card.value:SetFontObject(st.font)
    card.label:SetWidth(0)
    card.value:SetWidth(0)
    card.label:SetText((st.short and card.labelShort or card.labelFull) or "")
    return left, left + math.max(card.label:GetStringWidth(), card.value:GetStringWidth()) + 8
end

-- Fits the text of a card to its width, in steps (the picture goes, the labels get short, the figures smaller). Cards that belong together
-- (card.group) take the same step: when one of them needs the next step, all do.
function W.FitStatCard(card)
    local w = card:GetWidth()
    if not w or w < 20 then return end
    local idx = #FIT_STEPS
    for i, st in ipairs(FIT_STEPS) do
        local _, need = MeasureStep(card, st)
        if need <= w then idx = i break end
    end
    card.natural = idx
    for _, other in ipairs(card.group or {}) do idx = math.max(idx, other.natural or 1) end
    local used = FIT_STEPS[idx]
    local left = MeasureStep(card, used)
    card.frame:SetShown(used.icon)
    card.icon:SetShown(used.icon)
    card.label:ClearAllPoints()
    card.value:ClearAllPoints()
    if used.icon then
        card.label:SetPoint("TOPLEFT", card.frame, "TOPRIGHT", card.compact and 7 or 9, -1)
        card.value:SetPoint("BOTTOMLEFT", card.frame, "BOTTOMRIGHT", card.compact and 7 or 9, 0)
    else
        card.label:SetPoint("LEFT", card, "LEFT", 10, 0)
        card.label:SetPoint("TOP", card.frame, "TOP", 0, -1)
        card.value:SetPoint("LEFT", card, "LEFT", 10, 0)
        card.value:SetPoint("BOTTOM", card.frame, "BOTTOM", 0, 0)
    end
    -- a compact card without its picture has it as its background, darkened
    if card.compact then
        if not card.bgPic then
            card.bgPic = card:CreateTexture(nil, "BACKGROUND", nil, 1)
            card.bgPic:SetPoint("TOPLEFT", 2, -2)
            card.bgPic:SetPoint("BOTTOMRIGHT", -2, 2)
            card.bgPic:SetVertexColor(0.3, 0.3, 0.3)
            card.bgPic:SetAlpha(0.22) -- (faint: the text has to read well over it)
        end
        card.bgPic:SetShown(not used.icon)
        if not used.icon then
            card.bgPic:SetTexture(card.icon:GetTexture())
            local h = math.min(1, (card:GetHeight() or 40) / math.max(1, w)) * 0.43 -- (the middle of the square picture, as high as the card is)
            card.bgPic:SetTexCoord(0.07, 0.93, 0.5 - h, 0.5 + h)
        end
    end
    local room = math.max(10, w - left - 6)
    card.label:SetWidth(math.min(room, card.label:GetStringWidth() + 2))
    card.value:SetWidth(math.min(room, card.value:GetStringWidth() + 2))
    local subW = card.sub:GetText() and card.sub:GetText() ~= "" and card.sub:GetStringWidth() or 0
    card.sub:SetShown(subW > 0 and used.icon and not used.short
        and left + math.max(card.label:GetStringWidth(), card.value:GetStringWidth()) + subW + 18 <= w)
end

local function ApplyTotalValue(card, v)
    card.value:SetText(v >= 1 and ns.Value.Format(v) or (W.Hex(C.muted) .. "-|r"))
    W.FitStatCard(card)
end

-- fills the three cards: total value (counts up), value per hour, session time and kills
-- xpMode: the third card shows the experience per hour (instead of the session), the second only the gold per hour
function W.UpdateStatCards(cards, snap, showPaused, xpMode)
    if showPaused == nil then showPaused = true end
    local s = ns.session
    local elapsed = ns.SessionElapsed()
    cards[1].labelFull, cards[1].labelShort = xpMode and L["Gold"] or L["Total value"], xpMode and L["Gold"] or L["Total value"]
    Ease(cards[1], "val", snap.value, 5, ApplyTotalValue)
    -- the experience per hour next to the gold per hour
    local _, xpPerHour = ns.XPInfo()
    cards[2].labelShort = xpMode and L["Gold/hour"] or L["Per hour"]
    cards[2].labelFull = xpMode and L["Gold/hour"] or (L["Per hour"] .. (xpPerHour and ("  " .. W.Hex({ 0.55, 0.75, 1 }) .. ns.ShortNumber(xpPerHour) .. " XP|r") or ""))
    local perHour = elapsed >= 60 and ns.Value.Format(snap.value / (elapsed / 3600)) or ""
    cards[2].value:SetText(perHour ~= "" and perHour or W.Hex(C.muted) .. "-|r")
    if xpMode then
        cards[3].labelShort, cards[3].labelFull = L["XP/hour"], L["XP/hour"]
        -- the figure in full (as the game writes big numbers), short from a hundred thousand on; in the blue of the experience
        local xpText = "-"
        if xpPerHour then
            local v = math.floor(xpPerHour + 0.5)
            xpText = v >= 100000 and ns.ShortNumber(v) or BreakUpLargeNumbers(v)
        end
        cards[3].value:SetText(W.Hex({ 0.45, 0.7, 1 }) .. xpText .. "|r")
        cards[3].sub:SetText("")
    else
        cards[3].labelShort = W.Duration(elapsed)
        cards[3].labelFull = L["Session"] .. "  " .. W.Duration(elapsed)
            .. ((showPaused and s.paused) and ("  " .. W.Hex({ 0.93, 0.65, 0.37 }) .. L["paused"] .. "|r") or "")
        cards[3].value:SetText(L["%d kills"]:format(snap.kills))
        cards[3].sub:SetText((snap.gathered or 0) > 0 and L["%d gathered"]:format(snap.gathered) or "")
    end
    for _, card in ipairs(cards) do card.group = cards end
    for _, card in ipairs(cards) do W.FitStatCard(card) end
    for _, card in ipairs(cards) do W.FitStatCard(card) end -- (the second time every card knows what the others need)
end



-- Debug aids ---------------------------------------------------------------------------------------------------------------------

-- A window with text that can be selected and copied (the chat cannot): W.Console(text, title). Ctrl+A selects all, Ctrl+C copies.
local console
function W.Console(text, title)
    if not console then
        local f = W.NewPlate(UIParent, C.page)
        f:SetSize(760, 460)
        f:SetPoint("CENTER")
        f:SetFrameStrata("FULLSCREEN_DIALOG")
        f:SetMovable(true)
        f:SetClampedToScreen(true)
        f:EnableMouse(true)
        f:RegisterForDrag("LeftButton")
        f:SetScript("OnDragStart", f.StartMoving)
        f:SetScript("OnDragStop", f.StopMovingOrSizing)
        f.title = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        f.title:SetPoint("TOPLEFT", 14, -14)
        local close = W.NewButton(f, "×", 20, 20, "GameFontNormal")
        close:SetPoint("TOPRIGHT", -8, -8)
        close:SetScript("OnClick", function() f:Hide() end)
        local all = W.NewButton(f, "Select all", 90, 22)
        all:SetPoint("TOPRIGHT", -36, -8)
        local sf = CreateFrame("ScrollFrame", nil, f)
        sf:SetPoint("TOPLEFT", 12, -40)
        sf:SetPoint("BOTTOMRIGHT", -26, 12)
        sf:EnableMouseWheel(true)
        local edit = CreateFrame("EditBox", nil, sf)
        edit:SetMultiLine(true)
        edit:SetAutoFocus(false)
        edit:SetFontObject("GameFontHighlightSmall")
        edit:SetWidth(720)
        edit:SetTextInsets(4, 4, 4, 4)
        sf:SetScrollChild(edit)
        local measure = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        measure:SetWidth(712)
        measure:SetJustifyH("LEFT")
        measure:SetAlpha(0)
        local thumb = f:CreateTexture(nil, "OVERLAY")
        thumb:SetWidth(5)
        thumb:SetColorTexture(C.gold[1], C.gold[2], C.gold[3], 0.75)
        local function Thumb()
            local view, total = sf:GetHeight(), edit:GetHeight()
            if total <= view + 1 then thumb:Hide() return end
            local h = math.max(24, view * view / total)
            local off = sf:GetVerticalScroll() / (total - view) * (view - h)
            thumb:ClearAllPoints()
            thumb:SetPoint("TOPRIGHT", f, "TOPRIGHT", -12, -40 - off)
            thumb:SetHeight(h)
            thumb:Show()
        end
        local function Fit()
            measure:SetText(edit:GetText())
            edit:SetHeight(math.max(sf:GetHeight(), (measure:GetStringHeight() or 0) + 12))
            Thumb()
        end
        edit:SetScript("OnTextChanged", Fit)
        edit:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
        edit:SetScript("OnCursorChanged", function(self, _, y, _, h)
            -- the view follows the cursor
            local top, view = sf:GetVerticalScroll(), sf:GetHeight()
            y = -y
            if y < top then sf:SetVerticalScroll(y) elseif y + h > top + view then sf:SetVerticalScroll(y + h - view) end
        end)
        sf:SetScript("OnMouseWheel", function(self, delta)
            local maxScroll = math.max(0, edit:GetHeight() - self:GetHeight())
            self:SetVerticalScroll(math.max(0, math.min(maxScroll, self:GetVerticalScroll() - delta * 60)))
        end)
        sf:SetScript("OnVerticalScroll", Thumb)
        all:SetScript("OnClick", function() edit:SetFocus(); edit:HighlightText() end)
        f.edit, f.fit = edit, Fit
        console = f
    end
    console.title:SetText(title or "Console")
    console:Show()
    console.edit:SetText(text or "")
    console.fit()
    console.edit:SetFocus()
    console.edit:HighlightText()
end

-- A description of a frame or texture of the game (atlas or file, size, colour, coordinates, places, child frames), as text.
function W.Dump(path)
    local obj = _G
    if type(path) == "table" then
        obj = path
    else
        for part in tostring(path or ""):gmatch("[^%.]+") do
            obj = type(obj) == "table" and obj[part] or nil
        end
    end
    if type(obj) ~= "table" or not obj.GetObjectType then
        return "nothing found for \"" .. tostring(path) .. "\" (is the window loaded? open it once)"
    end
    local lines = {}
    local function Out(fmt, ...) lines[#lines + 1] = fmt:format(...) end
    local function Name(o)
        return tostring(o:GetName() or (o.GetDebugName and o:GetDebugName()) or "?")
    end
    local function Points(o, indent)
        for n = 1, (o.GetNumPoints and o:GetNumPoints() or 0) do
            local point, rel, relPoint, x, y = o:GetPoint(n)
            Out("%s   point %s of %s at %s %.1f,%.1f", indent, tostring(point), rel and Name(rel) or "nil", tostring(relPoint), x or 0, y or 0)
        end
    end
    local function Texture(t, indent)
        local atlas = t.GetAtlas and t:GetAtlas()
        local file = t.GetTexture and t:GetTexture()
        local r, g, bl = 1, 1, 1
        if t.GetVertexColor then r, g, bl = t:GetVertexColor() end
        local layer, sub = t:GetDrawLayer()
        Out("%sTexture layer=%s/%s atlas=%s file=%s size=%dx%d vc=%.2f,%.2f,%.2f alpha=%.2f shown=%s", indent, tostring(layer), tostring(sub),
            tostring(atlas), tostring(file), t:GetWidth() or 0, t:GetHeight() or 0, r, g, bl, t:GetAlpha() or 1, tostring(t:IsShown()))
        if t.GetTexCoord then
            local ulx, uly, llx, lly, urx, ury, lrx, lry = t:GetTexCoord()
            Out("%s   coords ul=%.2f,%.2f ll=%.2f,%.2f ur=%.2f,%.2f lr=%.2f,%.2f  parent=%s", indent, ulx or 0, uly or 0, llx or 0, lly or 0,
                urx or 0, ury or 0, lrx or 0, lry or 0, t:GetParent() and Name(t:GetParent()) or "nil")
        end
        Points(t, indent)
    end
    local function Walk(fr, indent, depth)
        for _, region in ipairs({ fr:GetRegions() }) do
            if region.GetObjectType and region:GetObjectType() == "Texture" then Texture(region, indent) end
        end
        if depth < 2 then
            for _, ch in ipairs({ fr:GetChildren() }) do
                Out("%s> child %s (%s) %dx%d level %d shown=%s", indent, Name(ch), ch:GetObjectType(), ch:GetWidth() or 0, ch:GetHeight() or 0,
                    ch:GetFrameLevel() or 0, tostring(ch:IsShown()))
                Walk(ch, indent .. "   ", depth + 1)
            end
        end
    end
    Out("%s (%s) %dx%d level %d", Name(obj), obj:GetObjectType(), obj:GetWidth() or 0, obj:GetHeight() or 0,
        obj.GetFrameLevel and obj:GetFrameLevel() or 0)
    Points(obj, "")
    if obj:GetObjectType() == "Texture" then Texture(obj, "") else Walk(obj, "  ", 0) end
    return table.concat(lines, "\n")
end

-- /fcdump <name of a frame, e.g. PlayerSpellsFrame.TalentsFrame.Background>: its textures and child frames, in a window to copy from
SLASH_FOREVERCOMPANIONDUMP1 = "/fcdump"
SlashCmdList.FOREVERCOMPANIONDUMP = function(path)
    W.Console(W.Dump(path), "fcdump " .. tostring(path))
end
