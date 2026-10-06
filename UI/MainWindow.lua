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

-- Older clients lack some modern atlases, and SetAtlas on a missing one draws nothing.
---@param name string
---@return boolean
local function HasAtlas(name)
	return C_Texture and C_Texture.GetAtlasInfo and C_Texture.GetAtlasInfo(name) ~= nil
end

-- Three-slice button art: atlases when the client has them, otherwise the classic panel
-- button texture cut into the same left/center/right pieces.
local BUTTON_ART = {
	normal = {
		atlas = { '128-RedButton-Left', '_128-RedButton-Center', '128-RedButton-Right' },
		file = 'Interface\\Buttons\\UI-Panel-Button-Up',
	},
	pushed = {
		atlas = { '128-RedButton-Left-Pressed', '_128-RedButton-Center-Pressed', '128-RedButton-Right-Pressed' },
		file = 'Interface\\Buttons\\UI-Panel-Button-Down',
	},
}
local FILE_SLICE_COORDS = {
	{ 0, 0.09375, 0, 0.6875 },
	{ 0.09375, 0.53125, 0, 0.6875 },
	{ 0.53125, 0.625, 0, 0.6875 },
}
local FILE_EDGE_WIDTH = 12

---@param btn Button
---@param art table
---@param leftWidth number
---@param rightWidth number
---@return Texture[] slices
local function CreateButtonSlices(btn, art, leftWidth, rightWidth)
	local useAtlas = HasAtlas(art.atlas[1])
	if not useAtlas then
		leftWidth, rightWidth = FILE_EDGE_WIDTH, FILE_EDGE_WIDTH
	end

	local slices = {}
	for i = 1, 3 do
		local tex = btn:CreateTexture(nil, 'BACKGROUND')
		if useAtlas then
			tex:SetAtlas(art.atlas[i])
		else
			tex:SetTexture(art.file)
			tex:SetTexCoord(unpack(FILE_SLICE_COORDS[i]))
		end
		slices[i] = tex
	end

	local left, center, right = slices[1], slices[2], slices[3]
	left:SetPoint('TOPLEFT')
	left:SetPoint('BOTTOMLEFT')
	left:SetWidth(leftWidth)
	right:SetPoint('TOPRIGHT')
	right:SetPoint('BOTTOMRIGHT')
	right:SetWidth(rightWidth)
	center:SetPoint('TOPLEFT', left, 'TOPRIGHT')
	center:SetPoint('BOTTOMRIGHT', right, 'BOTTOMLEFT')
	return slices
end

function MainWindow:OnInitialize()
	self.window = nil
	self.itemRows = {}
	self.isSettingsVisible = false
	self.refreshPending = false
end

function MainWindow:OnEnable()
	self:RegisterMessage('DISENCHANT_ASSIST_ITEMS_UPDATED', 'ScheduleRefresh')
	self:RegisterMessage('DISENCHANT_ASSIST_CASTING', 'OnEngineCasting')
	self:RegisterMessage('DISENCHANT_ASSIST_ITEM_DESTROYED', 'OnItemDestroyed')
	self:RegisterMessage('DISENCHANT_ASSIST_CAST_FAILED', 'OnCastFailed')
	self:RegisterMessage('DISENCHANT_ASSIST_BLOCKED', 'OnBlocked')
	self:RegisterMessage('DISENCHANT_ASSIST_PAUSED', 'OnQueuePaused')
	self:RegisterMessage('DISENCHANT_ASSIST_PROFILE_CHANGED', 'ScheduleRefresh')
	self:RegisterMessage('DISENCHANT_ASSIST_KEY_CHANGED', 'UpdateKeyButton')
	self:RegisterEvent('UPDATE_BINDINGS', 'UpdateKeyButton')
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

	-- Per-row secure disenchant button (1-click disenchant)
	local deBtn = CreateFrame('Button', 'LibsDADeBtn' .. index, row, 'SecureActionButtonTemplate')
	deBtn:SetSize(40, 18)
	deBtn:SetPoint('RIGHT', -40, 0)

	local ilvl = row:CreateFontString(nil, 'ARTWORK', 'GameFontNormalSmall')
	ilvl:SetPoint('RIGHT', deBtn, 'LEFT', -4, 0)
	ilvl:SetJustifyH('RIGHT')
	ilvl:SetTextColor(0.8, 0.8, 1, 1)
	row.Ilvl = ilvl

	local name = row:CreateFontString(nil, 'ARTWORK', 'GameFontNormalSmall')
	name:SetPoint('LEFT', icon, 'RIGHT', 4, 0)
	name:SetPoint('RIGHT', ilvl, 'LEFT', -4, 0)
	name:SetJustifyH('LEFT')
	name:SetWordWrap(false)
	row.Name = name

	local engine = LibsDisenchantAssist.DisenchantEngine
	engine:SetupSecureButton(deBtn, function()
		return engine:IsUsable(row.item) and row.item or nil
	end)

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
	if HasAtlas('common-icon-redx') then
		ignoreBtn:SetNormalAtlas('common-icon-redx')
		ignoreBtn:SetHighlightAtlas('common-icon-redx')
		ignoreBtn:GetHighlightTexture():SetAlpha(0.5)
	else
		ignoreBtn:SetNormalTexture('Interface\\Buttons\\UI-GroupLoot-Pass-Up')
		ignoreBtn:SetHighlightTexture('Interface\\Buttons\\UI-GroupLoot-Pass-Highlight', 'ADD')
	end

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
	self.statusText:SetJustifyH('LEFT')
	self.statusText:SetWordWrap(false)
	self.statusText:SetTextColor(0.8, 0.8, 0.8, 1)
	self.statusText:SetText('')
end

---@param owner Frame
local function ShowShortcutTooltip(owner)
	local key = LibsDisenchantAssist:GetKeyText(LibsDisenchantAssist:GetNextKey())
	GameTooltip:AddLine(' ')
	GameTooltip:AddLine('Faster ways to press it:', 1, 0.82, 0)
	if key then
		GameTooltip:AddLine('Your key: ' .. key, 1, 1, 1)
	else
		GameTooltip:AddLine('Set a key with the button above.', 0.8, 0.8, 0.8)
	end
	GameTooltip:AddLine('Drag it to an action bar to make a button there.', 0.8, 0.8, 0.8)
	GameTooltip:AddLine('Macro line: ' .. LibsDisenchantAssist.MACRO_BODY, 0.8, 0.8, 0.8)
end

function MainWindow:CreateDisenchantButton()
	local engine = LibsDisenchantAssist.DisenchantEngine
	local secureBtn = engine:GetSecureButton()

	local dragIcon = self:CreateMacroIcon()
	dragIcon:SetPoint('BOTTOMLEFT', self.window, 'BOTTOMLEFT', 15, 30)

	secureBtn:SetParent(self.window)
	secureBtn:ClearAllPoints()
	secureBtn:SetPoint('BOTTOMLEFT', dragIcon, 'BOTTOMRIGHT', 6, 0)
	secureBtn:SetPoint('BOTTOMRIGHT', self.window, 'BOTTOMRIGHT', -15, 30)
	secureBtn:SetHeight(36)
	secureBtn:Show()

	local LEFT_WIDTH = 35
	local RIGHT_WIDTH = 80

	local normalSlices = CreateButtonSlices(secureBtn, BUTTON_ART.normal, LEFT_WIDTH, RIGHT_WIDTH)
	local pushedSlices = CreateButtonSlices(secureBtn, BUTTON_ART.pushed, LEFT_WIDTH, RIGHT_WIDTH)

	local highlightTex = secureBtn:CreateTexture(nil, 'HIGHLIGHT')
	if HasAtlas('128-RedButton-Highlight') then
		highlightTex:SetAtlas('128-RedButton-Highlight')
	else
		highlightTex:SetTexture('Interface\\Buttons\\UI-Panel-Button-Highlight')
		highlightTex:SetTexCoord(0, 0.625, 0, 0.6875)
	end
	highlightTex:SetAllPoints()
	highlightTex:SetBlendMode('ADD')

	local function ShowPushed(pushed)
		for i = 1, 3 do
			normalSlices[i]:SetShown(not pushed)
			pushedSlices[i]:SetShown(pushed)
		end
	end
	ShowPushed(false)
	secureBtn:HookScript('OnMouseDown', function()
		ShowPushed(true)
	end)
	secureBtn:HookScript('OnMouseUp', function()
		ShowPushed(false)
	end)

	-- Dragging the button itself puts the same "disenchant next" action on the cursor
	secureBtn:RegisterForDrag('LeftButton')
	secureBtn:SetScript('OnDragStart', function()
		ShowPushed(false)
		self:PickupMacro()
	end)

	secureBtn:SetScript('OnEnter', function(btn)
		GameTooltip:SetOwner(btn, 'ANCHOR_TOP')
		GameTooltip:SetText('Disenchant next', 1, 1, 1)
		GameTooltip:AddLine('Each press disenchants one item. The game needs a separate click or key press for every item.', 0.8, 0.8, 0.8, true)
		ShowShortcutTooltip(btn)
		GameTooltip:Show()
	end)
	secureBtn:SetScript('OnLeave', function()
		GameTooltip:Hide()
	end)

	secureBtn.Text = secureBtn:CreateFontString(nil, 'OVERLAY', 'GameFontNormalLarge')
	secureBtn.Text:SetPoint('LEFT', LEFT_WIDTH * 0.5, 0)
	secureBtn.Text:SetPoint('RIGHT', -LEFT_WIDTH * 0.5, 0)
	secureBtn.Text:SetWordWrap(false)
	secureBtn.Text:SetText('Disenchant next')
	secureBtn.Text:SetTextColor(1, 1, 1, 1)

	self.disenchantButton = secureBtn

	self:CreateKeyButton()
end

---The icon left of the big button: drag or click it to get a "disenchant next" action bar button.
---@return Button
function MainWindow:CreateMacroIcon()
	local icon = CreateFrame('Button', nil, self.window)
	icon:SetSize(36, 36)
	icon:RegisterForDrag('LeftButton')

	local texture = icon:CreateTexture(nil, 'ARTWORK')
	texture:SetAllPoints()
	texture:SetTexture('Interface\\Icons\\INV_Enchant_Disenchant')
	texture:SetTexCoord(0.07, 0.93, 0.07, 0.93)

	local highlight = icon:CreateTexture(nil, 'HIGHLIGHT')
	highlight:SetAllPoints()
	highlight:SetColorTexture(1, 1, 1, 0.2)

	icon:SetScript('OnClick', function()
		self:PickupMacro()
	end)
	icon:SetScript('OnDragStart', function()
		self:PickupMacro()
	end)
	icon:SetScript('OnEnter', function(btn)
		GameTooltip:SetOwner(btn, 'ANCHOR_TOP')
		GameTooltip:SetText('Put it on an action bar', 1, 1, 1)
		GameTooltip:AddLine('Drag this to an action bar. That button then disenchants the next item, the same as the big button, even with this window closed.', 0.8, 0.8, 0.8, true)
		GameTooltip:Show()
	end)
	icon:SetScript('OnLeave', function()
		GameTooltip:Hide()
	end)

	self.macroIcon = icon
	return icon
end

function MainWindow:PickupMacro()
	if InCombatLockdown() then
		self:SetStatus('Not in combat. Try again after the fight.')
		return
	end
	if LibsDisenchantAssist:PickupNextMacro() then
		self:SetStatus('Drop it on an action bar.')
	end
end

-- Keys the capture ignores: the mouse buttons that click the key button, and lone modifiers
local IGNORED_KEYS = {
	LeftButton = true,
	RightButton = true,
	BUTTON1 = true,
	BUTTON2 = true,
	UNKNOWN = true,
	LSHIFT = true,
	RSHIFT = true,
	LCTRL = true,
	RCTRL = true,
	LALT = true,
	RALT = true,
	LMETA = true,
	RMETA = true,
}

local MOUSE_BUTTON_KEYS = {
	MiddleButton = 'BUTTON3',
	Button4 = 'BUTTON4',
	Button5 = 'BUTTON5',
}

---The binding name for a key plus the modifiers held right now, as SetBinding wants it
---@param key string
---@return string
local function WithModifiers(key)
	if IsShiftKeyDown() then
		key = 'SHIFT-' .. key
	end
	if IsControlKeyDown() then
		key = 'CTRL-' .. key
	end
	if IsAltKeyDown() then
		key = 'ALT-' .. key
	end
	if IsMetaKeyDown and IsMetaKeyDown() then
		key = 'META-' .. key
	end
	return key
end

---The "Key:" button: click it and press a key (or the mouse wheel) to bind "disenchant next".
function MainWindow:CreateKeyButton()
	local KEY_BUTTON_WIDTH = 150
	local keyBtn
	if LibAT and LibAT.UI and LibAT.UI.CreateButton then
		keyBtn = LibAT.UI.CreateButton(self.window, KEY_BUTTON_WIDTH, 22, '')
	else
		keyBtn = CreateFrame('Button', nil, self.window, 'UIPanelButtonTemplate')
		keyBtn:SetSize(KEY_BUTTON_WIDTH, 22)
	end
	keyBtn:SetPoint('BOTTOMRIGHT', self.window, 'BOTTOMRIGHT', -15, 70)
	keyBtn:RegisterForClicks('LeftButtonUp', 'RightButtonUp')
	self.keyButton = keyBtn

	self.statusText:SetPoint('RIGHT', keyBtn, 'LEFT', -8, 0)

	local function StopListening()
		self.listeningForKey = false
		keyBtn:EnableKeyboard(false)
		keyBtn:EnableMouseWheel(false)
		self:UpdateKeyButton()
	end

	local function KeyChosen(key)
		StopListening()
		if key == 'ESCAPE' then
			return
		end
		self:BindKey(key)
	end

	keyBtn:SetScript('OnClick', function(_, mouseButton)
		if self.listeningForKey then
			StopListening()
			return
		end
		if mouseButton == 'RightButton' then
			if LibsDisenchantAssist:GetNextKey() then
				LibsDisenchantAssist:ClearNextKey()
				self:SetStatus('Key removed.')
			end
			return
		end
		if InCombatLockdown() then
			self:SetStatus('Keys cannot be changed in combat.')
			return
		end
		self.listeningForKey = true
		keyBtn:EnableKeyboard(true)
		keyBtn:EnableMouseWheel(true)
		keyBtn:SetText('Press a key...')
	end)

	keyBtn:SetScript('OnKeyDown', function(_, key)
		if self.listeningForKey and not IGNORED_KEYS[key] then
			KeyChosen(key == 'ESCAPE' and key or WithModifiers(key))
		end
	end)
	keyBtn:SetScript('OnMouseWheel', function(_, delta)
		if self.listeningForKey then
			KeyChosen(WithModifiers(delta > 0 and 'MOUSEWHEELUP' or 'MOUSEWHEELDOWN'))
		end
	end)
	keyBtn:HookScript('OnMouseDown', function(_, mouseButton)
		local key = MOUSE_BUTTON_KEYS[mouseButton]
		if self.listeningForKey and key then
			KeyChosen(WithModifiers(key))
		end
	end)
	keyBtn:HookScript('OnHide', StopListening)

	keyBtn:HookScript('OnEnter', function(btn)
		GameTooltip:SetOwner(btn, 'ANCHOR_TOP')
		GameTooltip:SetText('Disenchant with a key', 1, 1, 1)
		GameTooltip:AddLine('Click, then press any key or turn the mouse wheel. Each press of that key disenchants the next item, even with this window closed.', 0.8, 0.8, 0.8, true)
		GameTooltip:AddLine('Right-click to remove the key.', 0.8, 0.8, 0.8, true)
		GameTooltip:AddLine('It is also in Key Bindings, under AddOns.', 0.8, 0.8, 0.8, true)
		GameTooltip:Show()
	end)
	keyBtn:HookScript('OnLeave', function()
		GameTooltip:Hide()
	end)

	self:UpdateKeyButton()
end

---@param key string
function MainWindow:BindKey(key)
	local conflict = LibsDisenchantAssist:GetKeyConflict(key)
	if not conflict then
		LibsDisenchantAssist:SetNextKey(key)
		return
	end

	StaticPopupDialogs['LIBSDA_REPLACE_KEY'] = {
		text = '|cffb048f8Disenchant Assist|r\n\n%s is used for:\n%s\n\nUse it to disenchant instead?',
		button1 = 'Yes',
		button2 = 'No',
		OnAccept = function(_, data)
			LibsDisenchantAssist:SetNextKey(data)
		end,
		timeout = 0,
		whileDead = true,
		hideOnEscape = true,
		preferredIndex = 3,
	}
	local popup = StaticPopup_Show('LIBSDA_REPLACE_KEY', LibsDisenchantAssist:GetKeyText(key) or key, conflict)
	if popup then
		popup.data = key
	end
end

function MainWindow:UpdateKeyButton()
	if not self.keyButton or self.listeningForKey then
		return
	end
	local key = LibsDisenchantAssist:GetKeyText(LibsDisenchantAssist:GetNextKey(), true)
	self.keyButton:SetText(key and ('Key: ' .. key) or 'Set a key')
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
	if LibsDisenchantAssist.IsRetail then
		AddCheckbox('Exclude warbound', 'excludeWarbound', 210, yPos)
	end
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

	local engine = LibsDisenchantAssist.DisenchantEngine
	local items = LibsDisenchantAssist.FilterSystem:GetFilteredItems()
	local nextItem = engine:PeekNextItem(items)

	for i = 1, MAX_VISIBLE_ITEMS do
		local row = self.itemRows[i]
		local item = items[i]
		row.item = item
		if item then
			local itemIcon = C_Item.GetItemIconByID(item.itemID)
			row.Icon:SetTexture(itemIcon)

			local r, g, b = C_Item.GetItemQualityColor(item.quality)
			row.Name:SetText(item.itemName)
			row.Name:SetTextColor(r, g, b)

			row.Ilvl:SetText('iLvl ' .. item.itemLevel)
			row.Ilvl:Show()

			if item == nextItem then
				row:LockHighlight()
			else
				row:UnlockHighlight()
			end
			row:Show()
		else
			row:UnlockHighlight()
			row:Hide()
		end
	end

	local totalHeight = math.max(#items * (ITEM_ROW_HEIGHT + 1), 1)
	self.itemList:SetHeight(totalHeight)

	local done = engine:GetSessionCount()
	if done > 0 then
		self.itemCountText:SetText('Items: ' .. #items .. '    Disenchanted: ' .. done)
	else
		self.itemCountText:SetText('Items: ' .. #items)
	end

	self.nextItem = nextItem
	self:UpdateDisenchantButton(#items)
	self:UpdateKeyButton()
	if not self.statusTimer then
		self:ShowDefaultStatus()
	end

	if LibsDisenchantAssist.DataBroker then
		LibsDisenchantAssist.DataBroker:UpdateText()
	end
end

---@param count? number How many items are listed
function MainWindow:UpdateDisenchantButton(count)
	if not self.disenchantButton then
		return
	end

	local text = self.disenchantButton.Text
	count = count or #LibsDisenchantAssist.FilterSystem:GetFilteredItems()
	if LibsDisenchantAssist.DisenchantEngine:GetCastingItem() then
		text:SetText('Disenchanting...')
		text:SetTextColor(1, 1, 0.5, 1)
	elseif count > 0 then
		text:SetText('Disenchant next  (' .. count .. ' left)')
		text:SetTextColor(1, 1, 1, 1)
	else
		text:SetText('Nothing to disenchant')
		text:SetTextColor(0.5, 0.5, 0.5, 1)
	end
end

---Show a message under the list for a few seconds, then go back to the usual "Next:" line.
---@param text string
---@param seconds? number
function MainWindow:SetStatus(text, seconds)
	if not self.statusText then
		return
	end
	self.statusText:SetText(text)
	if self.statusTimer then
		self:CancelTimer(self.statusTimer)
	end
	self.statusTimer = self:ScheduleTimer('ShowDefaultStatus', seconds or 4)
end

function MainWindow:ShowDefaultStatus()
	if self.statusTimer then
		self:CancelTimer(self.statusTimer)
		self.statusTimer = nil
	end
	if not self.statusText then
		return
	end
	local casting = LibsDisenchantAssist.DisenchantEngine:GetCastingItem()
	if casting then
		self.statusText:SetText('Disenchanting ' .. (casting.itemLink or casting.itemName) .. '...')
	elseif self.nextItem then
		self.statusText:SetText('Next: ' .. (self.nextItem.itemLink or self.nextItem.itemName))
	else
		self.statusText:SetText('')
	end
end

function MainWindow:OnEngineCasting(_, item)
	if not item or not self.window then
		return
	end
	self:UpdateDisenchantButton()
	self:ShowDefaultStatus()
end

function MainWindow:OnItemDestroyed(_, item)
	if not item or not self.window then
		return
	end
	self:ScheduleRefresh()
	self:ShowDefaultStatus()
end

function MainWindow:OnCastFailed()
	if not self.window then
		return
	end
	self:UpdateDisenchantButton()
	self:ShowDefaultStatus()
end

-- What a press that did nothing means for the player. Spam-pressing while a cast is under way
-- is normal, so that one says nothing.
local BLOCKED_TEXT = {
	combat = 'In combat. Disenchanting works again after the fight.',
	loot = 'Take the materials from the loot window first. Are your bags full?',
	empty = 'Nothing left to disenchant.',
	cursor = 'Put down what is on your cursor first.',
}

function MainWindow:OnBlocked(_, reason)
	local text = BLOCKED_TEXT[reason]
	if not text then
		return
	end
	if self.window and self.window:IsVisible() then
		self:SetStatus(text)
	elseif UIErrorsFrame then
		UIErrorsFrame:AddMessage(text, 1, 0.1, 0.1)
	end
end

function MainWindow:OnQueuePaused(_, reason)
	if reason == 'combat' and self.window and self.window:IsVisible() then
		self:SetStatus(BLOCKED_TEXT.combat)
	end
end
