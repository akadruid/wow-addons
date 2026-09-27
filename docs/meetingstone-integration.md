# 集合石最近搜索收藏集成

## 目标

让同一账号下的所有角色都能在集合石的“最近搜索”中看到指定活动，例如火焰之地。

## 集合石原行为

- 最近搜索保存在角色级 `MEETINGSTONE_CHARACTER_DB.profiles[...].searchHistoryList`。
- 下拉菜单由 `RefreshHistoryMenuTable` 读取 `Profile:GetHistoryList()`。
- 条目使用活动代码，格式为 `类别-分组-活动-自定义`。
- 代码必须在集合石当前活动缓存中可以解析，否则不会显示。

## 集成方式

`AzerothAssistant` 在 `MeetingStone` 加载后包装：

```lua
Profile.GetHistoryList
```

集合石通过 `NetEaseEnv-1.0` 使用自定义加载环境，因此 `Profile` 不一定位于 `_G`。当前实现会从：

```lua
LibStub("NetEaseEnv-1.0")._NSList.MeetingStone.Profile
```

取得模块对象，并以 `_G.Profile` 作为回退。

包装后的行为：

1. 调用集合石原函数，取得当前角色的真实搜索历史。
2. 读取账号级 `AzerothAssistantDB.meetingStoneFavorites.entries`。
3. 把收藏代码去重后放到列表最前面。
4. 返回新列表，供集合石生成“最近搜索”菜单。

不会修改 `MEETINGSTONE_CHARACTER_DB`，也不会向集合石角色存档写入收藏。

## 默认收藏

```text
3-78-676-0 = 火焰之地（普通）
```

## 名称解析

非活动代码的条目会调用：

```lua
C_LFGList.GetAvailableActivities(nil, nil, nil, keyword)
```

再通过 `C_LFGList.GetActivityInfoTable(activityID)` 构造完整活动代码。

## 收藏当前搜索

不需要手动查找活动代码：

1. 在集合石中搜索目标副本。
2. 执行 `/aa stone addcurrent`。
3. 插件调用 `Profile:GetLastSearchCode()`，取得当前活动代码并加入收藏。

收藏窗口会通过活动 ID 显示集合石提供的真实副本名称。

## 风险与兼容

- 依赖集合石的内部方法 `Profile:GetHistoryList`，集合石大版本更新后需要重新验证。
- 不安装集合石时，模块只注册监听，不执行钩子。
- 收藏是账号级 SavedVariables，因此所有角色共享。
- 关闭功能或移除助手后，集合石原搜索历史保持不变。
