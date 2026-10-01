local _, ns = ...

local Runestone = {}
ns.Runestone = Runestone

local tooltip

local EVERSONG_WOODS_MAP_ID = 2395

local RUNESTONE_VIGNETTE_IDS = {
    [6951] = true,
    [6954] = true,
    [6955] = true,
    [6959] = true,
    [7130] = true,
}

local RUNESTONE_LOCATIONS = {
    [6951] = "左中",
    [6954] = "右下",
    [6955] = "中间",
    [6959] = "左下",
    [7130] = "左上",
}

local RUNESTONE_WEEKLY_QUESTS = {
    90574, -- Fortify the Runestones: Blood Knights
    90573, -- Fortify the Runestones: Magisters
    90575, -- Fortify the Runestones: Farstriders
    90576, -- Fortify the Runestones: Shades of the Row
}

local EVERSONG_MAP_IDS = {
    [2395] = true,
    [2594] = true,
}

local function IsRunestoneName(name)
    if not name or name == "" then
        return false
    end
    return string.find(name, "符文石", 1, true) ~= nil
        or string.find(string.lower(name), "runestone", 1, true) ~= nil
end

local function CollectText(region, result, visited)
    if not region or visited[region] then
        return
    end
    visited[region] = true

    if type(region.GetText) == "function" then
        local text = region:GetText()
        if text and text ~= "" then
            result[#result + 1] = text
        end
    end

    if type(region.GetChildren) == "function" then
        for _, child in ipairs({ region:GetChildren() }) do
            CollectText(child, result, visited)
        end
    end

    if type(region.GetRegions) == "function" then
        for _, child in ipairs({ region:GetRegions() }) do
            CollectText(child, result, visited)
        end
    end
end

local function GetRunestoneTooltipText(vignetteInfo)
    if not vignetteInfo
        or not vignetteInfo.tooltipWidgetSet
        or type(GameTooltip_AddWidgetSet) ~= "function"
        or type(GameTooltip_ClearWidgetSet) ~= "function" then
        return nil
    end

    if not tooltip then
        tooltip = CreateFrame("GameTooltip", "CheeserRunestoneTooltip", UIParent, "GameTooltipTemplate")
        tooltip:SetOwner(UIParent, "ANCHOR_NONE")
        tooltip:Hide()
    end

    GameTooltip_ClearWidgetSet(tooltip)
    GameTooltip_AddWidgetSet(tooltip, vignetteInfo.tooltipWidgetSet)

    local result = {}
    if tooltip.widgetContainer then
        CollectText(tooltip.widgetContainer, result, {})
    end
    GameTooltip_ClearWidgetSet(tooltip)

    if #result == 0 then
        return nil
    end
    return table.concat(result, "\n")
end

local function GetRunestoneActivationState(vignetteInfo)
    local text = GetRunestoneTooltipText(vignetteInfo)
    if not text then
        return nil
    end

    local lowerText = string.lower(text)
    if string.find(text, "需要充能", 1, true)
        or string.find(text, "潜藏奥能", 1, true)
        or string.find(lowerText, "latent arcana", 1, true)
        or string.find(lowerText, "recharge", 1, true) then
        return false
    end

    if string.find(text, "符文石状态", 1, true)
        or string.find(lowerText, "runestone status", 1, true) then
        return true
    end

    return nil
end

local function GetRunestonePosition(vignetteGUID)
    if type(C_VignetteInfo.GetVignettePosition) ~= "function" then
        return nil
    end

    -- uiMapID 必须和 Vignette 所在地图匹配，否则接口会直接报参数错误，
    -- 因此这里按候选地图逐个尝试，并且只取得到的结果。
    local candidates = { EVERSONG_WOODS_MAP_ID }
    if C_Map and type(C_Map.GetBestMapForUnit) == "function" then
        local currentMapID = C_Map.GetBestMapForUnit("player")
        if currentMapID and currentMapID ~= EVERSONG_WOODS_MAP_ID then
            candidates[#candidates + 1] = currentMapID
        end
    end

    for _, mapID in ipairs(candidates) do
        local ok, position = pcall(C_VignetteInfo.GetVignettePosition, vignetteGUID, mapID)
        if ok and position and type(position.GetXY) == "function" then
            return position:GetXY()
        end
    end

    return nil
end

function Runestone:GetRunestones()
    if not C_VignetteInfo
        or type(C_VignetteInfo.GetVignettes) ~= "function"
        or type(C_VignetteInfo.GetVignetteInfo) ~= "function" then
        return nil
    end

    local runestones = {}
    for _, vignetteGUID in ipairs(C_VignetteInfo.GetVignettes() or {}) do
        local info = C_VignetteInfo.GetVignetteInfo(vignetteGUID)
        if info and (RUNESTONE_VIGNETTE_IDS[info.vignetteID] or IsRunestoneName(info.name)) then
            local x, y = GetRunestonePosition(vignetteGUID)
            runestones[#runestones + 1] = {
                guid = vignetteGUID,
                info = info,
                x = x,
                y = y,
                activationState = GetRunestoneActivationState(info),
            }
        end
    end

    return runestones
end

function Runestone:GetShardInfo()
    local _, _, _, _, _, _, _, instanceID = GetInstanceInfo()
    local firstVignetteGUID

    if C_VignetteInfo and type(C_VignetteInfo.GetVignettes) == "function" then
        firstVignetteGUID = (C_VignetteInfo.GetVignettes() or {})[1]
    end

    local serverID
    local vignetteInstanceID
    local zoneUID
    if firstVignetteGUID then
        local parts = { strsplit("-", firstVignetteGUID) }
        serverID = parts[3]
        vignetteInstanceID = parts[4]
        zoneUID = parts[5]
    end

    local displayID
    if zoneUID and zoneUID ~= "0" then
        displayID = zoneUID
    elseif instanceID and instanceID > 0 then
        displayID = tostring(instanceID)
    elseif serverID then
        displayID = serverID
    else
        displayID = ns.L.RUNESTONE_SHARD_UNKNOWN
    end

    local signature = table.concat({
        tostring(instanceID or 0),
        serverID or "",
        vignetteInstanceID or "",
        zoneUID or "",
    }, ":")

    return displayID, signature
end

function Runestone:IsPlayerInEversong()
    if not C_Map or type(C_Map.GetBestMapForUnit) ~= "function" then
        return false
    end

    local mapID = C_Map.GetBestMapForUnit("player")
    return EVERSONG_MAP_IDS[mapID] == true
end

function Runestone:GetStatus()
    local runestones = self:GetRunestones()
    if runestones == nil then
        return "UNSUPPORTED", nil
    end

    for _, runestone in ipairs(runestones) do
        if not runestone.info.isDead and runestone.activationState == true then
            return "ACTIVATED", runestone
        end
    end

    for _, runestone in ipairs(runestones) do
        if not runestone.info.isDead and runestone.activationState == false then
            return "INACTIVE", runestone
        end
    end

    if #runestones > 0 then
        return "UNKNOWN", runestones[1]
    end

    return "NONE", nil
end

function Runestone:GetAcceptedQuestCount()
    if not C_QuestLog
        or type(C_QuestLog.IsOnQuest) ~= "function"
        or type(C_QuestLog.IsQuestFlaggedCompleted) ~= "function" then
        return nil
    end

    local accepted = 0
    for _, questID in ipairs(RUNESTONE_WEEKLY_QUESTS) do
        if C_QuestLog.IsOnQuest(questID)
            or C_QuestLog.IsQuestFlaggedCompleted(questID) then
            accepted = accepted + 1
        end
    end
    return accepted
end

function Runestone:PrintQuestStatus()
    local accepted = self:GetAcceptedQuestCount()
    if accepted and accepted < #RUNESTONE_WEEKLY_QUESTS then
        ns.Addon:Print(string.format(
            ns.L.RUNESTONE_QUESTS_MISSING,
            accepted,
            #RUNESTONE_WEEKLY_QUESTS
        ))
    end
end

local function GetActivationLabel(state)
    if state == true then
        return ns.L.RUNESTONE_STATE_ACTIVATED
    elseif state == false then
        return ns.L.RUNESTONE_STATE_NEEDS_CHARGE
    end
    return ns.L.RUNESTONE_STATE_UNKNOWN
end

local function FormatCoordinate(value)
    if not value then
        return ns.L.RUNESTONE_COORDINATE_UNKNOWN
    end
    return string.format("%.1f", value * 100)
end

local function StripColors(text)
    if type(text) ~= "string" then
        return ""
    end
    text = text:gsub("|c%x%x%x%x%x%x%x%x", "")
    text = text:gsub("|r", "")
    return text
end

function Runestone:PrintStatus(announceToParty)
    -- 未接任务（既没接、也没完成）时，不通报符文石状态，只提示任务缺失。
    local accepted = self:GetAcceptedQuestCount()
    if accepted == 0 then
        self:PrintQuestStatus()
        return
    end

    local status, runestone = self:GetStatus()
    local shardID = self:GetShardInfo()
    local message

    if status == "ACTIVATED" then
        local location = RUNESTONE_LOCATIONS[runestone.info.vignetteID] or tostring(runestone.info.vignetteID)
        message = string.format(ns.L.RUNESTONE_ACTIVE, shardID, location)
    elseif status == "INACTIVE" then
        message = string.format(ns.L.RUNESTONE_INACTIVE, shardID)
    elseif status == "UNKNOWN" then
        message = string.format(ns.L.RUNESTONE_UNKNOWN, shardID)
    elseif status == "UNSUPPORTED" then
        message = string.format(ns.L.RUNESTONE_UNSUPPORTED, shardID)
    else
        message = string.format(ns.L.RUNESTONE_NONE, shardID)
    end

    ns.Addon:Print(message)
    self:PrintQuestStatus()

    if announceToParty then
        self:AnnounceToParty(message)
    end
end

function Runestone:CheckManual()
    self:PrintStatus(true)
end

function Runestone:AnnounceToParty(message)
    if not ns.Config:IsEnabled("runestoneAnnounce") then
        return
    end
    if IsInRaid and IsInRaid() then
        return
    end
    if not IsInGroup or not IsInGroup() then
        return
    end

    local text = StripColors(message or "")
    if text ~= "" then
        SendChatMessage(text, "PARTY")
    end
end

function Runestone:CheckAutomatic(force)
    if not ns.Config:IsEnabled("runestone") then
        self.lastShardSignature = nil
        return
    end

    if not self:IsPlayerInEversong() then
        self.lastShardSignature = nil
        return
    end

    local _, signature = self:GetShardInfo()
    if force or signature ~= self.lastShardSignature then
        self.lastShardSignature = signature
        self:PrintStatus()
    end
end

function Runestone:PrintDebug()
    local runestones = self:GetRunestones()
    if runestones == nil then
        ns.Addon:Print(ns.L.RUNESTONE_UNSUPPORTED)
        return
    end

    if #runestones == 0 then
        ns.Addon:Print(ns.L.RUNESTONE_DEBUG_NONE)
        return
    end

    for _, runestone in ipairs(runestones) do
        ns.Addon:Print(string.format(
            ns.L.RUNESTONE_DEBUG_LINE,
            runestone.info.vignetteID,
            FormatCoordinate(runestone.x),
            FormatCoordinate(runestone.y),
            GetActivationLabel(runestone.activationState),
            tostring(runestone.info.onWorldMap),
            tostring(runestone.info.isDead)
        ))
    end
end
