local ADDON_NAME = ...

JohnnysAddonHub = LibStub("AceAddon-3.0"):NewAddon("JohnnysAddonHub", "AceConsole-3.0", "AceEvent-3.0")

local defaults = {
	profile = {
		hubBarPosition = { point = "CENTER", relativePoint = "CENTER", x = 0, y = 250 },
		hubBarCollapsed = false,
		-- Edge drawer (Modules\Hub\Init.lua): dock is "LEFT", "RIGHT" or "TOP",
		-- offset slides it along that edge from the centre.
		drawer = { dock = "LEFT", offset = 0, pinned = false, hover = true },
	},
}

function JohnnysAddonHub:OnInitialize()
	self.db = LibStub("AceDB-3.0"):New("JohnnysAddonHubDB", defaults)

	self:RegisterChatCommand("hub", "OnHubSlashCommand")
end

function JohnnysAddonHub:OnHubSlashCommand(input)
	local module = self:GetModule("Hub", true)
	if module then
		module:HandleCommand(input)
	else
		self:Print("Hub module failed to load.")
	end
end
