-------------------------------------------------------------------------------
--  EUI_DamageMeter_Options.lua  —  Settings page for the Damage Meter
--  Registers a page in the Core options sidebar. Most per-window settings
--  (mode, segment, position, size) live in each window's "M" menu; this page
--  exposes the shared defaults that apply across all meter windows.
-------------------------------------------------------------------------------
local ADDON_NAME, ns = ...

local PAGE_DISPLAY = "Damage Meter"

local initFrame = CreateFrame("Frame")
initFrame:RegisterEvent("PLAYER_LOGIN")
initFrame:SetScript("OnEvent", function(self)
    self:UnregisterEvent("PLAYER_LOGIN")

    if not EllesmereUI or not EllesmereUI.RegisterModule then return end

    local function BuildPage(pageName, parent, yOffset)
        local W = EllesmereUI.Widgets
        local y = yOffset
        local _, h

        if EllesmereUI.ClearContentHeader then EllesmereUI:ClearContentHeader() end
        parent._showRowDivider = true

        -- ── GENERAL ──────────────────────────────────────────────────────
        _, h = W:SectionHeader(parent, "DAMAGE METER", y); y = y - h

        _, h = W:Toggle(parent, "Lock all windows", y,
            function() return _G.EllesmereUI_DM_GetLockedDefault and EllesmereUI_DM_GetLockedDefault() or false end,
            function(v) if _G.EllesmereUI_DM_SetLockedAll then EllesmereUI_DM_SetLockedAll(v) end end)
        y = y - h

        _, h = W:Slider(parent, "Max bars per window", y, 3, 20, 1,
            function() return _G.EllesmereUI_DM_GetMaxBars and EllesmereUI_DM_GetMaxBars() or 8 end,
            function(v) if _G.EllesmereUI_DM_SetMaxBarsAll then EllesmereUI_DM_SetMaxBarsAll(v) end end)
        y = y - h

        _, h = W:Spacer(parent, y, 10); y = y - h

        -- Hint: most options are reachable from each window's "M" menu.
        if W.Note then
            _, h = W:Note(parent,
                "Mode, segment, position and size are set per window via the \"M\" menu.", y)
            y = y - h
        end

        _, h = W:Spacer(parent, y, 6); y = y - h

        _, h = W:WideButton(parent, "Reset Damage Meter", y,
            function()
                EllesmereUI:ShowConfirmPopup({
                    title       = "Reset Damage Meter",
                    message     = "This resets all Damage Meter windows and settings, then reloads your UI.",
                    confirmText = "Reset",
                    cancelText  = "Cancel",
                    onConfirm   = function()
                        if _G.EllesmereUI_DM_ResetAll then EllesmereUI_DM_ResetAll() end
                    end,
                })
            end)
        y = y - h

        _, h = W:Spacer(parent, y, 20); y = y - h

        parent:SetHeight(math.abs(y - yOffset))
    end

    EllesmereUI:RegisterModule("EllesmereUIDamageMeter", {
        title       = "Damage Meter",
        description = "Real-time damage, healing and damage-taken meter with multiple windows.",
        icon_on  = "Interface\\AddOns\\EllesmereUI-MoP\\media\\icons\\sidebar\\dm-ig-on.png",
        icon_off = "Interface\\AddOns\\EllesmereUI-MoP\\media\\icons\\sidebar\\dm-ig.png",
        pages    = { PAGE_DISPLAY },
        buildPage = BuildPage,
        onReset  = function()
            if _G.EllesmereUI_DM_ResetAll then EllesmereUI_DM_ResetAll() end
        end,
    })
end)
