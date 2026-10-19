-- XpieHUD Parchment Test (phase 0). Not part of XpieHUD; delete after testing.
-- /xpt            show / hide the test window (drag it anywhere)
-- /xpt horde      Horde campaign parchment     /xpt plain   plain parchment
-- /xpt unit X     portrait unit: target (default), npc, player, mouseover
-- /xpt anim N     play model animation N (60 = talk, 0 = stand)
-- /xpt zoom N     portrait zoom 0..1 (default 1 = head and shoulders)
--
-- What to check (screenshot each):
--   1. Main parchment: torn top/right/bottom edges float, no grey block, and
--      the #191919 70% shadow follows the torn edge (mask = RLE 512x512 TGA).
--   2. Small strip, left to right: raw native atlas (grey block expected),
--      mask from an uncompressed TGA, mask from a non-power-of-two TGA.
--      Blank / white / missing = that TGA kind isn't usable.
--   3. Portrait: target an NPC, /xpt unit target. Model fills the ring
--      opening; /xpt anim 60 should make it talk.
--   4. Scroll bar: Blizzard's MinimalScrollBar on real scrolling text; the
--      chat-style return-to-bottom arrow flashes until you reach the bottom.
--   5. Buttons: 128-GoldRedButton desaturated + tan, gold text; hover and
--      press them.

local MEDIA = "Interface\\AddOns\\XpieHUD_ParchmentTest\\Media\\"
local THEMES = {
    plain = { atlas = "QuestBG-Parchment", key = "questbg_parchment" },
    horde = { atlas = "QuestBG-Horde",     key = "questbg_horde" },
}
local ART_W, ART_H = 299, 407          -- the atlas' own size
local PAD = 12                          -- shadow padding baked into the shadow TGA (art px)
local W, H = 420, 572                   -- test parchment size (UI units)
local TAN = { 1.00, 0.82, 0.58 }
local SHADOW = { 25 / 255, 25 / 255, 25 / 255, 0.70 }

local theme = "plain"
local frame, parchment, shadow, strip = nil, nil, nil, {}
local model, unit, zoom = nil, "target", 1

local function Label(parent, text, point, rel, relPoint, x, y, font)
    local fs = parent:CreateFontString(nil, "OVERLAY", font or "GameFontHighlightSmall")
    fs:SetPoint(point, rel, relPoint, x, y)
    fs:SetText(text)
    return fs
end

-- Native atlas + an alpha mask TGA from this addon.
local function MaskedArt(parent, layer, sub)
    local tex = parent:CreateTexture(nil, layer, nil, sub)
    local mask = parent:CreateMaskTexture()
    mask:SetAllPoints(tex)
    tex:AddMaskTexture(mask)
    tex.mask = mask
    return tex
end

local function SetMaskFile(tex, file)
    tex.mask:SetTexture(MEDIA .. file, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
end

local function ApplyTheme()
    local t = THEMES[theme]
    parchment:SetAtlas(t.atlas)
    SetMaskFile(parchment, t.key .. "_mask.tga")
    shadow.mask:SetTexture(MEDIA .. t.key .. "_shadow.tga", "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
    strip.raw:SetAtlas(t.atlas)
    strip.unc:SetAtlas(t.atlas); SetMaskFile(strip.unc, t.key .. "_mask_raw.tga")
    strip.npot:SetAtlas(t.atlas); SetMaskFile(strip.npot, t.key .. "_mask_npot.tga")
end

local function RefreshModel()
    if not model then return end
    model:ClearModel()
    if UnitExists(unit) then
        model:SetUnit(unit)
        model:SetPortraitZoom(zoom)
        model:SetCamDistanceScale(1)
        model:SetAnimation(0)
    end
end

-- 128-GoldRedButton, desaturated + tan (SetDesaturated + SetVertexColor)
local function TanButton(parent, text, width)
    local b = CreateFrame("Button", nil, parent)
    b:SetSize(width, 30)
    local k = 30 / 128
    local L = b:CreateTexture(nil, "BACKGROUND"); L:SetPoint("LEFT"); L:SetSize(114 * k, 30)
    local R = b:CreateTexture(nil, "BACKGROUND"); R:SetPoint("RIGHT"); R:SetSize(292 * k, 30)
    local M = b:CreateTexture(nil, "BACKGROUND"); M:SetPoint("TOPLEFT", L, "TOPRIGHT"); M:SetPoint("BOTTOMRIGHT", R, "BOTTOMLEFT")
    local function Art(suffix)
        L:SetAtlas("128-GoldRedButton-left" .. suffix)
        M:SetAtlas("_128-GoldRedButton-center" .. suffix)
        R:SetAtlas("128-GoldRedButton-right" .. suffix)
        for _, t in ipairs({ L, M, R }) do
            t:SetDesaturated(true)
            t:SetVertexColor(TAN[1], TAN[2], TAN[3])
        end
    end
    Art("")
    local hl = b:CreateTexture(nil, "HIGHLIGHT")
    hl:SetAtlas("128-GoldRedButton-highlight"); hl:SetAllPoints(); hl:SetBlendMode("ADD"); hl:SetAlpha(0.35)
    local fs = b:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    fs:SetPoint("CENTER", 0, 1); fs:SetText(text)
    b:SetScript("OnMouseDown", function() Art("-pressed"); fs:SetPoint("CENTER", 1, 0) end)
    b:SetScript("OnMouseUp", function() Art(""); fs:SetPoint("CENTER", 0, 1) end)
    return b
end

local function Build()
    frame = CreateFrame("Frame", "XpieHUDParchmentTest", UIParent)
    frame:SetSize(W, H)
    frame:SetPoint("CENTER", 120, 0)
    frame:SetFrameStrata("DIALOG")
    frame:SetMovable(true); frame:EnableMouse(true); frame:SetClampedToScreen(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", frame.StartMoving)
    frame:SetScript("OnDragStop", frame.StopMovingOrSizing)

    -- 1. shadow (#191919 70%, shaped by the blurred outline) + masked parchment
    local kx, ky = W / ART_W, H / ART_H
    shadow = MaskedArt(frame, "BACKGROUND", -8)
    shadow:SetColorTexture(SHADOW[1], SHADOW[2], SHADOW[3], SHADOW[4])
    shadow:SetPoint("TOPLEFT", -PAD * kx, PAD * ky)
    shadow:SetPoint("BOTTOMRIGHT", PAD * kx, -PAD * ky)
    parchment = MaskedArt(frame, "BACKGROUND", -7)
    parchment:SetAllPoints()

    local title = Label(frame, "Parchment Test", "TOP", frame, "TOP", 0, -30, "QuestTitleFont")
    title:SetTextColor(0.12, 0.06, 0.02); title:SetShadowColor(0, 0, 0, 0)

    -- 3. portrait: PlayerModel inside the Talking Head ring (138px in the mockups)
    local ring = 104
    local holder = CreateFrame("Frame", nil, frame)
    holder:SetSize(ring, ring)
    holder:SetPoint("TOPLEFT", 30, -64)
    local bg = holder:CreateTexture(nil, "BACKGROUND"); bg:SetAtlas("TalkingHeads-PortraitBg")
    local inset = ring * 17 / 150
    bg:SetPoint("TOPLEFT", inset, -inset); bg:SetPoint("BOTTOMRIGHT", -inset, inset)
    model = CreateFrame("PlayerModel", nil, holder)
    model:SetPoint("TOPLEFT", inset, -inset); model:SetPoint("BOTTOMRIGHT", -inset, inset)
    local over = CreateFrame("Frame", nil, holder)
    over:SetAllPoints(); over:SetFrameLevel(model:GetFrameLevel() + 2)
    local frameArt = over:CreateTexture(nil, "OVERLAY"); frameArt:SetAtlas("TalkingHeads-Horde-PortraitFrame"); frameArt:SetAllPoints()

    -- 4. scrolling text with the native MinimalScrollBar + chat's return-to-bottom flash
    local sf = CreateFrame("ScrollFrame", nil, frame)
    sf:SetPoint("TOPLEFT", holder, "TOPRIGHT", 12, 0)
    sf:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -40, 90)
    local child = CreateFrame("Frame", nil, sf); child:SetSize(1, 1); sf:SetScrollChild(child)
    local body = child:CreateFontString(nil, "OVERLAY", "QuestFont")
    body:SetPoint("TOPLEFT"); body:SetJustifyH("LEFT"); body:SetTextColor(0.18, 0.11, 0.05)
    local lines = {}
    for i = 1, 30 do lines[i] = i .. ". Scroll test line - the minimal scroll bar and flashing arrow should track this text." end
    body:SetText(table.concat(lines, "\n"))
    sf:SetScript("OnSizeChanged", function(self, w) body:SetWidth(w); child:SetSize(w, body:GetStringHeight()) end)

    local bar
    if ScrollUtil and ScrollUtil.InitScrollFrameWithScrollBar then
        bar = CreateFrame("EventFrame", nil, frame, "MinimalScrollBar")
        bar:SetPoint("TOPLEFT", sf, "TOPRIGHT", 8, 0)
        bar:SetPoint("BOTTOMLEFT", sf, "BOTTOMRIGHT", 8, 0)
        ScrollUtil.InitScrollFrameWithScrollBar(sf, bar)
    else
        Label(frame, "ScrollUtil.InitScrollFrameWithScrollBar missing", "TOPRIGHT", frame, "TOPRIGHT", -20, -64)
    end

    local more = CreateFrame("Button", nil, frame)
    more:SetSize(17, 15)
    more:SetPoint("TOP", sf, "BOTTOMRIGHT", 12, -4)
    more:SetNormalAtlas("minimal-scrollbar-arrow-returntobottom")
    more:SetPushedAtlas("minimal-scrollbar-arrow-returntobottom-down")
    more:SetHighlightAtlas("minimal-scrollbar-arrow-returntobottom-over")
    local flash = more:CreateTexture(nil, "OVERLAY")
    flash:SetAtlas("minimal-scrollbar-arrow-returntobottom"); flash:SetAllPoints(); flash:SetBlendMode("ADD")
    local anim = flash:CreateAnimationGroup(); anim:SetLooping("REPEAT")
    local a1 = anim:CreateAnimation("Alpha"); a1:SetOrder(1); a1:SetDuration(0.1); a1:SetFromAlpha(0); a1:SetToAlpha(1)
    local a2 = anim:CreateAnimation("Alpha"); a2:SetOrder(2); a2:SetDuration(0.1); a2:SetFromAlpha(1); a2:SetToAlpha(0); a2:SetEndDelay(0.8)
    more:SetScript("OnClick", function() sf:SetVerticalScroll(sf:GetVerticalScrollRange()) end)
    local function UpdateMore()
        local atBottom = sf:GetVerticalScroll() >= sf:GetVerticalScrollRange() - 1
        more:SetShown(not atBottom)
        if atBottom then anim:Stop() elseif not anim:IsPlaying() then anim:Play() end
    end
    sf:HookScript("OnVerticalScroll", UpdateMore)
    sf:HookScript("OnScrollRangeChanged", UpdateMore)
    C_Timer.After(0, UpdateMore)

    -- static arrow atlases (top should point up, bottom down)
    local up = frame:CreateTexture(nil, "OVERLAY"); up:SetAtlas("minimal-scrollbar-arrow-top", true)
    up:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 36, 64)
    local down = frame:CreateTexture(nil, "OVERLAY"); down:SetAtlas("minimal-scrollbar-arrow-bottom", true)
    down:SetPoint("LEFT", up, "RIGHT", 8, 0)
    Label(frame, "arrow-top / arrow-bottom atlases", "LEFT", down, "RIGHT", 8, 0):SetTextColor(0.25, 0.15, 0.05)

    -- 5. buttons
    local accept = TanButton(frame, ACCEPT or "Accept", 150); accept:SetPoint("BOTTOMLEFT", 30, 26)
    local decline = TanButton(frame, DECLINE or "Decline", 150); decline:SetPoint("BOTTOMRIGHT", -30, 26)

    -- 2. comparison strip, left of the parchment
    local sw, sh = 120, 120 * ART_H / ART_W
    local names = { { "raw", "native atlas, no mask" }, { "unc", "mask: uncompressed TGA" }, { "npot", "mask: 299x407 TGA" } }
    for i, n in ipairs(names) do
        local t = MaskedArt(frame, "ARTWORK")
        t:SetSize(sw, sh)
        t:SetPoint("TOPRIGHT", frame, "TOPLEFT", -30 - (3 - i) * (sw + 14), -20)
        if n[1] == "raw" then t:RemoveMaskTexture(t.mask) end
        strip[n[1]] = t
        local l = Label(frame, n[2], "TOP", t, "BOTTOM", 0, -4); l:SetWidth(sw)
    end

    ApplyTheme()
    RefreshModel()

    frame:RegisterEvent("PLAYER_TARGET_CHANGED")
    frame:RegisterEvent("QUEST_DETAIL")
    frame:RegisterEvent("GOSSIP_SHOW")
    frame:SetScript("OnEvent", function(_, event)
        if event ~= "PLAYER_TARGET_CHANGED" then unit = "npc" end
        RefreshModel()
    end)
end

SLASH_XPIEHUDPARCHMENTTEST1 = "/xpt"
SlashCmdList.XPIEHUDPARCHMENTTEST = function(msg)
    local cmd, arg = strtrim(msg or ""):match("^(%S*)%s*(.-)$")
    cmd = cmd:lower()
    if not frame then Build() frame:Hide() end
    if cmd == "" then frame:SetShown(not frame:IsShown())
    elseif THEMES[cmd] then theme = cmd; ApplyTheme(); frame:Show()
    elseif cmd == "unit" then unit = arg ~= "" and arg or "target"; RefreshModel()
    elseif cmd == "anim" then model:SetAnimation(tonumber(arg) or 60)
    elseif cmd == "zoom" then zoom = tonumber(arg) or 1; RefreshModel()
    else print("/xpt [plain|horde|unit X|anim N|zoom N]") end
end
