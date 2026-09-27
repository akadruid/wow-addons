local _, ns = ...

local Roster = {
    members = {},
    onlineCount = 0,
    totalCount = 0,
    state = "UNKNOWN",
    lastRequestTime = 0,
    isSending = false,
}

ns.Roster = Roster

local inviteQueue = {}
local InviteUnit = (C_PartyInfo and C_PartyInfo.InviteUnit) or _G.InviteUnit

local function ShortName(fullName)
    if Ambiguate then
        return Ambiguate(fullName, "short")
    end
    return string.match(fullName or "", "^[^-]+") or fullName
end

local function GetClassColor(classFile)
    local color
    if C_ClassColor and C_ClassColor.GetClassColor then
        color = C_ClassColor.GetClassColor(classFile)
    end
    if not color and RAID_CLASS_COLORS then
        color = RAID_CLASS_COLORS[classFile]
    end
    if color then
        return color.r, color.g, color.b
    end
    return 1, 1, 1
end

function Roster:IsCurrentPlayer(fullName)
    return ShortName(fullName) == UnitName("player")
end

function Roster:RequestUpdate()
    if not C_GuildInfo or type(C_GuildInfo.GuildRoster) ~= "function" then
        return false
    end

    local now = GetTime()
    if now - self.lastRequestTime < 10 then
        return false
    end

    self.lastRequestTime = now
    C_GuildInfo.GuildRoster()
    return true
end

function Roster:Refresh()
    self.members = {}
    self.onlineCount = 0
    self.totalCount = 0

    if not IsInGuild() then
        self.state = "NO_GUILD"
        return
    end

    if type(GetNumGuildMembers) ~= "function" or type(GetGuildRosterInfo) ~= "function" then
        self.state = "UNSUPPORTED"
        return
    end

    local total, online = GetNumGuildMembers()
    self.totalCount = total or 0
    self.onlineCount = online or 0

    for index = 1, self.totalCount do
        local name, rankName, _, level, classDisplayName, zone, _, _, isOnline, status, classFile, _, _, isMobile, _, _, guid =
            GetGuildRosterInfo(index)

        if name and isOnline and not self:IsCurrentPlayer(name) then
            local red, green, blue = GetClassColor(classFile)
            local isInGroup = false

            if guid and C_PartyInfo and type(C_PartyInfo.IsGUIDInGroup) == "function" then
                isInGroup = C_PartyInfo.IsGUIDInGroup(guid)
            end

            self.members[#self.members + 1] = {
                name = name,
                rankName = rankName or "",
                level = level or 0,
                classDisplayName = classDisplayName or "",
                classFile = classFile or "",
                classColorR = red,
                classColorG = green,
                classColorB = blue,
                zone = zone or "",
                status = status or 0,
                isMobile = isMobile and true or false,
                isInGroup = isInGroup and true or false,
                guid = guid,
            }
        end
    end

    table.sort(self.members, function(left, right)
        if left.isInGroup ~= right.isInGroup then
            return not left.isInGroup
        end
        if left.level ~= right.level then
            return left.level > right.level
        end
        return left.name < right.name
    end)

    self.state = "OK"
end

function Roster:GetMembers()
    return self.members
end

function Roster:GetGroupState()
    local inRaid = IsInRaid and IsInRaid() or false
    local inGroup = IsInGroup and IsInGroup() or false
    local groupMembers = GetNumGroupMembers and GetNumGroupMembers() or 0
    local partySize = groupMembers > 0 and groupMembers or 1
    local freeSlots = inRaid and 0 or math.max(0, 5 - partySize)

    if not inRaid and C_PartyInfo and type(C_PartyInfo.IsPartyFull) == "function" and C_PartyInfo.IsPartyFull() then
        freeSlots = 0
    end

    local canInvite
    if C_PartyInfo and type(C_PartyInfo.CanInvite) == "function" then
        canInvite = C_PartyInfo.CanInvite()
    end

    if type(canInvite) ~= "boolean" then
        canInvite = not inGroup or UnitIsGroupLeader("player") or UnitIsGroupAssistant("player")
    end

    return {
        inRaid = inRaid,
        inGroup = inGroup,
        freeSlots = freeSlots,
        canInvite = canInvite,
        isSending = self.isSending,
    }
end

function Roster:GetFirstEligibleMember()
    for _, member in ipairs(self.members) do
        local isInGroup = member.isInGroup
        if member.guid and C_PartyInfo and type(C_PartyInfo.IsGUIDInGroup) == "function" then
            isInGroup = C_PartyInfo.IsGUIDInGroup(member.guid)
        end
        if not isInGroup then
            return member
        end
    end

    return nil
end

local function SendNextInvite()
    if #inviteQueue == 0 then
        Roster.isSending = false
        return
    end

    local groupState = Roster:GetGroupState()
    if groupState.inRaid or not groupState.canInvite or groupState.freeSlots <= 0 then
        inviteQueue = {}
        Roster.isSending = false
        ns.Addon:Print(ns.L.NOTIFY_QUEUE_STOPPED)
        if ns.UI then
            ns.UI:Refresh()
        end
        return
    end

    local member = table.remove(inviteQueue, 1)
    if not member or not InviteUnit then
        inviteQueue = {}
        Roster.isSending = false
        return
    end

    InviteUnit(member.name)
    ns.Addon:Print(string.format(ns.L.NOTIFY_INVITE_SENT, member.name))

    if ns.UI then
        ns.UI:Refresh()
    end

    C_Timer.After(0.8, SendNextInvite)
end

function Roster:QueueInvites(members)
    if self.isSending then
        return false
    end

    inviteQueue = {}
    for _, member in ipairs(members) do
        inviteQueue[#inviteQueue + 1] = member
    end

    if #inviteQueue == 0 then
        return false
    end

    self.isSending = true
    SendNextInvite()
    return true
end
