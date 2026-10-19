-- Frame.lua  (XpieHUD_Parchment, phase 2: the parchment frame)
-- Re-dresses Blizzard's QuestFrame and GossipFrame in place:
--   * their chrome (NineSlice border, portrait, title bar, close button, rock
--     background, inset, panel parchment / material textures) hidden by
--     alpha, never Hide(); every alpha is recorded and put back
--   * a fixed size, a share of the screen's height (the mockups' 600x820 on
--     a 1125px screen); Core's Size slider still scales it
--   * Blizzard's QuestBG parchment for the quest's theme
--     (C_QuestLog.GetQuestDetailsTheme), masked by our torn-edge outline
--     (Media/masks, built by Media/src/masks.lua), over a shadow made of the
--     same outline blurred (#191919, Shadow Opacity)
--   * the title pinned at the top, centred, wrapping centred
--   * Blizzard's own bottom buttons pinned at fixed spots and re-skinned with
--     128-GoldRedButton desaturated + tan (their red art kept at alpha 0, so
--     Blizzard's press / enable scripts can keep swapping it unseen)
-- Blizzard's content (quest text, rewards, gossip list) stays where Blizzard
-- puts it until phases 3 and 4 lay it out on the parchment.

local core = XpieHUD
local module = core:GetModule("parchment")

-- Size: the mockups' parchment was 820px tall on a 1125px screen.
local SCREEN_HEIGHT_SHARE = 820 / 1125
-- ...but never taller than this share of the screen once Core's Size slider
-- has scaled it, so it always fits (it is also clamped to the screen).
local MAX_SCREEN_SHARE = 0.92
local ASPECT = 600 / 820                  -- width / height
-- Blizzard's QuestBG art and the padding baked into our shadow TGAs (art px).
local ART_W, ART_H = 299, 407
local SHADOW_PAD = 12
local SHADOW_RGB = { 25 / 255, 25 / 255, 25 / 255 }     -- #191919
local MASK_DIR = "Interface\\AddOns\\XpieHUD_Parchment\\Media\\masks\\"
-- module.masks (MaskList.lua, generated with the masks): themes with a mask
local DEFAULT_ATLAS = "QuestBG-Parchment"
-- Layout, as shares of the parchment (from the mockups, 600x820).
local PAD_X = 44 / 600                    -- text inset from the left/right edges
local TITLE_TOP = 46 / 820
local TITLE_COLOR = { 0.12, 0.06, 0.02 }
local TAG_COLOR = { 0.29, 0.13, 0.03 }
local BUTTON_W, BUTTON_WIDE, BUTTON_H = 170 / 600, 220 / 600, 30 / 820
local BUTTON_BOTTOM = 58 / 820            -- button bottom above the parchment's bottom
local CONTENT_GAP = 18 / 820              -- between the title / buttons and the content
-- Buttons: 128-GoldRedButton, desaturated + tan, plus an ADD copy at LIFT.
local TAN = { 1.00, 0.82, 0.58 }
local LIFT = 0.20
local CAP_LEFT, CAP_RIGHT, ART_BUTTON_H = 114, 292, 128   -- atlas piece sizes

local R = {}
local dressed = {}     -- [frame] = state
R.dressed = dressed

-- Fonts scale with the parchment: the mockups' sizes on an 820px parchment.
-- Title / header in the quest title font, text in the quest font, badges and
-- key hints in the standard UI font.
local FONT_SIZES = { title = 27, body = 19, header = 21, badge = 14, badge2 = 12, hint = 11, tag = 15 }
local fonts = {}
R.fonts = fonts

local function UpdateFonts(h)
    local files = {
        title = (QuestTitleFont:GetFont()), header = (QuestTitleFont:GetFont()),
        body = (QuestFont:GetFont()), hint = (GameFontNormal:GetFont()), tag = (QuestTitleFont:GetFont()),
        -- badges: Blizzard's number font (narrow digits, so 10-19 fit the circle)
        badge = (NumberFontNormal:GetFont()), badge2 = (NumberFontNormal:GetFont()),
    }
    for key, size in pairs(FONT_SIZES) do
        fonts[key] = fonts[key] or CreateFont("XpieHUDParchmentFont_" .. key)
        fonts[key]:SetFont(files[key], math.floor(size * h / 820 + 0.5), "")
    end
end

-- ---------------------------------------------------------------------------
-- Alpha bookkeeping: hide by alpha, remember, restore
-- ---------------------------------------------------------------------------
local function Fade(state, region)
    if not region or state.faded[region] then return end
    state.faded[region] = region:GetAlpha()
    region:SetAlpha(0)
end

local function Unfade(state)
    for region, alpha in pairs(state.faded) do region:SetAlpha(alpha) end
    wipe(state.faded)
end

local function PanelsOf(frame)
    if frame == QuestFrame then
        return { QuestFrameGreetingPanel, QuestFrameDetailPanel, QuestFrameProgressPanel, QuestFrameRewardPanel }
    elseif frame == GossipFrame then
        return { GossipFrame.GreetingPanel }
    end
    return {}
end

local function FadeChrome(frame, state)
    for _, key in ipairs({ "NineSlice", "PortraitContainer", "TitleContainer", "CloseButton", "Bg", "TopTileStreaks", "Inset", "Background" }) do
        Fade(state, frame[key])
    end
    if frame == QuestFrame then
        Fade(state, QuestFramePortrait)
        Fade(state, QuestNpcNameFrame)
        Fade(state, QuestFrame.AccountCompletedNotice)   -- shown in our tag line instead
        Fade(state, QuestModelScene)                     -- our portrait replaces the side model
    end
    for _, panel in ipairs(PanelsOf(frame)) do
        for _, key in ipairs({ "Bg", "MaterialTopLeft", "MaterialTopRight", "MaterialBotLeft", "MaterialBotRight", "SealMaterialBG" }) do
            Fade(state, panel[key])
        end
    end
    -- the invisible close button mustn't catch clicks on the parchment
    if frame.CloseButton and frame.CloseButton:IsMouseEnabled() then
        state.closeMouse = true
        frame.CloseButton:EnableMouse(false)
    end
end

-- ---------------------------------------------------------------------------
-- Parchment layers (regions on the Blizzard frame, under its panels)
-- ---------------------------------------------------------------------------
local function CreateLayers(frame, state)
    local shadow = frame:CreateTexture(nil, "BACKGROUND", nil, -8)
    local shadowMask = frame:CreateMaskTexture()
    shadowMask:SetAllPoints(shadow)
    shadow:AddMaskTexture(shadowMask)

    local art = frame:CreateTexture(nil, "BACKGROUND", nil, -7)
    art:SetAllPoints(frame)
    local artMask = frame:CreateMaskTexture()
    artMask:SetAllPoints(art)
    art:AddMaskTexture(artMask)

    local title = frame:CreateFontString(nil, "OVERLAY", "QuestTitleFont")
    title:SetJustifyH("CENTER")
    title:SetJustifyV("TOP")
    title:SetWordWrap(true)
    title:SetMaxLines(2)
    title:SetTextColor(TITLE_COLOR[1], TITLE_COLOR[2], TITLE_COLOR[3])
    title:SetShadowColor(0, 0, 0, 0)

    local tag = frame:CreateFontString(nil, "OVERLAY")
    tag:SetJustifyH("CENTER")
    tag:SetWordWrap(false)
    tag:SetShadowColor(0, 0, 0, 0)
    state.tag = tag

    state.shadow, state.shadowMask = shadow, shadowMask
    state.art, state.artMask, state.title = art, artMask, title
end

local function ThemeAtlas(frame)
    if frame == QuestFrame and not R.ContrastOn() and (QuestFrameDetailPanel:IsShown() or QuestFrameProgressPanel:IsShown() or QuestFrameRewardPanel:IsShown()) then
        local questID = GetQuestID and GetQuestID()
        local theme = questID and questID > 0 and C_QuestLog.GetQuestDetailsTheme and C_QuestLog.GetQuestDetailsTheme(questID)
        if theme and theme.background then return theme.background end
    end
    return R.DefaultAtlas()
end

-- Quest Text Contrast (Accessibility): Blizzard's contrast parchment replaces
-- every theme, and its darkest level uses light "Stone" text.
function R.DefaultAtlas()
    if QuestTextContrast and QuestTextContrast.GetDefaultBackgroundAtlas then
        return QuestTextContrast.GetDefaultBackgroundAtlas() or DEFAULT_ATLAS
    end
    return DEFAULT_ATLAS
end

function R.ContrastOn()
    return QuestTextContrast and QuestTextContrast.IsEnabled and QuestTextContrast.IsEnabled() or false
end

-- text, title colours ({ r, g, b }) for light text, or nil for the usual inks
function R.LightTextColors()
    if QuestTextContrast and QuestTextContrast.UseLightText and QuestTextContrast.UseLightText() and GetMaterialTextColors then
        return GetMaterialTextColors("Stone")
    end
end

local function TitleText(frame)
    if frame == QuestFrame and not QuestFrameGreetingPanel:IsShown() then
        local title = GetTitleText and GetTitleText()
        if title and title ~= "" then return title end
    end
    local fs = frame.GetTitleText and frame:GetTitleText()
    return fs and fs:GetText() or UnitName("npc") or ""
end

-- ---------------------------------------------------------------------------
-- Buttons: Blizzard's own, pinned and re-skinned
-- ---------------------------------------------------------------------------
local function ButtonsOf(frame)
    if frame == QuestFrame then
        return {
            { QuestFrameAcceptButton, "LEFT", "SPACE" }, { QuestFrameDeclineButton, "RIGHT", "ESC" },
            { QuestFrameCompleteButton, "LEFT", "SPACE" }, { QuestFrameGoodbyeButton, "RIGHT", "ESC" },
            { QuestFrameCompleteQuestButton, "CENTER", "SPACE" }, { QuestFrameGreetingGoodbyeButton, "CENTER", "ESC" },
        }
    elseif frame == GossipFrame then
        return { { GossipFrame.GreetingPanel and GossipFrame.GreetingPanel.GoodbyeButton, "CENTER", "ESC" } }
    end
    return {}
end

local skins = {}       -- [button] = our textures
local HINT_COLOR = { 0.37, 0.24, 0.10, 0.85 }

-- Space only acts where Core's Space would (PvP and gold quests confirm
-- through popups the player clicks).
local function SpaceWouldAct(button)
    if button == QuestFrameAcceptButton then return not QuestFlagsPVP() end
    if button == QuestFrameCompleteQuestButton then
        local money = GetQuestMoneyToGet()
        return not (money and money > 0)
    end
    return true
end

local function UpdateHint(button)
    local skin = skins[button]
    if not (skin and skin.hint) then return end
    skin.hint:SetShown(skin.on and R.hintsOn and button:IsShown()
        and (skin.key ~= "SPACE" or SpaceWouldAct(button)))
end
R.UpdateHint = UpdateHint

local function SkinState(button)
    local skin = skins[button]
    if not (skin and skin.on) then return end
    local suffix = not button:IsEnabled() and "-disabled" or (skin.down and "-pressed" or "")
    for i, t in ipairs(skin.pieces) do
        local piece = (i - 1) % 3
        t:SetAtlas(piece == 0 and "128-GoldRedButton-left" .. suffix
            or piece == 1 and "_128-GoldRedButton-center" .. suffix
            or "128-GoldRedButton-right" .. suffix)
        t:SetDesaturated(true)
        t:SetVertexColor(TAN[1], TAN[2], TAN[3])
    end
    for i = 4, 6 do skin.pieces[i]:SetAlpha(LIFT) end
end

local function Skin(button, state, height, key)
    local skin = skins[button]
    if not skin then
        skin = { pieces = {} }
        skin.hint = button:CreateFontString(nil, "OVERLAY")
        skin.hint:SetPoint("TOP", button, "BOTTOM", 0, -3)
        local L = button:CreateTexture(nil, "BACKGROUND", nil, 1)
        local R2 = button:CreateTexture(nil, "BACKGROUND", nil, 1)
        local M = button:CreateTexture(nil, "BACKGROUND", nil, 1)
        L:SetPoint("TOPLEFT"); L:SetPoint("BOTTOMLEFT")
        R2:SetPoint("TOPRIGHT"); R2:SetPoint("BOTTOMRIGHT")
        M:SetPoint("TOPLEFT", L, "TOPRIGHT"); M:SetPoint("BOTTOMRIGHT", R2, "BOTTOMLEFT")
        skin.pieces = { L, M, R2 }
        for i, base in ipairs({ L, M, R2 }) do
            local lift = button:CreateTexture(nil, "BACKGROUND", nil, 2)
            lift:SetAllPoints(base); lift:SetBlendMode("ADD")
            skin.pieces[3 + i] = lift
        end
        skin.highlight = button:CreateTexture(nil, "HIGHLIGHT")
        skin.highlight:SetAtlas("128-GoldRedButton-highlight")
        skin.highlight:SetAllPoints()
        skin.highlight:SetBlendMode("ADD")
        skin.highlight:SetAlpha(0.35)
        skin.highlight:SetDesaturated(true)          -- tan, like the button (no red glow)
        skin.highlight:SetVertexColor(TAN[1], TAN[2], TAN[3])
        button:HookScript("OnMouseDown", function(self) local s = skins[self]; if s then s.down = self:IsEnabled(); SkinState(self) end end)
        button:HookScript("OnMouseUp", function(self) local s = skins[self]; if s then s.down = false; SkinState(self) end end)
        button:HookScript("OnEnable", SkinState)
        button:HookScript("OnDisable", SkinState)
        skins[button] = skin
    end
    local k = height / ART_BUTTON_H
    skin.pieces[1]:SetWidth(CAP_LEFT * k)
    skin.pieces[3]:SetWidth(CAP_RIGHT * k)
    for _, key in ipairs({ "Left", "Middle", "Right" }) do Fade(state, button[key]) end
    Fade(state, button:GetHighlightTexture())
    skin.on = true
    for _, t in ipairs(skin.pieces) do t:Show() end
    skin.highlight:Show()
    skin.down = false
    skin.key = key
    skin.hint:SetFontObject(fonts.hint)
    local light = R.LightTextColors()
    local hint = light or HINT_COLOR
    skin.hint:SetTextColor(hint[1], hint[2], hint[3], HINT_COLOR[4])
    skin.hint:SetText(key or "")
    SkinState(button)
    UpdateHint(button)
end

local function Unskin(button)
    local skin = skins[button]
    if not skin then return end
    skin.on = false
    for _, t in ipairs(skin.pieces) do t:Hide() end
    skin.highlight:Hide()
    skin.hint:Hide()
end

local function SavePoints(region)
    local points = {}
    for i = 1, region:GetNumPoints() do points[i] = { region:GetPoint(i) } end
    return { points = points, w = region:GetWidth(), h = region:GetHeight() }
end

local function RestorePoints(region, saved)
    region:ClearAllPoints()
    for _, p in ipairs(saved.points) do region:SetPoint(unpack(p)) end
    region:SetSize(saved.w, saved.h)
end

local function PinButtons(frame, state, w, h)
    local bw, bwide, bh = w * BUTTON_W, w * BUTTON_WIDE, h * BUTTON_H
    local x, y = w * PAD_X, h * BUTTON_BOTTOM
    for _, entry in ipairs(ButtonsOf(frame)) do
        local button, side, key = entry[1], entry[2], entry[3]
        if button then
            state.buttons[button] = state.buttons[button] or SavePoints(button)
            button:ClearAllPoints()
            if side == "LEFT" then
                button:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", x, y); button:SetSize(bw, bh)
            elseif side == "RIGHT" then
                button:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -x, y); button:SetSize(bw, bh)
            else
                button:SetPoint("BOTTOM", frame, "BOTTOM", 0, y); button:SetSize(bwide, bh)
            end
            Skin(button, state, bh, key)
        end
    end
end

-- ---------------------------------------------------------------------------
-- Dress / undress
-- ---------------------------------------------------------------------------
local function Layout(frame, state)
    local screenH = UIParent:GetHeight()
    local scale = frame:GetEffectiveScale() / UIParent:GetEffectiveScale()   -- Core's Size slider
    local h = math.min(screenH * SCREEN_HEIGHT_SHARE, screenH * MAX_SCREEN_SHARE / scale)
    local w = h * ASPECT
    frame:SetSize(w, h)
    if state.clamped == nil then state.clamped = frame:IsClampedToScreen() end
    frame:SetClampedToScreen(true)
    UpdateFonts(h)
    state.title:SetFontObject(fonts.title)
    local lightText, lightTitle = R.LightTextColors()
    local titleColor = lightTitle or TITLE_COLOR
    state.title:SetTextColor(titleColor[1], titleColor[2], titleColor[3])

    local atlas = ThemeAtlas(frame)
    local key = atlas:lower()
    local maskKey = (module.masks or {})[key] and key or DEFAULT_ATLAS:lower()
    state.art:SetAtlas(atlas)
    state.artMask:SetTexture(MASK_DIR .. maskKey .. "_mask.tga", "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
    state.shadowMask:SetTexture(MASK_DIR .. maskKey .. "_shadow.tga", "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
    local px, py = SHADOW_PAD * w / ART_W, SHADOW_PAD * h / ART_H
    state.shadow:ClearAllPoints()
    state.shadow:SetPoint("TOPLEFT", frame, "TOPLEFT", -px, py)
    state.shadow:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", px, -py)
    state.shadow:SetColorTexture(SHADOW_RGB[1], SHADOW_RGB[2], SHADOW_RGB[3], (module.db.shadowOpacity or 70) / 100)

    local pad = w * PAD_X
    state.title:ClearAllPoints()
    state.title:SetPoint("TOPLEFT", frame, "TOPLEFT", pad, -h * TITLE_TOP)
    state.title:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -pad, -h * TITLE_TOP)
    state.title:SetText(TitleText(frame))

    -- tag line: quest classification + Warband Completed (Quest.lua)
    local tagText = R.TagText and R:TagText(frame)
    state.tag:SetFontObject(fonts.tag)
    local tagColor = lightText or TAG_COLOR
    state.tag:SetTextColor(tagColor[1], tagColor[2], tagColor[3])
    state.tag:ClearAllPoints()
    state.tag:SetPoint("TOP", state.title, "BOTTOM", 0, -h * 6 / 820)
    state.tag:SetText(tagText or "")
    state.tag:SetShown(tagText ~= nil)

    PinButtons(frame, state, w, h)

    -- content area: under the title, above the pinned buttons
    local top = h * TITLE_TOP + math.max(state.title:GetStringHeight() or 0, h * 27 / 820) + h * CONTENT_GAP
    if state.tag:IsShown() then top = top + h * 6 / 820 + (state.tag:GetStringHeight() or 0) end
    local bottom = h * (BUTTON_BOTTOM + BUTTON_H) + h * CONTENT_GAP
    state.content = { left = pad, right = pad, top = top, bottom = bottom, w = w, h = h }
    if R.LayoutLists then R:LayoutLists(frame, state) end
    if R.LayoutQuestPage then R:LayoutQuestPage(frame, state) end
end

local function Dress(frame)
    local state = dressed[frame]
    if not state then
        state = { faded = {}, buttons = {} }
        dressed[frame] = state
    end
    if not state.art then CreateLayers(frame, state) end
    if not state.on then
        state.size = { frame:GetSize() }
        FadeChrome(frame, state)
        state.on = true
    end
    for _, region in ipairs({ state.shadow, state.art, state.title }) do region:Show() end
    Layout(frame, state)
end

local function Undress(frame)
    local state = dressed[frame]
    if not (state and state.on) then return end
    Unfade(state)
    if state.closeMouse and frame.CloseButton then frame.CloseButton:EnableMouse(true) end
    state.closeMouse = nil
    for button, saved in pairs(state.buttons) do
        Unskin(button)
        RestorePoints(button, saved)
    end
    wipe(state.buttons)
    for _, region in ipairs({ state.shadow, state.art, state.title, state.tag }) do region:Hide() end
    if R.UndressLists then R:UndressLists(frame, state) end
    if R.UndressQuestPage then R:UndressQuestPage(frame, state) end
    frame:SetSize(state.size[1], state.size[2])
    if state.clamped ~= nil then frame:SetClampedToScreen(state.clamped); state.clamped = nil end
    state.on = false
end

local function Frames()
    return { QuestFrame, GossipFrame }
end

local hooked = false
local function Refresh(frame)
    if frame and frame:IsShown() and module.look:IsActive() then Dress(frame) end
end
R.Refresh = Refresh

local function HookBlizzard()
    if hooked then return end
    hooked = true
    for _, frame in ipairs(Frames()) do
        if frame then frame:HookScript("OnShow", Refresh) end
    end
    -- quest panels switch inside a shown QuestFrame (detail -> reward ...)
    for _, panel in ipairs(PanelsOf(QuestFrame)) do
        panel:HookScript("OnShow", function() Refresh(QuestFrame) end)
    end
    -- titles are set after the frames show
    if QuestFrame_SetPortrait then hooksecurefunc("QuestFrame_SetPortrait", function() Refresh(QuestFrame) end) end
    if GossipFrame and GossipFrame.HandleShow then hooksecurefunc(GossipFrame, "HandleShow", function() Refresh(GossipFrame) end) end
    -- the lists are (re)built here, also on QUEST_LOG_UPDATE while open
    if GossipFrame and GossipFrame.Update then hooksecurefunc(GossipFrame, "Update", function() Refresh(GossipFrame) end) end
    if QuestFrameGreetingPanel_OnShow then hooksecurefunc("QuestFrameGreetingPanel_OnShow", function() Refresh(QuestFrame) end) end
    if R.HookQuestInfo then R:HookQuestInfo() end
    -- Quest Text Contrast changed with a window open: re-dress it
    local watcher = CreateFrame("Frame")
    watcher:RegisterEvent("CVAR_UPDATE")
    watcher:SetScript("OnEvent", function(_, _, cvar)
        if cvar == "QuestTextContrast" or cvar == "questTextContrast" then
            for _, frame in ipairs(Frames()) do Refresh(frame) end
        end
    end)
end

-- ---------------------------------------------------------------------------
-- Renderer interface (module.renderer; see Parchment.lua)
-- ---------------------------------------------------------------------------
function R:Apply(active)
    HookBlizzard()
    for _, frame in ipairs(Frames()) do
        if frame then
            if active then
                if frame:IsShown() then Dress(frame) end
            else
                Undress(frame)
            end
        end
    end
end

function R:OnDialogShow(frame)
    Refresh(frame)
end

-- Core asks on every badge refresh (see Parchment.lua's look). Returns true
-- while the gossip / greeting list on screen is ours.
function R:RefreshBadges(show)
    R.hintsOn = show
    for button in pairs(skins) do UpdateHint(button) end
    if R.ListBadges then return R:ListBadges(show) end
end

module.renderer = R
