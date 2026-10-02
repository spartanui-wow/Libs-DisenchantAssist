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

	-- One question for enchanters: how much it may break down. Each answer also says what stays safe.
	-- Characters without Enchanting are not asked; the addon waits for one that has it.
	local LEVELS = {
		[2] = { excludeHigherIlvl = true, excludeGearSets = true, excludeBOE = true },
		[3] = { excludeHigherIlvl = true, excludeGearSets = true, excludeBOE = false },
		[4] = { excludeHigherIlvl = true, excludeGearSets = true, excludeBOE = false },
	}
	reg:AddStep({
		id = 'quality',
		kind = 'choice',
		name = 'What it breaks down',
		title = 'What gear may it break down?',
		text = 'Gear better than what you wear and gear in your equipment sets is always kept. Fine-tune with /de options.',
		hidden = function()
			return not LibsDisenchantAssist:KnowsDisenchant()
		end,
		choices = {
			{ value = 2, title = 'Green only', caption = 'Also keeps Bind on Equip gear you could sell.' },
			{ value = 3, title = 'Green and blue', caption = 'Uncommon and Rare gear.' },
			{ value = 4, title = 'Green, blue and purple', caption = 'Uncommon, Rare and Epic gear.', recommended = true },
		},
		get = function()
			return LibsDisenchantAssist.db.profile.deMaxQuality
		end,
		set = function(value)
			local profile = LibsDisenchantAssist.db.profile
			profile.deMaxQuality = value
			for key, keep in pairs(LEVELS[value] or {}) do
				profile[key] = keep
			end
			SettingsChanged()
		end,
	})
end
