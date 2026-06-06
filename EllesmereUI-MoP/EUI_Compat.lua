--------------------------------------------------------------------------------
--  EUI_Compat.lua
--  Compatibility shim layer for the EllesmereUI-MoP port (Mists of Pandaria
--  Classic, interface 5.5.x / 50501).
--
--  PURPOSE
--  -------
--  The original EllesmereUI targets retail (Midnight, 12.0.x). Most of its
--  retail-only API calls are already guarded with `if C_X and C_X.Func then`,
--  so on MoP Classic those features simply no-op. This file does NOT try to
--  recreate retail systems that do not exist in MoP (Edit Mode, Cooldown
--  Viewer, Mythic+, Great Vault, Dragonriding, talent trees) -- those stay
--  disabled by their existing guards.
--
--  What this file DOES is provide MoP-native fallbacks for namespaced APIs
--  that DO have a working equivalent in MoP (e.g. C_Spell.GetSpellInfo via the
--  global GetSpellInfo), so guarded features keep working instead of silently
--  switching off.
--
--  RULES
--  -----
--   * Purely additive. Every shim is wrapped in a presence check, so on a
--     client where Blizzard already ships the namespace/function we leave the
--     real implementation untouched.
--   * No metatable "no-op" traps on retail-only namespaces -- that would defeat
--     the existing guards and risk subtle nil-return bugs. Genuinely absent
--     systems are left absent.
--   * Loaded immediately after EllesmereUI_Lite.lua and before everything else
--     (see the .toc), so the shims exist before any module code runs.
--------------------------------------------------------------------------------
local _, ns = ...

local EUICompat = {}
EllesmereUI = EllesmereUI or {}
EllesmereUI.Compat = EUICompat

-- Build / interface detection -------------------------------------------------
-- WOW_PROJECT_ID is present on all modern clients. MoP Classic reports its own
-- project id; we expose a couple of convenience flags other files can read.
local _, _, _, tocversion = GetBuildInfo()
EUICompat.tocVersion = tocversion or 0
EUICompat.isMoPClassic = (tocversion or 0) >= 50000 and (tocversion or 0) < 60000
EUICompat.isRetail = (tocversion or 0) >= 100000

--------------------------------------------------------------------------------
--  C_Spell  (retail returns info tables; MoP exposes the classic globals)
--------------------------------------------------------------------------------
do
    C_Spell = C_Spell or {}

    if not C_Spell.GetSpellInfo and GetSpellInfo then
        -- Retail C_Spell.GetSpellInfo(spell) -> table {name, iconID, castTime,
        -- minRange, maxRange, spellID, ...}. Classic GetSpellInfo returns a
        -- positional tuple. Wrap it into the table shape callers expect.
        function C_Spell.GetSpellInfo(spell)
            if spell == nil then return nil end
            local name, _, icon, castTime, minRange, maxRange, spellID = GetSpellInfo(spell)
            if not name then return nil end
            return {
                name        = name,
                iconID      = icon,
                originalIconID = icon,
                castTime    = castTime,
                minRange    = minRange,
                maxRange    = maxRange,
                spellID     = spellID or (type(spell) == "number" and spell or nil),
            }
        end
    end

    if not C_Spell.GetSpellTexture then
        local fn = GetSpellTexture or (C_Spell and C_Spell.GetSpellInfo and function(s)
            local i = C_Spell.GetSpellInfo(s); return i and i.iconID
        end)
        if fn then
            function C_Spell.GetSpellTexture(spell)
                if spell == nil then return nil end
                return (GetSpellTexture and GetSpellTexture(spell))
                    or (function() local i = C_Spell.GetSpellInfo(spell); return i and i.iconID end)()
            end
        end
    end

    if not C_Spell.GetSpellCooldown and GetSpellCooldown then
        function C_Spell.GetSpellCooldown(spell)
            if spell == nil then return nil end
            local start, duration, enabled, modRate = GetSpellCooldown(spell)
            if start == nil then return nil end
            return { startTime = start, duration = duration,
                     isEnabled = enabled == 1 or enabled == true, modRate = modRate or 1 }
        end
    end

    if not C_Spell.IsSpellUsable then
        local isUsable = IsUsableSpell
        if isUsable then
            function C_Spell.IsSpellUsable(spell)
                if spell == nil then return nil end
                local usable, noMana = isUsable(spell)
                return usable, noMana
            end
        end
    end

    -- GetSpellCastCount exists only on retail (charge/stack reads). MoP has no
    -- equivalent; leave it nil so the existing `C_Spell.GetSpellCastCount and`
    -- guards keep that path disabled.
end

--------------------------------------------------------------------------------
--  C_UnitAuras  (retail aura-data tables; MoP uses UnitAura positional API)
--------------------------------------------------------------------------------
do
    C_UnitAuras = C_UnitAuras or {}

    -- Internal: scan a unit's auras for a given spellID in a given filter and
    -- return a retail-shaped aura table, or nil.
    local function scanForSpellID(unit, spellID, filter)
        if not UnitAura then return nil end
        for i = 1, 64 do
            local name, icon, count, dispelType, duration, expirationTime,
                  source, isStealable, nameplateShowPersonal, auraSpellID,
                  canApplyAura, isBossDebuff, castByPlayer =
                  UnitAura(unit, i, filter)
            if not name then break end
            if auraSpellID == spellID then
                return {
                    name              = name,
                    icon              = icon,
                    applications      = count or 0,
                    charges           = count or 0,
                    dispelName        = dispelType,
                    duration          = duration,
                    expirationTime    = expirationTime,
                    sourceUnit        = source,
                    isStealable       = isStealable,
                    spellId           = auraSpellID,
                    canApplyAura      = canApplyAura,
                    isBossAura        = isBossDebuff,
                    isFromPlayerOrPlayerPet = castByPlayer,
                    auraInstanceID    = i,
                }
            end
        end
        return nil
    end

    if not C_UnitAuras.GetPlayerAuraBySpellID then
        function C_UnitAuras.GetPlayerAuraBySpellID(spellID)
            if not spellID then return nil end
            return scanForSpellID("player", spellID, "HELPFUL")
                or scanForSpellID("player", spellID, "HARMFUL")
        end
    end

    if not C_UnitAuras.GetAuraDataByIndex and UnitAura then
        function C_UnitAuras.GetAuraDataByIndex(unit, index, filter)
            local name, icon, count, dispelType, duration, expirationTime,
                  source, isStealable, _, auraSpellID, canApplyAura,
                  isBossDebuff, castByPlayer = UnitAura(unit, index, filter)
            if not name then return nil end
            return {
                name = name, icon = icon, applications = count or 0,
                charges = count or 0, dispelName = dispelType, duration = duration,
                expirationTime = expirationTime, sourceUnit = source,
                isStealable = isStealable, spellId = auraSpellID,
                canApplyAura = canApplyAura, isBossAura = isBossDebuff,
                isFromPlayerOrPlayerPet = castByPlayer, auraInstanceID = index,
            }
        end
    end
end

--------------------------------------------------------------------------------
--  C_Item  (icon lookup is the only core dependency)
--------------------------------------------------------------------------------
do
    C_Item = C_Item or {}

    if not C_Item.GetItemIconByID then
        -- Prefer the classic global GetItemIcon(itemID); fall back to the 10th
        -- return of GetItemInfo (the texture) when needed.
        local getItemIcon = GetItemIcon
        function C_Item.GetItemIconByID(item)
            if item == nil then return nil end
            if getItemIcon then
                local icon = getItemIcon(item)
                if icon then return icon end
            end
            if GetItemInfo then
                local _, _, _, _, _, _, _, _, _, tex = GetItemInfo(item)
                return tex
            end
            return nil
        end
    end
    -- C_Item.GetItemUpgradeInfo is retail-only; left nil (guarded by callers).
end

--------------------------------------------------------------------------------
--  C_Container  (backported on MoP Classic; provide a thin fallback only)
--------------------------------------------------------------------------------
do
    if not C_Container then
        C_Container = {}
        if GetContainerNumSlots then C_Container.GetContainerNumSlots = GetContainerNumSlots end
        if GetContainerItemInfo then
            -- Classic global returns a positional tuple; expose under the same
            -- name. The Bags module (later phase) will adapt the shape.
            C_Container.GetContainerItemInfo = function(bag, slot)
                return GetContainerItemInfo(bag, slot)
            end
        end
        if GetContainerItemID then C_Container.GetContainerItemID = GetContainerItemID end
        if UseContainerItem then C_Container.UseContainerItem = UseContainerItem end
    end
end

--------------------------------------------------------------------------------
--  C_AddOns  (backported on MoP Classic; fallback to legacy globals)
--------------------------------------------------------------------------------
do
    if not C_AddOns then
        C_AddOns = {}
        C_AddOns.IsAddOnLoaded   = IsAddOnLoaded
        C_AddOns.GetAddOnMetadata = GetAddOnMetadata
        C_AddOns.EnableAddOn     = EnableAddOn
        C_AddOns.DisableAddOn    = DisableAddOn
        C_AddOns.LoadAddOn       = LoadAddOn
        C_AddOns.GetAddOnInfo    = GetAddOnInfo
    end
end

--------------------------------------------------------------------------------
--  C_Timer  (present on MoP Classic, but guarantee After/NewTicker exist)
--------------------------------------------------------------------------------
do
    if not C_Timer or not C_Timer.After then
        -- Extremely defensive: MoP Classic ships C_Timer, but if a private/older
        -- build lacks it, fall back to an OnUpdate-driven scheduler.
        C_Timer = C_Timer or {}
        if not C_Timer.After then
            local f = CreateFrame and CreateFrame("Frame")
            local queue = {}
            if f then
                f:SetScript("OnUpdate", function()
                    local now = GetTime()
                    for i = #queue, 1, -1 do
                        if now >= queue[i].at then
                            local cb = queue[i].cb
                            table.remove(queue, i)
                            pcall(cb)
                        end
                    end
                end)
                function C_Timer.After(delay, cb)
                    queue[#queue + 1] = { at = GetTime() + (delay or 0), cb = cb }
                end
            end
        end
    end
end

--------------------------------------------------------------------------------
--  Safe event registration
--------------------------------------------------------------------------------
-- Retail builds know events that MoP Classic does not (e.g. PVP_MATCH_COMPLETE).
-- A plain frame:RegisterEvent on an unknown event raises a hard Lua error that
-- can abort the rest of a frame's setup. This helper validates first (via
-- C_EventUtils.IsEventValid when present) and otherwise pcall-guards the call,
-- so an unknown event name is silently skipped instead of breaking load.
do
    local IsEventValid = C_EventUtils and C_EventUtils.IsEventValid

    function EUICompat.RegisterEventSafe(frame, event)
        if not frame or not event then return false end
        if IsEventValid then
            if not IsEventValid(event) then return false end
            frame:RegisterEvent(event)
            return true
        end
        return (pcall(frame.RegisterEvent, frame, event)) and true or false
    end

    -- Global alias for ported call sites.
    EllesmereUI_RegisterEventSafe = EUICompat.RegisterEventSafe
end

--------------------------------------------------------------------------------
EUICompat.loaded = true
return EUICompat
