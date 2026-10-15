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

-- The guide window's panel has no title of its own: the guide name is the title.
local panelDefaults = CopyTable(core.PANEL_DEFAULTS)
panelDefaults.title = ""

local module = core:RegisterModule("restedxp", {
    title = "RestedXP Guides",
    defaults = {
        -- "xpiehud": XpieHUD theme + native panel. "original": leave RXP alone.
        style = "xpiehud",
        panel = panelDefaults,   -- deep-copied into the saved settings
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

-- Boxes follow the panel's opacity setting.
local function UpdateThemeOpacity()
    if not theme then return false end
    local alpha = ((module.db.panel and module.db.panel.opacity) or 80) / 100
    if theme.background[4] == alpha then return false end
    theme.background[4] = alpha
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
    local changed = UpdateThemeOpacity() and profile.activeTheme == THEME_NAME
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
    return { name and name.bg, name and name.icon, name and name.classIcon, footer and footer.bg }
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
-- Guide title: the native gold font (GameFontNormal), left-aligned on the
-- header bar after the gear. RXP sets its own font and colour on setup and
-- theme changes; those calls are post-hooked.
-- ---------------------------------------------------------------------------
local GEAR_SIZE, GEAR_X, GEAR_Y = 27, 4, -2   -- as XpieHUD_Zygor (Blizzard's Damage Meter gear)
local TITLE_LEFT  = GEAR_X + GEAR_SIZE + 5
local TITLE_RIGHT = 8
local RXP_TITLE_LEFT, RXP_TITLE_SIZE = 29, 11   -- RXP's own (GuideWindow.lua)

local styling = false
local function StyleTitle(text)
    if styling then return end
    styling = true
    local name = _G.RXPFrame.GuideName
    if XpieStyle() then
        text:SetFontObject(GameFontNormal)
        text:SetTextColor(NORMAL_FONT_COLOR:GetRGB())
        text:SetShadowColor(0, 0, 0, 1)
        text:SetShadowOffset(1, -1)
        text:ClearAllPoints()
        text:SetPoint("LEFT", name, "LEFT", TITLE_LEFT, 0)
        text:SetPoint("RIGHT", name, "RIGHT", -TITLE_RIGHT, 0)
        text:SetJustifyH("LEFT")
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
    end
    StyleTitle(text)
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
-- Scroll bar: Blizzard's minimal scroll bar art (MinimalScrollBar.xml) on
-- RXP's UIPanelScrollFrameTemplate buttons and thumb. RXP re-textures them in
-- RXPFrame.UpdateScrollBar on every theme reload; that is post-hooked.
-- ---------------------------------------------------------------------------
local SCROLL_ART = {
    ScrollUpButton   = { "minimal-scrollbar-arrow-top", "minimal-scrollbar-arrow-top-over", "minimal-scrollbar-arrow-top-down" },
    ScrollDownButton = { "minimal-scrollbar-arrow-bottom", "minimal-scrollbar-arrow-bottom-over", "minimal-scrollbar-arrow-bottom-down" },
}
local SCROLL_THUMB = "minimal-scrollbar-small-thumb-middle"
local SCROLL_ARROW_W, SCROLL_ARROW_H = 17, 11   -- the arrow atlases' size

local function ScrollBar()
    return _G.RXPFrame.ScrollFrame and _G.RXPFrame.ScrollFrame.ScrollBar
end

local function StyleScrollBar()
    if not XpieStyle() then return end   -- Original: RXP's UpdateScrollBar has just painted its own
    local bar = ScrollBar()
    if not (bar and C_Texture.GetAtlasInfo(SCROLL_THUMB)) then return end
    for key, art in pairs(SCROLL_ART) do
        local button = bar[key]
        if button then
            local normal, over, down = art[1], art[2], art[3]
            for field, atlas in pairs({ Normal = normal, Highlight = over, Pushed = down, Disabled = normal }) do
                local tx = button[field]
                if tx then
                    if not tx.xhudPoints then   -- RXP's layout, for the Original style
                        tx.xhudPoints = {}
                        for i = 1, tx:GetNumPoints() do tx.xhudPoints[i] = { tx:GetPoint(i) } end
                        tx.xhudBlend = tx:GetBlendMode()
                    end
                    tx:SetAtlas(atlas, false)
                    tx:ClearAllPoints()
                    tx:SetPoint("CENTER")
                    tx:SetSize(SCROLL_ARROW_W, SCROLL_ARROW_H)
                end
            end
            if button.Disabled then button.Disabled:SetDesaturated(true) end
            if button.Highlight then button.Highlight:SetBlendMode("BLEND") end
        end
    end
    local thumb = bar:GetThumbTexture()
    if thumb then thumb:SetAtlas(SCROLL_THUMB, false) end
    bar.xhudStyled = true
end

-- Original style: RXP's layout back, then RXP repaints its own art.
local function RestoreScrollBar()
    local bar = ScrollBar()
    if not (bar and bar.xhudStyled) then return end
    bar.xhudStyled = nil
    for key in pairs(SCROLL_ART) do
        local button = bar[key]
        for _, field in ipairs({ "Normal", "Highlight", "Pushed", "Disabled" }) do
            local tx = button and button[field]
            if tx and tx.xhudPoints then
                tx:ClearAllPoints()
                for _, p in ipairs(tx.xhudPoints) do tx:SetPoint(unpack(p)) end
                if #tx.xhudPoints == 0 then tx:SetAllPoints() end
                tx:SetTexCoord(0, 1, 0, 1)
                tx:SetDesaturated(false)
                if tx.xhudBlend then tx:SetBlendMode(tx.xhudBlend) end
            end
        end
    end
    local thumb = bar:GetThumbTexture()
    if thumb then thumb:SetTexCoord(0, 1, 0, 1) end
    if _G.RXPFrame.UpdateScrollBar then _G.RXPFrame.UpdateScrollBar() end
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

local function StyleActiveSteps()
    local current = _G.RXPFrame.CurrentStepFrame
    local pool = current and current.framePool
    if not pool or not C_Texture.GetAtlasInfo("checkbox-minimal") then return end
    local on = XpieStyle()
    for _, stepframe in pairs(pool) do
        for _, element in pairs(stepframe.elements or {}) do
            if element.button then StyleCheckbox(element.button) end
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
    self.panel:SetStyle(self.db.panel)
    self.panel:SetActive(on)

    ApplyChrome(on)
    ApplyTitle()
    ApplyGear(self.panel)
    if on then StyleScrollBar() else RestoreScrollBar() end
    if not rethemed then StyleActiveSteps() end
    -- Leaving the XpieHUD style: RXP re-textures the checkboxes on its next step update.
    if self.wasOn and not on and rxp.ReloadStep and rxp.currentGuide then rxp.ReloadStep() end
    self.wasOn = on
end

-- RXP sets its window up on its own load; its guide loads just after login.
function module:OnLogin()
    for _, delay in ipairs({ 0, 1, 3 }) do
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
    page:Note("Choose RestedXP's original look, or the XpieHUD style: the native font, gold settings gear and checkboxes, and a native panel behind the guide window. The XpieHUD style selects an \"XpieHUD\" theme in RestedXP; the Original style puts your previous theme back. Disable the XpieHUD_RestedXP addon to remove this page completely.")
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
    page:PanelStyle(function() return module.db.panel end)
end
