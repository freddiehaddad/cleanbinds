local _, addon = ...
local L = addon.L
local slots, bars = {}, {}
local values, anchors, observed, edited = {}, {}, {}, {}
local bindingSet
local loadPending = false

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

local function CaptureBindings()
    local snapshot = {}
    for id, slot in pairs(slots) do
        local _, keys = addon.GetBindingInfo(slot.bar, slot.index)
        snapshot[id] = keys
    end
    return snapshot
end

local function Contains(keys, key)
    for _, candidate in ipairs(keys) do
        if candidate == key then
            return true
        end
    end
    return false
end

local function SameKeys(left, right, ordered)
    if #left ~= #right then
        return false
    end
    for index, key in ipairs(left) do
        if (ordered and right[index] ~= key) or (not ordered and not Contains(right, key)) then
            return false
        end
    end
    return true
end

local function Rebase(snapshot, selectedSet)
    observed = snapshot
    edited = {}
    anchors = {}
    bindingSet = selectedSet or GetCurrentBindingSet()
    for id in pairs(values) do
        anchors[id] = snapshot[id]
    end
end

local function ObserveEdit(key)
    local current = CaptureBindings()
    for id, keys in pairs(current) do
        local previous = observed[id]
        if not SameKeys(previous, keys, true)
            and (key == nil or Contains(previous, key) or Contains(keys, key)) then
            edited[id] = true
        end
    end
    observed = current
end

local function OnBindingsSaved()
    local current = CaptureBindings()
    local currentSet = GetCurrentBindingSet()
    if loadPending or currentSet ~= bindingSet then
        loadPending = false
        Rebase(current, currentSet)
        Notify()
        return
    end

    local cleared = {}
    for id in pairs(values) do
        local before = anchors[id]
        local after = current[id]
        if before and before[1] and before[1] ~= after[1]
            and (edited[id] or not SameKeys(before, after, false)) then
            values[id] = nil
            addon.db.overrides[id] = nil
            cleared[#cleared + 1] = id
        end
    end
    Rebase(current, currentSet)
    Notify()
    if #cleared == 1 then
        local slot = slots[cleared[1]]
        local name = GetBindingName(slot.bar.bindingPrefix .. slot.index)
        addon.Print(L.CLEARED_LABEL:format(name))
    elseif #cleared > 1 then
        addon.Print(L.CLEARED_LABELS:format(#cleared))
    end
end

local function OnBindingsLoaded(selectedSet)
    loadPending = false
    if selectedSet == Enum.BindingSet.Default then
        ObserveEdit()
    else
        local knownSet = selectedSet == Enum.BindingSet.Account or selectedSet == Enum.BindingSet.Character
        Rebase(CaptureBindings(), knownSet and selectedSet or nil)
    end
    Notify()
end

function addon.GetLabel(bar, index)
    return values[LabelKey(bar, index)]
end

function addon.SetLabel(bar, index, text)
    if InCombatLockdown() then
        return false, L.COMBAT_READ_ONLY
    end

    local id = LabelKey(bar, index)
    if not slots[id] then
        return false, L.INVALID_BUTTON
    end
    local normalized, reason = addon.NormalizeLabel(text)
    if not normalized then
        return false, reason
    end

    local _, keys = addon.GetBindingInfo(bar, index)
    values[id] = normalized ~= "" and normalized or nil
    addon.db.overrides[id] = values[id]
    -- An edit made after a pending rebind belongs to the new binding, not the old one.
    anchors[id] = values[id] and keys or nil
    edited[id] = nil
    Notify()
    return true
end

function addon.ResetLabels(barID)
    if InCombatLockdown() then
        return false, L.COMBAT_READ_ONLY
    end
    if barID and not bars[barID] then
        return false, L.INVALID_BAR
    end
    for id in pairs(addon.db.overrides) do
        if not barID or (type(id) == "string" and id:sub(1, #barID + 1) == barID .. ":") then
            addon.db.overrides[id] = nil
            values[id] = nil
            anchors[id] = nil
            edited[id] = nil
        end
    end
    Notify()
    return true
end

function addon.InitializeLabels()
    for _, bar in ipairs(addon.Bars) do
        bars[bar.id] = true
        for index = 1, bar.buttonCount do
            slots[LabelKey(bar, index)] = { bar = bar, index = index }
        end
    end

    local skipped = 0
    for id, text in pairs(addon.db.overrides) do
        local normalized = slots[id] and addon.NormalizeLabel(text)
        if normalized then
            values[id] = normalized ~= "" and normalized or nil
            addon.db.overrides[id] = values[id]
        else
            skipped = skipped + 1
        end
    end
    if skipped > 0 then
        addon.Print(L.SKIPPED_LABELS:format(skipped))
    end
    Rebase(CaptureBindings())

    hooksecurefunc("SaveBindings", OnBindingsSaved)
    hooksecurefunc("LoadBindings", OnBindingsLoaded)
    for _, name in ipairs({ "SetBinding", "SetBindingClick", "SetBindingSpell", "SetBindingItem", "SetBindingMacro" }) do
        if type(_G[name]) == "function" then
            hooksecurefunc(name, ObserveEdit)
        end
    end

    local events = CreateFrame("Frame")
    events:RegisterEvent("BINDINGS_LOADED")
    events:RegisterEvent("GAME_PAD_ACTIVE_CHANGED")
    events:SetScript("OnEvent", function(_, event)
        if event == "GAME_PAD_ACTIVE_CHANGED" then
            observed = CaptureBindings()
        else
            loadPending = true
            -- LoadBindings emits this synchronously, before its posthook supplies the load reason.
            C_Timer.After(0, function()
                if loadPending then
                    loadPending = false
                    Rebase(CaptureBindings())
                    Notify()
                end
            end)
        end
    end)
end
