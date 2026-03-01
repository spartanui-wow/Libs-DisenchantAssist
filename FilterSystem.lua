---@class LibsDisenchantAssist
local LibsDisenchantAssist = LibStub('AceAddon-3.0'):GetAddon('LibsDisenchantAssist')

---@class LibsDisenchantAssist.FilterSystem : AceModule
local FilterSystem = LibsDisenchantAssist:NewModule('FilterSystem')
LibsDisenchantAssist.FilterSystem = FilterSystem

local slotMap = {
	['INVTYPE_HEAD'] = { 1 },
	['INVTYPE_NECK'] = { 2 },
	['INVTYPE_SHOULDER'] = { 3 },
	['INVTYPE_BODY'] = { 4 },
	['INVTYPE_CHEST'] = { 5 },
	['INVTYPE_WAIST'] = { 6 },
	['INVTYPE_LEGS'] = { 7 },
	['INVTYPE_FEET'] = { 8 },
	['INVTYPE_WRIST'] = { 9 },
	['INVTYPE_HAND'] = { 10 },
	['INVTYPE_FINGER'] = { 11, 12 },
	['INVTYPE_TRINKET'] = { 13, 14 },
	['INVTYPE_WEAPON'] = { 16, 17 },
	['INVTYPE_SHIELD'] = { 17 },
	['INVTYPE_RANGED'] = { 18 },
	['INVTYPE_CLOAK'] = { 15 },
	['INVTYPE_2HWEAPON'] = { 16, 17 },
	['INVTYPE_WEAPONMAINHAND'] = { 16 },
	['INVTYPE_WEAPONOFFHAND'] = { 17 },
	['INVTYPE_HOLDABLE'] = { 17 },
	['INVTYPE_THROWN'] = { 18 },
	['INVTYPE_RANGEDRIGHT'] = { 18 },
}

---@return table[]
function FilterSystem:GetFilteredItems()
	local allItems = LibsDisenchantAssist.ItemScanner:GetDisenchantableItems()
	return self:FilterItems(allItems)
end

---@param items table[]
---@return table[]
function FilterSystem:FilterItems(items)
	local filtered = {}
	local options = LibsDisenchantAssist.DB

	for _, item in ipairs(items) do
		if self:PassesAllFilters(item, options) then
			table.insert(filtered, item)
		end
	end

	table.sort(filtered, function(a, b)
		if a.itemLevel ~= b.itemLevel then
			return a.itemLevel < b.itemLevel
		end
		return a.itemName < b.itemName
	end)

	return filtered
end

---@param item table
---@param options LibsDisenchantAssistOptions
---@return boolean
function FilterSystem:PassesAllFilters(item, options)
	if not options.enabled then
		return false
	end

	if LibsDisenchantAssist:IsItemIgnored(item.itemID) then
		return false
	end

	if not self:PassesDisenchantFilters(item, options) then
		return false
	end

	if options.excludeToday and item.seenToday then
		return false
	end

	return true
end

---@param item table
---@param options LibsDisenchantAssistOptions
---@return boolean
function FilterSystem:PassesDisenchantFilters(item, options)
	if item.quality > options.deMaxQuality then
		return false
	end

	if item.itemLevel < options.minIlvl or item.itemLevel > options.maxIlvl then
		return false
	end

	if options.excludeHigherIlvl and self:IsHigherThanEquipped(item) then
		return false
	end

	if options.excludeGearSets and self:IsInGearSet(item) then
		return false
	end

	if options.excludeWarbound and self:IsWarbound(item) then
		return false
	end

	if options.excludeBOE and self:IsBOE(item) then
		return false
	end

	if options.excludePawnUpgrades and self:IsPawnUpgrade(item) then
		return false
	end

	return true
end

---@param item table
---@return boolean
function FilterSystem:IsHigherThanEquipped(item)
	if not item.equipLoc or item.equipLoc == '' then
		return false
	end

	local slots = slotMap[item.equipLoc]
	if not slots then
		return false
	end

	for _, slotID in ipairs(slots) do
		local equippedLink = GetInventoryItemLink('player', slotID)
		if equippedLink then
			local equippedIlvl = C_Item.GetDetailedItemLevelInfo(equippedLink)
			if equippedIlvl and item.itemLevel > equippedIlvl then
				return true
			end
		end
	end

	return false
end

---@param item table
---@return boolean
function FilterSystem:IsInGearSet(item)
	local setIDs = C_EquipmentSet.GetEquipmentSetIDs()
	for _, setID in ipairs(setIDs) do
		local itemIDs = C_EquipmentSet.GetItemIDs(setID)
		if itemIDs then
			for _, id in pairs(itemIDs) do
				if id == item.itemID then
					return true
				end
			end
		end
	end
	return false
end

---@param item table
---@return boolean
function FilterSystem:IsWarbound(item)
	local tooltipData = C_TooltipInfo.GetBagItem(item.bag, item.slot)
	if not tooltipData then
		return false
	end

	for _, line in ipairs(tooltipData.lines) do
		if line.leftText then
			if string.find(line.leftText, 'Warbound') then
				return true
			end
		end
	end
	return false
end

---@param item table
---@return boolean
function FilterSystem:IsBOE(item)
	local tooltipData = C_TooltipInfo.GetBagItem(item.bag, item.slot)
	if not tooltipData then
		return false
	end

	for _, line in ipairs(tooltipData.lines) do
		if line.leftText and string.find(line.leftText, 'Binds when equipped') then
			return true
		end
	end
	return false
end

---@param item table
---@return boolean
function FilterSystem:IsPawnUpgrade(item)
	if not PawnIsReady or not PawnIsReady() then
		return false
	end
	if not PawnGetItemData or not PawnIsItemAnUpgrade then
		return false
	end

	local pawnItem = PawnGetItemData(item.itemLink)
	if not pawnItem then
		return false
	end

	local upgradeTable = PawnIsItemAnUpgrade(pawnItem)
	if upgradeTable and #upgradeTable > 0 then
		return true
	end

	return false
end

---@return number
function FilterSystem:GetItemCount()
	local items = self:GetFilteredItems()
	return #items
end
