local _, ns = ...

local Favorites = {
    frame = nil,
    rows = {},
    originalGetHistoryList = nil,
    hookedProfile = nil,
}

ns.MeetingStoneFavorites = Favorites

local DEFAULT_FAVORITES = {
    "1-397-1943-0", -- Eversong Woods (永歌森林)
}

local MAX_VISIBLE_FAVORITES = 8

local function GetMeetingStoneEnvironment()
    local envLibrary = LibStub and LibStub("NetEaseEnv-1.0", true)
    if not envLibrary or type(envLibrary._NSList) ~= "table" then
        return nil
    end
    return envLibrary._NSList.MeetingStone
end

local function GetMeetingStoneValue(name)
    local environment = GetMeetingStoneEnvironment()
    local value = environment and environment[name]
    if value ~= nil then
        return value
    end
    return _G[name]
end

local function FindMeetingStoneProfile()
    local environment = GetMeetingStoneEnvironment()
    if environment and type(environment.Profile) == "table" then
        return environment.Profile
    end

    local envLibrary = LibStub and LibStub("NetEaseEnv-1.0", true)
    if envLibrary and type(envLibrary._NSList) == "table" then
        for _, namespace in pairs(envLibrary._NSList) do
            local profile = namespace.Profile
            if type(profile) == "table" and type(profile.GetHistoryList) == "function" then
                return profile
            end
        end
    end

    return _G.Profile
end

local function Trim(value)
    return string.match(value or "", "^%s*(.-)%s*$") or ""
end

local function IsActivityCode(value)
    return string.match(value or "", "^%d+%-%d+%-%d+%-%d+$") ~= nil
end

local function CopyDefaults()
    local result = {}
    for _, value in ipairs(DEFAULT_FAVORITES) do
        result[#result + 1] = value
    end
    return result
end

local function GetActivityIDFromCode(code)
    local _, _, activityID = string.match(code or "", "^(%d+)%-(%d+)%-(%d+)%-(%d+)$")
    return tonumber(activityID)
end

local function GetActivityNameFromCode(code)
    local activityID = GetActivityIDFromCode(code)
    if not activityID or activityID == 0 or not C_LFGList then
        return nil
    end
    local info = C_LFGList.GetActivityInfoTable(activityID)
    return info and info.fullName or nil
end

function Favorites:GetDb()
    local db = ns.Addon.db
    local settings = db.meetingStoneFavorites
    if not settings then
        settings = {
            enabled = true,
            entries = CopyDefaults(),
        }
        db.meetingStoneFavorites = settings
    end
    settings.entries = settings.entries or CopyDefaults()
    if settings.enabled == nil then
        settings.enabled = true
    end
    return settings
end

function Favorites:ResolveEntry(entry)
    entry = Trim(entry)
    if entry == "" then
        return {}
    end
    if IsActivityCode(entry) then
        return { entry }
    end
    if not C_LFGList or type(C_LFGList.GetAvailableActivities) ~= "function" then
        return {}
    end

    local activityIDs = C_LFGList.GetAvailableActivities(nil, nil, nil, entry)
    local result = {}
    local seen = {}
    for _, activityID in ipairs(activityIDs or {}) do
        local info = C_LFGList.GetActivityInfoTable(activityID)
        if info then
            local code = string.format(
                "%d-%d-%d-0",
                info.categoryID or 0,
                info.groupFinderActivityGroupID or 0,
                activityID
            )
            if not seen[code] then
                seen[code] = true
                result[#result + 1] = code
            end
        end
    end
    return result
end

function Favorites:GetResolvedEntries()
    local settings = self:GetDb()
    local result = {}
    local seen = {}

    for _, entry in ipairs(settings.entries) do
        for _, code in ipairs(self:ResolveEntry(entry)) do
            if not seen[code] then
                seen[code] = true
                result[#result + 1] = code
            end
        end
    end
    return result
end

function Favorites:GetEntryLabel(entry)
    local resolved = self:ResolveEntry(entry)
    if #resolved == 0 then
        return entry
    end

    local names = {}
    local seen = {}
    for _, code in ipairs(resolved) do
        local name = GetActivityNameFromCode(code) or code
        if not seen[name] then
            seen[name] = true
            names[#names + 1] = name
        end
    end
    return table.concat(names, " / ")
end

function Favorites:MergeHistory(history)
    local merged = {}
    local seen = {}

    local settings = self:GetDb()
    if settings.enabled then
        for _, code in ipairs(self:GetResolvedEntries()) do
            if not seen[code] then
                seen[code] = true
                merged[#merged + 1] = code
            end
        end
    end

    for _, code in ipairs(history or {}) do
        if not seen[code] then
            seen[code] = true
            merged[#merged + 1] = code
        end
    end
    return merged
end

function Favorites:RefreshMeetingStoneMenu()
    local refreshHistoryMenuTable = GetMeetingStoneValue("RefreshHistoryMenuTable")
    local activityFilterBrowse = GetMeetingStoneValue("ACTIVITY_FILTER_BROWSE")
    if type(refreshHistoryMenuTable) ~= "function" or not activityFilterBrowse then
        return
    end

    C_Timer.After(0, function()
        if type(refreshHistoryMenuTable) == "function" then
            refreshHistoryMenuTable(activityFilterBrowse)
        end
    end)
end

function Favorites:HookProfile(profile)
    if self.hookedProfile == profile then
        return true
    end
    if not profile or type(profile.GetHistoryList) ~= "function" then
        return false
    end

    local original = profile.GetHistoryList
    self.originalGetHistoryList = original
    self.hookedProfile = profile
    profile.GetHistoryList = function(self, isCreator)
        local history = original(self, isCreator)
        if isCreator then
            return history
        end
        return Favorites:MergeHistory(history)
    end

    self:RefreshMeetingStoneMenu()
    return true
end

function Favorites:TryHook()
    local profile = FindMeetingStoneProfile()
    if self:HookProfile(profile) then
        if self.frame then
            self:RefreshUI()
        end
        return true
    end
    return false
end

function Favorites:AddEntry(entry)
    entry = Trim(entry)
    if entry == "" then
        return false
    end

    local settings = self:GetDb()
    for _, existing in ipairs(settings.entries) do
        if existing == entry then
            return false
        end
    end

    settings.entries[#settings.entries + 1] = entry
    self:RefreshMeetingStoneMenu()
    self:RefreshUI()
    return true
end

function Favorites:RemoveEntry(index)
    local settings = self:GetDb()
    if not settings.entries[index] then
        return false
    end

    table.remove(settings.entries, index)
    self:RefreshMeetingStoneMenu()
    self:RefreshUI()
    return true
end

function Favorites:AddCurrentSearch()
    local profile = FindMeetingStoneProfile()
    if not profile or type(profile.GetLastSearchCode) ~= "function" then
        ns.Addon:Print(ns.L.MEETINGSTONE_NOT_LOADED)
        return false
    end

    local code = profile:GetLastSearchCode()
    local activityID = GetActivityIDFromCode(code)
    if not code or not activityID or activityID == 0 then
        ns.Addon:Print(ns.L.MEETINGSTONE_NO_CURRENT_SEARCH)
        return false
    end

    if not self:AddEntry(code) then
        ns.Addon:Print(ns.L.MEETINGSTONE_ADD_FAILED)
        return false
    end

    local name = GetActivityNameFromCode(code)
    if name then
        ns.Addon:Print(string.format(ns.L.MEETINGSTONE_ADDED_NAMED, name))
    else
        ns.Addon:Print(string.format(ns.L.MEETINGSTONE_ADDED, code))
    end
    return true
end

function Favorites:ResetEntries()
    local settings = self:GetDb()
    settings.entries = CopyDefaults()
    self:RefreshMeetingStoneMenu()
    self:RefreshUI()
end

function Favorites:SetEnabled(enabled)
    self:GetDb().enabled = enabled and true or false
    self:RefreshMeetingStoneMenu()
    self:RefreshUI()
end

function Favorites:PrintList()
    local settings = self:GetDb()
    ns.Addon:Print(string.format(ns.L.MEETINGSTONE_ENABLED, settings.enabled and ns.L.ON or ns.L.OFF))
    if #settings.entries == 0 then
        ns.Addon:Print(ns.L.MEETINGSTONE_LIST_EMPTY)
        return
    end

    for index, entry in ipairs(settings.entries) do
        ns.Addon:Print(string.format("%d. %s [%s]", index, self:GetEntryLabel(entry), entry))
    end
end

function Favorites:CreateRow(index)
    local row = CreateFrame("Frame", nil, self.frame)
    row:SetSize(430, 26)
    row:SetPoint("TOPLEFT", self.frame, "TOPLEFT", 24, -118 - (index - 1) * 28)

    row.IndexText = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    row.IndexText:SetPoint("LEFT", row, "LEFT", 0, 0)
    row.IndexText:SetWidth(24)
    row.IndexText:SetJustifyH("RIGHT")

    row.EntryText = row:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    row.EntryText:SetPoint("LEFT", row.IndexText, "RIGHT", 10, 0)
    row.EntryText:SetPoint("RIGHT", row, "RIGHT", -34, 0)
    row.EntryText:SetJustifyH("LEFT")

    row.RemoveButton = CreateFrame("Button", nil, row, "UIPanelCloseButton")
    row.RemoveButton:SetSize(22, 22)
    row.RemoveButton:SetPoint("RIGHT", row, "RIGHT", 0, 0)
    row.RemoveButton:SetScript("OnClick", function()
        Favorites:RemoveEntry(row.index)
    end)

    self.rows[index] = row
end

function Favorites:RefreshUI()
    if not self.frame then
        return
    end

    local settings = self:GetDb()
    self.enabledCheck:SetChecked(settings.enabled)

    for index = 1, MAX_VISIBLE_FAVORITES do
        local row = self.rows[index]
        local entry = settings.entries[index]
        if entry then
            row.index = index
            row.IndexText:SetText(tostring(index) .. ".")
            row.EntryText:SetText(self:GetEntryLabel(entry))
            row:Show()
        else
            row.index = nil
            row:Hide()
        end
    end
end

function Favorites:CreateUI()
    if self.frame then
        return
    end

    local frame = CreateFrame("Frame", "CheeserMeetingStoneFrame", UIParent, "BackdropTemplate")
    self.frame = frame
    frame:SetSize(480, 410)
    frame:SetPoint("CENTER")
    frame:SetFrameStrata("DIALOG")
    frame:SetClampedToScreen(true)
    frame:SetMovable(true)
    frame:EnableMouse(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetBackdrop({
        bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
        edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
        tile = true,
        tileSize = 32,
        edgeSize = 32,
        insets = { left = 8, right = 8, top = 8, bottom = 8 },
    })
    frame:SetScript("OnDragStart", frame.StartMoving)
    frame:SetScript("OnDragStop", frame.StopMovingOrSizing)

    frame.Title = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    frame.Title:SetPoint("TOPLEFT", frame, "TOPLEFT", 24, -18)
    frame.Title:SetText(ns.L.MEETINGSTONE_TITLE)

    local closeButton = CreateFrame("Button", nil, frame, "UIPanelCloseButton")
    closeButton:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -10, -10)

    local enabledCheck = CreateFrame("CheckButton", nil, frame, "InterfaceOptionsCheckButtonTemplate")
    self.enabledCheck = enabledCheck
    enabledCheck:SetPoint("TOPLEFT", frame, "TOPLEFT", 22, -50)
    enabledCheck.Text:SetText(ns.L.MEETINGSTONE_ENABLE)
    enabledCheck:SetScript("OnClick", function(button)
        Favorites:SetEnabled(button:GetChecked())
    end)

    local hint = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    hint:SetPoint("TOPLEFT", enabledCheck, "BOTTOMLEFT", 4, -4)
    hint:SetText(ns.L.MEETINGSTONE_HINT)

    for index = 1, MAX_VISIBLE_FAVORITES do
        self:CreateRow(index)
    end

    local inputLabel = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    inputLabel:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 24, 58)
    inputLabel:SetText(ns.L.MEETINGSTONE_ENTRY)

    local input = CreateFrame("EditBox", nil, frame, "InputBoxTemplate")
    self.input = input
    input:SetSize(230, 26)
    input:SetPoint("LEFT", inputLabel, "RIGHT", 10, 0)
    input:SetAutoFocus(false)
    input:SetTextInsets(8, 8, 0, 0)
    input:SetScript("OnEnterPressed", function(editBox)
        if Favorites:AddEntry(editBox:GetText()) then
            editBox:SetText("")
        end
        editBox:ClearFocus()
    end)
    input:SetScript("OnEscapePressed", function(editBox)
        editBox:ClearFocus()
    end)

    local addButton = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    addButton:SetSize(80, 24)
    addButton:SetPoint("LEFT", input, "RIGHT", 8, 0)
    addButton:SetText(ns.L.MEETINGSTONE_ADD)
    addButton:SetScript("OnClick", function()
        if Favorites:AddEntry(input:GetText()) then
            input:SetText("")
        end
        input:ClearFocus()
    end)

    local addCurrentButton = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    addCurrentButton:SetSize(130, 24)
    addCurrentButton:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 24, 20)
    addCurrentButton:SetText(ns.L.MEETINGSTONE_ADD_CURRENT)
    addCurrentButton:SetScript("OnClick", function()
        Favorites:AddCurrentSearch()
    end)

    if UISpecialFrames then
        UISpecialFrames[#UISpecialFrames + 1] = "CheeserMeetingStoneFrame"
    end

    frame:Hide()
end

function Favorites:ToggleUI()
    self:CreateUI()
    if self.frame:IsShown() then
        self.frame:Hide()
    else
        self:RefreshUI()
        self.frame:Show()
    end
end

function Favorites:Initialize()
    self:GetDb()
    self:TryHook()

    local watcher = CreateFrame("Frame")
    watcher:RegisterEvent("ADDON_LOADED")
    watcher:RegisterEvent("PLAYER_ENTERING_WORLD")
    watcher:SetScript("OnEvent", function(_, event, addonName)
        if event == "PLAYER_ENTERING_WORLD" or addonName == "MeetingStone" then
            Favorites:TryHook()
        end
    end)
end
