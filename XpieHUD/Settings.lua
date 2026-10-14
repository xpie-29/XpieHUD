local _, addon = ...

-- ---------------------------------------------------------------------------
-- Settings page kit, shared by the core and module addons.
--
--   local page = XpieHUD:NewSettingsPage(bind)
--   page:Header("Zygor Guides")
--   page:Note("...")
--   page:Checkbox({ key = "strip", label = "...", description = "..." })
--   page:CheckGrid("Fade while talking:", { { key = ..., label = ... }, ... })
--   page:Slider({ key = ..., label = ..., description = ..., min, max, step, format })
--   page:Button("Reset", onClick)
--
-- bind = { get = function(key) end, set = function(key, value) end } connects
-- the controls to the core's XpieHUDDB or a module's module.db.
-- ---------------------------------------------------------------------------
local PageMixin = {}
local pages = {}

function addon:NewSettingsPage(bind)
    local page = Mixin({ bind = bind, refreshers = {}, y = -16 }, PageMixin)

    -- Canvas frame registered with Blizzard; a scroll frame fills it.
    page.frame = CreateFrame("Frame")
    local sf = CreateFrame("ScrollFrame", nil, page.frame, "UIPanelScrollFrameTemplate")
    sf:SetPoint("TOPLEFT", page.frame, "TOPLEFT", 4, -4)
    sf:SetPoint("BOTTOMRIGHT", page.frame, "BOTTOMRIGHT", -26, 4)
    page.content = CreateFrame("Frame", nil, sf)
    page.content:SetWidth(580)
    page.content:SetHeight(1)
    sf:SetScrollChild(page.content)
    page.frame:SetScript("OnSizeChanged", function(_, w)
        sf:SetWidth(w - 30)
        page.content:SetWidth(w - 50)
    end)
    page.frame:SetScript("OnShow", function() page:Refresh() end)

    pages[#pages + 1] = page
    return page
end

function PageMixin:Title(text, subtitle)
    local title = self.content:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
    title:SetPoint("TOPLEFT", 16, self.y)
    title:SetText(text)
    self.y = self.y - 26
    if subtitle then
        local sub = self.content:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
        sub:SetPoint("TOPLEFT", 16, self.y)
        sub:SetWidth(560)
        sub:SetJustifyH("LEFT")
        sub:SetText(subtitle)
        self.y = self.y - 28
    end
end

function PageMixin:Header(text)
    local header = self.content:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    header:SetPoint("TOPLEFT", 16, self.y)
    header:SetText("|cff70d5ff" .. text .. "|r")
    self.y = self.y - 22
    return header
end

function PageMixin:Note(text)
    local note = self.content:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    note:SetPoint("TOPLEFT", 24, self.y)
    note:SetWidth(560)
    note:SetJustifyH("LEFT")
    note:SetText(text)
    self.y = self.y - 30
    return note
end

-- Grey text next to the last header, refreshed on show (e.g. "(not loaded)").
function PageMixin:Status(getText)
    local status = self.content:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
    status:SetPoint("TOPLEFT", 150, self.y + 21)
    self.refreshers[#self.refreshers + 1] = function() status:SetText(getText() or "") end
end

function PageMixin:Checkbox(opt)
    local bind = self.bind
    local check = CreateFrame("CheckButton", nil, self.content, "UICheckButtonTemplate")
    check:SetPoint("TOPLEFT", 20, self.y)
    check:SetSize(26, 26)

    local label = check:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    label:SetPoint("LEFT", check, "RIGHT", 5, 1)
    label:SetText(opt.label)

    local description = check:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    description:SetPoint("TOPLEFT", label, "BOTTOMLEFT", 0, -2)
    description:SetWidth(520)
    description:SetJustifyH("LEFT")
    description:SetText(opt.description)

    check:SetScript("OnClick", function(btn) bind.set(opt.key, btn:GetChecked()) end)
    self.refreshers[#self.refreshers + 1] = function() check:SetChecked(bind.get(opt.key)) end
    self.y = self.y - 52
    return check
end

-- Compact two-column list of label-only checkboxes.
function PageMixin:CheckGrid(label, opts)
    local bind = self.bind
    local caption = self.content:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    caption:SetPoint("TOPLEFT", 48, self.y + 6)
    caption:SetText(label)
    self.y = self.y - 14

    for index, opt in ipairs(opts) do
        local column = (index - 1) % 2
        local check = CreateFrame("CheckButton", nil, self.content, "UICheckButtonTemplate")
        check:SetPoint("TOPLEFT", 44 + column * 220, self.y)
        check:SetSize(24, 24)
        local text = check:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
        text:SetPoint("LEFT", check, "RIGHT", 4, 1)
        text:SetText(opt.label)
        check:SetScript("OnClick", function(btn) bind.set(opt.key, btn:GetChecked()) end)
        self.refreshers[#self.refreshers + 1] = function() check:SetChecked(bind.get(opt.key)) end
        if column == 1 or index == #opts then
            self.y = self.y - 28
        end
    end
    self.y = self.y - 12
end

function PageMixin:Slider(cfg)
    local page, bind = self, self.bind
    local label = self.content:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    label:SetPoint("TOPLEFT", 24, self.y)
    label:SetText(cfg.label)

    local description = self.content:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    description:SetPoint("TOPLEFT", label, "BOTTOMLEFT", 0, -4)
    description:SetWidth(520)
    description:SetJustifyH("LEFT")
    description:SetText(cfg.description)

    local slider = CreateFrame("Slider", nil, self.content, "OptionsSliderTemplate")
    slider:SetPoint("TOPLEFT", description, "BOTTOMLEFT", 4, -18)
    slider:SetWidth(260)
    slider:SetMinMaxValues(cfg.min, cfg.max)
    slider:SetValueStep(cfg.step)
    slider:SetObeyStepOnDrag(true)
    if slider.Low  then slider.Low:SetText(string.format(cfg.format, cfg.min))  end
    if slider.High then slider.High:SetText(string.format(cfg.format, cfg.max)) end
    if slider.Text then slider.Text:SetText("") end

    local valueText = self.content:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
    valueText:SetPoint("LEFT", slider, "RIGHT", 14, 0)

    slider:SetScript("OnValueChanged", function(_, value)
        value = math.floor((value / cfg.step) + 0.5) * cfg.step
        valueText:SetFormattedText(cfg.format, value)
        if not page.refreshing and bind.get(cfg.key) ~= value then
            bind.set(cfg.key, value)
        end
    end)
    self.refreshers[#self.refreshers + 1] = function() slider:SetValue(bind.get(cfg.key) or cfg.min) end
    self.y = self.y - 82
    return slider
end

function PageMixin:Button(text, onClick)
    local button = CreateFrame("Button", nil, self.content, "UIPanelButtonTemplate")
    button:SetPoint("TOPLEFT", 24, self.y)
    button:SetSize(180, 24)
    button:SetText(text)
    button:SetScript("OnClick", onClick)
    self.y = self.y - 34
    return button
end

function PageMixin:Space(px)
    self.y = self.y - (px or 10)
end

function PageMixin:Refresh()
    self.refreshing = true
    for _, refresh in ipairs(self.refreshers) do refresh() end
    self.refreshing = nil
end

function PageMixin:Finish()
    self.content:SetHeight(math.abs(self.y) + 40)
end

-- ---------------------------------------------------------------------------
-- Core page (Quest Window) + one sub-page per module. Built at PLAYER_LOGIN,
-- once every module addon has loaded and registered.
-- ---------------------------------------------------------------------------
local coreBind = {
    get = function(key) return XpieHUDDB[key] end,
    set = function(key, value) addon:SetOption(key, value) end,
}

local function BuildCorePage()
    local page = addon:NewSettingsPage(coreBind)
    page:Title("XpieHUD", "Quality-of-life for Blizzard's native quest, gossip and book windows. Extensions appear as sub-pages below.")

    page:Header("Quest Window")
    page:Note("Drag a window's title bar to move it. /xhud questreset restores the default position and size. Other addons' panels can be added to the fade with /xhud questscan and /xhud questhide.")
    page:Checkbox({ key = "questDialogEnabled", label = "Enable Quest Window Enhancements", description = "Master switch for everything on this page. Blizzard's quest and gossip windows themselves are never replaced." })
    page:Checkbox({ key = "questDialogKeys",    label = "Keyboard Shortcuts", description = "1–9 pick options, quests and rewards. Space accepts, continues or completes. Out of combat only; all other keys pass through." })
    page:Checkbox({ key = "questDialogBadges",  label = "Number Badges & Key Hints", description = "Show numbers on the options the 1–9 keys select, and small Space / Esc hints beside the window's buttons." })
    page:Checkbox({ key = "questTooltipCursor", label = "Tooltips at Cursor While Talking", description = "While a quest, gossip or book window is open, tooltips that normally sit in the screen corner appear at the mouse instead." })
    page:Checkbox({ key = "questDialogHideUI",  label = "Hide UI While Talking", description = "Fade the rest of the interface while a quest, gossip or book window is open. Restores on close or when combat starts." })
    page:CheckGrid("Fade while talking:", {
        { key = "questHideActionBars", label = "Action & Status Bars" },
        { key = "questHideUnitFrames", label = "Unit Frames" },
        { key = "questHideTracker",    label = "Objective Tracker" },
        { key = "questHideChat",       label = "Chat" },
        { key = "questHideMinimap",    label = "Minimap" },
        { key = "questHideRXP",        label = "Guide Addons" },
        { key = "questHideBuffs",      label = "Buffs & Debuffs" },
    })
    page:Slider({
        key = "questDialogScale", label = "Quest Window Size",
        description = "Scale the quest, gossip and book windows. Takes effect immediately, including on an open window.",
        min = 50, max = 150, step = 5, format = "%d%%",
    })
    page:Button("Reset Position & Size", function() addon:ResetQuestDialogPosition() end)
    page:Finish()
    return page
end

local function ModuleBind(module)
    return {
        get = function(key) return module.db[key] end,
        set = function(key, value) module:SetOption(key, value) end,
    }
end

function addon:CreateSettings()
    if self.settingsCategory then return end
    if not (Settings and Settings.RegisterCanvasLayoutCategory) then return end

    local corePage = BuildCorePage()
    local category = Settings.RegisterCanvasLayoutCategory(corePage.frame, "XpieHUD")

    for _, module in ipairs(self.modules) do
        if module.BuildSettings then
            local page = self:NewSettingsPage(ModuleBind(module))
            page:Title(module.title or module.id)
            module:BuildSettings(page)
            page:Finish()
            Settings.RegisterCanvasLayoutSubcategory(category, page.frame, module.title or module.id)
        end
    end

    Settings.RegisterAddOnCategory(category)
    self.settingsCategory = category
end

function addon:RefreshSettings()
    for _, page in ipairs(pages) do
        if page.frame:IsVisible() then page:Refresh() end
    end
end

function addon:OpenSettings()
    if self.settingsCategory and Settings and Settings.OpenToCategory then
        Settings.OpenToCategory(self.settingsCategory:GetID())
    else
        self:Print("Settings are not available yet. Try again after entering the world.")
    end
end
