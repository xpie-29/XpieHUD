# XpieHUD

A lightweight World of Warcraft addon: quality-of-life for Blizzard's **native** quest windows, plus Zygor Guides styling to match. Built for Retail (Midnight, 12.1.5).

General HUD hiding (chat, minimap, bars, menus) now lives in Enhance QoL. The original all-in-one XpieHUD, with visibility controls, the chat/meter toggle and the RestedXP integration, is preserved on the [`archive/full-v1.2.2`](https://github.com/xpie-29/XpieHUD/tree/archive/full-v1.2.2) branch.

## Features

### Quest Window
Quality-of-life for Blizzard's native quest, gossip and book/plaque windows. There's no reskin: the parchment and campaign themes stay exactly as Blizzard draws them.
- **Hide UI While Talking**: fades action bars, unit frames (including the Personal Resource Display), the objective tracker, chat, the minimap, the Zygor guide and buffs (each can be toggled) while a window is open. Everything comes back on close, or immediately if combat starts.
  - Frames from other addons can be added by name: run `/xhud questscan`, talk to an NPC, and close the window to read what's still visible, then `/xhud questhide <FrameName>`.
- **Tooltips at Cursor**: while talking, tooltips that normally sit in the screen corner appear at the mouse (can be turned off).
- **Position and Size**: drag a window's title bar to move it. A size slider (50–150%) sits in settings. Both are saved and re-applied every time the window opens.
- **Keyboard Shortcuts** (out of combat):
  - **1–9** pick gossip options, quests in an NPC's list, and reward choices.
  - **Space** accepts, continues, completes, or turns a book's page.
  - **Esc** closes the window, as it always has.
  - All other keys pass through, so movement and camera still work. PvP quests and quests that cost gold still need a click.
- **Number Badges & Key Hints**: quests keep their native icon (!, ?, daily, campaign...) with a small number on it; gossip options show the number over a dimmed icon; reward choices get a number in the corner. Also adds small "Space" / "Esc" hints beside the window's own buttons (can be turned off).

### Zygor Guides
- **Strip Backgrounds & Borders**: transparent Zygor window background, borders, tab strip and toolbar, title logo hidden; step boxes keep Zygor's state colours (normal, complete, unavailable) at 50% opacity without edges. Survives Zygor skin changes.
- **Gold Waypoint Arrow**: a gold arrowhead in Blizzard's HUD style, registered as a native Zygor arrow skin ("XpieHUD Gold", `Media/Zygor/arrow.tga`: 160 pre-rotated frames). Zygor's arrived / stairs / taxi icons are unchanged.
- **Enable Zygor Integration** switch: unticking puts back everything XpieHUD changed and leaves Zygor alone.

---

## Slash Commands

| Command | Description |
|---|---|
| `/xhud` or `/xpiehud` | Open settings panel |
| `/xhud questreset` | Reset quest window position and size |
| `/xhud questscan` | List frames still visible during a quest window (arms for the next NPC if none is open) |
| `/xhud questhide <name>` | Add/remove a frame (case-sensitive) from the fade list |
| `/xhud arrowdebug` | Report in chat when Zygor's arrow switches away from the gold sprite (troubleshooting) |
| `/xhud reset` | Reset all settings to defaults (confirm twice) |

---

## Installation

1. Download the latest release zip
2. Extract the `XpieHUD` folder (including its `Media` subfolder) into your `World of Warcraft/_retail_/Interface/AddOns/` directory
3. Restart WoW (a `/reload` is enough when no files were added)

## Requirements

- World of Warcraft Retail (Midnight, Interface 120105)
- Optional: Zygor Guides Viewer for the Zygor features

## Notes

- XpieHUD never calls `Hide()`/`Show()` on Blizzard HUD frames. Most are Edit Mode frames, and hiding them from addon code taints Blizzard's layout system (this caused the old world map `ADDON_ACTION_BLOCKED` error). The quest window fades frames by transparency instead, and moves the minimap off-screen because its blips ignore transparency.
- Quest window positioning: if another addon (e.g. Enhance QoL's Move module) also moves `QuestFrame`, `GossipFrame` or `ItemTextFrame`, turn it off there so the two don't fight.
- Upgrading from 1.x: settings for removed features are cleaned out of `XpieHUDDB` automatically. RestedXP's own Active Targets / Active Items options may still be switched off from when XpieHUD managed them; turn them back on in RestedXP if you use it again.

## Version History

- **2.0.1**: `/xhud arrowdebug` diagnostic for the Zygor arrow
- **2.0.0**: Slimmed down to the quest window features and the Zygor integration (everything else moved to Enhance QoL; full version archived on `archive/full-v1.2.2`). Updated for 12.1.5. Obsolete settings pruned on load.
- **1.2.2**: Fix ADDON_ACTION_BLOCKED (SetPropagateKeyboardInput) when reloading in combat; quest keys reset to pass-through on key release
- **1.2.1**: Zygor title logo hidden with the window chrome; Zygor step boxes at 50% opacity
- **1.2.0**: Zygor Guides integration (transparent window, 30% step boxes, gold arrow skin); guide addon selector (RestedXP / Zygor / both); quest fade "RestedXP" option is now "Guide Addons"
- **1.1.6**: Gold arrowhead replaces the RestedXP waypoint arrow (toggle in settings)
- **1.1.5**: Fix world map `ADDON_ACTION_BLOCKED` (SetPropagateMouseClicks) and Objective Tracker secret-aura taint: Blizzard frames are now hidden by alpha + mouse instead of Hide(); minimap moved off-screen instead of hidden; chat shows while typing when hidden
- **1.1.4**: RestedXP step frame background darkened to 30%
- **1.1.3**: Quest entries keep their native icon with a small gold number on it (options keep the dimmed-icon number); tooltips at cursor while talking; fade Personal Resource Display and MicroButtonAndBagsBar; badge/hint offsets tuned in game
- **1.1.2**: Gold number badges; badge and key-hint alignment; chat shows while typing mid-dialog; `questscan` arms itself for the next NPC and skips frames it cannot inspect
- **1.1.1**: Title-bar drag handle; badges moved onto option icons; Space/Esc key hints; minimap fully hidden while talking; RXP arrow and chat/meter button fade; `questscan`/`questhide`; fixed `/xhud meterframe <name>` (was lowercased and mis-parsed)
- **1.1.0**: Native quest window QoL: hide UI while talking, saved position and size, 1–9/Space keys, number badges

- **1.0.9** — Removed quest tracker width (protected frame limitations in TWW)
- **1.0.8** — Quest tracker width attempt via sub-tracker frames
- **1.0.7** — Quest tracker width auto-detects live value on login
- **1.0.6** — Quest tracker width targets correct content frames
- **1.0.5** — Meter frame OnShow hook prevents data-driven re-shows
- **1.0.4** — Quest tracker width slider (Settings panel)
- **1.0.3** — Meter frame scanner and manual name persistence via `/xhud meterframe`
- **1.0.2** — Chat/meter toggle redesign; frame-based click detection; correct chat routing
- **1.0.1** — Settings panel scroll frame
- **1.0.0** — Chat/Meter 3-state toggle with movable button
- **0.9.x** — RestedXP border strip; Active Targets/Items hide; Bindings.xml modernisation
- **0.2.0** — Initial release: chat/minimap toggle, status bar/micro menu/bag bar hide, extra abilities scale
