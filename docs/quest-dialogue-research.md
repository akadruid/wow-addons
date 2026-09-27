# 任务对话快速选择可行性调研

调研日期：2026-09-27（Asia/Shanghai）

调研环境：正式服 `12.1.0 (69814)`，本机客户端目录 `D:\game\World of Warcraft\_retail_`

调研目标：能否做成"通用任务对话快速选择"插件，即"接了指定任务后，和 NPC 对话时固定选择某个选项"；如果做不到通用，是否可以针对单个任务定制。

## 一、结论

1. 可以做通用插件，不需要逐任务定制代码。
2. 技术上只有三步：监听对话事件、读取当前对话选项列表、命中规则后调用选择接口。
3. 对话选项带稳定 ID（`gossipOptionID`），与客户端语言无关，因此可以做成"规则表 + 采集界面"的通用形态。
4. 本机已经安装的多个插件在 `12.1.0` 上就是这么做的（见第二节），说明该接口没有被封锁，也不需要模拟硬件事件。

进一步说：只要目标任务的对话属于"普通 NPC 对话选项"（`GossipFrame`），新增一个任务就是往规则表里加一行配置。只有下面第五节的几类界面才真的需要单独定制开发。

## 二、证据：本机 12.1.0 上正在运行的同类实现

| 插件 | 文件 | 做法 |
| --- | --- | --- |
| DialogueUI（Curse，`v1.0.5 f`） | `Code\GossipData\GossipData_AutoSelect.lua` | 内置 `gossipOptionID → 自动选择` 映射表。值 `true` 表示总是自动选，值 `1` 表示仅当它是唯一选项时才自动选。表中已经包含 Midnight（12.x）任务对话，例如 `136045 (Quest) Let's spar! Armies of Darkness`、`135188 (Quest) Vyrin wants you to join him at Saltheril's Haven` |
| DialogueUI | `Code\GossipData\GossipData_AutoQuest.lua` | 内置自动接取/自动交付任务表，其中已包含本插件关注的符文石周常 `90573 90574 90575 90576` |
| DialogueUI | `Code\Dialogue\DialogueUI.lua`（约 1140–1195 行） | 真正的选择逻辑：先判断"是否唯一选项"，再调用 `C_GossipInfo.SelectOptionByIndex` 或 `C_GossipInfo.SelectOption` |
| ExwindTools | `Modules\NODISPLAY\ExTools.GossipID.lua` | 在对话选项行右侧挂一个 "+" 小图标，悬停显示 `gossipOptionID`，点击即把该 ID 加入"自定义自动对话"；也支持手动输入 ID。这是"通用采集界面"的现成参考 |
| EXBoss | `Modules\AutoGossip.lua` | 预设 `gossipOptionID` 列表（学院 BUFF `107065/107081/107082/107083/107088` 等），`GOSSIP_SHOW` 后自动选择，并用"选项签名"去重，避免重复触发 |
| Plumber | `Modules\AutoJoinEvents.lua` | 用"地图 + NPC 名 + `gossipOptionID`"三重条件限定，自动选择剧场巡演、时光裂缝的报到选项 |
| BigWigs / LittleWigs | `BigWigs_Core\BossPrototype.lua`（Gossip API 段落） | `C_GossipInfo.GetOptions()` + `C_GossipInfo.SelectOption(id, "", skipConfirmDialogBox)`，并附带 `C_PlayerChoice` 支持 |

也就是说，本机就有 5 个不同作者的插件在做同一件事，全部标注支持 `12.1.0`。

## 三、可用接口清单（12.1.0）

### 事件

| 事件 | 用途 |
| --- | --- |
| `GOSSIP_SHOW` / `GOSSIP_CLOSED` | NPC 普通对话打开 / 关闭 |
| `GOSSIP_CONFIRM` / `GOSSIP_CONFIRM_CANCEL` / `GOSSIP_ENTER_CODE` | 需要二次确认或输入文本的对话 |
| `QUEST_GREETING` | NPC 直接列出任务（可接 / 可交），不走普通对话选项 |
| `QUEST_ACCEPTED` / `QUEST_REMOVED` / `QUEST_TURNED_IN` | 任务状态变化，用来刷新规则条件 |

### 读取与选择

| 接口 | 用途 |
| --- | --- |
| `C_GossipInfo.GetOptions()` | 返回当前对话选项数组，元素含 `gossipOptionID`、`orderIndex`、`name`、`icon` |
| `C_GossipInfo.SelectOption(gossipOptionID [, text, confirmed])` | 按 ID 选择；第二、三个参数用于输入型或确认型对话 |
| `C_GossipInfo.SelectOptionByIndex(orderIndex)` | 按显示顺序选择 |
| `C_GossipInfo.GetAvailableQuests()` / `SelectAvailableQuest(questID)` | 读取 / 选择可接任务 |
| `C_GossipInfo.GetActiveQuests()` / `SelectActiveQuest(questID)` | 读取 / 选择可交任务（`quest.isComplete` 表示可交） |
| `C_PlayerChoice.GetCurrentPlayerChoiceInfo()` / `SendPlayerChoiceResponse(...)` | 另一类"抉择"界面，不是对话选项 |

### 条件判断

| 接口 | 用途 |
| --- | --- |
| `C_QuestLog.IsOnQuest(questID)` / `C_QuestLog.IsQuestFlaggedCompleted(questID)` | 任务是否已接 / 本周是否已完成（本插件 Runestone 模块已在用） |
| `UnitName("npc")` / `UnitGUID("npc")` / `GetCreatureIDFromGUID(UnitGUID("npc"))` | 限定 NPC |
| `C_Map.GetBestMapForUnit("player")` / `GetInstanceInfo()` | 限定地图或副本 |

## 四、通用插件设计草案

### 规则表（SavedVariables）

```lua
rules = {
    {
        questID = 90574,          -- 条件：该任务在任务日志中
        optionID = 123456,        -- 动作：选择这个对话选项
        onlyWhenSingle = true,    -- 仅当它是唯一选项时才自动选
        npcName = nil,            -- 可选：限定 NPC
        mapID = nil,              -- 可选：限定地图
        enabled = true,
        note = "加固符文石：血骑士",
    },
}
```

### 运行时流程

1. 注册 `GOSSIP_SHOW`、`QUEST_GREETING`、`GOSSIP_CLOSED`。
2. 对话打开时读取 `C_GossipInfo.GetOptions()`，构造"选项签名"（`orderIndex : gossipOptionID : name` 拼接）。
3. 签名与上一次已处理的签名相同则直接返回，避免死循环与重复点击。
4. 按顺序检查规则：是否启用 → 任务条件（`C_QuestLog.IsOnQuest`）→ 可选 NPC / 地图条件 → 目标 ID 是否出现在当前选项里。
5. 命中后调用 `C_GossipInfo.SelectOption(optionID)`，记录签名并输出一行提示。
6. `GOSSIP_CLOSED` 时清空签名记录。
7. 连续多段对话（同一个 NPC 反复弹窗）需要次数上限，例如每个对话会话最多触发 N 次，防止脚本失控。

### 界面与命令

- 采集入口：在 `GossipOptionButtonMixin.Setup` 上 `hooksecurefunc`，给每个选项行加 ID 文本和 "+" 图标（做法与 ExwindTools 一致）。
- 配置入口：沿用现有 `UI.lua` 的窗口风格，加一个"任务对话"区块，列出规则并支持启用 / 停用 / 删除。
- 命令：`/aa talk add <optionID> [questID]`、`/aa talk list`、`/aa talk remove <index>`、`/aa talk on`、`/aa talk off`。

### 默认安全策略

- 默认 `onlyWhenSingle = true`，即"只有这一个选项时才自动选"，与 DialogueUI 的 `1` 语义一致。
- 多个选项同时存在时自动选择必须显式指定 ID 并显式开启。
- 规则默认要求带任务条件或 NPC 条件，避免在任意 NPC 处误选。
- 带二次确认弹窗的选项默认不自动确认，需要用户明确授权后再跳过。

## 五、做不到通用、需要单独定制的部分

1. 不是对话选项的界面
   - 任务详情页 / 完成页（`QUEST_DETAIL` / `QUEST_COMPLETE`）与奖励选择（`GetQuestReward`）。
   - 抉择界面（`C_PlayerChoice`）。
   - 地下堡难度 / 伙伴选择框（`DelvesDifficultyPickerFrame`）。
   - 这些都要单独写模块，并在游戏内逐项验证。
2. Taint 风险
   - 本机 EllesmereUI 的源码注释记录了实测结论：从插件执行里调用 `ShowQuestComplete()` 会污染后续地图与奖励相关调用，所以他们的做法是放弃该路径，交回暴雪原生流程。"任务完成 / 奖励"这类流程远比"对话选项"危险。
3. 受限内容里的"秘密值"
   - 在地下城、团本、PvP、史诗钥石等状态下，`UnitName` 等接口可能返回 secret 值（Plumber 为此单独封装了 `Secret_GetUnitName`）。开放世界任务对话不受影响；如果要在副本里使用，NPC 判定需要退化成"不看 NPC 名称"。
4. 少数选项只有文本、ID 不稳定
   - 只能用文本匹配兜底，容易因语言或措辞变化而失效。

## 六、与已装插件的关系

本机已安装 DialogueUI 与 ExwindTools，两者都能做类似的事，但覆盖面有限：

- DialogueUI 的 `AutoSelectGossip` 默认关闭。
- ExwindTools 的自动对话默认开启，但只覆盖"学院 BUFF"一个预设，自定义列表为空。

建议本插件的任务对话模块自带独立开关，只处理自己的规则。如果两边规则命中同一个选项，会出现重复点击，需要避免。

## 七、落地建议

1. 先实现通用模块：规则表 + 选项 ID 采集界面 + `/aa talk` 命令。
2. 用目标任务的真实数据加第一条预设，并在游戏内实测。
3. 如果确实需要，再把"自动接取 / 自动交付任务"合并进同一模块。

## 八、需要确认的信息

- 具体任务名称或任务 ID（任务日志截图也可以）。
- 对话中要固定选择的那句话的原文，以及出现时机（接了任务之后，还是交任务时）。
- 该选项通常是否唯一，还是会和其他选项同时出现。
- 是否需要顺带自动接取 / 自动交付该任务。
- 是否允许在只有一个选项时无条件自动选择。

## 九、只用本地插件能不能直接做到

结论：能自动选对话选项，但都不能把"接了某个任务"当作触发条件。三条可用路径的成本和限制如下。

### 本机三个相关开关的当前状态（2026-09-27 检查）

配置文件位于 `D:\game\World of Warcraft\_retail_\WTF\Account\191236879#1\SavedVariables\`：

| 插件 | 键 | 当前值 | 含义 |
| --- | --- | --- | --- |
| DialogueUI | `AutoSelectGossip` | `false` | 内置自动选择列表未启用 |
| DialogueUI | `AutoCompleteQuest` | `false` | 内置自动交付列表未启用 |
| ExwindTools | `LoadByKey["ExTools.GossipID"]` | `false` | 整个"对话ID显示 / 自动对话"模块处于禁用状态 |
| EXBoss | `autoGossip.enabled` | `false` | 自动对话未启用 |

也就是说目前没有任何插件在自动选择对话选项，不存在冲突。

### 路径一：DialogueUI（开关即可，规则不可编辑）

- 设置入口：小地图旁的插件栏图标，或"选项 → 插件"。
- `Auto Select Gossip`：启用作者内置的 `gossipOptionID` 自动选择表。表中 `1` 的条目只在"它是唯一选项"时自动选，比较安全。
- `Auto Complete Quest`：启用内置的自动交付任务表。该表里已经包含符文石周常 `90573 90574 90575 90576`，会在对话里自动选中可交付任务。
- 限制：规则是作者硬编码的，用户不能自己加"某个任务 → 某个选项"。

### 路径二：ExwindTools（可以自己指定选项，但不能限定任务）

- 打开方式：`/ex`、`/extools` 或 `/exwindtools`。
- 先在模块管理里启用"对话ID显示"模块（当前是禁用状态），再在模块设置里勾选"启用自动对话"。
- 之后和 NPC 对话时，每个选项行右侧会出现 ID 文本和 "+" 按钮，点击即把该选项加入自定义自动对话列表；也可以在设置里手动输入对话 ID 和名称。
- 限制：规则的字段只有"启用、名称、记录时的副本"，没有任务条件；并且命中即选，没有"仅唯一选项时选"的保护。只要该选项在任何 NPC 处出现都会被选中。

### 路径三：EXBoss（只能逐项开关作者预设）

- 预设覆盖学院 BUFF、洞穴大锅、救援、NPX BUFF 等固定场景，不能自己加选项。

### 判断标准

- 如果需求是"只要和这个 NPC 对话就固定选这一项"，路径一或路径二直接够用，不需要写代码。
- 如果需求是"任务没接时不要自动选""任务交完就自动停止""只有接了任务 A 时才对选项 B 生效"，三个本地插件都做不到，需要在 `AzerothAssistant` 里新增模块（规则表 + 选项 ID 采集 UI，约 100~200 行）。

## 十、目标任务落地：狩猎：择优猎杀

第八节需要的信息已由用户提供，本节是据此确认的数据与已完成的实现。

### 已确认的数据

| 数据 | 值 | 来源 |
| --- | --- | --- |
| 任务名 | `狩猎：择优猎杀` | 用户提供 |
| 任务 ID | `91277` | `SavedInstances` 存档 |
| 任务类型 | 银月城日常（`isDaily = true`） | `SavedInstances` 存档 |
| 英文名 | Prey: Preferential Killing | `Plumber\Modules\ExpansionLandingPage\Retail\MID_Activity.lua` 注释 |
| 选择后的结果任务 | `95024 狩猎：利爪卡达尼（梦魇）`，地点 `盘卷蛇岛`（mapID `2512`） | `SavedInstances` 存档 |
| 官方接口 | `C_QuestLog.GetActivePreyQuest()` 返回当前狩猎任务 | `Plumber\Modules\PreyQuestSuperTrack.lua` |
| 难度取值 | `1` 普通、`2` 困难、`3` 梦魇 | `Plumber\Modules\Shared\SharedData.lua` 的 `PreyQuestData` |

固定选择序列：

1. 你们提供的太无趣了。我要自己挑选猎物
2. 利爪卡达尼
3. 盘卷蛇岛
4. 梦魇

### 实现

- 新增模块 `AzerothAssistant/Talk.lua`。
- 监听 `GOSSIP_SHOW` 与 `GOSSIP_CLOSED`，另外在 `GossipOptionButtonMixin.Setup` 上挂 `hooksecurefunc`，覆盖"选项变化但不重新触发 GOSSIP_SHOW"的情况。
- 规则表 `RULES` 保存任务 ID 与步骤关键词，按顺序匹配 `C_GossipInfo.GetOptions()` 返回的选项文本；文本先去掉颜色/材质标记并压缩空白。
- 第一步使用完整句子触发；第二到第四步要求"任务 `91277` 在任务日志中"或"仍处在同一次自动选择链条内（30 秒）"，避免短关键词在别的对话里误选。
- 命中后调用 `C_GossipInfo.SelectOption(gossipOptionID)`，拿不到 ID 时退回 `SelectOptionByIndex(orderIndex)`。
- 同一份选项列表只处理一次；每条对话链最多连续自动选择 10 次。
- 对话时按住 `Shift` 跳过自动选择。
- 命令：`/aa talk`、`/aa talk on`、`/aa talk off`、`/aa talk list`。
- 游戏内实测确认：四步分别对应对话选项 ID `134312 → 140843 → 140847 → 134313`，规则优先按 ID 匹配。

### 仍需在客户端验证

- 这四个选项确实通过普通对话选项（gossip）呈现，已在游戏内验证通过。
- 选项文本与 ID 已在 `12.1.0` 实测记录；客户端更新后如果选项 ID 变化，需要同步更新规则。
- 挑选过程中任务 `91277` 一直在任务日志中；第二到第四步另外还有 30 秒链条窗口兜底。
