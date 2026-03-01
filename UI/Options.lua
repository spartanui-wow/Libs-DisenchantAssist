---@class LibsDisenchantAssist
local LibsDisenchantAssist = LibStub('AceAddon-3.0'):GetAddon('LibsDisenchantAssist')

---@class LibsDisenchantAssist.Options : AceModule, AceEvent-3.0
local Options = LibsDisenchantAssist:NewModule('Options')
LibsDisenchantAssist.Options = Options

function Options:OnEnable()
	self:RegisterSpartanUI()
end

function Options:RegisterSpartanUI()
	if not SUI or not SUI.opt or not SUI.opt.args or not SUI.opt.args.Modules then
		return
	end

	local optionsTable = {
		name = "Lib's - Disenchant Assist",
		type = 'group',
		desc = 'Smart disenchanting with advanced filtering',
		args = {
			enabled = {
				name = 'Enable Disenchant Assist',
				desc = 'Enable or disable the addon',
				type = 'toggle',
				order = 10,
				get = function()
					return LibsDisenchantAssist.DB.enabled
				end,
				set = function(_, val)
					LibsDisenchantAssist.DB.enabled = val
				end,
			},
			filterHeader = {
				name = 'Filters',
				type = 'header',
				order = 50,
			},
			excludeToday = {
				name = "Exclude Today's Items",
				desc = 'Skip items gained today',
				type = 'toggle',
				order = 60,
				get = function()
					return LibsDisenchantAssist.DB.excludeToday
				end,
				set = function(_, val)
					LibsDisenchantAssist.DB.excludeToday = val
				end,
			},
			excludeHigherIlvl = {
				name = 'Exclude Higher Item Level',
				desc = 'Skip gear with higher item level than equipped',
				type = 'toggle',
				order = 70,
				get = function()
					return LibsDisenchantAssist.DB.excludeHigherIlvl
				end,
				set = function(_, val)
					LibsDisenchantAssist.DB.excludeHigherIlvl = val
				end,
			},
			excludeGearSets = {
				name = 'Exclude Equipment Sets',
				desc = 'Skip items in saved equipment sets',
				type = 'toggle',
				order = 80,
				get = function()
					return LibsDisenchantAssist.DB.excludeGearSets
				end,
				set = function(_, val)
					LibsDisenchantAssist.DB.excludeGearSets = val
				end,
			},
			excludeWarbound = {
				name = 'Exclude Warbound Items',
				desc = 'Skip warbound items',
				type = 'toggle',
				order = 90,
				get = function()
					return LibsDisenchantAssist.DB.excludeWarbound
				end,
				set = function(_, val)
					LibsDisenchantAssist.DB.excludeWarbound = val
				end,
			},
			excludeBOE = {
				name = 'Exclude Bind on Equip',
				desc = 'Skip bind on equip items',
				type = 'toggle',
				order = 100,
				get = function()
					return LibsDisenchantAssist.DB.excludeBOE
				end,
				set = function(_, val)
					LibsDisenchantAssist.DB.excludeBOE = val
				end,
			},
			excludePawnUpgrades = {
				name = 'Exclude Pawn Upgrades',
				desc = 'Skip items that Pawn considers an upgrade (requires Pawn addon)',
				type = 'toggle',
				order = 105,
				get = function()
					return LibsDisenchantAssist.DB.excludePawnUpgrades
				end,
				set = function(_, val)
					LibsDisenchantAssist.DB.excludePawnUpgrades = val
				end,
			},
			rangeHeader = {
				name = '',
				type = 'header',
				order = 110,
			},
			minIlvl = {
				name = 'Minimum Item Level',
				desc = 'Only disenchant items at or above this item level',
				type = 'range',
				min = 1,
				max = 1000,
				step = 1,
				order = 120,
				get = function()
					return LibsDisenchantAssist.DB.minIlvl
				end,
				set = function(_, val)
					LibsDisenchantAssist.DB.minIlvl = val
				end,
			},
			maxIlvl = {
				name = 'Maximum Item Level',
				desc = 'Only disenchant items at or below this item level',
				type = 'range',
				min = 1,
				max = 1000,
				step = 1,
				order = 130,
				get = function()
					return LibsDisenchantAssist.DB.maxIlvl
				end,
				set = function(_, val)
					LibsDisenchantAssist.DB.maxIlvl = val
				end,
			},
			deMaxQuality = {
				name = 'Max Disenchant Quality',
				desc = 'Maximum item quality to disenchant (2=Uncommon, 3=Rare, 4=Epic)',
				type = 'range',
				min = 2,
				max = 4,
				step = 1,
				order = 140,
				get = function()
					return LibsDisenchantAssist.DB.deMaxQuality
				end,
				set = function(_, val)
					LibsDisenchantAssist.DB.deMaxQuality = val
				end,
			},
			actionHeader = {
				name = '',
				type = 'header',
				order = 150,
			},
			showUI = {
				name = 'Open Window',
				desc = 'Open the Disenchant Assist window',
				type = 'execute',
				order = 160,
				func = function()
					if LibsDisenchantAssist.MainWindow then
						LibsDisenchantAssist.MainWindow:Show()
					end
				end,
			},
		},
	}

	if SUI.Handlers and SUI.Handlers.Options and SUI.Handlers.Options.AddOptions then
		SUI.Handlers.Options:AddOptions(optionsTable, 'LibsDisenchantAssist')
	else
		SUI.opt.args.Modules.args['LibsDisenchantAssist'] = optionsTable
	end
end
