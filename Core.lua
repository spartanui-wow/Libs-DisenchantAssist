---@class LibsDisenchantAssist : AceAddon, AceEvent-3.0, AceTimer-3.0, AceConsole-3.0
local LibsDisenchantAssist = LibStub('AceAddon-3.0'):NewAddon('LibsDisenchantAssist', 'AceEvent-3.0', 'AceTimer-3.0', 'AceConsole-3.0')
_G.LibsDisenchantAssist = LibsDisenchantAssist

LibsDisenchantAssist:SetDefaultModuleLibraries('AceEvent-3.0', 'AceTimer-3.0')

-- Spell ID for disenchant
LibsDisenchantAssist.DISENCHANT_SPELL_ID = 13262

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
		minimap = { hide = false },
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

	if LibAT and LibAT.Logger then
		self.logger = LibAT.Logger.RegisterAddon("Lib's Disenchant Assist")
	end

	self:RegisterChatCommands()
end

function LibsDisenchantAssist:OnEnable()
	self:RegisterEvent('PLAYER_LOGIN', function()
		C_Timer.After(2, function()
			if self.ItemScanner then
				self.ItemScanner:ScanBagsForNewItems()
			end
		end)
	end)

	if self.logger then
		self.logger.info('Enabled - Use /disenchant for commands')
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
