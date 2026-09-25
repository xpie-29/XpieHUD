-- QuestDialog.lua  (XpieHUD)
-- Quality-of-life for Blizzard's native quest, gossip and book/plaque windows:
--   * saved position and scale (Shift+drag to move)
--   * fades the rest of the UI (alpha only) while one of them is open
--   * keys 1-9 pick options/quests/rewards, Space accepts/continues/completes
--   * small number badges next to the pickable options
-- Blizzard's own frames, parchment and quest themes are never replaced.
--
-- Frame names / APIs checked against wow-ui-source 12.1.0 (live):
--   UIPanelWindows["QuestFrame"/"GossipFrame"/"ItemTextFrame"] = { area = "left", pushable = 0 }
--   The panel manager positions these from a local secure delegate, so we
--   post-hook each frame's SetPoint instead of anything in the panel system.

local _, addon = ...

local DIALOG_FRAME_NAMES = { "QuestFrame", "GossipFrame", "ItemTextFrame" }
local RESTORE_DELAY  = 0.15  -- gossip -> quest swaps hide one frame before showing the next
local BADGE_GAP      = -2    -- gap between a list badge and its option icon
local MIN_SCALE, MAX_SCALE = 50, 150

local dialogFrames = {}
local initialized = false

local function IsEnabled()
    return XpieHUDDB and XpieHUDDB.questDialogEnabled
end

local function AnyDialogShown()
    for _, frame in ipairs(dialogFrames) do
        if frame:IsShown() then return true end
    end
    return false
end

-- ---------------------------------------------------------------------------
-- Position and scale
-- Position is stored as the frame centre in UIParent units, so it stays put
-- when the scale changes.
-- ---------------------------------------------------------------------------
local positioning = false   -- re-entrancy guard for the SetPoint post-hook
local scaled = {}           -- frames we have rescaled (so we can undo it)
local moving = {}

local function GetScaleSetting()
    local pct = tonumber(XpieHUDDB.questDialogScale) or addon.defaults.questDialogScale
    pct = math.max(MIN_SCALE, math.min(MAX_SCALE, pct))
    XpieHUDDB.questDialogScale = pct
    return pct / 100
end

local function ApplyScale(frame)
    if IsEnabled() then
        frame:SetScale(GetScaleSetting())
        scaled[frame] = true
    elseif scaled[frame] then
        frame:SetScale(1)
        scaled[frame] = nil
    end
end

local function ApplyPosition(frame)
    if positioning or moving[frame] then return end
    local pos = XpieHUDDB and XpieHUDDB.questDialogPoint
    if not IsEnabled() or type(pos) ~= "table" or not pos[1] then return end

    positioning = true
    local scale = frame:GetScale()
    frame:ClearAllPoints()
    frame:SetPoint("CENTER", UIParent, "BOTTOMLEFT", pos[1] / scale, pos[2] / scale)
    positioning = false
end

local function SavePosition(frame)
    local x, y = frame:GetCenter()
    if not x then return end
    local scale = frame:GetScale()
    XpieHUDDB.questDialogPoint = { math.floor(x * scale + 0.5), math.floor(y * scale + 0.5) }
end

local function HookMovement(frame)
    frame:SetMovable(true)

    frame:HookScript("OnMouseDown", function(self, button)
        if button == "LeftButton" and IsShiftKeyDown() and IsEnabled() then
            moving[self] = true
            self:StartMoving()
        end
    end)

    local function StopMoving(self)
        if not moving[self] then return end
        self:StopMovingOrSizing()
        self:SetUserPlaced(false)   -- we own the position, not the layout cache
        moving[self] = nil
        SavePosition(self)
        ApplyPosition(self)
    end
    frame:HookScript("OnMouseUp", StopMoving)
    frame:HookScript("OnHide", StopMoving)

    -- Blizzard's panel manager calls SetPoint every time it lays out the left
    -- panel area; put the window back where the player wants it afterwards.
    hooksecurefunc(frame, "SetPoint", function(self)
        ApplyPosition(self)
    end)
end

-- ---------------------------------------------------------------------------
-- Hide the rest of the UI (alpha layer)
-- Separate from Visibility.lua's Hide()/Show() state: we only touch alpha,
-- remember what it was, and put it back.
-- ---------------------------------------------------------------------------
local function Collect(list, ...)
    for index = 1, select("#", ...) do
        local frame = select(index, ...)
        if frame and frame.SetAlpha then
            list[#list + 1] = frame
        end
    end
    return list
end

local hideGroups = {
    { key = "questHideActionBars", frames = function()
        return Collect({},
            MainActionBar, MultiBarBottomLeft, MultiBarBottomRight, MultiBarRight, MultiBarLeft,
            MultiBar5, MultiBar6, MultiBar7, StanceBar, PetActionBar, PossessActionBar,
            MainMenuBarVehicleLeaveButton, MicroMenuContainer, MicroMenu, BagsBar,
            MainStatusTrackingBarContainer, SecondaryStatusTrackingBarContainer,
            ExtraAbilityContainer)
    end },
    { key = "questHideUnitFrames", frames = function()
        return Collect({}, PlayerFrame, PetFrame, TargetFrame, FocusFrame, PartyFrame, TotemFrame)
    end },
    { key = "questHideTracker", frames = function()
        return Collect({}, ObjectiveTrackerFrame)
    end },
    { key = "questHideChat", frames = function()
        -- Edit boxes are left alone so typing mid-dialog stays visible.
        local list = Collect({}, GeneralDockManager, ChatFrameMenuButton, ChatFrameChannelButton,
            QuickJoinToastButton, addon.FindMeterFrame and addon.FindMeterFrame())
        for i = 1, (NUM_CHAT_WINDOWS or 10) do
            Collect(list, _G["ChatFrame" .. i], _G["ChatFrame" .. i .. "Tab"], _G["ChatFrame" .. i .. "ButtonFrame"])
        end
        return list
    end },
    { key = "questHideMinimap", frames = function()
        return Collect({}, MinimapCluster)
    end },
    { key = "questHideRXP", frames = function()
        local rxp = _G["RXPGuides"]
        local arrow = rxp and rxp.enabledFrames and rxp.enabledFrames.arrowFrame
        return Collect({}, _G["RXPFrame"], _G["RXPTargetFrame"], _G["RXPItemFrame"], arrow)
    end },
    { key = "questHideBuffs", frames = function()
        return Collect({}, BuffFrame, DebuffFrame)
    end },
}
addon.questHideGroups = hideGroups

local faded = {}   -- [frame] = alpha to restore
local uiFaded = false

local function FadeFrame(frame)
    local current = frame:GetAlpha()
    if faded[frame] == nil or current > 0 then
        -- first fade, or something else changed the alpha since: remember theirs
        faded[frame] = current
    end
    if current ~= 0 then
        frame:SetAlpha(0)
    end
end

local function RestoreFrame(frame)
    -- If someone else changed the alpha while we were faded, keep theirs.
    if frame:GetAlpha() == 0 then
        frame:SetAlpha(faded[frame])
    end
    faded[frame] = nil
end

local function FadeUI()
    local isDialog, wanted = {}, {}
    for _, frame in ipairs(dialogFrames) do isDialog[frame] = true end

    for _, group in ipairs(hideGroups) do
        if XpieHUDDB[group.key] then
            for _, frame in ipairs(group.frames()) do
                if not isDialog[frame] then
                    wanted[frame] = true
                    FadeFrame(frame)
                end
            end
        end
    end
    -- A group was unticked while the dialog is open: bring it back now.
    for frame in pairs(faded) do
        if not wanted[frame] then RestoreFrame(frame) end
    end
    uiFaded = true
end

local function RestoreUI()
    for frame in pairs(faded) do
        RestoreFrame(frame)
    end
    uiFaded = false
end

-- ---------------------------------------------------------------------------
-- Keyboard: 1-9 and Space
-- ---------------------------------------------------------------------------
local function ClickIfUsable(button)
    if button and button:IsVisible() and button:IsEnabled() then
        button:Click("LeftButton")
        return true
    end
    return false
end

local function GetGossipScrollBox()
    local panel = GossipFrame and GossipFrame.GreetingPanel
    return panel and panel.ScrollBox
end

local function SelectGossip(number)
    local scrollBox = GetGossipScrollBox()
    local provider = scrollBox and scrollBox:GetDataProvider()
    if not provider then return false end

    local data = provider:FindElementDataByPredicate(function(elementData)
        return elementData.index == number
    end)
    if not data or not data.info then return false end

    if data.buttonType == GOSSIP_BUTTON_TYPE_AVAILABLE_QUEST then
        C_GossipInfo.SelectAvailableQuest(data.info.questID)
    elseif data.buttonType == GOSSIP_BUTTON_TYPE_ACTIVE_QUEST then
        C_GossipInfo.SelectActiveQuest(data.info.questID)
    elseif data.buttonType == GOSSIP_BUTTON_TYPE_OPTION then
        C_GossipInfo.SelectOptionByIndex(data.info.orderIndex)
    else
        return false
    end
    return true
end

-- Greeting list: active quests first, then available, matching Blizzard's layout.
local function GetGreetingButtons()
    local list = {}
    local pool = QuestFrameGreetingPanel and QuestFrameGreetingPanel.titleButtonPool
    if not pool then return list end
    for button in pool:EnumerateActive() do
        if button:IsShown() then list[#list + 1] = button end
    end
    table.sort(list, function(a, b)
        if a.isActive ~= b.isActive then return a.isActive == 1 end
        return a:GetID() < b:GetID()
    end)
    return list
end

local function GetRewardChoiceButtons()
    local list = {}
    local rewards = QuestInfoRewardsFrame
    if not (rewards and rewards.RewardButtons and rewards:IsVisible()) then return list end
    for _, button in ipairs(rewards.RewardButtons) do
        if button:IsShown() and button.type == "choice" then list[#list + 1] = button end
    end
    table.sort(list, function(a, b) return a:GetID() < b:GetID() end)
    return list
end

local function HandleNumber(number)
    if GossipFrame and GossipFrame:IsShown() then
        return SelectGossip(number)
    end
    if QuestFrame and QuestFrame:IsShown() then
        if QuestFrameGreetingPanel:IsShown() then
            return ClickIfUsable(GetGreetingButtons()[number])
        elseif QuestFrameRewardPanel:IsShown() then
            return ClickIfUsable(GetRewardChoiceButtons()[number])
        end
    end
    return false
end

local function HandleSpace()
    if QuestFrame and QuestFrame:IsShown() then
        if QuestFrameDetailPanel:IsShown() then
            -- PvP quests open a StaticPopup; let the player click those so we
            -- never taint the popup system.
            if QuestFlagsPVP() then return false end
            return ClickIfUsable(QuestFrameAcceptButton)
        elseif QuestFrameProgressPanel:IsShown() then
            return ClickIfUsable(QuestFrameCompleteButton)
        elseif QuestFrameRewardPanel:IsShown() then
            -- Quests that cost gold also confirm through a StaticPopup.
            local money = GetQuestMoneyToGet()
            if money and money > 0 then return false end
            return ClickIfUsable(QuestFrameCompleteQuestButton)
        end
    elseif ItemTextFrame and ItemTextFrame:IsShown() then
        return ClickIfUsable(ItemTextNextPageButton)
    end
    return false
end

local function HandleKey(key)
    if IsModifierKeyDown() then return false end
    if key == "SPACE" then
        return HandleSpace()
    end
    local number = tonumber(key) or tonumber(key:match("^NUMPAD(%d)$") or "")
    if number and number >= 1 and number <= 9 then
        return HandleNumber(number)
    end
    return false   -- Esc and everything else: Blizzard handles it
end

local keyFrame

local function CreateKeyFrame()
    keyFrame = CreateFrame("Frame", nil, UIParent)
    keyFrame:Hide()
    keyFrame:EnableKeyboard(true)
    keyFrame:SetPropagateKeyboardInput(true)
    keyFrame:SetScript("OnKeyDown", function(self, key)
        -- SetPropagateKeyboardInput is restricted in combat; the frame is
        -- hidden on PLAYER_REGEN_DISABLED, this is just a safety net.
        if InCombatLockdown() then return end
        self:SetPropagateKeyboardInput(not HandleKey(key))
    end)
end

-- ---------------------------------------------------------------------------
-- Number badges
-- ---------------------------------------------------------------------------
local badges = {}   -- [button] = FontString

local function SetBadge(button, number, onIcon)
    local badge = badges[button]
    if not badge then
        badge = button:CreateFontString(nil, "OVERLAY", onIcon and "NumberFontNormal" or "GameFontNormalSmall")
        local icon = button.Icon or button
        if onIcon then
            badge:SetPoint("TOPLEFT", icon, "TOPLEFT", 2, -2)
        else
            badge:SetPoint("RIGHT", icon, "LEFT", BADGE_GAP, 0)
        end
        badges[button] = badge
    end
    badge:SetText(number)
    badge:Show()
end

local function RefreshBadges()
    for _, badge in pairs(badges) do badge:Hide() end
    if not (IsEnabled() and XpieHUDDB.questDialogKeys and XpieHUDDB.questDialogBadges) then return end

    if GossipFrame and GossipFrame:IsShown() then
        local scrollBox = GetGossipScrollBox()
        if scrollBox then
            scrollBox:ForEachFrame(function(frame, elementData)
                if elementData and elementData.index and elementData.index <= 9 then
                    SetBadge(frame, elementData.index)
                end
            end)
        end
    end

    if QuestFrame and QuestFrame:IsShown() then
        if QuestFrameGreetingPanel:IsShown() then
            for number, button in ipairs(GetGreetingButtons()) do
                if number > 9 then break end
                SetBadge(button, number)
            end
        elseif QuestFrameRewardPanel:IsShown() then
            for number, button in ipairs(GetRewardChoiceButtons()) do
                if number > 9 then break end
                SetBadge(button, number, true)
            end
        end
    end
end

local function HookBadges()
    if GossipFrame and GossipFrame.Update then
        hooksecurefunc(GossipFrame, "Update", RefreshBadges)
    end
    local scrollBox = GetGossipScrollBox()
    if scrollBox and scrollBox.RegisterCallback and ScrollBoxListMixin and ScrollBoxListMixin.Event then
        scrollBox:RegisterCallback(ScrollBoxListMixin.Event.OnDataRangeChanged, RefreshBadges, addon)
    end

    for _, panel in ipairs({ QuestFrameGreetingPanel, QuestFrameDetailPanel, QuestFrameProgressPanel, QuestFrameRewardPanel }) do
        panel:HookScript("OnShow", RefreshBadges)
    end
    -- Called directly (not via OnShow) on QUEST_LOG_UPDATE / QUEST_ITEM_UPDATE.
    hooksecurefunc("QuestFrameGreetingPanel_OnShow", RefreshBadges)
    hooksecurefunc("QuestInfo_ShowRewards", RefreshBadges)
end

-- ---------------------------------------------------------------------------
-- State
-- ---------------------------------------------------------------------------
local restoreToken = 0

local function UpdateState()
    local open = IsEnabled() and AnyDialogShown()
    local inCombat = InCombatLockdown()

    if open and XpieHUDDB.questDialogHideUI and not inCombat then
        FadeUI()
    elseif uiFaded then
        RestoreUI()
    end

    if keyFrame then
        keyFrame:SetShown(open and XpieHUDDB.questDialogKeys and not inCombat)
    end
end

local function OnDialogShow(frame)
    restoreToken = restoreToken + 1
    ApplyScale(frame)
    ApplyPosition(frame)
    UpdateState()
    RefreshBadges()
end

local function OnDialogHide()
    restoreToken = restoreToken + 1
    local token = restoreToken
    C_Timer.After(RESTORE_DELAY, function()
        if token == restoreToken then
            UpdateState()
            RefreshBadges()
        end
    end)
end

local eventFrame = CreateFrame("Frame")
eventFrame:SetScript("OnEvent", function(_, event)
    if event == "PLAYER_REGEN_DISABLED" then
        if uiFaded then RestoreUI() end
        if keyFrame then keyFrame:Hide() end
    elseif event == "PLAYER_REGEN_ENABLED" then
        UpdateState()
    end
end)

-- ---------------------------------------------------------------------------
-- Public API
-- ---------------------------------------------------------------------------
function addon:InitQuestDialog()
    if initialized then return end

    for _, name in ipairs(DIALOG_FRAME_NAMES) do
        local frame = _G[name]
        if frame then
            dialogFrames[#dialogFrames + 1] = frame
            HookMovement(frame)
            frame:HookScript("OnShow", OnDialogShow)
            frame:HookScript("OnHide", OnDialogHide)
        end
    end

    CreateKeyFrame()
    HookBadges()
    eventFrame:RegisterEvent("PLAYER_REGEN_DISABLED")
    eventFrame:RegisterEvent("PLAYER_REGEN_ENABLED")

    initialized = true
    self:ApplyQuestDialog()
end

-- Called at the end of ApplyAll so settings changes take effect immediately.
function addon:ApplyQuestDialog()
    if not initialized then return end
    for _, frame in ipairs(dialogFrames) do
        ApplyScale(frame)
        if frame:IsShown() then ApplyPosition(frame) end
    end
    UpdateState()
    RefreshBadges()
end

function addon:ResetQuestDialogPosition()
    XpieHUDDB.questDialogPoint = nil
    XpieHUDDB.questDialogScale = self.defaults.questDialogScale
    self:ApplyAll()
    self:RefreshSettings()
    self:Print("Quest window position and scale reset. The position takes effect the next time the window opens.")
end
