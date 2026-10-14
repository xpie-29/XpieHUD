-- Panels.lua  (XpieHUD_Core)
-- Background panels that modules attach behind other addons' frames (e.g. the
-- Zygor guide window), with Enhance QoL-style control over background and
-- border texture, colour, opacity, size, padding and strata.
--
--   local panel = XpieHUD:CreatePanel()
--   panel:Attach(targetFrame)          -- sits behind target, resizes with it
--   panel:SetStyle(styleTable)         -- see PANEL_DEFAULTS for the fields
--   panel:SetActive(true/false)        -- show/hide (still follows target visibility)
--
-- Style tables live in a module's saved settings (module.db.panel), filled
-- from XpieHUD.PANEL_DEFAULTS, and are edited with page:PanelStyle(...).

local _, addon = ...

local SOLID = "Interface\\Buttons\\WHITE8X8"

-- ---------------------------------------------------------------------------
-- Media. Built-ins are Blizzard textures (checked in use in the 12.1.5 UI).
-- inset: fraction of the border size the background is pulled in by, so the
-- fill doesn't poke out past rounded border corners.
-- ---------------------------------------------------------------------------
local BACKGROUNDS = {
    { key = "solid",       label = "Solid",          file = SOLID },
    { key = "tooltip",     label = "Tooltip",        file = "Interface\\Tooltips\\UI-Tooltip-Background" },
    { key = "dialog",      label = "Dialog",         file = "Interface\\DialogFrame\\UI-DialogBox-Background" },
    { key = "dialogdark",  label = "Dialog (Dark)",  file = "Interface\\DialogFrame\\UI-DialogBox-Background-Dark" },
    { key = "marble",      label = "Marble",         file = "Interface\\FrameGeneral\\UI-Background-Marble" },
    { key = "rock",        label = "Rock",           file = "Interface\\FrameGeneral\\UI-Background-Rock" },
}

local BORDERS = {
    { key = "none",        label = "None" },
    { key = "pixel",       label = "Pixel (solid line)", file = SOLID, inset = 1 },
    { key = "tooltip",     label = "Tooltip",        file = "Interface\\Tooltips\\UI-Tooltip-Border", inset = 0.3 },
    { key = "dialog",      label = "Dialog",         file = "Interface\\DialogFrame\\UI-DialogBox-Border", inset = 0.34 },
    { key = "dialoggold",  label = "Dialog (Gold)",  file = "Interface\\DialogFrame\\UI-DialogBox-Gold-Border", inset = 0.34 },
    { key = "wood",        label = "Achievement Wood", file = "Interface\\ACHIEVEMENTFRAME\\UI-Achievement-WoodBorder", inset = 0.25 },
    { key = "textpanel",   label = "Text Panel",     file = "Interface\\Glues\\Common\\TextPanel-Border", inset = 0.25 },
    { key = "toast",       label = "Toast",          file = "Interface\\FriendsFrame\\UI-Toast-Border", inset = 0.25 },
}

local STRATAS = { "AUTO", "BACKGROUND", "LOW", "MEDIUM", "HIGH", "DIALOG" }

local function LSM()
    return LibStub and LibStub("LibSharedMedia-3.0", true)
end

-- { key, label } list for a dropdown: built-ins, then LibSharedMedia entries
-- (prefixed "lsm:") when that library is loaded by any addon.
local function MediaList(builtins, lsmType)
    local list = {}
    for _, entry in ipairs(builtins) do list[#list + 1] = { key = entry.key, label = entry.label } end
    local lib = LSM()
    if lib and lib.List then
        for _, name in ipairs(lib:List(lsmType)) do
            list[#list + 1] = { key = "lsm:" .. name, label = name .. "  |cff888888(SharedMedia)|r" }
        end
    end
    return list
end

function addon:GetBackgroundList() return MediaList(BACKGROUNDS, "background") end
function addon:GetBorderList()     return MediaList(BORDERS, "border") end
function addon:GetStrataList()     return STRATAS end

local function Resolve(builtins, lsmType, key)
    if type(key) == "string" and key:sub(1, 4) == "lsm:" then
        local lib = LSM()
        local file = lib and lib:Fetch(lsmType, key:sub(5), true)
        return file and { file = file, inset = 0.25 } or nil
    end
    for _, entry in ipairs(builtins) do
        if entry.key == key then return entry end
    end
end

-- The XpieHUD look: a dark tooltip-style fill with a gold tooltip border,
-- like Blizzard's own HUD panels. Colours are { r, g, b, a } (0-1).
addon.PANEL_DEFAULTS = {
    bgTexture     = "tooltip",
    bgColor       = { r = 0.04, g = 0.04, b = 0.06, a = 0.75 },
    borderTexture = "tooltip",
    borderSize    = 14,
    borderColor   = { r = 0.80, g = 0.66, b = 0.32, a = 0.90 },
    padX          = 6,      -- extra space left/right of the target (negative = inside)
    padY          = 6,      -- extra space above/below the target
    strata        = "AUTO", -- AUTO = same strata as the target, just behind it
}

-- ---------------------------------------------------------------------------
-- Panel object
-- ---------------------------------------------------------------------------
local PanelMixin = {}

function addon:CreatePanel()
    local frame = CreateFrame("Frame", nil, UIParent, "BackdropTemplate")
    frame:Hide()
    frame:EnableMouse(false)   -- backgrounds never eat clicks
    return Mixin({ frame = frame, active = false }, PanelMixin)
end

local function SyncShown(panel)
    local target = panel.target
    panel.frame:SetShown(panel.active and target ~= nil and target:IsShown())
end

-- Sit behind `target` and follow its size. The panel is parented to the
-- target's parent (so it fades and scales with that frame tree) and sits
-- one frame level below the target. Visibility follows the target.
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
    local f = self.frame
    f:ClearAllPoints()
    f:SetPoint("TOPLEFT", target, "TOPLEFT", -style.padX, style.padY)
    f:SetPoint("BOTTOMRIGHT", target, "BOTTOMRIGHT", style.padX, -style.padY)
end

function PanelMixin:ApplyLayer()
    local target, style = self.target, self.style
    if not (target and style) then return end
    local f = self.frame
    if style.strata == "AUTO" then
        f:SetFrameStrata(target:GetFrameStrata())
        f:SetFrameLevel(math.max(0, target:GetFrameLevel() - 1))
    else
        f:SetFrameStrata(style.strata)
    end
end

function PanelMixin:SetStyle(style)
    self.style = style
    local bg = Resolve(BACKGROUNDS, "background", style.bgTexture) or BACKGROUNDS[2]
    local border = Resolve(BORDERS, "border", style.borderTexture)
    local size = style.borderSize or 14
    local hasBorder = border and border.file ~= nil
    local inset = hasBorder and math.floor(size * (border.inset or 0.25) + 0.5) or 0

    local f = self.frame
    f:SetBackdrop({
        bgFile   = bg.file,
        edgeFile = hasBorder and border.file or nil,
        edgeSize = hasBorder and size or nil,
        tile     = bg.file ~= SOLID,
        tileSize = 128,
        insets   = { left = inset, right = inset, top = inset, bottom = inset },
    })
    local c = style.bgColor
    f:SetBackdropColor(c.r, c.g, c.b, c.a)
    if hasBorder then
        local b = style.borderColor
        f:SetBackdropBorderColor(b.r, b.g, b.b, b.a)
    end
    self:ApplyAnchors()
    self:ApplyLayer()
end

function PanelMixin:SetActive(active)
    self.active = active and true or false
    SyncShown(self)
end
