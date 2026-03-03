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

-- Non-disenchantable items blocklist (from TSM + our own discoveries)
-- Source: https://www.wowhead.com/items=2?filter=qu=2:3:4;cr=8:2;crs=2:2;crv=0:0
-- Source: https://www.wowhead.com/items=4?filter=qu=2:3:4;cr=8:2;crs=2:2;crv=0:0
---@type table<number, boolean>
local nonDisenchantable = {
	-- Classic era
	[38] = true,
	[45] = true,
	[49] = true,
	[53] = true,
	[127] = true,
	[148] = true,
	[154] = true,
	[2105] = true,
	[2575] = true,
	[2576] = true,
	[2577] = true,
	[2579] = true,
	[2587] = true,
	[3426] = true,
	[3427] = true,
	[3428] = true,
	[4330] = true,
	[4332] = true,
	[4333] = true,
	[4334] = true,
	[4335] = true,
	[4336] = true,
	[4344] = true,
	[5107] = true,
	[6096] = true,
	[6097] = true,
	[6117] = true,
	[6120] = true,
	[6125] = true,
	[6134] = true,
	[6136] = true,
	[6384] = true,
	[6385] = true,
	[6795] = true,
	[6796] = true,
	[6833] = true,
	[10034] = true,
	[10052] = true,
	[10054] = true,
	[10055] = true,
	[10056] = true,
	[11287] = true,
	[11288] = true,
	[11289] = true,
	[11290] = true,
	[13347] = true,
	[16059] = true,
	[16060] = true,
	[17723] = true,
	[18231] = true,
	[20406] = true,
	[20407] = true,
	[20408] = true,
	[20897] = true,
	[20901] = true,
	[21766] = true,
	[23345] = true,
	[23473] = true,
	[23476] = true,
	[24143] = true,
	[31279] = true,
	-- Wrath era
	[41248] = true,
	[41249] = true,
	[41250] = true,
	[41251] = true,
	[41252] = true,
	[41253] = true,
	[41254] = true,
	[41255] = true,
	[42360] = true,
	[42361] = true,
	[42363] = true,
	[42365] = true,
	[42368] = true,
	[42369] = true,
	[42370] = true,
	[42371] = true,
	[42372] = true,
	[42373] = true,
	[42374] = true,
	[42375] = true,
	[42376] = true,
	[42377] = true,
	[42378] = true,
	[44693] = true,
	[44694] = true,
	[45664] = true,
	[45666] = true,
	[45667] = true,
	[45668] = true,
	[45669] = true,
	[45670] = true,
	[45671] = true,
	[45672] = true,
	[45673] = true,
	[45674] = true,
	[48663] = true,
	[49567] = true,
	-- Cata era
	[52252] = true,
	[52485] = true,
	[52486] = true,
	[52487] = true,
	[52488] = true,
	[52548] = true,
	[53852] = true,
	[60223] = true,
	-- MoP/WoD/Legion era
	[68611] = true,
	[75274] = true,
	[84661] = true,
	[89586] = true,
	[97826] = true,
	[97827] = true,
	[97828] = true,
	[97829] = true,
	[97830] = true,
	[97831] = true,
	[97832] = true,
	[109262] = true,
	[122604] = true,
	[127842] = true,
	[128023] = true,
	[128024] = true,
	[141408] = true,
	-- BFA era
	[151607] = true,
	[151771] = true,
	[151772] = true,
	[152632] = true,
	[152633] = true,
	[152635] = true,
	[152637] = true,
	[167081] = true,
	[167082] = true,
	[167177] = true,
	[167178] = true,
	[167179] = true,
	[167180] = true,
	[167181] = true,
	[167182] = true,
	[167183] = true,
	[167184] = true,
	[167185] = true,
	[167186] = true,
	[167187] = true,
	[167188] = true,
	[167189] = true,
	[167190] = true,
	[167191] = true,
	[167192] = true,
	[167193] = true,
	[167194] = true,
	[167195] = true,
	[167196] = true,
	[167197] = true,
	-- Shadowlands era
	[186056] = true,
	[186058] = true,
	[186163] = true,
	-- TWW/Midnight Pre-Launch gear (Ascension Arrestor's set)
	[231955] = true,
	[231956] = true,
	[231957] = true,
	[231958] = true,
	[231959] = true,
	[231960] = true,
	[231961] = true,
	[231962] = true,
	[231963] = true,
	[231964] = true,
	[231965] = true,
	[231966] = true,
	[231967] = true,
	[231968] = true,
	[231969] = true,
	[231970] = true,
	[234830] = true,
	[234831] = true,
	[234832] = true,
	[234833] = true,
	[234834] = true,
	[234835] = true,
	[234836] = true,
	[234837] = true,
	[234881] = true,
	[234882] = true,
	[234883] = true,
	[234884] = true,
	[234885] = true,
	[234886] = true,
	[234887] = true,
	[234888] = true,
	[234924] = true,
	[234925] = true,
	[234926] = true,
	[234927] = true,
	[234928] = true,
	[234929] = true,
	[234930] = true,
	[234931] = true,
}

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

	if not self:IsDisenchantable(itemID, classID, itemQuality, itemLevel, equipLoc) then
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
---@param equipLoc string
---@return boolean
function ItemScanner:IsDisenchantable(itemID, classID, quality, itemLevel, equipLoc)
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

	-- Tabards and shirts cannot be disenchanted
	if equipLoc == 'INVTYPE_TABARD' or equipLoc == 'INVTYPE_BODY' then
		return false
	end

	if nonDisenchantable[itemID] then
		return false
	end

	-- Check user-discovered non-disenchantable items (global DB)
	if LibsDisenchantAssist:IsNonDisenchantable(itemID) then
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
