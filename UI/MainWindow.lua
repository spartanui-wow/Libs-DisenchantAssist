---@class LibsDisenchantAssist
local LibsDisenchantAssist = LibStub('AceAddon-3.0'):GetAddon('LibsDisenchantAssist')

---@class LibsDisenchantAssist.MainWindow : AceModule, AceEvent-3.0, AceTimer-3.0
local MainWindow = LibsDisenchantAssist:NewModule('MainWindow')
LibsDisenchantAssist.MainWindow = MainWindow

local MAX_VISIBLE_ITEMS = 50
local ITEM_ROW_HEIGHT = 24
local WINDOW_WIDTH = 460
local WINDOW_HEIGHT = 550

local DE_COLOR = { r = 0.6, g = 0.4, b = 1.0 }

function MainWindow:OnInitialize()
	self.window = nil
	self.itemRows = {}
	self.isSettingsVisible = false
	self.refreshPending = false
end

function MainWindow:OnEnable()
	self:RegisterMessage('DISENCHANT_ASSIST_ITEMS_UPDATED', 'ScheduleRefresh')
	self:RegisterMessage('DISENCHANT_ASSIST_READY', 'OnEngineReady')
	self:RegisterMessage('DISENCHANT_ASSIST_CASTING', 'OnEngineCasting')
	self:RegisterMessage('DISENCHANT_ASSIST_ITEM_DESTROYED', 'OnItemDestroyed')
	self:RegisterMessage('DISENCHANT_ASSIST_QUEUE_COMPLETE', 'OnQueueComplete')
	self:RegisterMessage('DISENCHANT_ASSIST_STOPPED', 'OnQueueStopped')
	self:RegisterMessage('DISENCHANT_ASSIST_PAUSED', 'OnQueuePaused')
	self:RegisterMessage('DISENCHANT_ASSIST_PROFILE_CHANGED', 'ScheduleRefresh')
	self:RegisterEvent('PLAYER_REGEN_ENABLED', 'ScheduleRefresh')
end

function MainWindow:Show()
	if not self.window then
		self:CreateWindow()
	end
	self.window:Show()
	self:RefreshItemList()
	self:UpdateDisenchantButton()
end

function MainWindow:Hide()
	if self.window then
		self.window:Hide()
	end
end

function MainWindow:Toggle()
	if self.window and self.window:IsVisible() then
		self:Hide()
	else
		self:Show()
	end
end

function MainWindow:ShowSettings()
	if not self.window then
		self:CreateWindow()
		self.window:Show()
	end
	if not self.isSettingsVisible then
		self:ToggleSettings()
	end
end

function MainWindow:CreateWindow()
	if LibAT and LibAT.UI and LibAT.UI.CreateWindow then
		self.window = LibAT.UI.CreateWindow({
			name = 'LibsDisenchantAssistMainFrame',
			title = "Lib's - Disenchant Assist",
			width = WINDOW_WIDTH,
			height = WINDOW_HEIGHT,
			hidePortrait = true,
		})
	else
		self.window = self:CreateFallbackWindow()
	end

	self:CreateControlBar()
	self:CreateItemListFrame()
	self:CreateStatusBar()
	self:CreateDisenchantButton()
	self:CreateSettingsPanel()

	self.window:SetScript('OnShow', function()
		self:RefreshItemList()
		self:UpdateDisenchantButton()
	end)
end

function MainWindow:CreateFallbackWindow()
	local frame = CreateFrame('Frame', 'LibsDisenchantAssistMainFrame', UIParent, 'ButtonFrameTemplate')
	frame:SetSize(WINDOW_WIDTH, WINDOW_HEIGHT)
	frame:SetPoint('CENTER')
	frame:SetMovable(true)
	frame:SetClampedToScreen(true)
	frame:SetFrameStrata('HIGH')
	frame:EnableMouse(true)
	frame:Hide()

	frame:SetScript('OnMouseDown', function(self, button)
		if button == 'LeftButton' then
			self:StartMoving()
		end
	end)
	frame:SetScript('OnMouseUp', function(self)
		self:StopMovingOrSizing()
	end)

	frame.TitleText = frame:CreateFontString(nil, 'ARTWORK', 'GameFontNormal')
	frame.TitleText:SetPoint('TOP', 0, -5)
	frame.TitleText:SetText("Lib's - Disenchant Assist")

	ButtonFrameTemplate_HidePortrait(frame)

	tinsert(UISpecialFrames, 'LibsDisenchantAssistMainFrame')

	return frame
end

function MainWindow:CreateControlBar()
	local controlBar = CreateFrame('Frame', nil, self.window)
	controlBar:SetSize(WINDOW_WIDTH - 20, 30)
	controlBar:SetPoint('TOPLEFT', 10, -30)
	self.controlBar = controlBar

	self.itemCountText = controlBar:CreateFontString(nil, 'ARTWORK', 'GameFontHighlight')
	self.itemCountText:SetPoint('LEFT', 0, 0)
	self.itemCountText:SetText('Items: 0')

	if LibAT and LibAT.UI and LibAT.UI.CreateIconButton then
		local gearBtn = LibAT.UI.CreateIconButton(controlBar, 'Warfronts-BaseMapIcons-Empty-Workshop', 'Warfronts-BaseMapIcons-Alliance-Workshop', 'Warfronts-BaseMapIcons-Horde-Workshop', 24)
		gearBtn:SetPoint('RIGHT', 0, 0)
		gearBtn:SetScript('OnClick', function()
			self:ToggleSettings()
		end)
		gearBtn:SetScript('OnEnter', function(btn)
			GameTooltip:SetOwner(btn, 'ANCHOR_TOP')
			GameTooltip:SetText('Settings', 1, 1, 1)
			GameTooltip:Show()
		end)
		gearBtn:SetScript('OnLeave', function()
			GameTooltip:Hide()
		end)
		self.settingsGearButton = gearBtn
	end
end

function MainWindow:CreateItemListFrame()
	local scrollFrame
	if LibAT and LibAT.UI and LibAT.UI.CreateScrollFrame then
		scrollFrame = LibAT.UI.CreateScrollFrame(self.window)
	else
		scrollFrame = CreateFrame('ScrollFrame', 'LibsDAItemScrollFrame', self.window, 'UIPanelScrollFrameTemplate')
	end
	scrollFrame:SetPoint('TOPLEFT', self.controlBar, 'BOTTOMLEFT', 0, -4)
	scrollFrame:SetPoint('BOTTOMRIGHT', self.window, 'BOTTOMRIGHT', -30, 100)
	self.scrollFrame = scrollFrame

	local itemList = CreateFrame('Frame', 'LibsDAItemList', scrollFrame)
	itemList:SetSize(WINDOW_WIDTH - 50, 1)
	scrollFrame:SetScrollChild(itemList)
	self.itemList = itemList

	for i = 1, MAX_VISIBLE_ITEMS do
		local row = self:CreateItemRow(itemList, i)
		if i == 1 then
			row:SetPoint('TOPLEFT', 0, 0)
		else
			row:SetPoint('TOPLEFT', self.itemRows[i - 1], 'BOTTOMLEFT', 0, -1)
		end
		row:Hide()
		self.itemRows[i] = row
	end
end

---@param parent Frame
---@param index number
---@return Frame
function MainWindow:CreateItemRow(parent, index)
	local row = CreateFrame('Button', 'LibsDAItemRow' .. index, parent)
	local rowWidth = WINDOW_WIDTH - 55
	row:SetSize(rowWidth, ITEM_ROW_HEIGHT)
	row:EnableMouse(true)

	local bg = row:CreateTexture(nil, 'BACKGROUND')
	bg:SetAllPoints()
	if index % 2 == 0 then
		bg:SetColorTexture(0.15, 0.15, 0.15, 0.6)
	else
		bg:SetColorTexture(0.1, 0.1, 0.1, 0.4)
	end
	row.Background = bg

	local highlight = row:CreateTexture(nil, 'HIGHLIGHT')
	highlight:SetAllPoints()
	highlight:SetColorTexture(0.3, 0.3, 0.3, 0.4)
	row:SetHighlightTexture(highlight)

	local icon = row:CreateTexture(nil, 'ARTWORK')
	icon:SetSize(20, 20)
	icon:SetPoint('LEFT', 4, 0)
	row.Icon = icon

	local name = row:CreateFontString(nil, 'ARTWORK', 'GameFontNormalSmall')
	name:SetPoint('LEFT', icon, 'RIGHT', 4, 0)
	name:SetPoint('RIGHT', -120, 0)
	name:SetJustifyH('LEFT')
	name:SetWordWrap(false)
	row.Name = name

	local ilvl = row:CreateFontString(nil, 'ARTWORK', 'GameFontNormalSmall')
	ilvl:SetPoint('RIGHT', -70, 0)
	ilvl:SetJustifyH('RIGHT')
	ilvl:SetTextColor(0.8, 0.8, 1, 1)
	row.Ilvl = ilvl

	-- Per-row secure disenchant button (1-click disenchant)
	local deBtn = CreateFrame('Button', 'LibsDADeBtn' .. index, row, 'SecureActionButtonTemplate')
	deBtn:SetSize(40, 18)
	deBtn:SetPoint('RIGHT', -40, 0)
	deBtn:RegisterForClicks('AnyUp', 'AnyDown')

	local deBtnBg = deBtn:CreateTexture(nil, 'BACKGROUND')
	deBtnBg:SetAllPoints()
	deBtnBg:SetColorTexture(0.2, 0.2, 0.2, 0.6)
	deBtn.Bg = deBtnBg

	local deBtnHighlight = deBtn:CreateTexture(nil, 'HIGHLIGHT')
	deBtnHighlight:SetAllPoints()
	deBtnHighlight:SetColorTexture(0.4, 0.4, 0.4, 0.4)
	deBtn:SetHighlightTexture(deBtnHighlight)

	deBtn.Text = deBtn:CreateFontString(nil, 'OVERLAY', 'GameFontNormalSmall')
	deBtn.Text:SetPoint('CENTER')
	deBtn.Text:SetText('DE')
	deBtn.Text:SetTextColor(DE_COLOR.r, DE_COLOR.g, DE_COLOR.b)
	row.TypeButton = deBtn

	deBtn:SetScript('PreClick', function()
		if not row.item then
			deBtn:SetAttribute('type', 'macro')
			deBtn:SetAttribute('macrotext', '')
			return
		end
		local item = row.item
		local containerInfo = C_Container.GetContainerItemInfo(item.bag, item.slot)
		if not containerInfo or containerInfo.itemID ~= item.itemID then
			deBtn:SetAttribute('type', 'macro')
			deBtn:SetAttribute('macrotext', '')
			return
		end
	end)

	deBtn:SetScript('OnEnter', function(btn)
		GameTooltip:SetOwner(btn, 'ANCHOR_TOP')
		GameTooltip:SetText('Click to disenchant this item', 1, 1, 1)
		GameTooltip:Show()
	end)
	deBtn:SetScript('OnLeave', function()
		GameTooltip:Hide()
	end)

	local ignoreBtn = CreateFrame('Button', nil, row)
	ignoreBtn:SetSize(20, 20)
	ignoreBtn:SetPoint('RIGHT', -4, 0)
	ignoreBtn:SetNormalAtlas('common-icon-redx')
	ignoreBtn:SetHighlightAtlas('common-icon-redx')
	ignoreBtn:GetHighlightTexture():SetAlpha(0.5)

	ignoreBtn:SetScript('OnClick', function(_, button)
		if not row.item then
			return
		end
		if button == 'RightButton' then
			LibsDisenchantAssist:PermanentIgnoreItem(row.item.itemID)
			if LibsDisenchantAssist.logger then
				LibsDisenchantAssist.logger.info('Permanently ignored: ' .. (row.item.itemLink or row.item.itemName))
			end
		else
			LibsDisenchantAssist:SessionIgnoreItem(row.item.itemID)
			if LibsDisenchantAssist.logger then
				LibsDisenchantAssist.logger.info('Session ignored: ' .. (row.item.itemLink or row.item.itemName))
			end
		end
	end)

	ignoreBtn:RegisterForClicks('LeftButtonUp', 'RightButtonUp')

	ignoreBtn:SetScript('OnEnter', function(self)
		GameTooltip:SetOwner(self, 'ANCHOR_TOP')
		GameTooltip:SetText('Ignore this item', 1, 1, 1)
		GameTooltip:AddLine('Left-click: Ignore until /rl', 0.8, 0.8, 0.8)
		GameTooltip:AddLine('Right-click: Ignore permanently', 0.8, 0.8, 0.8)
		GameTooltip:Show()
	end)
	ignoreBtn:SetScript('OnLeave', function()
		GameTooltip:Hide()
	end)
	row.IgnoreButton = ignoreBtn

	row:SetScript('OnEnter', function(self)
		if self.item then
			GameTooltip:SetOwner(self, 'ANCHOR_RIGHT')
			GameTooltip:SetBagItem(self.item.bag, self.item.slot)
			GameTooltip:Show()
		end
	end)
	row:SetScript('OnLeave', function()
		GameTooltip:Hide()
	end)

	return row
end

function MainWindow:CreateStatusBar()
	self.statusText = self.window:CreateFontString(nil, 'ARTWORK', 'GameFontNormalSmall')
	self.statusText:SetPoint('BOTTOMLEFT', 15, 75)
	self.statusText:SetTextColor(0.8, 0.8, 0.8, 1)
	self.statusText:SetText('Ready')
end

function MainWindow:CreateDisenchantButton()
	local engine = LibsDisenchantAssist.DisenchantEngine
	local secureBtn = engine:GetSecureButton()

	secureBtn:SetParent(self.window)
	secureBtn:ClearAllPoints()
	secureBtn:SetPoint('BOTTOMLEFT', self.window, 'BOTTOMLEFT', 15, 25)
	secureBtn:SetPoint('BOTTOMRIGHT', self.window, 'BOTTOMRIGHT', -15, 25)
	secureBtn:SetHeight(36)
	secureBtn:Show()

	local normalTex = secureBtn:CreateTexture(nil, 'BACKGROUND')
	normalTex:SetAllPoints()
	normalTex:SetColorTexture(0.15, 0.45, 0.15, 0.9)
	secureBtn:SetNormalTexture(normalTex)

	local highlightTex = secureBtn:CreateTexture(nil, 'HIGHLIGHT')
	highlightTex:SetAllPoints()
	highlightTex:SetColorTexture(0.2, 0.6, 0.2, 0.5)
	secureBtn:SetHighlightTexture(highlightTex)

	local pushedTex = secureBtn:CreateTexture(nil, 'BACKGROUND')
	pushedTex:SetAllPoints()
	pushedTex:SetColorTexture(0.1, 0.3, 0.1, 0.9)
	secureBtn:SetPushedTexture(pushedTex)

	secureBtn.Text = secureBtn:CreateFontString(nil, 'OVERLAY', 'GameFontNormalLarge')
	secureBtn.Text:SetPoint('CENTER')
	secureBtn.Text:SetText('Click to Disenchant')
	secureBtn.Text:SetTextColor(1, 1, 1, 1)

	self.disenchantButton = secureBtn
end

function MainWindow:CreateSettingsPanel()
	local panel = CreateFrame('Frame', nil, self.window)
	panel:SetSize(WINDOW_WIDTH - 20, 200)
	panel:SetPoint('TOPLEFT', self.controlBar, 'BOTTOMLEFT', 0, -4)
	panel:Hide()

	if BackdropTemplateMixin then
		Mixin(panel, BackdropTemplateMixin)
		panel:SetBackdrop({
			bgFile = 'Interface\\ChatFrame\\ChatFrameBackground',
			edgeFile = 'Interface\\Tooltips\\UI-Tooltip-Border',
			tile = true,
			tileSize = 16,
			edgeSize = 8,
			insets = { left = 2, right = 2, top = 2, bottom = 2 },
		})
		panel:SetBackdropColor(0.08, 0.08, 0.08, 0.95)
		panel:SetBackdropBorderColor(0.3, 0.3, 0.3, 1)
	end

	self:PopulateSettingsPanel(panel)
	self.settingsPanel = panel
end

function MainWindow:PopulateSettingsPanel(panel)
	local yPos = -10

	local function AddCheckbox(label, optionKey, x, y)
		local cb = CreateFrame('CheckButton', nil, panel, 'UICheckButtonTemplate')
		cb:SetPoint('TOPLEFT', x, y)
		cb.text = cb:CreateFontString(nil, 'ARTWORK', 'GameFontNormalSmall')
		cb.text:SetPoint('LEFT', cb, 'RIGHT', 2, 0)
		cb.text:SetText(label)
		cb:SetChecked(LibsDisenchantAssist.DB[optionKey])
		cb:SetScript('OnClick', function()
			LibsDisenchantAssist.DB[optionKey] = cb:GetChecked()
			self:RefreshItemList()
		end)
		return cb
	end

	local headerDE = panel:CreateFontString(nil, 'ARTWORK', 'GameFontNormal')
	headerDE:SetPoint('TOPLEFT', 10, yPos)
	headerDE:SetText('Disenchant Filters')
	headerDE:SetTextColor(1, 0.82, 0)
	yPos = yPos - 22

	AddCheckbox("Exclude today's items", 'excludeToday', 10, yPos)
	AddCheckbox('Exclude higher ilvl', 'excludeHigherIlvl', 210, yPos)
	yPos = yPos - 22

	AddCheckbox('Exclude gear sets', 'excludeGearSets', 10, yPos)
	AddCheckbox('Exclude warbound', 'excludeWarbound', 210, yPos)
	yPos = yPos - 22

	AddCheckbox('Exclude BOE', 'excludeBOE', 10, yPos)
	AddCheckbox('Exclude Pawn upgrades', 'excludePawnUpgrades', 210, yPos)
	yPos = yPos - 30

	local minLabel = panel:CreateFontString(nil, 'ARTWORK', 'GameFontNormalSmall')
	minLabel:SetPoint('TOPLEFT', 10, yPos)
	minLabel:SetText('Min iLvl:')

	local minInput = CreateFrame('EditBox', 'LibsDASettingsMinIlvl', panel, 'InputBoxTemplate')
	minInput:SetPoint('TOPLEFT', 70, yPos + 2)
	minInput:SetSize(50, 20)
	minInput:SetAutoFocus(false)
	minInput:SetNumeric(true)
	minInput:SetMaxLetters(4)
	minInput:SetText(tostring(LibsDisenchantAssist.DB.minIlvl))
	minInput:SetScript('OnEnterPressed', function(editBox)
		local value = tonumber(editBox:GetText())
		if value and value >= 1 then
			LibsDisenchantAssist.DB.minIlvl = value
		else
			editBox:SetText(tostring(LibsDisenchantAssist.DB.minIlvl))
		end
		editBox:ClearFocus()
		self:RefreshItemList()
	end)
	minInput:SetScript('OnEscapePressed', function(editBox)
		editBox:SetText(tostring(LibsDisenchantAssist.DB.minIlvl))
		editBox:ClearFocus()
	end)

	local maxLabel = panel:CreateFontString(nil, 'ARTWORK', 'GameFontNormalSmall')
	maxLabel:SetPoint('TOPLEFT', 150, yPos)
	maxLabel:SetText('Max iLvl:')

	local maxInput = CreateFrame('EditBox', 'LibsDASettingsMaxIlvl', panel, 'InputBoxTemplate')
	maxInput:SetPoint('TOPLEFT', 210, yPos + 2)
	maxInput:SetSize(50, 20)
	maxInput:SetAutoFocus(false)
	maxInput:SetMaxLetters(4)
	local maxIlvlText = LibsDisenchantAssist.DB.maxIlvl == 999 and '' or tostring(LibsDisenchantAssist.DB.maxIlvl)
	maxInput:SetText(maxIlvlText)
	maxInput:SetScript('OnEnterPressed', function(editBox)
		local text = strtrim(editBox:GetText())
		if text == '' then
			LibsDisenchantAssist.DB.maxIlvl = 999
		else
			local value = tonumber(text)
			if value and value >= 1 then
				LibsDisenchantAssist.DB.maxIlvl = value
			else
				local displayText = LibsDisenchantAssist.DB.maxIlvl == 999 and '' or tostring(LibsDisenchantAssist.DB.maxIlvl)
				editBox:SetText(displayText)
			end
		end
		editBox:ClearFocus()
		self:RefreshItemList()
	end)
	maxInput:SetScript('OnEscapePressed', function(editBox)
		local displayText = LibsDisenchantAssist.DB.maxIlvl == 999 and '' or tostring(LibsDisenchantAssist.DB.maxIlvl)
		editBox:SetText(displayText)
		editBox:ClearFocus()
	end)

	local maxHint = panel:CreateFontString(nil, 'ARTWORK', 'GameFontDisableSmall')
	maxHint:SetPoint('LEFT', maxInput, 'RIGHT', 4, 0)
	maxHint:SetText('(blank = no limit)')

	yPos = yPos - 30

	local qualityLabel = panel:CreateFontString(nil, 'ARTWORK', 'GameFontNormalSmall')
	qualityLabel:SetPoint('TOPLEFT', 10, yPos)
	qualityLabel:SetText('Max DE quality:')

	local qualityNames = { [2] = 'Uncommon', [3] = 'Rare', [4] = 'Epic' }

	if LibAT and LibAT.UI and LibAT.UI.CreateDropdown then
		local qualityDropdown = LibAT.UI.CreateDropdown(panel, qualityNames[LibsDisenchantAssist.DB.deMaxQuality] or 'Epic', 120, 22)
		qualityDropdown:SetPoint('TOPLEFT', 110, yPos + 2)

		if qualityDropdown.SetupMenu then
			qualityDropdown:SetupMenu(function(_, rootDescription)
				for _, quality in ipairs({ 2, 3, 4 }) do
					local r, g, b = C_Item.GetItemQualityColor(quality)
					local coloredText = string.format('|cff%02x%02x%02x%s|r', r * 255, g * 255, b * 255, qualityNames[quality])
					rootDescription:CreateRadio(coloredText, function()
						return LibsDisenchantAssist.DB.deMaxQuality == quality
					end, function()
						LibsDisenchantAssist.DB.deMaxQuality = quality
						qualityDropdown:SetText(qualityNames[quality])
						self:RefreshItemList()
					end)
				end
			end)
		end
	else
		local qualitySlider = CreateFrame('Slider', 'LibsDASettingsMaxQuality', panel, 'OptionsSliderTemplate')
		qualitySlider:SetPoint('TOPLEFT', 110, yPos - 2)
		qualitySlider:SetSize(80, 17)
		qualitySlider:SetMinMaxValues(2, 4)
		qualitySlider:SetValueStep(1)
		qualitySlider:SetValue(LibsDisenchantAssist.DB.deMaxQuality)
		_G[qualitySlider:GetName() .. 'Low']:SetText('')
		_G[qualitySlider:GetName() .. 'High']:SetText('')
		_G[qualitySlider:GetName() .. 'Text']:SetText(qualityNames[LibsDisenchantAssist.DB.deMaxQuality] or 'Epic')
		qualitySlider:SetScript('OnValueChanged', function(_, value)
			value = math.floor(value + 0.5)
			LibsDisenchantAssist.DB.deMaxQuality = value
			_G[qualitySlider:GetName() .. 'Text']:SetText(qualityNames[value] or 'Epic')
			self:RefreshItemList()
		end)
	end

	panel:SetHeight(math.abs(yPos) + 30)
end

function MainWindow:ToggleSettings()
	self.isSettingsVisible = not self.isSettingsVisible

	if self.isSettingsVisible then
		self.settingsPanel:Show()
		self.scrollFrame:SetPoint('TOPLEFT', self.settingsPanel, 'BOTTOMLEFT', 0, -4)
	else
		self.settingsPanel:Hide()
		self.scrollFrame:SetPoint('TOPLEFT', self.controlBar, 'BOTTOMLEFT', 0, -4)
	end
end

function MainWindow:ScheduleRefresh()
	if not self.window or not self.window:IsVisible() then
		return
	end
	if not self.refreshPending then
		self.refreshPending = true
		C_Timer.After(0.1, function()
			self.refreshPending = false
			self:RefreshItemList()
		end)
	end
end

function MainWindow:RefreshItemList()
	if not self.window or not self.window:IsVisible() then
		return
	end

	local items = LibsDisenchantAssist.FilterSystem:GetFilteredItems()

	for i = 1, MAX_VISIBLE_ITEMS do
		local row = self.itemRows[i]
		if items[i] then
			local item = items[i]
			row.item = item

			local itemIcon = C_Item.GetItemIconByID(item.itemID)
			row.Icon:SetTexture(itemIcon)

			local r, g, b = C_Item.GetItemQualityColor(item.quality)
			row.Name:SetText(item.itemName)
			row.Name:SetTextColor(r, g, b)

			row.Ilvl:SetText('iLvl ' .. item.itemLevel)
			row.Ilvl:Show()

			if not InCombatLockdown() then
				self:SetRowButtonAttributes(row.TypeButton, item)
			end

			row:Show()
		else
			row:Hide()
			row.item = nil
			if not InCombatLockdown() then
				self:ClearRowButtonAttributes(row.TypeButton)
			end
		end
	end

	local totalHeight = math.max(#items * (ITEM_ROW_HEIGHT + 1), 1)
	self.itemList:SetHeight(totalHeight)

	self.itemCountText:SetText('Items: ' .. #items)

	self:UpdateDisenchantButton()

	if LibsDisenchantAssist.DataBroker then
		LibsDisenchantAssist.DataBroker:UpdateText()
	end
end

---@param btn Button SecureActionButton on the row
---@param item table Item data with bag, slot
function MainWindow:SetRowButtonAttributes(btn, item)
	local spellID = LibsDisenchantAssist.DISENCHANT_SPELL_ID

	if FindSpellBookSlotBySpellID and FindSpellBookSlotBySpellID(spellID) then
		btn:SetAttribute('type', 'spell')
		btn:SetAttribute('spell', spellID)
		btn:SetAttribute('target-bag', item.bag)
		btn:SetAttribute('target-slot', item.slot)
	else
		local macroText = string.format('/run C_TradeSkillUI.CraftSalvage(%d, 1, ItemLocation:CreateFromBagAndSlot(%d, %d))', spellID, item.bag, item.slot)
		btn:SetAttribute('type', 'macro')
		btn:SetAttribute('macrotext', macroText)
	end
end

---@param btn Button SecureActionButton on the row
function MainWindow:ClearRowButtonAttributes(btn)
	btn:SetAttribute('type', 'macro')
	btn:SetAttribute('macrotext', '')
	btn:SetAttribute('spell', nil)
	btn:SetAttribute('target-bag', nil)
	btn:SetAttribute('target-slot', nil)
end

function MainWindow:UpdateDisenchantButton()
	if not self.disenchantButton then
		return
	end

	local engine = LibsDisenchantAssist.DisenchantEngine
	local currentItem = engine:GetCurrentItem()

	if currentItem then
		self.disenchantButton.Text:SetText('>>> DE: ' .. currentItem.itemName .. ' <<<')
		self.disenchantButton.Text:SetTextColor(1, 1, 0.5, 1)
	else
		local items = LibsDisenchantAssist.FilterSystem:GetFilteredItems()
		if #items > 0 then
			self.disenchantButton.Text:SetText('Disenchant All (' .. #items .. ' items)')
			self.disenchantButton.Text:SetTextColor(1, 1, 1, 1)
		else
			self.disenchantButton.Text:SetText('No items to disenchant')
			self.disenchantButton.Text:SetTextColor(0.5, 0.5, 0.5, 1)
		end
	end
end

function MainWindow:UpdateStatus(text)
	if self.statusText then
		self.statusText:SetText(text)
	end
end

function MainWindow:OnEngineReady(_, item)
	if not item then
		return
	end
	self:UpdateStatus('Ready - Click to disenchant: ' .. item.itemName)
	self:UpdateDisenchantButton()
end

function MainWindow:OnEngineCasting(_, item)
	if not item then
		return
	end
	self:UpdateStatus('Disenchanting ' .. item.itemName .. '...')
end

function MainWindow:OnItemDestroyed(_, item, destroyed, total)
	if not item then
		return
	end
	self:UpdateStatus('Disenchanted ' .. destroyed .. ' of ' .. total)
	self:RefreshItemList()
end

function MainWindow:OnQueueComplete(_, destroyed, total)
	self:UpdateStatus('Done! Disenchanted ' .. (destroyed or 0) .. ' of ' .. (total or 0) .. ' items')
	self:RefreshItemList()
	self:UpdateDisenchantButton()
end

function MainWindow:OnQueueStopped()
	self:UpdateStatus('Stopped')
	self:UpdateDisenchantButton()
end

function MainWindow:OnQueuePaused(_, reason)
	self:UpdateStatus('Paused: ' .. (reason or 'unknown'))
end
