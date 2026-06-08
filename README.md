# EllesmereUI-MoP

A port of the EllesmereUI interface suite to **World of Warcraft Classic: Mists of Pandaria** (interface `50504`).

## Installation

Extract the packaged zip into `World of Warcraft\_classic_\Interface\AddOns\`.
You should end up with these folders side by side in `AddOns`:

- `EllesmereUI-MoP` (core — required)
- `EllesmereUIActionBars`, `EllesmereUIAuraBuffReminders`, `EllesmereUIBags`,
  `EllesmereUIBasics`, `EllesmereUIBlizzardSkin`, `EllesmereUIChat`,
  `EllesmereUIDamageMeter`, `EllesmereUIFriends`, `EllesmereUIMinimap`,
  `EllesmereUIMythicTimer`, `EllesmereUINameplates`, `EllesmereUIQoL`,
  `EllesmereUIQuestTracker`, `EllesmereUIRaidFrames`, `EllesmereUIResourceBars`,
  `EllesmereUIUnitFrames`

All modules depend on the core `EllesmereUI-MoP` addon.

## Slash commands

- `/euidm` — toggle the DamageMeter window (`reset`, `lock`, `unlock`, `heal`, `dmg`).

## Building / releasing

Releases are packaged automatically by the [BigWigs packager](https://github.com/BigWigsMods/packager)
via GitHub Actions on every pushed tag. See `REPO-SETUP.md`.
