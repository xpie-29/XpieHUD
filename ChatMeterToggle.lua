-- ChatMeterToggle.lua  (XpieHUD)
-- 3-state cycle for Chat and the native Blizzard Damage Meter:
--   State 0 — Chat ON,   Meter OFF  (default)
--   State 1 — Chat OFF,  Meter ON
--   State 2 — Chat OFF,  Meter OFF  (clean screen)
--
-- Chat visibility is handled by the existing frameGroup in Visibility.lua.
-- This module only manages the meter frame and the toggle button.
-- State is stored in XpieHUDDB.chatMeterState (nil = untouched / 0).

local _, addon = ...

-- ---------------------------------------------------------------------------
-- State table
-- ---------------------------------------------------------------------------
local STATES = {
    [0] = { chat = true,  meter = false, label = "C", tip = "Chat On  |  Meter Off"  },
    [1] = { chat = false, meter = true,  label = "M", tip = "Chat Off |  Meter On"   },
    [2] = { chat = false, meter = false, label = "-", tip = "Chat Off |  Meter Off"  },
}
local NUM_STATES = 3

-- ---------------------------------------------------------------------------
-- Meter frame finder
-- Tries several known globals for the Blizzard native damage meter.
-- ---------------------------------------------------------------------------
-- Cached meter frame reference (set by ScanForMeterFrame or SetMeterName)
local meterFrameName = nil

-- Try these first before scanning
local METER_FRAME_CANDIDATES = {
    "DamageMeterFrame",
    "Blizzard_DamageMeterFrame",
    "CombatLogMeterFrame",
    "DamageMeter",
    "Blizzard_DamageMeter",
}

local function FindMeterFrame()
    -- Use cached name if set
    if meterFrameName and _G[meterFrameName] then
        return _G[meterFrameName], meterFrameName
    end
    -- Try known candidates
    for _, name in ipairs(METER_FRAME_CANDIDATES) do
        if _G[name] then
            meterFrameName = name
            return _G[name], name
        end
    end
    return nil, nil
end
addon.FindMeterFrame = FindMeterFrame   -- QuestDialog.lua fades the meter with the chat group

local meterOnShowHooked = false

local function SetMeterVisible(show)
    local f = FindMeterFrame()
    if not f then return end

    if show then
        f:Show()
    else
        f:Hide()
        -- Hook OnShow so data-driven re-shows are immediately suppressed
        if not meterOnShowHooked then
            meterOnShowHooked = true
            f:HookScript("OnShow", function(self)
                if XpieHUDDB and XpieHUDDB.chatMeterState then
                    local def = STATES[XpieHUDDB.chatMeterState]
                    if def and not def.meter then
                        self:Hide()
                    end
                end
            end)
        end
    end
end

-- Set meter frame name manually (from /xhud meterframe <name>)
function addon:SetMeterFrameName(name)
    if name and name ~= "" then
        if _G[name] then
            meterFrameName = name
            XpieHUDDB.meterFrameName = name  -- persist across sessions
            self:Print("Meter frame set to: |cffffffff" .. name .. "|r")
        else
            self:Print("Frame not found: " .. name .. ". Check spelling.")
        end
    else
        self:PrintMeterFrame()
    end
end

-- ---------------------------------------------------------------------------
-- Apply a state
-- Chat is handled by routing through ApplyAll so the existing frameGroup
-- logic (OnShow hooks, combat lockdown handling) does the work correctly.
-- ---------------------------------------------------------------------------
local function ApplyState(state)
    local def = STATES[state]
    if not def then return end

    XpieHUDDB.chatMeterState = state
    -- Drive the existing chat hide flag — ApplyAll will enforce it
    XpieHUDDB.hideChat = not def.chat

    -- Meter is not protected so we can toggle directly
    SetMeterVisible(def.meter)

    -- Re-run the full visibility pass so chat picks up the new hideChat value
    if addon.ready then
        addon:ApplyAll()
    end

    -- Update button
    if addon.chatMeterButton then
        addon.chatMeterButton.label:SetText(def.label)
    end
end

function addon:CycleChatMeter(targetState)
    local current = XpieHUDDB.chatMeterState or 0
    local next
    if targetState == nil then
        next = (current + 1) % NUM_STATES
    else
        next = tonumber(targetState)
        if not next or not STATES[next] then
            self:Print("Valid states: 0 (chat on/meter off), 1 (chat off/meter on), 2 (both off)")
            return
        end
    end
    ApplyState(next)
    local def = STATES[next]
    self:Print("State " .. next .. ": " .. def.tip)
end

function addon:ApplyChatMeterState()
    -- Restore saved state on login. Meter frame may not exist yet at PLAYER_LOGIN
    -- so this is called via a 1s deferred timer from Core.lua.
    -- A second attempt at 5s catches meters that load very late.
    local state = XpieHUDDB.chatMeterState
    if state == nil then return end
    local def = STATES[state]
    -- SetMeterVisible(false) installs the OnShow hook; always call it when hiding
    SetMeterVisible(def.meter)
    if addon.chatMeterButton then
        addon.chatMeterButton.label:SetText(def.label)
    end
    -- If meter frame wasn't found yet, retry once more
    if not def.meter and not FindMeterFrame() then
        C_Timer.After(4, function()
            local s = XpieHUDDB.chatMeterState
            if s and not STATES[s].meter then
                SetMeterVisible(false)
            end
        end)
    end
end

-- Scan _G for frames containing "meter" or "damage" and print results
function addon:PrintMeterFrame()
    local f, name = FindMeterFrame()
    if f then
        self:Print("Meter frame: |cffffffff" .. name .. "|r")
        return
    end
    -- Live scan
    local found = {}
    for k, v in pairs(_G) do
        if type(k) == "string" and type(v) == "table" and v.Show and v.Hide then
            local lk = k:lower()
            if lk:find("meter") or (lk:find("damage") and lk:find("frame")) then
                found[#found + 1] = k
            end
        end
    end
    if #found == 0 then
        self:Print("No meter frames found in _G. Is the Damage Meter enabled in Gameplay options?")
    else
        self:Print("Found " .. #found .. " candidate(s):")
        for _, k in ipairs(found) do
            self:Print("  |cffffffff" .. k .. "|r  — use: /xhud meterframe " .. k)
        end
    end
end

-- ---------------------------------------------------------------------------
-- Movable toggle button
-- Using a simple Frame rather than Button to avoid template quirks,
-- with manual click detection via OnMouseUp.
-- ---------------------------------------------------------------------------
local BUTTON_SIZE = 24

local function SaveButtonPosition()
    local b = addon.chatMeterButton
    if not b then return end
    local point, _, relPoint, x, y = b:GetPoint()
    XpieHUDDB.chatMeterButtonPos = { point, relPoint, math.floor(x), math.floor(y) }
end

local function RestoreButtonPosition()
    local b = addon.chatMeterButton
    if not b then return end
    local p = XpieHUDDB.chatMeterButtonPos
    if p then
        b:ClearAllPoints()
        b:SetPoint(p[1], UIParent, p[2], p[3], p[4])
    end
end

function addon:CreateChatMeterButton()
    if self.chatMeterButton then return end

    local b = CreateFrame("Frame", "XpieHUDChatMeterToggle", UIParent, "BackdropTemplate")
    self.chatMeterButton = b

    b:SetSize(BUTTON_SIZE, BUTTON_SIZE)
    b:SetFrameStrata("HIGH")
    b:SetClampedToScreen(true)
    b:SetMovable(true)
    b:EnableMouse(true)

    b:SetBackdrop({
        bgFile   = "Interface/ChatFrame/ChatFrameBackground",
        edgeFile = "Interface/Tooltips/UI-Tooltip-Border",
        edgeSize = 8,
        insets   = { left = 2, right = 2, top = 2, bottom = 2 },
    })
    b:SetBackdropColor(0, 0, 0, 0.6)
    b:SetBackdropBorderColor(0.4, 0.4, 0.4, 0.9)

    b.label = b:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    b.label:SetPoint("CENTER", b, 0, 0)
    local state = XpieHUDDB.chatMeterState or 0
    b.label:SetText(STATES[state].label)

    -- Highlight texture on hover
    b.highlight = b:CreateTexture(nil, "HIGHLIGHT")
    b.highlight:SetAllPoints()
    b.highlight:SetColorTexture(1, 1, 1, 0.15)

    b:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", 4, 100)
    RestoreButtonPosition()

    local dragging = false

    b:SetScript("OnMouseDown", function(self, btn)
        if btn == "LeftButton" then
            dragging = false
        elseif btn == "RightButton" then
            self:StartMoving()
            dragging = true
        end
    end)

    b:SetScript("OnMouseUp", function(self, btn)
        if btn == "RightButton" then
            self:StopMovingOrSizing()
            SaveButtonPosition()
            dragging = false
        elseif btn == "LeftButton" and not dragging then
            addon:CycleChatMeter()
        end
    end)

    b:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText("Chat / Meter", 1, 1, 1)
        local s = XpieHUDDB.chatMeterState or 0
        GameTooltip:AddLine(STATES[s].tip, 0.8, 0.8, 0.8)
        GameTooltip:AddLine("Left-click: cycle  |  Right-drag: move", 0.5, 0.5, 0.5)
        GameTooltip:Show()
    end)
    b:SetScript("OnLeave", function() GameTooltip:Hide() end)

    if XpieHUDDB.hideChatMeterButton then
        b:Hide()
    else
        b:Show()
    end
end

function addon:ToggleChatMeterButton()
    XpieHUDDB.hideChatMeterButton = not XpieHUDDB.hideChatMeterButton
    if self.chatMeterButton then
        if XpieHUDDB.hideChatMeterButton then
            self.chatMeterButton:Hide()
        else
            self.chatMeterButton:Show()
        end
    end
    self:Print("Chat/Meter button " .. (XpieHUDDB.hideChatMeterButton and "hidden." or "shown."))
end
