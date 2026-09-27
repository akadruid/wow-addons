local ADDON_NAME, ns = ...

local Addon = CreateFrame("Frame")
ns.Addon = Addon

function Addon:Print(message)
    local text = "|cff33ff99" .. ns.L.ADDON_NAME .. "|r: " .. tostring(message)
    local printed = false

    for index = 1, NUM_CHAT_WINDOWS or 10 do
        local chatFrame = _G["ChatFrame" .. index]
        if chatFrame then
            chatFrame:AddMessage(text)
            printed = true
        end
    end

    if not printed and DEFAULT_CHAT_FRAME then
        DEFAULT_CHAT_FRAME:AddMessage(text)
    end
end

function Addon:RefreshAll(requestServer)
    if requestServer then
        ns.Roster:RequestUpdate()
    end
    ns.Roster:Refresh()
    if ns.UI then
        ns.UI:Refresh()
    end
end

function Addon:ScheduleRunestoneAutoCheck()
    if not ns.Config:IsEnabled("runestone") then
        return
    end

    if self.runestoneCheckPending then
        return
    end

    self.runestoneCheckPending = true
    C_Timer.After(1, function()
        self.runestoneCheckPending = false
        ns.Runestone:CheckAutomatic(true)
    end)
end

function Addon:LeavePartyWithoutConfirmation()
    if IsInRaid() then
        self:Print(ns.L.LEAVE_PARTY_RAID_BLOCKED)
        return
    end

    if not IsInGroup() then
        self:Print(ns.L.LEAVE_PARTY_NO_GROUP)
        return
    end

    if not C_PartyInfo or type(C_PartyInfo.ConfirmLeaveParty) ~= "function" then
        self:Print(ns.L.LEAVE_PARTY_UNSUPPORTED)
        return
    end

    C_PartyInfo.ConfirmLeaveParty()
    self:Print(ns.L.LEAVE_PARTY_DONE)
end

function Addon:OnAddonLoaded(name)
    if name ~= ADDON_NAME then
        return
    end

    AzerothAssistantDB = AzerothAssistantDB or GuildPartyInviterDB or {}
    self.db = AzerothAssistantDB

    self:UnregisterEvent("ADDON_LOADED")
    self:RegisterEvent("PLAYER_ENTERING_WORLD")
    self:RegisterEvent("GUILD_ROSTER_UPDATE")
    self:RegisterEvent("GROUP_ROSTER_UPDATE")
    self:RegisterEvent("PLAYER_GUILD_UPDATE")
    self:RegisterEvent("UPDATE_BINDINGS")
    self:RegisterEvent("ZONE_CHANGED_NEW_AREA")
    self:RegisterEvent("GOSSIP_SHOW")
    self:RegisterEvent("GOSSIP_CLOSED")
    self:RegisterEvent("QUEST_GREETING")

    ns.UI:Create()
    ns.MeetingStoneFavorites:Initialize()
    ns.Talk.Initialize()
    ns.Config:Apply()

    SLASH_AZEROTHASSISTANT1 = "/aa"
    SLASH_AZEROTHASSISTANT2 = "/assistant"
    SLASH_AZEROTHASSISTANT3 = "/gpi"
    SlashCmdList.AZEROTHASSISTANT = function(message)
        local command = string.lower((message or ""):match("^%s*(.-)%s*$"))
        if command == "refresh" then
            self:RefreshAll(true)
            self:Print(ns.L.REFRESH)
        elseif command == "lock" then
            ns.UI:SetQuickBarLocked(true)
        elseif command == "unlock" then
            ns.UI:SetQuickBarLocked(false)
        elseif command == "rune" or command == "runestone" then
            if ns.Config:IsEnabled("runestone") then
                ns.Runestone:PrintStatus()
            else
                self:Print(ns.L.SETTINGS_DISABLED_RUNESTONE)
            end
        elseif command == "rune debug" or command == "runestone debug" then
            if ns.Config:IsEnabled("runestone") then
                ns.Runestone:PrintDebug()
            else
                self:Print(ns.L.SETTINGS_DISABLED_RUNESTONE)
            end
        elseif command == "config" or command == "settings" or command == "options" then
            ns.Config:Open()
        elseif command == "leave" then
            self:LeavePartyWithoutConfirmation()
        elseif command == "talk" then
            ns.Talk.PrintStatus()
        elseif command == "talk on" then
            ns.Talk.SetEnabled(true)
        elseif command == "talk off" then
            ns.Talk.SetEnabled(false)
        elseif command == "talk list" then
            ns.Talk.PrintRules()
        elseif command == "stone" or command == "meetingstone" then
            ns.MeetingStoneFavorites:ToggleUI()
        elseif command == "stone on" then
            ns.MeetingStoneFavorites:SetEnabled(true)
        elseif command == "stone off" then
            ns.MeetingStoneFavorites:SetEnabled(false)
        elseif command == "stone list" then
            ns.MeetingStoneFavorites:PrintList()
        elseif command == "stone reset" then
            ns.MeetingStoneFavorites:ResetEntries()
            self:Print(ns.L.MEETINGSTONE_RESET)
        elseif command == "stone addcurrent" then
            ns.MeetingStoneFavorites:AddCurrentSearch()
        elseif string.sub(command, 1, 9) == "stone add" then
            local value = string.match(command, "^stone%s+add%s+(.+)$")
            if ns.MeetingStoneFavorites:AddEntry(value) then
                self:Print(string.format(ns.L.MEETINGSTONE_ADDED, value))
            else
                self:Print(ns.L.MEETINGSTONE_ADD_FAILED)
            end
        elseif string.sub(command, 1, 12) == "stone remove" then
            local value = string.match(command, "^stone%s+remove%s+(.+)$")
            local index = tonumber(value)
            if not index then
                local settings = ns.MeetingStoneFavorites:GetDb()
                local lowerValue = string.lower(value)
                for entryIndex, entry in ipairs(settings.entries) do
                    if string.lower(entry) == lowerValue then
                        index = entryIndex
                        break
                    end
                end
            end
            if index and ns.MeetingStoneFavorites:RemoveEntry(index) then
                self:Print(string.format(ns.L.MEETINGSTONE_REMOVED, value))
            else
                self:Print(ns.L.MEETINGSTONE_REMOVE_FAILED)
            end
        else
            ns.UI:Toggle()
        end
    end

    self:RefreshAll(true)
    self:ScheduleRunestoneAutoCheck()

    self.runestoneTicker = C_Timer.NewTicker(2, function()
        if ns.Config:IsEnabled("runestone") then
            ns.Runestone:CheckAutomatic(false)
        end
    end)
end

function Addon:OnEvent(event, ...)
    if event == "ADDON_LOADED" then
        self:OnAddonLoaded(...)
    elseif event == "PLAYER_ENTERING_WORLD" then
        self:RefreshAll(true)
        self:ScheduleRunestoneAutoCheck()
    elseif event == "GUILD_ROSTER_UPDATE" then
        local canRequestRosterUpdate = ...
        if canRequestRosterUpdate then
            ns.Roster:RequestUpdate()
        end
        self:RefreshAll(false)
    elseif event == "GROUP_ROSTER_UPDATE" then
        self:RefreshAll(false)
        self:ScheduleRunestoneAutoCheck()
    elseif event == "PLAYER_GUILD_UPDATE" then
        self:RefreshAll(false)
    elseif event == "ZONE_CHANGED_NEW_AREA" then
        self:ScheduleRunestoneAutoCheck()
    elseif event == "UPDATE_BINDINGS" then
        ns.UI:Refresh()
    elseif event == "GOSSIP_SHOW" then
        ns.Talk.OnGossipShow()
    elseif event == "GOSSIP_CLOSED" then
        ns.Talk.OnGossipClosed()
    elseif event == "QUEST_GREETING" then
        ns.Talk.OnQuestGreeting()
    end
end

Addon:SetScript("OnEvent", Addon.OnEvent)
Addon:RegisterEvent("ADDON_LOADED")
