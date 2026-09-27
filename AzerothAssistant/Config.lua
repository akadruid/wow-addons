local _, ns = ...

local Config = {}
ns.Config = Config

local DEFAULTS = {
    guildInvite = true,
    runestone = true,
    autoHunt = true,
}

local function IsKnownKey(key)
    return DEFAULTS[key] ~= nil
end

local function GetModuleDb()
    local db = ns.Addon and ns.Addon.db
    if not db then
        return nil
    end

    if type(db.modules) ~= "table" then
        db.modules = {}
    end

    -- 0.9.0 之前的自动对话开关保存在 db.talk.enabled，迁移到统一模块表。
    if db.modules.autoHunt == nil
        and type(db.talk) == "table"
        and db.talk.enabled ~= nil then
        db.modules.autoHunt = db.talk.enabled and true or false
    end

    return db.modules
end

function Config:IsEnabled(key)
    if not IsKnownKey(key) then
        return false
    end

    local modules = GetModuleDb()
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
    if not IsKnownKey(key) then
        return
    end

    local modules = GetModuleDb()
    if not modules then
        return
    end

    modules[key] = enabled and true or false
    self:Apply()
end

function Config:Apply()
    if ns.Talk then
        ns.Talk.OnSettingsChanged()
    end

    if ns.UI then
        ns.UI:ApplyModuleVisibility()
    end

    if ns.Addon and ns.Addon.ScheduleRunestoneAutoCheck then
        ns.Addon:ScheduleRunestoneAutoCheck()
    end

    self:RefreshPanel()
end

local panel = CreateFrame("Frame", "AzerothAssistantOptionsPanel", UIParent)
panel.name = ns.L.SETTINGS_TITLE

local toggles = {}
local sourceDropdown

local function FormatSourceText(name, sourceType)
    if type(name) == "string" and name ~= "" then
        return string.format(ns.L.SOURCE_NAME_FORMAT, name, sourceType)
    end

    return nil
end

local function GetSourceOptions()
    local options = {
        { value = "guild", text = ns.Roster:GetGuildSourceLabel() },
    }

    for _, community in ipairs(ns.Roster:GetAvailableCommunities()) do
        options[#options + 1] = {
            value = "club:" .. community.clubId,
            text = FormatSourceText(community.name, ns.L.SOURCE_TYPE_COMMUNITY) or community.name,
        }
    end

    return options
end

local function GetCurrentSourceValue()
    local kind, clubId = ns.Roster:GetSource()
    if kind == "club" and clubId then
        return "club:" .. clubId
    end

    return "guild"
end

local function GetCurrentSourceText()
    local value = GetCurrentSourceValue()

    for _, option in ipairs(GetSourceOptions()) do
        if option.value == value then
            return option.text
        end
    end

    -- 选中的社区已经不在订阅列表里时，仍然显示一次它的名字。
    if value ~= "guild" then
        local label = ns.Roster:GetSourceLabel()
        if type(label) == "string" and label ~= "" then
            return label
        end
    end

    return ns.Roster:GetGuildSourceLabel()
end

local function ApplySourceValue(value)
    if type(value) == "string" and string.sub(value, 1, 5) == "club:" then
        ns.Roster:SetSource("club", string.sub(value, 6))
    else
        ns.Roster:SetSource("guild")
    end

    ns.Addon:RefreshAll(true)
    ns.Addon:Print(string.format(ns.L.NOTIFY_SOURCE_CHANGED, ns.Roster:GetSourceLabel()))
end

local function CreateSourceRow(y)
    local label = panel:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    label:SetPoint("TOPLEFT", panel, "TOPLEFT", 16, y)
    label:SetText(ns.L.SETTINGS_INVITE_SOURCE)

    local hint = panel:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    hint:SetPoint("TOPLEFT", label, "BOTTOMLEFT", 0, -2)
    hint:SetWidth(520)
    hint:SetJustifyH("LEFT")
    hint:SetText(ns.L.SETTINGS_INVITE_SOURCE_HINT)
    hint:SetTextColor(0.62, 0.62, 0.62)

    local dropdown = CreateFrame("Frame", "AzerothAssistantSourceDropdown", panel, "UIDropDownMenuTemplate")
    dropdown:SetPoint("LEFT", label, "RIGHT", -8, 0)
    UIDropDownMenu_SetWidth(dropdown, 220)
    UIDropDownMenu_Initialize(dropdown, function(_, level)
        for _, option in ipairs(GetSourceOptions()) do
            local info = UIDropDownMenu_CreateInfo()
            info.text = option.text
            info.value = option.value
            info.checked = (UIDropDownMenu_GetSelectedValue(dropdown) == option.value)
            info.func = function()
                ApplySourceValue(option.value)
            end
            UIDropDownMenu_AddButton(info, level)
        end
    end, "MENU")

    sourceDropdown = dropdown
end

local function CreateModuleToggle(key, label, hint, y)
    local check = CreateFrame("CheckButton", nil, panel, "UICheckButtonTemplate")
    check:SetSize(26, 26)
    check:SetPoint("TOPLEFT", panel, "TOPLEFT", 16, y)
    check.moduleKey = key

    check.Label = check:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    check.Label:SetPoint("LEFT", check, "RIGHT", 6, 0)
    check.Label:SetText(label)

    check.Hint = panel:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    check.Hint:SetPoint("TOPLEFT", check, "BOTTOMLEFT", 30, -2)
    check.Hint:SetWidth(520)
    check.Hint:SetJustifyH("LEFT")
    check.Hint:SetText(hint)
    check.Hint:SetTextColor(0.62, 0.62, 0.62)

    check:SetScript("OnClick", function(button)
        Config:SetEnabled(button.moduleKey, button:GetChecked() and true or false)
    end)

    toggles[#toggles + 1] = check
    return check
end

function Config:RefreshPanel()
    for _, check in ipairs(toggles) do
        check:SetChecked(self:IsEnabled(check.moduleKey))
    end

    if sourceDropdown then
        UIDropDownMenu_SetSelectedValue(sourceDropdown, GetCurrentSourceValue())
        UIDropDownMenu_SetText(sourceDropdown, GetCurrentSourceText())
    end
end

local function BuildPanel()
    if panel.built then
        return
    end
    panel.built = true

    local title = panel:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    title:SetPoint("TOPLEFT", 16, -16)
    title:SetText(ns.L.SETTINGS_TITLE)

    local subtitle = panel:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    subtitle:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -6)
    subtitle:SetText(ns.L.SETTINGS_SUBTITLE)
    subtitle:SetTextColor(0.7, 0.7, 0.7)

    local y = -62
    CreateModuleToggle("guildInvite", ns.L.SETTINGS_GUILD_INVITE, ns.L.SETTINGS_GUILD_INVITE_HINT, y)
    y = y - 62
    CreateSourceRow(y)
    y = y - 56
    CreateModuleToggle("runestone", ns.L.SETTINGS_RUNESTONE, ns.L.SETTINGS_RUNESTONE_HINT, y)
    y = y - 54
    CreateModuleToggle("autoHunt", ns.L.SETTINGS_AUTO_HUNT, ns.L.SETTINGS_AUTO_HUNT_HINT, y)
    y = y - 46

    local openButton = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
    openButton:SetSize(190, 24)
    openButton:SetPoint("TOPLEFT", panel, "TOPLEFT", 16, y)
    openButton:SetText(ns.L.SETTINGS_OPEN_INVITE_WINDOW)
    openButton:SetScript("OnClick", function()
        if not Config:IsEnabled("guildInvite") then
            Config:SetEnabled("guildInvite", true)
        end
        ns.UI:Toggle()
    end)
end

-- 面板内容在第一次显示时才创建，避免设置页没打开过就先渲染。
panel:SetScript("OnShow", function()
    BuildPanel()
    Config:RefreshPanel()
end)

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

    ns.Addon:Print(ns.L.SETTINGS_UNSUPPORTED)
end

if not Config:Register() then
    local waiter = CreateFrame("Frame")
    waiter:RegisterEvent("PLAYER_LOGIN")
    waiter:SetScript("OnEvent", function(frame)
        frame:UnregisterAllEvents()
        Config:Register()
    end)
end
