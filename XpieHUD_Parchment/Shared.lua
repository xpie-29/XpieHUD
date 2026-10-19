-- Shared.lua  (XpieHUD_Parchment: pieces used by the quest pages and the lists)
--   * a text block: the NPC's 3D portrait at the top left, the text wrapping
--     beside it and then running full width below it
--   * the portrait: a PlayerModel in Blizzard's Talking Head ring
--   * the "more below" arrow: the chat frame's ScrollToBottomButton art + flash

local core = XpieHUD
local module = core:GetModule("parchment")
local R = module.renderer

local TALK_ANIMATION = 60          -- EmoteTalk
local TALK_SECONDS = 3.5           -- then back to idle
local FALLBACK_ICON = "Interface\\QuestFrame\\UI-QuestLog-BookIcon"   -- Blizzard's own, for item quests
local RING_INSET = 17 / 150        -- the ring's opening, as a share of its size
local RINGS = { Horde = "TalkingHeads-Horde-PortraitFrame", Alliance = "TalkingHeads-Alliance-PortraitFrame" }

-- ---------------------------------------------------------------------------
-- Portrait
-- ---------------------------------------------------------------------------
function R.NewPortrait(parent)
    local p = CreateFrame("Frame", nil, parent)
    p.bg = p:CreateTexture(nil, "BACKGROUND")
    p.bg:SetAtlas("TalkingHeads-PortraitBg")
    p.model = CreateFrame("PlayerModel", nil, p)
    p.icon = p:CreateTexture(nil, "ARTWORK")
    p.over = CreateFrame("Frame", nil, p)
    p.over:SetAllPoints()
    p.ring = p.over:CreateTexture(nil, "OVERLAY")
    p.ring:SetAllPoints()
    return p
end

-- key: changes when the speaker or the page changes (restarts the talk)
function R.SetPortrait(p, size, unit, key)
    p:SetSize(size, size)
    p.over:SetFrameLevel(p.model:GetFrameLevel() + 2)
    local inset = size * RING_INSET
    for _, region in ipairs({ p.bg, p.model, p.icon }) do
        region:ClearAllPoints()
        region:SetPoint("TOPLEFT", inset, -inset)
        region:SetPoint("BOTTOMRIGHT", -inset, inset)
    end
    p.ring:SetAtlas(RINGS[UnitFactionGroup("player") or ""] or "TalkingHeads-Neutral-PortraitFrame")
    p:Show()

    local hasModel = unit and UnitExists(unit)
    p.model:SetShown(hasModel and true or false)
    p.icon:SetShown(not hasModel)
    if not hasModel then
        p.icon:SetTexture(FALLBACK_ICON)
        p.key = nil
        return
    end
    key = (UnitGUID(unit) or "") .. ":" .. tostring(key)
    p.model:SetPortraitZoom((module.db.portraitZoom or 80) / 100)
    if p.key == key then return end
    p.key = key
    p.model:ClearModel()
    p.model:SetUnit(unit)
    p.model:SetPortraitZoom((module.db.portraitZoom or 80) / 100)
    p.model:SetCamDistanceScale(1)
    p.model:SetAnimation(TALK_ANIMATION)
    C_Timer.After(TALK_SECONDS, function()
        if p.key == key then p.model:SetAnimation(0) end
    end)
end

-- ---------------------------------------------------------------------------
-- Text wrap: one FontString beside the portrait, one full width below it.
-- The split is the last word break at which the beside part still fits the
-- portrait's height, found by measuring with the same FontString.
-- ---------------------------------------------------------------------------
local function Split(fs, text, maxHeight)
    fs:SetText(text)
    if fs:GetStringHeight() <= maxHeight then return text, "" end
    local breaks = {}
    for pos in text:gmatch("()[ \n]") do breaks[#breaks + 1] = pos end
    -- languages written without spaces: the text starts below the portrait
    if #breaks < 3 and #text > 60 then return "", text end
    local lo, hi, best = 1, #breaks, 0
    while lo <= hi do
        local mid = math.floor((lo + hi) / 2)
        fs:SetText(text:sub(1, breaks[mid] - 1))
        if fs:GetStringHeight() <= maxHeight then best = mid; lo = mid + 1 else hi = mid - 1 end
    end
    if best == 0 then return "", text end
    local head, tail = text:sub(1, breaks[best] - 1), text:sub(breaks[best] + 1)
    -- a colour opened in the head and not closed carries over to the tail
    local lastOpen, code = nil, nil
    for pos, c in head:gmatch("()(|c%x%x%x%x%x%x%x%x)") do lastOpen, code = pos, c end
    if lastOpen and not head:find("|r", lastOpen, true) then tail = code .. tail end
    return head, tail
end

function R.NewTextBlock(parent)
    local b = CreateFrame("Frame", nil, parent)
    b.portrait = R.NewPortrait(b)
    b.portrait:SetPoint("TOPLEFT")
    b.beside = b:CreateFontString(nil, "OVERLAY")
    b.below = b:CreateFontString(nil, "OVERLAY")
    for _, fs in ipairs({ b.beside, b.below }) do
        fs:SetJustifyH("LEFT")
        fs:SetJustifyV("TOP")
        fs:SetWordWrap(true)
        fs:SetNonSpaceWrap(true)
    end
    return b
end

-- o = { width, portraitSize, gap, text, font, color = { r, g, b }, unit, key }
-- Returns the block's height.
function R.LayoutTextBlock(b, o)
    local p, gap = o.portraitSize, o.gap
    R.SetPortrait(b.portrait, p, o.unit, o.key)
    for _, fs in ipairs({ b.beside, b.below }) do
        fs:SetFontObject(o.font)
        if o.color then fs:SetTextColor(o.color[1], o.color[2], o.color[3]) end
    end
    b.beside:ClearAllPoints()
    b.beside:SetPoint("TOPLEFT", b, "TOPLEFT", p + gap, 0)
    b.beside:SetWidth(o.width - p - gap)
    local head, tail = Split(b.beside, o.text or "", p)
    b.beside:SetText(head)
    local besideH = head ~= "" and b.beside:GetStringHeight() or 0
    local height = math.max(p, besideH)
    b.below:ClearAllPoints()
    b.below:SetWidth(o.width)
    b.below:SetText(tail)
    if tail ~= "" then
        b.below:SetPoint("TOPLEFT", b, "TOPLEFT", 0, -(height + gap * 0.5))
        b.below:Show()
        height = height + gap * 0.5 + b.below:GetStringHeight()
    else
        b.below:Hide()
    end
    b:SetSize(o.width, height)
    b:Show()
    return height
end

-- ---------------------------------------------------------------------------
-- "More below" (the chat frame's ScrollToBottomButton: art + ADD flash),
-- shown while a scroll frame isn't at its bottom. Returns an update function.
-- ---------------------------------------------------------------------------
function R.AttachMoreArrow(sf, parent)
    local more = CreateFrame("Button", nil, parent)
    more:SetSize(17, 15)
    more:SetNormalAtlas("minimal-scrollbar-arrow-returntobottom")
    more:SetPushedAtlas("minimal-scrollbar-arrow-returntobottom-down")
    more:SetHighlightAtlas("minimal-scrollbar-arrow-returntobottom-over")
    local flash = more:CreateTexture(nil, "OVERLAY")
    flash:SetAtlas("minimal-scrollbar-arrow-returntobottom")
    flash:SetAllPoints()
    flash:SetBlendMode("ADD")
    local anim = flash:CreateAnimationGroup()
    anim:SetLooping("REPEAT")
    local fadeIn = anim:CreateAnimation("Alpha"); fadeIn:SetOrder(1); fadeIn:SetDuration(0.1); fadeIn:SetFromAlpha(0); fadeIn:SetToAlpha(1)
    local fadeOut = anim:CreateAnimation("Alpha"); fadeOut:SetOrder(2); fadeOut:SetDuration(0.1); fadeOut:SetFromAlpha(1); fadeOut:SetToAlpha(0); fadeOut:SetEndDelay(0.8)
    more:SetScript("OnClick", function() sf:SetVerticalScroll(sf:GetVerticalScrollRange()) end)

    local function Update()
        local range = sf:GetVerticalScrollRange()
        local show = more.enabled ~= false and sf:IsVisible() and range > 0.5 and sf:GetVerticalScroll() < range - 1
        more:SetShown(show)
        if show then
            if not anim:IsPlaying() then anim:Play() end
        else
            anim:Stop()
        end
    end
    sf:HookScript("OnVerticalScroll", Update)
    sf:HookScript("OnScrollRangeChanged", Update)
    more.Update = Update
    return more
end
