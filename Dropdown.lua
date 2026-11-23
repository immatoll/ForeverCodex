local ADDON, ns = ...
local L = ns.L
local W = ns.W
local C = W.C

-- A context menu that opens while the mouse is over its button (or over the menu) and closes a
-- moment after it has left both. Its rows are described by a function, asked again after every click:
--   { kind = "check",  state = "all" | "some" | "none", label, icon, right, indent, onClick }
--   { kind = "radio",  state = "all" | "none", ... }          (one of several)
--   { kind = "action", label, icon, onClick, close }
--   { kind = "header", label }  { kind = "separator" }  { kind = "text", label }
-- label may carry colour codes; color = { r, g, b } colours a plain label.

local ROW_H, SEP_H, HEAD_H = 22, 10, 22

local function HeightOf(e, dd)
    if e.kind == "separator" then return SEP_H end
    if e.kind == "header" then return HEAD_H end
    return dd and dd.rowH or ROW_H
end

local function NewRow(dd)
    local r = CreateFrame("Button", nil, dd)
    r.hl = r:CreateTexture(nil, "BACKGROUND")
    r.hl:SetAllPoints()
    r.hl:SetColorTexture(1, 0.85, 0.4, 0.10)
    r.hl:SetAlpha(0)
    r.line = r:CreateTexture(nil, "ARTWORK")
    r.line:SetPoint("LEFT", 6, 0)
    r.line:SetPoint("RIGHT", -6, 0)
    r.line:SetHeight(1)
    r.line:SetColorTexture(C.goldDim[1], C.goldDim[2], C.goldDim[3], 0.5)
    r.edge = r:CreateTexture(nil, "ARTWORK")
    r.edge:SetSize(12, 12)
    r.edge:SetColorTexture(unpack(C.goldDim))
    r.box = r:CreateTexture(nil, "ARTWORK", nil, 1)
    r.box:SetPoint("TOPLEFT", r.edge, 1, -1)
    r.box:SetPoint("BOTTOMRIGHT", r.edge, -1, 1)
    r.box:SetColorTexture(unpack(C.inset))
    r.tick = r:CreateTexture(nil, "OVERLAY")
    r.tick:SetColorTexture(unpack(C.gold))
    r.icon = r:CreateTexture(nil, "ARTWORK")
    r.icon:SetSize(16, 16)
    r.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
    r.label = r:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    r.label:SetJustifyH("LEFT")
    r.label:SetWordWrap(false)
    r.right = r:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    r.right:SetPoint("RIGHT", -8, 0)
    r.right:SetTextColor(unpack(C.muted))
    r:SetScript("OnEnter", function(self) if self.fn then self.hl:SetAlpha(1) end end)
    r:SetScript("OnLeave", function(self) self.hl:SetAlpha(0) end)
    r:SetScript("OnClick", function(self)
        if not self.fn then return end
        W.Click()
        local close = self.closes
        self.fn()
        if close then dd:Close() else dd:Render() end
    end)
    return r
end

-- While a menu is open no tooltip is shown (the one of the button that opened it would cover the menu): every menu is listed here, and
-- a tooltip that is shown meanwhile is taken away again, except one that belongs to the menu itself.
local menus = {}
function W.MenuOpen()
    for _, m in ipairs(menus) do if m:IsShown() then return true end end
    return false
end
local function InsideMenu(frame)
    while frame do
        for _, m in ipairs(menus) do if m == frame then return true end end
        frame = frame.GetParent and frame:GetParent() or nil
    end
    return false
end
hooksecurefunc(GameTooltip, "Show", function(tt)
    if not W.MenuOpen() then return end
    local owner = tt:GetOwner()
    if owner and owner ~= UIParent and not InsideMenu(owner) then tt:Hide() end
end)

function W.NewDropdown(parent, opts)
    opts = opts or {}
    local dd = W.NewPlate(parent, { 0.045, 0.035, 0.026, 0.98 })
    menus[#menus + 1] = dd
    -- opts.strata: a menu in front of a window of the game must not sit behind that window's frame
    dd:SetFrameStrata(opts.strata or "FULLSCREEN_DIALOG") -- (a menu is always in front of the windows, whichever of them it belongs to)
    dd:SetFrameLevel(opts.level or (parent:GetFrameLevel() + 60))
    dd:SetWidth(opts.width or 250)
    dd:EnableMouse(true)
    dd:EnableMouseWheel(true)
    dd:Hide()
    dd.rows, dd.offset, dd.shown = {}, 0, 0
    local maxH = opts.maxHeight or 380
    -- a larger, framed look for a menu of its own (opts: rowH, iconSize, font, headFont, padX, padY, metal: the metal frame of the game's windows)
    dd.rowH, dd.iconSize, dd.font, dd.headFont = opts.rowH, opts.iconSize, opts.font, opts.headFont
    dd.padX, dd.padY = opts.padX, opts.padY
    dd.offX, dd.offY = opts.offX, opts.offY -- (where it hangs under its button)
    if opts.metal then
        local nine = CreateFrame("Frame", nil, dd)
        nine:SetAllPoints(dd)
        nine:SetFrameLevel(dd:GetFrameLevel() + 8)
        nine:EnableMouse(false)
        local ok = NineSliceUtil and NineSliceUtil.ApplyLayoutByName and pcall(NineSliceUtil.ApplyLayoutByName, nine, "ButtonFrameTemplateNoPortrait")
        if not ok then
            -- (without the game's frame: a gilded tooltip border)
            nine:SetBackdrop({ edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border", edgeSize = 16 })
            nine:SetBackdropBorderColor(C.goldDim[1], C.goldDim[2], C.goldDim[3], 1)
        end
        dd:SetBackdropColor(0.06, 0.05, 0.04, 0.98)
    end

    function dd:Close()
        self:Hide()
        self.owner = nil
    end

    function dd:Render()
        if not (self:IsShown() and self.gen) then return end
        local list = self.gen()
        self.list = list
        self.offset = math.max(0, math.min(self.offset, math.max(0, #list - 1)))
        -- does everything fit? if not, a scroll bar takes the room at the right
        local px, py = self.padX or 5, self.padY or 5
        local sum, fit, acc = 0, 0, py
        for i = 1, #list do
            local h = HeightOf(list[i], self)
            sum = sum + h
            if not (acc + h > maxH and fit > 0) and fit == i - 1 then fit = i; acc = acc + h end
        end
        local scrolls = sum + 2 * py > maxH
        self.fit = fit
        local pad = scrolls and 16 or px
        local y, n = py, 0
        for i = self.offset + 1, #list do
            local e = list[i]
            local h = HeightOf(e, self)
            if y + h > maxH and n > 0 then break end
            n = n + 1
            local r = self.rows[n]
            if not r then r = NewRow(self); self.rows[n] = r end
            r:SetHeight(h)
            r:ClearAllPoints()
            r:SetPoint("TOPLEFT", px, -y)
            r:SetPoint("TOPRIGHT", -pad, -y)
            y = y + h

            local kind = e.kind or "action"
            local check = kind == "check" or kind == "radio"
            r.line:SetShown(kind == "separator")
            r.edge:SetShown(check)
            r.box:SetShown(check)
            r.tick:SetShown(check and e.state ~= "none" and e.state ~= nil)
            local x = (e.indent or 0) + 8
            if check then
                r.edge:ClearAllPoints()
                r.edge:SetPoint("LEFT", x - 2, 0)
                r.tick:ClearAllPoints()
                local inset = kind == "radio" and 4 or 3
                r.tick:SetPoint("TOPLEFT", r.edge, inset, -inset)
                r.tick:SetPoint("BOTTOMRIGHT", r.edge, -inset, inset)
                r.tick:SetAlpha(e.state == "some" and 0.5 or 1)
                x = x + 18
            end
            if e.icon then
                r.icon:ClearAllPoints()
                r.icon:SetPoint("LEFT", x, 0)
                r.icon:SetTexture(e.icon)
                if e.coords then r.icon:SetTexCoord(unpack(e.coords)) else r.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93) end
                r.icon:SetSize(self.iconSize or 16, self.iconSize or 16)
                r.icon:Show()
                x = x + (self.iconSize or 16) + 5
            else
                r.icon:Hide()
            end
            r.label:ClearAllPoints()
            r.label:SetPoint("LEFT", x, 0)
            r.label:SetPoint("RIGHT", -(e.right and 56 or 8), 0)
            r.label:SetText(e.label or "")
            if kind == "header" then
                r.label:SetFontObject(self.headFont or "GameFontNormalSmall")
                r.label:SetTextColor(1, 0.88, 0.5)
            else
                r.label:SetFontObject(self.font or "GameFontHighlightSmall")
                local col = e.color or (kind == "action" and C.gold) or (kind == "text" and C.muted) or C.text
                r.label:SetTextColor(col[1], col[2], col[3])
            end
            r.label:SetAlpha(((kind == "check" or kind == "radio") and e.state == "none") and 0.7 or 1)
            r.right:SetText(e.right or "")
            r.fn = (kind == "header" or kind == "separator" or kind == "text") and nil or e.onClick
            r.closes = e.close
            r:Show()
        end
        for k = n + 1, #self.rows do self.rows[k]:Hide() end
        self.shown = n
        self:SetHeight(y + py)
        self.total = #list
        self:UpdateBar(scrolls, y)
    end

    -- the scroll bar: a thin track with a thumb that can be dragged
    function dd:UpdateBar(show, bottom)
        local bar = self.bar
        if not bar then
            if not show then return end
            bar = CreateFrame("Frame", nil, self)
            bar:SetWidth(8)
            bar:EnableMouse(true)
            -- (a slim gilded thumb, no dark track: as the scroll bars of the windows)
            bar.thumb = CreateFrame("Button", nil, bar)
            bar.thumb:SetWidth(4)
            bar.thumb.tex = bar.thumb:CreateTexture(nil, "ARTWORK")
            bar.thumb.tex:SetAllPoints()
            bar.thumb.tex:SetColorTexture(C.goldDim[1], C.goldDim[2], C.goldDim[3], 0.8)
            local dd = self
            local function MaxOffset() return math.max(0, (dd.total or 0) - (dd.fit or 0)) end
            bar.thumb:SetScript("OnMouseDown", function(t)
                local _, cy = GetCursorPosition()
                t.drag = { y = cy / t:GetEffectiveScale(), offset = dd.offset }
            end)
            bar.thumb:SetScript("OnMouseUp", function(t) t.drag = nil end)
            bar.thumb:SetScript("OnUpdate", function(t)
                if not t.drag then return end
                local _, cy = GetCursorPosition()
                cy = cy / t:GetEffectiveScale()
                local room = bar:GetHeight() - t:GetHeight()
                if room > 0 then
                    local off = t.drag.offset + (t.drag.y - cy) / room * MaxOffset()
                    off = math.max(0, math.min(MaxOffset(), math.floor(off + 0.5)))
                    if off ~= dd.offset then dd.offset = off; dd:Render() end
                end
            end)
            bar:SetScript("OnMouseDown", function(b)
                local _, cy = GetCursorPosition()
                cy = cy / b:GetEffectiveScale()
                local top = b.thumb:GetTop()
                local page = math.max(1, (dd.fit or 3) - 1)
                local off = dd.offset + ((top and cy > top) and -page or page)
                dd.offset = math.max(0, math.min(MaxOffset(), off))
                dd:Render()
            end)
            self.bar = bar
        end
        bar:SetShown(show)
        if not show then return end
        bar:ClearAllPoints()
        bar:SetPoint("TOPRIGHT", self, "TOPRIGHT", -4, -(self.padY or 5))
        bar:SetHeight(math.max(10, bottom - (self.padY or 5)))
        local room = bar:GetHeight()
        local fit, total = math.max(1, self.fit or 1), math.max(1, self.total or 1)
        local th = math.max(18, room * fit / total)
        bar.thumb:SetHeight(th)
        bar.thumb:ClearAllPoints()
        local maxOff = math.max(1, total - fit)
        bar.thumb:SetPoint("TOP", bar, "TOP", 0, -(math.min(1, self.offset / maxOff)) * (room - th))
    end

    -- opened by the mouse over btn; gen() gives the rows. atCursor: the menu's corner is at the mouse (a context menu)
    -- instead of under the button; it is moved up when it would reach below the screen.
    function dd:Open(btn, gen, atCursor)
        GameTooltip:Hide() -- (the tooltip of the button, or of the row clicked, would hide the menu)
        self.away = 0
        self.gen = gen
        if self.owner == btn and self:IsShown() and not atCursor then return self:Render() end
        self.owner, self.offset = btn, 0
        self:ClearAllPoints()
        if atCursor then
            local x, y = GetCursorPosition()
            local sc = self:GetEffectiveScale()
            x, y = x / sc, y / sc
            self:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", x + 2, y - 2)
            self:Show()
            self:Render()
            local h = self:GetHeight() or 0
            if y - 2 - h < 4 then -- it would reach below the screen: its lower corner at the mouse instead
                self:ClearAllPoints()
                self:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", x + 2, math.max(4, y - 2))
            end
            return
        end
        self:SetPoint("TOPLEFT", btn, "BOTTOMLEFT", self.offX or 0, self.offY or 0)
        self:Show()
        self:Render()
    end

    -- the menu is there while the mouse is over its button or over the menu itself
    dd:SetScript("OnUpdate", function(self, dt)
        local owner = self.owner
        if owner and owner:IsShown() and (owner:IsMouseOver() or self:IsMouseOver()) then
            self.away = 0
            return
        end
        self.away = (self.away or 0) + dt
        if self.away > 0.2 then self:Close() end
    end)

    dd:SetScript("OnMouseWheel", function(self, delta)
        if not W.TopFrameIs(self) then return end
        local list = self.list or {}
        if delta < 0 and self.offset + self.shown < #list then
            self.offset = self.offset + 3
        elseif delta > 0 and self.offset > 0 then
            self.offset = math.max(0, self.offset - 3)
        end
        self:Render()
    end)
    return dd
end

-- a button that opens a menu when the mouse comes over it: text, an optional picture, an arrow
function W.NewMenuButton(parent, dd, text, icon)
    local b = W.NewButton(parent, text or "", 100, 24)
    b.arrow = b:CreateTexture(nil, "OVERLAY")
    b.arrow:SetSize(9, 9)
    b.arrow:SetPoint("RIGHT", -7, 0)
    b.arrow:SetTexture("Interface\\ChatFrame\\ChatFrameExpandArrow")
    b.arrow:SetRotation(math.rad(-90))
    b.arrow:SetVertexColor(0.8, 0.72, 0.5)
    b.pic = b:CreateTexture(nil, "OVERLAY")
    b.pic:SetSize(14, 14)
    b.pic:SetPoint("LEFT", 7, 0)
    b.pic:SetTexCoord(0.07, 0.93, 0.07, 0.93)
    b.dd = dd
    function b:SetContent(label, picture, gen, on)
        self.gen = gen
        self.text:SetText(label)
        self.text:ClearAllPoints()
        if picture then
            self.pic:SetTexture(picture)
            self.pic:Show()
            self.text:SetPoint("LEFT", 26, 0)
        else
            self.pic:Hide()
            self.text:SetPoint("LEFT", 9, 0)
        end
        self:SetWidth(self.text:GetStringWidth() + (picture and 26 or 9) + 24)
        self:SetSelected(on and true or false)
    end
    -- by default the menu opens when the mouse comes over; with clickOnly it opens (and closes) with a click, which
    -- is what a column of such buttons needs: the mouse passes over the others on its way to a menu
    b:HookScript("OnEnter", function(self) if self.gen and not self.clickOnly then self.dd:Open(self, self.gen) end end)
    b:SetScript("OnClick", function(self)
        if not (self.clickOnly and self.gen) then return end
        if self.dd.owner == self and self.dd:IsShown() then self.dd:Close() else self.dd:Open(self, self.gen) end
    end)
    return b
end
