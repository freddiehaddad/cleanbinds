local _, addon = ...
local L = addon.L
local pages = {}
local rowHeight = 25
local previewSize = 56
local previewScale = previewSize / 45
-- SettingsList's -15 scroll offset plus 25 units of left padding.
local listLeftInset, listRightInset = 10, 20

CleanBindsDescriptionMixin = {}

function CleanBindsDescriptionMixin:Init(initializer)
    self.Text:SetText(initializer.data.text)
end

local function SetNotice(page, text)
    page.notice = text
    page.Status:SetText(text or "")
end

local function AddText(parent, font, text)
    local label = parent:CreateFontString(nil, "OVERLAY", font)
    label:SetJustifyH("LEFT")
    label:SetText(text)
    return label
end

local function RefreshBinding(row)
    local bar = row.page.bar
    local command, keys = addon.GetBindingInfo(bar, row.index)
    row.keys = keys
    row.name = GetBindingName(command)
    row.Label:SetText(row.name)
    row.Binding:SetText(row.keys[1] and GetBindingText(row.keys[1]) or L.NOT_BOUND)
    row.defaultLabel = row.keys[1] and GetBindingText(row.keys[1], true) or ""
    row.unavailableReason = addon.GetLabelUnavailableReason(bar, row.index)
end

local function RefreshCell(row)
    local label = addon.GetLabel(row.page.bar, row.index)
    row.Override:SetText(row.unavailableReason and L.UNAVAILABLE or (label and addon.LiteralLabel(label) or L.DEFAULT_LABEL))
    row.Override:SetEnabled(not InCombatLockdown() and not row.unavailableReason)
end

local function UpdatePreviewGeometry(preview, button)
    local hotkey = button and button.HotKey
    local sample = preview.Button
    local label = preview.HotKey
    local width, height = 45, 45
    local labelWidth, labelHeight = 37, 10
    local accurate = hotkey ~= nil

    label:ClearAllPoints()
    if hotkey then
        width, height = button:GetSize()
        labelWidth, labelHeight = hotkey:GetSize()
        label:SetFont(hotkey:GetFont())
        label:SetJustifyH(hotkey:GetJustifyH())
        label:SetJustifyV(hotkey:GetJustifyV())
        label:SetShadowColor(hotkey:GetShadowColor())
        label:SetShadowOffset(hotkey:GetShadowOffset())
        label:SetTextColor(hotkey:GetTextColor())

        local pointCount = hotkey:GetNumPoints()
        accurate = pointCount > 0
        for index = 1, pointCount do
            local point, relative, relativePoint, x, y = hotkey:GetPoint(index)
            if relative == button or relative == button.TextOverlayContainer then
                label:SetPoint(point, sample, relativePoint, x, y)
            else
                accurate = false
            end
        end
    else
        label:SetFontObject(NumberFontNormalSmallGray)
    end

    if not accurate then
        label:ClearAllPoints()
        label:SetPoint("TOPRIGHT", sample, "TOPRIGHT", -4, -5)
    end

    sample:SetSize(width, height)
    sample:SetScale(previewScale)
    label:SetSize(labelWidth, labelHeight)

    local border = button and button:GetNormalTexture()
    if border and border:GetAtlas() then
        preview.Border:SetAtlas(border:GetAtlas())
        preview.Border:SetSize(border:GetSize())
    else
        preview.Border:SetAtlas("UI-HUD-ActionBar-IconFrame")
        preview.Border:SetSize(46, 45)
    end

    return accurate and labelWidth > 0 and labelHeight > 0
end

local function UpdatePreview(page)
    local row = page.selectedRow
    if not row then
        return
    end

    local available = not row.unavailableReason
    page.Preview:SetShown(available)
    page.PreviewTitle:SetShown(available)
    page.PreviewDefault:SetShown(available)
    if not available then
        page.Status:SetText(row.unavailableReason)
        return
    end

    local button = addon.GetBarButton(page.bar, row.index)
    local accurate = UpdatePreviewGeometry(page.Preview, button)
    local label = row.editing and row.Editor:GetText() or addon.GetLabel(page.bar, row.index)
    local customLabel, validationError = addon.NormalizeLabel(label or "")
    page.Preview.HotKey:SetText(customLabel and customLabel ~= "" and addon.LiteralLabel(customLabel) or row.defaultLabel)
    page.PreviewTitle:SetText(row.name)
    page.PreviewDefault:SetText(L.PREVIEW_DEFAULT:format(row.defaultLabel ~= "" and row.defaultLabel or L.NOT_BOUND))

    if page.notice then
        page.Status:SetText(page.notice)
    elseif validationError then
        page.Status:SetText(validationError)
    elseif InCombatLockdown() then
        page.Status:SetText(L.COMBAT_READ_ONLY)
    elseif page.Preview.HotKey:IsTruncated() then
        page.Status:SetText(L.LABEL_TOO_WIDE)
    elseif not row.keys[1] then
        page.Status:SetText(L.UNBOUND_NOTICE)
    elseif not accurate then
        page.Status:SetText(L.PREVIEW_APPROXIMATE)
    else
        local barFrame = _G[page.bar.frameName]
        if not barFrame then
            page.Status:SetText(L.BAR_INACTIVE)
        elseif not barFrame:IsShown() then
            page.Status:SetText(page.bar.id:match("^actionbar") and L.BAR_HIDDEN or L.BAR_INACTIVE)
        else
            page.Status:SetText("")
        end
    end
end

local function SelectRow(row)
    local page = row.page
    if page.editingRow and page.editingRow ~= row then
        return
    end
    if page.selectedRow then
        page.selectedRow.Highlight:Hide()
    end
    page.selectedRow = row
    row.Highlight:Show()
    UpdatePreview(page)
end

local function CloseEditor(row)
    row.editing = false
    if row.page.editingRow == row then
        row.page.editingRow = nil
    end
    row.Editor:ClearFocus()
    row.Editor:Hide()
    row.Override:Show()
    RefreshCell(row)
    UpdatePreview(row.page)
end

local function CancelEdit(row, notice)
    SetNotice(row.page, notice)
    CloseEditor(row)
end

local function CommitEdit(row)
    if not row.editing then
        return true
    end
    if InCombatLockdown() then
        CancelEdit(row, L.COMBAT_CANCELED)
        return false
    end

    local success, reason = addon.SetLabel(row.page.bar, row.index, row.Editor:GetText())
    if not success then
        SetNotice(row.page, reason)
        return false
    end

    SetNotice(row.page, nil)
    CloseEditor(row)
    return true
end

local function FinishPageEdit(page)
    local row = page.editingRow
    if row and not CommitEdit(row) then
        addon.Print(page.notice or L.INVALID_LABEL)
        CloseEditor(row)
    end
end

local function BeginEdit(row)
    if InCombatLockdown() then
        SetNotice(row.page, L.COMBAT_READ_ONLY)
        return
    end
    if row.unavailableReason then
        SetNotice(row.page, row.unavailableReason)
        return
    end
    local previous = row.page.editingRow
    if previous and previous ~= row and not CommitEdit(previous) then
        return
    end

    SetNotice(row.page, nil)
    SelectRow(row)
    row.editing = true
    row.page.editingRow = row
    row.Override:Hide()
    row.Editor:SetText(addon.GetLabel(row.page.bar, row.index) or "")
    row.Editor:Show()
    row.Editor:SetFocus()
    row.Editor:HighlightText()

    local scroll = row.page.Scroll
    local top = (row.index - 1) * rowHeight
    local offset = scroll:GetVerticalScroll()
    if top < offset then
        scroll:SetVerticalScroll(top)
    elseif top + rowHeight > offset + scroll:GetHeight() then
        scroll:SetVerticalScroll(top + rowHeight - scroll:GetHeight())
    end
    UpdatePreview(row.page)
end

local function ShowBindingTooltip(row, owner, editable)
    SelectRow(row)
    GameTooltip:SetOwner(owner, "ANCHOR_RIGHT")
    GameTooltip:SetText(row.name)
    for index, key in ipairs(row.keys) do
        local format = index == 1 and L.PRIMARY_BINDING or L.OTHER_BINDING
        GameTooltip:AddLine(format:format(GetBindingText(key)), 1, 1, 1, true)
    end
    GameTooltip:AddLine(row.unavailableReason or (editable and L.EDIT_HINT or L.READ_ONLY_BINDING), 0.8, 0.8, 0.8, true)
    GameTooltip:Show()
end

local function RefreshPage(page)
    for _, row in ipairs(page.rows) do
        RefreshBinding(row)
        if row.editing and row.unavailableReason then
            CancelEdit(row, row.unavailableReason)
        end
        RefreshCell(row)
    end
    page.Reset:SetEnabled(not InCombatLockdown())
    UpdatePreview(page)
end

local function RefreshPages()
    for _, page in ipairs(pages) do
        if page:IsShown() then
            RefreshPage(page)
        end
    end
end
addon.RefreshSettings = RefreshPages

local function ResetLabels(barID)
    local success, reason = addon.ResetLabels(barID)
    if not success then
        addon.Print(reason)
    end
end

local function ConfirmReset(bar)
    if InCombatLockdown() then
        addon.Print(L.COMBAT_READ_ONLY)
        return
    end
    local message = bar and L.RESET_BAR_CONFIRM:format(addon.GetBarName(bar)) or L.RESET_ALL_CONFIRM
    StaticPopup_Show("CLEANBINDS_CONFIRM_RESET", message, nil, { barID = bar and bar.id })
end

local function CreateRow(page, index)
    local row = CreateFrame("Frame", nil, page.Content, "CleanBindsBindingRowTemplate")
    row.page = page
    row.index = index
    row:SetPoint("TOPLEFT", 0, -(index - 1) * rowHeight)
    row:SetPoint("TOPRIGHT", 0, -(index - 1) * rowHeight)
    row.Override:SetScript("OnClick", function()
        BeginEdit(row)
    end)
    row.Override:SetScript("OnEnter", function(self)
        ShowBindingTooltip(row, self, true)
    end)
    row.Binding:SetScript("OnEnter", function(self)
        ShowBindingTooltip(row, self, false)
    end)
    row.Override:SetScript("OnLeave", function()
        GameTooltip:Hide()
    end)
    row.Binding:SetScript("OnLeave", function()
        GameTooltip:Hide()
    end)
    row.Label:SetScript("OnEnter", function()
        ShowBindingTooltip(row, row, false)
    end)
    row.Label:SetScript("OnLeave", function()
        GameTooltip:Hide()
    end)
    row:SetScript("OnEnter", function()
        SelectRow(row)
    end)
    row.Editor:SetScript("OnTextChanged", function()
        if row.editing then
            SetNotice(page, nil)
            UpdatePreview(page)
        end
    end)
    row.Editor:SetScript("OnEnterPressed", function()
        CommitEdit(row)
    end)
    row.Editor:SetScript("OnEscapePressed", function()
        CancelEdit(row)
    end)
    row.Editor:SetScript("OnEditFocusLost", function()
        if not CommitEdit(row) then
            CloseEditor(row)
        end
    end)
    row.Editor:SetScript("OnTabPressed", function()
        if CommitEdit(row) then
            local step = IsShiftKeyDown() and -1 or 1
            BeginEdit(page.rows[(index - 1 + step) % #page.rows + 1])
        end
    end)
    page.rows[index] = row
    RefreshBinding(row)
    RefreshCell(row)
end

local function CreatePage(bar)
    local page = CreateFrame("Frame")
    page:Hide()
    page.bar = bar
    page.rows = {}

    local title = AddText(page, "GameFontNormalLarge", addon.GetBarName(bar))
    title:SetPoint("TOPLEFT", 16, -16)
    local description = AddText(page, "GameFontHighlightSmall", L.SESSION_NOTICE)
    description:SetPoint("TOPLEFT", 16, -46)
    description:SetPoint("TOPRIGHT", -16, -46)

    local header = CreateFrame("Frame", nil, page)
    header:SetPoint("TOPLEFT", listLeftInset, -85)
    header:SetPoint("TOPRIGHT", -listRightInset, -85)
    header:SetHeight(20)
    local actionHeading = AddText(header, "GameFontNormalSmall", L.ACTION_BUTTON)
    actionHeading:SetPoint("LEFT", 37, 0)
    local bindingHeading = AddText(header, "GameFontNormalSmall", L.CURRENT_BINDING)
    bindingHeading:SetPoint("LEFT", header, "CENTER", -80, 0)
    bindingHeading:SetWidth(160)
    bindingHeading:SetJustifyH("CENTER")
    local labelHeading = AddText(header, "GameFontNormalSmall", L.CUSTOM_LABEL)
    labelHeading:SetPoint("LEFT", bindingHeading, "RIGHT")
    labelHeading:SetWidth(160)
    labelHeading:SetJustifyH("CENTER")

    page.Scroll = CreateFrame("ScrollFrame", nil, page, "ScrollFrameTemplate")
    page.Scroll:SetPoint("TOPLEFT", listLeftInset, -108)
    page.Scroll:SetPoint("BOTTOMRIGHT", -listRightInset, 142)
    page.Scroll.ScrollBar:SetHideIfUnscrollable(true)
    page.Content = CreateFrame("Frame", nil, page.Scroll)
    page.Content:SetSize(1, bar.buttonCount * rowHeight)
    page.Scroll:SetScrollChild(page.Content)
    page.Scroll:HookScript("OnSizeChanged", function(self, width)
        page.Content:SetWidth(math.max(1, width))
    end)

    page.Preview = CreateFrame("Frame", nil, page)
    page.Preview:SetSize(previewSize, previewSize)
    page.Preview:SetPoint("BOTTOMLEFT", 16, 60)
    page.Preview.Button = CreateFrame("Frame", nil, page.Preview)
    page.Preview.Button:SetPoint("CENTER")
    local background = page.Preview.Button:CreateTexture(nil, "BACKGROUND")
    background:SetAllPoints()
    background:SetAtlas("UI-HUD-ActionBar-IconFrame-Background")
    page.Preview.Border = page.Preview.Button:CreateTexture(nil, "BORDER")
    page.Preview.Border:SetPoint("TOPLEFT")
    page.Preview.HotKey = page.Preview.Button:CreateFontString(nil, "OVERLAY", "NumberFontNormalSmallGray")
    page.Preview.HotKey:SetWordWrap(false)
    page.Preview.HotKey:SetMaxLines(1)
    page.PreviewTitle = AddText(page, "GameFontNormal", L.PREVIEW)
    page.PreviewTitle:SetPoint("BOTTOMLEFT", page.Preview, "RIGHT", 14, 3)
    page.PreviewDefault = AddText(page, "GameFontHighlightSmall", "")
    page.PreviewDefault:SetPoint("TOPLEFT", page.Preview, "RIGHT", 14, -3)
    page.Status = AddText(page, "GameFontNormalSmall", "")
    page.Status:SetPoint("BOTTOMLEFT", 16, 38)
    page.Status:SetPoint("BOTTOMRIGHT", -16, 38)

    page.Reset = CreateFrame("Button", nil, page, "UIPanelButtonTemplate")
    page.Reset:SetSize(150, 22)
    page.Reset:SetPoint("BOTTOMRIGHT", -16, 8)
    page.Reset:SetText(L.RESET_BAR)
    page.Reset:SetScript("OnClick", function()
        ConfirmReset(bar)
    end)
    for index = 1, bar.buttonCount do
        CreateRow(page, index)
    end
    SelectRow(page.rows[1])
    page:SetScript("OnShow", function()
        page.Content:SetWidth(math.max(1, page.Scroll:GetWidth()))
        RefreshPage(page)
    end)
    page:SetScript("OnHide", function()
        FinishPageEdit(page)
        GameTooltip:Hide()
    end)
    page.OnCommit = FinishPageEdit
    page.OnRefresh = RefreshPage
    pages[#pages + 1] = page
    return page
end

local function LockInCombat(initializer)
    initializer:AddModifyPredicate(function()
        return not InCombatLockdown()
    end)
    initializer:AddEvaluateStateFrameEvent("PLAYER_REGEN_DISABLED")
    initializer:AddEvaluateStateFrameEvent("PLAYER_REGEN_ENABLED")
end

function addon.InitializeSettings()
    local category, layout = Settings.RegisterVerticalLayoutCategory(L.ADDON_NAME)
    addon.category = category
    layout:AddInitializer(Settings.CreateElementInitializer("CleanBindsDescriptionTemplate", {
        text = L.DESCRIPTION .. "\n" .. L.SESSION_NOTICE .. "\n" .. L.CLEAR_NOTICE,
    }))
    local setting = Settings.RegisterAddOnSetting(category, "CLEANBINDS_ENABLED", "enabled", addon.db,
        Settings.VarType.Boolean, L.ENABLE_LABELS, true)
    setting:SetValueChangedCallback(function()
        addon.RefreshActionLabels()
    end)
    LockInCombat(Settings.CreateCheckbox(category, setting, L.ENABLE_TOOLTIP))

    local reset = CreateSettingsButtonInitializer("", L.RESET_ALL, function()
        ConfirmReset()
    end, L.RESET_TOOLTIP, true)
    LockInCombat(reset)
    layout:AddInitializer(reset)

    for _, bar in ipairs(addon.Bars) do
        local page = CreatePage(bar)
        page.category = Settings.RegisterCanvasLayoutSubcategory(category, page, addon.GetBarName(bar))
    end
    Settings.RegisterAddOnCategory(category)

    StaticPopupDialogs.CLEANBINDS_CONFIRM_RESET = {
        text = "%s",
        button1 = YES,
        button2 = NO,
        OnAccept = function(_, data)
            ResetLabels(data.barID)
        end,
        timeout = 0,
        whileDead = true,
        hideOnEscape = true,
        preferredIndex = 3,
    }

    local events = CreateFrame("Frame")
    for _, event in ipairs({
        "UPDATE_BINDINGS", "GAME_PAD_ACTIVE_CHANGED", "PLAYER_REGEN_DISABLED",
        "PLAYER_REGEN_ENABLED", "UI_SCALE_CHANGED", "GLOBAL_MOUSE_DOWN",
        "ADDON_LOADED", "PLAYER_ENTERING_WORLD", "UPDATE_SHAPESHIFT_FORM", "PET_BAR_UPDATE",
    }) do
        events:RegisterEvent(event)
    end
    events:SetScript("OnEvent", function(_, event)
        for _, currentPage in ipairs(pages) do
            local row = currentPage.editingRow
            if event == "PLAYER_REGEN_DISABLED" then
                if row then
                    CancelEdit(row, L.COMBAT_CANCELED)
                else
                    SetNotice(currentPage, L.COMBAT_READ_ONLY)
                end
            elseif event == "PLAYER_REGEN_ENABLED" and currentPage.notice == L.COMBAT_READ_ONLY then
                SetNotice(currentPage, nil)
            elseif row and event == "GLOBAL_MOUSE_DOWN" and not MouseIsOver(row.Editor) then
                if not CommitEdit(row) then
                    CloseEditor(row)
                end
            end
        end
        if event ~= "GLOBAL_MOUSE_DOWN" then
            RefreshPages()
        end
    end)
end
