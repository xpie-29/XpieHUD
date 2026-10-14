local addonName, addon = ...

_G.XpieHUD = addon

addon.name = addonName
addon.defaults = {
    -- Quest / gossip window QoL (QuestDialog.lua)
    questDialogEnabled  = true,   -- master switch
    questDialogKeys     = true,   -- 1-9 / Space keyboard shortcuts
    questDialogBadges   = true,   -- number badges on pickable options
    questDialogHideUI   = true,   -- fade the rest of the UI while talking
    questTooltipCursor  = true,   -- default-anchored tooltips follow the cursor while talking
    questHideActionBars = true,
    questHideUnitFrames = true,
    questHideTracker    = true,
    questHideChat       = true,
    questHideMinimap    = true,
    questHideRXP        = true,   -- the Zygor guide (pre-2.0 key name kept so saved choices carry over)
    questHideBuffs      = true,
    questDialogScale    = 100,    -- 50–150 (%)
    -- questDialogPoint = { x, y }: window centre in UIParent units; nil = Blizzard default
    -- questExtraFrames = { [FrameName] = true }: extra frames faded while talking

    -- Zygor Guides Viewer (Zygor.lua)
    guideZygor          = true,   -- master switch for the Zygor integration
    zygorStrip          = true,   -- transparent window chrome, step boxes at 50%
    zygorGoldArrow      = true,   -- "XpieHUD Gold" arrow skin
    -- zygorPrevArrowSkin: the Zygor arrow skin to restore when zygorGoldArrow is off
}

-- Settings from features removed in 2.0 (kept in the archive/full-v1.2.2
-- branch). Pruned from XpieHUDDB so saved variables stay tidy.
local OBSOLETE_KEYS = {
    "hideChat", "hideMinimap", "hideStatusBar1", "hideStatusBar2", "hideMicroMenu",
    "hideBagBar", "extraAbilityScale", "guideRXP", "rxpFrameAlpha", "rxpHideBorders",
    "rxpGoldArrow", "hideRXPTargets", "hideRXPItems", "chatMeterState",
    "hideChatMeterButton", "meterFrameName", "chatMeterButtonPos", "questTrackerWidth",
}

local eventFrame = CreateFrame("Frame")
eventFrame:RegisterEvent("ADDON_LOADED")
eventFrame:RegisterEvent("PLAYER_LOGIN")
eventFrame:RegisterEvent("PLAYER_REGEN_ENABLED")

local function CopyDefaults()
    for key, value in pairs(addon.defaults) do
        if XpieHUDDB[key] == nil then
            XpieHUDDB[key] = value
        end
    end
end

local function PruneObsolete()
    for _, key in ipairs(OBSOLETE_KEYS) do
        XpieHUDDB[key] = nil
    end
end

function addon:Print(message)
    if DEFAULT_CHAT_FRAME then
        DEFAULT_CHAT_FRAME:AddMessage("|cff70d5ffXpieHUD:|r " .. message)
    end
end

-- Central re-apply entry point: settings changes and post-combat catch-up.
function addon:ApplyAll()
    if not self.ready or not XpieHUDDB then
        return
    end
    self:ApplyQuestDialog()
    self:ApplyZygor()
end

function addon:SetOption(key, value)
    if self.defaults[key] == nil then return end

    if type(self.defaults[key]) == "boolean" then
        XpieHUDDB[key] = not not value
    else
        XpieHUDDB[key] = value
    end
    self:ApplyAll()
    self:RefreshSettings()
end

function addon:Reset()
    wipe(XpieHUDDB)
    CopyDefaults()
    self.resetPendingUntil = nil
    self:ApplyAll()
    self:RefreshSettings()
    self:Print("Preferences reset to defaults.")
end

local function HandleSlashCommand(input)
    -- Lowercase only the command word; frame-name arguments are case-sensitive.
    local verb, rest = strtrim(input or ""):match("^(%S*)%s*(.-)$")
    local command = string.lower(verb or "")
    local arg = rest ~= "" and rest or nil
    if command == "" then
        addon:OpenSettings()
    elseif command == "questreset" then
        addon:ResetQuestDialogPosition()
    elseif command == "questhide" then
        addon:ToggleQuestExtraFrame(arg)
    elseif command == "questscan" then
        addon:ScanQuestVisibleFrames()
    elseif command == "reset" then
        local now = GetTime()
        if addon.resetPendingUntil and now <= addon.resetPendingUntil then
            addon:Reset()
        else
            addon.resetPendingUntil = now + 15
            addon:Print("Type |cffffffff/xpiehud reset|r again within 15 seconds to confirm.")
        end
    else
        addon:Print("Commands: /xpiehud, questreset, questscan, questhide [name], reset")
    end
end

SLASH_XPIEHUD1 = "/xpiehud"
SLASH_XPIEHUD2 = "/xhud"
SlashCmdList.XPIEHUD = HandleSlashCommand

eventFrame:SetScript("OnEvent", function(_, event, arg1)
    if event == "ADDON_LOADED" and arg1 == addonName then
        XpieHUDDB = type(XpieHUDDB) == "table" and XpieHUDDB or {}
        PruneObsolete()
        CopyDefaults()
        addon:CreateSettings()
        -- Zygor normally loads after us (alphabetical); if it somehow loaded
        -- first, hook it now.
        if C_AddOns.IsAddOnLoaded("ZygorGuidesViewer") then
            addon:OnZygorLoaded()
        end
    elseif event == "ADDON_LOADED" and arg1 == "ZygorGuidesViewer" then
        -- Before Zygor builds its window: register our arrow skin, hook step frames.
        addon:OnZygorLoaded()
    elseif event == "PLAYER_LOGIN" then
        addon.ready = true
        -- Zygor builds its window and arrow in a background thread after login
        addon:ScheduleZygorInit()
        -- Quest window hooks go in just after login (out of the load window)
        C_Timer.After(0, function()
            addon:InitQuestDialog()
            addon:ApplyAll()
        end)
    elseif event == "PLAYER_REGEN_ENABLED" and addon.applyPending then
        addon.applyPending = nil
        addon:ApplyAll()
    end
end)
