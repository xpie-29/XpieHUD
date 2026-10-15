-- RestedXP.lua  (XpieHUD_RestedXP module)
-- RestedXP Guides' guide window (the classic "V1" window, RXP's default) in
-- the XpieHUD style, matching XpieHUD_Zygor. Style "xpiehud" (default):
--   * an "XpieHUD" RXP theme (RXP's own theme system): native font, no RXP
--     borders, transparent step rows with a faint gold hover, the native
--     dark tooltip colour behind RXP's other boxes (active steps, item and
--     target buttons)
--   * the guide window's own boxes made transparent, with the native panel
--     (XpieHUD_Core Panels.lua) behind it and its gold header bar over the
--     guide title
--   * the guide title in the native gold font, left-aligned after the gear
--   * RXP's cog as the Damage Meter's gold settings gear, at the left of the
--     header bar (still RXP's own button: same menu)
--   * RXP logo, class icon and banners hidden
--   * native minimal scroll bar and settings checkboxes
-- Style "original" puts the player's previous RXP theme and RXP's look back.
--
-- RestedXP internals used (checked against RestedXP Guides v4.11.23, 12.1.5):
--   the addon object, from AceAddon: LibStub("AceAddon-3.0"):GetAddon("RXPGuides")
--   addon:RegisterTheme(theme), addon.themes, addon.settings.profile.activeTheme,
--   addon:ReloadTheme() / addon.RenderFrame(true)   (Themes.lua, GuideWindow.lua)
--   addon.SetStep (hooked: active step boxes and their checkboxes)
--   _G.RXPFrame and its .BottomFrame / .GuideName (.text .bg .icon .classIcon)
--   / .Footer (.bg .cog) / .ScrollFrame / .CurrentStepFrame.framePool,
--   RXPFrame:UpdateVisuals / RXPFrame.UpdateScrollBar          (GuideWindow.lua)
-- RXP's V2 window (a beta option) isn't styled yet.
-- RestedXP is CC BY-NC-SA: nothing here is copied from it, only hooked.
-- RestedXP isn't secure code, so hooking it can't taint Blizzard's UI.

local core = XpieHUD

local THEME_NAME = "XpieHUD"
local MEDIA_DIR  = "Interface\\AddOns\\XpieHUD_RestedXP\\Media\\"
-- RXP's DarkMode art set is complete and neutral; the XpieHUD theme borrows
-- it for anything we don't replace (Textures/DarkMode in RXPGuides).
local RXP_ART    = "Interface/AddOns/RXPGuides/Textures/DarkMode/"

-- The guide window's panel is fixed: the gold header bar titled "RestedXP"
-- (the guide name sits under it) and no background behind the step list.
-- Only the current step boxes below the window get a background.
local WINDOW_PANEL = {
    look = "tracker", opacity = 0, header = true, border = false,
    title = "RestedXP", padding = 5,
}

local module = core:RegisterModule("restedxp", {
    title = "RestedXP Guides",
    defaults = {
        -- "xpiehud": XpieHUD theme + native panel. "original": leave RXP alone.
        style = "xpiehud",
        -- Current step boxes (below the window): background opacity, %, so
        -- they stand out from the step list above (Quest Tracker look).
        -- (3.8.x saved "panel" and "stepOpacity"; no longer used.)
        stepBackground = 25,
        -- prevTheme: the RXP theme to put back for the Original style
    },
})

local function GetRXP()
    local ace = LibStub and LibStub("AceAddon-3.0", true)
    return ace and ace:GetAddon("RXPGuides", true)
end

local function XpieStyle()
    return module.db and module.db.style == "xpiehud" and _G.RXPFrame ~= nil
end

-- ---------------------------------------------------------------------------
-- The XpieHUD theme (RXP's theme format, Themes.lua). Colours that RXP paints
-- with SetBackdropColor come from here, so they need no hooks:
--   background            RXP's boxes: the native dark tooltip colour, at the
--                         panel opacity (the main window's own boxes are made
--                         transparent below; the panel shows through)
--   bottomFrameBG         step list rows: transparent
--   bottomFrameHighlight  step list row under the mouse: faint gold
--   edges                 RXP's borders: a transparent texture (Media/blank)
-- ---------------------------------------------------------------------------
local ROW_HOVER_ALPHA = 0.15

local function TooltipColor()
    local c = TOOLTIP_DEFAULT_BACKGROUND_COLOR
    if c then return c:GetRGB() end
    return 0.09, 0.09, 0.19
end

local theme
local function BuildTheme()
    local gr, gg, gb = NORMAL_FONT_COLOR:GetRGB()
    local tr, tg, tb = TooltipColor()
    local text = _G.OBJECTIVE_TRACKER_COLOR and _G.OBJECTIVE_TRACKER_COLOR.Normal
    theme = {
        name = THEME_NAME,
        displayName = "XpieHUD (native)",
        author = "XpieHUD",
        applicable = true,
        background = { tr, tg, tb, 0.8 },
        bottomFrameBG = { 0, 0, 0, 0 },
        bottomFrameHighlight = { gr, gg, gb, ROW_HOVER_ALPHA },
        mapPins = { gr, gg, gb, 1 },
        tooltip = "|cffffd200",
        texturePath = RXP_ART,
        headerTexture = "rxp-banner",
        font = STANDARD_TEXT_FONT,
        textColor = text and { text.r, text.g, text.b } or { 0.8, 0.8, 0.8 },
        bgTextures = { edge = "Interface/BUTTONS/WHITE8X8", bottom = "Interface/BUTTONS/WHITE8X8" },
        edges = { edge = MEDIA_DIR .. "blank", guideName = MEDIA_DIR .. "blank" },
    }
    return theme
end

-- RXP's other boxes (item and target buttons) look like the current step
-- boxes: black (the Quest Tracker background is a black fade), at the
-- current step opacity.
local function UpdateThemeBackground()
    if not theme then return false end
    local r, g, b = 0, 0, 0
    local a = (module.db.stepBackground or 25) / 100
    local bg = theme.background
    if bg[1] == r and bg[2] == g and bg[3] == b and bg[4] == a then return false end
    bg[1], bg[2], bg[3], bg[4] = r, g, b, a
    return true
end

local function ReloadRXPTheme(rxp)
    local profile = rxp.settings and rxp.settings.profile
    if rxp.ReloadTheme and profile and profile.enableThemeLiveReload then
        rxp:ReloadTheme()
    elseif rxp.RenderFrame then
        rxp.RenderFrame(true)
    end
end

-- Registers the theme and switches RXP to it (or back to the player's own
-- theme for the Original style). Returns true when RXP was re-themed.
local function ApplyTheme()
    local rxp = GetRXP()
    local profile = rxp and rxp.settings and rxp.settings.profile
    if not (profile and rxp.RegisterTheme and rxp.themes) then return false end
    if not rxp.themes[THEME_NAME] then rxp:RegisterTheme(theme or BuildTheme()) end
    theme = rxp.themes[THEME_NAME]

    local db = module.db
    local want = XpieStyle()
    local changed = UpdateThemeBackground() and profile.activeTheme == THEME_NAME
    if want and profile.activeTheme ~= THEME_NAME then
        db.prevTheme = profile.activeTheme
        profile.activeTheme = THEME_NAME
        changed = true
    elseif not want and profile.activeTheme == THEME_NAME then
        local prev = db.prevTheme
        if not (prev and (rxp.themes[prev] or prev == "Default")) then prev = "RXP Blue" end
        profile.activeTheme = prev
        changed = true
    end
    if changed then ReloadRXPTheme(rxp) end
    return changed
end

-- ---------------------------------------------------------------------------
-- Guide window chrome: RXP's boxes transparent (it repaints them on every
-- theme reload, so its colour calls are post-hooked), its banners, logo and
-- class icon hidden by alpha (RXP only ever sets their image).
-- ---------------------------------------------------------------------------
local clearing = false
local hookedChrome = {}

local function ClearBackdrop(f)
    if not (f and f.GetBackdropColor) then return end
    clearing = true
    local r, g, b = f:GetBackdropColor()
    if r then f:SetBackdropColor(r, g, b, 0) end
    local br, bg, bb = f:GetBackdropBorderColor()
    if br then f:SetBackdropBorderColor(br, bg, bb, 0) end
    clearing = false
end

local function HookChrome(f)
    if not f or hookedChrome[f] or not f.SetBackdropColor then return end
    hookedChrome[f] = true
    local function reclear(self)
        if clearing or not XpieStyle() then return end
        ClearBackdrop(self)
    end
    hooksecurefunc(f, "SetBackdropColor", reclear)
    hooksecurefunc(f, "SetBackdropBorderColor", reclear)
end

local function ChromeFrames()
    local f = _G.RXPFrame
    return { f.BottomFrame, f.GuideName, f.Footer }
end

local function BrandingTextures()
    local f = _G.RXPFrame
    local name, footer = f.GuideName, f.Footer
    -- footer.icon is the resize grip: invisible, but still drags to resize.
    return { name and name.bg, name and name.icon, name and name.classIcon,
             footer and footer.bg, footer and footer.icon }
end

local function ApplyChrome(on)
    for _, f in ipairs(ChromeFrames()) do
        HookChrome(f)
        if on then ClearBackdrop(f) end
    end
    for _, tx in ipairs(BrandingTextures()) do
        if tx then tx:SetAlpha(on and 0 or 1) end
    end
end

-- ---------------------------------------------------------------------------
-- Guide name: on its own line just under the header bar (the bar carries the
-- panel's title, after the gear), like the guide tab under Zygor's title.
-- Native gold font at the size of the guide tab in the Zygor module
-- (Zygor's 12pt tab text at Zygor's window scale), left-aligned with the step text, one
-- line: RXP's two-line name ("Guide\n(1-90) Default") is joined with a
-- space and truncated if the window is narrow. RXP sets its own font, colour
-- and text on setup, theme changes and guide loads; those calls are
-- post-hooked. The step list starts below the name line.
-- ---------------------------------------------------------------------------
local GEAR_SIZE, GEAR_X, GEAR_Y = 27, 4, -2   -- as XpieHUD_Zygor (Blizzard's Damage Meter gear)
local TITLE_LEFT  = GEAR_X + GEAR_SIZE + 5    -- panel title on the header bar
local TITLE_RIGHT = 8
local NAME_X      = 7     -- guide name inset: Blizzard's tracker title inset
local NAME_GAP    = 2     -- header bar to guide name
-- Guide name size as it appears on screen: Zygor's guide tab text when
-- Zygor is loaded (its font size x its window's scale), otherwise this, at
-- the UI's scale. RXP has its own window scale, so the size is converted.
local NAME_SIZE_FALLBACK = 10

local function ZygorTabText()
    local tabs = _G.ZGV and _G.ZGV.Tabs and _G.ZGV.Tabs.Pool
    if not tabs then return end
    for _, tab in pairs(tabs) do
        if tab.Text and tab.Text.GetFont and tab.Text:GetFont() then return tab.Text end
    end
end

local function NameFontSize(text)
    local scale = text:GetEffectiveScale()
    if not scale or scale <= 0 then return NAME_SIZE_FALLBACK end
    local ref = ZygorTabText()
    local _, refSize = ref and ref:GetFont()
    if refSize then
        return refSize * ref:GetEffectiveScale() / scale
    end
    return NAME_SIZE_FALLBACK * UIParent:GetEffectiveScale() / scale
end

local nameLine = 12   -- the name line's height, set with the font
local LIST_GAP    = 4     -- guide name to step list
local RXP_TITLE_LEFT, RXP_TITLE_SIZE = 29, 11   -- RXP's own (GuideWindow.lua)

local styling = false

local function OneLine(value)
    return (value:gsub("%s*\n%s*", " "))
end

local function StyleTitle(text)
    if styling then return end
    styling = true
    local name = _G.RXPFrame.GuideName
    if XpieStyle() then
        -- An explicit size: RXP sets one with SetFont, which a font object
        -- (SetFontObject) doesn't override.
        local size = NameFontSize(text)
        text:SetFont(STANDARD_TEXT_FONT, size, "")
        nameLine = math.ceil(size) + 2
        text:SetTextColor(NORMAL_FONT_COLOR:GetRGB())
        text:SetShadowColor(0, 0, 0, 1)
        text:SetShadowOffset(1, -1)
        text:ClearAllPoints()
        text:SetPoint("TOPLEFT", name, "BOTTOMLEFT", NAME_X, -NAME_GAP)
        text:SetPoint("RIGHT", name, "RIGHT", -TITLE_RIGHT, 0)
        text:SetJustifyH("LEFT")
        text:SetJustifyV("TOP")
        text:SetWordWrap(false)
        text:SetMaxLines(1)
        local raw = text.xhudRaw or text:GetText()
        text.xhudRaw = raw
        if raw then text:SetText(OneLine(raw)) end
        text.xhudStyled = true
    elseif text.xhudStyled then
        text.xhudStyled = nil
        local rxp = GetRXP()
        local color = rxp and rxp.activeTheme and rxp.activeTheme.textColor
        text:SetFont((rxp and rxp.font) or STANDARD_TEXT_FONT, RXP_TITLE_SIZE, "")
        if color then text:SetTextColor(unpack(color)) end
        text:ClearAllPoints()
        text:SetPoint("LEFT", name, RXP_TITLE_LEFT, 0)
        text:SetPoint("RIGHT", name, 0, 0)
        text:SetJustifyH("CENTER")
        text:SetJustifyV("MIDDLE")
        text:SetWordWrap(true)
        text:SetMaxLines(0)
        if text.xhudRaw then text:SetText(text.xhudRaw) end
    end
    styling = false
end

local titleHooked = false
local function ApplyTitle()
    local name = _G.RXPFrame.GuideName
    local text = name and name.text
    if not text then return end
    if not titleHooked then
        titleHooked = true
        local function restyle() if XpieStyle() then StyleTitle(text) end end
        hooksecurefunc(text, "SetFont", restyle)
        hooksecurefunc(text, "SetTextColor", restyle)
        -- RXP's new text is remembered as given (for the Original style),
        -- then shown on one line.
        hooksecurefunc(text, "SetText", function(self, value)
            if styling then return end
            self.xhudRaw = value
            if XpieStyle() then StyleTitle(self) end
        end)
    end
    StyleTitle(text)
end

-- ---------------------------------------------------------------------------
-- Step list top: RXP lets its title box overlap the list by 9px (its banner
-- covered the rows scrolling under it). The list now starts below the guide
-- name line instead.
-- ---------------------------------------------------------------------------
local function ApplyListTop(on)
    local f = _G.RXPFrame
    local scroll, name = f.ScrollFrame, f.GuideName
    if not (scroll and name and scroll.GetPointByName) then return end
    if not scroll.xhudTop then
        local point, rel, relPoint, x, y = scroll:GetPointByName("TOPLEFT")
        if not point then return end
        scroll.xhudTop = { point, rel, relPoint, x, y }
    end
    local saved = scroll.xhudTop
    if on then
        scroll:SetPoint("TOPLEFT", name, "BOTTOMLEFT", saved[4] or 0, -(NAME_GAP + nameLine + LIST_GAP))
    else
        scroll:SetPoint(unpack(saved))
    end
end

-- Footer version line ("RestedXP Guides v4.11.23"): kept, in Blizzard's
-- quiet grey like other secondary text. RXP colours it on setup and theme
-- changes; post-hooked.
local function ApplyFooterText()
    local text = _G.RXPFrame.Footer and _G.RXPFrame.Footer.text
    if not text then return end
    local function restyle()
        if styling then return end
        styling = true
        if XpieStyle() then
            text:SetTextColor(GRAY_FONT_COLOR:GetRGB())
            text.xhudStyled = true
        elseif text.xhudStyled then
            text.xhudStyled = nil
            local rxp = GetRXP()
            local color = rxp and rxp.activeTheme and rxp.activeTheme.textColor
            if color then text:SetTextColor(unpack(color)) end
        end
        styling = false
    end
    if not text.xhudHooked then
        text.xhudHooked = true
        hooksecurefunc(text, "SetTextColor", restyle)
    end
    restyle()
end

-- ---------------------------------------------------------------------------
-- Settings gear: RXP's cog stays the real button (its menu, its tooltip).
-- Its art is hidden by alpha and our gear art drawn on it; it moves from the
-- footer to the left end of the header bar, like the Zygor module's menu gear.
-- ---------------------------------------------------------------------------
local GEAR = {
    normal = "common-dropdown-a-button-settings-shadowless",
    pushed = "common-dropdown-a-button-settings-pressed-shadowless",
    hover  = "common-dropdown-a-button-settings-hover-shadowless",
}
local gearSkin

local function SetRXPCogArtShown(cog, shown)
    for _, tx in ipairs({ cog:GetNormalTexture(), cog:GetPushedTexture(), cog:GetHighlightTexture() }) do
        if tx then tx:SetAlpha(shown and 1 or 0) end
    end
end

local function ApplyGear(panel)
    local cog = _G.RXPFrame.Footer and _G.RXPFrame.Footer.cog
    if not cog then return end
    if not gearSkin then
        local art = cog:CreateTexture(nil, "ARTWORK")
        art:SetAllPoints()
        art:SetAtlas(GEAR.normal)
        local glow = cog:CreateTexture(nil, "HIGHLIGHT")
        glow:SetAllPoints()
        glow:SetAtlas(GEAR.hover)
        local points = {}
        for i = 1, cog:GetNumPoints() do points[i] = { cog:GetPoint(i) } end
        gearSkin = { art = art, glow = glow, points = points,
                     w = cog:GetWidth(), h = cog:GetHeight(), level = cog:GetFrameLevel() }
        cog:HookScript("OnMouseDown", function()
            if gearSkin.on then art:SetAtlas(GEAR.pushed) end
        end)
        cog:HookScript("OnMouseUp", function() art:SetAtlas(GEAR.normal) end)
    end

    local on = XpieStyle() and panel ~= nil
    gearSkin.on = on
    gearSkin.art:SetShown(on)
    gearSkin.glow:SetShown(on)
    SetRXPCogArtShown(cog, not on)
    cog:ClearAllPoints()
    if on then
        cog:SetSize(GEAR_SIZE, GEAR_SIZE)
        cog:SetPoint("LEFT", panel.headerFrame, "LEFT", GEAR_X, GEAR_Y)
        local headerLevel = panel.headerFrame:GetFrameLevel()
        if cog:GetFrameLevel() <= headerLevel then cog:SetFrameLevel(headerLevel + 2) end
    else
        cog:SetSize(gearSkin.w, gearSkin.h)
        for _, p in ipairs(gearSkin.points) do cog:SetPoint(unpack(p)) end
        cog:SetFrameLevel(gearSkin.level)
    end
end

-- ---------------------------------------------------------------------------
-- Scroll bar: Blizzard's minimal scroll bar (MinimalScrollBar.xml: 17x11
-- arrow steppers, an 8px three-piece thumb) on RXP's UIPanelScrollFrame.
-- RXP's buttons stay the real buttons. Their own state textures can't take
-- the art: the template crops them (UIPanelScrollBarButton TexCoords
-- .2-.8 / .25-.75), which cut the arrows and blew them up. So those are
-- hidden by alpha and our textures drawn on the buttons instead. Everything
-- is sized in the UI's scale, so it matches Blizzard's own scroll bars
-- whatever scale RXP's window has.
-- ---------------------------------------------------------------------------
local SCROLL_ARROWS = {
    ScrollUpButton   = { normal = "minimal-scrollbar-arrow-top", over = "minimal-scrollbar-arrow-top-over", down = "minimal-scrollbar-arrow-top-down" },
    ScrollDownButton = { normal = "minimal-scrollbar-arrow-bottom", over = "minimal-scrollbar-arrow-bottom-over", down = "minimal-scrollbar-arrow-bottom-down" },
}
local ARROW_W, ARROW_H = 17, 11   -- Blizzard's stepper size
local THUMB_W = 8                 -- Blizzard's thumb width
local SCROLL_THUMB = {
    top    = "minimal-scrollbar-small-thumb-top",
    middle = "minimal-scrollbar-small-thumb-middle",
    bottom = "minimal-scrollbar-small-thumb-bottom",
}
local RXP_BUTTON_ART = { "Normal", "Pushed", "Disabled", "Highlight" }

local function ScrollBar()
    return _G.RXPFrame.ScrollFrame and _G.RXPFrame.ScrollFrame.ScrollBar
end

-- UI units -> the region's own units.
local function UIScale(region)
    local s = region:GetEffectiveScale()
    return (s and s > 0) and UIParent:GetEffectiveScale() / s or 1
end

local function ArrowSkin(button, art)
    if button.xhudArrow then return button.xhudArrow end
    local skin = { art = art, on = false, down = false }
    skin.tex = button:CreateTexture(nil, "ARTWORK", nil, 2)
    skin.tex:SetPoint("CENTER")
    skin.glow = button:CreateTexture(nil, "HIGHLIGHT")
    skin.glow:SetPoint("CENTER")
    skin.glow:SetAtlas(art.over, false)
    function skin.Update()
        local shown = skin.on
        skin.tex:SetShown(shown)
        skin.glow:SetShown(shown)
        if not shown then return end
        local k = UIScale(button)
        skin.tex:SetSize(ARROW_W * k, ARROW_H * k)
        skin.glow:SetSize(ARROW_W * k, ARROW_H * k)
        local enabled = button:IsEnabled()
        skin.tex:SetAtlas((enabled and skin.down) and art.down or art.normal, false)
        skin.tex:SetDesaturated(not enabled)
        skin.tex:SetAlpha(enabled and 1 or 0.5)
    end
    button:HookScript("OnMouseDown", function() skin.down = true; skin.Update() end)
    button:HookScript("OnMouseUp", function() skin.down = false; skin.Update() end)
    button:HookScript("OnEnable", skin.Update)
    button:HookScript("OnDisable", skin.Update)
    button:HookScript("OnShow", skin.Update)
    button.xhudArrow = skin
    return skin
end

local function ThumbPieces(bar, thumb)
    if bar.xhudThumb then return bar.xhudThumb end
    local pieces = {}
    for key, atlas in pairs(SCROLL_THUMB) do
        local tx = bar:CreateTexture(nil, "OVERLAY", nil, 1)
        tx:SetAtlas(atlas, false)
        pieces[key] = tx
    end
    pieces.top:SetPoint("TOP", thumb, "TOP")
    pieces.bottom:SetPoint("BOTTOM", thumb, "BOTTOM")
    pieces.middle:SetPoint("TOPLEFT", pieces.top, "BOTTOMLEFT")
    pieces.middle:SetPoint("BOTTOMRIGHT", pieces.bottom, "TOPRIGHT")
    -- Shown while styled and while the scroll bar shows its thumb; caps at
    -- their atlas size, in the UI's scale.
    function pieces.Sync()
        local shown = (bar.xhudStyled and thumb:IsShown()) and true or false
        local k = UIScale(bar)
        for _, key in ipairs({ "top", "bottom" }) do
            local info = C_Texture.GetAtlasInfo(SCROLL_THUMB[key])
            pieces[key]:SetSize(THUMB_W * k, ((info and info.height) or 4) * k)
        end
        for _, key in ipairs({ "top", "middle", "bottom" }) do pieces[key]:SetShown(shown) end
    end
    hooksecurefunc(thumb, "Show", pieces.Sync)
    hooksecurefunc(thumb, "Hide", pieces.Sync)
    hooksecurefunc(thumb, "SetShown", pieces.Sync)
    bar.xhudThumb = pieces
    return pieces
end

local function SetRXPScrollArtShown(bar, shown)
    for key in pairs(SCROLL_ARROWS) do
        local button = bar[key]
        for _, field in ipairs(RXP_BUTTON_ART) do
            local tx = button and button[field]
            if tx then tx:SetAlpha(shown and 1 or 0) end
        end
    end
    local thumb = bar:GetThumbTexture()
    if thumb then thumb:SetAlpha(shown and 1 or 0) end
end

local function StyleScrollBar()
    if not XpieStyle() then return end   -- Original: RXP's UpdateScrollBar has just painted its own
    local bar = ScrollBar()
    if not (bar and C_Texture.GetAtlasInfo(SCROLL_THUMB.middle)) then return end
    bar.xhudStyled = true
    SetRXPScrollArtShown(bar, false)
    for key, art in pairs(SCROLL_ARROWS) do
        local button = bar[key]
        if button then
            local skin = ArrowSkin(button, art)
            skin.on = true
            skin.Update()
        end
    end
    local thumb = bar:GetThumbTexture()
    if thumb then ThumbPieces(bar, thumb).Sync() end
end

-- Original style: our art off, RXP's back.
local function RestoreScrollBar()
    local bar = ScrollBar()
    if not (bar and bar.xhudStyled) then return end
    bar.xhudStyled = nil
    for key in pairs(SCROLL_ARROWS) do
        local skin = bar[key] and bar[key].xhudArrow
        if skin then
            skin.on = false
            skin.Update()
        end
    end
    if bar.xhudThumb then bar.xhudThumb.Sync() end
    SetRXPScrollArtShown(bar, true)
end

-- ---------------------------------------------------------------------------
-- Active step checkboxes: Blizzard's settings checkbox (checkbox-minimal /
-- checkmark-minimal). RXP only re-textures them when the theme changes, after
-- which our SetStep post-hook runs again.
-- ---------------------------------------------------------------------------
-- RXP gives every state a texture (SetNormalTexture etc.), so each exists and
-- takes the atlas directly.
local CHECKBOX_ART = {
    GetNormalTexture         = "checkbox-minimal",
    GetCheckedTexture        = "checkmark-minimal",
    GetDisabledCheckedTexture = "checkmark-minimal-disabled",
}

local function StyleCheckbox(button)
    if XpieStyle() then
        for getter, atlas in pairs(CHECKBOX_ART) do
            local tx = button[getter] and button[getter](button)
            if tx then tx:SetAtlas(atlas, false) end
        end
        button.xhudStyled = true
    elseif button.xhudStyled then
        button.xhudStyled = nil
        button.theme = nil   -- RXP re-textures it on its next SetStep
    end
end

-- Each active step box gets the guide window's panel body (no header bar,
-- no title) behind it instead of RXP's flat colour, so the steps read as
-- part of the same HUD, at their own opacity (Current Step Background). RXP's own box and its title tab go transparent.
local stepPanels = {}

local STEP_PADDING = WINDOW_PANEL.padding - 2   -- a touch tighter than the window's

local function StepPanelStyle()
    local style = CopyTable(WINDOW_PANEL)
    style.header, style.title = false, ""
    style.opacity = module.db.stepBackground or 25
    style.padding = STEP_PADDING
    return style
end

-- RXP's title tab ("Step 3") sits 5px above the step box (GuideWindow.lua:
-- number frame at TOPLEFT 7, 5). The panel goes behind a holder that reaches
-- above the tab, so the background frames the title with room to spare.
local STEP_TAB_RISE = 5   -- RXP's
local STEP_TOP_PAD  = 4   -- extra room above the tab, inside the background

local function StepPanelHolder(stepframe)
    if stepframe.xhudHolder then return stepframe.xhudHolder end
    local holder = CreateFrame("Frame", nil, stepframe)
    holder:SetPoint("TOPLEFT", stepframe, "TOPLEFT", 0, STEP_TAB_RISE + STEP_TOP_PAD)
    holder:SetPoint("BOTTOMRIGHT", stepframe, "BOTTOMRIGHT")
    holder:EnableMouse(false)
    stepframe.xhudHolder = holder
    return holder
end

-- With that taller background, the step boxes move away from the guide
-- window so the two never touch: RXP anchors its step area just below the
-- window (or just above the title, near the top of the screen); post-hooked
-- and pushed out by the room the background needs.
local STEP_GAP = 18   -- tab rise 5 + room 4 + background padding, + a few px from the window

local function SpaceStepArea(frame, point, rel, relPoint, x, y)
    if frame.xhudSpacing or type(point) ~= "string" then return end
    if type(rel) ~= "table" then return end   -- only RXP's relative anchors
    frame.xhudSpacing = true
    local shift = 0
    if XpieStyle() then
        shift = point:find("^TOP") and -STEP_GAP or (point:find("^BOTTOM") and STEP_GAP or 0)
    end
    frame:SetPoint(point, rel, relPoint, x or 0, (y or 0) + shift)
    frame.xhudSpacing = false
end

local function StyleStepBox(stepframe, on, style)
    HookChrome(stepframe)
    HookChrome(stepframe.number)
    if on then
        ClearBackdrop(stepframe)
        ClearBackdrop(stepframe.number)
    end
    local panel = stepPanels[stepframe]
    if on and not panel then
        panel = core:CreatePanel()
        panel:Attach(StepPanelHolder(stepframe))
        stepPanels[stepframe] = panel
    end
    if panel then
        panel:SetStyle(style)
        panel:SetActive(on)
    end
end

local function StyleActiveSteps()
    local current = _G.RXPFrame.CurrentStepFrame
    local pool = current and current.framePool
    if not pool then return end
    local on = XpieStyle()
    local checkboxes = C_Texture.GetAtlasInfo("checkbox-minimal") ~= nil
    local style = StepPanelStyle()
    for _, stepframe in pairs(pool) do
        StyleStepBox(stepframe, on, style)
        if checkboxes then
            for _, element in pairs(stepframe.elements or {}) do
                if element.button then StyleCheckbox(element.button) end
            end
        end
        -- The step's title tab ("Step 3"): native gold. RXP colours it only
        -- when it creates it, so the Original style puts its colour back.
        local number = stepframe.number and stepframe.number.text
        if number and on then
            number:SetTextColor(NORMAL_FONT_COLOR:GetRGB())
            number.xhudStyled = true
        elseif number and number.xhudStyled then
            number.xhudStyled = nil
            local rxp = GetRXP()
            local color = rxp and rxp.activeTheme and rxp.activeTheme.textColor
            if color then number:SetTextColor(unpack(color)) end
        end
    end
end

-- ---------------------------------------------------------------------------
-- Module hooks (called by the core)
-- ---------------------------------------------------------------------------
local rxpHooked = false
local function HookRXP(rxp)
    if rxpHooked then return end
    rxpHooked = true
    local frame = _G.RXPFrame
    if frame.UpdateVisuals then
        hooksecurefunc(frame, "UpdateVisuals", function()
            if not XpieStyle() then return end
            ApplyChrome(true)
            ApplyGear(module.panel)
        end)
    end
    if frame.UpdateScrollBar then hooksecurefunc(frame, "UpdateScrollBar", StyleScrollBar) end
    if rxp.SetStep then hooksecurefunc(rxp, "SetStep", StyleActiveSteps) end
    if frame.CurrentStepFrame then hooksecurefunc(frame.CurrentStepFrame, "SetPoint", SpaceStepArea) end
end

function module:Apply()
    local rxp = GetRXP()
    local frame = _G.RXPFrame
    if not (rxp and frame and rxp.settings) then return end
    HookRXP(rxp)

    local on = XpieStyle()
    local rethemed = ApplyTheme()

    self.panel = self.panel or core:CreatePanel()
    self.panel:Attach(frame)
    if frame.GuideName then self.panel:SetHeaderAnchor(frame.GuideName) end
    self.panel:SetTitleInsets(TITLE_LEFT, TITLE_RIGHT)
    self.panel:SetStyle(WINDOW_PANEL)
    self.panel:SetActive(on)

    ApplyChrome(on)
    ApplyTitle()
    ApplyFooterText()
    ApplyListTop(on)
    ApplyGear(self.panel)
    if on then StyleScrollBar() else RestoreScrollBar() end
    if not rethemed then StyleActiveSteps() end
    -- Re-anchor the step area so its spacing follows the style.
    if frame.SetStepFrameAnchor then frame.SetStepFrameAnchor() end
    -- Leaving the XpieHUD style: RXP re-textures the checkboxes on its next step update.
    if self.wasOn and not on and rxp.ReloadStep and rxp.currentGuide then rxp.ReloadStep() end
    self.wasOn = on
end

-- RXP sets its window up on its own load; its guide loads just after login.
function module:OnLogin()
    for _, delay in ipairs({ 0, 1, 3, 6, 12 }) do   -- late ones: Zygor's tabs (guide name size) appear after its threaded startup
        C_Timer.After(delay, function()
            if core.ready then module:Apply() end
        end)
    end
end

-- Frames the quest window's "Guide Addons" fade group may fade (the panel is
-- parented with RXPFrame, so it fades too).
function module:GetFadeFrames()
    local list = {}
    for _, name in ipairs({ "RXPFrame", "RXPG_ARROW" }) do
        if _G[name] then list[#list + 1] = _G[name] end
    end
    return list
end

function module:BuildSettings(page)
    page:Status(function()
        return C_AddOns.IsAddOnLoaded("RXPGuides") and "" or "(RestedXP Guides not loaded)"
    end)
    page:Note("Choose RestedXP's original look, or the XpieHUD style: the native font, gold settings gear and checkboxes, a gold header bar on the guide window with the guide name under it, and a native background behind the current step. The XpieHUD style selects an \"XpieHUD\" theme in RestedXP; the Original style puts your previous theme back. Disable the XpieHUD_RestedXP addon to remove this page completely.")
    page:Dropdown({
        key = "style", label = "Style",
        values = function()
            return {
                { key = "xpiehud",  label = "XpieHUD" },
                { key = "original", label = "Original (leave RestedXP's look alone)" },
            }
        end,
    })
    page:Space(6)
    page:Slider({ key = "stepBackground", label = "Current Step Background", description = "Background behind the current step boxes below the guide window (and RestedXP's item and target buttons), so they stand out from the step list. The step list itself has no background.", min = 0, max = 100, step = 5, format = "%d%%" })
end
