-------------------------------------------------------------------------------
--  EllesmereUIBags_GuildBank.lua
--  Full-featured styled guild bank window matching the EllesmereUI bank look.
--  Drives all interaction through the standard guild-bank API (MoP 5.5.x).
--    * item tabs with grid, quality borders, lock overlay, search
--    * deposit/withdraw items, stack split, auto-withdraw to bags
--    * money deposit/withdraw with limit handling
--    * buy new tab, permissions (viewable / deposit / remaining withdrawals)
--    * per-tab item log, money log, editable tab info text
-------------------------------------------------------------------------------
local EUI = EllesmereUI

-------------------------------------------------------------------------------
--  Constants (mirrors the bank module for a consistent look)
-------------------------------------------------------------------------------
local SLOT       = 34
local SPACING    = 4
local COLS       = 14
local ROWS       = 7                       -- 14 x 7 = 98
local SLOTS_PER_TAB = (MAX_GUILDBANK_SLOTS_PER_TAB or 98)
local MAX_TABS   = (MAX_GUILDBANK_TABS or 8)
local MONEYLOG_TAB = MAX_TABS + 1
local HEADER_H   = 35
local FOOTER_H   = 32
local SIDEBAR_W  = 160
local PAD        = 10

local PP = EUI and EUI.PP
local BANK_FONT = (EUI.GetFontPath and EUI.GetFontPath()) or "Fonts\\FRIZQT__.TTF"
local function SetF(fs, size) fs:SetFont(BANK_FONT, size, "") end
local function Accent()
    if EUI.GetAccentColor then return EUI.GetAccentColor() end
    return 0.05, 0.82, 0.62
end
local function Money(copper)
    if GetCoinTextureString then return GetCoinTextureString(copper or 0) end
    return (math.floor((copper or 0) / 10000)) .. "g"
end
local function QualityColor(q)
    local c = q and ITEM_QUALITY_COLORS and ITEM_QUALITY_COLORS[q]
    if c then return c.r, c.g, c.b end
    return 0.3, 0.3, 0.3
end

-- Runtime state
local _tab    = 1                 -- selected item tab
local _mode   = "GRID"            -- GRID | ITEMLOG | INFO | MONEYLOG
local _filter = ""
local _slots  = {}
local _tabBtns = {}
local _specialBtns = {}

-- Forward declarations
local RefreshGrid, RefreshMain, RefreshFooter, RebuildSidebar, RefreshAll
local SelectTab, SetMode

-------------------------------------------------------------------------------
--  Main frame
-------------------------------------------------------------------------------
local GB = CreateFrame("Frame", "EUI_GuildBankFrame", UIParent)
GB:Hide()
GB:SetFrameStrata("HIGH")
GB:SetClampedToScreen(true)
GB:SetMovable(true); GB:EnableMouse(true)
GB:RegisterForDrag("LeftButton")
GB:SetScript("OnDragStart", function(self) self:StartMoving() end)
GB:SetScript("OnDragStop", function(self) self:StopMovingOrSizing() end)

local gridW = COLS * (SLOT + SPACING) - SPACING
local gridH = ROWS * (SLOT + SPACING) - SPACING
GB:SetSize(SIDEBAR_W + gridW + PAD * 3, HEADER_H + gridH + FOOTER_H + PAD * 2)
GB:SetPoint("TOPLEFT", UIParent, "TOPLEFT", 20, -110)

local bg = GB:CreateTexture(nil, "BACKGROUND")
bg:SetAllPoints(); bg:SetColorTexture(0.05, 0.05, 0.06, 0.92)
if PP and PP.CreateBorder then pcall(PP.CreateBorder, GB, 0, 0, 0, 1, 1, "OVERLAY", 7) end

-------------------------------------------------------------------------------
--  Header
-------------------------------------------------------------------------------
local header = CreateFrame("Frame", nil, GB)
header:SetPoint("TOPLEFT", 0, 0); header:SetPoint("TOPRIGHT", 0, 0); header:SetHeight(HEADER_H)
local hdrBg = header:CreateTexture(nil, "BACKGROUND", nil, 1)
hdrBg:SetAllPoints(); hdrBg:SetColorTexture(0, 0, 0, 0.35)

local title = header:CreateFontString(nil, "OVERLAY")
SetF(title, 14); title:SetPoint("LEFT", header, "LEFT", PAD, 0); title:SetText("Gildenbank")
do local r, g, b = Accent(); title:SetTextColor(r, g, b) end

local hdrCount = header:CreateFontString(nil, "OVERLAY")
SetF(hdrCount, 11); hdrCount:SetPoint("LEFT", title, "RIGHT", 10, 0); hdrCount:SetTextColor(0.7, 0.7, 0.7)

local closeBtn = CreateFrame("Button", nil, header)
closeBtn:SetSize(20, 20); closeBtn:SetPoint("RIGHT", header, "RIGHT", -8, 0)
local cx = closeBtn:CreateFontString(nil, "OVERLAY")
SetF(cx, 16); cx:SetPoint("CENTER"); cx:SetText("x"); cx:SetTextColor(0.7, 0.7, 0.7)
closeBtn:SetScript("OnEnter", function() cx:SetTextColor(1, 1, 1) end)
closeBtn:SetScript("OnLeave", function() cx:SetTextColor(0.7, 0.7, 0.7) end)
closeBtn:SetScript("OnClick", function() if CloseGuildBankFrame then CloseGuildBankFrame() end end)

-- Search box (mirrors bank)
local search = CreateFrame("EditBox", nil, header)
search:SetSize(150, 18); search:SetPoint("RIGHT", closeBtn, "LEFT", -8, 0)
search:SetAutoFocus(false); SetF(search, 11); search:SetTextInsets(6, 6, 0, 0)
local sBg = search:CreateTexture(nil, "BACKGROUND"); sBg:SetAllPoints(); sBg:SetColorTexture(0, 0, 0, 0.4)
if PP and PP.CreateBorder then pcall(PP.CreateBorder, search, 0, 0, 0, 0.6, 1, "OVERLAY", 7) end
local sPlaceholder = search:CreateFontString(nil, "OVERLAY")
SetF(sPlaceholder, 11); sPlaceholder:SetPoint("LEFT", 6, 0); sPlaceholder:SetText("Suche...")
sPlaceholder:SetTextColor(0.5, 0.5, 0.5)
search:SetScript("OnTextChanged", function(self)
    local t = self:GetText() or ""
    sPlaceholder:SetShown(t == "")
    _filter = t:lower()
    if _mode == "GRID" then RefreshGrid() end
end)
search:SetScript("OnEscapePressed", function(self) self:SetText(""); self:ClearFocus() end)
search:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)

-- mode toggle buttons (Items / Log / Info) on the right of the title
local function MakeToggle(text, anchorRight)
    local b = CreateFrame("Button", nil, header)
    b:SetSize(46, 18)
    local lbl = b:CreateFontString(nil, "OVERLAY")
    SetF(lbl, 10); lbl:SetPoint("CENTER"); lbl:SetText(text)
    lbl:SetTextColor(0.7, 0.7, 0.7)
    b._lbl = lbl
    if PP and PP.CreateBorder then pcall(PP.CreateBorder, b, 0, 0, 0, 0.5, 1, "OVERLAY", 7) end
    b:SetScript("OnEnter", function(self) self._lbl:SetTextColor(1, 1, 1) end)
    b:SetScript("OnLeave", function(self) self._lbl:SetTextColor(self._on and select(1, Accent()) or 0.7,
        self._on and select(2, Accent()) or 0.7, self._on and select(3, Accent()) or 0.7) end)
    return b
end
local itemsTgl = MakeToggle("Items"); itemsTgl:SetPoint("LEFT", hdrCount, "RIGHT", 14, 0)
local logTgl   = MakeToggle("Log");   logTgl:SetPoint("LEFT", itemsTgl, "RIGHT", 4, 0)
local infoTgl  = MakeToggle("Info");  infoTgl:SetPoint("LEFT", logTgl, "RIGHT", 4, 0)
itemsTgl:SetScript("OnClick", function() SetMode("GRID") end)
logTgl:SetScript("OnClick", function() SetMode("ITEMLOG") end)
infoTgl:SetScript("OnClick", function() SetMode("INFO") end)

local function PaintToggles()
    local function paint(b, on)
        b._on = on
        local r, g, bl = Accent()
        b._lbl:SetTextColor(on and r or 0.7, on and g or 0.7, on and bl or 0.7)
    end
    local tabView = (_mode ~= "MONEYLOG")
    itemsTgl:SetShown(tabView); logTgl:SetShown(tabView); infoTgl:SetShown(tabView)
    paint(itemsTgl, _mode == "GRID")
    paint(logTgl, _mode == "ITEMLOG")
    paint(infoTgl, _mode == "INFO")
end

-------------------------------------------------------------------------------
--  Sidebar
-------------------------------------------------------------------------------
local sidebar = CreateFrame("Frame", nil, GB)
sidebar:SetPoint("TOPLEFT", header, "BOTTOMLEFT", 0, 0)
sidebar:SetPoint("BOTTOMLEFT", GB, "BOTTOMLEFT", 0, FOOTER_H)
sidebar:SetWidth(SIDEBAR_W)
local sbBg = sidebar:CreateTexture(nil, "BACKGROUND", nil, 2)
sbBg:SetAllPoints(); sbBg:SetColorTexture(0, 0, 0, 0.25)

local sbHdr = sidebar:CreateFontString(nil, "OVERLAY")
SetF(sbHdr, 10); sbHdr:SetPoint("TOPLEFT", sidebar, "TOPLEFT", 8, -8)
sbHdr:SetText("Tabs"); sbHdr:SetTextColor(0.5, 0.5, 0.5)

local function StyleSidebarBtn(btn)
    local sel = btn:CreateTexture(nil, "BACKGROUND")
    sel:SetAllPoints(); sel:SetColorTexture(Accent()); sel:SetAlpha(0.22); sel:Hide()
    btn._sel = sel
    local hl = btn:CreateTexture(nil, "HIGHLIGHT")
    hl:SetAllPoints(); hl:SetColorTexture(1, 1, 1, 0.06)
    local ic = btn:CreateTexture(nil, "ARTWORK")
    ic:SetSize(18, 18); ic:SetPoint("LEFT", 4, 0); ic:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    btn._icon = ic
    local nm = btn:CreateFontString(nil, "OVERLAY")
    SetF(nm, 11); nm:SetPoint("LEFT", ic, "RIGHT", 6, 0); nm:SetPoint("RIGHT", btn, "RIGHT", -22, 0)
    nm:SetJustifyH("LEFT"); nm:SetTextColor(0.85, 0.85, 0.85)
    btn._name = nm
    local cnt = btn:CreateFontString(nil, "OVERLAY")
    SetF(cnt, 10); cnt:SetPoint("RIGHT", btn, "RIGHT", -6, 0); cnt:SetTextColor(0.6, 0.6, 0.6)
    btn._count = cnt
end

-------------------------------------------------------------------------------
--  Main area (grid / log / info share this region)
-------------------------------------------------------------------------------
local mainArea = CreateFrame("Frame", nil, GB)
mainArea:SetPoint("TOPLEFT", sidebar, "TOPRIGHT", PAD, -PAD)
mainArea:SetSize(gridW, gridH)

-- Grid
local grid = CreateFrame("Frame", nil, mainArea)
grid:SetAllPoints()

-- Log (scrolling message frame)
local logFrame = CreateFrame("ScrollingMessageFrame", nil, mainArea)
logFrame:SetAllPoints()
logFrame:SetFontObject(GameFontHighlightSmall)
SetF(logFrame, 11)
logFrame:SetJustifyH("LEFT")
logFrame:SetFading(false)
logFrame:SetMaxLines(250)
logFrame:SetHyperlinksEnabled(true)
logFrame:EnableMouseWheel(true)
logFrame:SetScript("OnMouseWheel", function(self, d)
    if d > 0 then self:ScrollUp() else self:ScrollDown() end
end)
logFrame:SetScript("OnHyperlinkClick", function(_, link, text, button)
    if SetItemRef then SetItemRef(link, text, button) end
end)
logFrame:Hide()

-- Info text
local infoFrame = CreateFrame("Frame", nil, mainArea)
infoFrame:SetAllPoints(); infoFrame:Hide()
local infoScroll = CreateFrame("ScrollFrame", nil, infoFrame)
infoScroll:SetPoint("TOPLEFT", 0, 0); infoScroll:SetPoint("BOTTOMRIGHT", -4, 24)
local infoEdit = CreateFrame("EditBox", nil, infoScroll)
infoEdit:SetMultiLine(true); infoEdit:SetAutoFocus(false); infoEdit:SetWidth(gridW - 8)
infoEdit:SetHeight(gridH - 30)
SetF(infoEdit, 12); infoEdit:SetTextColor(0.9, 0.9, 0.9)
infoEdit:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
infoScroll:SetScrollChild(infoEdit)
local infoSave = CreateFrame("Button", nil, infoFrame)
infoSave:SetSize(90, 20); infoSave:SetPoint("BOTTOMRIGHT", 0, 0)
local isl = infoSave:CreateFontString(nil, "OVERLAY"); SetF(isl, 11); isl:SetPoint("CENTER"); isl:SetText("Speichern")
do local r, g, b = Accent(); isl:SetTextColor(r, g, b) end
if PP and PP.CreateBorder then pcall(PP.CreateBorder, infoSave, 0, 0, 0, 0.6, 1, "OVERLAY", 7) end
infoSave:SetScript("OnClick", function()
    if SetGuildBankText then SetGuildBankText(_tab, infoEdit:GetText() or "") end
    infoEdit:ClearFocus()
end)

-------------------------------------------------------------------------------
--  Footer (guild money + withdraw/deposit buttons)
-------------------------------------------------------------------------------
local footer = CreateFrame("Frame", nil, GB)
footer:SetPoint("BOTTOMLEFT", 0, 0); footer:SetPoint("BOTTOMRIGHT", 0, 0); footer:SetHeight(FOOTER_H)
local ftBg = footer:CreateTexture(nil, "BACKGROUND", nil, 1)
ftBg:SetAllPoints(); ftBg:SetColorTexture(0, 0, 0, 0.35)

local guildMoney = footer:CreateFontString(nil, "OVERLAY")
SetF(guildMoney, 11); guildMoney:SetPoint("LEFT", footer, "LEFT", PAD, 0); guildMoney:SetTextColor(1, 1, 1)

local withdrawInfo = footer:CreateFontString(nil, "OVERLAY")
SetF(withdrawInfo, 10); withdrawInfo:SetTextColor(0.7, 0.7, 0.7)

local GOLD_R, GOLD_G, GOLD_B = 0.855, 0.722, 0.259
local function MakeMoneyBtn(label)
    local b = CreateFrame("Button", nil, footer)
    b:SetSize(70, 18)
    if PP and PP.CreateBorder then pcall(PP.CreateBorder, b, GOLD_R, GOLD_G, GOLD_B, 0.8, 1, "OVERLAY", 7) end
    local l = b:CreateFontString(nil, "OVERLAY"); SetF(l, 9); l:SetPoint("CENTER"); l:SetText(label)
    l:SetTextColor(GOLD_R, GOLD_G, GOLD_B, 0.85); b._lbl = l
    b:SetScript("OnEnter", function(self) self._lbl:SetTextColor(GOLD_R, GOLD_G, GOLD_B, 1) end)
    b:SetScript("OnLeave", function(self) self._lbl:SetTextColor(GOLD_R, GOLD_G, GOLD_B, 0.85) end)
    return b
end
local depositMoneyBtn  = MakeMoneyBtn("Einzahlen")
depositMoneyBtn:SetPoint("RIGHT", footer, "RIGHT", -PAD, 0)
local withdrawMoneyBtn = MakeMoneyBtn("Abheben")
withdrawMoneyBtn:SetPoint("RIGHT", depositMoneyBtn, "LEFT", -6, 0)
withdrawInfo:SetPoint("RIGHT", withdrawMoneyBtn, "LEFT", -10, 0)

local function AskAmount(titleText, onAccept)
    if EUI and EUI.ShowInputPopup then
        EUI:ShowInputPopup({
            title = titleText, message = "Betrag in Gold:", placeholder = "100",
            confirmText = ACCEPT, cancelText = CANCEL, modernBlizz = true,
            onConfirm = function(text)
                local g = tonumber(text)
                if g and g > 0 then onAccept(g * 10000) end
            end,
        })
        return
    end
    StaticPopupDialogs["EUI_GBANK_MONEY"] = StaticPopupDialogs["EUI_GBANK_MONEY"] or {
        text = "%s\nBetrag in Gold:", button1 = ACCEPT, button2 = CANCEL,
        hasEditBox = true, timeout = 0, whileDead = true, hideOnEscape = true,
        OnAccept = function(self) local g = tonumber(self.editBox:GetText())
            if g and g > 0 and self.data then self.data(g * 10000) end end,
        EditBoxOnEnterPressed = function(self) local p = self:GetParent()
            local g = tonumber(self:GetText()); if g and g > 0 and p.data then p.data(g * 10000) end
            p:Hide() end,
    }
    local dlg = StaticPopup_Show("EUI_GBANK_MONEY", titleText)
    if dlg then dlg.data = onAccept end
end

depositMoneyBtn:SetScript("OnClick", function()
    if StaticPopupDialogs and StaticPopupDialogs["GUILDBANK_DEPOSIT"] then
        StaticPopup_Show("GUILDBANK_DEPOSIT")
    else
        AskAmount("In Gildenbank einzahlen", function(copper)
            if DepositGuildBankMoney then DepositGuildBankMoney(copper) end
        end)
    end
end)
withdrawMoneyBtn:SetScript("OnClick", function()
    if CanWithdrawGuildBankMoney and not CanWithdrawGuildBankMoney() then return end
    if StaticPopupDialogs and StaticPopupDialogs["GUILDBANK_WITHDRAW"] then
        StaticPopup_Show("GUILDBANK_WITHDRAW")
    else
        AskAmount("Aus Gildenbank abheben", function(copper)
            if WithdrawGuildBankMoney then WithdrawGuildBankMoney(copper) end
        end)
    end
end)

-------------------------------------------------------------------------------
--  Slot buttons
-------------------------------------------------------------------------------
local function MakeSlot(index)
    local b = CreateFrame("Button", nil, grid)
    b:SetSize(SLOT, SLOT)
    local col = (index - 1) % COLS
    local row = math.floor((index - 1) / COLS)
    b:SetPoint("TOPLEFT", grid, "TOPLEFT", col * (SLOT + SPACING), -row * (SLOT + SPACING))

    local sbg = b:CreateTexture(nil, "BACKGROUND"); sbg:SetAllPoints(); sbg:SetColorTexture(0, 0, 0, 0.4)
    if PP and PP.CreateBorder then pcall(PP.CreateBorder, b, 0, 0, 0, 0.6, 1, "OVERLAY", 7) end

    local icon = b:CreateTexture(nil, "ARTWORK")
    icon:SetPoint("TOPLEFT", 1, -1); icon:SetPoint("BOTTOMRIGHT", -1, 1)
    icon:SetTexCoord(0.08, 0.92, 0.08, 0.92); b.icon = icon

    local lock = b:CreateTexture(nil, "OVERLAY")
    lock:SetAllPoints(); lock:SetColorTexture(0, 0, 0, 0.55); lock:Hide(); b.lock = lock

    local cnt = b:CreateFontString(nil, "OVERLAY"); SetF(cnt, 11)
    cnt:SetPoint("BOTTOMRIGHT", -2, 2); cnt:SetJustifyH("RIGHT"); b.count = cnt

    b:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    b.SplitStack = function(self, amt) if SplitGuildBankItem then SplitGuildBankItem(self.tab, self.slot, amt) end end
    b:SetScript("OnEnter", function(self)
        if not self.slot then return end
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        if GameTooltip.SetGuildBankItem then GameTooltip:SetGuildBankItem(self.tab, self.slot) end
        GameTooltip:Show()
    end)
    b:SetScript("OnLeave", function() GameTooltip:Hide() end)
    b:SetScript("OnClick", function(self, button)
        if not self.slot then return end
        if button == "LeftButton" and IsShiftKeyDown() then
            local _, count = GetGuildBankItemInfo(self.tab, self.slot)
            if count and count > 1 and OpenStackSplitFrame then
                OpenStackSplitFrame(count, self, "BOTTOMLEFT", "TOPLEFT")
                return
            end
        end
        if button == "RightButton" then
            if AutoStoreGuildBankItem then AutoStoreGuildBankItem(self.tab, self.slot) end
        else
            if PickupGuildBankItem then PickupGuildBankItem(self.tab, self.slot) end
        end
        if C_Timer and C_Timer.After then
            C_Timer.After(0.15, function() if GB:IsShown() and _mode == "GRID" then RefreshGrid() end end)
        end
    end)
    return b
end

local function EnsureSlots()
    for i = 1, SLOTS_PER_TAB do if not _slots[i] then _slots[i] = MakeSlot(i) end end
end

-------------------------------------------------------------------------------
--  Refresh: grid
-------------------------------------------------------------------------------
local function MatchesFilter(tab, slot)
    if _filter == "" then return true end
    local link = GetGuildBankItemLink and GetGuildBankItemLink(tab, slot)
    if not link then return false end
    local name = link:match("%[(.-)%]")
    return name and name:lower():find(_filter, 1, true) ~= nil
end

function RefreshGrid()
    EnsureSlots()
    local tab = _tab
    local used = 0
    local _, _, isViewable = GetGuildBankTabInfo and GetGuildBankTabInfo(tab)
    for i = 1, SLOTS_PER_TAB do
        local b = _slots[i]
        b.tab = tab; b.slot = i
        local texture, count, locked, _, quality
        if isViewable ~= false and GetGuildBankItemInfo then
            texture, count, locked, _, quality = GetGuildBankItemInfo(tab, i)
        end
        if texture then
            b.icon:SetTexture(texture); b.icon:Show()
            b.count:SetText((count and count > 1) and count or "")
            if PP and PP.SetBorderColor then
                local qr, qg, qb = QualityColor(quality)
                PP.SetBorderColor(b, qr, qg, qb, (quality and quality > 1) and 1 or 0.5)
            end
            b.icon:SetAlpha(MatchesFilter(tab, i) and 1 or 0.2)
            b.lock:SetShown(locked and true or false)
            used = used + 1
        else
            b.icon:SetTexture(nil); b.icon:Hide(); b.count:SetText("")
            b.lock:Hide(); b.icon:SetAlpha(1)
            if PP and PP.SetBorderColor then PP.SetBorderColor(b, 0, 0, 0, 0.6) end
        end
        b:Show()
    end
    -- remaining withdrawals for this tab in the header count
    local name, _, viewable, canDeposit, numW, remW = GetGuildBankTabInfo and GetGuildBankTabInfo(tab)
    local extra = ""
    if remW and numW and numW > 0 then extra = "   Abheb. " .. remW .. "/" .. numW end
    hdrCount:SetText(used .. " / " .. SLOTS_PER_TAB .. extra)
end
RefreshGrid = RefreshGrid

-------------------------------------------------------------------------------
--  Refresh: logs + info
-------------------------------------------------------------------------------
local function AgoText(y, mo, d, h)
    if y and y > 0 then return y .. "j" end
    if mo and mo > 0 then return mo .. "mo" end
    if d and d > 0 then return d .. "t" end
    return (h or 0) .. "h"
end

local function RefreshItemLog()
    logFrame:Clear()
    local tab = _tab
    local n = GetNumGuildBankTransactions and GetNumGuildBankTransactions(tab) or 0
    if n == 0 then logFrame:AddMessage("Keine Eintraege.", 0.6, 0.6, 0.6); return end
    for i = 1, n do
        local tp, who, link, count, t1, t2, y, mo, d, h = GetGuildBankTransaction(tab, i)
        who = who or UNKNOWN
        local when = "|cff808080(" .. AgoText(y, mo, d, h) .. ")|r"
        local msg
        if tp == "deposit" then
            msg = who .. " legt ab: " .. (link or "?") .. (count and count > 1 and (" x" .. count) or "")
        elseif tp == "withdraw" then
            msg = who .. " nimmt: " .. (link or "?") .. (count and count > 1 and (" x" .. count) or "")
        elseif tp == "move" then
            msg = who .. " verschiebt: " .. (link or "?") .. " (" .. (t1 or "?") .. " -> " .. (t2 or "?") .. ")"
        else
            msg = (who or "?") .. ": " .. (link or "?")
        end
        logFrame:AddMessage(when .. " " .. msg, 0.9, 0.9, 0.9)
    end
end

local function RefreshMoneyLog()
    logFrame:Clear()
    local n = GetNumGuildBankMoneyTransactions and GetNumGuildBankMoneyTransactions() or 0
    if n == 0 then logFrame:AddMessage("Keine Eintraege.", 0.6, 0.6, 0.6); return end
    for i = 1, n do
        local tp, who, amount, y, mo, d, h = GetGuildBankMoneyTransaction(i)
        who = who or UNKNOWN
        local when = "|cff808080(" .. AgoText(y, mo, d, h) .. ")|r"
        local verb = (tp == "deposit") and "zahlt ein" or (tp == "withdraw") and "hebt ab"
            or (tp == "repair") and "Reparatur" or (tp == "buyTab") and "kauft Tab" or tostring(tp)
        logFrame:AddMessage(when .. " " .. who .. " " .. verb .. " " .. Money(amount), 0.9, 0.9, 0.9)
    end
end

local function RefreshInfo()
    local txt = GetGuildBankText and GetGuildBankText(_tab) or ""
    infoEdit:SetText(txt or "")
    local canEdit = CanEditGuildBankTabInfo and CanEditGuildBankTabInfo(_tab)
    if infoEdit.SetEnabled then
        infoEdit:SetEnabled(canEdit and true or false)
    elseif canEdit then
        if infoEdit.Enable then infoEdit:Enable() end
    else
        if infoEdit.Disable then infoEdit:Disable() end
    end
    infoSave:SetShown(canEdit and true or false)
end

-------------------------------------------------------------------------------
--  Mode / tab switching
-------------------------------------------------------------------------------
function RefreshMain()
    grid:SetShown(_mode == "GRID")
    logFrame:SetShown(_mode == "ITEMLOG" or _mode == "MONEYLOG")
    infoFrame:SetShown(_mode == "INFO")
    PaintToggles()
    if _mode == "GRID" then
        title:SetText("Gildenbank")
        RefreshGrid()
    elseif _mode == "ITEMLOG" then
        title:SetText("Gildenbank - Log")
        RefreshItemLog()
    elseif _mode == "MONEYLOG" then
        title:SetText("Gildenbank - Geld-Log")
        hdrCount:SetText("")
        RefreshMoneyLog()
    elseif _mode == "INFO" then
        title:SetText("Gildenbank - Info")
        RefreshInfo()
    end
    -- update sidebar selection highlight
    for t, btn in pairs(_tabBtns) do
        local on = (t == _tab) and _mode ~= "MONEYLOG"
        if btn._sel then btn._sel:SetShown(on) end
    end
    if _specialBtns.moneylog and _specialBtns.moneylog._sel then
        _specialBtns.moneylog._sel:SetShown(_mode == "MONEYLOG")
    end
end

function SetMode(m)
    _mode = m
    if m == "ITEMLOG" then if QueryGuildBankLog then QueryGuildBankLog(_tab) end
    elseif m == "MONEYLOG" then if QueryGuildBankLog then QueryGuildBankLog(MONEYLOG_TAB) end
    elseif m == "INFO" then if QueryGuildBankText then QueryGuildBankText(_tab) end end
    RefreshMain()
end

function SelectTab(tab)
    _tab = tab
    -- keep the currently open view (Items/Log/Info); the money log is not
    -- tab-bound, so leaving it via a tab click falls back to the item grid.
    if _mode == "MONEYLOG" then _mode = "GRID" end
    if SetCurrentGuildBankTab then SetCurrentGuildBankTab(tab) end
    if QueryGuildBankTab then QueryGuildBankTab(tab) end
    if _mode == "ITEMLOG" then
        if QueryGuildBankLog then QueryGuildBankLog(tab) end
    elseif _mode == "INFO" then
        if QueryGuildBankText then QueryGuildBankText(tab) end
    end
    RefreshMain()
end

-------------------------------------------------------------------------------
--  Sidebar build
-------------------------------------------------------------------------------
function RebuildSidebar()
    local num = GetNumGuildBankTabs and GetNumGuildBankTabs() or 0
    local y = -28
    for t = 1, num do
        local name, icon, isViewable = GetGuildBankTabInfo(t)
        local btn = _tabBtns[t]
        if not btn then
            btn = CreateFrame("Button", nil, sidebar)
            btn:SetHeight(26)
            StyleSidebarBtn(btn)
            btn:SetScript("OnClick", function(self) SelectTab(self._tab) end)
            btn:SetScript("OnEnter", function(self)
                if not self._tab then return end
                local nm, _, vw, cd, nW, rW = GetGuildBankTabInfo(self._tab)
                GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
                GameTooltip:AddLine(nm and nm ~= "" and nm or ("Tab " .. self._tab))
                if vw == false then GameTooltip:AddLine("Nicht einsehbar", 1, 0.3, 0.3) end
                if nW and nW > 0 then GameTooltip:AddLine("Abhebungen: " .. (rW or 0) .. "/" .. nW, 0.8, 0.8, 0.8) end
                GameTooltip:AddLine(cd and "Einzahlen erlaubt" or "Kein Einzahlen", 0.7, 0.7, 0.7)
                GameTooltip:Show()
            end)
            btn:SetScript("OnLeave", function() GameTooltip:Hide() end)
            _tabBtns[t] = btn
        end
        btn._tab = t
        btn._icon:SetTexture(icon or "Interface\\Icons\\INV_Misc_Bag_08")
        btn._name:SetText(name and name ~= "" and name or ("Tab " .. t))
        btn._name:SetTextColor(isViewable == false and 0.45 or 0.85,
            isViewable == false and 0.45 or 0.85, isViewable == false and 0.45 or 0.85)
        btn:ClearAllPoints()
        btn:SetPoint("TOPLEFT", sidebar, "TOPLEFT", 4, y)
        btn:SetPoint("TOPRIGHT", sidebar, "TOPRIGHT", -4, y)
        btn:Show()
        y = y - 28
    end
    for t = num + 1, #_tabBtns do if _tabBtns[t] then _tabBtns[t]:Hide() end end
    if _tab > num and num > 0 then _tab = 1 end

    y = y - 6
    -- Money log entry
    local ml = _specialBtns.moneylog
    if not ml then
        ml = CreateFrame("Button", nil, sidebar); ml:SetHeight(26); StyleSidebarBtn(ml)
        ml._icon:SetTexture("Interface\\Icons\\INV_Misc_Coin_01")
        ml._name:SetText("Geld-Log")
        ml:SetScript("OnClick", function() _mode = "MONEYLOG"; SetMode("MONEYLOG") end)
        _specialBtns.moneylog = ml
    end
    ml:ClearAllPoints()
    ml:SetPoint("TOPLEFT", sidebar, "TOPLEFT", 4, y)
    ml:SetPoint("TOPRIGHT", sidebar, "TOPRIGHT", -4, y)
    ml:Show(); y = y - 28

    -- Buy tab entry (only when a tab is available for purchase)
    local cost = GetGuildBankTabCost and GetGuildBankTabCost()
    local buy = _specialBtns.buy
    if cost and num < MAX_TABS then
        if not buy then
            buy = CreateFrame("Button", nil, sidebar); buy:SetHeight(26); StyleSidebarBtn(buy)
            buy._icon:SetTexture("Interface\\Icons\\INV_Misc_Bag_10_Green")
            _specialBtns.buy = buy
        end
        buy._name:SetText("Tab kaufen")
        buy._count:SetText("")
        buy._cost = cost
        buy:SetScript("OnClick", function(self)
            if StaticPopupDialogs and StaticPopupDialogs["CONFIRM_BUY_GUILDBANK_TAB"] then
                StaticPopup_Show("CONFIRM_BUY_GUILDBANK_TAB")
                return
            end
            local c = self._cost or (GetGuildBankTabCost and GetGuildBankTabCost())
            local msg = "Neuen Gildenbank-Tab kaufen fuer " .. Money(c) .. "?"
            if EUI and EUI.ShowConfirmPopup then
                EUI:ShowConfirmPopup({ title = "Tab kaufen", message = msg,
                    confirmText = ACCEPT, cancelText = CANCEL,
                    onConfirm = function() if BuyGuildBankTab then BuyGuildBankTab() end end })
            else
                if BuyGuildBankTab then BuyGuildBankTab() end
            end
        end)
        buy:ClearAllPoints()
        buy:SetPoint("TOPLEFT", sidebar, "TOPLEFT", 4, y)
        buy:SetPoint("TOPRIGHT", sidebar, "TOPRIGHT", -4, y)
        buy:Show()
    elseif buy then
        buy:Hide()
    end
end

-------------------------------------------------------------------------------
--  Footer refresh
-------------------------------------------------------------------------------
function RefreshFooter()
    guildMoney:SetText(Money(GetGuildBankMoney and GetGuildBankMoney() or 0))
    local rem = GetGuildBankWithdrawMoney and GetGuildBankWithdrawMoney() or 0
    if rem == -1 then withdrawInfo:SetText("Abhebbar: unbegrenzt")
    else withdrawInfo:SetText("Abhebbar: " .. Money(rem)) end
    local canW = (not CanWithdrawGuildBankMoney) or CanWithdrawGuildBankMoney()
    if canW and rem ~= 0 then
        withdrawMoneyBtn:Enable(); withdrawMoneyBtn._lbl:SetTextColor(GOLD_R, GOLD_G, GOLD_B, 0.85)
    else
        withdrawMoneyBtn:Disable(); withdrawMoneyBtn._lbl:SetTextColor(0.4, 0.4, 0.4, 1)
    end
end

function RefreshAll()
    RebuildSidebar()
    RefreshFooter()
    RefreshMain()
end

-------------------------------------------------------------------------------
--  Hide the default Blizzard guild bank visuals (keep the session open)
-------------------------------------------------------------------------------
local function NeuterBlizzard()
    local gbf = _G.GuildBankFrame
    if not gbf or gbf._euiNeutered then return end
    gbf._euiNeutered = true
    local function hide(self) self:SetAlpha(0); self:EnableMouse(false) end
    gbf:HookScript("OnShow", hide)
    if gbf:IsShown() then hide(gbf) end
end

-------------------------------------------------------------------------------
--  Open / close
-------------------------------------------------------------------------------
local function OpenGB()
    NeuterBlizzard()
    _mode = "GRID"
    GB:Show()
    RefreshAll()
    SelectTab(_tab)
end
local function CloseGB() GB:Hide() end

-------------------------------------------------------------------------------
--  Events
-------------------------------------------------------------------------------
local GUILD_BANKER_TYPE = Enum and Enum.PlayerInteractionType and Enum.PlayerInteractionType.GuildBanker

local ev = CreateFrame("Frame")
ev:RegisterEvent("ADDON_LOADED")
ev:RegisterEvent("GUILDBANKFRAME_OPENED")
ev:RegisterEvent("GUILDBANKFRAME_CLOSED")
ev:RegisterEvent("GUILDBANKBAGSLOTS_CHANGED")
ev:RegisterEvent("GUILDBANK_UPDATE_TABS")
ev:RegisterEvent("GUILDBANK_UPDATE_MONEY")
pcall(ev.RegisterEvent, ev, "GUILDBANK_UPDATE_WITHDRAWMONEY")
pcall(ev.RegisterEvent, ev, "GUILDBANK_ITEM_LOCK_CHANGED")
pcall(ev.RegisterEvent, ev, "GUILDBANKLOG_UPDATE")
pcall(ev.RegisterEvent, ev, "GUILDBANK_TEXT_CHANGED")
pcall(ev.RegisterEvent, ev, "PLAYER_INTERACTION_MANAGER_FRAME_SHOW")
pcall(ev.RegisterEvent, ev, "PLAYER_INTERACTION_MANAGER_FRAME_HIDE")

ev:SetScript("OnEvent", function(self, event, arg1)
    if event == "ADDON_LOADED" then
        if arg1 == "Blizzard_GuildBankUI" then NeuterBlizzard() end
        return
    elseif event == "PLAYER_INTERACTION_MANAGER_FRAME_SHOW" then
        if GUILD_BANKER_TYPE and arg1 == GUILD_BANKER_TYPE then OpenGB() end
    elseif event == "PLAYER_INTERACTION_MANAGER_FRAME_HIDE" then
        if GUILD_BANKER_TYPE and arg1 == GUILD_BANKER_TYPE then CloseGB() end
    elseif event == "GUILDBANKFRAME_OPENED" then
        OpenGB()
    elseif event == "GUILDBANKFRAME_CLOSED" then
        CloseGB()
    elseif not GB:IsShown() then
        return
    elseif event == "GUILDBANKBAGSLOTS_CHANGED" or event == "GUILDBANK_ITEM_LOCK_CHANGED" then
        if _mode == "GRID" then RefreshGrid() end
    elseif event == "GUILDBANK_UPDATE_TABS" then
        RebuildSidebar(); RefreshMain()
    elseif event == "GUILDBANK_UPDATE_MONEY" or event == "GUILDBANK_UPDATE_WITHDRAWMONEY" then
        RefreshFooter()
    elseif event == "GUILDBANKLOG_UPDATE" then
        if _mode == "ITEMLOG" then RefreshItemLog()
        elseif _mode == "MONEYLOG" then RefreshMoneyLog() end
    elseif event == "GUILDBANK_TEXT_CHANGED" then
        if _mode == "INFO" then RefreshInfo() end
    end
end)

EUI.GuildBank = GB
