local addonName, ns = ...

local Config = {}
ns.Config = Config

-- 账号级设置：SavedVariables 用 RollWorthyDB，所有角色共用一份。
-- 每个场景一个过滤开关：过滤关闭 = 该场景完全不拦截。
local DEFAULTS = {
    enabled = false,
    mythicPlusFilter = true,
    raidFilter = true,
    worldFilter = true,
    delveFilter = true,
}

local NUMBER_DEFAULTS = {
    mythicPlusLevel = 10,
    raidMinDifficulty = 15, -- 14 普通 / 15 英雄 / 17 随机（不提供史诗：史诗永不过滤）
    delveLevel = 0,         -- 0 = 全不Roll
}

local RAID_OPTIONS = {
    { value = 17, labelKey = "SETTINGS_RAID_LFR" },
    { value = 14, labelKey = "SETTINGS_RAID_NORMAL" },
    { value = 15, labelKey = "SETTINGS_RAID_HEROIC" },
}

local function RangeOptions(from, to)
    local options = {}
    for value = from, to do
        options[#options + 1] = { value = value }
    end
    return options
end

-- 大秘境列表最上面多一个「史诗及以下」：连同普通 / 英雄 / 史诗(M0) 五人本一起跳过。
-- 追随者地下城、时光漫游不在这里，它们只归“世界”组。
local MYTHIC_OPTIONS = { { value = 1, labelKey = "SETTINGS_MYTHIC_LOW" } }
for _, option in ipairs(RangeOptions(2, 15)) do
    MYTHIC_OPTIONS[#MYTHIC_OPTIONS + 1] = option
end

local DELVE_OPTIONS = { { value = 0, labelKey = "SETTINGS_NEVER_ROLL" } }
for _, option in ipairs(RangeOptions(1, 11)) do
    DELVE_OPTIONS[#DELVE_OPTIONS + 1] = option
end

-- 早期版本用过的旧键，加载时清掉，避免和新设置混淆。
local LEGACY_KEYS = {
    "notify",
    "minKeyLevel",
    "mythicPlus",
    "delve",
    "raidHeroic",
    "raidMythic",
    "raidNormal",
    "raidLFR",
    "huntNormal",
    "huntHard",
    "huntNightmare",
    "huntMinDifficulty",
    "huntFilter",
}

local function IsKnownToggle(key)
    return DEFAULTS[key] ~= nil
end

local function IsKnownNumber(key)
    return NUMBER_DEFAULTS[key] ~= nil
end

local function GetModules()
    local db = RollWorthyDB
    if type(db) ~= "table" then
        return nil
    end

    if type(db.modules) ~= "table" then
        db.modules = {}
    end

    return db.modules
end

function Config:IsEnabled(key)
    if not IsKnownToggle(key) then
        return false
    end

    local modules = GetModules()
    if not modules then
        return DEFAULTS[key] ~= false
    end

    local value = modules[key]
    if value == nil then
        return DEFAULTS[key] ~= false
    end

    return value and true or false
end

function Config:SetEnabled(key, enabled)
    if not IsKnownToggle(key) then
        return
    end

    local modules = GetModules()
    if not modules then
        return
    end

    modules[key] = enabled and true or false
    self:RefreshPanel()
end

function Config:GetNumber(key)
    if not IsKnownNumber(key) then
        return 0
    end

    local modules = GetModules()
    if not modules then
        return NUMBER_DEFAULTS[key]
    end

    local value = tonumber(modules[key])
    if value == nil then
        return NUMBER_DEFAULTS[key]
    end

    return value
end

function Config:SetNumber(key, value)
    if not IsKnownNumber(key) then
        return
    end

    local modules = GetModules()
    if not modules then
        return
    end

    modules[key] = tonumber(value) or NUMBER_DEFAULTS[key]
    self:RefreshPanel()
end

local panel = CreateFrame("Frame", "RollWorthyOptionsPanel", UIParent)
panel.name = ns.L.SETTINGS_TITLE

local scroll = CreateFrame("ScrollFrame", nil, panel)
scroll:SetPoint("TOPLEFT")
scroll:SetPoint("BOTTOMRIGHT", -14, 0)
scroll:EnableMouseWheel(true)

local page = CreateFrame("Frame", nil, scroll)
page:SetSize(620, 620)
scroll:SetScrollChild(page)

local barTrack = panel:CreateTexture(nil, "ARTWORK")
barTrack:SetPoint("TOPRIGHT", -6, -8)
barTrack:SetPoint("BOTTOMRIGHT", -6, 8)
barTrack:SetWidth(4)
barTrack:SetColorTexture(1, 1, 1, 0.08)

local barThumb = panel:CreateTexture(nil, "OVERLAY")
barThumb:SetWidth(4)
barThumb:SetColorTexture(1, 0.82, 0, 0.5)

local function paintScrollBar()
    local range = scroll:GetVerticalScrollRange()
    local view = scroll:GetHeight()

    if range < 1 or view < 1 then
        barTrack:Hide()
        barThumb:Hide()
        return
    end

    barTrack:Show()
    barThumb:Show()

    local barH = barTrack:GetHeight()
    local thumb = math.max(24, barH * view / (view + range))
    barThumb:ClearAllPoints()
    barThumb:SetHeight(thumb)
    barThumb:SetPoint("TOP", barTrack, "TOP", 0, -(barH - thumb) * scroll:GetVerticalScroll() / range)
end

scroll:SetScript("OnMouseWheel", function(self, delta)
    local range = self:GetVerticalScrollRange()
    local value = self:GetVerticalScroll() - delta * 40
    self:SetVerticalScroll(math.min(math.max(value, 0), range))
    paintScrollBar()
end)

scroll:SetScript("OnSizeChanged", function(self)
    page:SetWidth(self:GetWidth())
    paintScrollBar()
end)

local toggles = {}
local dropdowns = {}
-- 每个场景过滤开关管着自己那一组细分控件：过滤关掉时细分控件置灰。
local groupMembers = {}

local function LinkControl(filterKey, control, kind)
    local entry = groupMembers[filterKey]
    if not entry then
        entry = { checks = {}, dropdowns = {} }
        groupMembers[filterKey] = entry
    end

    if kind == "dropdown" then
        entry.dropdowns[#entry.dropdowns + 1] = control
    else
        entry.checks[#entry.checks + 1] = control
    end
end

local function OptionText(option)
    if option.labelKey then
        return ns.L[option.labelKey]
    end
    return string.format(ns.L.SETTINGS_LEVEL_OPTION, option.value)
end

local function CreateFilterCheck(key, label, hint, y)
    local check = CreateFrame("CheckButton", nil, page, "UICheckButtonTemplate")
    check:SetSize(26, 26)
    check:SetPoint("TOPLEFT", page, "TOPLEFT", 16, y)
    check.moduleKey = key

    check.Label = check:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    check.Label:SetPoint("LEFT", check, "RIGHT", 6, 0)
    check.Label:SetText(label)

    check:SetScript("OnClick", function(button)
        Config:SetEnabled(button.moduleKey, button:GetChecked() and true or false)
    end)

    if hint then
        check.Hint = page:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        check.Hint:SetPoint("TOPLEFT", check, "BOTTOMLEFT", 30, -2)
        check.Hint:SetWidth(500)
        check.Hint:SetJustifyH("LEFT")
        check.Hint:SetText(hint)
        check.Hint:SetTextColor(0.62, 0.62, 0.62)
    end

    toggles[#toggles + 1] = check
    return check
end

-- 下拉：选项值可以是难度 ID，也可以是层数。
local function CreateChoiceDropdown(key, labelText, options, x, y)
    local label = page:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    label:SetPoint("TOPLEFT", page, "TOPLEFT", x, y)
    label:SetText(labelText)
    label:SetTextColor(0.75, 0.75, 0.75)

    local dropdown = CreateFrame("Frame", nil, page, "UIDropDownMenuTemplate")
    dropdown:SetPoint("LEFT", label, "RIGHT", -8, 0)
    dropdown.fieldLabel = labelText
    dropdown.options = options
    UIDropDownMenu_SetWidth(dropdown, 120)
    UIDropDownMenu_Initialize(dropdown, function(_, menuLevel)
        for _, option in ipairs(options) do
            local info = UIDropDownMenu_CreateInfo()
            info.text = OptionText(option)
            info.value = option.value
            info.checked = (UIDropDownMenu_GetSelectedValue(dropdown) == option.value)
            info.func = function()
                Config:SetNumber(key, option.value)
                print(string.format(ns.L.SETTINGS_LEVEL_CHANGED, dropdown.fieldLabel, OptionText(option)))
            end
            UIDropDownMenu_AddButton(info, menuLevel)
        end
    end, "MENU")

    dropdowns[#dropdowns + 1] = { key = key, dropdown = dropdown }
    return dropdown
end

local function CreateSectionLabel(text, y)
    local label = page:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    label:SetPoint("TOPLEFT", page, "TOPLEFT", 16, y)
    label:SetText(text)
    label:SetTextColor(0.9, 0.82, 0.35)
    return label
end

local function CreateSeparator(y)
    local line = page:CreateTexture(nil, "OVERLAY")
    line:SetPoint("TOPLEFT", page, "TOPLEFT", 16, y)
    line:SetSize(540, 1)
    line:SetColorTexture(0.45, 0.45, 0.45, 0.55)
end

local function CreateHint(text, y, width)
    local hint = page:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    hint:SetPoint("TOPLEFT", page, "TOPLEFT", 16, y)
    hint:SetWidth(width or 520)
    hint:SetJustifyH("LEFT")
    hint:SetText(text)
    hint:SetTextColor(0.7, 0.7, 0.7)
    return hint
end

local function BuildPanel()
    if panel.built then
        return
    end
    panel.built = true

    local title = page:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    title:SetPoint("TOPLEFT", 16, -16)
    title:SetText(ns.L.SETTINGS_TITLE)

    local subtitle = page:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    subtitle:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -6)
    subtitle:SetWidth(540)
    subtitle:SetJustifyH("LEFT")
    subtitle:SetText(ns.L.SETTINGS_SUBTITLE)
    subtitle:SetTextColor(0.7, 0.7, 0.7)

    CreateFilterCheck("enabled", ns.L.SETTINGS_ENABLED, ns.L.SETTINGS_ENABLED_HINT, -76)

    local groupLabel = page:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    groupLabel:SetPoint("TOPLEFT", page, "TOPLEFT", 16, -140)
    groupLabel:SetWidth(540)
    groupLabel:SetJustifyH("LEFT")
    groupLabel:SetText(ns.L.SETTINGS_GROUP_ALLOW)
    groupLabel:SetTextColor(1, 0.82, 0.1)

    CreateHint(ns.L.SETTINGS_GROUP_ALLOW_HINT, -160, 540)
    CreateSeparator(-188)

    -- 大秘境
    CreateSectionLabel(ns.L.SETTINGS_SECTION_MYTHIC, -204)
    CreateFilterCheck("mythicPlusFilter", ns.L.SETTINGS_MYTHIC_FILTER, ns.L.SETTINGS_MYTHIC_HINT, -232)
    LinkControl("mythicPlusFilter", CreateChoiceDropdown("mythicPlusLevel", ns.L.SETTINGS_MYTHIC_MIN, MYTHIC_OPTIONS, 250, -227), "dropdown")

    -- 团本
    CreateSectionLabel(ns.L.SETTINGS_SECTION_RAID, -292)
    CreateFilterCheck("raidFilter", ns.L.SETTINGS_RAID_FILTER, ns.L.SETTINGS_RAID_HINT, -320)
    LinkControl("raidFilter", CreateChoiceDropdown("raidMinDifficulty", ns.L.SETTINGS_MIN_DIFFICULTY, RAID_OPTIONS, 250, -315), "dropdown")

    -- 世界（狩猎 / 世界首领 / Lair 等）
    CreateSectionLabel(ns.L.SETTINGS_SECTION_WORLD, -382)
    CreateFilterCheck("worldFilter", ns.L.SETTINGS_WORLD_FILTER, ns.L.SETTINGS_WORLD_HINT, -410)

    -- 地下堡
    CreateSectionLabel(ns.L.SETTINGS_SECTION_DELVE, -472)
    CreateFilterCheck("delveFilter", ns.L.SETTINGS_DELVE_FILTER, ns.L.SETTINGS_DELVE_HINT, -500)
    LinkControl("delveFilter", CreateChoiceDropdown("delveLevel", ns.L.SETTINGS_MIN_LEVEL, DELVE_OPTIONS, 250, -495), "dropdown")

    -- 其它场景
    CreateSectionLabel(ns.L.SETTINGS_SECTION_OTHER, -562)
    CreateHint(ns.L.SETTINGS_OTHER_HINT, -584)

    CreateSeparator(-640)

    local commandsTitle = page:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    commandsTitle:SetPoint("TOPLEFT", page, "TOPLEFT", 16, -658)
    commandsTitle:SetText(ns.L.SETTINGS_COMMANDS_TITLE)
    commandsTitle:SetTextColor(0.9, 0.82, 0.35)

    local commandsText = page:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    commandsText:SetPoint("TOPLEFT", page, "TOPLEFT", 16, -680)
    commandsText:SetJustifyH("LEFT")
    commandsText:SetJustifyV("TOP")
    commandsText:SetWidth(540)
    commandsText:SetSpacing(4)
    commandsText:SetText(ns.L.SETTINGS_COMMANDS_TEXT)
    commandsText:SetTextColor(0.75, 0.75, 0.75)

    page:SetHeight(780)
end

panel:SetScript("OnShow", function()
    BuildPanel()
    Config:RefreshPanel()
end)

function Config:RefreshPanel()
    for _, check in ipairs(toggles) do
        check:SetChecked(self:IsEnabled(check.moduleKey))
    end

    for _, entry in ipairs(dropdowns) do
        local value = self:GetNumber(entry.key)
        local text
        for _, option in ipairs(entry.dropdown.options) do
            if option.value == value then
                text = OptionText(option)
                break
            end
        end
        UIDropDownMenu_SetSelectedValue(entry.dropdown, value)
        UIDropDownMenu_SetText(entry.dropdown, text or tostring(value))
    end

    -- 过滤关掉时，把该组的细分控件置灰。
    for filterKey, entry in pairs(groupMembers) do
        local active = self:IsEnabled(filterKey)

        for _, check in ipairs(entry.checks) do
            if active then
                check:Enable()
            else
                check:Disable()
            end
        end

        for _, dropdown in ipairs(entry.dropdowns) do
            if active then
                UIDropDownMenu_EnableDropDown(dropdown)
            else
                UIDropDownMenu_DisableDropDown(dropdown)
            end
        end
    end

    paintScrollBar()
end

function Config:Register()
    if self.registered then
        return true
    end

    if type(Settings) ~= "table"
        or type(Settings.RegisterCanvasLayoutCategory) ~= "function"
        or type(Settings.RegisterAddOnCategory) ~= "function" then
        return false
    end

    local category = Settings.RegisterCanvasLayoutCategory(panel, ns.L.SETTINGS_TITLE)
    if category then
        Settings.RegisterAddOnCategory(category)
        if category.GetID then
            self.categoryID = category:GetID()
        end
    end

    self.registered = true
    self:RefreshPanel()
    return true
end

function Config:Open()
    if type(Settings) == "table" and type(Settings.OpenToCategory) == "function" then
        if self.categoryID then
            Settings.OpenToCategory(self.categoryID)
        else
            Settings.OpenToCategory(ns.L.SETTINGS_TITLE)
        end
        return
    end

    print(ns.L.SETTINGS_UNSUPPORTED)
end

local loader = CreateFrame("Frame")
loader:RegisterEvent("ADDON_LOADED")
loader:SetScript("OnEvent", function(frame, _, loadedName)
    if loadedName ~= addonName then
        return
    end

    frame:UnregisterAllEvents()

    RollWorthyDB = RollWorthyDB or {}
    if type(RollWorthyDB.modules) ~= "table" then
        RollWorthyDB.modules = {}
    end

    -- “狩猎”组改名为“世界”组：把旧开关的值带过来，再按 LEGACY_KEYS 清掉旧键。
    if RollWorthyDB.modules.huntFilter ~= nil and RollWorthyDB.modules.worldFilter == nil then
        RollWorthyDB.modules.worldFilter = RollWorthyDB.modules.huntFilter and true or false
    end

    for _, key in ipairs(LEGACY_KEYS) do
        RollWorthyDB.modules[key] = nil
    end

    if not Config:Register() then
        -- 客户端还没准备好设置面板接口时，登录后再试一次。
        local waiter = CreateFrame("Frame")
        waiter:RegisterEvent("PLAYER_LOGIN")
        waiter:SetScript("OnEvent", function(waiterFrame)
            waiterFrame:UnregisterAllEvents()
            Config:Register()
        end)
    end
end)
