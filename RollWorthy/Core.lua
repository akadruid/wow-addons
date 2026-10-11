local addonName, ns = ...

-- 值得才 ROLL（RollWorthy）
--
-- 按场景给 ROLL 币（晦暗虚空核心）弹窗放行或跳过，分四组：
--   大秘境：按钥石层数门槛（可选「史诗及以下」，连普通/英雄/史诗(M0) 五人本一起跳过）
--   团本：按最低难度（随机 / 普通 / 英雄；史诗永不过滤）
--   世界：狩猎、世界首领 / Lair、时光漫游、追随者地下城（整组开关）
--   地下堡：按层数门槛，或「全不Roll」
-- 四类以外的场景一律不阻止。
--
-- 只做两件事：用 hooksecurefunc 后置钩子读取暴雪弹窗自带的场景信息（难度 / 层数 / 池子标记），
-- 再走暴雪自己的 BonusRollFrame_CloseBonusRoll 关闭流程；不替换任何暴雪脚本。
-- 注意：真ROLL吗（BonusRollConfirm）把 PassButton 的 OnClick 换成了它自己的二次确认，
-- 所以这里不能去点“不ROLL”按钮，否则会再弹它一次确认框。

-- 团本难度：14 普通 / 15 英雄 / 16 史诗 / 17 随机
local RAID_NORMAL = 14
local RAID_HEROIC = 15
local RAID_MYTHIC = 16
local RAID_LFR = 17
-- 大秘境（钥石）场景难度；弹窗自带的 treasureContextLevel 就是钥石层数
local DUNGEON_MYTHIC_KEYSTONE = 8
local DUNGEON_HEROIC = 2
local DUNGEON_NORMAL = 1
-- 低档五人本：史诗(M0) —— 大秘境选项选「史诗及以下」时一起跳过
local DUNGEON_MYTHIC = 23
local DUNGEON_FOLLOWER = 205
local DUNGEON_TIMEWALKING = 24
local DUNGEON_TIMEWALKING_HEROIC = 33
local LOW_DUNGEON_DIFFICULTIES = {
    [DUNGEON_NORMAL] = true,
    [DUNGEON_HEROIC] = true,
    [DUNGEON_MYTHIC] = true,
}
-- 归到“世界”组的其它低价值内容：追随者地下城、时光漫游（含时光漫游团本）
local WORLD_EXTRA_DIFFICULTIES = {
    [DUNGEON_FOLLOWER] = true,
    [DUNGEON_TIMEWALKING] = true,
    [DUNGEON_TIMEWALKING_HEROIC] = true,
}
-- 大秘境下拉里的「史诗及以下」取值（列表最上面一项）
local MYTHIC_LOW_OPTION = 1
-- 地下堡：treasureContextLevel 是层数（1-11）
local DELVE = 208
-- 世界这一档：客户端里就是 250（BigWigs 标注 World / Lair bosses）。
local WORLD = 250
-- 实测：狩猎弹窗的 itemContext 恒为 55（VoidcoreHelper 取狩猎掉落池用的也是 55，团本是 3/4/5，地下堡是 108）。
local WORLD_ITEM_CONTEXT = 55
-- 团本难度递增顺序：随机 1 < 普通 2 < 英雄 3 < 史诗 4
local RAID_RANK = {
    [RAID_LFR] = 1,
    [RAID_NORMAL] = 2,
    [RAID_HEROIC] = 3,
    [RAID_MYTHIC] = 4,
}

-- 暴雪的战利品容器布局可能在弹窗出现后重新显示窗口；弹窗存活期间只补隐藏同一个弹窗。
local GUARD_FALLBACK_SECONDS = 10
local GUARD_MAX_SECONDS = 10

local hookInstalled = false
local guardFrame
local guardUntil = 0
local guardSpellID
local guardEndTime = 0
local lastHandledKey
local lastHandledAt = 0
local lastPrompt
local lastAction = "none"

-- 原始事件日志：用来确认“游戏到底有没有发 ROLL 币弹窗”，以及判定用到的原始数值。
-- 每行格式：#序号 时间 [标签] 内容；标签有 init / hook / event / decide / print / skip / guard。
-- 同时镜像到 RollWorthyDB.debugLog，跨 /reload 保留，方便事后回看。
local LOG_LIMIT = 60
local LOG_SHOW = 20
local logEntries = {}
local logSeq = 0
-- 打印日志本身时不再入库，否则每次 /rw log 都会把整段旧日志嵌进新行里。
local printingLog = false

local function GetAddonVersion()
    if C_AddOns and type(C_AddOns.GetAddOnMetadata) == "function" then
        return C_AddOns.GetAddOnMetadata(addonName, "Version") or "?"
    end
    return "?"
end

local function LogDb()
    if type(RollWorthyDB) ~= "table" then
        return nil
    end

    if type(RollWorthyDB.debugLog) ~= "table" then
        RollWorthyDB.debugLog = {}
    end

    return RollWorthyDB.debugLog
end

local function LogLine(tag, text)
    logSeq = logSeq + 1
    local line = string.format("#%d %.1f [%s] %s", logSeq, GetTime(), tag, text)

    logEntries[#logEntries + 1] = line
    if #logEntries > LOG_LIMIT then
        table.remove(logEntries, 1)
    end

    local stored = LogDb()
    if stored then
        stored[#stored + 1] = line
        while #stored > LOG_LIMIT do
            table.remove(stored, 1)
        end
    end
end

local function Shorten(value, maxLength)
    local text = tostring(value or "")
    text = text:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")

    -- 中文按字节截断会把字切坏，能用 utf8 就按字符截。
    local length = #text
    if utf8 and type(utf8.len) == "function" then
        length = utf8.len(text) or length
    end

    if length > maxLength then
        if utf8 and type(utf8.offset) == "function" then
            local offset = utf8.offset(text, maxLength + 1)
            if offset then
                return string.sub(text, 1, offset - 1) .. "…"
            end
        end
        return string.sub(text, 1, maxLength) .. "…"
    end
    return text
end

-- 加载时把上一次会话的尾巴接回来，这样复现后 /reload 也能看到现场。
local function AdoptSavedLog()
    local stored = LogDb()
    if not stored or #stored == 0 or #logEntries > 0 then
        return
    end

    for index = 1, #stored do
        logEntries[index] = stored[index]
    end
end

-- 只在本地聊天框提示：不广播到小队 / 团队 / 频道，也不做屏幕弹字。
local function Print(message)
    local text = "|cff33ff99" .. ns.L.ADDON_NAME .. "|r: " .. tostring(message)
    local printed = 0

    for index = 1, NUM_CHAT_WINDOWS or 10 do
        local chatFrame = _G["ChatFrame" .. index]
        if chatFrame then
            chatFrame:AddMessage(text)
            printed = printed + 1
        end
    end

    if printed == 0 and DEFAULT_CHAT_FRAME then
        DEFAULT_CHAT_FRAME:AddMessage(text)
        printed = 1
    end

    if not printingLog then
        LogLine("print", string.format("frames=%d %s", printed, tostring(message)))
    end
end

-- 跳过时同时提示：聊天框写一行，屏幕中央再闪一次（都只对自己可见，不发任何频道）。
local function NotifySkip(chatText, screenText)
    Print(chatText)

    local errorsFrame = _G.UIErrorsFrame
    if errorsFrame and screenText then
        local ok = pcall(errorsFrame.AddMessage, errorsFrame, screenText, 1, 0.35, 0.35, 1, 4)
        LogLine("screen", string.format("ok=%s %s", tostring(ok), screenText))
    end
end

local function GetActiveKeystoneLevel()
    if C_ChallengeMode and type(C_ChallengeMode.GetActiveKeystoneInfo) == "function" then
        local ok, _, level = pcall(C_ChallengeMode.GetActiveKeystoneInfo)
        if ok and type(level) == "number" and level > 0 then
            return level
        end
    end
    return 0
end

-- 暴雪 12.1 自带“当前狩猎目标”接口（Blizzard 的 PreyHunt 部件和 DialogueUI 都在用）。
local function GetActivePreyQuestID()
    if C_QuestLog and type(C_QuestLog.GetActivePreyQuest) == "function" then
        local questID = C_QuestLog.GetActivePreyQuest()
        if type(questID) == "number" and questID > 0 then
            return questID
        end
    end
    return nil
end

local function GetInstanceType()
    local _, instanceType = GetInstanceInfo()
    return instanceType
end

local function GetQuestTitle(questID)
    if questID and C_QuestLog and type(C_QuestLog.GetTitleForQuestID) == "function" then
        local title = C_QuestLog.GetTitleForQuestID(questID)
        if type(title) == "string" and title ~= "" then
            return title
        end
    end
    return "?"
end

local function GetScenarioName()
    if C_Scenario and type(C_Scenario.GetInfo) == "function" then
        local ok, name = pcall(C_Scenario.GetInfo)
        if ok and type(name) == "string" and name ~= "" then
            return name
        end
    end
    return "?"
end

-- 返回：是否放行、难度 ID、难度层数（大秘境 = 钥石层数，地下堡 = 层数，狩猎 = 1/2/3）
local function Evaluate(prompt)
    local difficultyID = tonumber(prompt.difficultyID) or 0
    if difficultyID == 0 then
        local _, _, instanceDifficulty = GetInstanceInfo()
        difficultyID = tonumber(instanceDifficulty) or 0
    end

    local level = tonumber(prompt.treasureContextLevel) or 0

    local instanceType = GetInstanceType()
    local preyActive = GetActivePreyQuestID() ~= nil

    -- 判定顺序与实例类型都很关键：狩猎弹窗上报的难度 ID 和普通团本相同（实测都是 14），
    -- 所以「团本难度 ID」必须再结合实例类型和狩猎状态才能定性。
    local branch
    if difficultyID == DUNGEON_MYTHIC_KEYSTONE then
        branch = "mythicPlus"
    elseif LOW_DUNGEON_DIFFICULTIES[difficultyID] and instanceType == "party" then
        -- 低档五人本要确认真的在五人本实例里；时光漫游团本(33)之类不能算进来。
        branch = "lowDungeon"
    elseif WORLD_EXTRA_DIFFICULTIES[difficultyID] then
        -- 追随者地下城、时光漫游归“世界”组一起跳过。
        branch = "world"
    elseif difficultyID == DELVE then
        branch = "delve"
    elseif difficultyID == WORLD
        or tonumber(prompt.itemContext) == WORLD_ITEM_CONTEXT
        or (RAID_RANK[difficultyID] and preyActive and instanceType ~= "raid") then
        -- 归世界组的三种情况：
        --   1) 难度就是 250（世界难度）；
        --   2) itemContext = 55：狩猎/世界那个池子（真实团本用 3/4/5、地下堡 108），
        --      拿它当池子标记最可靠，狩猎任务结束后 prey 变 nil 也认得出来；
        --   3) 不在团本实例里 + 有狩猎目标：14 这类被复用的难度按狩猎处理。
        branch = "world"
    elseif RAID_RANK[difficultyID] then
        -- 团本：难度 ID 属于 14/15/16/17 就按团本处理。
        -- 不加“必须在团本实例里”这个条件：实测暴雪会在离开副本后重新发一次同一次弹窗，
        -- 那时 instanceType 已经变成 none，靠实例类型判断会漏掉（2026-10-11 实测）。
        branch = "raid"
    else
        branch = "other"
    end

    if branch == "mythicPlus" then
        if not ns.Config:IsEnabled("mythicPlusFilter") then
            return true, difficultyID, level, branch
        end
        local minLevel = ns.Config:GetNumber("mythicPlusLevel")
        if minLevel <= MYTHIC_LOW_OPTION then
            -- 选了「史诗及以下」：大秘境本身全部放行，低档五人本另走下面那条分支。
            return true, difficultyID, level, branch
        end
        if level <= 0 then
            level = GetActiveKeystoneLevel()
        end
        if level <= 0 then
            -- 拿不到层数时放行：误拦会白丢一次机会，误放只多弹一次窗。
            return true, difficultyID, level, branch
        end
        return level >= minLevel, difficultyID, level, branch
    end

    if branch == "lowDungeon" then
        -- 只有大秘境过滤开着、且门槛选的是「史诗及以下」时才跳过这些低档五人本。
        if ns.Config:IsEnabled("mythicPlusFilter")
            and ns.Config:GetNumber("mythicPlusLevel") <= MYTHIC_LOW_OPTION then
            return false, difficultyID, level, branch
        end
        return true, difficultyID, level, branch
    end

    if branch == "delve" then
        if not ns.Config:IsEnabled("delveFilter") then
            return true, difficultyID, level, branch
        end
        local delveMin = ns.Config:GetNumber("delveLevel")
        if delveMin <= 0 then
            -- 全不Roll：地下堡一律跳过。
            return false, difficultyID, level, branch
        end
        if level <= 0 then
            -- 层数取不到时放行，避免误吞机会。
            return true, difficultyID, level, branch
        end
        return level >= delveMin, difficultyID, level, branch
    end

    if branch == "world" then
        -- 世界这一组不做难度细分（游戏也没提供）：开过滤就整组跳过。
        if not ns.Config:IsEnabled("worldFilter") then
            return true, difficultyID, level, branch
        end
        return false, difficultyID, level, branch
    end

    if branch == "raid" then
        if not ns.Config:IsEnabled("raidFilter") then
            return true, difficultyID, level, branch
        end
        -- 按难度递增比较：史诗永远在所选最低难度之上，所以不会被过滤。
        local minRank = RAID_RANK[ns.Config:GetNumber("raidMinDifficulty")] or RAID_RANK[RAID_HEROIC]
        return RAID_RANK[difficultyID] >= minRank, difficultyID, level, branch
    end

    -- 四类以外的场景一律不阻止。
    return true, difficultyID, level, branch
end

local function DescribeContext(difficultyID, level, branch)
    -- 先按“命中的规则”出标签，避免把狩猎写成团本。
    if branch == "world" then
        if difficultyID == DUNGEON_FOLLOWER then
            return ns.L.DIFF_DUNGEON_FOLLOWER
        elseif difficultyID == DUNGEON_TIMEWALKING or difficultyID == DUNGEON_TIMEWALKING_HEROIC then
            return ns.L.DIFF_DUNGEON_TIMEWALKING
        end
        return ns.L.DIFF_WORLD
    end

    if branch == "delve" then
        if level and level > 0 then
            return string.format(ns.L.DIFF_DELVE, level)
        end
        return ns.L.DIFF_DELVE_UNKNOWN
    end

    if difficultyID == RAID_HEROIC then
        return ns.L.DIFF_RAID_HEROIC
    elseif difficultyID == RAID_MYTHIC then
        return ns.L.DIFF_RAID_MYTHIC
    elseif difficultyID == RAID_NORMAL then
        return ns.L.DIFF_RAID_NORMAL
    elseif difficultyID == RAID_LFR then
        return ns.L.DIFF_RAID_LFR
    elseif difficultyID == DUNGEON_MYTHIC_KEYSTONE then
        if level and level > 0 then
            return string.format(ns.L.DIFF_KEYSTONE, level)
        end
        return ns.L.DIFF_KEYSTONE_UNKNOWN
    elseif difficultyID == DUNGEON_HEROIC then
        return ns.L.DIFF_DUNGEON_HEROIC
    elseif difficultyID == DUNGEON_NORMAL then
        return ns.L.DIFF_DUNGEON_NORMAL
    elseif difficultyID == DUNGEON_MYTHIC then
        return ns.L.DIFF_DUNGEON_MYTHIC
    elseif difficultyID == DUNGEON_FOLLOWER then
        return ns.L.DIFF_DUNGEON_FOLLOWER
    elseif difficultyID == DUNGEON_TIMEWALKING or difficultyID == DUNGEON_TIMEWALKING_HEROIC then
        return ns.L.DIFF_DUNGEON_TIMEWALKING
    elseif difficultyID == DELVE then
        if level and level > 0 then
            return string.format(ns.L.DIFF_DELVE, level)
        end
        return ns.L.DIFF_DELVE_UNKNOWN
    elseif difficultyID == WORLD then
        return ns.L.DIFF_WORLD
    end
    return string.format(ns.L.DIFF_OTHER, difficultyID)
end

local function StopGuard()
    guardUntil = 0
    if guardFrame then
        guardFrame:SetScript("OnUpdate", nil)
    end
end

local function OnGuardUpdate()
    if guardUntil <= 0 or GetTime() >= guardUntil then
        StopGuard()
        return
    end

    local bonusFrame = BonusRollFrame
    if not bonusFrame then
        StopGuard()
        return
    end

    if bonusFrame:IsShown()
        and bonusFrame.spellID == guardSpellID
        and (bonusFrame.endTime or 0) == guardEndTime then
        LogLine("guard", "re-hide same prompt")
        pcall(bonusFrame.Hide, bonusFrame)
    end
end

local function StartGuard(spellID, endTime)
    -- 弹窗标识不完整时不做守卫：否则会把之后的弹窗一起静默隐藏，连提示都没有。
    -- 守卫只是防止布局把窗口又显示出来的兜底，丢了不影响拦截本身。
    if spellID == nil or (endTime or 0) <= 0 then
        LogLine("guard", string.format("disabled (identity incomplete spell=%s endTime=%s)",
            tostring(spellID), tostring(endTime)))
        StopGuard()
        return
    end

    guardSpellID = spellID
    guardEndTime = endTime or 0

    local now = GetTime()
    if guardEndTime > now then
        guardUntil = math.min(guardEndTime + 1, now + GUARD_MAX_SECONDS)
    else
        guardUntil = now + GUARD_FALLBACK_SECONDS
    end

    if not guardFrame then
        guardFrame = CreateFrame("Frame")
        guardFrame:SetScript("OnUpdate", OnGuardUpdate)
    end
end

local function SuppressPrompt()
    local bonusFrame = BonusRollFrame
    if not bonusFrame then
        return false
    end

    local spellID = bonusFrame.spellID
    local endTime = bonusFrame.endTime or 0

    -- 走暴雪自己的关闭流程（等价于点“不ROLL”），再兜底隐藏。
    if type(BonusRollFrame_CloseBonusRoll) == "function" then
        pcall(BonusRollFrame_CloseBonusRoll)
    end
    if bonusFrame:IsShown() then
        pcall(bonusFrame.Hide, bonusFrame)
    end

    StartGuard(spellID, endTime)
    return not bonusFrame:IsShown()
end

local function HandlePrompt(prompt)
    local allowed, difficultyID, level, branch = Evaluate(prompt)
    local enabled = ns.Config:IsEnabled("enabled")

    LogLine("decide", string.format("enabled=%s allowed=%s rule=%s diff=%s ctx=%s lvl=%s item=%s source=%s",
        tostring(enabled), tostring(allowed), tostring(branch), tostring(difficultyID),
        tostring(prompt.itemContext), tostring(level), tostring(prompt.displayItemID),
        tostring(prompt.source)))
    local preyQuestID = GetActivePreyQuestID()
    LogLine("context", string.format("prey=%s title=%s scenario=%s instanceType=%s instanceDiff=%s",
        tostring(preyQuestID), GetQuestTitle(preyQuestID), GetScenarioName(),
        tostring(GetInstanceType()), tostring(select(3, GetInstanceInfo()))))

    lastPrompt = {
        difficultyID = difficultyID,
        level = level,
        branch = branch,
        itemContext = prompt.itemContext,
        displayItemID = prompt.displayItemID,
        -- 守门关闭时一律放行，状态查询里按“已放行”展示。
        allowed = allowed or not enabled,
    }

    if not enabled then
        lastAction = "disabled"
        return
    end

    if allowed then
        lastAction = "allowed"
        return
    end

    -- 跳过时一定有提示，不做开关；提示里带上原始数值，方便直接看出是按哪条规则拦的。
    local label = DescribeContext(difficultyID, level, branch)
    NotifySkip(
        string.format(ns.L.NOTIFY_SKIPPED_DETAIL, label, tostring(branch), tostring(difficultyID), tostring(level)),
        string.format(ns.L.NOTIFY_SKIPPED_SCREEN, label, tostring(difficultyID), tostring(level)))

    if SuppressPrompt() then
        lastAction = "skipped"
        LogLine("skip", string.format("closed=true %s diff=%s lvl=%s",
            label, tostring(difficultyID), tostring(level)))
    else
        lastAction = "failed"
        LogLine("skip", "closed=false (window still shown)")
        Print(ns.L.NOTIFY_FAILED)
    end
end

-- 同一个弹窗可能同时从后置钩子和事件里进来，这里做一次去重。
local function HandlePromptOnce(prompt, source)
    prompt.source = source or prompt.source or "unknown"

    local key = string.format("%s:%s:%s:%s",
        tostring(prompt.spellID),
        tostring(prompt.difficultyID),
        tostring(prompt.displayItemID),
        tostring(prompt.treasureContextLevel))

    local now = GetTime()
    if key == lastHandledKey and (now - lastHandledAt) < 2 then
        return
    end

    lastHandledKey = key
    lastHandledAt = now
    HandlePrompt(prompt)
end

local function IsBonusRollConfirmType(confirmType)
    if not Enum or not Enum.ConfirmationPromptUIType then
        return false
    end
    return confirmType == Enum.ConfirmationPromptUIType.BonusRoll
end

local function HandleActivePrompt()
    if type(GetSpellConfirmationPromptsInfo) ~= "function" then
        return
    end

    local prompts = GetSpellConfirmationPromptsInfo()
    if type(prompts) ~= "table" then
        return
    end

    for _, entry in ipairs(prompts) do
        if IsBonusRollConfirmType(entry.confirmType) then
            HandlePromptOnce({
                spellID = entry.spellID,
                difficultyID = entry.difficultyID,
                displayItemID = entry.displayItemID,
                itemContext = entry.itemContext,
                treasureContextLevel = entry.treasureContextLevel,
            }, "event:BONUS_ROLL_STARTED")
        end
    end
end

local function InstallStartHook()
    if hookInstalled or type(BonusRollFrame_StartBonusRoll) ~= "function" then
        return
    end

    hooksecurefunc("BonusRollFrame_StartBonusRoll", function(spellID, promptText, _, currencyID, currencyCost, difficultyID, displayItemID, itemContext, treasureContextLevel)
        LogLine("hook", string.format("StartBonusRoll spell=%s currency=%s diff=%s ctx=%s lvl=%s item=%s text=%s",
            tostring(spellID), tostring(currencyID), tostring(difficultyID), tostring(itemContext),
            tostring(treasureContextLevel), tostring(displayItemID), Shorten(promptText, 48)))
        HandlePromptOnce({
            spellID = spellID,
            difficultyID = difficultyID,
            displayItemID = displayItemID,
            itemContext = itemContext,
            treasureContextLevel = treasureContextLevel,
        }, "hook:StartBonusRoll")
    end)

    hookInstalled = true
end

local eventFrame = CreateFrame("Frame")
eventFrame:RegisterEvent("ADDON_LOADED")
eventFrame:RegisterEvent("PLAYER_LOGIN")
eventFrame:RegisterEvent("BONUS_ROLL_STARTED")
eventFrame:RegisterEvent("SPELL_CONFIRMATION_PROMPT")
eventFrame:SetScript("OnEvent", function(_, event, ...)
    if event == "ADDON_LOADED" then
        local loadedName = ...
        if loadedName == addonName then
            AdoptSavedLog()
            LogLine("init", string.format("v%s loaded, enabled=%s",
                GetAddonVersion(), tostring(ns.Config:IsEnabled("enabled"))))
        end
        -- 暴雪 ROLL 币界面是懒加载的，等它加载完再装钩子。
        if loadedName == addonName or loadedName == "Blizzard_UIPanels_Game" then
            InstallStartHook()
        end
    elseif event == "PLAYER_LOGIN" then
        InstallStartHook()
    elseif event == "BONUS_ROLL_STARTED" then
        InstallStartHook()
        LogLine("event", string.format("BONUS_ROLL_STARTED shown=%s",
            tostring(BonusRollFrame ~= nil and BonusRollFrame:IsShown())))
        HandleActivePrompt()
    elseif event == "SPELL_CONFIRMATION_PROMPT" then
        local spellID, confirmType, text, _, currencyID, currencyCost, difficultyID, displayItemID, itemContext, treasureContextLevel = ...
        LogLine("event", string.format("SPELL_CONFIRMATION_PROMPT type=%s bonusRoll=%s spell=%s currency=%s cost=%s diff=%s ctx=%s lvl=%s item=%s text=%s",
            tostring(confirmType), tostring(IsBonusRollConfirmType(confirmType)), tostring(spellID),
            tostring(currencyID), tostring(currencyCost), tostring(difficultyID), tostring(itemContext),
            tostring(treasureContextLevel), tostring(displayItemID), Shorten(text, 48)))
        if IsBonusRollConfirmType(confirmType) then
            HandlePromptOnce({
                spellID = spellID,
                difficultyID = difficultyID,
                displayItemID = displayItemID,
                itemContext = itemContext,
                treasureContextLevel = treasureContextLevel,
            }, "event:SPELL_CONFIRMATION_PROMPT")
        end
    end
end)

local function StatusText()
    local state = ns.Config:IsEnabled("enabled") and ns.L.ON or ns.L.OFF
    local text = string.format(ns.L.STATUS, state)

    if lastPrompt then
        text = text .. "\n" .. string.format(
            ns.L.STATUS_LAST,
            DescribeContext(lastPrompt.difficultyID, lastPrompt.level, lastPrompt.branch),
            lastPrompt.allowed and ns.L.ALLOWED or ns.L.BLOCKED)
    else
        text = text .. "\n" .. ns.L.STATUS_NONE
    end

    return text
end

local function DebugText()
    local yes = ns.L.DEBUG_YES
    local no = ns.L.DEBUG_NO
    local text = string.format(ns.L.DEBUG_HEAD,
        ns.Config:IsEnabled("enabled") and yes or no,
        hookInstalled and yes or no)

    if lastPrompt then
        text = text .. "\n" .. string.format(ns.L.DEBUG_RAW,
            tostring(lastPrompt.difficultyID),
            tostring(lastPrompt.itemContext),
            tostring(lastPrompt.level),
            tostring(lastPrompt.displayItemID))
        text = text .. "\n" .. string.format(ns.L.DEBUG_LAST,
            DescribeContext(lastPrompt.difficultyID, lastPrompt.level, lastPrompt.branch),
            lastPrompt.allowed and ns.L.ALLOWED or ns.L.BLOCKED)
    else
        text = text .. "\n" .. ns.L.DEBUG_NO_LAST
    end

    local actionText = ns.L.ACTION_NONE
    if lastAction == "disabled" then
        actionText = ns.L.ACTION_DISABLED
    elseif lastAction == "allowed" then
        actionText = ns.L.ACTION_ALLOWED
    elseif lastAction == "skipped" then
        actionText = ns.L.ACTION_SKIPPED
    elseif lastAction == "failed" then
        actionText = ns.L.ACTION_FAILED
    end

    return text .. "\n" .. string.format(ns.L.DEBUG_ACTION, actionText)
end

local function LogText()
    if #logEntries == 0 then
        return ns.L.LOG_EMPTY
    end

    local lines = { string.format(ns.L.LOG_HEAD, GetAddonVersion()) }
    local first = math.max(1, #logEntries - LOG_SHOW + 1)
    for index = #logEntries, first, -1 do
        lines[#lines + 1] = logEntries[index]
    end
    return table.concat(lines, "\n")
end

local function HandleCommand(message)
    local command = string.lower((message or ""):match("^%s*(.-)%s*$"))

    if command == "on" then
        ns.Config:SetEnabled("enabled", true)
        Print(StatusText())
    elseif command == "off" then
        ns.Config:SetEnabled("enabled", false)
        Print(StatusText())
    elseif command == "test" then
        NotifySkip(
            string.format(ns.L.NOTIFY_SKIPPED_DETAIL, ns.L.DIFF_RAID_NORMAL, "raid", "14", "0"),
            string.format(ns.L.NOTIFY_SKIPPED_SCREEN, ns.L.DIFF_RAID_NORMAL, "14", "0"))
    elseif command == "debug" then
        Print(DebugText())
    elseif command == "log" then
        printingLog = true
        Print(LogText())
        printingLog = false
    elseif command == "log clear" then
        logEntries = {}
        Print(ns.L.LOG_CLEARED)
    elseif command == "" or command == "status" then
        Print(StatusText())
    else
        ns.Config:Open()
    end
end

SLASH_ROLLWORTHY1 = "/rw"
SLASH_ROLLWORTHY2 = "/rollworthy"
SlashCmdList.ROLLWORTHY = HandleCommand
