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
local BADGE_ICON_ALPHA = 0.3 -- option icon alpha under a number badge
local HINT_GAP       = 5     -- gap between a Space/Esc hint and its button
local HINT_Y         = -2    -- vertical nudge to line hints up with the button text (tuned in game)
local BADGE_Y        = -1.5  -- vertical nudge to line option badges up with their text (tuned in game)
local QUEST_BADGE_X  = -1    -- quest-icon number: offset from the icon's bottom-left corner
local QUEST_BADGE_Y  = -1
local MIN_SCALE, MAX_SCALE = 50, 150

local dialogFrames = {}
local initialized = false
local inCombat = false

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

    local function StopMoving(self)
        if not moving[self] then return end
        self:StopMovingOrSizing()
        self:SetUserPlaced(false)   -- we own the position, not the layout cache
        moving[self] = nil
        SavePosition(self)
        ApplyPosition(self)
    end

    -- Invisible drag handle over the title bar (between portrait and close
    -- button). Clicks on the frame body land on Blizzard's scroll frames, so
    -- a modifier-drag on the frame itself never fires.
    local handle = CreateFrame("Frame", nil, frame)
    handle:SetPoint("TOPLEFT", frame, "TOPLEFT", 60, 0)
    handle:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -28, 0)
    handle:SetHeight(22)
    handle:SetFrameLevel(frame:GetFrameLevel() + 10)
    handle:EnableMouse(true)
    handle:RegisterForDrag("LeftButton")
    handle:SetScript("OnDragStart", function()
        if not IsEnabled() then return end
        moving[frame] = true
        frame:StartMoving()
    end)
    handle:SetScript("OnDragStop", function() StopMoving(frame) end)
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
        if type(frame) == "table" and frame.SetAlpha then
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
            MainMenuBarVehicleLeaveButton, MicroMenuContainer, MicroMenu, BagsBar, MicroButtonAndBagsBar,
            MainStatusTrackingBarContainer, SecondaryStatusTrackingBarContainer,
            ExtraAbilityContainer)
    end },
    { key = "questHideUnitFrames", frames = function()
        return Collect({}, PlayerFrame, PetFrame, TargetFrame, FocusFrame, PartyFrame, TotemFrame,
            PersonalResourceDisplayFrame)
    end },
    { key = "questHideTracker", frames = function()
        return Collect({}, ObjectiveTrackerFrame)
    end },
    { key = "questHideChat", frames = function()
        -- Edit boxes are left alone so typing mid-dialog stays visible.
        local list = Collect({}, GeneralDockManager, ChatFrameMenuButton, ChatFrameChannelButton,
            QuickJoinToastButton, addon.chatMeterButton, addon.FindMeterFrame and addon.FindMeterFrame())
        for i = 1, (NUM_CHAT_WINDOWS or 10) do
            Collect(list, _G["ChatFrame" .. i], _G["ChatFrame" .. i .. "Tab"], _G["ChatFrame" .. i .. "ButtonFrame"])
        end
        return list
    end },
    { key = "questHideMinimap", frames = function()
        return Collect({}, MinimapCluster)
    end },
    -- "Guide Addons": whichever guide addons are ticked in the guide selector.
    -- (Key kept as questHideRXP so existing settings carry over.)
    { key = "questHideRXP", frames = function()
        local list = {}
        if XpieHUDDB.guideRXP then
            local rxp = _G["RXPGuides"]
            local arrow = rxp and rxp.enabledFrames and rxp.enabledFrames.arrowFrame
            -- RXPG_ARROW: the waypoint arrow (map.lua). RXP only touches its alpha on
            -- state changes, so a fade sticks.
            Collect(list, _G["RXPFrame"], _G["RXPTargetFrame"], _G["RXPItemFrame"], _G["RXPG_ARROW"], arrow)
        end
        if addon.GetZygorFrames then
            Collect(list, unpack(addon:GetZygorFrames()))
        end
        return list
    end },
    { key = "questHideBuffs", frames = function()
        return Collect({}, BuffFrame, DebuffFrame)
    end },
    -- Frames added by name with /xhud questhide <FrameName> (e.g. other addons' panels).
    { key = "questDialogHideUI", frames = function()
        local list = {}
        if type(XpieHUDDB.questExtraFrames) == "table" then
            for name in pairs(XpieHUDDB.questExtraFrames) do
                Collect(list, _G[name])
            end
        end
        return list
    end },
}
addon.questHideGroups = hideGroups

local faded = {}   -- [frame] = alpha to restore
local uiFaded = false
local chatPeek = false   -- a chat edit box has focus: keep the chat group visible

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
        if XpieHUDDB[group.key] and not (chatPeek and group.key == "questHideChat") then
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

-- The minimap draws blips, quest areas and the player arrow outside normal
-- alpha inheritance, so fading MinimapCluster leaves them floating. It's moved
-- off-screen instead (Visibility.lua; no Hide(), which would run Blizzard's
-- minimap scripts as XpieHUD and taint them).
local function FadeUIAll()
    FadeUI()
    addon:SetMinimapAway("quest", XpieHUDDB.questHideMinimap)
end

local function RestoreUI()
    for frame in pairs(faded) do
        RestoreFrame(frame)
    end
    addon:SetMinimapAway("quest", false)
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
-- Badges sit ON the icon: the gossip/greeting lists clip anything left of it,
-- and nudging Blizzard's text over would break the scroll box's row heights.
-- Three styles:
--   "option": gossip options; icon dimmed, gold number centred on it
--   "quest":  available/active quests; Blizzard's real icon (!, ?, daily,
--             campaign, ...) at full alpha with a small outlined gold number
--             on its bottom-left corner, so new vs turn-in stays readable
--   "reward": reward choices; number in the item icon's top-left corner
local badges = {}        -- [button] = FontString
local dimmedIcons = {}   -- [texture] = true

local BADGE_STYLES = {
    option = { font = "GameFontNormal",         point = "CENTER",     x = 0,             y = BADGE_Y,       dim = true },
    quest  = { font = "NumberFontNormalSmall",  point = "BOTTOMLEFT", x = QUEST_BADGE_X, y = QUEST_BADGE_Y, gold = true },
    reward = { font = "NumberFontNormal",       point = "TOPLEFT",    x = 2,             y = -2 },
}

local function SetBadge(button, number, styleName)
    local style = BADGE_STYLES[styleName]
    local icon = button.Icon
    local badge = badges[button]
    if not badge then
        badge = button:CreateFontString(nil, "OVERLAY")
        badges[button] = badge
    end
    -- Pooled buttons can change role between refreshes; re-style when needed.
    if badge.xhudStyle ~= styleName then
        badge.xhudStyle = styleName
        badge:SetFontObject(style.font)
        if style.gold then
            badge:SetTextColor(NORMAL_FONT_COLOR:GetRGB())
        end
        badge:ClearAllPoints()
        badge:SetPoint(style.point, icon or button, style.point, style.x, style.y)
    end
    if icon and style.dim then
        icon:SetAlpha(BADGE_ICON_ALPHA)
        dimmedIcons[icon] = true
    end
    badge:SetText(number)
    badge:Show()
end

-- Subtle key hints next to Blizzard's own bottom buttons. Space hints sit to
-- the right of the left-hand button, Esc hints to the left of the right-hand one.
local keyHints = {}   -- [button] = FontString

local function GetHintButtons()
    return {
        { QuestFrameAcceptButton,        "Space", true },
        { QuestFrameCompleteButton,      "Space", true },
        { QuestFrameCompleteQuestButton, "Space", true },
        { QuestFrameDeclineButton,         "Esc", false },
        { QuestFrameGoodbyeButton,         "Esc", false },
        { QuestFrameGreetingGoodbyeButton, "Esc", false },
        { GossipFrame and GossipFrame.GreetingPanel and GossipFrame.GreetingPanel.GoodbyeButton, "Esc", false },
    }
end

local function SpaceWouldAct()
    if QuestFrameDetailPanel and QuestFrameDetailPanel:IsShown() then
        return not QuestFlagsPVP()
    elseif QuestFrameRewardPanel and QuestFrameRewardPanel:IsShown() then
        local money = GetQuestMoneyToGet()
        return not (money and money > 0)
    end
    return true
end

local function RefreshKeyHints(show)
    for _, entry in ipairs(GetHintButtons()) do
        local button, text, isLeftButton = entry[1], entry[2], entry[3]
        if button then
            local hint = keyHints[button]
            if not hint and show then
                hint = button:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
                if isLeftButton then
                    hint:SetPoint("LEFT", button, "RIGHT", HINT_GAP, HINT_Y)
                else
                    hint:SetPoint("RIGHT", button, "LEFT", -HINT_GAP, HINT_Y)
                end
                hint:SetText(text)
                keyHints[button] = hint
            end
            if hint then
                hint:SetShown(show and (text ~= "Space" or SpaceWouldAct()))
            end
        end
    end
end

local function RefreshBadges()
    for _, badge in pairs(badges) do badge:Hide() end
    for icon in pairs(dimmedIcons) do icon:SetAlpha(1) end
    wipe(dimmedIcons)

    local show = IsEnabled() and XpieHUDDB.questDialogKeys and XpieHUDDB.questDialogBadges
        and not (inCombat or InCombatLockdown())
    RefreshKeyHints(show)
    if not show then return end

    if GossipFrame and GossipFrame:IsShown() then
        local scrollBox = GetGossipScrollBox()
        if scrollBox then
            scrollBox:ForEachFrame(function(frame, elementData)
                if elementData and elementData.index and elementData.index <= 9 then
                    local isQuest = elementData.buttonType == GOSSIP_BUTTON_TYPE_AVAILABLE_QUEST
                        or elementData.buttonType == GOSSIP_BUTTON_TYPE_ACTIVE_QUEST
                    SetBadge(frame, elementData.index, isQuest and "quest" or "option")
                end
            end)
        end
    end

    if QuestFrame and QuestFrame:IsShown() then
        if QuestFrameGreetingPanel:IsShown() then
            for number, button in ipairs(GetGreetingButtons()) do
                if number > 9 then break end
                SetBadge(button, number, "quest")   -- greeting lists are all quests
            end
        elseif QuestFrameRewardPanel:IsShown() then
            for number, button in ipairs(GetRewardChoiceButtons()) do
                if number > 9 then break end
                SetBadge(button, number, "reward")
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
    local combat = inCombat or InCombatLockdown()

    if open and XpieHUDDB.questDialogHideUI and not combat then
        FadeUIAll()
    elseif uiFaded then
        RestoreUI()
    end

    if keyFrame then
        keyFrame:SetShown(open and XpieHUDDB.questDialogKeys and not combat)
    end
end

local function OnDialogShow(frame)
    restoreToken = restoreToken + 1
    ApplyScale(frame)
    ApplyPosition(frame)
    UpdateState()
    RefreshBadges()
    if addon.questScanArmed then
        addon.questScanArmed = nil
        C_Timer.After(0.5, function()
            if AnyDialogShown() then addon:ScanQuestVisibleFrames() end
        end)
    end
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
        inCombat = true   -- InCombatLockdown() can still be false during this event
        if uiFaded then RestoreUI() end
        if keyFrame then keyFrame:Hide() end
        RefreshBadges()
    elseif event == "PLAYER_REGEN_ENABLED" then
        inCombat = false
        UpdateState()
        RefreshBadges()
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

    -- With the UI faded, tooltips at their usual corner feel detached; put
    -- default-anchored tooltips (units, world objects) at the cursor instead.
    hooksecurefunc("GameTooltip_SetDefaultAnchor", function(tooltip, parent)
        if not (tooltip and tooltip.SetOwner) or tooltip:IsForbidden() then return end
        if parent and parent.IsForbidden and parent:IsForbidden() then return end
        if XpieHUDDB.questTooltipCursor and IsEnabled() and AnyDialogShown() then
            tooltip:SetOwner(parent, "ANCHOR_CURSOR")
        end
    end)

    -- Typing mid-dialog: show chat while an edit box has focus, re-fade after.
    for i = 1, (NUM_CHAT_WINDOWS or 10) do
        local editBox = _G["ChatFrame" .. i .. "EditBox"]
        if editBox then
            editBox:HookScript("OnEditFocusGained", function()
                chatPeek = true
                if uiFaded then UpdateState() end
            end)
            editBox:HookScript("OnEditFocusLost", function()
                chatPeek = false
                if uiFaded then UpdateState() end
            end)
        end
    end
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

-- /xhud questhide <FrameName>: toggle an extra frame (by global name) in the
-- fade list. Names are case-sensitive.
function addon:ToggleQuestExtraFrame(name)
    if not name or name == "" then
        local names = {}
        for extra in pairs(XpieHUDDB.questExtraFrames or {}) do names[#names + 1] = extra end
        table.sort(names)
        self:Print("Extra frames faded while talking: " .. (#names > 0 and table.concat(names, ", ") or "none"))
        self:Print("Usage: /xhud questhide <FrameName>   (find names with /xhud questscan while a quest window is open)")
        return
    end
    XpieHUDDB.questExtraFrames = XpieHUDDB.questExtraFrames or {}
    if XpieHUDDB.questExtraFrames[name] then
        XpieHUDDB.questExtraFrames[name] = nil
        local frame = _G[name]
        if type(frame) == "table" and faded[frame] ~= nil then RestoreFrame(frame) end
        self:Print("No longer fading |cffffffff" .. name .. "|r.")
    else
        if type(_G[name]) ~= "table" or not _G[name].SetAlpha then
            self:Print("No frame named |cffffffff" .. name .. "|r right now (names are case-sensitive). Saved anyway; it'll be used if it appears.")
        else
            self:Print("Now fading |cffffffff" .. name .. "|r while talking.")
        end
        XpieHUDDB.questExtraFrames[name] = true
    end
    UpdateState()
end

-- /xhud questscan: list what's still visible on UIParent while a quest window
-- is open, so stragglers from other addons can be added with questhide.
-- Run it with no window open and it arms itself for the next NPC you talk to
-- (no typing needed mid-dialog). Output lands in chat, readable after closing.
local function DescribeChild(child)
    if child:IsForbidden() or not child:IsVisible() or child:GetEffectiveAlpha() <= 0.05 then return end
    local w, h = child:GetSize()
    local left, top = child:GetLeft(), child:GetTop()
    if not (w and h and left and top) or w * h < 400 then return end
    local label = child:GetName()
    if not label then
        label = "<unnamed> " .. (child.GetDebugName and child:GetDebugName() or "?")
    end
    return { label = label, area = w * h,
             text = string.format("  |cffffffff%s|r  %dx%d at (%d, %d)", label, w, h, left, top) }
end

function addon:ScanQuestVisibleFrames()
    if not AnyDialogShown() then
        self.questScanArmed = true
        self:Print("Scan armed: talk to any NPC and the scan runs automatically. The results appear in chat once the window closes.")
        return
    end
    self.questScanArmed = nil

    local skip = {}
    for _, frame in ipairs(dialogFrames) do skip[frame] = true end
    if keyFrame then skip[keyFrame] = true end

    local found, skipped = {}, 0
    for _, child in ipairs({ UIParent:GetChildren() }) do
        if not skip[child] and not faded[child] then
            -- Some frames refuse inspection (forbidden / secret values); skip them.
            local ok, entry = pcall(DescribeChild, child)
            if ok and entry then
                found[#found + 1] = entry
            elseif not ok then
                skipped = skipped + 1
            end
        end
    end
    table.sort(found, function(a, b) return a.area > b.area end)

    self:Print(#found .. " visible frame(s) on UIParent, largest first" ..
        (skipped > 0 and (" (" .. skipped .. " couldn't be inspected)") or "") .. ":")
    for index, entry in ipairs(found) do
        if index > 20 then break end
        self:Print(entry.text)
    end
end
