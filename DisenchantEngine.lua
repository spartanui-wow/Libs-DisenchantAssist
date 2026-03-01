---@class LibsDisenchantAssist
local LibsDisenchantAssist = LibStub('AceAddon-3.0'):GetAddon('LibsDisenchantAssist')

---@class LibsDisenchantAssist.DisenchantEngine : AceModule, AceEvent-3.0, AceTimer-3.0
local DisenchantEngine = LibsDisenchantAssist:NewModule('DisenchantEngine')
LibsDisenchantAssist.DisenchantEngine = DisenchantEngine

-- State machine states
local STATE_IDLE = 'IDLE'
local STATE_PENDING_CLICK = 'PENDING_CLICK'
local STATE_CASTING = 'CASTING'
local STATE_LOOTING = 'LOOTING'
local STATE_WAITING_BAGS = 'WAITING_BAGS'

function DisenchantEngine:OnInitialize()
	self.state = STATE_IDLE
	self.currentItem = nil
	self.itemQueue = {}
	self.disenchantedCount = 0
	self.totalCount = 0
	self.timeoutTimer = nil

	self:CreateSecureButton()
end

function DisenchantEngine:OnEnable()
	self:RegisterEvent('UNIT_SPELLCAST_START', 'OnSpellcastStart')
	self:RegisterEvent('UNIT_SPELLCAST_SUCCEEDED', 'OnSpellcastSucceeded')
	self:RegisterEvent('UNIT_SPELLCAST_FAILED', 'OnSpellcastFailed')
	self:RegisterEvent('UNIT_SPELLCAST_INTERRUPTED', 'OnSpellcastFailed')
	self:RegisterEvent('LOOT_READY', 'OnLootReady')
	self:RegisterEvent('LOOT_CLOSED', 'OnLootClosed')
	self:RegisterEvent('BAG_UPDATE_DELAYED', 'OnBagUpdateDelayed')
	self:RegisterEvent('PLAYER_REGEN_ENABLED', 'OnCombatEnd')
	self:RegisterEvent('PLAYER_REGEN_DISABLED', 'OnCombatStart')
end

function DisenchantEngine:OnDisable()
	self:UnregisterAllEvents()
	self:ResetState()
end

function DisenchantEngine:CreateSecureButton()
	local btn = CreateFrame('Button', 'LibsDADisenchantButton', UIParent, 'SecureActionButtonTemplate')
	btn:SetSize(200, 40)
	btn:SetPoint('CENTER')
	btn:RegisterForClicks('AnyUp', 'AnyDown')
	btn:Hide()

	btn:SetScript('PreClick', function()
		-- Auto-start the full queue if idle and items exist
		if self.state == STATE_IDLE and not self.currentItem then
			local items = LibsDisenchantAssist.FilterSystem and LibsDisenchantAssist.FilterSystem:GetFilteredItems() or {}
			if #items > 0 then
				self:StartQueue(items)
			else
				btn:SetAttribute('type', 'macro')
				btn:SetAttribute('macrotext', '')
				return
			end
		end

		if self.state ~= STATE_PENDING_CLICK or not self.currentItem then
			btn:SetAttribute('type', 'macro')
			btn:SetAttribute('macrotext', '')
			return
		end

		-- Verify item is still at the expected bag/slot
		local item = self.currentItem
		local containerInfo = C_Container.GetContainerItemInfo(item.bag, item.slot)
		if not containerInfo or containerInfo.itemID ~= item.itemID then
			btn:SetAttribute('type', 'macro')
			btn:SetAttribute('macrotext', '')
			self:Log('warning', 'Item moved or missing from bag ' .. item.bag .. ' slot ' .. item.slot)
			self:OnDisenchantFailed()
			return
		end
	end)

	btn:SetScript('PostClick', function()
		if self.state == STATE_PENDING_CLICK then
			self:StartTimeout()
		end
	end)

	self.secureButton = btn
end

---@return Frame
function DisenchantEngine:GetSecureButton()
	return self.secureButton
end

---@param items table[]
function DisenchantEngine:StartQueue(items)
	if self.state ~= STATE_IDLE then
		self:Log('warning', 'Cannot start queue - engine busy (state: ' .. self.state .. ')')
		return
	end

	self.itemQueue = {}
	for _, item in ipairs(items) do
		table.insert(self.itemQueue, item)
	end

	self.disenchantedCount = 0
	self.totalCount = #self.itemQueue

	self:Log('info', 'Starting disenchant queue: ' .. self.totalCount .. ' items')
	LibsDisenchantAssist:SendMessage('DISENCHANT_ASSIST_QUEUE_STARTED', self.totalCount)

	self:PrepareNextDisenchant()
end

function DisenchantEngine:PrepareNextDisenchant()
	if #self.itemQueue == 0 then
		self:Log('info', 'Queue complete! Disenchanted ' .. self.disenchantedCount .. ' of ' .. self.totalCount .. ' items')
		LibsDisenchantAssist:SendMessage('DISENCHANT_ASSIST_QUEUE_COMPLETE', self.disenchantedCount, self.totalCount)
		self:ResetState()
		return
	end

	if InCombatLockdown() then
		self:Log('info', 'In combat - pausing queue')
		LibsDisenchantAssist:SendMessage('DISENCHANT_ASSIST_PAUSED', 'combat')
		return
	end

	local nextItem = table.remove(self.itemQueue, 1)

	local containerInfo = C_Container.GetContainerItemInfo(nextItem.bag, nextItem.slot)
	if not containerInfo or containerInfo.itemID ~= nextItem.itemID then
		self:Log('debug', 'Item moved, skipping: ' .. (nextItem.itemName or 'unknown'))
		self:PrepareNextDisenchant()
		return
	end

	self.currentItem = nextItem
	self.state = STATE_PENDING_CLICK

	-- Set secure button attributes now so they're ready before the click arrives
	self:SetButtonAttributes(nextItem)

	self:Log('info', 'Ready to disenchant: ' .. nextItem.itemLink)
	LibsDisenchantAssist:SendMessage('DISENCHANT_ASSIST_READY', nextItem)
end

-- Retail trade skills (DE) don't have spellbook slots, so type=spell
-- with target-bag/slot won't work. Instead use C_TradeSkillUI.CraftSalvage() via macro.
-- If the spell IS in the spellbook (Classic), use the direct spell+target approach.
-- Attributes must be set here (not in PreClick) so the secure framework can read them.
function DisenchantEngine:SetButtonAttributes(item)
	if InCombatLockdown() then
		return
	end

	local spellID = LibsDisenchantAssist.DISENCHANT_SPELL_ID
	local btn = self.secureButton

	if FindSpellBookSlotBySpellID and FindSpellBookSlotBySpellID(spellID) then
		btn:SetAttribute('type', 'spell')
		btn:SetAttribute('spell', spellID)
		btn:SetAttribute('target-bag', item.bag)
		btn:SetAttribute('target-slot', item.slot)
		self:Log('debug', 'Spell mode: spellID ' .. spellID .. ' on bag ' .. item.bag .. ' slot ' .. item.slot)
	else
		local macroText = string.format('/run C_TradeSkillUI.CraftSalvage(%d, 1, ItemLocation:CreateFromBagAndSlot(%d, %d))', spellID, item.bag, item.slot)
		btn:SetAttribute('type', 'macro')
		btn:SetAttribute('macrotext', macroText)
		self:Log('debug', 'Macro mode: ' .. macroText)
	end
end

function DisenchantEngine:ClearButtonAttributes()
	if InCombatLockdown() then
		return
	end
	local btn = self.secureButton
	btn:SetAttribute('type', 'macro')
	btn:SetAttribute('macrotext', '')
	btn:SetAttribute('spell', nil)
	btn:SetAttribute('target-bag', nil)
	btn:SetAttribute('target-slot', nil)
end

function DisenchantEngine:Stop()
	local remaining = #self.itemQueue
	self:ResetState()
	self:Log('info', 'Stopped. ' .. remaining .. ' items remaining in queue.')
	LibsDisenchantAssist:SendMessage('DISENCHANT_ASSIST_STOPPED')
end

function DisenchantEngine:ResetState()
	self.state = STATE_IDLE
	self.currentItem = nil
	self.itemQueue = {}
	self:CancelTimeout()
	self:ClearButtonAttributes()
end

function DisenchantEngine:StartTimeout()
	self:CancelTimeout()
	self.timeoutTimer = self:ScheduleTimer('OnTimeout', 10)
end

function DisenchantEngine:CancelTimeout()
	if self.timeoutTimer then
		self:CancelTimer(self.timeoutTimer)
		self.timeoutTimer = nil
	end
end

function DisenchantEngine:OnTimeout()
	self.timeoutTimer = nil
	if self.state ~= STATE_IDLE then
		self:Log('warning', 'Operation timed out (state: ' .. self.state .. '), resetting')
		local hadItem = self.currentItem
		self.state = STATE_IDLE
		self.currentItem = nil
		self:CancelTimeout()

		if #self.itemQueue > 0 then
			self:ScheduleTimer('PrepareNextDisenchant', 0.5)
		else
			if hadItem then
				LibsDisenchantAssist:SendMessage('DISENCHANT_ASSIST_QUEUE_COMPLETE', self.disenchantedCount, self.totalCount)
			end
		end
	end
end

function DisenchantEngine:OnSpellcastStart(_, unitID, _, spellID)
	if unitID ~= 'player' then
		return
	end

	if self.state ~= STATE_PENDING_CLICK then
		return
	end

	if spellID == LibsDisenchantAssist.DISENCHANT_SPELL_ID then
		self.state = STATE_CASTING
		self:CancelTimeout()
		self:Log('debug', 'Cast started for ' .. (self.currentItem.itemName or 'item'))
		LibsDisenchantAssist:SendMessage('DISENCHANT_ASSIST_CASTING', self.currentItem)
	end
end

function DisenchantEngine:OnSpellcastSucceeded(_, unitID, _, spellID)
	if unitID ~= 'player' then
		return
	end

	if self.state ~= STATE_CASTING then
		return
	end

	if spellID == LibsDisenchantAssist.DISENCHANT_SPELL_ID then
		self:Log('debug', 'Cast succeeded for ' .. (self.currentItem.itemName or 'item'))
		self:StartTimeout()
	end
end

function DisenchantEngine:OnSpellcastFailed(_, unitID)
	if unitID ~= 'player' then
		return
	end

	if self.state ~= STATE_PENDING_CLICK and self.state ~= STATE_CASTING then
		return
	end

	self:OnDisenchantFailed()
end

function DisenchantEngine:OnDisenchantFailed()
	local itemName = self.currentItem and self.currentItem.itemName or 'unknown'
	self:Log('warning', 'Disenchant failed for ' .. itemName)

	self.state = STATE_IDLE
	self.currentItem = nil
	self:CancelTimeout()

	if #self.itemQueue > 0 then
		self:ScheduleTimer('PrepareNextDisenchant', 0.5)
	else
		LibsDisenchantAssist:SendMessage('DISENCHANT_ASSIST_QUEUE_COMPLETE', self.disenchantedCount, self.totalCount)
	end
end

function DisenchantEngine:OnLootReady()
	if self.state ~= STATE_CASTING then
		return
	end

	self.state = STATE_LOOTING
	self:CancelTimeout()

	local numItems = GetNumLootItems()
	for i = 1, numItems do
		LootSlot(i)
	end

	self:Log('debug', 'Auto-looted ' .. numItems .. ' items')
	self:StartTimeout()
end

function DisenchantEngine:OnLootClosed()
	if self.state ~= STATE_LOOTING then
		return
	end

	self.state = STATE_WAITING_BAGS
	self:Log('debug', 'Loot closed, waiting for bag update')
	self:StartTimeout()
end

function DisenchantEngine:OnBagUpdateDelayed()
	if self.state ~= STATE_WAITING_BAGS then
		return
	end

	self:CancelTimeout()

	if self.currentItem then
		local containerInfo = C_Container.GetContainerItemInfo(self.currentItem.bag, self.currentItem.slot)
		local itemGone = not containerInfo or containerInfo.itemID ~= self.currentItem.itemID

		if itemGone then
			self.disenchantedCount = self.disenchantedCount + 1
			self:Log('info', 'Disenchanted: ' .. self.currentItem.itemLink .. ' (' .. self.disenchantedCount .. '/' .. self.totalCount .. ')')
			LibsDisenchantAssist:SendMessage('DISENCHANT_ASSIST_ITEM_DESTROYED', self.currentItem, self.disenchantedCount, self.totalCount)
		else
			self:Log('warning', 'Item still present after loot - may have failed')
		end
	end

	self.state = STATE_IDLE
	self.currentItem = nil

	if #self.itemQueue > 0 then
		self:ScheduleTimer('PrepareNextDisenchant', 0.3)
	else
		LibsDisenchantAssist:SendMessage('DISENCHANT_ASSIST_QUEUE_COMPLETE', self.disenchantedCount, self.totalCount)
	end
end

function DisenchantEngine:OnCombatStart()
	if self.state ~= STATE_IDLE and self.state ~= STATE_PENDING_CLICK then
		return
	end

	if #self.itemQueue > 0 or self.currentItem then
		self:Log('info', 'Entered combat - pausing disenchant queue')
		self.state = STATE_IDLE
		if self.currentItem then
			table.insert(self.itemQueue, 1, self.currentItem)
			self.currentItem = nil
		end
		self:CancelTimeout()
		LibsDisenchantAssist:SendMessage('DISENCHANT_ASSIST_PAUSED', 'combat')
	end
end

function DisenchantEngine:OnCombatEnd()
	if #self.itemQueue > 0 then
		self:Log('info', 'Left combat - resuming disenchant queue')
		self:ScheduleTimer('PrepareNextDisenchant', 0.5)
	end
end

---@return string
function DisenchantEngine:GetState()
	return self.state
end

---@return table|nil
function DisenchantEngine:GetCurrentItem()
	return self.currentItem
end

---@return number, number
function DisenchantEngine:GetProgress()
	return self.disenchantedCount, self.totalCount
end

---@return boolean
function DisenchantEngine:IsActive()
	return self.state ~= STATE_IDLE or #self.itemQueue > 0
end

---@param level string
---@param msg string
function DisenchantEngine:Log(level, msg)
	if LibsDisenchantAssist.logger then
		LibsDisenchantAssist.logger[level](msg)
	end
end
