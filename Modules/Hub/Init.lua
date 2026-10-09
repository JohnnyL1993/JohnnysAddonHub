-- Edge drawer launcher: a slim "HUB" tab docked to the left, right or top edge
-- of the screen. Hovering the tab (or clicking it to pin) slides out a compact
-- panel listing one numbered row per launcher, grouped into categories. Add
-- more launchers here as more addons get wired in - a new category gets its
-- own heading automatically.
--
-- Each launcher (other than the ButtonForge macro one) names the standalone
-- addon it belongs to via `addon` - only launchers whose addon is currently
-- loaded (IsAddOnLoaded) are shown, so the drawer reflects whichever of
-- Johnny's addons are actually installed and enabled.
local Hub = JohnnysAddonHub:NewModule("Hub", "AceEvent-3.0")

local WHITE = "Interface\\Buttons\\WHITE8X8"
local FONT_NUM = "Fonts\\ARIALN.TTF"
local FONT_TEXT = "Fonts\\FRIZQT__.TTF"

-- "Workshop rack" palette: blue-black panels, 1px rules, one lime accent.
local C = {
	ground = { 0.063, 0.078, 0.086 },
	panel = { 0.090, 0.114, 0.125 },
	raised = { 0.122, 0.153, 0.169 },
	rule = { 0.180, 0.224, 0.243 },
	text = { 0.902, 0.925, 0.918 },
	muted = { 0.604, 0.659, 0.651 },
	accent = { 0.725, 0.886, 0.290 },
}

local PANEL_WIDTH = 176
local HEADER_HEIGHT = 26
local GROUP_HEIGHT = 18
local ROW_HEIGHT = 24
local FOOTER_HEIGHT = 18
local TAB_THICKNESS = 16
local TAB_LENGTH = 64
local SLIDE_SPEED = 6 -- full open/close takes 1/6 of a second
local CLOSE_DELAY = 0.35 -- grace period after the mouse leaves before closing
local DRAG_THRESHOLD = 6

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
		category = "Crafting",
		name = "Professions",
		addon = "JohnnysProfessions",
		onClick = function()
			JohnnysProfessions:Toggle()
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
-- field at all, e.g. the ButtonForge macro entry) are shown.
local function GetVisibleLaunchers()
	local visible = {}
	for _, launcher in ipairs(LAUNCHERS) do
		if not launcher.addon or IsAddOnLoaded(launcher.addon) then
			table.insert(visible, launcher)
		end
	end
	return visible
end

local drawer, tab, pinBtn
local rowWidgets = {}
local secureRows = {} -- rows whose click is handled by a secure overlay button
local secureByName = {}
local progress = 0 -- 0 = tucked away, 1 = fully out
local lastOver = 0
local pressX, pressY
local dragging = false
local inCombat = false
local securePlaced = false

local function DB()
	return JohnnysAddonHub.db.profile.drawer
end

local function Solid(parent, layer, color, alpha)
	local tex = parent:CreateTexture(nil, layer)
	tex:SetTexture(WHITE)
	tex:SetVertexColor(color[1], color[2], color[3], alpha or 1)
	return tex
end

local function StyleBox(frame, color, alpha)
	frame:SetBackdrop({ bgFile = WHITE, edgeFile = WHITE, edgeSize = 1 })
	frame:SetBackdropColor(color[1], color[2], color[3], alpha or 1)
	frame:SetBackdropBorderColor(C.rule[1], C.rule[2], C.rule[3], 1)
end

local function Text(parent, font, size, color)
	local fs = parent:CreateFontString(nil, "OVERLAY")
	-- Arial Narrow gets thin and hard to read below about 14px, so only the
	-- larger sizes (title, row numbers) use it.
	if font == FONT_NUM and size < 14 then
		font, size = FONT_TEXT, math.max(10, size - 1)
	end
	fs:SetFont(font, size)
	fs:SetTextColor(color[1], color[2], color[3])
	return fs
end

-- The ButtonForge row needs a secure button, but a frame with a secure child
-- (or one a secure frame is anchored to) can't be moved in combat - which
-- would freeze the slide. So the secure button lives on UIParent instead and
-- is only laid over its row while the drawer is fully out and out of combat.
local function HideSecure()
	if InCombatLockdown() then
		return
	end
	for _, row in ipairs(secureRows) do
		row.secure:Hide()
	end
	securePlaced = false
end

local function PlaceSecure()
	if InCombatLockdown() then
		return
	end
	for _, row in ipairs(secureRows) do
		local left, bottom = row:GetLeft(), row:GetBottom()
		if left and bottom then
			row.secure:ClearAllPoints()
			row.secure:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", left, bottom)
			row.secure:SetWidth(row:GetWidth())
			row.secure:SetHeight(row:GetHeight())
			row.secure:Show()
		end
	end
	securePlaced = true
end

local function RefreshSecureRows()
	for _, row in ipairs(secureRows) do
		local color = inCombat and C.muted or C.text
		row.label:SetTextColor(color[1], color[2], color[3])
		color = inCombat and C.muted or C.accent
		row.num:SetTextColor(color[1], color[2], color[3])
	end
end

local function ClampOffset(offset)
	local limit
	if DB().dock == "TOP" then
		limit = (UIParent:GetWidth() - PANEL_WIDTH) / 2
	else
		limit = (UIParent:GetHeight() - drawer:GetHeight()) / 2
	end
	if limit < 0 then
		limit = 0
	end
	return math.max(-limit, math.min(limit, offset))
end

local function ApplyPosition()
	local db = DB()
	-- Ease out so the panel decelerates into place.
	local hidden = (1 - progress) * (1 - progress)
	local offset = ClampOffset(db.offset or 0)

	drawer:ClearAllPoints()
	if db.dock == "RIGHT" then
		drawer:SetPoint("RIGHT", UIParent, "RIGHT", PANEL_WIDTH * hidden, offset)
	elseif db.dock == "TOP" then
		drawer:SetPoint("TOP", UIParent, "TOP", offset, drawer:GetHeight() * hidden)
	else
		drawer:SetPoint("LEFT", UIParent, "LEFT", -PANEL_WIDTH * hidden, offset)
	end
end

local function LayoutTab()
	local dock = DB().dock
	tab:ClearAllPoints()
	tab.mark:ClearAllPoints()
	if dock == "TOP" then
		tab:SetWidth(TAB_LENGTH)
		tab:SetHeight(TAB_THICKNESS)
		tab:SetPoint("TOP", drawer, "BOTTOM", 0, 1)
		tab.mark:SetPoint("BOTTOMLEFT", tab, "BOTTOMLEFT", 0, 0)
		tab.mark:SetPoint("BOTTOMRIGHT", tab, "BOTTOMRIGHT", 0, 0)
		tab.mark:SetHeight(2)
		tab.label:SetText("HUB")
	else
		tab:SetWidth(TAB_THICKNESS)
		tab:SetHeight(TAB_LENGTH)
		if dock == "RIGHT" then
			tab:SetPoint("RIGHT", drawer, "LEFT", 1, 0)
			tab.mark:SetPoint("TOPLEFT", tab, "TOPLEFT", 0, 0)
			tab.mark:SetPoint("BOTTOMLEFT", tab, "BOTTOMLEFT", 0, 0)
		else
			tab:SetPoint("LEFT", drawer, "RIGHT", -1, 0)
			tab.mark:SetPoint("TOPRIGHT", tab, "TOPRIGHT", 0, 0)
			tab.mark:SetPoint("BOTTOMRIGHT", tab, "BOTTOMRIGHT", 0, 0)
		end
		tab.mark:SetWidth(2)
		-- No rotated text on this client, so stack the letters instead.
		tab.label:SetText("H\nU\nB")
	end
end

local function RefreshPin()
	local color = DB().pinned and C.accent or C.muted
	pinBtn.text:SetText(DB().pinned and "PINNED" or "PIN")
	pinBtn.text:SetTextColor(color[1], color[2], color[3])
end

local function TogglePinned()
	DB().pinned = not DB().pinned
	if not DB().pinned then
		-- Don't linger on the close delay after an explicit un-pin.
		lastOver = 0
	end
	RefreshPin()
end

local function SetDock(dock)
	if securePlaced then
		HideSecure()
	end
	DB().dock = dock
	DB().offset = 0
	LayoutTab()
	ApplyPosition()
end

local function CycleDock()
	local dock = DB().dock
	if dock == "LEFT" then
		SetDock("TOP")
	elseif dock == "TOP" then
		SetDock("RIGHT")
	else
		SetDock("LEFT")
	end
end

local function CreateRow(index, launcher)
	local row = CreateFrame("Button", nil, drawer)
	row:SetWidth(PANEL_WIDTH - 2)
	row:SetHeight(ROW_HEIGHT)

	local hover = Solid(row, "BACKGROUND", C.raised)
	hover:SetAllPoints()
	hover:Hide()
	row.hover = hover

	local mark = Solid(row, "ARTWORK", C.accent)
	mark:SetPoint("TOPLEFT", row, "TOPLEFT", 0, 0)
	mark:SetPoint("BOTTOMLEFT", row, "BOTTOMLEFT", 0, 0)
	mark:SetWidth(2)
	mark:Hide()
	row.mark = mark

	local num = Text(row, FONT_NUM, 15, C.accent)
	num:SetPoint("LEFT", row, "LEFT", 9, 0)
	num:SetWidth(20)
	num:SetJustifyH("LEFT")
	num:SetText(string.format("%02d", index))
	row.num = num

	local label = Text(row, FONT_TEXT, 11, C.text)
	label:SetPoint("LEFT", num, "RIGHT", 6, 0)
	label:SetPoint("RIGHT", row, "RIGHT", -8, 0)
	label:SetJustifyH("LEFT")
	label:SetText(launcher.name)
	row.label = label

	local function OnEnter()
		hover:Show()
		mark:Show()
	end
	local function OnLeave()
		hover:Hide()
		mark:Hide()
	end
	row:SetScript("OnEnter", OnEnter)
	row:SetScript("OnLeave", OnLeave)

	if launcher.macro then
		local secure = secureByName[launcher.name]
		if not secure then
			secure = CreateFrame("Button", nil, UIParent, "SecureActionButtonTemplate")
			secure:RegisterForClicks("AnyUp")
			secure:SetAttribute("type", "macro")
			secure:SetAttribute("macrotext", launcher.macro)
			secure:SetFrameStrata("MEDIUM")
			secure:SetFrameLevel(drawer:GetFrameLevel() + 10)
			if not InCombatLockdown() then
				secure:Hide()
			end
			secureByName[launcher.name] = secure
		end
		secure:SetScript("OnEnter", OnEnter)
		secure:SetScript("OnLeave", OnLeave)
		row.secure = secure
		table.insert(secureRows, row)
	else
		row:SetScript("OnClick", launcher.onClick)
	end

	return row
end

-- Tears down and rebuilds the category headings/rows from the current set of
-- visible launchers - called from CreateDrawer() and again from the
-- PLAYER_LOGIN safety net in case any addon's load state wasn't settled yet.
local function RebuildRows()
	if securePlaced then
		HideSecure()
	end
	for _, widget in ipairs(rowWidgets) do
		widget:Hide()
	end
	rowWidgets = {}
	secureRows = {}

	local y = -(1 + HEADER_HEIGHT)
	local lastCategory
	for index, launcher in ipairs(GetVisibleLaunchers()) do
		if launcher.category ~= lastCategory then
			lastCategory = launcher.category

			local rule = Solid(drawer, "ARTWORK", C.rule)
			rule:SetPoint("TOPLEFT", drawer, "TOPLEFT", 1, y)
			rule:SetPoint("TOPRIGHT", drawer, "TOPRIGHT", -1, y)
			rule:SetHeight(1)
			table.insert(rowWidgets, rule)

			local heading = Text(drawer, FONT_NUM, 10, C.muted)
			heading:SetPoint("TOPLEFT", drawer, "TOPLEFT", 10, y - 1)
			heading:SetHeight(GROUP_HEIGHT - 1)
			heading:SetJustifyV("MIDDLE")
			heading:SetText(string.upper(launcher.category))
			table.insert(rowWidgets, heading)

			y = y - GROUP_HEIGHT
		end

		local row = CreateRow(index, launcher)
		row:SetPoint("TOPLEFT", drawer, "TOPLEFT", 1, y)
		table.insert(rowWidgets, row)
		y = y - ROW_HEIGHT
	end

	drawer:SetHeight(-y + FOOTER_HEIGHT + 1)
	RefreshSecureRows()
	ApplyPosition()
end

local function OnUpdate(self, elapsed)
	local db = DB()

	-- Dragging the tab slides the whole drawer along its edge.
	if pressX then
		local x, y = GetCursorPosition()
		if not dragging and (math.abs(x - pressX) > DRAG_THRESHOLD or math.abs(y - pressY) > DRAG_THRESHOLD) then
			dragging = true
		end
		if dragging then
			local scale = UIParent:GetEffectiveScale()
			if db.dock == "TOP" then
				db.offset = ClampOffset(x / scale - UIParent:GetWidth() / 2)
			else
				db.offset = ClampOffset(y / scale - UIParent:GetHeight() / 2)
			end
			ApplyPosition()
		end
	end

	local over = MouseIsOver(tab) or (progress > 0 and MouseIsOver(drawer))
	local now = GetTime()
	if over then
		lastOver = now
	end

	local want
	if db.pinned then
		want = true
	elseif dragging then
		want = progress > 0.5
	elseif db.hover then
		want = over or (progress > 0 and (now - lastOver) < CLOSE_DELAY)
	else
		want = false
	end

	local target = want and 1 or 0
	if progress ~= target then
		local step = elapsed * SLIDE_SPEED
		if progress < target then
			progress = math.min(1, progress + step)
		else
			progress = math.max(0, progress - step)
		end
		ApplyPosition()
	end

	local shouldPlace = progress >= 1 and not dragging and not inCombat
	if shouldPlace and not securePlaced then
		PlaceSecure()
	elseif not shouldPlace and securePlaced then
		HideSecure()
	end
end

local function CreateDrawer()
	drawer = CreateFrame("Frame", "JohnnysAddonHubDrawer", UIParent)
	drawer:SetFrameStrata("MEDIUM")
	drawer:SetWidth(PANEL_WIDTH)
	drawer:SetHeight(HEADER_HEIGHT + FOOTER_HEIGHT + 2)
	drawer:EnableMouse(true)
	StyleBox(drawer, C.ground, 0.95)

	local head = Solid(drawer, "BORDER", C.panel)
	head:SetPoint("TOPLEFT", drawer, "TOPLEFT", 1, -1)
	head:SetPoint("TOPRIGHT", drawer, "TOPRIGHT", -1, -1)
	head:SetHeight(HEADER_HEIGHT)

	local title = Text(drawer, FONT_NUM, 14, C.text)
	title:SetPoint("LEFT", head, "LEFT", 9, 0)
	title:SetText("ADDON HUB")

	pinBtn = CreateFrame("Button", nil, drawer)
	pinBtn:SetWidth(54)
	pinBtn:SetHeight(HEADER_HEIGHT)
	pinBtn:SetPoint("RIGHT", head, "RIGHT", 0, 0)
	pinBtn.text = Text(pinBtn, FONT_NUM, 10, C.muted)
	pinBtn.text:SetPoint("RIGHT", pinBtn, "RIGHT", -9, 0)
	pinBtn:SetScript("OnClick", TogglePinned)

	local footRule = Solid(drawer, "ARTWORK", C.rule)
	footRule:SetPoint("BOTTOMLEFT", drawer, "BOTTOMLEFT", 1, FOOTER_HEIGHT)
	footRule:SetPoint("BOTTOMRIGHT", drawer, "BOTTOMRIGHT", -1, FOOTER_HEIGHT)
	footRule:SetHeight(1)

	local foot = Text(drawer, FONT_NUM, 10, C.muted)
	foot:SetPoint("BOTTOMLEFT", drawer, "BOTTOMLEFT", 10, 1)
	foot:SetHeight(FOOTER_HEIGHT - 1)
	foot:SetJustifyV("MIDDLE")
	foot:SetText("/hub help for options")

	tab = CreateFrame("Button", "JohnnysAddonHubTab", drawer)
	StyleBox(tab, C.panel, 0.95)
	tab.mark = Solid(tab, "ARTWORK", C.accent)
	tab.label = Text(tab, FONT_NUM, 11, C.text)
	tab.label:SetPoint("CENTER", tab, "CENTER", 0, 0)
	tab.label:SetJustifyH("CENTER")

	-- Left-click pins/unpins, left-drag moves along the edge, right-click
	-- cycles which edge the drawer is docked to.
	tab:SetScript("OnMouseDown", function(self, button)
		if button == "LeftButton" then
			pressX, pressY = GetCursorPosition()
			dragging = false
		end
	end)
	tab:SetScript("OnMouseUp", function(self, button)
		if button == "RightButton" then
			CycleDock()
		elseif button == "LeftButton" then
			if not dragging then
				TogglePinned()
			end
			dragging = false
			pressX, pressY = nil, nil
		end
	end)

	LayoutTab()
	RefreshPin()
	RebuildRows()

	drawer:SetScript("OnUpdate", OnUpdate)
end

function Hub:OnEnable()
	if not drawer then
		CreateDrawer()
	end
	drawer:Show()

	-- Safety net: on the off chance another addon's load state wasn't fully
	-- settled yet when this fired, re-derive the visible launchers once more
	-- after every addon has finished loading.
	self:RegisterEvent("PLAYER_LOGIN", function()
		RebuildRows()
	end)

	-- PLAYER_REGEN_DISABLED fires just before combat lockdown starts, which is
	-- the last chance to take the secure overlay off screen.
	self:RegisterEvent("PLAYER_REGEN_DISABLED", function()
		HideSecure()
		inCombat = true
		RefreshSecureRows()
	end)
	self:RegisterEvent("PLAYER_REGEN_ENABLED", function()
		inCombat = false
		RefreshSecureRows()
	end)
end

-- Bare /hub - the drawer tab is otherwise always on screen, this just lets you
-- tuck it away completely (e.g. for a screenshot) without disabling the addon.
function Hub:ToggleBar()
	if not drawer then
		CreateDrawer()
	end
	if drawer:IsShown() then
		if securePlaced then
			HideSecure()
		end
		drawer:Hide()
	else
		drawer:Show()
	end
end

function Hub:HandleCommand(input)
	local cmd = string.lower(strtrim(input or ""))
	if cmd == "" then
		self:ToggleBar()
		return
	end
	if not drawer then
		CreateDrawer()
	end

	if cmd == "left" or cmd == "right" or cmd == "top" then
		SetDock(string.upper(cmd))
	elseif cmd == "pin" then
		TogglePinned()
	elseif cmd == "hover" then
		DB().hover = not DB().hover
		JohnnysAddonHub:Print(DB().hover and "Drawer opens on hover." or "Drawer opens on click only.")
	elseif cmd == "reset" then
		DB().pinned = false
		DB().hover = true
		RefreshPin()
		SetDock("LEFT")
	else
		JohnnysAddonHub:Print("/hub - show or hide the drawer tab")
		JohnnysAddonHub:Print("/hub left | right | top - dock to that screen edge (or right-click the tab)")
		JohnnysAddonHub:Print("/hub pin - keep the drawer open (or click the tab)")
		JohnnysAddonHub:Print("/hub hover - toggle opening when the mouse touches the tab")
		JohnnysAddonHub:Print("/hub reset - back to the left edge with default settings")
		JohnnysAddonHub:Print("Drag the tab to slide the drawer along its edge.")
	end
end
