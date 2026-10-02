local passed = 0
local unpackValues = unpack or table.unpack

local function copyTable(value)
    if type(value) ~= "table" then
        return value
    end
    local result = {}
    for key, entry in pairs(value) do
        result[key] = copyTable(entry)
    end
    return result
end

local function bindingSnapshot(command, keyboard, gamepad, device)
    return {
        command = command,
        context = 0,
        keyboard = keyboard or false,
        gamepad = gamepad or false,
        device = device or "keyboard",
    }
end

local function equal(actual, expected)
    assert(actual == expected, ("expected %s, got %s"):format(tostring(expected), tostring(actual)))
end

local function mockFontObject(size, font, flags)
    local object = { size = size or 11, font = font or "Fonts\\Native.ttf", flags = flags or "OUTLINE" }
    function object:GetFont()
        return self.font, self.size, self.flags
    end
    return object
end

local function addFontMethods(object)
    object.fontObject = mockFontObject()
    object.fontWrites, object.heightWrites = 0, 0
    object.width, object.height = 32, 10
    object.color, object.shadow = { 0.6, 0.6, 0.6, 1 }, { 0, 0, 0, 1 }
    function object:GetFont()
        if self.font then
            return self.font[1], self.font[2], self.font[3]
        end
        return self.fontObject:GetFont()
    end
    function object:GetFontObject()
        return self.fontObject
    end
    function object:SetFont(font, size, flags)
        if self.rejectFont then
            error("Rejected font write")
        end
        self.font = { font, size, flags }
        self.fontWrites = self.fontWrites + 1
    end
    function object:SetFontObject(font)
        self.fontObject = font
        self.font = nil
    end
    function object:GetHeight() return self.height end
    function object:GetWidth() return self.width end
    function object:GetSize() return self.width, self.height end
    function object:SetHeight(height)
        self.height = height
        self.heightWrites = self.heightWrites + 1
    end
    function object:SetWidth(width) self.width = width end
    function object:SetSize(width, height) self.width, self.height = width, height end
    function object:GetJustifyH() return self.justifyH or "RIGHT" end
    function object:GetJustifyV() return self.justifyV or "MIDDLE" end
    function object:SetJustifyH(value) self.justifyH = value end
    function object:SetJustifyV(value) self.justifyV = value end
    function object:GetTextColor() return unpackValues(self.color) end
    function object:SetTextColor(...) self.color = { ... } end
    function object:GetShadowColor() return unpackValues(self.shadow) end
    function object:SetShadowColor(...) self.shadow = { ... } end
    function object:GetShadowOffset() return 1, -1 end
    function object:SetShadowOffset() end
    function object:GetStringWidth()
        local _, size = self:GetFont()
        return #(self.text or "") * size * 0.6
    end
    function object:IsTruncated()
        return self:GetStringWidth() > self.width
    end
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
        bindingSet = options.bindingSet or 1,
        savedBindings = options.savedBindings or {},
        actions = options.actions or {},
        combat = false,
    }
    game.savedBindings[game.bindingSet] = copyTable(game.bindings)
    local environment = setmetatable({}, { __index = _G })
    environment._G = environment
    environment.CleanBindsDB = options.database
    environment.CleanBindsCharacterDB = options.characterDatabase
    environment.SlashCmdList = {}
    environment.Settings = {}
    environment.SettingsPanel = {
        SelectCategory = function()
            error("The foundation must not navigate settings")
        end,
    }
    environment.CreateSettingsButtonInitializer = function()
        error("The foundation must not create settings buttons")
    end
    environment.EventRegistry = { callbacks = {} }
    function environment.EventRegistry:RegisterCallback(event, callback, owner)
        local callbacks = self.callbacks[event] or {}
        self.callbacks[event] = callbacks
        callbacks[#callbacks + 1] = { callback = callback, owner = owner }
    end
    function environment.EventRegistry:TriggerEvent(event, ...)
        for _, entry in ipairs(self.callbacks[event] or {}) do
            entry.callback(entry.owner, ...)
        end
    end
    environment.NumberFontNormalSmallGray = mockFontObject()
    environment.MinimalSliderWithSteppersMixin = { Label = { Right = 1 } }
    environment.Enum = { BindingSet = { Default = 0, Account = 1, Character = 2, Current = 3 } }
    environment.C_KeyBindings = { GetBindingContextForAction = function() end }
    local bindingCommands, bindingIndices = {}, {}
    environment.C_KeyBindings.GetBindingIndex = function(command)
        if game.unavailableBinding == command then
            return nil
        end
        return bindingIndices[command]
    end
    environment.GetBinding = function(index, includeGamepad)
        assert(includeGamepad == true)
        local command = bindingCommands[index]
        return command, "BINDING_HEADER_ACTIONBAR", unpackValues(game.bindings[command] or {})
    end
    environment.IsBindingForGamePad = function(key)
        return key:match("PAD") ~= nil
    end
    environment.RANGE_INDICATOR = "*"
    environment.ApproximatelyEqual = function(first, second, epsilon)
        return math.abs(first - second) < (epsilon or 0.000001)
    end
    environment.issecretvalue = function(value)
        return type(value) == "table" and value.secret == true
    end
    environment.C_Timer = {
        After = function(_, callback)
            timers[#timers + 1] = callback
        end,
    }
    environment.GetBuildInfo = function()
        return "1.60.1", "70009", "", options.interface or 16001
    end
    environment.IsLoggedIn = function()
        return options.loggedIn or false
    end
    environment.print = function(message)
        messages[#messages + 1] = message
    end

    environment.GetBindingKey = function(command)
        local displayed = game.displayedBindings and game.displayedBindings[command]
        return unpackValues(displayed or game.bindings[command] or {})
    end
    environment.GetBindingName = function(command)
        return options.bindingNames and options.bindingNames[command] or command
    end
    environment.GetBindingText = function(key)
        return key or ""
    end
    environment.GetCurrentBindingSet = function()
        return game.bindingSet
    end
    environment.GetActionInfo = function(action)
        assert(type(action) == "number" and action > 0)
        return game.actions[action]
    end
    environment.InCombatLockdown = function()
        return game.combat
    end
    environment.hooksecurefunc = function(target, name, callback)
        if type(target) == "table" then
            local original = target[name]
            assert(type(original) == "function", name)
            target[name] = function(self, ...)
                original(self, ...)
                callback(self, ...)
            end
        else
            assert(type(environment[target]) == "function", target)
            hooks[target] = hooks[target] or {}
            hooks[target][#hooks[target] + 1] = name
        end
    end

    for _, name in ipairs({
        "SetBinding", "SetBindingClick", "SetBindingSpell", "SetBindingItem", "SetBindingMacro",
        "SaveBindings", "LoadBindings", "EditMacro", "DeleteMacro",
    }) do
        environment[name] = function()
            error("The addon must not call " .. name)
        end
    end

    for _, name in ipairs({
        "RegisterAddOnCategory", "RegisterVerticalLayoutCategory",
        "RegisterCanvasLayoutSubcategory", "RegisterProxySetting",
        "CreateCheckbox", "CreateControlInitializer", "CreateSliderOptions", "OpenToCategory",
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
    local paths = { "Locale.lua", "Bars.lua", "Labels.lua", "ActionLabels.lua" }
    if options.settings then
        paths[#paths + 1] = "Settings.lua"
    end
    paths[#paths + 1] = "Core.lua"
    for _, path in ipairs(paths) do
        local chunk
        if setfenv then
            chunk = assert(loadfile(path))
            setfenv(chunk, environment)
        else
            chunk = assert(loadfile(path, "t", environment))
        end
        chunk("CleanBinds", addon)
    end
    for _, bar in ipairs(addon.Bars) do
        for index = 1, bar.buttonCount do
            local command = bar.bindingPrefix .. index
            bindingCommands[#bindingCommands + 1] = command
            bindingIndices[command] = #bindingCommands
        end
    end
    if options.setup then
        options.setup(environment, game)
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
        game.savedBindings[game.bindingSet] = copyTable(game.bindings)
        fire("UPDATE_BINDINGS")
        callHooks("SaveBindings", game.bindingSet)
    end

    function game.Load(selectedSet, bindings)
        local source = selectedSet == 3 and game.bindingSet or selectedSet
        game.bindings = copyTable(bindings or game.savedBindings[source] or game.bindings)
        fire("BINDINGS_LOADED")
        callHooks("LoadBindings", selectedSet)
    end

    function game.Switch(selectedSet)
        if selectedSet == 2 then
            game.Save(1)
        end
        game.Load(selectedSet)
        game.Save(selectedSet)
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
    equal(next(addon.db.bindingSnapshots), nil)
    equal(env.CleanBindsCharacterDB, nil)
    equal(#messages, 0)
end)

test("supports loading after login", function()
    local _, addon, fire = loadAddon({ loggedIn = true })
    fire("ADDON_LOADED", "CleanBinds")
    equal(addon.state, "ready")
end)

test("waits for an initial binding scope without creating or editing saved data", function()
    local env, addon, fire, messages, game = loadAddon({ bindingSet = 0 })
    fire("ADDON_LOADED", "CleanBinds")
    equal(addon.state, "loading")
    fire("PLAYER_LOGIN")
    equal(addon.state, "waiting_bindings")
    equal(addon.db, nil)
    equal(addon.category, nil)
    equal(env.CleanBindsDB, nil)
    equal(env.CleanBindsCharacterDB, nil)
    equal(addon.IsEnabled(), false)
    equal(addon.SetLabel(addon.Bars[1], 1, "Wrong"), false)
    equal(addon.SetEnabled(false), false)
    equal(addon.ResetLabels(), false)
    equal(#messages, 1)
    equal(messages[1], addon.L.ADDON_NAME .. ": " .. addon.L.BINDINGS_LOADING)

    game.Flush()
    game.Flush()
    equal(addon.state, "waiting_bindings")
    equal(env.CleanBindsDB, nil)
    equal(env.CleanBindsCharacterDB, nil)
    equal(#messages, 1)
    env.SlashCmdList.CLEANBINDS("")
    env.SlashCmdList.CLEANBINDS("status")
    equal(messages[2], messages[1])
    equal(messages[3], messages[1])
end)

test("a deferred startup selects only the resolved account or character profile", function()
    for _, scope in ipairs({ 1, 2 }) do
        local account = {
            schemaVersion = 1, enabled = false,
            overrides = { ["actionbar1:1"] = "Account" },
            bindingSnapshots = { ["actionbar1:1"] = bindingSnapshot("ACTIONBUTTON1", "F") },
        }
        local character = {
            schemaVersion = 1, enabled = true,
            overrides = { ["actionbar1:1"] = "Character" },
            bindingSnapshots = { ["actionbar1:1"] = bindingSnapshot("ACTIONBUTTON1", "G") },
        }
        local env, addon, fire, messages, game = loadAddon({
            loggedIn = true, bindingSet = 0, database = account, characterDatabase = character,
        })
        fire("ADDON_LOADED", "CleanBinds")
        equal(addon.state, "waiting_bindings")
        equal(addon.db, nil)
        equal(account.overrides["actionbar1:1"], "Account")
        equal(character.overrides["actionbar1:1"], "Character")
        equal(account.bindingSnapshots["actionbar1:1"].keyboard, "F")
        equal(character.bindingSnapshots["actionbar1:1"].keyboard, "G")

        game.bindingSet = scope
        game.bindings = { ACTIONBUTTON1 = { scope == 1 and "F" or "G" } }
        game.Flush()
        equal(addon.state, "ready")
        equal(addon.db, scope == 1 and account or character)
        equal(addon.GetLabel(addon.Bars[1], 1), scope == 1 and "Account" or "Character")
        equal(addon.IsEnabled(), scope == 2)
        equal(env.CleanBindsDB, account)
        equal(env.CleanBindsCharacterDB, character)
        equal(account.overrides["actionbar1:1"], "Account")
        equal(character.overrides["actionbar1:1"], "Character")
        equal(account.bindingSnapshots["actionbar1:1"].keyboard, "F")
        equal(character.bindingSnapshots["actionbar1:1"].keyboard, "G")
        equal(#messages, 1)
    end
end)

test("binding lifecycle events recover startup without polling or duplicate initialization", function()
    for _, event in ipairs({ "BINDINGS_LOADED", "UPDATE_BINDINGS", "PLAYER_ENTERING_WORLD" }) do
        local env, addon, fire, messages, game = loadAddon({ bindingSet = 0 })
        local initializeLabels = addon.InitializeLabels
        local initializations = 0
        addon.InitializeLabels = function()
            initializations = initializations + 1
            return initializeLabels()
        end
        local scopeReads = 0
        env.GetCurrentBindingSet = function()
            scopeReads = scopeReads + 1
            return game.bindingSet
        end
        fire(event)
        equal(initializations, 0)
        fire("ADDON_LOADED", "CleanBinds")
        fire("PLAYER_LOGIN")
        game.Flush()
        equal(addon.state, "waiting_bindings")
        local reads = scopeReads
        game.Flush()
        equal(scopeReads, reads)
        fire(event)
        fire(event)
        game.Flush()
        equal(scopeReads, reads + 1)
        equal(initializations, 0)
        equal(#messages, 1)

        fire(event)
        fire(event)
        equal(addon.state, "waiting_bindings")
        game.bindingSet = 1
        game.Flush()
        equal(addon.state, "ready")
        equal(initializations, 1)
        equal(addon.db, env.CleanBindsDB)
        local category = addon.category
        fire("PLAYER_LOGIN")
        fire("ADDON_LOADED", "CleanBinds")
        fire(event)
        fire(event)
        game.Flush()
        equal(initializations, 1)
        equal(addon.category, category)
        equal(#messages, 1)
    end
end)

test("deferred startup still rejects invalid profiles and truly unknown scopes", function()
    for _, scope in ipairs({ 1, 2, 99 }) do
        local account = { schemaVersion = 99 }
        local character = { schemaVersion = 99 }
        local env, addon, fire, messages, game = loadAddon({
            loggedIn = true, bindingSet = 0, database = account, characterDatabase = character,
        })
        fire("ADDON_LOADED", "CleanBinds")
        equal(addon.state, "waiting_bindings")
        game.bindingSet = scope
        game.Flush()
        equal(addon.state, "failed")
        equal(addon.db, nil)
        equal(addon.category, nil)
        equal(env.CleanBindsDB, account)
        equal(env.CleanBindsCharacterDB, character)
        equal(#messages, 2)
        assert(messages[2]:find(scope == 99 and "scope 99" or "unsupported schema", 1, true))
        game.bindingSet = 1
        fire("UPDATE_BINDINGS")
        fire("PLAYER_ENTERING_WORLD")
        game.Flush()
        equal(addon.state, "failed")
        equal(#messages, 2)
    end
end)

test("preserves existing account data", function()
    local existing = {
        schemaVersion = 1,
        enabled = false,
        overrides = { ["actionbar2:1"] = "MWD" },
        bindingSnapshots = { ["actionbar2:1"] = bindingSnapshot("MULTIACTIONBAR1BUTTON1") },
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
        { schemaVersion = 1, enabled = true, overrides = {} },
        { schemaVersion = 2, enabled = true, overrides = {}, bindingSnapshots = {} },
        { schemaVersion = 1, enabled = "true", overrides = {}, bindingSnapshots = {} },
        { schemaVersion = 1, enabled = true, overrides = false, bindingSnapshots = {} },
        { schemaVersion = 1, enabled = true, overrides = {}, bindingSnapshots = false },
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
    equal(messages[3], addon.L.ADDON_NAME .. ": " .. addon.L.ACCOUNT_NOTICE)
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

local function readySettings(options)
    local pages = {}
    local settingsOptions = {
        settings = true,
        setup = function(environment, game)
            local function noop() end
            local createFrame = environment.CreateFrame
            local function widget(frameType, name, parent, template)
                local frame = createFrame()
                addFontMethods(frame)
                frame.shown = true
                frame.text = ""
                frame.width, frame.height = 600, 400
                frame.mouseOver = false

                -- Layout is not simulated; interaction methods below are explicit.
                for _, method in ipairs({
                    "SetPoint", "ClearAllPoints", "SetAllPoints", "SetJustifyH",
                    "SetWordWrap", "SetScale", "SetMaxLines",
                    "SetAtlas", "SetHideIfUnscrollable", "HighlightText", "SetScrollChild",
                }) do
                    frame[method] = noop
                end
                function frame:SetText(text)
                    self.text = text
                    if self.OnTextChanged then
                        self:OnTextChanged()
                    end
                end
                function frame:GetText()
                    return self.text
                end
                function frame:SetWidth(width)
                    self.width = width
                end
                function frame:GetWidth()
                    return self.width
                end
                function frame:SetHeight(height)
                    self.height = height
                end
                function frame:GetHeight()
                    return self.height
                end
                function frame:SetSize(width, height)
                    self.width, self.height = width, height
                end
                function frame:SetShown(shown)
                    if self.shown ~= shown then
                        self.shown = shown
                        local script = shown and self.OnShow or self.OnHide
                        if script then
                            script(self)
                        end
                    end
                end
                function frame:Show()
                    self:SetShown(true)
                end
                function frame:Hide()
                    self:SetShown(false)
                end
                function frame:IsShown()
                    return self.shown
                end
                function frame:SetEnabled(enabled)
                    self.enabled = enabled
                end
                function frame:IsMouseOver()
                    return self.mouseOver
                end
                function frame:SetFocus()
                    self.focused = true
                end
                function frame:ClearFocus()
                    if self.focused then
                        self.focused = false
                        if self.OnEditFocusLost then
                            self:OnEditFocusLost()
                        end
                    end
                end
                function frame:GetVerticalScroll()
                    return self.offset or 0
                end
                function frame:SetVerticalScroll(offset)
                    self.offset = offset
                end
                function frame:HookScript(script, callback)
                    local previous = self[script]
                    self[script] = function(self, ...)
                        if previous then
                            previous(self, ...)
                        end
                        callback(self, ...)
                    end
                end
                frame.CreateFontString = widget
                frame.CreateTexture = widget
                if template == "CleanBindsBindingRowTemplate" then
                    for _, key in ipairs({ "Highlight", "Label", "Binding", "Override", "Editor" }) do
                        frame[key] = widget()
                    end
                    frame.Editor:Hide()
                elseif template == "ScrollFrameTemplate" then
                    frame.ScrollBar = widget()
                end
                return frame
            end
            environment.CreateFrame = widget
            local initializer = {
                AddModifyPredicate = noop,
                AddEvaluateStateFrameEvent = noop,
                AddEvaluateStateCVar = noop,
                SetValueChangedCallback = noop,
            }
            function initializer:AddSearchTags(...)
                self.searchTags = self.searchTags or {}
                for _, tag in ipairs({ ... }) do
                    if tag ~= "" then
                        self.searchTags[#self.searchTags + 1] = tag:upper()
                    end
                end
            end
            function initializer:MatchesSearchTags(words)
                for _, word in ipairs(words) do
                    for _, tag in ipairs(self.searchTags or {}) do
                        local first, last = tag:find(word, 1, true)
                        if first then return last - first end
                    end
                end
            end
            function initializer:IsSearchIgnoredInLayout() return false end
            function initializer:ShouldShow() return true end
            environment.Settings.VarType = { Boolean = "boolean", Number = "number" }
            game.categories, game.settings, game.layouts, game.rootCategories = {}, {}, {}, {}
            local function category(name, parent)
                local result = { id = #game.categories + 1, name = name, parent = parent, subcategories = {} }
                function result:GetID() return self.id end
                function result:GetName() return self.name end
                function result:GetSubcategories() return self.subcategories end
                game.categories[#game.categories + 1] = result
                if parent then
                    parent.subcategories[#parent.subcategories + 1] = result
                end
                return result
            end
            environment.Settings.RegisterVerticalLayoutCategory = function(name)
                local result = category(name)
                local layout = { initializers = {} }
                function layout:AddInitializer(value)
                    self.initializers[#self.initializers + 1] = value
                end
                function layout:IsVerticalLayout() return true end
                function layout:EnumerateInitializers() return ipairs(self.initializers) end
                game.layouts[result] = layout
                return result, layout
            end
            environment.Settings.RegisterCanvasLayoutSubcategory = function(parent, page, name)
                local result = category(name, parent)
                game.layouts[result] = { frame = page, IsVerticalLayout = function() return false end }
                pages[#pages + 1] = page
                return result
            end
            environment.Settings.RegisterAddOnCategory = function(category)
                game.rootCategories[#game.rootCategories + 1] = category
            end
            environment.Settings.RegisterProxySetting = function(category, variable, variableType, name, default, getter, setter)
                local setting = { variable = variable, variableType = variableType, name = name, default = default, updates = 0, writes = 0 }
                game.settings[setting] = category
                setting.GetValueDerived = getter
                function setting:SetValueDerived(value)
                    self.writes = self.writes + 1
                    setter(value)
                end
                function setting:GetValue()
                    return getter()
                end
                function setting:TriggerValueChanged(value)
                    self.displayedValue = value
                    if self.onValueChanged then
                        self.onValueChanged(value)
                    end
                end
                function setting:ApplyValue(value)
                    if getter() ~= value then
                        equal(type(value), variableType)
                        self.locked = true
                        self:SetValueDerived(value)
                        self.locked = false
                    end
                    -- Native settings notify with the requested value, not the getter's result.
                    self:TriggerValueChanged(value)
                end
                function setting:SetValue(value)
                    if not self.locked then
                        self:ApplyValue(value)
                    end
                end
                function setting:SetValueToDefault()
                    if self.default == nil then
                        return false
                    end
                    self:ApplyValue(self.default)
                    return true
                end
                function setting:NotifyUpdate()
                    self.updates = self.updates + 1
                    self:TriggerValueChanged(getter())
                end
                if variable == "CLEANBINDS_ENABLED" then
                    game.enabledSetting = setting
                elseif variable == "CLEANBINDS_HIDE_MACRO_NAMES" then
                    game.hideMacroNamesSetting = setting
                elseif variable == "CLEANBINDS_KEYBIND_FONT_SIZE" then
                    game.fontSizeSetting = setting
                else
                    error("Unexpected proxy setting: " .. variable)
                end
                return setting
            end
            game.checkboxes = {}
            environment.Settings.CreateCheckbox = function(category, setting)
                local checkbox = copyTable(initializer)
                checkbox.data = { setting = setting, name = setting.name }
                checkbox:AddSearchTags(setting.name)
                function checkbox:AddModifyPredicate(predicate)
                    self.canModify = predicate
                end
                game.checkboxes[setting.variable] = checkbox
                game.layouts[category]:AddInitializer(checkbox)
                return checkbox
            end
            environment.Settings.CreateSliderOptions = function(minValue, maxValue, rate)
                local options = { minValue = minValue, maxValue = maxValue, steps = (maxValue - minValue) / rate }
                function options:SetLabelFormatter(labelType, formatter)
                    self.formatters = { [labelType] = formatter }
                end
                return options
            end
            environment.SettingsSliderControlMixin = {
                Init = function(self, controlInitializer)
                    self.initializer = controlInitializer
                    local setting, options = controlInitializer.setting, controlInitializer.options
                    setting.onValueChanged = function(value)
                        self:OnSettingValueChanged(setting, value)
                    end
                    self.SliderWithSteppers:Init(setting:GetValue(),
                        options.minValue, options.maxValue, options.steps, options.formatters)
                    self.SliderWithSteppers.onValueChanged = function(value)
                        self:OnSliderValueChanged(value)
                    end
                    self:EvaluateState()
                end,
                GetSetting = function(self) return self.initializer.setting end,
                SetValue = function(self, value) self.SliderWithSteppers:SetValue(value) end,
                OnSettingValueChanged = function(self, _, value) self:SetValue(value) end,
                OnSliderValueChanged = function(self, value) self:GetSetting():SetValue(value) end,
                DisplayEnabled = function(self, enabled) self.enabled = enabled end,
                EvaluateState = function(self)
                    local enabled = not self.initializer.canModify or self.initializer.canModify()
                    self.SliderWithSteppers:SetEnabled(enabled)
                    self:DisplayEnabled(enabled)
                end,
            }
            environment.Settings.CreateControlInitializer = function(template, setting, options)
                equal(template, "CleanBindsFontSizeSliderTemplate")
                local controlInitializer = copyTable(initializer)
                controlInitializer.setting, controlInitializer.options = setting, options
                controlInitializer.data = { setting = setting, name = setting.name }
                controlInitializer:AddSearchTags(setting.name)
                function controlInitializer:AddModifyPredicate(predicate) self.canModify = predicate end
                local slider = {}
                function slider:FormatValue(value)
                    self.label = self.options.formatters[1](value)
                end
                function slider:Init(value, minValue, maxValue, steps, formatters)
                    self.options = { minValue = minValue, maxValue = maxValue, steps = steps, formatters = formatters }
                    self:SetValue(value)
                    self:FormatValue(value)
                end
                function slider:SetValue(value)
                    value = math.max(self.options.minValue, math.min(self.options.maxValue, value))
                    if self.value ~= value then
                        self.value = value
                        self:FormatValue(value)
                        if self.onValueChanged then
                            self.onValueChanged(value)
                        end
                    end
                end
                function slider:SetEnabled(enabled) self.enabled = enabled end
                slider.canModify = function() return controlInitializer.canModify() end
                local control = { SliderWithSteppers = slider }
                for key, method in pairs(environment.SettingsSliderControlMixin) do
                    control[key] = method
                end
                for key, method in pairs(environment.CleanBindsFontSizeSliderMixin) do
                    control[key] = method
                end
                game.fontSlider = slider
                game.fontSliderControl = control
                control:Init(controlInitializer)
                return controlInitializer
            end
            environment.Settings.CreateElementInitializer = function(template, data)
                local element = copyTable(initializer)
                element.data = data
                if template == "CleanBindsDescriptionTemplate" then
                    game.description = data.text
                elseif template == "CleanBindsFontPreviewTemplate" then
                    local preview = widget()
                    for key, method in pairs(environment.CleanBindsFontPreviewMixin) do
                        preview[key] = method
                    end
                    preview:OnLoad()
                    preview:Init()
                    game.fontPreview = preview
                else
                    error("Unexpected initializer: " .. template)
                end
                return element
            end
            environment.CreateSettingsButtonInitializer = function(name, buttonText, callback, tooltip, addSearchTags)
                local element = copyTable(initializer)
                element.data = { name = name, buttonText = buttonText, buttonClick = callback, tooltip = tooltip }
                if addSearchTags then
                    element:AddSearchTags(name, buttonText)
                end
                return element
            end
            environment.SettingsPanel.SelectCategory = function(_, category, force)
                game.navigation = { category = category, force = force }
                if force or game.currentCategory ~= category then
                    local previous = game.layouts[game.currentCategory]
                    if previous and previous.frame then previous.frame:Hide() end
                    game.searchText = ""
                    game.currentCategory = category
                    local layout = assert(game.layouts[category])
                    if layout.frame then
                        layout.frame:Show()
                        layout.frame:OnRefresh()
                    end
                end
            end
            function game.Search(text)
                game.searchText = text
                local layout = game.layouts[game.currentCategory]
                if layout and layout.frame then layout.frame:Hide() end
                local query = text:upper()
                local words = { query }
                for word in query:gmatch("([^, ]+)") do
                    words[#words + 1] = word
                end
                local results = {}
                local function searchCategory(category)
                    local layout = game.layouts[category]
                    if layout:IsVerticalLayout() then
                        for _, entry in layout:EnumerateInitializers() do
                            if entry:ShouldShow() and not entry:IsSearchIgnoredInLayout(layout)
                                and entry:MatchesSearchTags(words) then
                                results[#results + 1] = {
                                    category = category.redirectCategory or category, initializer = entry,
                                }
                            end
                        end
                    end
                end
                for _, root in ipairs(game.rootCategories) do
                    searchCategory(root)
                    for _, child in ipairs(root:GetSubcategories()) do searchCategory(child) end
                end
                return results
            end
            environment.StaticPopupDialogs = {}
            environment.StaticPopup_Show = function(which, text, _, data)
                game.popup = { which = which, text = text, data = data }
            end
            environment.StaticPopup_Hide = function(which)
                if game.popup and game.popup.which == which then
                    game.popup = nil
                end
            end
            function game.ResetBar(page)
                page.Reset:OnClick()
                local popup = assert(game.popup)
                game.popup = nil
                environment.StaticPopupDialogs[popup.which].OnAccept(nil, popup.data)
            end
            function game.DefaultSettings(choice, category)
                if choice == "cancel" then
                    return
                end
                assert(choice == "all" or choice == "these")
                for setting, owner in pairs(game.settings) do
                    if choice == "all" or owner == category then
                        setting:SetValueToDefault()
                    end
                end
                for _, page in ipairs(pages) do
                    if (choice == "all" or page.category == category) and page.OnDefault then
                        page:OnDefault()
                    end
                end
                if choice == "all" then
                    game.defaultBindingLoads = (game.defaultBindingLoads or 0) + 1
                    game.Load(0)
                    environment.EventRegistry:TriggerEvent("Settings.Defaulted")
                else
                    environment.EventRegistry:TriggerEvent("Settings.CategoryDefaulted", category)
                end
            end
            environment.GameTooltip = { Hide = noop }
        end,
    }
    for key, value in pairs(options or {}) do
        settingsOptions[key] = value
    end
    local env, addon, fire, messages, game = ready(settingsOptions)
    return env, addon, fire, pages, messages, game
end

test("repeated clicks inside a label editor keep the draft open", function()
    local env, addon, fire, pages = readySettings()
    equal(env.MouseIsOver, nil)
    local page = pages[2]
    local row = page.rows[3]
    page:Show()
    assert(addon.SetLabel(page.bar, row.index, "Original"))
    row.Override:OnClick()
    row.Editor:SetText("Draft")
    row.Editor.mouseOver = true

    for _ = 1, 3 do
        fire("GLOBAL_MOUSE_DOWN", "LeftButton")
    end

    equal(page.editingRow, row)
    equal(row.editing, true)
    equal(row.Editor.focused, true)
    equal(row.Editor:GetText(), "Draft")
    equal(addon.GetLabel(page.bar, row.index), "Original")
end)

test("clicking outside a label editor commits exactly once", function()
    local _, addon, fire, pages = readySettings()
    local page = pages[2]
    local row = page.rows[3]
    page:Show()
    row.Override:OnClick()
    row.Editor:SetText("MWD")
    local saves = 0
    local setLabel = addon.SetLabel
    addon.SetLabel = function(...)
        saves = saves + 1
        return setLabel(...)
    end
    fire("GLOBAL_MOUSE_DOWN", "LeftButton")
    fire("GLOBAL_MOUSE_DOWN", "LeftButton")

    equal(addon.GetLabel(page.bar, row.index), "MWD")
    equal(saves, 1)
    equal(page.editingRow, nil)
    equal(row.Editor:IsShown(), false)
    equal(row.Editor.focused, false)
    equal(row.Override:IsShown(), true)
end)

test("clicking another label field commits the previous draft", function()
    local _, addon, fire, pages = readySettings()
    local page = pages[2]
    local previous, nextRow = page.rows[3], page.rows[4]
    page:Show()
    previous.Override:OnClick()
    previous.Editor:SetText("MWD")
    fire("GLOBAL_MOUSE_DOWN", "LeftButton")
    nextRow.Override:OnClick()
    nextRow.Editor.mouseOver = true
    fire("GLOBAL_MOUSE_DOWN", "LeftButton")

    equal(addon.GetLabel(page.bar, previous.index), "MWD")
    equal(previous.editing, false)
    equal(page.editingRow, nextRow)
    equal(nextRow.Editor.focused, true)
end)

test("clicking away from invalid label text preserves the committed value", function()
    local _, addon, fire, pages = readySettings()
    local page = pages[2]
    local row = page.rows[3]
    page:Show()
    assert(addon.SetLabel(page.bar, row.index, "Original"))
    row.Override:OnClick()
    row.Editor:SetText("Invalid\nlabel")
    fire("GLOBAL_MOUSE_DOWN", "LeftButton")

    equal(addon.GetLabel(page.bar, row.index), "Original")
    equal(page.editingRow, nil)
    equal(page.Status:GetText(), addon.L.INVALID_LABEL)
end)

test("Escape and combat cancel drafts before subsequent outside clicks", function()
    for _, combat in ipairs({ false, true }) do
        local _, addon, fire, pages, _, game = readySettings()
        local page = pages[2]
        local row = page.rows[3]
        page:Show()
        assert(addon.SetLabel(page.bar, row.index, "Original"))
        row.Override:OnClick()
        row.Editor:SetText("Draft")
        if combat then
            game.combat = true
            fire("PLAYER_REGEN_DISABLED")
            equal(page.Status:GetText(), addon.L.COMBAT_CANCELED)
        else
            row.Editor:OnEscapePressed()
        end
        fire("GLOBAL_MOUSE_DOWN", "LeftButton")
        equal(addon.GetLabel(page.bar, row.index), "Original")
        equal(page.editingRow, nil)
        equal(row.Editor:IsShown(), false)
    end
end)

local function snapshotDatabase(db)
    return copyTable(db)
end

test("initializes saved data loaded after addon files but before login", function()
    local env, addon, fire = loadAddon()
    local saved = {
        schemaVersion = 1, enabled = false, overrides = { ["stance:1"] = "Form" },
        bindingSnapshots = { ["stance:1"] = bindingSnapshot("SHAPESHIFTBUTTON1") },
    }
    env.CleanBindsDB = saved
    fire("ADDON_LOADED", "CleanBinds")
    equal(addon.state, "loading")
    equal(env.CleanBindsDB, saved)
    fire("PLAYER_LOGIN")
    equal(addon.db, saved)
    equal(addon.db.enabled, false)
    equal(addon.GetLabel(addon.Bars[10], 1), "Form")
end)

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
    local _, other, _, messages, game = ready({
        database = snapshotDatabase(env.CleanBindsDB),
        bindings = { ACTIONBUTTON1 = { "MOUSEWHEELDOWN" } },
    })
    game.Save()
    equal(other.GetLabel(other.Bars[1], 1), "MWD")
    equal(other.GetLabel(other.Bars[2], 1), "Different")
    equal(#messages, 0)
end)

test("restores edited and cleared labels with the saved enable state", function()
    local env, addon = ready()
    assert(addon.SetLabel(addon.Bars[1], 1, "Original"))
    assert(addon.SetLabel(addon.Bars[1], 2, "Remove"))
    local reloaded, other = ready({ database = snapshotDatabase(env.CleanBindsDB) })
    assert(other.SetLabel(other.Bars[1], 1, "Updated"))
    assert(other.SetLabel(other.Bars[1], 2, ""))
    other.db.enabled = false

    local _, restored = ready({ database = snapshotDatabase(reloaded.CleanBindsDB) })
    equal(restored.GetLabel(restored.Bars[1], 1), "Updated")
    equal(restored.GetLabel(restored.Bars[1], 2), nil)
    equal(restored.db.enabled, false)
    equal(addon.GetLabel(addon.Bars[1], 1), "Original")
    equal(addon.GetLabel(addon.Bars[1], 2), "Remove")
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
        bindingSnapshots = { ["actionbar1:2"] = bindingSnapshot("ACTIONBUTTON2") },
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

test("loading and saving another binding set selects independent labels", function()
    local env, addon, _, _, game = ready({ bindings = { ACTIONBUTTON1 = { "F" } } })
    assert(addon.SetLabel(addon.Bars[1], 1, "Shared"))
    game.Load(2, { ACTIONBUTTON1 = { "G" } })
    game.Save(2)
    game.Flush()
    equal(addon.GetLabel(addon.Bars[1], 1), nil)
    equal(env.CleanBindsDB.overrides["actionbar1:1"], "Shared")
    assert(addon.SetLabel(addon.Bars[1], 1, "Character"))
    game.SetKeys("ACTIONBUTTON1", { "H" })
    game.Save()
    equal(addon.GetLabel(addon.Bars[1], 1), nil)
    equal(env.CleanBindsDB.overrides["actionbar1:1"], "Shared")
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

test("unobserved client loads preserve uncertain labels without applying them", function()
    local env, addon, fire, messages, game = ready({ bindings = { ACTIONBUTTON1 = { "F" } } })
    assert(addon.SetLabel(addon.Bars[1], 1, "Keep"))
    game.bindings = { ACTIONBUTTON1 = { "G" } }
    fire("BINDINGS_LOADED")
    game.Save()
    game.Flush()
    equal(addon.GetLabel(addon.Bars[1], 1), nil)
    equal(env.CleanBindsDB.overrides["actionbar1:1"], "Keep")
    assert(messages[1]:find("could not be verified", 1, true))
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

local function mockButton(name, text, shown)
    local hotkey = { text = text, shown = shown ~= false, alpha = 0.8, writes = 0 }
    addFontMethods(hotkey)
    function hotkey:GetText()
        return self.text
    end
    function hotkey:SetText(value)
        if self.rejectWrite then
            error("Rejected text write")
        end
        self.text = value
        self.writes = self.writes + 1
    end
    function hotkey:IsForbidden()
        return self.forbidden or false
    end
    local button = { HotKey = hotkey, scripts = {} }
    function hotkey:GetNumPoints() return 1 end
    function hotkey:GetPoint() return "TOPRIGHT", button, "TOPRIGHT", -4, -5 end
    function button:GetSize() return 45, 45 end
    function button:GetNormalTexture() return nil end
    function button:GetName()
        return name
    end
    function button:IsForbidden()
        return self.forbidden or false
    end
    function button:HookScript(script, callback)
        self.scripts[script] = self.scripts[script] or {}
        table.insert(self.scripts[script], callback)
    end
    function button:Fire(script)
        for _, callback in ipairs(self.scripts[script] or {}) do
            callback(self)
        end
    end
    return button
end

test("applies and restores actual hotkey text without changing visibility", function()
    local button = mockButton("ActionButton1", "F", false)
    local _, addon = ready({
        bindings = { ACTIONBUTTON1 = { "F" } },
        setup = function(env)
            env.MainActionBar = { actionButtons = { button } }
        end,
    })
    assert(addon.SetLabel(addon.Bars[1], 1, "MWD"))
    equal(button.HotKey:GetText(), "MWD")
    equal(button.HotKey.shown, false)
    equal(button.HotKey.alpha, 0.8)
    assert(addon.SetLabel(addon.Bars[1], 1, ""))
    equal(button.HotKey:GetText(), "F")
    equal(button.HotKey.shown, false)
end)

test("restores the latest native text rather than an old snapshot", function()
    local button = mockButton("ActionButton1", "F")
    local _, addon = ready({
        bindings = { ACTIONBUTTON1 = { "F" } },
        setup = function(env)
            env.MainActionBar = { actionButtons = { button } }
        end,
    })
    assert(addon.SetLabel(addon.Bars[1], 1, "Custom"))
    button.HotKey:SetText("New native text")
    equal(button.HotKey:GetText(), "Custom")
    assert(addon.ResetLabels("actionbar1"))
    equal(button.HotKey:GetText(), "New native text")
end)

test("master disable restores native text and re-enable reapplies labels", function()
    local button = mockButton("ActionButton1", "F")
    local _, addon = ready({
        bindings = { ACTIONBUTTON1 = { "F" } },
        setup = function(env)
            env.MainActionBar = { actionButtons = { button } }
        end,
    })
    assert(addon.SetLabel(addon.Bars[1], 1, "Custom"))
    addon.db.enabled = false
    addon.RefreshActionLabels()
    equal(button.HotKey:GetText(), "F")
    addon.db.enabled = true
    addon.RefreshActionLabels()
    equal(button.HotKey:GetText(), "Custom")
end)

test("vehicle display mirrors share the main button override", function()
    local main = mockButton("ActionButton1", "F")
    local vehicle = mockButton("OverrideActionBarButton1", "F")
    local _, addon = ready({
        bindings = { ACTIONBUTTON1 = { "F" } },
        setup = function(env)
            env.MainActionBar = { actionButtons = { main } }
            env.OverrideActionBar = {}
            env.OverrideActionBarButton1 = vehicle
        end,
    })
    assert(addon.SetLabel(addon.Bars[1], 1, "Shared"))
    equal(main.HotKey:GetText(), "Shared")
    equal(vehicle.HotKey:GetText(), "Shared")
    assert(addon.ResetLabels("actionbar1"))
    equal(main.HotKey:GetText(), "F")
    equal(vehicle.HotKey:GetText(), "F")
end)

test("pet and stance text works without calling native action handlers", function()
    local pet = mockButton("PetActionButton1", "CTRL-1")
    local stance = mockButton("StanceButton1", nil)
    local _, addon = ready({
        bindings = { BONUSACTIONBUTTON1 = { "CTRL-1" }, SHAPESHIFTBUTTON1 = { "F1" } },
        setup = function(env)
            env.PetActionBar = { actionButtons = { pet } }
            env.StanceBar = { actionButtons = { stance } }
        end,
    })
    assert(addon.SetLabel(addon.Bars[9], 1, "Pet"))
    assert(addon.SetLabel(addon.Bars[10], 1, "Form"))
    equal(pet.HotKey:GetText(), "Pet")
    equal(stance.HotKey:GetText(), "Form")
    assert(addon.ResetLabels("stance"))
    equal(stance.HotKey:GetText(), nil)
    equal(pet.HotKey:GetText(), "Pet")
end)

test("unbound buttons keep their native range indicator", function()
    local button = mockButton("ActionButton1", "*", false)
    local _, addon = ready({
        setup = function(env)
            env.MainActionBar = { actionButtons = { button } }
        end,
    })
    assert(addon.SetLabel(addon.Bars[1], 1, "Dormant"))
    equal(button.HotKey:GetText(), "*")
    equal(button.HotKey.shown, false)
end)

test("custom range-dot text cannot impersonate the native range marker", function()
    local button = mockButton("ActionButton1", "F")
    local _, addon = ready({
        bindings = { ACTIONBUTTON1 = { "F" } },
        setup = function(env)
            env.MainActionBar = { actionButtons = { button } }
        end,
    })
    assert(addon.SetLabel(addon.Bars[1], 1, "*"))
    equal(button.HotKey:GetText(), "*|r")
    equal(addon.GetLabel(addon.Bars[1], 1), "*")
end)

test("respects native suppression by empty text", function()
    local button = mockButton("ActionButton1", "F")
    local _, addon = ready({
        bindings = { ACTIONBUTTON1 = { "F" } },
        setup = function(env)
            env.MainActionBar = { actionButtons = { button } }
        end,
    })
    assert(addon.SetLabel(addon.Bars[1], 1, "Custom"))
    button.HotKey:SetText("")
    equal(button.HotKey:GetText(), "")
    addon.RefreshActionLabels()
    equal(button.HotKey:GetText(), "")
    button.HotKey:SetText("F")
    equal(button.HotKey:GetText(), "Custom")
end)

test("attaches late native buttons without duplicate hooks", function()
    local env, addon, fire, _, game = ready({ bindings = { ACTIONBUTTON1 = { "F" } } })
    assert(addon.SetLabel(addon.Bars[1], 1, "Late"))
    local button = mockButton("ActionButton1", "F")
    env.MainActionBar = { actionButtons = { button } }
    fire("ADDON_LOADED", "Blizzard_ActionBar")
    game.Flush()
    equal(button.HotKey:GetText(), "Late")
    addon.RefreshActionLabels()
    addon.RefreshActionLabels()
    equal(#button.scripts.OnShow, 1)
    button:Fire("OnShow")
    equal(button.HotKey:GetText(), "Late")
end)

test("leaves secret native text untouched and reports the restriction", function()
    local secret = { secret = true }
    local button = mockButton("ActionButton1", secret)
    local _, addon, _, messages = ready({
        bindings = { ACTIONBUTTON1 = { "F" } },
        setup = function(env)
            env.MainActionBar = { actionButtons = { button } }
        end,
    })
    assert(addon.SetLabel(addon.Bars[1], 1, "Custom"))
    equal(button.HotKey:GetText(), secret)
    assert(messages[1]:find("restricted this key label", 1, true))
    addon.RefreshActionLabels()
    equal(#messages, 1)
    button.HotKey:SetText("F")
    equal(button.HotKey:GetText(), "Custom")
end)

test("releases the reentrancy guard after a rejected native write", function()
    local button = mockButton("ActionButton1", "F")
    local _, addon = ready({
        bindings = { ACTIONBUTTON1 = { "F" } },
        setup = function(env)
            env.MainActionBar = { actionButtons = { button } }
        end,
    })
    button.HotKey.rejectWrite = true
    local success = pcall(addon.SetLabel, addon.Bars[1], 1, "Custom")
    equal(success, false)
    button.HotKey.rejectWrite = false
    addon.RefreshActionLabels()
    equal(button.HotKey:GetText(), "Custom")
    button.HotKey:SetText("Latest")
    assert(addon.ResetLabels())
    equal(button.HotKey:GetText(), "Latest")
end)

test("committed rebinding restores the new native hotkey", function()
    local button = mockButton("ActionButton1", "F")
    local _, addon, _, _, game = ready({
        bindings = { ACTIONBUTTON1 = { "F" } },
        setup = function(env)
            env.MainActionBar = { actionButtons = { button } }
        end,
    })
    assert(addon.SetLabel(addon.Bars[1], 1, "Old binding"))
    game.SetKeys("ACTIONBUTTON1", { "G" })
    button.HotKey:SetText("G")
    equal(button.HotKey:GetText(), "Old binding")
    game.Save()
    game.Flush()
    equal(addon.GetLabel(addon.Bars[1], 1), nil)
    equal(button.HotKey:GetText(), "G")
end)

test("dormant display activates on first binding and restores when unbound", function()
    local button = mockButton("ActionButton1", "*", false)
    local _, addon, _, _, game = ready({
        setup = function(env)
            env.MainActionBar = { actionButtons = { button } }
        end,
    })
    assert(addon.SetLabel(addon.Bars[1], 1, "Prepared"))
    equal(button.HotKey:GetText(), "*")
    game.SetKeys("ACTIONBUTTON1", { "F" })
    button.HotKey:SetText("F")
    button.HotKey.shown = true
    game.Save()
    game.Flush()
    equal(button.HotKey:GetText(), "Prepared")
    equal(button.HotKey.shown, true)
    game.SetKeys("ACTIONBUTTON1", {})
    button.HotKey:SetText("*")
    button.HotKey.shown = false
    game.Save()
    game.Flush()
    equal(button.HotKey:GetText(), "*")
    equal(button.HotKey.shown, false)
end)

test("combat refreshes preserve display while configuration stays locked", function()
    local button = mockButton("ActionButton1", "F")
    local _, addon, _, _, game = ready({
        bindings = { ACTIONBUTTON1 = { "F" } },
        setup = function(env)
            env.MainActionBar = { actionButtons = { button } }
        end,
    })
    assert(addon.SetLabel(addon.Bars[1], 1, "Custom"))
    game.combat = true
    button.HotKey:SetText("F")
    equal(button.HotKey:GetText(), "Custom")
    equal(addon.SetLabel(addon.Bars[1], 1, "Changed"), false)
    equal(addon.ResetLabels(), false)
    equal(button.HotKey:GetText(), "Custom")
    game.combat = false
    assert(addon.ResetLabels())
    equal(button.HotKey:GetText(), "F")
end)

test("forbidden action buttons are never hooked or rewritten", function()
    local button = mockButton("ActionButton1", "F")
    button.forbidden = true
    local _, addon, _, messages = ready({
        bindings = { ACTIONBUTTON1 = { "F" } },
        setup = function(env)
            env.MainActionBar = { actionButtons = { button } }
        end,
    })
    assert(addon.SetLabel(addon.Bars[1], 1, "Custom"))
    equal(button.HotKey:GetText(), "F")
    equal(button.HotKey.writes, 0)
    equal(next(button.scripts), nil)
    equal(#messages, 1)
end)

test("character profiles start empty and inherit enabled only once", function()
    local env, addon, _, _, game = ready()
    assert(addon.SetLabel(addon.Bars[1], 1, "Account"))
    assert(addon.SetEnabled(false))
    equal(env.CleanBindsCharacterDB, nil)
    game.Switch(2)
    equal(addon.db, env.CleanBindsCharacterDB)
    equal(addon.db.enabled, false)
    equal(next(addon.db.overrides), nil)
    equal(next(addon.db.bindingSnapshots), nil)
    assert(addon.SetLabel(addon.Bars[1], 1, "Character"))
    assert(addon.SetEnabled(true))
    game.Switch(1)
    equal(addon.db, env.CleanBindsDB)
    equal(addon.IsEnabled(), false)
    equal(addon.GetLabel(addon.Bars[1], 1), "Account")
    game.Switch(2)
    equal(addon.IsEnabled(), true)
    equal(addon.GetLabel(addon.Bars[1], 1), "Character")
    assert(env.CleanBindsDB.overrides ~= env.CleanBindsCharacterDB.overrides)
    assert(env.CleanBindsDB.bindingSnapshots ~= env.CleanBindsCharacterDB.bindingSnapshots)
end)

test("an empty reset character profile is never reseeded", function()
    local env, addon, _, _, game = ready()
    assert(addon.SetLabel(addon.Bars[1], 1, "Shared"))
    game.Switch(2)
    assert(addon.SetEnabled(false))
    assert(addon.SetLabel(addon.Bars[1], 1, "Local"))
    assert(addon.ResetLabels())
    game.Switch(1)
    assert(addon.SetEnabled(true))
    game.Switch(2)
    equal(addon.IsEnabled(), false)
    equal(addon.GetLabel(addon.Bars[1], 1), nil)
    equal(env.CleanBindsDB.overrides["actionbar1:1"], "Shared")
    equal(next(env.CleanBindsCharacterDB.bindingSnapshots), nil)
end)

test("startup directly in character scope uses only its native saved table", function()
    local account = { schemaVersion = 1, enabled = false, overrides = {}, bindingSnapshots = {} }
    local env, addon = ready({ database = account, bindingSet = 2 })
    equal(addon.db, env.CleanBindsCharacterDB)
    equal(addon.IsEnabled(), false)
    assert(addon.SetLabel(addon.Bars[9], 1, "Pet"))
    equal(next(account.overrides), nil)
end)

test("two characters share account data but retain independent profiles", function()
    local envA, addonA, _, _, gameA = ready()
    assert(addonA.SetLabel(addonA.Bars[1], 1, "Shared"))
    gameA.Switch(2)
    assert(addonA.SetLabel(addonA.Bars[1], 1, "Character A"))
    assert(addonA.SetEnabled(false))

    local envB, addonB, _, _, gameB = ready({ database = snapshotDatabase(envA.CleanBindsDB) })
    equal(addonB.GetLabel(addonB.Bars[1], 1), "Shared")
    equal(envB.CleanBindsCharacterDB, nil)
    gameB.Switch(2)
    equal(addonB.GetLabel(addonB.Bars[1], 1), nil)
    assert(addonB.SetLabel(addonB.Bars[1], 1, "Character B"))
    local _, restored = ready({
        database = snapshotDatabase(envB.CleanBindsDB),
        characterDatabase = snapshotDatabase(envA.CleanBindsCharacterDB),
        bindingSet = 2,
    })
    equal(restored.GetLabel(restored.Bars[1], 1), "Character A")
    equal(restored.IsEnabled(), false)
    equal(envB.CleanBindsCharacterDB.overrides["actionbar1:1"], "Character B")
end)

test("the load-save gap cannot write to the outgoing profile", function()
    local env, addon, _, _, game = ready({ bindings = { ACTIONBUTTON1 = { "F" } } })
    assert(addon.SetLabel(addon.Bars[1], 1, "Account"))
    local token = addon.GetScopeToken()
    game.Load(2, { ACTIONBUTTON1 = { "G" } })
    equal(game.bindingSet, 1)
    equal(addon.CanEdit(), false)
    equal(addon.IsEnabled(), false)
    equal(addon.GetScopeNotice(), addon.L.SCOPE_LOADING)
    equal(addon.SetLabel(addon.Bars[1], 1, "Wrong", token), false)
    equal(addon.ResetLabels(nil, token), false)
    equal(addon.SetEnabled(false, token), false)
    equal(env.CleanBindsDB.overrides["actionbar1:1"], "Account")
    equal(env.CleanBindsCharacterDB, nil)
    game.Save(2)
    game.Flush()
    equal(addon.GetScopeNotice(), addon.L.CHARACTER_NOTICE)
    equal(next(addon.db.overrides), nil)
    equal(env.CleanBindsDB.overrides["actionbar1:1"], "Account")
end)

test("canceled scope loads retain both profile data and the saved scope", function()
    local env, addon, _, _, game = ready({ bindings = { ACTIONBUTTON1 = { "F" } } })
    assert(addon.SetLabel(addon.Bars[1], 1, "Account"))
    game.Load(2, { ACTIONBUTTON1 = { "G" } })
    game.Load(1, { ACTIONBUTTON1 = { "F" } })
    game.Flush()
    equal(addon.db, env.CleanBindsDB)
    equal(addon.GetLabel(addon.Bars[1], 1), "Account")
    equal(env.CleanBindsCharacterDB, nil)
end)

test("saving outgoing edits does not compare them against incoming bindings", function()
    local env, addon, _, _, game = ready({
        bindings = { ACTIONBUTTON1 = { "F" } },
        savedBindings = { [2] = { ACTIONBUTTON1 = { "H" } } },
    })
    assert(addon.SetLabel(addon.Bars[1], 1, "Old"))
    game.SetKeys("ACTIONBUTTON1", { "G" })
    game.Switch(2)
    equal(env.CleanBindsDB.overrides["actionbar1:1"], nil)
    equal(next(env.CleanBindsCharacterDB.overrides), nil)
    equal(game.bindings.ACTIONBUTTON1[1], "H")
end)

test("stale labels are cleared within their profile after an offline change", function()
    local env, addon = ready({
        bindings = { ACTIONBUTTON1 = { "F" }, ACTIONBUTTON2 = { "G", "H" } },
    })
    assert(addon.SetLabel(addon.Bars[1], 1, "Stale"))
    assert(addon.SetLabel(addon.Bars[1], 2, "Keep"))
    local _, restored, _, messages = ready({
        database = snapshotDatabase(env.CleanBindsDB),
        bindings = { ACTIONBUTTON1 = { "J" }, ACTIONBUTTON2 = { "G", "K" } },
    })
    equal(restored.GetLabel(restored.Bars[1], 1), nil)
    equal(restored.db.bindingSnapshots["actionbar1:1"], nil)
    equal(restored.GetLabel(restored.Bars[1], 2), "Keep")
    equal(#messages, 1)
    assert(messages[1]:find(restored.L.ACCOUNT_SCOPE, 1, true))
end)

test("returning to character scope clears only changed character labels", function()
    local env, addon, _, _, game = ready({ bindings = { ACTIONBUTTON1 = { "F" } } })
    assert(addon.SetLabel(addon.Bars[1], 1, "Account"))
    game.Switch(2)
    assert(addon.SetLabel(addon.Bars[1], 1, "Character"))
    game.Switch(1)
    game.savedBindings[2] = { ACTIONBUTTON1 = { "G" } }
    game.Switch(2)
    equal(addon.GetLabel(addon.Bars[1], 1), nil)
    equal(env.CleanBindsDB.overrides["actionbar1:1"], "Account")
    equal(env.CleanBindsCharacterDB.bindingSnapshots["actionbar1:1"], nil)
end)

test("canonical snapshots ignore display-only input preference changes after restart", function()
    local env, addon = ready({ bindings = { ACTIONBUTTON1 = { "F", "PAD1" } } })
    assert(addon.SetLabel(addon.Bars[1], 1, "Keep"))
    local _, restored = ready({
        database = snapshotDatabase(env.CleanBindsDB),
        bindings = { ACTIONBUTTON1 = { "F", "PAD1" } },
        setup = function(_, game)
            game.displayedBindings = { ACTIONBUTTON1 = { "PAD1", "F" } }
        end,
    })
    equal(restored.GetLabel(restored.Bars[1], 1), "Keep")
    equal(restored.db.bindingSnapshots["actionbar1:1"].device, "gamepad")
end)

test("an offline swap of primary and secondary keyboard keys invalidates the label", function()
    local env, addon = ready({ bindings = { ACTIONBUTTON1 = { "F", "G" } } })
    assert(addon.SetLabel(addon.Bars[1], 1, "First"))
    local _, restored = ready({
        database = snapshotDatabase(env.CleanBindsDB),
        bindings = { ACTIONBUTTON1 = { "G", "F" } },
    })
    equal(restored.GetLabel(restored.Bars[1], 1), nil)
end)

test("click fallback snapshots remain valid when their frame is temporarily absent", function()
    local env, addon = ready({ bindings = { ["CLICK ActionButton1:LeftButton"] = { "F" } } })
    assert(addon.SetLabel(addon.Bars[1], 1, "Fallback"))
    local _, restored = ready({
        database = snapshotDatabase(env.CleanBindsDB),
        bindings = { ["CLICK ActionButton1:LeftButton"] = { "F" } },
    })
    equal(restored.GetLabel(restored.Bars[1], 1), "Fallback")
end)

test("missing canonical bindings cannot delete data or accept misleading metadata", function()
    local env, addon, _, _, game = ready({ bindings = { ACTIONBUTTON1 = { "F" } } })
    assert(addon.SetLabel(addon.Bars[1], 1, "Keep"))
    game.unavailableBinding = "ACTIONBUTTON1"
    local success, reason = addon.SetLabel(addon.Bars[1], 1, "New")
    equal(success, false)
    equal(reason, addon.L.BINDING_UNAVAILABLE)
    game.Save()
    equal(env.CleanBindsDB.overrides["actionbar1:1"], "Keep")
    equal(env.CleanBindsDB.bindingSnapshots["actionbar1:1"].keyboard, "F")
end)

test("invalid binding metadata is preserved without applying the label", function()
    local saved = {
        schemaVersion = 1, enabled = true,
        overrides = { ["actionbar1:1"] = "Missing", ["actionbar1:2"] = "Bad" },
        bindingSnapshots = { ["actionbar1:2"] = { device = "keyboard" } },
    }
    local _, addon, _, messages = ready({ database = saved })
    equal(addon.GetLabel(addon.Bars[1], 1), nil)
    equal(addon.GetLabel(addon.Bars[1], 2), nil)
    equal(saved.overrides["actionbar1:1"], "Missing")
    equal(saved.overrides["actionbar1:2"], "Bad")
    assert(messages[1]:find("2 invalid", 1, true))
end)

test("an invalid character profile never falls back to account labels", function()
    local env, addon, _, messages, game = ready({ characterDatabase = { schemaVersion = 99 } })
    assert(addon.SetLabel(addon.Bars[1], 1, "Account"))
    game.Switch(2)
    equal(addon.db, nil)
    equal(addon.CanEdit(), false)
    equal(addon.GetLabel(addon.Bars[1], 1), nil)
    equal(env.CleanBindsCharacterDB.schemaVersion, 99)
    equal(env.CleanBindsDB.overrides["actionbar1:1"], "Account")
    assert(messages[#messages]:find("unsupported schema", 1, true))
    game.Switch(1)
    equal(addon.GetLabel(addon.Bars[1], 1), "Account")
end)

test("an unknown scope is reported without creating or resetting saved data", function()
    local env, addon, fire, messages = loadAddon({ loggedIn = true, bindingSet = 99 })
    fire("ADDON_LOADED", "CleanBinds")
    equal(addon.state, "failed")
    equal(env.CleanBindsDB, nil)
    equal(env.CleanBindsCharacterDB, nil)
    assert(messages[1]:find("scope 99", 1, true))
end)

test("profile switches cancel drafts and update the native enable proxy without writes", function()
    local env, addon, _, pages, messages, game = readySettings()
    local page = pages[2]
    page:Show()
    game.enabledSetting:SetValue(false)
    assert(addon.SetLabel(page.bar, 1, "Shared"))
    page.rows[1].Override:OnClick()
    page.rows[1].Editor:SetText("Wrong scope")
    game.Switch(2)
    equal(page.editingRow, nil)
    equal(env.CleanBindsDB.overrides["actionbar2:1"], "Shared")
    equal(next(env.CleanBindsCharacterDB.overrides), nil)
    equal(game.enabledSetting:GetValue(), false)
    equal(page.Description:GetText(), addon.L.CHARACTER_NOTICE)
    assert(game.description():find(addon.L.CHARACTER_NOTICE, 1, true))
    equal(game.enabledSetting.writes, 1)
    assert(messages[1]:find(addon.L.SCOPE_CHANGED, 1, true))
    game.enabledSetting:SetValue(true)
    game.Switch(1)
    equal(game.enabledSetting:GetValue(), false)
    equal(game.enabledSetting.writes, 2)
    equal(page.Description:GetText(), addon.L.ACCOUNT_NOTICE)
end)

test("stale reset tokens cannot clear a new or revisited scope", function()
    local _, addon, _, pages, _, game = readySettings()
    local page = pages[1]
    page:Show()
    assert(addon.SetLabel(page.bar, 1, "Account"))
    local token = addon.GetScopeToken()
    game.Switch(2)
    assert(addon.SetLabel(page.bar, 1, "Character"))
    equal(addon.ResetLabels(page.bar.id, token), false)
    equal(addon.GetLabel(page.bar, 1), "Character")
    game.Switch(1)
    equal(addon.ResetLabels(page.bar.id, token), false)
    equal(addon.GetLabel(page.bar, 1), "Account")
end)

test("scoped resets remove matching snapshots without touching the other setup", function()
    local env, addon, _, _, game = ready()
    assert(addon.SetLabel(addon.Bars[1], 1, "Account"))
    game.Switch(2)
    assert(addon.SetLabel(addon.Bars[1], 1, "First"))
    assert(addon.SetLabel(addon.Bars[2], 1, "Second"))
    assert(addon.SetEnabled(false))
    assert(addon.ResetLabels("actionbar1"))
    equal(addon.db.bindingSnapshots["actionbar1:1"], nil)
    equal(addon.GetLabel(addon.Bars[2], 1), "Second")
    assert(addon.ResetLabels())
    equal(next(addon.db.overrides), nil)
    equal(next(addon.db.bindingSnapshots), nil)
    equal(addon.IsEnabled(), false)
    equal(env.CleanBindsDB.overrides["actionbar1:1"], "Account")
end)

test("switching profiles restores native text and reuses the existing rendering hooks", function()
    local button = mockButton("ActionButton1", "F")
    local _, addon, _, _, game = ready({
        bindings = { ACTIONBUTTON1 = { "F" } },
        setup = function(env)
            env.MainActionBar = { actionButtons = { button } }
        end,
    })
    assert(addon.SetLabel(addon.Bars[1], 1, "Account"))
    equal(button.HotKey:GetText(), "Account")
    game.Switch(2)
    equal(button.HotKey:GetText(), "F")
    assert(addon.SetLabel(addon.Bars[1], 1, "Character"))
    equal(button.HotKey:GetText(), "Character")
    assert(addon.SetEnabled(false))
    equal(button.HotKey:GetText(), "F")
    game.Switch(1)
    equal(button.HotKey:GetText(), "Account")
    game.Switch(2)
    equal(button.HotKey:GetText(), "F")
    equal(#button.scripts.OnShow, 1)
end)

test("new keyboard binding replacing a gamepad display is a real binding change", function()
    local _, addon, _, _, game = ready({ bindings = { ACTIONBUTTON1 = { "PAD1" } } })
    assert(addon.SetLabel(addon.Bars[1], 1, "Pad"))
    game.SetKeys("ACTIONBUTTON1", { "F", "PAD1" })
    game.Save()
    equal(addon.GetLabel(addon.Bars[1], 1), nil)
end)

test("temporarily unavailable binding snapshots recover after their definitions load", function()
    local saved = {
        schemaVersion = 1, enabled = true, overrides = { ["actionbar1:1"] = "Keep" },
        bindingSnapshots = { ["actionbar1:1"] = bindingSnapshot("ACTIONBUTTON1", "F") },
    }
    local _, addon, fire, _, game = ready({
        database = saved,
        bindings = { ACTIONBUTTON1 = { "F" } },
        setup = function(_, state)
            state.unavailableBinding = "ACTIONBUTTON1"
        end,
    })
    equal(addon.GetLabel(addon.Bars[1], 1), nil)
    equal(saved.overrides["actionbar1:1"], "Keep")
    game.unavailableBinding = nil
    fire("ADDON_LOADED", "Blizzard_ActionBar")
    equal(addon.GetLabel(addon.Bars[1], 1), "Keep")
end)

test("unknown binding-scope saves cannot mutate the previous profile", function()
    local env, addon, _, _, game = ready()
    assert(addon.SetLabel(addon.Bars[1], 1, "Account"))
    game.Save(99)
    equal(addon.IsEnabled(), false)
    equal(addon.CanEdit(), false)
    equal(addon.db, nil)
    equal(env.CleanBindsDB.overrides["actionbar1:1"], "Account")
    game.Load(1)
    game.Save(1)
    equal(addon.GetLabel(addon.Bars[1], 1), "Account")
end)

test("initializing an existing character profile does not read an invalid inactive account profile", function()
    local account = { schemaVersion = 99 }
    local character = {
        schemaVersion = 1, enabled = true, overrides = { ["stance:1"] = "Form" },
        bindingSnapshots = { ["stance:1"] = bindingSnapshot("SHAPESHIFTBUTTON1") },
    }
    local env, addon = ready({ bindingSet = 2, database = account, characterDatabase = character })
    equal(addon.db, character)
    equal(addon.GetLabel(addon.Bars[10], 1), "Form")
    equal(env.CleanBindsDB, account)
end)

test("leaving either character setup restores native text when account labels are empty", function()
    for _, customLabel in ipairs({ "CHAR", "PAL" }) do
        local button = mockButton("ActionButton1", "Q")
        local character = {
            schemaVersion = 1, enabled = true,
            overrides = { ["actionbar1:1"] = customLabel },
            bindingSnapshots = { ["actionbar1:1"] = bindingSnapshot("ACTIONBUTTON1", "Q") },
        }
        local env, addon, _, _, game = ready({
            bindingSet = 2,
            characterDatabase = character,
            bindings = { ACTIONBUTTON1 = { "Q" } },
            savedBindings = { [1] = { ACTIONBUTTON1 = { "Q" } } },
            setup = function(environment)
                environment.MainActionBar = { actionButtons = { button } }
            end,
        })
        equal(button.HotKey:GetText(), customLabel)
        game.Switch(1)
        equal(addon.GetLabel(addon.Bars[1], 1), nil)
        equal(button.HotKey:GetText(), "Q")
        equal(env.CleanBindsCharacterDB.overrides["actionbar1:1"], customLabel)
        equal(next(env.CleanBindsDB.overrides), nil)
        game.Switch(2)
        equal(button.HotKey:GetText(), customLabel)
    end
end)

test("deferred startup restores action labels and installs scope hooks only once", function()
    local button = mockButton("ActionButton1", "F")
    local account = {
        schemaVersion = 1, enabled = true,
        overrides = { ["actionbar1:1"] = "Shared" },
        bindingSnapshots = { ["actionbar1:1"] = bindingSnapshot("ACTIONBUTTON1", "F") },
    }
    local env, addon, fire, _, game = loadAddon({
        loggedIn = true, bindingSet = 0, database = account,
        setup = function(environment)
            environment.MainActionBar = { actionButtons = { button } }
        end,
    })
    fire("ADDON_LOADED", "CleanBinds")
    game.Flush()
    equal(addon.state, "waiting_bindings")
    equal(button.HotKey:GetText(), "F")
    equal(button.HotKey.writes, 0)
    equal(button.scripts.OnShow, nil)
    equal(account.overrides["actionbar1:1"], "Shared")

    fire("BINDINGS_LOADED")
    fire("UPDATE_BINDINGS")
    fire("PLAYER_ENTERING_WORLD")
    game.bindingSet = 1
    game.bindings = { ACTIONBUTTON1 = { "F" } }
    game.Flush()
    equal(addon.state, "ready")
    equal(button.HotKey:GetText(), "Shared")
    equal(#button.scripts.OnShow, 1)

    game.Switch(2)
    equal(button.HotKey:GetText(), "F")
    assert(addon.SetLabel(addon.Bars[1], 1, "Local"))
    equal(button.HotKey:GetText(), "Local")
    game.Switch(1)
    game.Flush()
    equal(button.HotKey:GetText(), "Shared")
    equal(env.CleanBindsCharacterDB.overrides["actionbar1:1"], "Local")
    equal(#button.scripts.OnShow, 1)
end)

test("deferred startup reconciles changed bindings only after the scope is known", function()
    local account = {
        schemaVersion = 1, enabled = true,
        overrides = { ["actionbar1:1"] = "Old" },
        bindingSnapshots = { ["actionbar1:1"] = bindingSnapshot("ACTIONBUTTON1", "F") },
    }
    local character = {
        schemaVersion = 1, enabled = true,
        overrides = { ["actionbar1:1"] = "Local" },
        bindingSnapshots = { ["actionbar1:1"] = bindingSnapshot("ACTIONBUTTON1", "G") },
    }
    local _, addon, fire, messages, game = loadAddon({
        loggedIn = true, bindingSet = 0, database = account, characterDatabase = character,
    })
    fire("ADDON_LOADED", "CleanBinds")
    game.Flush()
    equal(account.overrides["actionbar1:1"], "Old")
    equal(account.bindingSnapshots["actionbar1:1"].keyboard, "F")

    game.bindingSet = 1
    game.bindings = { ACTIONBUTTON1 = { "H" } }
    fire("UPDATE_BINDINGS")
    game.Flush()
    equal(addon.state, "ready")
    equal(account.overrides["actionbar1:1"], nil)
    equal(account.bindingSnapshots["actionbar1:1"], nil)
    equal(character.overrides["actionbar1:1"], "Local")
    equal(character.bindingSnapshots["actionbar1:1"].keyboard, "G")
    equal(#messages, 2)
    assert(messages[2]:find("displayed binding changed", 1, true))
end)

local function macroProfile(hidden)
    return {
        schemaVersion = 1,
        enabled = true,
        hideMacroNames = hidden,
        overrides = {},
        bindingSnapshots = {},
    }
end

local function mockMacroButton(name, action, text)
    local button = mockButton(name, "F")
    button.action = action
    button.Name = mockButton(name .. "Name", text).HotKey
    button.Name.alphaWrites = 0
    function button.Name:GetAlpha()
        return self.alpha
    end
    function button.Name:SetAlpha(value)
        if self.rejectAlpha then
            error("Rejected alpha write")
        end
        self.alpha = value
        self.alphaWrites = self.alphaWrites + 1
    end
    return button
end

test("macro names are visible for fresh and existing profiles without migrating their data", function()
    local _, fresh = ready()
    equal(fresh.db.hideMacroNames, false)
    equal(fresh.ShouldHideMacroNames(), false)
    for _, scope in ipairs({ 1, 2 }) do
        local saved = macroProfile()
        saved.overrides["actionbar1:1"] = "Keep"
        saved.bindingSnapshots["actionbar1:1"] = bindingSnapshot("ACTIONBUTTON1", "F")
        local account = scope == 1 and saved or macroProfile(true)
        local _, addon = ready({
            bindingSet = scope, database = account, characterDatabase = scope == 2 and saved or nil,
            bindings = { ACTIONBUTTON1 = { "F" } },
        })
        equal(addon.db, saved)
        equal(addon.ShouldHideMacroNames(), false)
        equal(saved.hideMacroNames, nil)
        equal(saved.schemaVersion, 1)
        equal(saved.overrides["actionbar1:1"], "Keep")
        equal(saved.bindingSnapshots["actionbar1:1"].keyboard, "F")
    end
end)

test("invalid macro visibility settings are rejected without replacing profiles", function()
    for _, value in ipairs({ "false", 0, {} }) do
        for _, scope in ipairs({ 1, 2 }) do
            local saved = macroProfile(value)
            local env, addon, fire, messages = loadAddon({
                loggedIn = true, bindingSet = scope,
                database = scope == 1 and saved or nil,
                characterDatabase = scope == 2 and saved or nil,
            })
            fire("ADDON_LOADED", "CleanBinds")
            equal(addon.state, "failed")
            equal(scope == 1 and env.CleanBindsDB or env.CleanBindsCharacterDB, saved)
            equal(saved.hideMacroNames, value)
            assert(messages[1]:find("hideMacroNames must be a boolean", 1, true))
        end
    end
end)

test("new character setups inherit macro visibility once and keep independent choices", function()
    local env, addon, _, _, game = ready()
    assert(addon.SetHideMacroNames(true))
    game.Switch(2)
    equal(env.CleanBindsCharacterDB.hideMacroNames, true)
    assert(addon.SetHideMacroNames(false))
    game.Switch(1)
    equal(addon.ShouldHideMacroNames(), true)
    game.Switch(2)
    equal(addon.ShouldHideMacroNames(), false)
    game.Switch(1)
    local _, another, _, _, anotherGame = ready({ database = snapshotDatabase(env.CleanBindsDB) })
    equal(another.ShouldHideMacroNames(), true)
    anotherGame.Switch(2)
    equal(another.ShouldHideMacroNames(), true)
    local _, restored = ready({
        database = snapshotDatabase(env.CleanBindsDB),
        characterDatabase = snapshotDatabase(env.CleanBindsCharacterDB), bindingSet = 2,
    })
    equal(restored.ShouldHideMacroNames(), false)
end)

test("macro visibility setters respect combat, pending scopes, stale tokens, and invalid input", function()
    local env, addon, _, _, game = ready()
    assert(addon.SetHideMacroNames(true))
    local token = addon.GetScopeToken()
    for _, invalid in ipairs({ "true", 1, {} }) do
        local success, reason = addon.SetHideMacroNames(invalid)
        equal(success, false)
        assert(reason:find("hideMacroNames must be a boolean", 1, true))
        equal(env.CleanBindsDB.hideMacroNames, true)
    end
    game.combat = true
    local success, reason = addon.SetHideMacroNames(false)
    equal(success, false)
    equal(reason, addon.L.COMBAT_READ_ONLY)
    game.combat = false
    game.Load(2)
    equal(addon.SetHideMacroNames(false), false)
    equal(addon.ShouldHideMacroNames(), false)
    equal(env.CleanBindsDB.hideMacroNames, true)
    equal(env.CleanBindsCharacterDB, nil)
    game.Save(2)
    equal(addon.SetHideMacroNames(false, token), false)
    equal(env.CleanBindsCharacterDB.hideMacroNames, true)
    game.Save(99)
    equal(addon.ShouldHideMacroNames(), false)
    equal(addon.SetHideMacroNames(false), false)
    equal(env.CleanBindsDB.hideMacroNames, true)
    equal(env.CleanBindsCharacterDB.hideMacroNames, true)
end)

test("label resets and custom-label enable changes leave macro visibility alone", function()
    local _, addon = ready()
    assert(addon.SetHideMacroNames(true))
    assert(addon.SetLabel(addon.Bars[1], 1, "Custom"))
    assert(addon.SetEnabled(false))
    equal(addon.ShouldHideMacroNames(), true)
    assert(addon.ResetLabels("actionbar1"))
    equal(addon.ShouldHideMacroNames(), true)
    assert(addon.ResetLabels())
    equal(addon.ShouldHideMacroNames(), true)
    assert(addon.SetHideMacroNames(false))
    equal(addon.IsEnabled(), false)
end)

test("the macro-name checkbox follows the active scope without writing during refresh", function()
    local env, addon, _, _, _, game = readySettings()
    local setting = game.hideMacroNamesSetting
    local checkbox = game.checkboxes.CLEANBINDS_HIDE_MACRO_NAMES
    equal(setting:GetValue(), false)
    equal(checkbox.canModify(), true)
    setting:SetValue(true)
    equal(env.CleanBindsDB.hideMacroNames, true)
    game.Switch(2)
    equal(setting.displayedValue, true)
    setting:SetValue(false)
    game.Switch(1)
    equal(setting.displayedValue, true)
    game.Switch(2)
    equal(setting.displayedValue, false)
    equal(setting.writes, 2)
    equal(game.enabledSetting.writes, 0)
    game.combat = true
    equal(checkbox.canModify(), false)
    game.combat = false
    game.Load(1)
    equal(checkbox.canModify(), false)
    game.Save(1)
    equal(checkbox.canModify(), true)
    equal(setting.displayedValue, true)
    equal(setting.writes, 2)
end)

test("hiding macro names changes only their visibility, not text or keybinding labels", function()
    local button = mockMacroButton("ActionButton1", 1, "Long macro name")
    button.Count = { text = "3" }
    button.cooldown = { text = "5" }
    local _, addon = ready({
        bindings = { ACTIONBUTTON1 = { "F" } }, actions = { [1] = "macro" },
        setup = function(env)
            env.MainActionBar = { actionButtons = { button } }
        end,
    })
    equal(button.Name.alpha, 0.8)
    equal(button.Name.alphaWrites, 0)
    assert(addon.SetLabel(addon.Bars[1], 1, "Key"))
    assert(addon.SetHideMacroNames(true))
    equal(button.Name.alpha, 0)
    equal(button.Name:GetText(), "Long macro name")
    equal(button.Name.writes, 0)
    equal(button.HotKey:GetText(), "Key")
    equal(button.Count.text, "3")
    equal(button.cooldown.text, "5")
    assert(addon.SetEnabled(false))
    equal(button.Name.alpha, 0)
    equal(button.HotKey:GetText(), "F")
    assert(addon.SetHideMacroNames(false))
    equal(button.Name.alpha, 0.8)
    equal(button.Name:GetText(), "Long macro name")
end)

test("macro visibility covers all normal bars but leaves non-macros and special bars alone", function()
    local env, addon, fire, _, game = loadAddon({ loggedIn = true })
    local buttons = {}
    for number, bar in ipairs(addon.Bars) do
        local macro = mockMacroButton(bar.buttonNamePrefix .. "1", number * 2, "Macro")
        local spell = mockMacroButton(bar.buttonNamePrefix .. "2", number * 2 + 1, "Other text")
        game.actions[number * 2] = "macro"
        game.actions[number * 2 + 1] = "spell"
        env[bar.frameName] = { actionButtons = { macro, spell } }
        buttons[number] = { macro, spell }
    end
    local override = mockMacroButton("OverrideActionBarButton1", 100, "Vehicle")
    game.actions[100] = "spell"
    env.OverrideActionBar = { actionButtons = { override } }
    fire("ADDON_LOADED", "CleanBinds")
    assert(addon.SetHideMacroNames(true))
    for number, pair in ipairs(buttons) do
        equal(pair[1].Name.alpha, number <= 8 and 0 or 0.8)
        equal(pair[2].Name.alpha, 0.8)
        equal(pair[1].Name.writes, 0)
    end
    equal(override.Name.alpha, 0.8)
    game.actions[100] = "macro"
    override.Name:SetText("Macro on override bar")
    equal(override.Name.alpha, 0)
end)

test("macro hiding survives native renames and alpha updates and restores the latest values", function()
    local button = mockMacroButton("ActionButton1", 1, "Original")
    local _, addon, fire, _, game = ready({
        actions = { [1] = "macro" },
        setup = function(env)
            env.MainActionBar = { actionButtons = { button } }
        end,
    })
    assert(addon.SetHideMacroNames(true))
    button.Name:SetText("Renamed")
    button.Name:SetAlpha(0.4)
    fire("UPDATE_MACROS")
    game.Flush()
    equal(button.Name.alpha, 0)
    equal(button.Name:GetText(), "Renamed")
    equal(button.Name.writes, 1)
    local writes = button.Name.alphaWrites
    addon.RefreshActionLabels()
    addon.RefreshActionLabels()
    equal(button.Name.alphaWrites, writes)
    assert(addon.SetHideMacroNames(false))
    equal(button.Name.alpha, 0.4)
    equal(button.Name:GetText(), "Renamed")
end)

test("action swaps and bar paging hide only the macro currently on the button", function()
    local button = mockMacroButton("ActionButton1", 1, "Macro")
    local _, addon, fire, _, game = ready({
        actions = { [1] = "macro", [2] = "item", [3] = "macro" },
        setup = function(env)
            env.MainActionBar = { actionButtons = { button } }
        end,
    })
    assert(addon.SetHideMacroNames(true))
    for _, event in ipairs({ "ACTIONBAR_SLOT_CHANGED", "ACTIONBAR_PAGE_CHANGED", "UPDATE_BONUS_ACTIONBAR" }) do
        button.action = 2
        fire(event)
        game.Flush()
        equal(button.Name.alpha, 0.8)
        button.action = 3
        fire(event)
        game.Flush()
        equal(button.Name.alpha, 0)
    end
    button.action = nil
    button.Name:SetText("")
    equal(button.Name.alpha, 0.8)
    equal(button.Name:GetText(), "")
end)

test("macro visibility restores during scope changes and resumes with the selected preference", function()
    local button = mockMacroButton("ActionButton1", 1, "Macro")
    local env, addon, _, _, game = ready({
        database = macroProfile(true), characterDatabase = macroProfile(false),
        actions = { [1] = "macro" },
        setup = function(environment)
            environment.MainActionBar = { actionButtons = { button } }
        end,
    })
    equal(button.Name.alpha, 0)
    game.Load(2)
    equal(button.Name.alpha, 0.8)
    equal(env.CleanBindsDB.hideMacroNames, true)
    game.Save(2)
    equal(button.Name.alpha, 0.8)
    game.Switch(1)
    equal(button.Name.alpha, 0)
    game.Save(99)
    equal(button.Name.alpha, 0.8)
    game.Switch(1)
    game.Flush()
    equal(button.Name.alpha, 0)
end)

test("combat updates keep hiding macro names while configuration remains locked", function()
    local button = mockMacroButton("ActionButton1", 1, "Macro")
    local _, addon, fire, _, game = ready({
        database = macroProfile(true), actions = { [1] = "macro", [2] = "spell" },
        setup = function(env)
            env.MainActionBar = { actionButtons = { button } }
        end,
    })
    game.combat = true
    button.Name:SetText("Updated")
    equal(button.Name.alpha, 0)
    equal(addon.SetHideMacroNames(false), false)
    button.action = 2
    button.Name:SetText("Spell text")
    equal(button.Name.alpha, 0.8)
    button.action = 1
    button.Name:SetText("Macro")
    equal(button.Name.alpha, 0)
    game.combat = false
    fire("PLAYER_REGEN_ENABLED")
    game.Flush()
    equal(button.Name.alpha, 0)
end)

test("late buttons without hotkey regions still get macro visibility with no duplicate hooks", function()
    local env, addon, fire, _, game = ready({ database = macroProfile(true), actions = { [1] = "macro" } })
    local button = mockMacroButton("ActionButton1", 1, "Macro")
    button.HotKey = nil
    env.MainActionBar = { actionButtons = { button } }
    fire("ADDON_LOADED", "Blizzard_ActionBar")
    game.Flush()
    equal(button.Name.alpha, 0)
    local hooks = #button.scripts.OnShow
    local writes = button.Name.alphaWrites
    addon.RefreshActionLabels()
    button:Fire("OnShow")
    equal(#button.scripts.OnShow, hooks)
    equal(button.Name.alphaWrites, writes)
end)

test("macro hiding never reads or replaces the macro name text", function()
    local secret = { secret = true }
    local button = mockMacroButton("ActionButton1", 1, secret)
    button.Name.GetText = function()
        error("Macro text must not be read")
    end
    local _, addon, _, messages = ready({
        actions = { [1] = "macro" },
        setup = function(env)
            env.MainActionBar = { actionButtons = { button } }
        end,
    })
    assert(addon.SetHideMacroNames(true))
    equal(button.Name.alpha, 0)
    assert(addon.SetHideMacroNames(false))
    equal(button.Name.alpha, 0.8)
    equal(button.Name.text, secret)
    equal(button.Name.writes, 0)
    equal(#messages, 0)
end)

test("showing macro names preserves native hidden and transparent states", function()
    for _, alpha in ipairs({ 0, 0.5 }) do
        local button = mockMacroButton("ActionButton1", 1, "Macro")
        button.Name.shown = false
        button.Name.alpha = alpha
        local _, addon = ready({
            actions = { [1] = "macro" },
            setup = function(env)
                env.MainActionBar = { actionButtons = { button } }
            end,
        })
        assert(addon.SetHideMacroNames(true))
        equal(button.Name.alpha, 0)
        assert(addon.SetHideMacroNames(false))
        equal(button.Name.alpha, alpha)
        equal(button.Name.shown, false)
        equal(button.Name:GetText(), "Macro")
    end
end)

test("unreadable macro-name opacity is preserved until the client supplies a readable value", function()
    local secret = { secret = true }
    local button = mockMacroButton("ActionButton1", 1, "Macro")
    button.Name.alpha = secret
    local _, addon, _, messages = ready({
        database = macroProfile(true), actions = { [1] = "macro" },
        setup = function(env)
            env.MainActionBar = { actionButtons = { button } }
        end,
    })
    equal(button.Name.alpha, secret)
    equal(button.Name.alphaWrites, 0)
    equal(#messages, 1)
    button.Name:SetAlpha(0.6)
    equal(button.Name.alpha, 0)
    assert(addon.SetHideMacroNames(false))
    equal(button.Name.alpha, 0.6)
end)

test("saved macro visibility waits for binding startup before applying to buttons", function()
    local button = mockMacroButton("ActionButton1", 1, "Macro")
    local saved = macroProfile(true)
    local _, addon, fire, _, game = loadAddon({
        loggedIn = true, bindingSet = 0, database = saved, actions = { [1] = "macro" },
        setup = function(env)
            env.MainActionBar = { actionButtons = { button } }
        end,
    })
    fire("ADDON_LOADED", "CleanBinds")
    equal(addon.state, "waiting_bindings")
    equal(addon.ShouldHideMacroNames(), false)
    equal(addon.SetHideMacroNames(false), false)
    equal(saved.hideMacroNames, true)
    equal(button.Name.alpha, 0.8)
    equal(button.Name.alphaWrites, 0)
    game.bindingSet = 1
    game.Flush()
    equal(addon.state, "ready")
    equal(addon.ShouldHideMacroNames(), true)
    equal(button.Name.alpha, 0)
end)

test("forbidden macro regions and buttons are not modified and report restrictions once", function()
    for _, forbiddenButton in ipairs({ false, true }) do
        local button = mockMacroButton("ActionButton1", 1, "Macro")
        if forbiddenButton then
            button.forbidden = true
        else
            button.Name.forbidden = true
        end
        local _, addon, _, messages = ready({
            actions = { [1] = "macro" },
            setup = function(env)
                env.MainActionBar = { actionButtons = { button } }
            end,
        })
        assert(addon.SetHideMacroNames(true))
        addon.RefreshActionLabels()
        equal(button.Name.alpha, 0.8)
        equal(button.Name.alphaWrites, 0)
        equal(#messages, 1)
        assert(messages[1]:find("restricted this macro name", 1, true))
    end
end)

test("unreadable action data restores native name visibility rather than assuming a macro", function()
    local button = mockMacroButton("ActionButton1", 1, "Macro")
    local _, addon, _, messages, game = ready({
        database = macroProfile(true), actions = { [1] = "macro" },
        setup = function(env)
            env.MainActionBar = { actionButtons = { button } }
        end,
    })
    equal(button.Name.alpha, 0)
    button.action = { secret = true }
    addon.RefreshActionLabels()
    equal(button.Name.alpha, 0.8)
    button.action = 1
    game.actions[1] = { secret = true }
    addon.RefreshActionLabels()
    equal(button.Name.alpha, 0.8)
    equal(#messages, 1)
    game.actions[1] = "macro"
    addon.RefreshActionLabels()
    equal(button.Name.alpha, 0)
end)

test("failed macro visibility writes release the recursion guard and remain recoverable", function()
    local button = mockMacroButton("ActionButton1", 1, "Macro")
    local _, addon = ready({
        actions = { [1] = "macro" },
        setup = function(env)
            env.MainActionBar = { actionButtons = { button } }
        end,
    })
    button.Name.rejectAlpha = true
    local success, reason = pcall(addon.SetHideMacroNames, true)
    equal(success, false)
    assert(reason:find("Rejected alpha write", 1, true))
    button.Name.rejectAlpha = false
    addon.RefreshActionLabels()
    equal(button.Name.alpha, 0)
    button.Name:SetAlpha(0.3)
    assert(addon.SetHideMacroNames(false))
    equal(button.Name.alpha, 0.3)
end)

local function fontProfile(size)
    local profile = macroProfile(false)
    profile.keybindFontSize = size
    return profile
end

local function readyFont(size, button)
    button = button or mockButton("ActionButton1", "F")
    local env, addon, fire, messages, game = ready({
        database = fontProfile(size),
        bindings = { ACTIONBUTTON1 = { "F" } },
        setup = function(environment)
            environment.MainActionBar = { actionButtons = { button } }
        end,
    })
    return env, addon, fire, messages, game, button
end

test("choosing the native font size leaves keybind geometry identical to Default", function()
    local _, addon, _, _, _, button = readyFont()
    local hotkey = button.HotKey
    local font, size, flags = hotkey:GetFont()
    local width, height = hotkey:GetSize()
    local point, relative, relativePoint, x, y = hotkey:GetPoint()
    local justifyV = hotkey:GetJustifyV()
    hotkey.SetPoint = function() error("Font sizing must not move the anchor") end
    hotkey.ClearAllPoints = function() error("Font sizing must not clear the anchor") end
    assert(addon.SetKeybindFontSize(size))
    equal(hotkey:GetHeight(), height)
    equal(hotkey:GetWidth(), width)
    equal(hotkey.fontWrites, 0)
    equal(hotkey.heightWrites, 0)
    equal(hotkey:GetJustifyV(), justifyV)
    local actualPoint, actualRelative, actualRelativePoint, actualX, actualY = hotkey:GetPoint()
    equal(actualPoint, point)
    equal(actualRelative, relative)
    equal(actualRelativePoint, relativePoint)
    equal(actualX, x)
    equal(actualY, y)
    assert(addon.SetKeybindFontSize(14))
    assert(addon.SetKeybindFontSize(size))
    equal(hotkey:GetHeight(), height)
    equal(hotkey:GetFont(), font)
    equal(select(3, hotkey:GetFont()), flags)
    assert(addon.SetKeybindFontSize(nil))
    equal(hotkey:GetHeight(), height)
    equal(hotkey:GetJustifyV(), justifyV)
    equal(hotkey.heightWrites, 0)
end)

test("font size defaults preserve native fonts and existing saved data", function()
    local env, addon, _, _, _, button = readyFont()
    equal(addon.GetKeybindFontSize(), nil)
    equal(env.CleanBindsDB.keybindFontSize, nil)
    equal(env.CleanBindsDB.schemaVersion, 1)
    equal(select(2, button.HotKey:GetFont()), 11)
    equal(button.HotKey.fontWrites, 0)
    equal(button.HotKey.heightWrites, 0)
    assert(addon.SetKeybindFontSize(10))
    equal(select(2, button.HotKey:GetFont()), 10)
    assert(addon.SetKeybindFontSize(14))
    equal(select(2, button.HotKey:GetFont()), 14)
    equal(button.HotKey:GetHeight(), 10)
    assert(addon.SetKeybindFontSize(nil))
    equal(select(2, button.HotKey:GetFont()), 11)
    equal(button.HotKey:GetHeight(), 10)
    equal(env.CleanBindsDB.keybindFontSize, nil)
end)

test("font size accepts every whole-number step and rejects out-of-range or invalid values", function()
    local _, addon, _, _, _, button = readyFont()
    for size = 10, 14 do
        assert(addon.SetKeybindFontSize(size))
        equal(addon.GetKeybindFontSize(), size)
        equal(select(2, button.HotKey:GetFont()), size)
        equal(button.HotKey:GetHeight(), 10)
        equal(button.HotKey.heightWrites, 0)
    end
    for _, invalid in ipairs({ 0, 9, 15, 10.5, "12", false, {}, math.huge, 0 / 0 }) do
        local success, reason = addon.SetKeybindFontSize(invalid)
        equal(success, false)
        equal(reason, addon.L.INVALID_FONT_SIZE:format(10, 14))
        equal(addon.GetKeybindFontSize(), 14)
    end
end)

test("invalid saved font sizes fail without replacing the existing profile", function()
    for _, invalid in ipairs({ 0, 9, 15, 10.5, "12", false, {} }) do
        local saved = fontProfile(invalid)
        local env, addon, fire, messages = loadAddon({ loggedIn = true, database = saved })
        fire("ADDON_LOADED", "CleanBinds")
        equal(addon.state, "failed")
        equal(env.CleanBindsDB, saved)
        equal(saved.keybindFontSize, invalid)
        assert(messages[1]:find("whole-number font size", 1, true))
    end
end)

test("new character profiles inherit font size once without changing older character defaults", function()
    local env, addon, _, _, game = readyFont(14)
    game.Switch(2)
    equal(addon.GetKeybindFontSize(), 14)
    assert(addon.SetKeybindFontSize(12))
    game.Switch(1)
    equal(addon.GetKeybindFontSize(), 14)
    assert(addon.SetKeybindFontSize(nil))
    game.Switch(2)
    equal(addon.GetKeybindFontSize(), 12)
    local _, restored = ready({
        database = snapshotDatabase(env.CleanBindsDB),
        characterDatabase = snapshotDatabase(env.CleanBindsCharacterDB), bindingSet = 2,
    })
    equal(restored.GetKeybindFontSize(), 12)
    local oldCharacter = macroProfile()
    local _, old = ready({ database = fontProfile(14), characterDatabase = oldCharacter, bindingSet = 2 })
    equal(old.GetKeybindFontSize(), nil)
    equal(oldCharacter.keybindFontSize, nil)
end)

test("font preferences cannot be written during combat, scope loading, or through stale tokens", function()
    local env, addon, _, _, game = readyFont(14)
    local token = addon.GetScopeToken()
    game.combat = true
    equal(addon.SetKeybindFontSize(12), false)
    equal(addon.SetKeybindFontSize(nil), false)
    equal(addon.GetKeybindFontSize(), 14)
    game.combat = false
    game.Load(2)
    equal(addon.GetKeybindFontSize(), nil)
    equal(addon.SetKeybindFontSize(12), false)
    equal(env.CleanBindsDB.keybindFontSize, 14)
    game.Save(2)
    equal(addon.SetKeybindFontSize(12, token), false)
    equal(env.CleanBindsCharacterDB.keybindFontSize, 14)
    game.Save(99)
    equal(addon.GetKeybindFontSize(), nil)
    equal(addon.SetKeybindFontSize(12), false)
end)

test("font sizing stays independent of custom text, macro hiding, and label resets", function()
    local button = mockMacroButton("ActionButton1", 1, "Macro")
    local _, addon, _, _, game = readyFont(14, button)
    game.actions[1] = "macro"
    assert(addon.SetHideMacroNames(true))
    assert(addon.SetLabel(addon.Bars[1], 1, "Key"))
    equal(button.HotKey:GetText(), "Key")
    equal(select(2, button.HotKey:GetFont()), 14)
    equal(select(2, button.Name:GetFont()), 11)
    equal(button.Name.alpha, 0)
    assert(addon.SetEnabled(false))
    equal(button.HotKey:GetText(), "F")
    equal(select(2, button.HotKey:GetFont()), 14)
    assert(addon.ResetLabels("actionbar1"))
    assert(addon.ResetLabels())
    equal(addon.GetKeybindFontSize(), 14)
    assert(addon.SetKeybindFontSize(nil))
    equal(button.HotKey:GetText(), "F")
    equal(button.Name.alpha, 0)
    equal(addon.ShouldHideMacroNames(), true)
end)

test("all supported bars and mirrors keep their own native font styles and default sizes", function()
    local env, addon, fire, _, game = loadAddon({ loggedIn = true })
    local buttons = {}
    for index, bar in ipairs(addon.Bars) do
        local button = mockButton(bar.buttonNamePrefix .. "1", "F")
        button.HotKey.fontObject = mockFontObject(index + 8, "Font" .. index, "OUTLINE, MONOCHROME")
        game.bindings[bar.bindingPrefix .. "1"] = { "F" }
        env[bar.frameName] = { actionButtons = { button } }
        buttons[index] = button
    end
    local mirror = mockButton("OverrideActionBarButton1", "F")
    mirror.HotKey.fontObject = mockFontObject(13, "MirrorFont", "")
    env.OverrideActionBar = { actionButtons = { mirror } }
    fire("ADDON_LOADED", "CleanBinds")
    assert(addon.SetKeybindFontSize(14))
    for index, button in ipairs(buttons) do
        local font, size, flags = button.HotKey:GetFont()
        equal(font, "Font" .. index)
        equal(size, 14)
        equal(flags, "OUTLINE, MONOCHROME")
        equal(button.HotKey.fontObject.size, index + 8)
        equal(button.HotKey.color[1], 0.6)
        equal(button.HotKey.alpha, 0.8)
        equal(button.HotKey:GetWidth(), 32)
        equal(button:GetSize(), 45)
    end
    equal(select(2, mirror.HotKey:GetFont()), 14)
    assert(addon.SetKeybindFontSize(nil))
    for index, button in ipairs(buttons) do
        equal(select(2, button.HotKey:GetFont()), index + 8)
        equal(button.HotKey:GetHeight(), 10)
    end
    equal(select(2, mirror.HotKey:GetFont()), 13)
end)

test("native font updates keep the override while native region size changes are left alone", function()
    local _, addon, _, _, game, button = readyFont(14)
    button.HotKey:SetFont("Fonts\\Changed.ttf", 13, "THICKOUTLINE")
    button.HotKey:SetSize(37, 12)
    game.Flush()
    local font, size, flags = button.HotKey:GetFont()
    equal(font, "Fonts\\Changed.ttf")
    equal(size, 14)
    equal(flags, "THICKOUTLINE")
    equal(button.HotKey:GetHeight(), 12)
    equal(button.HotKey:GetWidth(), 37)
    assert(addon.SetKeybindFontSize(nil))
    equal(select(2, button.HotKey:GetFont()), 13)
    equal(button.HotKey:GetHeight(), 12)
    equal(button.HotKey:GetWidth(), 37)
end)

test("font-object changes and UI scaling preserve native styling without modifying shared fonts", function()
    local _, addon, fire, _, game, button = readyFont(14)
    local source = mockFontObject(14, "Fonts\\Gamepad.ttf", "MONOCHROME")
    button.HotKey:SetFontObject(source)
    game.Flush()
    equal(select(2, button.HotKey:GetFont()), 14)
    equal(source.size, 14)
    equal(button.HotKey:GetFontObject(), source)
    source.size = 15
    source.font = "Fonts\\Updated.ttf"
    fire("UI_SCALE_CHANGED")
    game.Flush()
    equal(button.HotKey:GetFont(), "Fonts\\Updated.ttf")
    equal(select(2, button.HotKey:GetFont()), 14)
    assert(addon.SetKeybindFontSize(nil))
    equal(select(2, button.HotKey:GetFont()), 15)
    source.size = 16
    fire("UI_SCALE_CHANGED")
    game.Flush()
    equal(select(2, button.HotKey:GetFont()), 16)
    equal(addon.GetKeybindFontSize(), nil)
end)

test("unbound range indicators are not resized and newly bound labels use the chosen size", function()
    local _, addon, _, _, game, button = readyFont(14)
    game.SetKeys("ACTIONBUTTON1", {})
    button.HotKey:SetText("*")
    game.Flush()
    equal(select(2, button.HotKey:GetFont()), 11)
    equal(button.HotKey:GetHeight(), 10)
    game.SetKeys("ACTIONBUTTON1", { "G" })
    button.HotKey:SetText("G")
    game.Flush()
    equal(select(2, button.HotKey:GetFont()), 14)
    equal(button.HotKey:GetText(), "G")
    equal(addon.GetKeybindFontSize(), 14)
end)

test("font updates remain active in combat and repeated refreshes do not rewrite unchanged fonts", function()
    local _, addon, fire, _, game, button = readyFont(14)
    local writes, heights = button.HotKey.fontWrites, button.HotKey.heightWrites
    addon.RefreshActionLabels()
    button:Fire("OnShow")
    equal(button.HotKey.fontWrites, writes)
    equal(button.HotKey.heightWrites, heights)
    game.combat = true
    button.HotKey:SetFont("CombatFont", 12, "")
    fire("GAME_PAD_ACTIVE_CHANGED")
    fire("ACTIONBAR_PAGE_CHANGED")
    game.Flush()
    equal(button.HotKey:GetFont(), "CombatFont")
    equal(select(2, button.HotKey:GetFont()), 14)
    equal(addon.SetKeybindFontSize(12), false)
end)

test("scope transitions restore the native font before applying the destination preference", function()
    local env, addon, _, _, game, button = readyFont(14)
    env.CleanBindsCharacterDB = fontProfile(12)
    game.Load(2)
    equal(select(2, button.HotKey:GetFont()), 11)
    game.Save(2)
    equal(select(2, button.HotKey:GetFont()), 12)
    game.Switch(1)
    equal(select(2, button.HotKey:GetFont()), 14)
    game.Save(99)
    equal(select(2, button.HotKey:GetFont()), 11)
    equal(env.CleanBindsDB.keybindFontSize, 14)
end)

test("font and text hooks use independent guards for nested native updates", function()
    local button = mockButton("ActionButton1", "F")
    local setFont = button.HotKey.SetFont
    button.HotKey.SetFont = function(self, ...)
        setFont(self, ...)
        self:SetText("Native update")
    end
    local _, addon, _, _, game = readyFont(nil, button)
    assert(addon.SetLabel(addon.Bars[1], 1, "Custom"))
    assert(addon.SetKeybindFontSize(14))
    equal(button.HotKey:GetText(), "Custom")
    button.HotKey:SetFont("ChangedFont", 12, "MONOCHROME")
    game.Flush()
    equal(button.HotKey:GetText(), "Custom")
    equal(select(2, button.HotKey:GetFont()), 14)
    assert(addon.SetKeybindFontSize(nil))
    equal(select(2, button.HotKey:GetFont()), 12)
    assert(addon.SetEnabled(false))
    equal(button.HotKey:GetText(), "Native update")
end)

test("font size still applies when native keybind text cannot be inspected", function()
    local secret = { secret = true }
    local button = mockButton("ActionButton1", secret)
    local _, _, _, messages = readyFont(14, button)
    equal(button.HotKey:GetText(), secret)
    equal(select(2, button.HotKey:GetFont()), 14)
    equal(button.HotKey.writes, 0)
    equal(#messages, 0)
end)

test("restricted font properties are left untouched and recover when readable", function()
    local secret = { secret = true }
    local button = mockButton("ActionButton1", "F")
    button.HotKey.font = { secret, 11, "OUTLINE" }
    local _, addon, _, messages, game = readyFont(14, button)
    equal(button.HotKey.fontWrites, 0)
    equal(#messages, 1)
    assert(messages[1]:find("restricted this keybinding font", 1, true))
    button.HotKey:SetFont("ReadableFont", 12, "OUTLINE")
    game.Flush()
    equal(select(2, button.HotKey:GetFont()), 14)
    assert(addon.SetKeybindFontSize(nil))
    equal(select(2, button.HotKey:GetFont()), 12)
end)

test("forbidden buttons never receive font writes", function()
    for _, forbidButton in ipairs({ false, true }) do
        local button = mockButton("ActionButton1", "F")
        if forbidButton then button.forbidden = true else button.HotKey.forbidden = true end
        local _, addon, _, messages = readyFont(14, button)
        addon.RefreshActionLabels()
        equal(button.HotKey.fontWrites, 0)
        equal(#messages, 1)
        assert(messages[1]:find("restricted this keybinding font", 1, true))
    end
end)

test("rejected font writes release the guard without corrupting the native default", function()
    local _, addon, _, _, game, button = readyFont()
    button.HotKey.rejectFont = true
    local success, reason = pcall(addon.SetKeybindFontSize, 14)
    equal(success, false)
    assert(reason:find("Rejected font write", 1, true))
    button.HotKey.rejectFont = false
    addon.RefreshActionLabels()
    equal(select(2, button.HotKey:GetFont()), 14)
    button.HotKey:SetFont("NewFont", 12, "")
    game.Flush()
    assert(addon.SetKeybindFontSize(nil))
    equal(select(2, button.HotKey:GetFont()), 12)
end)

test("the native font slider has one-unit steps, live previews, and an independent Default reset", function()
    local env, addon, fire, pages, _, game = readySettings({ bindings = { ACTIONBUTTON1 = { "F" } } })
    local button = mockButton("ActionButton1", "F")
    button.HotKey:SetWidth(24)
    env.MainActionBar = { actionButtons = { button }, IsShown = function() return true end }
    fire("ADDON_LOADED", "Blizzard_ActionBar")
    game.Flush()
    equal(game.fontSlider.options.minValue, 10)
    equal(game.fontSlider.options.maxValue, 14)
    equal(game.fontSlider.options.steps, 4)
    equal(game.fontSlider.value, 11)
    equal(game.fontSizeSetting.default, 0)
    equal(game.fontSlider.label, addon.L.DEFAULT_FONT_SIZE:format(11))
    equal(game.fontSizeSetting.writes, 0)
    equal(game.fontPreview.Reset.enabled, false)
    game.fontSizeSetting:SetValue(14)
    equal(select(2, button.HotKey:GetFont()), 14)
    equal(select(2, game.fontPreview.Preview.HotKey:GetFont()), 14)
    pages[1]:Show()
    equal(select(2, pages[1].Preview.HotKey:GetFont()), 14)
    equal(game.fontPreview.Preview.HotKey:GetHeight(), button.HotKey:GetHeight())
    equal(game.fontSlider.label, "14")
    equal(game.fontPreview.Status:GetText(), addon.L.LABEL_TOO_WIDE)
    game.fontSizeSetting:SetValue(10)
    equal(select(2, game.fontPreview.Preview.HotKey:GetFont()), 10)
    equal(game.fontPreview.Status:GetText(), "")
    equal(game.fontPreview.Reset.enabled, true)
    game.fontPreview.Reset:OnClick()
    equal(addon.GetKeybindFontSize(), nil)
    equal(select(2, game.fontPreview.Preview.HotKey:GetFont()), 11)
    equal(game.fontSlider.value, 11)
    equal(game.fontSlider.label, addon.L.DEFAULT_FONT_SIZE:format(11))
    equal(game.fontPreview.Reset.enabled, false)
    equal(game.fontSizeSetting.writes, 2)
end)

test("font controls refresh across scopes without writing and remain read-only during combat", function()
    local env, addon, _, _, _, game = readySettings()
    game.fontSizeSetting:SetValue(14)
    game.Switch(2)
    equal(game.fontSizeSetting.displayedValue, 14)
    game.fontSizeSetting:SetValue(12)
    game.Switch(1)
    equal(game.fontSizeSetting.displayedValue, 14)
    equal(game.fontSizeSetting.writes, 2)
    game.combat = true
    equal(game.fontSlider.canModify(), false)
    game.fontPreview.Reset:OnClick()
    equal(env.CleanBindsDB.keybindFontSize, 14)
    game.combat = false
    game.Load(2)
    equal(game.fontSlider.canModify(), false)
    game.Save(2)
    equal(game.fontSlider.canModify(), true)
    equal(addon.GetKeybindFontSize(), 12)
    equal(pcall(game.fontSizeSetting.SetValue, game.fontSizeSetting, false), false)
    equal(addon.GetKeybindFontSize(), 12)
    assert(game.fontSizeSetting:SetValueToDefault())
    equal(addon.GetKeybindFontSize(), nil)
end)

test("Blizzard Defaults restores native sizing through the slider notification path", function()
    local env, addon, _, _, _, game = readySettings()
    for size = addon.MIN_KEYBIND_FONT_SIZE, addon.MAX_KEYBIND_FONT_SIZE do
        local minimum = addon.MIN_KEYBIND_FONT_SIZE
        game.fontSlider:SetValue(size == minimum and minimum + 1 or minimum)
        game.fontSlider:SetValue(size)
        equal(addon.GetKeybindFontSize(), size ~= 11 and size or nil)
        equal(game.fontSlider.label, size == 11 and addon.L.DEFAULT_FONT_SIZE:format(11) or tostring(size))
        assert(game.fontSizeSetting:SetValueToDefault())
        equal(addon.GetKeybindFontSize(), nil)
        equal(env.CleanBindsDB.keybindFontSize, nil)
        equal(game.fontSizeSetting:GetValue(), 0)
        equal(game.fontSlider.value, 11)
        equal(game.fontSlider.label, addon.L.DEFAULT_FONT_SIZE:format(11))
        equal(game.fontPreview.Reset.enabled, false)
        equal(select(2, game.fontPreview.Preview.HotKey:GetFont()), 11)
    end
end)

test("returning the slider to its native size clears the custom preference", function()
    local _, addon, _, _, _, game = readySettings()
    local slider, setting = game.fontSlider, game.fontSizeSetting
    equal(slider.value, 11)
    equal(setting:GetValue(), 0)
    equal(slider.label, addon.L.DEFAULT_FONT_SIZE:format(11))
    slider:SetValue(slider.value + 1)
    equal(addon.GetKeybindFontSize(), 12)
    slider:SetValue(slider.value - 1)
    equal(addon.GetKeybindFontSize(), nil)
    equal(slider.value, 11)
    equal(slider.label, addon.L.DEFAULT_FONT_SIZE:format(11))
    equal(game.fontPreview.Reset.enabled, false)

    slider:SetValue(slider.options.minValue)
    equal(addon.GetKeybindFontSize(), 10)
    assert(setting:SetValueToDefault())
    equal(addon.GetKeybindFontSize(), nil)
    local writes = setting.writes
    assert(setting:SetValueToDefault())
    assert(setting:SetValueToDefault())
    game.fontPreview.Reset:OnClick()
    equal(setting.writes, writes)
    equal(slider.value, 11)
    equal(slider.label, addon.L.DEFAULT_FONT_SIZE:format(11))
end)

test("returning the slider to Default restores each button and preserves the other scope", function()
    local env, addon, fire, _, _, game = readySettings({
        bindings = { ACTIONBUTTON1 = { "F" }, ACTIONBUTTON2 = { "G" } },
        characterDatabase = fontProfile(12),
    })
    local first = mockButton("ActionButton1", "F")
    local second = mockButton("ActionButton2", "G")
    second.HotKey.fontObject = mockFontObject(13)
    env.MainActionBar = { actionButtons = { first, second } }
    fire("ADDON_LOADED", "Blizzard_ActionBar")
    game.Flush()
    game.fontSlider:SetValue(14)
    equal(select(2, first.HotKey:GetFont()), 14)
    equal(select(2, second.HotKey:GetFont()), 14)
    game.fontSlider:SetValue(11)
    equal(addon.GetKeybindFontSize(), nil)
    equal(env.CleanBindsDB.keybindFontSize, nil)
    equal(env.CleanBindsCharacterDB.keybindFontSize, 12)
    equal(select(2, first.HotKey:GetFont()), 11)
    equal(select(2, second.HotKey:GetFont()), 13)
    equal(game.fontSlider.label, addon.L.DEFAULT_FONT_SIZE:format(11))
    equal(game.fontPreview.Reset.enabled, false)
end)

test("only user slider movement normalizes a size matching the current native font", function()
    local env, addon, fire, _, _, game = readySettings({
        database = fontProfile(14), characterDatabase = fontProfile(11),
        bindings = { ACTIONBUTTON1 = { "F" } },
    })
    local button = mockButton("ActionButton1", "F")
    env.MainActionBar = { actionButtons = { button } }
    fire("ADDON_LOADED", "Blizzard_ActionBar")
    game.Flush()
    game.Switch(2)
    equal(addon.GetKeybindFontSize(), 11)
    equal(env.CleanBindsCharacterDB.keybindFontSize, 11)
    equal(game.fontSizeSetting.writes, 0)
    game.Switch(1)
    button.HotKey:SetFont("UpdatedNative", 14, "OUTLINE")
    game.Flush()
    equal(addon.GetKeybindFontSize(), 14)
    equal(env.CleanBindsDB.keybindFontSize, 14)
    equal(game.fontSizeSetting.writes, 0)
    game.fontSlider:SetValue(13)
    equal(addon.GetKeybindFontSize(), 13)
    game.fontSlider:SetValue(14)
    equal(addon.GetKeybindFontSize(), nil)
    equal(env.CleanBindsCharacterDB.keybindFontSize, 11)
    equal(game.fontSlider.label, addon.L.DEFAULT_FONT_SIZE:format(14))
end)

test("slider return to Default handles the client's floating-point font size", function()
    for _, nativeSize in ipairs({ 12.000000953674316, 11.999999046325684 }) do
        local env, addon, fire, _, _, game = readySettings({ bindings = { ACTIONBUTTON1 = { "F" } } })
        local button = mockButton("ActionButton1", "F")
        button.HotKey.fontObject = mockFontObject(nativeSize)
        env.MainActionBar = { actionButtons = { button } }
        fire("ADDON_LOADED", "Blizzard_ActionBar")
        game.Flush()
        game.fontSlider:SetValue(10)
        equal(addon.GetKeybindFontSize(), 10)
        game.fontSlider:SetValue(12)
        equal(addon.GetKeybindFontSize(), nil)
        equal(env.CleanBindsDB.keybindFontSize, nil)
        equal(game.fontSlider.label, addon.L.DEFAULT_FONT_SIZE:format(12))
        equal(game.fontSlider.value, 12)
        equal(game.fontPreview.Reset.enabled, false)
        equal(select(2, button.HotKey:GetFont()), nativeSize)
        game.fontSlider:SetValue(game.fontSlider.value + 1)
        equal(addon.GetKeybindFontSize(), 13)
        game.fontSlider:SetValue(game.fontSlider.value - 1)
        equal(addon.GetKeybindFontSize(), nil)
        game.fontSlider:SetValue(13.000000953674316)
        equal(addon.GetKeybindFontSize(), 13)
        equal(game.fontSlider.value, 13)
    end
end)

test("font-size precision tolerance does not hide a genuinely fractional native size", function()
    local env, addon, fire, _, _, game = readySettings({ bindings = { ACTIONBUTTON1 = { "F" } } })
    local button = mockButton("ActionButton1", "F")
    button.HotKey.fontObject = mockFontObject(12.25)
    env.MainActionBar = { actionButtons = { button } }
    fire("ADDON_LOADED", "Blizzard_ActionBar")
    game.Flush()
    game.fontSlider:SetValue(12)
    equal(addon.GetKeybindFontSize(), 12)
    equal(game.fontSlider.label, "12")
    game.fontPreview.Reset:OnClick()
    equal(addon.GetKeybindFontSize(), nil)
    equal(game.fontSlider.value, 12.25)
    equal(game.fontSlider.label, addon.L.DEFAULT_FONT_SIZE:format(12.25))
    equal(select(2, button.HotKey:GetFont()), 12.25)
end)

test("native font precision does not cause repeated writes or lose font-object tracking", function()
    local button = mockButton("ActionButton1", "F")
    local getFont = button.HotKey.GetFont
    local noise = 0.000000953674316
    button.HotKey.GetFont = function(self)
        local font, size, flags = getFont(self)
        return font, size + noise, flags
    end
    local _, addon, fire, _, game = readyFont(14, button)
    local writes = button.HotKey.fontWrites
    addon.RefreshActionLabels()
    addon.RefreshActionLabels()
    button:Fire("OnShow")
    equal(button.HotKey.fontWrites, writes)
    button.HotKey.fontObject.size = 12
    fire("UI_SCALE_CHANGED")
    game.Flush()
    equal(button.HotKey.fontWrites, writes)
    assert(addon.SetKeybindFontSize(nil))
    equal(select(2, button.HotKey:GetFont()), 12 + noise)
    local restoredWrites = button.HotKey.fontWrites
    addon.RefreshActionLabels()
    equal(button.HotKey.fontWrites, restoredWrites)
end)

test("native Defaults restores each font and leaves the other binding scope intact", function()
    local env, addon, fire, _, _, game = readySettings({
        bindings = { ACTIONBUTTON1 = { "F" }, ACTIONBUTTON2 = { "G" } },
    })
    local first = mockButton("ActionButton1", "F")
    local second = mockButton("ActionButton2", "G")
    second.HotKey.fontObject = mockFontObject(13)
    env.MainActionBar = { actionButtons = { first, second } }
    fire("ADDON_LOADED", "Blizzard_ActionBar")
    game.Flush()
    game.fontSlider:SetValue(14)
    game.Switch(2)
    game.fontSlider:SetValue(12)
    assert(game.fontSizeSetting:SetValueToDefault())
    equal(env.CleanBindsDB.keybindFontSize, 14)
    equal(env.CleanBindsCharacterDB.keybindFontSize, nil)
    equal(select(2, first.HotKey:GetFont()), 11)
    equal(select(2, second.HotKey:GetFont()), 13)
    game.Switch(1)
    equal(game.fontSlider.value, 14)
    equal(select(2, first.HotKey:GetFont()), 14)
    game.fontPreview.Reset:OnClick()
    equal(game.fontSlider.value, 11)
    equal(env.CleanBindsDB.keybindFontSize, nil)
    equal(select(2, first.HotKey:GetFont()), 11)
    equal(select(2, second.HotKey:GetFont()), 13)
end)

test("the Default thumb follows the preview button's native font without saving a numeric override", function()
    local env, addon, fire, _, _, game = readySettings({ bindings = { ACTIONBUTTON1 = { "F" } } })
    local button = mockButton("ActionButton1", "F")
    button.HotKey.fontObject = mockFontObject(13)
    env.MainActionBar = { actionButtons = { button } }
    fire("ADDON_LOADED", "Blizzard_ActionBar")
    game.Flush()
    equal(game.fontSlider.value, 13)
    equal(game.fontSlider.label, addon.L.DEFAULT_FONT_SIZE:format(13))
    equal(addon.GetKeybindFontSize(), nil)
    equal(game.fontSizeSetting.writes, 0)

    button.HotKey:SetFont("UpdatedNative", 12, "OUTLINE")
    game.Flush()
    equal(game.fontSlider.value, 12)
    equal(game.fontSlider.label, addon.L.DEFAULT_FONT_SIZE:format(12))
    equal(addon.GetKeybindFontSize(), nil)
    equal(game.fontSizeSetting.writes, 0)
    game.fontSlider:SetValue(14)
    assert(game.fontSizeSetting:SetValueToDefault())
    equal(game.fontSlider.value, 12)
    equal(game.fontSlider.label, addon.L.DEFAULT_FONT_SIZE:format(12))
    equal(select(2, button.HotKey:GetFont()), 12)
    equal(addon.GetKeybindFontSize(), nil)
end)

test("initializing a reused numeric slider cannot turn Default into a saved size", function()
    local _, addon, _, _, _, game = readySettings()
    local control, setting, slider = game.fontSliderControl, game.fontSizeSetting, game.fontSlider
    slider:SetValue(14)
    game.fontPreview.Reset:OnClick()
    local writes = setting.writes
    control:Init(control.initializer)
    equal(addon.GetKeybindFontSize(), nil)
    equal(setting.writes, writes)
    equal(slider.value, 11)
    equal(slider.label, addon.L.DEFAULT_FONT_SIZE:format(11))
    slider:SetValue(14)
    game.combat = true
    assert(setting:SetValueToDefault())
    equal(addon.GetKeybindFontSize(), 14)
    equal(slider.value, 14)
    equal(slider.label, "14")
end)

test("unavailable default fonts disable the numeric slider until a native size can be read", function()
    local env, addon, fire, _, _, game = readySettings({ bindings = { ACTIONBUTTON1 = { "F" } } })
    local button = mockButton("ActionButton1", "F")
    button.HotKey.font = { { secret = true }, 11, "OUTLINE" }
    env.MainActionBar = { actionButtons = { button } }
    fire("ADDON_LOADED", "Blizzard_ActionBar")
    game.Flush()
    equal(game.fontSlider.enabled, false)
    equal(game.fontSlider.label, addon.L.UNAVAILABLE)
    equal(game.fontPreview.Status:GetText(), addon.L.FONT_REFERENCE_UNAVAILABLE)
    equal(game.fontSizeSetting.writes, 0)
    button.HotKey:SetFont("ReadableFont", 13, "OUTLINE")
    game.Flush()
    equal(game.fontSlider.enabled, true)
    equal(game.fontSlider.value, 13)
    equal(game.fontSlider.label, addon.L.DEFAULT_FONT_SIZE:format(13))
    equal(game.fontSizeSetting.writes, 0)
    equal(addon.GetKeybindFontSize(), nil)
end)

test("font previews show the selected size before native action buttons exist", function()
    local _, addon, _, _, _, game = readySettings()
    game.fontSizeSetting:SetValue(14)
    equal(select(2, game.fontPreview.Preview.HotKey:GetFont()), 14)
    equal(game.fontPreview.Preview.HotKey:GetHeight(), 10)
    game.fontPreview.Reset:OnClick()
    equal(addon.GetKeybindFontSize(), nil)
    equal(select(2, game.fontPreview.Preview.HotKey:GetFont()), 11)
end)

test("font previews report restricted fonts and resume when the native font becomes readable", function()
    local env, addon, fire, pages, _, game = readySettings({ bindings = { ACTIONBUTTON1 = { "F" } } })
    local button = mockButton("ActionButton1", "F")
    button.HotKey.font = { { secret = true }, 11, "OUTLINE" }
    env.MainActionBar = { actionButtons = { button }, IsShown = function() return true end }
    fire("ADDON_LOADED", "Blizzard_ActionBar")
    game.Flush()
    game.fontSizeSetting:SetValue(14)
    equal(game.fontPreview.Preview:IsShown(), false)
    equal(game.fontPreview.Status:GetText(), addon.L.FONT_REFERENCE_UNAVAILABLE)
    pages[1]:Show()
    equal(pages[1].Preview:IsShown(), false)
    equal(pages[1].Status:GetText(), addon.L.FONT_REFERENCE_UNAVAILABLE)
    button.HotKey:SetFont("ReadableFont", 12, "OUTLINE")
    game.Flush()
    equal(game.fontPreview.Preview:IsShown(), true)
    equal(pages[1].Preview:IsShown(), true)
    equal(select(2, game.fontPreview.Preview.HotKey:GetFont()), 14)
end)

test("font styling waits for startup scope and attaches late buttons without changing their defaults", function()
    local env, addon, fire, _, game = loadAddon({
        loggedIn = true, bindingSet = 0, database = fontProfile(14),
        bindings = { ACTIONBUTTON1 = { "F" } },
    })
    fire("ADDON_LOADED", "CleanBinds")
    equal(addon.GetKeybindFontSize(), nil)
    equal(addon.SetKeybindFontSize(nil), false)
    equal(env.CleanBindsDB.keybindFontSize, 14)
    game.bindingSet = 1
    game.Flush()
    local button = mockButton("ActionButton1", "F")
    env.MainActionBar = { actionButtons = { button } }
    fire("ADDON_LOADED", "Blizzard_ActionBar")
    game.Flush()
    equal(select(2, button.HotKey:GetFont()), 14)
    local writes = button.HotKey.fontWrites
    addon.RefreshActionLabels()
    button:Fire("OnShow")
    equal(button.HotKey.fontWrites, writes)
    equal(#button.scripts.OnShow, 1)
    assert(addon.SetKeybindFontSize(nil))
    equal(select(2, button.HotKey:GetFont()), 11)
end)

test("These Settings on the main page resets labels and options in the active setup only", function()
    for _, scope in ipairs({ 1, 2 }) do
        local env, addon, _, pages, _, game = readySettings()
        assert(addon.SetLabel(addon.Bars[1], 1, "Shared"))
        assert(addon.SetLabel(addon.Bars[2], 1, "Shared two"))
        assert(addon.SetEnabled(false))
        assert(addon.SetHideMacroNames(true))
        assert(addon.SetKeybindFontSize(14))
        game.Switch(2)
        assert(addon.SetLabel(addon.Bars[1], 1, "Character"))
        assert(addon.SetLabel(addon.Bars[2], 1, "Character two"))
        assert(addon.SetKeybindFontSize(13))
        game.Switch(scope)
        local active = addon.db
        local inactive = scope == 1 and env.CleanBindsCharacterDB or env.CleanBindsDB
        local inactiveLabel = inactive.overrides["actionbar1:1"]
        local inactiveSize = inactive.keybindFontSize

        game.DefaultSettings("these", addon.category)
        equal(addon.db, active)
        equal(next(active.overrides), nil)
        equal(next(active.bindingSnapshots), nil)
        equal(active.enabled, true)
        equal(active.hideMacroNames, false)
        equal(active.keybindFontSize, nil)
        equal(addon.GetLabel(addon.Bars[1], 1), nil)
        equal(addon.GetLabel(addon.Bars[2], 1), nil)
        equal(inactive.overrides["actionbar1:1"], inactiveLabel)
        equal(inactive.enabled, false)
        equal(inactive.hideMacroNames, true)
        equal(inactive.keybindFontSize, inactiveSize)
        equal(game.enabledSetting.displayedValue, true)
        equal(game.hideMacroNamesSetting.displayedValue, false)
        equal(game.fontSlider.label, addon.L.DEFAULT_FONT_SIZE:format(11))
        equal(game.fontPreview.Reset.enabled, false)
        game.Flush()
        equal(next(active.overrides), nil)
        equal(pages[1].rows[1].Override:GetText(), addon.L.DEFAULT_LABEL)
    end
end)

test("Reset This Bar resets only that bar and leaves the appearance controls alone", function()
    local env, addon, _, pages, _, game = readySettings()
    assert(addon.SetEnabled(false))
    assert(addon.SetHideMacroNames(true))
    assert(addon.SetKeybindFontSize(14))
    for _, selected in ipairs(pages) do
        for _, page in ipairs(pages) do
            assert(addon.SetLabel(page.bar, 1, page.bar.id))
        end
        game.ResetBar(selected)
        for _, page in ipairs(pages) do
            local id = page.bar.id .. ":1"
            local label = page ~= selected and page.bar.id or nil
            equal(addon.GetLabel(page.bar, 1), label)
            equal(env.CleanBindsDB.overrides[id], label)
            equal(env.CleanBindsDB.bindingSnapshots[id] ~= nil, page ~= selected)
        end
        equal(addon.db.enabled, false)
        equal(addon.ShouldHideMacroNames(), true)
        equal(addon.GetKeybindFontSize(), 14)
        equal(game.enabledSetting.writes, 0)
        equal(game.hideMacroNamesSetting.writes, 0)
        equal(game.fontSizeSetting.writes, 0)
        equal(game.defaultBindingLoads, nil)
    end
end)

test("All Settings resets the active addon setup once and retains the inactive setup", function()
    for _, scope in ipairs({ 1, 2 }) do
        local env, addon, _, pages, _, game = readySettings({
            savedBindings = { [0] = { ACTIONBUTTON1 = { "1" } } },
        })
        assert(addon.SetLabel(addon.Bars[1], 1, "Account"))
        assert(addon.SetEnabled(false))
        assert(addon.SetHideMacroNames(true))
        assert(addon.SetKeybindFontSize(14))
        game.Switch(2)
        assert(addon.SetLabel(addon.Bars[1], 1, "Character"))
        assert(addon.SetLabel(addon.Bars[9], 1, "Pet"))
        assert(addon.SetKeybindFontSize(13))
        game.Switch(scope)
        local active = addon.db
        local inactive = scope == 1 and env.CleanBindsCharacterDB or env.CleanBindsDB
        local inactiveLabel = inactive.overrides["actionbar1:1"]
        local inactiveSize = inactive.keybindFontSize
        local calls, reset = 0, addon.ResetLabels
        addon.ResetLabels = function(...)
            calls = calls + 1
            return reset(...)
        end

        game.DefaultSettings("all", scope == 1 and pages[2].category or { GetID = function() return -1 end })
        game.Flush()
        equal(calls, 1)
        equal(addon.db, active)
        equal(next(active.overrides), nil)
        equal(next(active.bindingSnapshots), nil)
        equal(active.enabled, true)
        equal(active.hideMacroNames, false)
        equal(active.keybindFontSize, nil)
        equal(inactive.overrides["actionbar1:1"], inactiveLabel)
        equal(inactive.enabled, false)
        equal(inactive.hideMacroNames, true)
        equal(inactive.keybindFontSize, inactiveSize)
        equal(game.bindingSet, scope)
        equal(game.bindings.ACTIONBUTTON1[1], "1")
        equal(game.defaultBindingLoads, 1)
        game.Save()
        game.Flush()
        equal(next(active.overrides), nil)
        equal(calls, 1)
    end
end)

test("confirmed resets discard affected drafts before they can be committed again", function()
    for _, target in ipairs({ "bar", "main", "all" }) do
        local _, addon, _, pages, _, game = readySettings()
        local page, other = pages[1], pages[2]
        page:Show()
        other:Show()
        assert(addon.SetLabel(page.bar, 1, "Old"))
        assert(addon.SetLabel(other.bar, 1, "Other"))
        local row, otherRow = page.rows[1], other.rows[1]
        row.Override:OnClick()
        row.Editor:SetText("Do not restore")
        otherRow.Override:OnClick()
        otherRow.Editor:SetText("Other draft")
        if target == "bar" then
            game.ResetBar(page)
        else
            game.DefaultSettings(target == "all" and "all" or "these", addon.category)
        end

        equal(page.editingRow, nil)
        equal(row.Editor:IsShown(), false)
        equal(row.Editor.focused, false)
        equal(row.Override:GetText(), addon.L.DEFAULT_LABEL)
        row.Editor:OnEnterPressed()
        row.Editor:OnEditFocusLost()
        page:OnCommit()
        page:Hide()
        equal(addon.GetLabel(page.bar, 1), nil)
        if target == "bar" then
            equal(other.editingRow, otherRow)
            equal(addon.GetLabel(other.bar, 1), "Other")
            other:OnCommit()
            equal(addon.GetLabel(other.bar, 1), "Other draft")
        else
            equal(other.editingRow, nil)
            other:OnCommit()
            equal(addon.GetLabel(other.bar, 1), nil)
        end
    end
end)

test("Cancel and These Settings for another category leave Clean Binds unchanged", function()
    local env, addon, _, pages, _, game = readySettings()
    assert(addon.SetLabel(addon.Bars[1], 1, "Keep"))
    assert(addon.SetEnabled(false))
    assert(addon.SetHideMacroNames(true))
    assert(addon.SetKeybindFontSize(14))
    local page = pages[1]
    page:Show()
    page.rows[1].Override:OnClick()
    page.rows[1].Editor:SetText("Draft")
    local unrelated = env.Settings.RegisterVerticalLayoutCategory("Other addon")
    game.DefaultSettings("cancel", addon.category)
    game.DefaultSettings("these", unrelated)
    equal(addon.GetLabel(page.bar, 1), "Keep")
    equal(page.editingRow, page.rows[1])
    equal(page.rows[1].Editor:GetText(), "Draft")
    equal(addon.db.enabled, false)
    equal(addon.ShouldHideMacroNames(), true)
    equal(addon.GetKeybindFontSize(), 14)
    equal(game.defaultBindingLoads, nil)
end)

test("native category resets match stable category IDs", function()
    local env, addon = readySettings()
    assert(addon.SetLabel(addon.Bars[1], 1, "First"))
    assert(addon.SetLabel(addon.Bars[2], 1, "Second"))
    local category = { GetID = function() return addon.category:GetID() end }
    env.EventRegistry:TriggerEvent("Settings.CategoryDefaulted", category)
    equal(addon.GetLabel(addon.Bars[1], 1), nil)
    equal(addon.GetLabel(addon.Bars[2], 1), nil)
end)

test("native resets stay read-only during combat or an unresolved binding scope", function()
    for _, condition in ipairs({ "combat", "loading", "unknown" }) do
        for _, target in ipairs({ "bar", "main", "all" }) do
            local env, addon, _, pages, messages, game = readySettings()
            assert(addon.SetLabel(addon.Bars[1], 1, "Keep"))
            assert(addon.SetEnabled(false))
            assert(addon.SetHideMacroNames(true))
            assert(addon.SetKeybindFontSize(14))
            local saved = env.CleanBindsDB
            if condition == "combat" then
                game.combat = true
            elseif condition == "loading" then
                game.Load(2)
            else
                game.Save(99)
            end
            if target == "bar" then
                pages[1].Reset:OnClick()
                equal(game.popup, nil)
            else
                game.DefaultSettings(target == "all" and "all" or "these", addon.category)
            end
            equal(saved.overrides["actionbar1:1"], "Keep")
            assert(saved.bindingSnapshots["actionbar1:1"])
            equal(saved.enabled, false)
            equal(saved.hideMacroNames, true)
            equal(saved.keybindFontSize, 14)
            assert(#messages > 0)
            if condition == "combat" then
                equal(messages[#messages], addon.L.ADDON_NAME .. ": " .. addon.L.COMBAT_READ_ONLY)
                equal(game.enabledSetting.displayedValue, false)
                equal(game.hideMacroNamesSetting.displayedValue, true)
                equal(game.fontSlider.value, 14)
            end
        end
    end
end)

test("a scope change during draft cancellation cannot redirect a bar reset", function()
    local env, addon, _, pages, messages, game = readySettings()
    local page = pages[1]
    assert(addon.SetLabel(page.bar, 1, "Account"))
    game.Switch(2)
    assert(addon.SetLabel(page.bar, 1, "Character"))
    game.Switch(1)
    page:Show()
    local row = page.rows[1]
    row.Override:OnClick()
    row.Editor:SetText("Draft")
    local clearFocus = row.Editor.ClearFocus
    row.Editor.ClearFocus = function(self)
        clearFocus(self)
        game.Switch(2)
    end
    game.ResetBar(page)
    equal(env.CleanBindsDB.overrides["actionbar1:1"], "Account")
    equal(env.CleanBindsCharacterDB.overrides["actionbar1:1"], "Character")
    equal(addon.db, env.CleanBindsCharacterDB)
    equal(messages[#messages], addon.L.ADDON_NAME .. ": " .. addon.L.SCOPE_CHANGED)
end)

test("resetting a bar removes unverified labels so later binding reads cannot restore them", function()
    local env, addon, fire, pages, _, game = readySettings({ bindings = { ACTIONBUTTON1 = { "F" } } })
    assert(addon.SetLabel(addon.Bars[1], 1, "Keep until reset"))
    game.unavailableBinding = "ACTIONBUTTON1"
    game.Save()
    equal(addon.GetLabel(addon.Bars[1], 1), nil)
    equal(env.CleanBindsDB.overrides["actionbar1:1"], "Keep until reset")
    game.ResetBar(pages[1])
    equal(env.CleanBindsDB.overrides["actionbar1:1"], nil)
    equal(env.CleanBindsDB.bindingSnapshots["actionbar1:1"], nil)
    game.unavailableBinding = nil
    fire("ADDON_LOADED", "Blizzard_ActionBar")
    game.Flush()
    equal(addon.GetLabel(addon.Bars[1], 1), nil)
end)

test("native main reset restores text, appearance, and keeps the bar and font-only reset controls", function()
    local env, addon, fire, pages, _, game = readySettings({
        bindings = { ACTIONBUTTON1 = { "F" } }, actions = { [1] = "macro" },
    })
    local button = mockMacroButton("ActionButton1", 1, "Macro")
    env.MainActionBar = { actionButtons = { button } }
    fire("ADDON_LOADED", "Blizzard_ActionBar")
    game.Flush()
    assert(addon.SetLabel(addon.Bars[1], 1, "Custom"))
    assert(addon.SetHideMacroNames(true))
    assert(addon.SetKeybindFontSize(14))
    equal(button.HotKey:GetText(), "Custom")
    equal(select(2, button.HotKey:GetFont()), 14)
    equal(button.Name.alpha, 0)
    game.DefaultSettings("these", addon.category)
    equal(button.HotKey:GetText(), "F")
    equal(select(2, button.HotKey:GetFont()), 11)
    equal(button.Name.alpha, 0.8)
    for _, page in ipairs(pages) do
        equal(page.Reset:GetText(), addon.L.RESET_BAR)
    end
    assert(env.StaticPopupDialogs.CLEANBINDS_CONFIRM_RESET)
    assert(game.fontPreview.Reset)
end)

test("bar reset confirmation can be canceled and is invalidated by scope changes", function()
    local env, addon, _, pages, _, game = readySettings()
    local page = pages[1]
    assert(addon.SetLabel(page.bar, 1, "Account"))
    page.Reset:OnClick()
    local popup = game.popup
    assert(popup.text:find(addon.L.ACCOUNT_SCOPE, 1, true))
    local dialog = env.StaticPopupDialogs[popup.which]
    dialog.OnCancel()
    game.popup = nil
    equal(addon.GetLabel(page.bar, 1), "Account")
    page.Reset:OnClick()
    local stale = game.popup
    game.Switch(2)
    equal(game.popup, nil)
    assert(addon.SetLabel(page.bar, 1, "Character"))
    dialog.OnAccept(nil, stale.data)
    equal(addon.GetLabel(page.bar, 1), "Character")
    game.Switch(1)
    dialog.OnAccept(nil, stale.data)
    equal(addon.GetLabel(page.bar, 1), "Account")
end)

test("a native full reset dismisses an outstanding bar reset confirmation", function()
    local _, addon, _, pages, _, game = readySettings()
    assert(addon.SetLabel(addon.Bars[1], 1, "First"))
    pages[1].Reset:OnClick()
    assert(game.popup)
    game.DefaultSettings("these", addon.category)
    equal(game.popup, nil)
    equal(addon.GetLabel(addon.Bars[1], 1), nil)
end)

test("labels reset even when all three native controls already have default values", function()
    local _, addon, _, _, _, game = readySettings()
    assert(addon.SetLabel(addon.Bars[1], 1, "Only label changed"))
    game.DefaultSettings("these", addon.category)
    equal(addon.GetLabel(addon.Bars[1], 1), nil)
    equal(game.enabledSetting.writes, 0)
    equal(game.hideMacroNamesSetting.writes, 0)
    equal(game.fontSizeSetting.writes, 0)
end)

test("missing native Settings callbacks fail without writing saved data", function()
    local env, addon, fire, messages = loadAddon({
        loggedIn = true,
        setup = function(environment)
            environment.EventRegistry.RegisterCallback = nil
        end,
    })
    fire("ADDON_LOADED", "CleanBinds")
    equal(addon.state, "failed")
    equal(env.CleanBindsDB, nil)
    equal(env.CleanBindsCharacterDB, nil)
    assert(messages[1]:find("EventRegistry.RegisterCallback", 1, true))
end)

local function findSearchEntry(game, query, category, name)
    for _, result in ipairs(game.Search(query)) do
        if result.category == category and result.initializer.data.name == name then
            return result.initializer
        end
    end
    error("Missing search entry: " .. name)
end

test("Options search finds the main controls by addon name as well as setting name", function()
    local _, addon, _, _, _, game = readySettings()
    for _, query in ipairs({ "Clean Binds", "CleanBinds", "cLeAnBiNdS" }) do
        local results = game.Search(query)
        equal(#results, 3)
        local settings = {}
        for _, result in ipairs(results) do
            equal(result.category, addon.category)
            settings[result.initializer.data.setting.variable] = true
        end
        assert(settings.CLEANBINDS_ENABLED)
        assert(settings.CLEANBINDS_HIDE_MACRO_NAMES)
        assert(settings.CLEANBINDS_KEYBIND_FONT_SIZE)
    end
    for _, query in ipairs({ addon.L.HIDE_MACRO_NAMES, addon.L.KEYBIND_FONT_SIZE, addon.L.ENABLE_LABELS }) do
        local found = false
        for _, result in ipairs(game.Search(query)) do
            if result.initializer.data.name == query then found = true end
        end
        assert(found, query)
    end
end)

test("search indexes redirect to existing canvas pages without adding visible categories or settings", function()
    local _, addon, _, pages, _, game = readySettings()
    local visible, indexed = 0, 0
    for _, category in ipairs(game.rootCategories) do
        if category.redirectCategory then
            indexed = indexed + 1
            local target = game.layouts[category.redirectCategory]
            equal(target:IsVerticalLayout(), false)
            assert(target.frame.bar)
            local entries = game.layouts[category].initializers
            equal(#entries, #target.frame.rows + 1)
        else
            visible = visible + 1
            equal(category, addon.category)
        end
    end
    equal(visible, 1)
    equal(indexed, #addon.Bars)
    equal(#addon.category:GetSubcategories(), #pages)
    local settings = 0
    for _ in pairs(game.settings) do settings = settings + 1 end
    equal(settings, 3)
    for _, entry in ipairs(game.layouts[addon.category].initializers) do
        equal(entry.data.buttonClick, nil)
    end
end)

test("search Open actions select and scroll to every button without starting an edit", function()
    local env, addon, _, pages, messages, game = readySettings()
    for _, page in ipairs(pages) do
        local barEntry = findSearchEntry(game, addon.GetBarName(page.bar),
            page.category, addon.GetBarName(page.bar))
        barEntry.data.buttonClick()
        equal(game.currentCategory, page.category)
        equal(game.searchText, "")
        equal(game.navigation.force, true)
        page.Scroll:SetHeight(50)
        for _, row in ipairs(page.rows) do
            local entry = findSearchEntry(game, row.name, page.category, row.name)
            page.Scroll:SetVerticalScroll(0)
            entry.data.buttonClick()
            equal(game.currentCategory, page.category)
            equal(game.searchText, "")
            equal(game.navigation.force, true)
            equal(page:IsShown(), true)
            equal(page.selectedRow, row)
            equal(row.Highlight:IsShown(), true)
            equal(page.PreviewTitle:GetText(), row.name)
            equal(page.Scroll:GetVerticalScroll(), math.max(0, row.index * 25 - 50))
            equal(page.editingRow, nil)
            equal(row.Editor:IsShown(), false)
            assert(not row.Editor.focused)
        end
    end
    equal(next(env.CleanBindsDB.overrides), nil)
    equal(next(env.CleanBindsDB.bindingSnapshots), nil)
    equal(game.enabledSetting.writes, 0)
    equal(game.hideMacroNamesSetting.writes, 0)
    equal(game.fontSizeSetting.writes, 0)
    equal(#messages, 0)
end)

test("search navigation exits results even when the destination page was already selected", function()
    local env, _, _, pages, _, game = readySettings()
    local page = pages[2]
    env.SettingsPanel:SelectCategory(page.category, true)
    local entry = findSearchEntry(game, page.rows[3].name, page.category, page.rows[3].name)
    equal(game.currentCategory, page.category)
    equal(page:IsShown(), false)
    entry.data.buttonClick()
    equal(game.searchText, "")
    equal(page:IsShown(), true)
    equal(page.selectedRow, page.rows[3])
    equal(page.editingRow, nil)
end)

test("search supports native localized button names and numbered main-bar aliases", function()
    local _, addon, _, pages, _, game = readySettings({
        bindingNames = { MULTIACTIONBAR1BUTTON3 = "Localized button three" },
    })
    local page = pages[2]
    local entry = findSearchEntry(game, "localized button three", page.category, "Localized button three")
    entry.data.buttonClick()
    equal(page.selectedRow, page.rows[3])
    entry = findSearchEntry(game, "Action Bar 2 Button 3", page.category, page.rows[3].name)
    entry.data.buttonClick()
    equal(page.selectedRow, page.rows[3])
    local main = pages[1]
    entry = findSearchEntry(game, "Action Bar 1", main.category, addon.GetBarName(main.bar))
    entry.data.buttonClick()
    equal(game.currentCategory, main.category)
    entry = findSearchEntry(game, "Action Bar 1 Button 12", main.category, main.rows[12].name)
    entry.data.buttonClick()
    equal(main.selectedRow, main.rows[12])
end)

test("search navigation reads the current binding scope and stays available in combat", function()
    local env, addon, _, pages, messages, game = readySettings()
    local page = pages[2]
    assert(addon.SetLabel(page.bar, 1, "Account"))
    local entry = findSearchEntry(game, page.rows[1].name, page.category, page.rows[1].name)
    game.Switch(2)
    assert(addon.SetLabel(page.bar, 1, "Character"))
    game.combat = true
    entry.data.buttonClick()
    equal(page.selectedRow, page.rows[1])
    equal(page.rows[1].Override:GetText(), "Character")
    equal(page.rows[1].Override.enabled, false)
    equal(page.Description:GetText(), addon.L.CHARACTER_NOTICE)
    equal(page.editingRow, nil)
    equal(env.CleanBindsDB.overrides["actionbar2:1"], "Account")
    equal(env.CleanBindsCharacterDB.overrides["actionbar2:1"], "Character")
    equal(#messages, 0)
    for _, result in ipairs(game.Search("Clean Binds")) do
        equal(result.initializer.canModify(), false)
    end
end)

test("search does not index saved label values, current keys, or the generic Open caption", function()
    local _, addon, _, _, _, game = readySettings({
        bindings = { ACTIONBUTTON1 = { "UNIQUE_BINDING_VALUE" } },
    })
    assert(addon.SetLabel(addon.Bars[1], 1, "UniqueSavedLabel"))
    for _, query in ipairs({ "UniqueSavedLabel", "UNIQUE_BINDING_VALUE", "Open", "[" }) do
        equal(#game.Search(query), 0)
    end
    equal(addon.GetLabel(addon.Bars[1], 1), "UniqueSavedLabel")
end)

test("search navigation preserves the existing save-or-cancel behavior of unfinished edits", function()
    for _, valid in ipairs({ false, true }) do
        local env, addon, _, pages, messages, game = readySettings()
        local previous, destination = pages[1], pages[2]
        env.SettingsPanel:SelectCategory(previous.category, true)
        assert(addon.SetLabel(previous.bar, 1, "Original"))
        previous.rows[1].Override:OnClick()
        previous.rows[1].Editor:SetText(valid and "Draft" or "Invalid\nlabel")
        local entry = findSearchEntry(game, destination.rows[2].name,
            destination.category, destination.rows[2].name)
        entry.data.buttonClick()
        equal(previous.editingRow, nil)
        equal(addon.GetLabel(previous.bar, 1), valid and "Draft" or "Original")
        equal(destination.selectedRow, destination.rows[2])
        equal(destination.editingRow, nil)
        equal(#messages, valid and 0 or 1)
    end
end)

test("search-only categories do not interfere with native main Defaults or per-bar reset", function()
    local env, addon, _, pages, _, game = readySettings()
    assert(addon.SetLabel(addon.Bars[1], 1, "First"))
    assert(addon.SetLabel(addon.Bars[2], 1, "Second"))
    assert(addon.SetHideMacroNames(true))
    assert(addon.SetKeybindFontSize(14))
    local calls, reset = 0, addon.ResetLabels
    addon.ResetLabels = function(...)
        calls = calls + 1
        return reset(...)
    end
    for _, category in ipairs(game.rootCategories) do
        if category.redirectCategory then
            game.DefaultSettings("these", category)
        end
    end
    equal(calls, 0)
    local entry = findSearchEntry(game, pages[1].rows[1].name, pages[1].category, pages[1].rows[1].name)
    entry.data.buttonClick()
    game.ResetBar(pages[1])
    equal(calls, 1)
    equal(addon.GetLabel(addon.Bars[1], 1), nil)
    equal(addon.GetLabel(addon.Bars[2], 1), "Second")
    equal(addon.ShouldHideMacroNames(), true)
    equal(addon.GetKeybindFontSize(), 14)
    env.SettingsPanel:SelectCategory(addon.category, true)
    game.DefaultSettings("these", addon.category)
    equal(calls, 2)
    equal(addon.GetLabel(addon.Bars[2], 1), nil)
    equal(addon.ShouldHideMacroNames(), false)
    equal(addon.GetKeybindFontSize(), nil)
end)

test("missing native search navigation capabilities fail without writing saved data", function()
    for _, missing in ipairs({ "SettingsPanel.SelectCategory", "CreateSettingsButtonInitializer" }) do
        local env, addon, fire, messages = loadAddon({
            loggedIn = true,
            setup = function(environment)
                if missing == "SettingsPanel.SelectCategory" then
                    environment.SettingsPanel.SelectCategory = nil
                else
                    environment.CreateSettingsButtonInitializer = nil
                end
            end,
        })
        fire("ADDON_LOADED", "CleanBinds")
        equal(addon.state, "failed")
        equal(env.CleanBindsDB, nil)
        equal(env.CleanBindsCharacterDB, nil)
        assert(messages[1]:find(missing, 1, true))
    end
end)

print(("%d tests passed"):format(passed))
