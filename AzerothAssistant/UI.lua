local _, ns = ...

local ROW_HEIGHT = 24
local VISIBLE_ROWS = 12

local UI = {
    frame = nil,
    rows = {},
    selected = {},
    filterText = "",
    filteredMembers = {},
}

ns.UI = UI

local function SetBackdrop(frame)
    frame:SetBackdrop({
        bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
        edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
        tile = true,
        tileSize = 32,
        edgeSize = 32,
        insets = { left = 8, right = 8, top = 8, bottom = 8 },
    })
end

function UI:CreateRow(index)
    local row = CreateFrame("CheckButton", "AzerothAssistantRow" .. index, self.frame, "UICheckButtonTemplate")
    row:SetSize(540, ROW_HEIGHT)
    row:SetPoint("TOPLEFT", self.scrollFrame, "TOPLEFT", 0, -((index - 1) * ROW_HEIGHT))
    row:SetHitRectInsets(0, 0, 0, 0)
    row:RegisterForClicks("LeftButtonUp")

    row.NameText = row:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    row.NameText:SetPoint("LEFT", row, "LEFT", 28, 0)
    row.NameText:SetSize(180, ROW_HEIGHT)
    row.NameText:SetJustifyH("LEFT")

    row.LevelText = row:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    row.LevelText:SetPoint("LEFT", row.NameText, "RIGHT", 6, 0)
    row.LevelText:SetSize(36, ROW_HEIGHT)
    row.LevelText:SetJustifyH("RIGHT")

    row.ClassText = row:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    row.ClassText:SetPoint("LEFT", row.LevelText, "RIGHT", 10, 0)
    row.ClassText:SetSize(86, ROW_HEIGHT)
    row.ClassText:SetJustifyH("LEFT")

    row.ZoneText = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    row.ZoneText:SetPoint("LEFT", row.ClassText, "RIGHT", 8, 0)
    row.ZoneText:SetSize(130, ROW_HEIGHT)
    row.ZoneText:SetJustifyH("LEFT")
    row.ZoneText:SetWordWrap(false)

    row.StatusText = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    row.StatusText:SetPoint("LEFT", row.ZoneText, "RIGHT", 6, 0)
    row.StatusText:SetSize(54, ROW_HEIGHT)
    row.StatusText:SetJustifyH("RIGHT")

    row:SetScript("OnClick", function(button)
        if button.member and not button.member.isInGroup then
            UI.selected[button.member.name] = button:GetChecked() and true or nil
            UI:Refresh()
        end
    end)

    row:SetScript("OnEnter", function(button)
        if not button.member then
            return
        end

        GameTooltip:SetOwner(button, "ANCHOR_RIGHT")
        GameTooltip:AddLine(button.member.name, button.member.classColorR, button.member.classColorG, button.member.classColorB)
        if button.member.rankName ~= "" then
            GameTooltip:AddLine(string.format(ns.L.TOOLTIP_RANK, button.member.rankName), 1, 1, 1)
        end
        if button.member.zone ~= "" then
            GameTooltip:AddLine(string.format(ns.L.TOOLTIP_ZONE, button.member.zone), 0.8, 0.8, 0.8)
        end
        GameTooltip:Show()
    end)

    row:SetScript("OnLeave", function()
        GameTooltip:Hide()
    end)

    self.rows[index] = row
end

function UI:GetQuickBarDb()
    local db = ns.Addon.db
    if not db.quickBar then
        db.quickBar = db.quickButton or {
            point = "TOP",
            relativePoint = "TOP",
            x = -180,
            y = -40,
            locked = true,
        }
        db.quickButton = nil
    end
    return db.quickBar
end

function UI:UpdateQuickBar()
    if not self.quickBar then
        return
    end

    local db = self:GetQuickBarDb()
    self.quickBar:SetAlpha(db.locked and 1 or 0.72)

    if self.quickInviteButton then
        self.quickInviteButton.Label:SetTextColor(1, 0.96, 0.84)
    end

    if self.quickRunestoneButton then
        if not self.quickRunestoneButton:IsShown() then
            return
        end

        local status = ns.Runestone:GetStatus()
        local red, green, blue = 0.58, 0.58, 0.54
        if status == "ACTIVATED" then
            red, green, blue = 0.34, 0.83, 0.43
        elseif status == "INACTIVE" then
            red, green, blue = 0.88, 0.72, 0.25
        end
        self.quickRunestoneButton.Label:SetTextColor(red, green, blue)
    end
end

-- 快捷栏按模块开关收起或展开：两个模块都关闭时整条快捷栏隐藏。
function UI:ApplyModuleVisibility()
    if not self.quickBar then
        return
    end

    local showInvite = ns.Config:IsEnabled("guildInvite")
    local showRunestone = ns.Config:IsEnabled("runestone")
    local bar = self.quickBar
    local gap = self.quickBarGap or 12
    local offset = 0

    if self.quickInviteButton then
        if showInvite then
            self.quickInviteButton:ClearAllPoints()
            self.quickInviteButton:SetPoint("LEFT", bar, "LEFT", 0, 0)
            self.quickInviteButton:Show()
            offset = (self.quickInviteWidth or 16) + gap
        else
            self.quickInviteButton:Hide()
        end
    end

    if self.quickRunestoneButton then
        if showRunestone then
            self.quickRunestoneButton:ClearAllPoints()
            self.quickRunestoneButton:SetPoint("LEFT", bar, "LEFT", offset, 0)
            self.quickRunestoneButton:Show()
            offset = offset + (self.quickRunestoneWidth or 16)
        else
            self.quickRunestoneButton:Hide()
        end
    end

    if showInvite or showRunestone then
        bar:SetSize(math.max(offset, 16), 24)
        bar:Show()
    else
        bar:Hide()
    end

    if not showInvite and self.frame and self.frame:IsShown() then
        self.frame:Hide()
    end
end

function UI:SetQuickBarLocked(locked, silent)
    local db = self:GetQuickBarDb()
    db.locked = locked and true or false
    self:UpdateQuickBar()

    if not silent then
        if db.locked then
            ns.Addon:Print(ns.L.NOTIFY_QUICK_LOCKED)
        else
            ns.Addon:Print(ns.L.NOTIFY_QUICK_UNLOCKED)
        end
    end
end

local function ConfigureQuickBarButton(button, onClick, tooltipTitle, tooltipHint)
    button:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    button:RegisterForDrag("LeftButton")

    button:SetScript("OnClick", function(_, mouseButton)
        if mouseButton == "RightButton" then
            UI:SetQuickBarLocked(not UI:GetQuickBarDb().locked)
        else
            onClick()
        end
    end)

    button:SetScript("OnDragStart", function()
        if not UI:GetQuickBarDb().locked then
            UI.quickBar:StartMoving()
        end
    end)

    button:SetScript("OnDragStop", function()
        if UI:GetQuickBarDb().locked then
            return
        end

        local bar = UI.quickBar
        bar:StopMovingOrSizing()
        local point, _, relativePoint, x, y = bar:GetPoint(1)
        local db = UI:GetQuickBarDb()
        db.point = point
        db.relativePoint = relativePoint
        db.x = x
        db.y = y
    end)

    button:SetScript("OnEnter", function(quickButton)
        GameTooltip:SetOwner(quickButton, "ANCHOR_RIGHT")
        GameTooltip:AddLine(tooltipTitle, 1, 0.82, 0)
        GameTooltip:AddLine(tooltipHint, 1, 1, 1, true)

        if quickButton == UI.quickInviteButton then
            local bindingKey = GetBindingKey and GetBindingKey("AZEROTHASSISTANT_RANDOM_INVITE")
            if bindingKey and bindingKey ~= "" then
                GameTooltip:AddLine(string.format(ns.L.QUICK_KEY, bindingKey), 0.25, 0.8, 1)
            end
        end

        GameTooltip:AddLine(UI:GetQuickBarDb().locked and ns.L.QUICK_LOCKED or ns.L.QUICK_UNLOCKED, 0.75, 0.75, 0.75)
        GameTooltip:AddLine(ns.L.QUICK_DRAG_HINT, 0.75, 0.75, 0.75, true)
        GameTooltip:Show()
    end)

    button:SetScript("OnLeave", function()
        GameTooltip:Hide()
    end)
end

local function StyleQuickBarTextButton(button, label)
    button.Label = button:CreateFontString(nil, "OVERLAY")
    button.Label:SetPoint("CENTER", button, "CENTER", 0, 1)
    button.Label:SetFont(STANDARD_TEXT_FONT, 20, "OUTLINE")
    button.Label:SetJustifyH("CENTER")
    button.Label:SetText(label)
    button.Label:SetTextColor(1, 0.96, 0.84)
    button.Label:SetShadowOffset(1, -1)

    local width = math.max(16, math.ceil(button.Label:GetStringWidth()) + 2)
    button:SetSize(width, 24)
    return width
end

function UI:CreateQuickBar()
    if self.quickBar then
        return
    end

    local db = self:GetQuickBarDb()
    local bar = CreateFrame("Frame", "AzerothAssistantQuickBar", UIParent, "BackdropTemplate")
    self.quickBar = bar
    bar:SetFrameStrata("HIGH")
    bar:SetClampedToScreen(true)
    bar:SetMovable(true)
    bar:SetPoint(db.point or "TOP", UIParent, db.relativePoint or "TOP", db.x or -180, db.y or -40)

    local inviteButton = CreateFrame("Button", "AzerothAssistantInviteButton", bar)
    inviteButton:SetPoint("LEFT", bar, "LEFT", 0, 0)
    self.quickInviteButton = inviteButton
    local inviteWidth = StyleQuickBarTextButton(inviteButton, ns.L.QUICK_INVITE)

    local runestoneButton = CreateFrame("Button", "AzerothAssistantRunestoneButton", bar)
    self.quickRunestoneButton = runestoneButton
    local runestoneWidth = StyleQuickBarTextButton(runestoneButton, ns.L.QUICK_RUNESTONE)
    local characterGap = math.max(12, math.ceil(inviteButton.Label:GetStringWidth()))
    runestoneButton:SetPoint("LEFT", inviteButton, "RIGHT", characterGap, 0)
    bar:SetSize(inviteWidth + characterGap + runestoneWidth, 24)

    self.quickInviteWidth = inviteWidth
    self.quickRunestoneWidth = runestoneWidth
    self.quickBarGap = characterGap

    ConfigureQuickBarButton(inviteButton, function()
        UI:InviteFirstMember()
    end, ns.L.QUICK_INVITE, ns.L.QUICK_CLICK_HINT)

    ConfigureQuickBarButton(runestoneButton, function()
        ns.Runestone:PrintStatus()
    end, ns.L.QUICK_RUNESTONE, ns.L.QUICK_RUNESTONE_HINT)

    self:ApplyModuleVisibility()
    self:UpdateQuickBar()
end

function UI:Create()
    if self.frame then
        return
    end

    local frame = CreateFrame("Frame", "AzerothAssistantFrame", UIParent, "BackdropTemplate")
    self.frame = frame
    frame:SetSize(600, 510)
    frame:SetFrameStrata("DIALOG")
    frame:SetClampedToScreen(true)
    frame:SetMovable(true)
    frame:EnableMouse(true)
    frame:RegisterForDrag("LeftButton")
    SetBackdrop(frame)

    local db = ns.Addon.db
    frame:SetPoint(db.point or "CENTER", UIParent, db.point or "CENTER", db.x or 0, db.y or 0)
    frame:SetScript("OnDragStart", frame.StartMoving)
    frame:SetScript("OnDragStop", function(movingFrame)
        movingFrame:StopMovingOrSizing()
        local point, _, _, x, y = movingFrame:GetPoint(1)
        db.point, db.x, db.y = point, x, y
    end)
    frame:SetScript("OnShow", function()
        ns.Addon:RefreshAll(true)
    end)

    if UISpecialFrames then
        local alreadyRegistered = false
        for _, frameName in ipairs(UISpecialFrames) do
            if frameName == "AzerothAssistantFrame" then
                alreadyRegistered = true
                break
            end
        end
        if not alreadyRegistered then
            UISpecialFrames[#UISpecialFrames + 1] = "AzerothAssistantFrame"
        end
    end

    frame.Title = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    frame.Title:SetPoint("TOPLEFT", frame, "TOPLEFT", 24, -18)
    frame.Title:SetText(ns.L.TITLE_GUILD)

    local closeButton = CreateFrame("Button", nil, frame, "UIPanelCloseButton")
    closeButton:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -10, -10)

    frame.StatusText = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    frame.StatusText:SetPoint("TOPLEFT", frame.Title, "BOTTOMLEFT", 0, -8)
    frame.StatusText:SetSize(540, 32)
    frame.StatusText:SetJustifyH("LEFT")

    local search = CreateFrame("EditBox", "AzerothAssistantSearchBox", frame, "InputBoxTemplate")
    search:SetSize(220, 26)
    search:SetPoint("TOPLEFT", frame, "TOPLEFT", 24, -82)
    search:SetAutoFocus(false)
    search:SetTextInsets(8, 8, 0, 0)
    search:SetScript("OnEscapePressed", function(editBox)
        editBox:ClearFocus()
    end)
    search:SetScript("OnTextChanged", function(editBox, userInput)
        if userInput then
            UI.filterText = string.lower(editBox:GetText() or "")
            UI:Refresh()
        end
    end)
    search:SetScript("OnShow", function(editBox)
        if editBox:GetText() == "" then
            editBox:SetText(ns.L.SEARCH)
            editBox:SetTextColor(0.55, 0.55, 0.55)
        end
    end)
    search:SetScript("OnEditFocusGained", function(editBox)
        if editBox:GetText() == ns.L.SEARCH then
            editBox:SetText("")
            editBox:SetTextColor(1, 1, 1)
        end
    end)
    search:SetScript("OnEditFocusLost", function(editBox)
        if editBox:GetText() == "" then
            editBox:SetText(ns.L.SEARCH)
            editBox:SetTextColor(0.55, 0.55, 0.55)
            UI.filterText = ""
            UI:Refresh()
        end
    end)
    self.search = search

    local refreshButton = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    refreshButton:SetSize(82, 24)
    refreshButton:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -28, -84)
    refreshButton:SetText(ns.L.REFRESH)
    refreshButton:SetScript("OnClick", function()
        ns.Addon:RefreshAll(true)
    end)

    local clearButton = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    clearButton:SetSize(64, 24)
    clearButton:SetPoint("RIGHT", refreshButton, "LEFT", -6, 0)
    clearButton:SetText(ns.L.CLEAR)
    clearButton:SetScript("OnClick", function()
        UI.selected = {}
        UI:Refresh()
    end)

    local selectAllButton = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    selectAllButton:SetSize(82, 24)
    selectAllButton:SetPoint("RIGHT", clearButton, "LEFT", -6, 0)
    selectAllButton:SetText(ns.L.SELECT_ALL)
    selectAllButton:SetScript("OnClick", function()
        UI:SelectVisible()
    end)
    self.selectAllButton = selectAllButton

    local scrollFrame = CreateFrame("ScrollFrame", "AzerothAssistantScrollFrame", frame, "FauxScrollFrameTemplate")
    scrollFrame:SetPoint("TOPLEFT", frame, "TOPLEFT", 24, -118)
    scrollFrame:SetSize(550, VISIBLE_ROWS * ROW_HEIGHT)
    scrollFrame:SetScript("OnVerticalScroll", function(scroll, offset)
        FauxScrollFrame_OnVerticalScroll(scroll, offset, ROW_HEIGHT, function()
            UI:UpdateRows()
        end)
    end)
    self.scrollFrame = scrollFrame

    for index = 1, VISIBLE_ROWS do
        self:CreateRow(index)
    end

    local inviteButton = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    inviteButton:SetSize(170, 28)
    inviteButton:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -24, 20)
    inviteButton:SetScript("OnClick", function()
        UI:InviteSelected()
    end)
    self.inviteButton = inviteButton

    local firstInviteButton = CreateFrame("Button", "AzerothAssistantFirstInviteButton", frame, "UIPanelButtonTemplate")
    firstInviteButton:SetSize(210, 28)
    firstInviteButton:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 24, 20)
    firstInviteButton:SetScript("OnClick", function()
        UI:InviteFirstMember()
    end)
    self.firstInviteButton = firstInviteButton

    local leavePartyButton = CreateFrame("Button", "AzerothAssistantLeavePartyButton", UIParent)
    leavePartyButton:Hide()
    leavePartyButton:SetScript("OnClick", function()
        ns.Addon:LeavePartyWithoutConfirmation()
    end)
    self.leavePartyButton = leavePartyButton

    self:CreateQuickBar()

    frame:Hide()
end

function UI:Toggle()
    if not ns.Config:IsEnabled("guildInvite") then
        ns.Addon:Print(ns.L.SETTINGS_DISABLED_GUILD)
        return
    end

    self:Create()
    if self.frame:IsShown() then
        self.frame:Hide()
    else
        self.frame:Show()
    end
end

function UI:GetSelectedMembers()
    local selectedMembers = {}
    for _, member in ipairs(ns.Roster:GetMembers()) do
        if self.selected[member.name] and not member.isInGroup then
            selectedMembers[#selectedMembers + 1] = member
        end
    end
    return selectedMembers
end

function UI:GetStatusLabel(member)
    if member.isInGroup then
        return ns.L.STATUS_IN_GROUP, 0.5, 0.5, 0.5
    end
    if member.isMobile then
        return ns.L.STATUS_MOBILE, 0.25, 0.65, 1
    end
    if member.status == 1 then
        return ns.L.STATUS_AFK, 1, 0.82, 0
    end
    if member.status == 2 then
        return ns.L.STATUS_DND, 1, 0.25, 0.25
    end
    return ns.L.STATUS_ONLINE_LABEL, 0.25, 1, 0.25
end

function UI:UpdateStatusText()
    local text
    local red, green, blue = 1, 0.82, 0
    local roster = ns.Roster
    local groupState = roster:GetGroupState()

    if roster.state == "NO_GUILD" then
        text = ns.L.STATUS_NO_GUILD
    elseif roster.state == "UNSUPPORTED" then
        text = ns.L.STATUS_UNSUPPORTED
    elseif groupState.inRaid then
        text = ns.L.STATUS_IN_RAID
        red, green, blue = 1, 0.25, 0.25
    elseif not groupState.canInvite then
        text = ns.L.STATUS_NOT_LEADER
        red, green, blue = 1, 0.25, 0.25
    elseif groupState.freeSlots <= 0 then
        text = ns.L.STATUS_FULL
        red, green, blue = 1, 0.25, 0.25
    elseif groupState.isSending then
        text = ns.L.STATUS_SENDING
    else
        text = string.format(ns.L.STATUS_ONLINE, #roster:GetMembers(), roster.onlineCount)
        red, green, blue = 0.25, 1, 0.25
    end

    self.frame.StatusText:SetText(text)
    self.frame.StatusText:SetTextColor(red, green, blue)
end

function UI:UpdateRows()
    local offset = FauxScrollFrame_GetOffset(self.scrollFrame) or 0
    local maxOffset = math.max(0, #self.filteredMembers - VISIBLE_ROWS)
    if offset > maxOffset then
        offset = maxOffset
        self.scrollFrame:SetVerticalScroll(offset * ROW_HEIGHT)
    end
    FauxScrollFrame_Update(self.scrollFrame, #self.filteredMembers, VISIBLE_ROWS, ROW_HEIGHT)

    for rowIndex = 1, VISIBLE_ROWS do
        local row = self.rows[rowIndex]
        local member = self.filteredMembers[offset + rowIndex]

        if member then
            local statusText, statusRed, statusGreen, statusBlue = self:GetStatusLabel(member)

            row.member = member
            row.NameText:SetText(member.name)
            row.NameText:SetTextColor(member.classColorR, member.classColorG, member.classColorB)
            row.LevelText:SetText(member.level > 0 and tostring(member.level) or "")
            row.ClassText:SetText(member.classDisplayName)
            row.ZoneText:SetText(member.zone)
            row.StatusText:SetText(statusText)
            row.StatusText:SetTextColor(statusRed, statusGreen, statusBlue)
            row:SetChecked(self.selected[member.name] and true or false)
            row:Show()

            if member.isInGroup then
                row:Disable()
            else
                row:Enable()
            end
        else
            row.member = nil
            row:Hide()
        end
    end
end

function UI:ApplyFilter()
    local filtered = {}
    for _, member in ipairs(ns.Roster:GetMembers()) do
        if self.filterText == "" or string.find(string.lower(member.name), self.filterText, 1, true) then
            filtered[#filtered + 1] = member
        end
    end
    self.filteredMembers = filtered
end

function UI:UpdateInviteButton(groupState)
    local selectedCount = #self:GetSelectedMembers()
    self.inviteButton:SetText(string.format(ns.L.INVITE_SELECTED, selectedCount, groupState.freeSlots))

    local enabled = selectedCount > 0
        and selectedCount <= groupState.freeSlots
        and groupState.freeSlots > 0
        and groupState.canInvite
        and not groupState.inRaid
        and not groupState.isSending

    self.inviteButton:SetEnabled(enabled)
end

function UI:UpdateFirstInviteButton(groupState)
    local bindingKey = GetBindingKey and GetBindingKey("AZEROTHASSISTANT_RANDOM_INVITE")
    if bindingKey and bindingKey ~= "" then
        self.firstInviteButton:SetText(string.format(ns.L.FIRST_INVITE_BOUND, bindingKey))
    else
        self.firstInviteButton:SetText(ns.L.FIRST_INVITE)
    end

    local enabled = groupState.freeSlots > 0
        and groupState.canInvite
        and not groupState.inRaid
        and not groupState.isSending

    self.firstInviteButton:SetEnabled(enabled)
    self:UpdateQuickBar()
end

function UI:Refresh()
    if not self.frame then
        return
    end

    local memberLookup = {}
    for _, member in ipairs(ns.Roster:GetMembers()) do
        memberLookup[member.name] = true
    end

    for name in pairs(self.selected) do
        if not memberLookup[name] then
            self.selected[name] = nil
        end
    end

    self:ApplyFilter()
    self:UpdateStatusText()
    self:UpdateRows()
    local groupState = ns.Roster:GetGroupState()
    self:UpdateInviteButton(groupState)
    self:UpdateFirstInviteButton(groupState)
end

function UI:SelectVisible()
    local groupState = ns.Roster:GetGroupState()
    if groupState.inRaid or not groupState.canInvite or groupState.freeSlots <= 0 or groupState.isSending then
        return
    end

    local selectedCount = #self:GetSelectedMembers()
    local limit = groupState.freeSlots
    local hitLimit = false

    for _, member in ipairs(self.filteredMembers) do
        if selectedCount >= limit then
            hitLimit = true
            break
        end
        if not member.isInGroup and not self.selected[member.name] then
            self.selected[member.name] = true
            selectedCount = selectedCount + 1
        end
    end

    if hitLimit then
        ns.Addon:Print(string.format(ns.L.NOTIFY_SELECTION_LIMIT, limit))
    end

    self:Refresh()
end

function UI:InviteSelected()
    if not ns.Config:IsEnabled("guildInvite") then
        ns.Addon:Print(ns.L.SETTINGS_DISABLED_GUILD)
        return
    end

    local groupState = ns.Roster:GetGroupState()
    if groupState.isSending then
        ns.Addon:Print(ns.L.ERROR_SENDING)
        return
    end
    if not IsInGuild() then
        ns.Addon:Print(ns.L.ERROR_NOT_IN_GUILD)
        return
    end
    if groupState.inRaid then
        ns.Addon:Print(ns.L.ERROR_IN_RAID)
        return
    end
    if not groupState.canInvite then
        ns.Addon:Print(ns.L.ERROR_NOT_LEADER)
        return
    end
    if groupState.freeSlots <= 0 then
        ns.Addon:Print(ns.L.ERROR_PARTY_FULL)
        return
    end

    local selectedMembers = self:GetSelectedMembers()
    if #selectedMembers == 0 then
        ns.Addon:Print(ns.L.ERROR_NO_SELECTION)
        return
    end
    if #selectedMembers > groupState.freeSlots then
        ns.Addon:Print(string.format(ns.L.ERROR_TOO_MANY, groupState.freeSlots, #selectedMembers - groupState.freeSlots))
        return
    end

    if ns.Roster:QueueInvites(selectedMembers) then
        self.selected = {}
        self:Refresh()
    end
end

function UI:InviteFirstMember()
    if not ns.Config:IsEnabled("guildInvite") then
        ns.Addon:Print(ns.L.SETTINGS_DISABLED_GUILD)
        return
    end

    local groupState = ns.Roster:GetGroupState()
    if groupState.isSending then
        ns.Addon:Print(ns.L.ERROR_SENDING)
        return
    end
    if not IsInGuild() then
        ns.Addon:Print(ns.L.ERROR_NOT_IN_GUILD)
        return
    end
    if groupState.inRaid then
        ns.Addon:Print(ns.L.ERROR_IN_RAID)
        return
    end
    if not groupState.canInvite then
        ns.Addon:Print(ns.L.ERROR_NOT_LEADER)
        return
    end
    if groupState.freeSlots <= 0 then
        ns.Addon:Print(ns.L.ERROR_PARTY_FULL)
        return
    end

    local member = ns.Roster:GetFirstEligibleMember()
    if not member then
        ns.Addon:Print(ns.L.ERROR_NO_INVITE_CANDIDATE)
        return
    end

    if ns.Roster:QueueInvites({ member }) then
        self:Refresh()
    end
end
