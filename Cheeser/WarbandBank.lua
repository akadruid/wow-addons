local _, ns = ...

local WarbandBank = {}
ns.WarbandBank = WarbandBank

local eventFrame = CreateFrame("Frame")
local bankOpen = false
local bankSession = 0
local depositScheduled = false
local depositDone = false
local portableAccountBank = false
local bankTypeTicker

local function IsPortableAccountBank()
    local manager = C_PlayerInteractionManager
    local interactionType = Enum and Enum.PlayerInteractionType
    return manager
        and interactionType
        and interactionType.AccountBanker
        and type(manager.IsInteractingWithNpcOfType) == "function"
        and manager.IsInteractingWithNpcOfType(interactionType.AccountBanker)
        or false
end

local function GetActiveBankType()
    local genericGetter = _G.Addon_GetBankType
    if type(genericGetter) == "function" then
        local ok, bankType = pcall(genericGetter)
        if ok and bankType ~= nil then
            return bankType
        end
    end

    local bankFrame = _G.BankFrame
    if bankFrame and type(bankFrame.GetActiveBankType) == "function" then
        local ok, bankType = pcall(bankFrame.GetActiveBankType, bankFrame)
        if ok then
            return bankType
        end
    end

    return nil
end

local function IsWarbandBankActive()
    if portableAccountBank then
        return true
    end

    local bankType = Enum and Enum.BankType and Enum.BankType.Account
    return bankType ~= nil and GetActiveBankType() == bankType
end

local function StopBankTypePolling()
    if bankTypeTicker then
        bankTypeTicker:Cancel()
        bankTypeTicker = nil
    end
end

local function CanDeposit()
    if not bankOpen
        or depositDone
        or not ns.Config:IsEnabled("warbandBank")
        or not IsWarbandBankActive() then
        return false
    end

    if InCombatLockdown and InCombatLockdown() then
        return false
    end

    local bankType = Enum and Enum.BankType and Enum.BankType.Account
    if not bankType
        or not C_Bank
        or type(C_Bank.AutoDepositItemsIntoBank) ~= "function" then
        return false
    end

    if type(C_Bank.CanUseBank) == "function"
        and not C_Bank.CanUseBank(bankType) then
        return false
    end

    if type(C_Bank.DoesBankTypeSupportAutoDeposit) == "function"
        and not C_Bank.DoesBankTypeSupportAutoDeposit(bankType) then
        return false
    end

    if type(C_Bank.FetchBankLockedReason) == "function"
        and C_Bank.FetchBankLockedReason(bankType) ~= nil then
        return false
    end

    return true
end

local function TryDeposit()
    if not CanDeposit() then
        return false
    end

    local ok = pcall(
        C_Bank.AutoDepositItemsIntoBank,
        Enum.BankType.Account
    )
    if ok then
        depositDone = true
        StopBankTypePolling()
        ns.Addon:Print(ns.L.WARBAND_BANK_DEPOSIT_TRIGGERED)
    end
    return ok
end

local function ScheduleDeposit()
    if depositScheduled or depositDone or not bankOpen then
        return
    end

    depositScheduled = true
    local scheduledSession = bankSession
    C_Timer.After(0.4, function()
        if scheduledSession ~= bankSession then
            return
        end

        local deadline = GetTime() + 2.5
        local function Attempt()
            if scheduledSession ~= bankSession or not bankOpen or depositDone then
                if scheduledSession == bankSession then
                    depositScheduled = false
                end
                return
            end

            if TryDeposit() then
                depositScheduled = false
            elseif GetTime() < deadline then
                C_Timer.After(0.25, Attempt)
            else
                depositScheduled = false
            end
        end

        Attempt()
    end)
end

local function CheckBankType()
    if not bankOpen
        or depositDone
        or not ns.Config:IsEnabled("warbandBank") then
        StopBankTypePolling()
        return
    end

    if IsWarbandBankActive() then
        ScheduleDeposit()
    end
end

local function StartBankTypePolling()
    if bankTypeTicker or not bankOpen then
        return
    end

    CheckBankType()
    if bankOpen and not depositDone and ns.Config:IsEnabled("warbandBank") then
        bankTypeTicker = C_Timer.NewTicker(0.5, CheckBankType)
    end
end

local function OnBankOpened()
    bankOpen = true
    bankSession = bankSession + 1
    depositScheduled = false
    depositDone = false
    portableAccountBank = IsPortableAccountBank()

    StartBankTypePolling()
end

local function OnBankClosed()
    StopBankTypePolling()
    bankOpen = false
    bankSession = bankSession + 1
    depositScheduled = false
    depositDone = false
    portableAccountBank = false
end

function WarbandBank:Initialize()
    if self.initialized then
        return
    end

    self.initialized = true
    eventFrame:RegisterEvent("BANKFRAME_OPENED")
    eventFrame:RegisterEvent("BANKFRAME_CLOSED")
    eventFrame:SetScript("OnEvent", function(_, event)
        if event == "BANKFRAME_OPENED" then
            OnBankOpened()
        elseif event == "BANKFRAME_CLOSED" then
            OnBankClosed()
        end
    end)
end

function WarbandBank:OnSettingsChanged()
    if not ns.Config:IsEnabled("warbandBank") then
        StopBankTypePolling()
        bankSession = bankSession + 1
        depositScheduled = false
    elseif bankOpen then
        StartBankTypePolling()
    end
end
