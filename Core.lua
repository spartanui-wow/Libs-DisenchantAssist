---@class LibsDisenchantAssist : AceAddon, AceEvent-3.0, AceTimer-3.0, AceConsole-3.0
local LibsDisenchantAssist = LibStub('AceAddon-3.0'):NewAddon('LibsDisenchantAssist', 'AceEvent-3.0', 'AceTimer-3.0', 'AceConsole-3.0')
_G.LibsDisenchantAssist = LibsDisenchantAssist

LibsDisenchantAssist:SetDefaultModuleLibraries('AceEvent-3.0', 'AceTimer-3.0')

-- All modules start disabled until we confirm enchanting is known
LibsDisenchantAssist:SetDefaultModuleState(false)

-- Spell ID for disenchant
LibsDisenchantAssist.DISENCHANT_SPELL_ID = 13262

-- Flavor is decided by interface number, not WOW_PROJECT_ID: WoW Forever runs the modern client
-- and reports a project id older code mistakes for Retail, but it plays by Classic rules, where
-- Disenchant is an ordinary spell cast on a bag item rather than a salvage recipe.
local _, _, _, tocVersion = GetBuildInfo()
LibsDisenchantAssist.IsRetail = (tocVersion or 0) >= 110000

-- Raw frame for profession detection events (lives outside Ace3 lifecycle)
local professionFrame = CreateFrame('Frame')
local trainerThrottleTimer = nil

professionFrame:RegisterEvent('TRAINER_UPDATE')
professionFrame:SetScript('OnEvent', function()
	if trainerThrottleTimer then
		trainerThrottleTimer:Cancel()
	end
	trainerThrottleTimer = C_Timer.NewTimer(2, function()
		trainerThrottleTimer = nil
		LibsDisenchantAssist:CheckEnchantingProfession()
	end)
end)

---@class LibsDisenchantAssistOptions
---@field enabled boolean
---@field deMaxQuality number
---@field minIlvl number
---@field maxIlvl number
---@field excludeHigherIlvl boolean
---@field excludeGearSets boolean
---@field excludeWarbound boolean
---@field excludeBOE boolean
---@field excludePawnUpgrades boolean
---@field includeSoulbound boolean
---@field excludeToday boolean
---@field autoShow boolean

---@class LibsDisenchantAssistCharDB
---@field itemFirstSeen table<number, number>
---@field permanentIgnore table<number, boolean>
---@field minimap table

local defaults = {
	profile = {
		enabled = true,
		deMaxQuality = 4,
		minIlvl = 1,
		maxIlvl = 999,
		excludeHigherIlvl = true,
		excludeGearSets = true,
		excludeWarbound = false,
		excludeBOE = false,
		excludePawnUpgrades = true,
		includeSoulbound = true,
		excludeToday = false,
		autoShow = false,
	},
	char = {
		itemFirstSeen = {},
		permanentIgnore = {},
		minimap = { hide = true },
	},
	global = {
		nonDisenchantable = {},
	},
}

function LibsDisenchantAssist:OnInitialize()
	-- Before the database exists, so Setup can spot a new install
	self:RegisterSetup()

	self.db = LibStub('AceDB-3.0'):New('LibsDisenchantAssistDB', defaults, true)

	self.db.RegisterCallback(self, 'OnProfileChanged', 'OnProfileChanged')
	self.db.RegisterCallback(self, 'OnProfileCopied', 'OnProfileChanged')
	self.db.RegisterCallback(self, 'OnProfileReset', 'OnProfileChanged')

	self.DB = self.db.profile ---@type LibsDisenchantAssistOptions
	self.DBC = self.db.char ---@type LibsDisenchantAssistCharDB
	self.DBG = self.db.global

	-- Session-only ignore list (cleared on /rl)
	self.sessionIgnore = {}

	-- Track items we already prompted about this session (don't re-ask)
	self.promptedNonDE = {}

	-- Tracks whether modules are currently active
	self.modulesActive = false

	if LibAT and LibAT.Logger then
		self.logger = LibAT.Logger.RegisterAddon("Lib's Disenchant Assist")
	end

	self:RegisterChatCommands()
end

function LibsDisenchantAssist:OnEnable()
	-- Check immediately - no delay for players who already have enchanting
	self:CheckEnchantingProfession()
end

function LibsDisenchantAssist:CheckEnchantingProfession()
	local hasDisenchant = self:KnowsDisenchant()

	if hasDisenchant and not self.modulesActive then
		self:EnableAllModules()
		self.modulesActive = true
		if self.ItemScanner then
			self.ItemScanner:ScanBagsForNewItems()
		end
		if self.logger then
			self.logger.info('Enchanting detected - modules enabled')
		end
	elseif not hasDisenchant and self.modulesActive then
		if self.logger then
			self.logger.info('Enchanting not found - modules disabled')
		end
		self:DisableAllModules()
		self.modulesActive = false
	elseif not hasDisenchant and not self.modulesActive then
		if self.logger then
			self.logger.info('Enchanting not found - addon idle')
		end
	end
end

function LibsDisenchantAssist:EnableAllModules()
	for name, module in self:IterateModules() do
		module:Enable()
	end
end

function LibsDisenchantAssist:DisableAllModules()
	for name, module in self:IterateModules() do
		module:Disable()
	end
end

function LibsDisenchantAssist:OnProfileChanged()
	self.DB = self.db.profile
	self.DBC = self.db.char

	self:SendMessage('DISENCHANT_ASSIST_PROFILE_CHANGED')
end

function LibsDisenchantAssist:RegisterChatCommands()
	SLASH_LIBSDISENCHANTASSIST1 = '/disenchant'
	SLASH_LIBSDISENCHANTASSIST2 = '/de'

	SlashCmdList['LIBSDISENCHANTASSIST'] = function(msg)
		self:HandleChatCommand(msg)
	end
end

---@param msg string
function LibsDisenchantAssist:HandleChatCommand(msg)
	local command = string.lower(string.trim(msg or ''))

	if not self.modulesActive then
		if self.logger then
			self.logger.info('Disenchant Assist is inactive - this character does not know Enchanting')
		end
		return
	end

	if command == '' or command == 'show' then
		if self.MainWindow then
			self.MainWindow:Show()
		end
	elseif command == 'hide' then
		if self.MainWindow then
			self.MainWindow:Hide()
		end
	elseif command == 'toggle' then
		if self.MainWindow then
			self.MainWindow:Toggle()
		end
	elseif command == 'scan' then
		if self.ItemScanner then
			self.ItemScanner:ScanBagsForNewItems()
			self:SendMessage('DISENCHANT_ASSIST_ITEMS_UPDATED')
			if self.logger then
				self.logger.info('Manual bag scan complete')
			end
		end
	elseif command == 'stop' then
		if self.DisenchantEngine then
			self.DisenchantEngine:Stop()
		end
	elseif command == 'options' or command == 'settings' then
		if self.MainWindow then
			self.MainWindow:Show()
			self.MainWindow:ShowSettings()
		end
	elseif command == 'help' then
		if self.logger then
			self.logger.info('Commands:')
			self.logger.info('/disenchant - Open main window')
			self.logger.info('/disenchant hide - Hide main window')
			self.logger.info('/disenchant toggle - Toggle main window')
			self.logger.info('/disenchant scan - Rescan bags')
			self.logger.info('/disenchant stop - Stop current disenchant queue')
			self.logger.info('/disenchant settings - Open settings')
			self.logger.info('/disenchant help - Show this help')
		end
	else
		if self.logger then
			self.logger.warning('Unknown command: ' .. command .. ". Use '/disenchant help'")
		end
	end
end

---@return boolean
function LibsDisenchantAssist:KnowsDisenchant()
	if C_SpellBook and C_SpellBook.IsSpellInSpellBook and C_SpellBook.IsSpellInSpellBook(self.DISENCHANT_SPELL_ID) then
		return true
	end
	return IsPlayerSpell and IsPlayerSpell(self.DISENCHANT_SPELL_ID) or false
end

-- Retail disenchanting is a salvage recipe with no spellbook slot, so it goes through
-- C_TradeSkillUI.CraftSalvage in a macro. Everywhere else Disenchant is cast as a spell and the
-- secure template aims it at the bag slot, which needs no macro text (some clients refuse it).
---@param btn Button SecureActionButton
---@param bag number
---@param slot number
function LibsDisenchantAssist:SetDisenchantAttributes(btn, bag, slot)
	local spellID = self.DISENCHANT_SPELL_ID
	local inSpellBook = FindSpellBookSlotBySpellID and FindSpellBookSlotBySpellID(spellID)
	local canSalvage = self.IsRetail and C_TradeSkillUI and C_TradeSkillUI.CraftSalvage

	if canSalvage and not inSpellBook then
		btn:SetAttribute('type', 'macro')
		btn:SetAttribute('macrotext', string.format('/run C_TradeSkillUI.CraftSalvage(%d, 1, ItemLocation:CreateFromBagAndSlot(%d, %d))', spellID, bag, slot))
		btn:SetAttribute('spell', nil)
		btn:SetAttribute('target-bag', nil)
		btn:SetAttribute('target-slot', nil)
	else
		btn:SetAttribute('type', 'spell')
		btn:SetAttribute('spell', spellID)
		btn:SetAttribute('target-bag', bag)
		btn:SetAttribute('target-slot', slot)
		btn:SetAttribute('macrotext', nil)
	end
end

---@param btn Button SecureActionButton
function LibsDisenchantAssist:ClearDisenchantAttributes(btn)
	btn:SetAttribute('type', nil)
	btn:SetAttribute('macrotext', nil)
	btn:SetAttribute('spell', nil)
	btn:SetAttribute('target-bag', nil)
	btn:SetAttribute('target-slot', nil)
end

---@param itemID number
---@return boolean
function LibsDisenchantAssist:IsItemIgnored(itemID)
	if self.sessionIgnore[itemID] then
		return true
	end
	if self.DBC.permanentIgnore[itemID] then
		return true
	end
	if self.DBG.nonDisenchantable[itemID] then
		return true
	end
	return false
end

---@param itemID number
function LibsDisenchantAssist:SessionIgnoreItem(itemID)
	self.sessionIgnore[itemID] = true
	self:SendMessage('DISENCHANT_ASSIST_ITEMS_UPDATED')
end

---@param itemID number
function LibsDisenchantAssist:PermanentIgnoreItem(itemID)
	self.DBC.permanentIgnore[itemID] = true
	self:SendMessage('DISENCHANT_ASSIST_ITEMS_UPDATED')
end

---@param itemID number
---@return boolean
function LibsDisenchantAssist:IsNonDisenchantable(itemID)
	return self.DBG.nonDisenchantable[itemID] == true
end

---@param itemID number
---@param itemName string
function LibsDisenchantAssist:MarkNonDisenchantable(itemID, itemName)
	self.DBG.nonDisenchantable[itemID] = true
	if self.logger then
		self.logger.info('Marked as non-disenchantable: ' .. (itemName or tostring(itemID)))
	end
	self:SendMessage('DISENCHANT_ASSIST_ITEMS_UPDATED')
end
