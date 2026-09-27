-- Corrective fix for Blizzard's own Chat Config window (Interface Options >
-- Chat: the "Global Channels" checkbox list rendering visually behind its
-- own panel - Chat/Other are unaffected). Diagnosed live via /fstack: a
-- checkbox like ChatConfigChannelSettingsLeftCheckBox4 sits at frame level
-- 128 - behind its own parent ChatConfigChannelSettingsLeft (131),
-- ChatConfigBackgroundFrame (130), ChatConfigFrame (129), and an unnamed
-- frame at 132 matching ElvUI's checkbox-backdrop pattern.
--
-- Two prior attempts (one-shot fix on OnShow, then a repeating sweep) both
-- read back completely unchanged in /fstack, meaning the fix isn't taking
-- effect at all - not even reverted, just never applied. That points at the
-- fix code itself not running (or not finding the checkbox) rather than
-- something else re-breaking it. DEBUG_PRINT below adds chat output so we
-- can see exactly what's happening instead of guessing again; remove once
-- this is solved.
local DEBUG_PRINT = true

local function Debug(msg)
	if DEBUG_PRINT then
		DEFAULT_CHAT_FRAME:AddMessage("|cff40ffffChatConfigFix:|r " .. msg)
	end
end

Debug("file loaded")

local CHECKBOX_PREFIXES = {
	"ChatConfigChatSettingsLeftCheckBox",
	"ChatConfigChatSettingsRightCheckBox",
	"ChatConfigChannelSettingsLeftCheckBox",
	"ChatConfigChannelSettingsRightCheckBox",
	"ChatConfigOtherSettingsCheckBox",
}
local MAX_CHECKBOXES_PER_LIST = 30
local SWEEP_INTERVAL = 0.2

local function FixChatConfigLayering()
	if not ChatConfigFrame then
		Debug("sweep: ChatConfigFrame doesn't exist")
		return
	end

	local topLevel = ChatConfigFrame:GetFrameLevel() + 100
	local found = 0

	for _, prefix in ipairs(CHECKBOX_PREFIXES) do
		for i = 1, MAX_CHECKBOXES_PER_LIST do
			local checkbox = _G[prefix .. i]
			if checkbox then
				found = found + 1
				local before = checkbox:GetFrameLevel()
				checkbox:SetFrameLevel(topLevel)
				local after = checkbox:GetFrameLevel()
				if before ~= after or i <= 4 then
					Debug(prefix .. i .. ": was " .. before .. ", set to " .. topLevel .. ", now " .. after)
				end
			end
		end
	end

	Debug("sweep ran, found " .. found .. " checkboxes, topLevel=" .. topLevel)
end

local ticker = CreateFrame("Frame")
ticker:Hide()
local tickerElapsed = 0
ticker:SetScript("OnUpdate", function(self, elapsed)
	tickerElapsed = tickerElapsed + elapsed
	if tickerElapsed < SWEEP_INTERVAL then
		return
	end
	tickerElapsed = 0
	FixChatConfigLayering()
end)

local function StartSweeping()
	Debug("ChatConfigFrame OnShow fired - starting sweep ticker")
	FixChatConfigLayering()
	tickerElapsed = 0
	ticker:Show()
end

local function StopSweeping()
	Debug("ChatConfigFrame OnHide fired - stopping sweep ticker")
	ticker:Hide()
end

-- Blizzard_ChatConfig is a load-on-demand system addon - ChatConfigFrame
-- doesn't exist until it loads (normally the first time this window is
-- opened each session), so the hooks have to wait for that rather than
-- being attached at file-load time.
local watcher = CreateFrame("Frame")
watcher:RegisterEvent("ADDON_LOADED")
watcher:SetScript("OnEvent", function(self, event, addonName)
	if addonName == "Blizzard_ChatConfig" then
		Debug("Blizzard_ChatConfig ADDON_LOADED fired, ChatConfigFrame exists=" .. tostring(ChatConfigFrame ~= nil))
		if ChatConfigFrame then
			ChatConfigFrame:HookScript("OnShow", StartSweeping)
			ChatConfigFrame:HookScript("OnHide", StopSweeping)
			Debug("hooks attached via ADDON_LOADED")
		end
		self:UnregisterEvent("ADDON_LOADED")
	end
end)

-- Covers the rarer case where Blizzard_ChatConfig had already loaded before
-- this file ran (e.g. the window was opened earlier in the same session).
if ChatConfigFrame then
	Debug("ChatConfigFrame already existed at file-load time")
	ChatConfigFrame:HookScript("OnShow", StartSweeping)
	ChatConfigFrame:HookScript("OnHide", StopSweeping)
end
