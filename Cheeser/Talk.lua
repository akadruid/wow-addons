local _, ns = ...

local Talk = {}
ns.Talk = Talk

local CHAIN_SECONDS = 30
local MAX_CHAIN_SELECTIONS = 10
-- 同一个对话页面在事件之后按这些间隔重试，覆盖界面刷新比事件慢的情况。
local ATTEMPT_DELAYS = { 0, 0.3, 0.9, 1.8 }

-- 自动选择规则
-- questID 是触发条件：该任务在任务日志中时规则才生效。
-- steps 按顺序匹配当前对话里的选项：优先匹配 optionID（与语言无关），匹配不到再退回文本关键词。
-- 规则命中第一项就自动选择。
local RULES = {
    {
        key = "huntPreyChoice",
        questID = 91277,
        steps = {
            { optionID = 134312, match = "我要自己挑选猎物" },
            { optionID = 140843, match = "利爪卡达尼" },
            { optionID = 140847, match = "盘卷蛇岛" },
            { optionID = 134313, match = "梦魇" },
        },
    },
}

-- 注意：本文件所有入口都写成 Talk.Xxx() 形式，函数内部一律使用 Talk 这个 upvalue，
-- 不使用方法参数 self。这样无论调用方写 Talk:Xxx() 还是 Talk.Xxx()，都不会因为
-- self 丢失而直接报错中断。

local function StripColors(text)
    if type(text) ~= "string" then
        return ""
    end

    text = text:gsub("|c%x%x%x%x%x%x%x%x", "")
    text = text:gsub("|r", "")
    text = text:gsub("|T.-|t", "")
    text = text:gsub("|H.-|h", "")
    text = text:gsub("|h", "")
    return text
end

local function Normalize(text)
    return (StripColors(text):gsub("%s+", ""))
end

local function Trim(text)
    return (StripColors(text):gsub("^%s+", ""):gsub("%s+$", ""))
end

local function BuildSignature(options)
    local parts = {}
    for index, option in ipairs(options) do
        local orderIndex = tonumber(option.orderIndex) or index
        local optionID = tonumber(option.gossipOptionID) or 0
        parts[#parts + 1] = string.format("%d:%d:%s", orderIndex, optionID, Normalize(option.name))
    end
    return table.concat(parts, "|")
end

local function FindOptionByID(options, optionID)
    if not optionID then
        return nil
    end

    for _, option in ipairs(options) do
        if tonumber(option.gossipOptionID) == optionID then
            return option
        end
    end

    return nil
end

local function FindOptionByText(options, keyword)
    local target = Normalize(keyword)
    if target == "" then
        return nil
    end

    for _, option in ipairs(options) do
        local name = Normalize(option.name)
        if name ~= "" and string.find(name, target, 1, true) then
            return option
        end
    end

    return nil
end

-- 返回 option 以及命中方式（"id" / "text"）。
local function FindOption(options, step)
    local option = FindOptionByID(options, step.optionID)
    if option then
        return option, "id"
    end

    option = FindOptionByText(options, step.match)
    if option then
        return option, "text"
    end

    return nil
end

-- 用 upvalue 里的 Talk 调用，避免任何调用方忘记传 self 时直接报错。
local function EnsureOptionHook()
    if Talk.hookInstalled or type(_G.GossipOptionButtonMixin) ~= "table" then
        return
    end

    hooksecurefunc(_G.GossipOptionButtonMixin, "Setup", function()
        Talk.Process()
    end)

    Talk.hookInstalled = true
end

function Talk.IsEnabled()
    return ns.Config:IsEnabled("autoHunt")
end

function Talk.SetEnabled(enabled)
    ns.Config:SetEnabled("autoHunt", enabled and true or false)
    ns.Addon:Print(string.format(
        ns.L.TALK_STATUS,
        Talk.IsEnabled() and ns.L.ON or ns.L.OFF
    ))
end

function Talk.OnSettingsChanged()
    if not Talk.IsEnabled() then
        Talk.ResetSession()
        Talk.ResetChain()
    end
end

function Talk.ResetSession()
    Talk.handled = {}
    Talk.progress = {}
    Talk.active = false
    Talk.scheduleUntil = nil
end

function Talk.ResetChain()
    Talk.chainUntil = nil
    Talk.chainCount = 0
end

-- 第一步用的是很有辨识度的整句，本身就可以作为触发条件；
-- 后面的短关键词（例如"梦魇"）只在任务条件成立或仍处在同一次自动选择链条里才生效，
-- 避免在别的对话里误选。
function Talk.IsStepActive(rule, stepIndex, chained)
    if stepIndex == 1 or chained or not rule.questID then
        return true
    end

    if not C_QuestLog or type(C_QuestLog.IsOnQuest) ~= "function" then
        return false
    end

    return C_QuestLog.IsOnQuest(rule.questID) and true or false
end

function Talk.Select(option)
    if not C_GossipInfo then
        return false
    end

    local optionID = tonumber(option.gossipOptionID)
    if optionID and type(C_GossipInfo.SelectOption) == "function" then
        C_GossipInfo.SelectOption(optionID)
    elseif option.orderIndex and type(C_GossipInfo.SelectOptionByIndex) == "function" then
        C_GossipInfo.SelectOptionByIndex(option.orderIndex)
    else
        return false
    end

    ns.Addon:Print(string.format(ns.L.TALK_SELECTED, Trim(option.name)))
    return true
end

function Talk.Process()
    if not Talk.IsEnabled() or not Talk.active then
        return
    end

    if not C_GossipInfo or type(C_GossipInfo.GetOptions) ~= "function" then
        return
    end

    if IsShiftKeyDown and IsShiftKeyDown() then
        return
    end

    local options = C_GossipInfo.GetOptions()
    if type(options) ~= "table" or #options == 0 then
        return
    end

    local signature = BuildSignature(options)
    if not signature or (Talk.handled and Talk.handled[signature]) then
        return
    end

    local now = GetTime()
    local chained = Talk.chainUntil ~= nil and now < Talk.chainUntil
    if not chained then
        Talk.chainCount = 0
    end

    for _, rule in ipairs(RULES) do
        local progress = (Talk.progress and Talk.progress[rule.key]) or 0
        for stepIndex, step in ipairs(rule.steps) do
            if stepIndex > progress and Talk.IsStepActive(rule, stepIndex, chained) then
                local option = FindOption(options, step)
                if option then
                    if Talk.chainCount >= MAX_CHAIN_SELECTIONS then
                        return
                    end

                    Talk.handled = Talk.handled or {}
                    Talk.handled[signature] = true
                    if Talk.Select(option) then
                        Talk.progress = Talk.progress or {}
                        Talk.progress[rule.key] = stepIndex
                        Talk.chainUntil = GetTime() + CHAIN_SECONDS
                        Talk.chainCount = Talk.chainCount + 1
                    end
                    return
                end
            end
        end
    end
end

function Talk.Schedule()
    local now = GetTime()
    if Talk.scheduleUntil and now < Talk.scheduleUntil then
        return
    end
    Talk.scheduleUntil = now + 2

    for _, delay in ipairs(ATTEMPT_DELAYS) do
        local function Runner()
            Talk.Process()
        end

        if C_Timer and C_Timer.After then
            C_Timer.After(delay, Runner)
        elseif delay == 0 then
            Runner()
        end
    end
end

function Talk.OnDialogueOpened(event)
    Talk.active = true

    EnsureOptionHook()
    Talk.Schedule()
end

function Talk.OnGossipShow()
    Talk.OnDialogueOpened("GOSSIP_SHOW")
end

function Talk.OnQuestGreeting()
    Talk.OnDialogueOpened("QUEST_GREETING")
end

function Talk.OnGossipClosed()
    Talk.ResetSession()
end

function Talk.Initialize()
    Talk.ResetSession()
    Talk.ResetChain()
    EnsureOptionHook()
end
