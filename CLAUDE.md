# XpieHUD — Claude Code Handoff

You are picking up development of **XpieHUD**, a personal World of Warcraft retail addon, at **v1.0.9**. The repo is https://github.com/xpie-29/XpieHUD and it is the source of truth. Where anything below disagrees with the code in the repo, trust the code and tell me.

The next feature is a **native quest window enhancement** (details in "Next feature" below). Before you write code, read the repo, confirm the file layout matches what's described here, and propose a short plan for my approval.

---

## About me and how I like to work

- I'm Jeremy. I play a Hunter named Introvurt. I'm not a professional Lua developer, but I'm comfortable with git, testing in-game, and reading errors.
- **Goal of XpieHUD:** a clean, minimal UI with as few addons as possible. XpieHUD is the lightweight central controller. I prefer to keep features self-contained in XpieHUD rather than add new addons.
- **Eyesight:** I'm 52 and prefer dark or low-strain interfaces for long sessions. Keep that in mind for any visual choices.
- **Testing loop:** you make changes, I `/reload` in game and report back with BugSack/BugGrabber error dumps (including locals), `/script print(...)` results, and screenshots. Give me specific diagnostic commands when you need information from the live client.
- **Versioning:** bump the version in `XpieHUD.toc` for every iteration I test (1.1.0, 1.1.1, …). Update the README version history. One commit per version, with a message like `v1.x.x - description`. Tag releases when I say a feature is done.
- **Tone:** a little personality and humor is welcome. Credit me when my diagnostics actually help, but no flattery when I haven't earned it. Be direct about what won't work.
- **Scope discipline:** if something fights the WoW protected-frame system and isn't working after a few honest attempts, tell me so we can cut it. (We already did this once with the quest tracker width slider, and that was the right call.)

---

## Environment

- WoW retail. The TOC uses `## Interface: 120100`. Note: older docs and the README say "The War Within / 11.x," but 120100 is a 12.x (Midnight-era) interface number, and Midnight is live. Please check the current retail interface version, fix the README wording, and add `120105` if appropriate (DialogueUI's TOC lists `120100, 120105`).
- Other addons I run: **Enhance QOL** (Chat, Skinner, and Move modules enabled), **RestedXP Guides**, **BugGrabber/BugSack**.
- **DialogueUI:** I'm disabling it. The new feature replaces it, and it takes over the same quest/gossip frames. Assume it is not loaded.
- Blizzard's UI source for checking frame names and APIs: https://github.com/Gethe/wow-ui-source (use the live/retail branch). **Check every Blizzard frame name and API call against it rather than relying on memory.** Frame names and APIs shift between patches.

---

## Current state: v1.0.9

### Files (verify against the repo)
- `XpieHUD.toc`: load order, version, SavedVariables
- `Core.lua`: addon table, defaults, `SetOption`, event handling (PLAYER_LOGIN etc.), slash commands, and the global keybinding handlers `XPIEHUD_TOGGLE_CHAT()` and `XPIEHUD_TOGGLE_MINIMAP()`
- `Visibility.lua`: hide/show logic for Blizzard elements. `ApplyAll()` is the central re-apply entry point.
- `RestedXP.lua`: the RestedXP integration
- `ChatMeterToggle.lua`: the three-state chat/meter toggle and its movable button
- `Settings.lua`: the settings panel (scroll frame, checkboxes, sliders, `RefreshSettings`)
- `Bindings.xml`: intentionally emptied (see lessons learned)
- `README.md`, `.gitignore`
- SavedVariables table: `XpieHUDDB`

### Features
- **General visibility:** hides the status (XP/rep) bars, the micro menu, and the bag bar. Scales the Extra Action Button and Zone Ability frame.
- **RestedXP integration:**
  - Hides the Active Targets and Active Items panels.
  - Strips borders on all RXP themes, and the stripping survives theme switches.
  - Overall opacity slider.
  - Hides the resize grip (`RXPFrame.Footer.icon`) by setting its alpha, so it stays usable.
  - Subtle background alpha on step frames (`STEP_FRAME_BG_ALPHA = 0.1`).
- **Chat/meter toggle:**
  - Cycles three states: chat on/meter off → chat off/meter on → both off.
  - Movable on-screen button: left-click cycles, right-drag moves, and the position is saved.
  - The meter frame's name changes between patches, so `/xhud meterframe` scans for it, and the name can also be set manually and saved.
  - An OnShow hook stops the meter from re-showing itself when its data updates.
- **Keybindings:** Toggle Chat and Toggle Minimap, listed under "XpieHUD" in Key Bindings.

### Slash commands
`/xhud` or `/xpiehud` (open settings), `chat`, `minimap`, `meter`, `meter 0|1|2`, `button`, `meterframe`, `meterframe <name>`, `showall`, `reset` (asks for confirmation twice).

### Known issue (parked)
- **False-positive `ADDON_ACTION_BLOCKED` when opening the world map.** The error blames XpieHUD for calling `SetPropagateMouseClicks()`, which XpieHUD never calls. It looks like a Blizzard taint chain (through the Pet Tamer map pins) getting misattributed to us. The suspected cause is the mouse-enabled `ChatMeterToggle` button parented to `UIParent`. Proposed fix: create the button in `C_Timer.After(0, ...)`, after the load taint window, and/or look at how it's parented. It's cosmetic because the map works fine, so it's low priority. But if the new feature touches keyboard or mouse propagation, keep this in mind.

### Lessons learned (please don't relearn these)
1. **Bindings.xml:** the `name` and `header` attributes on `<Binding>` are deprecated in the current client and cause load warnings. Keybinds are defined as global Lua functions in `Core.lua`. The `BINDING_NAME_*` and `BINDING_HEADER_*` globals still label them in the Key Bindings UI.
2. **`hooksecurefunc` recursion:** a post-hook that calls the same method it's hooking (for example, `SetBackdropBorderColor` inside a `SetBackdropBorderColor` hook) recurses until the C stack overflows. Always use a re-entrancy guard boolean.
3. **Recursive frame walkers:** default the depth parameter (`depth = depth or 0`) *before* comparing it.
4. **One-shot styling gets overwritten.** Other addons and Blizzard re-apply their own styling when themes switch or frames refresh. Use persistent hooks (on the setter or on OnShow) instead of applying a change once.
5. **Protected frames:** the quest tracker width slider failed because objective tracker widths are effectively locked by protected layout in the current client. It was removed in v1.0.9. Expect similar walls around anything Blizzard lays out through the UI panel manager.
6. **Hide by alpha, not `Hide()`,** for anything that might be protected or that another addon manages. It's safer in combat and doesn't fight other addons' show/hide logic.

---

## Next feature: native quest window QoL (target: v1.1.0)

### What I want
Keep Blizzard's **native** retail quest and gossip windows exactly as they are. That includes the native parchment/background that changes with quest type (normal, campaign, and specific campaign themes). Add only the following quality-of-life features. It should feel like Blizzard shipped an update to its own quest window, with no reskin.

1. **Hide the rest of the UI while a quest or gossip window is open,** so the dialog stands out. Restore everything on close. Reuse the `Visibility.lua` machinery and hide by alpha. Make sure this restores cleanly and doesn't clash with the states XpieHUD already manages (the chat/meter state, RXP opacity, and so on). If combat starts while the UI is hidden, restore it immediately.
2. **Persistent scale and position** for the quest and gossip windows: a drag handle or modifier-drag to move, a scale slider in settings, a position reset, and values saved in `XpieHUDDB`. Blizzard's UI panel manager (`UIPanelWindows`, `ShowUIPanel`) repositions these frames when they show. Re-apply the saved position and scale on every show with a persistent hook, and avoid tainting the panel system. Check the approach against the FrameXML source.
3. **Keyboard navigation:**
   - Keys **1–9** select gossip options, available/active quests in the NPC's list or greeting, and reward choices.
   - **Space** accepts, continues, or completes (Accept on the detail panel, Continue on the progress panel, Complete on the reward panel once a reward is chosen when a choice is required).
   - **Esc** declines or closes.
   - Every other key must pass through, so movement and camera still work.
   - Show small number badges on the options, styled to look native. Include an on/off setting for the badges.
   - The functions to use are unprotected ones like `C_GossipInfo.SelectOption` / `SelectAvailableQuest` / `SelectActiveQuest`, `AcceptQuest`, `DeclineQuest`, `CompleteQuest`, and `GetQuestReward`. Confirm each one against the current API.
   - `SetPropagateKeyboardInput` is restricted in combat. Out of combat the keyboard handler works; in combat it stands down and I click normally.
4. **A settings section** in the existing panel: master enable, hide-UI toggle (optionally with per-element choices), scale slider, reset position, and the number badges toggle.

### Explicitly out of scope
- No camera movement or zoom, and no features from DialogueUI's Gameplay or Accessibility options (TTS and the like). No custom themes or reskinning.
- Don't replace the native background or theme logic. It already switches by quest type. I believe it gets its theme from something like `C_QuestLog.GetQuestDetailsTheme`, but verify that. It should keep working untouched.

### Decisions still open (ask me)
- **Enhance QOL's Move module might already move or scale `QuestFrame`/`GossipFrame`.** If both addons try to position these frames, they'll fight. My preference is for XpieHUD to own the quest window so all of its behavior lives in one place, and I'll turn that frame off in Enhance QOL. Confirm with me before you build the positioning.
- Which UI elements get hidden while the dialog is open: everything except the quest window, or a configurable list?
- **Frames in scope:** at minimum `QuestFrame` (greeting, detail, progress, and reward panels) and `GossipFrame`. Ask whether to include others, such as `ItemTextFrame` for books and plaques.

### Suggested structure
- New file `QuestDialog.lua`, added to the TOC after `Visibility.lua` and before `Settings.lua`.
- New defaults in `Core.lua` (for example `questDialogEnabled`, `questDialogHideUI`, `questDialogScale`, `questDialogPoint`, `questDialogBadges`), plus a `/xhud questreset` slash command.
- New section in `Settings.lua`, following the existing checkbox and slider patterns, with values refreshed in `RefreshSettings`.
- README: add a feature section, the new slash command, and a version history line.

### Testing checklist I'll run in game
- Gossip-only NPC, an NPC with multiple quests, quest accept, quest progress (items still needed), quest turn-in with no choice, turn-in with a reward choice, and a campaign quest (to confirm the themed parchment still appears).
- Keys 1–9, Space, and Esc in each of those states. Movement keys still work with the window open.
- UI hides on open and fully restores on close, including after switching NPCs quickly and after entering combat mid-dialog.
- Scale and position persist across `/reload` and relog.
- No new BugSack errors, and no new taint when opening the world map afterward.
