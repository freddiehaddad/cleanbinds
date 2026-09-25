local _, addon = ...
local L = addon.L

local normalBars = {
    { "MainActionBar", "ACTIONBUTTON" },
    { "MultiBarBottomLeft", "MULTIACTIONBAR1BUTTON" },
    { "MultiBarBottomRight", "MULTIACTIONBAR2BUTTON" },
    { "MultiBarRight", "MULTIACTIONBAR3BUTTON" },
    { "MultiBarLeft", "MULTIACTIONBAR4BUTTON" },
    { "MultiBar5", "MULTIACTIONBAR5BUTTON" },
    { "MultiBar6", "MULTIACTIONBAR6BUTTON" },
    { "MultiBar7", "MULTIACTIONBAR7BUTTON" },
}

addon.Bars = {}

for number, definition in ipairs(normalBars) do
    addon.Bars[#addon.Bars + 1] = {
        id = "actionbar" .. number,
        frameName = definition[1],
        buttonNamePrefix = number == 1 and "ActionButton" or definition[1] .. "Button",
        bindingPrefix = definition[2],
        buttonCount = 12,
        nameKey = number == 1 and "BINDING_HEADER_ACTIONBAR" or "BINDING_HEADER_ACTIONBAR" .. number,
        fallbackName = number == 1 and L.MAIN_ACTION_BAR or L.ACTION_BAR:format(number),
    }
end

addon.Bars[1].mirrors = {
    {
        frameName = "OverrideActionBar",
        buttonNamePrefix = "OverrideActionBarButton",
        buttonCount = 6,
    },
}

local specialBars = {
    {
        id = "pet",
        frameName = "PetActionBar",
        buttonNamePrefix = "PetActionButton",
        bindingPrefix = "BONUSACTIONBUTTON",
        buttonCount = 10,
        nameKey = "HUD_EDIT_MODE_PET_ACTION_BAR_LABEL",
        fallbackName = L.PET_BAR,
    },
    {
        id = "stance",
        frameName = "StanceBar",
        buttonNamePrefix = "StanceButton",
        bindingPrefix = "SHAPESHIFTBUTTON",
        buttonCount = 10,
        nameKey = "HUD_EDIT_MODE_STANCE_BAR_LABEL",
        fallbackName = L.STANCE_BAR,
    },
}

for _, bar in ipairs(specialBars) do
    addon.Bars[#addon.Bars + 1] = bar
end

function addon.GetBarName(bar)
    return (bar.nameKey and _G[bar.nameKey]) or bar.fallbackName
end

function addon.GetBarButton(bar, index)
    local frame = _G[bar.frameName]
    if not frame then
        return nil
    end

    if frame.actionButtons then
        return frame.actionButtons[index]
    end
    return bar.buttonNamePrefix and _G[bar.buttonNamePrefix .. index]
end

function addon.CountBarButtons(bar)
    local count = 0
    for index = 1, bar.buttonCount do
        if addon.GetBarButton(bar, index) then
            count = count + 1
        end
    end
    return count
end

function addon.GetLabelUnavailableReason(bar, index)
    if not bar.bindingPrefix then
        return L.NO_NATIVE_LABEL
    end

    local button = addon.GetBarButton(bar, index)
    if button and not button.HotKey then
        return L.NO_NATIVE_LABEL
    end
end

function addon.GetBindingInfo(bar, index)
    local command = bar.bindingPrefix .. index
    local context = C_KeyBindings.GetBindingContextForAction(command)
    local keys = { GetBindingKey(command, nil, context) }
    if not keys[1] then
        keys = { GetBindingKey("CLICK " .. bar.buttonNamePrefix .. index .. ":LeftButton", nil, context) }
    end
    return command, keys
end

function addon.GetBindingSnapshot(bar, index)
    local command, displayed = addon.GetBindingInfo(bar, index)
    local bindingIndex = C_KeyBindings.GetBindingIndex(command)
    if not bindingIndex then
        return nil, L.BINDING_UNAVAILABLE
    end

    local result = { GetBinding(bindingIndex, true) }
    if result[1] ~= command then
        return nil, L.BINDING_UNAVAILABLE
    end
    local snapshot = {
        command = command,
        context = C_KeyBindings.GetBindingContextForAction(command) or 0,
        keyboard = false,
        gamepad = false,
        device = displayed[1] and IsBindingForGamePad(displayed[1]) and "gamepad" or "keyboard",
    }
    local function IncludeKey(key)
        if type(key) ~= "string" or key == "" then
            return false
        end
        local device = IsBindingForGamePad(key) and "gamepad" or "keyboard"
        if snapshot[device] == false then
            snapshot[device] = key
        end
        return true
    end
    for offset = 3, #result do
        if not IncludeKey(result[offset]) then
            return nil, L.BINDING_UNAVAILABLE
        end
    end

    local fallback = { GetBindingKey("CLICK " .. bar.buttonNamePrefix .. index .. ":LeftButton", nil, snapshot.context) }
    for _, key in ipairs(fallback) do
        if not IncludeKey(key) then
            return nil, L.BINDING_UNAVAILABLE
        end
    end
    if not displayed[1] and snapshot.keyboard == false and snapshot.gamepad ~= false then
        snapshot.device = "gamepad"
    end
    return snapshot
end
