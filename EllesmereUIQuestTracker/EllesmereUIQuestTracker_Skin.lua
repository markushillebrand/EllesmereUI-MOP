-------------------------------------------------------------------------------
-- EllesmereUIQuestTracker_Skin.lua  (MoP Classic rewrite)
--
-- The retail ObjectiveTrackerFrame does not exist on MoP Classic (5.5.x);
-- the game uses the legacy WatchFrame. This file styles WatchFrame:
--   * font sizes for quest-title (header) lines and objective lines
--   * quest-title text colour (titleR/G/B) when skinHeaders is enabled
--   * the "OBJECTIVES" header label (WatchFrameTitle)
--
-- Injection point: hooksecurefunc("WatchFrame_SetLine", ...) -- Blizzard calls
-- this for every line on every WatchFrame_Update, passing isHeader, so we can
-- re-apply font/colour after Blizzard sets its defaults. No SetScript, no
-- secure-tree writes, no calls into WatchFrame_Update (taint-free).
--
-- completed/focus colours: retail concepts (per-objective completion state,
-- supertracked quest) have no clean WatchFrame equivalent and are deferred to
-- a later pass; the DB keys are preserved so nothing breaks.
-------------------------------------------------------------------------------
local _, ns = ...
local EQT = ns.EQT

local abs = math.abs
local function Cfg(k) return EQT.Cfg(k) end

-- Blizzard's WatchFrame_SetLine sets header lines to (0.75, 0.61, 0). We use
-- this to detect headers on lines styled before our hook was installed.
local function ColorLooksHeader(fs)
    if not fs then return false end
    local r, g, b = fs:GetTextColor()
    return r and g and b
        and abs(r - 0.75) < 0.06 and abs(g - 0.61) < 0.06 and abs(b - 0.0) < 0.06
end

-------------------------------------------------------------------------------
-- Per-line styling
-------------------------------------------------------------------------------
local function StyleLine(line, isHeader)
    if not line or not line.text then return end
    local objSize = tonumber(Cfg("objectiveFontSize")) or 10
    local file, _, flags = line.text:GetFont()
    if isHeader then
        local titleSize = tonumber(Cfg("titleFontSize")) or 12
        if file then line.text:SetFont(file, titleSize, flags) end
        if Cfg("skinHeaders") ~= false then
            local r, g, b = Cfg("titleR"), Cfg("titleG"), Cfg("titleB")
            if r and g and b then line.text:SetTextColor(r, g, b) end
        end
    else
        if file then line.text:SetFont(file, objSize, flags) end
        -- objective colour left at Blizzard default on MoP (completed/focus
        -- colouring deferred)
    end
    if line.dash then
        local df, _, dflags = line.dash:GetFont()
        if df then line.dash:SetFont(df, objSize, dflags) end
    end
end

-------------------------------------------------------------------------------
-- Header label ("OBJECTIVES")
-------------------------------------------------------------------------------
local function StyleTitle()
    local t = _G.WatchFrameTitle
    if not t then return end
    if Cfg("skinHeaders") == false then return end
    local file, _, flags = t:GetFont()
    local titleSize = tonumber(Cfg("titleFontSize")) or 12
    if file then t:SetFont(file, titleSize, flags) end
    if Cfg("accentHeaders") ~= false then
        local r, g, b = Cfg("titleR"), Cfg("titleG"), Cfg("titleB")
        if r and g and b then t:SetTextColor(r, g, b) end
    end
end

-------------------------------------------------------------------------------
-- Re-style every currently visible line (no call into Blizzard's update).
-- Live updates are handled by the WatchFrame_SetLine hook; this path is for
-- font-size / colour option changes and profile swaps.
-------------------------------------------------------------------------------
local function RestyleExisting()
    local lines = _G.WatchFrameLines
    if lines and lines.GetChildren then
        local kids = { lines:GetChildren() }
        for _, f in ipairs(kids) do
            if f and f.text then
                local isHeader = f._euiHeader
                if isHeader == nil then isHeader = ColorLooksHeader(f.text) end
                StyleLine(f, isHeader and true or false)
            end
        end
    end
    StyleTitle()
end

EQT.RefreshFonts = RestyleExisting
EQT.RestyleAll   = RestyleExisting

-------------------------------------------------------------------------------
-- Init
-------------------------------------------------------------------------------
local _hooked = false
function EQT.InitSkin()
    if not _G.WatchFrame then return end

    if not _hooked and type(_G.WatchFrame_SetLine) == "function" then
        _hooked = true
        hooksecurefunc("WatchFrame_SetLine", function(line, _anchor, _vo, isHeader)
            if not line then return end
            line._euiHeader = isHeader and true or false
            StyleLine(line, isHeader and true or false)
        end)
    end

    -- Initial pass over anything already rendered, plus the header label.
    RestyleExisting()
end
