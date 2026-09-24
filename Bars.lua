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
        bindingPrefix = definition[2],
        hotkeyMethod = "UpdateHotkeys",
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
        bindingPrefix = "BONUSACTIONBUTTON",
        hotkeyMethod = "SetHotkeys",
        buttonCount = 10,
        nameKey = "HUD_EDIT_MODE_PET_ACTION_BAR_LABEL",
        fallbackName = L.PET_BAR,
    },
    {
        id = "stance",
        frameName = "StanceBar",
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

    if bar.buttonNamePrefix then
        return _G[bar.buttonNamePrefix .. index]
    end

    return frame.actionButtons and frame.actionButtons[index]
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
    local button = addon.GetBarButton(bar, index)
    if not keys[1] and button then
        keys = { GetBindingKey("CLICK " .. button:GetName() .. ":LeftButton", nil, context) }
    end
    return command, keys
end
