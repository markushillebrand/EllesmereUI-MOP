-------------------------------------------------------------------------------
-- EllesmereUIQuestTracker_Visibility.lua  (MoP Classic rewrite)
--
-- Visibility, suppression, mouseover and the custom background for MoP's
-- legacy WatchFrame (the retail ObjectiveTrackerFrame does not exist here).
--
-- Rules kept from the original:
--   * Never SetScript on the tracker -- HookScript / hooksecurefunc only.
--   * The background is our own UIParent-parented frame anchored to the
--     tracker's bounds, never a child of it.
--   * Visibility composes the user's mode (always/combat/mouseover/...) with
--     cross-module suppression and a hard raid/arena auto-hide.
-------------------------------------------------------------------------------
local _, ns = ...
local EQT = ns.EQT

local _eqtSuppressed = false
local _bgFrame

local function GetTracker() return _G.WatchFrame end

-------------------------------------------------------------------------------
-- Raid/arena auto-hide
-------------------------------------------------------------------------------
local function ShouldAutoHide()
    local _, instanceType = GetInstanceInfo()
    return instanceType == "raid" or instanceType == "arena"
end

-- Suspend/resume QT event frames (populated by the QoL module) so quest
-- events don't burn work while the tracker is hidden.
local _eventsSuspended = false
local function SuspendQTEvents()
    if _eventsSuspended then return end
    _eventsSuspended = true
    if EQT._eventFrames then
        for _, f in ipairs(EQT._eventFrames) do f:UnregisterAllEvents() end
    end
end
local function ResumeQTEvents()
    if not _eventsSuspended then return end
    _eventsSuspended = false
    if EQT._eventFrames and EQT._eventRegistrations then
        for i, f in ipairs(EQT._eventFrames) do
            local evts = EQT._eventRegistrations[i]
            if evts then for _, ev in ipairs(evts) do f:RegisterEvent(ev) end end
        end
    end
end

function EQT.ApplySuppression(on)
    _eqtSuppressed = on and true or false
    if _eqtSuppressed then SuspendQTEvents() else ResumeQTEvents() end
    if EQT.UpdateVisibility then EQT.UpdateVisibility() end
end

-------------------------------------------------------------------------------
-- Show / hide hooks
-------------------------------------------------------------------------------
local _showHookInstalled = false
local function InstallShowHook()
    if _showHookInstalled then return end
    local wf = GetTracker()
    if not wf then return end
    _showHookInstalled = true
    hooksecurefunc(wf, "Show", function(self)
        if _eqtSuppressed then return end
        if ShouldAutoHide() then self:Hide() end
    end)
    wf:HookScript("OnHide", function() if _bgFrame then _bgFrame:Hide() end end)
    wf:HookScript("OnShow", function()
        if _eqtSuppressed then return end
        if EQT.ResizeBGToContent then EQT.ResizeBGToContent() end
    end)
end

-------------------------------------------------------------------------------
-- Visibility evaluation
-------------------------------------------------------------------------------
local function UpdateVisibility()
    InstallShowHook()
    local wf = GetTracker()
    if not wf then return end

    if ShouldAutoHide() then
        SuspendQTEvents()
        wf:Hide()
        if _bgFrame then _bgFrame:Hide() end
        return
    end

    ResumeQTEvents()
    if not wf:IsShown() then wf:Show() end

    local cfg = EQT.DB()
    local vis = true
    if EllesmereUI and EllesmereUI.EvalVisibility then
        vis = EllesmereUI.EvalVisibility(cfg)
    end

    local alpha
    if _eqtSuppressed or vis == false then
        alpha = 0
    elseif vis == "mouseover" then
        alpha = 0
    else
        alpha = 1
    end

    wf:SetAlpha(alpha)
    if _bgFrame then _bgFrame:SetAlpha(alpha) end
    if EQT.ResizeBGToContent then EQT.ResizeBGToContent() end
end
EQT.UpdateVisibility = UpdateVisibility
function EQT.RefreshStateDriver() UpdateVisibility() end

-------------------------------------------------------------------------------
-- Background frame (own frame anchored to the tracker)
-------------------------------------------------------------------------------
local function EnsureBG()
    if _bgFrame then return _bgFrame end
    local wf = GetTracker()
    if not wf then return nil end
    _bgFrame = CreateFrame("Frame", "EllesmereUIQTBackground", UIParent)
    _bgFrame:SetFrameStrata(wf:GetFrameStrata() or "LOW")
    _bgFrame:SetFrameLevel(math.max(0, (wf:GetFrameLevel() or 1) - 1))
    _bgFrame:SetPoint("TOPLEFT",  wf, "TOPLEFT",  -6, -30)
    _bgFrame:SetPoint("BOTTOMRIGHT", wf, "TOPRIGHT", 11, -60)
    local tex = _bgFrame:CreateTexture(nil, "BACKGROUND")
    tex:SetAllPoints()
    _bgFrame._tex = tex
    local divider = _bgFrame:CreateTexture(nil, "OVERLAY")
    divider:SetPoint("TOPLEFT",  wf, "TOPLEFT",  -6, -30)
    divider:SetPoint("TOPRIGHT", wf, "TOPRIGHT", 11, -30)
    _bgFrame._divider = divider
    return _bgFrame
end

local function ApplyTopDivider()
    local bg = _bgFrame
    if not bg or not bg._divider then return end
    local tex = bg._divider
    if EQT.Cfg("showTopLine") == false then tex:Hide(); return end
    local PP_CORE = EllesmereUI and EllesmereUI.PP
    local PP_SEC  = EllesmereUI and EllesmereUI.PanelPP
    if PP_SEC and PP_SEC.DisablePixelSnap then PP_SEC.DisablePixelSnap(tex) end
    local perfect = (PP_CORE and PP_CORE.perfect) or (PP_SEC and PP_SEC.mult) or 1
    local wf = GetTracker()
    local es = (wf and wf.GetEffectiveScale and wf:GetEffectiveScale()) or 1
    local onePixel = (es and es > 0) and (perfect / es) or (PP_SEC and PP_SEC.mult) or 1
    tex:SetHeight(onePixel)
    local eg = EllesmereUI and EllesmereUI.ELLESMERE_GREEN
    local r, g, b = (eg and eg.r) or 0.047, (eg and eg.g) or 0.824, (eg and eg.b) or 0.624
    tex:SetColorTexture(r, g, b, 1)
    tex:Show()
end

-- Lowest visible WatchFrame line, used to size the BG to real content.
local function GetLowestLineBottom()
    local lines = _G.WatchFrameLines
    if not lines or not lines.GetChildren then return nil end
    local lowest
    local kids = { lines:GetChildren() }
    for _, f in ipairs(kids) do
        if f and f.IsShown and f:IsShown() and f.GetBottom then
            local b = f:GetBottom()
            if b and (not lowest or b < lowest) then lowest = b end
        end
    end
    return lowest
end

local _resizePending = false
local function QueueResize()
    if _resizePending then return end
    _resizePending = true
    C_Timer.After(0.05, function()
        _resizePending = false
        if EQT.ResizeBGToContent then EQT.ResizeBGToContent() end
    end)
end
EQT.QueueResize = QueueResize

local function ResizeBGToContent()
    local bg = _bgFrame
    local wf = GetTracker()
    if not bg or not wf then return end
    if not wf:IsShown() then
        if bg:IsShown() then bg:Hide() end
        return
    end
    -- Hide chrome during active Challenge Mode (scenario blocks, not quests).
    if C_ChallengeMode and C_ChallengeMode.IsChallengeModeActive
       and C_ChallengeMode.IsChallengeModeActive() then
        if bg:IsShown() then bg:Hide() end
        return
    end
    local lowestBottom = GetLowestLineBottom()
    if not lowestBottom then
        if bg._lastHeight then
            -- keep last size briefly to avoid blink during track/untrack
            if not bg._hideCheck then
                bg._hideCheck = true
                C_Timer.After(0.2, function()
                    bg._hideCheck = nil
                    if EQT.ResizeBGToContent then EQT.ResizeBGToContent() end
                end)
            end
            return
        end
        if bg:IsShown() then bg:Hide() end
        return
    end
    bg._hideCheck = nil
    if not bg:IsShown() then bg:Show() end
    local wfTop = wf:GetTop()
    if wfTop then
        local h = wfTop - 30 - lowestBottom + 15
        if h < 1 then h = 1 end
        bg:ClearAllPoints()
        bg:SetPoint("TOPLEFT",  wf, "TOPLEFT",  -6, -30)
        bg:SetPoint("TOPRIGHT", wf, "TOPRIGHT", 11, -30)
        bg:SetHeight(h)
        bg._lastHeight = h
    end
end
EQT.ResizeBGToContent = ResizeBGToContent

function EQT.ApplyBackground()
    local bg = EnsureBG()
    if not bg then return end
    local cfg = EQT.DB()
    bg._tex:SetColorTexture(cfg.bgR or 0, cfg.bgG or 0, cfg.bgB or 0, cfg.bgAlpha or 0.5)
    ResizeBGToContent()
    ApplyTopDivider()
end

-------------------------------------------------------------------------------
-- Init
-------------------------------------------------------------------------------
-------------------------------------------------------------------------------
-- Positioning / Unlock Mode
--
-- WatchFrame lives inside UIParentRightManagedFrameContainer and is positioned
-- by that container's :Layout(). To let the user move it we reparent it to
-- UIParent (removing it from the container's child layout) and pin it to its
-- current on-screen spot, then drive it via the core unlock system. Positions
-- are stored CENTER/CENTER vs UIParent to match the core's convention.
-------------------------------------------------------------------------------
local _detached = false

local function PinToCurrent(wf)
    local es  = wf:GetEffectiveScale() or 1
    local ues = UIParent:GetEffectiveScale() or 1
    local wcx, wcy = wf:GetCenter()
    local ucx, ucy = UIParent:GetCenter()
    wf:ClearAllPoints()
    if wcx and ucx and ues > 0 then
        local offX = (wcx * es - ucx * ues) / ues
        local offY = (wcy * es - ucy * ues) / ues
        wf:SetPoint("CENTER", UIParent, "CENTER", offX, offY)
    else
        wf:SetPoint("TOPRIGHT", UIParent, "TOPRIGHT", -110, -260)
    end
end

local function DetachTracker()
    local wf = GetTracker()
    if not wf or _detached then return end
    if InCombatLockdown() then return end
    _detached = true
    wf.ignoreFramePositionManager = true
    local cur = wf:GetParent()
    if cur ~= UIParent then
        PinToCurrent(wf)            -- capture spot before reparent
        wf:SetParent(UIParent)
        PinToCurrent(wf)            -- re-pin in UIParent space
    end
end

local function ApplyTrackerPosition()
    local wf = GetTracker()
    if not wf then return end
    if InCombatLockdown() then return end
    DetachTracker()
    local pos = EQT.DB().trackerPos
    if not pos then return end       -- nil = leave at detached default
    wf:ClearAllPoints()
    wf:SetPoint(pos.point or "CENTER", UIParent, pos.relPoint or "CENTER", pos.x or 0, pos.y or 0)
end
EQT.ApplyTrackerPosition = ApplyTrackerPosition

local function RegisterMover()
    if not (EllesmereUI and EllesmereUI.RegisterUnlockElements and EllesmereUI.MakeUnlockElement) then return end
    local MK = EllesmereUI.MakeUnlockElement
    EllesmereUI:RegisterUnlockElements({
        MK({
            key      = "EUI_QuestTracker",
            label    = "Quest Tracker",
            group    = "Quest Tracker",
            order    = 600,
            noResize = true,
            noAnchorTo = true,
            -- The legacy WatchFrame is nearly screen-height; sizing the unlock
            -- mover from its real height makes a screen-tall, clamped overlay
            -- that can only slide horizontally. Tell the core mover to size
            -- itself from getSize() (content height) instead.
            sizeFromGetSize = true,
            getFrame = function() return GetTracker() end,
            getSize  = function()
                -- Fixed, stable size for the unlock mover. The legacy WatchFrame
                -- is screen-tall and the content-background height fluctuates
                -- (shown/hidden as lines change), which made the mover oscillate
                -- and jump away from the cursor on hover. A constant height keeps
                -- the handle steady and grabbable in both axes.
                local wf = GetTracker()
                local w = (wf and wf:GetWidth()) or 204
                if not w or w < 40 then w = 204 end
                return w, 150
            end,
            isHidden = function() return EQT.Cfg("enabled") == false end,
            savePos  = function(_, point, relPoint, x, y)
                EQT.DB().trackerPos = { point = point, relPoint = relPoint, x = x, y = y }
                if not EllesmereUI._unlockActive then ApplyTrackerPosition() end
            end,
            loadPos  = function() return EQT.DB().trackerPos end,
            clearPos = function() EQT.DB().trackerPos = nil end,
            applyPos = function() ApplyTrackerPosition() end,
        }),
    })
end

function EQT.InitVisibility()
    local wf = GetTracker()
    if not wf then return end

    EnsureBG()
    EQT.ApplyBackground()
    InstallShowHook()

    -- NOTE: Free-positioning is disabled for now. MoP's legacy WatchFrame is
    -- screen-tall (~960px), so detaching it only ever let it sit in the top
    -- portion of the screen (clamped) and made the unlock handle oscillate on
    -- hover. Until a proper content-height rewrite lands, leave the WatchFrame
    -- in Blizzard's managed position and skip the unlock mover. Styling,
    -- background, visibility and mouseover below all stay active.
    -- (ApplyTrackerPosition / DetachTracker / RegisterMover intentionally skipped)

    -- Resize the BG whenever WatchFrame re-lays-out or changes size.
    if type(_G.WatchFrame_Update) == "function" then
        hooksecurefunc("WatchFrame_Update", function() QueueResize() end)
    end
    if type(_G.WatchFrame_OnSizeChanged) == "function" then
        hooksecurefunc("WatchFrame_OnSizeChanged", function() QueueResize() end)
    end

    if EllesmereUI and EllesmereUI.RegAccent then
        EllesmereUI.RegAccent({ type = "callback", fn = ApplyTopDivider })
    end

    local function SyncBGToTracker()
        if not _bgFrame then return end
        if wf:IsShown() then _bgFrame:Show() else _bgFrame:Hide() end
    end
    SyncBGToTracker()
    C_Timer.After(0.1, SyncBGToTracker)
    C_Timer.After(0.5, SyncBGToTracker)

    local evt = CreateFrame("Frame")
    evt:RegisterEvent("PLAYER_ENTERING_WORLD")
    evt:RegisterEvent("ZONE_CHANGED_NEW_AREA")
    evt:SetScript("OnEvent", function() UpdateVisibility(); SyncBGToTracker() end)

    if EllesmereUI and EllesmereUI.RegisterVisibilityUpdater then
        EllesmereUI.RegisterVisibilityUpdater(function()
            if _eqtSuppressed then return end
            UpdateVisibility()
        end)
    end

    if EllesmereUI and EllesmereUI.RegisterMouseoverTarget then
        local moProxy = {}
        moProxy.IsShown = function() return wf and wf:IsShown() and not ShouldAutoHide() end
        moProxy.IsMouseOver = function()
            if wf and wf:IsMouseOver() then return true end
            if _bgFrame and _bgFrame:IsShown() and _bgFrame:IsMouseOver() then return true end
            return false
        end
        moProxy.GetRect = function()
            if _bgFrame and _bgFrame:IsShown() then return _bgFrame:GetRect() end
            if wf then return wf:GetRect() end
            return nil
        end
        moProxy.GetEffectiveScale = function() return (wf and wf:GetEffectiveScale()) or 1 end
        moProxy.SetAlpha = function(_, a)
            if wf then wf:SetAlpha(a) end
            if _bgFrame then _bgFrame:SetAlpha(a) end
        end
        moProxy.Show = function() end
        moProxy.Hide = function()
            if wf then wf:SetAlpha(0) end
            if _bgFrame then _bgFrame:SetAlpha(0) end
        end
        moProxy.EnableMouse = function() end
        EllesmereUI.RegisterMouseoverTarget(moProxy, function()
            if ShouldAutoHide() then return false end
            if _eqtSuppressed then return false end
            return EQT.DB().visibility == "mouseover"
        end)
    end

    C_Timer.After(0.5, UpdateVisibility)
end
