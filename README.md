# Cheeser / 逃课助手

面向《魔兽世界》正式服的“逃课”小工具：把多角色、重复性的操作收进一条极简快捷栏，能少点一下是一下。

作者：[akadruid](https://github.com/akadruid) · 仓库：[akadruid/wow-addons](https://github.com/akadruid/wow-addons) · 许可：[MIT](LICENSE)

当前基线：

- 正式服 `12.1.0 (69814)`，TOC `Interface: 120100`
- 面向 `zhCN` 客户端，保留 `enUS` 回退文本

## 功能

- 极简快捷栏 `[邀] [符]`：一键组队、一键查符文石。
- 公会 / 社区一键邀请：自动邀请来源中首位符合条件的在线成员。
- 符文石状态检测：进入永歌森林自动检测，手动查询可通报小队。
- 集合石账号级收藏：所有角色共享同一份“最近搜索”收藏。
- 任务对话自动选择：接 `狩猎：择优猎杀` 后自动走完四步。
- 快速离队：绑定快捷键即可无确认离队。

## 快捷栏

默认在屏幕顶部左侧显示两个并排文字按钮 `[邀] [符]`：

- `邀`：邀请当前来源（当前角色公会，或某个角色社区）中首位符合条件的在线成员。
- `符`：手动查询当前位面的保护符文石状态。
- `符` 的颜色：灰=不存在，黄=未激活，绿=已激活。
- 右键任一按钮锁定 / 解锁；解锁后可拖动整条快捷栏，位置自动保存。
- 两个按钮可分别在设置面板关闭；都关闭时快捷栏自动隐藏。

## 设置面板

打开方式：`选项 → 插件 → 逃课助手`，或输入 `/che`（`/cheeser` 同义）。

- 公会 / 社区邀请助手：开关 + 邀请来源下拉框。
- 符文石助手：开关 + “符文石状态通报小队”（默认开启，仅手动查询时通报）。
- 自动蛇岛梦魇狩猎：开关。
- 集合石收藏：打开收藏窗口按钮。
- 底部列出常用命令。

## 命令

主命令 `/che`，别名 `/cheeser`。

| 命令 | 作用 |
| --- | --- |
| `/che` | 打开设置面板 |
| `/che rune` | 手动查询符文石状态（开启通报时同步发送到小队） |
| `/che rune debug` | 输出每个符文石的 ID、坐标和状态 |
| `/che stone` | 打开集合石收藏窗口 |
| `/che talk` | 开关“任务对话自动选择” |
| `/che leave` | 无需确认直接离开当前小队 |

集合石子命令：

```text
/che stone addcurrent         收藏集合石当前搜索
/che stone add 1-397-1943-0   按活动代码收藏
/che stone add 永歌森林        按名称关键字收藏
/che stone list
/che stone remove 1
/che stone on / off
/che stone reset
```

## 快捷键

`选项 → 按键设置 → 插件 → 逃课助手`：

- 邀请首位符合条件的在线成员
- 无需确认直接离开当前小队

## 保护符文石

- 识别永歌森林的 5 个符文石位置：左上、左中、中间、右下、左下。
- 登录、进入永歌森林、进/退队伍、位面变化时自动检测。
- 一个周常都没接时，只提示 `符文石任务缺失0/4`，不输出符文石状态；已接或已完成则正常输出。
- 同时检查 4 个周常（血骑士 / 魔导师 / 远行者 / 径巷之影），未全部满足时提示 `符文石任务缺失X/4`（X 为已满足数）。

示例输出：

```text
[符文石检测] 位面 1234：左中 已激活
符文石任务缺失2/4
```

## 集合石最近搜索收藏

- 账号级收藏，所有角色共享；运行时合并进集合石“最近搜索”，不改集合石自身存档。
- 默认收藏：永歌森林 `1-397-1943-0`。
- 支持活动代码或名称关键字；未安装集合石时模块保持空闲。

## 任务对话自动选择

- 内置 `狩猎：择优猎杀`：自动选择 你们提供的太无趣了。我要自己挑选猎物 → 利爪卡达尼 → 盘卷蛇岛 → 梦魇。
- 优先按对话选项 ID 匹配（`134312 → 140843 → 140847 → 134313`），取不到再退回文本关键词。
- 每步输出一行提示；对话时按住 `Shift` 跳过；每条链最多自动选 10 次。

## 安装

把 `Cheeser` 目录放到：

```text
World of Warcraft/_retail_/Interface/AddOns/Cheeser
```

部署前确认 `AddOns` 目录下只有一份 `Cheeser`，避免重复加载。

## 目录

```text
Cheeser/
  Cheeser.toc
  Bindings.xml
  Config.lua
  Core.lua
  Locales.lua
  MeetingStone.lua
  Roster.lua
  Runestone.lua
  Talk.lua
  UI.lua
docs/
  api-research.md
  meetingstone-integration.md
  quest-dialogue-research.md
  testing.md
```

## 文档

- [功能说明](docs/features.md)
- [API 调研](docs/api-research.md)
- [集合石集成](docs/meetingstone-integration.md)
- [任务对话调研](docs/quest-dialogue-research.md)
- [测试步骤](docs/testing.md)
