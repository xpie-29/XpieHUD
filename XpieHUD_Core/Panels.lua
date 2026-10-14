-- Panels.lua  (XpieHUD_Core)
-- Native background panels that modules attach behind other addons' frames
-- (e.g. the Zygor guide window).
--
-- XpieHUD's look IS the native look. A panel is built from Blizzard's own art,
-- exactly the way Blizzard builds the matching HUD element (checked in 12.1.5):
--
--   "tracker" (default)  the Objective Tracker: body is the Edit Mode
--                        background (NineSlicePanelTemplate, UniqueCornersLayout
--                        + texture kit "common-opacity-background", faded with
--                        SetAlpha like Edit Mode's Background Opacity), with the
--                        gold "ui-questtracker-primary-objective-header" bar on top.
--   "tooltip"            Blizzard's dark tooltip (TooltipDefaultDarkLayout,
--                        TOOLTIP_DEFAULT_BACKGROUND_COLOR / TOOLTIP_DEFAULT_COLOR).
--
-- Players get a few native-safe controls, not colour pickers:
--   look     "tracker" | "tooltip"
--   opacity  0-100   body opacity (the header bar stays solid)
--   header   bool    gold header bar (tracker look)
--   border   bool    tooltip border (tooltip look)
--   padding  px      space around the attached window (negative = inside)
--   title    string  text on the header bar ("" = none), in the tracker's header font
--
--   local panel = XpieHUD:CreatePanel()
--   panel:Attach(targetFrame)   -- sits behind target, resizes/fades with it
--   panel:SetStyle(style)       -- the fields above
--   panel:SetActive(true/false) -- show/hide (still follows target visibility)
--   panel:SetHeaderAnchor(region)   -- lay the header bar over a region of the target
--   panel:SetTitleInsets(left, right) -- keep the title clear of buttons on the bar
--   panel.headerFrame               -- anchor point for buttons a module puts on the bar

local _, addon = ...

local TRACKER_LAYOUT = "UniqueCornersLayout"
local TRACKER_KIT    = "common-opacity-background"
local TRACKER_PROBE  = TRACKER_KIT .. "-NineSlice-Center"   -- one of the kit's atlases
local TRACKER_HEADER = "ui-questtracker-primary-objective-header"
local TOOLTIP_LAYOUT = "TooltipDefaultDarkLayout"

local function AtlasExists(name)
    return C_Texture and C_Texture.GetAtlasInfo and C_Texture.GetAtlasInfo(name) ~= nil
end

-- If a patch renames the tracker art, fall back to the tooltip look rather
-- than drawing a broken panel.
local function TrackerAvailable()
    return AtlasExists(TRACKER_PROBE) and AtlasExists(TRACKER_HEADER)
end

local function TooltipBackgroundColor()
    local c = TOOLTIP_DEFAULT_BACKGROUND_COLOR
    if c then return c:GetRGB() end
    return 0.09, 0.09, 0.19
end

local function TooltipBorderColor()
    local c = TOOLTIP_DEFAULT_COLOR
    if c then return c:GetRGB() end
    return 1, 1, 1
end

addon.PANEL_DEFAULTS = {
    look    = "tracker",
    title   = "Leveling Guide",   -- header bar text; "" for none
    opacity = 80,    -- %
    header  = true,  -- tracker look
    border  = true,  -- tooltip look
    padding = 6,     -- px
}

addon.PANEL_LOOKS = {
    { key = "tracker", label = "Quest Tracker" },
    { key = "tooltip", label = "Tooltip" },
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
--   frame         container (no art), anchored around the target
--   trackerBody   Edit Mode tracker background   } one of the two is shown
--   tooltipBody   dark tooltip                   }
--   headerFrame   gold header bar, one level above the bodies
-- ---------------------------------------------------------------------------
local PanelMixin = {}

function addon:CreatePanel()
    local frame = CreateFrame("Frame", nil, UIParent)
    frame:Hide()
    frame:EnableMouse(false)   -- backgrounds never eat clicks

    local trackerBody = CreateFrame("Frame", nil, frame, "NineSlicePanelTemplate")
    trackerBody:SetAllPoints()
    NineSliceUtil.ApplyLayoutByName(trackerBody, TRACKER_LAYOUT, TRACKER_KIT)

    local tooltipBody = CreateFrame("Frame", nil, frame, "NineSlicePanelTemplate")
    tooltipBody:SetAllPoints()
    NineSliceUtil.ApplyLayoutByName(tooltipBody, TOOLTIP_LAYOUT)

    local headerFrame = CreateFrame("Frame", nil, frame)
    -- Like ObjectiveTrackerContainerHeaderTemplate: a 32px-tall header frame
    -- with the gold art drawn at its native size, centred. The tracker's frame
    -- is 260 wide, so art wider than that overhangs both ends, and the
    -- tracker's own buttons sit inside the art. We keep that overhang and
    -- stretch the middle to the panel's width.
    local TRACKER_HEADER_WIDTH = 260
    headerFrame:SetHeight(32)
    local header = headerFrame:CreateTexture(nil, "BACKGROUND")
    header:SetAtlas(TRACKER_HEADER, false)
    local info = C_Texture and C_Texture.GetAtlasInfo and C_Texture.GetAtlasInfo(TRACKER_HEADER)
    local overhang = info and info.width and math.max(0, (info.width - TRACKER_HEADER_WIDTH) / 2) or 0
    header:SetPoint("LEFT", -overhang, 0)
    header:SetPoint("RIGHT", overhang, 0)
    header:SetHeight(info and info.height or 32)

    -- Title in the Objective Tracker's own header font ("All Objectives"),
    -- placed like Blizzard's: left-aligned, 7px in, one line, truncated.
    local title = headerFrame:CreateFontString(nil, "ARTWORK")
    title:SetFontObject(_G.ObjectiveTrackerHeaderFont or GameFontNormalMed2 or GameFontNormal)
    title:SetPoint("LEFT", 7, 0)
    title:SetPoint("RIGHT", -8, 0)
    title:SetJustifyH("LEFT")
    title:SetWordWrap(false)
    title:SetMaxLines(1)

    for _, f in ipairs({ trackerBody, tooltipBody, headerFrame }) do f:EnableMouse(false) end

    return Mixin({
        frame = frame, trackerBody = trackerBody, tooltipBody = tooltipBody,
        headerFrame = headerFrame, title = title, active = false,
    }, PanelMixin)
end

local function SyncShown(panel)
    local target = panel.target
    panel.frame:SetShown(panel.active and target ~= nil and target:IsShown())
end

-- Sit behind `target` and follow its size. The panel is parented to the
-- target's parent (so it fades and scales with that frame tree), uses the
-- target's strata below it, and follows its visibility.
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

-- Header placement. By default the bar sits above the target (like a tracker
-- section header above its content) and the panel grows upward by its
-- height. A module can instead lay it over a region of the target (e.g. the
-- target's own title bar): the bar is centred vertically on that region and
-- spans the panel's width.
function PanelMixin:SetHeaderAnchor(region)
    self.headerAnchor = region
    self:ApplyAnchors()
end

-- Title text insets from the header bar's edges, so a module can keep the
-- title clear of buttons it places on the bar (Blizzard's tracker uses 7).
function PanelMixin:SetTitleInsets(left, right)
    self.titleLeft, self.titleRight = left, right
    self.title:ClearAllPoints()
    self.title:SetPoint("LEFT", left or 7, 0)
    self.title:SetPoint("RIGHT", -(right or 8), 0)
end

function PanelMixin:ApplyAnchors()
    local target, style = self.target, self.style
    if not (target and style) then return end
    local pad = style.padding or 0
    local hf, anchor = self.headerFrame, self.headerAnchor
    local headerSpace = (not anchor and hf:IsShown()) and hf:GetHeight() or 0
    local f = self.frame
    f:ClearAllPoints()
    f:SetPoint("TOPLEFT", target, "TOPLEFT", -pad, pad + headerSpace)
    f:SetPoint("BOTTOMRIGHT", target, "BOTTOMRIGHT", pad, -pad)

    hf:ClearAllPoints()
    if anchor then
        local dy = (hf:GetHeight() - (anchor:GetHeight() or 0)) / 2
        hf:SetPoint("TOPLEFT", anchor, "TOPLEFT", -pad, dy)
        hf:SetPoint("TOPRIGHT", anchor, "TOPRIGHT", pad, dy)
    else
        hf:SetPoint("TOPLEFT", f, "TOPLEFT")
        hf:SetPoint("TOPRIGHT", f, "TOPRIGHT")
    end
end

-- Bodies two levels below the target, the header bar one below: everything
-- stays behind the target's own content.
function PanelMixin:ApplyLayer()
    local target = self.target
    if not target then return end
    local strata = target:GetFrameStrata()
    local base = math.max(0, target:GetFrameLevel() - 2)
    for _, f in ipairs({ self.frame, self.trackerBody, self.tooltipBody, self.headerFrame }) do
        f:SetFrameStrata(strata)
    end
    self.frame:SetFrameLevel(base)
    self.trackerBody:SetFrameLevel(base)
    self.tooltipBody:SetFrameLevel(base)
    self.headerFrame:SetFrameLevel(base + 1)
end

function PanelMixin:SetStyle(style)
    self.style = style
    local opacity = (style.opacity or 80) / 100
    local tracker = style.look ~= "tooltip" and TrackerAvailable()
    if style.look ~= "tooltip" and not tracker and not addon.warnedTrackerArt then
        addon.warnedTrackerArt = true
        addon:Print("The Quest Tracker panel art wasn't found in this game version; using the Tooltip look instead.")
    end

    self.trackerBody:SetShown(tracker)
    self.headerFrame:SetShown(tracker and style.header)
    local text = style.title or ""
    self.title:SetText(text)
    self.title:SetShown(text ~= "")
    self.tooltipBody:SetShown(not tracker)

    if tracker then
        -- Same as Edit Mode's Background Opacity on the Objective Tracker.
        self.trackerBody:SetAlpha(opacity)
    else
        local r, g, b = TooltipBackgroundColor()
        self.tooltipBody:SetCenterColor(r, g, b, opacity)
        local br, bg, bb = TooltipBorderColor()
        self.tooltipBody:SetBorderColor(br, bg, bb, style.border and 1 or 0)
    end

    self:ApplyAnchors()
    self:ApplyLayer()
end

function PanelMixin:SetActive(active)
    self.active = active and true or false
    SyncShown(self)
end
