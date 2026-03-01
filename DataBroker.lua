---@class LibsDisenchantAssist
local LibsDisenchantAssist = LibStub('AceAddon-3.0'):GetAddon('LibsDisenchantAssist')

---@class LibsDisenchantAssist.DataBroker : AceModule, AceEvent-3.0
local DataBroker = LibsDisenchantAssist:NewModule('DataBroker')
LibsDisenchantAssist.DataBroker = DataBroker

function DataBroker:OnInitialize()
	self.ldbObject = nil
end

function DataBroker:OnEnable()
	self:RegisterLDB()
	self:RegisterMessage('DISENCHANT_ASSIST_ITEMS_UPDATED', 'UpdateText')
	self:RegisterMessage('DISENCHANT_ASSIST_ITEM_DESTROYED', 'UpdateText')
	self:RegisterMessage('DISENCHANT_ASSIST_QUEUE_COMPLETE', 'UpdateText')
	self:RegisterMessage('DISENCHANT_ASSIST_PROFILE_CHANGED', 'UpdateText')
end

function DataBroker:RegisterLDB()
	local LDB = LibStub:GetLibrary('LibDataBroker-1.1', true)
	if not LDB then
		return
	end

	self.ldbObject = LDB:NewDataObject('LibsDisenchantAssist', {
		type = 'data source',
		text = 'DE: 0',
		icon = 'Interface\\Icons\\INV_Enchant_Disenchant',
		label = "Lib's - Disenchant Assist",

		OnClick = function(_, button)
			if button == 'LeftButton' then
				if LibsDisenchantAssist.MainWindow then
					LibsDisenchantAssist.MainWindow:Toggle()
				end
			elseif button == 'RightButton' then
				if LibsDisenchantAssist.MainWindow then
					LibsDisenchantAssist.MainWindow:Show()
					LibsDisenchantAssist.MainWindow:ShowSettings()
				end
			end
		end,

		OnTooltipShow = function(tooltip)
			if not tooltip then
				return
			end

			tooltip:AddLine("|cff00ff00Lib's - Disenchant Assist|r")
			tooltip:AddLine(' ')

			local count = LibsDisenchantAssist.FilterSystem:GetItemCount()

			if count > 0 then
				tooltip:AddDoubleLine('Disenchantable', tostring(count), 1, 1, 1, 0.5, 1, 0.5)
			else
				tooltip:AddLine('|cff888888No items to disenchant|r')
			end

			tooltip:AddLine(' ')
			tooltip:AddLine('|cffFFFFFFLeft Click:|r |cff00ffffToggle window|r')
			tooltip:AddLine('|cffFFFFFFRight Click:|r |cff00ffffSettings|r')
		end,
	})

	LibsDisenchantAssist._ldbObject = self.ldbObject

	local LibDBIcon = LibStub:GetLibrary('LibDBIcon-1.0', true)
	if LibDBIcon then
		if not LibsDisenchantAssist.DBC.minimapDefaultApplied then
			LibsDisenchantAssist.DBC.minimapDefaultApplied = true
			if C_AddOns.IsAddOnLoaded('Libs-DataBar') then
				LibsDisenchantAssist.DBC.minimap.hide = true
			end
		end

		LibDBIcon:Register('LibsDisenchantAssist', self.ldbObject, LibsDisenchantAssist.DBC.minimap)
	end
end

function DataBroker:UpdateText()
	if not self.ldbObject then
		return
	end

	local count = LibsDisenchantAssist.FilterSystem:GetItemCount()

	if count > 0 then
		self.ldbObject.text = 'DE: ' .. count
	else
		self.ldbObject.text = 'DE: 0'
	end
end
