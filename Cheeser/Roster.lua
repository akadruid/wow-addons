local _, ns = ...

local Roster = {
    members = {},
    onlineCount = 0,
    totalCount = 0,
    state = "UNKNOWN",
    lastRequestTime = 0,
    isSending = false,
    -- 当前邀请来源：guild = 当前角色公会，club = 指定的角色社区。
    sourceKind = "guild",
    sourceClubId = nil,
    sourceLabel = nil,
}

ns.Roster = Roster

local inviteQueue = {}
local InviteUnit = (C_PartyInfo and C_PartyInfo.InviteUnit) or _G.InviteUnit

-- Enum 常量在客户端更新时可能改名，这里保留数字回退值。
-- 参考 Blizzard_APIDocumentationGenerated/ClubDocumentation.lua。
local PRESENCE_FALLBACK = {
    Online = 1,
    OnlineMobile = 2,
    Offline = 3,
    Away = 4,
    Busy = 5,
}

local CLUB_TYPE_CHARACTER_FALLBACK = 1

local function EnumValue(enumName, key, fallback)
    local enum = Enum and Enum[enumName]
    local value = enum and enum[key]
    if type(value) == "number" then
        return value
    end
    return fallback
end

local function PresenceValue(key)
    return EnumValue("ClubMemberPresence", key, PRESENCE_FALLBACK[key])
end

local function CharacterClubType()
    return EnumValue("ClubType", "Character", CLUB_TYPE_CHARACTER_FALLBACK)
end

local function IsChatLockedDown()
    if C_ChatInfo and type(C_ChatInfo.InChatMessagingLockdown) == "function" then
        return C_ChatInfo.InChatMessagingLockdown() and true or false
    end

    return false
end

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

local function GetClassInfoFromID(classID)
    if not classID
        or classID <= 0
        or not C_CreatureInfo
        or type(C_CreatureInfo.GetClassInfo) ~= "function" then
        return nil
    end

    local ok, classInfo = pcall(C_CreatureInfo.GetClassInfo, classID)
    if ok and type(classInfo) == "table" then
        return classInfo
    end

    return nil
end

-- 社区职位名优先用暴雪自己的本地化文本，未加载 Communities UI 时回退到插件文本。
local function GetRoleLabel(roleID)
    local roleNames = _G.COMMUNITY_MEMBER_ROLE_NAMES
    if roleID and type(roleNames) == "table" then
        local label = roleNames[roleID]
        if type(label) == "string" and label ~= "" then
            return label
        end
    end

    local roleEnum = Enum and Enum.ClubRoleIdentifier
    if roleID and roleEnum then
        if roleID == roleEnum.Owner then
            return ns.L.CLUB_ROLE_OWNER
        elseif roleID == roleEnum.Leader then
            return ns.L.CLUB_ROLE_LEADER
        elseif roleID == roleEnum.Moderator then
            return ns.L.CLUB_ROLE_MODERATOR
        elseif roleID == roleEnum.Member then
            return ns.L.CLUB_ROLE_MEMBER
        end
    end

    return ""
end

-- 返回 UI 使用的状态码（0 在线 / 1 暂离 / 2 忙碌）以及是否手机在线；
-- 离线或未知状态返回 nil，表示该成员不计入可邀请列表。
local function GetPresenceState(presence)
    if presence == PresenceValue("Online") then
        return 0, false
    elseif presence == PresenceValue("OnlineMobile") then
        return 0, true
    elseif presence == PresenceValue("Away") then
        return 1, false
    elseif presence == PresenceValue("Busy") then
        return 2, false
    end

    return nil, false
end

function Roster:IsCurrentPlayer(fullName)
    return ShortName(fullName) == UnitName("player")
end

local function GetCurrentGuildName()
    if type(GetGuildInfo) ~= "function" then
        return nil
    end

    local guildName = GetGuildInfo("player")
    if type(guildName) == "string" and guildName ~= "" then
        return guildName
    end

    return nil
end

-- 名称后面补上“（公会）/（社区）”，避免公会与社区同名时提示产生歧义。
local function FormatSourceLabel(name, sourceType)
    if type(name) == "string" and name ~= "" then
        return string.format(ns.L.SOURCE_NAME_FORMAT, name, sourceType)
    end

    return nil
end

function Roster:IsCommunitySource()
    return self.sourceKind == "club"
end

function Roster:GetGuildSourceLabel()
    return FormatSourceLabel(GetCurrentGuildName(), ns.L.SOURCE_TYPE_GUILD)
        or ns.L.SETTINGS_SOURCE_GUILD
end

function Roster:GetSourceLabel()
    if self.sourceKind == "club" then
        return FormatSourceLabel(self.sourceLabel or self.sourceClubId, ns.L.SOURCE_TYPE_COMMUNITY)
            or ns.L.SETTINGS_SOURCE_CLUB
    end

    return self:GetGuildSourceLabel()
end

-- ===== 邀请来源 =====

function Roster:GetSource()
    local db = ns.Addon and ns.Addon.db
    local source = db and db.inviteSource
    if type(source) == "table"
        and source.kind == "club"
        and type(source.clubId) == "string"
        and source.clubId ~= "" then
        return "club", source.clubId
    end

    return "guild", nil
end

function Roster:SetSource(kind, clubId)
    local db = ns.Addon and ns.Addon.db
    if not db then
        return false
    end

    if kind == "club" and type(clubId) == "string" and clubId ~= "" then
        db.inviteSource = { kind = "club", clubId = clubId }
    else
        db.inviteSource = { kind = "guild" }
    end

    self:Refresh()
    if ns.UI then
        ns.UI:Refresh()
    end

    return true
end

-- 只返回可以邀请成员的角色社区。战网社区没有邀请入口，因此不在这里出现。
function Roster:GetAvailableCommunities()
    local result = {}

    if not (C_Club and type(C_Club.GetSubscribedClubs) == "function") then
        return result
    end

    if IsChatLockedDown() then
        return result
    end

    local ok, clubs = pcall(C_Club.GetSubscribedClubs)
    if not ok or type(clubs) ~= "table" then
        return result
    end

    local characterType = CharacterClubType()
    for _, clubInfo in pairs(clubs) do
        if type(clubInfo) == "table"
            and clubInfo.clubId
            and clubInfo.clubType == characterType then
            result[#result + 1] = {
                clubId = tostring(clubInfo.clubId),
                name = clubInfo.name or tostring(clubInfo.clubId),
                memberCount = clubInfo.memberCount or 0,
            }
        end
    end

    table.sort(result, function(left, right)
        if left.name ~= right.name then
            return left.name < right.name
        end
        return left.clubId < right.clubId
    end)

    return result
end

function Roster:FindCommunity(clubId)
    if not clubId then
        return nil
    end

    for _, community in ipairs(self:GetAvailableCommunities()) do
        if community.clubId == tostring(clubId) then
            return community
        end
    end

    return nil
end

-- ===== 名册读取 =====

function Roster:RequestUpdate()
    if self:GetSource() ~= "guild" then
        return false
    end

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

    local kind, clubId = self:GetSource()
    self.sourceKind = kind
    self.sourceClubId = clubId

    if kind == "club" then
        self:RefreshCommunity(clubId)
    else
        self.sourceLabel = GetCurrentGuildName()
        self:RefreshGuild()
    end
end

function Roster:RefreshGuild()
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

    self:SortMembers()
    self.state = "OK"
end

function Roster:RefreshCommunity(clubId)
    if not (C_Club
        and type(C_Club.GetSubscribedClubs) == "function"
        and type(C_Club.GetClubMembers) == "function"
        and type(C_Club.GetMemberInfo) == "function") then
        self.state = "CLUBS_UNAVAILABLE"
        return
    end

    if IsChatLockedDown() then
        self.state = "LOCKDOWN"
        return
    end

    local community = self:FindCommunity(clubId)
    if not community then
        self.state = "NO_CLUB"
        return
    end
    self.sourceLabel = community.name

    local ok, memberIds = pcall(C_Club.GetClubMembers, clubId)
    if not ok or type(memberIds) ~= "table" then
        self.state = "CLUBS_UNAVAILABLE"
        return
    end

    local members = {}
    local onlineCount = 0
    local totalCount = 0

    for _, memberId in ipairs(memberIds) do
        local infoOk, memberInfo = pcall(C_Club.GetMemberInfo, clubId, memberId)
        if infoOk and type(memberInfo) == "table" and not memberInfo.isSelf then
            totalCount = totalCount + 1

            local status, isMobile = GetPresenceState(memberInfo.presence)
            if status and memberInfo.name and memberInfo.name ~= "" then
                onlineCount = onlineCount + 1

                local classInfo = GetClassInfoFromID(memberInfo.classID)
                local classFile = (classInfo and classInfo.classFile) or ""
                local red, green, blue = GetClassColor(classFile)

                local isInGroup = false
                if memberInfo.guid and C_PartyInfo and type(C_PartyInfo.IsGUIDInGroup) == "function" then
                    local groupOk, inGroup = pcall(C_PartyInfo.IsGUIDInGroup, memberInfo.guid)
                    isInGroup = groupOk and inGroup and true or false
                end

                members[#members + 1] = {
                    name = memberInfo.name,
                    rankName = GetRoleLabel(memberInfo.role),
                    level = memberInfo.level or 0,
                    classDisplayName = (classInfo and classInfo.className) or "",
                    classFile = classFile,
                    classColorR = red,
                    classColorG = green,
                    classColorB = blue,
                    zone = memberInfo.zone or "",
                    status = status,
                    isMobile = isMobile,
                    isInGroup = isInGroup,
                    guid = memberInfo.guid,
                }
            end
        end
    end

    self.members = members
    self.totalCount = totalCount
    self.onlineCount = onlineCount

    self:SortMembers()
    self.state = "OK"
end

function Roster:SortMembers()
    table.sort(self.members, function(left, right)
        if left.isInGroup ~= right.isInGroup then
            return not left.isInGroup
        end
        if left.level ~= right.level then
            return left.level > right.level
        end
        return left.name < right.name
    end)
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

function Roster:GetSourceBlockReason()
    if self.sourceKind ~= "club" then
        if not IsInGuild() then
            return ns.L.ERROR_NOT_IN_GUILD
        end
        return nil
    end

    if self.state == "NO_CLUB" then
        return ns.L.STATUS_NO_CLUB
    end

    if self.state == "CLUBS_UNAVAILABLE" or self.state == "UNSUPPORTED" then
        return ns.L.STATUS_CLUB_UNSUPPORTED
    end

    if self.state == "LOCKDOWN" then
        return ns.L.STATUS_CLUB_LOCKED
    end

    return nil
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

-- 邀请跨服（连接服）公会成员时，短名可能触发“无法邀请该服务器的玩家”。
-- 用 GUID 取回完整“角色名-服务器”再邀请，和 EllesmereUI / MRT 的做法一致。
local function BuildInviteName(member)
    local name = member and member.name
    if not name or name == "" then
        return nil
    end

    local guid = member.guid
    if guid and GetPlayerInfoByGUID then
        local ok, _, _, _, _, _, infoName, realm = pcall(GetPlayerInfoByGUID, guid)
        if ok
            and type(infoName) == "string" and infoName ~= ""
            and not (issecretvalue and issecretvalue(infoName)) then
            local base = string.match(infoName, "^[^%-]+") or infoName
            if type(realm) == "string" and realm ~= ""
                and not (issecretvalue and issecretvalue(realm)) then
                return base .. "-" .. realm:gsub("%s+", "")
            end
            return base
        end
    end

    return name
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

    InviteUnit(BuildInviteName(member) or member.name)
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
