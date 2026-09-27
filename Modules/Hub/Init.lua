-- Always-on-screen launcher bar, grouped into categories (one button per
-- launcher, at most MAX_BUTTONS_PER_ROW per row). Add more here as more
-- addons get wired in - a new category gets its own row(s) automatically, a
-- launcher added to an existing category appends onto that category's last
-- row, overflowing onto a new row once the cap is hit.
--
-- Each launcher (other than the ButtonForge macro one) names the standalone
-- addon it belongs to via `addon` - only launchers whose addon is currently
-- loaded (IsAddOnLoaded) are shown, so the bar reflects whichever of Johnny's
-- addons are actually installed and enabled.
local Hub = JohnnysAddonHub:NewModule("Hub", "AceEvent-3.0")

local HANDLE_WIDTH = 14
local TOGGLE_WIDTH = 20
local CATEGORY_LABEL_WIDTH = 64
local BUTTON_WIDTH = 110
local ROW_HEIGHT = 22
local PADDING = 4
local MAX_BUTTONS_PER_ROW = 3

-- x where each row's real content starts, right after the drag handle.
local CONTENT_X = PADDING + HANDLE_WIDTH + PADDING

local Skin = JohnnysAddonHub.Skin

local LAUNCHERS = {
	{
		category = "Gearing",
		name = "Gear Advisor",
		addon = "JohnnysGearAdvisor",
		onClick = function()
			JohnnysGearAdvisor:Toggle()
		end,
	},
	{
		category = "Raiding",
		name = "Raid Browser",
		addon = "JohnnysRaidBrowser",
		onClick = function()
			JohnnysRaidBrowser.RaidBrowserUI:Toggle()
		end,
	},
	{
		category = "Raiding",
		name = "Raid Roll",
		addon = "JohnnysRaidRoll",
		onClick = function()
			JohnnysRaidRoll.RaidRollUI:Toggle()
		end,
	},
	{
		category = "Raiding",
		name = "Raid Loot",
		addon = "JohnnysRaidRoll",
		onClick = function()
			JohnnysRaidRoll.RaidLootUI:Toggle()
		end,
	},
	{
		category = "Raiding",
		name = "Raid Comp",
		addon = "JohnnysRaidComp",
		onClick = function()
			JohnnysRaidComp.RaidCompUI:Toggle()
		end,
	},
	-- Raid Spammer is now built into Johnny's Raid Comp - open it from the
	-- "LFM" button in that window's top-right corner.
	{
		category = "Social",
		name = "Blacklist",
		addon = "JohnnysBlackList",
		onClick = function()
			JohnnysBlackList:Toggle()
		end,
	},
	{
		category = "UI",
		name = "Button Forge",
		-- ButtonForge has no window of its own - it toggles an in-place
		-- "configure mode" via a SecureHandlerClickTemplate button that only
		-- responds to a real hardware-triggered "/click" (a scripted :Click()
		-- call errors with "Invalid 'self' frame handle"). Same fix ButtonForge
		-- uses internally: a SecureActionButtonTemplate macro button running
		-- "/click BFToolbarToggle" (see bindings.xml/CustomAction.lua).
		macro = "/click BFToolbarToggle",
	},
}

-- Only launchers whose addon is currently loaded (or that have no `addon`
-- field at all, e.g. the ButtonForge macro entry) are shown. Addon load state
-- doesn't change mid-session, so this is safe to re-derive each time the bar
-- is (re)built rather than cached.
local function GetVisibleLaunchers()
	local visible = {}
	for _, launcher in ipairs(LAUNCHERS) do
		if not launcher.addon or IsAddOnLoaded(launcher.addon) then
			table.insert(visible, launcher)
		end
	end
	return visible
end

local bar, handle, toggleBtn, title
local categoryWidgets = {}
local numCategoryRows = 0
local maxButtonsPerRow, TOGGLE_X, BAR_WIDTH

local function SavePosition()
	local point, _, relativePoint, x, y = bar:GetPoint()
	local pos = JohnnysAddonHub.db.profile.hubBarPosition
	pos.point, pos.relativePoint, pos.x, pos.y = point, relativePoint, x, y
end

local function CreateLauncherButton(parent, launcher)
	if launcher.macro then
		local btn = Skin:CreateButton(parent, BUTTON_WIDTH, ROW_HEIGHT, launcher.name, "SecureActionButtonTemplate")
		btn:RegisterForClicks("AnyUp")
		btn:SetAttribute("type", "macro")
		btn:SetAttribute("macrotext", launcher.macro)
		return btn
	end

	local btn = Skin:CreateButton(parent, BUTTON_WIDTH, ROW_HEIGHT, launcher.name)
	btn:SetScript("OnClick", launcher.onClick)
	return btn
end

-- The bar's width has to fit whichever row has the most buttons, not just
-- one - previously TOGGLE_X/BAR_WIDTH assumed a single button per row, so a
-- row like "Raiding" (Raid Browser/Raid Roll/Raid Loot) laid out buttons past
-- the panel's own background with nothing behind them. Rows now cap at
-- MAX_BUTTONS_PER_ROW (a category with more launchers than that wraps onto
-- extra rows instead), so the widest row is never wider than the cap.
--
-- Computed against GetVisibleLaunchers() (not the full static LAUNCHERS list)
-- since it must run after other addons' load state is known - see CreateBar().
local function ComputeLayoutMetrics(visibleLaunchers)
	local counts = {}
	for _, launcher in ipairs(visibleLaunchers) do
		counts[launcher.category] = (counts[launcher.category] or 0) + 1
	end
	maxButtonsPerRow = 1
	for _, count in pairs(counts) do
		local rowWidth = math.min(count, MAX_BUTTONS_PER_ROW)
		if rowWidth > maxButtonsPerRow then
			maxButtonsPerRow = rowWidth
		end
	end

	-- x where the collapse toggle sits when expanded - lines up right after
	-- the widest row's last button, so every row (and the title above them)
	-- shares the same overall width.
	TOGGLE_X = CONTENT_X + CATEGORY_LABEL_WIDTH + PADDING + maxButtonsPerRow * (BUTTON_WIDTH + PADDING)
	BAR_WIDTH = TOGGLE_X + TOGGLE_WIDTH + PADDING
end

-- Shows/hides the title + category rows and repositions the toggle/bar size
-- based on collapsed state - collapsing shrinks the bar down to just the
-- handle + toggle, same as before, just now covering the whole grouped list
-- instead of a single row of buttons.
local function Layout()
	local collapsed = JohnnysAddonHub.db.profile.hubBarCollapsed

	-- SetShown doesn't exist on this client - only Show()/Hide() do.
	if collapsed then
		title:Hide()
	else
		title:Show()
	end
	for _, widget in ipairs(categoryWidgets) do
		if collapsed then
			widget:Hide()
		else
			widget:Show()
		end
	end

	toggleBtn:ClearAllPoints()
	if collapsed then
		toggleBtn:SetPoint("TOPLEFT", bar, "TOPLEFT", CONTENT_X, 0)
		toggleBtn.text:SetText(">")
		bar:SetSize(CONTENT_X + TOGGLE_WIDTH + PADDING, ROW_HEIGHT)
	else
		toggleBtn:SetPoint("TOPLEFT", bar, "TOPLEFT", TOGGLE_X, 0)
		toggleBtn.text:SetText("<")
		bar:SetSize(BAR_WIDTH, ROW_HEIGHT * (1 + numCategoryRows))
	end
end

-- Tears down and rebuilds the category rows/buttons from the current set of
-- visible launchers - called from CreateBar() and again from the PLAYER_LOGIN
-- safety net in case any addon's load state wasn't settled yet on first build.
local function RebuildRows()
	for _, widget in ipairs(categoryWidgets) do
		widget:Hide()
		widget:SetParent(nil)
	end
	categoryWidgets = {}

	local visibleLaunchers = GetVisibleLaunchers()
	ComputeLayoutMetrics(visibleLaunchers)

	local categoryOrder = {}
	local seen = {}
	for _, launcher in ipairs(visibleLaunchers) do
		if not seen[launcher.category] then
			seen[launcher.category] = true
			table.insert(categoryOrder, launcher.category)
		end
	end

	local drawnRows = 0
	for _, category in ipairs(categoryOrder) do
		local buttonX = CONTENT_X + CATEGORY_LABEL_WIDTH + PADDING
		local buttonIndex = 0

		for _, launcher in ipairs(visibleLaunchers) do
			if launcher.category == category then
				if buttonIndex % MAX_BUTTONS_PER_ROW == 0 then
					drawnRows = drawnRows + 1
					buttonX = CONTENT_X + CATEGORY_LABEL_WIDTH + PADDING

					if buttonIndex == 0 then
						local label = bar:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
						label:SetPoint("TOPLEFT", bar, "TOPLEFT", CONTENT_X, -(drawnRows * ROW_HEIGHT))
						label:SetSize(CATEGORY_LABEL_WIDTH, ROW_HEIGHT)
						label:SetJustifyH("LEFT")
						label:SetJustifyV("MIDDLE")
						label:SetTextColor(0.7, 0.7, 0.7)
						label:SetText(category)
						table.insert(categoryWidgets, label)
					end
				end

				local btn = CreateLauncherButton(bar, launcher)
				btn:SetPoint("TOPLEFT", bar, "TOPLEFT", buttonX, -(drawnRows * ROW_HEIGHT))
				table.insert(categoryWidgets, btn)
				buttonX = buttonX + BUTTON_WIDTH + PADDING
				buttonIndex = buttonIndex + 1
			end
		end
	end
	numCategoryRows = drawnRows

	title:SetSize(TOGGLE_X - CONTENT_X - PADDING, ROW_HEIGHT)

	Layout()
end

local function CreateBar()
	bar = CreateFrame("Frame", "JohnnysAddonHubBar", UIParent)

	local pos = JohnnysAddonHub.db.profile.hubBarPosition
	bar:SetPoint(pos.point, UIParent, pos.relativePoint, pos.x, pos.y)

	Skin:StylePanel(bar, 0.85)
	bar:SetFrameStrata("MEDIUM")

	bar:SetMovable(true)
	bar:EnableMouse(true)
	bar:RegisterForDrag("LeftButton")
	bar:SetScript("OnDragStart", bar.StartMoving)
	bar:SetScript("OnDragStop", function(self)
		self:StopMovingOrSizing()
		SavePosition()
	end)

	-- Dedicated drag grip: once buttons are packed edge-to-edge there's almost
	-- no bare background left to grab, so this reserves a always-draggable strip.
	handle = CreateFrame("Frame", nil, bar)
	handle:SetSize(HANDLE_WIDTH, ROW_HEIGHT)
	handle:SetPoint("TOPLEFT", bar, "TOPLEFT", PADDING, 0)
	handle:EnableMouse(true)
	handle:RegisterForDrag("LeftButton")
	handle:SetScript("OnDragStart", function() bar:StartMoving() end)
	handle:SetScript("OnDragStop", function()
		bar:StopMovingOrSizing()
		SavePosition()
	end)
	for i = 1, 3 do
		local dot = handle:CreateTexture(nil, "ARTWORK")
		dot:SetTexture(Skin.WHITE)
		dot:SetVertexColor(0.55, 0.55, 0.55, 1)
		dot:SetSize(HANDLE_WIDTH - 6, 2)
		dot:SetPoint("CENTER", handle, "CENTER", 0, 7 - (i - 1) * 6)
	end

	title = bar:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	title:SetPoint("TOPLEFT", bar, "TOPLEFT", CONTENT_X, 0)
	title:SetJustifyH("CENTER")
	title:SetJustifyV("MIDDLE")
	title:SetTextColor(1, 1, 1)
	title:SetText("Johnny's Addon Hub")

	toggleBtn = Skin:CreateButton(bar, TOGGLE_WIDTH, ROW_HEIGHT, "<")
	toggleBtn:SetScript("OnClick", function()
		JohnnysAddonHub.db.profile.hubBarCollapsed = not JohnnysAddonHub.db.profile.hubBarCollapsed
		Layout()
	end)

	RebuildRows()
end

function Hub:OnEnable()
	if not bar then
		CreateBar()
	end
	bar:Show()

	-- Safety net: on the off chance another addon's load state wasn't fully
	-- settled yet when this fired, re-derive the visible launchers once more
	-- after every addon has finished loading. Load state doesn't change again
	-- after that, so a single extra pass here is enough - no polling needed.
	self:RegisterEvent("PLAYER_LOGIN", function()
		RebuildRows()
	end)
end

-- Bound to /hub - the bar is otherwise always shown, this just lets you tuck it
-- away temporarily (e.g. for a screenshot) without disabling the addon.
function Hub:ToggleBar()
	if not bar then
		CreateBar()
	end
	if bar:IsShown() then
		bar:Hide()
	else
		bar:Show()
	end
end
