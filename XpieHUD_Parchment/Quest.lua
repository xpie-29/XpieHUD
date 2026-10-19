-- Quest.lua  (XpieHUD_Parchment, phase 4: the quest pages)
-- Re-dresses the quest offer (detail), progress and reward pages on the
-- parchment. Blizzard keeps rendering everything below the text: objectives,
-- every reward type, the seal and signature, group size. We:
--   * move Blizzard's scroll frame into the parchment's content area and
--     scale it so the quest font reaches the mockups' size (its own minimal
--     scroll bar comes along); the content inside is widened to fill it
--   * hide Blizzard's title and quest text by alpha and draw the text again
--     as our block: the NPC's 3D portrait with the text wrapping beside it.
--     Blizzard's (invisible) text FontString is given the block's height, so
--     everything Blizzard anchors under it lands under the block
--   * scale the rewards to the text width (two-column grid edge to edge)
--   * add the "more below" flash
-- QuestInfo is shared with the world map's quest details, so every change to
-- a shared element is undone the moment QuestInfo_Display runs for anything
-- other than the quest frame (and when the parchment is switched off).

local core = XpieHUD
local module = core:GetModule("parchment")
local R = module.renderer

local BODY_SIZE = 19 / 820           -- target quest text size, share of the parchment height
local MIN_SCALE, MAX_SCALE = 1, 2.5
local PORTRAIT = 138 / 600           -- portrait size, share of the parchment width
local TEXT_GAP = 16 / 600            -- portrait -> text, share of the parchment width
local INSET_X = 10                   -- Blizzard's own left inset in the scroll child (native units)
local BAR_SPACE = 17                 -- the minimal scroll bar beside the scroll frame (native units)

local function Pages()
    return {
        detail   = { panel = QuestFrameDetailPanel,   sf = QuestDetailScrollFrame,   child = QuestDetailScrollChildFrame,
                     title = QuestInfoTitleHeader,    text = QuestInfoDescriptionText, get = GetQuestText,    shared = true },
        reward   = { panel = QuestFrameRewardPanel,   sf = QuestRewardScrollFrame,   child = QuestRewardScrollChildFrame,
                     title = QuestInfoTitleHeader,    text = QuestInfoRewardText,      get = GetRewardText,   shared = true },
        progress = { panel = QuestFrameProgressPanel, sf = QuestProgressScrollFrame, child = QuestProgressScrollChildFrame,
                     title = QuestProgressTitleText,  text = QuestProgressText,        get = GetProgressText },
    }
end

local pages
local saved = {}          -- [region] = { points, w, h, scale } (Blizzard's own layout)
local hidden = {}         -- [fontString] = true while hidden + resized by us
local blocks = {}         -- [page name] = text block
local arrows = {}         -- [scroll frame] = "more below" arrow
local barState = {}       -- [scroll bar] = its own hide-if-unscrollable setting

local function Save(region)
    if saved[region] then return end
    local points = {}
    for i = 1, region:GetNumPoints() do points[i] = { region:GetPoint(i) } end
    saved[region] = { points = points, w = region:GetWidth(), h = region:GetHeight(), scale = region:GetScale() }
end

local function Restore(region)
    local s = saved[region]
    if not s then return end
    region:SetScale(s.scale)
    region:ClearAllPoints()
    for _, p in ipairs(s.points) do region:SetPoint(unpack(p)) end
    region:SetSize(s.w, s.h)
    saved[region] = nil
end

local function HideText(fs, height)
    hidden[fs] = true
    fs:SetAlpha(0)
    fs:SetHeight(height)
end

local function ShowText(fs)
    if not hidden[fs] then return end
    hidden[fs] = nil
    fs:SetAlpha(1)
    fs:SetHeight(0)      -- back to its own height
end

-- Undo everything on QuestInfo's shared elements (the map uses them too).
local function RestoreShared()
    for fs in pairs(hidden) do ShowText(fs) end
    if QuestInfoRewardsFrame then QuestInfoRewardsFrame:SetScale(1) end
    for name, block in pairs(blocks) do
        if pages and pages[name] and pages[name].shared then block:Hide() end
    end
end

local function CurrentPage()
    pages = pages or Pages()
    for name, page in pairs(pages) do
        if page.panel and page.panel:IsShown() then return name, page end
    end
end

-- Quest classification (campaign, important ...) and "Warband Completed",
-- for the tag line under the title. Called by Frame.lua.
function R:TagText(frame)
    if frame ~= QuestFrame or not CurrentPage() then return nil end
    local parts = {}
    local questID = GetQuestID and GetQuestID()
    if questID and questID > 0 and QuestUtil.GetQuestClassificationDetails then
        local _, text, atlas, size = QuestUtil.GetQuestClassificationDetails(questID)
        if text and atlas then parts[#parts + 1] = CreateAtlasMarkup(atlas, size or 16, size or 16) .. " " .. text end
    end
    local notice = QuestFrame.AccountCompletedNotice
    if notice and notice:IsShown() then
        parts[#parts + 1] = CreateAtlasMarkup("warband-completed-icon", 15, 17) .. " " .. (ACCOUNT_COMPLETED_QUEST_NOTICE_LABEL or "Warband Completed")
    end
    if #parts == 0 then return nil end
    return table.concat(parts, "     ")
end

-- Frame.lua calls this after every layout of the dressed QuestFrame.
function R:LayoutQuestPage(frame, state)
    if frame ~= QuestFrame then return end
    local name, page = CurrentPage()
    if not (page and page.sf and page.text and page.title) then
        RestoreShared()
        return
    end
    local c = state.content
    local quest = select(2, QuestFont:GetFont()) or 13
    local scale = math.max(MIN_SCALE, math.min(MAX_SCALE, (c.h * BODY_SIZE) / quest))
    local cw, ch = c.w - c.left - c.right, c.h - c.top - c.bottom

    -- Blizzard's scroll frame, scaled, in the content area (its bar beside it)
    local sf = page.sf
    Save(sf)
    sf:SetScale(scale)
    sf:ClearAllPoints()
    sf:SetPoint("TOPLEFT", frame, "TOPLEFT", c.left / scale, -c.top / scale)
    local nativeW = cw / scale - BAR_SPACE
    sf:SetSize(nativeW, ch / scale)
    if page.child then Save(page.child); page.child:SetWidth(nativeW) end
    -- Blizzard's bar only while there's something to scroll
    local bar = sf.ScrollBar
    if bar and bar.SetHideIfUnscrollable and not barState[bar] then
        barState[bar] = { hide = bar.hideIfUnscrollable or false }
        bar:SetHideIfUnscrollable(true)
    end
    local textW = nativeW - INSET_X * 2

    -- wider Blizzard text under ours
    if page.shared and QuestInfoObjectivesText then QuestInfoObjectivesText:SetWidth(textW) end
    if page.shared and QuestInfoRewardsFrame and QuestInfoRewardsFrame:IsShown() then
        local width = QuestInfoRewardsFrame:GetWidth()
        if not width or width < 100 then width = 285 end
        QuestInfoRewardsFrame:SetScale(textW / width)
    end
    if name == "progress" and QuestProgressRequiredItemsText then QuestProgressRequiredItemsText:SetWidth(textW) end

    -- our text block in place of Blizzard's title + text
    local block = blocks[name]
    if not block then
        block = R.NewTextBlock(page.child or page.text:GetParent())
        blocks[name] = block
    end
    block:ClearAllPoints()
    block:SetPoint("TOPLEFT", page.title, "TOPLEFT", 0, 0)
    local r, g, b = page.text:GetTextColor()
    local height = R.LayoutTextBlock(block, {
        width = textW,
        portraitSize = PORTRAIT * c.w / scale,
        gap = TEXT_GAP * c.w / scale,
        text = page.get and page.get() or "",
        font = QuestFont,
        color = { r, g, b },
        unit = "questnpc",
        key = (GetQuestID and GetQuestID() or 0) .. name,
    })
    -- the title collapses; the text keeps the block's height so Blizzard's
    -- next element (seal, objectives, rewards ...) sits under the block
    HideText(page.title, 1)
    local _, _, _, _, gapY = page.text:GetPoint(1)
    HideText(page.text, math.max(1, height - 1 + (gapY or -5)))
    for other, ob in pairs(blocks) do
        if other ~= name then ob:Hide() end
    end

    -- "more below"
    local more = arrows[sf]
    if not more then
        more = R.AttachMoreArrow(sf, frame)
        arrows[sf] = more
    end
    more:ClearAllPoints()
    more:SetPoint("TOP", frame, "TOPLEFT", c.w - c.right - BAR_SPACE * scale / 2, -(c.top + ch) + 2)
    more.enabled = true
    if sf.UpdateScrollChildRect then sf:UpdateScrollChildRect() end
    more.Update()
end

function R:UndressQuestPage(frame, state)
    if frame ~= QuestFrame then return end
    RestoreShared()
    for _, block in pairs(blocks) do block:Hide() end
    for region in pairs(saved) do Restore(region) end
    for bar, s in pairs(barState) do bar:SetHideIfUnscrollable(s.hide) end
    wipe(barState)
    -- (QuestInfoObjectivesText's width: Blizzard sets it on every display)
    for _, more in pairs(arrows) do more.enabled = false; more.Update() end
end

-- QuestInfo_Display runs for the quest frame and for the world map: re-dress
-- ours, undo everything shared for anything else.
local hooked = false
function R:HookQuestInfo()
    if hooked or not QuestInfo_Display then return end
    hooked = true
    hooksecurefunc("QuestInfo_Display", function(template, parentFrame)
        local ours = parentFrame == QuestDetailScrollChildFrame or parentFrame == QuestRewardScrollChildFrame
        if ours and module.look:IsActive() then
            R.Refresh(QuestFrame)
        else
            RestoreShared()
        end
    end)
end
