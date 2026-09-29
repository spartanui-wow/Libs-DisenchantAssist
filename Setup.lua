---@class LibsDisenchantAssist
local LibsDisenchantAssist = LibStub('AceAddon-3.0'):GetAddon('LibsDisenchantAssist')

---Tell the window and the data text that a filter changed
local function SettingsChanged()
	LibsDisenchantAssist:SendMessage('DISENCHANT_ASSIST_PROFILE_CHANGED')
end

---Register the first-run setup with Libs-AddonTools. Must run before the database is created, so
---a new install can be told apart from a player who used the addon before.
function LibsDisenchantAssist:RegisterSetup()
	if not LibAT or not LibAT.Setup then
		return
	end

	local reg = LibAT.Setup:Register('libs-disenchantassist', {
		name = "Lib's Disenchant Assist",
		icon = 'Interface\\AddOns\\Libs-DisenchantAssist\\Logo-Icon',
		summary = 'Enchanters: turn the gear you do not need into materials with one click.',
		priority = 85,
		isExistingUser = function()
			return type(LibsDisenchantAssistDB) == 'table' and next(LibsDisenchantAssistDB) ~= nil
		end,
		optionsCommand = '/de options',
	})
	if not reg then
		return
	end

	reg:AddStep({
		id = 'quality',
		kind = 'choice',
		name = 'Best gear to break',
		title = 'What is the best gear it may break down?',
		text = 'This only matters on characters who know Enchanting. You can change it later.',
		choices = {
			{ value = 2, title = 'Green only', caption = 'Only green (Uncommon) gear is broken down.' },
			{ value = 3, title = 'Up to blue', caption = 'Green and blue (Rare) gear is broken down.' },
			{ value = 4, title = 'Up to purple', caption = 'Green, blue and purple (Epic) gear is broken down.', recommended = true },
		},
		get = function()
			return LibsDisenchantAssist.db.profile.deMaxQuality
		end,
		set = function(value)
			LibsDisenchantAssist.db.profile.deMaxQuality = value
			SettingsChanged()
		end,
	})

	reg:AddStep({
		id = 'keep',
		kind = 'toggles',
		name = 'Keep safe',
		title = 'Which gear should it keep safe?',
		text = 'Kept gear stays in your bags and is never broken down.',
		items = {
			{
				key = 'excludeHigherIlvl',
				title = 'Better than what you wear',
				caption = 'Keeps gear with a higher item level than yours.',
				recommended = true,
			},
			{
				key = 'excludeGearSets',
				title = 'Gear in your equipment sets',
				caption = 'Keeps anything saved in an equipment set.',
				recommended = true,
			},
			{
				key = 'excludeBOE',
				title = 'Gear you could sell',
				caption = 'Keeps Bind on Equip gear, so you can sell it or give it away.',
				recommended = false,
			},
		},
		get = function(key)
			return LibsDisenchantAssist.db.profile[key] and true or false
		end,
		set = function(key, value)
			LibsDisenchantAssist.db.profile[key] = value
			SettingsChanged()
		end,
	})
end
