local _, ns = ...

local AutoBuy = {}
ns.AutoBuy = AutoBuy

local bitBand = bit and bit.band or bit32 and bit32.band
local VERIFY_INTERVAL = 0.2
local VERIFY_TIMEOUT = 4
local MAX_CALLS_PER_BATCH = 10

local bagIndexes = { 0 }
for bag = 1, NUM_BAG_SLOTS or 4 do
    bagIndexes[#bagIndexes + 1] = bag
end

local reagentBag = Enum and Enum.BagIndex and Enum.BagIndex.ReagentBag or 5
bagIndexes[#bagIndexes + 1] = reagentBag

local PURCHASE_POPUPS = {
    "CONFIRM_PURCHASE_TOKEN_ITEM",
    "CONFIRM_PURCHASE_NONREFUNDABLE_ITEM",
    "CONFIRM_HIGH_COST_ITEM",
    "CONFIRM_MERCHANT_TRADE_TIMER_REMOVAL",
}

local eventFrame = CreateFrame("Frame")
local run
local merchantSerial = 0
local verifySerial = 0
local resumeLockedUntil = 0

local function IsStopping()
    return GetTime() < resumeLockedUntil
end

local function RefreshMerchantUI()
    if ns.AutoBuyMerchantUI and ns.AutoBuyMerchantUI.Refresh then
        ns.AutoBuyMerchantUI:Refresh()
    end
end

local function Print(message)
    ns.Addon:Print(message)
end

local function GetSettings()
    return ns.Config:GetAutoBuySettings()
end

local function GetItemLink(itemID)
    local _, link = C_Item.GetItemInfo(itemID)
    return link or tostring(itemID)
end

local function GetItemStackSize(itemID, merchantStack)
    local stackSize
    if C_Item.GetItemMaxStackSizeByID then
        stackSize = C_Item.GetItemMaxStackSizeByID(itemID)
    end

    if not stackSize or stackSize < 1 then
        stackSize = select(8, C_Item.GetItemInfo(itemID))
    end

    return math.max(stackSize or merchantStack or 1, 1)
end

local function GetItemCount(itemID)
    return C_Item.GetItemCount(itemID) or 0
end

local function FormatMoney(copper)
    if C_CurrencyInfo and C_CurrencyInfo.GetCoinTextureString then
        return C_CurrencyInfo.GetCoinTextureString(copper or 0)
    end

    return GetMoneyString and GetMoneyString(copper or 0, true) or tostring(copper or 0)
end

local function MerchantIsOpen()
    return MerchantFrame
        and MerchantFrame:IsShown()
        and (not MerchantFrame.selectedTab or MerchantFrame.selectedTab == 1)
end

local function ReadMerchantItem(index)
    if C_MerchantFrame and C_MerchantFrame.GetItemInfo then
        local info = C_MerchantFrame.GetItemInfo(index)
        if info then
            return {
                price = info.price or 0,
                stackCount = math.max(info.stackCount or 1, 1),
                numAvailable = info.numAvailable or -1,
                purchasable = info.isPurchasable ~= false,
            }
        end
    end

    if not GetMerchantItemInfo then
        return nil
    end

    local _, _, price, quantity, numAvailable, isUsable = GetMerchantItemInfo(index)
    return {
        price = price or 0,
        stackCount = math.max(quantity or 1, 1),
        numAvailable = numAvailable or -1,
        purchasable = isUsable ~= false,
    }
end

local function GetExtraCostEntries(index)
    local entries = {}
    if not GetMerchantItemCostInfo or not GetMerchantItemCostItem then
        return entries
    end

    local costCount = GetMerchantItemCostInfo(index) or 0
    costCount = math.min(costCount, MAX_ITEM_COST or costCount)
    for costIndex = 1, costCount do
        local texture, value, link, currencyName = GetMerchantItemCostItem(index, costIndex)
        if value and value > 0 and link then
            entries[#entries + 1] = {
                texture = texture,
                value = value,
                link = link,
                currencyName = currencyName,
            }
        end
    end

    return entries
end

local function GetExtraCostLimit(index)
    local limit
    for _, cost in ipairs(GetExtraCostEntries(index)) do
        local available
        if cost.currencyName and C_CurrencyInfo and C_CurrencyInfo.GetCurrencyInfoFromLink then
            local currency = C_CurrencyInfo.GetCurrencyInfoFromLink(cost.link)
            available = currency and currency.quantity
        else
            available = C_Item.GetItemCount(cost.link, false, false, true)
        end

        if available then
            limit = math.min(limit or available, math.floor(available / cost.value))
        end
    end

    return limit
end

local function FormatMerchantCost(index, units, step, info)
    local bundles = math.max(units / step, 0)
    local parts = {}
    if info.price > 0 then
        parts[#parts + 1] = FormatMoney(info.price * bundles)
    end

    for _, cost in ipairs(GetExtraCostEntries(index)) do
        parts[#parts + 1] = string.format(
            ns.L.AUTOBUY_COST_CURRENCY,
            cost.link,
            cost.value * bundles
        )
    end

    if #parts == 0 then
        return ns.L.AUTOBUY_COST_FREE
    end

    return table.concat(parts, "  ")
end

local function FindMerchantItem(itemID)
    if not MerchantIsOpen() or not GetMerchantNumItems then
        return nil
    end

    for index = 1, GetMerchantNumItems() do
        local merchantItemID = GetMerchantItemID and GetMerchantItemID(index)
        if not merchantItemID and GetMerchantItemLink then
            local link = GetMerchantItemLink(index)
            merchantItemID = type(link) == "string" and tonumber(string.match(link, "item:(%d+)"))
        end

        if merchantItemID == itemID then
            return index
        end
    end

    return nil
end

local function BagRoom(itemID, stackSize)
    local family = C_Item.GetItemFamily and C_Item.GetItemFamily(itemID) or 0
    local isReagent = select(17, C_Item.GetItemInfo(itemID))
    local room = 0

    for _, bag in ipairs(bagIndexes) do
        local fits
        if bag == reagentBag then
            fits = isReagent
        else
            local _, bagFamily = C_Container.GetContainerNumFreeSlots(bag)
            fits = not bagFamily
                or bagFamily == 0
                or (family > 0 and bitBand and bitBand(bagFamily, family) ~= 0)
        end

        if fits then
            for slot = 1, C_Container.GetContainerNumSlots(bag) do
                local containerItemID = C_Container.GetContainerItemID(bag, slot)
                if not containerItemID then
                    room = room + stackSize
                elseif containerItemID == itemID then
                    local info = C_Container.GetContainerItemInfo(bag, slot)
                    local count = info and info.stackCount or stackSize
                    room = room + math.max(stackSize - count, 0)
                end
            end
        end
    end

    return room
end

local function GetPurchaseBudget(activeRun)
    local index = FindMerchantItem(activeRun.itemID)
    if not index then
        return 0, ns.L.AUTOBUY_REASON_CLOSED
    end

    local info = ReadMerchantItem(index)
    if not info or not info.purchasable then
        return 0, ns.L.AUTOBUY_REASON_UNAVAILABLE
    end

    local step = math.max(info.stackCount, 1)
    local room = BagRoom(activeRun.itemID, activeRun.stackSize)
    local maxUnits = math.floor(math.max(room, 0) / step) * step

    if maxUnits < 1 then
        return 0, ns.L.AUTOBUY_REASON_FULL
    end

    if activeRun.quantity > 0 then
        local remainingQuantity = math.max(activeRun.quantity - activeRun.purchased, 0)
        maxUnits = math.min(maxUnits, math.floor(remainingQuantity / step) * step)
        if maxUnits < 1 then
            return 0, ns.L.AUTOBUY_REASON_QUANTITY
        end
    end

    if info.numAvailable >= 0 then
        maxUnits = math.min(maxUnits, info.numAvailable * step)
        if maxUnits < 1 then
            return 0, ns.L.AUTOBUY_REASON_STOCK
        end
    end

    if info.price > 0 then
        local affordableBundles = math.floor(GetMoney() / info.price)
        maxUnits = math.min(maxUnits, affordableBundles * step)
    end

    local extraCostLimit = GetExtraCostLimit(index)
    if extraCostLimit then
        maxUnits = math.min(maxUnits, extraCostLimit * step)
    end

    if maxUnits < 1 then
        if extraCostLimit == 0 then
            return 0, ns.L.AUTOBUY_REASON_CURRENCY
        end
        return 0, ns.L.AUTOBUY_REASON_MONEY
    end

    local callUnits = GetMerchantItemMaxStack and GetMerchantItemMaxStack(index) or step
    callUnits = math.max(math.floor((callUnits or step) / step) * step, step)
    callUnits = math.min(callUnits, maxUnits)
    local callCount = math.min(math.max(math.floor(maxUnits / callUnits), 1), MAX_CALLS_PER_BATCH)
    local purchaseUnits = callUnits * callCount
    return maxUnits, nil, index, info, purchaseUnits, callUnits, step
end

local function StopRun(reason, userRequested)
    local stoppedRun = run
    if not stoppedRun then
        return
    end

    run = nil
    verifySerial = verifySerial + 1
    if userRequested then
        resumeLockedUntil = GetTime() + 1.5
        C_Timer.After(1.6, RefreshMerchantUI)
    end

    Print(string.format(
        ns.L.AUTOBUY_FINISHED,
        GetItemLink(stoppedRun.itemID),
        stoppedRun.purchased,
        FormatMoney(stoppedRun.spentCopper),
        reason and (" " .. reason) or ""
    ))
    RefreshMerchantUI()
end

local ScheduleVerify

local function StepRun()
    if not run or run.pending then
        return
    end

    local maxUnits, reason, index, info, purchaseUnits, callUnits, step = GetPurchaseBudget(run)
    if maxUnits < 1 or not info or not purchaseUnits or not callUnits or not step then
        StopRun(reason)
        return
    end

    run.pending = true
    run.pendingUntil = GetTime() + VERIFY_TIMEOUT
    local purchaseToken = run.purchaseToken + 1
    run.purchaseToken = purchaseToken
    run.pendingUnits = purchaseUnits
    run.pendingGained = 0
    run.lastPurchasePrice = (info.price or 0) / step
    run.forcedStopReason = nil

    local issuedUnits = 0
    for _ = 1, purchaseUnits / callUnits do
        local ok = pcall(BuyMerchantItem, index, callUnits)
        if not ok then
            run.forcedStopReason = ns.L.AUTOBUY_REASON_FAILED
            break
        end
        issuedUnits = issuedUnits + callUnits
    end

    if issuedUnits < 1 then
        run.pending = false
        StopRun(run.forcedStopReason or ns.L.AUTOBUY_REASON_FAILED)
        return
    end

    run.pendingUnits = issuedUnits

    -- 高价、不可退还或货币购买会弹确认框；只在本次自动购买仍待确认时处理。
    for attempt = 1, 20 do
        C_Timer.After((attempt - 1) * 0.15, function()
            if not run or not run.pending or run.purchaseToken ~= purchaseToken then
                return
            end

            for _, popupName in ipairs(PURCHASE_POPUPS) do
                local popup = type(StaticPopup_FindVisible) == "function"
                    and StaticPopup_FindVisible(popupName)
                if popup then
                    local button = popup.GetButton1 and popup:GetButton1() or popup.button1
                    if button and button:IsEnabled() then
                        pcall(button.Click, button)
                        run.pendingUntil = math.max(run.pendingUntil, GetTime() + 2)
                    end
                    return
                end
            end
        end)
    end

    ScheduleVerify(0.5)
end

ScheduleVerify = function(delay)
    if not run or not run.pending then
        return
    end

    verifySerial = verifySerial + 1
    local serial = verifySerial
    C_Timer.After(delay, function()
        if serial ~= verifySerial or not run or not run.pending then
            return
        end

        local count = GetItemCount(run.itemID)
        if count < run.lastCount then
            run.pending = false
            StopRun(ns.L.AUTOBUY_REASON_CHANGED)
        elseif count > run.lastCount then
            local gained = count - run.lastCount
            run.purchased = run.purchased + gained
            run.pendingGained = run.pendingGained + gained
            run.spentCopper = run.spentCopper + run.lastPurchasePrice * gained
            run.lastCount = count
            if run.pendingGained >= run.pendingUnits then
                run.pending = false
                if run.forcedStopReason then
                    StopRun(run.forcedStopReason)
                else
                    StepRun()
                end
            else
                ScheduleVerify(VERIFY_INTERVAL)
            end
        elseif GetTime() < run.pendingUntil then
            ScheduleVerify(VERIFY_INTERVAL)
        else
            run.pending = false
            StopRun(run.forcedStopReason or ns.L.AUTOBUY_REASON_FAILED)
        end
    end)
end

local function StartRun(itemID, info)
    if run then
        Print(ns.L.AUTOBUY_ALREADY_RUNNING)
        return
    end

    local settings = GetSettings()
    local stackSize = GetItemStackSize(itemID, info.stackCount)
    local startCount = GetItemCount(itemID)

    run = {
        itemID = itemID,
        stackSize = stackSize,
        quantity = settings.quantity,
        spentCopper = 0,
        purchased = 0,
        lastCount = startCount,
        pending = false,
        purchaseToken = 0,
    }
    RefreshMerchantUI()

    local maxUnits, reason, index, budgetInfo, purchaseUnits, callUnits, step
    maxUnits, reason, index, budgetInfo, purchaseUnits, callUnits, step = GetPurchaseBudget(run)
    if maxUnits < 1 or not budgetInfo or not step then
        StopRun(reason)
        return
    end

    Print(string.format(
        ns.L.AUTOBUY_START,
        GetItemLink(itemID),
        maxUnits,
        FormatMerchantCost(index, maxUnits, step, budgetInfo)
    ))
    StepRun()
end

function AutoBuy:Resume()
    if run then
        return false
    end

    if IsStopping() then
        Print(ns.L.AUTOBUY_STOP_WAIT)
        return false
    end

    if not ns.Config:IsEnabled("autoBuy") then
        Print(ns.L.SETTINGS_DISABLED_AUTOBUY)
        return false
    end

    if not MerchantIsOpen() then
        Print(ns.L.AUTOBUY_OPEN_MERCHANT)
        return false
    end

    if InCombatLockdown and InCombatLockdown() then
        Print(ns.L.AUTOBUY_COMBAT)
        return false
    end

    local settings = GetSettings()
    local itemID = math.floor(tonumber(settings.itemID) or 0)
    if itemID < 1 then
        Print(ns.L.AUTOBUY_NO_ITEM)
        return false
    end

    local index = FindMerchantItem(itemID)
    if not index then
        Print(ns.L.AUTOBUY_NOT_SOLD)
        return false
    end

    local info = ReadMerchantItem(index)
    if not info or not info.purchasable then
        Print(ns.L.AUTOBUY_REASON_UNAVAILABLE)
        return false
    end

    StartRun(itemID, info)
    return true
end

function AutoBuy:Toggle()
    if run then
        StopRun(ns.L.AUTOBUY_STOPPED_BY_USER, true)
        RefreshMerchantUI()
        return false
    end
    return self:Resume()
end

function AutoBuy:GetStatusSnapshot()
    local settings = GetSettings()
    local snapshot = {
        enabled = ns.Config:IsEnabled("autoBuy"),
        itemID = math.floor(tonumber(settings.itemID) or 0),
        running = run ~= nil,
        stopping = IsStopping(),
        purchased = run and run.purchased or 0,
        merchantOpen = MerchantIsOpen(),
    }

    if snapshot.itemID > 0 then
        local name, link = C_Item.GetItemInfo(snapshot.itemID)
        snapshot.itemName = name
        snapshot.itemLink = link or tostring(snapshot.itemID)
    end

    if not snapshot.merchantOpen then
        snapshot.reason = ns.L.AUTOBUY_REASON_CLOSED
        return snapshot
    end

    if snapshot.itemID < 1 then
        snapshot.reason = ns.L.AUTOBUY_NO_ITEM
        return snapshot
    end

    local index = FindMerchantItem(snapshot.itemID)
    if not index then
        snapshot.reason = ns.L.AUTOBUY_NOT_SOLD
        return snapshot
    end

    snapshot.sold = true
    local info = ReadMerchantItem(index)
    if not info or not info.purchasable then
        snapshot.reason = ns.L.AUTOBUY_REASON_UNAVAILABLE
        return snapshot
    end

    local probe = {
        itemID = snapshot.itemID,
        stackSize = GetItemStackSize(snapshot.itemID, info.stackCount),
        quantity = settings.quantity,
        purchased = snapshot.purchased,
    }
    local maxUnits, reason, _, budgetInfo, _, _, step = GetPurchaseBudget(probe)
    snapshot.maxUnits = maxUnits
    snapshot.reason = reason
    if maxUnits > 0 and budgetInfo and step then
        snapshot.costText = FormatMerchantCost(index, maxUnits, step, budgetInfo)
    end

    return snapshot
end

function AutoBuy:IsRunning()
    return run ~= nil
end

function AutoBuy:IsStopping()
    return IsStopping()
end

local function TryStart()
    if run then
        return
    end

    local settings = GetSettings()
    if not ns.Config:IsEnabled("autoBuy") then
        return
    end

    local itemID = math.floor(tonumber(settings.itemID) or 0)
    if itemID < 1 or not MerchantIsOpen() then
        return
    end

    if InCombatLockdown and InCombatLockdown() then
        Print(ns.L.AUTOBUY_COMBAT)
        return
    end

    if C_Item.RequestLoadItemDataByID then
        pcall(C_Item.RequestLoadItemDataByID, itemID)
    end

    local index = FindMerchantItem(itemID)
    if not index then
        return
    end

    local info = ReadMerchantItem(index)
    if not info or not info.purchasable then
        return
    end

    StartRun(itemID, info)
end

local picker
local pickerCallback
local pickerButtons = {}

local function RefreshPicker()
    if not picker or not picker:IsShown() then
        return
    end

    local itemsByID = {}
    local items = {}
    for _, bag in ipairs(bagIndexes) do
        for slot = 1, C_Container.GetContainerNumSlots(bag) do
            local info = C_Container.GetContainerItemInfo(bag, slot)
            local itemID = info and info.itemID or C_Container.GetContainerItemID(bag, slot)
            if itemID then
                local entry = itemsByID[itemID]
                if not entry then
                    entry = {
                        itemID = itemID,
                        count = 0,
                    }
                    itemsByID[itemID] = entry
                    items[#items + 1] = entry
                end
                entry.count = entry.count + (info and info.stackCount or 1)
                entry.icon = entry.icon or (info and info.icon)
                entry.link = entry.link or (info and info.hyperlink)
            end
        end
    end

    local buttonIndex = 0
    local y = -4
    for _, item in ipairs(items) do
        buttonIndex = buttonIndex + 1
        local button = pickerButtons[buttonIndex]
        if not button then
            button = CreateFrame("Button", nil, picker.page, "UIPanelButtonTemplate")
            button:SetHeight(32)
            button:RegisterForClicks("LeftButtonUp")
            button:SetScript("OnClick", function(clicked)
                local callback = pickerCallback
                local itemID = clicked.itemID
                picker:Hide()
                if callback and itemID then
                    callback(itemID)
                end
            end)
            button:SetScript("OnEnter", function(entered)
                GameTooltip:SetOwner(entered, "ANCHOR_RIGHT")
                if entered.itemLink then
                    GameTooltip:SetHyperlink(entered.itemLink)
                else
                    GameTooltip:SetItemByID(entered.itemID)
                end
            end)
            button:SetScript("OnLeave", function()
                GameTooltip:Hide()
            end)
            pickerButtons[buttonIndex] = button
        end

        local _, itemLink, _, _, _, _, _, _, _, itemIcon = C_Item.GetItemInfo(item.itemID)
        local name = C_Item.GetItemNameByID and C_Item.GetItemNameByID(item.itemID)
        if not name and C_Item.RequestLoadItemDataByID then
            pcall(C_Item.RequestLoadItemDataByID, item.itemID)
        end

        local label = item.link
            or itemLink
            or name
            or string.format(ns.L.AUTOBUY_PICKER_UNKNOWN, item.itemID)
        local icon = item.icon or itemIcon or C_Item.GetItemIconByID(item.itemID)
        button:ClearAllPoints()
        button:SetPoint("TOPLEFT", picker.page, "TOPLEFT", 4, y)
        button:SetPoint("TOPRIGHT", picker.page, "TOPRIGHT", -4, y)
        button.itemID = item.itemID
        button.itemLink = item.link or itemLink
        button:SetText(string.format(
            ns.L.AUTOBUY_PICKER_ROW,
            icon and ("|T" .. icon .. ":24:24:0:0|t") or "",
            label,
            item.count
        ))
        button:GetFontString():SetJustifyH("LEFT")
        button:GetFontString():SetWordWrap(false)
        button:Show()
        y = y - 36
    end

    for index = buttonIndex + 1, #pickerButtons do
        pickerButtons[index]:Hide()
    end

    if picker.emptyText then
        picker.emptyText:SetShown(buttonIndex == 0)
    end

    picker.page:SetHeight(math.max(-y, 1))
    picker.scroll:SetVerticalScroll(0)
end

local function RefreshPickerSafe()
    local ok, message = pcall(RefreshPicker)
    if not ok then
        Print(string.format(ns.L.AUTOBUY_PICKER_ERROR, tostring(message)))
        if picker and picker.emptyText then
            picker.emptyText:SetText(ns.L.AUTOBUY_PICKER_ERROR_TEXT)
            picker.emptyText:Show()
        end
    end
end

local function CreatePicker()
    if picker then
        return picker
    end

    picker = CreateFrame(
        "Frame",
        "CheeserBagPicker",
        UIParent,
        "BasicFrameTemplateWithInset"
    )
    picker:SetSize(480, 430)
    picker:SetPoint("CENTER")
    picker:SetFrameStrata("FULLSCREEN_DIALOG")
    picker:SetFrameLevel(100)
    picker:SetClampedToScreen(true)
    picker:SetToplevel(true)
    picker:EnableMouse(true)
    picker:SetMovable(true)
    picker:RegisterForDrag("LeftButton")
    picker:SetScript("OnDragStart", picker.StartMoving)
    picker:SetScript("OnDragStop", picker.StopMovingOrSizing)
    tinsert(UISpecialFrames, "CheeserBagPicker")

    if picker.TitleText then
        picker.TitleText:SetText(ns.L.AUTOBUY_PICKER_TITLE)
    end

    if picker.CloseButton then
        picker.CloseButton:SetScript("OnClick", function()
            picker:Hide()
        end)
    end

    local hint = picker:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    hint:SetPoint("TOPLEFT", 18, -32)
    hint:SetText(ns.L.AUTOBUY_PICKER_HINT)
    hint:SetTextColor(0.7, 0.7, 0.7)

    picker.scroll = CreateFrame("ScrollFrame", nil, picker)
    picker.scroll:SetPoint("TOPLEFT", 18, -54)
    picker.scroll:SetPoint("BOTTOMRIGHT", -18, 18)
    picker.scroll:EnableMouseWheel(true)

    picker.page = CreateFrame("Frame", nil, picker.scroll)
    picker.page:SetWidth(420)
    picker.scroll:SetScrollChild(picker.page)

    picker.scroll:SetScript("OnMouseWheel", function(scroll, delta)
        local range = scroll:GetVerticalScrollRange()
        local value = scroll:GetVerticalScroll() - delta * 40
        scroll:SetVerticalScroll(math.min(math.max(value, 0), range))
    end)
    picker.emptyText = picker:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    picker.emptyText:SetPoint("CENTER", picker.scroll, "CENTER", 0, 0)
    picker.emptyText:SetText(ns.L.AUTOBUY_PICKER_EMPTY)
    picker.emptyText:SetTextColor(0.65, 0.65, 0.65)
    picker.emptyText:Hide()
    picker:SetScript("OnShow", RefreshPickerSafe)
    picker:SetScript("OnEvent", function()
        if picker:IsShown() then
            RefreshPickerSafe()
        end
    end)
    picker:RegisterEvent("BAG_UPDATE_DELAYED")
    return picker
end

function AutoBuy:ShowBagPicker(callback)
    pickerCallback = callback
    CreatePicker()
    -- 设置页位于全屏对话框层；每次打开都重新置顶，避免被其画布遮住。
    picker:SetFrameStrata("FULLSCREEN_DIALOG")
    picker:SetFrameLevel(100)
    picker:Show()
    picker:Raise()
    RefreshPickerSafe()
    C_Timer.After(0, function()
        if picker:IsShown() then
            picker:Raise()
            RefreshPickerSafe()
        end
    end)
end

function AutoBuy:Initialize()
    if self.initialized then
        return
    end

    self.initialized = true
    eventFrame:RegisterEvent("MERCHANT_SHOW")
    eventFrame:RegisterEvent("MERCHANT_CLOSED")
    eventFrame:RegisterEvent("BAG_UPDATE_DELAYED")
    eventFrame:RegisterEvent("UI_ERROR_MESSAGE")
    eventFrame:RegisterEvent("GET_ITEM_INFO_RECEIVED")
    eventFrame:SetScript("OnEvent", function(_, event, arg1, arg2)
        if event == "MERCHANT_SHOW" then
            merchantSerial = merchantSerial + 1
            RefreshMerchantUI()
            local serial = merchantSerial
            C_Timer.After(0.25, function()
                if serial == merchantSerial and MerchantIsOpen() then
                    TryStart()
                end
            end)
        elseif event == "MERCHANT_CLOSED" then
            merchantSerial = merchantSerial + 1
            StopRun(ns.L.AUTOBUY_REASON_CLOSED)
            if ns.AutoBuyMerchantUI then
                ns.AutoBuyMerchantUI:HidePanel()
            end
        elseif event == "BAG_UPDATE_DELAYED" then
            if run and run.pending then
                ScheduleVerify(0)
            end
        elseif event == "UI_ERROR_MESSAGE" then
            if run then
                local detail = type(arg2) == "string" and (" " .. arg2) or ""
                local reason = ns.L.AUTOBUY_REASON_ERROR .. detail
                if run.pending and run.pendingUnits > 0 then
                    run.forcedStopReason = reason
                else
                    StopRun(reason)
                end
            end
        elseif event == "GET_ITEM_INFO_RECEIVED"
            and tonumber(arg1) == tonumber(GetSettings().itemID) then
            ns.Config:RefreshPanel()
            RefreshMerchantUI()
        end
    end)
end

function AutoBuy:OnSettingsChanged()
    if run then
        StopRun(ns.L.AUTOBUY_REASON_DISABLED)
    end
    RefreshMerchantUI()
end
