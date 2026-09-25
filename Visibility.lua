local _, addon = ...

local managed = {}
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

-- Keep all volatile Blizzard frame names here so future client changes have one patch point.
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

local function IsRestricted(frame)
    return InCombatLockdown() and frame.IsProtected and frame:IsProtected()
end

local function GetState(frame)
    local state = managed[frame]
    if not state then
        state = { shouldHide = false, restoreShown = false }
        managed[frame] = state

        frame:HookScript("OnShow", function(self)
            local current = managed[self]
            if not current or not current.shouldHide then
                return
            end
            current.restoreShown = true
            if IsRestricted(self) then
                addon.applyPending = true
            else
                self:Hide()
            end
        end)
    end
    return state
end

local function ApplyFrame(frame, shouldHide, forceShow)
    if not frame then
        return
    end

    local state = GetState(frame)
    state.shouldHide = shouldHide

    if IsRestricted(frame) then
        addon.applyPending = true
        return
    end

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

local function ApplyGroup(groupName, shouldHide, forceShow)
    local seen = {}
    for _, frame in ipairs(frameGroups[groupName]()) do
        if frame and not seen[frame] then
            seen[frame] = true
            ApplyFrame(frame, shouldHide, forceShow)
        end
    end
end

function addon:ApplyAll(forceShow)
    if not self.ready or not XpieHUDDB then
        return
    end

    ApplyGroup("chat", XpieHUDDB.hideChat, forceShow and not XpieHUDDB.hideChat)
    ApplyGroup("minimap", XpieHUDDB.hideMinimap, forceShow and not XpieHUDDB.hideMinimap)
    ApplyGroup("statusBar1", XpieHUDDB.hideStatusBar1, forceShow and not XpieHUDDB.hideStatusBar1)
    ApplyGroup("statusBar2", XpieHUDDB.hideStatusBar2, forceShow and not XpieHUDDB.hideStatusBar2)
    ApplyGroup("microMenu", XpieHUDDB.hideMicroMenu, forceShow and not XpieHUDDB.hideMicroMenu)
    ApplyGroup("bagBar", XpieHUDDB.hideBagBar, forceShow and not XpieHUDDB.hideBagBar)
    ApplyGroup("rxpTargets", XpieHUDDB.hideRXPTargets, forceShow and not XpieHUDDB.hideRXPTargets)
    ApplyGroup("rxpItems", XpieHUDDB.hideRXPItems, forceShow and not XpieHUDDB.hideRXPItems)
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
