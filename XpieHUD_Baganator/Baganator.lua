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

local _, ns = ...
local core = XpieHUD

local PROFILE_NAME = "XpieHUD"

local module = core:RegisterModule("baganator", {
    title = "Baganator",
    defaults = {
        -- "xpiehud": Combined Backpack look. "original": leave Baganator alone.
        style = "xpiehud",
        -- Set each new character's Baganator up with the XpieHUD profile
        -- (Profile.lua) once; the player can change profile in Baganator after.
        useProfile = true,
        profileApplied = {},   -- ["Name-Realm"] = true
    },
})

local BAG_ICON     = "Interface\\Icons\\Inv_misc_bag_08"   -- ContainerFrameCombinedBags portrait
-- The Combined Backpack's frame: the small portrait corner ("HeldBagLayout"),
-- a 36px portrait at (-4, 1) and the title 35px in (ContainerFrame.lua).
local BORDER_LAYOUT = "HeldBagLayout"
local PORTRAIT_SIZE, PORTRAIT_X, PORTRAIT_Y = 36, -4, 1
local TITLE_OFFSET = 35
local BG_LEFT      = 2      -- background inset from the left edge (PortraitFrameFlatBaseTemplate)
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
local CURRENCY_SIZE, CURRENCY_ICON = 24, 14
local CURRENCY_ICON_Y = 2   -- the frame's arrow sits low; the icon covers it centred 2px up (tuned in game)
local CURRENCY_X   = 6
local CURRENCY_Y   = -2     -- the frame art sits high in its texture; lines up with the coin box (tuned in game)
-- The gear's frame without the gear: the dropdown button art (its arrow is
-- hidden under the icon), with the same normal / hover / pressed states.
local CURRENCY_ART = {
    normal       = "common-dropdown-a-button-shadowless",
    hover        = "common-dropdown-a-button-hover-shadowless",
    pressed      = "common-dropdown-a-button-pressed-shadowless",
    pressedHover = "common-dropdown-a-button-pressedhover-shadowless",
}
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
-- Currencies button: in the gear's square frame (gear-sized, with its hover
-- and pressed states), bottom-left, with the coin box running from its right
-- edge.
-- ---------------------------------------------------------------------------
local function PlaceCurrency(button)
    if button.xpiePlacing then return end
    button.xpiePlacing = true
    button:ClearAllPoints()
    button:SetPoint("BOTTOMLEFT", button:GetParent(), "BOTTOMLEFT", CURRENCY_X,
        COINBOX_INSET + (COINBOX_H - CURRENCY_SIZE) / 2 + CURRENCY_Y)
    button.xpiePlacing = false
end

local function StyleCurrency(button)
    if button.xpieCurrency then return end
    button.xpieCurrency = true
    Flatten(button)   -- drops the red art, keeps the tooltip below the window
    Stash(button:GetHighlightTexture())   -- the frame art has its own hover state
    button:SetSize(CURRENCY_SIZE, CURRENCY_SIZE)

    local frame = button:CreateTexture(nil, "BACKGROUND", nil, 1)
    frame:SetAllPoints()
    local over, down = false, false
    local function Update()
        frame:SetAtlas(down and (over and CURRENCY_ART.pressedHover or CURRENCY_ART.pressed)
            or (over and CURRENCY_ART.hover or CURRENCY_ART.normal))
    end
    Update()

    local icon = button.Icon
    local function PlaceIcon()
        if not icon then return end
        icon:ClearAllPoints()
        icon:SetPoint("CENTER", down and 1 or 0, CURRENCY_ICON_Y - (down and 1 or 0))
    end
    if icon then
        icon:SetSize(CURRENCY_ICON, CURRENCY_ICON)
        icon:SetDrawLayer("ARTWORK", 2)
        PlaceIcon()
    end

    button:HookScript("OnEnter", function() over = true; Update() end)
    button:HookScript("OnLeave", function() over = false; Update() end)
    button:HookScript("OnMouseDown", function() down = true; Update(); PlaceIcon() end)
    button:HookScript("OnMouseUp", function() down = false; Update(); PlaceIcon() end)

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
    -- Baganator's Blizzard skin insets the background 6px for its own frame
    -- (and re-applies it on layout and setting changes), which leaves a gap
    -- inside the thinner HeldBagLayout edge; keep it 2px in, like the native bag.
    if view.Bg and view.Bg.GetPointByName then
        local function FixBgLeft(bg)
            if bg.xpieFixing then return end
            local point, relativeTo, relativePoint, x, y = bg:GetPointByName("TOPLEFT")
            if point and x ~= BG_LEFT then
                bg.xpieFixing = true
                bg:SetPoint(point, relativeTo, relativePoint, BG_LEFT, y)
                bg.xpieFixing = false
            end
        end
        hooksecurefunc(view.Bg, "SetPoint", FixBgLeft)
        FixBgLeft(view.Bg)
    end
    -- The Combined Backpack is a flat portrait frame: no tile streaks.
    if view.TopTileStreaks then Stash(view.TopTileStreaks) end

    CreateGear(view)
    if kind == "backpack" then CreateCoinBox(view) end
    CreatePendingSorts()
    if view.SearchWidget then AnchorSearch(view.SearchWidget) end
end

-- ---------------------------------------------------------------------------
-- Category section headers ("Equipment", "Crafting") as Objective Tracker
-- section headers ("Campaign", "Quests"): the gold
-- "UI-QuestTracker-Secondary-Objective-Header" bar across the bag window,
-- the title in the font and gold of a tracker quest name, lined up with the first item icon,
-- and the tracker's -/+ button lined up with the last icon, instead of
-- Baganator's arrow (ObjectiveTrackerModuleHeaderTemplate).
-- The header button spans the item area, so clicking anywhere on it still
-- collapses / expands, and right-click still transfers the section.
-- ---------------------------------------------------------------------------
local SECTION_BAR      = "UI-QuestTracker-Secondary-Objective-Header"
local SECTION_COLLAPSE = "ui-questtrackerbutton-secondary-collapse"   -- shown while expanded (-)
local SECTION_EXPAND   = "ui-questtrackerbutton-secondary-expand"     -- shown while collapsed (+)
local SECTION_HOVER    = "ui-questtrackerbutton-yellow-highlight"
local SECTION_TEXT_X   = 0      -- title starts at the item icons' left edge
local SECTION_TOGGLE   = 16
-- The art's ends fade out over ~17px; the tracker lets the faded ends
-- overhang, so its gold line runs from well before the title to just past the
-- -/+ button. Here: on the right the line ends 2px past the -/+ button, and
-- on the left it starts the same distance inside the window's edge.
local SECTION_FADE      = 17    -- tuned in game
local SECTION_LINE_PAST_TOGGLE = 2
local SECTION_FONT_SIZE = 13    -- section titles (tracker quest names are 12 by default)
-- The art fades in and out at its ends; stretched as one piece the fades
-- stretch too. Drawn as three slices instead: both ends at native size, only
-- the even middle stretched.
local SECTION_BAR_CAP  = 0.15   -- share of the art's width kept unstretched at each end

-- Fonts as the tracker sizes them: section headers like quest names, category
-- labels like objective lines. Both copy ObjectiveTrackerLineFont: labels at
-- its size (the tracker's Edit Mode text size), section titles at a fixed 13;
-- titles in the tracker's quest-name "Header" gold, labels in its objective
-- "Normal" off-white (OBJECTIVE_TRACKER_COLOR).
local trackerFonts = {}
local function TrackerFont(kind, size)
    if trackerFonts[kind] then return trackerFonts[kind] end
    local base = _G.ObjectiveTrackerLineFont or GameFontNormal
    local colors = _G.OBJECTIVE_TRACKER_COLOR
    local color = colors and colors[kind]
        or (kind == "Header" and NORMAL_FONT_COLOR or { r = 0.8, g = 0.8, b = 0.8 })
    local font = CreateFont("XpieHUDBaganator" .. kind .. "Font")
    font:CopyFontObject(base)
    if size then
        local path, _, flags = font:GetFont()
        if path then font:SetFont(path, size, flags or "") end
    end
    font:SetTextColor(color.r, color.g, color.b)
    trackerFonts[kind] = font
    return font
end

local function StyleCategoryLabel(label)
    if label.xpieLabel or not label.SetNormalFontObject then return end
    label.xpieLabel = true
    label:SetNormalFontObject(TrackerFont("Normal"))
end

local function FindView(region)
    local parent = region:GetParent()
    while parent do
        if parent.xpieKind then return parent end
        parent = parent:GetParent()
    end
end

-- Section bars are drawn in a frame that clips to the window background, so
-- a bar can reach past the window's edges and is cut cleanly at them.
local function SectionClip(view)
    if not view.xpieSectionClip then
        local clip = CreateFrame("Frame", nil, view)
        clip:SetClipsChildren(true)
        clip:SetAllPoints(view.Bg or view)
        clip:EnableMouse(false)
        view.xpieSectionClip = clip
    end
    return view.xpieSectionClip
end

-- The frame the bar is drawn on: a holder over the header inside the window's
-- clip frame (following the header's visibility), or the header itself.
local function SectionBarHolder(button)
    local view = FindView(button)
    if not view then return button end
    local clip = SectionClip(view)
    -- One level below the header, so its title draws over the bar. The clip is
    -- shared by every header, so it takes the lowest level any of them needs
    -- (setting it from the last header put it over the earlier headers' titles).
    if button:GetFrameLevel() < 1 then button:SetFrameLevel(1) end
    clip:SetFrameStrata(button:GetFrameStrata())
    local level = button:GetFrameLevel() - 1
    if level < clip:GetFrameLevel() or not clip.xpieLevelSet then
        clip:SetFrameLevel(level)
        clip.xpieLevelSet = true
    end
    level = clip:GetFrameLevel()
    local holder = CreateFrame("Frame", nil, clip)
    holder:SetAllPoints(button)
    holder:SetFrameLevel(level)
    holder:EnableMouse(false)
    holder:SetShown(button:IsShown())
    button:HookScript("OnShow", function() holder:Show() end)
    button:HookScript("OnHide", function() holder:Hide() end)
    return holder
end

-- Left: the gold line starts as far inside the window's left edge as it ends
-- inside the right one. That gap depends on the window's layout, so it's
-- measured whenever Baganator lays the header out.
local function PlaceSectionBarLeft(button)
    local bar = button.xpieBar
    if not bar then return end
    local leftX = -SECTION_FADE
    local view = FindView(button)
    local bg = view and view.Bg
    local bl, br = button:GetLeft(), button:GetRight()
    local gl, gr = bg and bg:GetLeft(), bg and bg:GetRight()
    if bl and br and gl and gr then
        local gap = gr - br - SECTION_LINE_PAST_TOGGLE   -- right-hand gap
        leftX = (gl - bl) + gap - SECTION_FADE
    end
    bar.left:SetPoint("LEFT", button, "LEFT", leftX, 0)
end

local function DrawSectionBar(button, info)
    local height = info.height or 26
    local file = info.file or info.filename
    local l, r, t, b = info.leftTexCoord, info.rightTexCoord, info.topTexCoord, info.bottomTexCoord
    local owner = SectionBarHolder(button)
    local bar = {}
    if not (file and l and r and t and b and info.width) then
        -- Atlas details unavailable: one stretched piece.
        local whole = owner:CreateTexture(nil, "BACKGROUND")
        whole:SetAtlas(SECTION_BAR, false)
        whole:SetHeight(height)
        bar.left, bar.right = whole, whole
    else
        local capWidth = math.floor(info.width * SECTION_BAR_CAP + 0.5)
        local capCoord = (r - l) * SECTION_BAR_CAP
        local function Slice(left, right)
            local slice = owner:CreateTexture(nil, "BACKGROUND")
            slice:SetTexture(file)
            slice:SetTexCoord(left, right, t, b)
            slice:SetHeight(height)
            return slice
        end
        bar.left = Slice(l, l + capCoord)
        bar.left:SetWidth(capWidth)
        bar.right = Slice(r - capCoord, r)
        bar.right:SetWidth(capWidth)
        local middle = Slice(l + capCoord, r - capCoord)
        middle:SetPoint("TOPLEFT", bar.left, "TOPRIGHT")
        middle:SetPoint("BOTTOMRIGHT", bar.right, "BOTTOMLEFT")
    end
    -- Right: the gold line ends just past the -/+ button, its faded end
    -- beyond it (clipped at the window).
    bar.right:SetPoint("RIGHT", owner, "RIGHT", SECTION_LINE_PAST_TOGGLE + SECTION_FADE, 0)
    button.xpieBar = bar
    PlaceSectionBarLeft(button)
end

local function AnchorSectionRight(button)
    if button.xpieAnchoring then return end
    local container = button:GetParent()
    if not container then return end
    button.xpieAnchoring = true
    button:SetPoint("RIGHT", container, "RIGHT", 0, 0)
    button.xpieAnchoring = false
    PlaceSectionBarLeft(button)
    -- Again once this layout pass has settled (the window may resize after).
    C_Timer.After(0, function() PlaceSectionBarLeft(button) end)
end

local function StyleSectionHeader(button)
    if button.xpieSection then return end
    button.xpieSection = true

    local info = C_Texture.GetAtlasInfo(SECTION_BAR)
    if info then DrawSectionBar(button, info) end

    button:SetNormalFontObject(TrackerFont("Header", SECTION_FONT_SIZE))
    local text = button:GetFontString()
    if text then
        text:ClearAllPoints()
        text:SetPoint("LEFT", SECTION_TEXT_X, 0)
        text:SetPoint("RIGHT", -(SECTION_TOGGLE + 4), 0)
    end

    if button.arrow then button.arrow:Hide() end
    local toggle = button:CreateTexture(nil, "ARTWORK")
    toggle:SetSize(SECTION_TOGGLE, SECTION_TOGGLE)
    toggle:SetPoint("RIGHT", 0, 0)
    toggle:SetAtlas(SECTION_COLLAPSE)
    local hover = button:CreateTexture(nil, "HIGHLIGHT")
    hover:SetAtlas(SECTION_HOVER)
    hover:SetBlendMode("ADD")
    hover:SetAllPoints(toggle)
    if button.SetExpanded then
        hooksecurefunc(button, "SetExpanded", function() toggle:SetAtlas(SECTION_COLLAPSE) end)
    end
    if button.SetCollapsed then
        hooksecurefunc(button, "SetCollapsed", function() toggle:SetAtlas(SECTION_EXPAND) end)
    end

    -- Stretch the button to the right edge of the item area.
    hooksecurefunc(button, "SetPoint", AnchorSectionRight)
    button:HookScript("OnSizeChanged", PlaceSectionBarLeft)
    button:HookScript("OnShow", PlaceSectionBarLeft)
    AnchorSectionRight(button)
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
    elseif regionType == "CategorySectionHeader" then
        StyleSectionHeader(region)
    elseif regionType == "CategoryLabel" then
        StyleCategoryLabel(region)
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
-- Default profile: Profile.lua's export string, imported with Baganator's own
-- public import (Baganator.API.ImportString). Importing creates (or replaces)
-- the Baganator profile "XpieHUD" and switches this character to it.
-- Baganator profiles are chosen per character, so it's applied once per
-- character; after that the player is free to pick another profile.
-- ---------------------------------------------------------------------------
local function CharacterKey()
    return (UnitName("player") or "?") .. "-" .. (GetNormalizedRealmName() or "?")
end

function module:ApplyProfile(quiet)
    local text = ns.BAGANATOR_PROFILE
    if not text or text == "" then
        if not quiet then core:Print("No Baganator profile is included in this version yet.") end
        return false
    end
    if not (Baganator and Baganator.API and Baganator.API.ImportString) then return false end
    local ok, err = pcall(Baganator.API.ImportString, text, PROFILE_NAME)
    if not ok then
        core:Print("Couldn't set up the Baganator profile: " .. tostring(err))
        return false
    end
    self.db.profileApplied[CharacterKey()] = true
    return true
end

function module:OnLogin()
    if not (self.db.useProfile and ns.BAGANATOR_PROFILE) then return end
    if self.db.profileApplied[CharacterKey()] then return end
    -- After Baganator has finished its own login setup.
    C_Timer.After(0, function() self:ApplyProfile(true) end)
end

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
    page:Space(6)
    page:Header("Baganator Profile")
    page:Checkbox({ key = "useProfile", label = "Set Up New Characters",
        description = "The first time each character logs in, set Baganator up with the XpieHUD profile (category layout, icon size and spacing). You can switch to another profile in Baganator afterwards." })
    page:Button("Apply XpieHUD Profile", function() module:ApplyProfile(false) end)
end
