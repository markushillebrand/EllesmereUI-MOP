# Changelog

All notable changes to EllesmereUI (MoP Classic). Compatible with Mists of
Pandaria Classic — interface 50504 (build 5.5.4).

## [1.1.3]

### Added
- **Loot Roll module.** Replaces Blizzard's default group loot frame with custom
  EUI roll bars: item icon, quality-colored border and name, a countdown status
  bar, and Need / Greed / Disenchant / Pass buttons. Each button shows a live
  per-choice tally of who rolled what, sourced from the loot history
  (`C_LootHistory`) so it is locale-independent. Includes its own config page,
  a mover (Unlock Mode), growth direction, sizing/scale options, and a
  `/euilr test` preview. Fully localized (English base + German).
- **Minimap clock format.** New "Clock Format" option on the Minimap page:
  Game Default, 12-Hour, or 24-Hour. Previously the clock only followed the
  game's time setting; you can now force 12h or 24h independently. Changes apply
  immediately.

### Fixed
- **Damage Meter.** The "Current" segment label was a hardcoded German string;
  it is now localized through the standard translation system (English base,
  German via locale).

## [1.1.2]

### Added
- **Challenge Mode Timer — medal display.** Colored medal-threshold ticks on the
  timer bar plus a live status line ("Current: Diamond · 5:48 until Platinum"),
  counting down through the tiers. Data-driven; adapts to the medal tiers the
  realm exposes (up to five).
- **Movable Quest Tracker.** The quest tracker can be repositioned via the
  unlock/move handle; its background sizes to the tracked content.
- **Buff consolidation** toggle under Player Buffs & Debuffs.

### Changed
- Mythic → Challenge Mode alignment in the timer module (Keystone wording
  replaced, retail-only affix readout removed).
- Added missing German translations for the configuration tabs; the medal
  display is fully localized.

### Removed
- Retail-only options not present in MoP: Mythic boss/0 celebration triggers,
  Auto-Insert Keystone, a dead Dragonriding constant, and the obsolete
  `EllesmereUIBasics` migration-helper module.

## [1.1.1]

### Fixed
- Damage Meter crash fix.
- Bags: German category names.
- Reverted the earlier buff-consolidation change pending rework.

## [1.1.0]

- First 1.1.x release of the MoP Classic port.
