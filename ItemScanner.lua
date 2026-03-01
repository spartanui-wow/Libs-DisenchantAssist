---@class LibsDisenchantAssist
local LibsDisenchantAssist = LibStub('AceAddon-3.0'):GetAddon('LibsDisenchantAssist')

---@class LibsDisenchantAssist.ItemScanner : AceModule, AceEvent-3.0, AceTimer-3.0
local ItemScanner = LibsDisenchantAssist:NewModule('ItemScanner')
LibsDisenchantAssist.ItemScanner = ItemScanner

-- Item class IDs
local WEAPON_CLASS = 2
local ARMOR_CLASS = 4

-- Quality thresholds
local QUALITY_UNCOMMON = 2
local QUALITY_EPIC = 4

function ItemScanner:OnEnable()
	self:RegisterEvent('BAG_UPDATE_DELAYED', 'OnBagUpdate')
	self:RegisterEvent('LOOT_READY', 'TrackLootedItems')
end

function ItemScanner:OnDisable()
	self:UnregisterAllEvents()
end

function ItemScanner:OnBagUpdate()
	self:ScanBagsForNewItems()
	LibsDisenchantAssist:SendMessage('DISENCHANT_ASSIST_ITEMS_UPDATED')
end

function ItemScanner:ScanBagsForNewItems()
	local currentTime = time()
	local firstSeen = LibsDisenchantAssist.DBC.itemFirstSeen

	for bag = 0, 4 do
		local numSlots = C_Container.GetContainerNumSlots(bag)
		if numSlots then
			for slot = 1, numSlots do
				local itemID = C_Container.GetContainerItemID(bag, slot)
				if itemID and not firstSeen[itemID] then
					firstSeen[itemID] = currentTime
				end
			end
		end
	end
end

function ItemScanner:TrackLootedItems()
	local currentTime = time()
	local numLootItems = GetNumLootItems()

	for i = 1, numLootItems do
		local itemLink = GetLootSlotLink(i)
		if itemLink then
			local itemID = tonumber(string.match(itemLink, 'item:(%d+)'))
			if itemID and not LibsDisenchantAssist.DBC.itemFirstSeen[itemID] then
				LibsDisenchantAssist.DBC.itemFirstSeen[itemID] = currentTime
			end
		end
	end
end

---@return table[]
function ItemScanner:GetDisenchantableItems()
	local items = {}

	for bag = 0, 4 do
		local numSlots = C_Container.GetContainerNumSlots(bag)
		if numSlots then
			for slot = 1, numSlots do
				local containerInfo = C_Container.GetContainerItemInfo(bag, slot)
				if containerInfo and containerInfo.itemID then
					local item = self:CreateItemInfo(bag, slot, containerInfo)
					if item then
						table.insert(items, item)
					end
				end
			end
		end
	end

	return items
end

---@param bag number
---@param slot number
---@param containerInfo table
---@return table|nil
function ItemScanner:CreateItemInfo(bag, slot, containerInfo)
	local itemID = containerInfo.itemID
	local itemLink = C_Container.GetContainerItemLink(bag, slot)
	if not itemLink then
		return nil
	end

	local itemName, _, itemQuality, _, _, _, _, _, equipLoc, _, _, classID, subClassID = C_Item.GetItemInfo(itemID)
	if not itemName then
		return nil
	end

	-- Use GetDetailedItemLevelInfo on the itemLink for the actual effective ilvl
	-- C_Item.GetItemInfo returns the base/template ilvl which is often 100+ lower than real
	local actualItemLevel = C_Item.GetDetailedItemLevelInfo(itemLink)
	local itemLevel = actualItemLevel or 0

	if not self:IsDisenchantable(itemID, classID, itemQuality, itemLevel) then
		return nil
	end

	local firstSeenTimestamp = LibsDisenchantAssist.DBC.itemFirstSeen[itemID]
	local firstSeen = firstSeenTimestamp and date('%m/%d/%y', firstSeenTimestamp) or 'Unknown'
	local seenToday = self:WasItemSeenToday(itemID)

	return {
		bag = bag,
		slot = slot,
		itemID = itemID,
		itemLink = itemLink,
		itemName = itemName,
		itemLevel = itemLevel or 0,
		quality = itemQuality or 0,
		equipLoc = equipLoc,
		classID = classID,
		subClassID = subClassID,
		quantity = containerInfo.stackCount or 1,
		isBound = containerInfo.isBound,
		firstSeen = firstSeen,
		seenToday = seenToday,
	}
end

---@param itemID number
---@param classID number
---@param quality number
---@param itemLevel number
---@return boolean
function ItemScanner:IsDisenchantable(itemID, classID, quality, itemLevel)
	if not LibsDisenchantAssist:KnowsDisenchant() then
		return false
	end

	if classID ~= WEAPON_CLASS and classID ~= ARMOR_CLASS then
		return false
	end

	if not quality or quality < QUALITY_UNCOMMON or quality > QUALITY_EPIC then
		return false
	end

	if not itemLevel or itemLevel < 1 then
		return false
	end

	return true
end

---@param itemID number
---@return boolean
function ItemScanner:WasItemSeenToday(itemID)
	local timestamp = LibsDisenchantAssist.DBC.itemFirstSeen[itemID]
	if not timestamp then
		return true
	end

	local today = date('%j', time())
	local itemDay = date('%j', timestamp)
	return today == itemDay
end

---@param itemID number
---@return string
function ItemScanner:GetItemFirstSeenDate(itemID)
	local timestamp = LibsDisenchantAssist.DBC.itemFirstSeen[itemID]
	if timestamp then
		return date('%m/%d/%y', timestamp)
	end
	return 'Unknown'
end
