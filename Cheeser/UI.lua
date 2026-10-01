local _, ns = ...

local UI = {}

ns.UI = UI

function UI:GetQuickBarDb()
    local db = ns.Addon.db
    if not db.quickBar then
        db.quickBar = db.quickButton or {
            point = "TOPLEFT",
            relativePoint = "TOPLEFT",
            x = 21,
            y = 0,
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
            local bindingKey = GetBindingKey and GetBindingKey("CHEESER_RANDOM_INVITE")
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
    local bar = CreateFrame("Frame", "CheeserQuickBar", UIParent, "BackdropTemplate")
    self.quickBar = bar
    bar:SetFrameStrata("HIGH")
    bar:SetClampedToScreen(true)
    bar:SetMovable(true)
    bar:SetPoint(db.point or "TOPLEFT", UIParent, db.relativePoint or "TOPLEFT", db.x or 21, db.y or 0)

    local inviteButton = CreateFrame("Button", "CheeserInviteButton", bar)
    inviteButton:SetPoint("LEFT", bar, "LEFT", 0, 0)
    self.quickInviteButton = inviteButton
    local inviteWidth = StyleQuickBarTextButton(inviteButton, ns.L.QUICK_INVITE)

    local runestoneButton = CreateFrame("Button", "CheeserRunestoneButton", bar)
    self.quickRunestoneButton = runestoneButton
    local runestoneWidth = StyleQuickBarTextButton(runestoneButton, ns.L.QUICK_RUNESTONE)
    local characterGap = math.max(6, math.ceil(inviteButton.Label:GetStringWidth() * 0.5))
    runestoneButton:SetPoint("LEFT", inviteButton, "RIGHT", characterGap, 0)
    bar:SetSize(inviteWidth + characterGap + runestoneWidth, 24)

    self.quickInviteWidth = inviteWidth
    self.quickRunestoneWidth = runestoneWidth
    self.quickBarGap = characterGap

    ConfigureQuickBarButton(inviteButton, function()
        UI:InviteFirstMember()
    end, ns.L.QUICK_INVITE, ns.L.QUICK_CLICK_HINT)

    ConfigureQuickBarButton(runestoneButton, function()
        ns.Runestone:CheckManual()
    end, ns.L.QUICK_RUNESTONE, ns.L.QUICK_RUNESTONE_HINT)

    self:ApplyModuleVisibility()
    self:UpdateQuickBar()
end

function UI:Create()
    if self.leavePartyButton then
        return
    end

    self:CreateQuickBar()

    -- 供“无需确认离开小队”按键绑定使用的隐藏按钮。
    self.leavePartyButton = CreateFrame("Button", "CheeserLeavePartyButton", UIParent)
    self.leavePartyButton:Hide()
    self.leavePartyButton:SetScript("OnClick", function()
        ns.Addon:LeavePartyWithoutConfirmation()
    end)
end

function UI:Refresh()
    self:UpdateQuickBar()
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

    local sourceBlockReason = ns.Roster:GetSourceBlockReason()
    if sourceBlockReason then
        ns.Addon:Print(sourceBlockReason)
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
