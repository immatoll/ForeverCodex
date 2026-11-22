# Forever Codex

<img src="Media/logo.png" alt="Forever Codex logo" width="128" align="right">

An all-in-one companion suite for **WoW Forever** (Classic-era client, Interface 16001). It logs what you
kill and loot, values it, shows it on a map, and keeps track of all your characters, in one gilded-brown
interface.

> Formerly *ForeverKillLog*. Data saved by the old name is picked up automatically (see
> [Upgrading](#upgrading-from-foreverkilllog)).

## Features

- **Loot log per source**: kills, drops and gathering (mining, herbalism, skinning, fishing) are recorded per
  creature or node, with drop chances that firm up as the sample grows.
- **Session HUD ("Kills & Loot")**: live totals, value per hour, best drops, goals, a Regionboard, and a
  collapsible compact mode.
- **Journal**: sources, loot, search, history and statistics.
- **Map window**: heatmaps and markers of where things drop, filters with hover menus, creature search with
  grouped markers, saved spots and routes.
- **Account window** (Altoholic-style): all characters with level, class, XP and rested bonus, location and
  hearthstone, professions and recipes, equipment, bags and bank, mail, auctions, worth and gold. Item and
  material search across characters, and a crafting view that shows what you can make and what you could still
  learn.
- **Prices**: vendor and auction values (Auctionator if present, or the built-in auction house scan with a
  7-day price and supply trend).
- **Tooltips**: items and creatures get grouped, individually switchable lines: prices, loot you got, where it
  drops, crafting uses, which characters own it.
- **Settings window** with categories and optional descriptions; English and German.

## Installation

1. Download a release ZIP (or clone this repository).
2. Make sure the folder is named exactly `ForeverCodex` and sits in
   `World of Warcraft\<version>\Interface\AddOns\`.
3. Restart the game (a `/reload` is not enough for a new addon).

## Commands

| Command | Opens |
|---|---|
| `/fc` or `/codex` | Main command (`/fc journal`, `/fc reset`, `/fc minimap`, ...; the chat help lists them) |
| `/fcmap` | Map window |
| `/fcaccount` or `/fcalts` | Account window |
| `/fcsettings` | Settings |
| `/fcmini` | Mini map |

Window corners can be dragged to resize. Ctrl scales, Shift keeps proportions, right-click centres the window
(Shift + right-click: default size).

## Upgrading from ForeverKillLog

Close the game, then copy
`WTF\Account\<ACCOUNT>\SavedVariables\ForeverKillLog.lua` to `ForeverCodex.lua` in the same folder. The addon
takes the old data over on first load. The old `/fkl` commands keep working.

## Notes

Nothing here is verified by automated tests: it is a game UI addon and is checked in the client. Please report
problems with the steps that led to them (and `/fc debug` output for loot or gathering issues).

## License

Copyright (c) 2026 Christian Remy. All rights reserved. See [LICENSE](LICENSE). The bundled libraries in
`Libs/` keep their own licenses ([notices](Libs/THIRD_PARTY_NOTICES.txt)).
