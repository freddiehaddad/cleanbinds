local addonName, addon = ...
local L = addon.L
local interfaceVersion = 16001
local schemaVersion = 1

addon.state = "loading"

function addon.Print(message)
    print(L.ADDON_NAME .. ": " .. message)
end

local function CheckCapabilities()
    local version, build, _, interface = GetBuildInfo()
    addon.build = { version = version, number = build, interface = interface }

    if interface ~= interfaceVersion then
        return L.UNSUPPORTED_INTERFACE:format(tostring(interface))
    end

    for _, name in ipairs({
        "GetBindingKey", "GetBindingName", "GetBindingText", "GetCurrentBindingSet",
        "SaveBindings", "LoadBindings", "SetBinding", "hooksecurefunc", "InCombatLockdown",
    }) do
        if type(_G[name]) ~= "function" then
            return L.MISSING_API:format(name)
        end
    end
    if type(C_KeyBindings) ~= "table" or type(C_KeyBindings.GetBindingContextForAction) ~= "function" then
        return L.MISSING_API:format("C_KeyBindings.GetBindingContextForAction")
    end
    if type(C_Timer) ~= "table" or type(C_Timer.After) ~= "function" then
        return L.MISSING_API:format("C_Timer.After")
    end
    for _, name in ipairs({ "Default", "Account", "Character" }) do
        if type(Enum) ~= "table" or type(Enum.BindingSet) ~= "table"
            or type(Enum.BindingSet[name]) ~= "number" then
            return L.MISSING_API:format("Enum.BindingSet." .. name)
        end
    end

    for _, name in ipairs({
        "RegisterAddOnCategory",
        "RegisterVerticalLayoutCategory",
        "RegisterCanvasLayoutSubcategory",
        "RegisterAddOnSetting",
        "CreateCheckbox",
        "OpenToCategory",
    }) do
        if type(Settings) ~= "table" or type(Settings[name]) ~= "function" then
            return L.MISSING_API:format("Settings." .. name)
        end
    end
end

local function InitializeDatabase()
    if CleanBindsDB == nil then
        CleanBindsDB = {
            schemaVersion = schemaVersion,
            enabled = true,
            overrides = {},
        }
    end

    local db = CleanBindsDB
    if type(db) ~= "table" then
        return nil, L.INVALID_DATABASE:format("expected a table")
    end
    if db.schemaVersion ~= schemaVersion then
        return nil, L.UNSUPPORTED_SCHEMA
    end
    if type(db.enabled) ~= "boolean" then
        return nil, L.INVALID_DATABASE:format("enabled must be a boolean")
    end
    if type(db.overrides) ~= "table" then
        return nil, L.INVALID_DATABASE:format("overrides must be a table")
    end

    return db
end

local function Fail(message)
    addon.state = "failed"
    addon.failure = message
    addon.Print(L.STARTUP_FAILED:format(message))
end

local function Initialize()
    local capabilityError = CheckCapabilities()
    if capabilityError then
        Fail(capabilityError)
        return
    end

    local db, databaseError = InitializeDatabase()
    if not db then
        Fail(databaseError)
        return
    end

    addon.db = db
    addon.InitializeLabels()
    addon.InitializeSettings()
    addon.state = "ready"
end

function addon.PrintStatus()
    if addon.state == "failed" then
        addon.Print(L.STARTUP_FAILED:format(addon.failure))
        return
    end
    if addon.state ~= "ready" then
        addon.Print(L.LOADING)
        return
    end

    addon.Print(L.READY:format(addon.build.version, addon.build.number, addon.build.interface))
    addon.Print(L.SESSION_NOTICE)
    addon.Print(L.RENDER_PENDING)
    for _, bar in ipairs(addon.Bars) do
        local count = addon.CountBarButtons(bar)
        local name = addon.GetBarName(bar)
        if count == 0 then
            addon.Print(L.BAR_UNAVAILABLE:format(name))
        else
            addon.Print(L.BAR_STATUS:format(name, count, bar.buttonCount))
        end
    end
end

SLASH_CLEANBINDS1 = "/cleanbinds"
SlashCmdList.CLEANBINDS = function(message)
    local command = message:match("^%s*(.-)%s*$"):lower()
    if command == "" and addon.state == "ready" then
        Settings.OpenToCategory(addon.category:GetID())
    elseif command == "" or command == "status" then
        addon.PrintStatus()
    else
        addon.Print(L.USAGE)
    end
end

local events = CreateFrame("Frame")
events:RegisterEvent("ADDON_LOADED")
events:SetScript("OnEvent", function(self, event, name)
    if event == "ADDON_LOADED" then
        if name ~= addonName then
            return
        end
        self:UnregisterEvent("ADDON_LOADED")
        if IsLoggedIn() then
            Initialize()
        else
            self:RegisterEvent("PLAYER_LOGIN")
        end
    elseif event == "PLAYER_LOGIN" then
        self:UnregisterEvent("PLAYER_LOGIN")
        Initialize()
    end
end)
