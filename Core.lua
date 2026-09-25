local addonName, addon = ...

_G.XpieHUD = addon

addon.name = addonName
addon.defaults = {
    hideChat         = false,
    hideMinimap      = false,
    hideStatusBar1   = false,
    hideStatusBar2   = false,
    hideMicroMenu    = false,
    hideBagBar       = false,
    extraAbilityScale = 100,
    -- RestedXP transparency and borders
    rxpFrameAlpha    = 100,   -- 0–100; 100 = fully visible (default, no change)
    rxpHideBorders   = false, -- strip border/edge textures from RXP frames
    hideRXPTargets      = false, -- hide the RXP Active Targets panel
    hideRXPItems        = false, -- hide the RXP Active Items panel
    chatMeterState      = nil,    -- nil = feature unused; 0/1/2 = active state
    hideChatMeterButton = false,  -- hide the on-screen toggle button
    meterFrameName      = nil,    -- persisted meter frame global name
    -- Quest / gossip window QoL (QuestDialog.lua)
    questDialogEnabled  = true,   -- master switch
    questDialogKeys     = true,   -- 1-9 / Space keyboard shortcuts
    questDialogBadges   = true,   -- number badges on pickable options
    questDialogHideUI   = true,   -- fade the rest of the UI while talking
    questHideActionBars = true,
    questHideUnitFrames = true,
    questHideTracker    = true,
    questHideChat       = true,
    questHideMinimap    = true,
    questHideRXP        = true,
    questHideBuffs      = true,
    questDialogScale    = 100,    -- 50–150 (%)
    -- questDialogPoint = { x, y }: window centre in UIParent units; nil = Blizzard default
}

BINDING_HEADER_XPIEHUD             = "XpieHUD"
BINDING_NAME_XPIEHUD_TOGGLE_CHAT    = "Toggle Chat"
BINDING_NAME_XPIEHUD_TOGGLE_MINIMAP = "Toggle Minimap"

-- Global handler functions called by WoW's keybinding system when a key is pressed.
-- These replace the Bindings.xml <Binding> elements, whose name/header attributes are deprecated.
function XPIEHUD_TOGGLE_CHAT()    XpieHUD:Toggle("chat")    end
function XPIEHUD_TOGGLE_MINIMAP() XpieHUD:Toggle("minimap") end

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

function addon:Print(message)
    if DEFAULT_CHAT_FRAME then
        DEFAULT_CHAT_FRAME:AddMessage("|cff70d5ffXpieHUD:|r " .. message)
    end
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

function addon:Toggle(target)
    local key = target == "chat" and "hideChat" or target == "minimap" and "hideMinimap"
    if not key then return end

    self:SetOption(key, not XpieHUDDB[key])
    self:Print((target == "chat" and "Chat" or "Minimap") .. (XpieHUDDB[key] and " hidden." or " shown."))
end

function addon:ShowAll()
    for key, value in pairs(self.defaults) do
        -- Only the persistent hide options; quest window settings are left alone.
        if type(value) == "boolean" and (key:find("^hide") or key == "rxpHideBorders") then
            XpieHUDDB[key] = false
        end
    end
    self:ApplyAll(true)
    self:RefreshSettings()
    self:Print("All managed UI elements restored.")
end

function addon:Reset()
    wipe(XpieHUDDB)
    CopyDefaults()
    self.resetPendingUntil = nil
    self:ApplyAll(true)
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
    elseif command == "chat" or command == "minimap" then
        addon:Toggle(command)
    elseif command == "showall" then
        addon:ShowAll()
    elseif command == "meter" then
        addon:CycleChatMeter(arg)
    elseif command == "button" then
        addon:ToggleChatMeterButton()
    elseif command == "meterframe" then
        addon:SetMeterFrameName(arg)
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
        addon:Print("Commands: /xpiehud, chat, minimap, meter [0|1|2], button, meterframe [name], questreset, questscan, questhide [name], showall, reset")
    end
end

SLASH_XPIEHUD1 = "/xpiehud"
SLASH_XPIEHUD2 = "/xhud"
SlashCmdList.XPIEHUD = HandleSlashCommand

eventFrame:SetScript("OnEvent", function(_, event, arg1)
    if event == "ADDON_LOADED" and arg1 == addonName then
        XpieHUDDB = type(XpieHUDDB) == "table" and XpieHUDDB or {}
        CopyDefaults()
        addon:CreateSettings()
    elseif event == "ADDON_LOADED" and arg1 == "Blizzard_UIPanels_Game" and addon.ready then
        addon:ApplyAll()
    elseif event == "ADDON_LOADED" and arg1 == "RXPGuides" then
        -- RXP loaded after us; apply immediately if we're already in-world
        if addon.ready then
            C_Timer.After(0.5, function() addon:ApplyRXP() end)
        end
    elseif event == "PLAYER_LOGIN" then
        addon.ready = true
        addon:ApplyAll()
        -- RXP creates step frames lazily; schedule staggered init passes
        addon:ScheduleRXPInit()
        -- Create chat/meter toggle button and restore saved state
        addon:CreateChatMeterButton()
        -- Quest window hooks go in after the login load window (see the map-taint note)
        C_Timer.After(0, function() addon:InitQuestDialog() end)
        -- Blizzard_DamageMeter may load slightly after PLAYER_LOGIN
        C_Timer.After(1, function()
            -- Restore persisted meter frame name
            if XpieHUDDB.meterFrameName then
                addon:SetMeterFrameName(XpieHUDDB.meterFrameName)
            end
            addon:ApplyChatMeterState()
        end)
    elseif event == "PLAYER_REGEN_ENABLED" and addon.applyPending then
        addon.applyPending = nil
        addon:ApplyAll()
    end
end)
