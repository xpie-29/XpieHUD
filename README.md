# XpieHUD

A lightweight World of Warcraft addon for personal HUD management. Built for Retail (Midnight / 12.x).

## Features

### General Visibility
- **Hide Status Bars** — hide the primary and secondary Blizzard XP/rep tracking bars
- **Hide Micro Menu** — hide the Blizzard micro menu cluster
- **Hide Bag Bar** — hide the Blizzard bag buttons (keybindings unaffected)
- **Extra Abilities Size** — scale the Extra Action Button and Zone Ability frame independently

### RestedXP Integration
- **Hide Active Targets** — hide the RestedXP Active Targets panel
- **Hide Active Items** — hide the RestedXP Active Items / spells panel
- **Strip Borders** — remove all border and edge textures from RestedXP frames (works on all themes including Dark Mode)
- **RestedXP Opacity** — set overall transparency for all RestedXP frames

### Chat / Meter Toggle
Three-state visibility cycle for the chat window and native Blizzard damage meter:
- **State 0** — Chat visible, Meter hidden
- **State 1** — Chat hidden, Meter visible  
- **State 2** — Chat hidden, Meter hidden

Includes a small movable on-screen button (left-click to cycle, right-drag to reposition).

### Quest Window
Quality-of-life for Blizzard's **native** quest, gossip and book/plaque windows. There's no reskin: the parchment and campaign themes stay exactly as Blizzard draws them.
- **Tooltips at Cursor**: while talking, tooltips that normally sit in the screen corner appear at the mouse (can be turned off).
- **Hide UI While Talking**: fades action bars, unit frames (incl. Personal Resource Display), the objective tracker, chat and meter, the minimap, RestedXP frames and buffs (each can be toggled) while a window is open. Everything comes back on close, or immediately if combat starts.
  - Frames from other addons can be added by name: run `/xhud questscan`, talk to an NPC, and close the window to read what's still visible, then `/xhud questhide <FrameName>`.
- **Position and Size**: drag a window's title bar to move it. A size slider (50–150%) sits in settings. Both are saved and re-applied every time the window opens.
- **Keyboard Shortcuts** (out of combat):
  - **1–9** pick gossip options, quests in an NPC's list, and reward choices.
  - **Space** accepts, continues, completes, or turns a book's page.
  - **Esc** closes the window, as it always has.
  - All other keys pass through, so movement and camera still work. PvP quests and quests that cost gold still need a click.
- **Number Badges & Key Hints**: quests keep their native icon (!, ?, daily, campaign...) with a small number on it; gossip options show the number over a dimmed icon; reward choices get a number in the corner. Also adds small "Space" / "Esc" hints beside the window's own buttons (can be turned off).

### Key Bindings
- **Toggle Chat** — bindable in the standard Key Bindings UI under "XpieHUD"
- **Toggle Minimap** — bindable in the standard Key Bindings UI under "XpieHUD"

---

## Slash Commands

| Command | Description |
|---|---|
| `/xhud` or `/xpiehud` | Open settings panel |
| `/xhud chat` | Toggle chat visibility |
| `/xhud minimap` | Toggle minimap visibility |
| `/xhud meter` | Cycle to next chat/meter state |
| `/xhud meter 0\|1\|2` | Jump to specific state |
| `/xhud button` | Show/hide the on-screen toggle button |
| `/xhud meterframe` | Scan for the native damage meter frame global |
| `/xhud meterframe <name>` | Set meter frame name manually (saved across sessions) |
| `/xhud questreset` | Reset quest window position and size |
| `/xhud questscan` | List frames still visible during a quest window (arms for the next NPC if none is open) |
| `/xhud questhide <name>` | Add/remove a frame (case-sensitive) from the fade list |
| `/xhud showall` | Restore all hidden elements |
| `/xhud reset` | Reset all settings to defaults (confirm twice) |

---

## Installation

1. Download the latest release zip
2. Extract the `XpieHUD` folder into your `World of Warcraft/_retail_/Interface/AddOns/` directory
3. Reload the UI or restart WoW

## Requirements

- World of Warcraft Retail (Midnight, Interface 120100+)
- Optional: RestedXP Guides addon for the RestedXP features

## Notes

- The native damage meter frame name varies by patch. If the meter toggle doesn't work, run `/xhud meterframe` to scan for it, then set it with `/xhud meterframe <name>`. This is saved permanently.
- RestedXP border stripping works on all themes (Custom, Dark Mode, etc.) and survives theme switches.
- The chat/meter toggle button position is saved across sessions.
- Quest window positioning: if another addon (e.g. Enhance QOL's Move module) also moves `QuestFrame`, `GossipFrame` or `ItemTextFrame`, turn it off there so the two don't fight.
- `/xhud showall` only clears the persistent hide options; it doesn't touch the quest window settings.

## Version History

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
