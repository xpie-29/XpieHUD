local _, addon = ...

local controls = {}

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
    { key = "questHideChat",       label = "Chat" },
    { key = "questHideMinimap",    label = "Minimap" },
    { key = "questHideRXP",        label = "Zygor Guide" },
    { key = "questHideBuffs",      label = "Buffs & Debuffs" },
}

local zygorOptions = {
    { key = "guideZygor",     label = "Enable Zygor Integration",    description = "Style Zygor Guides Viewer. Unticking puts back everything XpieHUD changed and leaves Zygor alone." },
    { key = "zygorStrip",     label = "Strip Backgrounds & Borders", description = "Transparent Zygor window background and borders; step boxes keep their colours at 50% opacity; title logo hidden." },
    { key = "zygorGoldArrow", label = "Gold Waypoint Arrow",         description = "Use the XpieHUD gold arrowhead as Zygor's arrow skin (also selectable as \"XpieHUD Gold\" in Zygor's own options)." },
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
    return check
end

local function CreateSectionHeader(parent, text, y)
    local header = parent:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    header:SetPoint("TOPLEFT", 16, y)
    header:SetText("|cff70d5ff" .. text .. "|r")
end

local function CreateNote(parent, text, y)
    local note = parent:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    note:SetPoint("TOPLEFT", 24, y)
    note:SetWidth(560)
    note:SetJustifyH("LEFT")
    note:SetText(text)
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

    -- Title block
    local title = content:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
    title:SetPoint("TOPLEFT", 16, -16)
    title:SetText("XpieHUD")

    local subtitle = content:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
    subtitle:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -8)
    subtitle:SetWidth(560)
    subtitle:SetJustifyH("LEFT")
    subtitle:SetText("Quest window quality-of-life and Zygor Guides styling for the native Retail UI.")

    local y = -70

    -- -----------------------------------------------------------------------
    -- Quest Window section
    -- -----------------------------------------------------------------------
    CreateSectionHeader(content, "Quest Window", y)
    y = y - 22
    CreateNote(content, "Applies to the quest, gossip and book/plaque windows. Drag a window's title bar to move it. /xhud questreset restores the default position and size. Other addons' panels can be added to the fade with /xhud questscan and /xhud questhide.", y)
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
    y = y - 44

    -- -----------------------------------------------------------------------
    -- Zygor section
    -- -----------------------------------------------------------------------
    CreateSectionHeader(content, "Zygor Guides", y)
    -- "(not loaded)" status, filled in by RefreshSettings
    local zygorStatus = content:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
    zygorStatus:SetPoint("TOPLEFT", 130, y - 1)
    controls.zygorStatus = zygorStatus
    y = y - 22

    for _, option in ipairs(zygorOptions) do
        CreateCheckbox(content, option, y)
        y = y - 52
    end

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
    if controls.zygorStatus then
        controls.zygorStatus:SetText(C_AddOns.IsAddOnLoaded("ZygorGuidesViewer") and "" or "(not loaded)")
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
