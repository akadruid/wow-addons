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
    y = y - 54
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
