-- Zygor.lua  (XpieHUD)
-- Zygor Guides Viewer integration, matching what RestedXP.lua does for RXP:
--   * strip the viewer window's backgrounds and borders
--   * step boxes keep Zygor's state colours at 30% opacity, without edges
--   * "XpieHUD Gold" arrow skin: our gold arrowhead as a native Zygor arrow skin
--
-- Zygor internals used (checked against Zygor 9.6 retail):
--   _G.ZGV, ZGV.Frame (ZygorGuidesViewerFrame, skin "default")
--   ZGV.Frame:ApplySkin()            Skins/Default/Skin.lua   (window backdrops)
--   ZGV.Frame.Border / .Border.Back / .Border.TabContainer / .Border.Toolbar
--   ZGV_DefaultSkin_DefaultStep_Mixin:ApplySkin / :SetBackgroundForStep
--   ZGV.Pointer:AddArrowSkin / :SetArrowSkin, sprite arrows (Arrows/ArrowSkin.lua)
-- Zygor isn't secure code, so hooking it can't taint Blizzard's UI.

local _, addon = ...

local STEP_BG_ALPHA = 0.5                   -- step box tint (readable on dark ground)
local SKIN_ID       = "XpieHUD"
local SKIN_NAME     = "XpieHUD Gold"
local MEDIA_DIR     = "Interface\\AddOns\\XpieHUD\\Media\\Zygor\\"

local function Enabled()
    return XpieHUDDB and XpieHUDDB.guideZygor and _G.ZGV ~= nil
end
local function StripOn()
    return Enabled() and XpieHUDDB.zygorStrip
end

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
    if r then step:SetBackdropColor(r, g, b, STEP_BG_ALPHA) end
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
-- 1024x1024 sprite sheet (Media/Zygor/arrow.tga): 160 frames of the gold
-- arrowhead, 2.25 deg apart counter-clockwise, in 96x64 cells (Zygor's arrow
-- texture is 50x33, same 1.5 aspect, so the arrowhead shows ~33px tall).
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
        -- white gradient = no tint: the arrow stays gold like the RXP one
        ar = 1, ag = 1, ab = 1,
        br = 1, bg = 1, bb = 1,
        cr = 1, cg = 1, cb = 1,
        texture = MEDIA_DIR .. "arrow",
        template = "ZygorGuidesViewerFrame_ArrowSkin_Template",
    }
    -- Arrived / stairs / taxi / ship icons: reuse Zygor's Stealth set.
    skin.icons = {
        here = { 1, 1, 40, 40 }, upstairs = { 2, 1, 60, 60 }, error = { 3, 1, 40, 40 },
        instance = { 4, 1, 40, 40 }, taxi = { 5, 1, 40, 40 }, ship = { 6, 1, 40, 40 },
        waiting = { 1, 2, 40, 40 }, downstairs = { 2, 2, 60, 60 }, instancehide = { 4, 2, 40, 40 },
        file = (ZGV.ARROWSDIR or "Interface\\AddOns\\ZygorGuidesViewer\\Arrows\\") .. "Stealth\\specials",
        cols = 8, rows = 2, width = 1024, height = 256, padding = 0,
        default = "wait",
    }
    -- The "metal" option swaps in an -specular texture we don't ship.
    local createFrame = skin.CreateFrame
    skin.CreateFrame = function(self)
        local f = createFrame(self)
        f.SetOption = function() end
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
        addon.applyPending = true
        return
    end

    local want = Enabled() and XpieHUDDB.zygorGoldArrow
    local current = profile.arrowskin
    if want and current ~= SKIN_ID then
        XpieHUDDB.zygorPrevArrowSkin = current
        Pointer:SetArrowSkin(SKIN_ID)
        Pointer:UpdateArrowVisibility()
    elseif not want and current == SKIN_ID then
        local prev = XpieHUDDB.zygorPrevArrowSkin
        if not (prev and Pointer.ArrowSkins[prev]) then prev = "Starlight" end
        Pointer:SetArrowSkin(prev)
        Pointer:UpdateArrowVisibility()
    end
end

-- ---------------------------------------------------------------------------
-- Public API
-- ---------------------------------------------------------------------------
-- Called from Core.lua on ADDON_LOADED("ZygorGuidesViewer"), before Zygor
-- builds its window: register the arrow skin and hook the step mixin.
function addon:OnZygorLoaded()
    if not _G.ZGV then return end
    RegisterArrowSkin()
    HookStepMixin()
end

local frameHooked = false
local stripped = false

function addon:ApplyZygor()
    local ZGV = _G.ZGV
    if not ZGV then return end
    RegisterArrowSkin()
    HookStepMixin()

    local frame = ZGV.Frame
    if frame and frame.ApplySkin and not frameHooked then
        frameHooked = true
        hooksecurefunc(frame, "ApplySkin", function()
            if not StripOn() then return end
            StripChrome()
            ForEachStep(StyleStep)
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
        end
    end

    ApplyArrow()
end

-- Frames the quest window may fade (only while this guide is enabled).
function addon:GetZygorFrames()
    if not Enabled() then return {} end
    local list = {}
    for _, name in ipairs({ "ZygorGuidesViewerFrameMaster", "ZygorGuidesViewerPointer_ArrowCtrl" }) do
        if _G[name] then list[#list + 1] = _G[name] end
    end
    return list
end

-- Zygor starts up in a background thread after login; catch its window and
-- arrow once they exist.
function addon:ScheduleZygorInit()
    for _, delay in ipairs({ 1, 3, 6, 12 }) do
        C_Timer.After(delay, function()
            if addon.ready then addon:ApplyZygor() end
        end)
    end
end
