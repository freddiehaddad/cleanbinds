local passed = 0

local function equal(actual, expected)
    assert(actual == expected, ("expected %s, got %s"):format(tostring(expected), tostring(actual)))
end

local function test(name, callback)
    callback()
    passed = passed + 1
    print("PASS " .. name)
end

local function loadAddon(options)
    options = options or {}
    local messages = {}
    local frames = {}
    local environment = setmetatable({}, { __index = _G })
    environment._G = environment
    environment.CleanBindsDB = options.database
    environment.SlashCmdList = {}
    environment.Settings = {}
    environment.GetBuildInfo = function()
        return "1.60.1", "69977", "", options.interface or 16001
    end
    environment.IsLoggedIn = function()
        return options.loggedIn or false
    end
    environment.print = function(message)
        messages[#messages + 1] = message
    end

    for _, name in ipairs({
        "GetBindingKey", "GetBindingName", "GetBindingText", "hooksecurefunc",
        "InCombatLockdown", "SetBinding", "SaveBindings",
    }) do
        environment[name] = function()
            error("The foundation must not call " .. name)
        end
    end

    for _, name in ipairs({
        "RegisterAddOnCategory", "RegisterVerticalLayoutCategory",
        "RegisterCanvasLayoutSubcategory", "RegisterAddOnSetting",
        "CreateCheckbox", "OpenToCategory",
    }) do
        environment.Settings[name] = function()
            error("The foundation must not call Settings." .. name)
        end
    end
    if options.missingSetting then
        environment.Settings[options.missingSetting] = nil
    end

    environment.CreateFrame = function()
        local frame = { registered = {} }
        function frame:RegisterEvent(event)
            self.registered[event] = true
        end
        function frame:UnregisterEvent(event)
            self.registered[event] = nil
        end
        function frame:SetScript(script, callback)
            self[script] = callback
        end
        frames[#frames + 1] = frame
        return frame
    end

    local addon = {}
    for _, path in ipairs({ "Locale.lua", "Bars.lua", "Core.lua" }) do
        local chunk
        if setfenv then
            chunk = assert(loadfile(path))
            setfenv(chunk, environment)
        else
            chunk = assert(loadfile(path, "t", environment))
        end
        chunk("CleanBinds", addon)
    end

    local function fire(event, ...)
        for _, frame in ipairs(frames) do
            if frame.registered[event] then
                frame.OnEvent(frame, event, ...)
            end
        end
    end

    return environment, addon, fire, messages
end

test("initializes fresh account data after login", function()
    local env, addon, fire, messages = loadAddon()
    fire("ADDON_LOADED", "AnotherAddon")
    equal(env.CleanBindsDB, nil)
    fire("ADDON_LOADED", "CleanBinds")
    equal(addon.state, "loading")
    equal(env.CleanBindsDB, nil)
    fire("PLAYER_LOGIN")
    equal(addon.state, "ready")
    equal(addon.db, env.CleanBindsDB)
    equal(addon.db.schemaVersion, 1)
    equal(addon.db.enabled, true)
    equal(next(addon.db.overrides), nil)
    equal(#messages, 0)
end)

test("supports loading after login", function()
    local _, addon, fire = loadAddon({ loggedIn = true })
    fire("ADDON_LOADED", "CleanBinds")
    equal(addon.state, "ready")
end)

test("preserves existing account data", function()
    local existing = {
        schemaVersion = 1,
        enabled = false,
        overrides = { ["actionbar2:1"] = "MWD" },
        retainedField = "keep",
    }
    local env, addon, fire = loadAddon({ database = existing, loggedIn = true })
    fire("ADDON_LOADED", "CleanBinds")
    equal(env.CleanBindsDB, existing)
    equal(addon.db, existing)
    equal(addon.db.enabled, false)
    equal(addon.db.overrides["actionbar2:1"], "MWD")
    equal(addon.db.retainedField, "keep")
end)

test("rejects malformed or unknown data without replacing it", function()
    for _, existing in ipairs({
        false,
        "invalid",
        {},
        { schemaVersion = 2, enabled = true, overrides = {} },
        { schemaVersion = 1, enabled = "true", overrides = {} },
        { schemaVersion = 1, enabled = true, overrides = false },
    }) do
        local env, addon, fire, messages = loadAddon({ database = existing, loggedIn = true })
        fire("ADDON_LOADED", "CleanBinds")
        equal(addon.state, "failed")
        equal(addon.db, nil)
        equal(env.CleanBindsDB, existing)
        equal(#messages, 1)
        assert(messages[1]:find("Existing data was kept.", 1, true))
    end
end)

test("rejects another client without writing saved data", function()
    local env, addon, fire, messages = loadAddon({ interface = 99999, loggedIn = true })
    fire("ADDON_LOADED", "CleanBinds")
    equal(addon.state, "failed")
    equal(env.CleanBindsDB, nil)
    assert(messages[1]:find("99999", 1, true))
end)

test("reports missing native settings capabilities", function()
    local env, addon, fire, messages = loadAddon({
        missingSetting = "RegisterCanvasLayoutSubcategory",
        loggedIn = true,
    })
    fire("ADDON_LOADED", "CleanBinds")
    equal(addon.state, "failed")
    equal(env.CleanBindsDB, nil)
    assert(messages[1]:find("Settings.RegisterCanvasLayoutSubcategory", 1, true))
end)

test("maps native bars without mixing up right-side bars", function()
    local env, addon = loadAddon()
    equal(#addon.Bars, 12)
    equal(addon.Bars[4].frameName, "MultiBarRight")
    equal(addon.Bars[4].bindingPrefix, "MULTIACTIONBAR3BUTTON")
    equal(addon.Bars[5].frameName, "MultiBarLeft")
    equal(addon.Bars[5].bindingPrefix, "MULTIACTIONBAR4BUTTON")

    local first = {}
    env.MainActionBar = { actionButtons = { first, {} } }
    equal(addon.GetBarButton(addon.Bars[1], 1), first)
    equal(addon.CountBarButtons(addon.Bars[1]), 2)
    equal(addon.CountBarButtons(addon.Bars[2]), 0)

    env.BINDING_HEADER_ACTIONBAR = "Localized action bar"
    equal(addon.GetBarName(addon.Bars[1]), "Localized action bar")
    equal(addon.GetBarName(addon.Bars[2]), "Action Bar 2")

    env.OverrideActionBar = {}
    env.OverrideActionBarButton1 = first
    equal(addon.GetBarButton(addon.Bars[12], 1), first)
    equal(addon.CountBarButtons(addon.Bars[12]), 1)
end)

test("reports startup status and invalid slash commands", function()
    local env, addon, fire, messages = loadAddon({ loggedIn = true })
    env.SlashCmdList.CLEANBINDS("")
    assert(messages[1]:find("Waiting for the game", 1, true))
    fire("ADDON_LOADED", "CleanBinds")
    env.SlashCmdList.CLEANBINDS(" STATUS ")
    assert(messages[2]:find("Interface 16001", 1, true))
    assert(messages[3]:find("not implemented yet", 1, true))
    equal(addon.state, "ready")
    env.SlashCmdList.CLEANBINDS("invalid")
    assert(messages[#messages]:find("Usage:", 1, true))
end)

print(("%d tests passed"):format(passed))
