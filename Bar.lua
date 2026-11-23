-- Bar: the rows of clickable icons, how each icon is painted, where each bar
-- sits and when it's shown. A profile has up to four bars; each has its own
-- icons, position, look and show rules. Icons are only repainted when
-- something about them changed; there is no per-frame code.
--
-- The icons are secure action buttons, which is what lets a click use an
-- item. The game doesn't allow such buttons to be created, moved, resized,
-- shown or hidden by an addon during combat, so those changes wait until
-- combat ends. Showing and hiding by combat or group state is handed to the
-- game itself (a visibility state driver), which is allowed to do it.
local _, ns = ...

local Glow = ns.Glow
local MAIN_HAND, OFF_HAND = 16, 17

local slots = {}      -- every bar ever made, by position; reused, never destroyed
local pending = {}    -- work waiting for combat to end
local needs = {}      -- which kinds of icon are in use, for event registration
local countStamp = 0  -- bumped whenever bag counts should be read again

---------------------------------------------------------------------------
-- Tooltip
---------------------------------------------------------------------------
local function OnEnter(button)
	local entry = button.entry
	if not entry or not ns.db.bar.tooltips or button.owner.invisible then return end
	GameTooltip:SetOwner(button, "ANCHOR_TOP")
	if not pcall(GameTooltip.SetItemByID, GameTooltip, entry.id) then
		GameTooltip:SetText(ns.ItemName(entry.id))
	end
	if button.slot then
		GameTooltip:AddLine(button.slot == MAIN_HAND and "Applies to your main hand" or "Applies to your off hand", 0.6, 0.8, 1)
	end
	local state = button.state
	if entry.kind == "view" then
		local count = ns.ItemCount(entry.id)
		if count == 0 then
			GameTooltip:AddLine("None in your bags", 1, 0.2, 0.2)
		elseif state and state.status == "expiring" then
			GameTooltip:AddLine("Running low: " .. count .. " in your bags", 1, 0.82, 0)
		else
			GameTooltip:AddLine(count .. " in your bags", 0.3, 1, 0.3)
		end
		GameTooltip:AddLine("View only: clicking does nothing", 0.6, 0.6, 0.6)
		GameTooltip:Show()
		return
	end
	if state then
		local status = state.status
		local left = state.expires and state.expires > 0 and ns.FormatTime(state.expires - GetTime())
		if status == "active" then
			GameTooltip:AddLine(left and ("Active, " .. left .. " left") or "Active", 0.3, 1, 0.3)
		elseif status == "expiring" then
			GameTooltip:AddLine("Running out, " .. (left or "soon") .. " left", 1, 0.82, 0)
		elseif status == "missing" then
			GameTooltip:AddLine("Missing", 1, 0.2, 0.2)
		elseif status == "na" then
			GameTooltip:AddLine("No weapon in this hand", 0.6, 0.6, 0.6)
		end
		if state.predicted then
			GameTooltip:AddLine("Estimated: the game hides this buff in combat.", 0.6, 0.6, 0.6, true)
		end
	end
	if ns.ItemCount(entry.id) == 0 then
		GameTooltip:AddLine("None in your bags", 1, 0.2, 0.2)
	else
		GameTooltip:AddLine("Left-click to use", 0.6, 0.6, 0.6)
	end
	GameTooltip:Show()
end

local function OnLeave()
	GameTooltip:Hide()
end

---------------------------------------------------------------------------
-- Buttons
---------------------------------------------------------------------------
local function CreateButton(bar, index)
	-- Bar 1 keeps the plain names it has always had.
	local name = "ClickableConsumeBarButton" .. (bar.index == 1 and "" or (bar.index .. "_")) .. index
	local button = CreateFrame("Button", name, bar.frame, "SecureActionButtonTemplate")
	button.owner = bar
	-- Both, so a click works whichever way "cast on key down" is set.
	button:RegisterForClicks("AnyUp", "AnyDown")

	button.bg = button:CreateTexture(nil, "BACKGROUND")
	button.bg:SetAllPoints(button)
	button.bg:SetColorTexture(0, 0, 0, 0.6)

	button.icon = button:CreateTexture(nil, "ARTWORK")
	button.icon:SetAllPoints(button)
	button.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)

	button:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD")

	Glow.Build(button)

	-- Text sits on its own layer so the glow never covers it.
	local text = CreateFrame("Frame", nil, button)
	text:SetAllPoints(button)
	text:SetFrameLevel(button:GetFrameLevel() + 6)
	button.timer = text:CreateFontString(nil, "OVERLAY", "GameFontHighlightOutline")
	button.timer:SetPoint("CENTER", text, "CENTER", 0, 0)
	button.count = text:CreateFontString(nil, "OVERLAY", "NumberFontNormal")
	button.count:SetPoint("BOTTOMRIGHT", text, "BOTTOMRIGHT", -1, 1)
	button.hand = text:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmallOutline")
	button.hand:SetPoint("TOPLEFT", text, "TOPLEFT", 1, -1)
	button.hand:SetTextColor(0.6, 0.8, 1)

	button:SetScript("OnEnter", OnEnter)
	button:SetScript("OnLeave", OnLeave)
	return button
end

-- Paints one icon from its state. Called several times a second, so every
-- change is skipped when nothing is different.
function ns.PaintButton(button, now)
	local state = button.state
	if not state then return end
	local db = ns.db
	local status = state.status

	local desaturate = db.desaturate and (status == "missing" or status == "na") or false
	if button.desaturated ~= desaturate then
		button.desaturated = desaturate
		button.icon:SetDesaturated(desaturate)
	end
	local shade = status == "na" and 0.35 or 1
	if button.shade ~= shade then
		button.shade = shade
		button.icon:SetVertexColor(shade, shade, shade)
	end

	local glow
	if status == "expiring" then glow = db.glow.expiring elseif status == "missing" then glow = db.glow.missing end
	Glow.Apply(button, glow, button.size, button.size)

	-- The timer text only changes when the number it would show does, so the
	-- text is formatted then and not on every update.
	local key, left = 0, nil
	if button.cfg.showTimer and (status == "active" or status == "expiring") and state.expires and state.expires > 0 then
		left = state.expires - now
		if left >= 5400 then
			key = 200000 + math.floor(left / 3600 + 0.5)
		elseif left >= 60 then
			key = 100000 + math.ceil(left / 60)
		else
			key = 1 + math.max(0, math.ceil(left))
		end
	end
	if button.timerKey ~= key then
		button.timerKey = key
		button.timer:SetText(key == 0 and "" or ns.FormatTime(left))
	end
	if button.timerStatus ~= status then
		button.timerStatus = status
		if status == "expiring" then
			button.timer:SetTextColor(1, 0.82, 0)
		else
			button.timer:SetTextColor(1, 1, 1)
		end
	end

	if button.countStamp ~= countStamp then
		button.countStamp = countStamp
		local label = ""
		if button.cfg.showCount or button.entry.kind == "view" then
			local count = ns.ItemCount(button.entry.id)
			label = tostring(count)
			if count == 0 then
				button.count:SetTextColor(1, 0.2, 0.2)
			else
				button.count:SetTextColor(1, 1, 1)
			end
		end
		button.count:SetText(label)
	end
end

function ns.RefreshIcons()
	for _, button in ipairs(ns.buttons) do
		button.icon:SetTexture(ns.ItemIcon(button.entry.id))
	end
end

-- Makes the next paint read bag counts again (your bags changed).
function ns.InvalidateCounts()
	countStamp = countStamp + 1
end

-- Makes the next paint redo every icon from scratch (a setting changed).
function ns.Invalidate()
	countStamp = countStamp + 1
	for _, button in ipairs(ns.buttons) do
		button.desaturated, button.shade, button.timerKey, button.timerStatus = nil, nil, nil, nil
	end
end

---------------------------------------------------------------------------
-- Bars
---------------------------------------------------------------------------
-- A bar here is the on-screen thing: a frame, its icons and its drag handle.
-- bar.data is the saved bar it currently shows (name, entries, cfg, show).
local function SavePosition(bar)
	local cfg = bar.cfg
	local point, _, relPoint, x, y = bar.frame:GetPoint(1)
	if point and cfg then
		cfg.point, cfg.relPoint, cfg.x, cfg.y = point, relPoint or point, x or 0, y or 0
	end
end

local function StopMoving()
	for _, bar in ipairs(slots) do
		if bar.moving then
			bar.moving = false
			bar.frame:StopMovingOrSizing()
			SavePosition(bar)
		end
	end
	ns.moving = false
end

local function CreateBar(index)
	local frame = CreateFrame("Frame", "ClickableConsumeBarFrame" .. (index == 1 and "" or index), UIParent)
	frame:SetSize(36, 36)
	frame:SetMovable(true)
	frame:SetClampedToScreen(true)
	local bar = { index = index, frame = frame, pool = {}, buttons = {}, shown = true }

	-- A hidden bar isn't repainted and doesn't keep its timers ticking (see
	-- Track.lua). The game shows and hides bars by itself, so this is how
	-- the addon hears about it: catch up the moment the bar appears.
	frame:SetScript("OnShow", function()
		bar.shown = true
		if bar.data then ns.RequestScan() end
	end)
	frame:SetScript("OnHide", function() bar.shown = false end)

	-- The handle shown above the bar while the bars are unlocked.
	local mover = CreateFrame("Frame", "ClickableConsumeBarMover" .. (index == 1 and "" or index), UIParent)
	mover:SetFrameStrata("HIGH")
	mover:SetHeight(16)
	mover:SetPoint("BOTTOMLEFT", frame, "TOPLEFT", 0, 3)
	mover.bg = mover:CreateTexture(nil, "BACKGROUND")
	mover.bg:SetAllPoints(mover)
	mover.bg:SetColorTexture(0, 0.45, 0.9, 0.75)
	mover.label = mover:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	mover.label:SetPoint("CENTER", mover, "CENTER", 0, 0)
	mover:EnableMouse(true)
	mover:RegisterForDrag("LeftButton")
	mover:SetScript("OnDragStart", function()
		if InCombatLockdown() then
			ns.Print("Bars can't be moved during combat.")
			return
		end
		bar.moving, ns.moving = true, true
		frame:StartMoving()
	end)
	mover:SetScript("OnDragStop", StopMoving)
	mover:SetScript("OnMouseUp", function(_, mouseButton)
		if mouseButton == "RightButton" then
			-- Open the menu on this bar.
			if bar.data then ns.SelectBar(bar.index) end
			ns.ToggleOptions(true)
		end
	end)
	mover:SetScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_TOP")
		GameTooltip:SetText(bar.data and bar.data.name or "ClickableConsumeBar")
		GameTooltip:AddLine("Drag to move this bar.", 1, 1, 1)
		GameTooltip:AddLine("Right-click to open the menu on this bar. Lock the bars there to hide the handles.", 1, 1, 1, true)
		GameTooltip:Show()
	end)
	mover:SetScript("OnLeave", OnLeave)
	mover:Hide()
	bar.mover = mover
	return bar
end

-- Called once at login.
function ns.StartBars()
	ns.ready = true
	ns.combat = UnitAffectingCombat("player") and true or false
end

function ns.UpdateMover()
	local locked = ns.db.bar.locked
	for _, bar in ipairs(slots) do
		local mover = bar.mover
		if locked or not bar.data then
			mover:Hide()
		else
			local empty = #bar.buttons == 0
			local label = bar.data.name
			if empty then label = label .. ": type /ccb to add consumables" end
			mover.label:SetText(label)
			mover:SetWidth(math.max(empty and 300 or 110, bar.frame:GetWidth() or 0))
			mover:Show()
		end
	end
end

-- Lays one bar out from its saved settings and adds its icons to the shared
-- lists the tracker walks.
local function LayoutBar(bar)
	local cfg, frame = bar.cfg, bar.frame
	local size, spacing, perRow = cfg.size, cfg.spacing, math.max(1, cfg.perRow)

	local wanted = {}
	for _, entry in ipairs(bar.data.entries) do
		ns.allEntries[#ns.allEntries + 1] = entry
		if entry.kind == "weapon" then
			if entry.mh then wanted[#wanted + 1] = { entry, MAIN_HAND } end
			if entry.oh then wanted[#wanted + 1] = { entry, OFF_HAND } end
		else
			wanted[#wanted + 1] = { entry }
		end
	end

	for i = #bar.buttons, 1, -1 do bar.buttons[i] = nil end
	for i, spec in ipairs(wanted) do
		local entry, slot = spec[1], spec[2]
		local kind = entry.kind
		if kind == "weapon" then needs.weapon = true elseif kind ~= "view" then needs.self = true end
		if kind ~= "view" then needs.usable = true end

		local button = bar.pool[i]
		if not button then
			button = CreateButton(bar, i)
			bar.pool[i] = button
		end
		button.entry, button.slot, button.cfg = entry, slot, cfg
		-- What's known about this icon's buff, kept across rebuilds. Each bar
		-- keeps its own, since the same item can sit on two bars with
		-- different warning times.
		button.key = bar.index .. ":" .. entry.id .. ":" .. (slot or 0)
		button.size = size
		button.state = nil
		local cache = ns.cache[button.key]
		if not cache then
			cache = {}
			ns.cache[button.key] = cache
		end
		button.cache = cache

		local col, row = (i - 1) % perRow, math.floor((i - 1) / perRow)
		if cfg.vertical then col, row = row, col end
		button:SetSize(size, size)
		button:ClearAllPoints()
		button:SetPoint("TOPLEFT", frame, "TOPLEFT", col * (size + spacing), -row * (size + spacing))

		-- Left-click uses the item; for weapon items the game then applies
		-- it to the inventory slot named by "target-slot". View-only icons
		-- get no action at all.
		local usable = kind ~= "view"
		button:SetAttribute("type1", usable and "item" or nil)
		button:SetAttribute("item", usable and ("item:" .. entry.id) or nil)
		button:SetAttribute("target-slot", slot)

		button.icon:SetTexture(ns.ItemIcon(entry.id))
		button.hand:SetText(slot and (slot == MAIN_HAND and "MH" or "OH") or "")
		button:Show()
		bar.buttons[i] = button
		ns.buttons[#ns.buttons + 1] = button
	end
	for i = #wanted + 1, #bar.pool do
		local button = bar.pool[i]
		button:Hide()
		button.entry, button.slot, button.state = nil, nil, nil
		Glow.Apply(button, nil)
	end

	local count = #wanted
	local across, down = math.min(count, perRow), math.ceil(count / perRow)
	if cfg.vertical then across, down = down, across end
	frame:SetSize(math.max(1, across * size + math.max(0, across - 1) * spacing),
		math.max(1, down * size + math.max(0, down - 1) * spacing))
	frame:ClearAllPoints()
	frame:SetPoint(cfg.point, UIParent, cfg.relPoint, cfg.x, cfg.y)
end

-- A bar the profile in use doesn't have: put its icons away and hide it.
local function RetireBar(bar)
	bar.data, bar.cfg, bar.show = nil, nil, nil
	bar.attention, bar.invisible = nil, nil
	for i = #bar.buttons, 1, -1 do bar.buttons[i] = nil end
	for _, button in ipairs(bar.pool) do
		button:Hide()
		button.entry, button.slot, button.state = nil, nil, nil
		Glow.Apply(button, nil)
	end
	if bar.driver ~= "hide" then
		bar.driver = "hide"
		RegisterStateDriver(bar.frame, "visibility", "hide")
	end
end

-- Builds every bar of the profile in use from the saved settings.
function ns.Rebuild()
	if not ns.ready then return end
	ns.spellMap = nil
	if InCombatLockdown() then
		pending.rebuild = true
		return
	end
	pending.rebuild = nil

	needs.self, needs.weapon, needs.usable = false, false, false
	for i = #ns.buttons, 1, -1 do ns.buttons[i] = nil end
	for i = #ns.allEntries, 1, -1 do ns.allEntries[i] = nil end
	for i = #ns.bars, 1, -1 do ns.bars[i] = nil end

	local saved = ns.profile.bars
	for index, data in ipairs(saved) do
		local bar = slots[index]
		if not bar then
			bar = CreateBar(index)
			slots[index] = bar
		end
		bar.data, bar.cfg, bar.show = data, data.cfg, data.show
		LayoutBar(bar)
		ns.bars[index] = bar
	end
	for index = #saved + 1, #slots do RetireBar(slots[index]) end

	ns.UpdateEvents(needs)
	ns.UpdateLearnFlag()
	ns.Invalidate()
	ns.UpdateMover()
	ns.UpdateVisibility()
	ns.Scan()
end

---------------------------------------------------------------------------
-- When each bar is shown
---------------------------------------------------------------------------
-- Called by the tracker after every update: each bar's `needs` says whether
-- one of its icons is missing or running out.
function ns.ApplyAttention()
	local changed, any = false, false
	for _, bar in ipairs(ns.bars) do
		local attention = bar.needs and true or false
		if bar.attention ~= attention then
			bar.attention = attention
			changed = true
		end
		if attention then any = true end
	end
	ns.attention = any
	if changed then ns.UpdateVisibility() end
end

-- The rule handed to the game for one bar: a visibility state driver string.
local function DriverFor(bar, idle)
	if #bar.buttons == 0 then return "hide" end
	if not ns.db.bar.locked then return "show" end -- always visible while you're placing it
	local show = bar.show
	if show.instance ~= "any" then
		local inInstance = IsInInstance()
		if ns.Secret(inInstance) then inInstance = false end
		if (show.instance == "inside") ~= (inInstance and true or false) then return "hide" end
	end
	if show.hideResting and IsResting() then return "hide" end

	local rule = ""
	if show.hideMounted then rule = rule .. "[mounted] hide; " end
	if show.combat == "in" then
		rule = rule .. "[nocombat] hide; "
	elseif show.combat == "out" then
		rule = rule .. "[combat] hide; "
	end
	if show.group == "solo" then
		rule = rule .. "[group] hide; "
	elseif show.group == "group" then
		rule = rule .. "[nogroup] hide; "
	elseif show.group == "raid" then
		rule = rule .. "[nogroup:raid] hide; "
	end
	return rule .. (idle and "[combat] show; hide" or "show")
end

function ns.UpdateVisibility()
	if not ns.ready then return end
	local locked = ns.db.bar.locked
	local lockdown = InCombatLockdown()
	local fighting = ns.combat or lockdown
	for _, bar in ipairs(ns.bars) do
		-- "Only when something needs attention": out of combat the bar is
		-- really hidden. In combat it can't be shown or hidden on demand, so
		-- it's kept shown but fully transparent until a buff needs you.
		local idle = bar.show.mode == "attention" and not bar.attention and locked
		local alpha = (idle and fighting) and 0 or bar.cfg.alpha
		if bar.alpha ~= alpha then
			-- Coming back from invisible: its timers weren't ticking, so
			-- bring the text up to date straight away.
			if bar.alpha == 0 then ns.ScheduleWake(0.01) end
			bar.alpha = alpha
			bar.frame:SetAlpha(alpha)
		end
		bar.invisible = alpha == 0

		if not lockdown then
			local driver = DriverFor(bar, idle)
			if driver ~= bar.driver then
				bar.driver = driver
				RegisterStateDriver(bar.frame, "visibility", driver)
			end
		end
	end
	pending.visibility = lockdown or nil
end

-- Prints everything that decides whether each bar is visible right now.
function ns.DebugVisibility()
	if not ns.ready or #ns.bars == 0 then
		ns.Print("The bars haven't been created yet.")
		return
	end
	ns.Print(("v%s, profile \"%s\", bars %s, in combat %s"):format(ns.version, ns.db.profile,
		ns.db.bar.locked and "locked" or "unlocked", tostring(ns.combat or InCombatLockdown() or false)))
	for _, bar in ipairs(ns.bars) do
		local show = bar.show
		ns.Print(("%s: %d icons, %s, opacity %.2f"):format(bar.data.name, #bar.buttons,
			bar.frame:IsShown() and "shown" or "hidden", bar.frame:GetAlpha() or 1))
		ns.Print(("   Rules: show %s, combat %s, group %s, place %s, hide resting %s, hide mounted %s"):format(
			show.mode, show.combat, show.group, show.instance, tostring(show.hideResting), tostring(show.hideMounted)))
		ns.Print(("   A buff needs attention %s, rule given to the game: %s"):format(
			tostring(bar.attention or false), tostring(bar.driver)))
	end
	if pending.rebuild or pending.visibility then
		ns.Print("Changes are waiting for combat to end.")
	end
end

---------------------------------------------------------------------------
-- Combat
---------------------------------------------------------------------------
-- Runs just before the game locks the bars for combat.
function ns.OnCombatStart()
	ns.combat = true
	if not ns.ready then return end
	ns.liveInCombat = ns.AnyLiveInCombat()
	StopMoving()
	ns.UpdateVisibility()
end

function ns.AfterCombat()
	ns.combat = false
	if not ns.ready then return end
	if pending.rebuild then
		ns.Rebuild()
	else
		ns.UpdateVisibility()
	end
end
