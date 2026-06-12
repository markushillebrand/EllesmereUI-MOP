-------------------------------------------------------------------------------
-- EUI_LootRoll_Options.lua
--
-- Config page for the custom loot roll bars: enable, sizing, growth direction,
-- scale, disenchant button, roll-count tally, quality border.
-------------------------------------------------------------------------------
local _, ns = ...
local ELR = ns.ELR

local initFrame = CreateFrame("Frame")
initFrame:RegisterEvent("PLAYER_LOGIN")
initFrame:SetScript("OnEvent", function(self)
    self:UnregisterEvent("PLAYER_LOGIN")
    if not EllesmereUI or not EllesmereUI.RegisterModule then return end
    if not ELR then return end

    local function DB()
        local d = _G._ELR_DB
        if d and d.profile and d.profile.lootRoll then return d.profile.lootRoll end
        return {}
    end
    local function Cfg(k) return DB()[k] end
    local function Set(k, v) DB()[k] = v end
    local function Apply() if ELR.Rebuild then ELR.Rebuild() end end

    local GROWTH_VALUES = { DOWN = EllesmereUI.L("Down"), UP = EllesmereUI.L("Up") }
    local GROWTH_ORDER  = { "DOWN", "UP" }

    local function BuildPage(_, parent, yOffset)
        local W = EllesmereUI.Widgets
        local y = yOffset
        local h

        if EllesmereUI.ClearContentHeader then EllesmereUI:ClearContentHeader() end
        parent._showRowDivider = true

        -- Reposition hint
        do
            local fontPath = EllesmereUI.GetFontPath and EllesmereUI.GetFontPath() or STANDARD_TEXT_FONT
            local infoFrame = CreateFrame("Frame", nil, parent)
            infoFrame:SetSize(parent:GetWidth() or 400, 30)
            infoFrame:SetPoint("TOP", parent, "TOP", 0, y - 20)
            infoFrame._isSpacer = true
            local infoLabel = infoFrame:CreateFontString(nil, "OVERLAY")
            infoLabel:SetFont(fontPath, 15, "")
            infoLabel:SetTextColor(1, 1, 1, 0.75)
            infoLabel:SetPoint("CENTER")
            infoLabel:SetJustifyH("CENTER")
            infoLabel:SetText(EllesmereUI.L("Reposition this element in Unlock Mode. Preview with /euilr test."))
            y = y - 40
        end

        -- GENERAL ----------------------------------------------------------
        _, h = W:SectionHeader(parent, "GENERAL", y); y = y - h

        local r
        r, h = W:DualRow(parent, y,
            { type = "toggle", text = "Enable",
              tooltip = "Replace Blizzard's default loot roll frame with EUI bars. Toggling off requires a /reload to restore Blizzard's frame.",
              getValue = function() return Cfg("enabled") ~= false end,
              setValue = function(v) Set("enabled", v) end },
            { type = "dropdown", text = "Growth Direction",
              values = GROWTH_VALUES, order = GROWTH_ORDER,
              getValue = function() return Cfg("growth") or "DOWN" end,
              setValue = function(v) Set("growth", v); Apply() end })
        y = y - h

        r, h = W:DualRow(parent, y,
            { type = "toggle", text = "Disenchant Button",
              tooltip = "Show the Disenchant roll button when available.",
              getValue = function() return Cfg("showDisenchant") ~= false end,
              setValue = function(v) Set("showDisenchant", v); Apply() end },
            { type = "toggle", text = "Roll Counts",
              tooltip = "Show how many players chose Need / Greed / Disenchant / Pass on each button (via the loot history).",
              getValue = function() return Cfg("showRollCounts") ~= false end,
              setValue = function(v) Set("showRollCounts", v) end })
        y = y - h

        r, h = W:DualRow(parent, y,
            { type = "toggle", text = "Quality Border",
              tooltip = "Color each bar's border by item quality.",
              getValue = function() return Cfg("qualityBorder") ~= false end,
              setValue = function(v) Set("qualityBorder", v); Apply() end },
            { type = "dropdown", text = "",
              values = { __ = "" }, order = { "__" },
              getValue = function() return "__" end, setValue = function() end })
        do
            local rr = r._rightRegion
            if rr and rr._control then rr._control:Hide() end
        end
        y = y - h

        -- SIZE -------------------------------------------------------------
        _, h = W:SectionHeader(parent, "SIZE", y); y = y - h

        r, h = W:DualRow(parent, y,
            { type = "slider", text = "Width", min = 200, max = 500, step = 2,
              getValue = function() return Cfg("width") or 328 end,
              setValue = function(v) Set("width", v); Apply() end },
            { type = "slider", text = "Height", min = 18, max = 48, step = 1,
              getValue = function() return Cfg("height") or 28 end,
              setValue = function(v) Set("height", v); Apply() end })
        y = y - h

        r, h = W:DualRow(parent, y,
            { type = "slider", text = "Spacing", min = 0, max = 16, step = 1,
              getValue = function() return Cfg("spacing") or 4 end,
              setValue = function(v) Set("spacing", v); Apply() end },
            { type = "slider", text = "Scale", min = 0.5, max = 2.0, step = 0.05,
              getValue = function() return Cfg("scale") or 1.0 end,
              setValue = function(v) Set("scale", v); Apply() end })
        y = y - h

        return math.abs(y)
    end

    _G._EBS_BuildLootRollPage = BuildPage

    EllesmereUI:RegisterModule("EllesmereUILootRoll", {
        title       = "Loot Roll",
        description = "Custom group loot roll bars: countdown, roll tally, disenchant button, mover.",
        pages       = { "Loot Roll" },
        buildPage   = function(pageName, p, yOffset) return BuildPage(pageName, p, yOffset) end,
        onReset = function()
            local d = _G._ELR_DB
            if d and d.ResetProfile then d:ResetProfile() end
            if ELR.Rebuild then ELR.Rebuild() end
            EllesmereUI:InvalidatePageCache()
        end,
    })

    SLASH_EUILROPTS1 = "/euilropts"
    SlashCmdList.EUILROPTS = function()
        if InCombatLockdown and InCombatLockdown() then return end
        EllesmereUI:ShowModule("EllesmereUILootRoll")
    end
end)
