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
local ASPECT = 600 / 820                  -- width / height
-- Blizzard's QuestBG art and the padding baked into our shadow TGAs (art px).
local ART_W, ART_H = 299, 407
local SHADOW_PAD = 12
local SHADOW_RGB = { 25 / 255, 25 / 255, 25 / 255 }     -- #191919
local MASK_DIR = "Interface\\AddOns\\XpieHUD_Parchment\\Media\\masks\\"
local MASKED = { ["questbg-parchment"] = true, ["questbg-horde"] = true, ["questbg-alliance"] = true }
local DEFAULT_ATLAS = "QuestBG-Parchment"
-- Layout, as shares of the parchment (from the mockups, 600x820).
local PAD_X = 44 / 600                    -- text inset from the left/right edges
local TITLE_TOP = 46 / 820
local TITLE_COLOR = { 0.12, 0.06, 0.02 }
local BUTTON_W, BUTTON_WIDE, BUTTON_H = 170 / 600, 220 / 600, 30 / 820
local BUTTON_BOTTOM = 58 / 820            -- button bottom above the parchment's bottom
-- Buttons: 128-GoldRedButton, desaturated + tan, plus an ADD copy at LIFT.
local TAN = { 1.00, 0.82, 0.58 }
local LIFT = 0.20
local CAP_LEFT, CAP_RIGHT, ART_BUTTON_H = 114, 292, 128   -- atlas piece sizes

local R = {}
local dressed = {}     -- [frame] = state

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

    state.shadow, state.shadowMask = shadow, shadowMask
    state.art, state.artMask, state.title = art, artMask, title
end

local function ThemeAtlas(frame)
    if frame == QuestFrame and (QuestFrameDetailPanel:IsShown() or QuestFrameProgressPanel:IsShown() or QuestFrameRewardPanel:IsShown()) then
        local questID = GetQuestID and GetQuestID()
        local theme = questID and questID > 0 and C_QuestLog.GetQuestDetailsTheme and C_QuestLog.GetQuestDetailsTheme(questID)
        if theme and theme.background then return theme.background end
    end
    return DEFAULT_ATLAS
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
            { QuestFrameAcceptButton, "LEFT" }, { QuestFrameDeclineButton, "RIGHT" },
            { QuestFrameCompleteButton, "LEFT" }, { QuestFrameGoodbyeButton, "RIGHT" },
            { QuestFrameCompleteQuestButton, "CENTER" }, { QuestFrameGreetingGoodbyeButton, "CENTER" },
        }
    elseif frame == GossipFrame then
        return { { GossipFrame.GreetingPanel and GossipFrame.GreetingPanel.GoodbyeButton, "CENTER" } }
    end
    return {}
end

local skins = {}       -- [button] = our textures

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

local function Skin(button, state, height)
    local skin = skins[button]
    if not skin then
        skin = { pieces = {} }
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
    SkinState(button)
end

local function Unskin(button)
    local skin = skins[button]
    if not skin then return end
    skin.on = false
    for _, t in ipairs(skin.pieces) do t:Hide() end
    skin.highlight:Hide()
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
        local button, side = entry[1], entry[2]
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
            Skin(button, state, bh)
        end
    end
end

-- ---------------------------------------------------------------------------
-- Dress / undress
-- ---------------------------------------------------------------------------
local function Layout(frame, state)
    local h = UIParent:GetHeight() * SCREEN_HEIGHT_SHARE
    local w = h * ASPECT
    frame:SetSize(w, h)

    local atlas = ThemeAtlas(frame)
    local key = atlas:lower()
    local maskKey = MASKED[key] and key or DEFAULT_ATLAS:lower()
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

    PinButtons(frame, state, w, h)
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
    for _, region in ipairs({ state.shadow, state.art, state.title }) do region:Hide() end
    frame:SetSize(state.size[1], state.size[2])
    state.on = false
end

local function Frames()
    return { QuestFrame, GossipFrame }
end

local hooked = false
local function Refresh(frame)
    if frame and frame:IsShown() and module.look:IsActive() then Dress(frame) end
end

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

module.renderer = R
