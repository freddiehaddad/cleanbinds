local _, addon = ...
local L = addon.L
local slots, bars = {}, {}
local values = {}
local unverified = {}
local bindingSet, loadedSet, scopeError
local scopeReady = false
local scopeToken = 0
local loadPending = false
local loadSerial = 0

local function LabelKey(bar, index)
    return bar.id .. ":" .. index
end

local function IsSpace(codepoint)
    return codepoint == 32 or codepoint == 160 or codepoint == 5760
        or (codepoint >= 8192 and codepoint <= 8202)
        or codepoint == 8239 or codepoint == 8287 or codepoint == 12288
end

function addon.NormalizeLabel(text)
    if type(text) ~= "string" then
        return nil, L.INVALID_LABEL
    end

    local index, first, last = 1
    while index <= #text do
        local start = index
        local byte = text:byte(index)
        local length, minimum
        if byte < 128 then
            length, minimum = 1, 0
        elseif byte >= 194 and byte <= 223 then
            length, minimum = 2, 128
        elseif byte >= 224 and byte <= 239 then
            length, minimum = 3, 2048
        elseif byte >= 240 and byte <= 244 then
            length, minimum = 4, 65536
        else
            return nil, L.INVALID_UTF8
        end

        local codepoint = length == 1 and byte or byte % (2 ^ (7 - length))
        for offset = 1, length - 1 do
            local continuation = text:byte(index + offset)
            if not continuation or continuation < 128 or continuation > 191 then
                return nil, L.INVALID_UTF8
            end
            codepoint = codepoint * 64 + continuation - 128
        end
        if codepoint < minimum or codepoint > 1114111 or (codepoint >= 55296 and codepoint <= 57343) then
            return nil, L.INVALID_UTF8
        end
        if codepoint < 32 or (codepoint >= 127 and codepoint <= 159)
            or codepoint == 8232 or codepoint == 8233 then
            return nil, L.INVALID_LABEL
        end

        index = index + length
        if not IsSpace(codepoint) then
            first = first or start
            last = index - 1
        end
    end

    return first and text:sub(first, last) or ""
end

function addon.LiteralLabel(text)
    return (text:gsub("|", "||"))
end

local function Notify()
    if addon.RefreshSettings then
        addon.RefreshSettings()
    end
    if addon.RefreshActionLabels then
        addon.RefreshActionLabels()
    end
end

local function IsKnownScope(scope)
    return scope == Enum.BindingSet.Account or scope == Enum.BindingSet.Character
end

local function IsScopeReady()
    return scopeReady and not loadPending and bindingSet == GetCurrentBindingSet()
end

function addon.GetScopeName()
    if bindingSet == Enum.BindingSet.Account then
        return L.ACCOUNT_SCOPE
    elseif bindingSet == Enum.BindingSet.Character then
        return L.CHARACTER_SCOPE
    end
    return L.UNKNOWN_BINDING_SCOPE:format(tostring(bindingSet))
end

function addon.GetScopeNotice()
    if scopeError then
        return scopeError
    elseif not IsScopeReady() then
        return L.SCOPE_LOADING
    end
    return bindingSet == Enum.BindingSet.Account and L.ACCOUNT_NOTICE or L.CHARACTER_NOTICE
end

function addon.GetScopeToken()
    return scopeToken
end

function addon.CanEdit(expectedToken)
    if expectedToken ~= nil and expectedToken ~= scopeToken then
        return false, L.SCOPE_CHANGED
    elseif InCombatLockdown() then
        return false, L.COMBAT_READ_ONLY
    elseif scopeError then
        return false, scopeError
    elseif not IsScopeReady() then
        return false, L.SCOPE_LOADING
    end
    return true
end

function addon.IsEnabled()
    return IsScopeReady() and addon.db ~= nil and addon.db.enabled
end

local function InvalidateInteractions()
    scopeToken = scopeToken + 1
    if addon.CancelScopeInteractions then
        addon.CancelScopeInteractions()
    end
end

local function ValidSnapshot(snapshot, slot)
    local function ValidKey(key)
        return key == false or (type(key) == "string" and key ~= "" and not key:find("%c"))
    end
    return type(snapshot) == "table"
        and snapshot.command == slot.bar.bindingPrefix .. slot.index
        and type(snapshot.context) == "number"
        and snapshot.context >= 0 and snapshot.context % 1 == 0
        and ValidKey(snapshot.keyboard) and ValidKey(snapshot.gamepad)
        and (snapshot.device == "keyboard" or snapshot.device == "gamepad")
end

local function BindingChanged(before, after)
    if before.keyboard == false and before.gamepad == false then
        return false
    end
    return before.context ~= after.context or before[before.device] ~= after[before.device]
        or (before.device ~= after.device and before[after.device] ~= after[after.device])
end

local function ReconcileProfile(preserveUncertain)
    local cleared, skipped, unavailable = {}, 0, 0
    values = {}
    unverified = {}
    for id, text in pairs(addon.db.overrides) do
        local slot = slots[id]
        local normalized = slot and addon.NormalizeLabel(text)
        local before = addon.db.bindingSnapshots[id]
        if not normalized or normalized == "" or not ValidSnapshot(before, slot) then
            skipped = skipped + 1
        else
            local after = addon.GetBindingSnapshot(slot.bar, slot.index)
            if not after or (preserveUncertain and BindingChanged(before, after)) then
                unavailable = unavailable + 1
                unverified[id] = normalized
            elseif BindingChanged(before, after) then
                addon.db.overrides[id] = nil
                addon.db.bindingSnapshots[id] = nil
                cleared[#cleared + 1] = slot
            else
                values[id] = normalized
                addon.db.bindingSnapshots[id] = after
            end
        end
    end
    local scopeName = addon.GetScopeName()
    if skipped > 0 then
        addon.Print(L.SKIPPED_LABELS:format(scopeName, skipped))
    end
    if unavailable > 0 then
        addon.Print(L.SKIPPED_BINDINGS:format(scopeName, unavailable))
    end
    if #cleared == 1 then
        local slot = cleared[1]
        addon.Print(L.CLEARED_LABEL:format(GetBindingName(slot.bar.bindingPrefix .. slot.index), scopeName))
    elseif #cleared > 1 then
        addon.Print(L.CLEARED_LABELS:format(#cleared, scopeName))
    end
end

local function ActivateScope(scope, preserveUncertain)
    if scope ~= bindingSet or not scopeReady then
        InvalidateInteractions()
    end
    bindingSet = scope
    loadedSet = nil
    scopeReady = false
    values = {}
    unverified = {}
    local db, reason = addon.GetProfile(scope)
    addon.db = db
    scopeError = reason
    if not db then
        Notify()
        return false, reason
    end
    ReconcileProfile(preserveUncertain)
    scopeReady = true
    Notify()
    return true
end

local function ActivateAndReport(scope, preserveUncertain)
    local success, reason = ActivateScope(scope, preserveUncertain)
    if not success then
        addon.Print(reason)
    end
end

local function SuspendScope()
    if scopeReady then
        InvalidateInteractions()
    end
    scopeReady = false
    Notify()
end

local function OnBindingsSaved()
    local current = GetCurrentBindingSet()
    if loadPending then
        loadPending = false
        ActivateAndReport(current, true)
    elseif loadedSet and loadedSet ~= current then
        SuspendScope()
        addon.Print(L.SCOPE_LOADING)
    else
        ActivateAndReport(current)
    end
end

local function OnBindingsLoaded(scope)
    loadPending = false
    if scope == Enum.BindingSet.Default then
        -- Defaults are an uncommitted edit in the current scope, not another profile.
        loadedSet = nil
        Notify()
        return
    elseif scope == Enum.BindingSet.Current then
        scope = GetCurrentBindingSet()
    end

    if not IsKnownScope(scope) then
        ActivateAndReport(scope)
    elseif scope == GetCurrentBindingSet() then
        ActivateAndReport(scope)
    else
        loadedSet = scope
        SuspendScope()
    end
end

function addon.GetLabel(bar, index)
    if IsScopeReady() then
        return values[LabelKey(bar, index)]
    end
end

function addon.SetLabel(bar, index, text, expectedToken)
    local allowed, reason = addon.CanEdit(expectedToken)
    if not allowed then
        return false, reason
    end
    local id = LabelKey(bar, index)
    if not slots[id] then
        return false, L.INVALID_BUTTON
    end
    local normalized, validationError = addon.NormalizeLabel(text)
    if not normalized then
        return false, validationError
    end

    local snapshot
    if normalized ~= "" then
        snapshot, reason = addon.GetBindingSnapshot(bar, index)
        if not snapshot then
            return false, reason
        end
    end
    values[id] = normalized ~= "" and normalized or nil
    unverified[id] = nil
    addon.db.overrides[id] = values[id]
    addon.db.bindingSnapshots[id] = snapshot
    Notify()
    return true
end

function addon.SetEnabled(enabled, expectedToken)
    local allowed, reason = addon.CanEdit(expectedToken)
    if not allowed then
        return false, reason
    end
    if type(enabled) ~= "boolean" then
        return false, L.INVALID_DATABASE:format("enabled must be a boolean")
    end
    addon.db.enabled = enabled
    Notify()
    return true
end

function addon.ResetLabels(barID, expectedToken)
    local allowed, reason = addon.CanEdit(expectedToken)
    if not allowed then
        return false, reason
    end
    if barID and not bars[barID] then
        return false, L.INVALID_BAR
    end
    for _, entries in ipairs({ addon.db.overrides, addon.db.bindingSnapshots, values, unverified }) do
        for id in pairs(entries) do
            if not barID or (type(id) == "string" and id:sub(1, #barID + 1) == barID .. ":") then
                entries[id] = nil
            end
        end
    end
    Notify()
    return true
end

local function OnInputDeviceChanged()
    if not IsScopeReady() then
        return
    end
    for id in pairs(values) do
        local slot = slots[id]
        local before = addon.db.bindingSnapshots[id]
        local after = addon.GetBindingSnapshot(slot.bar, slot.index)
        if after and before.context == after.context
            and before.keyboard == after.keyboard and before.gamepad == after.gamepad then
            before.device = after.device
        end
    end
end

local function RetryBindingReads()
    if not IsScopeReady() then
        return
    end
    local restored = false
    for id, label in pairs(unverified) do
        local slot = slots[id]
        local before = addon.db.bindingSnapshots[id]
        local after = addon.GetBindingSnapshot(slot.bar, slot.index)
        if after and not BindingChanged(before, after) then
            values[id] = label
            unverified[id] = nil
            addon.db.bindingSnapshots[id] = after
            restored = true
        end
    end
    if restored then
        Notify()
    end
end

function addon.InitializeLabels()
    for _, bar in ipairs(addon.Bars) do
        bars[bar.id] = true
        for index = 1, bar.buttonCount do
            slots[LabelKey(bar, index)] = { bar = bar, index = index }
        end
    end
    local initialized, reason = ActivateScope(GetCurrentBindingSet())
    if not initialized then
        return false, reason
    end

    hooksecurefunc("SaveBindings", OnBindingsSaved)
    hooksecurefunc("LoadBindings", OnBindingsLoaded)
    local events = CreateFrame("Frame")
    events:RegisterEvent("BINDINGS_LOADED")
    events:RegisterEvent("GAME_PAD_ACTIVE_CHANGED")
    events:RegisterEvent("ADDON_LOADED")
    events:RegisterEvent("PLAYER_ENTERING_WORLD")
    events:SetScript("OnEvent", function(_, event)
        if event == "GAME_PAD_ACTIVE_CHANGED" then
            OnInputDeviceChanged()
        elseif event == "BINDINGS_LOADED" then
            loadPending = true
            loadSerial = loadSerial + 1
            local serial = loadSerial
            -- The synchronous event precedes the LoadBindings posthook that identifies its target.
            C_Timer.After(0, function()
                if loadPending and loadSerial == serial then
                    loadPending = false
                    ActivateAndReport(GetCurrentBindingSet(), true)
                end
            end)
        else
            RetryBindingReads()
        end
    end)
    return true
end
