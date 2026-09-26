local _, addon = ...

local controls = {}

local options = {
    { key = "hideStatusBar1", label = "Hide Status Bar 1", description = "Hide the primary Blizzard status-tracking bar." },
    { key = "hideStatusBar2", label = "Hide Status Bar 2", description = "Hide the secondary Blizzard status-tracking bar." },
    { key = "hideMicroMenu",  label = "Hide Micro Menu",   description = "Hide the Blizzard micro menu cluster." },
    { key = "hideBagBar",     label = "Hide Bag Bar",      description = "Hide the Blizzard bag buttons without changing bags or bindings." },
}

local rxpPanelOptions = {
    { key = "hideRXPTargets", label = "Hide Active Targets", description = "Hide the RestedXP Active Targets panel." },
    { key = "hideRXPItems",   label = "Hide Active Items",   description = "Hide the RestedXP Active Items / spells panel." },
    { key = "rxpGoldArrow",   label = "Gold Waypoint Arrow", description = "Replace the RestedXP waypoint arrow with a gold arrowhead in Blizzard's HUD style." },
}

-- Guide addon selector: tick the guide addon(s) currently in use.
local guideOptions = {
    { key = "guideRXP",   addon = "RXPGuides",         label = "RestedXP Guides", description = "Style RestedXP (options in the RestedXP section below)." },
    { key = "guideZygor", addon = "ZygorGuidesViewer", label = "Zygor Guides",    description = "Style Zygor (options in the Zygor section below)." },
}

local zygorOptions = {
    { key = "zygorStrip",     label = "Strip Backgrounds & Borders", description = "Transparent Zygor window background and borders; step boxes keep their colours at 30% opacity." },
    { key = "zygorGoldArrow", label = "Gold Waypoint Arrow",         description = "Use the XpieHUD gold arrowhead as Zygor's arrow skin (also selectable as \"XpieHUD Gold\" in Zygor's own options)." },
}

local questOptions = {
    { key = "questDialogEnabled", label = "Enable Quest Window Enhancements", description = "Master switch for everything in this section. Blizzard's quest and gossip windows themselves are never replaced." },
    { key = "questDialogKeys",    label = "Keyboard Shortcuts",   description = "1–9 pick options, quests and rewards. Space accepts, continues or completes. Out of combat only; all other keys pass through." },
    { key = "questDialogBadges",  label = "Number Badges & Key Hints", description = "Show numbers on the options the 1–9 keys select, and small Space / Esc hints beside the window's buttons." },
    { key = "questTooltipCursor", label = "Tooltips at Cursor While Talking", description = "While a quest, gossip or book window is open, tooltips that normally sit in the screen corner appear at the mouse instead." },
    { key = "questDialogHideUI",  label = "Hide UI While Talking", description = "Fade the rest of the interface while a quest, gossip or book window is open. Restores on close or when combat starts." },
}

-- Compact two-column list: which parts of the UI fade while talking.
local questHideOptions = {
    { key = "questHideActionBars", label = "Action & Status Bars" },
    { key = "questHideUnitFrames", label = "Unit Frames" },
    { key = "questHideTracker",    label = "Objective Tracker" },
    { key = "questHideChat",       label = "Chat & Meter" },
    { key = "questHideMinimap",    label = "Minimap" },
    { key = "questHideRXP",        label = "Guide Addons" },
    { key = "questHideBuffs",      label = "Buffs & Debuffs" },
}

-- ---------------------------------------------------------------------------
-- Widget factories  (parent is always the scroll child)
-- ---------------------------------------------------------------------------
local function CreateCheckbox(parent, option, y)
    local check = CreateFrame("CheckButton", nil, parent, "UICheckButtonTemplate")
    check:SetPoint("TOPLEFT", 20, y)
    check:SetSize(26, 26)

    local label = check:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    label:SetPoint("LEFT", check, "RIGHT", 5, 1)
    label:SetText(option.label)

    local description = check:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    description:SetPoint("TOPLEFT", label, "BOTTOMLEFT", 0, -2)
    description:SetWidth(520)
    description:SetJustifyH("LEFT")
    description:SetText(option.description)

    check:SetScript("OnClick", function(self)
        addon:SetOption(option.key, self:GetChecked())
    end)

    controls[option.key] = check
    return -52   -- height consumed
end

local function CreateSectionHeader(parent, text, y)
    local header = parent:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    header:SetPoint("TOPLEFT", 16, y)
    header:SetText(text)
    return -22
end

local function CreateNote(parent, text, y, width)
    local note = parent:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    note:SetPoint("TOPLEFT", 24, y)
    note:SetWidth(width or 560)
    note:SetJustifyH("LEFT")
    note:SetText(text)
    -- Measure actual height after setting text
    note:SetHeight(0)  -- let it auto-size
    return -36
end

local function CreateSlider(parent, cfg)
    local label = parent:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    label:SetPoint("TOPLEFT", 24, cfg.y)
    label:SetText(cfg.label)

    local description = parent:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    description:SetPoint("TOPLEFT", label, "BOTTOMLEFT", 0, -4)
    description:SetWidth(520)
    description:SetJustifyH("LEFT")
    description:SetText(cfg.description)

    local slider = CreateFrame("Slider", nil, parent, "OptionsSliderTemplate")
    slider:SetPoint("TOPLEFT", description, "BOTTOMLEFT", 4, -18)
    slider:SetWidth(260)
    slider:SetMinMaxValues(cfg.min, cfg.max)
    slider:SetValueStep(cfg.step)
    slider:SetObeyStepOnDrag(true)

    if slider.Low  then slider.Low:SetText(string.format(cfg.format, cfg.min))   end
    if slider.High then slider.High:SetText(string.format(cfg.format, cfg.max))  end
    if slider.Text then slider.Text:SetText("") end

    local valueText = parent:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
    valueText:SetPoint("LEFT", slider, "RIGHT", 14, 0)
    slider.valueText = valueText

    slider:SetScript("OnValueChanged", function(self, value)
        value = math.floor((value / cfg.step) + 0.5) * cfg.step
        self.valueText:SetFormattedText(cfg.format, value)
        if not addon.refreshingSettings and XpieHUDDB[cfg.key] ~= value then
            addon:SetOption(cfg.key, value)
        end
    end)

    controls[cfg.key] = slider
end

-- ---------------------------------------------------------------------------
-- Settings panel with scroll frame
-- ---------------------------------------------------------------------------
function addon:CreateSettings()
    if self.settingsPanel then return end

    -- Outer panel registered with Blizzard
    local panel = CreateFrame("Frame")
    panel.name  = "XpieHUD"
    self.settingsPanel = panel

    -- ScrollFrame fills the panel
    local sf = CreateFrame("ScrollFrame", nil, panel, "UIPanelScrollFrameTemplate")
    sf:SetPoint("TOPLEFT",     panel, "TOPLEFT",      4, -4)
    sf:SetPoint("BOTTOMRIGHT", panel, "BOTTOMRIGHT", -26, 4)

    -- Scroll child holds all actual content
    local content = CreateFrame("Frame", nil, sf)
    content:SetWidth(sf:GetWidth() or 580)
    content:SetHeight(1)   -- will be updated after content is built
    sf:SetScrollChild(content)

    -- Update content width when panel resizes (e.g. first draw)
    panel:SetScript("OnSizeChanged", function(self, w, h)
        sf:SetWidth(w - 30)
        content:SetWidth(w - 50)
    end)

    -- -----------------------------------------------------------------------
    -- Title block (inside scroll child)
    -- -----------------------------------------------------------------------
    local title = content:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
    title:SetPoint("TOPLEFT", 16, -16)
    title:SetText("XpieHUD")

    local subtitle = content:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
    subtitle:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -8)
    subtitle:SetWidth(560)
    subtitle:SetJustifyH("LEFT")
    subtitle:SetText("Lightweight visibility controls for the default Retail HUD.")

    local note = content:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    note:SetPoint("TOPLEFT", subtitle, "BOTTOMLEFT", 0, -8)
    note:SetWidth(560)
    note:SetJustifyH("LEFT")
    note:SetText("Toggle Chat or Minimap from Key Bindings, or with /xpiehud chat and /xpiehud minimap.")

    -- -----------------------------------------------------------------------
    -- Content — track y as we go
    -- -----------------------------------------------------------------------
    local y = -88

    -- General checkboxes
    for _, option in ipairs(options) do
        CreateCheckbox(content, option, y)
        y = y - 52
    end

    y = y - 8

    -- Extra Abilities slider
    CreateSlider(content, {
        key = "extraAbilityScale", label = "Extra Abilities Size",
        description = "Scale the Extra Action Button and Zone Ability element independently of the rest of the UI.",
        min = 40, max = 100, step = 5, format = "%d%%", y = y,
    })
    y = y - 82

    -- -----------------------------------------------------------------------
    -- Guide Addons selector
    -- -----------------------------------------------------------------------
    local guideHead = content:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    guideHead:SetPoint("TOPLEFT", 16, y)
    guideHead:SetText("|cff70d5ffGuide Addons|r")
    y = y - 22

    local guideNote = content:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    guideNote:SetPoint("TOPLEFT", 24, y)
    guideNote:SetWidth(560)
    guideNote:SetJustifyH("LEFT")
    guideNote:SetText("Tick the guide addon(s) you're using. Unticked guides are left completely alone, and anything XpieHUD changed on them is put back.")
    y = y - 30

    for _, option in ipairs(guideOptions) do
        CreateCheckbox(content, option, y)
        -- "(not loaded)" status, filled in by RefreshSettings
        local status = content:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
        status:SetPoint("TOPLEFT", 240, y - 6)
        controls[option.key].status = status
        y = y - 52
    end
    y = y - 8

    -- -----------------------------------------------------------------------
    -- RestedXP section
    -- -----------------------------------------------------------------------
    local rxpHead = content:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    rxpHead:SetPoint("TOPLEFT", 16, y)
    rxpHead:SetText("|cff70d5ffRestedXP|r")
    y = y - 22

    for _, option in ipairs(rxpPanelOptions) do
        CreateCheckbox(content, option, y)
        y = y - 52
    end

    local rxpNote = content:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    rxpNote:SetPoint("TOPLEFT", 24, y)
    rxpNote:SetWidth(560)
    rxpNote:SetJustifyH("LEFT")
    rxpNote:SetText("Enable \"Strip Borders\" to remove frame edges. Use RXP's Background alpha=0 to clear fills. Adjust Opacity to taste.")
    y = y - 30

    -- Strip Borders checkbox (inline, not from table)
    local rxpBorderCheck = CreateFrame("CheckButton", nil, content, "UICheckButtonTemplate")
    rxpBorderCheck:SetPoint("TOPLEFT", 20, y)
    rxpBorderCheck:SetSize(26, 26)
    local rbl = rxpBorderCheck:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    rbl:SetPoint("LEFT", rxpBorderCheck, "RIGHT", 5, 1)
    rbl:SetText("Strip Borders")
    local rbd = rxpBorderCheck:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    rbd:SetPoint("TOPLEFT", rbl, "BOTTOMLEFT", 0, -2)
    rbd:SetWidth(520)
    rbd:SetJustifyH("LEFT")
    rbd:SetText("Hide border and edge textures on RestedXP frames (reload UI to fully reset if toggled off).")
    rxpBorderCheck:SetScript("OnClick", function(self)
        addon:SetOption("rxpHideBorders", self:GetChecked())
    end)
    controls["rxpHideBorders"] = rxpBorderCheck
    y = y - 52

    CreateSlider(content, {
        key = "rxpFrameAlpha", label = "RestedXP Opacity",
        description = "Set transparency for all RestedXP frames (guide window, arrow, item frame).",
        min = 0, max = 100, step = 5, format = "%d%%", y = y,
    })
    y = y - 82

    -- -----------------------------------------------------------------------
    -- Zygor section
    -- -----------------------------------------------------------------------
    local zgvHead = content:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    zgvHead:SetPoint("TOPLEFT", 16, y)
    zgvHead:SetText("|cff70d5ffZygor Guides|r")
    y = y - 22

    for _, option in ipairs(zygorOptions) do
        CreateCheckbox(content, option, y)
        y = y - 52
    end
    y = y - 8

    -- -----------------------------------------------------------------------
    -- Chat / Meter Toggle section
    -- -----------------------------------------------------------------------
    local cmHead = content:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    cmHead:SetPoint("TOPLEFT", 16, y)
    cmHead:SetText("|cff70d5ffChat / Meter Toggle|r")
    y = y - 22

    local cmNote = content:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    cmNote:SetPoint("TOPLEFT", 24, y)
    cmNote:SetWidth(560)
    cmNote:SetJustifyH("LEFT")
    cmNote:SetText("Cycles chat and native damage meter visibility. /xhud meter [0|1|2] or left-click the on-screen button. Right-drag to reposition.")
    y = y - 30

    local cmCheck = CreateFrame("CheckButton", nil, content, "UICheckButtonTemplate")
    cmCheck:SetPoint("TOPLEFT", 20, y)
    cmCheck:SetSize(26, 26)
    local cml = cmCheck:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    cml:SetPoint("LEFT", cmCheck, "RIGHT", 5, 1)
    cml:SetText("Hide Toggle Button")
    local cmd = cmCheck:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    cmd:SetPoint("TOPLEFT", cml, "BOTTOMLEFT", 0, -2)
    cmd:SetWidth(520)
    cmd:SetJustifyH("LEFT")
    cmd:SetText("Hide the on-screen chat/meter toggle button (still usable via /xhud meter).")
    cmCheck:SetScript("OnClick", function(self)
        addon:SetOption("hideChatMeterButton", self:GetChecked())
        if addon.chatMeterButton then
            if self:GetChecked() then addon.chatMeterButton:Hide()
            else addon.chatMeterButton:Show() end
        end
    end)
    controls["hideChatMeterButton"] = cmCheck
    y = y - 52

    -- -----------------------------------------------------------------------
    -- Quest Window section
    -- -----------------------------------------------------------------------
    local qHead = content:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    qHead:SetPoint("TOPLEFT", 16, y)
    qHead:SetText("|cff70d5ffQuest Window|r")
    y = y - 22

    local qNote = content:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    qNote:SetPoint("TOPLEFT", 24, y)
    qNote:SetWidth(560)
    qNote:SetJustifyH("LEFT")
    qNote:SetText("Applies to the quest, gossip and book/plaque windows. Drag a window's title bar to move it. /xhud questreset restores the default position and size. Other addons' panels can be added to the fade with /xhud questscan and /xhud questhide.")
    y = y - 30

    for _, option in ipairs(questOptions) do
        CreateCheckbox(content, option, y)
        y = y - 52
    end

    local hideLabel = content:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    hideLabel:SetPoint("TOPLEFT", 48, y + 6)
    hideLabel:SetText("Fade while talking:")
    y = y - 14

    for index, option in ipairs(questHideOptions) do
        local column = (index - 1) % 2
        local check = CreateFrame("CheckButton", nil, content, "UICheckButtonTemplate")
        check:SetPoint("TOPLEFT", 44 + column * 220, y)
        check:SetSize(24, 24)
        local label = check:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
        label:SetPoint("LEFT", check, "RIGHT", 4, 1)
        label:SetText(option.label)
        check:SetScript("OnClick", function(self)
            addon:SetOption(option.key, self:GetChecked())
        end)
        controls[option.key] = check
        if column == 1 or index == #questHideOptions then
            y = y - 28
        end
    end
    y = y - 12

    CreateSlider(content, {
        key = "questDialogScale", label = "Quest Window Size",
        description = "Scale the quest, gossip and book windows. Takes effect immediately, including on an open window.",
        min = 50, max = 150, step = 5, format = "%d%%", y = y,
    })
    y = y - 82

    local resetButton = CreateFrame("Button", nil, content, "UIPanelButtonTemplate")
    resetButton:SetPoint("TOPLEFT", 24, y)
    resetButton:SetSize(180, 24)
    resetButton:SetText("Reset Position & Size")
    resetButton:SetScript("OnClick", function()
        addon:ResetQuestDialogPosition()
    end)
    y = y - 34

    -- Pad the bottom so the last item isn't flush against the scroll edge
    y = y - 20

    -- Set scroll child height to fit all content
    content:SetHeight(math.abs(y) + 20)

    panel:SetScript("OnShow", function()
        addon:RefreshSettings()
    end)

    if Settings and Settings.RegisterCanvasLayoutCategory and Settings.RegisterAddOnCategory then
        local category = Settings.RegisterCanvasLayoutCategory(panel, "XpieHUD")
        Settings.RegisterAddOnCategory(category)
        self.settingsCategory = category
    elseif InterfaceOptions_AddCategory then
        InterfaceOptions_AddCategory(panel)
    end
end

function addon:RefreshSettings()
    if not XpieHUDDB then return end
    self.refreshingSettings = true
    for _, option in ipairs(options) do
        controls[option.key]:SetChecked(XpieHUDDB[option.key])
    end
    controls.extraAbilityScale:SetValue(XpieHUDDB.extraAbilityScale or self.defaults.extraAbilityScale)
    controls.rxpFrameAlpha:SetValue(XpieHUDDB.rxpFrameAlpha or self.defaults.rxpFrameAlpha)
    if controls["rxpHideBorders"] then
        controls["rxpHideBorders"]:SetChecked(XpieHUDDB.rxpHideBorders)
    end
    if controls["hideChatMeterButton"] then
        controls["hideChatMeterButton"]:SetChecked(XpieHUDDB.hideChatMeterButton)
    end
    for _, option in ipairs(rxpPanelOptions) do
        if controls[option.key] then
            controls[option.key]:SetChecked(XpieHUDDB[option.key])
        end
    end
    for _, option in ipairs(guideOptions) do
        local check = controls[option.key]
        if check then
            check:SetChecked(XpieHUDDB[option.key])
            check.status:SetText(C_AddOns.IsAddOnLoaded(option.addon) and "" or "(not loaded)")
        end
    end
    for _, list in ipairs({ questOptions, questHideOptions, zygorOptions }) do
        for _, option in ipairs(list) do
            if controls[option.key] then
                controls[option.key]:SetChecked(XpieHUDDB[option.key])
            end
        end
    end
    if controls.questDialogScale then
        controls.questDialogScale:SetValue(XpieHUDDB.questDialogScale or self.defaults.questDialogScale)
    end
    self.refreshingSettings = nil
end

function addon:OpenSettings()
    if self.settingsCategory and Settings and Settings.OpenToCategory then
        Settings.OpenToCategory(self.settingsCategory:GetID())
    elseif self.settingsPanel and InterfaceOptionsFrame_OpenToCategory then
        InterfaceOptionsFrame_OpenToCategory(self.settingsPanel)
        InterfaceOptionsFrame_OpenToCategory(self.settingsPanel)
    else
        self:Print("Settings are not available yet. Try again after entering the world.")
    end
end
