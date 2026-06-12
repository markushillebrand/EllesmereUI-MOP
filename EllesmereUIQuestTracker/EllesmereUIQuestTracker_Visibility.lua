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
-- The real quest lines are not reachable via WatchFrameLines or
-- WatchFrame_SetLine on this client, so instead of guessing the line structure
-- we measure the content extent directly: recurse the WatchFrame's frame tree
-- and find the lowest *visible* FontString that actually carries text. That is
-- robust regardless of how Blizzard nests the lines.
local function ScanLowestText(frame, low)
    if frame.GetRegions then
        for _, r in ipairs({ frame:GetRegions() }) do
            if r.GetText and r.IsShown and r:IsShown() then
                local t = r:GetText()
                if t and t ~= "" and r.GetBottom then
                    local b = r:GetBottom()
                    if b and (not low or b < low) then low = b end
                end
            end
        end
    end
    if frame.GetChildren then
        for _, c in ipairs({ frame:GetChildren() }) do
            if c.IsShown and c:IsShown() then
                low = ScanLowestText(c, low)
            end
        end
    end
    return low
end

local function GetLowestLineBottom()
    local wf = GetTracker()
    if not wf then return nil end
    return ScanLowestText(wf, nil)
end

local _resizePending = false
local function QueueResize()
    if _resizePending then return end
    _resizePending = true
    C_Timer.After(0.05, function()
        _resizePending = false
        if EQT.ResizeBGToContent then EQT.ResizeBGToContent() end
        if EQT.ApplyTrackerHeight then EQT.ApplyTrackerHeight() end
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
        -- Content gone. Keep the BG for a short grace period (avoids a blink
        -- during a quick track/untrack), then hide it for real if STILL empty.
        if not bg:IsShown() then
            bg._lastHeight = nil
            return
        end
        if not bg._hideCheck then
            bg._hideCheck = true
            C_Timer.After(0.2, function()
                bg._hideCheck = nil
                if GetLowestLineBottom() then
                    if EQT.ResizeBGToContent then EQT.ResizeBGToContent() end
                else
                    bg._lastHeight = nil
                    if bg:IsShown() then bg:Hide() end
                end
            end)
        end
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

-------------------------------------------------------------------------------
-- Re-sync the mover handle to the current content height.
--
-- MoP's WatchFrame is kept screen-tall by Blizzard, which actively overrides
-- SetHeight (verified: SetHeight(173) snapped back to ~921). So we do NOT try to
-- shrink the frame anymore. Instead the mover handle is sized to the content
-- (see getSize), and this function just nudges the unlock overlay to re-read
-- that size when the content changes. The frame stays tall but is invisible /
-- click-through below the content, so free-positioning works regardless.
-------------------------------------------------------------------------------
local function ApplyTrackerHeight()
    local wf = GetTracker()
    if not wf or not wf:IsShown() then return end
    -- Keep the proxy sized to the content and the WatchFrame pinned to it, so the
    -- mover handle stays content-sized and the content rides along on drag.
    if EQT.SyncProxy then EQT.SyncProxy() end
end
EQT.ApplyTrackerHeight = ApplyTrackerHeight

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
local _proxy

-- A small, content-sized proxy frame that the unlock mover actually moves. The
-- screen-tall WatchFrame is pinned to it (TOPLEFT->TOPLEFT) and rides along, so
-- the mover only ever deals with a small frame: no screen-tall overlay, no
-- clamping to the upper screen, and no center-vs-top jump on drag.
local function EnsureProxy()
    if _proxy then return _proxy end
    _proxy = CreateFrame("Frame", "EUI_QTProxy", UIParent)
    _proxy:SetSize(204, 150)
    return _proxy
end

-- Size the proxy to the current content extent (WatchFrame width; height =
-- top..lowest visible line). Falls back to a sane default before content loads.
local function ContentSize()
    local wf = GetTracker()
    local w = (wf and wf:GetWidth()) or 204
    if not w or w < 40 then w = 204 end
    local h = 150
    if wf then
        local top = wf:GetTop()
        local low = GetLowestLineBottom()
        if top and low then h = (top - low) + 8 end
    end
    if not h or h < 30 then h = 150 end
    if h > 700 then h = 700 end
    return w, h
end

local function SizeProxy()
    local p = EnsureProxy()
    local w, h = ContentSize()
    p:SetSize(w, h)
end

-- Mirror the WatchFrame's top-left onto the proxy's top-left, keeping the
-- WatchFrame anchored to UIParent (NOT to the proxy). Anchoring the WatchFrame
-- to a non-UIParent frame makes Blizzard's WatchFrame_Update do arithmetic on a
-- nil coordinate and throw, so we only ever COPY the position instead.
local function MirrorWatchToProxy()
    local wf = GetTracker()
    local p  = _proxy
    if not wf or not p or InCombatLockdown() then return end
    local l, t = p:GetLeft(), p:GetTop()
    if not l or not t then return end
    local wl, wt = wf:GetLeft(), wf:GetTop()
    if wl and wt and math.abs(wl - l) < 0.5 and math.abs(wt - t) < 0.5 then return end
    wf:ClearAllPoints()
    wf:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", l, t)
end
EQT.SyncProxy = function()
    if not _detached then return end
    SizeProxy()
    MirrorWatchToProxy()
end

local function DetachTracker()
    local wf = GetTracker()
    if not wf or _detached then return end
    if InCombatLockdown() then return end
    _detached = true
    wf.ignoreFramePositionManager = true
    -- The WatchFrame stays screen-tall (Blizzard forces its height), so screen
    -- clamping would pin it to the upper portion. Turn it off; the empty lower
    -- part may hang off-screen, which is fine since it is invisible.
    if wf.SetClampedToScreen then wf:SetClampedToScreen(false) end
    if wf:GetParent() ~= UIParent then wf:SetParent(UIParent) end
    -- Place the proxy where the WatchFrame currently sits, so nothing jumps.
    local p = EnsureProxy()
    local l, t = wf:GetLeft(), wf:GetTop()
    p:ClearAllPoints()
    if l and t then
        p:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", l, t)
    else
        p:SetPoint("TOPRIGHT", UIParent, "TOPRIGHT", -110, -260)
    end
    SizeProxy()
    -- Live-mirror the WatchFrame onto the proxy as it is dragged. Throttled and
    -- change-gated so it is essentially free when nothing moves.
    if not p._euiMirror then
        p._euiMirror = true
        local accum = 0
        p:SetScript("OnUpdate", function(_, e)
            accum = accum + e
            if accum < 0.02 then return end
            accum = 0
            MirrorWatchToProxy()
        end)
    end
    MirrorWatchToProxy()
end

local function ApplyTrackerPosition()
    local wf = GetTracker()
    if not wf then return end
    if InCombatLockdown() then return end
    DetachTracker()
    local p = EnsureProxy()
    local pos = EQT.DB().trackerPos
    if pos then
        p:ClearAllPoints()
        p:SetPoint(pos.point or "TOPLEFT", UIParent, pos.relPoint or "BOTTOMLEFT", pos.x or 0, pos.y or 0)
    end
    SizeProxy()
    MirrorWatchToProxy()
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
            getFrame = function() return EnsureProxy() end,
            getSize  = function()
                -- Blizzard keeps the WatchFrame screen-tall (~958px) and
                -- overrides SetHeight, so we do NOT use wf:GetHeight() here.
                -- Instead we size the mover handle to the actual visible content
                -- (top minus lowest visible line), which is what the user grabs.
                local wf = GetTracker()
                local w = (wf and wf:GetWidth()) or 204
                if not w or w < 40 then w = 204 end
                local h = 150
                if wf then
                    local top = wf:GetTop()
                    local low = GetLowestLineBottom()
                    if top and low then h = (top - low) + 8 end
                end
                if not h or h < 30 then h = 150 end
                if h > 700 then h = 700 end
                return w, h
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

    -- Option A is in place (ApplyTrackerHeight shrinks the WatchFrame to its
    -- content height), so the frame is no longer screen-tall and free-positioning
    -- works again: re-enable the detach + unlock mover. Out of combat we apply
    -- immediately; in combat we defer to PLAYER_REGEN_ENABLED.
    if InCombatLockdown() then
        local cf = CreateFrame("Frame")
        cf:RegisterEvent("PLAYER_REGEN_ENABLED")
        cf:SetScript("OnEvent", function(f)
            f:UnregisterAllEvents()
            ApplyTrackerPosition()
        end)
    else
        ApplyTrackerPosition()
    end
    RegisterMover()

    -- Resize the BG + tracker height whenever WatchFrame re-lays-out.
    if type(_G.WatchFrame_Update) == "function" then
        hooksecurefunc("WatchFrame_Update", function() QueueResize() end)
    end

    -- Recompute the content height when Blizzard (re)sets a line.
    if type(_G.WatchFrame_SetLine) == "function" then
        hooksecurefunc("WatchFrame_SetLine", function() QueueResize() end)
    end
    if type(_G.WatchFrame_OnSizeChanged) == "function" then
        hooksecurefunc("WatchFrame_OnSizeChanged", function() QueueResize() end)
    end

    if EllesmereUI and EllesmereUI.RegAccent then
        EllesmereUI.RegAccent({ type = "callback", fn = ApplyTopDivider })
    end

    local function SyncBGToTracker()
        if not _bgFrame then return end
        if wf:IsShown() then
            -- Let the content-aware sizer decide: it shows + sizes the BG when
            -- there are lines, and hides it when the tracker is empty.
            if EQT.ResizeBGToContent then EQT.ResizeBGToContent() end
        else
            _bgFrame:Hide()
        end
    end
    -- Engage EUI styling + content-height on login/zone WITHOUT calling
    -- Blizzard's WatchFrame_Update (taint-free): restyle whatever lines already
    -- exist and apply the content height. Closes the "stock design until you
    -- toggle a quest" gap and runs Option A's height pass on login.
    local function EngageEUI()
        SyncBGToTracker()
        if EQT.RestyleAll then EQT.RestyleAll() end
        if EQT.ResizeBGToContent then EQT.ResizeBGToContent() end
        if EQT.ApplyTrackerHeight then EQT.ApplyTrackerHeight() end
    end
    EngageEUI()
    C_Timer.After(0.1, EngageEUI)
    C_Timer.After(0.5, EngageEUI)
    C_Timer.After(1.5, EngageEUI)

    local evt = CreateFrame("Frame")
    evt:RegisterEvent("PLAYER_ENTERING_WORLD")
    evt:RegisterEvent("ZONE_CHANGED_NEW_AREA")
    evt:SetScript("OnEvent", function() UpdateVisibility(); EngageEUI() end)

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
