# 正式服 逃课助手 API 调研

调研日期：2026-09-14（Asia/Shanghai）

## 版本基线

当前正式服 UI 源码的最新提交为 `12.1.0 (69814)`，提交时间为 2026-09-12。Warcraft Wiki 的主 API 索引标注为 PTR `12.1.5 (69594)`，因此本项目的功能 API 同时与当前正式服生成文档和下一 PTR 文档做了对比。

主要来源：

- [World of Warcraft API](https://warcraft.wiki.gg/wiki/World_of_Warcraft_API)
- [C_PartyInfo.InviteUnit](https://warcraft.wiki.gg/wiki/API:C_PartyInfo.InviteUnit)
- [GetGuildRosterInfo](https://warcraft.wiki.gg/wiki/API:GetGuildRosterInfo)
- [GetNumGuildMembers](https://warcraft.wiki.gg/wiki/API:GetNumGuildMembers)
- [C_GuildInfo.GuildRoster](https://warcraft.wiki.gg/wiki/API:C_GuildInfo.GuildRoster)
- [GUILD_ROSTER_UPDATE](https://warcraft.wiki.gg/wiki/Event:GUILD_ROSTER_UPDATE)
- [GROUP_ROSTER_UPDATE](https://warcraft.wiki.gg/wiki/Event:GROUP_ROSTER_UPDATE)
- [GetBindingKey](https://warcraft.wiki.gg/wiki/API:GetBindingKey)
- [C_VignetteInfo.GetVignettes](https://warcraft.wiki.gg/wiki/API:C_VignetteInfo.GetVignettes)
- [C_VignetteInfo.GetVignetteInfo](https://warcraft.wiki.gg/wiki/API:C_VignetteInfo.GetVignetteInfo)
- [Wago Tools Vignette](https://wago.tools/db2/Vignette?locale=zhCN)
- [Gethe/wow-ui-source live](https://github.com/Gethe/wow-ui-source/tree/live)
- [Ketho/wow-ui-source-midnight-ptr](https://github.com/Ketho/wow-ui-source-midnight-ptr)

## 结论摘要

第一版采用以下接口：

| 用途 | 接口 | 当前结论 |
| --- | --- | --- |
| 请求公会名册刷新 | `C_GuildInfo.GuildRoster()` | 正式服和 PTR 生成文档仍存在；两次调用之间有约 10 秒节流 |
| 获取成员数量 | `GetNumGuildMembers()` | 返回 `numTotal, numOnline`；传统名册最多 500 人 |
| 读取成员详情 | `GetGuildRosterInfo(index)` | 返回角色名、职业、等级、区域、在线状态、GUID 等字段 |
| 邀请成员 | `C_PartyInfo.InviteUnit(name)` | 当前推荐调用；名称参数为 `cstring` |
| 判断邀请权限 | `C_PartyInfo.CanInvite()` | 返回布尔值 |
| 判断小队满员 | `C_PartyInfo.IsPartyFull([category])` | 不传参数时使用当前队伍类别 |
| 判断成员是否已在队伍 | `C_PartyInfo.IsGUIDInGroup(guid[, category])` | 用于禁用已在小队中的公会成员 |
| 监听名册变化 | `GUILD_ROSTER_UPDATE(canRequestRosterUpdate)` | 名册数据变化后刷新 |
| 监听小队变化 | `GROUP_ROSTER_UPDATE` | 队伍创建、解散、加入或离开时刷新 |
| 显示快捷键 | `GetBindingKey(command)` | 返回命令当前绑定的按键，可能返回多个值 |
| 查询当前 Vignette | `C_VignetteInfo.GetVignettes()` | 返回当前客户端和位面的 Vignette GUID |
| 读取 Vignette 详情 | `C_VignetteInfo.GetVignetteInfo(vignetteGUID)` | 返回 Vignette ID、名称、存活状态和地图标记信息 |

## 永歌森林符文石事件

真正的符文石是独立的 Vignette 地图事件，不要和 `Saltheril's Soiree / 萨瑟利尔的聚会` 混在一起。周常任务只是消费该地图事件的结果。

仅有 Vignette 只能说明符文石在地图上刷新，不能说明它已经充能激活。游戏内 tooltip 有两种状态：

- 未激活：出现“这个符文石需要充能！使用潜藏奥能为其充能。”
- 已激活：只显示“符文石状态：”，没有“需要充能／潜藏奥能”提示

已确认的区域数据：

| 数据 | 值 |
| --- | --- |
| Vignette 名称 | `符文石 / Runestone` |
| Vignette ID 1 | `6951` |
| Vignette ID 2 | `6954` |
| Vignette ID 3 | `6955` |
| Vignette ID 4 | `6959` |
| Vignette ID 5 | `7130` |

当前实现先调用：

```lua
local active = {}
for _, vignetteGUID in ipairs(C_VignetteInfo.GetVignettes()) do
    local info = C_VignetteInfo.GetVignetteInfo(vignetteGUID)
    if info and not info.isDead and RUNESTONE_VIGNETTE_IDS[info.vignetteID] then
        active[#active + 1] = info
    end
end
```

然后读取 `vignetteInfo.tooltipWidgetSet`，通过 `GameTooltip_AddWidgetSet` 构建一个隐藏 tooltip，并递归读取其中 FontString 文本。

判定规则：

```lua
if text contains "需要充能" or "潜藏奥能" or "recharge" then
    -- 未激活
elseif text contains "符文石状态" then
    -- 已激活
end
```

原因：

- `C_VignetteInfo.GetVignettes()` 返回当前客户端和位面中正在存在的 Vignette。
- 符文石使用独立 Vignette 模板，名称本地化为“符文石”，不是萨瑟利尔的聚会 POI。
- 同一时间可能有多个随机位置的符文石 Vignette 存在，因此输出数量而不是只判断一个。
- `isDead` 为 true 的 Vignette 不计入正在激活的数量。
- Tooltip 状态文本来自暴雪自己的 Vignette tooltip widget，和玩家在地图悬停时看到的内容一致。

运行时还需要在当前正式服位面确认 tooltip 文本读取是否稳定；无法读取时插件会显示“无法确认”，不会误报已激活。

标准聊天框输出保持精简：

```text
[符文石检测] 位面 1234：不存在
[符文石检测] 位面 1234：未激活
[符文石检测] 位面 1234：左中 已激活
```

其中位置名称使用黄色，`已激活` 使用绿色。坐标和 Vignette ID 仅通过 `/che rune debug` 输出。

四个周常任务同时使用 `C_QuestLog.IsOnQuest(questID)` 和 `C_QuestLog.IsQuestFlaggedCompleted(questID)` 检查：

| Quest ID | 任务 |
| --- | --- |
| `90574` | 加固符文石：血骑士 |
| `90573` | 加固符文石：魔导师 |
| `90575` | 加固符文石：远行者 |
| `90576` | 加固符文石：径巷之影 |

任一判断为真，该任务就计入本周已满足数量。未全部满足时，额外输出 `符文石任务缺失X/4`；X 为已满足数量，`X/4` 使用红色。

## 最近版本变化

### 12.0.5

以下组队相关接口在战斗中不再允许插件调用：

- `C_PartyInfo.PromoteToLeader`
- `C_PartyInfo.PromoteToAssistant`
- `C_PartyInfo.DemoteAssistant`
- `C_PartyInfo.SetEveryoneIsAssistant`
- `C_PartyInfo.DoReadyCheck`
- `C_PartyInfo.ConfirmReadyCheck`
- `C_PartyInfo.ConvertToParty`
- `C_PartyInfo.ConvertToRaid`
- `C_PartyInfo.ConfirmConvertToRaid`
- `C_PartyInfo.DoCountdown`
- `C_PartyInfo.SetRestrictPings`
- `C_PartyInfo.SetLootMethod`

`C_PartyInfo.InviteUnit` 不在这份战斗限制列表中。它带有 `RequiresValidInviteTarget` 和 `SecretArguments = AllowedWhenUntainted` 标记，但本插件传入的是公会名册返回的普通字符串，不依赖秘密值。

### 12.0.7

一批旧全局队伍函数迁移到 `C_PartyInfo`：

- `ConfirmReadyCheck` -> `C_PartyInfo.ConfirmReadyCheck`
- `DemoteAssistant` -> `C_PartyInfo.DemoteAssistant`
- `DoReadyCheck` -> `C_PartyInfo.DoReadyCheck`
- `PromoteToAssistant` -> `C_PartyInfo.PromoteToAssistant`
- `PromoteToLeader` -> `C_PartyInfo.PromoteToLeader`
- `SetEveryoneIsAssistant` -> `C_PartyInfo.SetEveryoneIsAssistant`
- `UninviteUnit` -> `C_PartyInfo.UninviteUnit`
- `IsGUIDInGroup` -> `C_PartyInfo.IsGUIDInGroup`

本插件直接使用新命名空间，不依赖旧全局别名。

### 12.1.0 与 12.1.5

与公会小队邀请直接相关的函数没有发现签名变化。正式服 `12.1.0` 和 PTR `12.1.5` 的生成文档中，以下定义一致：

```lua
C_PartyInfo.InviteUnit(name)
C_PartyInfo.ConfirmInviteUnit(name)
C_PartyInfo.CanInvite()
C_PartyInfo.IsPartyFull([category])
C_GuildInfo.GuildRoster()
```

## 为什么不使用 ConfirmInviteUnit

`C_PartyInfo.ConfirmInviteUnit(name)` 会立即执行邀请，不处理可能的破坏性确认。例如队伍将被转换为团队，或者队伍同步正在进行时，客户端本来需要用户确认。

本插件只组建最多 5 人的小队，并使用 `C_PartyInfo.InviteUnit`。这样：

- 保留暴雪原生确认框
- 不绕过队伍同步提示
- 不绕过转团队提示

## 为什么不把 C_Club 作为第一版主数据源

当前公会 UI 使用 `C_Club` 展示社区式成员列表：

```lua
local clubId = C_Club.GetGuildClubId()
local memberIds = C_Club.GetClubMembers(clubId)
local memberInfo = C_Club.GetMemberInfo(clubId, memberId)
```

在线状态由 `memberInfo.presence` 判断，在线状态包括 `Online`、`Away`、`Busy` 和 `OnlineMobile`。

但当前生成文档把 `C_Club.GetClubMembers`、`C_Club.GetMemberInfo` 和 `C_Club.GetMemberInfoForSelf` 标记为 `SecretInChatMessagingLockdown = true`。这意味着在地下城、团队副本、遭遇战、史诗钥石或 PvP 等限制状态下，返回数据可能变成秘密值，普通插件不能可靠地迭代、比较或再次传递给 API。

传统公会名册接口当前仍然存在，且不带有这些秘密值限制，因此“当前角色公会”来源继续使用它。`C_Club` 只用于“角色社区”来源，细节见下面的社区邀请来源一节。

## 社区（C_Club）邀请来源

调研日期：2026-09-27（Asia/Shanghai）

依据 `Gethe/wow-ui-source` 的 `live` 分支：`Blizzard_APIDocumentationGenerated/ClubDocumentation.lua`、`Blizzard_Communities/CommunitiesMemberList.lua`、`Blizzard_UnitPopup/Standard/UnitPopupMenus.lua`、`Blizzard_UnitPopupShared/UnitPopupSharedMenus.lua`、`Blizzard_FrameXMLUtil/CommunitiesUtil.lua`。

### 接口

| 用途 | 接口 | 说明 |
| --- | --- | --- |
| 列出已加入的社区 | `C_Club.GetSubscribedClubs()` | 返回 `ClubInfo` 表，含 `clubId`、`name`、`clubType`、`memberCount` |
| 读取社区成员 | `C_Club.GetClubMembers(clubId[, streamId])` | 不传 `streamId` 时返回整个社区的成员 ID |
| 读取成员详情 | `C_Club.GetMemberInfo(clubId, memberId)` | 返回 `ClubMemberInfo` |
| 判断数据是否就绪 | `INITIAL_CLUBS_LOADED` | 该事件之前社区数据不可用 |
| 成员变化 | `CLUB_MEMBER_ADDED / REMOVED / UPDATED`、`CLUB_MEMBER_PRESENCE_UPDATED`、`CLUB_MEMBERS_UPDATED` | 用来刷新名册 |

本插件用到的 `ClubMemberInfo` 字段：

```text
name（角色名，可能带服务器）、classID、level、zone、presence、role、guid、isSelf
```

`Enum.ClubMemberPresence`：`Unknown 0 / Online 1 / OnlineMobile 2 / Offline 3 / Away 4 / Busy 5`。

`Enum.ClubType`：`BattleNet 0 / Character 1 / Guild 2 / Other 3`。

在线状态映射到与公会来源相同的状态码：`Online → 在线`、`Away → 暂离`、`Busy → 忙碌`、`OnlineMobile → 手机在线`；`Offline` 与 `Unknown` 不计入可邀请列表。

### 为什么只支持角色社区

暴雪的右键菜单把社区成员分成两套：

- 角色社区（`Enum.ClubType.Character`）成员使用 `COMMUNITIES_WOW_MEMBER` 菜单，其中包含“邀请加入队伍”子菜单，最终执行 `C_PartyInfo.InviteUnit(memberInfo.name)`。
- 战网社区（`Enum.ClubType.BattleNet`）成员使用 `COMMUNITIES_MEMBER` 菜单，整份菜单没有任何队伍邀请项，只有“添加战网好友”。也就是说客户端本身不提供从战网社区直接邀请队伍的能力。

因此可选来源只列出 `clubType == Character` 的社区。`InviteUnit` 的入参就是暴雪菜单里 `contextData.name` 使用的同一个 `memberInfo.name`，与官方行为保持一致。

### 秘密值限制

`GetSubscribedClubs`、`GetClubMembers`、`GetMemberInfo` 在生成文档里都带 `SecretInChatMessagingLockdown = true`。在地下城、团本、PvP、史诗钥石等聊天限制状态下，返回值可能变成秘密值，插件无法可靠迭代。

处理方式：调用前检查 `C_ChatInfo.InChatMessagingLockdown()`，为真时跳过刷新并显示“当前无法读取该社区的成员数据”，不会误报空名单；所有 `C_Club` 调用都包在 `pcall` 里。

### 公会来源不变

选择“当前角色公会”时仍然使用 `GetNumGuildMembers` / `GetGuildRosterInfo`，因为传统接口不受秘密值限制，而且能直接拿到职位、等级和区域。

## 实现边界

- 只列出在线成员，不建立离线成员列表
- 排除当前玩家
- 已在小队中的成员会显示但不可选择
- 小队容量按 5 人计算
- 当前在团队中时禁用邀请
- 每次根据当前剩余空位限制选择人数
- 逐个邀请，默认间隔 0.8 秒
- 首位邀请会先校验小队状态，再选择当前列表中首个未在小队中的在线成员
- 邀请过程中如果队伍状态变化或满员，停止后续队列

## 仍需在客户端验证

- `GetGuildRosterInfo` 在当前正式服的实际字段顺序
- 跨服角色名的自我排除逻辑
- `C_PartyInfo.CanInvite()` 在队长、助理和无队伍状态下的返回值
- `C_PartyInfo.IsPartyFull()` 对小队和团队类别的实际行为
- 连续触发 `InviteUnit` 时客户端邀请限流和确认框行为
- 中文输入法下的搜索框占位文本与 `OnTextChanged` 行为
- 符文石未激活和已激活时，五个 Vignette ID 各自的 `isDead`、`onWorldMap` 和存在数量
- 同一时间实际同时存在 3 个、4 个还是 5 个符文石 Vignette
