---@class LibsDisenchantAssist : AceAddon, AceEvent-3.0, AceTimer-3.0, AceConsole-3.0
local LibsDisenchantAssist = LibStub('AceAddon-3.0'):NewAddon('LibsDisenchantAssist', 'AceEvent-3.0', 'AceTimer-3.0', 'AceConsole-3.0')
_G.LibsDisenchantAssist = LibsDisenchantAssist

LibsDisenchantAssist:SetDefaultModuleLibraries('AceEvent-3.0', 'AceTimer-3.0')

-- All modules start disabled until we confirm enchanting is known
LibsDisenchantAssist:SetDefaultModuleState(false)

-- Spell ID for disenchant
LibsDisenchantAssist.DISENCHANT_SPELL_ID = 13262

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
}

function LibsDisenchantAssist:OnInitialize()
	self.db = LibStub('AceDB-3.0'):New('LibsDisenchantAssistDB', defaults, true)

	self.db.RegisterCallback(self, 'OnProfileChanged', 'OnProfileChanged')
	self.db.RegisterCallback(self, 'OnProfileCopied', 'OnProfileChanged')
	self.db.RegisterCallback(self, 'OnProfileReset', 'OnProfileChanged')

	self.DB = self.db.profile ---@type LibsDisenchantAssistOptions
	self.DBC = self.db.char ---@type LibsDisenchantAssistCharDB

	-- Session-only ignore list (cleared on /rl)
	self.sessionIgnore = {}

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
	return C_SpellBook.IsSpellInSpellBook(self.DISENCHANT_SPELL_ID)
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
