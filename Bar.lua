-- Bar: the row of clickable icons, how each one is painted, where the bar
-- sits and when it's shown. Icons are only repainted when something about
-- them changed; there is no per-frame code.
--
-- The icons are secure action buttons, which is what lets a click use an
-- item. The game doesn't allow such buttons to be created, moved, resized,
-- shown or hidden by an addon during combat, so those changes wait until
-- combat ends. Showing and hiding by combat or group state is handed to the
-- game itself (a visibility state driver), which is allowed to do it.
local _, ns = ...

local Glow = ns.Glow
local MAIN_HAND, OFF_HAND = 16, 17

local pool = {}       -- every button ever made, reused in order
local pending = {}    -- work waiting for combat to end
local needs = {}      -- which kinds of icon are on the bar, for event registration
local countStamp = 0  -- bumped whenever bag counts should be read again

---------------------------------------------------------------------------
-- Tooltip
---------------------------------------------------------------------------
local function OnEnter(button)
	local entry = button.entry
	if not entry or not ns.db.bar.tooltips or ns.barInvisible then return end
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
local function CreateButton(index)
	local button = CreateFrame("Button", "ClickableConsumeBarButton" .. index, ns.bar, "SecureActionButtonTemplate")
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
	if db.bar.showTimer and (status == "active" or status == "expiring") and state.expires and state.expires > 0 then
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
		if db.bar.showCount or button.entry.kind == "view" then
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
-- The bar
---------------------------------------------------------------------------
local function SavePosition()
	local bar, cfg = ns.bar, ns.db.bar
	local point, _, relPoint, x, y = bar:GetPoint(1)
	if point then
		cfg.point, cfg.relPoint, cfg.x, cfg.y = point, relPoint or point, x or 0, y or 0
	end
end

local function StopMoving()
	if ns.moving then
		ns.moving = false
		ns.bar:StopMovingOrSizing()
		SavePosition()
	end
end

function ns.CreateBar()
	if ns.bar then return end
	local bar = CreateFrame("Frame", "ClickableConsumeBarFrame", UIParent)
	bar:SetSize(36, 36)
	bar:SetMovable(true)
	bar:SetClampedToScreen(true)
	ns.bar = bar
	ns.combat = UnitAffectingCombat("player") and true or false

	-- The handle shown above the bar while it's unlocked.
	local mover = CreateFrame("Frame", "ClickableConsumeBarMover", UIParent)
	mover:SetFrameStrata("HIGH")
	mover:SetHeight(16)
	mover:SetPoint("BOTTOMLEFT", bar, "TOPLEFT", 0, 3)
	mover.bg = mover:CreateTexture(nil, "BACKGROUND")
	mover.bg:SetAllPoints(mover)
	mover.bg:SetColorTexture(0, 0.45, 0.9, 0.75)
	mover.label = mover:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	mover.label:SetPoint("CENTER", mover, "CENTER", 0, 0)
	mover.label:SetText("ClickableConsumeBar")
	mover:EnableMouse(true)
	mover:RegisterForDrag("LeftButton")
	mover:SetScript("OnDragStart", function()
		if InCombatLockdown() then
			ns.Print("The bar can't be moved during combat.")
			return
		end
		ns.moving = true
		bar:StartMoving()
	end)
	mover:SetScript("OnDragStop", StopMoving)
	mover:SetScript("OnMouseUp", function(_, mouseButton)
		if mouseButton == "RightButton" then ns.ToggleOptions() end
	end)
	mover:SetScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_TOP")
		GameTooltip:SetText("ClickableConsumeBar")
		GameTooltip:AddLine("Drag to move the bar.", 1, 1, 1)
		GameTooltip:AddLine("Right-click for the menu. Lock the bar there to hide this handle.", 1, 1, 1, true)
		GameTooltip:Show()
	end)
	mover:SetScript("OnLeave", OnLeave)
	mover:Hide()
	ns.mover = mover
end

function ns.UpdateMover()
	local mover = ns.mover
	if not mover then return end
	if ns.db.bar.locked then
		mover:Hide()
	else
		local empty = #ns.buttons == 0
		mover.label:SetText(empty and "ClickableConsumeBar: type /ccb to add consumables" or "ClickableConsumeBar")
		mover:SetWidth(math.max(empty and 320 or 150, ns.bar:GetWidth() or 0))
		mover:Show()
	end
end

-- Lays the bar out again from the saved settings.
function ns.Rebuild()
	local bar = ns.bar
	if not bar then return end
	ns.spellMap = nil
	if InCombatLockdown() then
		pending.rebuild = true
		return
	end
	pending.rebuild = nil

	local cfg = ns.db.bar
	local size, spacing, perRow = cfg.size, cfg.spacing, math.max(1, cfg.perRow)

	local wanted = {}
	for _, entry in ipairs(ns.entries) do
		if entry.kind == "weapon" then
			if entry.mh then wanted[#wanted + 1] = { entry, MAIN_HAND } end
			if entry.oh then wanted[#wanted + 1] = { entry, OFF_HAND } end
		else
			wanted[#wanted + 1] = { entry }
		end
	end

	needs.self, needs.weapon, needs.usable = false, false, false
	for i = #ns.buttons, 1, -1 do ns.buttons[i] = nil end
	for i, spec in ipairs(wanted) do
		local kind = spec[1].kind
		if kind == "weapon" then needs.weapon = true elseif kind ~= "view" then needs.self = true end
		if kind ~= "view" then needs.usable = true end
		local button = pool[i]
		if not button then
			button = CreateButton(i)
			pool[i] = button
		end
		local entry, slot = spec[1], spec[2]
		button.entry, button.slot = entry, slot
		button.key = entry.id .. ":" .. (slot or 0)
		button.size = size
		button.state = nil
		-- What's known about this icon's buff, kept across rebuilds.
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
		button:SetPoint("TOPLEFT", bar, "TOPLEFT", col * (size + spacing), -row * (size + spacing))

		-- Left-click uses the item; for weapon items the game then applies
		-- it to the inventory slot named by "target-slot". View-only icons
		-- get no action at all.
		local usable = entry.kind ~= "view"
		button:SetAttribute("type1", usable and "item" or nil)
		button:SetAttribute("item", usable and ("item:" .. entry.id) or nil)
		button:SetAttribute("target-slot", slot)

		button.icon:SetTexture(ns.ItemIcon(entry.id))
		button.hand:SetText(slot and (slot == MAIN_HAND and "MH" or "OH") or "")
		button:Show()
		ns.buttons[i] = button
	end
	for i = #wanted + 1, #pool do
		local button = pool[i]
		button:Hide()
		button.entry, button.slot, button.state = nil, nil, nil
		Glow.Apply(button, nil)
	end

	local count = #wanted
	local across, down = math.min(count, perRow), math.ceil(count / perRow)
	if cfg.vertical then across, down = down, across end
	bar:SetSize(math.max(1, across * size + math.max(0, across - 1) * spacing),
		math.max(1, down * size + math.max(0, down - 1) * spacing))
	bar:ClearAllPoints()
	bar:SetPoint(cfg.point, UIParent, cfg.relPoint, cfg.x, cfg.y)

	ns.UpdateEvents(needs)
	ns.UpdateLearnFlag()
	ns.Invalidate()
	ns.UpdateMover()
	ns.UpdateVisibility()
	ns.Scan()
end

---------------------------------------------------------------------------
-- When the bar is shown
---------------------------------------------------------------------------
function ns.SetAttention(attention)
	if ns.attention ~= attention then
		ns.attention = attention
		ns.UpdateVisibility()
	end
end

function ns.UpdateVisibility()
	local bar = ns.bar
	if not bar then return end
	local db = ns.db
	local show = db.show
	local lockdown = InCombatLockdown()

	-- "Only when something needs attention": out of combat the bar is really
	-- hidden. In combat it can't be shown or hidden on demand, so it's kept
	-- shown but fully transparent until a buff needs you.
	local idle = show.mode == "attention" and not ns.attention and db.bar.locked
	local alpha = (idle and (ns.combat or lockdown)) and 0 or db.bar.alpha
	bar:SetAlpha(alpha)
	ns.barInvisible = alpha == 0

	if lockdown then
		pending.visibility = true
		return
	end
	pending.visibility = nil

	local driver
	if #ns.buttons == 0 then
		driver = "hide"
	elseif not db.bar.locked then
		driver = "show" -- always visible while you're placing it
	else
		local allowed = true
		if show.instance ~= "any" then
			local inInstance = IsInInstance()
			if ns.Secret(inInstance) then inInstance = false end
			if (show.instance == "inside") ~= (inInstance and true or false) then allowed = false end
		end
		if show.hideResting and IsResting() then allowed = false end
		if not allowed then
			driver = "hide"
		else
			local parts = {}
			if show.hideMounted then parts[#parts + 1] = "[mounted] hide" end
			if show.combat == "in" then
				parts[#parts + 1] = "[nocombat] hide"
			elseif show.combat == "out" then
				parts[#parts + 1] = "[combat] hide"
			end
			if show.group == "solo" then
				parts[#parts + 1] = "[group] hide"
			elseif show.group == "group" then
				parts[#parts + 1] = "[nogroup] hide"
			elseif show.group == "raid" then
				parts[#parts + 1] = "[nogroup:raid] hide"
			end
			parts[#parts + 1] = idle and "[combat] show; hide" or "show"
			driver = table.concat(parts, "; ")
		end
	end
	if driver ~= ns.driver then
		ns.driver = driver
		RegisterStateDriver(bar, "visibility", driver)
	end
end

-- Prints everything that decides whether the bar is visible right now.
function ns.DebugVisibility()
	local bar, db = ns.bar, ns.db
	if not bar then
		ns.Print("The bar hasn't been created yet.")
		return
	end
	local show = db.show
	ns.Print(("v%s: %d icons, bar %s, opacity %.2f, %s"):format(ns.version, #ns.buttons,
		bar:IsShown() and "shown" or "hidden", bar:GetAlpha() or 1, db.bar.locked and "locked" or "unlocked"))
	ns.Print(("Rules: show %s, combat %s, group %s, place %s, hide resting %s, hide mounted %s"):format(
		show.mode, show.combat, show.group, show.instance, tostring(show.hideResting), tostring(show.hideMounted)))
	ns.Print(("State: in combat %s, a buff needs attention %s, rule given to the game: %s"):format(
		tostring(ns.combat or InCombatLockdown() or false), tostring(ns.attention or false), tostring(ns.driver)))
	if pending.rebuild or pending.visibility then
		ns.Print("Changes are waiting for combat to end.")
	end
end

---------------------------------------------------------------------------
-- Combat
---------------------------------------------------------------------------
-- Runs just before the game locks the bar for combat.
function ns.OnCombatStart()
	ns.combat = true
	if not ns.bar then return end
	ns.liveInCombat = ns.AnyLiveInCombat()
	StopMoving()
	ns.UpdateVisibility()
end

function ns.AfterCombat()
	ns.combat = false
	if not ns.bar then return end
	if pending.rebuild then
		ns.Rebuild()
	else
		ns.UpdateVisibility()
	end
end
