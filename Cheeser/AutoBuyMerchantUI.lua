local _, ns = ...

local MerchantUI = {}
ns.AutoBuyMerchantUI = MerchantUI

local button
local panel
local statusText
local itemText
local enabledCheck
local dryRunCheck
local pickButton
local resumeButton
local fields = {}
local updateElapsed = 0

local FIELD_DEFINITIONS = {
    { key = "quantity", x = 18, y = -226, width = 78, maxLetters = 7 },
    { key = "maxSpendGold", x = 118, y = -226, width = 88, maxLetters = 8 },
    { key = "reserveSlots", x = 228, y = -226, width = 72, maxLetters = 4 },
}

local function RefreshMerchantPanel()
    if not panel then
        return
    end

    local settings = ns.Config:GetAutoBuySettings()
    local snapshot = ns.AutoBuy:GetStatusSnapshot()
    local running = snapshot.running
    local stopping = snapshot.stopping
    local busy = running or stopping

    if not fields.itemID:HasFocus() then
        fields.itemID:SetText(settings.itemID > 0 and tostring(settings.itemID) or "")
    end
    if not fields.quantity:HasFocus() then
        fields.quantity:SetText(tostring(settings.quantity))
    end
    if not fields.maxSpendGold:HasFocus() then
        fields.maxSpendGold:SetText(tostring(settings.maxSpendGold))
    end
    if not fields.reserveSlots:HasFocus() then
        fields.reserveSlots:SetText(tostring(settings.reserveSlots))
    end

    enabledCheck:SetChecked(snapshot.enabled)
    dryRunCheck:SetChecked(settings.dryRun)

    for _, field in pairs(fields) do
        field:SetEnabled(not busy)
        field:SetAlpha(busy and 0.55 or 1)
    end
    pickButton:SetEnabled(not busy)
    pickButton:SetAlpha(busy and 0.55 or 1)
    enabledCheck:SetEnabled(not busy)
    dryRunCheck:SetEnabled(not busy)

    if snapshot.itemID > 0 then
        itemText:SetText(string.format(
            ns.L.AUTOBUY_PANEL_ITEM,
            snapshot.itemLink or snapshot.itemName or ns.L.AUTOBUY_SETTING_LOADING,
            snapshot.itemID
        ))
    else
        itemText:SetText(ns.L.AUTOBUY_SETTING_NO_ITEM)
    end

    if stopping then
        statusText:SetText(ns.L.AUTOBUY_PANEL_STOPPING)
    elseif running then
        statusText:SetText(string.format(
            ns.L.AUTOBUY_PANEL_RUNNING,
            snapshot.purchased,
            snapshot.maxUnits or 0
        ))
    elseif not snapshot.enabled then
        statusText:SetText(ns.L.AUTOBUY_PANEL_DISABLED)
    elseif not snapshot.merchantOpen then
        statusText:SetText(ns.L.AUTOBUY_OPEN_MERCHANT)
    elseif snapshot.maxUnits and snapshot.maxUnits > 0 then
        statusText:SetText(string.format(
            ns.L.AUTOBUY_PANEL_READY,
            snapshot.maxUnits,
            snapshot.costText or ns.L.AUTOBUY_COST_FREE
        ))
    else
        statusText:SetText(snapshot.reason or ns.L.AUTOBUY_REASON_UNAVAILABLE)
    end

    if stopping then
        resumeButton:SetText(ns.L.AUTOBUY_PANEL_STOPPING_BUTTON)
    elseif running then
        resumeButton:SetText(ns.L.AUTOBUY_PANEL_STOP)
    elseif settings.dryRun then
        resumeButton:SetText(ns.L.AUTOBUY_PANEL_PREVIEW_BUTTON)
    else
        resumeButton:SetText(ns.L.AUTOBUY_PANEL_RESUME)
    end

    local canToggle = not stopping and (
        running
        or (
            snapshot.enabled
            and snapshot.merchantOpen
            and snapshot.itemID > 0
        )
    )
    resumeButton:SetEnabled(canToggle)
    resumeButton:SetAlpha(canToggle and 1 or 0.55)
end

local function CommitField(field)
    local value = math.floor(tonumber(field:GetText()) or 0)
    ns.Config:SetAutoBuyOption(field.settingKey, value)
    RefreshMerchantPanel()
end

local function CreateField(parent, definition)
    local editBox = CreateFrame("EditBox", nil, parent, "InputBoxTemplate")
    editBox:SetSize(definition.width, 28)
    editBox:SetPoint("TOPLEFT", definition.x, definition.y)
    editBox:SetAutoFocus(false)
    editBox:SetNumeric(true)
    editBox:SetMaxLetters(definition.maxLetters)
    editBox.settingKey = definition.key

    editBox:SetScript("OnEditFocusGained", function(entered)
        entered.savedText = entered:GetText()
    end)
    editBox:SetScript("OnEnterPressed", function(entered)
        entered:ClearFocus()
    end)
    editBox:SetScript("OnEscapePressed", function(entered)
        entered:SetText(entered.savedText or entered:GetText())
        entered:ClearFocus()
    end)
    editBox:SetScript("OnEditFocusLost", function(entered)
        CommitField(entered)
        entered.savedText = entered:GetText()
    end)

    fields[definition.key] = editBox
    return editBox
end

local function CreatePanel()
    if panel or not MerchantFrame then
        return
    end

    panel = CreateFrame(
        "Frame",
        "CheeserAutoBuyPanel",
        UIParent,
        "BasicFrameTemplateWithInset"
    )
    panel:SetSize(360, 410)
    panel:SetPoint("LEFT", MerchantFrame, "RIGHT", 10, 0)
    panel:SetFrameStrata("DIALOG")
    panel:SetClampedToScreen(true)
    panel:SetToplevel(true)
    panel:SetMovable(true)
    panel:EnableMouse(true)
    panel:RegisterForDrag("LeftButton")
    panel:SetScript("OnDragStart", panel.StartMoving)
    panel:SetScript("OnDragStop", panel.StopMovingOrSizing)
    tinsert(UISpecialFrames, "CheeserAutoBuyPanel")

    if panel.TitleText then
        panel.TitleText:SetText(ns.L.AUTOBUY_PANEL_TITLE)
    end
    if panel.CloseButton then
        panel.CloseButton:SetScript("OnClick", function()
            panel:Hide()
        end)
    end

    enabledCheck = CreateFrame("CheckButton", nil, panel, "UICheckButtonTemplate")
    enabledCheck:SetSize(26, 26)
    enabledCheck:SetPoint("TOPLEFT", 18, -36)

    local enabledLabel = enabledCheck:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    enabledLabel:SetPoint("LEFT", enabledCheck, "RIGHT", 6, 0)
    enabledLabel:SetText(ns.L.SETTINGS_AUTOBUY)

    statusText = panel:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    statusText:SetPoint("TOPLEFT", 18, -66)
    statusText:SetWidth(324)
    statusText:SetHeight(44)
    statusText:SetJustifyH("LEFT")
    statusText:SetJustifyV("TOP")
    statusText:SetTextColor(0.78, 0.78, 0.78)

    local separator = panel:CreateTexture(nil, "OVERLAY")
    separator:SetPoint("TOPLEFT", 18, -116)
    separator:SetSize(324, 1)
    separator:SetColorTexture(0.5, 0.5, 0.5, 0.45)

    local itemLabel = panel:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    itemLabel:SetPoint("TOPLEFT", 18, -134)
    itemLabel:SetText(ns.L.AUTOBUY_SETTING_ITEM)

    fields.itemID = CreateField(panel, {
        key = "itemID",
        x = 18,
        y = -156,
        width = 112,
        maxLetters = 9,
    })

    pickButton = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
    pickButton:SetSize(112, 24)
    pickButton:SetPoint("LEFT", fields.itemID, "RIGHT", 8, -1)
    pickButton:SetText(ns.L.AUTOBUY_SETTING_PICK)
    pickButton:SetScript("OnClick", function()
        ns.AutoBuy:ShowBagPicker(function(itemID)
            ns.Config:SetAutoBuyOption("itemID", itemID)
            RefreshMerchantPanel()
        end)
    end)

    itemText = panel:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    itemText:SetPoint("TOPLEFT", 18, -190)
    itemText:SetWidth(324)
    itemText:SetJustifyH("LEFT")
    itemText:SetTextColor(0.68, 0.68, 0.68)

    local quantityLabel = panel:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    quantityLabel:SetPoint("TOPLEFT", 18, -212)
    quantityLabel:SetText(ns.L.AUTOBUY_SETTING_QUANTITY)

    local maxLabel = panel:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    maxLabel:SetPoint("TOPLEFT", 118, -212)
    maxLabel:SetText(ns.L.AUTOBUY_SETTING_MAX)

    local reserveLabel = panel:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    reserveLabel:SetPoint("TOPLEFT", 228, -212)
    reserveLabel:SetText(ns.L.AUTOBUY_SETTING_RESERVE)

    for _, definition in ipairs(FIELD_DEFINITIONS) do
        CreateField(panel, definition)
    end

    dryRunCheck = CreateFrame("CheckButton", nil, panel, "UICheckButtonTemplate")
    dryRunCheck:SetSize(26, 26)
    dryRunCheck:SetPoint("TOPLEFT", 18, -270)

    local dryRunLabel = dryRunCheck:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    dryRunLabel:SetPoint("LEFT", dryRunCheck, "RIGHT", 6, 0)
    dryRunLabel:SetText(ns.L.AUTOBUY_SETTING_DRY_RUN)

    local helpText = panel:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    helpText:SetPoint("TOPLEFT", 18, -304)
    helpText:SetWidth(324)
    helpText:SetJustifyH("LEFT")
    helpText:SetText(ns.L.AUTOBUY_PANEL_HELP)
    helpText:SetTextColor(0.62, 0.62, 0.62)

    enabledCheck:SetScript("OnClick", function(checked)
        ns.Config:SetEnabled("autoBuy", checked:GetChecked() and true or false)
        RefreshMerchantPanel()
    end)
    dryRunCheck:SetScript("OnClick", function(checked)
        ns.Config:SetAutoBuyOption("dryRun", checked:GetChecked() and true or false)
        RefreshMerchantPanel()
    end)

    resumeButton = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
    resumeButton:SetSize(170, 26)
    resumeButton:SetPoint("BOTTOMLEFT", 18, 18)
    resumeButton:SetText(ns.L.AUTOBUY_PANEL_RESUME)
    resumeButton:SetScript("OnClick", function()
        ns.AutoBuy:Toggle()
        RefreshMerchantPanel()
    end)

    local settingsButton = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
    settingsButton:SetSize(126, 26)
    settingsButton:SetPoint("BOTTOMRIGHT", -18, 18)
    settingsButton:SetText(ns.L.AUTOBUY_PANEL_SETTINGS)
    settingsButton:SetScript("OnClick", function()
        ns.Config:Open()
    end)

    panel:SetScript("OnShow", RefreshMerchantPanel)
end

local function TogglePanel()
    CreatePanel()
    if not panel then
        return
    end

    if panel:IsShown() then
        panel:Hide()
    elseif MerchantFrame and MerchantFrame:IsShown() then
        panel:Show()
        panel:Raise()
        RefreshMerchantPanel()
    end
end

local function CreateMerchantButton()
    if button or not MerchantFrame then
        return
    end

    button = CreateFrame(
        "Button",
        "CheeserAutoBuyMerchantButton",
        MerchantFrame,
        "UIPanelButtonTemplate"
    )
    button:SetSize(112, 28)
    button:SetPoint("TOPRIGHT", MerchantFrame, "TOPLEFT", -8, -32)
    button:SetFrameStrata("DIALOG")
    button:SetText(ns.L.AUTOBUY_MERCHANT_BUTTON)
    button:RegisterForClicks("LeftButtonUp", "RightButtonUp")

    button:SetScript("OnClick", function(_, mouseButton)
        if mouseButton == "RightButton" then
            TogglePanel()
        else
            ns.AutoBuy:Toggle()
        end
    end)
    button:SetScript("OnEnter", function(entered)
        GameTooltip:SetOwner(entered, "ANCHOR_RIGHT")
        GameTooltip:SetText(ns.L.AUTOBUY_PANEL_TITLE, 1, 0.82, 0)
        if ns.AutoBuy:IsRunning() then
            GameTooltip:AddLine(ns.L.AUTOBUY_MERCHANT_STOP_HINT)
        elseif ns.AutoBuy:IsStopping() then
            GameTooltip:AddLine(ns.L.AUTOBUY_STOP_WAIT)
        else
            GameTooltip:AddLine(ns.L.AUTOBUY_MERCHANT_LEFT_CLICK)
        end
        GameTooltip:AddLine(ns.L.AUTOBUY_MERCHANT_RIGHT_CLICK)
        GameTooltip:Show()
    end)
    button:SetScript("OnLeave", function()
        GameTooltip:Hide()
    end)
    button:SetScript("OnUpdate", function(_, elapsed)
        updateElapsed = updateElapsed + elapsed
        if updateElapsed < 0.2 then
            return
        end
        updateElapsed = 0

        if MerchantFrame:IsShown() then
            local running = ns.AutoBuy:IsRunning()
            local stopping = ns.AutoBuy:IsStopping()
            if stopping then
                button:SetText(ns.L.AUTOBUY_MERCHANT_STOPPING)
            elseif running then
                button:SetText(ns.L.AUTOBUY_MERCHANT_STOP)
            else
                button:SetText(ns.L.AUTOBUY_MERCHANT_BUTTON)
            end
            button:SetAlpha((running or stopping) and 0.72 or 1)
            if panel and panel:IsShown() then
                RefreshMerchantPanel()
            end
        end
    end)
end

function MerchantUI:Refresh()
    CreateMerchantButton()
    if panel and panel:IsShown() then
        RefreshMerchantPanel()
    end
end

function MerchantUI:Initialize()
    if self.initialized then
        return
    end

    self.initialized = true
    if MerchantFrame then
        CreateMerchantButton()
        return
    end

    local waiter = CreateFrame("Frame")
    waiter:RegisterEvent("ADDON_LOADED")
    waiter:RegisterEvent("PLAYER_LOGIN")
    waiter:SetScript("OnEvent", function(frame)
        if MerchantFrame then
            frame:UnregisterAllEvents()
            CreateMerchantButton()
        end
    end)
end

function MerchantUI:HidePanel()
    if panel then
        panel:Hide()
    end
end
