local _, addon = ...
local L = addon.L
local pages = {}
local descriptions = {}
local fontPreviews = {}
local enabledSetting
local hideMacroNamesSetting
local fontSizeSetting
local pendingReset
local rowHeight = 25
local previewSize = 56
local previewScale = previewSize / 45
-- SettingsList's -15 scroll offset plus 25 units of left padding.
local listLeftInset, listRightInset = 10, 20

CleanBindsDescriptionMixin = {}

function CleanBindsDescriptionMixin:Init(initializer)
    self.initializer = initializer
    self.Text:SetText(initializer.data.text())
    descriptions[self] = true
end

function CleanBindsDescriptionMixin:Release()
    descriptions[self] = nil
    self.initializer = nil
end

local function NormalizeFontSliderSize(size)
    local rounded = math.floor(size + 0.5)
    return ApproximatelyEqual(size, rounded) and rounded or size
end

CleanBindsFontSizeSliderMixin = {}

function CleanBindsFontSizeSliderMixin:Init(initializer)
    self.fontUnavailable = false
    self.synchronizing = true
    SettingsSliderControlMixin.Init(self, initializer)
    self.synchronizing = false
    self:SetValue()
end

function CleanBindsFontSizeSliderMixin:SetValue()
    -- Native sizing is a setting mode, not a numeric slider position.
    local size = self:GetSetting():GetValue()
    if size == 0 then
        local font, nativeSize = addon.GetPreviewKeybindFont(addon.GetBarButton(addon.Bars[1], 1), true)
        size = font and nativeSize or nil
    end
    self.fontUnavailable = size == nil
    local previous = self.synchronizing
    self.synchronizing = true
    if size then
        size = NormalizeFontSliderSize(size)
        SettingsSliderControlMixin.SetValue(self, size)
    end
    self.synchronizing = previous
    self.SliderWithSteppers:FormatValue(size)
    self:EvaluateState()
end

function CleanBindsFontSizeSliderMixin:OnSliderValueChanged(value)
    if not self.synchronizing then
        value = NormalizeFontSliderSize(value)
        local font, nativeSize = addon.GetPreviewKeybindFont(addon.GetBarButton(addon.Bars[1], 1), true)
        if font and ApproximatelyEqual(value, nativeSize) then
            value = 0
        end
        SettingsSliderControlMixin.OnSliderValueChanged(self, value)
    end
end

function CleanBindsFontSizeSliderMixin:EvaluateState()
    SettingsSliderControlMixin.EvaluateState(self)
    if self.fontUnavailable then
        self.SliderWithSteppers:SetEnabled(false)
        self:DisplayEnabled(false)
    end
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
    row.Override:SetEnabled(addon.CanEdit() and not row.unavailableReason)
end

local function CreatePreview(parent)
    local preview = CreateFrame("Frame", nil, parent)
    preview:SetSize(previewSize, previewSize)
    preview.Button = CreateFrame("Frame", nil, preview)
    preview.Button:SetPoint("CENTER")
    local background = preview.Button:CreateTexture(nil, "BACKGROUND")
    background:SetAllPoints()
    background:SetAtlas("UI-HUD-ActionBar-IconFrame-Background")
    preview.Border = preview.Button:CreateTexture(nil, "BORDER")
    preview.Border:SetPoint("TOPLEFT")
    preview.HotKey = preview.Button:CreateFontString(nil, "OVERLAY", "NumberFontNormalSmallGray")
    preview.HotKey:SetWordWrap(false)
    preview.HotKey:SetMaxLines(1)
    return preview
end

local function UpdatePreviewGeometry(preview, button)
    local hotkey = button and button.HotKey
    local sample = preview.Button
    local label = preview.HotKey
    local font, size, flags = addon.GetPreviewKeybindFont(button)
    if not font then
        return false, size
    end
    local width, height = 45, 45
    local labelWidth, labelHeight = 37, 10
    local accurate = hotkey ~= nil

    label:ClearAllPoints()
    if hotkey then
        width, height = button:GetSize()
        labelWidth, labelHeight = hotkey:GetSize()
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
    label:SetFont(font, size, flags)
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

CleanBindsFontPreviewMixin = {}

function CleanBindsFontPreviewMixin:OnLoad()
    self.Preview = CreatePreview(self)
    self.Preview:SetPoint("TOPLEFT", 8, -8)
    self.Title = AddText(self, "GameFontNormal", L.PREVIEW)
    self.Title:SetPoint("TOPLEFT", self.Preview, "TOPRIGHT", 14, -3)
    self.Status = AddText(self, "GameFontHighlightSmall", "")
    self.Status:SetPoint("TOPLEFT", self.Title, "BOTTOMLEFT", 0, -8)
    self.Status:SetPoint("BOTTOMRIGHT", self, "BOTTOMRIGHT", -130, 8)
    self.Status:SetJustifyV("TOP")
    self.Reset = CreateFrame("Button", nil, self, "UIPanelButtonTemplate")
    self.Reset:SetSize(110, 22)
    self.Reset:SetPoint("TOPRIGHT", -16, -8)
    self.Reset:SetText(L.DEFAULT_LABEL)
    self.Reset:SetScript("OnClick", function()
        local success, reason = addon.SetKeybindFontSize(nil, self.scopeToken)
        if not success then
            addon.Print(reason)
        end
    end)
end

function CleanBindsFontPreviewMixin:Init()
    fontPreviews[self] = true
    self:Refresh()
end

function CleanBindsFontPreviewMixin:Release()
    fontPreviews[self] = nil
end

function CleanBindsFontPreviewMixin:Refresh()
    self.scopeToken = addon.GetScopeToken()
    local accurate, reason = UpdatePreviewGeometry(self.Preview, addon.GetBarButton(addon.Bars[1], 1))
    self.Preview:SetShown(reason == nil)
    self.Preview.HotKey:SetText(L.FONT_SIZE_SAMPLE)
    self.Status:SetText(reason or (self.Preview.HotKey:IsTruncated() and L.LABEL_TOO_WIDE
        or (not accurate and L.PREVIEW_APPROXIMATE or "")))
    self.Reset:SetEnabled(addon.CanEdit() and addon.GetKeybindFontSize() ~= nil)
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
    local accurate, previewError = UpdatePreviewGeometry(page.Preview, button)
    if previewError then
        page.Preview:Hide()
        page.Status:SetText(previewError)
        return
    end
    local label = row.editing and row.Editor:GetText() or addon.GetLabel(page.bar, row.index)
    local customLabel, validationError = addon.NormalizeLabel(label or "")
    page.Preview.HotKey:SetText(customLabel and customLabel ~= "" and addon.LiteralLabel(customLabel) or row.defaultLabel)
    page.PreviewTitle:SetText(row.name)
    page.PreviewDefault:SetText(L.PREVIEW_DEFAULT:format(row.defaultLabel ~= "" and row.defaultLabel or L.NOT_BOUND))
    local editable, editReason = addon.CanEdit()

    if page.notice then
        page.Status:SetText(page.notice)
    elseif not editable then
        page.Status:SetText(editReason)
    elseif validationError then
        page.Status:SetText(validationError)
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
    row.scopeToken = nil
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

    local success, reason = addon.SetLabel(row.page.bar, row.index, row.Editor:GetText(), row.scopeToken)
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
    local allowed, reason = addon.CanEdit()
    if not allowed then
        SetNotice(row.page, reason)
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
    row.scopeToken = addon.GetScopeToken()
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
    if editable and not row.unavailableReason then
        GameTooltip:AddLine(L.CLEAR_NOTICE, 0.8, 0.8, 0.8, true)
    end
    GameTooltip:Show()
end

local function RefreshPage(page)
    page.Description:SetText(addon.GetScopeNotice())
    for _, row in ipairs(page.rows) do
        RefreshBinding(row)
        if row.editing and row.unavailableReason then
            CancelEdit(row, row.unavailableReason)
        end
        RefreshCell(row)
    end
    local editable = addon.CanEdit()
    page.Reset:SetEnabled(editable)
    UpdatePreview(page)
end

local function RefreshPages()
    if enabledSetting then
        enabledSetting:NotifyUpdate()
    end
    if hideMacroNamesSetting then
        hideMacroNamesSetting:NotifyUpdate()
    end
    if fontSizeSetting then
        fontSizeSetting:NotifyUpdate()
    end
    for preview in pairs(fontPreviews) do
        preview:Refresh()
    end
    for frame in pairs(descriptions) do
        frame.Text:SetText(frame.initializer.data.text())
    end
    for _, page in ipairs(pages) do
        if page:IsShown() then
            RefreshPage(page)
        end
    end
end
addon.RefreshSettings = RefreshPages

local function ResetLabels(barID, token)
    local success, reason = addon.ResetLabels(barID, token)
    if not success then
        addon.Print(reason)
    end
end

local function ConfirmReset(bar)
    local allowed, reason = addon.CanEdit()
    if not allowed then
        addon.Print(reason)
        return
    end
    local scope = addon.GetScopeName()
    local message = bar and L.RESET_BAR_CONFIRM:format(addon.GetBarName(bar), scope) or L.RESET_ALL_CONFIRM:format(scope)
    pendingReset = { barID = bar and bar.id, scopeToken = addon.GetScopeToken() }
    StaticPopup_Show("CLEANBINDS_CONFIRM_RESET", message, nil, pendingReset)
end

function addon.CancelScopeInteractions()
    local canceled = false
    for _, page in ipairs(pages) do
        if page.editingRow then
            CancelEdit(page.editingRow, L.SCOPE_CHANGED)
            canceled = true
        end
    end
    if pendingReset then
        pendingReset = nil
        StaticPopup_Hide("CLEANBINDS_CONFIRM_RESET")
        canceled = true
    end
    if canceled then
        addon.Print(L.SCOPE_CHANGED)
    end
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
    page.Description = AddText(page, "GameFontHighlightSmall", addon.GetScopeNotice())
    page.Description:SetPoint("TOPLEFT", 16, -46)
    page.Description:SetPoint("TOPRIGHT", -16, -46)

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

    page.Preview = CreatePreview(page)
    page.Preview:SetPoint("BOTTOMLEFT", 16, 60)
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

local function LockWhenUnavailable(initializer)
    initializer:AddModifyPredicate(function()
        return addon.CanEdit()
    end)
    initializer:AddEvaluateStateFrameEvent("PLAYER_REGEN_DISABLED")
    initializer:AddEvaluateStateFrameEvent("PLAYER_REGEN_ENABLED")
    -- Proxy notifications refresh availability without writing either profile.
    initializer:AddEvaluateStateCVar("CLEANBINDS_ENABLED")
end

function addon.InitializeSettings()
    local category, layout = Settings.RegisterVerticalLayoutCategory(L.ADDON_NAME)
    addon.category = category
    layout:AddInitializer(Settings.CreateElementInitializer("CleanBindsDescriptionTemplate", {
        text = function()
            return L.DESCRIPTION .. "\n" .. addon.GetScopeNotice() .. "\n" .. L.SCOPE_HELP
        end,
    }))
    enabledSetting = Settings.RegisterProxySetting(category, "CLEANBINDS_ENABLED",
        Settings.VarType.Boolean, L.ENABLE_LABELS, true, addon.IsEnabled, function(value)
            local success, reason = addon.SetEnabled(value)
            if not success then
                addon.Print(reason)
            end
        end)
    LockWhenUnavailable(Settings.CreateCheckbox(category, enabledSetting, L.ENABLE_TOOLTIP))

    hideMacroNamesSetting = Settings.RegisterProxySetting(category, "CLEANBINDS_HIDE_MACRO_NAMES",
        Settings.VarType.Boolean, L.HIDE_MACRO_NAMES, false, addon.ShouldHideMacroNames, function(value)
            local success, reason = addon.SetHideMacroNames(value)
            if not success then
                addon.Print(reason)
            end
        end)
    LockWhenUnavailable(Settings.CreateCheckbox(category, hideMacroNamesSetting, L.HIDE_MACRO_NAMES_TOOLTIP))

    local function GetFontSize()
        return addon.GetKeybindFontSize() or 0
    end
    fontSizeSetting = Settings.RegisterProxySetting(category, "CLEANBINDS_KEYBIND_FONT_SIZE",
        Settings.VarType.Number, L.KEYBIND_FONT_SIZE, 0, GetFontSize, function(value)
            local size = value
            if value == 0 then
                size = nil
            end
            local success, reason = addon.SetKeybindFontSize(size)
            if not success then
                addon.Print(reason)
            end
        end)
    local fontOptions = Settings.CreateSliderOptions(addon.MIN_KEYBIND_FONT_SIZE, addon.MAX_KEYBIND_FONT_SIZE, 1)
    fontOptions:SetLabelFormatter(MinimalSliderWithSteppersMixin.Label.Right, function(value)
        if not value then
            return L.UNAVAILABLE
        end
        return addon.GetKeybindFontSize() and tostring(value) or L.DEFAULT_FONT_SIZE:format(value)
    end)
    local fontSlider = Settings.CreateControlInitializer("CleanBindsFontSizeSliderTemplate",
        fontSizeSetting, fontOptions, L.KEYBIND_FONT_SIZE_TOOLTIP)
    LockWhenUnavailable(fontSlider)
    layout:AddInitializer(fontSlider)
    layout:AddInitializer(Settings.CreateElementInitializer("CleanBindsFontPreviewTemplate", {}))

    local reset = CreateSettingsButtonInitializer("", L.RESET_ALL, function()
        ConfirmReset()
    end, L.RESET_TOOLTIP, true)
    LockWhenUnavailable(reset)
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
            pendingReset = nil
            ResetLabels(data.barID, data.scopeToken)
        end,
        OnCancel = function()
            pendingReset = nil
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
            elseif row and event == "GLOBAL_MOUSE_DOWN" and not row.Editor:IsMouseOver() then
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
