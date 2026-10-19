# XpieHUD - Quest Parchment: build plan

Status (2026-10-19): design settled through six mockup rounds; phase 0 in-game
test passed (Tools/XpieHUD_ParchmentTest). Nothing built in the addon yet.

## What it is

An optional extension addon, **XpieHUD_Parchment** ("XpieHUD - Quest Parchment"),
like the Zygor / Baganator / RestedXP / MinimapButtonButton extensions. Players
install and enable it if they want it. XpieHUD Core's quest window features stay
exactly as they are; when this module is loaded and its Style is "Parchment",
it takes over how the quest, gossip and greeting windows look. Style "Blizzard"
(or disabling the addon) gives the Core behaviour back unchanged.

**Not compatible** with DialogueUI, Immersion, or any other addon that replaces
or reskins the quest/gossip frames. Stated in the .toc Notes, the README and the
settings page; at login, if one of those is loaded, the module stays on the
Blizzard style and prints one chat line saying why.

## Design (from the mockups)

- Fixed-size floating parchment (Blizzard's own QuestBG art, switched per quest
  via `C_QuestLog.GetQuestDetailsTheme`), never resizes; content scrolls.
- Torn-edge alpha mask per parchment theme (our TGA, outline only) removes the
  dark backing baked into Blizzard's art. Shadow: the same outline blurred,
  `#191919` at 70%.
- Title pinned at the top, full width, centred, wraps centred. Tag line under
  it: quest classification icon + text, and "Warband Completed" when set.
- Framed 3D NPC portrait (PlayerModel in `TalkingHeads-<faction>-PortraitFrame`,
  138px in the mockups, portrait zoom 0.8) at the top left; quest text wraps to
  its right, then runs full width below it. Item-started quests show the item
  icon in the ring.
- Native quest/gossip icons (QuestUtil), XpieHUD number badges, grey low-level.
- Rewards: native item buttons in an even two-column grid (12px gaps).
- Native seal + signature (QuestInfoSealFrame), native section headers.
- Blizzard MinimalScrollBar; "more below" = chat's flashing
  `minimal-scrollbar-arrow-returntobottom`.
- Buttons pinned at the bottom: `128-GoldRedButton` desaturated + tan, with a
  ~20% ADD lift (two shades lighter than phase 0; /xpt light to tune).
- Movable and resizable exactly like today (Core's saved position and size).
- Quest text appears instantly (no typewriter) so AI Quest Voices stays in sync.

## Architecture

**Re-dress Blizzard's frames in place; never replace them.**
`QuestFrame` and `GossipFrame` stay the real, shown frames. AI Quest Voices
times its audio on `QuestFrame:IsShown()` / `GossipFrame:IsShown()`, and the
accept / complete / reward-choice flows stay Blizzard's own.

- Chrome (NineSlice, portrait, title bar, backgrounds) hidden by alpha, never
  Hide(). Frames resized to the fixed parchment size; Core keeps positioning.
- Our layers (shadow, masked parchment, title, tag line, portrait) are added as
  children of those frames.
- **Quest pages (detail / progress / reward):** Blizzard's QuestInfo keeps
  rendering objectives, every reward type (items, currencies, reputation,
  spells, followers, titles, XP, money, war mode, warband first-completion
  flags), seal and group size. We post-hook `QuestInfo_Display` and
  `QuestInfo_ShowRewards` (only when the template is the quest frame's, never
  the map's), re-anchor Blizzard's scroll frame into our content area, swap its
  scroll bar for MinimalScrollBar, hide `QuestInfoTitleHeader` /
  `QuestInfoDescriptionText` by alpha and re-anchor the next element under our
  wrapped text block, and lay reward buttons out in the grid.
- **Gossip and quest greeting lists:** drawn by us from `C_GossipInfo` /
  `GetNumAvailableQuests` etc. (simple data), clicking the same functions
  Blizzard's buttons call (`C_GossipInfo.SelectOptionByIndex`,
  `SelectAvailableQuest`, `SelectActiveQuest`, `SelectAvailableQuest(i)` on the
  greeting panel). Blizzard's list is kept but moved out of view (anchoring, not
  hiding) so its buttons can't be clicked by accident.
- **Buttons:** Blizzard's own Accept / Decline / Complete / Goodbye buttons,
  re-skinned (texture swap) and re-anchored to the pinned positions, so their
  clicks and enable states are unchanged.

**Taint rules:** never write to Blizzard tables, globals or template element
lists (QuestInfo is shared with the world map's quest details: that is where the
old ADDON_ACTION_BLOCKED came from). Only `hooksecurefunc` post-hooks, alpha,
anchors, sizes and our own child frames. Nothing protected is touched; keyboard
capture stays out of combat as today.

## Pieces

1. **Text wrap around the portrait.** WoW FontStrings can't flow around a
   shape, so: one FontString beside the portrait (narrow) and one below (full
   width). Binary-search the word index where the narrow block reaches the
   portrait's height, using the same FontString to measure (exact). Carry an
   open colour code across the split. Languages without spaces (zhCN, zhTW,
   koKR) fall back to text starting below the portrait.
2. **Portrait.** PlayerModel, `SetUnit("npc")`, `SetPortraitZoom(0.8)`, talk
   animation (60) on show. Optional later: per-race zoom (UnitRace /
   UnitCreatureType -> small table, e.g. goblin/gnome closer, tauren further).
   No model (objects, items, boards) -> item/quest icon in the ring.
3. **Masks.** Build script in `XpieHUD_Parchment/Media/src` (like the MBB
   chest icon): reads Blizzard's parchment BLPs at dev time, flood-fills the
   backing, writes 512x512 RLE TGAs (mask ~25-55 KB, shadow ~75-100 KB). One
   pair per QuestBG theme (about 45 incl. professions, zones, accessibility
   variants) plus a generic fallback for themes added in later patches.
4. **Keys past 9.** Core's key capture extended: 1-9, 0 = 10, Shift+1..9 =
   11-19 (city guards list about 15-17). Two-digit badges.
5. **Scroll.** MinimalScrollBar + return-to-bottom flash shown while not at
   the bottom (phase 0 confirmed both).
6. **Core hand-off.** Core gets a small hook: `addon.questLook` (set by the
   module) answers `SelectNumber(n)`, `HandleSpace()`, `GetBadgeTargets()` for
   the gossip / greeting lists the module draws. Everything else in Core (fade,
   tooltips at cursor, position, size, hints) keeps working unchanged.

## Phases

0. In-game test (done, 2026-10-19): masks (RLE, raw, NPOT all load), shadow, portrait,
   scroll bar, arrows, tan buttons.
1. Module shell (done, 3.10.0): addon folder, RegisterModule, settings page (Style, Shadow
   opacity, Portrait zoom), incompatibility check, Core hand-off hook.
2. Parchment frame: masks + shadow for plain/Horde/Alliance first, theme
   switching, chrome by alpha, fixed size, pinned buttons.
3. Gossip + greeting lists (own rendering), badges, keys past 9.
4. Quest detail / progress / reward re-dress: title, tag line, wrap, seal,
   reward grid, scroll bar.
5. Portrait model + item fallback.
6. All theme masks via the build script; accessibility (Quest Text Contrast)
   uses Blizzard's contrast parchments and light text.
7. Version bump, README, screenshots from you to tune.

## What could break

- Other quest-frame addons (DialogueUI, Immersion, ...): unsupported; detected
  and the module stays on the Blizzard style.
- Custom gossip frames (`CustomGossipFrameBase`, NPCs with their own textureKit):
  left to Blizzard.
- QuestInfo shared with the map: hooks act only on the quest frame's templates.
- Long titles / reward names: titles wrap; reward names truncate in their plate.
- Unknown future parchment themes: generic mask until the build script is rerun.
- Model edge cases: no "npc" model, huge models (zoom clamps), models that fail
  to load (fallback icon after a short timeout).
- Brightness: the parchment looked much brighter in the phase-0 screenshots
  than Blizzard's art - check against a native quest window (HDR capture?).
