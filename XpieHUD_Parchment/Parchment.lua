-- Parchment.lua  (XpieHUD_Parchment module)
-- The quest, gossip and greeting windows as a floating native parchment
-- (Blizzard's QuestBG art with its torn edges freed from the dark backing,
-- an edge-following shadow, the NPC's 3D portrait with the text wrapping
-- beside it, native icons, reward grid, minimal scroll bar and tan buttons).
-- Design and phases: docs/quest-parchment-plan.md.
--
-- Style "parchment" (default) restyles the windows; "blizzard" leaves Core's
-- quest window exactly as it is without the module. Blizzard's QuestFrame and
-- GossipFrame stay the real, shown frames (AI Quest Voices and the accept /
-- complete flows rely on that); the module only re-dresses them, and hands
-- number keys, Space and badges back to Core through XpieHUD:SetQuestLook().
--
-- Phase 1 (this file): module shell, settings, incompatibility check, Core
-- hand-off. Nothing is restyled yet: IsActive() stays false until the
-- renderer (phase 2) exists, so Core behaves exactly as without the module.

local core = XpieHUD

-- Addons that replace or restyle the quest windows. If one is loaded the
-- module stays on the Blizzard style and says why once per session.
local CONFLICTS = { "DialogueUI", "Immersion", "Storyline" }

local module = core:RegisterModule("parchment", {
    title = "Quest Parchment",
    defaults = {
        style = "parchment",   -- "parchment" | "blizzard"
        shadowOpacity = 70,    -- %, the #191919 shadow around the parchment's edge
        portraitZoom = 80,     -- %, PlayerModel portrait zoom (100 = head only)
    },
})

local function FindConflict()
    for _, name in ipairs(CONFLICTS) do
        if C_AddOns.IsAddOnLoaded(name) then
            return C_AddOns.GetAddOnMetadata(name, "Title") or name
        end
    end
end

-- ---------------------------------------------------------------------------
-- Core hand-off (XpieHUD:SetQuestLook): see XpieHUD_Core/QuestDialog.lua.
-- Every answer is nil ("not mine") until the renderer takes the lists over.
-- ---------------------------------------------------------------------------
local look = {}

function look:IsActive()
    return module.renderer ~= nil
        and module.db.style == "parchment"
        and not module.conflict
        and XpieHUDDB.questDialogEnabled
end

function look:SelectNumber(number)
    local r = module.renderer
    if r and r.SelectNumber then return r:SelectNumber(number) end
end

function look:HandleSpace()
    local r = module.renderer
    if r and r.HandleSpace then return r:HandleSpace() end
end

function look:RefreshBadges(show)
    local r = module.renderer
    if r and r.RefreshBadges then return r:RefreshBadges(show) end
end

function look:OnDialogShow(frame)
    local r = module.renderer
    if r and r.OnDialogShow then r:OnDialogShow(frame) end
end

module.look = look

-- ---------------------------------------------------------------------------
-- Module
-- ---------------------------------------------------------------------------
function module:Apply()
    local r = self.renderer
    if r and r.Apply then r:Apply(look:IsActive()) end
end

function module:OnLogin()
    self.conflict = FindConflict()
    if self.conflict and self.db.style == "parchment" then
        core:Print(("Quest Parchment is off: %s also changes the quest windows. Disable one of the two."):format(self.conflict))
    end
    core:SetQuestLook(look)
end

function module:BuildSettings(page)
    page:Status(function()
        if module.conflict then return ("(off: %s is loaded)"):format(module.conflict) end
        if not module.renderer then return "(in development: no visual changes yet)" end
        return ""
    end)
    page:Note("Shows the quest, gossip and greeting windows as a floating parchment: Blizzard's own quest parchment with its torn edges and a soft shadow, the NPC's 3D portrait with the text beside it, native quest icons, a reward grid and tan buttons. Quest text appears instantly. The window still moves and resizes as set on the XpieHUD page, and the number keys keep working.")
    page:Note("|cffff8080Not compatible with DialogueUI, Immersion or any other addon that replaces or restyles the quest windows.|r If one of them is loaded, Quest Parchment stays off. Disable the XpieHUD_Parchment addon to remove this page completely.")
    page:Dropdown({
        key = "style", label = "Style",
        values = function()
            return {
                { key = "parchment", label = "Parchment" },
                { key = "blizzard",  label = "Blizzard (XpieHUD Core's quest window)" },
            }
        end,
    })
    page:Space(6)
    page:Slider({ key = "shadowOpacity", label = "Shadow Opacity", description = "The soft dark shadow that follows the parchment's torn edge.", min = 0, max = 100, step = 5, format = "%d%%" })
    page:Slider({ key = "portraitZoom", label = "Portrait Zoom", description = "How close the NPC's 3D portrait is framed. 100% shows the head only; lower shows more of the model.", min = 50, max = 100, step = 5, format = "%d%%" })
end
