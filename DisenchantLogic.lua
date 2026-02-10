---@class LibsDisenchantAssist
local LibsDisenchantAssist = _G.LibsDisenchantAssist

---@class DisenchantLogic
local DisenchantLogic = {}

DisenchantLogic.isDisenchanting = false
DisenchantLogic.currentItem = nil
DisenchantLogic.itemQueue = {}
DisenchantLogic.DISENCHANT_SPELL_ID = 13262
DisenchantLogic.secureOperationInProgress = false
DisenchantLogic.expectedSpellcast = false

---Handle profile changes
function DisenchantLogic:OnProfileChanged()
	-- Nothing specific needed for profile changes currently
end

---Initialize DisenchantLogic
function DisenchantLogic:Initialize()
	LibsDisenchantAssist:RegisterEvent('UNIT_SPELLCAST_START', function(event, unitID, _, spellID)
		if unitID == 'player' then
			self:OnSpellcastStart(spellID)
		end
	end)

	LibsDisenchantAssist:RegisterEvent('UNIT_SPELLCAST_SUCCEEDED', function(event, unitID, _, spellID)
		if unitID == 'player' and spellID == self.DISENCHANT_SPELL_ID then
			self:OnDisenchantComplete()
		end
	end)

	LibsDisenchantAssist:RegisterEvent('UNIT_SPELLCAST_FAILED', function(event, unitID)
		if unitID == 'player' and self.isDisenchanting then
			self:OnDisenchantFailed()
		end
	end)

	LibsDisenchantAssist:RegisterEvent('UNIT_SPELLCAST_INTERRUPTED', function(event, unitID)
		if unitID == 'player' and self.isDisenchanting then
			self:OnDisenchantInterrupted()
		end
	end)
end

---Start a secure disenchant operation (called by secure button PreClick)
---@param item table
function DisenchantLogic:StartSecureDisenchant(item)
	if self.secureOperationInProgress then
		LibsDisenchantAssist:Print('Disenchant operation already in progress')
		return
	end

	self.secureOperationInProgress = true
	self.expectedSpellcast = true
	self.currentItem = item
	LibsDisenchantAssist:Print('Starting secure disenchant for ' .. (item.itemName or 'item'))

	-- Add a timeout to prevent stuck operations
	C_Timer.After(10, function()
		if self.secureOperationInProgress then
			LibsDisenchantAssist:DebugPrint('Secure operation timed out, resetting flags')
			self.secureOperationInProgress = false
			self.expectedSpellcast = false
			self.isDisenchanting = false
			self.currentItem = nil
		end
	end)
end

---Check if player can disenchant
---@return boolean
function DisenchantLogic:CanDisenchant()
	if not C_SpellBook.IsSpellInSpellBook(self.DISENCHANT_SPELL_ID) then
		LibsDisenchantAssist:Print("You don't know how to disenchant!")
		return false
	end

	if not C_Spell.IsSpellUsable(self.DISENCHANT_SPELL_ID) then
		LibsDisenchantAssist:Print('Cannot disenchant right now.')
		return false
	end

	if UnitCastingInfo('player') or UnitChannelInfo('player') then
		LibsDisenchantAssist:Print('Cannot disenchant while casting.')
		return false
	end

	if #GetLootInfo() > 0 then
		LibsDisenchantAssist:Print('Cannot disenchant while loot window is open.')
		return false
	end

	return true
end

---Disenchant a single item
---@param item table
---@return boolean
function DisenchantLogic:DisenchantItem(item)
	if not self:CanDisenchant() then
		return false
	end

	if not item or not item.bag or not item.slot then
		LibsDisenchantAssist:Print('Invalid item data.')
		return false
	end

	local itemInfo = C_Container.GetContainerItemInfo(item.bag, item.slot)
	if not itemInfo then
		LibsDisenchantAssist:Print('Item no longer exists in that location.')
		return false
	end

	if LibsDisenchantAssist.DB.confirmDisenchant then
		StaticPopupDialogs['LIBS_DISENCHANT_CONFIRM'] = {
			text = 'Disenchant ' .. item.itemLink .. '?',
			button1 = 'Yes',
			button2 = 'No',
			OnAccept = function()
				self:PerformDisenchant(item)
			end,
			timeout = 0,
			whileDead = true,
			hideOnEscape = true,
		}
		StaticPopup_Show('LIBS_DISENCHANT_CONFIRM')
	else
		self:PerformDisenchant(item)
	end

	return true
end

---Perform the actual disenchant action
---@param item table
function DisenchantLogic:PerformDisenchant(item)
	self.isDisenchanting = true
	self.currentItem = item

	-- Cast the Disenchant spell first
	local spellName = C_Spell.GetSpellName(self.DISENCHANT_SPELL_ID)
	if not spellName then
		LibsDisenchantAssist:Print('Disenchant spell not found')
		self.isDisenchanting = false
		self.currentItem = nil
		return
	end

	if not CastSpellByName(spellName) then
		LibsDisenchantAssist:Print('Failed to cast Disenchant spell')
		self.isDisenchanting = false
		self.currentItem = nil
		return
	end

	-- Wait a bit for the spell to be cast and cursor to change
	C_Timer.After(0.1, function()
		if CursorHasSpell() then
			-- Now click on the item to disenchant it
			C_Container.UseContainerItem(item.bag, item.slot)
		else
			LibsDisenchantAssist:Print('Failed to start disenchanting - no spell cursor')
			self.isDisenchanting = false
			self.currentItem = nil
		end
	end)
end

---Disenchant all filtered items
function DisenchantLogic:DisenchantAll()
	LibsDisenchantAssist:Print('=== DISENCHANT ALL DEBUG START ===')

	if self.isDisenchanting then
		LibsDisenchantAssist:Print('Already disenchanting an item.')
		LibsDisenchantAssist:Print('=== DISENCHANT ALL DEBUG END ===')
		return
	end

	-- Check if we can disenchant at all
	if not self:CanDisenchant() then
		LibsDisenchantAssist:Print('Cannot disenchant right now (see previous messages)')
		LibsDisenchantAssist:Print('=== DISENCHANT ALL DEBUG END ===')
		return
	end

	LibsDisenchantAssist:Print('Getting disenchantable items...')
	local items = LibsDisenchantAssist.FilterSystem:GetDisenchantableItems()
	LibsDisenchantAssist:Print('Found ' .. #items .. ' items to disenchant')

	if #items == 0 then
		LibsDisenchantAssist:Print('No items to disenchant.')
		LibsDisenchantAssist:Print('=== DISENCHANT ALL DEBUG END ===')
		return
	end

	-- Debug: Show the items we're about to disenchant
	LibsDisenchantAssist:Print('Items to disenchant:')
	for i, item in ipairs(items) do
		LibsDisenchantAssist:Print('  ' .. i .. '. ' .. (item.itemLink or item.itemName or 'Unknown') .. ' (Bag: ' .. item.bag .. ', Slot: ' .. item.slot .. ')')
	end

	LibsDisenchantAssist:Print('Confirmation setting: ' .. tostring(LibsDisenchantAssist.DB.confirmDisenchant))

	if LibsDisenchantAssist.DB.confirmDisenchant then
		LibsDisenchantAssist:Print('Showing confirmation dialog...')
		StaticPopupDialogs['LIBS_DISENCHANT_ALL_CONFIRM'] = {
			text = 'Disenchant ' .. #items .. ' items?',
			button1 = 'Yes',
			button2 = 'No',
			OnAccept = function()
				LibsDisenchantAssist:Print('User confirmed - starting batch disenchant')
				self:StartBatchDisenchant(items)
			end,
			OnCancel = function()
				LibsDisenchantAssist:Print('User cancelled disenchant')
			end,
			timeout = 0,
			whileDead = true,
			hideOnEscape = true,
		}
		StaticPopup_Show('LIBS_DISENCHANT_ALL_CONFIRM')
	else
		LibsDisenchantAssist:Print('No confirmation needed - starting batch disenchant')
		self:StartBatchDisenchant(items)
	end

	LibsDisenchantAssist:Print('=== DISENCHANT ALL DEBUG END ===')
end

---Start batch disenchant process
---@param items table<number, table>
function DisenchantLogic:StartBatchDisenchant(items)
	self.itemQueue = {}

	for i, item in ipairs(items) do
		table.insert(self.itemQueue, item)
	end

	LibsDisenchantAssist:Print('Starting batch disenchant of ' .. #self.itemQueue .. ' items...')
	self:ProcessNextItem()
end

---Process next item in queue
function DisenchantLogic:ProcessNextItem()
	if #self.itemQueue == 0 then
		LibsDisenchantAssist:Print('Batch disenchant complete!')
		return
	end

	local nextItem = table.remove(self.itemQueue, 1)

	local itemInfo = C_Container.GetContainerItemInfo(nextItem.bag, nextItem.slot)
	if not itemInfo or itemInfo.itemID ~= nextItem.itemID then
		self:ProcessNextItem()
		return
	end

	self:PerformDisenchant(nextItem)
end

---Handle spellcast start event
function DisenchantLogic:OnSpellcastStart(spellID)
	LibsDisenchantAssist:DebugPrint('OnSpellcastStart fired, spellID=' .. tostring(spellID) .. ', expected=' .. tostring(self.DISENCHANT_SPELL_ID))
	LibsDisenchantAssist:DebugPrint('secureOp=' .. tostring(self.secureOperationInProgress) .. ', expectedCast=' .. tostring(self.expectedSpellcast))

	-- Validate this is the expected disenchant operation
	if spellID == self.DISENCHANT_SPELL_ID then
		if self.secureOperationInProgress and self.expectedSpellcast then
			-- This is a valid secure disenchant operation
			self.expectedSpellcast = false
			self.isDisenchanting = true
			if self.currentItem then
				LibsDisenchantAssist:Print('Securely disenchanting ' .. self.currentItem.itemLink .. '...')
			end
		elseif self.isDisenchanting and self.currentItem then
			-- Legacy non-secure operation (for batch mode)
			LibsDisenchantAssist:Print('Disenchanting ' .. self.currentItem.itemLink .. '...')
		else
			-- Unexpected disenchant cast - could be security issue
			LibsDisenchantAssist:Print('Warning: Unexpected disenchant spell cast detected')
		end
	end
end

---Handle successful disenchant completion
function DisenchantLogic:OnDisenchantComplete()
	if self.currentItem then
		LibsDisenchantAssist:Print('Successfully disenchanted ' .. self.currentItem.itemLink)
		self.currentItem = nil
	end

	-- Reset all operation flags
	self.isDisenchanting = false
	self.secureOperationInProgress = false
	self.expectedSpellcast = false

	C_Timer.After(0.5, function()
		if LibsDisenchantAssist.UI and LibsDisenchantAssist.UI.frame and LibsDisenchantAssist.UI.frame:IsVisible() then
			LibsDisenchantAssist.UI:RefreshItemList()
		end

		if #self.itemQueue > 0 then
			C_Timer.After(1, function()
				self:ProcessNextItem()
			end)
		end
	end)
end

---Handle disenchant failure
function DisenchantLogic:OnDisenchantFailed()
	if self.currentItem then
		LibsDisenchantAssist:Print('Failed to disenchant ' .. self.currentItem.itemLink)
		self.currentItem = nil
	end

	-- Reset all operation flags
	self.isDisenchanting = false
	self.secureOperationInProgress = false
	self.expectedSpellcast = false
	self.itemQueue = {}
end

---Handle disenchant interruption
function DisenchantLogic:OnDisenchantInterrupted()
	if self.currentItem then
		LibsDisenchantAssist:Print('Disenchant interrupted for ' .. self.currentItem.itemLink)
		self.currentItem = nil
	end

	-- Reset all operation flags
	self.isDisenchanting = false
	self.secureOperationInProgress = false
	self.expectedSpellcast = false
	self.itemQueue = {}
end

---Stop batch disenchant process
function DisenchantLogic:StopBatchDisenchant()
	if #self.itemQueue > 0 then
		LibsDisenchantAssist:Print('Stopped batch disenchant. ' .. #self.itemQueue .. ' items remaining.')
		self.itemQueue = {}
	end
end

LibsDisenchantAssist.DisenchantLogic = DisenchantLogic
