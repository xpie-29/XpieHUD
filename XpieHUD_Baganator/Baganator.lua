-- Baganator.lua  (XpieHUD_Baganator module)
-- Baganator's windows in the style of Blizzard's Combined Backpack.
-- Style "xpiehud" (default), on top of Baganator's own "Blizzard" skin:
--   * the round portrait back in the top-left corner (bag icon, or the
--     banker for the bank)
--   * one native gear menu right of the portrait for Baganator's view and
--     search buttons (All Characters, Bank, Guild Bank, Search Everywhere,
--     Saved Searches, Transfer, Search Help)
--   * Customise and Bag Slots buttons removed (settings live on the minimap
--     button; the native bag bar stays in use)
--   * a native Clean Up Bags button at the end of the search box
--   * flat, native-size icon buttons along the bottom (Currencies, ...)
--   * the native coin box behind the money line
-- Style "original" leaves Baganator alone.
--
-- Uses only Baganator's public skin API (Baganator.API.Skins.RegisterListener /
-- GetAllFrames / GetCurrentSkin): every frame Baganator builds is announced
-- with a region type and tags, e.g. IconButton {"sort"}. Checked against
-- Baganator 837 (12.1.5). Baganator's buttons are never reparented (their
-- click handlers use GetParent); the ones we replace are made invisible and
-- click-through, and our controls call their :Click(), so Baganator's own
-- behaviour (sort modes, transfer rules, menus) is kept.
-- Baganator isn't secure code, so hooking it can't taint Blizzard's UI.

local core = XpieHUD

local module = core:RegisterModule("baganator", {
    title = "Baganator",
    defaults = {
        -- "xpiehud": Combined Backpack look. "original": leave Baganator alone.
        style = "xpiehud",
    },
})

local BAG_ICON     = "Interface\\Icons\\Inv_misc_bag_08"   -- ContainerFrameCombinedBags portrait
-- The Combined Backpack's frame: the small portrait corner ("HeldBagLayout"),
-- a 36px portrait at (-4, 1) and the title 35px in (ContainerFrame.lua).
local BORDER_LAYOUT = "HeldBagLayout"
local PORTRAIT_SIZE, PORTRAIT_X, PORTRAIT_Y = 36, -4, 1
local TITLE_OFFSET = 35
local GEAR_SIZE    = 24
local GEAR_X, GEAR_Y = 0, -3   -- from the title area's left edge: tucked against the portrait ring, centred on the title bar (tuned in game)
local SEARCH_LEFT  = 40     -- search box starts clear of the portrait ring
local SORT_W, SORT_H = 28, 26                              -- BagItemAutoSortButton
local SORT_GAP     = 4
local SMALL_BUTTON = 18       -- flattened icon buttons: fit inside the coin box
local SMALL_GLOW   = 16       -- their hover glow, kept inside the button
local COINBOX_H    = 17                                     -- ContainerMoneyFrameTemplate.Border
local COINBOX_INSET = 8
-- Currencies button: same size as the gear, bottom-left, centred on the
-- coin box, which starts just right of it.
local CURRENCY_SIZE, CURRENCY_ICON = 24, 20
local CURRENCY_X   = 6
local COINBOX_GAP  = 2

-- Gear menu entries, in menu order: Baganator button tag -> label.
local MENU_ITEMS = {
    { tag = "allCharacters",    label = "All Characters" },
    { tag = "bank",             label = "Bank" },
    { tag = "guildBank",        label = "Guild Bank" },
    { tag = "searchEverywhere", label = "Search Everywhere" },
    { tag = "savedsearches",    label = "Saved Searches" },
    { tag = "transfer",         label = "Transfer Items" },
    { tag = "help",             label = "Search Help" },
}
local MENU_TAGS = {}
for _, item in ipairs(MENU_ITEMS) do MENU_TAGS[item.tag] = true end

-- Removed outright, no menu entry.
local REMOVED_TAGS = { customise = true, bagSlots = true }
-- Kept where Baganator puts them, flattened to native-size icon buttons.
local FLAT_TAGS = { collapsingBagSection = true }
-- Windows that get the Combined Backpack treatment (ButtonFrame tags).
local VIEW_TAGS = { backpack = true, bank = true, guild = true }

local function Active()
    if module.db.style ~= "xpiehud" then return false end
    local skins = Baganator and Baganator.API and Baganator.API.Skins
    return skins and skins.GetCurrentSkin and skins.GetCurrentSkin() == "blizzard"
end

local function HasTag(tags, wanted)
    if not tags then return nil end
    for _, tag in ipairs(tags) do
        if wanted[tag] then return tag end
    end
end

-- ---------------------------------------------------------------------------
-- Stashing: invisible and click-through, but still parented and clickable
-- from code. Persistent, because Baganator sets alpha on its buttons.
-- ---------------------------------------------------------------------------
local stashed = {}

local function Stash(region)
    if stashed[region] then return end
    stashed[region] = true
    region:SetAlpha(0)
    hooksecurefunc(region, "SetAlpha", function(self, alpha)
        if alpha ~= 0 then self:SetAlpha(0) end
    end)
    if region.EnableMouse then
        region:EnableMouse(false)
        hooksecurefunc(region, "EnableMouse", function(self, enable)
            if enable then self:EnableMouse(false) end
        end)
    end
end

-- Tagged buttons we've seen: button -> tag. Looked up per window when the
-- gear menu opens (buttons are announced before their window is).
local taggedButtons = {}

local function BelongsTo(region, view)
    local parent = region:GetParent()
    while parent do
        if parent == view then return true end
        parent = parent:GetParent()
    end
    return false
end

local function FindButton(view, tag)
    for button, buttonTag in pairs(taggedButtons) do
        if buttonTag == tag and BelongsTo(button, view) then return button end
    end
end

-- ---------------------------------------------------------------------------
-- Flat icon buttons: Baganator's are red UIPanelButtonTemplate buttons
-- (32x22) with a small icon; keep the icon, drop the red button art.
-- ---------------------------------------------------------------------------
local function Flatten(button)
    if button.xpieFlat then return end
    button.xpieFlat = true
    for _, key in ipairs({ "Left", "Middle", "Right" }) do
        if button[key] then Stash(button[key]) end
    end
    button:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD")
    local glow = button:GetHighlightTexture()
    glow:ClearAllPoints()
    glow:SetPoint("CENTER")
    glow:SetSize(SMALL_GLOW, SMALL_GLOW)
    button:SetSize(SMALL_BUTTON, SMALL_BUTTON)
    -- Baganator's tooltip opens to the right, over the items; show it below
    -- the window instead.
    button:HookScript("OnEnter", function(self)
        if GameTooltip:IsOwned(self) then
            GameTooltip:ClearAllPoints()
            GameTooltip:SetPoint("TOPLEFT", self, "BOTTOMLEFT", 0, -6)
        end
    end)
end

-- ---------------------------------------------------------------------------
-- Currencies button: styled like the gear (no button frame, gear-sized, the
-- icon itself glows on hover and sinks on press), bottom-left, with the coin
-- box running from its right edge.
-- ---------------------------------------------------------------------------
local function PlaceCurrency(button)
    if button.xpiePlacing then return end
    button.xpiePlacing = true
    button:ClearAllPoints()
    button:SetPoint("BOTTOMLEFT", button:GetParent(), "BOTTOMLEFT", CURRENCY_X,
        COINBOX_INSET + (COINBOX_H - CURRENCY_SIZE) / 2)
    button.xpiePlacing = false
end

local function StyleCurrency(button)
    if button.xpieCurrency then return end
    button.xpieCurrency = true
    Flatten(button)   -- drops the red art, keeps the tooltip below the window
    button:SetSize(CURRENCY_SIZE, CURRENCY_SIZE)

    local icon = button.Icon
    if icon then
        icon:SetSize(CURRENCY_ICON, CURRENCY_ICON)
        button:SetHighlightTexture(icon:GetTexture(), "ADD")
        local glow = button:GetHighlightTexture()
        glow:ClearAllPoints()
        glow:SetPoint("CENTER")
        glow:SetSize(CURRENCY_ICON, CURRENCY_ICON)
        glow:SetAlpha(0.4)
        button:HookScript("OnMouseDown", function()
            icon:SetPoint("CENTER", 1, -1)
        end)
        button:HookScript("OnMouseUp", function()
            icon:SetPoint("CENTER", 0, 0)
        end)
    end

    hooksecurefunc(button, "SetPoint", PlaceCurrency)
    PlaceCurrency(button)
end

-- ---------------------------------------------------------------------------
-- Clean Up Bags button at the end of the search box, like the native bag.
-- ---------------------------------------------------------------------------
local function AnchorSearch(widget)
    local box, side = widget.SearchBox, widget.sideSpacing
    if not (box and side) then return end
    local view = widget:GetParent()
    local sort = widget.xpieSort
    local room = (sort and sort:IsShown()) and (SORT_W + SORT_GAP) or 0
    -- Replaces Baganator's RIGHT anchor (which left room for three buttons).
    box:SetPoint("RIGHT", view, "RIGHT", -side - room, 0)
    -- With the portrait back, start the box clear of its ring (Baganator's
    -- TOPLEFT is sideSpacing + 11 in, 28 down).
    if view.xpieKind then
        box:SetPoint("TOPLEFT", view, "TOPLEFT", math.max(side + 11, SEARCH_LEFT), -28)
    end
end

local function HookSearchWidget(widget)
    if widget.xpieHooked or not widget.SetSpacing then return end
    widget.xpieHooked = true
    hooksecurefunc(widget, "SetSpacing", AnchorSearch)
    AnchorSearch(widget)
end

-- Baganator announces its sort button before the window's search widget
-- exists, so sort buttons wait here until it does.
local pendingSorts = {}

local function CreateSortButton(original)
    local view = original:GetParent()
    local widget = view and view.SearchWidget
    if widget and widget.xpieSort then return true end
    if not (widget and widget.SearchBox) then return false end

    local button = CreateFrame("Button", nil, view)
    button:SetSize(SORT_W, SORT_H)
    button:SetNormalAtlas("bags-button-autosort-up")
    button:SetPushedAtlas("bags-button-autosort-down")
    button:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD")
    local highlight = button:GetHighlightTexture()
    highlight:ClearAllPoints()
    highlight:SetPoint("CENTER")
    highlight:SetSize(24, 23)
    button:SetPoint("LEFT", widget.SearchBox, "RIGHT", SORT_GAP, 0)
    button:SetFrameLevel(original:GetFrameLevel())
    button:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    button:SetScript("OnClick", function(_, mouseButton)
        original:Click(mouseButton)
    end)
    button:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip_SetTitle(GameTooltip, BAG_CLEANUP_BAGS or "Clean Up Bags", HIGHLIGHT_FONT_COLOR)
        GameTooltip:Show()
    end)
    button:SetScript("OnLeave", GameTooltip_Hide)
    widget.xpieSort = button

    -- Baganator shows its sort button only for the live character.
    local function Sync()
        button:SetShown(original:IsShown())
        AnchorSearch(widget)
    end
    hooksecurefunc(original, "Show", Sync)
    hooksecurefunc(original, "Hide", Sync)
    hooksecurefunc(original, "SetShown", Sync)
    Sync()
    HookSearchWidget(widget)
    return true
end

local function CreatePendingSorts()
    for original in pairs(pendingSorts) do
        if CreateSortButton(original) then pendingSorts[original] = nil end
    end
end

-- ---------------------------------------------------------------------------
-- Windows: portrait, gear menu, coin box.
-- ---------------------------------------------------------------------------
local function UpdatePortrait(view)
    if view.xpieKind == "bank" and UnitExists("npc") then
        view:SetPortraitToUnit("npc")      -- like BankFrame
    else
        view:SetPortraitToAsset(BAG_ICON)
    end
end

local function BuildMenu(gear, root)
    local view = gear:GetParent()
    for _, item in ipairs(MENU_ITEMS) do
        local original = FindButton(view, item.tag)
        if original and original:IsShown() then
            local entry = root:CreateButton(item.label, function()
                original:Click("LeftButton")
            end)
            entry:SetEnabled(original:IsEnabled())
        end
    end
end

local function CreateGear(view)
    local gear = CreateFrame("DropdownButton", nil, view)
    gear:SetSize(GEAR_SIZE, GEAR_SIZE)
    local icon = gear:CreateTexture(nil, "ARTWORK")
    icon:SetAllPoints()
    icon:SetAtlas("common-dropdown-a-button-settings-shadowless")
    local hover = gear:CreateTexture(nil, "HIGHLIGHT")
    hover:SetAllPoints()
    hover:SetAtlas("common-dropdown-a-button-settings-hover-shadowless")
    gear:SetScript("OnMouseDown", function() icon:SetAtlas("common-dropdown-a-button-settings-pressed-shadowless") end)
    gear:SetScript("OnMouseUp", function() icon:SetAtlas("common-dropdown-a-button-settings-shadowless") end)
    if view.TitleContainer then
        gear:SetPoint("LEFT", view.TitleContainer, "LEFT", GEAR_X, GEAR_Y)
    else
        gear:SetPoint("TOPLEFT", view, "TOPLEFT", TITLE_OFFSET + GEAR_X, 2 + GEAR_Y)
    end
    -- Above the frame's border art (the NineSlice sits high, at the title bar).
    local border = view.NineSlice and view.NineSlice:GetFrameLevel() or view:GetFrameLevel()
    gear:SetFrameLevel(math.max(border, view:GetFrameLevel()) + 5)
    gear:SetupMenu(BuildMenu)
    view.xpieGear = gear
end

local function CreateCoinBox(view)
    local box = CreateFrame("Frame", nil, view)
    box:SetHeight(COINBOX_H)
    -- Starts right of the Currencies button when the window has one.
    local left = FindButton(view, "currency") and (CURRENCY_X + CURRENCY_SIZE + COINBOX_GAP) or COINBOX_INSET
    box:SetPoint("BOTTOMLEFT", left, COINBOX_INSET)
    box:SetPoint("BOTTOMRIGHT", -COINBOX_INSET, COINBOX_INSET)
    local function Piece(atlas)
        local t = box:CreateTexture(nil, "BACKGROUND")
        t:SetTexelSnappingBias(0)
        t:SetAtlas(atlas)
        return t
    end
    local left, right, middle = Piece("common-coinbox-left"), Piece("common-coinbox-right"), Piece("_common-coinbox-center")
    left:SetSize(8, COINBOX_H)
    left:SetPoint("LEFT")
    right:SetSize(8, COINBOX_H)
    right:SetPoint("RIGHT")
    middle:SetPoint("TOPLEFT", left, "TOPRIGHT")
    middle:SetPoint("BOTTOMRIGHT", right, "BOTTOMLEFT")
    box:SetFrameLevel(view:GetFrameLevel() + 1)
    view.xpieCoinBox = box
end

local function StyleView(view, kind)
    if view.xpieKind then return end
    view.xpieKind = kind

    if ButtonFrameTemplate_ShowPortrait and view.SetPortraitToAsset then
        ButtonFrameTemplate_ShowPortrait(view)
        -- Then the Combined Backpack's smaller portrait corner and title spot.
        if view.SetBorder and NineSliceUtil.GetLayout(BORDER_LAYOUT) then
            view:SetBorder(BORDER_LAYOUT)
        end
        if view.SetPortraitTextureSizeAndOffset then
            view:SetPortraitTextureSizeAndOffset(PORTRAIT_SIZE, PORTRAIT_X, PORTRAIT_Y)
        end
        if view.SetTitleOffsets then
            view:SetTitleOffsets(TITLE_OFFSET)
        elseif view.TitleContainer then
            view.TitleContainer:SetPoint("TOPLEFT", view, "TOPLEFT", TITLE_OFFSET, -1)
        end
        UpdatePortrait(view)
        view:HookScript("OnShow", UpdatePortrait)
    end
    -- The Combined Backpack is a flat portrait frame: no tile streaks.
    if view.TopTileStreaks then Stash(view.TopTileStreaks) end

    CreateGear(view)
    if kind == "backpack" then CreateCoinBox(view) end
    CreatePendingSorts()
    if view.SearchWidget then AnchorSearch(view.SearchWidget) end
end

-- ---------------------------------------------------------------------------
-- Skin listener
-- ---------------------------------------------------------------------------
local function OnFrame(details)
    if not Active() then return end
    local region, regionType, tags = details.region, details.regionType, details.tags

    if regionType == "IconButton" then
        local tag = HasTag(tags, MENU_TAGS) or HasTag(tags, REMOVED_TAGS)
        if tag then
            taggedButtons[region] = tag
            Stash(region)
        elseif HasTag(tags, { sort = true }) then
            Stash(region)
            if not CreateSortButton(region) then pendingSorts[region] = true end
        elseif HasTag(tags, { currency = true }) then
            taggedButtons[region] = "currency"
            StyleCurrency(region)
        elseif HasTag(tags, FLAT_TAGS) then
            Flatten(region)
        end
    elseif regionType == "SearchBox" then
        local widget = region:GetParent()
        if widget and widget.SearchBox == region then
            HookSearchWidget(widget)
            CreatePendingSorts()
        end
    elseif regionType == "ButtonFrame" then
        local kind = HasTag(tags, VIEW_TAGS)
        if kind then StyleView(region, kind) end
    end
end

if Baganator and Baganator.API and Baganator.API.Skins then
    Baganator.API.Skins.RegisterListener(OnFrame)
    -- Frames announced before we loaded (normally none: Baganator builds its
    -- windows at PLAYER_LOGIN, after every addon has loaded).
    for _, details in ipairs(Baganator.API.Skins.GetAllFrames() or {}) do
        OnFrame(details)
    end
end

-- ---------------------------------------------------------------------------
-- /xhud bagbuttons: preview of native square button art for the Currencies
-- button, next to the gear, with working hover and press states.
-- Temporary: remove once a look is chosen.
-- ---------------------------------------------------------------------------
local PREVIEW_ICON = "Interface\\AddOns\\Baganator\\Assets\\Currency.png"
local PREVIEW_HOVER = "Interface\\Buttons\\UI-Common-MouseHilight"
local PREVIEWS = {
    { label = "Gear",  atlas = { "common-dropdown-a-button-settings-shadowless", "common-dropdown-a-button-settings-pressed-shadowless", "common-dropdown-a-button-settings-hover-shadowless" }, noIcon = true },
    { label = "A",     atlas = { "common-button-square-gray-up", "common-button-square-gray-down" } },
    { label = "B",     atlas = { "common-button-tertiary-square-normal", "common-button-tertiary-square-pressed" } },
    { label = "C",     file  = { "Interface\\Buttons\\UI-SquareButton-Up", "Interface\\Buttons\\UI-SquareButton-Down" } },
    { label = "D",     atlas = { "common-dropdown-a-button-shadowless", "common-dropdown-a-button-pressed-shadowless", "common-dropdown-a-button-hover-shadowless" } },
}

local previewFrame
local function ShowButtonPreview()
    if previewFrame then
        previewFrame:SetShown(not previewFrame:IsShown())
        return
    end
    local f = CreateFrame("Frame", nil, UIParent, "TooltipBackdropTemplate")
    f:SetSize(#PREVIEWS * 44 + 16, 64)
    f:SetPoint("CENTER", 0, 120)
    f:SetFrameStrata("DIALOG")
    f:EnableMouse(true)
    for i, p in ipairs(PREVIEWS) do
        local b = CreateFrame("Button", nil, f)
        b:SetSize(GEAR_SIZE, GEAR_SIZE)
        b:SetPoint("TOPLEFT", 8 + (i - 1) * 44 + 10, -10)
        local normal = b:CreateTexture(nil, "BACKGROUND")
        normal:SetAllPoints()
        local function Set(state)
            if p.atlas then normal:SetAtlas(p.atlas[state] or p.atlas[1]) else normal:SetTexture(p.file[state] or p.file[1]) end
        end
        Set(1)
        local icon
        if not p.noIcon then
            icon = b:CreateTexture(nil, "ARTWORK")
            icon:SetTexture(PREVIEW_ICON)
            icon:SetSize(14, 14)
            icon:SetPoint("CENTER")
        end
        if p.atlas and p.atlas[3] then
            b:SetScript("OnEnter", function() Set(3) end)
            b:SetScript("OnLeave", function() Set(1) end)
        else
            b:SetHighlightTexture(PREVIEW_HOVER, "ADD")
        end
        b:SetScript("OnMouseDown", function()
            Set(2)
            if icon then icon:SetPoint("CENTER", 1, -1) end
        end)
        b:SetScript("OnMouseUp", function()
            Set(b:IsMouseOver() and p.atlas and p.atlas[3] and 3 or 1)
            if icon then icon:SetPoint("CENTER", 0, 0) end
        end)
        local text = f:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
        text:SetPoint("TOP", b, "BOTTOM", 0, -4)
        text:SetText(p.label)
    end
    previewFrame = f
end

core:RegisterCommand("bagbuttons", ShowButtonPreview, "preview button styles for Baganator's Currencies button (toggle)")

-- ---------------------------------------------------------------------------
-- Settings
-- ---------------------------------------------------------------------------
function module:BuildSettings(page)
    page:Status(function()
        if not Active() and module.db.style == "xpiehud" then
            return "(Baganator's skin isn't \"Blizzard\": choose it under Customise > Theme)"
        end
        return ""
    end)
    page:Note("Choose Baganator's original look, or the XpieHUD style: Blizzard's Combined Backpack look with a portrait, one gear menu for Baganator's extra buttons, the native Clean Up Bags button and coin box. Needs Baganator's \"Blizzard\" skin. Changing the style takes effect after /reload. Disable the XpieHUD_Baganator addon to remove this page completely.")
    page:Dropdown({
        key = "style", label = "Style",
        values = function()
            return {
                { key = "xpiehud",  label = "XpieHUD" },
                { key = "original", label = "Original (leave Baganator's look alone)" },
            }
        end,
    })
end
