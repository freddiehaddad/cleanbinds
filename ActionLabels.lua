local _, addon = ...
local hotkeyRecords = {}
local macroRecords = {}
local warned = {}
local initialized = false
local refreshQueued = false
local QueueRefresh

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

local function WriteRegion(record, region, method, ...)
    record.writing = record.writing or {}
    local previous = record.writing[method]
    record.writing[method] = true
    local success, reason = pcall(region[method], region, ...)
    record.writing[method] = previous
    if not success then
        error(reason, 0)
    end
end

local function ApplyHotkeyText(record)
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

local function IsFontReadable(font, size, flags)
    return IsReadable(font) and IsReadable(size) and IsReadable(flags)
        and type(font) == "string" and font ~= ""
        and type(size) == "number" and size > 0
        and (flags == nil or type(flags) == "string")
end

local function NativeFont(record)
    if record.fontObject then
        return record.fontObject:GetFont()
    end
    return record.nativeFont[1], record.nativeFont[2], record.nativeFont[3]
end

local function CaptureFont(record, fontObject)
    record.nativeFont = { record.hotkey:GetFont() }
    record.fontObject = nil
    if IsReadable(fontObject) and fontObject and type(fontObject.GetFont) == "function" then
        local font, size, flags = fontObject:GetFont()
        if IsFontReadable(font, size, flags) then
            record.fontObject = fontObject
            record.nativeFont = { font, size, flags }
        end
    end
end

local function ApplyHotkeyFont(record)
    local size = addon.GetKeybindFontSize()
    local _, keys = addon.GetBindingInfo(record.bar, record.index)
    if not keys[1] then
        size = nil
    end
    if not size and not record.fontManaged then
        return
    end
    if IsForbidden(record.button) or IsForbidden(record.hotkey) then
        Warn(record, addon.L.FONT_ACCESS_BLOCKED)
        return
    end
    local font, nativeSize, flags = NativeFont(record)
    local currentFont, currentSize, currentFlags = record.hotkey:GetFont()
    if not IsFontReadable(font, nativeSize, flags) or not IsFontReadable(currentFont, currentSize, currentFlags) then
        Warn(record, addon.L.FONT_ACCESS_BLOCKED)
        return
    end
    local desiredSize = size or nativeSize
    if currentFont ~= font or not ApproximatelyEqual(currentSize, desiredSize) or currentFlags ~= flags then
        WriteRegion(record, record.hotkey, "SetFont", font, desiredSize, flags)
    end
    record.fontManaged = true
end

local function ApplyHotkey(record)
    ApplyHotkeyFont(record)
    ApplyHotkeyText(record)
end

local function IsWritingFont(record)
    local writing = record.writing
    return writing and (writing.SetFont or writing.SetFontObject)
end

local function TrackFont(record)
    local hotkey = record.hotkey
    CaptureFont(record)
    local object = hotkey:GetFontObject()
    if IsReadable(object) and object then
        local font, size, flags = object:GetFont()
        if IsFontReadable(record.nativeFont[1], record.nativeFont[2], record.nativeFont[3])
            and IsFontReadable(font, size, flags) and font == record.nativeFont[1]
            and ApproximatelyEqual(size, record.nativeFont[2]) and flags == record.nativeFont[3] then
            record.fontObject = object
        end
    end
    hooksecurefunc(hotkey, "SetFont", function(_, font, size, flags)
        if not IsWritingFont(record) then
            record.nativeFont = { font, size, flags }
            record.fontObject = nil
            ApplyHotkeyFont(record)
            QueueRefresh()
        end
    end)
    hooksecurefunc(hotkey, "SetFontObject", function()
        if not IsWritingFont(record) then
            CaptureFont(record, hotkey:GetFontObject())
            ApplyHotkeyFont(record)
            QueueRefresh()
        end
    end)
    hooksecurefunc(hotkey, "SetHeight", QueueRefresh)
    hooksecurefunc(hotkey, "SetSize", QueueRefresh)
end

function addon.GetPreviewKeybindFont(button, useNativeFont)
    local hotkey = button and button.HotKey
    if button and IsForbidden(button) or hotkey and IsForbidden(hotkey) then
        return nil, addon.L.FONT_REFERENCE_UNAVAILABLE
    end
    local font, size, flags
    local record = useNativeFont and button and hotkeyRecords[button]
    if record then
        font, size, flags = NativeFont(record)
    else
        font, size, flags = (hotkey or NumberFontNormalSmallGray):GetFont()
    end
    if not IsFontReadable(font, size, flags) then
        return nil, addon.L.FONT_REFERENCE_UNAVAILABLE
    end
    if not useNativeFont then
        size = addon.GetKeybindFontSize() or size
    end
    return font, size, flags
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
        if record.writing and record.writing.SetAlpha then
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

local function TrackButton(button, bar, index)
    if not button then
        return
    end

    if bar.id:match("^actionbar") then
        TrackMacroName(button, bar, index)
    end

    local record = hotkeyRecords[button]
    if record then
        ApplyHotkey(record)
        return
    end

    if IsForbidden(button) then
        if addon.GetLabel(bar, index) then
            Warn({ button = button, bar = bar, index = index })
        end
        if addon.GetKeybindFontSize() then
            Warn({ button = button, bar = bar, index = index }, addon.L.FONT_ACCESS_BLOCKED)
        end
        return
    end

    local hotkey = button.HotKey
    if not hotkey or IsForbidden(hotkey) then
        if addon.GetLabel(bar, index) then
            Warn({ button = button, bar = bar, index = index })
        end
        if hotkey and addon.GetKeybindFontSize() then
            Warn({ button = button, bar = bar, index = index }, addon.L.FONT_ACCESS_BLOCKED)
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
    hotkeyRecords[button] = record
    TrackFont(record)

    hooksecurefunc(hotkey, "SetText", function(_, text)
        if record.writing and record.writing.SetText then
            return
        end
        record.nativeText = text
        record.readable = IsReadable(text)
        record.allowBlank = false
        record.appliedText = nil
        ApplyHotkey(record)
    end)
    button:HookScript("OnShow", function()
        ApplyHotkey(record)
    end)
    ApplyHotkey(record)
end

function addon.RefreshActionLabels()
    if not initialized then
        return
    end
    for _, bar in ipairs(addon.Bars) do
        for index = 1, bar.buttonCount do
            TrackButton(addon.GetBarButton(bar, index), bar, index)
        end
        for _, mirror in ipairs(bar.mirrors or {}) do
            for index = 1, mirror.buttonCount do
                TrackButton(addon.GetBarButton(mirror, index), bar, index)
            end
        end
    end
end

QueueRefresh = function()
    if not refreshQueued then
        refreshQueued = true
        C_Timer.After(0, function()
            refreshQueued = false
            addon.RefreshActionLabels()
            if addon.RefreshSettings then
                addon.RefreshSettings()
            end
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
        "UI_SCALE_CHANGED",
        "ACTIONBAR_SLOT_CHANGED", "ACTIONBAR_PAGE_CHANGED", "UPDATE_BONUS_ACTIONBAR", "UPDATE_MACROS",
    }) do
        events:RegisterEvent(event)
    end
    events:SetScript("OnEvent", QueueRefresh)
end
