local _, addon = ...
local records = {}
local macroRecords = {}
local warned = {}
local initialized = false
local refreshQueued = false

local function IsReadable(value)
    return type(issecretvalue) ~= "function" or not issecretvalue(value)
end

local function IsForbidden(object)
    return type(object.IsForbidden) == "function" and object:IsForbidden()
end

local function Warn(record, message)
    message = message or addon.L.LABEL_ACCESS_BLOCKED
    local warnings = warned[record.button]
    if not warnings then
        warnings = {}
        warned[record.button] = warnings
    end
    if not warnings[message] then
        warnings[message] = true
        addon.Print(message:format(addon.GetBarName(record.bar), record.index))
    end
end

local function WriteRegion(record, region, method, value)
    record.writing = true
    local success, reason = pcall(region[method], region, value)
    record.writing = false
    if not success then
        error(reason, 0)
    end
end

local function Apply(record)
    if IsForbidden(record.button) or IsForbidden(record.hotkey) or not record.readable then
        if addon.GetLabel(record.bar, record.index) then
            Warn(record)
        end
        return
    end

    local _, keys = addon.GetBindingInfo(record.bar, record.index)
    local label = addon.IsEnabled() and keys[1] and addon.GetLabel(record.bar, record.index)
    local blankNativeText = record.nativeText == nil or record.nativeText == ""
    if blankNativeText and not record.allowBlank then
        label = nil
    end

    if label then
        local text = addon.LiteralLabel(label)
        -- The native range updater treats this exact string as an unbound range dot.
        if text == RANGE_INDICATOR then
            text = text .. "|r"
        end
        if record.appliedText ~= text then
            WriteRegion(record, record.hotkey, "SetText", text)
            record.appliedText = text
        end
    elseif record.appliedText then
        WriteRegion(record, record.hotkey, "SetText", record.nativeText)
        record.appliedText = nil
    end
end

local function ApplyMacroName(record)
    local hidden = addon.ShouldHideMacroNames()
    if IsForbidden(record.button) or IsForbidden(record.name) or not IsReadable(record.nativeAlpha) then
        if hidden or record.hidden then
            Warn(record, addon.L.MACRO_NAME_ACCESS_BLOCKED)
        end
        return
    end

    local isMacro = false
    if hidden then
        local action = record.button.action
        if not IsReadable(action) then
            Warn(record, addon.L.MACRO_NAME_ACCESS_BLOCKED)
        elseif type(action) == "number" and action > 0 then
            local actionType = GetActionInfo(action)
            if IsReadable(actionType) then
                isMacro = actionType == "macro"
            else
                Warn(record, addon.L.MACRO_NAME_ACCESS_BLOCKED)
            end
        end
    end

    if isMacro then
        if not record.hidden then
            WriteRegion(record, record.name, "SetAlpha", 0)
            record.hidden = true
        end
    elseif record.hidden then
        WriteRegion(record, record.name, "SetAlpha", record.nativeAlpha)
        record.hidden = false
    end
end

local function TrackMacroName(button, bar, index)
    local record = macroRecords[button]
    if record then
        ApplyMacroName(record)
        return
    end

    local name = button.Name
    if not name then
        return
    end
    if IsForbidden(button) or IsForbidden(name) then
        if addon.ShouldHideMacroNames() then
            Warn({ button = button, bar = bar, index = index }, addon.L.MACRO_NAME_ACCESS_BLOCKED)
        end
        return
    end

    record = {
        button = button,
        name = name,
        bar = bar,
        index = index,
        nativeAlpha = name:GetAlpha(),
    }
    macroRecords[button] = record
    hooksecurefunc(name, "SetAlpha", function(_, alpha)
        if record.writing then
            return
        end
        record.nativeAlpha = alpha
        record.hidden = false
        ApplyMacroName(record)
    end)
    hooksecurefunc(name, "SetText", function()
        ApplyMacroName(record)
    end)
    button:HookScript("OnShow", function()
        ApplyMacroName(record)
    end)
    ApplyMacroName(record)
end

local function Track(button, bar, index)
    if not button then
        return
    end

    if bar.id:match("^actionbar") then
        TrackMacroName(button, bar, index)
    end

    local record = records[button]
    if record then
        Apply(record)
        return
    end

    if IsForbidden(button) then
        if addon.GetLabel(bar, index) then
            Warn({ button = button, bar = bar, index = index })
        end
        return
    end

    local hotkey = button.HotKey
    if not hotkey or IsForbidden(hotkey) then
        if addon.GetLabel(bar, index) then
            Warn({ button = button, bar = bar, index = index })
        end
        return
    end

    local nativeText = hotkey:GetText()
    record = {
        button = button,
        hotkey = hotkey,
        bar = bar,
        index = index,
        nativeText = nativeText,
        readable = IsReadable(nativeText),
        allowBlank = bar.id == "stance",
    }
    records[button] = record

    hooksecurefunc(hotkey, "SetText", function(_, text)
        if record.writing then
            return
        end
        record.nativeText = text
        record.readable = IsReadable(text)
        record.allowBlank = false
        record.appliedText = nil
        Apply(record)
    end)
    button:HookScript("OnShow", function()
        Apply(record)
    end)
    Apply(record)
end

function addon.RefreshActionLabels()
    if not initialized then
        return
    end
    for _, bar in ipairs(addon.Bars) do
        for index = 1, bar.buttonCount do
            Track(addon.GetBarButton(bar, index), bar, index)
        end
        for _, mirror in ipairs(bar.mirrors or {}) do
            for index = 1, mirror.buttonCount do
                Track(addon.GetBarButton(mirror, index), bar, index)
            end
        end
    end
end

local function QueueRefresh()
    if not refreshQueued then
        refreshQueued = true
        C_Timer.After(0, function()
            refreshQueued = false
            addon.RefreshActionLabels()
        end)
    end
end

function addon.InitializeActionLabels()
    initialized = true
    addon.RefreshActionLabels()

    local events = CreateFrame("Frame")
    for _, event in ipairs({
        "ADDON_LOADED", "PLAYER_ENTERING_WORLD", "UPDATE_BINDINGS",
        "GAME_PAD_ACTIVE_CHANGED", "UPDATE_SHAPESHIFT_FORM", "PET_BAR_UPDATE",
        "UPDATE_VEHICLE_ACTIONBAR", "PLAYER_REGEN_ENABLED",
        "ACTIONBAR_SLOT_CHANGED", "ACTIONBAR_PAGE_CHANGED", "UPDATE_BONUS_ACTIONBAR", "UPDATE_MACROS",
    }) do
        events:RegisterEvent(event)
    end
    events:SetScript("OnEvent", QueueRefresh)
end
