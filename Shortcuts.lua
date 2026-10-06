---@class LibsDisenchantAssist
local LibsDisenchantAssist = LibStub('AceAddon-3.0'):GetAddon('LibsDisenchantAssist')

-- Ways to press the "disenchant next" button without opening the window: a key binding (also
-- listed in the game's Key Bindings under AddOns, from Bindings.xml) and a macro that can sit on
-- an action bar. Both press the same secure button, so the game still sees one press per item.

local NEXT_BUTTON = LibsDisenchantAssist.NEXT_BUTTON_NAME
local BINDING_COMMAND = 'CLICK ' .. NEXT_BUTTON .. ':LeftButton'
local MACRO_NAME = 'DE Next'
local MACRO_ICON = 'INV_Enchant_Disenchant'
local MACRO_BODY = '/click ' .. NEXT_BUTTON

LibsDisenchantAssist.BINDING_COMMAND = BINDING_COMMAND
LibsDisenchantAssist.MACRO_BODY = MACRO_BODY

BINDING_HEADER_LIBSDISENCHANTASSIST = "Lib's - Disenchant Assist"
_G['BINDING_NAME_' .. BINDING_COMMAND] = 'Disenchant next item'

---@return string|nil key The key bound to "disenchant next", as the game names it (SHIFT-F)
function LibsDisenchantAssist:GetNextKey()
	return GetBindingKey(BINDING_COMMAND)
end

---@param key string|nil
---@param short? boolean The short form used on buttons (S-F instead of Shift-F)
---@return string|nil text The key as players read it (Shift-F, Mouse Wheel Up)
function LibsDisenchantAssist:GetKeyText(key, short)
	if not key or key == '' then
		return nil
	end
	return GetBindingText(key, 'KEY_', short) or key
end

---@param key string
---@return string|nil name What the key does now, when that is something other than ours
function LibsDisenchantAssist:GetKeyConflict(key)
	local action = GetBindingAction(key)
	if not action or action == '' or action == BINDING_COMMAND then
		return nil
	end
	return _G['BINDING_NAME_' .. action] or action
end

---Bind a key to "disenchant next", replacing any key it had. Saved to the player's bindings.
---@param key string
---@return boolean ok
function LibsDisenchantAssist:SetNextKey(key)
	if InCombatLockdown() then
		LibsDisenchantAssist:Say('Key bindings cannot be changed in combat')
		return false
	end
	for _, oldKey in ipairs({ GetBindingKey(BINDING_COMMAND) }) do
		SetBinding(oldKey)
	end
	local ok = SetBinding(key, BINDING_COMMAND)
	SaveBindings(GetCurrentBindingSet())
	if ok then
		LibsDisenchantAssist:Say((self:GetKeyText(key) or key) .. ' now disenchants the next item')
	end
	self:SendMessage('DISENCHANT_ASSIST_KEY_CHANGED')
	return ok and true or false
end

---@return boolean ok
function LibsDisenchantAssist:ClearNextKey()
	if InCombatLockdown() then
		LibsDisenchantAssist:Say('Key bindings cannot be changed in combat')
		return false
	end
	for _, oldKey in ipairs({ GetBindingKey(BINDING_COMMAND) }) do
		SetBinding(oldKey)
	end
	SaveBindings(GetCurrentBindingSet())
	self:SendMessage('DISENCHANT_ASSIST_KEY_CHANGED')
	return true
end

---Find our macro, creating it when missing. Macros are character macros where there is room
---(only enchanters need it), account-wide otherwise.
---@return number|nil index
function LibsDisenchantAssist:EnsureNextMacro()
	if InCombatLockdown() then
		LibsDisenchantAssist:Say('Macros cannot be made in combat')
		return nil
	end

	local index = GetMacroIndexByName(MACRO_NAME)
	if index and index > 0 then
		local body = GetMacroBody(index) or ''
		if body:find(NEXT_BUTTON, 1, true) then
			return index
		end
		LibsDisenchantAssist:Say('You already have a macro named "' .. MACRO_NAME .. '". Rename it, or put this line in a macro yourself: ' .. MACRO_BODY)
		return nil
	end

	-- CreateMacro errors when that kind of macro is full; the limits differ between game versions
	local function Create(perCharacter)
		local ok, created = pcall(CreateMacro, MACRO_NAME, MACRO_ICON, MACRO_BODY, perCharacter)
		if ok and created and created > 0 then
			return created
		end
		return nil
	end

	local _, numCharacter = GetNumMacros()
	local created = numCharacter < (MAX_CHARACTER_MACROS or 18) and Create(true) or nil
	if not created then
		created = Create(nil)
	end
	if not created then
		LibsDisenchantAssist:Say('Your macro slots are full. Make a macro yourself with this line: ' .. MACRO_BODY)
		return nil
	end
	LibsDisenchantAssist:Say('Made a macro named "' .. MACRO_NAME .. '". It is also in your macro list.')
	return created
end

---Put the "disenchant next" macro on the cursor, ready to drop on an action bar.
---@return boolean ok
function LibsDisenchantAssist:PickupNextMacro()
	local index = self:EnsureNextMacro()
	if not index then
		return false
	end
	PickupMacro(index)
	return true
end
