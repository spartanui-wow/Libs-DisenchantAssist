---@class LibsDisenchantAssist
local LibsDisenchantAssist = LibStub('AceAddon-3.0'):GetAddon('LibsDisenchantAssist')

---@class LibsDisenchantAssist.DisenchantEngine : AceModule, AceEvent-3.0, AceTimer-3.0
local DisenchantEngine = LibsDisenchantAssist:NewModule('DisenchantEngine')
LibsDisenchantAssist.DisenchantEngine = DisenchantEngine

-- The game allows one disenchant per click or key press, so there is no queue to run. Every
-- press of a disenchant button picks its item at that moment (in PreClick, before the secure
-- handler reads the attributes), which keeps spam-clicking, key bindings and /click macros
-- working no matter how fast or how early they arrive.

-- A press that has not started a cast after this long is over
local PRESS_WINDOW = 1.5
-- How long after a press with no cast and no error the item counts as refused
local SILENT_FAILURE_DELAY = 2
-- A loot window opening this soon after a disenchant holds its materials
local LOOT_WINDOW = 5
-- A key released this soon after its press is the same press
local KEY_HOLD = 3

-- The game's own verdict that an item can never be disenchanted
local REFUSED_ERRORS = {
	'SPELL_FAILED_CANT_BE_DISENCHANTED',
	'SPELL_FAILED_CANT_BE_SALVAGED',
}

-- Spellcast events can carry a secret unit token for other units on modern clients, so even
-- comparing it to 'player' can error. A unit event registration keeps other units' casts out.
-- AceEvent has no unit registration, hence the dedicated frame.
local SPELLCAST_HANDLERS = {
	UNIT_SPELLCAST_START = 'OnSpellcastStart',
	UNIT_SPELLCAST_SUCCEEDED = 'OnSpellcastSucceeded',
	UNIT_SPELLCAST_FAILED = 'OnSpellcastFailed',
	UNIT_SPELLCAST_INTERRUPTED = 'OnSpellcastFailed',
}

local canaccessvalue = canaccessvalue or function()
	return true
end

---@param a table|nil
---@param b table|nil
---@return boolean
local function SameItem(a, b)
	return a ~= nil and b ~= nil and a.bag == b.bag and a.slot == b.slot and a.itemID == b.itemID
end

-- The item is still in the bag slot it was found in, and not locked by a cast or a move
---@param item table
---@return boolean
local function IsInPlace(item)
	local info = C_Container.GetContainerItemInfo(item.bag, item.slot)
	return info ~= nil and info.itemID == item.itemID and not info.isLocked
end

---@param record table|nil
---@param castGUID any
---@return boolean
local function IsCast(record, castGUID)
	if not record or record.castGUID == nil or castGUID == nil then
		return true
	end
	if not canaccessvalue(castGUID) or not canaccessvalue(record.castGUID) then
		return false
	end
	return record.castGUID == castGUID
end

function DisenchantEngine:OnInitialize()
	-- The last press: { item, at, started, error }
	self.pending = nil
	-- The cast under way: { item, castGUID }
	self.casting = nil
	-- The item just disenchanted, kept out of the list until the bags confirm it is gone
	self.consumed = nil
	-- When the last disenchant finished, until its loot window opens
	self.lootExpected = nil
	-- Our disenchant's loot window is open
	self.lootOpen = false
	self.sessionCount = 0
	-- Secure buttons set up by SetupSecureButton
	self.buttons = {}

	self:CreateSpellcastWatcher()

	self.windowButton = self:CreateNextButton('LibsDADisenchantButton')
	self.windowButton:Hide()

	-- Key bindings and /click macros press this one, so it works with the window closed. It is
	-- shown but has no size, art or mouse; nothing on screen ever reaches it.
	local nextButton = self:CreateNextButton(LibsDisenchantAssist.NEXT_BUTTON_NAME, true)
	nextButton:SetSize(1, 1)
	nextButton:SetPoint('BOTTOMRIGHT', UIParent, 'TOPLEFT', 0, 0)
	nextButton:EnableMouse(false)
	nextButton:Show()
	self.nextButton = nextButton
end

---A secure button that disenchants the next item each time it is pressed.
---@param name string
---@param keyboard? boolean
---@return Button
function DisenchantEngine:CreateNextButton(name, keyboard)
	local btn = CreateFrame('Button', name, UIParent, 'SecureActionButtonTemplate')
	self:SetupSecureButton(btn, function()
		return self:FindNextItem()
	end, keyboard)
	return btn
end

---Make a secure button disenchant whatever `getItem` returns at the moment it is pressed.
---
---The secure template acts on one half of a press, chosen by the `useOnKeyDown` attribute. Left
---to the "cast on key down" game setting, a /click macro (which sends only the release) does
---nothing at all, which is what made key binds and macros unreliable before.
---
---A mouse click always acts on the release, so window buttons fix the attribute to that. The
---key binding and macro button sees a key (down, then up when the key is let go), the mouse
---wheel and /click (one half only); it acts on whichever half arrives first and skips the
---release of a press that already acted.
---@param btn Button SecureActionButton
---@param getItem fun(btn: Button): table|nil
---@param keyboard? boolean Pressed by key bindings and macros rather than the mouse
function DisenchantEngine:SetupSecureButton(btn, getItem, keyboard)
	btn:RegisterForClicks('AnyUp', 'AnyDown')
	btn:SetAttribute('useOnKeyDown', false)
	self.buttons[btn] = true

	local downAt
	local function IsActingHalf(down)
		if not keyboard then
			return not down
		end
		if down then
			downAt = GetTime()
			return true
		end
		local pressedAt = downAt
		downAt = nil
		return not (pressedAt and (GetTime() - pressedAt) < KEY_HOLD)
	end

	btn:SetScript('PreClick', function(_, _, down)
		if not IsActingHalf(down) then
			return
		end
		if InCombatLockdown() then
			LibsDisenchantAssist:SendMessage('DISENCHANT_ASSIST_BLOCKED', 'combat')
			return
		end
		if keyboard then
			btn:SetAttribute('useOnKeyDown', down and true or false)
		end
		local item = self:CanPress() and getItem(btn) or nil
		if item then
			LibsDisenchantAssist:SetDisenchantAttributes(btn, item.bag, item.slot)
			-- Recorded before the click runs: the cast start (a synchronous event) and any error
			-- can arrive while the secure handler is still running, before PostClick.
			self:OnPressed(item)
		else
			LibsDisenchantAssist:ClearDisenchantAttributes(btn)
		end
	end)

	btn:SetScript('PostClick', function()
		if not InCombatLockdown() then
			LibsDisenchantAssist:ClearDisenchantAttributes(btn)
		end
	end)
end

---Why a press right now would do nothing, or nil when it can disenchant.
---@return string|nil reason 'combat', 'casting', 'loot' or 'cursor'
function DisenchantEngine:GetBlockReason()
	if InCombatLockdown() then
		return 'combat'
	end
	-- With something on the cursor, using the bag slot would drop it there instead of disenchanting
	if GetCursorInfo() then
		return 'cursor'
	end
	if self.casting or UnitCastingInfo('player') or UnitChannelInfo('player') then
		return 'casting'
	end
	local pending = self.pending
	if pending and not pending.started and not pending.error and (GetTime() - pending.at) < PRESS_WINDOW then
		return 'casting'
	end
	-- A new cast closes an open loot window, and anything left in it would be lost
	if self.lootOpen and GetNumLootItems() > 0 then
		return 'loot'
	end
	return nil
end

---@return boolean
function DisenchantEngine:CanPress()
	local reason = self:GetBlockReason()
	if reason then
		LibsDisenchantAssist:SendMessage('DISENCHANT_ASSIST_BLOCKED', reason)
		return false
	end
	return true
end

---@param item table|nil
---@return boolean
function DisenchantEngine:IsUsable(item)
	return item ~= nil and not SameItem(item, self.consumed) and IsInPlace(item)
end

---The first item of a list that a press could disenchant right now.
---@param items? table[] The filtered items, read fresh when omitted
---@return table|nil
function DisenchantEngine:PeekNextItem(items)
	for _, item in ipairs(items or LibsDisenchantAssist.FilterSystem:GetFilteredItems()) do
		if self:IsUsable(item) then
			return item
		end
	end
	return nil
end

---The item the next press disenchants.
---@return table|nil
function DisenchantEngine:FindNextItem()
	local item = self:PeekNextItem()
	if not item then
		LibsDisenchantAssist:SendMessage('DISENCHANT_ASSIST_BLOCKED', 'empty')
	end
	return item
end

---@param item table
function DisenchantEngine:OnPressed(item)
	local press = { item = item, at = GetTime() }
	self.pending = press
	self:CancelSilentFailureCheck()
	self.silentFailureTimer = self:ScheduleTimer('CheckForSilentFailure', SILENT_FAILURE_DELAY, press)
	self:Log('debug', 'Pressed for ' .. (item.itemLink or item.itemName or 'item') .. ' (bag ' .. item.bag .. ' slot ' .. item.slot .. ')')
end

function DisenchantEngine:CreateSpellcastWatcher()
	local watcher = CreateFrame('Frame')
	watcher:SetScript('OnEvent', function(_, event, unit, ...)
		if not watcher.unitFiltered and unit ~= 'player' then
			return
		end
		self[SPELLCAST_HANDLERS[event]](self, event, ...)
	end)
	self.spellcastWatcher = watcher
end

function DisenchantEngine:OnEnable()
	self.refusedErrors = {}
	for _, key in ipairs(REFUSED_ERRORS) do
		if type(_G[key]) == 'string' then
			self.refusedErrors[_G[key]] = true
		end
	end

	local watcher = self.spellcastWatcher
	watcher.unitFiltered = watcher.RegisterUnitEvent ~= nil
	for event in pairs(SPELLCAST_HANDLERS) do
		if watcher.unitFiltered then
			watcher:RegisterUnitEvent(event, 'player')
		else
			watcher:RegisterEvent(event)
		end
	end
	self:RegisterEvent('LOOT_READY', 'OnLootReady')
	self:RegisterEvent('LOOT_OPENED', 'OnLootReady')
	self:RegisterEvent('LOOT_CLOSED', 'OnLootClosed')
	self:RegisterEvent('BAG_UPDATE_DELAYED', 'OnBagUpdateDelayed')
	self:RegisterEvent('UI_ERROR_MESSAGE', 'OnUIError')
	-- Combat lockdown has not begun while this fires, so the buttons can still be disarmed
	self:RegisterEvent('PLAYER_REGEN_DISABLED', 'OnCombatStart')
end

function DisenchantEngine:OnDisable()
	self:UnregisterAllEvents()
	self.spellcastWatcher:UnregisterAllEvents()
	self:CancelSilentFailureCheck()
	self.pending = nil
	self.casting = nil
	self.consumed = nil
	self.lootExpected = nil
	self.lootOpen = false
	self:DisarmAll()
end

function DisenchantEngine:DisarmAll()
	if InCombatLockdown() then
		return
	end
	for btn in pairs(self.buttons) do
		LibsDisenchantAssist:ClearDisenchantAttributes(btn)
	end
end

---@return Button
function DisenchantEngine:GetSecureButton()
	return self.windowButton
end

---@return table|nil item The item of a press still waiting for its cast, now marked as started
function DisenchantEngine:TakePending()
	local pending = self.pending
	if not pending or pending.started or (GetTime() - pending.at) > PRESS_WINDOW then
		return nil
	end
	pending.started = true
	self:CancelSilentFailureCheck()
	return pending.item
end

-- CraftSalvage reports the cast under the salvage spell, not the base disenchant spell, so
-- casts are matched to our own press rather than by spell ID.
function DisenchantEngine:OnSpellcastStart(_, castGUID, spellID)
	local item = self:TakePending()
	if not item then
		return
	end
	self.casting = { item = item, castGUID = castGUID }
	self:Log('debug', 'Cast started (spellID ' .. tostring(spellID) .. ') for ' .. (item.itemName or 'item'))
	LibsDisenchantAssist:SendMessage('DISENCHANT_ASSIST_CASTING', item)
end

function DisenchantEngine:OnSpellcastSucceeded(_, castGUID)
	local item
	if self.casting then
		if not IsCast(self.casting, castGUID) then
			return
		end
		item = self.casting.item
		self.casting = nil
	else
		-- A cast that never reported a start
		item = self:TakePending()
	end
	if item then
		self:OnDisenchanted(item)
	end
end

function DisenchantEngine:OnSpellcastFailed(_, castGUID)
	if not self.casting or not IsCast(self.casting, castGUID) then
		return
	end
	local item = self.casting.item
	self.casting = nil
	self:Log('warning', 'Disenchant stopped for ' .. (item.itemName or 'item'))
	LibsDisenchantAssist:SendMessage('DISENCHANT_ASSIST_CAST_FAILED', item)
end

---@param item table
function DisenchantEngine:OnDisenchanted(item)
	self.consumed = item
	self.lootExpected = GetTime()
	self.sessionCount = self.sessionCount + 1
	self:Log('info', 'Disenchanted: ' .. (item.itemLink or item.itemName or 'item'))
	LibsDisenchantAssist:SendMessage('DISENCHANT_ASSIST_ITEM_DESTROYED', item, self.sessionCount)
end

function DisenchantEngine:OnUIError(_, _, message)
	local pending = self.pending
	if not pending or pending.started or type(message) ~= 'string' or not canaccessvalue(message) then
		return
	end
	if (GetTime() - pending.at) > SILENT_FAILURE_DELAY then
		return
	end

	-- Any message explains the press (moving, another action in progress...), so the "did not
	-- disenchant" question is not asked. Only the game's verdict on the item blocklists it.
	pending.error = message
	if self.refusedErrors[message] then
		self:CancelSilentFailureCheck()
		LibsDisenchantAssist:MarkNonDisenchantable(pending.item.itemID, pending.item.itemName)
	end
end

function DisenchantEngine:CancelSilentFailureCheck()
	if self.silentFailureTimer then
		self:CancelTimer(self.silentFailureTimer)
		self.silentFailureTimer = nil
	end
end

-- On Retail a salvage the item does not qualify for can fail without any message. A press that
-- started no cast, gave no error and left the item where it was is offered for the blocklist.
---@param press table
function DisenchantEngine:CheckForSilentFailure(press)
	self.silentFailureTimer = nil
	if press.started or press.error or self.casting or UnitCastingInfo('player') or UnitChannelInfo('player') then
		return
	end

	local item = press.item
	local info = C_Container.GetContainerItemInfo(item.bag, item.slot)
	if not info or info.itemID ~= item.itemID then
		return
	end
	if LibsDisenchantAssist:IsNonDisenchantable(item.itemID) or LibsDisenchantAssist.promptedNonDE[item.itemID] then
		return
	end
	LibsDisenchantAssist.promptedNonDE[item.itemID] = true

	self:Log('warning', (item.itemName or tostring(item.itemID)) .. ' did not disenchant - asking whether to blocklist it')
	self:ShowNonDEConfirmation(item)
end

---@param item table
function DisenchantEngine:ShowNonDEConfirmation(item)
	local itemName = item.itemName or tostring(item.itemID)
	local itemID = item.itemID

	StaticPopupDialogs['LIBSDA_NON_DISENCHANTABLE'] = {
		text = '|cffb048f8Disenchant Assist|r\n\n' .. (item.itemLink or itemName) .. ' did not disenchant.\n\nMark this item as non-disenchantable?\nIt will be hidden from future scans.',
		button1 = 'Yes',
		button2 = 'No',
		OnAccept = function()
			LibsDisenchantAssist:MarkNonDisenchantable(itemID, itemName)
		end,
		timeout = 30,
		whileDead = true,
		hideOnEscape = true,
		preferredIndex = 3,
	}
	StaticPopup_Show('LIBSDA_NON_DISENCHANTABLE')
end

-- LOOT_READY and LOOT_OPENED both land here; taking the loot twice is harmless
function DisenchantEngine:OnLootReady()
	if not self.lootOpen then
		if not self.lootExpected or (GetTime() - self.lootExpected) > LOOT_WINDOW then
			return
		end
		self.lootExpected = nil
		self.lootOpen = true
	end
	-- Last slot first, so taking one does not shift the others
	for i = GetNumLootItems(), 1, -1 do
		LootSlot(i)
	end
end

function DisenchantEngine:OnLootClosed()
	if not self.lootOpen then
		return
	end
	self.lootOpen = false
	LibsDisenchantAssist:SendMessage('DISENCHANT_ASSIST_ITEMS_UPDATED')
end

function DisenchantEngine:OnBagUpdateDelayed()
	local consumed = self.consumed
	if consumed then
		local info = C_Container.GetContainerItemInfo(consumed.bag, consumed.slot)
		if not info or info.itemID ~= consumed.itemID then
			self.consumed = nil
		end
	end
end

function DisenchantEngine:OnCombatStart()
	self:DisarmAll()
	LibsDisenchantAssist:SendMessage('DISENCHANT_ASSIST_PAUSED', 'combat')
end

---@return table|nil
function DisenchantEngine:GetCastingItem()
	return self.casting and self.casting.item or nil
end

---@return number
function DisenchantEngine:GetSessionCount()
	return self.sessionCount
end

---@param level string
---@param msg string
function DisenchantEngine:Log(level, msg)
	if LibsDisenchantAssist.logger then
		LibsDisenchantAssist.logger[level](msg)
	end
end
