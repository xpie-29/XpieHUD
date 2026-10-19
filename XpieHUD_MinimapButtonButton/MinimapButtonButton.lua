-- MinimapButtonButton.lua  (XpieHUD_MinimapButtonButton module)
-- MinimapButtonButton (MBB) as part of Blizzard's micro menu. Style "xpiehud"
-- (default):
--   * MBB's main button is a native micro menu button (32x40, the micro
--     menu's button background, pushed background while pressed or while the
--     drawer is open, a hover glow, MBB's logo in micro menu gold) sitting
--     directly left of the micro menu at the micro menu's own scale
--     (Attach to Micro Menu; it can't be dragged while attached)
--   * the drawer loses its tooltip box; each addon button in it gets the
--     micro button background, its round minimap border/background/highlight
--     faded out, and is spaced like the micro menu (neighbours overlap 5px)
-- Style "original" leaves MBB's look and position alone.
-- Separately (works without MBB): the queue status eye (QueueStatusButton) is
-- taken off the micro menu onto its own draggable anchor, with its own size.
--
-- MinimapButtonButton internals used (checked against v1.24.13, 12.1.5); its
-- module table is private, so only its frames are touched:
--   _G.MinimapButtonButtonButton: the main button (Logic/Main.lua). MBB calls
--     its SetSize (layout), SetScale (scale option) and SetPoint (saved or
--     reset position); all three are hooked. Its only ARTWORK texture is the
--     logo; its only child frame is the drawer (button container).
--   the drawer: MBB anchors it with SetPoint each layout (hooked) and lays the
--     collected buttons out by their GetWidth()/GetHeight(), centred on
--     offsets from the drawer's edge (inner edge offset 4 with MBB's default
--     skin, 2 with ElvUI/Tukui; measured, not assumed).
--   collected buttons: MBB hooks their Show/Hide and re-lays out when their
--     visibility changes; that's how a relayout is asked for after resizing.
-- MinimapButtonButton is all rights reserved: nothing here is copied from it,
-- only hooked at runtime. MBB isn't secure code, so hooking it can't taint.
--
-- Blizzard frames (checked against wow-ui-source live, 12.1.5):
--   MicroMenu (Blizzard_MicroMenu, MicroMenuContainer.xml): GridLayoutFrame,
--     childXPadding/childYPadding -5; Layout() and UpdateScale() are hooked
--     to keep the main button attached. Only read from, never changed.
--   QueueStatusButton (Blizzard_QueueStatusFrame, QueueStatusFrame.xml):
--     a plain Button parented to MicroMenuContainer; MicroMenu:Layout() puts
--     it back with QueueStatusButton:UpdatePosition() (hooked), and Edit
--     Mode's Eye Size calls MicroMenu:SetQueueStatusScale() (hooked). It's
--     re-anchored and scaled only: never hidden, shown or re-parented.

local core = XpieHUD

-- Blizzard's micro button (MainMenuBarMicroButton, MainMenuBarMicroButtons.xml):
-- 32x40, "ButtonBG-Up" background, "ButtonBG-Down" while pushed. MicroMenu
-- packs them with -5 padding, so neighbouring buttons overlap by 5px.
local MICRO_W, MICRO_H  = 32, 40
local MICRO_OVERLAP     = 5
local ATLAS_BG          = "UI-HUD-MicroMenu-ButtonBG-Up"
local ATLAS_BG_PUSHED   = "UI-HUD-MicroMenu-ButtonBG-Down"
-- Hover: the micro buttons swap to their own "-Mouseover" icon art, which
-- MBB's logo and addon icons don't have, so the background is added over
-- itself instead (a soft brightening of the same art).
local HOVER_ALPHA       = 0.35
-- MBB's logo on the main button (MBB draws it 16px, black or class coloured).
local LOGO_SIZE         = 18
local LOGO_COLOR        = { 0.96, 0.82, 0.48 }   -- micro menu icon gold
local LOGO_HOVER_COLOR  = { 1, 0.93, 0.70 }
-- Pushed (pressed or drawer open): the logo moves like a pressed icon.
local PUSHED_OFFSET_X, PUSHED_OFFSET_Y = 1, -1
-- Addon icons in the drawer (LibDBIcon draws them 18px).
local DRAWER_ICON_SIZE  = 20
local TOOLTIP_TITLE     = "Minimap Buttons"
-- MBB's default skin's inner edge offset; replaced by the measured one.
local DEFAULT_INNER     = 4
-- Round minimap-button chrome faded out on drawer buttons (LibDBIcon and most
-- hand-made minimap buttons use these Blizzard textures).
local CHROME_TEXTURES = {
    [136430] = true, ["interface\\minimap\\minimap-trackingborder"] = true,
    [136467] = true, ["interface\\minimap\\ui-minimap-background"] = true,
    [136477] = true, ["interface\\minimap\\ui-minimap-zoombutton-highlight"] = true,
}

-- Queue status eye: QueueStatusButton is 45x45 (QueueStatusFrame.xml). Its
-- default spot once separated, relative to the minimap (drag to move).
local QUEUE_SIZE          = 45
local QUEUE_DEFAULT_POINT = { "CENTER", "BOTTOMLEFT", 0, 30 }
-- Drag handle shown while the eye is unlocked (Edit Mode's selection blue).
local QUEUE_HANDLE_COLOR  = { 0.25, 0.55, 1, 0.35 }

local module = core:RegisterModule("minimapbuttonbutton", {
    title = "MinimapButtonButton",
    defaults = {
        -- "xpiehud": native micro menu buttons. "original": leave MBB alone.
        style = "xpiehud",
        attach = true,       -- main button directly left of the micro menu
        attachGap = 0,       -- extra px between it and the micro menu (0 = native overlap)
        spacing = 0,         -- extra px between drawer buttons (0 = native overlap)
        opacity = 100,       -- main button and drawer, %
        queueSeparate = true,
        queueScale = 100,    -- %, replaces Edit Mode's Eye Size while separated
        queueUnlocked = false,
        -- queuePoint = { point, relativePoint, x, y } on UIParent, once dragged
    },
})

local function Styled()
    return module.db and module.db.style == "xpiehud" and _G.MinimapButtonButtonButton ~= nil
end

local function Attached()
    return Styled() and module.db.attach and _G.MicroMenu ~= nil
end

local function Pack(...)
    return { n = select("#", ...), ... }
end

-- ---------------------------------------------------------------------------
-- Micro button art: background, pushed background, hover glow, drawn centred
-- on the frame at the atlas size (as MainMenuBarMicroButton does).
-- ---------------------------------------------------------------------------
local function CreateMicroArt(frame)
    local art = {}
    art.bg = frame:CreateTexture(nil, "BACKGROUND", nil, -7)
    art.bg:SetAtlas(ATLAS_BG, true)
    art.bg:SetPoint("CENTER")
    art.pushed = frame:CreateTexture(nil, "BACKGROUND", nil, -7)
    art.pushed:SetAtlas(ATLAS_BG_PUSHED, true)
    art.pushed:SetPoint("CENTER")
    art.glow = frame:CreateTexture(nil, "BACKGROUND", nil, -6)
    art.glow:SetPoint("CENTER")
    art.glow:SetBlendMode("ADD")
    art.glow:SetAlpha(HOVER_ALPHA)
    art.own = { [art.bg] = true, [art.pushed] = true, [art.glow] = true }
    for texture in pairs(art.own) do texture:Hide() end
    return art
end

local function ShowArt(art, on, hover, pushed)
    art.bg:SetShown(on and not pushed)
    art.pushed:SetShown(on and pushed)
    if on and hover then
        art.glow:SetAtlas(pushed and ATLAS_BG_PUSHED or ATLAS_BG, true)
    end
    art.glow:SetShown(on and hover)
end

-- MBB's skins give the main button and drawer a backdrop; the micro menu has none.
local savedBackdrops = {}

local function StripBackdrop(frame)
    if not (frame and frame.SetBackdrop and frame.backdropInfo) then return end
    savedBackdrops[frame] = {
        info = frame.backdropInfo,
        color = { frame:GetBackdropColor() },
        border = { frame:GetBackdropBorderColor() },
    }
    frame:SetBackdrop(nil)
end

local function RestoreBackdrop(frame)
    local saved = frame and savedBackdrops[frame]
    if not saved then return end
    frame:SetBackdrop(saved.info)
    if saved.color[1] then frame:SetBackdropColor(unpack(saved.color)) end
    if saved.border[1] then frame:SetBackdropBorderColor(unpack(saved.border)) end
    savedBackdrops[frame] = nil
end

-- ---------------------------------------------------------------------------
-- MinimapButtonButton
-- ---------------------------------------------------------------------------
local mbb = {
    inner = DEFAULT_INNER,
    buttons = {},           -- [collected button] = its saved look and state
    hover = false, down = false,
}
local guard = false         -- our own SetPoint/SetSize/SetScale calls

local function MicroScale()
    return MicroMenu:GetEffectiveScale() / UIParent:GetEffectiveScale()
end

-- Main button: at the micro menu's left end (or top, for a vertical micro
-- menu), overlapping it like a neighbouring micro button. When it stops
-- being attached it goes back to MBB's own position and scale (only then, so
-- a spot the player dragged it to with MBB is never overwritten).
local function PlaceMain()
    local main = mbb.main
    guard = true
    if Attached() then
        main:SetScale(MicroScale())
        main:ClearAllPoints()
        local gap = module.db.attachGap
        if MicroMenu.isHorizontal == false then
            main:SetPoint("BOTTOMLEFT", MicroMenu, "TOPLEFT", 0, gap - MICRO_OVERLAP)
        else
            main:SetPoint("TOPRIGHT", MicroMenu, "TOPLEFT", MICRO_OVERLAP - gap, 0)
        end
        mbb.attached = true
    elseif mbb.attached then
        if mbb.mbbScale then main:SetScale(mbb.mbbScale) end
        local point = mbb.mbbPoint
        if point and point.n > 0 then
            main:ClearAllPoints()
            main:SetPoint(unpack(point, 1, point.n))
        end
        mbb.attached = false
    end
    if Styled() then
        main:SetSize(MICRO_W, MICRO_H)
        main:SetAlpha(module.db.opacity / 100)
        mbb.sized = true
    elseif mbb.sized then
        if mbb.mbbSize then main:SetSize(mbb.mbbSize[1], mbb.mbbSize[2]) end
        main:SetAlpha(1)
        mbb.sized = false
    end
    guard = false
end

local function UpdateMain()
    if not mbb.art then return end
    local on = Styled()
    local pushed = mbb.down or (mbb.container ~= nil and mbb.container:IsShown())
    ShowArt(mbb.art, on, mbb.hover, pushed)
    local logo = mbb.logo
    if on and logo then
        local color = mbb.hover and LOGO_HOVER_COLOR or LOGO_COLOR
        logo:SetVertexColor(color[1], color[2], color[3], 1)
        logo:SetSize(LOGO_SIZE, LOGO_SIZE)
        logo:ClearAllPoints()
        logo:SetPoint("CENTER", mbb.main, "CENTER", pushed and PUSHED_OFFSET_X or 0, pushed and PUSHED_OFFSET_Y or 0)
    end
end

local function RestoreLogo()
    local logo = mbb.logo
    if not (logo and mbb.logoColor) then return end
    logo:SetVertexColor(unpack(mbb.logoColor))
    logo:SetSize(mbb.logoSize[1], mbb.logoSize[2])
    logo:ClearAllPoints()
    logo:SetPoint("CENTER", mbb.main, "CENTER", 0, 0)
end

-- Drawer. MBB anchors it to the main button and centres each collected button
-- `inner` px in from its edge; it's moved so the buttons land where a micro
-- menu would put them: first button overlapping the main button, rows lined up.
local function DrawerOffsets(point, relPoint)
    local half = (MICRO_OVERLAP - module.db.spacing) / 2   -- art beyond each button's frame
    local inner = mbb.inner
    local sideways = (point:find("RIGHT") and relPoint:find("LEFT")) or (point:find("LEFT") and relPoint:find("RIGHT"))
    if sideways then
        local dx = point:find("RIGHT") and (half + inner) or -(half + inner)
        local dy = point:find("TOP") and (inner - half) or -(inner - half)
        return dx, dy
    end
    local dy = point:find("BOTTOM") and -(half + inner) or (half + inner)
    local dx = point:find("RIGHT") and (inner - half) or -(inner - half)
    return dx, dy
end

local function PlaceDrawer()
    local drawer, point = mbb.container, mbb.drawerPoint
    if not (drawer and point and point[1] and point[3]) then return end
    guard = true
    drawer:ClearAllPoints()
    if Styled() then
        local dx, dy = DrawerOffsets(point[1], point[3])
        drawer:SetPoint(point[1], point[2], point[3], dx, dy)
    else
        drawer:SetPoint(point[1], point[2], point[3], point[4] or 0, point[5] or 0)
    end
    guard = false
end

-- MBB's inner edge offset, from where it centred the buttons last layout.
local function MeasureInner()
    local drawer = mbb.container
    local best
    for _, button in ipairs({ drawer:GetChildren() }) do
        if button:IsShown() and button:GetNumPoints() > 0 then
            local _, relativeTo, _, x, y = button:GetPoint(1)
            if relativeTo == drawer and x and y then
                local scale = button:GetScale()
                local inner = math.min(math.abs(x * scale) - button:GetWidth() * scale / 2,
                                       math.abs(y * scale) - button:GetHeight() * scale / 2)
                if not best or inner < best then best = inner end
            end
        end
    end
    if best and best >= 0 then
        best = math.floor(best * 2 + 0.5) / 2
        if best ~= mbb.inner then
            mbb.inner = best
            PlaceDrawer()
        end
    end
end

-- Drawer buttons. Blizzard's own (secure) minimap buttons keep their look.
local function IsChrome(region, button)
    if region == button.border or region == button.background then return true end
    local texture = region:GetTexture()
    if type(texture) == "string" then texture = (texture:lower():gsub("/", "\\")) end
    return texture ~= nil and CHROME_TEXTURES[texture] == true
end

local function UpdateDrawerButton(button)
    local saved = mbb.buttons[button]
    if saved and saved.on then ShowArt(saved.art, true, saved.hover, saved.down) end
end

local function SetDrawerButtonState(button, hover, down)
    local saved = mbb.buttons[button]
    if not saved then return end
    if hover ~= nil then saved.hover = hover end
    if down ~= nil then saved.down = down end
    UpdateDrawerButton(button)
end

local function DrawerButtonSize()
    local spacing = module.db.spacing
    return MICRO_W - MICRO_OVERLAP + spacing, MICRO_H - MICRO_OVERLAP + spacing
end

-- Returns true when the button's size changed (MBB must lay out again).
local function StyleButton(button)
    local name = button:GetName()
    if name and issecurevariable(_G, name) then return false end
    local saved = mbb.buttons[button]
    if not saved then
        saved = { faded = {} }
        saved.width, saved.height = button:GetSize()
        if button.icon and button.icon.GetSize then saved.iconW, saved.iconH = button.icon:GetSize() end
        saved.art = CreateMicroArt(button)
        button:HookScript("OnEnter", function(self) SetDrawerButtonState(self, true, nil) end)
        button:HookScript("OnLeave", function(self) SetDrawerButtonState(self, false, false) end)
        button:HookScript("OnMouseDown", function(self) SetDrawerButtonState(self, nil, true) end)
        button:HookScript("OnMouseUp", function(self) SetDrawerButtonState(self, nil, false) end)
        mbb.buttons[button] = saved
    end
    if not saved.on then
        for _, region in ipairs({ button:GetRegions() }) do
            if region:IsObjectType("Texture") and region ~= button.icon and not saved.art.own[region]
                and IsChrome(region, button) then
                saved.faded[region] = region:GetAlpha()
                region:SetAlpha(0)
            end
        end
        local highlight = button.GetHighlightTexture and button:GetHighlightTexture()
        if highlight and not saved.faded[highlight] then
            saved.faded[highlight] = highlight:GetAlpha()
            highlight:SetAlpha(0)
        end
        if saved.iconW then button.icon:SetSize(DRAWER_ICON_SIZE, DRAWER_ICON_SIZE) end
        saved.on = true
    end
    UpdateDrawerButton(button)
    local width, height = DrawerButtonSize()
    if math.abs(button:GetWidth() - width) < 0.01 and math.abs(button:GetHeight() - height) < 0.01 then
        return false
    end
    button:SetSize(width, height)
    return true
end

local function RestoreButton(button, saved)
    for region, alpha in pairs(saved.faded) do region:SetAlpha(alpha) end
    wipe(saved.faded)
    button:SetSize(saved.width, saved.height)
    if saved.iconW then button.icon:SetSize(saved.iconW, saved.iconH) end
    ShowArt(saved.art, false)
    saved.on = false
end

-- MBB lays out again when a collected button is shown or hidden (it hooks
-- their Show/Hide): hide and show one of the addon buttons in the same frame.
local relayoutQueued = false
local function Relayout()
    relayoutQueued = false
    for button, saved in pairs(mbb.buttons) do
        if button:IsShown() and button:GetParent() == mbb.container then
            button:Hide()
            button:Show()
            break
        end
    end
    MeasureInner()
end

local function QueueRelayout()
    if relayoutQueued then return end
    relayoutQueued = true
    C_Timer.After(0, Relayout)
end

local function UpdateDrawer()
    local drawer = mbb.container
    if not drawer then return end
    local on, changed = Styled(), false
    for _, button in ipairs({ drawer:GetChildren() }) do
        if on then
            if StyleButton(button) then changed = true end
        else
            local saved = mbb.buttons[button]
            if saved and saved.on then
                RestoreButton(button, saved)
                changed = true
            end
        end
    end
    if changed then QueueRelayout() end
end

-- Main button scripts. MBB replaces OnEnter/OnLeave when it adds or removes
-- its "drag me" tooltip and sets OnMouseUp while dragging, so these hooks are
-- put back whenever it calls SetScript.
local MAIN_HOOKS = {
    OnEnter = function(self)
        mbb.hover = true
        UpdateMain()
        if Styled() then
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            if GameTooltip_SetTitle then
                GameTooltip_SetTitle(GameTooltip, TOOLTIP_TITLE)
            else
                GameTooltip:SetText(TOOLTIP_TITLE)
            end
            GameTooltip:Show()
        end
    end,
    OnLeave = function(self)
        mbb.hover, mbb.down = false, false
        UpdateMain()
        if Styled() and GameTooltip:GetOwner() == self then GameTooltip:Hide() end
    end,
    OnMouseUp = function()
        mbb.down = false
        UpdateMain()
    end,
}

local function InstallMBB()
    if mbb.main then return true end
    local main = _G.MinimapButtonButtonButton
    if not main then return false end
    mbb.main = main
    for _, child in ipairs({ main:GetChildren() }) do
        if child.SetBackdrop then mbb.container = child break end
    end
    for _, region in ipairs({ main:GetRegions() }) do
        if region:IsObjectType("Texture") and region:GetDrawLayer() == "ARTWORK" then mbb.logo = region break end
    end
    -- MBB's own geometry, for the Original style and for detaching.
    if main:GetNumPoints() > 0 then mbb.mbbPoint = Pack(main:GetPoint(1)) end
    mbb.mbbSize = { main:GetSize() }
    mbb.mbbScale = main:GetScale()
    mbb.art = CreateMicroArt(main)

    hooksecurefunc(main, "SetPoint", function(_, ...)
        if guard then return end
        mbb.mbbPoint = Pack(...)
        if Attached() then PlaceMain() end
    end)
    hooksecurefunc(main, "SetSize", function(_, width, height)
        if guard then return end
        mbb.mbbSize = { width, height }
        if Styled() then PlaceMain() end
    end)
    hooksecurefunc(main, "SetScale", function(_, scale)
        if guard then return end
        mbb.mbbScale = scale
        if Attached() then PlaceMain() end
    end)

    -- Left click still toggles the drawer (MBB); while attached, the middle
    -- button / Alt drag is ignored so the button stays with the micro menu.
    local onMouseDown = main:GetScript("OnMouseDown")
    if onMouseDown then
        main:SetScript("OnMouseDown", function(self, button, ...)
            if Attached() and (button == "MiddleButton" or IsAltKeyDown()) then return end
            if Styled() then
                mbb.down = true
                UpdateMain()
            end
            return onMouseDown(self, button, ...)
        end)
    end
    for script, handler in pairs(MAIN_HOOKS) do main:HookScript(script, handler) end
    hooksecurefunc(main, "SetScript", function(self, script)
        local handler = MAIN_HOOKS[script]
        if handler then self:HookScript(script, handler) end
    end)

    local drawer = mbb.container
    if drawer then
        if drawer:GetNumPoints() > 0 then mbb.drawerPoint = { drawer:GetPoint(1) } end
        hooksecurefunc(drawer, "SetPoint", function(_, point, relativeTo, relativePoint, x, y)
            if guard then return end
            mbb.drawerPoint = { point, relativeTo, relativePoint, x, y }
            if Styled() then PlaceDrawer() end
        end)
        -- Every MBB layout sizes the drawer: style newly collected buttons.
        hooksecurefunc(drawer, "SetSize", function()
            if Styled() then UpdateDrawer() end
        end)
        drawer:HookScript("OnShow", UpdateMain)
        drawer:HookScript("OnHide", UpdateMain)
    end

    if _G.MicroMenu then
        local function Follow() if Attached() then PlaceMain() end end
        hooksecurefunc(MicroMenu, "Layout", Follow)
        if MicroMenu.UpdateScale then hooksecurefunc(MicroMenu, "UpdateScale", Follow) end
    end
    return true
end

local function ApplyMBB()
    if not InstallMBB() then return end
    local on = Styled()
    if on and not mbb.on then
        if mbb.logo then
            mbb.logoColor = { mbb.logo:GetVertexColor() }
            mbb.logoSize = { mbb.logo:GetSize() }
        end
        StripBackdrop(mbb.main)
        StripBackdrop(mbb.container)
    elseif not on and mbb.on then
        RestoreBackdrop(mbb.main)
        RestoreBackdrop(mbb.container)
        RestoreLogo()
    end
    mbb.on = on
    PlaceMain()
    PlaceDrawer()
    UpdateMain()
    UpdateDrawer()
end

-- ---------------------------------------------------------------------------
-- Queue status eye
-- ---------------------------------------------------------------------------
local queue = { moved = false }

local function QueueSeparate()
    return module.db and module.db.queueSeparate and _G.QueueStatusButton ~= nil
end

local function CreateQueueAnchor()
    local anchor = CreateFrame("Frame", "XpieHUDQueueStatusAnchor", UIParent)
    anchor:SetSize(QUEUE_SIZE, QUEUE_SIZE)
    anchor:SetMovable(true)
    anchor:SetClampedToScreen(true)
    anchor:SetFrameStrata("HIGH")
    anchor:RegisterForDrag("LeftButton")
    anchor:SetScript("OnDragStart", anchor.StartMoving)
    anchor:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        local point, _, relativePoint, x, y = self:GetPoint(1)
        module.db.queuePoint = { point, relativePoint, x, y }
    end)
    anchor.handle = anchor:CreateTexture(nil, "OVERLAY")
    anchor.handle:SetAllPoints()
    anchor.handle:SetColorTexture(unpack(QUEUE_HANDLE_COLOR))
    anchor.label = anchor:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    anchor.label:SetPoint("CENTER")
    anchor.label:SetText("Queue\nStatus")
    return anchor
end

local function PlaceQueue()
    local button = _G.QueueStatusButton
    if not button then return end
    if InCombatLockdown() and button:IsProtected() then
        core.applyPending = true
        return
    end
    if QueueSeparate() then
        if not queue.moved then queue.blizzScale = button:GetScale() end
        local db = module.db
        local scale = db.queueScale / 100
        local anchor = queue.anchor or CreateQueueAnchor()
        queue.anchor = anchor
        anchor:SetSize(QUEUE_SIZE * scale, QUEUE_SIZE * scale)
        anchor:ClearAllPoints()
        local point = db.queuePoint
        if point then
            anchor:SetPoint(point[1], UIParent, point[2], point[3], point[4])
        else
            local default = QUEUE_DEFAULT_POINT
            anchor:SetPoint(default[1], _G.Minimap or UIParent, default[2], default[3], default[4])
        end
        anchor:Show()
        anchor:EnableMouse(db.queueUnlocked)
        anchor.handle:SetShown(db.queueUnlocked)
        anchor.label:SetShown(db.queueUnlocked)
        button:SetScale(scale)
        button:ClearAllPoints()
        button:SetPoint("CENTER", anchor, "CENTER", 0, 0)
        queue.moved = true
    elseif queue.moved then
        if queue.anchor then queue.anchor:Hide() end
        button:SetScale(queue.blizzScale or 1)
        if _G.MicroMenuContainer and _G.MicroMenu then
            button:UpdatePosition(MicroMenuContainer:GetPosition(), MicroMenu.isHorizontal)
        end
        queue.moved = false
    end
end

local function InstallQueue()
    if queue.installed or not _G.QueueStatusButton then return end
    queue.installed = true
    -- The micro menu puts the eye back beside itself on every layout.
    if QueueStatusButton.UpdatePosition then
        hooksecurefunc(QueueStatusButton, "UpdatePosition", function()
            if QueueSeparate() then PlaceQueue() end
        end)
    end
    -- Edit Mode's Eye Size: remembered for when the eye goes back.
    if _G.MicroMenu and MicroMenu.SetQueueStatusScale then
        hooksecurefunc(MicroMenu, "SetQueueStatusScale", function(_, scale)
            queue.blizzScale = scale
            if QueueSeparate() then PlaceQueue() end
        end)
    end
end

function module:ResetQueuePosition()
    self.db.queuePoint = nil
    core:SettingsChanged()
end

-- ---------------------------------------------------------------------------
-- Module
-- ---------------------------------------------------------------------------
function module:Apply()
    if InCombatLockdown() then
        core.applyPending = true
        return
    end
    InstallQueue()
    PlaceQueue()
    ApplyMBB()
end

-- MBB sets up and collects buttons on the frame after login, and again a
-- second later; the hooks catch its layouts, these catch anything before them.
function module:OnLogin()
    for _, delay in ipairs({ 0, 1.5 }) do
        C_Timer.After(delay, function()
            if core.ready then module:Apply() end
        end)
    end
end

core:RegisterCommand("queuereset", function() module:ResetQueuePosition() end, "Put the queue status eye back at its default spot")

function module:BuildSettings(page)
    page:Status(function()
        return C_AddOns.IsAddOnLoaded("MinimapButtonButton") and "" or "(MinimapButtonButton not loaded)"
    end)
    page:Note("Choose MinimapButtonButton's original look, or the XpieHUD style: its button becomes a native micro menu button at the left end of the micro menu, and the addon buttons in its drawer look like micro menu buttons too. Left-click opens the drawer as before. Disable the XpieHUD_MinimapButtonButton addon to remove this page completely.")
    page:Dropdown({
        key = "style", label = "Style",
        values = function()
            return {
                { key = "xpiehud",  label = "XpieHUD" },
                { key = "original", label = "Original (leave MinimapButtonButton alone)" },
            }
        end,
    })
    page:Space(6)
    page:Checkbox({ key = "attach", label = "Attach to Micro Menu", description = "Keep the button at the left end of the micro menu, at the micro menu's size. Untick to place it yourself with MinimapButtonButton's own drag (middle button or Alt)." })
    page:Slider({ key = "attachGap", label = "Gap to Micro Menu", description = "Extra space between the button and the micro menu. 0 overlaps them like neighbouring micro buttons.", min = -5, max = 20, step = 1, format = "%d" })
    page:Slider({ key = "spacing", label = "Drawer Spacing", description = "Extra space between the buttons in the drawer. 0 spaces them like the micro menu.", min = -5, max = 10, step = 1, format = "%d" })
    page:Slider({ key = "opacity", label = "Opacity", description = "Opacity of the button and its drawer.", min = 20, max = 100, step = 5, format = "%d%%" })

    page:Space(6)
    page:Header("Queue Status")
    page:Note("Moves the Looking for Group eye off the micro menu so it can sit anywhere. The eye only appears while you're queued; unlock it to see and drag its spot. /xhud queuereset puts it back at its default spot.")
    page:Checkbox({ key = "queueSeparate", label = "Separate From Micro Menu", description = "Give the queue status eye its own position and size. Untick to put it back beside the micro menu (Edit Mode's Eye Size applies again)." })
    page:Slider({ key = "queueScale", label = "Eye Size", description = "Size of the separated eye (replaces Edit Mode's Eye Size while separated).", min = 50, max = 150, step = 5, format = "%d%%" })
    page:Checkbox({ key = "queueUnlocked", label = "Unlock Eye", description = "Show a handle where the eye sits; drag it to move the eye. Untick to lock it." })
    page:Button("Reset Eye Position", function() module:ResetQueuePosition() end)
end
