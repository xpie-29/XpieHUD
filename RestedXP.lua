-- RestedXP.lua  (XpieHUD v0.8)
-- Theme-agnostic RXP frame cleanup.
--
-- Root cause of the login timing issue:
--   RXP creates step frames lazily — they don't exist until guide data loads
--   and the guide window first renders. Our ApplyRXP on PLAYER_LOGIN fires
--   before that happens. The resize workaround works because it triggers
--   UpdateVisuals AFTER step frames are created, which re-fires SetBackdropColor,
--   which our hooks catch.
--
-- Fix: hook RXPFrame's OnSizeChanged to re-apply automatically (replicating
--   what the manual resize does), plus register PLAYER_ENTERING_WORLD and
--   staggered timers for belt-and-suspenders coverage.

local _, addon = ...

-- ---------------------------------------------------------------------------
-- Known top-level globals
-- ---------------------------------------------------------------------------
local RXP_FRAME_NAMES = {
    "RXPFrame",
    "RXPItemFrame",
    "RXPMapFrame",
    "RXPMinimapButton",
    "RXP_GuideList",
}

-- Frames to EXCLUDE from alpha and strip — content we want to keep visible
local RXP_EXCLUDE = {
    ["RXPG_ARROW"] = true,  -- navigation arrow; strip its backdrop but not its alpha
}

local RXP_CHILD_KEYS = {
    "CurrentStepFrame",
    "BottomFrame",
    "ScrollFrame",
    "ScrollChild",
    "MenuFrame",
    "Footer",
    "GuideName",
    "BarContainer",
}

-- ---------------------------------------------------------------------------
-- Texture patterns
-- ---------------------------------------------------------------------------
local BACKGROUND_PATH_PATTERNS = {
    "border", "edge", "shadow", "backdrop", "9slice", "nineslice",
    "squareborder", "rounded", "solid", "frame.*bg", "overlay.*bg",
    "background", "tileset", "parchment", "panel",
}

local NINESLICE_PIECES = {
    "TopLeftCorner", "TopRightCorner", "BottomLeftCorner", "BottomRightCorner",
    "TopEdge", "BottomEdge", "LeftEdge", "RightEdge", "Center",
}

-- ---------------------------------------------------------------------------
-- State
-- ---------------------------------------------------------------------------
local hookedFrames    = {}  -- backdrop hook registry
local rxpOnShowHooked = {}  -- OnShow hook registry
local rxpSizeHooked   = false
local bordersStripped = false
local rxpInitDone     = false  -- true once step frames confirmed to exist

-- ---------------------------------------------------------------------------
-- Forward declarations
-- ---------------------------------------------------------------------------
local CollectRXPFrames, StripAll, RestoreAll

-- ---------------------------------------------------------------------------
-- Per-frame backdrop hooks
-- Alpha for step box backdrops — dark tint to aid readability (0=none, 0.1=subtle, 0.3=current)
local STEP_FRAME_BG_ALPHA = 0.3

-- Returns true if frame is one of the active step display boxes
local function IsStepFrame(f)
    local csf = _G["RXPFrame"] and _G["RXPFrame"].CurrentStepFrame
    if not csf then return false end
    for _, sf in ipairs(csf.framePool or {}) do
        if f == sf or (sf.number and f == sf.number) then return true end
    end
    return false
end

-- Show/hide the resize grip triangle in the guide window footer
local function HideResizeGrip(hide)
    local rxpFrame = _G["RXPFrame"]
    if not rxpFrame then return end
    local grip = rxpFrame.Footer and rxpFrame.Footer.icon
    if grip and grip.SetAlpha then
        grip:SetAlpha(hide and 0 or 1)
    end
end

-- ---------------------------------------------------------------------------
-- Re-entrancy guards: prevent the hooks from calling themselves recursively.
local applyingBackdropColor       = false
local applyingBackdropBorderColor = false

local function HookBackdropOnFrame(f)
    if hookedFrames[f] or not f.SetBackdropColor then return end
    hookedFrames[f] = true

    hooksecurefunc(f, "SetBackdropColor", function(self)
        if applyingBackdropColor then return end
        if XpieHUDDB and XpieHUDDB.rxpHideBorders then
            applyingBackdropColor = true
            local a = IsStepFrame(self) and STEP_FRAME_BG_ALPHA or 0
            self:SetBackdropColor(0, 0, 0, a)
            applyingBackdropColor = false
        end
    end)

    hooksecurefunc(f, "SetBackdropBorderColor", function(self)
        if applyingBackdropBorderColor then return end
        if XpieHUDDB and XpieHUDDB.rxpHideBorders then
            applyingBackdropBorderColor = true
            self:SetBackdropBorderColor(0, 0, 0, 0)
            applyingBackdropBorderColor = false
        end
    end)
end

-- ---------------------------------------------------------------------------
-- Helpers
-- ---------------------------------------------------------------------------
local function IsBgRegion(region)
    local layer = region.GetDrawLayer and region:GetDrawLayer()
    if layer == "BORDER" or layer == "BACKGROUND" then return true end
    local path = region.GetTexture and region:GetTexture()
    if type(path) == "string" then
        local lp = path:lower()
        for _, pat in ipairs(BACKGROUND_PATH_PATTERNS) do
            if lp:find(pat) then return true end
        end
    end
    return false
end

local function WalkTree(frame, onRegion, onFrame, depth)
    depth = depth or 0
    if not frame or depth > 6 then return end

    local numRegions = frame.GetNumRegions and frame:GetNumRegions() or 0
    for i = 1, numRegions do
        local region = select(i, frame:GetRegions())
        if region then onRegion(region) end
    end

    for _, key in ipairs(NINESLICE_PIECES) do
        local child = frame[key]
        if child and child.SetAlpha then onFrame(child) end
    end

    local numChildren = frame.GetNumChildren and frame:GetNumChildren() or 0
    for i = 1, numChildren do
        local child = select(i, frame:GetChildren())
        if child then
            onFrame(child)
            WalkTree(child, onRegion, onFrame, depth + 1)
        end
    end
end

-- ---------------------------------------------------------------------------
-- Frame collection
-- ---------------------------------------------------------------------------
CollectRXPFrames = function()
    local frames, seen = {}, {}

    local function Add(f)
        if f and type(f) == "table" and f.SetAlpha and not seen[f] then
            seen[f] = true
            frames[#frames + 1] = f
        end
    end

    for _, name in ipairs(RXP_FRAME_NAMES) do
        Add(_G[name])
    end

    local rxpMain = _G["RXPFrame"]
    if rxpMain then
        for _, key in ipairs(RXP_CHILD_KEYS) do
            Add(rxpMain[key])
        end
        if type(rxpMain.activeSteps) == "table" then
            for _, stepFrame in pairs(rxpMain.activeSteps) do
                Add(stepFrame)
            end
        end
    end

    for name, obj in pairs(_G) do
        if type(name) == "string" and name:sub(1, 3) == "RXP"
           and type(obj) == "table" and obj.SetAlpha and obj.GetFrameType then
            Add(obj)
        end
    end

    local rxpAddon = _G["RXPGuides"] or _G["RXP"]
    if rxpAddon and rxpAddon.enabledFrames then
        for key, f in pairs(rxpAddon.enabledFrames) do
            -- Skip the arrow frame — we want it visible
            if key ~= "arrowFrame" then Add(f) end
        end
    end

    return frames
end

-- ---------------------------------------------------------------------------
-- Strip / restore
-- ---------------------------------------------------------------------------
local function ApplyStripToFrame(f, strip)
    if strip then
        if f.SetBackdropColor     then f:SetBackdropColor(0, 0, 0, 0)     end
        if f.SetBackdropBorderColor then f:SetBackdropBorderColor(0, 0, 0, 0) end
        HookBackdropOnFrame(f)
    else
        if f.UpdateVisuals then pcall(f.UpdateVisuals, f) end
    end
end

local function ApplyStepFrameAlpha(alpha)
    -- Step frames are created lazily and live in CurrentStepFrame.framePool.
    -- They are never in CollectRXPFrames() and are created after hooks run,
    -- so we must walk the pool directly and set backdrop color explicitly.
    local csf = _G["RXPFrame"] and _G["RXPFrame"].CurrentStepFrame
    if not (csf and csf.framePool) then return end
    for _, sf in ipairs(csf.framePool) do
        if sf.SetBackdropColor then
            sf:SetBackdropColor(0, 0, 0, alpha)
        end
        if sf.number and sf.number.SetBackdropColor then
            sf.number:SetBackdropColor(0, 0, 0, alpha)
        end
        -- Also hook each step frame now that we have a reference,
        -- so future SetBackdropColor calls (theme switch etc.) stay at alpha.
        HookBackdropOnFrame(sf)
        if sf.number then HookBackdropOnFrame(sf.number) end
    end
end

StripAll = function(frames)
    for _, f in ipairs(frames) do
        ApplyStripToFrame(f, true)
        WalkTree(f,
            function(region)
                if IsBgRegion(region) and region.SetAlpha then
                    region:SetAlpha(0)
                end
            end,
            function(child)
                ApplyStripToFrame(child, true)
            end
        )
    end
    -- Apply the step-frame alpha directly to step frames (created lazily, not in frames list)
    ApplyStepFrameAlpha(STEP_FRAME_BG_ALPHA)
    HideResizeGrip(true)
end

RestoreAll = function(frames)
    for _, f in ipairs(frames) do
        WalkTree(f,
            function(region)
                if IsBgRegion(region) and region.SetAlpha then
                    region:SetAlpha(1)
                end
            end,
            function(child)
                if child.UpdateVisuals then pcall(child.UpdateVisuals, child) end
            end
        )
        ApplyStripToFrame(f, false)
    end
    -- Restore step frame backdrops (RXP will repaint on next theme update)
    ApplyStepFrameAlpha(1)
    HideResizeGrip(false)
end

-- ---------------------------------------------------------------------------
-- Hook RXPFrame's OnSizeChanged — this is what the manual resize triggers.
-- We replicate it automatically so the strip applies as soon as RXP has
-- fully built its step frames (which happens around the same time the guide
-- window first becomes resizable/visible with content).
-- ---------------------------------------------------------------------------
local function HookRXPSizeChanged()
    if rxpSizeHooked then return end
    local rxpMain = _G["RXPFrame"]
    if not rxpMain then return end
    rxpSizeHooked = true

    rxpMain:HookScript("OnSizeChanged", function()
        if XpieHUDDB and XpieHUDDB.rxpHideBorders then
            -- Small defer so RXP's own OnSizeChanged runs first
            C_Timer.After(0.05, function()
                StripAll(CollectRXPFrames())
            end)
        end
    end)
end

-- Hook OnShow on each top-level frame (catches re-shows after zone etc.)
local function HookOnShow(frames)
    for _, f in ipairs(frames) do
        if not rxpOnShowHooked[f] then
            rxpOnShowHooked[f] = true
            f:HookScript("OnShow", function()
                C_Timer.After(0, function()
                    if XpieHUDDB and XpieHUDDB.rxpHideBorders then
                        StripAll(CollectRXPFrames())
                    end
                    addon:ApplyRXPAlpha(CollectRXPFrames())
                end)
            end)
        end
    end
end

-- ---------------------------------------------------------------------------
-- Staggered login init
-- Fires at 1s, 3s, and 6s after PLAYER_LOGIN to catch RXP's lazy frame
-- creation regardless of machine speed or guide load time.
-- ---------------------------------------------------------------------------
local function ScheduleLoginStrip()
    local delays = { 1, 3, 6 }
    for _, delay in ipairs(delays) do
        C_Timer.After(delay, function()
            -- Re-run full ApplyAll so panel hides (rxpTargets/rxpItems) also
            -- pick up frames that RXP created after login.
            if addon.ready then
                addon:ApplyAll()
            end
            if not (XpieHUDDB and XpieHUDDB.rxpHideBorders) then return end
            local frames = CollectRXPFrames()
            if #frames > 0 then
                HookRXPSizeChanged()
                HookOnShow(frames)
                StripAll(frames)
            end
        end)
    end
end

-- ---------------------------------------------------------------------------
-- Public API
-- ---------------------------------------------------------------------------
function addon:ApplyRXPBorders(frames)
    frames = frames or CollectRXPFrames()
    if XpieHUDDB.rxpHideBorders then
        HookRXPSizeChanged()
        HookOnShow(frames)
        StripAll(frames)
        bordersStripped = true
    elseif bordersStripped then
        RestoreAll(frames)
        bordersStripped = false
    end
end

function addon:ApplyRXPAlpha(frames)
    frames = frames or CollectRXPFrames()

    local pct = tonumber(XpieHUDDB and XpieHUDDB.rxpFrameAlpha)
    if pct == nil then pct = self.defaults.rxpFrameAlpha end
    local alpha = math.max(0, math.min(100, pct)) / 100

    for _, f in ipairs(frames) do
        f:SetAlpha(alpha)
    end
end

-- ---------------------------------------------------------------------------
-- Waypoint arrow texture
-- RXPG_ARROW (map.lua) is one texture that RXP rotates toward the waypoint;
-- its image is set only in RXPG_ARROW:UpdateVisuals() (on init and theme
-- change). Post-hook that and swap in XpieHUD's gold arrowhead. Any image
-- works as long as it points up.
-- ---------------------------------------------------------------------------
local ARROW_TEXTURE = "Interface\\AddOns\\XpieHUD\\Media\\rxp_arrow.tga"
local arrowHooked = false

function addon:ApplyRXPArrow()
    local arrow = _G["RXPG_ARROW"]
    if not (arrow and arrow.texture and arrow.UpdateVisuals) then return end

    if not arrowHooked then
        arrowHooked = true
        hooksecurefunc(arrow, "UpdateVisuals", function(self)
            if XpieHUDDB and XpieHUDDB.rxpGoldArrow then
                self.texture:SetTexture(ARROW_TEXTURE)
            end
        end)
    end
    -- Re-run RXP's own visuals: restores its texture when the option is off,
    -- and our hook swaps it when on.
    arrow:UpdateVisuals()
end

function addon:ApplyRXP()
    local frames = CollectRXPFrames()
    self:ApplyRXPAlpha(frames)
    self:ApplyRXPBorders(frames)
    self:ApplyRXPArrow()
end

-- Called once from Core.lua on PLAYER_LOGIN
function addon:ScheduleRXPInit()
    ScheduleLoginStrip()
    -- Also hook size changed as soon as RXPFrame exists
    C_Timer.After(0.5, HookRXPSizeChanged)
end
