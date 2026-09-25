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
        combat = false,
    }
    game.savedBindings[game.bindingSet] = copyTable(game.bindings)
    local environment = setmetatable({}, { __index = _G })
    environment._G = environment
    environment.CleanBindsDB = options.database
    environment.CleanBindsCharacterDB = options.characterDatabase
    environment.SlashCmdList = {}
    environment.Settings = {}
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
        "SaveBindings", "LoadBindings",
    }) do
        environment[name] = function()
            error("The addon must not call " .. name)
        end
    end

    for _, name in ipairs({
        "RegisterAddOnCategory", "RegisterVerticalLayoutCategory",
        "RegisterCanvasLayoutSubcategory", "RegisterProxySetting",
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
                frame.shown = true
                frame.text = ""
                frame.width, frame.height = 600, 400
                frame.mouseOver = false

                -- Layout is not simulated; interaction methods below are explicit.
                for _, method in ipairs({
                    "SetPoint", "ClearAllPoints", "SetAllPoints", "SetJustifyH",
                    "SetWordWrap", "SetFontObject", "SetScale", "SetMaxLines",
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
                function frame:IsTruncated()
                    return false
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
            environment.Settings.VarType = { Boolean = "boolean" }
            environment.Settings.RegisterVerticalLayoutCategory = function()
                return {}, { AddInitializer = noop }
            end
            environment.Settings.RegisterCanvasLayoutSubcategory = function(_, page)
                pages[#pages + 1] = page
                return {}
            end
            environment.Settings.RegisterAddOnCategory = noop
            environment.Settings.RegisterProxySetting = function(_, _, _, _, _, getter, setter)
                local setting = { updates = 0, writes = 0 }
                function setting:GetValue()
                    return getter()
                end
                function setting:SetValue(value)
                    self.writes = self.writes + 1
                    setter(value)
                end
                function setting:NotifyUpdate()
                    self.updates = self.updates + 1
                    self.displayedValue = getter()
                end
                game.enabledSetting = setting
                return setting
            end
            environment.Settings.CreateCheckbox = function() return initializer end
            environment.Settings.CreateElementInitializer = function(_, data)
                game.description = data.text
                return initializer
            end
            environment.CreateSettingsButtonInitializer = function() return initializer end
            environment.StaticPopupDialogs = {}
            environment.StaticPopup_Show = function(which, text, _, data)
                game.popup = { which = which, text = text, data = data }
            end
            environment.StaticPopup_Hide = function(which)
                if game.popup and game.popup.which == which then
                    game.popup = nil
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

test("stale reset confirmations cannot clear a new or revisited scope", function()
    local env, addon, _, pages, _, game = readySettings()
    local page = pages[1]
    page:Show()
    assert(addon.SetLabel(page.bar, 1, "Account"))
    page.Reset:OnClick()
    local stale = game.popup
    assert(stale.text:find(addon.L.ACCOUNT_SCOPE, 1, true))
    game.Switch(2)
    equal(game.popup, nil)
    assert(addon.SetLabel(page.bar, 1, "Character"))
    env.StaticPopupDialogs.CLEANBINDS_CONFIRM_RESET.OnAccept(nil, stale.data)
    equal(addon.GetLabel(page.bar, 1), "Character")
    game.Switch(1)
    env.StaticPopupDialogs.CLEANBINDS_CONFIRM_RESET.OnAccept(nil, stale.data)
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

print(("%d tests passed"):format(passed))
