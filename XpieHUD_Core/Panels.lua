-- Panels.lua  (XpieHUD_Core)
-- Native background panels that modules attach behind other addons' frames
-- (e.g. the Zygor guide window).
--
-- XpieHUD's look IS the native look: a panel is built exactly like Blizzard's
-- dark tooltips (NineSlicePanelTemplate + the "TooltipDefaultDarkLayout"
-- atlas border, tooltip background/border colours). Players get a few
-- native-safe controls, not colour pickers:
--
--   opacity  0-100   background opacity
--   border   bool    show the tooltip border
--   padding  px      space around the attached window (negative = inside)
--
--   local panel = XpieHUD:CreatePanel()
--   panel:Attach(targetFrame)   -- sits behind target, resizes/fades with it
--   panel:SetStyle(style)       -- { opacity, border, padding }
--   panel:SetActive(true/false) -- show/hide (still follows target visibility)

local _, addon = ...

local LAYOUT = "TooltipDefaultDarkLayout"

local function BackgroundColor()
    local c = TOOLTIP_DEFAULT_BACKGROUND_COLOR
    if c then return c:GetRGB() end
    return 0.09, 0.09, 0.19
end

local function BorderColor()
    local c = TOOLTIP_DEFAULT_COLOR
    if c then return c:GetRGB() end
    return 1, 1, 1
end

addon.PANEL_DEFAULTS = {
    opacity = 80,    -- %
    border  = true,
    padding = 6,     -- px
}

-- Settings saved by 3.1.0's texture/colour editor: back to the native defaults.
function addon:NormalizePanelStyle(style)
    if style.bgTexture ~= nil or style.bgColor ~= nil then
        wipe(style)
    end
    addon.CopyDefaults(style, addon.PANEL_DEFAULTS)
end

-- ---------------------------------------------------------------------------
-- Panel object
-- ---------------------------------------------------------------------------
local PanelMixin = {}

function addon:CreatePanel()
    local frame = CreateFrame("Frame", nil, UIParent, "NineSlicePanelTemplate")
    frame:Hide()
    frame:EnableMouse(false)   -- backgrounds never eat clicks
    NineSliceUtil.ApplyLayoutByName(frame, LAYOUT)
    return Mixin({ frame = frame, active = false }, PanelMixin)
end

local function SyncShown(panel)
    local target = panel.target
    panel.frame:SetShown(panel.active and target ~= nil and target:IsShown())
end

-- Sit behind `target` and follow its size. The panel is parented to the
-- target's parent (so it fades and scales with that frame tree), uses the
-- target's strata one frame level below it, and follows its visibility.
function PanelMixin:Attach(target)
    if self.target == target then return end
    self.target = target
    self.frame:SetParent(target:GetParent() or UIParent)
    if not self.hooked then
        self.hooked = true
        target:HookScript("OnShow", function() SyncShown(self); self:ApplyLayer() end)
        target:HookScript("OnHide", function() SyncShown(self) end)
    end
    self:ApplyAnchors()
    self:ApplyLayer()
    SyncShown(self)
end

function PanelMixin:ApplyAnchors()
    local target, style = self.target, self.style
    if not (target and style) then return end
    local pad = style.padding or 0
    local f = self.frame
    f:ClearAllPoints()
    f:SetPoint("TOPLEFT", target, "TOPLEFT", -pad, pad)
    f:SetPoint("BOTTOMRIGHT", target, "BOTTOMRIGHT", pad, -pad)
end

function PanelMixin:ApplyLayer()
    local target = self.target
    if not target then return end
    self.frame:SetFrameStrata(target:GetFrameStrata())
    self.frame:SetFrameLevel(math.max(0, target:GetFrameLevel() - 1))
end

function PanelMixin:SetStyle(style)
    self.style = style
    local f = self.frame
    local r, g, b = BackgroundColor()
    f:SetCenterColor(r, g, b, (style.opacity or 80) / 100)
    local br, bg, bb = BorderColor()
    f:SetBorderColor(br, bg, bb, style.border and 1 or 0)
    self:ApplyAnchors()
    self:ApplyLayer()
end

function PanelMixin:SetActive(active)
    self.active = active and true or false
    SyncShown(self)
end
