local _, addon = ...
local records = {}
local warned = {}
local initialized = false
local refreshQueued = false

local function IsReadable(value)
    return type(issecretvalue) ~= "function" or not issecretvalue(value)
end

local function IsForbidden(object)
    return type(object.IsForbidden) == "function" and object:IsForbidden()
end

local function Warn(record)
    if not warned[record.button] then
        warned[record.button] = true
        addon.Print(addon.L.LABEL_ACCESS_BLOCKED:format(addon.GetBarName(record.bar), record.index))
    end
end

local function WriteText(record, text)
    record.writing = true
    local success, reason = pcall(record.hotkey.SetText, record.hotkey, text)
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
            WriteText(record, text)
            record.appliedText = text
        end
    elseif record.appliedText then
        WriteText(record, record.nativeText)
        record.appliedText = nil
    end
end

local function Track(button, bar, index)
    if not button then
        return
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
    }) do
        events:RegisterEvent(event)
    end
    events:SetScript("OnEvent", QueueRefresh)
end
