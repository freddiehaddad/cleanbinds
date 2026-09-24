local passed = 0
local unpackValues = unpack or table.unpack

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
    local hooks = {}
    local timers = {}
    local game = {
        bindings = options.bindings or {},
        bindingSet = 1,
        combat = false,
    }
    local environment = setmetatable({}, { __index = _G })
    environment._G = environment
    environment.CleanBindsDB = options.database
    environment.SlashCmdList = {}
    environment.Settings = {}
    environment.Enum = { BindingSet = { Default = 0, Account = 1, Character = 2 } }
    environment.C_KeyBindings = { GetBindingContextForAction = function() end }
    environment.C_Timer = {
        After = function(_, callback)
            timers[#timers + 1] = callback
        end,
    }
    environment.GetBuildInfo = function()
        return "1.60.1", "69977", "", options.interface or 16001
    end
    environment.IsLoggedIn = function()
        return options.loggedIn or false
    end
    environment.print = function(message)
        messages[#messages + 1] = message
    end

    environment.GetBindingKey = function(command)
        return unpackValues(game.bindings[command] or {})
    end
    environment.GetBindingName = function(command)
        return command
    end
    environment.GetBindingText = function(key)
        return key or ""
    end
    environment.GetCurrentBindingSet = function()
        return game.bindingSet
    end
    environment.InCombatLockdown = function()
        return game.combat
    end
    environment.hooksecurefunc = function(name, callback)
        assert(type(environment[name]) == "function", name)
        hooks[name] = hooks[name] or {}
        hooks[name][#hooks[name] + 1] = callback
    end

    for _, name in ipairs({
        "SetBinding", "SetBindingClick", "SetBindingSpell", "SetBindingItem", "SetBindingMacro",
        "SaveBindings", "LoadBindings",
    }) do
        environment[name] = function()
            error("The addon must not call " .. name)
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
    addon.InitializeSettings = function()
        addon.category = { GetID = function() return 42 end }
    end
    for _, path in ipairs({ "Locale.lua", "Bars.lua", "Labels.lua", "Core.lua" }) do
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

    local function callHooks(name, ...)
        for _, callback in ipairs(hooks[name] or {}) do
            callback(...)
        end
    end

    function game.SetKeys(command, keys, setter)
        setter = setter or "SetBinding"
        local old = game.bindings[command] or {}
        game.bindings[command] = {}
        fire("UPDATE_BINDINGS")
        for _, key in ipairs(old) do
            callHooks(setter, key, nil)
        end
        for _, key in ipairs(keys) do
            for otherCommand, otherKeys in pairs(game.bindings) do
                if otherCommand ~= command then
                    for index = #otherKeys, 1, -1 do
                        if otherKeys[index] == key then
                            table.remove(otherKeys, index)
                        end
                    end
                end
            end
            table.insert(game.bindings[command], key)
            fire("UPDATE_BINDINGS")
            callHooks(setter, key, command)
        end
    end

    function game.Save(selectedSet)
        game.bindingSet = selectedSet or game.bindingSet
        fire("UPDATE_BINDINGS")
        callHooks("SaveBindings", game.bindingSet)
    end

    function game.Load(selectedSet, bindings)
        game.bindings = bindings
        fire("BINDINGS_LOADED")
        callHooks("LoadBindings", selectedSet)
    end

    function game.Flush()
        local pending = timers
        timers = {}
        for _, callback in ipairs(pending) do
            callback()
        end
        equal(#timers, 0)
    end

    return environment, addon, fire, messages, game
end

test("settings module compiles", function()
    assert(loadfile("Settings.lua"))
end)

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
    equal(#addon.Bars, 10)
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
    local mirror = addon.Bars[1].mirrors[1]
    equal(mirror.buttonCount, 6)
    equal(addon.GetBarButton(mirror, 1), first)
    equal(addon.CountBarButtons(mirror), 1)
    for _, bar in ipairs(addon.Bars) do
        assert(bar.id ~= "override")
        assert(bar.id ~= "possess")
    end
end)

test("reports startup status and invalid slash commands", function()
    local env, addon, fire, messages = loadAddon({ loggedIn = true })
    env.SlashCmdList.CLEANBINDS("")
    assert(messages[1]:find("Waiting for the game", 1, true))
    fire("ADDON_LOADED", "CleanBinds")
    env.SlashCmdList.CLEANBINDS(" STATUS ")
    assert(messages[2]:find("Interface 16001", 1, true))
    assert(messages[3]:find("Session-only on this beta", 1, true))
    assert(messages[4]:find("not implemented yet", 1, true))
    equal(addon.state, "ready")
    env.SlashCmdList.CLEANBINDS("invalid")
    assert(messages[#messages]:find("Usage:", 1, true))
end)

test("checks native label support while allowing inactive bars", function()
    local env, addon = loadAddon()
    equal(addon.GetLabelUnavailableReason(addon.Bars[1], 1), nil)
    equal(addon.GetLabelUnavailableReason(addon.Bars[9], 1), nil)

    env.MainActionBar = { actionButtons = { {} } }
    equal(addon.GetLabelUnavailableReason(addon.Bars[1], 1), addon.L.NO_NATIVE_LABEL)
    env.MainActionBar.actionButtons[1].HotKey = {}
    equal(addon.GetLabelUnavailableReason(addon.Bars[1], 1), nil)
end)

test("supports Special Action Buttons without a standard refresh method", function()
    local env, addon = loadAddon()
    local stance = addon.Bars[10]
    equal(stance.id, "stance")
    equal(stance.bindingPrefix .. 1, "SHAPESHIFTBUTTON1")
    equal(stance.bindingPrefix .. 10, "SHAPESHIFTBUTTON10")
    env.StanceBar = { actionButtons = { { HotKey = {} } } }
    equal(env.StanceBar.actionButtons[1].UpdateHotkeys, nil)
    equal(env.StanceBar.actionButtons[1].SetHotkeys, nil)
    equal(addon.GetLabelUnavailableReason(stance, 1), nil)
    equal(addon.GetBarName(stance), "Stance Bar")
end)

test("opens the registered settings category from the slash command", function()
    local env, _, fire = loadAddon({ loggedIn = true })
    local opened
    env.Settings.OpenToCategory = function(categoryID)
        opened = categoryID
    end
    fire("ADDON_LOADED", "CleanBinds")
    env.SlashCmdList.CLEANBINDS("")
    equal(opened, 42)
end)

local function ready(options)
    options = options or {}
    options.loggedIn = true
    local env, addon, fire, messages, game = loadAddon(options)
    fire("ADDON_LOADED", "CleanBinds")
    equal(addon.state, "ready")
    return env, addon, fire, messages, game
end

test("normalizes Unicode labels without truncation", function()
    local _, addon = ready()
    local label = "\231\159\173\226\134\147"
    equal(addon.NormalizeLabel("  " .. label .. "\194\160"), label)
    equal(addon.NormalizeLabel("\227\128\128\194\160  "), "")
    equal(addon.NormalizeLabel(string.rep("W", 256)), string.rep("W", 256))
    equal(addon.LiteralLabel("|cffff0000red|r"), "||cffff0000red||r")
end)

test("rejects controls and malformed Unicode", function()
    local _, addon = ready()
    for _, text in ipairs({
        "\nMWD", "MWD\t", "\0", "\127", "\194\133", "\226\128\168", "\226\128\169",
        "\128", "\192\128", "\224\128\128", "\237\160\128", "\244\144\128\128",
        "\245\128\128\128", "\240\159", "\226A\128",
    }) do
        local normalized, reason = addon.NormalizeLabel(text)
        equal(normalized, nil)
        assert(type(reason) == "string")
    end
end)

test("restores independent labels when the client supplies saved data", function()
    local env, addon = ready({ bindings = { ACTIONBUTTON1 = { "MOUSEWHEELDOWN" } } })
    assert(addon.SetLabel(addon.Bars[1], 1, " MWD "))
    assert(addon.SetLabel(addon.Bars[2], 1, "Different"))
    equal(addon.GetLabel(addon.Bars[1], 1), "MWD")
    equal(addon.GetLabel(addon.Bars[2], 1), "Different")
    local _, other, _, messages = ready({
        database = env.CleanBindsDB,
        bindings = { ACTIONBUTTON1 = { "F" } },
    })
    equal(other.GetLabel(other.Bars[1], 1), "MWD")
    equal(other.GetLabel(other.Bars[2], 1), "Different")
    equal(#messages, 0)
end)

test("clears blank labels and scopes resets to the requested bar", function()
    local env, addon = ready()
    assert(addon.SetLabel(addon.Bars[1], 1, "One"))
    assert(addon.SetLabel(addon.Bars[1], 2, "Two"))
    assert(addon.SetLabel(addon.Bars[2], 1, "Other"))
    assert(addon.SetLabel(addon.Bars[1], 1, "\194\160  "))
    equal(env.CleanBindsDB.overrides["actionbar1:1"], nil)
    assert(addon.ResetLabels("actionbar1"))
    equal(addon.GetLabel(addon.Bars[1], 2), nil)
    equal(addon.GetLabel(addon.Bars[2], 1), "Other")
    assert(addon.ResetLabels())
    equal(next(env.CleanBindsDB.overrides), nil)
    equal(env.CleanBindsDB.enabled, true)
end)

test("preserves invalid saved entries until explicitly reset", function()
    local db = {
        schemaVersion = 1, enabled = true,
        overrides = { ["actionbar1:1"] = false, ["actionbar1:2"] = "OK", ["unknown:1"] = "Keep" },
    }
    local _, addon, _, messages = ready({ database = db })
    equal(addon.GetLabel(addon.Bars[1], 1), nil)
    equal(addon.GetLabel(addon.Bars[1], 2), "OK")
    equal(db.overrides["actionbar1:1"], false)
    equal(db.overrides["unknown:1"], "Keep")
    equal(#messages, 1)
    assert(messages[1]:find("2 invalid", 1, true))
    assert(addon.ResetLabels("actionbar1"))
    equal(db.overrides["unknown:1"], "Keep")
    assert(addon.ResetLabels())
    equal(next(db.overrides), nil)
end)

test("clears a changed primary only after bindings are saved", function()
    local env, addon, _, messages, game = ready({ bindings = { ACTIONBUTTON1 = { "MOUSEWHEELDOWN" } } })
    assert(addon.SetLabel(addon.Bars[1], 1, "MWD"))
    game.SetKeys("ACTIONBUTTON1", { "F" })
    equal(addon.GetLabel(addon.Bars[1], 1), "MWD")
    game.Save()
    equal(addon.GetLabel(addon.Bars[1], 1), nil)
    equal(env.CleanBindsDB.overrides["actionbar1:1"], nil)
    assert(messages[1]:find("cleared its custom label", 1, true))
    game.Save()
    equal(#messages, 1)
end)

test("keeps a label when only the secondary binding changes", function()
    local _, addon, _, _, game = ready({ bindings = { ACTIONBUTTON1 = { "F", "G" } } })
    assert(addon.SetLabel(addon.Bars[1], 1, "Primary"))
    game.SetKeys("ACTIONBUTTON1", { "F", "H" })
    game.Save()
    equal(addon.GetLabel(addon.Bars[1], 1), "Primary")
end)

test("clears on a primary-secondary swap with the same key set", function()
    local _, addon, _, _, game = ready({ bindings = { ACTIONBUTTON1 = { "F", "G" } } })
    assert(addon.SetLabel(addon.Bars[1], 1, "Primary"))
    game.SetKeys("ACTIONBUTTON1", { "G", "F" })
    game.Save()
    equal(addon.GetLabel(addon.Bars[1], 1), nil)
end)

test("does not clear for an input-device preference change", function()
    local _, addon, fire, _, game = ready({ bindings = { ACTIONBUTTON1 = { "F", "PAD1" } } })
    assert(addon.SetLabel(addon.Bars[1], 1, "Action"))
    game.bindings.ACTIONBUTTON1 = { "PAD1", "F" }
    fire("GAME_PAD_ACTIVE_CHANGED")
    game.Save()
    equal(addon.GetLabel(addon.Bars[1], 1), "Action")
end)

test("unrelated edits do not turn preference changes into rebinds", function()
    local _, addon, _, _, game = ready({ bindings = { ACTIONBUTTON1 = { "F", "PAD1" } } })
    assert(addon.SetLabel(addon.Bars[1], 1, "Action"))
    game.bindings.ACTIONBUTTON1 = { "PAD1", "F" }
    game.SetKeys("ACTIONBUTTON2", { "G" })
    game.Save()
    equal(addon.GetLabel(addon.Bars[1], 1), "Action")
end)

test("canceled binding edits do not erase shared labels", function()
    local _, addon, _, _, game = ready({ bindings = { ACTIONBUTTON1 = { "F" } } })
    assert(addon.SetLabel(addon.Bars[1], 1, "Original"))
    game.SetKeys("ACTIONBUTTON1", { "G" })
    game.Load(1, { ACTIONBUTTON1 = { "F" } })
    game.Save()
    game.Flush()
    equal(addon.GetLabel(addon.Bars[1], 1), "Original")
end)

test("loading and saving another binding set establishes a baseline", function()
    local _, addon, _, _, game = ready({ bindings = { ACTIONBUTTON1 = { "F" } } })
    assert(addon.SetLabel(addon.Bars[1], 1, "Shared"))
    game.Load(2, { ACTIONBUTTON1 = { "G" } })
    game.Save(2)
    game.Flush()
    equal(addon.GetLabel(addon.Bars[1], 1), "Shared")
    game.SetKeys("ACTIONBUTTON1", { "H" })
    game.Save()
    equal(addon.GetLabel(addon.Bars[1], 1), nil)
end)

test("first binding activates a dormant label but later rebind clears it", function()
    local _, addon, _, _, game = ready()
    assert(addon.SetLabel(addon.Bars[1], 1, "Prepared"))
    game.SetKeys("ACTIONBUTTON1", { "F" })
    game.Save()
    equal(addon.GetLabel(addon.Bars[1], 1), "Prepared")
    game.SetKeys("ACTIONBUTTON1", { "G" })
    game.Save()
    equal(addon.GetLabel(addon.Bars[1], 1), nil)
end)

test("unbinding an assigned button clears its label on save", function()
    local _, addon, _, _, game = ready({ bindings = { ACTIONBUTTON1 = { "F" } } })
    assert(addon.SetLabel(addon.Bars[1], 1, "Assigned"))
    game.SetKeys("ACTIONBUTTON1", {})
    game.Save()
    equal(addon.GetLabel(addon.Bars[1], 1), nil)
end)

test("default bindings clear changed labels only when committed", function()
    local _, addon, _, _, game = ready({ bindings = { ACTIONBUTTON1 = { "F" } } })
    assert(addon.SetLabel(addon.Bars[1], 1, "Assigned"))
    game.Load(0, { ACTIONBUTTON1 = { "1" } })
    game.Flush()
    equal(addon.GetLabel(addon.Bars[1], 1), "Assigned")
    game.Save()
    equal(addon.GetLabel(addon.Bars[1], 1), nil)
end)

test("canceling a default reset preserves labels", function()
    local _, addon, _, _, game = ready({ bindings = { ACTIONBUTTON1 = { "F" } } })
    assert(addon.SetLabel(addon.Bars[1], 1, "Assigned"))
    game.Load(0, { ACTIONBUTTON1 = { "1" } })
    game.Load(1, { ACTIONBUTTON1 = { "F" } })
    game.Flush()
    game.Save()
    equal(addon.GetLabel(addon.Bars[1], 1), "Assigned")
end)

test("a label edited after a pending rebind survives its commit", function()
    local _, addon, fire, _, game = ready({ bindings = { ACTIONBUTTON1 = { "F", "PAD1" } } })
    assert(addon.SetLabel(addon.Bars[1], 1, "Old"))
    game.SetKeys("ACTIONBUTTON1", { "G", "PAD1" })
    assert(addon.SetLabel(addon.Bars[1], 1, "New"))
    game.bindings.ACTIONBUTTON1 = { "PAD1", "G" }
    fire("GAME_PAD_ACTIVE_CHANGED")
    game.Save()
    equal(addon.GetLabel(addon.Bars[1], 1), "New")
end)

test("an unchanged final binding preserves the label", function()
    local _, addon, _, _, game = ready({ bindings = { ACTIONBUTTON1 = { "F" } } })
    assert(addon.SetLabel(addon.Bars[1], 1, "Keep"))
    game.SetKeys("ACTIONBUTTON1", { "G" })
    game.SetKeys("ACTIONBUTTON1", { "F" })
    game.Save()
    equal(addon.GetLabel(addon.Bars[1], 1), "Keep")
end)

test("click-binding fallbacks participate in clearing", function()
    local env, addon, fire, _, game = loadAddon({
        loggedIn = true,
        bindings = { ["CLICK ActionButton1:LeftButton"] = { "F" } },
    })
    env.MainActionBar = {
        actionButtons = { { GetName = function() return "ActionButton1" end } },
    }
    fire("ADDON_LOADED", "CleanBinds")
    assert(addon.SetLabel(addon.Bars[1], 1, "Fallback"))
    game.SetKeys("CLICK ActionButton1:LeftButton", { "G" }, "SetBindingClick")
    game.Save()
    equal(addon.GetLabel(addon.Bars[1], 1), nil)
end)

test("unobserved client loads never look like user rebinding", function()
    local _, addon, fire, _, game = ready({ bindings = { ACTIONBUTTON1 = { "F" } } })
    assert(addon.SetLabel(addon.Bars[1], 1, "Keep"))
    game.bindings = { ACTIONBUTTON1 = { "G" } }
    fire("BINDINGS_LOADED")
    game.Save()
    game.Flush()
    equal(addon.GetLabel(addon.Bars[1], 1), "Keep")
end)

test("invalid edits and combat cannot mutate label data", function()
    local _, addon, _, _, game = ready()
    assert(addon.SetLabel(addon.Bars[1], 1, "Keep"))
    local success, reason = addon.SetLabel(addon.Bars[1], 1, "Bad\nLabel")
    equal(success, false)
    equal(reason, addon.L.INVALID_LABEL)
    equal(addon.GetLabel(addon.Bars[1], 1), "Keep")
    game.combat = true
    success, reason = addon.SetLabel(addon.Bars[1], 1, "Changed")
    equal(success, false)
    equal(reason, addon.L.COMBAT_READ_ONLY)
    success, reason = addon.ResetLabels()
    equal(success, false)
    equal(reason, addon.L.COMBAT_READ_ONLY)
    equal(addon.GetLabel(addon.Bars[1], 1), "Keep")
end)

test("moving a key clears both affected button labels", function()
    local _, addon, _, messages, game = ready({
        bindings = { ACTIONBUTTON1 = { "F" }, ACTIONBUTTON2 = { "G" } },
    })
    assert(addon.SetLabel(addon.Bars[1], 1, "First"))
    assert(addon.SetLabel(addon.Bars[1], 2, "Second"))
    game.SetKeys("ACTIONBUTTON2", { "F" })
    game.Save()
    equal(addon.GetLabel(addon.Bars[1], 1), nil)
    equal(addon.GetLabel(addon.Bars[1], 2), nil)
    assert(messages[1]:find("Cleared 2 custom labels", 1, true))
end)

test("default-reset reordering counts as a binding edit", function()
    local _, addon, _, _, game = ready({ bindings = { ACTIONBUTTON1 = { "F", "G" } } })
    assert(addon.SetLabel(addon.Bars[1], 1, "First"))
    game.Load(0, { ACTIONBUTTON1 = { "G", "F" } })
    game.Flush()
    game.Save()
    equal(addon.GetLabel(addon.Bars[1], 1), nil)
end)

print(("%d tests passed"):format(passed))
