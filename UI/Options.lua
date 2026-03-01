---@class LibsDisenchantAssist
local LibsDisenchantAssist = LibStub('AceAddon-3.0'):GetAddon('LibsDisenchantAssist')

---@class LibsDisenchantAssist.Options : AceModule, AceEvent-3.0
local Options = LibsDisenchantAssist:NewModule('Options')
LibsDisenchantAssist.Options = Options

local function BuildOptionsTable()
	return {
		name = "Lib's - Disenchant Assist",
		type = 'group',
		args = {
			general = {
				name = 'General',
				type = 'group',
				inline = true,
				order = 1,
				args = {
					enabled = {
						name = 'Enable Disenchant Assist',
						desc = 'Enable or disable the addon',
						type = 'toggle',
						order = 1,
						width = 'full',
						get = function()
							return LibsDisenchantAssist.DB.enabled
						end,
						set = function(_, val)
							LibsDisenchantAssist.DB.enabled = val
						end,
					},
					minimap = {
						name = 'Show Minimap Icon',
						desc = 'Show or hide the minimap button',
						type = 'toggle',
						order = 2,
						width = 'full',
						get = function()
							return not LibsDisenchantAssist.DBC.minimap.hide
						end,
						set = function(_, val)
							LibsDisenchantAssist.DBC.minimap.hide = not val
							local LibDBIcon = LibStub:GetLibrary('LibDBIcon-1.0', true)
							if LibDBIcon then
								if val then
									LibDBIcon:Show('LibsDisenchantAssist')
								else
									LibDBIcon:Hide('LibsDisenchantAssist')
								end
							end
						end,
					},
				},
			},
			filters = {
				name = 'Filters',
				type = 'group',
				inline = true,
				order = 2,
				args = {
					excludeToday = {
						name = "Exclude Today's Items",
						desc = 'Skip items gained today',
						type = 'toggle',
						order = 1,
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
						order = 2,
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
						order = 3,
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
						order = 4,
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
						order = 5,
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
						order = 6,
						get = function()
							return LibsDisenchantAssist.DB.excludePawnUpgrades
						end,
						set = function(_, val)
							LibsDisenchantAssist.DB.excludePawnUpgrades = val
						end,
					},
				},
			},
			itemLevel = {
				name = 'Item Level Range',
				type = 'group',
				inline = true,
				order = 3,
				args = {
					minIlvl = {
						name = 'Minimum Item Level',
						desc = 'Only disenchant items at or above this item level',
						type = 'range',
						min = 1,
						max = 1000,
						step = 1,
						order = 1,
						get = function()
							return LibsDisenchantAssist.DB.minIlvl
						end,
						set = function(_, val)
							LibsDisenchantAssist.DB.minIlvl = val
						end,
					},
					maxIlvl = {
						name = 'Maximum Item Level',
						desc = 'Only disenchant items at or below this item level (999 = no limit)',
						type = 'range',
						min = 1,
						max = 1000,
						step = 1,
						order = 2,
						get = function()
							return LibsDisenchantAssist.DB.maxIlvl
						end,
						set = function(_, val)
							LibsDisenchantAssist.DB.maxIlvl = val
						end,
					},
					deMaxQuality = {
						name = 'Max Disenchant Quality',
						desc = 'Maximum item quality to disenchant',
						type = 'select',
						order = 3,
						values = {
							[2] = 'Uncommon',
							[3] = 'Rare',
							[4] = 'Epic',
						},
						get = function()
							return LibsDisenchantAssist.DB.deMaxQuality
						end,
						set = function(_, val)
							LibsDisenchantAssist.DB.deMaxQuality = val
						end,
					},
				},
			},
			actions = {
				name = '',
				type = 'group',
				inline = true,
				order = 4,
				args = {
					showUI = {
						name = 'Open Window',
						desc = 'Open the Disenchant Assist window',
						type = 'execute',
						order = 1,
						func = function()
							if LibsDisenchantAssist.MainWindow then
								LibsDisenchantAssist.MainWindow:Show()
							end
						end,
					},
				},
			},
		},
	}
end

function Options:OnEnable()
	self:RegisterBlizzardOptions()
	self:RegisterSpartanUI()
end

function Options:RegisterBlizzardOptions()
	LibStub('AceConfig-3.0'):RegisterOptionsTable('LibsDisenchantAssist', BuildOptionsTable())
	LibStub('AceConfigDialog-3.0'):AddToBlizOptions('LibsDisenchantAssist', "Lib's - Disenchant Assist")
end

function Options:RegisterSpartanUI()
	if not SUI or not SUI.opt or not SUI.opt.args or not SUI.opt.args.Modules then
		return
	end

	local optionsTable = BuildOptionsTable()

	if SUI.Handlers and SUI.Handlers.Options and SUI.Handlers.Options.AddOptions then
		SUI.Handlers.Options:AddOptions(optionsTable, 'LibsDisenchantAssist')
	else
		SUI.opt.args.Modules.args['LibsDisenchantAssist'] = optionsTable
	end
end
