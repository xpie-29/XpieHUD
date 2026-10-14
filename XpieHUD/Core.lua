local addonName, addon = ...

_G.XpieHUD = addon

addon.name = addonName
addon.version = C_AddOns.GetAddOnMetadata(addonName, "Version")

-- Core settings: the quest window (QuestDialog.lua). Kept at the top level of
-- XpieHUDDB so settings from 1.x/2.x carry over unchanged.
addon.defaults = {
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
    questHideRXP        = true,   -- guide addon frames from modules (pre-2.0 key name kept)
    questHideBuffs      = true,
    questDialogScale    = 100,    -- 50–150 (%)
    -- questDialogPoint = { x, y }: window centre in UIParent units; nil = Blizzard default
    -- questExtraFrames = { [FrameName] = true }: extra frames faded while talking
    -- modules = { [moduleId] = { ...module settings... } }
}

-- Settings from features removed in 2.0 (kept in the archive/full-v1.2.2
-- branch). Pruned from XpieHUDDB so saved variables stay tidy.
local OBSOLETE_KEYS = {
    "hideChat", "hideMinimap", "hideStatusBar1", "hideStatusBar2", "hideMicroMenu",
    "hideBagBar", "extraAbilityScale", "guideRXP", "rxpFrameAlpha", "rxpHideBorders",
    "rxpGoldArrow", "hideRXPTargets", "hideRXPItems", "chatMeterState",
    "hideChatMeterButton", "meterFrameName", "chatMeterButtonPos", "questTrackerWidth",
}

local function CopyDefaults(db, defaults)
    for key, value in pairs(defaults) do
        if db[key] == nil then
            db[key] = value
        end
    end
end

function addon:Print(message)
    if DEFAULT_CHAT_FRAME then
        DEFAULT_CHAT_FRAME:AddMessage("|cff70d5ffXpieHUD:|r " .. message)
    end
end

-- ---------------------------------------------------------------------------
-- Modules
-- Each extension is its own addon folder (XpieHUD_Zygor, ...) with
-- "## Dependencies: XpieHUD", so it loads after the core and only when the
-- player has it enabled. It describes itself with RegisterModule:
--
--   local module = XpieHUD:RegisterModule("zygor", {
--       title    = "Zygor Guides",           -- settings page name
--       defaults = { ... },                   -- module.db is filled from these
--       Migrate  = function(self, rootDB, db) end,  -- optional, first run only
--       OnLogin  = function(self) end,        -- optional, after PLAYER_LOGIN
--       Apply    = function(self) end,        -- re-apply after settings / combat
--       BuildSettings = function(self, page) end,   -- optional settings page
--       GetFadeFrames = function(self) return {...} end, -- optional: faded with
--                                             -- the quest window's "Guide Addons" group
--   })
-- ---------------------------------------------------------------------------
addon.modules = {}

local function InitModuleDB(module)
    XpieHUDDB.modules = XpieHUDDB.modules or {}
    local db = XpieHUDDB.modules[module.id]
    if not db then
        db = {}
        XpieHUDDB.modules[module.id] = db
        if module.Migrate then module:Migrate(XpieHUDDB, db) end
    end
    CopyDefaults(db, module.defaults or {})
    module.db = db
end

-- module:SetOption(key, value): same contract as addon:SetOption, for module.db.
local function ModuleSetOption(module, key, value)
    local default = module.defaults and module.defaults[key]
    if default == nil then return end
    if type(default) == "boolean" then
        module.db[key] = not not value
    else
        module.db[key] = value
    end
    addon:ApplyAll()
    addon:RefreshSettings()
end

function addon:RegisterModule(id, module)
    assert(type(id) == "string" and not self:GetModule(id), "XpieHUD: bad or duplicate module id")
    module.id = id
    module.SetOption = ModuleSetOption
    self.modules[#self.modules + 1] = module
    if XpieHUDDB then InitModuleDB(module) end
    -- A module that loads after login (load-on-demand) still gets started.
    if self.ready and module.OnLogin then module:OnLogin() end
    return module
end

function addon:GetModule(id)
    for _, module in ipairs(self.modules) do
        if module.id == id then return module end
    end
end

-- Frames modules want faded with the quest window's "Guide Addons" group.
function addon:GetModuleFadeFrames()
    local list = {}
    for _, module in ipairs(self.modules) do
        if module.GetFadeFrames then
            for _, frame in ipairs(module:GetFadeFrames()) do
                list[#list + 1] = frame
            end
        end
    end
    return list
end

-- ---------------------------------------------------------------------------
-- Slash commands: core + module subcommands
-- ---------------------------------------------------------------------------
addon.commands = {}   -- ordered: { verb, fn, help }

function addon:RegisterCommand(verb, fn, help)
    self.commands[#self.commands + 1] = { verb = verb:lower(), fn = fn, help = help }
end

local function HandleSlashCommand(input)
    -- Lowercase only the command word; frame-name arguments are case-sensitive.
    local verb, rest = strtrim(input or ""):match("^(%S*)%s*(.-)$")
    local command = string.lower(verb or "")
    local arg = rest ~= "" and rest or nil
    if command == "" then
        addon:OpenSettings()
        return
    end
    for _, entry in ipairs(addon.commands) do
        if entry.verb == command then
            entry.fn(arg)
            return
        end
    end
    local verbs = {}
    for _, entry in ipairs(addon.commands) do verbs[#verbs + 1] = entry.verb end
    addon:Print("Commands: /xhud, " .. table.concat(verbs, ", "))
end

SLASH_XPIEHUD1 = "/xpiehud"
SLASH_XPIEHUD2 = "/xhud"
SlashCmdList.XPIEHUD = HandleSlashCommand

addon:RegisterCommand("questreset", function() addon:ResetQuestDialogPosition() end, "Reset quest window position and size")
addon:RegisterCommand("questscan",  function() addon:ScanQuestVisibleFrames() end,  "List frames still visible during a quest window")
addon:RegisterCommand("questhide",  function(arg) addon:ToggleQuestExtraFrame(arg) end, "Add/remove a frame from the fade list")
addon:RegisterCommand("reset", function()
    local now = GetTime()
    if addon.resetPendingUntil and now <= addon.resetPendingUntil then
        addon:Reset()
    else
        addon.resetPendingUntil = now + 15
        addon:Print("Type |cffffffff/xhud reset|r again within 15 seconds to confirm.")
    end
end, "Reset all settings (confirm twice)")

-- ---------------------------------------------------------------------------
-- Options
-- ---------------------------------------------------------------------------
-- Central re-apply entry point: settings changes and post-combat catch-up.
function addon:ApplyAll()
    if not self.ready or not XpieHUDDB then
        return
    end
    self:ApplyQuestDialog()
    for _, module in ipairs(self.modules) do
        if module.Apply then module:Apply() end
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

function addon:Reset()
    wipe(XpieHUDDB)
    CopyDefaults(XpieHUDDB, self.defaults)
    for _, module in ipairs(self.modules) do InitModuleDB(module) end
    self.resetPendingUntil = nil
    self:ApplyAll()
    self:RefreshSettings()
    self:Print("Preferences reset to defaults.")
end

-- ---------------------------------------------------------------------------
-- Events
-- ---------------------------------------------------------------------------
local eventFrame = CreateFrame("Frame")
eventFrame:RegisterEvent("ADDON_LOADED")
eventFrame:RegisterEvent("PLAYER_LOGIN")
eventFrame:RegisterEvent("PLAYER_REGEN_ENABLED")

eventFrame:SetScript("OnEvent", function(_, event, arg1)
    if event == "ADDON_LOADED" and arg1 == addonName then
        XpieHUDDB = type(XpieHUDDB) == "table" and XpieHUDDB or {}
        for _, key in ipairs(OBSOLETE_KEYS) do XpieHUDDB[key] = nil end
        CopyDefaults(XpieHUDDB, addon.defaults)
        -- Modules normally register after this (they load after the core).
        for _, module in ipairs(addon.modules) do InitModuleDB(module) end
    elseif event == "PLAYER_LOGIN" then
        addon.ready = true
        -- Every module addon has loaded by now: build the core page plus one
        -- sub-page per module in a single pass.
        addon:CreateSettings()
        for _, module in ipairs(addon.modules) do
            if module.OnLogin then module:OnLogin() end
        end
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
