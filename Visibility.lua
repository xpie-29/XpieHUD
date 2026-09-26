local _, addon = ...

-- ---------------------------------------------------------------------------
-- How XpieHUD hides things (read before changing!)
--
-- Blizzard frames are hidden by ALPHA + MOUSE, never Hide()/Show().
-- Most HUD frames (chat, micro menu, bag bar, status bars, minimap cluster,
-- damage meter) are Edit Mode systems. Their Hide is replaced by
-- EditModeSystemMixin:HideOverride -> ManagedFrameMixin.OnHide, which rewrites
-- the managed-frame containers' layout. Calling Hide() from addon code runs all
-- of that as XpieHUD, taints the layout, and the taint later surfaces as
-- ADDON_ACTION_BLOCKED on the world map (Pet Tamer pins,
-- SetPropagateMouseClicks) and "secret aura" errors in the Objective Tracker.
-- SetAlpha / EnableMouse / SetPoint run no Blizzard Lua, so nothing is tainted.
--
-- Third-party frames (RestedXP panels) still use Hide(): no secure code there.
-- ---------------------------------------------------------------------------

local extraAbilityHooked = false

local function Frames(...)
    local result = {}
    for index = 1, select("#", ...) do
        local frame = select(index, ...)
        if frame then
            result[#result + 1] = frame
        end
    end
    return result
end

-- ---------------------------------------------------------------------------
-- Alpha hiding
-- ---------------------------------------------------------------------------
local alphaState = {}      -- [frame] = { hidden, alpha, mouse = { [f] = {click, motion, wheel} } }
local settingAlpha = false -- re-entrancy guard for the SetAlpha post-hook

local function CanTouchMouse(frame)
    return not (InCombatLockdown() and frame:IsProtected())
end

-- Turn off mouse on a frame and all of its descendants so an invisible frame
-- can't be clicked, hovered or scrolled. Remembers what it changed.
local function DisableMouseTree(frame, store, depth)
    depth = depth or 0
    if depth > 8 or frame:IsForbidden() then return end

    if store[frame] == nil and frame.IsMouseClickEnabled then
        local click = frame:IsMouseClickEnabled()
        local motion = frame:IsMouseMotionEnabled()
        local wheel = frame:IsMouseWheelEnabled()
        if (click or motion or wheel) and CanTouchMouse(frame) then
            store[frame] = { click, motion, wheel }
            if click then frame:SetMouseClickEnabled(false) end
            if motion then frame:SetMouseMotionEnabled(false) end
            if wheel then frame:EnableMouseWheel(false) end
        elseif click or motion or wheel then
            addon.applyPending = true   -- protected child in combat: finish later
        end
    end

    for _, child in ipairs({ frame:GetChildren() }) do
        DisableMouseTree(child, store, depth + 1)
    end
end

local function RestoreMouseTree(store)
    for frame, saved in pairs(store) do
        if CanTouchMouse(frame) then
            if saved[1] then frame:SetMouseClickEnabled(true) end
            if saved[2] then frame:SetMouseMotionEnabled(true) end
            if saved[3] then frame:EnableMouseWheel(true) end
            store[frame] = nil
        else
            addon.applyPending = true
        end
    end
end

local function SetAlphaGuarded(frame, alpha)
    settingAlpha = true
    frame:SetAlpha(alpha)
    settingAlpha = false
end

local function GetAlphaState(frame)
    local state = alphaState[frame]
    if not state then
        state = { hidden = false, alpha = frame:GetAlpha(), mouse = {} }
        alphaState[frame] = state
        -- Blizzard (and other addons) set alpha on some of these frames
        -- (chat tab fading, action-bar override, meter fading). While we're
        -- hiding, remember the value they wanted and keep it at 0.
        hooksecurefunc(frame, "SetAlpha", function(self, alpha)
            local current = alphaState[self]
            if settingAlpha or not current or not current.hidden then return end
            if alpha and alpha > 0 then
                current.alpha = alpha
                SetAlphaGuarded(self, 0)
            end
        end)
    end
    return state
end

-- Public: hide/show a Blizzard frame without Hide()/Show().
function addon:SetFrameAlphaHidden(frame, hide)
    if not frame or frame:IsForbidden() then return end
    local state = GetAlphaState(frame)

    if hide then
        if not state.hidden then
            state.hidden = true
            state.alpha = frame:GetAlpha()
        end
        SetAlphaGuarded(frame, 0)
        -- Re-walk every time: children created since last pass get covered too.
        DisableMouseTree(frame, state.mouse)
    elseif state.hidden then
        state.hidden = false
        RestoreMouseTree(state.mouse)
        SetAlphaGuarded(frame, state.alpha or 1)
    end
end

function addon:IsFrameAlphaHidden(frame)
    local state = frame and alphaState[frame]
    return state and state.hidden or false
end

-- ---------------------------------------------------------------------------
-- Minimap: blips, quest areas and the player arrow ignore alpha, so the map
-- itself is moved off-screen (SetPoint runs no Blizzard Lua) and put back.
-- Several owners can ask for it (settings toggle, quest window); it stays
-- away until all of them let go.
-- ---------------------------------------------------------------------------
local minimapReasons = {}
local minimapSaved       -- { points = {...}, clamped = bool } while off-screen
local movingMinimap = false

local function MinimapWanted()
    return next(minimapReasons) ~= nil
end

local function SaveMinimapPoints()
    local points = {}
    for i = 1, Minimap:GetNumPoints() do
        points[i] = { Minimap:GetPoint(i) }
    end
    return points
end

local function MoveMinimapAway()
    movingMinimap = true
    Minimap:SetClampedToScreen(false)
    Minimap:ClearAllPoints()
    Minimap:SetPoint("TOPRIGHT", UIParent, "BOTTOMLEFT", -4000, -4000)
    movingMinimap = false
end

local minimapHooked = false
local function HookMinimap()
    if minimapHooked then return end
    minimapHooked = true
    -- Something re-anchored the minimap while it's away (Edit Mode, another
    -- addon): remember where it wanted to be and send it away again.
    hooksecurefunc(Minimap, "SetPoint", function()
        if movingMinimap or not minimapSaved then return end
        minimapSaved.points = SaveMinimapPoints()
        MoveMinimapAway()
    end)
end

function addon:SetMinimapAway(reason, away)
    if not Minimap or Minimap:IsForbidden() then return end
    if InCombatLockdown() and Minimap:IsProtected() then
        self.applyPending = true
        return
    end
    minimapReasons[reason] = away and true or nil

    if MinimapWanted() and not minimapSaved then
        HookMinimap()
        minimapSaved = { points = SaveMinimapPoints(), clamped = Minimap:IsClampedToScreen() }
        MoveMinimapAway()
    elseif not MinimapWanted() and minimapSaved then
        local saved = minimapSaved
        minimapSaved = nil
        movingMinimap = true
        Minimap:ClearAllPoints()
        for _, point in ipairs(saved.points) do
            Minimap:SetPoint(unpack(point))
        end
        Minimap:SetClampedToScreen(saved.clamped)
        movingMinimap = false
    end
end

-- ---------------------------------------------------------------------------
-- Groups
-- Keep all volatile Blizzard frame names here so future client changes have one patch point.
-- ---------------------------------------------------------------------------
local frameGroups = {
    chat = function()
        return Frames(
            ChatFrame1,
            ChatFrame1Tab,
            ChatFrame1ButtonFrame,
            -- ChatFrame2 is Blizzard's default Combat Log window. Its tab is a
            -- sibling of ChatFrame1, so hiding only the primary frame leaves an
            -- interactive tab that can reveal the combat log.
            ChatFrame2,
            ChatFrame2Tab,
            ChatFrame2ButtonFrame,
            ChatFrameMenuButton,
            ChatFrameChannelButton,
            QuickJoinToastButton
        )
    end,
    minimap = function()
        return Frames(MinimapCluster)
    end,
    statusBar1 = function()
        return Frames(
            MainStatusTrackingBarContainer,
            StatusTrackingBarManager and StatusTrackingBarManager.MainStatusTrackingBarContainer
        )
    end,
    statusBar2 = function()
        return Frames(
            SecondaryStatusTrackingBarContainer,
            StatusTrackingBarManager and StatusTrackingBarManager.SecondaryStatusTrackingBarContainer
        )
    end,
    microMenu = function()
        return Frames(MicroMenu, MicroMenuContainer)
    end,
    bagBar = function()
        return Frames(BagsBar)
    end,
    rxpTargets = function()
        -- "Active Targets" panel. Confirmed global from Targeting.lua:824.
        -- Also set RXP's own profile flag so IsFeatureEnabled() returns false.
        if XpieHUDDB and XpieHUDDB.hideRXPTargets then
            local rxp = _G["RXPGuides"]
            if rxp and rxp.settings and rxp.settings.profile then
                rxp.settings.profile.enableTargetFrame = false
            end
        end
        return Frames(_G["RXPTargetFrame"])
    end,
    rxpItems = function()
        -- "Active Items" panel. Confirmed global from ActiveItemFrame.lua:266.
        -- Also set RXP's own profile flag so UpdateItemFrame() returns early.
        if XpieHUDDB and XpieHUDDB.hideRXPItems then
            local rxp = _G["RXPGuides"]
            if rxp and rxp.settings and rxp.settings.profile then
                rxp.settings.profile.disableItemWindow = true
            end
        end
        return Frames(_G["RXPItemFrame"])
    end,
}

local function ApplyAlphaGroup(groupName, shouldHide)
    local seen = {}
    for _, frame in ipairs(frameGroups[groupName]()) do
        if not seen[frame] then
            seen[frame] = true
            addon:SetFrameAlphaHidden(frame, shouldHide)
        end
    end
end

-- Show()/Hide() path, for third-party (RestedXP) frames only.
local hiddenShown = {}   -- [frame] = { shouldHide, restoreShown }

local function ApplyHideFrame(frame, shouldHide, forceShow)
    local state = hiddenShown[frame]
    if not state then
        state = { shouldHide = false, restoreShown = false }
        hiddenShown[frame] = state
        frame:HookScript("OnShow", function(self)
            local current = hiddenShown[self]
            if current and current.shouldHide then
                current.restoreShown = true
                self:Hide()
            end
        end)
    end
    state.shouldHide = shouldHide

    if shouldHide then
        if frame:IsShown() then
            state.restoreShown = true
            frame:Hide()
        end
    elseif forceShow or state.restoreShown then
        state.restoreShown = false
        frame:Show()
    end
end

local function ApplyHideGroup(groupName, shouldHide, forceShow)
    for _, frame in ipairs(frameGroups[groupName]()) do
        ApplyHideFrame(frame, shouldHide, forceShow)
    end
end

-- Typing while chat is hidden: show chat while an edit box has focus.
local chatPeek = false
local chatPeekHooked = false

local function HookChatPeek()
    if chatPeekHooked then return end
    chatPeekHooked = true
    for i = 1, (NUM_CHAT_WINDOWS or 10) do
        local editBox = _G["ChatFrame" .. i .. "EditBox"]
        if editBox then
            editBox:HookScript("OnEditFocusGained", function()
                chatPeek = true
                if XpieHUDDB.hideChat then ApplyAlphaGroup("chat", false) end
            end)
            editBox:HookScript("OnEditFocusLost", function()
                chatPeek = false
                if XpieHUDDB.hideChat then ApplyAlphaGroup("chat", true) end
            end)
        end
    end
end

function addon:ApplyAll(forceShow)
    if not self.ready or not XpieHUDDB then
        return
    end

    HookChatPeek()
    ApplyAlphaGroup("chat", XpieHUDDB.hideChat and not chatPeek)
    ApplyAlphaGroup("minimap", XpieHUDDB.hideMinimap)
    self:SetMinimapAway("settings", XpieHUDDB.hideMinimap)
    ApplyAlphaGroup("statusBar1", XpieHUDDB.hideStatusBar1)
    ApplyAlphaGroup("statusBar2", XpieHUDDB.hideStatusBar2)
    ApplyAlphaGroup("microMenu", XpieHUDDB.hideMicroMenu)
    ApplyAlphaGroup("bagBar", XpieHUDDB.hideBagBar)
    ApplyHideGroup("rxpTargets", XpieHUDDB.hideRXPTargets, forceShow and not XpieHUDDB.hideRXPTargets)
    ApplyHideGroup("rxpItems", XpieHUDDB.hideRXPItems, forceShow and not XpieHUDDB.hideRXPItems)
    -- Restore RXP profile flags when panels are re-enabled
    if forceShow then
        local rxp = _G["RXPGuides"]
        if rxp and rxp.settings and rxp.settings.profile then
            if not XpieHUDDB.hideRXPTargets then
                rxp.settings.profile.enableTargetFrame = true
            end
            if not XpieHUDDB.hideRXPItems then
                rxp.settings.profile.disableItemWindow = false
            end
        end
    end
    self:ApplyExtraAbilityScale()
    self:ApplyRXP()
    if self.ApplyQuestDialog then
        self:ApplyQuestDialog()
    end
end

function addon:ApplyExtraAbilityScale()
    local frame = ExtraAbilityContainer
    if not frame then
        return
    end

    if not extraAbilityHooked then
        extraAbilityHooked = true
        frame:HookScript("OnShow", function()
            addon:ApplyExtraAbilityScale()
        end)
    end

    -- Scaling a container that owns action buttons can be restricted during
    -- combat even when the container itself does not report as protected.
    if InCombatLockdown() then
        self.applyPending = true
        return
    end

    local percent = tonumber(XpieHUDDB.extraAbilityScale) or self.defaults.extraAbilityScale
    percent = math.max(40, math.min(100, percent))
    XpieHUDDB.extraAbilityScale = percent
    frame:SetScale(percent / 100)
end
