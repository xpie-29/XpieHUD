-- Lists.lua  (XpieHUD_Parchment, phase 3: gossip and quest greeting lists)
-- Draws the gossip window (greeting text, available / active quests, options)
-- and the quest greeting panel (greeting text, Current / Available Quests) on
-- the parchment, from the same data Blizzard uses, in the same order and
-- numbering:
--   gossip:   GossipFrame.GreetingPanel.ScrollBox's data provider (built by
--             GossipFrame:Update: available quests, active quests, options)
--   greeting: GetGreetingText, GetActiveTitle / GetAvailableQuestInfo ...
-- Rows click the same functions Blizzard's buttons call. Icons come from
-- QuestUtil (campaign, important, legendary, meta, daily, low level ...),
-- low-level / ignored quests use Blizzard's own display strings and dimmed
-- icon. Number badges (1-19) sit left of each icon; keys come through Core.
-- Blizzard's own list stays alive (Core's Blizzard-style path and other
-- addons read it) but is moved out of view and made transparent.
-- Text appears instantly (no typewriter), so voice-over addons stay in sync.

local core = XpieHUD
local module = core:GetModule("parchment")
local R = module.renderer

-- Shares of the parchment's height (mockups: 820px parchment).
local ROW_MIN   = 30 / 820     -- row height (rows grow for wrapped text)
local ROW_GAP   = 10 / 820
local ICON      = 22 / 820
local BADGE     = 22 / 820
local BADGE_GAP = 8 / 820
local TEXT_GAP  = 8 / 820
local SECTION_GAP = 14 / 820   -- above a header / between the greeting and the list
local BAR_W     = 8            -- minimal scroll bar (its own art width)
local BAR_GAP   = 10 / 600     -- of the width, text -> scroll bar
local INK       = { 0.19, 0.12, 0.05 }     -- quest text on parchment
local HEADER_INK = { 0.12, 0.06, 0.02 }
local BADGE_FILL = { 0.16, 0.09, 0.02 }
local BADGE_RING = { 0.82, 0.66, 0.24 }
local ROUND_MASK = "Interface\\CharacterFrame\\TempPortraitAlphaMask"
local HIGHLIGHT  = "Interface\\QuestFrame\\UI-QuestTitleHighlight"
local MAX_CHOICES = 19
local PORTRAIT  = 138 / 600    -- share of the parchment's width (as on the quest pages)
local TEXT_GAP  = 16 / 600

-- ---------------------------------------------------------------------------
-- Data
-- ---------------------------------------------------------------------------
local function QuestText(info, title)
    if info.isIgnored then return IGNORED_QUEST_DISPLAY:format(title), true end
    if info.isTrivial then return TRIVIAL_QUEST_DISPLAY:format(title), true end
    return NORMAL_QUEST_DISPLAY:format(title), false
end

local function OptionText(info)
    local flags = Enum and Enum.GossipOptionRecFlags
    if flags and info.flags and FlagsUtil and GOSSIP_OPTION_PREPEND then
        local prepends = {}
        if FlagsUtil.IsSet(info.flags, flags.QuestLabelPrepend) then prepends[#prepends + 1] = QUEST_PREPEND end
        if flags.PlayMovieLabelPrepend and FlagsUtil.IsSet(info.flags, flags.PlayMovieLabelPrepend) then prepends[#prepends + 1] = PLAY_MOVIE_PREPEND end
        if #prepends > 0 then return GOSSIP_OPTION_PREPEND:format(table.concat(prepends, " "), info.name) end
    end
    return info.name
end

-- { text = greeting, entries = { { kind = "header"|"row", ... } } }
local function GossipData()
    local panel = GossipFrame.GreetingPanel
    local provider = panel and panel.ScrollBox and panel.ScrollBox:GetDataProvider()
    local data = { text = C_GossipInfo.GetText() or "", entries = {}, unit = "npc" }
    if not provider then return data end
    for _, e in provider:Enumerate() do
        local info = e.info
        if e.buttonType == GOSSIP_BUTTON_TYPE_TITLE then
            data.text = e.text or data.text
        elseif e.buttonType == GOSSIP_BUTTON_TYPE_AVAILABLE_QUEST and info then
            local text, dim = QuestText(info, info.title)
            data.entries[#data.entries + 1] = { kind = "row", index = e.index, text = text, dim = dim,
                icon = function(t) QuestUtil.ApplyQuestIconOfferToTextureForQuestID(t, info.questID, info.isLegendary, info.frequency, info.isRepeatable, info.isImportant, info.isMeta, info.questInfoID) end,
                click = function() C_GossipInfo.SelectAvailableQuest(info.questID) end }
        elseif e.buttonType == GOSSIP_BUTTON_TYPE_ACTIVE_QUEST and info then
            local text, dim = QuestText(info, info.title)
            data.entries[#data.entries + 1] = { kind = "row", index = e.index, text = text, dim = dim,
                icon = function(t) QuestUtil.ApplyQuestIconActiveToTextureForQuestID(t, info.questID, info.isComplete, info.isLegendary, info.frequency, info.isRepeatable, info.isImportant, info.isMeta, info.questInfoID) end,
                click = function() C_GossipInfo.SelectActiveQuest(info.questID) end }
        elseif e.buttonType == GOSSIP_BUTTON_TYPE_OPTION and info then
            data.entries[#data.entries + 1] = { kind = "row", index = e.index, text = OptionText(info),
                icon = function(t) t:SetTexture(info.overrideIconID or info.icon) end,
                click = function() C_GossipInfo.SelectOptionByIndex(info.orderIndex) end }
        end
    end
    return data
end

local function GreetingData()
    local data = { text = GetGreetingText() or "", entries = {}, unit = "questnpc" }
    local numActive, numAvailable = GetNumActiveQuests(), GetNumAvailableQuests()
    local index = 0
    if numActive > 0 then
        data.entries[#data.entries + 1] = { kind = "header", text = CURRENT_QUESTS }
        for i = 1, numActive do
            local title, isComplete = GetActiveTitle(i)
            local trivial = IsActiveQuestTrivial(i)
            local questID = GetActiveQuestID(i)
            index = index + 1
            data.entries[#data.entries + 1] = { kind = "row", index = index,
                text = (trivial and TRIVIAL_QUEST_DISPLAY or NORMAL_QUEST_DISPLAY):format(title), dim = trivial,
                icon = function(t) QuestUtil.ApplyQuestIconActiveToTextureForQuestID(t, questID, isComplete) end,
                click = function() SelectActiveQuest(i) end }
        end
    end
    if numAvailable > 0 then
        data.entries[#data.entries + 1] = { kind = "header", text = AVAILABLE_QUESTS }
        for i = 1, numAvailable do
            local isTrivial, frequency, isRepeatable, isLegendary, questID, isImportant, isMeta, questInfoID = GetAvailableQuestInfo(i)
            index = index + 1
            data.entries[#data.entries + 1] = { kind = "row", index = index,
                text = (isTrivial and TRIVIAL_QUEST_DISPLAY or NORMAL_QUEST_DISPLAY):format(GetAvailableTitle(i)), dim = isTrivial,
                icon = function(t) QuestUtil.ApplyQuestIconOfferToTextureForQuestID(t, questID, isLegendary, frequency, isRepeatable, isImportant, isMeta, questInfoID) end,
                click = function() SelectAvailableQuest(i) end }
        end
    end
    return data
end

local function ListKind(frame)
    if frame == GossipFrame then return "gossip" end
    if frame == QuestFrame and QuestFrameGreetingPanel:IsShown() then return "greeting" end
end

-- ---------------------------------------------------------------------------
-- Widgets
-- ---------------------------------------------------------------------------
local function CreateList(frame)
    local list = { rows = {}, headers = {} }
    local sf = CreateFrame("ScrollFrame", nil, frame)
    local child = CreateFrame("Frame", nil, sf)
    child:SetSize(1, 1)
    sf:SetScrollChild(child)
    sf:EnableMouseWheel(true)
    list.sf, list.child = sf, child

    -- the NPC's portrait with the greeting text wrapping beside it (Shared.lua)
    list.block = R.NewTextBlock(child)
    list.block:SetPoint("TOPLEFT")

    -- Blizzard's MinimalScrollBar; shown only when the list overflows
    if ScrollUtil and ScrollUtil.InitScrollFrameWithScrollBar then
        list.bar = CreateFrame("EventFrame", nil, frame, "MinimalScrollBar")
        list.bar:SetPoint("TOPLEFT", sf, "TOPRIGHT", 0, 0)
        list.bar:SetPoint("BOTTOMLEFT", sf, "BOTTOMRIGHT", 0, 0)
        ScrollUtil.InitScrollFrameWithScrollBar(sf, list.bar)
        R.TintScrollBar(list.bar, true)
    end

    -- "More below": the chat frame's ScrollToBottomButton (Shared.lua)
    local more = R.AttachMoreArrow(sf, frame)
    list.more = more
    -- divider at the top once the list is scrolled (Shared.lua)
    list.rule = R.AttachTopRule(sf, frame)

    local function UpdateScroll()
        if list.bar then list.bar:SetShown(sf:GetVerticalScrollRange() > 0.5 and sf:IsShown()) end
        more.Update()
        list.rule.Update()
    end
    if not sf:GetScript("OnMouseWheel") then
        sf:SetScript("OnMouseWheel", function(self, delta)
            local step = (list.rowStep or 30) * 3
            local range = self:GetVerticalScrollRange()
            self:SetVerticalScroll(math.max(0, math.min(range, self:GetVerticalScroll() - delta * step)))
        end)
    end
    sf:HookScript("OnVerticalScroll", UpdateScroll)
    sf:HookScript("OnScrollRangeChanged", UpdateScroll)
    list.UpdateScroll = UpdateScroll
    return list
end

local function Badge(row)
    local b = CreateFrame("Frame", nil, row)
    local ring = b:CreateTexture(nil, "ARTWORK", nil, 1)
    ring:SetAllPoints()
    ring:SetColorTexture(BADGE_RING[1], BADGE_RING[2], BADGE_RING[3], 1)
    local ringMask = b:CreateMaskTexture()
    ringMask:SetTexture(ROUND_MASK, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
    ringMask:SetAllPoints(ring)
    ring:AddMaskTexture(ringMask)
    local fill = b:CreateTexture(nil, "ARTWORK", nil, 2)
    fill:SetPoint("TOPLEFT", 1.5, -1.5); fill:SetPoint("BOTTOMRIGHT", -1.5, 1.5)
    fill:SetColorTexture(BADGE_FILL[1], BADGE_FILL[2], BADGE_FILL[3], 1)
    local fillMask = b:CreateMaskTexture()
    fillMask:SetTexture(ROUND_MASK, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
    fillMask:SetAllPoints(fill)
    fill:AddMaskTexture(fillMask)
    b.text = b:CreateFontString(nil, "OVERLAY")
    b.text:SetPoint("CENTER", 0, 0)
    return b
end

local function CreateRow(list)
    local row = CreateFrame("Button", nil, list.child)
    row:RegisterForClicks("LeftButtonUp")
    row.badge = Badge(row)
    row.icon = row:CreateTexture(nil, "ARTWORK")
    row.text = row:CreateFontString(nil, "OVERLAY")
    row.text:SetJustifyH("LEFT")
    row.text:SetWordWrap(true)
    local hl = row:CreateTexture(nil, "HIGHLIGHT")
    hl:SetTexture(HIGHLIGHT)
    hl:SetBlendMode("ADD")
    hl:SetAllPoints()
    row:SetScript("OnClick", function(self)
        if self.entry and self.entry.click then
            if SOUNDKIT and SOUNDKIT.IG_QUEST_LIST_SELECT then PlaySound(SOUNDKIT.IG_QUEST_LIST_SELECT) end
            self.entry.click()
        end
    end)
    return row
end

local function CreateHeader(list)
    local fs = list.child:CreateFontString(nil, "OVERLAY")
    fs:SetJustifyH("LEFT")
    return fs
end

-- ---------------------------------------------------------------------------
-- Layout
-- ---------------------------------------------------------------------------
local hiddenBlizzard = {}   -- [region] = { points, alpha }

local function HideBlizzardList(region)
    if not region or hiddenBlizzard[region] then return end
    local points = {}
    for i = 1, region:GetNumPoints() do points[i] = { region:GetPoint(i) } end
    hiddenBlizzard[region] = { points = points, alpha = region:GetAlpha() }
    region:SetAlpha(0)
    region:ClearAllPoints()
    region:SetPoint("TOPRIGHT", UIParent, "BOTTOMLEFT", -4000, -4000)   -- out of view, still alive
end

local function RestoreBlizzardList(region)
    local saved = region and hiddenBlizzard[region]
    if not saved then return end
    region:ClearAllPoints()
    for _, p in ipairs(saved.points) do region:SetPoint(unpack(p)) end
    region:SetAlpha(saved.alpha)
    hiddenBlizzard[region] = nil
end

local function BlizzardListOf(frame)
    if frame == GossipFrame then
        return GossipFrame.GreetingPanel and GossipFrame.GreetingPanel.ScrollBox
    end
    return QuestGreetingScrollFrame
end

local function Fill(list, data, c)
    local fonts = R.fonts
    local lightText, lightTitle = R.LightTextColors()
    local INK, HEADER_INK = lightText or INK, lightTitle or HEADER_INK
    local h = c.h
    local width = list.sf:GetWidth()
    local rowMin, gap, icon, badge = h * ROW_MIN, h * ROW_GAP, h * ICON, h * BADGE
    local textX = badge + h * BADGE_GAP + icon + h * TEXT_GAP
    list.rowStep = rowMin + gap

    local blockH = R.LayoutTextBlock(list.block, {
        width = width, portraitSize = PORTRAIT * c.w, gap = TEXT_GAP * c.w,
        text = data.text, font = fonts.body, color = INK,
        unit = data.unit, key = data.text,
    })
    local y = blockH + h * SECTION_GAP

    for _, r in ipairs(list.rows) do r:Hide(); r.entry = nil end
    for _, hd in ipairs(list.headers) do hd:Hide() end
    list.byIndex = {}
    local nRows, nHeaders = 0, 0
    for _, entry in ipairs(data.entries) do
        if entry.kind == "header" then
            nHeaders = nHeaders + 1
            local hd = list.headers[nHeaders] or CreateHeader(list)
            list.headers[nHeaders] = hd
            hd:SetFontObject(fonts.header)
            hd:SetTextColor(HEADER_INK[1], HEADER_INK[2], HEADER_INK[3])
            hd:ClearAllPoints()
            hd:SetPoint("TOPLEFT", list.child, "TOPLEFT", 0, -y)
            hd:SetText(entry.text)
            hd:Show()
            y = y + hd:GetStringHeight() + gap
        else
            nRows = nRows + 1
            local row = list.rows[nRows] or CreateRow(list)
            list.rows[nRows] = row
            row.entry = entry
            row.text:SetFontObject(fonts.body)
            row.text:SetTextColor(INK[1], INK[2], INK[3])
            row.text:ClearAllPoints()
            row.text:SetPoint("LEFT", row, "LEFT", textX, 0)
            row.text:SetWidth(width - textX)
            row.text:SetText(entry.text)
            local rh = math.max(rowMin, row.text:GetStringHeight() + gap * 0.6)
            row:ClearAllPoints()
            row:SetPoint("TOPLEFT", list.child, "TOPLEFT", 0, -y)
            row:SetSize(width, rh)

            row.badge:SetSize(badge, badge)
            row.badge:ClearAllPoints()
            row.badge:SetPoint("LEFT", row, "LEFT", 0, 0)
            row.badge.text:SetFontObject((entry.index or 0) >= 10 and fonts.badge2 or fonts.badge)
            row.badge.text:SetTextColor(1, 0.82, 0)
            row.badge.text:SetText(entry.index or "")
            row.badge:SetShown(R.listBadgesOn and entry.index and entry.index <= MAX_CHOICES or false)

            entry.icon(row.icon)               -- QuestUtil may resize it; ours wins
            row.icon:SetSize(icon, icon)
            row.icon:ClearAllPoints()
            row.icon:SetPoint("LEFT", row, "LEFT", badge + h * BADGE_GAP, 0)
            local shade = entry.dim and 0.5 or 1
            row.icon:SetVertexColor(shade, shade, shade)

            row:Show()
            if entry.index then list.byIndex[entry.index] = row end
            y = y + rh + gap
        end
    end
    list.child:SetSize(width, math.max(1, y))
    list.sf:UpdateScrollChildRect()
    list.UpdateScroll()
end

-- Frame.lua calls this after every layout of a dressed frame.
function R:LayoutLists(frame, state)
    local kind = ListKind(frame)
    local list = state.list
    if not kind then
        if list then list.sf:Hide(); list.UpdateScroll() end
        if frame == QuestFrame then RestoreBlizzardList(QuestGreetingScrollFrame) end
        state.listKind = nil
        return
    end
    list = list or CreateList(frame)
    state.list = list
    local c = state.content
    local barSpace = BAR_W + c.w * BAR_GAP
    list.sf:ClearAllPoints()
    list.sf:SetPoint("TOPLEFT", frame, "TOPLEFT", c.left, -c.top)
    list.sf:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -(c.right + barSpace), c.bottom)
    if list.bar then list.bar:ClearAllPoints()
        list.bar:SetPoint("TOPLEFT", list.sf, "TOPRIGHT", c.w * BAR_GAP, 0)
        list.bar:SetPoint("BOTTOMLEFT", list.sf, "BOTTOMRIGHT", c.w * BAR_GAP, 0)
    end
    list.more:ClearAllPoints()
    list.more:SetPoint("TOP", list.sf, "BOTTOMRIGHT", c.w * BAR_GAP + BAR_W / 2, -2)
    list.rule:ClearAllPoints()
    list.rule:SetPoint("BOTTOMLEFT", list.sf, "TOPLEFT", 0, 4)
    list.rule:SetSize(list.sf:GetWidth(), R.RULE_HEIGHT)
    list.sf:Show()

    HideBlizzardList(BlizzardListOf(frame))
    if frame == GossipFrame then HideBlizzardList(GossipFrame.GreetingPanel and GossipFrame.GreetingPanel.ScrollBar) end

    if state.listKind ~= kind then list.sf:SetVerticalScroll(0) end
    state.listKind = kind
    Fill(list, kind == "gossip" and GossipData() or GreetingData(), c)
    -- Core's own refresh can run before these rows exist; badge them now.
    core:RefreshQuestBadges()
end

function R:UndressLists(frame, state)
    if state.list then
        state.list.sf:Hide()
        state.list.UpdateScroll()
    end
    state.listKind = nil
    RestoreBlizzardList(BlizzardListOf(frame))
    if frame == GossipFrame then RestoreBlizzardList(GossipFrame.GreetingPanel and GossipFrame.GreetingPanel.ScrollBar) end
end

-- The list on screen, if it's ours.
local function ActiveList()
    for _, frame in ipairs({ GossipFrame, QuestFrame }) do
        local state = frame and R.dressed[frame]
        if state and state.on and frame:IsShown() and state.listKind and state.list and state.list.sf:IsShown() then
            return state.list
        end
    end
end

function R:ListBadges(show)
    R.listBadgesOn = show
    local list = ActiveList()
    if not list then return nil end
    for _, row in ipairs(list.rows) do
        local entry = row.entry
        row.badge:SetShown(show and row:IsShown() and entry and entry.index and entry.index <= MAX_CHOICES or false)
    end
    return true
end

function R:SelectNumber(number)
    local list = ActiveList()
    if not list then return nil end
    local row = list.byIndex and list.byIndex[number]
    if row and row:IsShown() and row.entry and row.entry.click then
        row.entry.click()
        return true
    end
    return false
end
