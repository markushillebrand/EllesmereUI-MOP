-------------------------------------------------------------------------------
--  EllesmereUIDamageMeter.lua
--  A self-contained damage / healing meter for EllesmereUI-MoP.
--  Combat-log based (CombatLogGetCurrentEventInfo). No dependency on the
--  EllesmereUI module/options framework; uses EllesmereUI visual helpers when
--  present and degrades gracefully otherwise.
--
--  v1 scope: damage (DPS) + healing (HPS) modes, "current fight" + "overall"
--  segments, pet attribution, class-coloured bars, reset / mode / segment /
--  lock controls, slash command. (Threat, interrupts, per-spell breakdown,
--  death log -> later iterations.)
-------------------------------------------------------------------------------
local ADDON = "EllesmereUIDamageMeter"

local floor, max, format, sort = math.floor, math.max, string.format, table.sort
local band = bit and bit.band
local GetTime = GetTime
local CLGetInfo = CombatLogGetCurrentEventInfo

-------------------------------------------------------------------------------
--  Combat-log flag constants (use globals if present, else standard values)
-------------------------------------------------------------------------------
local F_TYPE_PET      = COMBATLOG_OBJECT_TYPE_PET            or 0x00001000
local F_TYPE_GUARDIAN = COMBATLOG_OBJECT_TYPE_GUARDIAN       or 0x00002000
local F_AFF_MINE      = COMBATLOG_OBJECT_AFFILIATION_MINE    or 0x00000001
local F_AFF_PARTY     = COMBATLOG_OBJECT_AFFILIATION_PARTY   or 0x00000002
local F_AFF_RAID      = COMBATLOG_OBJECT_AFFILIATION_RAID    or 0x00000004
local F_AFF_GROUP     = F_AFF_MINE + F_AFF_PARTY + F_AFF_RAID
local F_TYPE_PETGUARD = F_TYPE_PET + F_TYPE_GUARDIAN

local DAMAGE_SUBEVENTS = {
    SWING_DAMAGE = true, RANGE_DAMAGE = true, SPELL_DAMAGE = true,
    SPELL_PERIODIC_DAMAGE = true, SPELL_BUILDING_DAMAGE = true,
    DAMAGE_SHIELD = true, DAMAGE_SPLIT = true,
}
local HEAL_SUBEVENTS = {
    SPELL_HEAL = true, SPELL_PERIODIC_HEAL = true,
}

-------------------------------------------------------------------------------
--  SavedVariables / config
-------------------------------------------------------------------------------
local DEFAULTS = {
    point     = { "CENTER", 250, 0 },
    width     = 230,
    height    = 210,
    barHeight = 18,
    maxBars   = 8,
    mode      = "DAMAGE",   -- "DAMAGE" | "HEALING"
    segment   = "CURRENT",  -- "CURRENT" | "OVERALL"
    locked    = false,
    shown     = true,
}

local db  -- assigned on ADDON_LOADED

local function ApplyDefaults()
    EllesmereUIDamageMeterDB = EllesmereUIDamageMeterDB or {}
    db = EllesmereUIDamageMeterDB
    for k, v in pairs(DEFAULTS) do
        if db[k] == nil then
            if type(v) == "table" then
                local t = {}; for i, vv in ipairs(v) do t[i] = vv end
                db[k] = t
            else
                db[k] = v
            end
        end
    end
end

-------------------------------------------------------------------------------
--  Data model
--  segment = { start, endTime, active, combatTime, actors = { [guid] = actor } }
--  actor   = { guid, name, class, damage, healing }
-------------------------------------------------------------------------------
local function NewSegment()
    return { start = nil, endTime = nil, active = false, combatTime = 0, actors = {} }
end

local overall = NewSegment()
local current = NewSegment()

local petOwner = {}  -- [petGUID] = ownerGUID

local function ActorDuration(seg)
    if not seg.start then return 0 end
    local live = seg.active and (GetTime() - seg.start) or 0
    if seg == overall then
        return max(1, (seg.combatTime or 0) + live)
    end
    local endT = seg.endTime or GetTime()
    return max(1, endT - seg.start)
end

local function GetOrCreateActor(seg, guid, name, class)
    local a = seg.actors[guid]
    if not a then
        a = { guid = guid, name = name or "?", class = class, damage = 0, healing = 0 }
        seg.actors[guid] = a
    else
        if name and a.name == "?" then a.name = name end
        if class and not a.class then a.class = class end
    end
    return a
end

local function AddAmount(guid, name, class, key, amount)
    if amount <= 0 then return end
    local ao = GetOrCreateActor(overall, guid, name, class); ao[key] = ao[key] + amount
    local ac = GetOrCreateActor(current, guid, name, class); ac[key] = ac[key] + amount
end

-------------------------------------------------------------------------------
--  Pet -> owner mapping
-------------------------------------------------------------------------------
local function MapUnitPet(petUnit, ownerUnit)
    local pg = UnitGUID(petUnit)
    local og = UnitGUID(ownerUnit)
    if pg and og then petOwner[pg] = og end
end

local function RescanPets()
    MapUnitPet("pet", "player")
    if IsInRaid() then
        for i = 1, 40 do MapUnitPet("raidpet" .. i, "raid" .. i) end
    else
        for i = 1, 4 do MapUnitPet("partypet" .. i, "party" .. i) end
    end
end

-- Resolve a combat-log source to the GUID we should credit (player, or the
-- owner of a group pet/guardian when known).
local function ResolveSource(guid, flags)
    if not guid then return nil end
    if band and flags and band(flags, F_TYPE_PETGUARD) > 0 then
        return petOwner[guid] or guid  -- unknown owner -> credit the pet itself
    end
    return guid
end

-------------------------------------------------------------------------------
--  Combat-log parser
-------------------------------------------------------------------------------
local function ParseCLEU(_, sub, _, srcGUID, srcName, srcFlags, _, dstGUID, _, _, _, ...)
    -- Pet ownership: a group member summoning a pet/guardian.
    if sub == "SPELL_SUMMON" then
        if srcGUID and dstGUID and band and srcFlags and band(srcFlags, F_AFF_GROUP) > 0 then
            petOwner[dstGUID] = srcGUID
        end
        return
    end

    local isDamage = DAMAGE_SUBEVENTS[sub]
    local isHeal   = not isDamage and HEAL_SUBEVENTS[sub]
    if not (isDamage or isHeal) then return end

    -- Only track friendly group members (and their pets/guardians).
    if not (band and srcFlags and band(srcFlags, F_AFF_GROUP) > 0) then return end

    local guid = ResolveSource(srcGUID, srcFlags)
    if not guid then return end

    -- Resolve display name + class (works for players; pets keep their own name).
    local name, class = srcName, nil
    if GetPlayerInfoByGUID then
        local _, engClass, _, _, _, pname = GetPlayerInfoByGUID(guid)
        class = engClass
        if pname and pname ~= "" then name = pname end
    end

    if isDamage then
        local amount
        if sub == "SWING_DAMAGE" then
            amount = ...                -- arg 12: amount
        else
            amount = select(4, ...)     -- spellID, spellName, spellSchool, amount(15)
        end
        if type(amount) == "number" then
            AddAmount(guid, name, class, "damage", amount)
        end
    else -- heal
        local amt  = select(4, ...)     -- amount(15)
        local over = select(5, ...)     -- overhealing(16)
        if type(amt) == "number" then
            local eff = amt - (type(over) == "number" and over or 0)
            if eff > 0 then AddAmount(guid, name, class, "healing", eff) end
        end
    end
end

-------------------------------------------------------------------------------
--  Segment lifecycle
-------------------------------------------------------------------------------
local function StartCombat()
    if current.active then return end
    -- New fight: wipe the "current" segment, keep "overall".
    wipe(current.actors)
    current.start    = GetTime()
    current.endTime  = nil
    current.active   = true
    if not overall.start then overall.start = GetTime() end
    overall.active = true
end

local function EndCombat()
    if not current.active then return end
    current.active  = false
    current.endTime = GetTime()
    overall.active  = false
    if current.start then
        overall.combatTime = (overall.combatTime or 0) + (current.endTime - current.start)
    end
end

local function ResetData()
    overall = NewSegment()
    current = NewSegment()
    wipe(petOwner)
end

-------------------------------------------------------------------------------
--  Visual helpers
-------------------------------------------------------------------------------
local FONT_FALLBACK = "Interface\\AddOns\\EllesmereUI-MoP\\media\\fonts\\Expressway.TTF"
local function FontPath()
    if EllesmereUI and EllesmereUI.GetFontPath then
        local ok, p = pcall(EllesmereUI.GetFontPath, "extras")
        if ok and p then return p end
    end
    return FONT_FALLBACK
end

local LSM = LibStub and LibStub("LibSharedMedia-3.0", true)
local function BarTexture()
    if LSM then
        return LSM:Fetch("statusbar", "EllesmereUI", true)
            or LSM:Fetch("statusbar", "Blizzard")
            or "Interface\\TargetingFrame\\UI-StatusBar"
    end
    return "Interface\\TargetingFrame\\UI-StatusBar"
end

local function ClassColor(class)
    local c = class and RAID_CLASS_COLORS and RAID_CLASS_COLORS[class]
    if c then return c.r, c.g, c.b end
    return 0.55, 0.55, 0.60
end

local function FormatNumber(n)
    if n >= 1e6 then return format("%.1fM", n / 1e6)
    elseif n >= 1e3 then return format("%.1fK", n / 1e3) end
    return format("%d", n)
end

-------------------------------------------------------------------------------
--  Window
-------------------------------------------------------------------------------
local win, bars

local function CreateBar(parent, index)
    local bar = CreateFrame("StatusBar", nil, parent)
    bar:SetStatusBarTexture(BarTexture())
    bar:SetMinMaxValues(0, 1)
    bar:SetValue(0)
    local bg = bar:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    bg:SetTexture(BarTexture())
    bg:SetVertexColor(0, 0, 0, 0.45)
    bar.bg = bg

    local left = bar:CreateFontString(nil, "OVERLAY")
    left:SetPoint("LEFT", 4, 0)
    left:SetFont(FontPath(), 11, "")
    left:SetShadowOffset(1, -1)
    bar.left = left

    local right = bar:CreateFontString(nil, "OVERLAY")
    right:SetPoint("RIGHT", -4, 0)
    right:SetFont(FontPath(), 11, "")
    right:SetShadowOffset(1, -1)
    bar.right = right
    return bar
end

local function LayoutBars()
    local n = db.maxBars
    for i = 1, n do
        local bar = bars[i]
        if not bar then bar = CreateBar(win.body, i); bars[i] = bar end
        bar:SetHeight(db.barHeight)
        bar:ClearAllPoints()
        if i == 1 then
            bar:SetPoint("TOPLEFT", win.body, "TOPLEFT", 0, 0)
            bar:SetPoint("TOPRIGHT", win.body, "TOPRIGHT", 0, 0)
        else
            bar:SetPoint("TOPLEFT", bars[i - 1], "BOTTOMLEFT", 0, -2)
            bar:SetPoint("TOPRIGHT", bars[i - 1], "BOTTOMRIGHT", 0, -2)
        end
        bar:Hide()
    end
    -- hide any surplus bars from a previous larger maxBars
    for i = n + 1, #bars do if bars[i] then bars[i]:Hide() end end
end

local _sortBuf = {}
local function RefreshDisplay()
    if not win or not win:IsShown() then return end
    local seg = (db.segment == "OVERALL") and overall or current
    local key = (db.mode == "HEALING") and "healing" or "damage"

    wipe(_sortBuf)
    local total = 0
    for _, a in pairs(seg.actors) do
        local v = a[key]
        if v and v > 0 then
            _sortBuf[#_sortBuf + 1] = a
            total = total + v
        end
    end
    sort(_sortBuf, function(x, y) return x[key] > y[key] end)

    local dur = ActorDuration(seg)
    local topVal = (_sortBuf[1] and _sortBuf[1][key]) or 1

    for i = 1, db.maxBars do
        local bar = bars[i]
        local a = _sortBuf[i]
        if a then
            local v = a[key]
            local r, g, b = ClassColor(a.class)
            bar:SetStatusBarColor(r, g, b)
            bar:SetValue(v / topVal)
            bar.left:SetText(format("%d. %s", i, a.name or "?"))
            local perSec = v / dur
            local pct = total > 0 and (v / total * 100) or 0
            bar.right:SetText(format("%s (%s)  %.0f%%", FormatNumber(v), FormatNumber(perSec), pct))
            bar:Show()
        else
            bar:Hide()
        end
    end

    -- header
    local modeTxt = (db.mode == "HEALING") and "HPS" or "DPS"
    local segTxt  = (db.segment == "OVERALL") and "Overall" or "Current"
    win.title:SetText(format("EllesmereUI %s  |cffaaaaaa%s|r", modeTxt, segTxt))
    win.total:SetText(format("%s  %s", FormatNumber(total), modeTxt))
end

local function SavePosition()
    local p, _, _, x, y = win:GetPoint()
    db.point = { p, floor(x + 0.5), floor(y + 0.5) }
end

local function ApplyPosition()
    win:ClearAllPoints()
    local p = db.point
    win:SetPoint(p[1] or "CENTER", UIParent, p[1] or "CENTER", p[2] or 0, p[3] or 0)
end

local function ApplyLock()
    win:SetMovable(not db.locked)
    win:EnableMouse(not db.locked)
    if win.lockBtn then win.lockBtn:SetText(db.locked and "U" or "L") end
end

local function MakeCtrlButton(parent, label, tip)
    local b = CreateFrame("Button", nil, parent)
    b:SetSize(16, 16)
    local fs = b:CreateFontString(nil, "OVERLAY")
    fs:SetAllPoints(); fs:SetFont(FontPath(), 11, "")
    fs:SetJustifyH("CENTER"); fs:SetText(label)
    b.SetText = function(_, t) fs:SetText(t) end
    b:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_TOP"); GameTooltip:SetText(tip); GameTooltip:Show()
    end)
    b:SetScript("OnLeave", function() GameTooltip:Hide() end)
    return b
end

local function CreateWindow()
    win = CreateFrame("Frame", "EllesmereUIDamageMeterFrame", UIParent)
    win:SetSize(db.width, db.height)
    win:SetFrameStrata("MEDIUM")
    win:SetClampedToScreen(true)
    win:RegisterForDrag("LeftButton")
    win:SetScript("OnDragStart", function(self) if not db.locked then self:StartMoving() end end)
    win:SetScript("OnDragStop", function(self) self:StopMovingOrSizing(); SavePosition() end)

    local bgt = win:CreateTexture(nil, "BACKGROUND")
    bgt:SetAllPoints(); bgt:SetTexture("Interface\\Buttons\\WHITE8x8")
    bgt:SetVertexColor(0.05, 0.05, 0.06, 0.85)
    if EllesmereUI and EllesmereUI.PP and EllesmereUI.PP.CreateBorder then
        pcall(EllesmereUI.PP.CreateBorder, win, 0, 0, 0, 1, 1, "OVERLAY", 7)
    end

    -- header row
    local header = CreateFrame("Frame", nil, win)
    header:SetPoint("TOPLEFT", 0, 0); header:SetPoint("TOPRIGHT", 0, 0)
    header:SetHeight(20)
    win.header = header

    win.title = header:CreateFontString(nil, "OVERLAY")
    win.title:SetPoint("LEFT", 6, 0)
    win.title:SetFont(FontPath(), 12, "")
    win.title:SetShadowOffset(1, -1)

    -- control buttons (right side of header): mode, segment, reset, lock
    local resetBtn = MakeCtrlButton(header, "R", "Reset")
    resetBtn:SetPoint("RIGHT", -4, 0)
    resetBtn:SetScript("OnClick", function() ResetData(); RefreshDisplay() end)
    win.resetBtn = resetBtn

    local lockBtn = MakeCtrlButton(header, "L", "Lock / Unlock")
    lockBtn:SetPoint("RIGHT", resetBtn, "LEFT", -2, 0)
    lockBtn:SetScript("OnClick", function() db.locked = not db.locked; ApplyLock() end)
    win.lockBtn = lockBtn

    local segBtn = MakeCtrlButton(header, "C", "Segment: Current / Overall")
    segBtn:SetPoint("RIGHT", lockBtn, "LEFT", -2, 0)
    segBtn:SetScript("OnClick", function()
        db.segment = (db.segment == "OVERALL") and "CURRENT" or "OVERALL"
        segBtn:SetText(db.segment == "OVERALL" and "O" or "C"); RefreshDisplay()
    end)
    segBtn:SetText(db.segment == "OVERALL" and "O" or "C")
    win.segBtn = segBtn

    local modeBtn = MakeCtrlButton(header, "D", "Mode: Damage / Healing")
    modeBtn:SetPoint("RIGHT", segBtn, "LEFT", -2, 0)
    modeBtn:SetScript("OnClick", function()
        db.mode = (db.mode == "HEALING") and "DAMAGE" or "HEALING"
        modeBtn:SetText(db.mode == "HEALING" and "H" or "D"); RefreshDisplay()
    end)
    modeBtn:SetText(db.mode == "HEALING" and "H" or "D")
    win.modeBtn = modeBtn

    -- footer total
    win.total = win:CreateFontString(nil, "OVERLAY")
    win.total:SetPoint("BOTTOMLEFT", 6, 4)
    win.total:SetFont(FontPath(), 11, "")
    win.total:SetTextColor(0.8, 0.8, 0.85)

    -- body (bars container)
    local body = CreateFrame("Frame", nil, win)
    body:SetPoint("TOPLEFT", header, "BOTTOMLEFT", 4, -2)
    body:SetPoint("BOTTOMRIGHT", -4, 16)
    win.body = body

    bars = {}
    LayoutBars()
    ApplyPosition()
    ApplyLock()
end

-------------------------------------------------------------------------------
--  Refresh ticker
-------------------------------------------------------------------------------
local _acc = 0
local function OnUpdate(_, dt)
    _acc = _acc + dt
    if _acc >= 0.5 then _acc = 0; RefreshDisplay() end
end

-------------------------------------------------------------------------------
--  Public toggle + slash
-------------------------------------------------------------------------------
local function ToggleWindow(show)
    if not win then return end
    if show == nil then show = not win:IsShown() end
    db.shown = show
    if show then win:Show(); RefreshDisplay() else win:Hide() end
end

SLASH_EUIDM1 = "/euidm"
SLASH_EUIDM2 = "/euimeter"
SlashCmdList["EUIDM"] = function(msg)
    msg = (msg or ""):lower():gsub("%s+", "")
    if msg == "reset" then
        ResetData(); RefreshDisplay()
    elseif msg == "lock" then
        db.locked = true; ApplyLock()
    elseif msg == "unlock" then
        db.locked = false; ApplyLock()
    elseif msg == "heal" or msg == "healing" then
        db.mode = "HEALING"; if win then win.modeBtn:SetText("H") end; RefreshDisplay()
    elseif msg == "dmg" or msg == "damage" then
        db.mode = "DAMAGE"; if win then win.modeBtn:SetText("D") end; RefreshDisplay()
    else
        ToggleWindow()
    end
end

-------------------------------------------------------------------------------
--  Events
-------------------------------------------------------------------------------
local ef = CreateFrame("Frame")
ef:RegisterEvent("ADDON_LOADED")
ef:RegisterEvent("PLAYER_LOGIN")
ef:SetScript("OnEvent", function(self, event, arg1)
    if event == "ADDON_LOADED" and arg1 == ADDON then
        ApplyDefaults()
        return
    end

    if event == "PLAYER_LOGIN" then
        if not db then ApplyDefaults() end
        CreateWindow()
        if db.shown == false then win:Hide() end
        win:SetScript("OnUpdate", OnUpdate)
        RescanPets()

        self:RegisterEvent("COMBAT_LOG_EVENT_UNFILTERED")
        self:RegisterEvent("PLAYER_REGEN_DISABLED")
        self:RegisterEvent("PLAYER_REGEN_ENABLED")
        self:RegisterEvent("GROUP_ROSTER_UPDATE")
        self:RegisterEvent("UNIT_PET")
        return
    end

    if event == "COMBAT_LOG_EVENT_UNFILTERED" then
        if CLGetInfo then ParseCLEU(CLGetInfo()) end
        return
    end

    if event == "PLAYER_REGEN_DISABLED" then
        StartCombat()
    elseif event == "PLAYER_REGEN_ENABLED" then
        EndCombat()
    elseif event == "GROUP_ROSTER_UPDATE" or event == "UNIT_PET" then
        RescanPets()
    end
end)
