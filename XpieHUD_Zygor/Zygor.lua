-- Zygor.lua  (XpieHUD_Zygor module)
-- Zygor Guides Viewer integration. Style "xpiehud" (default):
--   * transparent Zygor window chrome and logo
--   * step boxes keep Zygor's state colours at an adjustable opacity, no edges
--   * a native dark tooltip-style panel (XpieHUD_Core Panels.lua) anchored behind the window
--   * "XpieHUD Gold" arrow skin: our gold arrowhead as a native Zygor arrow skin
-- Style "original" leaves Zygor's look alone.
--
-- Zygor internals used (checked against Zygor 9.6 retail, 12.1.5):
--   _G.ZGV, ZGV.Frame (ZygorGuidesViewerFrame, skin "default")
--   ZGV.Frame:ApplySkin()            Skins/Default/Skin.lua   (window backdrops)
--   ZGV.Frame.Border / .Border.Back / .Border.TabContainer / .Border.Toolbar
--   ZGV_DefaultSkin_DefaultStep_Mixin:ApplySkin / :SetBackgroundForStep
--   ZGV.Pointer:AddArrowSkin / :SetArrowSkin, sprite arrows (Arrows/ArrowSkin.lua)
-- Zygor isn't secure code, so hooking it can't taint Blizzard's UI.
--
-- Load order: "XpieHUD_Zygor" sorts before "ZygorGuidesViewer", so this file
-- runs before Zygor's and can hook its step mixin before Zygor builds its
-- window (on Zygor's ADDON_LOADED below).

local core = XpieHUD

local SKIN_ID       = "XpieHUD"
local SKIN_NAME     = "XpieHUD Gold"
local MEDIA_DIR     = "Interface\\AddOns\\XpieHUD_Zygor\\Media\\"

local module = core:RegisterModule("zygor", {
    title = "Zygor Guides",
    defaults = {
        -- "xpiehud": transparent Zygor chrome + logo, gold arrow, XpieHUD
        --            background panel. "original": leave Zygor's look alone.
        style     = "xpiehud",
        goldArrow = true,   -- "XpieHUD Gold" arrow skin (XpieHUD style)
        stepAlpha = 50,     -- step box tint, % (XpieHUD style)
        panel     = core.PANEL_DEFAULTS,   -- deep-copied into the saved settings
        -- prevArrowSkin: the Zygor arrow skin to restore when goldArrow is off
    },
    -- 2.x kept these at the top level of XpieHUDDB; moved in on first run.
    Migrate = function(_, root, db)
        local moves = { guideZygor = "enabled", zygorStrip = "strip",
                        zygorGoldArrow = "goldArrow", zygorPrevArrowSkin = "prevArrowSkin" }
        for old, new in pairs(moves) do
            if root[old] ~= nil then
                db[new] = root[old]
                root[old] = nil
            end
        end
    end,
})

-- 2.x / 3.0 "enabled" + "strip" switches became the single style choice.
do
    local db = module.db
    if db and (db.enabled ~= nil or db.strip ~= nil) then
        db.style = (db.enabled ~= false and db.strip ~= false) and "xpiehud" or "original"
        db.enabled, db.strip = nil, nil
    end
    -- 3.1.0 briefly had a texture/colour panel editor; back to the native panel.
    if db and type(db.panel) == "table" then
        core:NormalizePanelStyle(db.panel)
    end
end

local function XpieStyle()
    return module.db and module.db.style == "xpiehud" and _G.ZGV ~= nil
end
local StripOn = XpieStyle

-- ---------------------------------------------------------------------------
-- Backdrop helpers
-- ---------------------------------------------------------------------------
local clearing = false   -- re-entrancy guard for the setter post-hooks

local function ClearBackdrop(f)
    if not (f and f.GetBackdropColor) then return end
    clearing = true
    local r, g, b = f:GetBackdropColor()
    if r then f:SetBackdropColor(r, g, b, 0) end
    local br, bg, bb = f:GetBackdropBorderColor()
    if br then f:SetBackdropBorderColor(br, bg, bb, 0) end
    clearing = false
end

-- Title-bar "ZYGOR" logo (Border.TitleBar.Logo, a texture). Zygor only sets its
-- image and size, never its alpha, so hiding it by alpha sticks.
local function SetLogoShown(shown)
    local frame = _G.ZGV and _G.ZGV.Frame
    local logo = frame and frame.Controls and frame.Controls.Logo
    if logo then logo:SetAlpha(shown and 1 or 0) end
end

-- Zygor re-colours its window on skin changes and flashes the border when a
-- step completes; keep whatever colour it wants but at zero alpha.
local hookedChrome = {}
local function HookChrome(f)
    if not f or hookedChrome[f] or not f.SetBackdropColor then return end
    hookedChrome[f] = true
    local function reclear(self)
        if clearing or not StripOn() then return end
        ClearBackdrop(self)
    end
    hooksecurefunc(f, "SetBackdropColor", reclear)
    hooksecurefunc(f, "SetBackdropBorderColor", reclear)
end

local function ChromeFrames()
    local frame = _G.ZGV and _G.ZGV.Frame
    local border = frame and frame.Border
    if not border then return {} end
    return { border, border.Back, border.TabContainer, border.Toolbar }
end

local function StripChrome()
    for _, f in ipairs(ChromeFrames()) do ClearBackdrop(f) end
    SetLogoShown(false)
end

-- ---------------------------------------------------------------------------
-- Step boxes
-- ---------------------------------------------------------------------------
local function StyleStep(step)
    if clearing or not StripOn() or not step.GetBackdropColor then return end
    clearing = true
    local r, g, b = step:GetBackdropColor()
    if r then step:SetBackdropColor(r, g, b, (module.db.stepAlpha or 50) / 100) end
    local br, bg, bb = step:GetBackdropBorderColor()
    if br then step:SetBackdropBorderColor(br, bg, bb, 0) end
    clearing = false
end

local stepMixinHooked = false
local function HookStepMixin()
    local mixin = _G.ZGV_DefaultSkin_DefaultStep_Mixin
    if stepMixinHooked or not mixin then return end
    stepMixinHooked = true
    -- Step frames copy these methods when the pool creates them, so hooking the
    -- mixin before Zygor builds its window covers every step.
    hooksecurefunc(mixin, "ApplySkin", StyleStep)
    hooksecurefunc(mixin, "SetBackgroundForStep", StyleStep)
end

-- Safety net for step frames created before the mixin hook (load-order race).
local function ForEachStep(fn)
    local frame = _G.ZGV and _G.ZGV.Frame
    local pools = frame and frame.stepFramePools
    if not pools then return end
    for _, pool in pairs(pools) do
        for step in pool:EnumerateActive() do fn(step) end
    end
end

local function HookStepInstance(step)
    local mixin = _G.ZGV_DefaultSkin_DefaultStep_Mixin
    if mixin and step.SetBackgroundForStep ~= mixin.SetBackgroundForStep and not step.xhudHooked then
        step.xhudHooked = true
        hooksecurefunc(step, "ApplySkin", StyleStep)
        hooksecurefunc(step, "SetBackgroundForStep", StyleStep)
    end
end

-- ---------------------------------------------------------------------------
-- Arrow skin
-- 1024x1024 sprite sheet (Media/arrow.tga): 160 frames of the gold arrowhead,
-- 2.25 deg apart counter-clockwise, in 96x64 cells (Zygor's arrow texture is
-- 50x33, same 1.5 aspect, so the arrowhead shows ~33px tall).
-- ---------------------------------------------------------------------------
local function RegisterArrowSkin()
    local ZGV = _G.ZGV
    local Pointer = ZGV and ZGV.Pointer
    if not (Pointer and Pointer.AddArrowSkin) or Pointer.ArrowSkins[SKIN_ID] then return end

    local skin = Pointer:AddArrowSkin(SKIN_ID, SKIN_NAME)
    skin.GetDir = function() return MEDIA_DIR end
    skin.features = { smooth = true }
    skin.options = {
        spr_w = 96, spr_h = 64, img_w = 1024, img_h = 1024,
        spritecount = 160,
        mirror = false,
        precise = { range = 3, smooth = false, r = 1, g = 1, b = 1 },
        -- white gradient = no tint: the arrow stays gold
        ar = 1, ag = 1, ab = 1,
        br = 1, bg = 1, bb = 1,
        cr = 1, cg = 1, cb = 1,
        texture = MEDIA_DIR .. "arrow",
        template = "ZygorGuidesViewerFrame_ArrowSkin_Template",
    }
    -- Stairs / taxi / ship / waiting / error icons: reuse Zygor's Stealth set.
    skin.icons = {
        here = { 1, 1, 40, 40 }, upstairs = { 2, 1, 60, 60 }, error = { 3, 1, 40, 40 },
        instance = { 4, 1, 40, 40 }, taxi = { 5, 1, 40, 40 }, ship = { 6, 1, 40, 40 },
        waiting = { 1, 2, 40, 40 }, downstairs = { 2, 2, 60, 60 }, instancehide = { 4, 2, 40, 40 },
        file = (ZGV.ARROWSDIR or "Interface\\AddOns\\ZygorGuidesViewer\\Arrows\\") .. "Stealth\\specials",
        cols = 8, rows = 2, width = 1024, height = 256, padding = 0,
        default = "wait",
    }
    local createFrame = skin.CreateFrame
    skin.CreateFrame = function(self)
        local f = createFrame(self)   -- runs Zygor's Setup(), which builds the icon helpers
        -- The "metal" option swaps in an -specular texture we don't ship.
        f.SetOption = function() end
        -- "You're here" marker: Zygor's is a green down-arrow, which flickers in
        -- when flying over a waypoint (in and out of its arrival radius). Use
        -- our gold arrowhead pointing down instead: sheet frame 80 (180 deg),
        -- row 8 / column 0, drawn at the arrow's own 50x33 size. Zygor's
        -- bounce animation still plays on it.
        local here = f.icons and f.icons.here
        if here then
            here.AssignToTexture = function(_, texture)
                texture:SetTexture(MEDIA_DIR .. "arrow")
                texture:SetTexCoord(0, 96 / 1024, 512 / 1024, 576 / 1024)
                texture:SetVertexColor(1, 1, 1)
                texture:SetSize(50, 33)
            end
        end
        return f
    end
end

local function ApplyArrow()
    local ZGV = _G.ZGV
    local Pointer = ZGV and ZGV.Pointer
    local profile = ZGV and ZGV.db and ZGV.db.profile
    -- Pointer builds its arrow parent during Zygor's threaded startup.
    if not (Pointer and Pointer.ArrowSkins and Pointer.ArrowSkins[SKIN_ID] and Pointer.ArrowFrameCtrl and profile) then
        return
    end
    if InCombatLockdown() then   -- the arrow frame uses a secure state driver
        core.applyPending = true
        return
    end

    local db = module.db
    local want = XpieStyle() and db.goldArrow
    local current = profile.arrowskin
    if want and current ~= SKIN_ID then
        db.prevArrowSkin = current
        Pointer:SetArrowSkin(SKIN_ID)
        Pointer:UpdateArrowVisibility()
    elseif not want and current == SKIN_ID then
        local prev = db.prevArrowSkin
        if not (prev and Pointer.ArrowSkins[prev]) then prev = "Starlight" end
        Pointer:SetArrowSkin(prev)
        Pointer:UpdateArrowVisibility()
    end
end

-- ---------------------------------------------------------------------------
-- Title bar buttons (XpieHUD style)
-- Zygor's menu ("burger") and close buttons stay the real buttons (clicks,
-- menus, dragging, tooltips all Zygor's own). We only change how they look:
--   * Zygor's own button art is hidden by alpha. Zygor repaints it with
--     SetTexture/SetTexCoord and never touches alpha (except the highlight
--     alpha in AssignTextures, which our ApplySkin post-hook re-hides).
--   * Our art is extra textures created on the button, which Zygor's code
--     doesn't know about, so it can't repaint them:
--       menu  -> the Damage Meter's gold settings gear (left end of the bar)
--       close -> Blizzard's red close button (UIPanelCloseButton art and size)
--     The HIGHLIGHT draw layer gives the native hover; mouse down/up hooks
--     swap in the pressed art.
-- The Original style hides our art and restores Zygor's alpha, size, anchors
-- and frame level.
-- ---------------------------------------------------------------------------
local BUTTON_STYLES = {
    MenuSettingsButton = {
        normal = "common-dropdown-a-button-settings-shadowless",
        pushed = "common-dropdown-a-button-settings-pressed-shadowless",
        hover  = "common-dropdown-a-button-settings-hover-shadowless", hoverBlend = "BLEND",
        size = 27, point = "LEFT", x = 4,   -- Blizzard's size (DamageMeterSettingsDropdownButtonTemplate)
        y = -2,   -- the gear art sits high in its box; Blizzard nudges it 2px down too (Damage Meter header)
    },
    CloseButton = {
        normal = "RedButton-Exit",
        pushed = "RedButton-exit-pressed",
        hover  = "RedButton-Highlight", hoverBlend = "ADD",
        size = 24, point = "RIGHT", x = -2,  -- Blizzard's size (UIPanelCloseButton)
    },
}
-- Title starts after the gear and stops before the close button.
local TITLE_LEFT  = 4 + 27 + 5
local TITLE_RIGHT = 2 + 24 + 6

local skins = {}       -- [button] = { art, glow, spec, saved = { points, level } }

local function ZygorTextures(button)
    return { button:GetNormalTexture(), button:GetPushedTexture(),
             button:GetHighlightTexture(), button:GetDisabledTexture() }
end

local function SetZygorArtShown(button, shown)
    for _, tx in ipairs(ZygorTextures(button)) do
        if tx then tx:SetAlpha(shown and 1 or 0) end
    end
end

local function GetSkin(button, spec)
    local skin = skins[button]
    if skin then return skin end

    local art = button:CreateTexture(nil, "ARTWORK")
    art:SetAllPoints()
    art:SetAtlas(spec.normal)
    local glow = button:CreateTexture(nil, "HIGHLIGHT")   -- shown on mouse-over
    glow:SetAllPoints()
    glow:SetAtlas(spec.hover)
    glow:SetBlendMode(spec.hoverBlend)

    art:Hide()    -- shown only while the XpieHUD style is on
    glow:Hide()
    skin = { art = art, glow = glow, spec = spec }
    skins[button] = skin

    button:HookScript("OnMouseDown", function(self)
        if skin.on and self:IsEnabled() then art:SetAtlas(spec.pushed) end
    end)
    local function Release() art:SetAtlas(spec.normal) end
    button:HookScript("OnMouseUp", Release)
    button:HookScript("OnHide", Release)

    -- Zygor re-skins its buttons on ApplySkin: hide its art and put the
    -- button back where we want it.
    if button.ApplySkin then
        hooksecurefunc(button, "ApplySkin", function(self)
            if skin.on then module:StyleTitleButton(self) end
        end)
    end
    return skin
end

function module:StyleTitleButton(button)
    local skin = skins[button]
    local spec = skin.spec
    if not skin.saved then
        local points = {}
        for i = 1, button:GetNumPoints() do points[i] = { button:GetPoint(i) } end
        skin.saved = { points = points, level = button:GetFrameLevel() }
    end
    skin.on = true
    SetZygorArtShown(button, false)
    skin.art:SetAtlas(spec.normal)
    skin.art:Show()
    skin.glow:Show()

    button:SetSize(spec.size, spec.size)
    button:ClearAllPoints()
    button:SetPoint(spec.point, self.panel.headerFrame, spec.point, spec.x, spec.y or 0)
    -- Zygor pins the menu button to an absolute frame level; keep both
    -- buttons above our header bar.
    local headerLevel = self.panel.headerFrame:GetFrameLevel()
    if button:GetFrameLevel() <= headerLevel then button:SetFrameLevel(headerLevel + 2) end
end

local function RestoreTitleButton(button)
    local skin = skins[button]
    if not (skin and skin.on) then return end
    skin.on = false
    skin.art:Hide()
    skin.glow:Hide()
    SetZygorArtShown(button, true)
    if button.ApplySkin then button:ApplySkin() end   -- Zygor's own size and highlight alpha
    local saved = skin.saved
    if saved then
        button:ClearAllPoints()
        for _, p in ipairs(saved.points) do button:SetPoint(unpack(p)) end
        if saved.level then button:SetFrameLevel(saved.level) end
        skin.saved = nil
    end
end

local function ApplyTitleButtons(controls)
    local on = XpieStyle() and module.panel ~= nil
    for key, spec in pairs(BUTTON_STYLES) do
        local button = controls[key]
        if button then
            GetSkin(button, spec)
            if on then module:StyleTitleButton(button) else RestoreTitleButton(button) end
        end
    end
end

-- ---------------------------------------------------------------------------
-- Module hooks (called by the core)
-- ---------------------------------------------------------------------------
-- ---------------------------------------------------------------------------
-- Guide tabs (XpieHUD style): Blizzard's chat tabs (ChatTabArtTemplate in
-- Blizzard_ChatFrameBase, 12.1.5), the HUD's own tab style.
--   background  ChatFrameTab-BG{Left,Mid,Right}           40% unless selected
--   selected    ChatFrameTab-Selected{Left,Mid,Right}     ADD, selected tab only
--   hover       ChatFrameTab-Highlight{Left,Mid,Right}    ADD, HIGHLIGHT layer
-- The chat art is drawn for 32px-tall tabs with 16px ends; Zygor's tabs are
-- 20px, so the ends scale with the tab height. Zygor's own tab decoration,
-- separators and backdrops are hidden (alpha / transparent backdrop) and
-- Zygor's tab objects (ZGV.Tabs, methods via metatable) are hooked so new,
-- moved and reselected tabs stay styled.
-- ---------------------------------------------------------------------------
local TAB_ART = "Interface\\ChatFrame\\ChatFrameTab-"
local TAB_INACTIVE_ALPHA = 0.4   -- Blizzard's CHAT_FRAME_TAB_NORMAL_NOMOUSE_ALPHA
local tabSkins = {}              -- [tab] = { bg, sel, hl (triples), font = {Zygor's} }

local function MakeTabTriple(button, kind, layer, blend)
    local triple = {}
    for i, part in ipairs({ "Left", "Mid", "Right" }) do
        local tx = button:CreateTexture(nil, layer, nil, 7)
        tx:SetTexture(TAB_ART .. kind .. part)
        if blend then tx:SetBlendMode(blend) end
        tx:Hide()
        triple[i] = tx
    end
    return triple
end

local function LayoutTabTriple(triple, button)
    local h = button:GetHeight()
    if not h or h <= 0 then h = 20 end
    local w = math.floor(16 * h / 32 + 0.5)   -- chat tab ends: 16 wide at 32 tall
    local left, mid, right = triple[1], triple[2], triple[3]
    left:ClearAllPoints();  left:SetPoint("BOTTOMLEFT", button, "BOTTOMLEFT", -1, 0);   left:SetSize(w, h)
    right:ClearAllPoints(); right:SetPoint("BOTTOMRIGHT", button, "BOTTOMRIGHT", 1, 0); right:SetSize(w, h)
    mid:ClearAllPoints()
    mid:SetPoint("TOPLEFT", left, "TOPRIGHT")
    mid:SetPoint("BOTTOMRIGHT", right, "BOTTOMLEFT")
end

local function SetTripleShown(triple, shown, alpha)
    for _, tx in ipairs(triple) do
        tx:SetShown(shown)
        if alpha then tx:SetAlpha(alpha) end
    end
end

local function ZygorTabArt(tab)
    return { tab.DecorLeft, tab.DecorMiddle, tab.DecorRight, tab.Separator }
end

local function StyleTab(tab)
    local button = tab.Button
    if not button then return end
    local skin = tabSkins[tab]
    if not skin then
        skin = {
            bg  = MakeTabTriple(button, "BG", "BACKGROUND"),
            sel = MakeTabTriple(button, "Selected", "BACKGROUND", "ADD"),
            hl  = MakeTabTriple(button, "Highlight", "HIGHLIGHT", "ADD"),
        }
        tabSkins[tab] = skin
        HookChrome(button)
        if tab.ButtonsContainer then HookChrome(tab.ButtonsContainer) end
    end
    skin.on = true

    for _, tx in pairs(ZygorTabArt(tab)) do tx:SetAlpha(0) end
    ClearBackdrop(button)
    if tab.ButtonsContainer then ClearBackdrop(tab.ButtonsContainer) end

    for _, triple in ipairs({ skin.bg, skin.sel, skin.hl }) do LayoutTabTriple(triple, button) end
    local active = tab.isActive and true or false
    SetTripleShown(skin.bg, true, active and 1 or TAB_INACTIVE_ALPHA)
    SetTripleShown(skin.sel, active)
    SetTripleShown(skin.hl, true)

    if tab.Text then
        if not skin.font then skin.font = { tab.Text:GetFont() } end
        local _, size, flags = tab.Text:GetFont()
        tab.Text:SetFont(STANDARD_TEXT_FONT, size or 12, flags or "")
        local r, g, b = NORMAL_FONT_COLOR:GetRGB()
        tab.Text:SetTextColor(r, g, b, active and 1 or 0.6)
    end
end

local function RestoreTab(tab)
    local skin = tabSkins[tab]
    if not (skin and skin.on) then return end
    skin.on = false
    for _, triple in ipairs({ skin.bg, skin.sel, skin.hl }) do SetTripleShown(triple, false) end
    for _, tx in pairs(ZygorTabArt(tab)) do tx:SetAlpha(1) end
    if tab.Text and skin.font and skin.font[1] then
        tab.Text:SetFont(skin.font[1], skin.font[2], skin.font[3] or "")
    end
end

local restyling = false
local function StyleAllTabs()
    local Tabs = _G.ZGV and _G.ZGV.Tabs
    if restyling or not (Tabs and Tabs.Pool) then return end
    restyling = true
    local on = XpieStyle()
    local restored = false
    for _, tab in pairs(Tabs.Pool) do
        if on then
            StyleTab(tab)
        elseif tabSkins[tab] and tabSkins[tab].on then
            RestoreTab(tab)
            restored = true
        end
    end
    -- Let Zygor repaint its own tab colours (backdrops, active tab, text).
    if restored and Tabs.ApplySkin then Tabs:ApplySkin() end
    restyling = false
end

local tabsHooked = false
local function HookTabs()
    local Tabs = _G.ZGV and _G.ZGV.Tabs
    if tabsHooked or not Tabs then return end
    tabsHooked = true
    for _, method in ipairs({ "ApplySkin", "SetAsCurrent", "ReanchorTabs" }) do
        if Tabs[method] then hooksecurefunc(Tabs, method, StyleAllTabs) end
    end
end

-- ---------------------------------------------------------------------------
-- Font (XpieHUD style)
-- Zygor draws with its own Open Sans (ZGV.Font / ZGV.FontBold, from its
-- localisation: Skins\OpenSans.TTF). The native UI and the Objective Tracker
-- use STANDARD_TEXT_FONT (Friz Quadrata in English). The guide's step text
-- reads ZGV.Font live each time it draws, so swapping it converts the guide.
-- Some Zygor files copy the font once at load (step number, tabs, menus):
-- the step number is set directly below; tabs are styled separately.
-- ---------------------------------------------------------------------------
local zygorFont, zygorFontBold   -- Zygor's own fonts, for the Original style

local function ApplyFont()
    local ZGV = _G.ZGV
    if not ZGV then return false end
    if not zygorFont then zygorFont, zygorFontBold = ZGV.Font, ZGV.FontBold end
    local native = XpieStyle() and STANDARD_TEXT_FONT
    local font, bold = native or zygorFont, native or zygorFontBold
    if ZGV.Font == font and ZGV.FontBold == bold then return false end
    ZGV.Font, ZGV.FontBold = font, bold
    return true
end

local function ApplyStepNumberFont(frame)
    local step = frame and frame.Controls and frame.Controls.StepNum and frame.Controls.StepNum.Step
    if not (step and XpieStyle()) then return end
    local _, size, flags = step:GetFont()
    step:SetFont(STANDARD_TEXT_FONT, size or 12, flags or "")
end

local frameHooked = false
local stripped = false

function module:Apply()
    local ZGV = _G.ZGV
    if not ZGV then return end
    RegisterArrowSkin()
    HookStepMixin()
    local fontChanged = ApplyFont()

    local frame = ZGV.Frame
    if frame and frame.ApplySkin and not frameHooked then
        frameHooked = true
        hooksecurefunc(frame, "ApplySkin", function()
            if not StripOn() then return end
            StripChrome()
            ForEachStep(StyleStep)
            ApplyStepNumberFont(frame)
        end)
    end

    if frame then
        for _, f in ipairs(ChromeFrames()) do HookChrome(f) end
        ForEachStep(HookStepInstance)

        if StripOn() then
            StripChrome()
            ForEachStep(StyleStep)
            stripped = true
        elseif stripped then
            -- Let Zygor repaint its own skin and step colours.
            stripped = false
            SetLogoShown(true)
            frame:ApplySkin()
            if ZGV.UpdateFrame then ZGV:UpdateFrame(true) end
            fontChanged = false   -- already redrawn
        end

        -- Native font: step number (cached by Zygor at load), then redraw the
        -- guide so its step text picks up the swapped ZGV.Font.
        ApplyStepNumberFont(frame)
        if fontChanged and ZGV.UpdateFrame then ZGV:UpdateFrame(true) end

        -- XpieHUD background panel, anchored to the guide window so it
        -- resizes with it (Zygor's own window background is transparent).
        self.panel = self.panel or core:CreatePanel()
        self.panel:Attach(frame)
        -- Gold header bar laid over Zygor's own title bar, title after the gear.
        local titleBar = (frame.Controls and frame.Controls.TitleBar) or (frame.Border and frame.Border.TitleBar)
        if titleBar then self.panel:SetHeaderAnchor(titleBar) end
        self.panel:SetTitleInsets(TITLE_LEFT, TITLE_RIGHT)
        self.panel:SetStyle(self.db.panel)
        self.panel:SetActive(XpieStyle())

        if frame.Controls then ApplyTitleButtons(frame.Controls) end
        HookTabs()
        StyleAllTabs()
    end

    ApplyArrow()
end

-- Zygor starts up in a background thread after login; catch its window and
-- arrow once they exist.
function module:OnLogin()
    for _, delay in ipairs({ 1, 3, 6, 12 }) do
        C_Timer.After(delay, function()
            if core.ready then module:Apply() end
        end)
    end
end

-- Frames the quest window's "Guide Addons" fade group may fade. Independent of
-- the style: fading is the quest window's job (its own checkbox), and the
-- background panel lives in ZygorGuidesViewerFrameMaster so it fades too.
function module:GetFadeFrames()
    if not _G.ZGV then return {} end
    local list = {}
    for _, name in ipairs({ "ZygorGuidesViewerFrameMaster", "ZygorGuidesViewerPointer_ArrowCtrl" }) do
        if _G[name] then list[#list + 1] = _G[name] end
    end
    return list
end

function module:BuildSettings(page)
    page:Status(function()
        return C_AddOns.IsAddOnLoaded("ZygorGuidesViewer") and "" or "(Zygor Guides Viewer not loaded)"
    end)
    page:Note("Choose Zygor's original look, or the XpieHUD style: transparent Zygor window and logo, gold waypoint arrow, and a native dark panel behind the guide. Disable the XpieHUD_Zygor addon to remove this page completely.")
    page:Dropdown({
        key = "style", label = "Style",
        values = function()
            return {
                { key = "xpiehud",  label = "XpieHUD" },
                { key = "original", label = "Original (leave Zygor's look alone)" },
            }
        end,
    })
    page:Space(6)

    page:Header("XpieHUD Style")
    page:Checkbox({ key = "goldArrow", label = "Gold Waypoint Arrow", description = "Use the XpieHUD gold arrowhead as Zygor's arrow skin (also selectable as \"XpieHUD Gold\" in Zygor's own options)." })
    page:Slider({ key = "stepAlpha", label = "Step Box Opacity", description = "Tint behind each guide step. Zygor's colours are kept (dark normal, green complete, red unavailable).", min = 0, max = 100, step = 5, format = "%d%%" })
    page:Space(6)

    page:PanelStyle(function() return module.db.panel end)
end

-- ---------------------------------------------------------------------------
-- Hook Zygor as it loads: register the arrow skin and hook the step mixin
-- before Zygor builds its window.
-- ---------------------------------------------------------------------------
local function OnZygorLoaded()
    if not _G.ZGV then return end
    RegisterArrowSkin()
    HookStepMixin()
    ApplyFont()   -- before Zygor builds its window, so it draws in the native font from the start
end

local loader = CreateFrame("Frame")
loader:RegisterEvent("ADDON_LOADED")
loader:SetScript("OnEvent", function(self, _, name)
    if name == "ZygorGuidesViewer" then
        OnZygorLoaded()
        self:UnregisterEvent("ADDON_LOADED")
    end
end)
-- Zygor normally loads after us (alphabetical); if it somehow loaded first,
-- hook it now.
if C_AddOns.IsAddOnLoaded("ZygorGuidesViewer") then OnZygorLoaded() end

-- ---------------------------------------------------------------------------
-- /xhud arrowdebug: report in chat whenever Zygor's arrow stops drawing our
-- gold sprite (special icon, error icon, another skin's frame showing).
-- Hooks stay installed once added; the toggle only mutes/unmutes them.
-- ---------------------------------------------------------------------------
local arrowDebug = false
local arrowDebugHooked = {}
local lastDebugMsg, lastDebugTime = nil, 0

local function DebugArrow(msg)
    if not arrowDebug then return end
    local now = GetTime()
    if msg == lastDebugMsg and now - lastDebugTime < 1 then return end   -- no spam
    lastDebugMsg, lastDebugTime = msg, now
    local Pointer = _G.ZGV and _G.ZGV.Pointer
    local skin = Pointer and Pointer.CurrentArrowSkin and Pointer.CurrentArrowSkin.id or "?"
    core:Print(("|cffffd200[arrow]|r %s  (active skin: %s)"):format(msg, skin))
end

local function HookArrowFrame(skinId, frame)
    if not frame or arrowDebugHooked[frame] then return end
    arrowDebugHooked[frame] = true
    if frame.ShowSpecial then
        hooksecurefunc(frame, "ShowSpecial", function(_, spec)
            DebugArrow(("%s frame: special icon '%s'"):format(skinId, tostring(spec)))
        end)
    end
    if frame.ShowTraveling then
        hooksecurefunc(frame, "ShowTraveling", function(self)
            if self.xhudLastSpecial ~= false then
                self.xhudLastSpecial = false
                DebugArrow(("%s frame: back to the direction arrow"):format(skinId))
            end
        end)
        hooksecurefunc(frame, "ShowSpecial", function(self) self.xhudLastSpecial = true end)
    end
    frame:HookScript("OnShow", function(self)
        local Pointer = _G.ZGV and _G.ZGV.Pointer
        if Pointer and Pointer.ArrowFrame ~= self then
            DebugArrow(("%s frame SHOWN but it is not the active arrow frame"):format(skinId))
        end
    end)
end

core:RegisterCommand("arrowdebug", function()
    local Pointer = _G.ZGV and _G.ZGV.Pointer
    if not (Pointer and Pointer.ArrowSkins) then
        core:Print("Zygor isn't loaded.")
        return
    end
    for id, skin in pairs(Pointer.ArrowSkins) do
        HookArrowFrame(id, skin.frame)   -- skins create their frame on first use
    end
    arrowDebug = not arrowDebug
    lastDebugMsg = nil
    core:Print("Zygor arrow debug " .. (arrowDebug and "|cff40ff40ON|r: reproduce the problem, then read chat. Run /xhud arrowdebug again to stop."
        or "|cffff4040OFF|r."))
    if arrowDebug then
        local frames = {}
        for id, skin in pairs(Pointer.ArrowSkins) do
            if skin.frame then
                frames[#frames + 1] = ("%s=%s"):format(id, skin.frame:IsShown() and "shown" or "hidden")
            end
        end
        core:Print("Arrow frames: " .. table.concat(frames, ", "))
    end
end, "Report Zygor arrow state changes in chat (troubleshooting)")
