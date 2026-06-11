# Changelog

Format: [Semantic Versioning](https://semver.org) — MAJOR.MINOR.PATCH.
- MAJOR: große, ggf. inkompatible Umbauten
- MINOR: neue Features / größere Rewrites
- PATCH: Bugfixes

## 1.1.1
- Fix (DamageMeter): No longer throws an error when a death-log entry
  references a segment that has already been pruned. `CountEvents` now
  nil-guards the segment (same as `SegDPS`) instead of indexing it.
- i18n (Bags): Category and group names in the bag UI are now localized.
  German translations added for All Items, Armor, Trade Goods,
  Miscellaneous, Professions, Quest Items, Reagent Bag, Weapons / Trinkets,
  Gear Enhancements, Item Set Gear, Housing, The Armory and Adventure Prep.
- Change (QuestTracker): Custom free-positioning is disabled on this client.
  MoP's legacy WatchFrame is screen-height, so detaching it only allowed
  placement in the upper portion of the screen and made the unlock handle
  oscillate. The tracker now stays at Blizzard's managed position with the
  EllesmereUI styling/background intact. A movable tracker is planned via a
  content-height rewrite.
- Locale (deDE): German localization completed — full options localization
  restored plus the 13 new Bags terms above.

## 1.1.0
- Locale: Complete German (deDE) localization across all modules, including
  every options panel.

## 1.0.0
First public release — EllesmereUI ported to Mists of Pandaria Classic
(interface 50504). Includes the core framework plus 16 modules: ActionBars,
AuraBuffReminders, Bags, Basics, BlizzardSkin, Chat, DamageMeter, Friends,
Minimap, MythicTimer (Challenge Mode timer), Nameplates, QoL, QuestTracker,
RaidFrames, ResourceBars, UnitFrames.
