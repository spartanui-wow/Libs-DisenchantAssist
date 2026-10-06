-- A small fake WoW client for driving Lib's Disenchant Assist headless (see Tests/run.lua).
-- The secure click emulation copies SecureActionButton_OnClick from wow-ui-source (live,
-- forever, classic_era are identical): the action runs on the press half chosen by the
-- useOnKeyDown attribute, falling back to the ActionButtonUseKeyDown CVar.

unpack = table.unpack
loadstring = load
tinsert, tremove = table.insert, table.remove
format, strmatch, strfind, gsub, strsub, strlower, strupper = string.format, string.match, string.find, string.gsub, string.sub, string.lower, string.upper
floor, ceil, max, min, abs = math.floor, math.ceil, math.max, math.min, math.abs
function wipe(t)
	for k in pairs(t) do
		t[k] = nil
	end
	return t
end
function strtrim(s)
	return (s:gsub('^%s+', ''):gsub('%s+$', ''))
end
string.trim = strtrim
function strsplit(sep, s, n)
	local out = {}
	for piece in (s .. sep):gmatch('(.-)' .. sep:gsub('%p', '%%%0')) do
		out[#out + 1] = piece
	end
	return unpack(out)
end
function strjoin(sep, ...)
	return table.concat({ ... }, sep)
end
strlenutf8 = string.len
function geterrorhandler()
	return function(e)
		error(e, 0)
	end
end
function securecallfunction(f, ...)
	return f(...)
end
function hooksecurefunc() end
function issecurevariable()
	return true
end
date = os.date
time = os.time

MOCK = {
	now = 1000,
	timers = {},
	frames = {},
	chat = {},
	errors = {},
	actions = {},
	cvars = { ActionButtonUseKeyDown = true },
	combat = false,
	casting = nil,
	cursor = nil,
	loot = {},
	lootOpen = false,
	bags = {},
	items = {},
	macros = {},
	bindings = {},
	salvageFails = {},
	refuse = {},
	guid = 0,
}

function GetTime()
	return MOCK.now
end

C_Timer = {}
function C_Timer.After(delay, fn)
	table.insert(MOCK.timers, { at = MOCK.now + delay, fn = fn })
end
function C_Timer.NewTimer(delay, fn)
	local t = { at = MOCK.now + delay, fn = fn }
	function t:Cancel()
		self.cancelled = true
	end
	table.insert(MOCK.timers, t)
	return t
end

function MOCK.Advance(seconds)
	local target = MOCK.now + seconds
	while true do
		table.sort(MOCK.timers, function(a, b)
			return a.at < b.at
		end)
		local nextTimer = MOCK.timers[1]
		if not nextTimer or nextTimer.at > target then
			break
		end
		table.remove(MOCK.timers, 1)
		MOCK.now = nextTimer.at
		if not nextTimer.cancelled then
			nextTimer.fn()
		end
	end
	MOCK.now = target
end

----------------------------------------------------------------------------------------------------
-- Frames
----------------------------------------------------------------------------------------------------
local Frame = {}
local FrameMeta = {
	__index = function(_, key)
		local method = Frame[key]
		if method then
			return method
		end
		-- Unknown widget methods are layout and art calls the tests do not check. Only
		-- method-style names answer, so field checks still see nil.
		if type(key) ~= 'string' or not key:match('^%u') then
			return nil
		end
		return function(self)
			return nil
		end
	end,
}

local function NewRegion(kind, name, parent)
	local f = setmetatable({ _kind = kind, _name = name, _parent = parent, _scripts = {}, _events = {}, _unitEvents = {}, _attr = {}, _shown = true, _text = nil }, FrameMeta)
	if name then
		_G[name] = f
	end
	return f
end

function CreateFrame(kind, name, parent, template)
	local f = NewRegion(kind, name, parent)
	f._template = template or ''
	f._secure = f._template:find('SecureActionButtonTemplate') ~= nil
	table.insert(MOCK.frames, f)
	if f._template:find('OptionsSliderTemplate') and name then
		NewRegion('FontString', name .. 'Low')
		NewRegion('FontString', name .. 'High')
		NewRegion('FontString', name .. 'Text')
	end
	if f._template:find('ButtonFrameTemplate') then
		f.TitleText = NewRegion('FontString')
	end
	return f
end

function Frame:GetName()
	return self._name
end
function Frame:GetParent()
	return self._parent
end
function Frame:SetParent(p)
	self._parent = p
end
function Frame:IsObjectType(t)
	return self._kind == t
end
function Frame:IsForbidden()
	return false
end
function Frame:SetScript(script, fn)
	self._scripts[script] = fn
end
function Frame:GetScript(script)
	return self._scripts[script]
end
function Frame:HookScript(script, fn)
	local old = self._scripts[script]
	self._scripts[script] = function(...)
		if old then
			old(...)
		end
		fn(...)
	end
end
function Frame:RunScript(script, ...)
	local fn = self._scripts[script]
	if fn then
		fn(self, ...)
	end
end
function Frame:RegisterEvent(event)
	self._events[event] = true
end
function Frame:RegisterUnitEvent(event, unit)
	self._events[event] = true
	self._unitEvents[event] = unit
end
function Frame:UnregisterEvent(event)
	self._events[event] = nil
	self._unitEvents[event] = nil
end
function Frame:UnregisterAllEvents()
	self._events = {}
	self._unitEvents = {}
end
function Frame:IsEventRegistered(event)
	return self._events[event] == true
end
function Frame:Show()
	self._shown = true
	self:RunScript('OnShow')
end
function Frame:Hide()
	local was = self._shown
	self._shown = false
	if was then
		self:RunScript('OnHide')
	end
end
function Frame:SetShown(s)
	if s then
		self:Show()
	else
		self:Hide()
	end
end
function Frame:IsShown()
	return self._shown
end
function Frame:IsVisible()
	local f = self
	while f do
		if not f._shown then
			return false
		end
		f = f._parent
	end
	return true
end
function Frame:SetText(t)
	self._text = t
end
function Frame:GetText()
	return self._text
end
function Frame:CreateFontString(name)
	return NewRegion('FontString', name, self)
end
function Frame:CreateTexture(name)
	return NewRegion('Texture', name, self)
end
function Frame:SetChecked(v)
	self._checked = v
end
function Frame:GetChecked()
	return self._checked
end
function Frame:EnableKeyboard(v)
	self._keyboard = v
end
function Frame:EnableMouseWheel(v)
	self._wheel = v
end
function Frame:SetHighlightTexture(t)
	self._highlight = t
end
function Frame:GetHighlightTexture()
	return self._highlight or NewRegion('Texture')
end
function Frame:LockHighlight()
	self._locked = true
end
function Frame:UnlockHighlight()
	self._locked = false
end
function Frame:SetAttribute(key, value)
	if MOCK.combat and self._secure then
		error('ADDON_ACTION_BLOCKED: SetAttribute on a protected frame in combat')
	end
	self._attr[key] = value
end
function Frame:GetAttribute(key)
	return self._attr[key]
end
function Frame:RegisterForClicks(...)
	self._clicks = { ... }
end

-- How the game presses a button. kind: 'mouse' (a real mouse click on the button), 'key' (a
-- CLICK binding) or 'script' (Click() from code, which /click uses).
function Frame:Press(kind, down)
	local fn = self._scripts.PreClick
	if fn then
		fn(self, 'LeftButton', down)
	end
	if self._secure then
		local isKeyPress = kind == 'key'
		local isSecureAction = kind ~= 'script'
		local isSecureMousePress = not isKeyPress and isSecureAction
		local useOnKeyDown = self._attr.useOnKeyDown
		if useOnKeyDown == nil then
			useOnKeyDown = MOCK.cvars.ActionButtonUseKeyDown
		end
		useOnKeyDown = not isSecureMousePress and useOnKeyDown
		local clickAction = (down and useOnKeyDown) or (not down and not useOnKeyDown)
		if clickAction then
			MOCK.PerformAction(self)
		end
	end
	fn = self._scripts.PostClick
	if fn then
		fn(self, 'LeftButton', down)
	end
end

-- A mouse click, a bound key and /click as the game sends them
function MOCK.MouseClick(btn)
	btn:Press('mouse', true)
	btn:Press('mouse', false)
end
function MOCK.KeyPress(btn)
	btn:Press('key', true)
	btn:Press('key', false)
end
function MOCK.SlashClick(btn)
	-- /click Name -> button:Click('LeftButton', false)
	btn:Press('script', false)
end
function MOCK.KeyBinding(key)
	local command = MOCK.bindings[key]
	local name = command and command:match('^CLICK ([^:]+):')
	if name then
		MOCK.KeyPress(_G[name])
	end
end

function MOCK.Fire(event, ...)
	for _, f in ipairs(MOCK.frames) do
		if f._events[event] then
			local unit = f._unitEvents[event]
			local arg1 = ...
			if not unit or unit == arg1 then
				local fn = f._scripts.OnEvent
				if fn then
					fn(f, event, ...)
				end
			end
		end
	end
end

UIParent = CreateFrame('Frame', 'UIParent')
WorldFrame = CreateFrame('Frame', 'WorldFrame')
UISpecialFrames = {}
GameTooltip = CreateFrame('GameTooltip', 'GameTooltip')
UIErrorsFrame = CreateFrame('Frame', 'UIErrorsFrame')
function UIErrorsFrame:AddMessage(text)
	table.insert(MOCK.errors, text)
end
DEFAULT_CHAT_FRAME = CreateFrame('Frame', 'ChatFrame1')
function DEFAULT_CHAT_FRAME:AddMessage(text)
	table.insert(MOCK.chat, text)
end
ChatFrame1 = DEFAULT_CHAT_FRAME
function ButtonFrameTemplate_HidePortrait() end
function Mixin(o, ...)
	for _, m in ipairs({ ... }) do
		for k, v in pairs(m) do
			o[k] = v
		end
	end
	return o
end
BackdropTemplateMixin = nil
StaticPopupDialogs = {}
MOCK.popups = {}
function StaticPopup_Show(which, a, b)
	local dialog = { which = which, a = a, b = b }
	table.insert(MOCK.popups, dialog)
	return dialog
end
function MOCK.AcceptPopup(dialog)
	StaticPopupDialogs[dialog.which].OnAccept(dialog, dialog.data)
end

----------------------------------------------------------------------------------------------------
-- Game state
----------------------------------------------------------------------------------------------------
function GetBuildInfo()
	return '1.0', '1', 'Oct 1 2026', MOCK.toc or 16001
end
function GetLocale()
	return 'enUS'
end
function UnitFactionGroup()
	return 'Alliance'
end
function UnitClass()
	return 'Mage', 'MAGE'
end
function UnitRace()
	return 'Human', 'Human'
end
function UnitName()
	return 'Tester'
end
function UnitNameUnmodified()
	return 'Tester'
end
function GetRealmName()
	return 'Realm'
end
function GetCurrentRegion()
	return 1
end
function GetCurrentRegionName()
	return 'US'
end
function IsLoggedIn()
	return true
end
function InCombatLockdown()
	return MOCK.combat
end
function GetCVarBool(name)
	return MOCK.cvars[name]
end
function UnitCastingInfo(unit)
	if unit == 'player' and MOCK.casting then
		return 'Disenchant'
	end
end
function UnitChannelInfo() end
function GetCursorInfo()
	if MOCK.cursor then
		return MOCK.cursor.kind, MOCK.cursor.id
	end
end
function ClearCursor()
	MOCK.cursor = nil
end
function IsShiftKeyDown()
	return MOCK.shift
end
function IsControlKeyDown()
	return false
end
function IsAltKeyDown()
	return false
end

C_SpellBook = {
	IsSpellInSpellBook = function()
		return true
	end,
}
function IsPlayerSpell()
	return true
end
function FindSpellBookSlotBySpellID()
	if MOCK.salvage then
		return nil
	end
	return 1
end
C_TradeSkillUI = {
	CraftSalvage = function() end,
}

-- Bags: MOCK.bags[bag][slot] = { itemID, locked }
C_Container = {}
function C_Container.GetContainerNumSlots(bag)
	return MOCK.bags[bag] and 16 or 0
end
function C_Container.GetContainerItemInfo(bag, slot)
	local entry = MOCK.bags[bag] and MOCK.bags[bag][slot]
	if not entry then
		return nil
	end
	local def = MOCK.items[entry.itemID]
	return { itemID = entry.itemID, isLocked = entry.locked or false, quality = def.quality, stackCount = 1, isBound = false }
end
function C_Container.GetContainerItemID(bag, slot)
	local entry = MOCK.bags[bag] and MOCK.bags[bag][slot]
	return entry and entry.itemID
end
function C_Container.GetContainerItemLink(bag, slot)
	local entry = MOCK.bags[bag] and MOCK.bags[bag][slot]
	return entry and ('|Hitem:' .. entry.itemID .. '|h[' .. MOCK.items[entry.itemID].name .. ']|h')
end
C_Item = {}
function C_Item.GetItemInfo(itemID)
	local def = MOCK.items[itemID]
	if not def then
		return nil
	end
	return def.name, nil, def.quality, def.ilvl, nil, nil, nil, nil, def.equipLoc or 'INVTYPE_CHEST', nil, nil, def.classID or 4, 1
end
function C_Item.GetDetailedItemLevelInfo(link)
	local id = tonumber(link:match('item:(%d+)'))
	return MOCK.items[id].ilvl
end
function C_Item.GetItemIconByID()
	return 134400
end
function C_Item.GetItemQualityColor()
	return 1, 1, 1
end
function GetInventoryItemLink() end
C_EquipmentSet = {
	GetEquipmentSetIDs = function()
		return {}
	end,
}
C_TooltipInfo = {
	GetBagItem = function()
		return { lines = {} }
	end,
}
C_Texture = {
	GetAtlasInfo = function()
		return nil
	end,
}
ITEM_BIND_ON_EQUIP = 'Binds when equipped'
SPELL_FAILED_CANT_BE_DISENCHANTED = 'Item cannot be disenchanted'
SPELL_FAILED_SPELL_IN_PROGRESS = 'Another action is in progress'

function MOCK.AddItem(bag, slot, itemID, name, quality, ilvl)
	MOCK.items[itemID] = { name = name, quality = quality or 2, ilvl = ilvl or 100 }
	MOCK.bags[bag] = MOCK.bags[bag] or {}
	MOCK.bags[bag][slot] = { itemID = itemID }
end

-- What the game does when the secure handler runs the button's action
function MOCK.PerformAction(btn)
	local t = btn._attr.type
	if not t then
		table.insert(MOCK.actions, { kind = 'none' })
		return
	end
	local bag, slot
	if t == 'spell' then
		bag, slot = btn._attr['target-bag'], btn._attr['target-slot']
	elseif t == 'macro' then
		local text = btn._attr.macrotext
		bag, slot = text:match('CreateFromBagAndSlot%((%d+), (%d+)%)')
		bag, slot = tonumber(bag), tonumber(slot)
	end
	table.insert(MOCK.actions, { kind = t, bag = bag, slot = slot })
	MOCK.StartCast(bag, slot)
end

function MOCK.StartCast(bag, slot)
	if MOCK.casting then
		MOCK.Fire('UNIT_SPELLCAST_FAILED', 'player', 'Cast-x', 13262)
		MOCK.Fire('UI_ERROR_MESSAGE', 51, SPELL_FAILED_SPELL_IN_PROGRESS)
		return
	end
	local entry = MOCK.bags[bag] and MOCK.bags[bag][slot]
	if not entry then
		return
	end
	if MOCK.refuse[entry.itemID] then
		MOCK.Fire('UNIT_SPELLCAST_FAILED', 'player', 'Cast-r', 13262)
		MOCK.Fire('UI_ERROR_MESSAGE', 50, SPELL_FAILED_CANT_BE_DISENCHANTED)
		return
	end
	if MOCK.salvageFails[entry.itemID] then
		return -- nothing at all happens
	end
	MOCK.guid = MOCK.guid + 1
	MOCK.casting = { bag = bag, slot = slot, guid = 'Cast-' .. MOCK.guid }
	entry.locked = true
	MOCK.Fire('UNIT_SPELLCAST_START', 'player', MOCK.casting.guid, 13262)
end

function MOCK.FinishCast(lootCount)
	local c = MOCK.casting
	assert(c, 'no cast to finish')
	MOCK.casting = nil
	MOCK.Fire('UNIT_SPELLCAST_SUCCEEDED', 'player', c.guid, 13262)
	MOCK.bags[c.bag][c.slot] = nil
	MOCK.loot = {}
	for i = 1, lootCount or 2 do
		MOCK.loot[i] = true
	end
	MOCK.lootOpen = true
	MOCK.Fire('LOOT_READY', false)
	MOCK.Fire('LOOT_OPENED', false, false)
	if #MOCK.loot == 0 then
		MOCK.lootOpen = false
		MOCK.Fire('LOOT_CLOSED')
	end
	MOCK.Fire('BAG_UPDATE_DELAYED')
end

function MOCK.InterruptCast()
	local c = MOCK.casting
	MOCK.casting = nil
	MOCK.bags[c.bag][c.slot].locked = false
	MOCK.Fire('UNIT_SPELLCAST_INTERRUPTED', 'player', c.guid, 13262)
end

function GetNumLootItems()
	return MOCK.lootOpen and #MOCK.loot or 0
end
function LootSlot(i)
	if MOCK.bagsFull then
		return
	end
	table.remove(MOCK.loot, i)
end
function GetLootSlotLink() end

-- Macros and bindings
function GetMacroIndexByName(name)
	for i, m in ipairs(MOCK.macros) do
		if m.name == name then
			return i
		end
	end
	return 0
end
function GetMacroBody(i)
	return MOCK.macros[i] and MOCK.macros[i].body
end
function GetNumMacros()
	local account, character = 0, 0
	for _, m in ipairs(MOCK.macros) do
		if m.perCharacter then
			character = character + 1
		else
			account = account + 1
		end
	end
	return account, character
end
MAX_ACCOUNT_MACROS = 120
MAX_CHARACTER_MACROS = 30
function CreateMacro(name, icon, body, perCharacter)
	if MOCK.combat then
		error('CreateMacro in combat')
	end
	local _, character = GetNumMacros()
	if perCharacter and character >= (MOCK.charMacroLimit or 30) then
		error('Too many macros')
	end
	table.insert(MOCK.macros, { name = name, icon = icon, body = body, perCharacter = perCharacter })
	return #MOCK.macros
end
function PickupMacro(i)
	MOCK.cursor = { kind = 'macro', id = i }
end
function GetBindingKey(command)
	local keys = {}
	for key, cmd in pairs(MOCK.bindings) do
		if cmd == command then
			keys[#keys + 1] = key
		end
	end
	table.sort(keys)
	return unpack(keys)
end
function GetBindingAction(key)
	return MOCK.bindings[key] or ''
end
function SetBinding(key, command)
	if MOCK.combat then
		error('SetBinding in combat')
	end
	MOCK.bindings[key] = command
	return true
end
function GetCurrentBindingSet()
	return 1
end
function SaveBindings()
	MOCK.Fire('UPDATE_BINDINGS')
end
function GetBindingText(key)
	return key
end
BINDING_NAME_JUMP = 'Jump'
