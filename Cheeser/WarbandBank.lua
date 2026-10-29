local _, ns = ...

local WarbandBank = {}
ns.WarbandBank = WarbandBank

local eventFrame = CreateFrame("Frame")
local bankOpen = false
local bankSession = 0
local depositScheduled = false
local depositDone = false
local refreshHooked = false

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

local function IsEllesmereWarbandViewVisible()
    local bankFrame = _G.EUI_BankFrame
    return bankFrame
        and type(bankFrame.IsVisible) == "function"
        and type(bankFrame.IsWarbandView) == "function"
        and bankFrame:IsVisible()
        and bankFrame:IsWarbandView()
        or false
end

local function CanDeposit()
    if not bankOpen
        or depositDone
        or not ns.Config:IsEnabled("warbandBank")
        or not IsEllesmereWarbandViewVisible() then
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

local function InstallEllesmereHook()
    if refreshHooked then
        return
    end

    local bankFrame = _G.EUI_BankFrame
    if not bankFrame or type(bankFrame.RefreshBank) ~= "function" then
        return
    end

    local ok = pcall(hooksecurefunc, bankFrame, "RefreshBank", function()
        if bankOpen and IsEllesmereWarbandViewVisible() then
            ScheduleDeposit()
        end
    end)
    if ok then
        refreshHooked = true
    end
end

local function OnBankOpened()
    bankOpen = true
    bankSession = bankSession + 1
    depositScheduled = false
    depositDone = false

    if IsPortableAccountBank() or IsEllesmereWarbandViewVisible() then
        ScheduleDeposit()
    end
end

local function OnBankClosed()
    bankOpen = false
    bankSession = bankSession + 1
    depositScheduled = false
    depositDone = false
end

function WarbandBank:Initialize()
    if self.initialized then
        return
    end

    self.initialized = true
    eventFrame:RegisterEvent("ADDON_LOADED")
    eventFrame:RegisterEvent("PLAYER_LOGIN")
    eventFrame:RegisterEvent("BANKFRAME_OPENED")
    eventFrame:RegisterEvent("BANKFRAME_CLOSED")
    eventFrame:SetScript("OnEvent", function(_, event, addonName)
        if event == "BANKFRAME_OPENED" then
            OnBankOpened()
        elseif event == "BANKFRAME_CLOSED" then
            OnBankClosed()
        elseif event == "ADDON_LOADED" and addonName == "EllesmereUIBags" then
            InstallEllesmereHook()
        elseif event == "PLAYER_LOGIN" then
            InstallEllesmereHook()
        end
    end)
end

function WarbandBank:OnSettingsChanged()
    if not ns.Config:IsEnabled("warbandBank") then
        bankSession = bankSession + 1
        depositScheduled = false
    end
end
