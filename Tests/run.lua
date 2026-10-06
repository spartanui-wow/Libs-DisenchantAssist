-- Headless tests for Lib's Disenchant Assist. Runs under the Lua language server binary:
--   lua-language-server.exe Tests/run.lua
-- Drives the real addon files and Ace3 core through a fake client (Tests/harness.lua) that
-- copies the game's secure button rules, so every way of pressing "disenchant next" can be checked.

local ADDON = ((arg and arg[0] and arg[0]:match('^(.*)[/\\]Tests[/\\]')) or '.') .. '/'

dofile(ADDON .. 'Tests/harness.lua')

local function load(path)
	local chunk, err = loadfile(path)
	if not chunk then
		error(err)
	end
	chunk('Libs-DisenchantAssist', {})
end

for _, lib in ipairs({
	'libs/Ace3/LibStub/LibStub.lua',
	'libs/Ace3/CallbackHandler-1.0/CallbackHandler-1.0.lua',
	'libs/Ace3/AceAddon-3.0/AceAddon-3.0.lua',
	'libs/Ace3/AceEvent-3.0/AceEvent-3.0.lua',
	'libs/Ace3/AceTimer-3.0/AceTimer-3.0.lua',
	'libs/Ace3/AceDB-3.0/AceDB-3.0.lua',
	'libs/Ace3/AceConsole-3.0/AceConsole-3.0.lua',
	'Core.lua',
	'Shortcuts.lua',
	'ItemScanner.lua',
	'FilterSystem.lua',
	'DisenchantEngine.lua',
	'Setup.lua',
	'DataBroker.lua',
	'UI/MainWindow.lua',
}) do
	load(ADDON .. lib)
end

MOCK.Fire('ADDON_LOADED', 'Libs-DisenchantAssist')
MOCK.Fire('PLAYER_LOGIN')

local DA = LibStub('AceAddon-3.0'):GetAddon('LibsDisenchantAssist')
local Engine = DA.DisenchantEngine
local Window = DA.MainWindow

local passed, failed = 0, 0
local function check(name, cond, detail)
	if cond then
		passed = passed + 1
		print('  ok   ' .. name)
	else
		failed = failed + 1
		print('  FAIL ' .. name .. (detail and ('  -- ' .. tostring(detail)) or ''))
	end
end

local function spells()
	local list = {}
	for _, a in ipairs(MOCK.actions) do
		if a.kind ~= 'none' then
			list[#list + 1] = a
		end
	end
	return list
end
local function reset()
	MOCK.actions = {}
	MOCK.errors = {}
	MOCK.chat = {}
	MOCK.popups = {}
end
local function lastChat()
	return MOCK.chat[#MOCK.chat] or ''
end

print('modules active: ' .. tostring(DA.modulesActive))
check('addon enabled for an enchanter', DA.modulesActive)

local nextBtn = _G.LibsDENext
local windowBtn = _G.LibsDADisenchantButton
check('LibsDENext exists and is secure', nextBtn and nextBtn._secure)
check('LibsDENext acts on release', nextBtn:GetAttribute('useOnKeyDown') == false)
check('binding name is defined', _G['BINDING_NAME_CLICK LibsDENext:LeftButton'] ~= nil)

MOCK.AddItem(0, 1, 101, 'Green Boots', 2, 100)
MOCK.AddItem(0, 2, 102, 'Blue Helm', 3, 110)
MOCK.AddItem(0, 3, 103, 'Green Gloves', 2, 120)
MOCK.AddItem(1, 4, 104, 'Purple Cloak', 4, 130)

Window:Show()
check('window shows the next item', (Window.statusText:GetText() or ''):find('Green Boots') ~= nil, Window.statusText:GetText())
check('big button counts items', (windowBtn.Text:GetText() or ''):find('4 left') ~= nil, windowBtn.Text:GetText())
check('next row is highlighted', Window.itemRows[1]._locked == true and not Window.itemRows[2]._locked)

print('-- mouse click on the big button')
reset()
MOCK.MouseClick(windowBtn)
local s = spells()
check('one disenchant from one click', #s == 1, #s)
check('first item targeted', s[1] and s[1].bag == 0 and s[1].slot == 1)
check('button disarmed after the click', windowBtn:GetAttribute('type') == nil)
check('engine knows the cast', Engine:GetCastingItem() and Engine:GetCastingItem().itemID == 101)

print('-- spamming during the cast does nothing')
reset()
for _ = 1, 5 do
	MOCK.MouseClick(windowBtn)
	MOCK.KeyPress(nextBtn)
	MOCK.SlashClick(nextBtn)
end
check('no new casts while casting', #spells() == 0, #spells())
check('no error spam while casting', #MOCK.errors == 0)

MOCK.FinishCast(2)
check('loot taken', #MOCK.loot == 0)
check('session count', Engine:GetSessionCount() == 1)
MOCK.Advance(0.2)

print('-- key binding (cast on key down ON)')
reset()
DA:SetNextKey('F')
check('F bound to disenchant next', MOCK.bindings.F == DA.BINDING_COMMAND)
check('key shown on the window', Window.keyButton:GetText() == 'Key: F', Window.keyButton:GetText())
MOCK.KeyBinding('F')
s = spells()
check('one disenchant from one key press', #s == 1, #s)
check('second item targeted', s[1] and s[1].slot == 2)
MOCK.FinishCast(1)

print('-- key binding (cast on key down OFF)')
MOCK.cvars.ActionButtonUseKeyDown = false
reset()
MOCK.KeyBinding('F')
check('one disenchant with the setting off', #spells() == 1, #spells())
MOCK.FinishCast(1)
MOCK.cvars.ActionButtonUseKeyDown = true

print('-- /click macro (cast on key down ON)')
reset()
MOCK.SlashClick(nextBtn)
s = spells()
check('one disenchant from /click', #s == 1, #s)
check('fourth item targeted', s[1] and s[1].bag == 1 and s[1].slot == 4)

print('-- control: a button left to the game setting ignores /click')
local control = CreateFrame('Button', 'ControlBtn', UIParent, 'SecureActionButtonTemplate')
control:SetAttribute('type', 'spell')
reset()
MOCK.SlashClick(control)
check('old-style button does nothing on /click (the reported bug)', #MOCK.actions == 0)
MOCK.FinishCast(1)

print('-- a mouse wheel bind that only sends the press half')
MOCK.AddItem(2, 1, 201, 'Wheel One', 2, 10)
MOCK.AddItem(2, 2, 202, 'Wheel Two', 2, 11)
reset()
nextBtn:Press('key', true)
check('press half alone disenchants', #spells() == 1, #spells())
MOCK.FinishCast(1)
reset()
nextBtn:Press('key', true)
check('the next wheel notch disenchants again', #spells() == 1, #spells())
MOCK.FinishCast(1)

print('-- a key held down through the whole cast')
MOCK.AddItem(2, 3, 203, 'Held One', 2, 12)
MOCK.AddItem(2, 4, 204, 'Held Two', 2, 13)
reset()
nextBtn:Press('key', true)
MOCK.Advance(1)
MOCK.FinishCast(1)
nextBtn:Press('key', false)
check('letting go of the key does not start a second item', #spells() == 1, #spells())
reset()
MOCK.KeyBinding('F')
check('the next key press does', #spells() == 1, #spells())
MOCK.FinishCast(1)

print('-- nothing left')
reset()
Window:Hide()
MOCK.KeyBinding('F')
check('no cast when the bags are empty', #spells() == 0)
check('player told there is nothing left', MOCK.errors[1] == 'Nothing left to disenchant.', MOCK.errors[1])

print('-- bags full: loot window stays open')
MOCK.AddItem(0, 5, 105, 'Green Belt', 2, 90)
MOCK.AddItem(0, 6, 106, 'Green Ring', 2, 95)
reset()
MOCK.KeyBinding('F')
MOCK.bagsFull = true
MOCK.FinishCast(2)
reset()
MOCK.KeyBinding('F')
check('no cast while loot would be lost', #spells() == 0)
check('player told to take the loot', (MOCK.errors[1] or ''):find('loot window') ~= nil, MOCK.errors[1])
MOCK.bagsFull = false
MOCK.loot = {}
MOCK.lootOpen = false
MOCK.Fire('LOOT_CLOSED')
reset()
MOCK.KeyBinding('F')
check('works again once the loot is taken', #spells() == 1)
MOCK.FinishCast(1)

print('-- cursor holding something')
MOCK.AddItem(0, 7, 107, 'Green Wrist', 2, 80)
MOCK.cursor = { kind = 'item', id = 5 }
reset()
MOCK.KeyBinding('F')
check('no cast with an item on the cursor', #spells() == 0)
MOCK.cursor = nil

print('-- press with lag before the cast starts')
MOCK.deferStart = true
local realStart = MOCK.StartCast
local deferred
MOCK.StartCast = function(bag, slot)
	deferred = { bag, slot }
end
reset()
MOCK.KeyBinding('F')
MOCK.KeyBinding('F')
MOCK.KeyBinding('F')
check('only the first press acts before the cast starts', #spells() == 1, #spells())
MOCK.StartCast = realStart
MOCK.Advance(0.2)
realStart(deferred[1], deferred[2])
check('late start still tracked', Engine:GetCastingItem() ~= nil)

print('-- interrupted cast')
MOCK.InterruptCast()
check('cast cleared after interrupt', Engine:GetCastingItem() == nil)
reset()
MOCK.KeyBinding('F')
check('next press disenchants again', #spells() == 1)
MOCK.FinishCast(1)

print('-- combat')
MOCK.AddItem(0, 8, 108, 'Green Shoulders', 2, 85)
MOCK.Fire('PLAYER_REGEN_DISABLED')
MOCK.combat = true
reset()
local ok, err = pcall(MOCK.KeyBinding, 'F')
check('no protected call errors in combat', ok, err)
check('no cast in combat', #spells() == 0)
MOCK.combat = false
MOCK.Fire('PLAYER_REGEN_ENABLED')
reset()
MOCK.KeyBinding('F')
check('works after combat', #spells() == 1)
MOCK.FinishCast(1)

print('-- the game refuses an item')
MOCK.AddItem(0, 9, 109, 'Odd Trinket', 2, 70)
MOCK.refuse[109] = true
reset()
MOCK.KeyBinding('F')
check('refused item blocklisted', DA:IsNonDisenchantable(109))
check('player told about it', lastChat():find('cannot be disenchanted') ~= nil, lastChat())
MOCK.Advance(3)
check('no question asked for a refused item', #MOCK.popups == 0)
reset()
MOCK.KeyBinding('F')
check('refused item no longer picked', #spells() == 0)

print('-- an item that fails silently (Retail salvage)')
MOCK.AddItem(0, 10, 110, 'Quiet Helm', 2, 60)
MOCK.salvageFails[110] = true
reset()
MOCK.KeyBinding('F')
MOCK.Advance(2.5)
check('asked whether to blocklist', MOCK.popups[1] and MOCK.popups[1].which == 'LIBSDA_NON_DISENCHANTABLE')
MOCK.AcceptPopup(MOCK.popups[1])
check('blocklisted after yes', DA:IsNonDisenchantable(110))

print('-- an error that is not about the item asks nothing')
MOCK.AddItem(0, 11, 111, 'Moving Pants', 2, 60)
MOCK.salvageFails[111] = true
local realStart2 = MOCK.StartCast
MOCK.StartCast = function()
	MOCK.Fire('UI_ERROR_MESSAGE', 50, 'You can not do that while moving')
end
reset()
MOCK.KeyBinding('F')
MOCK.Advance(2.5)
check('no question after a moving error', #MOCK.popups == 0)
check('item kept', not DA:IsNonDisenchantable(111))
reset()
MOCK.KeyBinding('F')
check('can press again right after an error', #spells() == 1)
MOCK.StartCast = realStart2
MOCK.salvageFails[111] = nil
MOCK.bags[0][11] = nil
MOCK.Fire('BAG_UPDATE_DELAYED')

print('-- Retail salvage path')
MOCK.AddItem(0, 12, 112, 'Retail Robe', 3, 600)
DA.IsRetail = true
MOCK.salvage = true
reset()
MOCK.KeyBinding('F')
s = spells()
check('salvage macro used on Retail', s[1] and s[1].kind == 'macro' and s[1].slot == 12, s[1] and s[1].kind)
MOCK.FinishCast(1)
DA.IsRetail = false
MOCK.salvage = false

print('-- row DE button')
MOCK.AddItem(0, 13, 113, 'Row One', 2, 50)
MOCK.AddItem(0, 14, 114, 'Row Two', 2, 55)
Window:Show()
local row2 = Window.itemRows[2]
check('row 2 shows the second item', row2.item and row2.item.itemID == 114, row2.item and row2.item.itemID)
reset()
MOCK.MouseClick(row2.TypeButton)
s = spells()
check('row button disenchants its own item', #s == 1 and s[1].slot == 14, s[1] and s[1].slot)
MOCK.FinishCast(1)
MOCK.Advance(0.2)
check('window lists what is left', Window.itemCountText:GetText():find('Items: 1') ~= nil, Window.itemCountText:GetText())

print('-- macro for an action bar')
reset()
check('macro made and picked up', DA:PickupNextMacro() and MOCK.cursor and MOCK.cursor.kind == 'macro')
check('macro clicks LibsDENext', MOCK.macros[1].body == '/click LibsDENext', MOCK.macros[1].body)
check('macro is per character', MOCK.macros[1].perCharacter == true)
MOCK.cursor = nil
DA:PickupNextMacro()
check('existing macro reused', #MOCK.macros == 1)
MOCK.cursor = nil
-- Drag from the big button
windowBtn:RunScript('OnDragStart')
check('dragging the big button picks up the macro', MOCK.cursor and MOCK.cursor.id == 1)
MOCK.cursor = nil

print('-- macro name taken by the player')
MOCK.macros = { { name = 'DE Next', body = '/say hi', perCharacter = true } }
reset()
check('players own macro left alone', not DA:PickupNextMacro() and MOCK.macros[1].body == '/say hi')
MOCK.macros = {}
MOCK.charMacroLimit = 0
check('falls back to an account macro when character slots are full', DA:PickupNextMacro() and MOCK.macros[1].perCharacter == nil)
MOCK.cursor = nil

print('-- key capture in the window')
MOCK.bindings.SPACE = 'JUMP'
reset()
local keyBtn = Window.keyButton
keyBtn:RunScript('OnClick', 'LeftButton')
check('key button waits for a key', keyBtn:GetText() == 'Press a key...', keyBtn:GetText())
keyBtn:RunScript('OnKeyDown', 'LSHIFT')
check('a lone modifier is ignored', Window.listeningForKey == true)
keyBtn:RunScript('OnKeyDown', 'SPACE')
check('taken key asks first', MOCK.popups[1] and MOCK.popups[1].which == 'LIBSDA_REPLACE_KEY' and MOCK.popups[1].b == 'Jump')
check('nothing changed before yes', MOCK.bindings.SPACE == 'JUMP' and MOCK.bindings.F == DA.BINDING_COMMAND)
MOCK.AcceptPopup(MOCK.popups[1])
check('space now disenchants', MOCK.bindings.SPACE == DA.BINDING_COMMAND)
check('old key F released', MOCK.bindings.F == nil)
check('window shows the new key', keyBtn:GetText() == 'Key: SPACE', keyBtn:GetText())

keyBtn:RunScript('OnClick', 'LeftButton')
MOCK.shift = true
keyBtn:RunScript('OnMouseWheel', 1)
MOCK.shift = false
check('shift + mouse wheel bound', MOCK.bindings['SHIFT-MOUSEWHEELUP'] == DA.BINDING_COMMAND)
check('keyboard released after capture', keyBtn._keyboard == false and keyBtn._wheel == false)

keyBtn:RunScript('OnClick', 'LeftButton')
keyBtn:RunScript('OnKeyDown', 'ESCAPE')
check('escape cancels', MOCK.bindings['SHIFT-MOUSEWHEELUP'] == DA.BINDING_COMMAND and not Window.listeningForKey)

keyBtn:RunScript('OnClick', 'RightButton')
check('right-click removes the key', DA:GetNextKey() == nil)
check('window shows no key', keyBtn:GetText() == 'Set a key', keyBtn:GetText())

print('-- slash commands')
reset()
DA:HandleChatCommand('next')
check('/de next explains the macro line', table.concat(MOCK.chat, '\n'):find('/click LibsDENext') ~= nil)
reset()
DA:HandleChatCommand('help')
check('/de help goes to chat', #MOCK.chat > 3)

print(string.format('\n%d passed, %d failed', passed, failed))
if failed > 0 then
	os.exit(1)
end
